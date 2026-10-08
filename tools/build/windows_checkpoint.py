"""Export a clean Git checkpoint; validate the packaged game before promotion.

Usage: python tools/build/windows_checkpoint.py build --checkpoint 002C.5
       python tools/build/windows_checkpoint.py promote --candidate <payload>
Requires Godot export templates and the workspace helper; no third-party Python.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "workspace"))
import workspace

EXE = "SpinningMetal.exe"
DELIVERY_FILES = (EXE, EXE + ".sha256", "README.txt", "build-manifest.json")
CONTROLLER_GUIDE = (
    "Controller: left stick steers; south face button bursts; shoulder/trigger brakes;\n"
    "Menu/Start pauses. In Options choose CONTROLLER: AUTO, XBOX, NINTENDO or PLAYSTATION.\n"
    "Nintendo: printed A confirms; printed B goes back (B bursts in combat).\n"
    "Xbox: A confirms; B goes back. PlayStation: Cross confirms; Circle goes back.\n"
)
SMOKE_MARKER = "INTEGRATION_SMOKE_PASS"
ERRORS = re.compile(r"SCRIPT ERROR|(?:^|\n)ERROR:|FAIL:|Assertion failed", re.I)
REQUIRED_CAPTURES = (
    "01-title.png", "09-starters.png", "09a-confirm.png", "09b-owned.png",
    "09c-owned-workshop.png", "10-starting-draft.png", "run-past-eight.png",
    "run-failed.png",
)
SHOP_REQUIRED_CAPTURES = ("003a-shop.png", "003a-odds.png", "003a-packet-result.png", "003a-acquired-workshop.png")
SHOP_SMOKE_MARKER = "SHOP_PROGRESSION_SMOKE_PASS"
NATIVE_IMPORT_EXIT_CODES = (-1073741819, 3221225477)


class ProcessValidationError(RuntimeError):
    def __init__(self, record: dict):
        self.record = record
        self.attempts = [record]
        super().__init__(f"Process failed validation (exit {record['exit_code']}); inspect {record['log']}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def within(path: Path, root: Path) -> Path:
    path = path.resolve()
    if not path.is_relative_to(root.resolve()) or path == root.resolve():
        raise ValueError(f"Path must remain inside {root}: {path}")
    return path


def is_reparse(path: Path) -> bool:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    return path.is_symlink() or bool(getattr(info, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0))


def build_destination(path: Path, root: Path) -> Path:
    """Reject redirects in every existing component before modifying builds."""
    root = root.resolve()
    path = path.absolute()
    relative = path.relative_to(root)
    current = root
    for component in relative.parts:
        current /= component
        if is_reparse(current):
            raise ValueError(f"Build destinations must not traverse reparse points: {current}")
    return within(path, root)


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def copy_clean_source(root: Path, target: Path) -> dict:
    """Copy tracked working files, including hydrated LFS data, without caches."""
    if git(root, "status", "--porcelain", "--untracked-files=no"):
        raise RuntimeError("Commit or preserve tracked changes before building an exact checkpoint.")
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    records = []
    excluded = {".git", ".godot", "build", "builds", "releases", "exports", "docs", "tools", "tests"}
    for relative in paths:
        if not relative or Path(relative).parts[0] in excluded:
            continue
        if is_reparse(root / relative):
            raise RuntimeError(f"Tracked build input is a reparse point: {relative}")
        source = within(root / relative, root)
        if not source.is_file():
            raise RuntimeError(f"Unsupported or missing tracked build input: {relative}")
        with source.open("rb") as handle:
            if handle.read(80).startswith(b"version https://git-lfs.github.com/spec/v1"):
                raise RuntimeError(f"Hydrate Git LFS before export: {relative}")
        destination = within(target / relative, target)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        records.append({"path": relative, "bytes": source.stat().st_size, "sha256": sha256(source)})
    if not (target / "project.godot").is_file():
        raise RuntimeError("Clean export snapshot lacks project.godot.")
    return {"git_sha": git(root, "rev-parse", "HEAD"), "branch": git(root, "branch", "--show-current"),
            "tracked_clean": True, "inputs": records,
            "input_digest": hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest()}


def run_logged(command: list[str], log: Path, timeout: int) -> dict:
    log.parent.mkdir(parents=True, exist_ok=True)
    options = {}
    if os.name == "nt":
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
        options.update(startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
    with log.open("wb") as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                timeout=timeout, **options)
    content = log.read_text(encoding="utf-8", errors="replace")
    record = {"command": command, "exit_code": result.returncode,
              "log": str(log.resolve()), "log_sha256": sha256(log)}
    if result.returncode != 0 or ERRORS.search(content):
        raise ProcessValidationError(record)
    return record


def run_packaged_smoke(executable: Path, engine_log: Path, images: Path,
                       collection: Path, log: Path, qa_root: Path,
                       qa_task: str, timeout: int = 240) -> dict:
    """Pass the same explicit QA boundary to the actual packaged child only."""
    workspace.valid_task(qa_task)
    configured_qa = str(qa_root.resolve())
    command = [str(executable), "--log-file", str(engine_log), "--", "--smoke-test",
               "--qa-task=" + qa_task, "--capture-dir=" + str(images),
               "--collection-path=" + str(collection)]
    previous = os.environ.get("TOPGAME_QA_ROOT")
    try:
        os.environ["TOPGAME_QA_ROOT"] = configured_qa
        record = run_logged(command, log, timeout)
    finally:
        if previous is None:
            os.environ.pop("TOPGAME_QA_ROOT", None)
        else:
            os.environ["TOPGAME_QA_ROOT"] = previous
    return {**record, "qa_task": qa_task,
            "child_environment": {"TOPGAME_QA_ROOT": configured_qa},
            "isolated_collection": str(collection.resolve())}


def shop_progression_record(collection: Path, *, qa_root: Path, qa_task: str) -> dict:
    """Verify actual persisted 003A smoke progression, independent of markers.

    This checks the fixed, explicitly labelled one-purchase smoke fixture. Real
    earned gameplay is different evidence. Rechecking the save before promotion
    prevents a release build with stripped assert-side effects from passing.
    """
    if qa_task != "003A":
        raise ValueError("Shop progression requires the explicit 003A QA task.")
    collection = collection.absolute()
    if is_reparse(collection):
        raise ValueError("Shop progression save cannot be a reparse point.")
    collection = within(collection, qa_root.resolve() / qa_task / "temp")
    if not collection.is_file():
        raise ValueError("Shop progression persisted save is missing.")
    try:
        saved = json.loads(collection.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ValueError("Shop progression persisted save is not valid JSON.") from error

    def require(condition: bool, message: str) -> None:
        if not condition:
            raise ValueError("Shop progression " + message)

    def exact_integer(value, expected: int) -> bool:
        return type(value) in (int, float) and value == expected

    require(isinstance(saved, dict) and exact_integer(saved.get("schema_version"), 3),
            "requires a schema3 saved collection.")
    require(saved.get("starter_selected") == "breaker", "starter fixture changed.")
    baseline = {"blade:smash", "ratchet:high", "bit:flat"}
    owned = saved.get("owned_part_ids")
    require(isinstance(owned, list) and all(isinstance(part, str) for part in owned)
            and len(owned) == len(set(owned)) and len(owned) > 3,
            "owned collection did not actually grow beyond the starter.")
    progression = saved.get("progression")
    require(isinstance(progression, dict), "persistent economic state is absent.")
    require(exact_integer(progression.get("credits"), 0), "wallet must reflect the actual 48-CREDIT debit.")
    require(exact_integer(progression.get("packet_serial"), 1), "must purchase exactly one packet without replay.")
    require(progression.get("pending_packet") == {}, "pending packet was not acknowledged.")
    require(progression.get("active_run") == "", "active Run was not retired.")
    require(exact_integer(progression.get("run_serial"), 1), "funding Run nonce changed or replayed.")
    receipt = progression.get("last_packet")
    require(isinstance(receipt, dict) and receipt.get("id") == "packet-1"
            and receipt.get("request_nonce") == "packet-1" and receipt.get("kind") == "standard"
            and receipt.get("currency") == "credits" and exact_integer(receipt.get("cost"), 48)
            and receipt.get("status") == "resolved", "resolved paid receipt is missing or changed.")
    rows = receipt.get("rows")
    require(isinstance(rows, list) and len(rows) == 3, "receipt must contain all three physical slots.")
    require(exact_integer(receipt.get("quantity"), 1) and exact_integer(receipt.get("cursor"), 1)
            and receipt.get("packets") == [{"rows": rows, "total_salvage": receipt.get("total_salvage")}],
            "single batch receipt lost its exact result group or completed cursor.")
    categories = ("blade", "ratchet", "bit")
    rarities = ("TRASH", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY")
    salvage_values = {"TRASH": 1, "COMMON": 1, "UNCOMMON": 2, "RARE": 4, "EPIC": 7, "LEGENDARY": 10}
    fresh = []
    total_salvage = 0
    for category, row in zip(categories, rows):
        require(isinstance(row, dict) and row.get("category") == category
                and isinstance(row.get("id"), str) and row["id"]
                and row.get("part_id") == category + ":" + row["id"]
                and row.get("rarity") in rarities and type(row.get("new")) is bool,
                "receipt contains an invalid category, identity, rarity or NEW flag.")
        part = row["part_id"]
        if row["new"]:
            require(part not in baseline and exact_integer(row.get("salvage"), 0),
                    "NEW receipt row is a starter duplicate or grants SALVAGE.")
            fresh.append(part)
        else:
            require(part in baseline and exact_integer(row.get("salvage"), salvage_values[row["rarity"]]),
                    "duplicate conversion is inconsistent with the one-purchase fixture.")
            total_salvage += int(row["salvage"])
    require(bool(fresh) and set(owned) == baseline.union(fresh),
            "ownership does not match the actually acquired NEW receipt designs.")
    require(any(rarities.index(row["rarity"]) >= 2 for row in rows), "receipt lost its Uncommon+ guarantee.")
    require(exact_integer(receipt.get("total_salvage"), total_salvage)
            and exact_integer(progression.get("salvage"), total_salvage),
            "SALVAGE wallet/receipt indicates a duplicate grant or replay.")
    build = saved.get("equipped_build")
    require(isinstance(build, dict) and set(build) == set(categories)
            and all(isinstance(build[category], str) and category + ":" + build[category] in owned
                    for category in categories), "equipped build is not a legal owned assembly.")
    equipped_new = [row["part_id"] for row in rows if row["new"] and build[row["category"]] == row["id"]]
    require(bool(equipped_new), "NEW design was not actually equipped in the persisted build.")
    reward = progression.get("last_reward")
    require(isinstance(reward, dict) and reward.get("id") == "run-1"
            and exact_integer(reward.get("credits"), 48) and reward.get("eligible") is True,
            "actual saved 48-CREDIT funding reward is absent or replayed.")
    breakdown = reward.get("breakdown")
    require(isinstance(breakdown, dict) and set(breakdown) == {"threats", "elites", "bosses"}
            and exact_integer(breakdown.get("threats"), 48) and exact_integer(breakdown.get("elites"), 0)
            and exact_integer(breakdown.get("bosses"), 0), "saved fixture funding ledger changed.")
    return {"path": str(collection), "sha256": sha256(collection), "schema_version": 3,
            "scope": "Actual persisted packaged one-purchase Shop flow; labelled funding/seed fixture, not earned gameplay.",
            "summary": {"owned_count": len(owned), "owned_part_ids": sorted(owned),
                        "credits": 0, "salvage": total_salvage, "packet_serial": 1, "receipt_id": "packet-1",
                        "receipt_status": "resolved", "receipt_rows": rows, "pending_packet_empty": True,
                        "new_part_ids": fresh, "equipped_build": build, "equipped_new_part_ids": equipped_new,
                        "run_serial": 1, "active_run_empty": True, "last_reward": reward}}


def completed_native_import_crash(record: dict) -> bool:
    """Recognise only the observed cold-import native crash after reimport ends."""
    if record.get("exit_code") not in NATIVE_IMPORT_EXIT_CODES:
        return False
    log = Path(record["log"])
    if not log.is_file() or sha256(log) != record["log_sha256"]:
        return False
    content = log.read_text(encoding="utf-8", errors="replace")
    # Godot's redirected progress output may retain colour/style SGR sequences.
    # Normalise only this comparison text; the raw log and its hash stay intact.
    content = re.sub(r"\x1b\[[0-9;:]*m", "", content)
    return "[ DONE ] reimport" in content and not ERRORS.search(content)


def import_source(command: list[str], logs: Path, timeout: int = 600) -> dict:
    attempts = []
    try:
        result = run_logged(command, logs / "import.log", timeout)
    except ProcessValidationError as first:
        attempts.append(first.record)
        if not completed_native_import_crash(first.record):
            raise
        print("RETRY_IMPORT_ONCE native 0xC0000005 after completed reimport; first log preserved", flush=True)
        try:
            result = run_logged(command, logs / "import-retry.log", timeout)
        except ProcessValidationError as second:
            second.attempts = attempts + [second.record]
            raise
    attempts.append(result)
    return {**result, "attempts": attempts,
            "retry_reason": "native_0xc0000005_after_completed_reimport" if len(attempts) == 2 else None}


def production_profile(root: Path) -> dict:
    """Fingerprint the real save and preferences without reading their contents."""
    text = (root / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/name="([^"]+)"', text, re.M)
    appdata = os.environ.get("APPDATA")
    if not appdata or not match:
        return {"available": False}
    directory = Path(appdata) / "Godot" / "app_userdata" / match.group(1)
    files = sorted(directory.glob("collection.json*"))
    if (directory / "prototype.cfg").is_file():
        files.append(directory / "prototype.cfg")
    return {"available": True, "directory": str(directory),
            "files": {p.name: sha256(p) for p in files if p.is_file()}}


def png_record(path: Path) -> dict:
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise RuntimeError(f"Packaged smoke capture is not a PNG: {path}")
    width, height = struct.unpack(">II", header[16:24])
    if width < 640 or height < 360 or path.stat().st_size < 1024:
        raise RuntimeError(f"Packaged smoke capture is incomplete: {path}")
    return {"path": str(path.resolve()), "sha256": sha256(path), "width": width, "height": height}


def verify_candidate(candidate: Path) -> dict:
    """Reject failed/tampered candidates before touching either build destination."""
    if is_reparse(candidate) or not candidate.is_dir():
        raise ValueError("Candidate must be an explicit ordinary directory, not a reparse point.")
    for name in DELIVERY_FILES:
        if is_reparse(candidate / name):
            raise ValueError(f"Candidate delivery is a reparse point: {name}")
    manifest = json.loads((candidate / "build-manifest.json").read_text(encoding="utf-8"))
    if manifest.get("schema") != 1 or manifest.get("validation") != "passed":
        raise ValueError("Candidate has no successful packaged validation.")
    workspace.valid_task(manifest.get("checkpoint", ""))
    workspace.valid_task(manifest.get("qa_task", ""))
    provisional_c5 = manifest["checkpoint"] == "002C.5" or manifest["checkpoint"].startswith("002C.5.")
    if provisional_c5 and manifest.get("human_acceptance") != "PENDING HOME HUMAN PLAYTEST":
        raise ValueError("Task 002C.5 must retain its pending human gameplay acceptance.")
    if manifest["checkpoint"] == "002C.6" and manifest.get("human_acceptance") != "PENDING HUMAN PRESENTATION PLAYTEST":
        raise ValueError("Task 002C.6 must retain its pending human presentation acceptance.")
    if manifest["checkpoint"] == "003A" and manifest.get("human_acceptance") != "PENDING HUMAN PROGRESSION PLAYTEST":
        raise ValueError("Task 003A must retain its pending human progression acceptance.")
    if not re.fullmatch(r"[0-9a-f]{40}", manifest.get("source", {}).get("git_sha", "")):
        raise ValueError("Candidate has no exact Git checkpoint.")
    if not manifest["source"].get("tracked_clean"):
        raise ValueError("Only a clean Git checkpoint can be promoted.")
    smoke = manifest.get("packaged_smoke", {})
    if smoke.get("exit_code") != 0 or smoke.get("marker") != SMOKE_MARKER or not smoke.get("profile_unchanged"):
        raise ValueError("Candidate failed packaged smoke or profile isolation.")
    for name in DELIVERY_FILES[:-1]:
        file = within(candidate / name, candidate)
        if not file.is_file() or sha256(file) != manifest["delivery_sha256"].get(name):
            raise ValueError(f"Candidate delivery hash mismatch: {name}")
    checksum = (candidate / (EXE + ".sha256")).read_text(encoding="ascii").split()
    if checksum != [manifest["delivery_sha256"][EXE], EXE]:
        raise ValueError("Executable SHA sidecar disagrees with manifest.")
    executable = candidate / EXE
    with executable.open("rb") as stream:
        if stream.read(2) != b"MZ" or executable.stat().st_size < 1024:
            raise ValueError("Candidate is not a Windows executable.")
    for step in (manifest["import"], manifest["export"], smoke):
        log = Path(step["log"])
        if not log.is_file() or sha256(log) != step["log_sha256"]:
            raise ValueError(f"Validation evidence missing or changed: {log}")
        content = log.read_text(encoding="utf-8", errors="replace")
        if step.get("exit_code") != 0 or ERRORS.search(content):
            raise ValueError(f"Validation evidence contains a failure: {log}")
    attempts = manifest["import"].get("attempts", [manifest["import"]])
    if not isinstance(attempts, list) or len(attempts) not in (1, 2):
        raise ValueError("Import evidence permits at most two attempts.")
    if len(attempts) == 2 and not completed_native_import_crash(attempts[0]):
        raise ValueError("First import failure is not the bounded native cold-import exception.")
    for index, attempt in enumerate(attempts):
        log = Path(attempt["log"])
        if not log.is_file() or sha256(log) != attempt["log_sha256"]:
            raise ValueError("Import attempt evidence missing or changed.")
        content = log.read_text(encoding="utf-8", errors="replace")
        if ERRORS.search(content) or (index == len(attempts) - 1 and attempt.get("exit_code") != 0):
            raise ValueError("Final import attempt must exit zero without script or engine errors.")
    if any(attempts[-1].get(key) != manifest["import"].get(key) for key in ("log", "log_sha256", "exit_code")):
        raise ValueError("Successful import record disagrees with final attempt.")
    if SMOKE_MARKER not in Path(smoke["log"]).read_text(encoding="utf-8", errors="replace"):
        raise ValueError("Packaged smoke marker absent from real process log.")
    engine_log = Path(smoke["engine_log"])
    if not engine_log.is_file() or sha256(engine_log) != smoke["engine_log_sha256"]:
        raise ValueError("Packaged engine log missing or changed.")
    engine_content = engine_log.read_text(encoding="utf-8", errors="replace")
    if SMOKE_MARKER not in engine_content or ERRORS.search(engine_content):
        raise ValueError("Packaged engine log did not independently pass.")
    captures = {Path(c["path"]).name: c for c in smoke.get("captures", [])}
    required = REQUIRED_CAPTURES + (SHOP_REQUIRED_CAPTURES if manifest["checkpoint"] == "003A" else ())
    if manifest["checkpoint"] == "003A" and SHOP_SMOKE_MARKER not in Path(smoke["log"]).read_text(encoding="utf-8", errors="replace"):
        raise ValueError("Task 003A packaged Shop flow marker is absent.")
    for name in required:
        if name not in captures:
            raise ValueError(f"Missing packaged smoke capture: {name}")
        capture = captures[name]
        if not Path(capture["path"]).is_file() or sha256(Path(capture["path"])) != capture["sha256"]:
            raise ValueError(f"Packaged smoke capture changed: {name}")
    if manifest["checkpoint"] == "003A":
        shop = smoke.get("shop_progression")
        if not isinstance(shop, dict) or not isinstance(shop.get("path"), str):
            raise ValueError("Task 003A has no verified persisted Shop progression evidence.")
        environment = smoke.get("child_environment", {})
        qa_root = environment.get("TOPGAME_QA_ROOT") if isinstance(environment, dict) else None
        if not isinstance(qa_root, str) or not qa_root or smoke.get("qa_task") != manifest["qa_task"]:
            raise ValueError("Task 003A persisted Shop progression has no explicit child QA boundary.")
        command = smoke.get("command", [])
        collection_flags = [arg for arg in command if isinstance(arg, str) and arg.startswith("--collection-path=")]
        if ("--qa-task=" + manifest["qa_task"] not in command or len(collection_flags) != 1
                or Path(collection_flags[0].removeprefix("--collection-path=")).resolve() != Path(shop["path"]).resolve()
                or smoke.get("isolated_collection") != str(Path(shop["path"]).resolve())):
            raise ValueError("Task 003A persisted Shop progression does not match the actual smoke command.")
        actual = shop_progression_record(Path(shop["path"]), qa_root=Path(qa_root), qa_task=manifest["qa_task"])
        if actual != shop:
            raise ValueError("Task 003A persisted Shop progression save/hash/summary changed after validation.")
    return manifest


def promote_candidate(candidate: Path, root: Path, qa: Path, checkpoint: str | None = None) -> dict:
    manifest = verify_candidate(candidate)
    if checkpoint:
        workspace.valid_task(checkpoint)
    if checkpoint and checkpoint != manifest["checkpoint"]:
        raise ValueError("Requested checkpoint differs from validated candidate metadata.")
    builds = build_destination(root.resolve() / "builds", root)
    token = uuid.uuid4().hex
    archive = build_destination(qa.resolve() / "archive" / "builds" / token, qa)
    builds.mkdir(parents=True, exist_ok=True)
    lock = build_destination(builds / ".promotion.lock", builds)
    descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    prepared, replaced, committed = [], [], []
    try:
        os.write(descriptor, str(os.getpid()).encode("ascii"))
        destinations = []
        if checkpoint:
            destinations.append(build_destination(builds / "checkpoints" / checkpoint, builds))
        destinations.append(build_destination(builds / "latest", builds))
        for index, destination in enumerate(destinations):
            staging = build_destination(builds / (".promotion-" + token + "-" + str(index)), builds)
            staging.mkdir()
            prepared.append(staging)
            for name in DELIVERY_FILES:
                shutil.copy2(candidate / name, staging / name)
            verify_candidate(staging)
            destination.parent.mkdir(parents=True, exist_ok=True)
        # Every candidate copy has passed before either current build is moved.
        for staging, destination in zip(prepared, destinations):
            backup = build_destination(builds / (".previous-" + token + "-" + destination.name), builds)
            if destination.exists():
                if destination.is_symlink() or not destination.is_dir():
                    raise ValueError(f"Build destination is not an ordinary directory: {destination}")
                destination.rename(backup)
                replaced.append((destination, backup))
            staging.rename(destination)
            committed.append(destination)
        # Preserve replaced builds; never silently discard a historical executable.
        for destination, backup in replaced:
            archive.mkdir(parents=True, exist_ok=True)
            shutil.move(str(backup), str(archive / destination.name))
        return {"latest": str(builds / "latest" / EXE),
                "checkpoint": str(builds / "checkpoints" / checkpoint / EXE) if checkpoint else None,
                "preserved_previous": str(archive) if replaced else None,
                "git_sha": manifest["source"]["git_sha"], "sha256": manifest["delivery_sha256"][EXE]}
    except Exception:
        # New candidates are retained for inspection; restore every prior destination.
        for destination in reversed(committed):
            failed = build_destination(builds / (".failed-" + token + "-" + destination.name), builds)
            destination.rename(failed)
        for destination, backup in reversed(replaced):
            if backup.exists():
                backup.rename(destination)
            elif (archive / destination.name).exists():
                shutil.move(str(archive / destination.name), str(destination))
        raise
    finally:
        os.close(descriptor)
        lock.unlink()


def build(args: argparse.Namespace) -> dict:
    workspace.valid_task(args.checkpoint)
    root = workspace.repo_root().resolve()
    qa = workspace.qa_root(args.qa_root)
    task = workspace.create_task_workspace(args.task, qa)
    engine = str(workspace.find_tool("godot", args.engine))
    run_id = "windows-" + args.checkpoint.lower().replace(".", "") + "-" + uuid.uuid4().hex[:12]
    staging = task / "temp" / run_id
    payload = staging / "payload"
    source = staging / "source"
    logs = task / "logs" / run_id
    images = task / "images" / run_id
    evidence = task / "manifests" / (run_id + ".json")
    payload.mkdir(parents=True)
    source.mkdir()
    images.mkdir(parents=True)
    report = {"schema": 1, "checkpoint": args.checkpoint, "qa_task": args.task,
              "build_date_utc": datetime.now(timezone.utc).isoformat(), "validation": "pending"}
    try:
        print(f"STAGE_CLEAN_CHECKPOINT {source}", flush=True)
        report["source"] = copy_clean_source(root, source)
        print(f"IMPORT {report['source']['git_sha']}", flush=True)
        report["import"] = import_source([engine, "--headless", "--path", str(source), "--editor", "--import"], logs)
        print("EXPORT_WINDOWS", flush=True)
        report["export"] = run_logged([engine, "--headless", "--path", str(source), "--export-release", "Windows Desktop", str(payload / EXE)], logs / "export.log", 600)
        if not (payload / EXE).is_file():
            raise RuntimeError("Export produced no executable.")
        before = production_profile(root)
        print(f"PACKAGED_SMOKE_ISOLATED {images}", flush=True)
        isolated_collection = staging / "isolated-collection.json"
        smoke = run_packaged_smoke(payload / EXE, logs / "packaged-engine.log", images,
                                  isolated_collection, logs / "packaged-smoke.log", qa, args.task)
        after = production_profile(root)
        engine_log = logs / "packaged-engine.log"
        if not engine_log.is_file():
            raise RuntimeError("Packaged game produced no engine log.")
        smoke.update(marker=SMOKE_MARKER, profile_unchanged=before == after,
                     engine_log=str(engine_log.resolve()), engine_log_sha256=sha256(engine_log),
                     profile_before=before, profile_after=after,
                     fixture_scope="Packaged menu/controller/starter/draft/continuous Run flow; synthetic outcomes are fixtures, not balance evidence.",
                     captures=[png_record(images / name) for name in REQUIRED_CAPTURES + (SHOP_REQUIRED_CAPTURES if args.checkpoint == "003A" else ())])
        report["packaged_smoke"] = smoke
        if args.checkpoint == "003A":
            smoke["shop_progression"] = shop_progression_record(isolated_collection, qa_root=qa, qa_task=args.task)
        if before != after:
            raise RuntimeError("Real profile changed during isolated smoke; preserve latest and inspect concurrent activity.")
        if SMOKE_MARKER not in Path(smoke["log"]).read_text(encoding="utf-8", errors="replace"):
            raise RuntimeError("Packaged process exited without its integration smoke pass marker.")
        if git(root, "rev-parse", "HEAD") != report["source"]["git_sha"] or git(root, "status", "--porcelain", "--untracked-files=no"):
            raise RuntimeError("Repository changed during build; candidate is not promotable.")
        digest = sha256(payload / EXE)
        (payload / (EXE + ".sha256")).write_text(digest + "  " + EXE + "\n", encoding="ascii")
        provisional_c5 = args.checkpoint == "002C.5" or args.checkpoint.startswith("002C.5.")
        acceptance = "PENDING HOME HUMAN PLAYTEST" if provisional_c5 else "PENDING HUMAN PRESENTATION PLAYTEST" if args.checkpoint == "002C.6" else "PENDING HUMAN PROGRESSION PLAYTEST" if args.checkpoint == "003A" else "Human acceptance is separate from automated validation."
        report["human_acceptance"] = acceptance
        readme = ("Spinning Metal / GyroBrothers\n"
                  f"Task/checkpoint: {args.checkpoint} (workspace/build task {args.task})\n"
                  f"Git SHA: {report['source']['git_sha']}\n"
                  f"Branch: {report['source']['branch']}\n"
                  f"Built UTC: {report['build_date_utc']}\n"
                  "Verification: clean Windows export + isolated packaged integration smoke PASSED.\n"
                  f"Human gameplay acceptance: {acceptance}\n\n"
                  "Run SpinningMetal.exe; game data is embedded.\n"
                  "Keyboard: WASD/arrows steer; Space bursts; Shift brakes; Esc pauses.\n"
                  + CONTROLLER_GUIDE +
                  "D-pad/stick navigate menus; mouse and keyboard are also supported.\n\n"
                  "Select and confirm your first owned top when starting a fresh collection.\n"
                  + ("Task 002C.5 remains PENDING HOME HUMAN PLAYTEST.\n"
                     "This checkpoint does not approve Task 002C.5 balance or gameplay.\n" if provisional_c5 else
                     "The C5 parts/combat foundation and Black Arrow/beasts are accepted in main.\n"
                     "Task 002C.6 presentation remains a human-review checkpoint.\n" if args.checkpoint == "002C.6" else
                     "This checkpoint's human acceptance remains separate from automated checks.\n"))
        (payload / "README.txt").write_text(readme, encoding="utf-8")
        report["delivery_sha256"] = {name: sha256(payload / name) for name in DELIVERY_FILES[:-1]}
        report["validation"] = "passed"
        write_json(payload / "build-manifest.json", report)
        verify_candidate(payload)
        if not args.no_promote:
            print("PROMOTE_VALIDATED_BUILD", flush=True)
            report["promotion"] = promote_candidate(payload, root, qa, args.checkpoint if args.archive_checkpoint else None)
        write_json(evidence, report)
        return {"candidate": str(payload), "evidence": str(evidence), **report.get("promotion", {})}
    except Exception as error:
        report["validation"] = "failed"
        report["error"] = str(error)
        if isinstance(error, ProcessValidationError):
            report["failed_process"] = error.record
            report["failed_process_attempts"] = error.attempts
        write_json(evidence, report)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("build", help="Clean export, packaged smoke and guarded promotion")
    create.add_argument("--task", default="002C.5.1", help="QA task ID")
    create.add_argument("--checkpoint", default="002C.5", help="Playable content checkpoint ID")
    create.add_argument("--engine", help="Godot executable; otherwise TOPGAME_GODOT or PATH")
    create.add_argument("--qa-root", type=Path)
    create.add_argument("--archive-checkpoint", action="store_true")
    create.add_argument("--no-promote", action="store_true", help="Validate and retain candidate only")
    promote = sub.add_parser("promote", help="Promote an already validated candidate with hash/evidence checks")
    promote.add_argument("--candidate", type=Path, required=True)
    promote.add_argument("--checkpoint", help="Also archive the validated checkpoint")
    promote.add_argument("--qa-root", type=Path)
    args = parser.parse_args()
    try:
        result = build(args) if args.command == "build" else promote_candidate(
            args.candidate.absolute(), workspace.repo_root(), workspace.qa_root(args.qa_root), args.checkpoint)
        print(json.dumps(result, indent=2))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"BUILD_NOT_PROMOTED: {error}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
