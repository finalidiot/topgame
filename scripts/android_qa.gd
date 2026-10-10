extends RefCounted
## Debug-only, explicit device QA. Never redirects or resets a player profile.
const REQUEST: String = "user://qa003a/request.json"
static func request_seed(value: Variant) -> int:
	if not (value is int or value is float): return 0
	var number: float = float(value)
	return int(number) if is_finite(number) and number==floorf(number) and number>0.0 and number<=2147483647.0 else 0
static func request() -> Dictionary:
	if not OS.has_feature("android") or not OS.has_feature("debug") or not FileAccess.file_exists(REQUEST): return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(REQUEST))
	if not data is Dictionary: return {}
	var id: String = str(data.get("run_id", ""))
	if id.length() != 32 or not id.is_valid_hex_number(false): return {}
	var requested_seed: int = request_seed(data.get("run_seed",0))
	return {"run_id":id,"run_seed":requested_seed,"collection_path":"user://test_collection/android_003a_"+id+".json", "capture_dir":"user://qa003a/"+id}

static func report(game: Node, request_data: Dictionary) -> void:
	if request_data.is_empty(): return
	var root: String = request_data.capture_dir
	DirAccess.make_dir_recursive_absolute(root)
	var viewport_size: Vector2 = game.get_viewport().get_visible_rect().size
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var surface: Rect2 = Rect2(Vector2.ZERO,viewport_size)
	if game.get_viewport().get_parent() is SubViewportContainer: surface = game.get_viewport().get_parent().get_global_rect()
	var presentation: Dictionary = game.window_presentation_snapshot()
	var touch_layout: Dictionary = game.touch_controls.layout_snapshot()
	var canvas_safe: Rect2 = presentation.get("safe_rect",Rect2(Vector2.ZERO,viewport_size))
	var arena_rect: Rect2 = Rect2(game.combat_frame.position,game.combat_frame.size)
	var burst_rect: Rect2 = touch_layout.burst_rect
	var brake_rect: Rect2 = touch_layout.brake_rect
	var steering_rect: Rect2 = touch_layout.steering_rect
	var menu_origin: Vector2 = presentation.get("menu_origin",Vector2(80,60))
	var menu_scale: float = float(presentation.get("menu_scale",1.0))
	var machines: Array = []
	for machine: Dictionary in game.battle.fighters:
		machines.append({"entity_id":machine.entity_id,"team":machine.team_id,"outcome":machine.outcome,"pos":[machine.pos.x,machine.pos.y],"vel":[machine.vel.x,machine.vel.y],"rpm":machine.get("rpm",machine.get("energy",0.0)),"cooldown":machine.get("cooldown",0.0)})
	var data: Dictionary = {"run_id":request_data.run_id,"platform":OS.get_name(), "debug":OS.has_feature("debug"),
		"isolated_collection":game.collection.save_path,"screen":game.screen,"mode":game.mode,
		"viewport":[viewport_size.x,viewport_size.y],"physical_screen":[screen_size.x,screen_size.y],
		"canvas_size":[viewport_size.x,viewport_size.y],
		"canvas_safe_area":[canvas_safe.position.x,canvas_safe.position.y,canvas_safe.size.x,canvas_safe.size.y],
		"combat_viewport":[game.combat_viewport.size.x,game.combat_viewport.size.y],"arena_origin":[game.combat_frame.position.x,game.combat_frame.position.y],
		"arena_rect":[arena_rect.position.x,arena_rect.position.y,arena_rect.size.x,arena_rect.size.y],
		"arena_scale":arena_rect.size.x/float(game.combat_viewport.size.x),
		"menu_origin":[menu_origin.x,menu_origin.y],"menu_scale":menu_scale,"menu_native_view":[640,360],
		"action_bounds":{"burst":[burst_rect.position.x,burst_rect.position.y,burst_rect.size.x,burst_rect.size.y],
			"brake":[brake_rect.position.x,brake_rect.position.y,brake_rect.size.x,brake_rect.size.y]},
		"steering_bounds":[steering_rect.position.x,steering_rect.position.y,steering_rect.size.x,steering_rect.size.y],
		"safe_area":[safe.position.x,safe.position.y,safe.size.x,safe.size.y],
		"native_surface":[surface.position.x,surface.position.y,surface.size.x,surface.size.y],
		"fps":Engine.get_frames_per_second(),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
		"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		"memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),
		"actions":game.audit_actions.duplicate(true),"collection":game.collection.snapshot(),"settings":game.settings.duplicate(true),
		"music":game.music.music_snapshot(),
		"touch":game.touch_controls.sample(),"touch_owners":game.touch_controls.owners.duplicate(),
		"battle_status":game.battle.battle_status,"elapsed":game.battle.elapsed,
		"machines":machines,"run_rewards":game.run_rewards.snapshot(),"run_seed":game.run_context.run_seed,
		"pending_offer":game.run_context.pending_offer.duplicate(),"pending_mutation_offer":game.run_context.pending_mutation_offer.duplicate(),
		"power_ids":game.run_context.owned_power_ids.duplicate(),"power_ranks":game.run_context.power_ranks.duplicate(),
		"arena":game.battle.arena_presentation.last_snapshot.duplicate(),"packet_phase":game.menus._packet_view.phase if is_instance_valid(game.menus._packet_view) else ""}
	data.touch.direction = [data.touch.direction.x,data.touch.direction.y]
	var file = FileAccess.open(root.path_join("state.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data,"\t"))
