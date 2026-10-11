"""Guarded actual ecology and legal mutation-draft recordings; fresh QA only."""
from __future__ import annotations
import argparse, json, re, sys
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
for folder in ['tools/build','tools/workspace','tools/presentation','tools/capture']:
    sys.path.insert(0,str(ROOT/folder))
import windows_checkpoint as pipeline
import workspace
from rpm_economy_study_003a1 import source,profile
from presentation_showcase import movie_metadata
from combat_art003a1 import frozen_project

def capture(args):
    qa=workspace.create_task_workspace('003A.2')
    base='003a2_build_ecology_showcase' if args.mode=='ecology' else '003a2_mutation_draft_showcase'
    stem=base+'_'+datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S_%f')
    report=qa/'manifests'/f'{stem}.json';frames=qa/'frames'/stem
    raw=qa/'temp'/f'{stem}.avi';video=qa/'video'/f'{base}.mp4'
    assert args.diagnostic or not video.exists(),'Preserve prior final movie'
    player=profile();stage,original,frozen=frozen_project(qa,stem)
    if args.mode=='draft':
        text=(stage/'project.godot').read_bytes().decode('utf-8')
        for key,value in {'viewport_width':800,'viewport_height':480,'window_width_override':800,'window_height_override':480,'min_width':800,'min_height':480}.items():
            text,count=re.subn(r'(?m)^(window/size/'+key+r'=)\d+(\r?)$',lambda m:m[1]+str(value)+m[2],text);assert count==1
        (stage/'project.godot').write_bytes(text.encode('utf-8'));frozen=source(stage)
        assert {k:v for k,v in frozen.items() if k!='project.godot'}=={k:v for k,v in original.items() if k!='project.godot'}
    driver='tests/capture_ecology_showcase_003a2.gd' if args.mode=='ecology' else 'tests/capture_mutation_draft_003a2.gd'
    dependencies=[driver,'tests/mutation_draft_policy_003a2.gd']
    if args.mode=='ecology':dependencies+=['tests/ecology_showcase_fixture_003a2.gd','tests/mutation_physics_fixture_003a2.gd','tests/capture_impact_music_003a1.gd']
    hashes={name:pipeline.sha256(stage/name) for name in dependencies}
    assert hashes=={name:pipeline.sha256(ROOT/name) for name in dependencies}
    dims='640x400' if args.mode=='ecology' else '800x480'
    command=[workspace.find_tool('godot',args.engine),'--path',str(stage),'--script','res://'+driver,'--log-file',str(qa/'logs'/f'{stem}_engine.log')]
    command+=['--headless'] if args.diagnostic else ['--resolution',dims,'--fixed-fps','60','--disable-vsync','--write-movie',str(raw),'--audio-driver','Dummy']
    command+=['--','--manifest='+str(report),'--frames='+str(frames),'--collection-prefix='+str(qa/'temp'/stem)]
    if args.diagnostic:command+=['--diagnostic']
    process=pipeline.run_logged(command,qa/'logs'/f'{stem}.log',1200)
    data=json.loads(report.read_text());assert not data['failures'],data['failures']
    assert source(stage)==frozen and source(ROOT)==original and profile()==player
    assert hashes=={name:pipeline.sha256(stage/name) for name in dependencies}=={name:pipeline.sha256(ROOT/name) for name in dependencies}
    if args.mode=='ecology':
        assert len(data['scenes'])==8 and data['movie_frames']==4800+(0 if args.diagnostic else 36)
        assert all(s['clock_failures']==0 for s in data['scenes'])
    else:
        assert data['chosen_branch']=='flywheel_release' and data['runtime_events'].get('flywheel_release',0)>0
        assert data['legal_claims'] and data['two_actual_siblings'] and data['clock_failures']==0
    data.update(capture_process=process,frozen_project=str(stage),original_production_source=original,frozen_source=frozen,frozen_source_unchanged=True,production_source_unchanged=True,fixture_dependency_sha256=hashes,player_before=player,player_after=profile(),player_and_backups_unchanged=True,source_git_sha=pipeline.git(ROOT,'rev-parse','HEAD'),human_status='PENDING HUMAN REVIEW')
    if not args.diagnostic:
        ffmpeg=workspace.find_tool('ffmpeg',args.ffmpeg);info=movie_metadata(ffmpeg,raw);assert dims in info['metadata']
        command=[ffmpeg,'-v','error','-i',str(raw)]
        if args.mode=='draft':
            caption=frames/'declared_xp_caption.png';canvas=Image.new('RGB',(1600,64),(13,21,30));draw=ImageDraw.Draw(canvas);font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',19)
            draw.text((16,6),'DECLARED XP FIXTURE / seeded normal Main offers, actual level-up, two siblings, one III choice',font=font,fill=(229,189,117))
            draw.text((16,34),'Controls earn Bank and Burst payoff / normal 60 Hz / initial pose only; no live reserve or actor holds',font=font,fill=(189,204,204));canvas.save(caption)
            command+=['-loop','1','-i',str(caption)]
            if not info['has_audio']:command+=['-i',str(raw.with_suffix('.wav'))]
            command+=['-filter_complex','[0:v]scale=1600:960:flags=neighbor,pad=1600:1024:0:0:color=0x0d151e[game];[game][1:v]overlay=0:960:shortest=1[v]','-map','[v]','-map','0:a:0' if info['has_audio'] else '2:a:0']
            data['external_caption']={'path':str(caption),'sha256':pipeline.sha256(caption),'position':[0,960],'source_game_pixels_untouched_above_caption':True}
        else:
            captions=[];font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',15)
            for index,scene in enumerate(data['scenes']):
                actor=scene['initial']['actors'][0];parts=[]
                for family in actor['powers']:
                    title=family.replace('_',' ').upper()+' '+{1:'I',2:'II',3:'III'}[actor['ranks'][family]]
                    if family in actor['branches']:title+=' / '+actor['branches'][family].replace('_',' ').upper()
                    parts.append(title)
                caption=frames/f'package_{index:02d}.png';canvas=Image.new('RGB',(1280,80),(13,21,30));draw=ImageDraw.Draw(canvas)
                draw.text((14,8),'DECLARED LEGAL INITIAL BUILD / '+scene['id'].replace('_',' ').upper(),font=font,fill=(229,189,117))
                draw.text((14,31),' | '.join(parts),font=font,fill=(202,218,212))
                draw.text((14,54),'Actual controls, costs and contacts / individual event and ledger proof in manifest / no hidden synergy bonus',font=font,fill=(165,188,198))
                canvas.save(caption);captions.append({'path':str(caption),'sha256':pipeline.sha256(caption),'package':parts,'scene':scene['id']})
            sequence=frames/'package_captions.ffconcat';lines=['ffconcat version 1.0']
            for index,item in enumerate(captions):
                lines+=['file '+"'"+Path(item['path']).as_posix()+"'",'duration '+str(10.6 if index==7 else 10.0)]
            lines+=['file '+"'"+Path(captions[-1]['path']).as_posix()+"'"];sequence.write_text('\n'.join(lines)+'\n',encoding='utf-8')
            command+=['-f','concat','-safe','0','-i',str(sequence)]
            if not info['has_audio']:command+=['-i',str(raw.with_suffix('.wav'))]
            command+=['-filter_complex','[0:v]scale=1280:800:flags=neighbor,pad=1280:880:0:0:color=0x0d151e[game];[game][1:v]overlay=0:800:eof_action=repeat[v]','-map','[v]','-map','0:a:0' if info['has_audio'] else '2:a:0']
            data['external_package_captions']={'images':captions,'position':[0,800],'native_game_and_caption_pixels_untouched_above_footer':True,'timeline':'Each declared600-frame scene; final36-frame silent teardown retains final package footer.'}
        command+=['-c:v','libx264','-crf','18','-preset','fast','-c:a','aac','-b:a','192k','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
        encode=pipeline.run_logged(command,qa/'logs'/f'{stem}_encode.log',600)
        decode=pipeline.run_logged([ffmpeg,'-v','error','-i',str(video),'-f','null','-'],qa/'logs'/f'{stem}_decode.log',180)
        meta=movie_metadata(ffmpeg,video);assert meta['has_audio'] and abs(meta['duration_seconds']-data['movie_frames']/60)<.3
        for item in data['features'].values():
            png=pipeline.png_record(Path(item['path']));assert (png['width'],png['height'])==((640,400) if args.mode=='ecology' else (800,480))
        data.update(video=str(video),video_sha256=pipeline.sha256(video),raw_sha256=pipeline.sha256(raw),encoder=encode,decoder=decode,movie_metadata=meta,editorial='Uncut normal60FPS within disclosed scenes, actual synchronized Godot audio. Integer2× nearest from native viewport. Legal initial fixtures and declared XP inputs, no injected live power state or ongoing body/resource holds. This is runtime/flow evidence, not natural survival or human balance acceptance.')
    assert profile()==player and source(ROOT)==original and source(stage)==frozen
    pipeline.write_json(report,data)
    if not args.diagnostic:
        primary=qa/'manifests'/f'{base}.json';assert not primary.exists();pipeline.write_json(primary,data)
    print(json.dumps({'passed':True,'manifest':str(report),'video':data.get('video'),'seconds':data['movie_frames']/60,'source_unchanged':True,'profiles_unchanged':True},indent=2),flush=True)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mode',choices=['ecology','draft'],required=True);p.add_argument('--diagnostic',action='store_true');p.add_argument('--engine');p.add_argument('--ffmpeg');capture(p.parse_args())
if __name__=='__main__':main()
