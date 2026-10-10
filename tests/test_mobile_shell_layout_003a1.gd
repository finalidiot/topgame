extends SceneTree
## Actual production nested surface, with root-screen event dispatch. Isolated
## wallet/initial Duel and small-window fixtures; no physical phone/button claim.
const Shell = preload("res://scripts/mobile_shell.gd")
const Battle = preload("res://scripts/battle.gd")
const Touch = preload("res://scripts/touch_controls.gd")
const Save = preload("res://scripts/collection_save.gd")
const Economy = preload("res://scripts/packet_economy.gd")
class IsolatedShell extends "res://scripts/mobile_shell.gd":
	func _ready() -> void: pass
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass
var report: String = ""
var profile: String = ""
var native: bool = false
var checks: int = 0
var failures: Array[String] = []
var shell: IsolatedShell
var game: QuietMain
var events: Array[Dictionary] = []
var fits: Array[Dictionary] = []
var observations: Array[Dictionary] = []
var packet_cases: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func settle() -> void:
	await process_frame; await process_frame; await process_frame
func valid_paths() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
		if arg.begins_with("--profile="): profile = arg.trim_prefix("--profile=")
		if arg == "--native": native = true
		if arg.begins_with("--collection-path=") or arg in ["--smoke-test", "--qa-catalogue", "--reset-collection"]:
			push_error("Main boot overrides refused before creating a fixture"); return false
	var qa: String = "gyrobrothers-qa/003a.2/" if report.replace("\\", "/").to_lower().contains("gyrobrothers-qa/003a.2/manifests/") else "gyrobrothers-qa/003a.1/"
	if not report.is_absolute_path() or not report.replace("\\", "/").to_lower().contains(qa + "manifests/") or FileAccess.file_exists(report):
		push_error("A fresh external QA report is required"); return false
	if not profile.is_absolute_path() or not profile.replace("\\", "/").to_lower().contains(qa + "temp/"):
		push_error("A fresh isolated external QA profile is required"); return false
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp", ".preferences.cfg", ".last_run_director.json"]:
		if FileAccess.file_exists(profile + suffix): push_error("Existing fixture preserved: " + profile + suffix); return false
	return true

func fit_contracts() -> void:
	check(Shell.NATIVE == Vector2i(800, 480), "Mobile outer canvas contains the complete800x480 HUD")
	for available: Rect2i in [Rect2i(0,0,1280,720), Rect2i(80,0,1760,1080), Rect2i(90,36,2220,1044),
		Rect2i(0,0,2560,1440), Rect2i(12,0,788,480), Rect2i(10,20,600,360), Rect2i(3,4,479,271),
		Rect2i(0,0,5,3), Rect2i(0,0,0,0)]:
		var fit: Rect2i = Shell.fit_surface(available)
		check(available.encloses(fit), "Cutout-safe fit never crops the canvas: " + str(available))
		check(fit.size.x * 3 == fit.size.y * 5, "Canvas preserves exact5:3 aspect even below native extent")
		if available.size.x >= 800 and available.size.y >= 480:
			check(fit.size.x % 800 == 0 and fit.size.y % 480 == 0, "Fitting surfaces retain whole authored pixels")
			check(fit.size.x / 800 == mini(available.size.x / 800, available.size.y / 480), "Largest bounded integer multiple is selected")
		else:
			check(fit.size.x <= 800 and fit.size.y <= 480, "Undersized fit is uniformly bounded instead of forced native clipping")
		fits.append({"available":available,"fit":fit,"integer_native_fit":available.size.x >= 800 and available.size.y >= 480})

func root_point(point: Vector2) -> Vector2:
	return shell.surface.get_global_transform_with_canvas() * point
