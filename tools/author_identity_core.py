"""Human correction v2: actual top bodies and physical floor/contact stories.

This is an explicit authoring recipe, not the normal exporter. It reuses the
accepted native starter blade cels without resampling/recolouring and assembles
the same native bit/ratchet parts as Battle. Saved Aseprite masters are editable.
No gameplay, RNG, capture or shared rendering code is changed by this recipe.
"""
import argparse, json, math, hashlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps
from build_power_art import write_ase, read_ase
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets/source-art/power_identity_002c5'
DESIGNS=ROOT/'assets/powers/identity'
P={'ink':'#111b24','floor':'#1b2d39','dark':'#253944','steel':'#617880','silver':'#afc4c5','paper':'#e7e5ca','white':'#fff3d1','brass':'#b88e50','gold':'#f0c572','red':'#bd5b3c','hot':'#f29558','sea':'#2f6969','mint':'#80b7a5','ice':'#c5e7d6','blue':'#37627b'}
FAMILIES=['momentum_bank','predator_line','crash_guard','crosscut']
HEADINGS={'e':(1,0),'se':(.707,.707),'s':(0,1),'sw':(-.707,.707),'w':(-1,0),'nw':(-.707,-.707),'n':(0,-1),'ne':(.707,-.707)}
BLADE_SOURCE=ROOT/'assets/source-art/starter_blade_accents_002b1.aseprite'
BLADES,BLADE_META=read_ase(BLADE_SOURCE)
PARTS={name:Image.open(ROOT/path).convert('RGBA') for name,path in {
 'ratchet':'assets/top/parts/ratchets/mid.png','flat':'assets/top/parts/bits/flat.png',
 'needle':'assets/top/parts/bits/needle.png','rubber':'assets/top/parts/bits/rubber.png'}.items()}

def rgba(c):return (*bytes.fromhex(P.get(c,c).lstrip('#')),255)
def blank(size):return Image.new('RGBA',size)
def line(im,p,c,w=1):ImageDraw.Draw(im).line([(round(x),round(y)) for x,y in p],fill=rgba(c),width=w)
def poly(im,p,c):ImageDraw.Draw(im).polygon([(round(x),round(y)) for x,y in p],fill=rgba(c))
def oval(im,xy,c):ImageDraw.Draw(im).ellipse(tuple(round(v) for v in xy),fill=rgba(c))
def dot(im,x,y,c):ImageDraw.Draw(im).point((round(x),round(y)),fill=rgba(c))
def card_layers():
 im=[blank((64,64)) for _ in range(5)]
 # Quiet card edge and real floor scratches; no box, machine or pedestal.
 poly(im[0],[(2,2),(61,2),(61,61),(2,61)],'ink')
 line(im[0],[(4,15),(4,5),(16,5)],'dark')
 line(im[0],[(48,59),(59,59),(59,48)],'dark')
 return im

def top(im,kind,cx,cy,pose=0):
 # Exact accepted native geometry and colours: no resized/recoloured rotor.
 offset=(round(cx-24),round(cy-26))
 bit={'vane':'rubber','breaker':'flat','bastion':'needle'}[kind]
 im.alpha_composite(PARTS[bit],offset)
 im.alpha_composite(PARTS['ratchet'],offset)
 index=BLADE_META['tags'][kind]['from']+pose%8
 im.alpha_composite(BLADES[index],offset)

def shadow(im,cx,cy,r=13):
 oval(im,(cx-r,cy+13,cx+r,cy+17),'floor')
 line(im,[(cx-r+3,cy+16),(cx+6,cy+17)],'dark')

