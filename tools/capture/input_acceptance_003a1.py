"""Fresh native input movies, isolated saves, and optional native physical probe."""
from __future__ import annotations
import argparse
import ctypes
from datetime import datetime, timezone
import difflib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
import workspace
sys.path.insert(0, str(ROOT / "tools/build"))
import windows_checkpoint as pipeline
sys.path.insert(0, str(ROOT / "tools/capture"))
from presentation_showcase import movie_metadata


def player_fingerprint() -> dict:
    result = pipeline.production_profile(ROOT)
    base = Path(result["directory"]) / "collection-backups"
    result["backups"] = {str(path.relative_to(base)): pipeline.sha256(path)
                         for path in sorted(base.rglob("*")) if path.is_file()} if base.is_dir() else {}
    return result


def native_snapshot(destination: Path, driver: str) -> dict:
    assert not destination.exists(), "Every source snapshot must be fresh"
    destination.mkdir(parents=True)
    if driver == "controller_physical_probe_003a1.gd":
        (destination / "scripts").mkdir()
        for name in ["front_end.gd", "controller_bindings.gd"]:
            shutil.copyfile(ROOT / "scripts" / name, destination / "scripts" / name)
        # The physical observer does not depend on Run/HUD/art changes that
        # other agents may still be editing. Preserve its exact actual font.
        (destination / "assets/ui").mkdir(parents=True)
        for source in (ROOT / "assets/ui").glob("foundry_small*"):
            if source.is_file(): shutil.copyfile(source, destination / "assets/ui" / source.name)
        shutil.copytree(ROOT / ".godot", destination / ".godot")
    else:
        for directory in ["scripts", "assets", ".godot"]:
            shutil.copytree(ROOT / directory, destination / directory)
    (destination / "tests").mkdir()
    for name in [driver, driver + ".uid"]:
        if (ROOT / "tests" / name).exists(): shutil.copyfile(ROOT / "tests" / name, destination / "tests" / name)
    shutil.copyfile(ROOT / "main.tscn", destination / "main.tscn")
    source = (ROOT / "project.godot").read_bytes()
    assert source.count(b"window/size/window_width_override=1280") == 1
    assert source.count(b"window/size/window_height_override=720") == 1
    adjusted = source.replace(b"window/size/window_width_override=1280", b"window/size/window_width_override=640")
    adjusted = adjusted.replace(b"window/size/window_height_override=720", b"window/size/window_height_override=360")
    (destination / "project.godot").write_bytes(adjusted)
    files = {str(path.relative_to(destination)).replace("\\", "/"): pipeline.sha256(path)
             for folder in ["scripts", "assets", "tests"] for path in (destination / folder).rglob("*") if path.is_file()}
    assert all(pipeline.sha256(ROOT / name) == digest for name, digest in files.items()), "Snapshot bytes must exactly match their canonical source"
    return {"root": str(destination), "files_sha256": files,
            "canonical_project_sha256": pipeline.sha256(ROOT / "project.godot"),
            "capture_project_sha256": pipeline.sha256(destination / "project.godot"),
            "display_only_diff": "".join(difflib.unified_diff(source.decode().splitlines(True), adjusted.decode().splitlines(True), fromfile="canonical/project.godot", tofile="QA-native/project.godot"))}


class Gamepad(ctypes.Structure):
    _fields_ = [("buttons", ctypes.c_ushort), ("left_trigger", ctypes.c_ubyte),
                ("right_trigger", ctypes.c_ubyte), ("left_x", ctypes.c_short),
                ("left_y", ctypes.c_short), ("right_x", ctypes.c_short), ("right_y", ctypes.c_short)]


class State(ctypes.Structure):
    _fields_ = [("packet", ctypes.c_uint), ("pad", Gamepad)]


