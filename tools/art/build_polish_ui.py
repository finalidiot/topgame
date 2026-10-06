"""Saved-native UI exporter and explicit 003A human-feedback pixel authoring.

--author reconstructs only this new family. Normal use exports artist edits.
--clean-background removes obsolete shared cels; --clean-power-beds edits only
known native UI backdrops, preserving all other source chunks/layers verbatim.
"""
from pathlib import Path
import argparse, hashlib, json, struct, subprocess, sys, tempfile, zlib
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from build_power_art import read_ase, write_ase
sys.path.insert(0,str(ROOT/'tools/art'))
import build_front_end as frontend
sys.path.insert(0,str(ROOT/'tools/workspace'))
from workspace import create_task_workspace, find_tool
SOURCE=ROOT/'assets/source-art/human_feedback003a'
OUT=ROOT/'assets/ui/human_feedback003a'
P={**frontend.PALETTE,'skin':'#b99377','skin light':'#e1c3a1','hair':'#574332',
   'apron':'#80553b','apron light':'#ad744a','blue cloth':'#365869','glove':'#d1d5ba',
   'cyan':'#79bed0','white':'#ffffff','grey':'#87999e','panel':'#1c2933',
   'button':'#263640','hover':'#344853','selected':'#704c33','disabled':'#172129'}
def c(name):return tuple(bytes.fromhex(P.get(name,name).lstrip('#')))+(255,)
def blank(size):return Image.new('RGBA',size)
def text(im,value,x,y,ink='paper'):
 for i,ch in enumerate(value):frontend.draw_pattern(im,frontend.PATTERNS[ch],x+i*6,y,c(ink))
def bolt(d,x,y):
 d.rectangle((x,y,x+2,y+2),fill=c('ink'));d.line((x+1,y,x+1,y+1),fill=c('silver'))
def plate_factory(kind):
 size=24 if kind=='button_caps' else 32
 states=['NORMAL','HOVER','PRESSED','DISABLED','FOCUS','SELECTED'] if kind=='button_caps' else (['INSPECTION'] if kind=='inspection_frame' else ['NORMAL','HOVER','SELECTED'])
 frames=[]
 for state in states:
  face,edge,detail=[blank((size,size)) for _ in range(3)]
  d=ImageDraw.Draw(face);e=ImageDraw.Draw(edge);a=ImageDraw.Draw(detail);n=size-1
  if state!='FOCUS':
   fill='selected' if state=='SELECTED' else ('amber' if state=='PRESSED' else ('disabled' if state=='DISABLED' else ('hover' if state=='HOVER' else ('button' if size==24 else 'panel'))))
   d.polygon([(3,1),(n-3,1),(n-1,3),(n-1,n-4),(n-4,n-1),(3,n-1),(1,n-3),(1,4)],fill=c('ink'))
   d.rectangle((4,4,n-4,n-5),fill=c(fill))
   d.rectangle((2,5,n-2,n-6),fill=c(fill));d.rectangle((5,2,n-5,n-4),fill=c(fill))
   e.line([(3,2),(n-4,2),(n-2,4)],fill=c('steel'))
   e.line([(2,5),(2,n-5),(4,n-3),(n-5,n-3)],fill=c('seam'))
   e.line([(n-2,5),(n-2,n-5),(n-5,n-2),(5,n-2)],fill=c('ink'),width=2)
   a.line((6,3,9,3),fill=c('oxide'));a.line((n-9,n-4,n-6,n-4),fill=c('steel'))
   if size==32:
    for x,y in [(4,5),(n-6,n-7)]:bolt(a,x,y)
   else:
    a.line((4,7,4,10),fill=c('steel'));a.line((n-5,n-10,n-5,n-7),fill=c('steel'))
   if state in ['HOVER','SELECTED','PRESSED']:
    a.line((5,3,n-6,3),fill=c('cyan' if state=='HOVER' else 'brass'))
   if kind=='inspection_frame':
    a.rectangle((3,11,4,n-10),fill=c('oxide'));a.line((8,3,15,3),fill=c('cyan'))
  else:
   # White mask is tinted by the theme; centre is genuinely transparent.
   for points in [[(1,8),(1,3),(3,1),(8,1)],[(n-8,1),(n-3,1),(n-1,3),(n-1,8)],[(1,n-8),(1,n-3),(3,n-1),(8,n-1)],[(n-8,n-1),(n-3,n-1),(n-1,n-3),(n-1,n-8)]]:
    a.line(points,fill=c('white'),width=2)
  frames.append([face,edge,detail])
 return frames,['inset material face','rolled edge and lower lip','placed fasteners and printed state'],[(s,i,i) for i,s in enumerate(states)],[1000]*len(states),(0,0)
