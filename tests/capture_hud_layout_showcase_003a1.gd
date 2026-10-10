extends SceneTree
## Production Main/world, explicit legal invested loadout and synthetic controls.
const Starters=preload("res://scripts/starters.gd")
const Layout=preload("res://scripts/combat_hud_layout.gd")
const Director=preload("res://scripts/threat_director.gd")
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
var game: QuietMain
var report: String
var profile: String
var frames: String
var notes: Array=[]
var features: Dictionary={}
var failures: Array=[]
var movie_frames: int=0
var caption: Label
func _initialize() -> void: call_deferred("run")
func input_state(direction: Vector2, burst: bool=false, brake: bool=false) -> void:
	for axis: int in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:
		var event:=InputEventJoypadMotion.new(); event.device=7; event.axis=axis; event.axis_value=direction.x if axis==JOY_AXIS_LEFT_X else direction.y; Input.parse_input_event(event)
	for row: Array in [[JOY_BUTTON_A,burst],[JOY_BUTTON_LEFT_SHOULDER,brake]]:
		var event:=InputEventJoypadButton.new(); event.device=7; event.button_index=row[0]; event.pressed=row[1]; Input.parse_input_event(event)
func feature(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	if image.get_size()!=Vector2i(800,520): failures.append("Non-native review extent "+name+str(image.get_size()))
	var path: String=frames.path_join(name+".png"); image.save_png(path)
	var native: Image=game.combat_viewport.get_texture().get_image()
	if name.contains("four_meters"):
		var rows: Dictionary=game.menus._hud.state_meters.diagnostic_snapshot().rows
		if rows.left.size()+rows.right.size()!=4: failures.append("Four owned meters missing "+name)
	if name.begins_with("overdrive_"):
		var player: Dictionary=game.battle.player_entity()
		var expected: bool=name=="overdrive_on"
		if game.battle.powers.overdrive_active(player)!=expected or game.menus._rpm_overdrive!=expected: failures.append("Overdrive lifecycle differs "+name)
		if game.menus._hud.player_rpm.text.contains("OVERDRIVE")!=expected: failures.append("Actual reserve label differs "+name)
		var rows: Dictionary=game.menus._hud.state_meters.diagnostic_snapshot().rows
		var redline_label: bool=false
		for row: Dictionary in rows.right:
			if row.id=="redline": redline_label=str(row.text).begins_with("REDLINE")
		if not redline_label: failures.append("Owned meter lost REDLINE identity "+name)
	if name=="boss_rival_world_bars":
		var boss: bool=false
		var rival: bool=false
		for bar: Dictionary in game.top_status_bars.diagnostic_snapshot().get("bars",[]):
			boss=boss or bool(bar.boss)
			rival=rival or (not bool(bar.player) and not bool(bar.boss))
		if not boss or not rival: failures.append("Live boss and rival bars missing")
	var arena: Image=image.get_region(Rect2i(80,60,640,360))
	if arena.get_data()!=native.get_data(): failures.append("Native world parity differs "+name)
	features[name]={"path":path,"native_view":[800,480],"native_world":[640,360],"review_caption_pixels":40,"screen":game.screen,"geometry":game.menus.combat_layout_snapshot(),"state":game.battle.powers.public_state(game.battle.player_entity()),"rpm":game.battle.player_entity().rpm,"overdrive_text":game.menus._hud.player_rpm.text if game.menus._hud.has("player_rpm") else "","world_bars":game.top_status_bars.diagnostic_snapshot()}
func phase(text: String, seconds: float, steering: bool=false, centre: bool=false, allow_burst: bool=true) -> void:
	caption.text=text
	var start: int=movie_frames
	for tick: int in range(roundi(seconds*60)):
		var direction: Vector2=Vector2.ZERO
		if steering:
			var p: Dictionary=game.battle.player_entity()
			var world: Vector2=Vector2(60*cos(tick/55.0),60*sin(tick/55.0))
			var desired: Vector2=(world-Vector2(p.pos))*2.2-Vector2(p.vel)*.8
			direction=Vector2(desired.x-desired.y,(desired.x+desired.y)*.5).limit_length(70)/70
		input_state(direction,allow_burst and (tick==40 or tick==260),false)
		await process_frame
		movie_frames+=1
		if tick%30==0:
			var player: Dictionary=game.battle.player_entity()
			notes.append({"frame":movie_frames,"phase":text,"rpm":player.rpm,"powers":game.battle.powers.public_state(player),"status":game.battle.battle_status,"hits":game.battle.hits})
	input_state(Vector2.ZERO)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="): report=arg.trim_prefix("--manifest=")
		if arg.begins_with("--profile="): profile=arg.trim_prefix("--profile=")
		if arg.begins_with("--frames="): frames=arg.trim_prefix("--frames=")
	var valid: bool=true
	for path: String in [report,profile,frames]: valid=valid and path.is_absolute_path() and path.replace("\\","/").to_lower().contains("gyrobrothers-qa/003a.1/")
	if not valid or FileAccess.file_exists(report) or FileAccess.file_exists(profile) or DirAccess.dir_exists_absolute(frames): quit(2); return
	DirAccess.make_dir_recursive_absolute(frames)
	root.size=Vector2i(800,520); root.content_scale_size=Vector2i(800,520); root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	game=QuietMain.new(); game.smoke_mode=true; game.collection_path=profile; root.add_child(game)
	game.review_audio=true; game.music.configure_playback(true); game.music.set_context("run"); game.music.set_paused(false)
	game.mode="run"; game.run_context.start(Starters.build_for("bastion"),7341,"bastion")
	game.run_context._pending_offer.assign(["redline","dead_centre","afterimage"])
	if not game.run_context.choose_power(game.run_context.pending_draft_id,"redline"): failures.append("Starting fixture claim refused")
	game._launch_run_encounter()
	var layer:=CanvasLayer.new(); layer.layer=20; root.add_child(layer)
	var strip:=ColorRect.new(); strip.position=Vector2(0,480); strip.size=Vector2(800,40); strip.color=Color("16202b"); layer.add_child(strip)
	caption=Label.new(); caption.position=Vector2(14,486); caption.size=Vector2(772,28); caption.add_theme_font_size_override("font_size",12); caption.theme=game.menus.theme; strip.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(caption)
	await phase("WINDOWED / OWNED REDLINE / NATIVE640 WORLD + EXTERNAL HUD",7,true)
	await feature("windows_single_meter")
	for id: String in ["dead_centre","impact_sink","orbit_drive"]:
		game.run_context._owned_power_ids.append(id); game.run_context._power_ranks[id]=2;
		if not game.battle.acquire_run_power(id,1) or not game.battle.acquire_run_power(id,2): failures.append("Sequential legal acquisition refused "+id)
	game.run_context._progression.level=7; game.battle.continuous.progression_level=7
	await phase("FIXTURE: FOUR LEGAL STATEFUL POWERS / METERS APPEAR IN SIDE MARGINS",8,false,true)
	await feature("windows_four_meters")
	var player: Dictionary=game.battle.player_entity()
	if game.battle.powers.redline_active(player): failures.append("Redline must naturally cool before the overcap fixture")
	# Declared QA initial state: start a real Rank-I activation, then place reserve
	# inside its legal cap once. Subsequent loss and expiry use the real solver.
	player.cooldown=0.0
	game.battle._attempt_burst(player,-Vector2(player.pos).normalized())
	player.rpm=1.11; player.energy=player.rpm
	game.battle._emit_hud()
	caption.text="FIXTURE: LEGAL 111% RESERVE / OVERDRIVE ON / OWNED METER REMAINS REDLINE"
	await feature("overdrive_on")
	await phase("ACTUAL REDLINE EXPIRY / EXCESS VENTS / OVERDRIVE LABEL CLEARS",5,false,false,false)
	await feature("overdrive_off")
	# Explicit late-arena admission fixture; AI, movement, collisions and bars
	# continue normally. This is layout evidence, never an earned boss reward.
	game.battle.elapsed=240.0
	game.battle.continuous.reward_fixture=true
	for entry: Array in [["anvil",Vector2(95,-55)],["hunter",Vector2(-90,70)]]:
		for row: Dictionary in Director.EVENTS:
			if row.key!=entry[0]: continue
			var event: Dictionary=row.duplicate(true)
			game.battle.continuous.director.serial+=1
			event["serial"]=game.battle.continuous.director.serial
			game.battle.continuous.director.active[int(event.serial)]={"time":game.battle.elapsed,"kind":event.kind}
			game.battle.continuous._admit(event,entry[1])
	await phase("INITIAL LATE-ARENA FIXTURE / ACTUAL BOSS + RIVAL RPM BARS",4,true,false,false)
	await feature("boss_rival_world_bars")
	game.menus.mobile_hud=true; game.top_status_bars.mobile_layout=true; game.touch_controls.show_controls=true
	await phase("ANDROID LAYOUT ON WINDOWS / HOLD-DRAG + RIGHT-MARGIN BURST-BRAKE",6,true,false,false)
	await feature("android_layout_four_meters")
	game.battle.set_paused(true); game.screen="battle"; game._pause(); game._settings_origin="pause"; game._show_settings()
	await phase("OPTIONS / TOP STATUS BARS ON / IMPACT NUMBERS OFF BY DEFAULT",3)
	var image: Image=root.get_texture().get_image(); var path: String=frames.path_join("options.png"); image.save_png(path); features.options={"path":path}
	var file:=FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"movie_frames":movie_frames,"nominal_seconds":movie_frames/60.0,"notes":notes,"features":features,"profile":profile,"scope":"Normal production Main/render/physics and mapped synthetic controls. Explicit legal invested loadout, one-time legal 111% reserve after a real Rank-I activation, and initial late-arena boss/rival admission are declared presentation fixtures, not earned balance evidence. Actual expiry/vent and live bars are observed without forcing outcomes. Caption strip is outside product canvas. Android cell is a Windows layout audit, not APK/device acceptance. Actual Windows fullscreen parity is in separate native regression."},"\t"))
	game.free(); print("HUD_LAYOUT_SHOWCASE_003A1_", "PASS" if failures.is_empty() else "FAIL"," frames=",movie_frames); quit(0 if failures.is_empty() else 1)
