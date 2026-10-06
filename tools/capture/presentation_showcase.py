"""Input-driven C6 front-end/Run capture with actual mixed game audio.

Creates only fresh external QA collections/reports. Native chronology is kept;
the review movie omits a labelled middle survival interval to stay45-90seconds.
"""
from __future__ import annotations

import argparse
from array import array
from datetime import datetime,timezone
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import wave

from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools/workspace"))
import workspace
sys.path.insert(0,str(ROOT/"tools/build"))
import windows_checkpoint as pipeline


def validate(data:dict,visible:bool)->None:
    assert data["fresh_save_proof"]["owned_count"]==3
    assert data["fresh_save_proof"]["starter"]=="breaker"
    assert data["catalogue_fixture"]["seeded_count"]==31
    assert data["catalogue_fixture"]["final"]["total_owned"]==31
    assert data["high_pressure_start_frame"]>data["prefix_end_frame"]
    assert data["natural_result_start_frame"]>data["high_pressure_start_frame"]
    assert data["natural_result"].get("continuous_run") and not data["natural_result"].get("won",True)
    assert all(event["type"] in ["key","joy_button","joy_axes","gui_mouse_click"] for event in data["input_events"])
    assert any(event["type"]=="joy_button" for event in data["input_events"])
    assert len(data["rows"])>3
    assert any(float(row["music"]["stable_run"]["pressure"])>=0.5 for row in data["rows"])
    assert data["sfx_final"]["played"].get("launch",0)>0
    assert data["sfx_final"]["played"].get("ui",0)>0
    if visible:
        for name in ["fresh_ceremony","fresh_confirmation","fresh_owned","catalogue_title_gate","hub","workshop_full_catalogue","workshop_blade","workshop_ratchet","workshop_bit","options","save_tools","reset_confirmation_cancelled","help","play_modes","starting_power","hud_opening","pause","pause_options","hud_high_pressure","natural_run_result","returned_hub"]:
            item=data["images"][name]
            assert pipeline.png_record(Path(item["path"]))["width"]==640
        assert data["music_final"]["playback_enabled"] and data["music_final"]["transport_starts"]==1


