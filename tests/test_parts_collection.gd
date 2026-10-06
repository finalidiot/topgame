extends SceneTree
## Expanded catalogue ownership, safe full-roster QA and actual focus scrolling.
## Uses isolated files only; gameplay outcomes are not fabricated here.

class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void:
		pass

const Parts = preload("res://scripts/parts.gd")
const Collection = preload("res://scripts/collection_save.gd")
const Starters = preload("res://scripts/starters.gd")
const NATIVE_RECT: Rect2 = Rect2(0, 0, 640, 360)
var checks: int = 0
var failures: int = 0
var files: Array[String] = []
var qa_folder: String
var real_before: Dictionary = {}
var capture_dir: String = ""

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func _path(label: String) -> String:
	var path: String = qa_folder.path_join("parts_collection_%d_%d_%s.json" % [OS.get_process_id(), Time.get_ticks_usec(), label])
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp", ".preferences.cfg", ".last_run_director.json"]:
		files.append(path + suffix)
	return path

func _game(path: String, catalogue_qa: bool = false) -> QuietMain:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = path
	game.qa_catalogue_requested = catalogue_qa
	root.add_child(game)
	game.set_process(false)
	game.battle.set_physics_process(false)
	return game

func _settle() -> void:
	await process_frame
	await process_frame

func _tap(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _settle()

func _navigate(target: Control) -> bool:
	# Catalogue rows now contain two cards. Follow the live focus graph with
	# real directional keys rather than assuming Right walks the whole list.
	check(target != null and target.is_visible_in_tree(), "Keyboard target is an actual visible catalogue control")
	if target == null or not target.is_visible_in_tree(): return false
	var origin: Control = root.gui_get_focus_owner()
	check(origin != null, "Keyboard catalogue navigation begins with visible focus")
	if origin == null: return false
	var frontier: Array[Control] = [origin]
	var paths: Dictionary = {origin:[]}
	var directions: Array[Key] = [KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN]
	while not frontier.is_empty() and not paths.has(target):
		var current: Control = frontier.pop_front()
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var next: Control = current.find_valid_focus_neighbor(side)
			if next == null or not next.is_visible_in_tree() or paths.has(next): continue
			var steps: Array = paths[current].duplicate()
			steps.append({"key":directions[int(side)], "control":next})
			paths[next] = steps
			frontier.append(next)
	check(paths.has(target), "Real keyboard focus graph reaches every active catalogue control")
	if not paths.has(target): return false
	for step: Dictionary in paths[target]:
		await _tap(step.key)
		check(root.gui_get_focus_owner() == step.control, "Actual directional key follows the explicit focus neighbour")
		if root.gui_get_focus_owner() != step.control: return false
	check(root.gui_get_focus_owner() == target, "Keyboard reaches the requested catalogue entry")
	return root.gui_get_focus_owner() == target

func _capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and image.save_png(capture_dir.path_join(name + ".png")) == OK, "Native catalogue review screenshot saved")

