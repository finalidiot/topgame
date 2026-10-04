"""Phone review from native authored card animation and genuine input-only movies.

Compositing is restricted to editorial labels/cuts and nearest card display.
Gameplay frames are decoded at their recorded1280x720 size and never altered.
"""
import argparse
import io
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT=Path(__file__).resolve().parents[1]
FFMPEG='C:/GPT GAME BUILDING/task-002c5-qa/runtimes/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
SIZE=(1280,720); FPS=60
NAMES={'impact_wake':'Impact Wake II','redline':'Redline II','iron_comet':'Iron Comet II',
       'dead_centre':'Dead Centre II','afterimage':'Afterimage II','chain_impact':'Chain Impact II',
       'clutch':'Clutch II','high_gear':'High Gear II','orbit_drive':'Orbit Drive II',
       'crash_guard':'Crash Guard II','momentum_bank':'Momentum Bank II',
       'predator_line':'Predator Line II','crosscut':'Crosscut II',
       'ghost_circuit':'Afterimage / Ghost Circuit'}
# 1.2s authored card story followed by1.8s from the recorded natural proc window.
SHOW=[('impact_wake','impact_wake_ii',.30),('momentum_bank','momentum_bank_ii',.15),
      ('predator_line','predator_line_ii',1.1),('iron_comet','iron_comet_ii',.25),
      ('redline','redline_ii',.30),('dead_centre','dead_centre_ii',.10),
      ('ghost_circuit','ghost_circuit',.20),('chain_impact','chain_impact_ii',.10),
      ('clutch','clutch_ii',.20),('high_gear','high_gear_ii',.10),
      ('orbit_drive','orbit_drive_ii',.20),('crash_guard','crash_guard_ii',.15),
      ('crosscut','crosscut_ii',.10)]
FONT=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',22)
BIG=ImageFont.truetype('C:/Windows/Fonts/consolab.ttf',36)

