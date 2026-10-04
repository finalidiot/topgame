-- Run INSIDE Aseprite: -b --script-param root=<repository> --script this-file.
-- Initial production key art only. Refuses to overwrite edited masters.
-- Pixel clusters below are deliberately drawn motifs, not particle simulation.
-- Edit cels/timing in Aseprite thereafter; export_signature_art.py never authors.
local root=app.params.root
assert(root,'root parameter required')
local palette={'.','172b38','334954','637773','b9bb91','f6e5ae','fff3d1','a34335','ef713b','ffc05a','247b79','52c8b5','c8f5d4'}
local ink={}
for i=2,#palette do ink[string.sub('0123456789AB',i-1,i-1)]=Color{r=tonumber(palette[i]:sub(1,2),16),g=tonumber(palette[i]:sub(3,4),16),b=tonumber(palette[i]:sub(5,6),16)}.rgbaPixel end
-- Indexed symbol language: 0 dark, 1 iron, 2 grey, 3 brass, 4 cream,
-- 5 white, 6 ember, 7 hot orange, 8 yellow, 9 teal, A mint, B ice.
local motifs={
 tooth={'...33....','..3443...','.344443..','034334430','012222210','..01110..'},
 jaw={'..222222...','.23444432..','02311112320','021....0120','021....0120','012....210.','..1....1...'},
 vent={'.....7......','....787.....','..67887.....','.6788876....','067788887...','..667887....','....677.....'},
 tear={'........8......','......887......','....58776......','..558877.......','5887776........','..87766........','....66.........'},
 latch={'...AA...','..ABBA..','.AB99BA.','AB9..9BA','AB9..9BA','.AB99BA.','..ABBA..','...AA...'},
 socket={'..9999..','.9AAAA9.','9AB..BA9','9A....A9','.9AAAA9.','..9999..'},
 arrow={'.....B...','....BB...','...BA9...','..BA9....','.BA9.....','BA9......','.9.......'},
 shard={'...5..','..548.','.5487.','54876.','.876..','..6...'},
 recoil={'..2......','.231.....','12341....','.12341...','..01231..','....012..'},
 crown={'5...5...5','83.383.38','833333338','.8333338.','..66666..'},
 catch={'....B....','...B5B...','..BA5AB..','.BAA5AAB.','B5555555B','.BAA5AAB.','..BA5AB..','...B5B...','....B....'}
}
local function px(im,x,y,c) x=math.floor(x+.5);y=math.floor(y+.5);if x>=0 and x<96 and y>=0 and y<80 then im:drawPixel(x,y,ink[c] or 0) end end
local function stamp(im,name,x,y,flip)
 local rows=motifs[name];for yy,row in ipairs(rows) do for xx=1,#row do local c=row:sub(xx,xx);if c~='.' then px(im,x+(flip and #row-xx or xx-1),y+yy-1,c) end end end
end
local function line(im,x,y,xx,yy,c)
 local n=math.max(math.abs(xx-x),math.abs(yy-y));for i=0,n do local t=n==0 and 0 or i/n;px(im,x+(xx-x)*t,y+(yy-y)*t,c) end
end
local function diamond(im,r,y,c)
 line(im,48-r,y,48,y-r/2,c);line(im,48,y-r/2,48+r,y,c);line(im,48+r,y,48,y+r/2,c);line(im,48,y+r/2,48-r,y,c)
end
local function flash(im,f,large)
 -- Anticipation pin -> white cut -> fractured fan -> separated hot fragments.
 local lengths=large and {7,27,39,29,19,9} or {3,9,17,14,8,3}
 local r=lengths[f];local col=f<=2 and '5' or (f<=4 and '8' or '6')
 line(im,48-r,34+math.floor(r/3),48+r,34-math.floor(r/3),col)
 line(im,48-math.floor(r/3),34-r/2,48+math.floor(r/3),34+r/2,col)
 if f>=2 and f<=4 then stamp(im,'shard',48-r,25,true);stamp(im,'shard',48+r-5,37);stamp(im,'shard',43,34-r/2) end
