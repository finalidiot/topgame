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
	var machines: Array = []
	for machine: Dictionary in game.battle.fighters:
		machines.append({"entity_id":machine.entity_id,"team":machine.team_id,"outcome":machine.outcome,"pos":[machine.pos.x,machine.pos.y],"vel":[machine.vel.x,machine.vel.y],"rpm":machine.get("rpm",machine.get("energy",0.0)),"cooldown":machine.get("cooldown",0.0)})
	var data: Dictionary = {"run_id":request_data.run_id,"platform":OS.get_name(), "debug":OS.has_feature("debug"),
		"isolated_collection":game.collection.save_path,"screen":game.screen,"mode":game.mode,
		"viewport":[viewport_size.x,viewport_size.y],"physical_screen":[screen_size.x,screen_size.y],
		"combat_viewport":[game.combat_viewport.size.x,game.combat_viewport.size.y],"arena_origin":[game.combat_frame.position.x,game.combat_frame.position.y],
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
