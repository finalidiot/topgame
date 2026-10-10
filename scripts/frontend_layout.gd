extends RefCounted
## Presentation policy only. Combat remains owned by CombatLayout; front-end
## pages allocate semantic panes across the client rather than scaling a page.
const MODALS: Array[String] = ["pause","reward","mutation","level_up","acquisition"]
const COMBAT: Array[String] = ["hud","battle"]

static func presentation_class(screen_id: String) -> String:
	if screen_id in COMBAT: return "combat"
	if screen_id in MODALS: return "modal"
	return "frontend"

static func desktop(canvas_size: Vector2, screen_id: String, requested_safe: Rect2 = Rect2()) -> Dictionary:
	var extent: Vector2 = Vector2(maxf(1,canvas_size.x),maxf(1,canvas_size.y))
	var safe: Rect2 = requested_safe.intersection(Rect2(Vector2.ZERO,extent))
	if safe.size.x<=0 or safe.size.y<=0: safe=Rect2(Vector2.ZERO,extent)
	var margin: float = clampf(minf(safe.size.x,safe.size.y)*.045,16,44)
	var frame: Rect2 = Rect2(safe.position+Vector2.ONE*margin,safe.size-Vector2.ONE*margin*2)
	var compact: bool = safe.size.x<1050 or safe.size.y<640
	var large: bool = safe.size.x>=1500 and safe.size.y>=800
	var gap: float = clampf(frame.size.x*.016,12,30)
	var header_height: float = clampf(frame.size.y*.115,56,104)
	var footer_height: float = clampf(frame.size.y*.10,44,84)
	var header: Rect2 = Rect2(frame.position,Vector2(frame.size.x,header_height))
	var footer: Rect2 = Rect2(Vector2(frame.position.x,frame.end.y-footer_height),Vector2(frame.size.x,footer_height))
	var body: Rect2 = Rect2(Vector2(frame.position.x,header.end.y+gap),Vector2(frame.size.x,maxf(1,footer.position.y-header.end.y-gap*2)))
	var regions: Dictionary = {"header":header,"footer":footer,"body":body}
	var half: float = (body.size.x-gap)*.5
	regions["left"] = Rect2(body.position,Vector2(half,body.size.y))
	regions["right"] = Rect2(Vector2(body.position.x+half+gap,body.position.y),Vector2(half,body.size.y))
	match screen_id:
		"title_gate":
			regions["identity"] = Rect2(frame.position,Vector2(frame.size.x*.48,frame.size.y-footer_height-gap))
			regions["hero"] = Rect2(Vector2(frame.position.x+frame.size.x*.50,frame.position.y+header_height*.3),Vector2(frame.size.x*.50,frame.size.y-footer_height-gap))
		"collection_title","title":
			var hero_width: float = body.size.x*(.55 if large else .48)
			regions["hero"] = Rect2(body.position,Vector2(hero_width,body.size.y))
			regions["navigation"] = Rect2(Vector2(body.position.x+hero_width+gap,body.position.y),Vector2(body.size.x-hero_width-gap,body.size.y))
		"starter_ceremony","starters":
			var width: float = (body.size.x-gap*2)/3
			for index: int in range(3): regions["starter_%d" % index]=Rect2(body.position+Vector2(index*(width+gap),0),Vector2(width,body.size.y))
		"settings":
			if compact:
				regions["audio"]=Rect2(body.position,Vector2(body.size.x,(body.size.y-gap)*.5))
				regions["comfort"]=Rect2(Vector2(body.position.x,regions.audio.end.y+gap),regions.audio.size)
				regions["controls"]=Rect2()
			elif large:
				var width: float = (body.size.x-gap*2)/3
				regions["audio"]=Rect2(body.position,Vector2(width,body.size.y))
				regions["comfort"]=Rect2(body.position+Vector2(width+gap,0),Vector2(width,body.size.y))
				regions["controls"]=Rect2(body.position+Vector2((width+gap)*2,0),Vector2(width,body.size.y))
			else:
				regions["audio"]=regions.left
				regions["comfort"]=Rect2(regions.right.position,Vector2(half,(body.size.y-gap)*.58))
				regions["controls"]=Rect2(Vector2(regions.right.position.x,regions.comfort.end.y+gap),Vector2(half,body.end.y-regions.comfort.end.y-gap))
		"collection_workshop","garage":
			if compact:
				regions["station"]=Rect2(body.position,Vector2(body.size.x*.36,body.size.y))
				regions["catalogue"]=Rect2(Vector2(regions.station.end.x+gap,body.position.y),Vector2(body.end.x-regions.station.end.x-gap,body.size.y))
			else:
				var station_width: float = body.size.x*.30
				var list_width: float = body.size.x*(.37 if large else .42)
				regions["catalogue"]=Rect2(body.position,Vector2(list_width,body.size.y))
				regions["station"]=Rect2(Vector2(regions.catalogue.end.x+gap,body.position.y),Vector2(station_width,body.size.y))
				regions["details"]=Rect2(Vector2(regions.station.end.x+gap,body.position.y),Vector2(body.end.x-regions.station.end.x-gap,body.size.y))
		"shop":
			var merchant_width: float = body.size.x*(.29 if large else .32)
			regions["merchant"]=Rect2(body.position,Vector2(merchant_width,body.size.y))
			regions["products"]=Rect2(Vector2(body.position.x+merchant_width+gap,body.position.y),Vector2(body.size.x-merchant_width-gap,body.size.y))
		"packet_open":
			var packet_scale: float=minf(body.size.x/640,body.size.y/360)
			regions["packet"]=Rect2(body.position+(body.size-Vector2(640,360)*packet_scale)*.5,Vector2(640,360)*packet_scale)
		"duel_result": regions["body"]=frame
	return {"canvas_size":extent,"safe_rect":safe,"frame_rect":frame,"root_rect":Rect2(Vector2.ZERO,extent),
		"root_scale":Vector2.ONE,"regions":regions,"gap":gap,"compact":compact,"large":large,
		"breakpoint":"large" if large else ("small" if compact else "medium"),
		"text_scale":clampf(minf(safe.size.x/1050,safe.size.y/640),1,2),"presentation_class":"frontend"}