def matrix(data:dict,task:Path,name:str)->Path:
    selected=["catalogue_title_gate","hub","fresh_ceremony","fresh_confirmation","fresh_owned","workshop_full_catalogue","workshop_blade","workshop_ratchet","workshop_bit","assembled_owned_top","options","save_tools","reset_confirmation_cancelled","play_modes","help","starting_power","hud_opening","pause","pause_options","hud_high_pressure","natural_run_result","returned_hub"]
    rows=(len(selected)+3)//4
    sheet=Image.new("RGB",(2560,rows*386),(20,25,32))
    draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype("C:/Windows/Fonts/consola.ttf",14)
    for i,key in enumerate(selected):
        item=data["images"][key]
        at=(i%4*640,i//4*386)
        draw.text((at[0]+8,at[1]+4),key.replace("_"," ").upper(),font=font,fill=(222,234,219))
        image=Image.open(item["path"]).convert("RGB")
        assert image.size==(640,360)
        sheet.paste(image,(at[0],at[1]+26))
    target=task/"images"/("002c6_ui_matrix.png" if not(task/"images/002c6_ui_matrix.png").exists() else name+"_ui_matrix.png")
    sheet.save(target)
    return target


def movie_metadata(ffmpeg:str,path:Path)->dict:
    p=subprocess.run([ffmpeg,"-hide_banner","-i",str(path)],capture_output=True,text=True)
    duration=re.search(r"Duration: (\d+):(\d+):(\d+(?:\.\d+)?)",p.stderr)
    assert duration,"Encoded duration must be readable"
    seconds=int(duration[1])*3600+int(duration[2])*60+float(duration[3])
    return {"duration_seconds":seconds,"has_audio":"Audio:" in p.stderr,"metadata":p.stderr}


def encode(data:dict,raw:Path,target:Path,task:Path,name:str,ffmpeg:str)->dict:
    # Use the actual writer's audio stream. If the platform puts it in a WAV
    # sidecar, preserve and mux that exact file; never substitute asset audio.
    raw_meta=movie_metadata(ffmpeg,raw)
    sidecar=raw.with_suffix(".wav")
    args=[ffmpeg,"-v","error","-i",str(raw)]
    audio_input="0:a"
    if not raw_meta["has_audio"]:
        assert sidecar.is_file(),"The review requires actual movie-writer mixed audio"
        args += ["-i",str(sidecar)]
        audio_input="1:a"
    prefix=int(data["prefix_end_frame"])
    high=int(data["high_pressure_start_frame"])
    result=int(data["natural_result_start_frame"])
    end=int(data["raw_frames"])-1
    # Keep the whole input/navigation prefix. Include six to ten seconds of
    # the genuinely observed high-intensity state and the real natural loss.
    high_end=min(high+600,result)
    loss_start=max(high_end,result-240)
    spans=[(0,prefix),(high,high_end),(loss_start,end)]
    spans=[(a,b) for a,b in spans if b>a]
    expected=sum(b-a for a,b in spans)/60
    assert 45<=expected<=90,f"Review edit must stay45-90s (computed{expected:.2f}s)"
    filters=[]
    for i,(start,stop) in enumerate(spans):
        label=("FRESH SAVE PROOF / THEN EXPLICIT31PART QA FIXTURE" if i==0 else (f"CHRONOLOGY SKIP / ACTUAL HIGH PRESSURE / RAW{start/60:.1f}s" if i==1 else f"CHRONOLOGY SKIP / NATURAL RUN END / RAW{start/60:.1f}s"))
        label=label.replace(":",r"\:").replace("'",r"\'")
        font=r"C\:/Windows/Fonts/consola.ttf"
        filters.append(f"[0:v]trim=start_frame={start}:end_frame={stop},setpts=PTS-STARTPTS,scale=1280:720:flags=neighbor,drawtext=fontfile='{font}':text='{label}':x=12:y=702:fontsize=12:fontcolor=white:box=1:boxcolor=black@0.7[v{i}]")
        filters.append(f"[{audio_input}]atrim=start={start/60:.8f}:end={stop/60:.8f},asetpts=PTS-STARTPTS[a{i}]")
    filters.append("".join(f"[v{i}][a{i}]" for i in range(len(spans)))+f"concat=n={len(spans)}:v=1:a=1[v][a]")
    args += ["-filter_complex",";".join(filters),"-map","[v]","-map","[a]","-c:v","libx264","-crf","18","-preset","fast","-pix_fmt","yuv420p","-c:a","aac","-b:a","192k","-ar","48000","-movflags","+faststart",str(target)]
    encoded=pipeline.run_logged(args,task/"logs"/(name+"_encode.log"),600)
    decoded=pipeline.run_logged([ffmpeg,"-v","error","-i",str(target),"-f","null","-"],task/"logs"/(name+"_decode.log"),300)
    metadata=movie_metadata(ffmpeg,target)
    assert metadata["has_audio"] and abs(metadata["duration_seconds"]-expected)<0.25
    assert 45<=metadata["duration_seconds"]<=90
    wav=task/"temp"/(name+"_actual_mix.wav")
    pipeline.run_logged([ffmpeg,"-v","error","-i",str(target),"-map","0:a:0","-c:a","pcm_s16le",str(wav)],task/"logs"/(name+"_audio_decode.log"),120)
    with wave.open(str(wav),"rb") as sound:
        assert sound.getnchannels()==2 and sound.getframerate() in [32000,48000]
        pcm=sound.readframes(sound.getnframes())
    samples=array("h",pcm)
    peak=max(abs(v) for v in samples)/32768
    rms=math.sqrt(sum(v*v for v in samples)/len(samples))/32768
    assert rms>0.001 and 0.005<peak<0.99,"Actual game mix must be audible with clipping headroom"
    return {"video":str(target),"video_sha256":pipeline.sha256(target),"actual_duration_seconds":metadata["duration_seconds"],"encoder":encoded,"decoder":decoded,"raw_movie":str(raw),"raw_movie_sha256":pipeline.sha256(raw),"raw_audio_in_avi":raw_meta["has_audio"],"raw_audio_sidecar":str(sidecar) if sidecar.is_file() else None,"actual_audio_decode":str(wav),"actual_audio_sha256":pipeline.sha256(wav),"audio_sample_rate":48000,"actual_audio_peak":peak,"actual_audio_rms":rms,"chronological_edit_spans":[{"from_frame":a,"to_frame":b,"raw_start_seconds":a/60,"raw_end_seconds":b/60} for a,b in spans],"editorial":"Actual input-driven navigation and real physics/music/SFX. Chronological excerpts only; omitted middle Run survival time is labelled. Native640x360 presentation enlarged integer2x nearest, no retouched game content or replacement audio."}


def music_review(data:dict,raw:Path,task:Path,name:str,ffmpeg:str)->dict:
    by_name={s["name"]:s for s in data["sections"]}
    title=by_name["catalogue_title_gate"]["from_frame"]
    workshop=by_name["workshop_full_catalogue"]["from_frame"]
    normal=by_name["normal_run"]["from_frame"]
    high=data["high_pressure_start_frame"]
    spans=[("TITLE",title,by_name["hub"]["to_frame"]),
           ("WORKSHOP",workshop,workshop+360),
           ("NORMAL RUN",normal,by_name["normal_run"]["to_frame"]),
           ("ACTUAL ADMITTED BOSS",high,min(high+600,data["natural_result_start_frame"]))]
    destination=task/"video"/("002c6_music_showcase.mp4" if not(task/"video/002c6_music_showcase.mp4").exists() else name+"_music.mp4")
    raw_meta=movie_metadata(ffmpeg,raw)
    args=[ffmpeg,"-v","error","-i",str(raw)]
    stream="0:a"
    if not raw_meta["has_audio"]:
        args += ["-i",str(raw.with_suffix(".wav"))];stream="1:a"
    filters=[]
    for i,(context,start,stop) in enumerate(spans):
        text=f"{context} / ACTUAL MIX / RAW{start/60:.1f}-{stop/60:.1f}s / CHRONOLOGICAL EXCERPT"
        filters.append(f"[0:v]trim=start_frame={start}:end_frame={stop},setpts=PTS-STARTPTS,scale=1280:720:flags=neighbor,drawtext=fontfile='C\\:/Windows/Fonts/consola.ttf':text='{text}':x=12:y=702:fontsize=12:fontcolor=white:box=1:boxcolor=black@0.7[v{i}]")
        filters.append(f"[{stream}]atrim=start={start/60:.8f}:end={stop/60:.8f},asetpts=PTS-STARTPTS[a{i}]")
    filters.append("".join(f"[v{i}][a{i}]" for i in range(4))+"concat=n=4:v=1:a=1[v][a]")
    args += ["-filter_complex",";".join(filters),"-map","[v]","-map","[a]","-c:v","libx264","-crf","18","-preset","fast","-pix_fmt","yuv420p","-c:a","aac","-b:a","192k","-ar","48000","-movflags","+faststart",str(destination)]
    encoder=pipeline.run_logged(args,task/"logs"/(name+"_music_encode.log"),300)
    decoder=pipeline.run_logged([ffmpeg,"-v","error","-i",str(destination),"-f","null","-"],task/"logs"/(name+"_music_decode.log"),120)
    metadata=movie_metadata(ffmpeg,destination)
    expected=sum(stop-start for _,start,stop in spans)/60
    assert metadata["has_audio"] and abs(metadata["duration_seconds"]-expected)<0.25
    pcm_path=task/"temp"/(name+"_music_actual_mix.wav")
    pipeline.run_logged([ffmpeg,"-v","error","-i",str(destination),"-map","0:a:0","-c:a","pcm_s16le",str(pcm_path)],task/"logs"/(name+"_music_audio.log"),120)
    with wave.open(str(pcm_path),"rb") as recording:
        rate=recording.getframerate();samples=array("h",recording.readframes(recording.getnframes()))
        assert rate==48000 and recording.getnchannels()==2
    peak=max(abs(v) for v in samples)/32768
    rms=math.sqrt(sum(v*v for v in samples)/len(samples))/32768
    assert rms>0.001 and 0.005<peak<0.99
    return {"video":str(destination),"sha256":pipeline.sha256(destination),"seconds":metadata["duration_seconds"],"source_raw_movie":str(raw),"source_raw_sha256":pipeline.sha256(raw),"actual_mix_pcm":str(pcm_path),"actual_mix_sha256":pipeline.sha256(pcm_path),"peak":peak,"rms":rms,"sample_rate":rate,"encoder":encoder,"decoder":decoder,"contexts":[{"context":context,"from_frame":start,"to_frame":stop,"raw_start_seconds":start/60,"raw_end_seconds":stop/60} for context,start,stop in spans],"provenance":"Exact same input-driven capture and its MovieMaker mixed audio; no substituted stems. High intensity is caused by an actual admitted Run boss. Chronological omissions are labelled."}


def main()->None:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine")
    parser.add_argument("--ffmpeg")
    parser.add_argument("--qa-root",type=Path)
    parser.add_argument("--diagnostic",action="store_true")
    parser.add_argument("--seed",type=int,default=421)
    parser.add_argument("--max-run-seconds",type=float,default=240)
    args=parser.parse_args()
    task=workspace.create_task_workspace("002C.6",args.qa_root)
    name="002c6_frontend_"+("diagnostic_" if args.diagnostic else "capture_")+datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S_%f")
    output=task/"manifests"/(name+".json")
    raw=task/"temp"/(name+".avi")
    frame_dir=task/"frames"/name
    target=task/"video"/("002c6_frontend_showcase.mp4" if not(task/"video/002c6_frontend_showcase.mp4").exists() else name+".mp4")
    profile_before=pipeline.production_profile(ROOT)
    files=["scripts/main.gd","scripts/menus.gd","scripts/front_end.gd","scripts/music.gd","scripts/top_preview.gd","scripts/collection_save.gd","scripts/battle.gd","tests/capture_presentation_c6.gd","tools/capture/presentation_showcase.py"]
    source_before={p:pipeline.sha256(ROOT/p) for p in files}
    (task/"manifests"/(name+"_inputs.json")).write_text(json.dumps({"source_git_sha":pipeline.git(ROOT,"rev-parse","HEAD"),"source_sha256":source_before,"profile_before":profile_before},indent=2)+"\n")
    command=[workspace.find_tool("godot",args.engine),"--path",str(ROOT),"--script","res://tests/capture_presentation_c6.gd","--fixed-fps","60","--disable-vsync"]
    command += ["--headless"] if args.diagnostic else ["--write-movie",str(raw),"--audio-driver","Dummy"]
    command += ["--","--manifest="+str(output),"--collection="+str(task/"temp"/(name+"_catalogue.json")),"--fresh-collection="+str(task/"temp"/(name+"_fresh.json")),"--run-seed="+str(args.seed),"--max-run-seconds="+str(args.max_run_seconds)]
    command += ["--diagnostic"] if args.diagnostic else ["--frames="+str(frame_dir)]
    print("INPUT_DRIVEN_FRONTEND_CAPTURE "+name,flush=True)
    process=pipeline.run_logged(command,task/"logs"/(name+".log"),900)
    data=json.loads(output.read_text())
    validate(data,not args.diagnostic)
    data.update(capture_process=process,source_git_sha=pipeline.git(ROOT,"rev-parse","HEAD"),working_tree=pipeline.git(ROOT,"status","--porcelain"),profile_before=profile_before,profile_after=pipeline.production_profile(ROOT))
    data["profile_unchanged"]=data["profile_before"]==data["profile_after"]
    assert data["profile_unchanged"]
    data["source_sha256"]={p:pipeline.sha256(ROOT/p) for p in files}
    data["capture_source_unchanged"]=data["source_sha256"]==source_before
    assert data["capture_source_unchanged"],"Freeze capture inputs until recording has finished"
    if not args.diagnostic:
        data["native_ui_matrix"]=str(matrix(data,task,name))
        ffmpeg=workspace.find_tool("ffmpeg",args.ffmpeg)
        data.update(encode(data,raw,target,task,name,ffmpeg))
        data["music_showcase"]=music_review(data,raw,task,name,ffmpeg)
    output.write_text(json.dumps(data,indent=2)+"\n")
    print(json.dumps({"passed":True,"manifest":str(output),"video":data.get("video"),"matrix":data.get("native_ui_matrix"),"profile_unchanged":True,"fresh_owned":3,"catalogue_fixture_owned":31},indent=2))


if __name__=="__main__":main()