func _check_inspector(game: QuietMain, category: String, id: String) -> void:
	var data: Dictionary = Parts.PARTS[category][id]
	var metadata: Label = game.menus._catalogue_metadata
	var description: Label = game.menus._catalogue_description
	check(metadata.text.contains(str(data.name)) and metadata.text.contains(category.to_upper()) and metadata.text.contains(str(data.rarity)), "Focused part shows its full name, type and rarity")
	check(description.text == str(data.description), "Focused part's full physical description reaches the inspector")
	var font: Font = metadata.get_theme_font("font")
	var font_size: int = metadata.get_theme_font_size("font_size")
	check(font.get_string_size(metadata.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= metadata.size.x, "Part metadata fits the native inspector width")
	var height: float = 0.0
	for line: int in range(description.get_line_count()): height += description.get_line_height(line)
	height += maxi(0, description.get_line_count() - 1) * description.get_theme_constant("line_spacing")
	check(height <= description.size.y and description.get_visible_line_count() == description.get_line_count(), "Full physical description fits the native inspector without clipping")

func _check_preview_assets(game: QuietMain) -> void:
	var preview: Control = game.menus._preview
	for category: String in Collection.CATEGORIES:
		var id: String = str(game.collection.equipped_build()[category])
		var path: String = "res://assets/top/parts/%ss/%s%s.png" % [category, id, "_spin" if category == "blade" else ""]
		var texture: Texture2D = preview._texture(path)
		check(texture != null and texture.get_width() == (384 if category == "blade" else 48) and texture.get_height() == 48, "Every equipped preview layer loads its correctly sized runtime sprite: " + category + ":" + id)
		if texture != null:
			var image: Image = texture.get_image()
			check(image != null and not image.is_empty() and not image.is_invisible(), "Every equipped preview layer contains visible pixels: " + category + ":" + id)

func _test_ordinary_collections() -> void:
	for starter: String in Starters.IDS:
		var path: String = _path(starter)
		var save: RefCounted = Collection.new(path)
		save.load_save()
		check(bool(save.initialize_starter(starter).ok), "Starter initializes in the expanded catalogue: " + starter)
		check(save.owned_count() == 3, "Ordinary fresh starter owns exactly three permanent parts")
		var before: PackedByteArray = _bytes(path)
		var game: QuietMain = _game(path)
		check(game.collection.owned_count() == 3 and game.build == Starters.build_for(starter), "Existing starter profile loads without granting catalogue additions")
		game._garage()
		await _settle()
		for category: String in Collection.CATEGORIES:
			for id: String in Parts.PARTS[category]:
				check(game.collection.owns_part(category + ":" + id) == (Starters.build_for(starter)[category] == id), "Ownership follows the chosen starter, never rarity or catalogue position")
				var card: Button = game.menus._part_buttons[category][id]
				check(card.custom_minimum_size.x >= 120.0, "Expanded catalogue keeps readable card widths")
				check(card.get_meta("owned") == game.collection.owns_part(category + ":" + id), "Catalogue card ownership matches persistent state")
			var last: String = str(Parts.PARTS[category].keys().back())
			game.menus.focus_collection_part(category, last)
			await _settle()
			var focused: Control = root.gui_get_focus_owner()
			check(NATIVE_RECT.encloses(focused.get_global_rect()), "Focus automatically scrolls the far catalogue card into the native viewport")
			check(game.menus._part_scrolls[category].get_global_rect().encloses(focused.get_global_rect()), "Far-card focus is fully contained by its clipped strip")
			check(game.menus._catalogue_metadata.text.contains(str(Parts.PARTS[category][last].get("rarity", "COMMON"))), "Inspector exposes rarity text independently of part colour")
			check(game.menus._catalogue_description.text == str(Parts.PARTS[category][last].description), "Inspector gives the focused part's mechanical trade-off")
			game._action("inspect_locked_part", {"category":category, "id":last})
			game._action("equip_part", {"category":category, "id":last})
			check(game.collection.owned_count() == 3 and game.build == Starters.build_for(starter), "Locked inspection and equip attempts grant no parts")
		check(_bytes(path) == before, "Browsing the new catalogue preserves the existing starter save bytes")
		if starter == "breaker": await _capture("002c5_2_locked_catalogue_native")
		game.queue_free()
		await _settle()

func _test_isolated_qa() -> void:
	var game: QuietMain = _game(_path("full_qa"), true)
	var total: int = Parts.BLADE_IDS.size() + Parts.RATCHET_IDS.size() + Parts.BIT_IDS.size()
	check(game.qa_catalogue_error.is_empty() and game.collection.owned_count() == total, "Explicit isolated QA path owns the complete catalogue")
	check(game.preferences_path == game.collection_path + ".preferences.cfg", "Catalogue QA preferences use a neighbouring isolated file")
	game.smoke_mode = false
	game._save_preferences()
	game.smoke_mode = true
	check(FileAccess.file_exists(game.preferences_path), "The isolated preference write actually ran")
	game._garage()
	await _settle()
	for category: String in Collection.CATEGORIES:
		var first: String = str(Parts.PARTS[category].keys()[0])
		if await _navigate(game.menus._catalogue_tabs[category]): await _tap(KEY_ENTER)
		check(game.menus._catalogue_category == category, "Real keyboard activation opens the required catalogue category")
		for other: String in Collection.CATEGORIES:
			for card: Button in game.menus._part_buttons[other].values():
				check(card.is_visible_in_tree() == (other == category), "Only the active catalogue category is visible")
				check(card.focus_mode == (Control.FOCUS_ALL if other == category else Control.FOCUS_NONE), "Hidden category entries cannot steal live keyboard focus")
		var index: int = 0
		for id: String in Parts.PARTS[category]:
			await _navigate(game.menus._part_buttons[category][id])
			var focused: Control = root.gui_get_focus_owner()
			check(str(focused.get_meta("part_id")) == id, "Actual keyboard focus traverses catalogue order")
			check(NATIVE_RECT.encloses(focused.get_global_rect()), "Every traversed card is visible at native resolution")
			check(game.menus._part_scrolls[category].get_global_rect().encloses(focused.get_global_rect()), "Every keyboard-focused card is fully contained by its clipped catalogue")
			_check_inspector(game, category, id)
			await _tap(KEY_ENTER)
			check(game.collection.equipped_build()[category] == id, "Every QA part equips through the production collection API")
			_check_preview_assets(game)
			# Check the actual two-column contract separately from vertical travel.
			if index % 2 == 0:
				var ids: Array = Parts.PARTS[category].keys()
				var right_id: String = str(ids[mini(index + 1, ids.size() - 1)])
				await _tap(KEY_RIGHT)
				check(str(root.gui_get_focus_owner().get_meta("part_id")) == right_id, "Right selects the neighbouring grid column, or stays in the unpaired final row")
				await _tap(KEY_LEFT)
				check(str(root.gui_get_focus_owner().get_meta("part_id")) == id, "Left returns through the same native catalogue row")
			index += 1
		# Tab traverses the real footer/category controls, then wraps to the
		# first entry. Horizontal row wrapping must not fake linear scrolling.
		for step: int in range(game.menus._catalogue_footer.size() + game.menus._catalogue_tabs.size() + 1): await _tap(KEY_TAB)
		check(str(root.gui_get_focus_owner().get_meta("part_id")) == first, "Tab navigation wraps through the entire view and scrolls to the first catalogue card")
		check(game.menus._part_scrolls[category].get_global_rect().encloses(root.gui_get_focus_owner().get_global_rect()), "Wrapped first-card focus is fully visible in the native catalogue")
	await _capture("002c5_2_isolated_catalogue_native")
	var chosen: Dictionary = game.collection.equipped_build()
	game._action("launch_owned_run")
	check(game.run_context.selected_build == chosen and game.screen == "reward", "An isolated mixed catalogue assembly starts the real Run draft")
	game._action("choose_power", {"encounter_id":game.run_context.pending_draft_id, "run_seed":game.run_context.run_seed, "power_id":game.run_context.pending_offer[0]})
	game._process(1.2)
	game.battle.set_physics_process(false)
	var player: Dictionary = game.battle.player_entity()
	check(game.screen == "battle" and player.get("build", {}) == chosen, "Expanded QA assembly reaches actual continuous battle physics")
	game._pause()
	game._action("end_run")
	var save: RefCounted = Collection.new(game.collection_path)
	save.load_save()
	check(save.owned_count() == total and save.equipped_build() == chosen, "The full isolated catalogue assembly reloads correctly")
	game.queue_free()
	await _settle()

func _test_refused_qa() -> void:
	for invalid: String in ["", Collection.DEFAULT_PATH, "res://collection.json", ProjectSettings.globalize_path(Collection.DEFAULT_PATH), qa_folder.get_base_dir().path_join("outside_temp.json"), qa_folder.path_join("../escaped.json")]:
		var game: QuietMain = _game(invalid, true)
		check(not game.qa_catalogue_error.is_empty() and game.screen == "collection_error", "Unsafe or missing catalogue QA path is explicitly refused")
		check(game.collection.read_only and game.collection.owned_count() == 0, "Refused QA grants nothing and cannot initialize another collection")
		check(not FileAccess.file_exists(game.collection_path), "Refused QA never writes its fallback state")
		game._action("settings_changed", {"muted":true})
		check(not FileAccess.file_exists(game.preferences_path), "Refused QA does not write preferences")
		game.queue_free()
		await _settle()

func _run() -> void:
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(640, 360)
	Input.use_accumulated_input = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	var project_folder: String = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var qa_root: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa_root.is_empty(): qa_root = project_folder.get_base_dir().path_join("GyroBrothers-QA")
	qa_folder = qa_root.path_join("002C.5.2/temp")
	DirAccess.make_dir_recursive_absolute(qa_folder)
	for path: String in ["user://collection.json", "user://collection.json.bak", "user://prototype.cfg", "user://last_run_director.json"]:
		real_before[path] = _bytes(path)
	await _test_ordinary_collections()
	await _test_isolated_qa()
	await _test_refused_qa()
	for path: String in real_before:
		check(_bytes(path) == real_before[path], "The real player's collection, backup, preferences and Run diagnostic bytes remain intact")
	for path: String in files:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("PARTS_COLLECTION_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