def bank_card(p,ii):
 im=card_layers()
 x,y=[(41,25),(35,31),(33,33),(40,27),(44,23),(42,25)][p]
 if ii and p in [2,3]:x+=1;y-=1
 # A real top brakes across its own floor track and folds its wake underneath.
 line(im[1],[(7,53),(17,47),(24,41),(29,38)],'dark',2)
 if p in [1,2]:
  folds=[[(9,48),(15,47),(23,45),(31,45),(36,42)],[(14,53),(23,53),(31,50),(36,46)]]
  for q in folds:line(im[1],q,'brass' if p==1 else 'gold',2)
  line(im[4],[(30,45),(33,43),(36,42)],'paper',2)
  if ii:
   line(im[1],[(7,56),(18,56),(29,53),(33,48)],'silver')
   line(im[4],[(25,48),(30,48),(34,45)],'gold')
 elif p==3:
  line(im[1],[(9,52),(20,46),(31,39),(37,34)],'gold',2)
  line(im[1],[(8,58),(19,52),(29,46),(36,39)],'brass',2)
  line(im[4],[(28,36),(33,32)],'paper',2)
  if ii:line(im[1],[(4,50),(13,45),(22,38),(29,33)],'silver')
 elif p==4:
  line(im[1],[(11,48),(23,41),(33,33)],'steel',2)
  line(im[1],[(14,55),(23,50),(30,45)],'brass')
  line(im[4],[(34,30),(38,27)],'gold',2)
 elif p==5:
  line(im[1],[(16,47),(24,42)],'dark')
  line(im[1],[(24,43),(31,39)],'steel')
 else:line(im[1],[(9,50),(19,44),(28,38)],'steel')
 shadow(im[1],x,y)
 # The accepted broad round body is the foreground subject. Its intact native
 # blade, front shell and bit read as a top more clearly than the small Vane
 # fin in the first correction. No scaled body or invented hardware is added.
 top(im[3],'bastion',x,y,[0,2,3,5,6,7][p])
 # Small rim flick, attached to the turning blade rather than a separate coil.
 if p==2:line(im[4],[(x-12,y+4),(x-10,y+6)],'gold',2)
 return im

def predator_card(p,ii):
 im=card_layers()
 hunter=[(17,41),(21,38),(26,34),(32,29),(35,27),(24,36)][p]
 quarry=[(47,19),(48,18),(48,18),(49,17),(50,17),(49,19)][p]
 if ii and p in [2,3,4]:hunter=(hunter[0]+2,hunter[1]-1)
 # One continuous physical pursuit direction; the two real tops are the story.
 line(im[1],[(4,59),(12,54),(20,48),(29,41),(38,33)],'dark',2)
 if p>=1:
  line(im[1],[(6,56),(12,52),(18,48)],'red',2)
  line(im[1],[(23,45),(28,40),(33,37)],'brass')
 if ii:
  line(im[1],[(3,61),(11,58),(18,53)],'steel')
  line(im[1],[(23,49),(29,45),(33,42)],'red')
 shadow(im[1],*quarry,11);top(im[2],'bastion',*quarry,[2,3,4,5,6,7][p])
 shadow(im[1],*hunter,13);top(im[3],'breaker',*hunter,[0,1,3,4,6,7][p])
 if p in [3,4]:
  # Small physical blade contact. No teeth, rails, bracket or HUD-like marker.
  contact=(40,25)
  line(im[4],[(contact[0]-3,contact[1]+2),contact,(contact[0]+3,contact[1]-1)],'gold',2)
  dot(im[4],40,24,'white');dot(im[4],42,26,'paper')
  if ii:line(im[4],[(38,29),(41,27)],'hot',2)
 return im

def guard_card(p,ii):
 im=card_layers()
 own=[(25,34),(25,34),(23,35),(21,37),(23,36),(25,35)][p]
 rival=[(53,18),(49,21),(44,25),(46,22),(52,16),(54,15)][p]
 if ii and p in [2,3]:own=(own[0]+2,own[1]-1)
 if ii and p in [3,4]:rival=(rival[0]+1,rival[1]-2)
 # The defender accepts a small displacement while the incoming top deflects.
 line(im[1],[(47,45),(41,42),(36,39)],'dark')
 if p>=2:
  line(im[1],[(15,51),(18,52),(23,51),(27,49)],'steel',2)
  line(im[1],[(17,56),(24,54),(30,51)],'dark',2)
  if ii:line(im[1],[(12,53),(17,55),(23,54)],'silver')
 if p>=3:
  line(im[1],[(41,38),(48,33),(55,27)],'red')
 shadow(im[1],*rival,10);top(im[2],'breaker',*rival,[0,2,3,4,6,7][p])
 shadow(im[1],*own,15);top(im[3],'bastion',*own,[0,1,2,3,5,7][p])
 if p in [1,2,3]:
  # The pressure hugs the genuine curved blade edge, not a detached device.
  q=[(35,28),(37,30),(37,33),(35,35)] if p==2 else [(38,27),(40,29),(40,31)]
  line(im[4],q,'paper' if p==2 else 'silver',2)
  if p==2:
   line(im[4],[(37,29),(40,26)],'gold',2)
   dot(im[4],38,32,'white')
  if ii:line(im[4],[(32,32),(34,35),(33,37)],'steel',2)
 return im

