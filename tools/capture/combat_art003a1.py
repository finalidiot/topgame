"""Render native arena/power reviews and a seven-card before/after matrix.

Each movie uses a fresh frozen source/cache copy. The power movie labels held
visual states; arena scenes label clock-offset initial fixtures and real solver
controls. Exact source and all real player/backups are fingerprinted. It never
opens Main or mutates collection/preferences. Previous final media is refused.
"""
from __future__ import annotations
import argparse, json, re, shutil, sys
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[2]
for folder in ['tools/build','tools/workspace','tools/presentation','tools/capture','tools']:
    sys.path.insert(0,str(ROOT/folder))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source, profile
from presentation_showcase import movie_metadata

def frozen_project(qa,stem):
    before=source(ROOT);stage=qa/'temp'/f'{stem}_source';assert not stage.exists()
    stage.mkdir()
    for name in ['project.godot','main.tscn']:shutil.copy2(ROOT/name,stage/name)
    for folder in ['scripts','assets','tests','.godot']:shutil.copytree(ROOT/folder,stage/folder)
    assert source(stage)==before,'Source changed while copying; retain unused stage and retry from a stable tree'
    # The production name contains a UTF-8 em dash and is also the save identity.
    # Decode explicitly and preserve original newline bytes outside six display
    # dimensions. A Windows locale decoder must never change that identity.
    original_project=(stage/'project.godot').read_bytes()
    text=original_project.decode('utf-8')
    dimensions={'viewport_width':640,'viewport_height':400,'window_width_override':640,'window_height_override':400,'min_width':640,'min_height':400}
    for key,value in dimensions.items():
        text,n=re.subn(r'(?m)^(window/size/'+key+r'=)\d+(\r?)$',lambda match:match[1]+str(value)+match[2],text);assert n==1,key
    original_lines=original_project.decode('utf-8').splitlines(keepends=True);adjusted_lines=text.splitlines(keepends=True)
    assert len(original_lines)==len(adjusted_lines),'QA project line topology changed'
    changed={}
    for old,new in zip(original_lines,adjusted_lines):
        if old==new:continue
        match=re.fullmatch(r'window/size/([a-z_]+)=\d+(\r?\n?)',old)
        assert match and match[1] in dimensions,'QA project changed outside declared display dimensions: '+old
        assert new==f'window/size/{match[1]}={dimensions[match[1]]}'+match[2]
        changed[match[1]]=True
    assert set(changed)==set(dimensions),'Each declared initial-window dimension must be changed exactly once'
    (stage/'project.godot').write_bytes(text.encode('utf-8'))
    observed=source(stage)
    assert {k:v for k,v in observed.items() if k!='project.godot'}=={k:v for k,v in before.items() if k!='project.godot'}
    return stage,before,observed

def validate(data,rendered):
    assert data['failures']==[],data['failures']
    assert not data['main_created'] and not data['collection_opened']
    assert data['native_gameplay']==[640,360] and data['native_caption_canvas']==[640,400]
    if data['mode']=='powers':
        assert [s['family'] for s in data['scenes']]==['redline','predator_line','impact_sink','ghost_circuit','afterimage']
        assert data['movie_frames']==1800 and all(s['held_state_fixture'] and not s['balance_claim'] for s in data['scenes'])
        required=['redline_ring_and_motion','predator_flow_turn','sink_partial','sink_full','sink_vent','ghost_physical_latch','ghost_travelling_current','afterimage_live_route']
        assert any(r['sink']['state']=='PARTIAL' for r in data['rows']) and any(r['sink']['state']=='FULL' for r in data['rows'])
        assert any(any(t.get('circuit_points') for t in r['traces']) for r in data['rows'])
    else:
        assert len(data['scenes'])==6 and data['movie_frames']==2160
        assert all(s['live_frames']>=120 and s['peak_arena_draw_calls']<=17 and not s['balance_claim'] for s in data['scenes'])
        assert all(r['native_arena'].get('display_panel_draw_calls',0)==0 for r in data['rows'])
        required=['early','building','mid','late','extreme','extreme_reduced_flashing']
    if rendered:
        assert set(required)<=set(data['features'])
        for name in required:
            item=pipeline.png_record(Path(data['features'][name]['path']));assert item['width']==640 and item['height']==360

