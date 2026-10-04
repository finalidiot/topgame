-- One-time native replacement of the rejected legacy knife/wedge card identity.
-- Appends new named rows; does not recreate or overwrite prior card cels.
local root=app.params.root;assert(root)
local palette={'172b38','334954','637773','b9bb91','f6e5ae','fff3d1','a34335','ef713b','ffc05a','247b79','52c8b5','c8f5d4','3d6e99','75b9e1'}
local ink={};for i,v in ipairs(palette) do ink[i]=Color{r=tonumber(v:sub(1,2),16),g=tonumber(v:sub(3,4),16),b=tonumber(v:sub(5,6),16)}.rgbaPixel end
local function px(im,x,y,c) x=math.floor(x+.5);y=math.floor(y+.5);if x>=0 and x<im.width and y>=0 and y<im.height then im:drawPixel(x,y,ink[c]) end end
local function line(im,x,y,xx,yy,c,width) local n=math.max(math.abs(xx-x),math.abs(yy-y));for k=0,n do local t=n==0 and 0 or k/n;for j=0,(width or 1)-1 do px(im,x+(xx-x)*t,y+(yy-y)*t+j,c) end end end
local function arc(im,x,y,r,a,len,c,width) local n=math.max(5,math.ceil(r*math.abs(len)));local last=nil;for i=0,n do local b=a+len*i/n;local q={x+math.cos(b)*r,y+math.sin(b)*r*.55};if last then line(im,last[1],last[2],q[1],q[2],c,width) end;last=q end end
for _,group in ipairs({'cards','icons'}) do
 local s=app.open(root..'/assets/source-art/roster_'..group..'_002c5.aseprite')
 for _,tag in ipairs(s.tags) do assert(tag.name~='iron_comet','Replacement source already authored') end
 local count=group=='cards' and 6 or 1;local w=group=='cards' and 64 or 16
 assert(#s.frames==16*count,'Unexpected edited source structure; refuse to append')
 for rank=1,2 do
  local first=#s.frames+1
  for f=1,count do
   app.frame=s.frames[#s.frames];s:newEmptyFrame();local frame=#s.frames
   s.frames[frame].duration=group=='cards' and ({.11,.09,.075,.075,.10,.17})[f] or .12
   local im={};for k=1,#s.layers do im[k]=Image(w,w,ColorMode.RGB) end
   if group=='cards' then
    for y=4,59 do for x=4,59 do if x==4 or x==59 or y==4 or y==59 then px(im[1],x,y,2) elseif y>51 then px(im[1],x,y,1) end end end
    -- A physical closed wall at left; actual spinning machine at right.
    for y=15,43 do line(im[2],10,y,15,y,1,1);line(im[2],11,y,13,y,3,1) end
    line(im[3],14,17,14,42,4,1);for y=21,37,8 do line(im[3],11,y,13,y,9,1) end
    local phase=f*.25;local r=15
    for k=0,7 do local a=phase+k*math.pi/4;arc(im[2],38,31,r,a,.58,1,5);arc(im[3],38,28,r,a,.58,3,4);arc(im[3],38,27,r,a+.04,.43,4,1) end
    arc(im[3],38,28,5,0,math.pi*2,1,2);line(im[3],36,26,40,26,6,1);line(im[3],38,40,38,48,2,2);px(im[3],38,48,6)
    -- A banked route made of short rails, with separated rotor fragments.
    line(im[4],25,47,16,36,7,2);line(im[4],17,32,25,25,9,2)
    line(im[4],24,35,29,32,9,2);line(im[4],22,41,28,37,5,1)
    for k=0,3 do local a=phase+k*math.pi/2;arc(im[4],38,28,19,a,.34,9,1) end
    if f==2 or f==3 then arc(im[5],38,28,18,phase,.42,6,1) end
    if rank==2 then
     arc(im[4],38,28,23,phase,.5,9,1);arc(im[4],38,28,23,phase+math.pi,.5,9,1)
     for k=0,2 do line(im[5],48+k*3,13+k*3,50+k*3,11+k*3,9,1) end
    end
   else
    line(im[1],1,3,1,13,3,2);line(im[2],3,5,3,10,9,1)
    for k=0,3 do arc(im[1],10,7,4,k*math.pi/2,.9,3,2) end
    arc(im[2],10,7,5,.1,1.0,9,1);arc(im[2],10,7,5,math.pi+.1,1.0,9,1)
    line(im[2],4,11,7,10,9,1);line(im[2],4,6,6,5,9,1)
    if rank==2 then line(im[2],8,0,12,0,6,1) end
   end
   for k=1,#s.layers do s:newCel(s.layers[k],frame,im[k],Point(0,0)) end
  end
  local tag=s:newTag(first,#s.frames);tag.name=rank==1 and 'iron_comet' or 'iron_comet_ii'
 end
 for i,tag in ipairs(s.tags) do tag.toFrame=s.frames[i*count] end
 s:saveAs(root..'/assets/source-art/roster_'..group..'_002c5.aseprite');s:close()
end
