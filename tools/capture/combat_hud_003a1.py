"""Native Windows and explicit Android-layout fixture matrix, without APK claims."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
sys.path.insert(0, str(ROOT / "tools/build"))
import workspace
import windows_checkpoint as pipeline

def inputs():
    paths = [*sorted((ROOT / "scripts").glob("*.gd")), ROOT / "tests/capture_combat_hud_003a1.gd", Path(__file__).resolve()]
    return {p.relative_to(ROOT).as_posix(): pipeline.sha256(p) for p in paths}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--engine")
    p.add_argument("--qa-root", type=Path)
    p.add_argument("--stem", default="003a1_combat_hud")
    a = p.parse_args()
    task = workspace.create_task_workspace("003A.1", a.qa_root)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    capture_stem = a.stem + "_" + stamp
    manifest = task / "manifests" / (capture_stem + ".json")
    frames = task / "frames" / capture_stem
    profile = task / "temp" / (capture_stem + "_collection.json")
    output = task / "images" / "003a1_combat_hud_matrix.png"
    summary = task / "manifests" / "003a1_combat_hud_matrix.json"
    assert not any(path.exists() for path in [manifest, frames, profile, output, summary]), "Preserve prior HUD evidence"
    before_profile = pipeline.production_profile(ROOT)
    before = inputs()
    command = [workspace.find_tool("godot", a.engine), "--path", str(ROOT), "--script", "res://tests/capture_combat_hud_003a1.gd", "--resolution", "640x360", "--audio-driver", "Dummy", "--", "--manifest=" + str(manifest), "--frames=" + str(frames), "--profile=" + str(profile)]
    process = pipeline.run_logged(command, task / "logs" / (capture_stem + ".log"), 120)
    data = json.loads(manifest.read_text(encoding="utf-8"))
    assert data["failures"] == [], data["failures"]
    after = inputs()
    after_profile = pipeline.production_profile(ROOT)
    assert before_profile == after_profile, "Human profile changed during capture"
    assert before == after, "Source changed during native capture; keep it as incomplete evidence and recapture a fresh identity"
    slots = [("WINDOWS / ANCHOR + OVERDRIVE", "windows_anchor_overdrive"), ("ANDROID LAYOUT / ANCHOR + OVERDRIVE", "android_layout_anchor_overdrive"),
             ("WINDOWS / ANCHOR RECOVERY", "windows_anchor_recharging"), ("ANDROID LAYOUT / ANCHOR RECOVERY", "android_layout_anchor_recharging"),
             ("WINDOWS / CROWDED FULL TOPS", "windows_crowd"), ("ANDROID LAYOUT / STATUS BARS OFF", "android_layout_bars_off")]
    image = Image.new("RGB", (1280, 1196), (17, 25, 33))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 16)
    small = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 14)
    draw.text((12, 8), "COMBAT HUD / native 640 x 360 cells / declared state and crowd fixtures", fill=(226, 234, 224), font=font)
    draw.text((12, 30), "Android columns audit the production landscape layout on Windows; no APK or phone acceptance claim.", fill=(165, 185, 194), font=small)
    entries = []
    for index, (label, key) in enumerate(slots):
        path = Path(data["images"][key]["path"])
        native = Image.open(path).convert("RGB")
        assert native.size == (640, 360)
        x, y = (index % 2) * 640, 54 + (index // 2) * 380
        draw.text((x + 10, y), label, fill=(220, 230, 220), font=small)
        image.paste(native, (x, y + 20))
        entries.append({"label": label, "source": str(path), "sha256": pipeline.sha256(path), "native_view": [640, 360]})
    image.save(output)
    data.update(source_sha256=before, source_unchanged=True, profile_before=before_profile, profile_after=after_profile,
                profile_unchanged=True, capture_process=process, source_git_sha=pipeline.git(ROOT, "rev-parse", "HEAD"))
    manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    evidence = {"matrix": str(output), "sha256": pipeline.sha256(output), "size": [1280, 1196], "entries": entries, "capture_manifest": str(manifest),
                "native_source_pixels_unscaled": True, "physical_android_acceptance": False, "scope": data["scope"], "android_scope": data["android_scope"]}
    summary.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))

if __name__ == "__main__": main()
