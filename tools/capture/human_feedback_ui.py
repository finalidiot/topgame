"""Record the corrected UI through real keyboard/pad input and natural rewards."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/capture"))
import progression_showcase as capture
pipeline, workspace = capture.pipeline, capture.workspace

def matrix(data: dict, task: Path) -> Path:
    before = task / "images/human_feedback_before"
    comparisons = [("TITLE / VISUAL CENTRE", "01-title.png", "title_centred"),
                   ("HUB / SHARED UNDERLAY", "01a-workbench.png", "clean_hub_owned"),
                   ("MAKE IT YOURS / DIVIDER", "09a-confirm.png", "make_it_yours"),
                   ("POWER DRAFT / ART AND READING", "10-starting-draft.png", "power_draft_inspection"),
                   ("SHOP / MERCHANT AND PRODUCT LIST", "003a-shop.png", "shop_native")]
    extras = ["three_starter_fx", "workshop", "collection_before", "options", "pause_ability_inspection",
              "run_1_result", "results_wallet_settled", "results_ability_inspection", "packet_purchase_confirmation", "packet_result"]
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 16)
    out = Image.new("RGB", (1280, (len(comparisons) + (len(extras)+1)//2)*386), (20,25,32))
    draw = ImageDraw.Draw(out)
    for row, (label, prior, current) in enumerate(comparisons):
        for column, (caption, path) in enumerate([("BEFORE", before/prior), ("AFTER", Path(data["images"][current]["path"]))]):
            pixels = Image.open(path).convert("RGB")
            if caption == "BEFORE" and pixels.size == (1280,720):
                # The retained packaged smoke used an integer2x window. Keep
                # its original file and show its native-scale comparison here.
                pixels = pixels.resize((640,360), Image.Resampling.NEAREST)
            assert pixels.size == (640,360)
            draw.text((column*640+10,row*386+4), caption+" / "+label, fill=(232,236,225),font=font)
            out.paste(pixels,(column*640,row*386+26))
    for index, key in enumerate(extras):
        column, row = index%2, len(comparisons)+index//2
        pixels = Image.open(data["images"][key]["path"]).convert("RGB")
        assert pixels.size == (640,360)
        draw.text((column*640+10,row*386+4), key.upper().replace("_"," "),fill=(232,236,225),font=font)
        out.paste(pixels,(column*640,row*386+26))
    target = task / "images/003a_human_feedback_ui_matrix.png"
    assert not target.exists()
    out.save(target)
    return target

def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--diagnostic",action="store_true")
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--encode-manifest",type=Path)
    args=parser.parse_args()
    task=workspace.create_task_workspace("003A")
    name="003a_human_feedback_ui_"+datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output=args.encode_manifest or task/"manifests"/(name+".json")
    raw=task/"temp"/(name+".avi")
    target=task/"video/003a_human_feedback_ui_polish.mp4"
    profile_before=pipeline.production_profile(ROOT)
    files=[*sorted(ROOT.glob("scripts/*.gd")),*sorted((ROOT/"assets").rglob("*.png")),*sorted((ROOT/"assets").rglob("*.json")),ROOT/"tests/capture_human_feedback_ui.gd",ROOT/"tests/capture_progression_003a.gd",Path(__file__).resolve()]
    source_before={p.relative_to(ROOT).as_posix():pipeline.sha256(p) for p in files}
    if not args.encode_manifest:
        (task/"manifests"/(name+"_inputs.json")).write_text(json.dumps({"source_before":source_before,"profile_before":profile_before},indent=2)+"\n")
        command=[workspace.find_tool("godot",args.engine),"--path",str(ROOT),"--script","res://tests/capture_human_feedback_ui.gd","--fixed-fps","60","--disable-vsync"]
        command += ["--headless"] if args.diagnostic else ["--write-movie",str(raw),"--audio-driver","Dummy"]
        command += ["--","--manifest="+str(output),"--collection="+str(task/"temp"/(name+"_collection.json")),"--qa-task=003A","--run-seed=421"]
        command += ["--diagnostic"] if args.diagnostic else ["--frames="+str(task/"frames"/name)]
        process=pipeline.run_logged(command,task/"logs"/(name+".log"),1500)
        data=json.loads(output.read_text())
        capture.validate(data,not args.diagnostic)
        assert not any(e["type"]=="gui_mouse_click" for e in data["input_events"])
        assert profile_before==pipeline.production_profile(ROOT)
        source_after={p.relative_to(ROOT).as_posix():pipeline.sha256(p) for p in files}
        assert source_before==source_after,"Recording inputs must remain frozen"
        data.update(capture_process=process,raw_movie=str(raw),source_sha256=source_after,capture_source_unchanged=True,profile_before=profile_before,profile_after=pipeline.production_profile(ROOT),profile_unchanged=True,source_git_sha=pipeline.git(ROOT,"rev-parse","HEAD"),working_tree=pipeline.git(ROOT,"status","--porcelain"))
        output.write_text(json.dumps(data,indent=2)+"\n")
    else:
        data=json.loads(output.read_text())
        raw=Path(data["raw_movie"])
    if not args.diagnostic:
        assert not target.exists()
        data.update(capture.encode(data,raw,target,task,name,workspace.find_tool("ffmpeg",args.ffmpeg)))
        data["ui_matrix"]=str(matrix(data,task))
        output.write_text(json.dumps(data,indent=2)+"\n")
    print(json.dumps({"passed":True,"manifest":str(output),"video":data.get("video"),"matrix":data.get("ui_matrix")},indent=2))

if __name__=="__main__": main()