def crosscut_card(p,ii):
 im=card_layers()
 own=[(18,19),(22,23),(29,28),(36,34),(45,40),(47,42)][p]
 rival=[(47,37),(46,36),(44,34),(45,28),(49,22),(50,21)][p]
 if ii and p in [3,4]:
  own=(own[0]+1,own[1]+1);rival=(rival[0]+1,rival[1]-2)
 # Tangential contact peels the physical bodies into two unequal exits.
 line(im[1],[(6,19),(14,24),(22,31)],'dark',2)
 if p>=2:
  line(im[1],[(27,38),(35,43),(44,48)],'sea',2)
  line(im[1],[(33,38),(40,33),(49,29)],'steel')
  if ii:line(im[1],[(27,43),(35,48),(41,51)],'mint')
 shadow(im[1],*rival,12);top(im[2],'bastion',*rival,[0,2,3,4,6,7][p])
 shadow(im[1],*own,13);top(im[3],'vane',*own,[0,1,3,4,6,7][p])
 if p in [2,3]:
  line(im[4],[(31,29),(35,32),(38,34)],'ice',2)
  line(im[4],[(34,34),(39,38),(44,40)],'mint',2)
  if ii:line(im[4],[(32,36),(37,40),(41,42)],'silver')
  dot(im[4],35,31,'white')
 return im

CARD={'momentum_bank':bank_card,'predator_line':predator_card,'crash_guard':guard_card,'crosscut':crosscut_card}
# Six deliberate key poses. Each is a true two-key hold, not twelve weak poses.
POSE_MS={'momentum_bank':[180,190,320,80,130,280],'predator_line':[200,170,140,100,160,290],'crash_guard':[250,130,120,180,200,280],'crosscut':[210,150,90,100,140,290]}
STATIC={'momentum_bank':4,'predator_line':6,'crash_guard':4,'crosscut':4}

def tiny_top(im,cx,cy,r=4,accent='steel'):
 # Individually authored at 16px: stepped blade, front shell, visible bit.
 poly(im,[(cx-r,cy-1),(cx-r+1,cy-2),(cx-1,cy-2),(cx+1,cy-3),(cx+r-1,cy-2),(cx+r,cy),(cx+r-1,cy+1),(cx+1,cy+2),(cx-r+1,cy+1)],'steel')
 oval(im,(cx-2,cy-1,cx+2,cy+1),'ink')
 line(im,[(cx-r+1,cy-1),(cx-r+2,cy-2),(cx-1,cy-2)],'silver')
 dot(im,cx+r-1,cy-1,'paper');dot(im,cx-r,cy,accent)
 line(im,[(cx-r+1,cy+1),(cx-1,cy+2),(cx+1,cy+2),(cx+r-1,cy+1)],accent)
 dot(im,cx,cy,'paper');line(im,[(cx,cy+3),(cx,cy+4)],'steel')

def icon(family,ii):
 im=[blank((16,16)) for _ in range(2)]
 if family=='momentum_bank':
  tiny_top(im[0],10,5,4,'blue')
  line(im[1],[(1,12),(4,13),(8,12),(10,10)],'gold')
  line(im[1],[(3,9),(5,10),(8,10)],'brass')
  if ii:line(im[1],[(2,15),(6,15),(9,13)],'silver')
 elif family=='predator_line':
  tiny_top(im[0],12,3,3,'blue');tiny_top(im[0],4,10,4,'red')
  line(im[1],[(5,7),(7,6),(9,4)],'hot')
  if ii:line(im[1],[(7,10),(9,8),(11,7)],'brass')
 elif family=='crash_guard':
  tiny_top(im[0],12,4,3,'red');tiny_top(im[0],5,8,4,'blue')
  line(im[1],[(9,5),(9,7)],'paper');dot(im[1],10,6,'gold')
  line(im[1],[(2,14),(5,14),(7,12)],'steel')
  if ii:line(im[1],[(1,12),(3,13)],'silver')
 else:
  tiny_top(im[0],4,3,3,'mint');tiny_top(im[0],12,9,3,'blue')
  line(im[1],[(4,7),(7,9),(10,13),(13,14)],'ice')
  if ii:line(im[1],[(3,10),(6,12),(8,14)],'steel')
 return im