func root_touch(point: Vector2, pressed: bool, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index; event.position = root_point(point); event.pressed = pressed
	events.append({"type":"touch", "index":index, "pressed":pressed, "native_point":point, "root_point":event.position,
		"surface_scale":shell.surface.scale, "screen":game.screen})
	Input.parse_input_event(event)
	await settle()
func root_drag(point: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index; event.position = root_point(point)
	events.append({"type":"drag", "index":index, "native_point":point, "root_point":event.position,
		"surface_scale":shell.surface.scale, "screen":game.screen})
	Input.parse_input_event(event)
	await settle()
func descendants(node: Node) -> Array:
	var result: Array = []
	for child: Node in node.get_children():
		result.append(child); result.append_array(descendants(child))
	return result
func menu_button(intent: String) -> Button:
	for node: Node in descendants(game.menus):
		if node is Button and node.is_visible_in_tree() and not node.disabled and str(node.get_meta("intent", "")) == intent:
			return node
	return null
func tap_menu(intent: String) -> void:
	var button: Button = menu_button(intent)
	check(is_instance_valid(button), "Actual centred menu target exists: " + intent)
	if not is_instance_valid(button): return
	var point: Vector2 = button.get_global_rect().get_center()
	check(Rect2(Vector2.ZERO,Vector2(Shell.NATIVE)).has_point(point), "Menu target remains inside complete native canvas")
	await root_touch(point, true, 4); await root_touch(point, false, 4)

func resize_surface(dimensions: Vector2i) -> void:
	root.size = dimensions
	await settle()
	shell._fit()
	await settle()
	check(shell.game_view.size == Vector2i(800,480), "Outer native SubViewport does not change with physical surface size")
	check(game.get_viewport() == shell.game_view and game.combat_viewport.size == Vector2i(640,360), "Actual nested Main hosts a separate canonical640x360 Battle")
	check(game.combat_frame.position == Vector2(80,60) and game.combat_frame.size == Vector2(640,360), "Arena projection is placed in the complete HUD canvas at80,60")
	check(shell.surface.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and game.combat_frame.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Both nested texture surfaces retain nearest-neighbour presentation")
	var actual: Rect2 = shell.surface.get_global_rect()
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(actual), "Actual scaled container stays within the available window")
	check(is_equal_approx(shell.surface.scale.x, shell.surface.scale.y), "Nested surface scales uniformly")
	if dimensions.x >= 800 and dimensions.y >= 480:
		check(is_equal_approx(shell.surface.scale.x, floorf(shell.surface.scale.x)), "Available native extent uses a whole scale")
	else: check(shell.surface.scale.x < 1.0 and shell.surface.scale.x > 0.0, "Actual declared undersized window retains the complete HUD")
	observations.append({"requested_window":dimensions, "actual_window":root.size, "surface_rect":actual,
		"surface_scale":shell.surface.scale, "outer_native":shell.game_view.size, "combat_native":game.combat_viewport.size,
		"arena_origin":game.combat_frame.position,"menu_origin":game.menus._content.position,"renderer":DisplayServer.get_name()})

func menu_contracts() -> void:
	game._title(); await settle()
	check(game.menus._content.position == Vector2(80,60), "Actual menu keeps its centred native origin in the nested canvas")
	await tap_menu("settings")
	check(game.screen == "settings", "Root-screen touch passes through the scaled container to the actual Options button")
	await tap_menu("back_settings")
	check(game.screen == "title", "Root-screen touch reaches the low native Back row without canvas clipping")

func gameplay_contracts() -> void:
	game._start_battle("duel"); game.battle.set_physics_process(false); game._process(0.0)
	for tick: int in range(240):
		if game.battle.battle_status == "battle": break
		game.battle._physics_process(Battle.FIXED_DT)
	check(game.battle.battle_status == "battle" and game.touch_controls.enabled, "Declared Duel completes its actual countdown with the Main input provider")
	# Countdown completion precedes the normal sampled HUD update. Advance real
	# live ticks so the native parity check does not compare a held LAUNCH label
	# from an artificially stopped fixture against the completed battle raster.
	for tick: int in range(8): game.battle._physics_process(Battle.FIXED_DT)
	await root_touch(Vector2(200,180), true)
	check(game.touch_controls.steering_finger == 0 and game.touch_controls.origin.is_equal_approx(Vector2(200,180)), "Root-screen touch is forwarded into the real Main touch provider in native coordinates")
	await root_drag(Vector2(230,192))
	var prepared: Vector2 = game.touch_controls.direction
	check(prepared.x > 0.0 and prepared.y > 0.0 and prepared.length() < 1.0, "Scaled root-screen drag retains analogue direction and magnitude")
	await root_touch(Touch.BURST_RECT.get_center(), true, 1)
	await root_touch(Touch.BRAKE_RECT.get_center(), true, 2)
	var sample: Dictionary = game.touch_controls.sample()
	check(game.touch_controls.owners.size() == 3 and sample.direction == prepared and sample.burst and sample.brake, "Steering and both margin actions arrive as three independent actual viewport fingers")
	var player: Dictionary = game.battle.player_entity()
	var rpm: float = player.rpm
	game.battle._physics_process(Battle.FIXED_DT)
	check(float(player.cooldown) > 3.9 and float(player.rpm) < rpm - 0.01, "Forwarded Burst is consumed by the real solver once and spends RPM")
	await root_touch(Touch.BURST_RECT.get_center(), false, 1)
	check(game.touch_controls.action_down("brake") and game.touch_controls.direction == prepared, "Releasing one forwarded action preserves both other fingers")
	await root_touch(Touch.BRAKE_RECT.get_center(), false, 2)
	await root_touch(Vector2(230,192), false)
	check(game.touch_controls.owners.is_empty() and game.touch_controls.direction == Vector2.ZERO, "Forwarded releases cleanly neutralise real ownership")
	await root_touch(Vector2(20,180), true, 3)
	check(game.touch_controls.owners.is_empty(), "Actual side HUD margin cannot acquire a steering finger")
	await root_touch(Vector2(20,180), false, 3)

func packet_contract(quantity: int, local: Vector2, direction: float) -> void:
	game._title(); await settle()
	var random := RandomNumberGenerator.new(); random.seed = 7341 + quantity
	var wallet: int = int(game.collection.wallet().credits)
	var purchased: Dictionary = game.collection.purchase_packet_batch("standard", quantity, random)
	check(purchased.ok, "Isolated paid x%d batch persists before nested presentation" % quantity)
	if not purchased.ok: return
	game._show_packet(false); await settle()
	check(game.screen == "packet_open" and game.menus._packet_view._quantity == quantity, "Actual Main displays the purchased batch")
	game.menus._packet_view.set_process(false)
	var fixed_rows: Array = game.collection.pending_packet().rows.duplicate(true)
	var point: Vector2 = game.menus._content.get_global_transform_with_canvas() * local
	await root_touch(point, true, 4)
	check(game.menus._packet_touch_index == 4, "Scaled touch on the visible x%d outer pouch acquires the actual gesture" % quantity)
	check(game.menus._packet_touch_origin.is_equal_approx(local), "Nested viewport and centred menu transforms recover exact native pouch coordinates")
	await root_drag(point + Vector2(41.5 * direction,0), 4)
	check(not game.menus._packet_view.opening, "Scaled fan gesture below42nativepixels does not tear")
	await root_drag(point + Vector2(42.0 * direction,0), 4)
	check(game.menus._packet_view.opening and game.menus._packet_touch_index == -1, "Exactly42nativepixels tears the actual batch once")
	await root_touch(point + Vector2(42.0 * direction,0), false, 4)
	game.menus._packet_view._process(8.0); await settle()
	check(game.menus._packet_view.phase == "RESULT", "Actual batch timeline reaches its terminal result")
	check(game.collection.pending_packet().rows == fixed_rows and game.collection.wallet().credits == wallet - Economy.packet_cost("standard") * quantity, "Nested fan gesture preserves all paid rows and never spends twice")
	packet_cases.append({"quantity":quantity,"native_pouch_point":local,"root_pouch_point":root_point(point),"surface_scale":shell.surface.scale,
		"native_drag_threshold":42,"phase":game.menus._packet_view.phase,"paid_rows":fixed_rows.size(),"scope":"Real isolated purchase/finalize/cursor writes; declared wallet and clock-step fixture, mapped root-screen gesture"})
	game._leave_packet("hub"); await settle()

func capture_native(label: String) -> void:
	if not native: return
	await settle(); await RenderingServer.frame_post_draw
	var outer: Image = shell.game_view.get_texture().get_image()
	var combat: Image = game.combat_viewport.get_texture().get_image()
	check(outer.get_size() == Vector2i(800,480) and combat.get_size() == Vector2i(640,360), "Actual nested native textures include the complete HUD and original combat raster")
	var crop: Image = outer.get_region(Rect2i(80,60,640,360))
	check(crop.get_data() == combat.get_data(), "Nested native composite retains exact canonical combat RGBA")
	var folder: String = report.get_base_dir().get_base_dir().path_join("frames/" + report.get_file().get_basename())
	check(DirAccess.make_dir_recursive_absolute(folder) == OK, "Unique native nested-surface evidence folder")
	var path: String = folder.path_join(label + ".png")
	check(not FileAccess.file_exists(path) and root.get_texture().get_image().save_png(path) == OK, "Fresh actual scaled native surface capture")
	observations[-1]["native_capture"] = path

func run() -> void:
	if not valid_paths(): quit(2); return
	if native and DisplayServer.get_name() == "headless": push_error("Native review requires an actual renderer"); quit(2); return
	fit_contracts()
	Input.use_accumulated_input = false
	# Declared isolated starter/wallet state. It never opens a default Main/save.
	var fixture = Save.new(profile)
	check(fixture.load_save().ok and fixture.initialize_starter("bastion").ok, "Fresh isolated starter owns its actual assembly")
	var initial: Dictionary = fixture._data.duplicate(true); initial.progression.credits = 10000
	check(fixture._commit(initial,"qa_nested_surface_wallet").ok, "Explicit isolated wallet permits actual batch transactions")
	game = QuietMain.new(); game.smoke_mode = true; game.collection_path = profile; game.preferences_path = profile + ".preferences.cfg"
	game.settings.muted = true; game.settings.screen_shake = false
	shell = IsolatedShell.new(); root.add_child(shell)
	root.min_size = Vector2i(160,96) # QA undersize fixture, not a product project change.
	shell.mount_mobile_surface(game); await settle()
	check(game.collection.save_path == profile and game.preferences_path == profile + ".preferences.cfg", "Native shell mounts only the supplied isolated Main and its preference path")
	for dimensions: Vector2i in [Vector2i(800,480),Vector2i(1600,960),Vector2i(600,360)]:
		await resize_surface(dimensions)
		await menu_contracts(); await gameplay_contracts()
		await capture_native("surface_%dx%d" % [dimensions.x,dimensions.y])
	await resize_surface(Vector2i(1600,960))
	await packet_contract(3,Vector2(206,190),-1.0)
	await packet_contract(5,Vector2(484,190),1.0)
	var file := FileAccess.open(report,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":DisplayServer.get_name(),"native":native,"fits":fits,"observations":observations,"input_events":events,"packet_cases":packet_cases,
		"scope":"Production mount_mobile_surface with isolated QuietMain, actual nested800x480-to640x360 viewport composition and root Input.parse_input_event forwarding. Starter/wallet/Duel/small-window/packet-clock fixtures are explicit. Logical touch events are not physical phone acceptance.",
		"profile":profile,"physical_android_acceptance":false,"direct_router_input_calls":0},"\t")); file.close()
	shell.free()
	print("MOBILE_SHELL_LAYOUT_003A1_%s checks=%d failures=%d native=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures.size(),native])
	quit(0 if failures.is_empty() else 1)
