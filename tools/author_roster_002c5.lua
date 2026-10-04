-- Initial construction inside native Aseprite. Refuses to replace edited masters.
-- The saved named-layer sources become the production authority thereafter.
local root=app.params.root;assert(root,'root parameter required')
local palette={'172b38','334954','637773','b9bb91','f6e5ae','fff3d1','a34335','ef713b','ffc05a','247b79','52c8b5','c8f5d4','3d6e99','75b9e1'}
local ink={};for i,v in ipairs(palette) do ink[i]=Color{r=tonumber(v:sub(1,2),16),g=tonumber(v:sub(3,4),16),b=tonumber(v:sub(5,6),16)}.rgbaPixel end
local function px(im,x,y,c) x=math.floor(x+.5);y=math.floor(y+.5);if x>=0 and x<im.width and y>=0 and y<im.height then im:drawPixel(x,y,ink[c] or 0) end end
local function line(im,x,y,xx,yy,c,width)
 local n=math.max(math.abs(xx-x),math.abs(yy-y));for k=0,n do local t=n==0 and 0 or k/n;for j=0,(width or 1)-1 do px(im,x+(xx-x)*t,y+(yy-y)*t+j,c) end end
end
local function arc(im,x,y,r,start,len,c,width,squash)
 local steps=math.max(5,math.ceil(r*math.abs(len)));local previous=nil
 for i=0,steps do local a=start+len*i/steps;local q={x+math.cos(a)*r,y+math.sin(a)*r*(squash or .5)};if previous then line(im,previous[1],previous[2],q[1],q[2],c,width) end;previous=q end
end
local function rotor(im,x,y,r,phase,accent)
 for k=0,7 do local a=phase+k*math.pi/4;arc(im,x,y+3,r,a,.57,1,5,.6);arc(im,x,y,r,a,.57,3,4,.6);arc(im,x,y-1,r,a+.04,.43,accent or 4,1,.6) end
 arc(im,x,y,5,0,math.pi*2,1,2,.6);line(im,x-3,y-1,x+2,y-1,6,1)
 line(im,x,y+r*.6+2,x,y+r*.6+8,2,2);px(im,x,y+r*.6+8,6)
end
local function shard(im,x,y,c)
 line(im,x,y,x+4,y-3,c,2);line(im,x+1,y+1,x+4,y-2,7,1)
end
local function socket(im,x,y,c)
 line(im,x-4,y-2,x-1,y-3,c,1);line(im,x+1,y-3,x+4,y-2,c,1);line(im,x-4,y-2,x-4,y+2,10,1);line(im,x+4,y-2,x+4,y+2,10,1);line(im,x-3,y+3,x+3,y+3,c,1)
end
local function teeth(im,x,y,r,f,c)
 for k=0,5 do local a=k*math.pi/3+f*.18;local ax=x+math.cos(a)*r;local ay=y+math.sin(a)*r*.5;line(im,ax,ay,ax+math.cos(a)*4,ay+math.sin(a)*2,c,2) end