def capture(args):
    qa=workspace.create_task_workspace('003A.1')
    base='003a1_power_visual_cleanup' if args.mode=='powers' else '003a1_arena_rework'
    stem=base+'_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    report=qa/'manifests'/f'{stem}.json';raw=qa/'temp'/f'{stem}.avi';video=qa/'video'/f'{stem if args.provisional else base}.mp4';frames=qa/'frames'/stem
    assert args.diagnostic or not video.exists(),'Preserve prior final evidence'
    player=profile();stage,original,frozen=frozen_project(qa,stem)
    driver=stage/'tests/capture_combat_art003a1.gd';driver_sha=pipeline.sha256(driver)
    command=[workspace.find_tool('godot',args.engine),'--path',str(stage),'--script','res://tests/capture_combat_art003a1.gd','--log-file',str(qa/'logs'/f'{stem}_engine.log')]
    if args.diagnostic:command+=['--headless']
    else:command+=['--resolution','640x400','--fixed-fps','60','--disable-vsync','--write-movie',str(raw),'--audio-driver','Dummy']
    command+=['--','--mode='+args.mode,'--manifest='+str(report),'--frames='+str(frames)]
    if args.diagnostic:command+=['--diagnostic']
    process=pipeline.run_logged(command,qa/'logs'/f'{stem}.log',1200)
    data=json.loads(report.read_text());validate(data,not args.diagnostic)
    assert source(stage)==frozen and pipeline.sha256(driver)==driver_sha and profile()==player
    data.update(capture_process=process,frozen_project=str(stage),original_production_source=original,frozen_source=frozen,source_unchanged=True,driver_sha256=driver_sha,player_before=player,player_after=profile(),player_and_backups_unchanged=True,source_git_sha=pipeline.git(ROOT,'rev-parse','HEAD'),display_variance='Only QA snapshot initial window/viewport minimum and override dimensions become640×400 before Movie Maker starts. Standalone Battle retains canonical640×360 projection; extra40pixels are outside-play caption strip. No Main/HUD acceptance claim.',human_status='PENDING HUMAN REVIEW')
    if not args.diagnostic:
        ffmpeg=workspace.find_tool('ffmpeg',args.ffmpeg);raw_info=movie_metadata(ffmpeg,raw)
        assert '640x400' in raw_info['metadata'],'Movie Maker source must remain native pixels'
        process=pipeline.run_logged([ffmpeg,'-v','error','-i',str(raw),'-an','-vf','scale=1280:800:flags=neighbor','-c:v','libx264','-crf','18','-preset','fast','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],qa/'logs'/f'{stem}_encode.log',600)
        decode=pipeline.run_logged([ffmpeg,'-v','error','-i',str(video),'-f','null','-'],qa/'logs'/f'{stem}_decode.log',180)
        metadata=movie_metadata(ffmpeg,video);assert abs(metadata['duration_seconds']-data['movie_frames']/60)<.3
        data.update(video=str(video),video_sha256=pipeline.sha256(video),raw_sha256=pipeline.sha256(raw),encoder=process,decoder=decode,movie_metadata=metadata,editorial='Native gameplay640×360 plus external40px caption strip, displayed at integer2× nearest. Silent art review; audio is evaluated separately by combat/music review. No cuts within each scene.')
    pipeline.write_json(report,data)
    print(json.dumps({'passed':True,'manifest':str(report),'video':data.get('video'),'seconds':data['movie_frames']/60,'player_and_backups_unchanged':True},indent=2))

def cards(args):
    qa=workspace.create_task_workspace('003A.1');output=qa/'images/003a1_card_art_corrections.png';report=qa/'manifests/003a1_card_art_corrections.json'
    assert not output.exists() and not report.exists(),'Preserve prior final evidence'
    families=[('redline','REDLINE'),('orbit_drive','ORBIT DRIVE'),('anchor_exchange','ANCHOR EXCHANGE'),('afterimage','AFTERIMAGE'),('predator_line','PREDATOR LINE'),('impact_sink','IMPACT SINK'),('ghost_circuit','GHOST CIRCUIT')]
    def metadata(project):
        result=json.loads((project/'assets/powers/identity_manifest.json').read_text())['art'];result.update(json.loads((project/'assets/powers/defence003a/manifest.json').read_text())['art']);return result
    before=metadata(args.baseline);after=metadata(ROOT);font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',10)
    sheet=Image.new('RGBA',(7*84+16,212),(11,18,25,255));draw=ImageDraw.Draw(sheet)
    draw.text((8,4),'BEFORE / ACCEPTED 6a852cf     NATIVE 64PX CARDS',(188,202,195),font)
    draw.text((8,110),'AFTER / 003A.1 COMBAT ART CANDIDATE',(217,184,112),font)
    evidence=[]
    for index,(name,label) in enumerate(families):
        for project,data,top in [(args.baseline,before,20),(ROOT,after,126)]:
            item=data[name];texture=project/str(item['card_texture']).removeprefix('res://');atlas=Image.open(texture).convert('RGBA')
            key=int(item['card_static_frame']);row=int(item['card_row']);cell=atlas.crop((key*64,row*64,(key+1)*64,(row+1)*64))
            at=(16+index*84,top);sheet.alpha_composite(cell,at)
            words=label.split(' ')
            for line_no,word in enumerate(words):draw.text((at[0],top+66+line_no*11),word,(174,195,196),font)
            evidence.append({'id':name,'period':'before' if project==args.baseline else 'after','cell':[64,64],'key':key,'row':row,'source_texture':str(texture),'texture_sha256':pipeline.sha256(texture),'cell_rgba_sha256':__import__('hashlib').sha256(cell.tobytes()).hexdigest()})
    sheet.save(output,optimize=True)
    pipeline.write_json(report,{'task':'003A.1 final combat art','native_scale':True,'resampling':False,'cards':evidence,'image':str(output),'image_sha256':pipeline.sha256(output),'baseline':str(args.baseline),'scope':'Native actual runtime card cels on review background. Unchanged comparison cards preserve roster grammar. Labels are outside64px cells. No animation/balance acceptance claim.'})
    print(json.dumps({'image':str(output),'report':str(report),'native_scale':True},indent=2))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mode',choices=['arena','powers','cards'],required=True);p.add_argument('--diagnostic',action='store_true');p.add_argument('--provisional',action='store_true');p.add_argument('--engine');p.add_argument('--ffmpeg');p.add_argument('--baseline',type=Path);args=p.parse_args()
    if args.mode=='cards':
        if not args.baseline:p.error('Cards require immutable --baseline source')
        cards(args)
    else:capture(args)

if __name__=='__main__':main()
