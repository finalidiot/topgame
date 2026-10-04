-- One-time native Aseprite key-frame revision after gameplay-scale inspection.
local root=app.params.root
local core={'..........W..........','..........W..........','.........WWW.........','.........WWW.........','........WWWWW........','........WWWWW........','......WWWWWWWWW......','.....WWWWWWWWWWW.....','..WWWWWWWWWWWWWWWWW..','WWWWWWWWWWWWWWWWWWWWW','..WWWWWWWWWWWWWWWWW..','.....WWWWWWWWWWW.....','......WWWWWWWWW......','........WWWWW........','.........WWW.........','..........W..........'}
for _,family in ipairs({'combat','redline'}) do
 local s=app.open(root..'/assets/source-art/'..family..'_fx_002c4.aseprite')
 for _,tag in ipairs(s.tags) do
  if tag.name=='signature' or tag.name=='breakneck_hit' or tag.name=='boss_defeat' or tag.name=='heavy' then
   for offset=1,2 do
    local cel=s.layers[4]:cel(tag.fromFrame.frameNumber+offset)
    -- Reconstruct full canvas in case a later manual save trimmed the cel.
    local im=Image(96,80,ColorMode.RGB);im:drawImage(cel.image,cel.position)
    for y,row in ipairs(core) do for x=1,#row do
     if row:sub(x,x)=='W' then
      local color=Color{r=255,g=243,b=209}.rgbaPixel
      if offset==2 and math.abs(x-11)<4 and math.abs(y-8)<4 then color=Color{r=239,g=113,b=59}.rgbaPixel end
      im:drawPixel(37+x,25+y,color)
     end
    end end
    cel.image=im;cel.position=Point(0,0)
   end
  end
 end
 s:saveAs(s.filename);s:close()
end