end
local function author(name,w,h,tags,count,durations,pivot,layers,paint)
 local path=root..'/assets/source-art/'..name..'_002c5.aseprite';assert(not app.fs.isFile(path),'Refusing artist overwrite '..path)
 local s=Sprite(w,h,ColorMode.RGB);local ls={s.layers[1]};for i=2,#layers do ls[i]=s:newLayer() end;for i,n in ipairs(layers) do ls[i].name=n end
 local pal=Palette(#palette+1);pal:setColor(0,Color{r=0,g=0,b=0,a=0});for i,v in ipairs(ink) do pal:setColor(i,Color(v)) end;s:setPalette(pal)
 local frame=0;for _,tag in ipairs(tags) do local first=frame+1;for f=1,count do frame=frame+1;if frame>1 then s:newEmptyFrame() end;s.frames[frame].duration=durations[f];local ims={};for i=1,#layers do ims[i]=Image(w,h,ColorMode.RGB) end;paint(ims,tag,f);for i=1,#layers do s:newCel(ls[i],frame,ims[i],Point(0,0)) end end;local t=s:newTag(first,frame);t.name=tag end
 for i,t in ipairs(s.tags) do t.toFrame=s.frames[i*count] end
 local slice=s:newSlice(Rectangle(0,0,w,h));slice.name='contact_pivot';slice.pivot=Point(pivot[1],pivot[2]);s.data='Task002C.5 authored integer key poses; nearest-neighbour; fixed2:1 projection; editable normal RGBA layers.';s:saveAs(path);s:close()
end
local effects={'comet_charge','comet_flight','comet_impact','comet_recovery','overcap','heat_extreme','clutch_danger','clutch_recover','gear1','gear2','terminal_surge','flow_state','orbit_drift','crash_guard','momentum_store','momentum_release','predator_lock','crosscut','ghost_preview','ghost_latch'}
author('roster_fx',96,80,effects,6,{.06,.045,.055,.08,.10,.14},{48,48},{'01 floor contact and silhouette','02 mechanical structure','03 active energy','04 key flash and fragments'},function(im,t,f)
 local phase=f*.30
 if t=='comet_charge' or t=='comet_flight' then
  -- Disconnected rotor rails surround an empty readable machine centre.
  local r=t=='comet_charge' and ({27,25,23,22,23,24})[f] or 24
  for k=0,3 do local a=phase+k*math.pi/2;arc(im[2],48,34,r,a,.56,3,2);arc(im[3],48,34,r-2,a+.1,.36,9,1) end
  if t=='comet_flight' then shard(im[4],23-f%3*2,40,9);shard(im[3],68+f%3*2,27,5) end
 elseif t=='comet_impact' then
  local r=({5,11,20,27,33,39})[f];if f<3 then line(im[4],48-r,34,48+r,34,6,2);line(im[4],48,29-f*2,48,41+f*2,6,1) end
  for k=0,5 do local a=k*math.pi/3+.21;shard(im[4],48+math.cos(a)*r,34+math.sin(a)*r*.65,f<4 and 9 or 7) end
 elseif t=='comet_recovery' then
  for k=0,2 do local x=23+k*19+(k-1)*f;line(im[1],x,50+k%2*3,x+8-f,49+k%2*3,3,1);if f<4 then shard(im[4],x,47,8) end end
 elseif t=='overcap' or t=='heat_extreme' then
  for k=0,5 do local a=phase+k*math.pi/3;arc(im[2],48,34,25,a,.31,7,2);arc(im[3],48,34,26,a+.06,.18,9,1) end
  if t=='heat_extreme' then for k=0,3 do shard(im[4],19+k*18+(f%3-1)*2,24+(k%2)*23,8) end;line(im[3],24,35,19,29-f%3,8,2);line(im[3],72,31,77,35+f%3,8,2) end
 elseif t=='clutch_danger' or t=='clutch_recover' then
  local r=t=='clutch_danger' and 21 or ({27,23,20,18,21,24})[f]
  for k=0,3 do local a=k*math.pi/2;arc(im[2],48,48,r,a+.22,.66,3,2);arc(im[3],48,48,r-2,a+.3,.42,t=='clutch_recover' and 12 or 9,1) end
  line(im[1],31,53,38,55,7,1);line(im[1],58,55,65,53,7,1)
  if t=='clutch_recover' and f==3 then socket(im[4],48,48,12) end
 elseif t=='gear1' or t=='gear2' or t=='terminal_surge' or t=='flow_state' then
  local c=t=='terminal_surge' and 9 or (t=='flow_state' and 12 or 14)
  for k=0,(t=='gear1' and 1 or 3) do local a=k*math.pi/2+phase;arc(im[2],48,34,24,a,.4,13,1);arc(im[3],48,34,25,a,.23,c,1) end
  if t=='terminal_surge' then shard(im[4],20-f,39,9);shard(im[4],69+f,25,9) end
 elseif t=='orbit_drift' then
  -- Twin segmented contact scuffs: the top and actual floor pivot stay clear.
  for k=0,2 do arc(im[1],45,48,20+k*4,.15+phase*.12,.50,3,1);arc(im[3],45,48,20+k*4,.15+phase*.12,.28,11,1) end
  shard(im[4],25-f%2,54,9);shard(im[4],64+f%3,45,9)
 elseif t=='crash_guard' then
  for k=0,3 do local a=k*math.pi/2+.15;arc(im[2],48,40,27,a,.57,3,3);arc(im[3],48,40,28,a+.12,.22,9,1) end
 elseif t=='momentum_store' or t=='momentum_release' then
  for k=0,4 do local x=32+k*7;line(im[2],x,53,x+4,53,2,2);if t=='momentum_release' or k<f-1 then line(im[3],x,52,x+4,52,9,1) end end
  if t=='momentum_release' and f<4 then for k=0,2 do shard(im[4],24+k*20,32+k%2*14,9) end end
 elseif t=='predator_lock' then
  local d=({8,5,2,0,1,2})[f];line(im[3],22-d,33,28-d,30,8,1);line(im[3],22-d,33,27-d,37,8,1);line(im[3],74+d,33,68+d,30,8,1);line(im[3],74+d,33,69+d,37,8,1)
 elseif t=='crosscut' then
  local r=({6,13,19,23,27,30})[f];line(im[3],48-r,48+r*.5,48+r,48-r*.5,11,1);line(im[4],48-r,48-r*.5,48+r,48+r*.5,12,1);if f<3 then socket(im[4],48,48,12) end
 elseif t=='ghost_preview' then
  socket(im[2],48,48,11);if f==2 or f==5 then line(im[3],44,43,52,43,12,1);line(im[3],44,52,52,52,12,1) end
 elseif t=='ghost_latch' then
  local d=({12,7,0,0,2,5})[f];socket(im[2],48-d,48,11);socket(im[3],48+d,48,12);if f==3 then line(im[4],32,48,64,48,12,2) end
 end
end)
local ids={'clutch','high_gear','orbit_drive','crash_guard','momentum_bank','predator_line','crosscut','clutch_ii','high_gear_ii','orbit_drive_ii','crash_guard_ii','momentum_bank_ii','predator_line_ii','crosscut_ii','terminal_velocity','flow_state'}
author('roster_cards',64,64,ids,6,{.11,.09,.075,.075,.10,.17},{32,32},{'01 industrial backplate','02 ground braces and machine depth','03 editable rotor and mechanism','04 route force and stress','05 confirmation glints and fragments'},function(im,t,f)
 local base=t:gsub('_ii$','');local deep=t:sub(-3)=='_ii';local c=(base=='clutch' or base=='crash_guard' or base=='momentum_bank') and 9 or 14
 -- A framed industrial backplate shared with the existing visual language.
 for y=4,59 do for x=4,59 do if x==4 or x==59 or y==4 or y==59 then px(im[1],x,y,2) elseif y>51 then px(im[1],x,y,1) end end end
 for x=8,56,8 do line(im[1],x,56,x+2,56,3,1) end
 local phase=f*.21;rotor(im[3],32,28,15,phase,c)
 if base=='clutch' then
  for k=0,3 do arc(im[4],32,37,22,k*math.pi/2+.14,.65,f<3 and 7 or 11,3) end;line(im[2],16,45,24,47,3,2);line(im[2],40,47,48,45,3,2);if deep then socket(im[5],32,47,12) end
 elseif base=='high_gear' or base=='terminal_velocity' or base=='flow_state' then
  local col=base=='terminal_velocity' and 9 or (base=='flow_state' and 12 or 14)
  for k=0,2 do line(im[4],10+k*6-f%2,37+k*3,19+k*6,33+k*3,col,2) end
  teeth(im[4],32,28,18,f,col);if deep or base=='terminal_velocity' then teeth(im[5],32,28,23,f,9) end;if base=='flow_state' then arc(im[4],32,37,24,.3,4.8,11,2) end
 elseif base=='orbit_drive' then
  for k=0,2 do arc(im[4],32,36,23+k,phase,4.9,11,1) end;for k=0,1 do shard(im[5],12+k*34,47-k*9,9) end;if deep then arc(im[5],32,36,28,phase+.8,3.3,12,1) end
 elseif base=='crash_guard' then
  for k=0,5 do arc(im[2],32,32,23,k*math.pi/3+.10,.67,3,4);arc(im[4],32,32,24,k*math.pi/3+f*.03,.21,9,1) end;if deep then shard(im[5],50,19+f,9) end
 elseif base=='momentum_bank' then
  for k=0,4 do line(im[2],17+k*6,46,21+k*6,46,3,3);if k<f then line(im[4],17+k*6,45,21+k*6,45,9,2) end end;line(im[4],12,41,9,38,9,2);line(im[4],52,41,55,38,9,2);if deep then arc(im[5],32,28,21,phase,.9,9,2) end
 elseif base=='predator_line' then
  rotor(im[2],46,16,8,-phase,8);line(im[4],35,29,44,22,8,2);line(im[5],13,39,25,34,9,1);for k=0,(deep and 2 or 1) do socket(im[4],18+k*8,44-k*4,8) end
 elseif base=='crosscut' then
  line(im[4],9,49,53,18,11,2);line(im[4],10,18,53,49,14,2);socket(im[5],32,33,12);if deep then for k=0,1 do shard(im[5],16+k*32,27+k*15,12) end end
 end
 if f==3 or f==4 then arc(im[5],32,27,15,phase,.7,6,1) end
end)
author('roster_icons',16,16,ids,1,{.12},{8,8},{'01 steel mechanism','02 state and motion'},function(im,t,f)
 local b=t:gsub('_ii$','');local deep=t:sub(-3)=='_ii';for k=0,3 do arc(im[1],8,7,5,k*math.pi/2,.9,3,2,.7) end
 if b=='clutch' then line(im[2],3,12,6,10,9,2);line(im[2],10,10,13,12,9,2)
 elseif b=='high_gear' or b=='terminal_velocity' or b=='flow_state' then line(im[2],1,12,6,9,14,2);line(im[2],1,8,4,6,14,1);if b=='terminal_velocity' then line(im[2],12,2,15,0,9,2) end
 elseif b=='orbit_drive' then arc(im[2],8,8,7,.2,4.6,11,1,.7)
 elseif b=='crash_guard' then line(im[2],1,5,1,11,9,2);line(im[2],13,5,13,11,9,2)
 elseif b=='momentum_bank' then for k=0,2 do line(im[2],3+k*4,12,5+k*4,12,9,2) end
 elseif b=='predator_line' then line(im[2],1,3,5,6,8,1);line(im[2],12,10,15,13,8,1)
 elseif b=='crosscut' then line(im[2],2,2,13,13,11,1);line(im[2],2,13,13,2,14,1) end
 if deep then line(im[2],6,0,10,0,6,1) end
end)
print('Native002C.5 authored20FX tags +16card/iconrows; sources protected from overwrite.')
