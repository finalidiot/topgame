extends SceneTree
## Logical input and native composition contracts; no physical-button acceptance claim.
const Layout = preload("res://scripts/combat_hud_layout.gd")
const Touch = preload("res://scripts/touch_controls.gd")
const Front = preload("res://scripts/front_end.gd")
const Bindings = preload("res://scripts/controller_bindings.gd")
const Starters = preload("res://scripts/starters.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
	func _battle_sound(_kind: String) -> void: pass
var checks: int = 0
var failures: Array[String] = []
var report: String
var native: bool = false
var game: QuietMain
var evidence: Dictionary = {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func settle() -> void:
	await process_frame; await process_frame
func pad(button: JoyButton) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventJoypadButton.new()
		event.device = 7; event.button_index = button; event.pressed = pressed
		Input.parse_input_event(event); await settle()
func touch(index: int, point: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new(); event.index = index; event.position = point; event.pressed = pressed
	return event
func draft_fixture(mutation: bool = false) -> void:
	game.run_context.clear(); game.run_context.start(Starters.build_for("breaker"),7341,"breaker")
	game.mode = "run"; game.run_context._pending_offer.assign(["redline","dead_centre","afterimage"])
	if mutation:
		game.run_context._owned_power_ids.assign(["redline"])
		game.run_context._power_ranks = {"redline":2}
		check(game.run_context.choose_power(game.run_context.pending_draft_id,"redline"),"Legal rank-II offer enters uncommitted mutation")
		game._show_mutation(false)
	else: game._show_reward()
	game.menus._ui_owner_device = 7
func reroll_contracts() -> void:
	var actions: Dictionary = {}
	for action: String in ["ui_accept","ui_cancel","burst","brake","pause"]:
		var buttons: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton: buttons.append([event.device,event.button_index])
		actions[action] = buttons
	var mapped: Array = []
	for event: InputEvent in InputMap.action_get_events("draft_reroll"):
		if event is InputEventJoypadButton: mapped.append(event.button_index)
	check(mapped == [JOY_BUTTON_RIGHT_SHOULDER],"Only right bumper maps dedicated reroll action, never a face button")
	for profile: String in ["xbox","nintendo","playstation"]:
		game._action("settings_changed",{"controller_layout":profile})
		draft_fixture(); await settle()
		var previous: Array = game.run_context.pending_offer
		var charges: int = game.run_context.reroll_charges
		await pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(game.screen == "reward" and game.run_context.reroll_charges == charges-1,"Right bumper debits exactly one charge for " + profile)
		check(game.run_context.pending_offer != previous and int(game.run_context.reroll_snapshot().revision) == 1,"Reroll changes actual draft and revision for " + profile)
		check(game.menus._reroll_control.text.begins_with(Front.prompt(profile,"reroll")),"Visible bumper label matches profile " + profile)
		check(Bindings.reroll_button(profile) == JOY_BUTTON_RIGHT_SHOULDER,"Printed shoulder mapping is position-stable for " + profile)
		var count: int = game.run_context.reroll_charges
		await pad(JOY_BUTTON_X)
		check(game.run_context.reroll_charges == count,"Other face button does not reroll " + profile)
		check(not game.run_context.reroll_offer(game.run_context.pending_draft_id,0),"Stale reroll callback rejected " + profile)
		draft_fixture(true); await settle()
		var owned: Array = game.run_context.owned_power_ids; var ranks: Dictionary = game.run_context.power_ranks
		charges = game.run_context.reroll_charges
		await pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(game.screen == "reward" and game.run_context.pending_mutation_power.is_empty(),"Mutation bumper returns to fresh uncommitted parent draft " + profile)
		check(game.run_context.reroll_charges == charges-1 and game.run_context.owned_power_ids == owned and game.run_context.power_ranks == ranks,"Mutation reroll debits once and preserves all investments " + profile)
		check(not game.run_context.reroll_pending_mutation(game.run_context.pending_draft_id,0),"Old mutation reroll cannot consume a second charge " + profile)
	draft_fixture(); game.run_context.collect_reroll_pickup("logical-bumper-extra-charge")
	var pressed:=InputEventJoypadButton.new(); pressed.device=7; pressed.button_index=JOY_BUTTON_RIGHT_SHOULDER; pressed.pressed=true
	Input.parse_input_event(pressed); await settle()
	var after_first: int=game.run_context.reroll_charges
	Input.parse_input_event(pressed); await settle()
	check(game.run_context.reroll_charges==after_first,"Held/duplicate bumper press cannot retrigger after menu rebuild")
	pressed=InputEventJoypadButton.new(); pressed.device=7; pressed.button_index=JOY_BUTTON_RIGHT_SHOULDER; pressed.pressed=false; Input.parse_input_event(pressed); await settle()
	await pad(JOY_BUTTON_RIGHT_SHOULDER)
	check(game.run_context.reroll_charges==after_first-1,"Released bumper permits next deliberate reroll")
	draft_fixture(true); game.run_context.reroll_pending_mutation(game.run_context.pending_draft_id,0)
	game.run_context._pending_offer.assign(["redline","dead_centre","afterimage"])
	game.run_context.choose_power(game.run_context.pending_draft_id,"redline"); game._show_mutation(false)
	game._action("choose_mutation",{"encounter_id":game.run_context.pending_draft_id,"run_seed":game.run_context.run_seed,"branch_id":"runaway","offer_revision":0})
	check(game.screen=="mutation" and int(game.run_context.power_ranks.redline)==2,"Old mutation card revision cannot commit a newly rebuilt preview")
	game.run_context._owned_power_ids.assign(["redline","dead_centre","afterimage","impact_wake","iron_comet","chain_impact","clutch"])
	for id: String in game.run_context._owned_power_ids: game.run_context._power_ranks[id]=preload("res://scripts/run_powers.gd").max_rank(id)
	game.run_context._power_ranks.redline=2; game.run_context._pending_offer.assign(["redline"])
	check(not game.run_context.can_reroll_mutation() and not game.run_context.reroll_pending_mutation(game.run_context.pending_draft_id,1),"No alternative at legal full family cap cannot charge to reorder exhaustive mutation branches")
	draft_fixture(true); game.run_context.reroll_charges = 0; game._show_mutation(false)
	check(game.menus._reroll_control.disabled and not game.run_context.can_reroll_mutation(),"No-charge mutation reroll visibly unavailable")
	check(not game.run_context.reroll_pending_mutation(game.run_context.pending_draft_id,0) and game.run_context.pending_mutation_power == "redline","Unavailable reroll cannot discard pending choice")
	evidence.controller = {"logical_device":7,"profiles":["xbox","nintendo","playstation"],"physical_button_test":false,"preserved_action_inventory":actions}
func hud_lifecycle() -> void:
	game.menus.show_hud({"player_rpm":.95,"redline_active":true,"overdrive_active":false,"power_state":{"redline":{"owned":true,"active":true,"heat":.6,"excess":0}}})
	check(not game.menus._rpm_overdrive and not game.menus._hud.player_rpm.text.contains("OVERDRIVE"),"Paid Redline window below normal cap does not claim Overdrive")
	check(game.menus._hud.state_meters.diagnostic_snapshot().rows.right[0].text.begins_with("REDLINE"),"Redline power always owns REDLINE label during paid window")
	game.menus.show_hud({"player_rpm":1.12,"overdrive_active":true,"power_state":{"redline":{"owned":true,"active":true,"heat":.6,"excess":.12}}})
	check(game.menus._rpm_overdrive and game.menus._hud.player_rpm.text.contains("OVERDRIVE") and game.menus._hud.rpm_overflow.visible,"Actual overcap enables main bar state and upper fill")
	game.menus.show_hud({"player_rpm":.99,"redline_active":true,"overdrive_active":false,"power_state":{"redline":{"owned":true,"active":true,"heat":.5,"excess":0}}})
	check(not game.menus._rpm_overdrive and not game.menus._hud.player_rpm.text.contains("OVERDRIVE") and not game.menus._hud.rpm_overflow.visible,"Overcap loss clears all main text and overflow immediately while Redline remains paid")
	game.menus.show_hud({"player_rpm":.9,"power_state":{}})
	var no_rows: Dictionary = game.menus._hud.state_meters.diagnostic_snapshot()
	check(no_rows.rows.left.is_empty() and no_rows.rows.right.is_empty(),"Unowned powers reserve no visible meter panels")
	game.menus.show_hud({"player_rpm":.9,"power_state":{"anchor":{"owned":true,"stress":.8},"sink":{"owned":true,"ratio":.7,"stored":105,"capacity":150},"redline":{"owned":true},"orbit":{"owned":true,"drive":.5}}})
	var layout: Dictionary = game.menus.combat_layout_snapshot()
	for area: Rect2 in layout.regions.values(): check(not area.intersects(Layout.PLAY_REGION),"Every permanent HUD region is outside actual arena viewport")
	var meters: Dictionary = game.menus._hud.state_meters.diagnostic_snapshot()
	check(meters.rows.left.size()+meters.rows.right.size() == 4 and int(meters.label_size)>=10,"Four owned state meters use margin space and readable ten-pixel labels")
	check(game.combat_viewport.size == Vector2i(640,360) and game.battle.get_viewport() == game.combat_viewport,"Canonical solver world retains native separate viewport")
	check(game.combat_frame.position == Vector2(80,60) and game.combat_frame.size == Vector2(640,360) and game.combat_frame.scale == Vector2.ONE,"Arena composition adds margins without changing camera or fractional stretching")
	check(game.combat_frame.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,"Composite preserves nearest authored pixels")
	check(game.battle.project(Vector2.ZERO) == Vector2(320,165),"Fixed canonical isometric camera remains exact")
	for display: Vector2i in [Vector2i(960,600),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(800,480)]:
		var fit: Dictionary = Layout.integer_fit(display)
		check(int(fit.scale)>=1 and Vector2i(fit.arena_pixels) == Vector2i(640,360)*int(fit.scale),"Display fit preserves uniform integer world pixels " + str(display))
	check(Layout.integer_fit(Vector2i(1920,1080)).scale > Layout.integer_fit(Vector2i(960,600)).scale,"Larger fullscreen display grows arena beyond small-window presentation")
	evidence.geometry = layout
func impact_number_options() -> void:
	check(not game._validated_settings({}).impact_numbers and not game._validated_settings({"impact_numbers":"on"}).impact_numbers,"Missing or malformed impact-number preference defaults OFF")
	game.run_context.clear(); game._title(); game.smoke_mode=false
	game._action("settings_changed",{"impact_numbers":true})
	check(game.settings.impact_numbers and game.battle.impact_numbers_enabled,"Options setting immediately enables actual Battle numbers")
	var config:=ConfigFile.new()
	check(config.load(game.preferences_path)==OK and bool(config.get_value("settings","impact_numbers",false)),"ON persists only to isolated preference path")
	game._show_settings()
	var toggle: Button=null
	for item: Node in game.menus._content.get_children():
		if item is Button and str(item.get_meta("setting_key",""))=="impact_numbers": toggle=item
	check(is_instance_valid(toggle) and toggle.text=="ON","Actual Options exposes matching Impact Numbers state")
	toggle.pressed.emit()
	check(not game.settings.impact_numbers and not game.battle.impact_numbers_enabled,"Visible toggle immediately disables actual Battle numbers")
	check(config.load(game.preferences_path)==OK and not bool(config.get_value("settings","impact_numbers",true)),"OFF persists through typed preference roundtrip")
	game.menus.show_hud({"impact_confirmation":"ELITE RING OUT"})
	check(game.menus._hud.impact_confirmation.text=="ELITE RING OUT" and not game.menus._hud.impact_confirmation.get_global_rect().intersects(Layout.PLAY_REGION),"Actual elimination confirmation stays in HUD margin")
	game.menus.show_hud({})
	check(game.menus._hud.impact_confirmation.text.is_empty(),"Expired elimination presentation leaves no stale confirmation")
	game.smoke_mode=true

func touch_contracts() -> void:
	var control: Node2D = game.touch_controls; control.clear(); control.set_enabled(true)
	for point: Vector2 in [Vector2(5,180),Vector2(400,30),Vector2(400,455),Vector2(730,170)]:
		check(not control.handle_touch(touch(12,point,true)) and control.steering_finger == -1,"Permanent HUD/margins cannot steal fresh steering touch " + str(point))
	check(control.handle_touch(touch(1,Vector2(320,180),true)) and control.steering_finger == 1,"Native central arena accepts hold-and-drag")
	var event := InputEventScreenDrag.new(); event.index=1; event.position=Vector2(760,20)
	check(control.handle_touch(event) and control.direction.length()>.99,"Owned drag keeps steering across HUD margins without ending gesture")
	control.handle_touch(touch(1,Vector2(760,20),false))
	check(control.steering_finger == -1 and control.direction == Vector2.ZERO,"Cross-margin release clears ownership")
	check(control.handle_touch(touch(2,Touch.BURST_RECT.get_center(),true)) and control.action_down("burst"),"Right-margin Burst remains independent opposite-thumb action")
	check(control.handle_touch(touch(3,Touch.BRAKE_RECT.get_center(),true)) and control.action_down("brake"),"Right-margin Brake remains independent opposite-thumb action")
	check(not Touch.BURST_RECT.intersects(Layout.PLAY_REGION) and not Touch.BRAKE_RECT.intersects(Layout.PLAY_REGION),"Android action controls frame rather than obscure arena")
	control.clear()
	game.run_context.clear(); game._title()
	check(game.menus._content.position == Vector2(80,60) and game.menus._content.size == Vector2(640,360),"Menus keep canonical art extent and centered native composition")
	check(Layout.menu_point(Vector2(302,132)) == Vector2(222,72) and Layout.arena_point(Vector2(400,225)) == Vector2(320,165),"Root-screen translation preserves menu gestures and native arena pivots")
func native_presentation() -> void:
	game.run_context.clear(); game.run_context.start(Starters.build_for("breaker"),7341,"breaker")
	game.run_context._owned_power_ids.assign(["redline","dead_centre","orbit_drive","impact_sink"])
	game.run_context._power_ranks={"redline":2,"dead_centre":2,"orbit_drive":2,"impact_sink":2}
	game.mode="run"; game._launch_run_encounter(); game.battle.set_physics_process(false)
	var player: Dictionary=game.battle.player_entity(); player.rpm=.82; player.redline_heat=.6; player.anchor_charge=.8
	game.battle.battle_status="battle"; game.battle._emit_hud()
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_stretch=Window.CONTENT_SCALE_STRETCH_INTEGER
	var directory: String=report.get_base_dir().get_base_dir().path_join("frames/hud_native_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var observed: Array=[]
	for mode: int in [DisplayServer.WINDOW_MODE_WINDOWED,DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_WINDOWED]:
		DisplayServer.window_set_mode(mode)
		if mode == DisplayServer.WINDOW_MODE_WINDOWED: DisplayServer.window_set_size(Vector2i(960,600))
		await settle(); await process_frame; await RenderingServer.frame_post_draw
		var display: Vector2i=DisplayServer.window_get_size()
		var native_world: Image=game.combat_viewport.get_texture().get_image()
		var canvas: Image=root.get_texture().get_image()
		check(native_world.get_size()==Vector2i(640,360),"Actual native world remains640x360 across fullscreen/windowed changes")
		check(game.combat_frame.scale==Vector2.ONE and game.combat_frame.position==Vector2(80,60),"Real window mode change preserves composition and fixed camera")
		var fit: Dictionary=Layout.integer_fit(display)
		var name: String="fullscreen" if mode==DisplayServer.WINDOW_MODE_FULLSCREEN else "windowed_%d" % observed.size()
		var path: String=directory.path_join(name+".png"); canvas.save_png(path)
		var multiple: int=int(fit.scale)
		var composed: Image=canvas.get_region(Rect2i(Vector2i(Layout.ARENA_ORIGIN)*multiple,Vector2i(640,360)*multiple))
		composed.resize(640,360,Image.INTERPOLATE_NEAREST)
		check(composed.get_data()==native_world.get_data(),"Actual fullscreen/windowed composite has exact native RGBA at integer scale")
		observed.append({"mode":name,"display_size":display,"root_texture_size":canvas.get_size(),"world_size":native_world.get_size(),"integer_fit":fit,"image":path})
		print("NATIVE_COMPOSITION ",name," display=",display," texture=",canvas.get_size()," native=",native_world.get_size()," fit=",fit)
	check(int(observed[1].integer_fit.scale)>=int(observed[0].integer_fit.scale),"Actual fullscreen uses at least the windowed integer scale")
	evidence.actual_windows_mode_changes=observed
	evidence.android_device_test=false

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report=arg.trim_prefix("--report=")
		if arg=="--native": native=true
	if not report.is_absolute_path() or not report.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/manifests/") or FileAccess.file_exists(report):
		push_error("Fresh external report required; no player data opened"); quit(2); return
	root.size=Vector2i(800,480); root.content_scale_size=Vector2i(800,480); Input.use_accumulated_input=false
	game=QuietMain.new(); game.smoke_mode=true
	game.collection_path=report.get_base_dir().get_base_dir().path_join("temp/hud_acceptance_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	root.add_child(game); await settle()
	await reroll_contracts(); hud_lifecycle(); touch_contracts(); impact_number_options()
	if native: await native_presentation()
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence},"\t"))
	game.free(); print("COMBAT_ACCEPTANCE_HUD_003A1_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL",checks]); quit(0 if failures.is_empty() else 1)
