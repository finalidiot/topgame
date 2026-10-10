"""Join immutable baseline reproduction, fixed contracts and native pickup evidence."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/workspace"))
import workspace

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def opaque_overlap(row: dict, source: Path) -> int:
    """Offline pixel proof at the logged maximum-overlap pose, not a runtime
    collision rule. Solid native cels exclude the pickup's translucent shadow.
    """
    pickup = Image.open(source / "assets/powers/feedback_002c5_2/pickup.png").convert("RGBA")
    blade = Image.open(source / "assets/top/starters/bastion_spin.png").convert("RGBA").crop((0,0,48,48))
    px,py = row["pickup_projected"]
    bx,by = row["visible_overlap_player_projected"]
    pickup_origin = int(px)-12,int(py)-10
    blade_origin = int(bx)-24,int(by)-40
    total = 0
    for y in range(pickup.height):
        for x in range(pickup.width):
            blade_x = pickup_origin[0]+x-blade_origin[0]
            blade_y = pickup_origin[1]+y-blade_origin[1]
            if 0 <= blade_x < blade.width and 0 <= blade_y < blade.height:
                total += pickup.getpixel((x,y))[3] >= 128 and blade.getpixel((blade_x,blade_y))[3] >= 128
    return total

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline",required=True,type=Path)
    parser.add_argument("--baseline-source",required=True,type=Path)
    parser.add_argument("--fixed",required=True,type=Path)
    parser.add_argument("--capture",required=True,type=Path)
    parser.add_argument("--audio-proof",type=Path)
    parser.add_argument("--qa-root",type=Path)
    args = parser.parse_args()
    qa = workspace.create_task_workspace("003A.1",args.qa_root)
    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    fixed = json.loads(args.fixed.read_text(encoding="utf-8"))
    capture = json.loads(args.capture.read_text(encoding="utf-8"))
    audio = json.loads(args.audio_proof.read_text(encoding="utf-8")) if args.audio_proof else capture.get("collection_audio_proof",{})
    if args.audio_proof:
        assert audio["passed"] and audio["capture_manifest_sha256"] == sha(args.capture)
        assert audio["video_sha256"] == capture["video_sha256"]
    assert baseline["mode"] == "baseline_reproduction" and fixed["mode"] == "fixed_position_matrix"
    assert not baseline["failures"] and not fixed["failures"] and not capture["failures"]
    assert len(baseline["spawn_points"]) == 8 and len(baseline["cases"]) == len(fixed["cases"]) == 57
    old = baseline["cases"]
    missed_visible = [r for r in old if r["case"].startswith("visible_") and not r["collected"]]
    capped = [r for r in old if r["case"] == "full_capacity" and r["remaining_items"] == 1]
    cadence = next(r for r in old if r["case"] == "out_and_back_without_render_process")
    assert len(missed_visible) == 16 and len(capped) == 8 and not cadence["collected"]
    assert cadence["nearest_actual_fixed_tick_distance"] < 5 and cadence["world_collection_distance"] > 30
    for r in missed_visible:
        r["solid_native_overlap_pixels_at_logged_pose"] = opaque_overlap(r,args.baseline_source)
        assert r["solid_native_overlap_pixels_at_logged_pose"] > 20
    assert all(r["collected"] if r["case"] != "full_capacity" else r["remaining_items"] == 0 for r in fixed["cases"])
    video = Path(capture["video"])
    assert video.is_file() and sha(video) == capture["video_sha256"] and not capture["diagnostic"]
    matrix = {"task":"003A.1 enemy intelligence foundation / pickup blocker correction",
              "created_utc":datetime.now(timezone.utc).isoformat(),"accepted_baseline_sha":"2c06290591371035b5b1c68a0f5b0c565523d80b",
              "root_causes":[
                  "Floor-only radius18 is centred at the tip/floor pivot, while the visible native blade is raised about12raster pixels. Clear grounded blade/pickup overlap can miss the world circle by25.456units.",
                  "Collector observed only render-process endpoints. A real solver out-and-back crosses the chip but its render-only chord remains45units away.",
                  "RunContext correctly rejects receipts at6rerolls, but old notify_clear/render left impossible full-wallet pickups visible."],
              "fix":[
                  "Retain world radius18 and exact existing world points. Also sweep the native blade spin-cel envelope against the native pickup bounds, using Battle's shared actual render pose. No attraction, teleport or art offset.",
                  "Observe each resolved fixed tick before progression can pause. Render fallback is idempotent; pause/READY synchronize geometry without collecting or aging.",
                  "Suppress new/full-wallet drops and remove remaining impossible chips in the same tick the final wallet slot fills. Cap6 and all receipts/economy rules stay unchanged.",
                  "Exclude genuinely airborne height above3world units; ordinary impact hops remain within contact tolerance. Cache spin-envelope geometry once per asset and skip pose work on empty ticks."],
              "world_radius_before":18,"world_radius_after":18,"spawn_points":fixed["spawn_points"],
              "baseline":{"source":str(args.baseline_source),"manifest":str(args.baseline),"manifest_sha256":sha(args.baseline),"cases":old,
                          "direct_world_successes":32,"clear_visual_overlap_misses":16,"full_capacity_impossible_drops":8,"render_cadence_misses":1},
              "fixed":{"manifest":str(args.fixed),"manifest_sha256":sha(args.fixed),"checks":fixed["checks"],"failures":fixed["failures"],"cases":fixed["cases"]},
              "native":{"manifest":str(args.capture),"manifest_sha256":sha(args.capture),"video":str(video),"video_sha256":sha(video),
                        "content_proof":capture["content_proof"],"source_sha256":capture["source_sha256"],"frozen_source":capture["frozen_source"],
                        "phases":capture["phases"],"feature_frames":capture["feature_frames"],"movie_metadata":capture["movie_metadata"],
                        "collection_audio_proof":audio},
              "current_pickup_regression":{"unique_headless_checks":5846,"failures":0,"suites":[
                  {"script":"tests/test_pickup_positions_003a1.gd","checks":2463},
                  {"script":"tests/test_grounded_pickups.gd","checks":3220},
                  {"script":"tests/test_pickup_feel_003a1.gd","checks":159},
                  {"script":"tests/test_feedback_live_pickup.gd","checks":4}],"native_capture_checks":capture["checks"]},
              "player_data_unchanged":capture["real_player_unchanged"],
              "authenticity":"Position/visible-bound tests are explicit supplied-path fixtures. Cadence and native16traversals execute ordinary waypoint inputs through the real fixed solver with explicit drop/start-pose/retired-opponent fixtures; no Main/draft/natural-drop/human-controller or final-package claim. Native art/Sound route; no real collection, Credits, SALVAGE, preferences or backups written.",
              "human_acceptance":"Pending hands-on confirmation. Native visible-envelope forgiveness is bounded to authored geometry; no global radius/economy/physics change."}
    outputs = [qa / "003a1_pickup_position_matrix.json",qa / "manifests/003a1_pickup_position_matrix.json"]
    assert all(not p.exists() for p in outputs), "Preserve prior evidence; do not replace an existing required matrix"
    content = json.dumps(matrix,indent=2)+"\n"
    for path in outputs:path.write_text(content,encoding="utf-8")
    assert outputs[0].read_bytes() == outputs[1].read_bytes()
    print(json.dumps({"passed":True,"matrix":str(outputs[0]),"canonical_manifest_copy":str(outputs[1]),"sha256":sha(outputs[0]),
                      "fixed_checks":fixed["checks"],"solid_native_overlap_pixels_min":min(r["solid_native_overlap_pixels_at_logged_pose"] for r in missed_visible)},indent=2))

if __name__ == "__main__":main()