end
local function author(family,tags,paint)
 local path=root..'/assets/source-art/'..family..'_fx_002c4.aseprite'
 assert(not app.fs.isFile(path),'Refusing to overwrite artist source: '..path)
 local s=Sprite(96,80,ColorMode.RGB)
 local layers={s.layers[1],s:newLayer(),s:newLayer(),s:newLayer()}
 for i,n in ipairs({'01 floor contact and silhouette','02 mechanical structure','03 active energy','04 key flash and fragments'}) do layers[i].name=n end
 local pal=Palette(#palette);pal:setColor(0,Color{r=0,g=0,b=0,a=0});for i=2,#palette do pal:setColor(i-1,Color(ink[string.sub('0123456789AB',i-1,i-1)])) end;s:setPalette(pal)
 local frame=0
 for _,name in ipairs(tags) do
  local first=frame+1
  for f=1,6 do
   frame=frame+1;if frame>1 then s:newEmptyFrame() end
   s.frames[frame].duration=({.06,.045,.055,.08,.10,.14})[f]
   local ims={Image(96,80,ColorMode.RGB),Image(96,80,ColorMode.RGB),Image(96,80,ColorMode.RGB),Image(96,80,ColorMode.RGB)}
   paint(ims,name,f)
   for i=1,4 do s:newCel(layers[i],frame,ims[i],Point(0,0)) end
  end
  local tag=s:newTag(first,frame);tag.name=name
 end
 -- Appending frames expands the active tag in Aseprite. Seal ranges last.
 for i,tag in ipairs(s.tags) do tag.toFrame=s.frames[i*6] end
 local slice=s:newSlice(Rectangle(0,0,96,80));slice.name='contact_pivot';slice.pivot=Point(48,48)
 s.data='002C.4 deliberate pixel-key poses. Fixed 2:1 floor; rotor at (48,34); contact (48,48). Six frames/tag: 60,45,55,80,100,140ms. No rotation or smoothing.'
 s:saveAs(path);s:close()
end
author('redline',{'rank1_active','rank2_active','runaway_low','runaway_high','breakneck_charge','breakneck_hit','breakneck_recovery'},function(im,t,f)
 if t=='breakneck_hit' then flash(im[4],f,true);if f>2 then stamp(im[2],'recoil',18-f,44);stamp(im[2],'recoil',72+f,20,true) end;return end
 if t=='breakneck_recovery' then
  stamp(im[2],'recoil',29-f*2,43+f);stamp(im[2],'recoil',59+f,48,true)
  if f<4 then stamp(im[3],'vent',32,34+f);line(im[4],27,52,46,54,'8') end;return
 end
 local offsets={0,2,1,-1,2,-2};local j=offsets[f]
 if t=='breakneck_charge' then
  -- Closing jaws compress behind the rotor, then spear out; open forward side.
  local r=({30,25,21,18,24,31})[f]
  line(im[2],48-r,29,38,34,'6');line(im[3],48-r,41,38,36,'8')
  stamp(im[4],'tear',46+j,22);stamp(im[3],'tear',46-j,40,true);return
 end
 stamp(im[3],'vent',26+j,29);stamp(im[3],'vent',60-j,33,true)
 if t~='rank1_active' then
  -- Rank II gains a second staggered exhaust bank and a broken rotor rail.
  stamp(im[2],'tooth',31,44);stamp(im[2],'tooth',57,23,true)
  stamp(im[3],'tear',17+j,38);stamp(im[3],'tear',66-j,24,true)
  line(im[4],33,23,46,20,'8');line(im[4],53,45,65,41,'8')
 end
 if t=='runaway_low' or t=='runaway_high' then
  stamp(im[4],'shard',19-j,24);stamp(im[4],'shard',72+j,44,true)
  if t=='runaway_high' then
   stamp(im[3],'tear',5+f%3*3,46);stamp(im[3],'tear',78-f%3*2,17,true)
   if f==2 or f==5 then flash(im[4],3,false) end
  end
 end
end)
author('dead_centre',{'anchor_build','anchor_full','bulwark_lock','bulwark_contact','counterweight_store','counterweight_release'},function(im,t,f)
 local r=t=='anchor_build' and 30-f*2 or 21
 diamond(im[1],r,49,'1');diamond(im[1],r+4,49,'2')
 if t=='anchor_build' then
  stamp(im[2],'tooth',43-r,46);stamp(im[2],'tooth',45+r,46,true);return
 end
 -- Four physical jaws at floor plane, open centre preserves top silhouette.
 stamp(im[2],'jaw',20,44);stamp(im[2],'jaw',65,44,true)
 stamp(im[2],'tooth',44,32);stamp(im[2],'tooth',44,58,true)
 if t=='bulwark_lock' or t=='bulwark_contact' then
  stamp(im[2],'jaw',13,47);stamp(im[2],'jaw',72,47,true)
  line(im[1],16,57,38,65,'2');line(im[1],59,65,81,57,'2')
  if t=='bulwark_contact' then
   local d=({0,2,5,9,13,17})[f];stamp(im[4],'shard',16-d,37);stamp(im[4],'shard',75+d,40,true)
   if f<4 then diamond(im[3],26+d,49,'4') end
  end
 elseif t=='counterweight_store' then
  -- Frames are six physical charge stages, not temporal playback.
  for k=0,4 do
   local c=k<f-1 and '8' or '1'
   line(im[3],31+k*7,62-math.abs(k-2),35+k*7,62-math.abs(k-2),c)
   line(im[3],31+k*7,63-math.abs(k-2),35+k*7,63-math.abs(k-2),c)
  end
 elseif t=='counterweight_release' then
  if f<4 then diamond(im[4],16+f*7,49,'4') end
  stamp(im[4],'shard',65+f*3,36-f);stamp(im[3],'recoil',18-f,51,true)
 else
  line(im[3],22,51,29,51,'4');line(im[3],68,51,75,51,'4')
  if f==2 or f==3 then stamp(im[4],'tooth',44,58) end
 end
end)
author('afterimage',{'rank1_trace','rank2_trace','ghost_closure','ghost_active','slipstream_cross'},function(im,t,f)
 if t=='rank1_trace' then stamp(im[3],'arrow',43,45);return end
 if t=='rank2_trace' then stamp(im[2],'socket',44,45);stamp(im[3],'arrow',52,43);return end
 if t=='ghost_closure' then
  -- Two separated terminal clamps SNAP into a single latched route node.
  local d=({14,9,0,0,3,6})[f]
  stamp(im[2],'socket',43-d,44);stamp(im[3],'socket',43+d,44)
  if f==3 or f==4 then stamp(im[4],'catch',43,43);line(im[4],25,48,70,48,'B') end
 elseif t=='ghost_active' then
  stamp(im[2],'latch',44,44);if f<3 then stamp(im[4],'catch',43,43) end
 elseif t=='slipstream_cross' then
  local d=({0,3,9,17,27,39})[f]
  stamp(im[3],'arrow',34+d,48-d/2);stamp(im[3],'arrow',42+d,52-d/2)
  if f<3 then stamp(im[4],'catch',43,43) end
 end
end)
author('combat',{'light','meaningful','heavy','signature','elite_entry','boss_entry','boss_defeat','reclaim','second_wind','low_rpm'},function(im,t,f)
 if t=='light' then if f<4 then stamp(im[4],'shard',44+f,33) end
 elseif t=='meaningful' then flash(im[4],f,false)
 elseif t=='heavy' or t=='signature' then flash(im[4],f,t=='signature');if f>1 and f<5 then stamp(im[3],'shard',18-f,43);stamp(im[3],'shard',70+f,23,true) end
 elseif t=='elite_entry' then diamond(im[2],18+f*2,48,'8');stamp(im[4],'crown',44,17)
 elseif t=='boss_entry' then
  diamond(im[1],34,48,'6');diamond(im[3],40-f*3,48,'8')
  stamp(im[2],'jaw',14,43);stamp(im[2],'jaw',71,43,true)
  stamp(im[4],'crown',44,8+f);line(im[3],48,18,48,27,'7')
 elseif t=='boss_defeat' then flash(im[4],f,true);diamond(im[2],14+f*6,48,'6');stamp(im[3],'recoil',11-f,51);stamp(im[3],'recoil',77+f,27,true)
 elseif t=='reclaim' then
  local d=({17,12,7,2,0,0})[f];stamp(im[3],'arrow',43-d,39+d);stamp(im[3],'arrow',48+d,26-d,true)
  if f==4 or f==5 then line(im[4],35,25,58,25,'B') end
 elseif t=='second_wind' then
  if f<3 then stamp(im[2],'recoil',30,39+f*2);stamp(im[3],'vent',58,41)
  else stamp(im[4],'catch',43,26);diamond(im[3],(f-2)*10,48,'B');stamp(im[3],'shard',21-f,26);stamp(im[3],'shard',70+f,35,true) end
 elseif t=='low_rpm' and (f==2 or f==5) then stamp(im[3],'shard',24,48);line(im[2],31,52,41,53,'6') end
end)