FX_TAGS={'momentum_bank':['bank_load','bank_stored','bank_release'],'predator_line':['predator_pressure','predator_tracking'],'crash_guard':['damper_contact'],'crosscut':['shear_slice']}
FX_MS={'momentum_bank':[80,60,55,80,90,100,140,180],'predator_line':[55,50,55,70,85,110,135,180],'crash_guard':[60,45,55,80,100,130,160,190],'crosscut':[50,35,45,60,90,115,155,200]}

def fx(family,f,ii,kind,heading):
 im=[blank((96,80)) for _ in range(4)]
 vx,vy=HEADINGS[heading];sx,sy=-vy,vx
 def q(forward,side=0,up=0):return (48+vx*forward+sx*side,48+vy*forward+sy*side+up)
 def stroke(which,points,c,w=1,up=0):line(im[which],[q(a,b,up) for a,b in points],c,w)
 if family=='momentum_bank':
  if kind=='bank_stored':
   # Stage zero is empty. Every positive earned stage has a visible compact
   # floor fold outside the rear heel, rather than a nearly transparent cel
   # beneath the actor/team ring. Higher charge tightens the same physical
   # skid; it never grows into a permanent aura or detached spring/widget.
   if f>0:
    # Upright native bodies rise above the floor pivot. A screen-south rear
    # skid therefore needs a longer seam than a screen-north one; otherwise
    # the real blade hides every bright pixel. These per-heading placements
    # were checked under the intact actual starter bodies in all eight poses.
    rear={'e':24,'se':26,'s':30,'sw':26,'w':27,'nw':24,'n':23,'ne':24}[heading]
    reach=rear-min(f-1,5)*0.5
    stroke(0,[(-2,1),(-9,4),(-reach+4,6),(-reach-3,7)],'steel')
    stroke(1,[(-reach-3,7),(-reach,10),(-reach+7,10),(-reach+10,7)],'gold',2)
    stroke(2,[(-reach,10),(-reach+3,11)],'paper',2)
    stroke(1,[(-reach+7,10),(-reach+10,7)],'brass')
    if ii:
     stroke(2,[(-reach-3,13),(-reach+1,14),(-reach+7,13),(-reach+10,10)],'silver',2)
    elif f>=4:
     stroke(2,[(-reach+1,13),(-reach+5,13)],'brass')
  elif kind=='bank_load':
   if f<=5:
    reach=[27,24,21,18,15,13,12,10][f]
    stroke(0,[(-reach,-6),(-reach+9,-4),(-4,-2)],'dark')
    stroke(1,[(-reach,6),(-reach+5,8),(-9,6),(-3,2)],'gold' if f in [2,3] else 'brass',2 if f in [2,3] else 1)
    if ii:stroke(2,[(-reach-2,1),(-reach+4,3),(-6,2)],'steel')
   else:stroke(0,[(-15,7),(-8,5)],'dark')
  else:
   # Tight heel fold straightens into the actual launch vector and erodes.
   length=[12,16,22,29,34,38,40,43][f]
   if f<6:
    stroke(1,[(-length,6),(-length+8,5),(-8,2),(4,0)],'paper' if f<3 else 'brass',2 if f<4 else 1)
    stroke(2,[(-length+4,-5),(-11,-3),(2,-1)],'gold' if f<4 else 'steel')
    if ii:stroke(0,[(-length-2,10),(-length+7,8),(-14,5)],'silver' if f<3 else 'dark')
   else:
    stroke(0,[(-length+4,6),(-length+10,5)],'dark')
    stroke(0,[(-19,3),(-13,2)],'steel' if f==6 else 'dark')
 elif family=='predator_line':
  if kind=='predator_tracking':
   # Three stack stages are genuine floor pursuit strokes behind the hunter.
   reach=9+f
   stroke(0,[(-reach,3),(-6,1),(-2,0)],'dark')
   stroke(1,[(-reach,5),(-reach+4,4),(-5,2)],'red')
   if f>=3:stroke(2,[(-reach-5,-2),(-reach,-1),(-8,0)],'brass')
   if ii and f>=5:stroke(1,[(-reach-3,8),(-reach+1,7)],'steel')
  else:
   # A local rim scrape at accepted repeated contact, not a comb or target box.
   if f<6:
    reach=[9,12,15,17,19,21,22,23][f]
    stroke(1,[(reach-7,-3),(reach-3,-2),(reach,0)],'hot' if f<4 else 'red',2 if f<3 else 1,up=-12)
    if f in [1,2,3]:stroke(3,[(reach-2,1),(reach+2,2)],'paper',up=-12)
    if ii:stroke(2,[(reach-9,4),(reach-4,4)],'brass',up=-10)
   stroke(0,[(7,5),(13,4)],'dark')
 elif family=='crash_guard':
  # Pressure enters the real blade rim, yields inward, and clears on rebound.
  r=[16,14,12,13,16,19,22,24][f]
  if f<=5:
   stroke(1,[(r-3,-5),(r,-3),(r+1,0),(r,3),(r-3,5)],'silver' if f<3 else 'steel',2 if f in [1,2] else 1,up=-13)
   if f in [1,2,3]:stroke(3,[(r+1,0),(r+4,1)],'paper',up=-13)
   if ii and f<=3:stroke(2,[(r-7,-3),(r-6,0),(r-7,3)],'blue',2,up=-11)
  if f>=2:
   stroke(0,[(-8,3),(-12,4),(-15,4)],'steel' if f<5 else 'dark')
   if ii:stroke(0,[(-7,7),(-11,8)],'dark')
 else:
  reach=[5,9,13,19,25,30,35,39][f]
  if f<6:
   stroke(2,[(-3,2),(4,1),(reach,-2),(reach+4,-4)],'ice' if f<3 else 'mint',2 if f<3 else 1)
   stroke(0,[(0,6),(reach-6,5),(reach+1,2)],'sea')
   if ii:stroke(1,[(2,9),(reach-5,8),(reach,5)],'silver')
  if f>=2:stroke(0,[(8,8),(13,9),(17,8)],'steel' if f<5 else 'dark')
 return im

