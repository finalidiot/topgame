-- Native-scale revision 2. Edits only the new masters inside Aseprite.
-- One-time art pass; production re-export does not invoke this file.
local root=app.params.root
local colours={s=Color{r=24,g=38,b=43}.rgbaPixel,m=Color{r=90,g=107,b=102}.rgbaPixel,b=Color{r=184,g=184,b=137}.rgbaPixel,h=Color{r=246,g=229,b=174}.rgbaPixel,r=Color{r=163,g=67,b=53}.rgbaPixel,o=Color{r=239,g=113,b=59}.rgbaPixel}
local brace={'....bbbbbbbb.......','..bbhhhhhhhhbb.....','.bhhmmmmmmmmhhb....','bhhmmssssssmmhhb...','bhmmss....ssmmhb...','bhmss......ssmhb...','bhms........smhb...','bms..........smb...','.s............s....'}
local function stamp(im,rows,x,y,flip)
 for yy,row in ipairs(rows) do for xx=1,#row do local c=colours[row:sub(xx,xx)];if c then im:drawPixel(x+(flip and #row-xx or xx-1),y+yy-1,c) end end end
end
local s=app.open(root..'/assets/source-art/dead_centre_fx_002c4.aseprite')
for _,tag in ipairs(s.tags) do
 if tag.name=='bulwark_lock' or tag.name=='bulwark_contact' then
  for f=tag.fromFrame.frameNumber,tag.toFrame.frameNumber do
   local cel=s.layers[2]:cel(f);local im=cel.image:clone()
   -- broad load-bearing feet, materially heavier than Rank II's four jaws
   stamp(im,brace,7,43);stamp(im,brace,69,43,true)
   stamp(im,{'....bbbbbbbb....','..bbhhhhhhhhbb..','bbmmmmmmmmmmmmmb','..ssssssssssss..'},39,63)
   cel.image=im
  end
 end
end
s:saveAs(s.filename);s:close()
s=app.open(root..'/assets/source-art/redline_fx_002c4.aseprite')
for _,tag in ipairs(s.tags) do
 if tag.name=='rank2_active' or tag.name=='runaway_low' or tag.name=='runaway_high' then
  for f=tag.fromFrame.frameNumber,tag.toFrame.frameNumber do
   local cel=s.layers[2]:cel(f);local im=cel.image:clone()
   stamp(im,{'.....rrrrrrrr.....','...rroooooooorr...','.rroo........oorr.','roo............oor'},28,21)
   stamp(im,{'roo............oor','.rroo........oorr.','...rroooooooorr...','.....rrrrrrrr.....'},50,44,true)
   cel.image=im
  end
 end
end
s:saveAs(s.filename);s:close()