static func reference_regions(screen_id: String) -> Dictionary:
	var common: Dictionary = {"header":Rect2(0,0,640,73),"footer":Rect2(0,310,640,50),"body":Rect2(0,60,640,250)}
	match screen_id:
		"title_gate": common.merge({"identity":Rect2(0,0,310,325),"hero":Rect2(310,0,330,325),"footer":Rect2(0,325,640,35)},true)
		"collection_title": common.merge({"navigation":Rect2(22,88,288,220),"hero":Rect2(338,94,280,212)},true)
		"title": common.merge({"navigation":Rect2(30,104,268,211),"hero":Rect2(324,104,286,211)},true)
		"settings": common.merge({"audio":Rect2(22,65,596,123),"comfort":Rect2(22,193,596,122)},true)
		"collection_workshop","garage": common.merge({"station":Rect2(16,65,220,241),"catalogue":Rect2(248,65,376,241),"details":Rect2(254,249,362,50)},true)
		"shop": common.merge({"merchant":Rect2(22,65,207,238),"products":Rect2(245,65,373,238)},true)
		"play_modes": common.merge({"left":Rect2(22,70,288,230),"right":Rect2(330,70,288,230)},true)
		"starter_ceremony","starters":
			for index: int in range(3): common["starter_%d" % index]=Rect2(22+index*202,68,192,240)
		"starter_confirm","starter_owned": common.merge({"left":Rect2(22,65,256,241),"right":Rect2(294,65,324,241)},true)
		"help": common.merge({"left":Rect2(22,65,279,237),"right":Rect2(313,65,305,237)},true)
		"duel_result": common["body"]=Rect2(121,35,398,290)
		"packet_open": common["packet"]=Rect2(0,0,640,360)
	return common

static func reference_region(screen_id: String, area: Rect2) -> String:
	var refs: Dictionary=reference_regions(screen_id)
	if area.size.x>=630 and area.size.y>=340: return "background"
	if screen_id=="title_gate": return "footer" if area.position.y>=325 else ("hero" if area.position.x>=310 else "identity")
	if screen_id=="duel_result": return "body"
	if screen_id=="packet_open": return "header" if area.get_center().y<60 else ("footer" if area.position.y>=309 else "packet")
	if area.position.y>=310: return "footer"
	if area.position.y<60 and area.size.y<80: return "header"
	if screen_id in ["collection_workshop","garage"] and area.position.x>=248 and area.position.y>=249: return "details"
	for key: String in refs:
		if key not in ["header","footer","body"] and refs[key].has_point(area.get_center()): return key
	return "body"

static func map_rect(area: Rect2, reference: Rect2, destination: Rect2) -> Rect2:
	var scalar: Vector2=destination.size/reference.size
	return Rect2(destination.position+(area.position-reference.position)*scalar,area.size*scalar)

static func modal_scale(canvas_size: Vector2, screen_id: String) -> float:
	if screen_id=="pause": return 1.0
	return minf(1.5,minf(maxf(1,canvas_size.x-160)/640,maxf(1,canvas_size.y-120)/360))