GRAMMAR={
'momentum_bank':{'silhouette':'accepted broad round top in the foreground above a folded braking skid at its own heel','motion':'braking skid folds, a compact positive-charge floor fold holds, directed launch unfolds it','location':'actual top heel and floor; release follows its real movement vector','persistence':'empty stage zero; visible earned charge stages one through seven plus existing store/release events','palette':'accepted blue Bastion steel body, restrained brass and pale floor wakes','feature':'one recognizable top and compressed physical floor travel; no detached cassette'},
'predator_line':{'silhouette':'two actual tops in diagonal pursuit, cropped near hunter and far rival','motion':'one quarry leads, hunter closes and makes a short rim scrape','location':'hunter floor footprint and the actual target direction','persistence':'only actual hunt stacks/target and accepted repeated contact','palette':'accepted vermilion Breaker and blue Bastion against floor shadows','feature':'pursuit is carried by two visible tops; no comb, teeth or hunter appliance'},
'crash_guard':{'silhouette':'round actual defender top receives an angular incoming top','motion':'contact bends at the blade, defender yields slightly, attacker redirects','location':'genuine incoming blade rim and local recoil skid','persistence':'existing contact event only','palette':'accepted blue steel defender against red attacker and short silver rim pressure','feature':'absorption and redirected displacement without piston, box or shield device'},
'crosscut':{'silhouette':'two real top bodies pass tangentially into unequal exit lanes','motion':'descending approach, offset glancing contact, separated floor skids','location':'actual paid lateral displacement and contact floor','persistence':'brief existing glancing event with eroding follow-through','palette':'accepted green Vane and blue Bastion with pale sea-green tangential scrape','feature':'physical tops and one offset shear; no added blade gadget or symmetric X'}}
EVENTS={'momentum_bank':{'momentum_store':'bank_load','momentum_release':'bank_release'},'predator_line':{'predator_lock':'predator_pressure'},'crash_guard':{'crash_guard':'damper_contact'},'crosscut':{'crosscut':'shear_slice'}}