def merchant_factory():
 frames=[]
 for k in range(14):
  shadow,stance,body,head,arms,prop=[blank((48,64)) for _ in range(6)]
  d=ImageDraw.Draw(shadow);d.polygon([(11,59),(16,57),(35,57),(41,60),(33,62),(14,62)],fill=c('ink'))
  d=ImageDraw.Draw(stance)
  d.rectangle((15,48,22,57),fill=c('blue cloth'));d.rectangle((28,48,34,57),fill=c('blue cloth'))
  d.polygon([(14,55),(21,55),(23,60),(12,60),(12,58)],fill=c('ink'));d.polygon([(28,55),(35,55),(38,59),(38,60),(27,60)],fill=c('ink'))
  d.line((14,57,20,57),fill=c('steel'));d.line((30,57,35,57),fill=c('steel'))
  dy=1 if k in [1,5,8,11] else 0
  d=ImageDraw.Draw(body)
  d.polygon([(15,26+dy),(33,26+dy),(39,32+dy),(36,48),(32,54),(14,54),(11,34+dy)],fill=c('ink'))
  d.polygon([(16,27+dy),(31,27+dy),(36,33+dy),(33,48),(15,48),(13,33+dy)],fill=c('blue cloth'))
  d.polygon([(18,28+dy),(30,28+dy),(33,34+dy),(34,52),(14,52),(16,34+dy)],fill=c('apron'))
  d.line([(18,29+dy),(20,33+dy),(29,33+dy),(30,29+dy)],fill=c('apron light'))
  d.rectangle((20,39+dy,28,46+dy),fill=c('hair'));d.line((21,40+dy,27,40+dy),fill=c('apron light'))
  d.rectangle((21,24+dy,27,29+dy),fill=c('skin'))
  d=ImageDraw.Draw(head)
  tilt=1 if k in [4,5,10,11] else 0
  d.polygon([(17+tilt,9+dy),(31+tilt,9+dy),(33+tilt,15+dy),(31+tilt,24+dy),(26+tilt,27+dy),(19+tilt,24+dy),(16+tilt,16+dy)],fill=c('ink'))
  d.polygon([(18+tilt,10+dy),(30+tilt,10+dy),(31+tilt,20+dy),(27+tilt,25+dy),(20+tilt,23+dy),(18+tilt,18+dy)],fill=c('skin'))
  d.rectangle((17+tilt,7+dy,31+tilt,11+dy),fill=c('oxide'));d.polygon([(19+tilt,4+dy),(29+tilt,4+dy),(32+tilt,8+dy),(16+tilt,8+dy)],fill=c('amber'))
  d.line((18+tilt,10+dy,31+tilt,10+dy),fill=c('hair'))
  d.rectangle((18+tilt,13+dy,31+tilt,17+dy),fill=c('ink'));d.rectangle((19+tilt,14+dy,23+tilt,16+dy),fill=c('cyan'));d.rectangle((26+tilt,14+dy,30+tilt,16+dy),fill=c('cyan'))
  if k in [2,12]:d.line((19+tilt,15+dy,30+tilt,15+dy),fill=c('steel'))
  else:d.point((22+tilt,14+dy),fill=c('paper'));d.point((29+tilt,14+dy),fill=c('paper'))
  d.line((22+tilt,22+dy,27+tilt,22+dy),fill=c('hair'));d.point((28+tilt,20+dy),fill=c('skin light'))
  d=ImageDraw.Draw(arms)
  d.polygon([(13,31+dy),(17,32+dy),(17,41+dy),(12,44+dy),(8,41+dy),(9,35+dy)],fill=c('blue cloth'))
  d.rectangle((10,39+dy,15,43+dy),fill=c('glove'));d.line((10,42+dy,14,42+dy),fill=c('paper'))
  reach=[0,0,1,0,4,5,1,4,7,3,1,2,2,0][k]
  hand_y=35+dy-(3 if k in [4,5,10,11] else 0)
  d.polygon([(32,30+dy),(36,30+dy),(39+reach//2,hand_y),(35+reach,hand_y+4),(32,38+dy)],fill=c('blue cloth'))
  d.rectangle((34+reach,hand_y,39+reach,hand_y+4),fill=c('glove'));d.line((36+reach,hand_y,38+reach,hand_y),fill=c('paper'))
  d=ImageDraw.Draw(prop)
  if k in [6,7,8,9]:
   x=min(39,33+reach);y=hand_y-4
   d.rectangle((x,y,x+7,y+12),fill=c('ink'));d.rectangle((x+1,y+1,x+6,y+11),fill=c('paper'))
   d.line((x+1,y+2,x+6,y+2),fill=c('pouch shade') if 'pouch shade' in P else c('grey'));d.rectangle((x+2,y+5,x+5,y+8),fill=c('oxide'))
  else:
   d.rectangle((7,43+dy,17,48+dy),fill=c('ink'));d.rectangle((8,43+dy,16,47+dy),fill=c('paper'));d.line((10,45+dy,14,45+dy),fill=c('steel'))
  frames.append([shadow,stance,body,head,arms,prop])
 tags=[('IDLE',0,3),('SELECT',4,5),('PURCHASE',6,9),('RARE',10,13)]
 return frames,['bounded contact shadow','boots and fixed stance','work clothes and leather apron','cap goggles and expression','authored arm and glove poses','sorting slip or hand-delivered pouch'],tags,[1200,160,1300,180,180,220,140,140,170,220,130,180,160,250],(24,60)
def fixture_factory():
 plate,details,label=[blank((192,64)) for _ in range(3)]
 d=ImageDraw.Draw(plate);d.polygon([(5,16),(20,5),(175,5),(187,16),(180,30),(8,30)],fill=c('ink'));d.polygon([(8,16),(22,8),(173,8),(183,16),(177,24),(11,24)],fill=c('steel'))
 d.rectangle((11,25,178,56),fill=c('bench'));d.line((12,26,177,26),fill=c('silver'));d.rectangle((15,31,175,52),fill=c('rubber'))
 e=ImageDraw.Draw(details)
 for x,y in [(14,15),(175,15),(17,47),(170,47)]:bolt(e,x,y)
 e.line((23,19,49,19),fill=c('oxide'));e.line((146,19,167,19),fill=c('seam'));e.rectangle((31,28,41,46),fill=c('ink'));e.rectangle((33,30,39,43),fill=c('oxide'))
 e.rectangle((151,28,164,44),fill=c('ink'));e.rectangle((154,29,161,40),fill=c('steel'));e.line((155,31,160,31),fill=c('silver'))
 d=ImageDraw.Draw(label);d.rectangle((68,34,123,47),fill=c('paper'));text(label,'PARTS',80,36,'ink');d.point((71,38),fill=c('oxide'));d.point((120,44),fill=c('oxide'))
 return [[plate,details,label]],['counter surface and lower weight','fasteners and used workshop tools','printed parts-trade paper label'],[('COUNTER',0,0)],[1000],(96,20)
def chip_factory():
 frames=[]
 for width in [12,8,3,7]:
  body,stamp=[blank((16,16)) for _ in range(2)];d=ImageDraw.Draw(body);x=8-width//2
  d.polygon([(x+2,2),(x+width-3,2),(x+width-1,4),(x+width-1,11),(x+width-3,13),(x+1,13),(x,11),(x,4)],fill=c('ink'))
  d.rectangle((x+1,4,x+width-2,11),fill=c('amber'));d.line((x+1,4,x+1,10),fill=c('brass'));d.line((x+2,12,x+width-3,12),fill=c('oxide'))
  if width>5:
   a=ImageDraw.Draw(stamp);a.line((7,5,7,10),fill=c('ink'));a.line((9,5,9,10),fill=c('ink'));a.line((6,7,10,7),fill=c('oxide'))
  frames.append([body,stamp])
 return frames,['stamped copper credit slug','pressed credit tally marks'],[('CHIP_SPIN',0,3)],[90,80,70,90],(8,8)
def station_factory():
 surface=blank((160,56));frontend.service_station(surface,80,18,64)
 return [[surface]],['accepted C6 station extracted into explicit screen-local fixture'],[('STATION',0,0)],[1000],(80,18)
SPECS={'metal_plate':lambda:plate_factory('metal_plate'),'inspection_frame':lambda:plate_factory('inspection_frame'),
 'button_caps':lambda:plate_factory('button_caps'),'merchant':merchant_factory,'merchant_fixture':fixture_factory,
 'credit_chip':chip_factory,'preview_station':station_factory}
def author():
 SOURCE.mkdir(parents=True,exist_ok=True)
 for name,factory in SPECS.items():write_ase(SOURCE/f'{name}.aseprite',*factory(),note='003A human feedback / original native pixel workshop UI / named editable cels / bounded merchant / nearest output',palette=P)
def rendered(name):
 frames,meta=read_ase(SOURCE/f'{name}.aseprite');w,h=meta['cell'];atlas=blank((w*len(frames),h))
 for i,frame in enumerate(frames):atlas.alpha_composite(frame,(i*w,0))
 meta.update(version=1,texture=f'{name}.png',columns=len(frames),frame_count=len(frames),native_pixels=True,filter='nearest',task='003A human feedback',source=f'../../source-art/human_feedback003a/{name}.aseprite')
 if name in ['metal_plate','inspection_frame','button_caps']:meta.update(stretch_margins=[8,8,8,8],content_margins=[8,2,8,2])
 return frames,atlas,meta
def export():
 OUT.mkdir(parents=True,exist_ok=True)
 for name in SPECS:
  _,atlas,meta=rendered(name);atlas.save(OUT/f'{name}.png',optimize=True);(OUT/f'{name}.json').write_text(json.dumps(meta,indent=2)+'\n')
def clean_background():
 # Only this source is explicitly reauthored; bitmap type/input masters stay saved.
 frontend.write_ase(frontend.SOURCE/'frontend_background.aseprite',*frontend.background_master(),note='003A human feedback / shared quiet chrome only / obsolete display bays and cross-content bench dividers removed / screen-local pedestal separately preserved',palette=frontend.PALETTE)
 frames,atlas,meta=frontend.render_source('frontend_background');atlas.save(frontend.OUT/'frontend_background.png',optimize=True);(frontend.OUT/'frontend_background.json').write_text(json.dumps(meta,indent=2)+'\n')
def edit_cels(path,callback):
 data=path.read_bytes();pos=128;out=[];frame_count=struct.unpack_from('<H',data,6)[0]
 for frame in range(frame_count):
  length,magic,old,duration,new=struct.unpack_from('<IHHH2xI',data,pos);at=pos+16;chunks=[]
  for _ in range(new or old):
   size,kind=struct.unpack_from('<IH',data,at);payload=data[at+6:at+size]
   if kind==0x2005:
    layer,x,y,opacity,cel_type,z=struct.unpack_from('<HhhBHh',payload)
    if cel_type in [0,2]:
     w,h=struct.unpack_from('<HH',payload,16);raw=zlib.decompress(payload[20:]) if cel_type==2 else payload[20:]
     image=Image.frombytes('RGBA',(w,h),raw);changed=callback(image,frame,layer,x,y)
     if changed:payload=payload[:20]+(zlib.compress(image.tobytes(),9) if cel_type==2 else image.tobytes())
   chunks.append(struct.pack('<IH',len(payload)+6,kind)+payload);at+=size
  body=b''.join(chunks);header=bytearray(data[pos:pos+16]);struct.pack_into('<I',header,0,len(body)+16);out.append(bytes(header)+body);pos+=length
 header=bytearray(data[:128]);body=b''.join(out);struct.pack_into('<I',header,0,len(body)+128)
 result=bytes(header)+body
 if result!=data:path.write_bytes(result)
def clean_power_beds():
 # Exact UI rectangle/corner mask from the inspected Core recipe. Other cels,
 # authored floor marks, accepted top anatomy/tags/timings are retained verbatim.
 import author_identity_core as core
 mask=core.card_layers()[0];changed=[]
 for family in ['momentum_bank','predator_line','crash_guard','crosscut','dead_centre']:
  source=ROOT/f'assets/source-art/power_identity_002c5/{family}_cards.aseprite';count=[0]
  def remove(im,frame,layer,x,y):
   if layer!=0:return False
   pixels=im.load();m=mask.load();n=0
   for py in range(im.height):
    for px in range(im.width):
     ax,ay=px+x,py+y
     if 0<=ax<64 and 0<=ay<64 and m[ax,ay][3] and pixels[px,py]==m[ax,ay]:pixels[px,py]=(0,0,0,0);n+=1
   count[0]+=n;return bool(n)
  edit_cels(source,remove)
  if count[0]:save_card_export(source)
  changed.append({'family':family,'removed_ui_bed_pixels':count[0]})
 # The native audit proved these two source layers contain only the historical
 # UI backplate, not the meaningful contact/machine composition on other layers.
 import build_power_art as original
 for family,index in [('impact_wake',0),('chain_impact',2)]:
  source=ROOT/f'assets/source-art/power_identity_002c5/{family}_cards.aseprite';mask=original.canvas(64);original.card_backdrop(mask,index);count=[0]
  def remove_backplate(im,frame,layer,x,y):
   if layer!=0:return False
   if not im.getbbox():return False
   if (x,y)!=(0,0) or im.tobytes()!=mask.tobytes():raise ValueError(f'{family}: saved backdrop no longer matches inspected UI-only layer; review artist changes')
   count[0]+=sum(pixel[3]>0 for pixel in im.get_flattened_data());im.paste((0,0,0,0),(0,0,64,64));return True
  edit_cels(source,remove_backplate)
  if count[0]:save_card_export(source)
  changed.append({'family':family,'removed_ui_bed_pixels':count[0],'scene_and_contact_layers_retained':True})
 # Afterimage's illustration shares layer0 with its bevel. The saved cells
 # exactly match this recipe; remove the bevel operation, preserving genuine
 # floor, route scars and contact shadows even where their colours match it.
 import author_identity_foundation as foundation
 source=ROOT/'assets/source-art/power_identity_002c5/afterimage_cards.aseprite';_,meta=read_ase(source)
 before=[];after=[];bed=foundation.card_bed
 for tag,span in meta['tags'].items():
  for index in range(span['to']-span['from']+1):before.append(foundation.afterimage_card(tag,index)[0])
 try:
  foundation.card_bed=lambda ims:None
  for tag,span in meta['tags'].items():
   for index in range(span['to']-span['from']+1):after.append(foundation.afterimage_card(tag,index)[0])
 finally:foundation.card_bed=bed
 count=[0]
 def remove_bevel(im,frame,layer,x,y):
  if layer!=0:return False
  if im.tobytes()==after[frame].tobytes():return False
  if (x,y)!=(0,0) or im.tobytes()!=before[frame].tobytes():raise ValueError('Afterimage floor no longer matches inspected original; review artist changes')
  count[0]+=sum(p!=q for p,q in zip(im.get_flattened_data(),after[frame].get_flattened_data()));im.paste(after[frame]);return True
 edit_cels(source,remove_bevel)
 if count[0]:save_card_export(source)
 changed.append({'family':'afterimage','removed_ui_bed_pixels':count[0],'floor_route_contact_pixels_retained':True})
 return changed
def save_card_export(source):
 frames,meta=read_ase(source);atlas=blank((64*12,64*((len(frames)+11)//12)))
 for i,frame in enumerate(frames):atlas.alpha_composite(frame,((i%12)*64,(i//12)*64))
 atlas.save(ROOT/f'assets/powers/identity/{source.stem}.png',optimize=True)
def check():
 exe=find_tool('aseprite');qa=create_task_workspace('003A');report={'task':'003A human feedback','read_only':True,'masters':[],'power_cards':[]}
 with tempfile.TemporaryDirectory(prefix='human-feedback-native-',dir=qa/'temp') as temp:
  for name in SPECS:
   frames,atlas,meta=rendered(name);png=Path(temp)/f'{name}.png';js=Path(temp)/f'{name}.json'
   subprocess.run([exe,'--batch',str(SOURCE/f'{name}.aseprite'),'--list-layers','--list-tags','--list-slices','--sheet-type','horizontal','--sheet',str(png),'--data',str(js),'--format','json-array'],check=True,capture_output=True)
   info=json.loads(js.read_text());assert Image.open(png).convert('RGBA').tobytes()==atlas.tobytes();assert Image.open(OUT/f'{name}.png').convert('RGBA').tobytes()==atlas.tobytes()
   assert json.loads((OUT/f'{name}.json').read_text())==meta;assert [l['name'] for l in info['meta']['layers']]==meta['layers'];assert [f['duration'] for f in info['frames']]==meta['durations_ms']
   assert {t['name']:{'from':t['from'],'to':t['to']} for t in info['meta']['frameTags']}==meta['tags']
   pivot=info['meta']['slices'][0]['keys'][0]['pivot'];assert [pivot['x'],pivot['y']]==meta['pivot']
   report['masters'].append({'name':name,'cell':meta['cell'],'layers':meta['layers'],'tags':meta['tags'],'pivot':meta['pivot'],'native_runtime_parity':True,'source_sha256':hashlib.sha256((SOURCE/f'{name}.aseprite').read_bytes()).hexdigest(),'runtime_sha256':hashlib.sha256((OUT/f'{name}.png').read_bytes()).hexdigest()})
  # Audit the entire real roster, not only the reported Crash Guard example.
  # This reads saved artists' masters; it never invokes reconstruct/export tools.
  for source in sorted((ROOT/'assets/source-art/power_identity_002c5').glob('*_cards.aseprite')):
   family=source.stem.removesuffix('_cards');frames,meta=read_ase(source);png=Path(temp)/f'{family}_cards.png';js=Path(temp)/f'{family}_cards.json'
   subprocess.run([exe,'--batch',str(source),'--list-layers','--list-tags','--list-slices','--sheet-columns','12','--sheet',str(png),'--data',str(js),'--format','json-array'],check=True,capture_output=True)
   native=Image.open(png).convert('RGBA');runtime=Image.open(ROOT/f'assets/powers/identity/{family}_cards.png').convert('RGBA');info=json.loads(js.read_text())
   assert native.size==runtime.size==(768,64*((len(frames)+11)//12)),(family,'sheet topology')
   # Native Aseprite retains RGB below alpha0; normalize only invisible pixels.
   def visible(im):
    data=bytearray(im.tobytes())
    for at in range(0,len(data),4):
     if data[at+3]==0:data[at:at+3]=b'\0\0\0'
    return bytes(data)
   assert visible(native)==visible(runtime),(family,'native/runtime pixels')
   for index,frame in enumerate(frames):
    cell=native.crop((index%12*64,index//12*64,index%12*64+64,index//12*64+64))
    assert visible(cell)==visible(frame),(family,index,'source reader/native parity')
   assert [l['name'] for l in info['meta']['layers']]==meta['layers'];assert [f['duration'] for f in info['frames']]==meta['durations_ms']
   assert {t['name']:{'from':t['from'],'to':t['to']} for t in info['meta']['frameTags']}==meta['tags']
   pivot=info['meta']['slices'][0]['keys'][0]['pivot'];assert [pivot['x'],pivot['y']]==meta['pivot']==[32,32]
   report['power_cards'].append({'family':family,'cell':meta['cell'],'frames':len(frames),'layers':meta['layers'],'native_runtime_parity':True,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'runtime_sha256':hashlib.sha256((ROOT/f'assets/powers/identity/{family}_cards.png').read_bytes()).hexdigest()})
 return report
def preview(path):
 im=Image.new('RGBA',(960,440),c('ink'))
 for i in range(6):
  frames,_,_=rendered('merchant');im.alpha_composite(frames[[0,2,4,7,8,11][i]].resize((96,128),Image.Resampling.NEAREST),(i*150+20,20))
 _,fixture,_=rendered('merchant_fixture');im.alpha_composite(fixture,(20,175))
 _,station,_=rendered('preview_station');im.alpha_composite(station,(250,190))
 for row,name in enumerate(['metal_plate','inspection_frame','button_caps','credit_chip']):
  frames,_,_=rendered(name)
  for column,frame in enumerate(frames):im.alpha_composite(frame.resize((frame.width*2,frame.height*2),Image.Resampling.NEAREST),(460+column*76,170+row*65))
 path.parent.mkdir(parents=True,exist_ok=True);im.convert('RGB').save(path)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--author',action='store_true');p.add_argument('--clean-background',action='store_true');p.add_argument('--clean-power-beds',action='store_true');p.add_argument('--check',action='store_true');p.add_argument('--report',type=Path);p.add_argument('--preview',type=Path);a=p.parse_args()
 for path in [a.report,a.preview]:
  if path and (path.resolve()==ROOT or ROOT in path.resolve().parents):raise ValueError('QA output must remain external')
 if a.check and (a.author or a.clean_background or a.clean_power_beds):p.error('--check is read-only')
 if a.author:author()
 if a.clean_background:clean_background()
 if a.clean_power_beds:print(json.dumps(clean_power_beds(),indent=2))
 report=check() if a.check else None
 if not a.check:export()
 if a.report and report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
 if a.preview:preview(a.preview)
 if report:print(json.dumps(report,indent=2))
if __name__=='__main__':main()
