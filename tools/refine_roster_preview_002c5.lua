-- One-time source revision after native QA. Not part of normal export.
local root=app.params.root;assert(root)
local s=app.open(root..'/assets/source-art/roster_fx_002c5.aseprite')
local tag=nil;for _,t in ipairs(s.tags) do if t.name=='ghost_preview' then tag=t end end;assert(tag)
for frame=tag.fromFrame.frameNumber,tag.toFrame.frameNumber do
 local cel=s.layers[4]:cel(frame);local im=cel.image:clone();local white=Color{r=200,g=245,b=212}.rgbaPixel
 -- Four separated mechanical clamp corners leave the route socket clear.
 for _,q in ipairs({{40,42,1,1},{56,42,-1,1},{40,54,1,-1},{56,54,-1,-1}}) do
  for k=0,3 do im:drawPixel(q[1]+q[3]*k,q[2],white);im:drawPixel(q[1],q[2]+q[4]*k,white) end
 end
 cel.image=im
end
s:saveAs(root..'/assets/source-art/roster_fx_002c5.aseprite');s:close()