def preview(family,review):
 if not review:return
 review.mkdir(parents=True,exist_ok=True)
 for group,cols in [('cards',12),('icons',2),('fx',8)]:
  flat,meta=read_ase(SOURCE/f'{family}_{group}.aseprite');w,h=meta['cell']
  im=Image.new('RGBA',(cols*w,math.ceil(len(flat)/cols)*h),rgba('ink'))
  for i,cel in enumerate(flat):im.alpha_composite(cel,(i%cols*w,i//cols*h))
  im.save(review/f'{family}_{group}.png');ImageOps.grayscale(im).save(review/f'{family}_{group}_gray.png')
  if group=='cards':
   for ii in [False,True]:
    cel=flat[(12 if ii else 0)+STATIC[family]]
    cel.save(review/f'{family}{"_ii" if ii else ""}_64.png')
    cel.resize((512,512),Image.Resampling.NEAREST).save(review/f'{family}{"_ii" if ii else ""}_nearest.png')

def make(family,revise,review):
 paths=[SOURCE/f'{family}_{group}.aseprite' for group in ['cards','icons','fx']]
 if not revise and any(x.exists() for x in paths):raise RuntimeError('Refusing artist overwrite; --revise is only for this explicit correction pass')
 cards=[];tags=[];times=[];icons=[]
 for ii in [False,True]:
  start=len(cards)
  for p in range(6):
   cel=CARD[family](p,ii)
   cards.extend([[x.copy() for x in cel],[x.copy() for x in cel]])
   duration=POSE_MS[family][p];times.extend([duration//2,duration-duration//2])
  tags.append((family+('_ii' if ii else ''),start,len(cards)-1));icons.append(icon(family,ii))
 write_ase(paths[0],cards,['01 quiet floor background','02 actual floor travel and shadows','03 accepted rival native top body','04 accepted owner native top body','05 blade contact and physical follow-through'],tags,times,(32,32),note=f'Human correction v2 {family}: six strong physical top poses with double holds; exact accepted native body pixels; no gadgets, image resampling or recolouring',palette=P)
 write_ase(paths[1],icons,['01 independently drawn miniature top bodies','02 physical travel and contact at 16px'],[(family,0,0),(family+'_ii',1,1)],[160,160],(8,8),note=f'{family} dedicated 16px tops/contact icon, separately drawn; no resized card or hardware symbol',palette=P)
 frames=[];ftags=[];durations=[]
 for kind in FX_TAGS[family]:
  for ii in [False,True]:
   for heading in HEADINGS:
    start=len(frames)
    frames.extend(fx(family,f,ii,kind,heading) for f in range(8))
    ftags.append((kind+('_ii' if ii else '')+'_'+heading,start,len(frames)-1));durations.extend(FX_MS[family])
 write_ase(paths[2],frames,['01 grounded floor skid and erosion','02 real contact and compressed wake','03 directed physical follow-through','04 small attached rim glints'],ftags,durations,(48,48),note=f'Human correction v2 {family}: no replacement top or detached gadget; bounded physical skid/contact cels, eight native headings, original event routing',palette=P)
 design={'family':family,'correction':'Human requested physical top restoration v2','grammar':GRAMMAR[family],'static_frames':{family:STATIC[family],family+'_ii':STATIC[family]},'event_tags':EVENTS[family],'notes':['Six strong card poses occupy twelve keyed frames through explicit two-key holds.','Card bodies copy exact accepted starter_blade_accents_002b1 native cels and the accepted bit/ratchet parts, without resizing or recolouring.','Rank II develops physical force and travel marks rather than adding a device.','Icons are separately authored recognizable miniature tops and travel/contact.','FX omit replacement bodies, gadgets and synthetic particles; real gameplay tops remain visible.','All eight projected headings have eight authored native keys. Existing gameplay fields/events remain authoritative.']}
 if family=='momentum_bank':
  design['active_tags']={'stored':'bank_stored'}
  design['notes'].extend(['The accepted broad round Bastion body replaces the smaller angular Vane as the foreground braking subject, at its original native pixel scale.','Stored key zero is empty. Positive keys one through seven retain a short bright folded floor skid behind the actual heel even at low earned charge; greater charge tightens it. Rank II adds one second fold. No free-running charge animation.'])
 if family=='predator_line':design['active_tags']={'tracking':'predator_tracking'};design['notes'].append('Tracking keys are actual-stack floor pursuit strokes. Render at the hunter floor origin facing its one real target, not the former floating 70% gap position.')
 if family=='crash_guard':design['notes'].append('Historical internal tag damper_contact now means a short physical blade absorption/redirect response, with no piston or device pixels.')
 (DESIGNS/f'{family}_design.json').write_text(json.dumps(design,indent=2)+'\n')
 preview(family,review)
 print(f'{family}: 6 strong poses/rank held as 12 keys; exact accepted native top geometry; 2 independent icons; {len(frames)} bounded directional FX keys')

def main():
 p=argparse.ArgumentParser();p.add_argument('--family',choices=FAMILIES,action='append');p.add_argument('--revise',action='store_true');p.add_argument('--review',type=Path);args=p.parse_args()
 for family in args.family or FAMILIES:make(family,args.revise,args.review)
if __name__=='__main__':main()
