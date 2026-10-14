extends SceneTree
const Policy=preload("res://scripts/frontend_layout.gd")
var checks:int=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures.append(label);push_error(label)
func _initialize()->void:
	for screen:String in ["hud","battle"]:check(Policy.presentation_class(screen)=="combat","combat classification: "+screen)
	for screen:String in ["pause","reward","mutation","level_up","acquisition"]:check(Policy.presentation_class(screen)=="modal","modal classification: "+screen)
	for screen:String in ["title_gate","collection_title","play_modes","starter_ceremony","starter_confirm","starter_owned","collection_workshop","shop","packet_open","settings","help","save_tools","reset_confirmation","result","future_frontend"]:check(Policy.presentation_class(screen)=="frontend","front-end classification: "+screen)
	for canvas:Vector2 in [Vector2(800,480),Vector2(960,600),Vector2(1280,720),Vector2(1920,1080),Vector2(1920,1017),Vector2(2560,1440)]:
		for page:String in ["title_gate","collection_title","settings","collection_workshop","shop","packet_open","starter_ceremony","duel_result"]:
			var actual:Dictionary=Policy.desktop(canvas,page)
			check(actual.root_rect==Rect2(Vector2.ZERO,canvas) and actual.root_scale==Vector2.ONE,page+": actual client root")
			check(actual.safe_rect.encloses(actual.frame_rect),page+": modest safe frame")
			for key:String in actual.regions:
				var area:Rect2=actual.regions[key]
				if area.has_area():check(actual.safe_rect.encloses(area),page+": semantic region inside client "+key)
			if page=="settings" and not actual.compact:
				check(not actual.regions.audio.intersects(actual.regions.comfort) and not actual.regions.audio.intersects(actual.regions.controls) and not actual.regions.comfort.intersects(actual.regions.controls),"Options panes separate")
			if page=="collection_workshop" and not actual.compact:check(actual.regions.catalogue.end.x<actual.regions.station.position.x and actual.regions.station.end.x<actual.regions.details.position.x,"Workshop catalogue / machine / inspector separate")
		check(Policy.modal_scale(canvas,"pause")==1,"Pause stays native centered modal")
		for screen:String in ["reward","mutation","level_up","acquisition"]:
			var overlay:Dictionary=Policy.run_overlay(canvas,screen)
			check(Policy.uses_run_overlay(screen) and Policy.presentation_class(screen)=="modal","Run overlay retains combat-modal classification: "+screen)
			check(overlay.root_rect==Rect2(Vector2.ZERO,canvas) and overlay.root_scale==Vector2.ONE,"Run overlay spans the actual client without a fixed panel transform: "+screen)
			check(overlay.safe_rect.encloses(overlay.frame_rect),"Run overlay frame stays safe: "+screen)
			for key:String in overlay.regions:
				var area:Rect2=overlay.regions[key]
				if area.has_area():check(overlay.safe_rect.encloses(area),"Run overlay semantic region stays safe: "+screen+" / "+key)
	check(not Policy.uses_run_overlay("pause") and not Policy.uses_run_overlay("hud"),"Pause and combat are excluded from full-client Run overlays")
	var safe:Rect2=Rect2(24,18,1190,670)
	var inset:Dictionary=Policy.desktop(Vector2(1280,720),"settings",safe)
	check(inset.safe_rect==safe and safe.encloses(inset.frame_rect),"Explicit safe region respected")
	for screen:String in ["reward","mutation","level_up","acquisition"]:
		var overlay:Dictionary=Policy.run_overlay(Vector2(1280,720),screen,safe)
		check(overlay.root_rect==Rect2(0,0,1280,720) and overlay.safe_rect==safe and safe.encloses(overlay.frame_rect),"Full background/client root is independent of inset safe interaction frame: "+screen)
	print("FRONTEND_LAYOUT_003A2_%s checks=%d failures=%d"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