def physical_process(command: list[str], log: Path, ready: Path) -> dict:
    library = ctypes.WinDLL("xinput1_4")
    raw_rows = []
    previous = {}
    started = time.monotonic()
    with log.open("w", encoding="utf-8") as stream:
        process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        announced = False
        while process.poll() is None:
            if ready.exists() and not announced:
                print("PHYSICAL_PROBE_READY " + str(ready), flush=True)
                print(ready.read_text(encoding="utf-8"), flush=True)
                announced = True
            for device in range(4):
                state = State()
                if library.XInputGetState(device, ctypes.byref(state)) == 0:
                    identity = (state.pad.buttons, state.pad.left_trigger, state.pad.right_trigger)
                    if previous.get(device) != identity:
                        raw_rows.append({"wall_elapsed_ms": round((time.monotonic() - started) * 1000), "xinput_index": device,
                                         "buttons_hex": f"0x{state.pad.buttons:04x}", "xinput_a": bool(state.pad.buttons & 0x1000),
                                         "xinput_b": bool(state.pad.buttons & 0x2000), "packet": state.packet})
                        previous[device] = identity
            time.sleep(0.02)
    return {"exit_code": process.returncode, "log": str(log), "seconds": time.monotonic() - started,
            "xinput_raw_changes": raw_rows, "xinput_scope": "Read-only native XInputGetState polling; no buttons, vibration, or synthetic input are sent."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kind", choices=["all", "flow", "mapping", "physical"], required=True)
    parser.add_argument("--diagnostic", action="store_true")
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--qa-root", type=Path)
    parser.add_argument("--name", help="Optional fresh video identity; primary review names are otherwise used")
    args = parser.parse_args()
    task = workspace.create_task_workspace("003A.1", args.qa_root)
    identity = "003a1_input_" + args.kind + "_" + datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    manifest = task / "manifests" / (identity + ".json")
    report = task / "manifests" / (identity + "_events.json")
    ready = task / "manifests" / (identity + "_ready.json")
    raw = task / "temp" / (identity + ".avi")
    profiles = task / "temp" / (identity + "_profiles")
    images = task / "frames" / identity
    names = {"flow":"003a1_input_flow_acceptance", "mapping":"003a1_controller_mapping", "physical":"003a1_controller_physical_mapping", "all":"003a1_input_all_acceptance"}
    video = task / "video" / ((args.name or names[args.kind]) + ".mp4")
    assert not manifest.exists() and not report.exists() and not raw.exists() and not profiles.exists()
    if not args.diagnostic: assert not video.exists(), "Earlier human review videos must be preserved"
    before = player_fingerprint()
    driver = "controller_physical_probe_003a1.gd" if args.kind == "physical" else "test_input_acceptance_003a1.gd"
    snapshot = None if args.diagnostic else native_snapshot(task / "temp" / (identity + "_source"), driver)
    source_root = ROOT if snapshot is None else Path(snapshot["root"])
    command = [workspace.find_tool("godot", args.engine), "--path", str(source_root), "--script", "res://tests/" + driver]
    command += ["--headless", "--fixed-fps", "60"] if args.diagnostic else ["--resolution", "640x360", "--fixed-fps", "60", "--disable-vsync", "--write-movie", str(raw), "--audio-driver", "Dummy"]
    command += ["--", "--report=" + str(report)]
    if args.kind == "physical": command += ["--ready=" + str(ready)]
    else:
        command += ["--kind=" + args.kind, "--profiles=" + str(profiles)]
        if not args.diagnostic: command += ["--images=" + str(images)]
    log = task / "logs" / (identity + ".log")
    print("INPUT_ACCEPTANCE_CAPTURE " + str(manifest), flush=True)
    process = physical_process(command, log, ready) if args.kind == "physical" else pipeline.run_logged(command, log, 900)
    # Preserve raw native polling even if a window was closed before the
    # engine driver could finish its report. Never turn an interruption into
    # a hardware acceptance claim.
    if args.kind == "physical":
        manifest.write_text(json.dumps({"kind":"physical","status":"awaiting_driver_report","process":process,"ready":str(ready),"native_snapshot":snapshot,"player_before":before},indent=2)+"\n",encoding="utf-8")
    text = log.read_text(encoding="utf-8", errors="replace")
    assert process["exit_code"] == 0 and not any(marker in text for marker in ["SCRIPT ERROR:", "ERROR:", "ObjectDB instances were leaked"]), text
    data = json.loads(report.read_text(encoding="utf-8"))
    if args.kind != "physical":
        assert data["passed"] and data["failures"] == 0
        assert all(item["passed"] for item in data["outcomes"])
    assert before == player_fingerprint(), "Actual player files and every collection backup must remain unchanged"
    if snapshot:
        assert pipeline.sha256(ROOT / "project.godot") == snapshot["canonical_project_sha256"]
        assert all(pipeline.sha256(source_root / name) == digest for name,digest in snapshot["files_sha256"].items())
    evidence = {"report": str(report), "report_sha256": pipeline.sha256(report), "checks":data.get("checks"), "failures":data.get("failures"),
                "source_git_sha": pipeline.git(ROOT,"rev-parse","HEAD"), "working_tree":pipeline.git(ROOT,"status","--porcelain"),
                "player_before":before,"player_unchanged":True,"process":process,"native_snapshot":snapshot,
                "scope":data["scope"],"kind":args.kind,"connected_devices":data.get("connected_devices",data.get("devices",[]))}
    if not args.diagnostic:
        ffmpeg = workspace.find_tool("ffmpeg",args.ffmpeg)
        metadata = movie_metadata(ffmpeg,raw)
        assert "640x360" in metadata["metadata"], "Raw capture must begin at native resolution"
        encode = [ffmpeg,"-v","error","-i",str(raw)]
        sidecar = raw.with_suffix(".wav")
        if not metadata["has_audio"] and sidecar.exists(): encode += ["-i",str(sidecar)]
        encode += ["-map","0:v:0"]
        if metadata["has_audio"] or sidecar.exists(): encode += ["-map","0:a:0" if metadata["has_audio"] else "1:a:0","-c:a","aac","-b:a","160k"]
        encode += ["-vf","scale=1280:720:flags=neighbor","-c:v","libx264","-crf","18","-preset","fast","-pix_fmt","yuv420p","-movflags","+faststart",str(video)]
        encoder = pipeline.run_logged(encode,task/"logs"/(identity+"_encode.log"),600)
        decoder = pipeline.run_logged([ffmpeg,"-v","error","-i",str(video),"-f","null","-"],task/"logs"/(identity+"_decode.log"),180)
        evidence.update(video=str(video),video_sha256=pipeline.sha256(video),raw_movie=str(raw),raw_sha256=pipeline.sha256(raw),movie_metadata=movie_metadata(ffmpeg,video),encoder=encoder,decoder=decoder,
                        editorial="Uncut chronological real engine images, captured at640x360 and enlarged integer2x nearest. Labels disclose logical controller/touch and XP/focus fixtures. Physical observer generates no synthetic events. No retouched game imagery or replacement audio.")
    manifest.write_text(json.dumps(evidence,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"manifest":str(manifest),"video":evidence.get("video"),"checks":data.get("checks"),"physical_both_received":data.get("both_received"),"physical_mapping_matches":data.get("mapping_matches"),"player_unchanged":True},indent=2),flush=True)


if __name__ == "__main__": main()