def decode(avi,start,length):
    process=subprocess.Popen([FFMPEG,'-v','error','-ss',str(start),'-i',str(avi),'-t',str(length),
                              '-an','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
    for _ in range(round(length*FPS)):
        data=process.stdout.read(SIZE[0]*SIZE[1]*3)
        if len(data)!=SIZE[0]*SIZE[1]*3: break
        yield Image.frombytes('RGB',SIZE,data)
    process.stdout.close(); assert process.wait()==0

def encoder(path):
    return subprocess.Popen([FFMPEG,'-y','-v','error','-f','rawvideo','-pix_fmt','rgb24','-s','1280x720',
        '-r','60','-i','-','-an','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p',
        '-movflags','+faststart',str(path)],stdin=subprocess.PIPE)

def image_at(avi,at):
    result=subprocess.check_output([FFMPEG,'-v','error','-ss',str(max(0,at)),'-i',str(avi),'-frames:v','1','-f','image2pipe','-vcodec','png','-'])
    image=Image.open(io.BytesIO(result)).convert('RGB');assert image.size==SIZE
    return image

def source_image(path):return Image.open(ROOT/path.removeprefix('res://')).convert('RGBA')

def card_frame(meta,art_id,t):
    a=meta['art'][art_id]; times=a['card_durations_ms']; total=sum(times)
    # Preserve authored relative holds, fitting exactly one full story into1.2s.
    cursor=t/1.2*total;index=0
    for index,duration in enumerate(times):
        cursor-=duration
        if cursor<0:break
    source=source_image(a['card_texture']);row=a['card_row']
    return source.crop((index*64,row*64,(index+1)*64,(row+1)*64))

def contact_sheets(motion,out):
    reviews=out/'motion-review';reviews.mkdir(exist_ok=True)
    summaries=[]
    for manifest in sorted(motion.glob('*.json')):
        selection=manifest.stem
        avi=motion/(selection+'.avi')
        if not avi.exists() or selection.endswith('probe'):continue
        report=json.loads(manifest.read_text());run=report['runs'][0]
        proc_times=[p['time']-run['actual_start'] for p in run['proc_moments']
                    if run['actual_start']+.05<=p['time']<=run['actual_start']+4.5
                    and p['kind'] not in ['afterimage','afterimage_ii','afterimage_hit','chain_prime','momentum_store','redline_overcap']]
        at=min(proc_times,default=.9)
        canvas=Image.new('RGB',(1024,352),'#111b24');d=ImageDraw.Draw(canvas)
        d.text((10,8),selection+' / actual input-only event or moving-state / 100ms sequence',font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',13),fill='#e4ebd6')
        rows=run['rows']
        for index in range(8):
            t=max(0,at-.2+index*.10)
            frame=image_at(avi,t)
            sample=min(rows,key=lambda r:abs(r['time']-(run['actual_start']+t)))
            px,py=sample['position']; center=(round(320+px-py),round(153+(px+py)*.5))
            # Reduce only the original integer2x view back to its logical native size.
            native=frame.resize((640,360),Image.Resampling.NEAREST)
            cx=max(96,min(544,center[0]));cy=max(56,min(304,center[1]))
            crop=native.crop((cx-96,cy-56,cx+96,cy+56))
            x=(index%4)*256;y=36+(index//4)*152
            canvas.paste(crop,(x,y));d.text((x+2,y+115),f'{t:.2f}s / real{run["actual_start"]+t:.2f}s',font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',12),fill='#bbc8cf')
        canvas.save(reviews/(selection+'_sequence.png'))
        ImageOps.grayscale(canvas).convert('RGB').save(reviews/(selection+'_sequence_gray.png'))
        summaries.append({'selection':selection,'start':run['actual_start'],'window_counters':run['window_counters'],'review_at':at})
    (out/'motion-review-index.json').write_text(json.dumps(summaries,indent=2))

def compose(motion,out,meta):
    showcase=encoder(out/'002c5_power_art_showcase.mp4')
    blind=encoder(out/'002c5_power_blind_review.mp4')
    segments=[]
    for selection,art_id,start in SHOW:
        report=json.loads((motion/(selection+'.json')).read_text());run=report['runs'][0]
        assert run['capture_frames']==360 and report['blind'] and not report['diagnostic']
        art=meta['art'][art_id];icon=source_image(art['icon']).crop((art['icon_frame']*16,0,(art['icon_frame']+1)*16,16))
        for index in range(72):
            canvas=Image.new('RGB',SIZE,'#111b24');d=ImageDraw.Draw(canvas)
            d.text((52,36),'002C.5 / POWER ART DESIGN REVIEW',font=FONT,fill='#bbc8cf')
            frame=card_frame(meta,art_id,index/FPS);frame=frame.resize((384,384),Image.Resampling.NEAREST)
            canvas.paste(frame,(146,164),frame);canvas.paste(icon.resize((64,64),Image.Resampling.NEAREST),(616,184),icon.resize((64,64),Image.Resampling.NEAREST))
            d.text((616,282),NAMES[selection],font=BIG,fill='#e4ebd6')
            d.text((616,346),'Authored card → HUD icon',font=FONT,fill='#d4b886')
            d.text((616,383),'Then real combat animation',font=FONT,fill='#bbc8cf')
            d.text((52,655),'Controlled single-family opening builds; full launch reserve, inputs only.',font=FONT,fill='#bbc8cf')
            showcase.stdin.write(canvas.tobytes())
        count=0
        for frame in decode(motion/(selection+'.avi'),start,1.8):
            blind.stdin.write(frame.tobytes())
            d=ImageDraw.Draw(frame);d.rectangle((0,672,1279,719),fill='#111b24')
            d.text((24,683),NAMES[selection]+' / REAL COMBAT / steering, Burst, brake',font=FONT,fill='#e4ebd6')
            showcase.stdin.write(frame.tobytes());count+=1
        assert count==108,(selection,count)
        segments.append({'selection':selection,'art_id':art_id,'source_avi':str(motion/(selection+'.avi')),
                         'actual_gameplay_start':run['actual_start']+start,'gameplay_seconds':1.8,'card_seconds':1.2,
                         'recorded_window_procs':run['window_counters']})
        print(selection+' editorial segment composed',flush=True)
    for process in [showcase,blind]: process.stdin.close();assert process.wait()==0
    (out/'showcase-provenance.json').write_text(json.dumps({'showcase_seconds':39,'blind_seconds':23.4,
        'encoding':'1280x72060fps H264 yuv420p faststart muted. Card nearest6x; gameplay native integer2x1280x720 untouched except labelled footer in showcase. Blind removes cards/names/footer.','segments':segments},indent=2))

def main():
    p=argparse.ArgumentParser();p.add_argument('--motion',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--sheets-only',action='store_true');args=p.parse_args();args.out.mkdir(parents=True,exist_ok=True)
    meta=json.loads((ROOT/'assets/powers/identity_manifest.json').read_text())
    if not args.sheets_only:compose(args.motion,args.out,meta)
    contact_sheets(args.motion,args.out)

if __name__=='__main__':main()
