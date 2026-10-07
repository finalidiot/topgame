"""Capture current production Windows UI and combine with verified Android pixels.

The Android image is required for final assembly. No simulated desktop touch
layout may be substituted for an APK-rendered cell. Old evidence is preserved.
"""
from __future__ import annotations
import argparse
from datetime import datetime,timezone
import json,sys
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/workspace'));sys.path.insert(0,str(ROOT/'tools/build'))
import workspace
import windows_checkpoint as pipeline

def capture(engine,task):
    stem='003a_final_ui_windows_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    manifest=task/'manifests'/f'{stem}.json';frames=task/'frames'/stem;collection=task/'temp'/f'{stem}_collection.json'
    assert not any(p.exists() for p in [manifest,frames,collection])
    profile=pipeline.production_profile(ROOT)
    paths=[*sorted((ROOT/'scripts').glob('*.gd')),*sorted((ROOT/'assets').rglob('*.png')),*sorted((ROOT/'assets').rglob('*.json')),ROOT/'project.godot',ROOT/'tests/capture_final_ui.gd',Path(__file__).resolve()]
    before={p.relative_to(ROOT).as_posix():pipeline.sha256(p) for p in paths}
    command=[workspace.find_tool('godot',engine),'--path',str(ROOT),'--script','res://tests/capture_final_ui.gd','--resolution','640x360','--audio-driver','Dummy','--','--manifest='+str(manifest),'--frames='+str(frames),'--collection='+str(collection),'--qa-task=003A']
    process=pipeline.run_logged(command,task/'logs'/f'{stem}.log',180)
    data=json.loads(manifest.read_text());assert data['failures']==[],data['failures']
    after={p.relative_to(ROOT).as_posix():pipeline.sha256(p) for p in paths}
    assert before==after,'UI source changed during capture'
    assert profile==pipeline.production_profile(ROOT),'Real profile changed'
    for image in data['images'].values():
        pixels=Image.open(image['path']);assert pixels.size==(640,360)
        image['sha256']=pipeline.sha256(Path(image['path']))
    data.update(source_sha256=before,source_unchanged=True,profile_before=profile,profile_after=profile,profile_unchanged=True,capture_process=process,source_git_sha=pipeline.git(ROOT,'rev-parse','HEAD'))
    manifest.write_text(json.dumps(data,indent=2)+'\n')
    print(json.dumps({'windows_manifest':str(manifest),'native_images':len(data['images']),'profile_unchanged':True},indent=2),flush=True)
    return manifest

def matrix(manifest,android,task,phone_provenance,android_surface):
    data=json.loads(manifest.read_text());assert data['failures']==[]
    slots=[('TITLE','title'),('MAIN HUB','main_hub'),('STARTER SELECTION','starter_selection'),('MAKE IT YOURS','make_it_yours'),('POWER DRAFT','power_draft'),('DEFENCE ABILITY INSPECTION','ability_inspection'),('RESULTS','results'),('SHOP','shop'),('PACKET FINAL RESULT','packet_final_result'),('WORKSHOP','workshop'),('GYRO LOCK MUTATIONS','mutation_gyro_lock'),('IMPACT SINK MUTATIONS','mutation_impact_sink'),('ANCHOR EXCHANGE MUTATIONS','mutation_anchor_exchange'),('REDUCED FLASHING OPTION','reduced_flashing_option')]
    frames=[(label,Path(data['images'][key]['path'])) for label,key in slots]
    frames.append(('ANDROID GAMEPLAY / '+android_surface.upper(),android))
    width,height=1280,((len(frames)+1)//2)*386
    out=Image.new('RGB',(width,height),(20,25,32));draw=ImageDraw.Draw(out);font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',16)
    entries=[]
    for index,(label,path) in enumerate(frames):
        pixels=Image.open(path).convert('RGB');assert pixels.size==(640,360),(path,pixels.size,'Require verified native640 image')
        column,row=index%2,index//2
        draw.text((column*640+10,row*386+4),label,fill=(232,236,225),font=font);out.paste(pixels,(column*640,row*386+26))
        entries.append({'label':label,'source':str(path),'sha256':pipeline.sha256(path),'native_pixels':[640,360]})
    target=task/'images/003a_final_ui_matrix.png';assert not target.exists(),'Preserve previous final matrix'
    out.save(target)
    report={'matrix':str(target),'sha256':pipeline.sha256(target),'size':[width,height],'entries':entries,'windows_manifest':str(manifest),'android_capture_provenance':str(phone_provenance) if phone_provenance else None,'android_surface':android_surface,'scope':'All screen cells use native640x360 source pixels without resizing. Caption rows are outside screen cells. Windows cells are labelled saved-flow/UI fixtures; Android gameplay is the actual APK capture on the labelled phone/emulator surface.'}
    path=task/'manifests/003a_final_ui_matrix.json';assert not path.exists();path.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    return target

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--capture-windows',action='store_true');p.add_argument('--windows-manifest',type=Path);p.add_argument('--android-frame',type=Path);p.add_argument('--phone-provenance',type=Path);p.add_argument('--android-surface',choices=['real phone','APK in emulator'],default='APK in emulator');p.add_argument('--engine');p.add_argument('--qa-root',type=Path);a=p.parse_args()
    task=workspace.create_task_workspace('003A',a.qa_root)
    if not a.capture_windows and not a.windows_manifest:p.error('--capture-windows or --windows-manifest required')
    manifest=capture(a.engine,task) if a.capture_windows else a.windows_manifest
    if a.android_frame:matrix(manifest,a.android_frame,task,a.phone_provenance,a.android_surface)
    else:print('Windows capture prepared; verified Android APK frame still required for matrix assembly.')

if __name__=='__main__':main()
