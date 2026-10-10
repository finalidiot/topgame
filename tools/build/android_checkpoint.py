"""Guarded Android milestone export and file-preserving promotion.

build --no-promote exports an exact committed source snapshot and validates the
signed debug APK. validate links native adb smoke evidence to that exact APK.
promote rechecks every hash and adds Android files beside the Windows checkpoint.
phone-review stages a package-validated pending APK only at its named checkpoint;
it never updates latest or claims native Android acceptance.
Debug signing is intentional for isolated run-as phone/emulator QA, not Store
distribution. Physical phone feel remains a separate human-review checkpoint.
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
import subprocess
import sys
import uuid
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "workspace"))
import workspace
import windows_checkpoint as windows

APK = "SpinningMetal-android.apk"
MANIFEST = "android-build-manifest.json"
README = "README-android.txt"
DELIVERY_FILES = (APK, APK + ".sha256", README, MANIFEST)
PACKAGE = "org.spinningmetal.prototype"
COVERAGE = ("installs", "boots", "landscape", "touch_menu", "hold_drag", "multitouch", "burst", "brake", "power_draft", "reentry", "packet_flow", "workshop", "shop", "results", "save_load", "background_resume", "safe_areas", "audio", "performance")
HUMAN_REVIEW = "PENDING HUMAN PHONE AND DEFENCE PLAYTEST"


def record(path: Path) -> dict:
    return {"path": str(path.resolve()), "sha256": windows.sha256(path), "bytes": path.stat().st_size}


def evidence_file(item: dict, task: Path) -> Path:
    if not isinstance(item, dict) or not isinstance(item.get("path"), str):
        raise ValueError("Evidence must name an existing hashed file.")
    path = windows.within(Path(item["path"]), task)
    if windows.is_reparse(path) or not path.is_file() or windows.sha256(path) != item.get("sha256"):
        raise ValueError("Android evidence missing, redirected or changed: " + str(path))
    return path


def settings_paths(sdk: str | None, java: str | None) -> tuple[Path, Path]:
    values: dict[str, str] = {}
    appdata = Path(os.environ.get("APPDATA", "")) / "Godot"
    for settings in sorted(appdata.glob("editor_settings-4*.tres"), reverse=True):
        text = settings.read_text(encoding="utf-8", errors="replace")
        for key in ("android_sdk_path", "java_sdk_path"):
            match = re.search(r'export/android/' + key + r'\s*=\s*"([^"]+)"', text)
            if match and key not in values:
                values[key] = match[1]
    sdk_path = Path(sdk or os.environ.get("ANDROID_HOME") or values.get("android_sdk_path", "")).resolve()
    java_path = Path(java or os.environ.get("JAVA_HOME") or values.get("java_sdk_path", "")).resolve()
    if not (sdk_path / "build-tools").is_dir() or not (java_path / "bin/java.exe").is_file():
        raise ValueError("Supply a configured Android SDK and JDK with --sdk / --java.")
    return sdk_path, java_path


def android_tool(sdk: Path, name: str) -> Path:
    versions = sorted((sdk / "build-tools").iterdir(), key=lambda p: tuple(int(x) for x in re.findall(r"\d+", p.name)), reverse=True)
    for version in versions:
        tool = version / name
        if tool.is_file():
            return tool
    raise FileNotFoundError("Android build tool unavailable: " + name)


def android_process(command: list[str], log: Path, java: Path, timeout: int = 180) -> dict:
    env = os.environ.copy()
    env["JAVA_HOME"] = str(java)
    env["PATH"] = str(java / "bin") + os.pathsep + env.get("PATH", "")
    options: dict = {}
    if os.name == "nt":
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = subprocess.SW_HIDE
        options.update(startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("wb") as out:
        result = subprocess.run(command, stdout=out, stderr=subprocess.STDOUT, env=env, timeout=timeout, **options)
    data = {"command": command, "exit_code": result.returncode, "log": str(log.resolve()), "log_sha256": windows.sha256(log)}
    if result.returncode != 0 or windows.ERRORS.search(log.read_text(encoding="utf-8", errors="replace")):
        raise windows.ProcessValidationError(data)
    return data


def inspect_apk(apk: Path, source: Path, sdk: Path, java: Path, logs: Path) -> dict:
    if not apk.is_file() or apk.stat().st_size < 1_000_000:
        raise ValueError("Android export produced no usable APK.")
    signature = android_process([str(android_tool(sdk, "apksigner.bat")), "verify", "--verbose", "--print-certs", str(apk)], logs / "signature.log", java)
    badging = android_process([str(android_tool(sdk, "aapt.exe")), "dump", "badging", str(apk)], logs / "badging.log", java)
    xml = android_process([str(android_tool(sdk, "aapt.exe")), "dump", "xmltree", str(apk), "AndroidManifest.xml"], logs / "manifest.log", java)
    text = Path(badging["log"]).read_text(encoding="utf-8", errors="replace")
    match = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", text)
    if not match or match[1] != PACKAGE:
        raise ValueError("Unexpected Android package identity.")
    xml_text = Path(xml["log"]).read_text(encoding="utf-8", errors="replace")
    if not re.search(r"android:debuggable[^\n]*0xffffffff", xml_text):
        raise ValueError("Foundation QA requires the signed debug APK for isolated run-as evidence.")
    certificate = re.search(r"certificate SHA-256 digest: ([0-9a-fA-F]{64})", Path(signature["log"]).read_text(encoding="utf-8", errors="replace"))
    if not certificate:
        raise ValueError("APK certificate digest absent from real signature verification.")
    resources: list[dict] = []
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None:
            raise ValueError("APK ZIP integrity failed.")
        names = set(archive.namelist())
        for expected in ["AndroidManifest.xml", "assets/project.binary", "lib/arm64-v8a/libgodot_android.so", "lib/x86_64/libgodot_android.so", "assets/scripts/main.gdc", "assets/scripts/mobile_shell.gdc", "assets/scripts/touch_controls.gdc", "assets/scripts/android_qa.gdc"]:
            if expected not in names:
                raise ValueError("Missing APK runtime resource: " + expected)
        for path in sorted((source / "assets").rglob("*.json")):
            if "source-art" in path.parts:
                continue
            relative = path.relative_to(source).as_posix()
            entry = "assets/" + relative
            if entry not in names or archive.read(entry) != path.read_bytes():
                raise ValueError("Embedded JSON differs from exact export source: " + relative)
        for entry in sorted(names):
            if entry.startswith("assets/assets/") and entry.endswith(".import"):
                imported = archive.read(entry).decode("utf-8", errors="strict")
                for target in re.findall(r'"res://(\.godot/imported/[^"]+)"', imported):
                    if "assets/" + target not in names:
                        raise ValueError("APK import points to missing runtime pixels/audio: " + target)
            if entry.startswith(("assets/assets/", "assets/.godot/imported/", "assets/scripts/")) or entry == "assets/project.binary":
                data = archive.read(entry)
                resources.append({"entry": entry, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        catalogue = json.loads(archive.read("assets/assets/data/parts_catalogue.json"))
        counts = {key: len(catalogue["categories"][key]) for key in ("blade", "ratchet", "bit")}
        if counts != {"blade": 11, "ratchet": 9, "bit": 11}:
            raise ValueError("APK has an unexpected physical catalogue.")
    return {"apk": record(apk), "package": match[1], "version_code": int(match[2]), "version_name": match[3], "certificate_sha256": certificate[1].lower(), "debug_signed": True, "abis": ["arm64-v8a", "x86_64"], "catalogue_counts": counts, "legal_assemblies": counts["blade"] * counts["ratchet"] * counts["bit"], "signature": signature, "badging": badging, "manifest": xml, "resources": resources}


def verify_process(item: dict) -> None:
    log = Path(item["log"])
    if item.get("exit_code") != 0 or not log.is_file() or windows.sha256(log) != item.get("log_sha256"):
        raise ValueError("Android process evidence failed or changed.")
    if windows.ERRORS.search(log.read_text(encoding="utf-8", errors="replace")):
        raise ValueError("Android process log contains an engine/export/signature error.")


def verify_smoke(report_file: Path, apk: Path, qa: Path, task_id: str) -> dict:
    task = qa.resolve() / workspace.valid_task(task_id)
    report_file = windows.within(report_file, task / "manifests")
    data = json.loads(report_file.read_text(encoding="utf-8"))
    if data.get("platform") != "Android" or data.get("package") != PACKAGE or data.get("apk_sha256") != windows.sha256(apk):
        raise ValueError("Native Android smoke does not match this exact packaged APK.")
    if not isinstance(data.get("checks_passed"), int) or isinstance(data["checks_passed"], bool) or data["checks_passed"] <= 0 or data.get("failures") != []:
        raise ValueError("Native Android smoke checks did not all pass.")
    if data.get("profile_unchanged") is not True or data.get("profile_before") != data.get("profile_after") or "profile_before" not in data:
        raise ValueError("Native Android smoke did not preserve the player profile.")
    isolated = data.get("isolated_collection", "")
    if not re.fullmatch(r"user://test_collection/android_003a_[0-9a-f]{32}\.json", isolated):
        raise ValueError("Native Android smoke lacks the unique isolated collection boundary.")
    device = data.get("device", {})
    if not isinstance(device, dict) or not device.get("serial") or not isinstance(device.get("physical"), bool):
        raise ValueError("Native Android device/emulator identity is absent.")
    for name in COVERAGE:
        item = data.get("coverage", {}).get(name)
        if item is not True and not (isinstance(item, dict) and item.get("passed") is True):
            raise ValueError("Native Android smoke lacks passed coverage: " + name)
    installed = evidence_file(data.get("installed_apk"), task)
    if windows.sha256(installed) != windows.sha256(apk):
        raise ValueError("The APK actually pulled from the installed device differs from this candidate.")
    evidence_file(data.get("adb_log"), task)
    captures = data.get("captures", [])
    states = data.get("state_reports", [])
    if not captures or not states:
        raise ValueError("Native Android captures and in-app state proof are required.")
    for item in captures:
        try:
            image = windows.png_record(evidence_file(item, task))
        except RuntimeError as error:
            raise ValueError("Android native capture is incomplete or invalid.") from error
        if image["width"] <= image["height"] or image["width"] < 640:
            raise ValueError("Android capture is not the required usable landscape layout.")
    for item in states:
        state = json.loads(evidence_file(item, task).read_text(encoding="utf-8"))
        if state.get("platform") != "Android" or state.get("debug") is not True or state.get("isolated_collection") != isolated:
            raise ValueError("In-app native state does not prove Android/debug/isolated-save execution.")
        if not re.fullmatch(r"[0-9a-f]{32}", state.get("run_id", "")) or state["run_id"] not in isolated:
            raise ValueError("In-app request identity differs from the isolated smoke run.")
    return {**record(report_file), "checks_passed": data["checks_passed"], "coverage": data["coverage"], "device": device, "profile_unchanged": True, "isolated_collection": isolated}


def verify_candidate(candidate: Path, require_smoke: bool = True) -> dict:
    candidate = candidate.resolve()
    if windows.is_reparse(candidate):
        raise ValueError("Candidate must be an ordinary directory.")
    manifest = json.loads((candidate / MANIFEST).read_text(encoding="utf-8"))
    if manifest.get("schema") != 1 or manifest.get("platform") != "Android" or manifest.get("human_acceptance") != HUMAN_REVIEW:
        raise ValueError("Android candidate metadata/acceptance status is invalid.")
    if manifest.get("validation") != ("passed" if require_smoke else "awaiting_android_smoke"):
        raise ValueError("Android candidate is not at the required validation stage.")
    if not manifest.get("source", {}).get("tracked_clean") or not re.fullmatch(r"[0-9a-f]{40}", manifest["source"].get("git_sha", "")):
        raise ValueError("Android candidate lacks an exact committed source identity.")
    for name in DELIVERY_FILES[:-1]:
        path = candidate / name
        if windows.is_reparse(path) or not path.is_file() or windows.sha256(path) != manifest.get("delivery_sha256", {}).get(name):
            raise ValueError("Android delivery file missing, redirected or changed: " + name)
    apk = candidate / APK
    if (candidate / (APK + ".sha256")).read_text(encoding="ascii").split()[0] != windows.sha256(apk):
        raise ValueError("Android checksum sidecar differs from the packaged APK.")
    for name in ("import", "export"):
        verify_process(manifest[name])
    for name in ("signature", "badging", "manifest"):
        verify_process(manifest["package_inspection"][name])
    if manifest["package_inspection"].get("apk", {}).get("sha256") != windows.sha256(apk) or not manifest["package_inspection"].get("debug_signed"):
        raise ValueError("APK inspection does not match the packaged candidate.")
    if require_smoke:
        smoke = manifest.get("android_smoke", {})
        if verify_smoke(Path(smoke.get("path", "")), apk, Path(manifest["qa_root"]), manifest["qa_task"]) != smoke:
            raise ValueError("Native Android smoke summary changed after validation.")
    return manifest


def current_source(root: Path, manifest: dict) -> None:
    if windows.git(root, "rev-parse", "HEAD") != manifest["source"]["git_sha"] or windows.git(root, "status", "--porcelain"):
        raise ValueError("Android checkpoint source no longer matches the clean committed checkout.")


def write_delivery(candidate: Path, manifest: dict) -> None:
    digest = windows.sha256(candidate / APK)
    (candidate / (APK + ".sha256")).write_text(digest + "  " + APK + "\n", encoding="ascii")
    status = "Native APK installation/boot/isolated Android smoke PASSED." if manifest["validation"] == "passed" else "AWAITING PHYSICAL ANDROID REVIEW. Native Android smoke is pending; candidate is not promotable to latest."
    (candidate / README).write_text("Spinning Metal / Android milestone\n" + f"Task/checkpoint: {manifest['checkpoint']}\nGit SHA: {manifest['source']['git_sha']}\nBranch: {manifest['source']['branch']}\nBuilt UTC: {manifest['build_date_utc']}\n" + status + "\n" + HUMAN_REVIEW + "\n\nSigned debug APK for phone testing; arm64 phones/tablets and x86_64 emulator.\nLandscape. Hold anywhere in the arena and drag to steer; release is neutral.\nUse the explicit Burst/Brake controls with the other thumb.\nCountdowns allow placing the steering thumb before live danger resumes.\nTap/scroll menus. Collection data persists across normal installs/resume.\n\n" + windows.CONTROLLER_GUIDE, encoding="utf-8")
    manifest["delivery_sha256"] = {name: windows.sha256(candidate / name) for name in DELIVERY_FILES[:-1]}
    windows.write_json(candidate / MANIFEST, manifest)


def validate(candidate: Path, smoke_report: Path, root: Path) -> dict:
    manifest = verify_candidate(candidate, require_smoke=False)
    current_source(root, manifest)
    manifest["android_smoke"] = verify_smoke(smoke_report, candidate / APK, Path(manifest["qa_root"]), manifest["qa_task"])
    manifest["validation"] = "passed"
    manifest["validated_date_utc"] = datetime.now(timezone.utc).isoformat()
    write_delivery(candidate, manifest)
    verify_candidate(candidate)
    windows.write_json(Path(manifest["evidence"]), manifest)
    return {"candidate": str(candidate), "evidence": manifest["evidence"], "validation": "passed", "sha256": windows.sha256(candidate / APK)}


def promote(candidate: Path, root: Path, qa: Path, checkpoint: str | None, *, phone_review: bool = False) -> dict:
    manifest = verify_candidate(candidate, require_smoke=not phone_review)
    if phone_review and (not checkpoint or Path(manifest["qa_root"]).resolve() != qa.resolve()):
        raise ValueError("Phone-review candidate requires its explicit checkpoint and original QA root.")
    current_source(root, manifest)
    if checkpoint and workspace.valid_task(checkpoint) != manifest["checkpoint"]:
        raise ValueError("Requested Android checkpoint differs from validated candidate.")
    builds = windows.build_destination(root / "builds", root)
    builds.mkdir(parents=True, exist_ok=True)
    token = uuid.uuid4().hex
    lock = windows.build_destination(builds / ".promotion.lock", builds)
    descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL)
    archive = windows.build_destination(qa / "archive/builds" / ("android-" + token), qa)
    backups: list[tuple[Path, Path]] = []
    replaced: list[Path] = []
    try:
        os.write(descriptor, str(os.getpid()).encode("ascii"))
        destinations = [] if phone_review else [windows.build_destination(builds / "latest", builds)]
        if checkpoint:
            destinations.append(windows.build_destination(builds / "checkpoints" / checkpoint, builds))
        prepared: list[Path] = []
        for index, destination in enumerate(destinations):
            if destination.exists() and not destination.is_dir():
                raise ValueError("Build destination is not an ordinary directory.")
            # Windows is promoted first so both milestone artifacts name one HEAD.
            windows_manifest = destination / "build-manifest.json"
            if not windows_manifest.is_file() or json.loads(windows_manifest.read_text(encoding="utf-8")).get("source", {}).get("git_sha") != manifest["source"]["git_sha"]:
                raise ValueError("Promote the matching Windows checkpoint before Android.")
            if phone_review and json.loads(windows_manifest.read_text(encoding="utf-8")).get("validation") != "passed":
                raise ValueError("Phone-review candidate requires a validated matching Windows checkpoint.")
            if phone_review:
                windows.verify_candidate(destination)
            staging = windows.build_destination(builds / (".android-promotion-" + token + "-" + str(index)), builds)
            staging.mkdir()
            for name in DELIVERY_FILES:
                shutil.copy2(candidate / name, staging / name)
            verify_candidate(staging, require_smoke=not phone_review)
            prepared.append(staging)
        for staging, destination in zip(prepared, destinations):
            for name in DELIVERY_FILES:
                target = windows.build_destination(destination / name, builds)
                if target.exists():
                    if not target.is_file():
                        raise ValueError("Android target is not an ordinary file.")
                    backup = windows.build_destination(archive / destination.name / name, qa)
                    backup.parent.mkdir(parents=True, exist_ok=True)
                    target.rename(backup)
                    backups.append((target, backup))
                (staging / name).rename(target)
                replaced.append(target)
            verify_candidate(destination, require_smoke=not phone_review)
        return {"latest": None if phone_review else str(builds / "latest" / APK), "validation": manifest["validation"], "physical_android_acceptance": False, "delivery": "checkpoint_phone_review_candidate" if phone_review else "native_smoke_validated", "checkpoint": str(builds / "checkpoints" / checkpoint / APK) if checkpoint else None, "preserved_previous": str(archive) if backups else None, "git_sha": manifest["source"]["git_sha"], "sha256": windows.sha256(candidate / APK)}
    except Exception:
        for target in reversed(replaced):
            if target.exists():
                failed = windows.build_destination(archive / "failed-new" / target.parent.name / target.name, qa)
                failed.parent.mkdir(parents=True, exist_ok=True)
                target.rename(failed)
        for target, backup in reversed(backups):
            if backup.exists():
                backup.rename(target)
        raise
    finally:
        os.close(descriptor)
        lock.unlink()


def build(args: argparse.Namespace) -> dict:
    workspace.valid_task(args.checkpoint)
    root = workspace.repo_root().resolve()
    if windows.git(root, "status", "--porcelain"):
        raise ValueError("Commit/preserve changes before an exact Android checkpoint export.")
    qa = workspace.qa_root(args.qa_root)
    task = workspace.create_task_workspace(args.task, qa)
    run_id = "android-" + args.checkpoint.lower().replace(".", "") + "-" + uuid.uuid4().hex[:12]
    staging = task / "temp" / run_id
    source, candidate = staging / "source", staging / "payload"
    source.mkdir(parents=True); candidate.mkdir()
    logs = task / "logs" / run_id
    evidence = task / "manifests" / (run_id + ".json")
    manifest = {"schema": 1, "platform": "Android", "checkpoint": args.checkpoint, "qa_task": args.task, "qa_root": str(qa.resolve()), "evidence": str(evidence.resolve()), "build_date_utc": datetime.now(timezone.utc).isoformat(), "human_acceptance": HUMAN_REVIEW, "validation": "pending", "export_mode": "signed_debug_phone_review"}
    try:
        sdk, java = settings_paths(args.sdk, args.java)
        engine = workspace.find_tool("godot", args.engine)
        print("STAGE_CLEAN_ANDROID_CHECKPOINT " + str(source), flush=True)
        manifest["source"] = windows.copy_clean_source(root, source)
        manifest["import"] = windows.import_source([engine, "--headless", "--path", str(source), "--editor", "--import"], logs)
        print("EXPORT_ANDROID_SIGNED_DEBUG", flush=True)
        manifest["export"] = windows.run_logged([engine, "--headless", "--path", str(source), "--export-debug", "Android", str(candidate / APK)], logs / "export.log", 900)
        manifest["package_inspection"] = inspect_apk(candidate / APK, source, sdk, java, logs)
        current_source(root, manifest)
        manifest["validation"] = "awaiting_android_smoke"
        write_delivery(candidate, manifest)
        verify_candidate(candidate, require_smoke=False)
        windows.write_json(evidence, manifest)
        if not args.no_promote:
            raise ValueError("Export retained. Native adb smoke must be linked with validate before promotion; use build --no-promote.")
        return {"candidate": str(candidate), "evidence": str(evidence), "validation": "awaiting_android_smoke", "apk": str(candidate / APK), "sha256": windows.sha256(candidate / APK)}
    except Exception as error:
        manifest["error"] = str(error)
        if manifest["validation"] != "awaiting_android_smoke":
            manifest["validation"] = "failed"
        windows.write_json(evidence, manifest)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    export = sub.add_parser("build")
    export.add_argument("--task", default="003A")
    export.add_argument("--checkpoint", default="003A")
    export.add_argument("--engine")
    export.add_argument("--sdk")
    export.add_argument("--java")
    export.add_argument("--qa-root", type=Path)
    export.add_argument("--no-promote", action="store_true")
    check = sub.add_parser("validate")
    check.add_argument("--candidate", type=Path, required=True)
    check.add_argument("--smoke-report", type=Path, required=True)
    publish = sub.add_parser("promote")
    publish.add_argument("--candidate", type=Path, required=True)
    publish.add_argument("--checkpoint")
    publish.add_argument("--qa-root", type=Path)
    review = sub.add_parser("phone-review", help="Stage a package-validated candidate at its checkpoint only; no phone acceptance or latest promotion.")
    review.add_argument("--candidate", type=Path, required=True)
    review.add_argument("--checkpoint", required=True)
    review.add_argument("--qa-root", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "build":
            result = build(args)
        elif args.command == "validate":
            result = validate(args.candidate.resolve(), args.smoke_report.resolve(), workspace.repo_root())
        else:
            result = promote(args.candidate.resolve(), workspace.repo_root(), workspace.qa_root(args.qa_root), args.checkpoint, phone_review=args.command == "phone-review")
        print(json.dumps(result, indent=2))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print("ANDROID_NOT_PROMOTED: " + str(error), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
