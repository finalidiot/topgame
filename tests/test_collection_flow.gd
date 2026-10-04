extends SceneTree
## Real Main/Run/collection integration. Defeat is an explicit screen-flow
## fixture; combat pacing is covered by the accepted natural-Run diagnostics.

class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void:
		pass

const Parts = preload("res://scripts/parts.gd")
const Starters = preload("res://scripts/starters.gd")
const Collection = preload("res://scripts/collection_save.gd")
const Fixtures = preload("res://tests/continuous_fixtures.gd")
const CATEGORIES: Array[String] = ["blade", "ratchet", "bit"]
var checks: int = 0
var failures: int = 0
var test_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _game(path: String, explicit_reset: bool = false) -> QuietMain:
	var game: QuietMain = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = path
	game.reset_collection_requested = explicit_reset
	root.add_child(game)
	game.battle.set_physics_process(false)
	return game

func _path(label: String) -> String:
	var path: String = "user://task003a-tests/flow-%d-%d-%s.json" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	test_paths.append(path)
	return path

func _raw(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func _claim_opening(game: QuietMain) -> void:
	check(game.screen == "reward" and game.run_context.pending_draft_kind == "starting", "Owned Run opens a temporary starting-power draft")
	if game.run_context.pending_offer.is_empty(): return
	var power: String = str(game.run_context.pending_offer[0])
	game._action("choose_power", {"encounter_id":game.run_context.pending_draft_id, "run_seed":game.run_context.run_seed, "power_id":power})
	game._process(1.2)
	game.battle.set_physics_process(false)
	check(game.screen == "battle" and game.run_context.owned_power_ids == [power], "Opening power launches the owned machine")

func _check_initial_ownership(game: QuietMain, starter: String) -> void:
	var expected: Dictionary = Starters.build_for(starter)
	check(game.collection.is_initialized() and game.collection.starter_id == starter, "Historical first choice is saved: "+starter)
	check(game.collection.owned_count() == 3, "Exactly three starter components are owned: "+starter)
	check(game.collection.equipped_build() == expected and game.build == expected, "Complete starter assembly is equipped: "+starter)
	var ids: Array = game.collection.owned_parts()
	var unique: Dictionary = {}
	for id: String in ids: unique[id] = true
	check(unique.size() == 3 and ids.size() == 3, "Ownership IDs are unique: "+starter)
	for category: String in CATEGORIES:
		check(game.collection.owned_parts(category) == [expected[category]], "Only selected %s is owned for %s" % [category, starter])
		for part_id: String in Parts.PARTS[category]:
			check(game.collection.owns_part(category+":"+part_id) == (part_id == str(expected[category])), "Catalogue ownership matches %s %s" % [starter, category+":"+part_id])
	for other: String in Starters.IDS:
		if other == starter: continue
		var other_build: Dictionary = Starters.build_for(other)
		for category: String in CATEGORIES:
			check(not game.collection.owns_part(category+":"+str(other_build[category])), "Unchosen starter component remains unowned: %s %s" % [other, category])
	check(game.collection.can_equip_build(expected), "Starting machine is legal and launchable")
	check(Starters.identity_for_build(expected) == starter, "Exact authored assembly retains its current handling identity")

func _test_starter(starter: String) -> void:
	var path: String = _path(starter)
	var game: QuietMain = _game(path)
	check(game.screen == "title" and not game.collection.is_initialized(), "Missing collection begins at fresh title: "+starter)
	check(game.collection.owned_count() == 0 and not FileAccess.file_exists(path), "New player starts with no owned parts or fabricated save")
	game._action("begin_collection")
	check(game.screen == "starter_ceremony" and game.run_context.status == "empty", "Begin opens first-save ceremony before generating a Run")
	game._action("select_first_starter", starter)
	check(game.screen == "starter_confirm" and not game.collection.is_initialized(), "First selection asks for confirmation without granting parts")
	game._action("back_to_starters", starter)
	check(game.screen == "starter_ceremony" and game.collection.owned_count() == 0, "Back reverses an unconfirmed first choice")
	game._action("select_first_starter", starter)
	game._action("confirm_first_starter", starter)
	check(game.screen == "starter_owned" and FileAccess.file_exists(path), "Successful confirmation saves ownership before its presentation")
	_check_initial_ownership(game, starter)
	var owned: Dictionary = game.collection.snapshot().duplicate(true)
	var saved: String = _raw(path)
	game._action("confirm_first_starter", Starters.IDS[(Starters.IDS.find(starter)+1)%3])
	check(game.collection.snapshot() == owned, "Repeated/stale starter confirmation cannot replace permanent first choice")
	game._action("finish_ownership")
	check(game.screen == "starter_owned", "Ownership beat cannot be immediately skipped by held confirmation")
	game._process(1.5)
	check(game.screen == "garage" and game.menus.screen == "collection_workshop", "Ownership moment enters the collection Workshop")
	check(game.run_context.status == "empty" and game.collection.snapshot() == owned, "Workshop arrival has no temporary Run state or additional grants")
	var locked: Dictionary = Starters.build_for(Starters.IDS[(Starters.IDS.find(starter)+1)%3])
	game._action("equip_part", {"category":"blade", "id":locked.blade})
	game._action("build_changed", locked)
	check(game.build == Starters.build_for(starter) and game.collection.snapshot() == owned, "Unowned direct/stale equip requests fail without changing the machine")
	game._action("launch_owned_run")
	check(game.screen == "reward" and game.run_context.selected_build == Starters.build_for(starter), "Workshop launches its owned assembly directly, without another starter choice")
	check(game.run_context.starter_id == starter, "Run identity is derived from the currently equipped complete assembly")
	_claim_opening(game)
	check(game.battle.player_entity().build == Starters.build_for(starter), "The exact permanently equipped machine reaches combat")
	check(game.battle.player_entity().starter_id == starter, "The first machine preserves its accepted handling and visuals")
	check(game.collection.snapshot() == owned and _raw(path) == saved, "Temporary opening power never rewrites collection data")
	Fixtures.defeat_player(game)
	check(game.screen == "result" and game.run_context.status == "failed", "Player defeat still ends the Run")
	check(game.collection.snapshot() == owned and _raw(path) == saved, "Run defeat preserves all permanent ownership and equipped components")
	var previous_seed: int = game.run_context.run_seed
	game._action("restart_run")
	check(game.screen == "reward" and game.run_context.run_seed != previous_seed, "Restart creates a fresh Run directly from the equipped machine")
	check(game.run_context.owned_power_ids.is_empty() and game.run_context.power_ranks.is_empty() and game.run_context.power_mutations.is_empty(), "Restart removes temporary powers, ranks and mutations")
	check(game.run_context.level == 1 and game.run_context.xp == 0, "Restart removes temporary XP and level")
	check(game.collection.snapshot() == owned and _raw(path) == saved, "Restart cannot erase or grow permanent ownership")
	_claim_opening(game)
	game._pause()
	game._action("end_run")
	check(game.screen == "garage" and game.run_context.status == "empty", "End Run returns to the same Workshop")
	_check_initial_ownership(game, starter)
	var json: Variant = JSON.parse_string(_raw(path))
	check(json is Dictionary, "Persisted collection is valid JSON")
	for forbidden: String in ["owned_power_ids", "power_ranks", "power_mutations", "pending_offer", "enemies", "survival_time", "rpm"]:
		check(not _raw(path).contains('"'+forbidden+'"'), "Temporary state is absent from collection: "+forbidden)
	game._action("main_menu")
	check(game.screen == "title", "Owned collection safely returns to title")
	game.queue_free()
	await process_frame
	game = _game(path)
	check(game.screen == "title" and game.collection.is_initialized(), "A new application instance loads the permanent collection")
	_check_initial_ownership(game, starter)
	game._action("begin_collection")
	check(game.screen == "garage", "Initialized normal title route skips the first-save ceremony")
	game._action("start_run")
	check(game.screen == "reward" and game.run_context.selected_build == owned.equipped_build, "Normal Run restart after application reload uses the persisted machine")
	game._pause()
	game._action("end_run")
	game.queue_free()
	await process_frame

func _test_future_build_and_practice() -> void:
	var path: String = _path("future")
	var game: QuietMain = _game(path)
	check(game.collection.initialize_starter("breaker").ok, "Future API scenario creates an actual first starter save")
	game._garage()
	var before: Dictionary = game.collection.snapshot().duplicate(true)
	var saved: String = _raw(path)
	game._action("quick_duel")
	check(game.mode == "duel" and game.screen == "battle", "Quick Duel remains available as separate practice")
	check(game.collection.snapshot() == before and _raw(path) == saved, "Practice combat cannot grant its player/opponent components")
	game._pause()
	game._action("main_menu")
	game._start_build_practice("counterweight")
	check(game.screen == "battle" and game.battle.player_entity().starter_id == "bastion", "Broad authored practice builds remain usable without owning their parts")
	check(game.collection.snapshot() == before and _raw(path) == saved, "Signature practice does not acquire Bastion parts or powers")
	game._pause()
	game._action("customize")
	check(game.screen == "garage" and game.build == game.collection.equipped_build(), "Leaving a practice preset restores the real equipped owned machine in the Workshop")
	var grant: Dictionary = game.collection.grant_part("blade:balance")
	check(grant.ok and grant.status == "newly_acquired", "A future reward can grant an ordinary catalogue component")
	var duplicate: Dictionary = game.collection.grant_part("blade:balance")
	check(duplicate.ok and duplicate.status == "already_owned" and game.collection.owned_count() == 4, "Duplicate reward reports ownership without adding another record")
	var mixed: Dictionary = Starters.build_for("breaker")
	mixed.blade = "balance"
	check(game.collection.equip_build(mixed).ok, "Future acquired parts can be combined into a legal owned build")
	game._garage()
	check(game.build == mixed and game.collection.starter_id == "breaker", "Current construction can differ from historical first starter")
	check(game.menus._preview.identity.is_empty(), "Mixed construction clears the original starter skin and motion identity")
	check(Starters.identity_for_build(mixed) == "custom", "Mixed physical build cannot inherit a historical starter class bonus")
	game._action("launch_owned_run")
	_claim_opening(game)
	check(game.run_context.starter_id == "custom" and game.battle.player_entity().starter_id == "custom", "Mixed construction reaches combat with neutral assembly handling")
	check(game.battle.player_entity().build == mixed and game.collection.owned_count() == 4, "Run launch cannot rebuild the player's original starter or grant extra parts")
	game._pause()
	game._action("end_run")
	game.queue_free()
	await process_frame
	var reloaded = Collection.new(path)
	check(reloaded.load_save().ok and reloaded.equipped_build() == mixed, "Future legal mixed construction survives save/load")
	check(reloaded.starter_id == "breaker" and reloaded.owned_count() == 4, "Save keeps historical choice separate from current construction")
	check(not reloaded.reset_collection().ok and reloaded.is_initialized(), "Collection reset requires explicit developer intent")
	check(reloaded.reset_collection(true).ok, "Explicit development reset removes only this isolated collection")
	game = _game(path)
	check(not game.collection.is_initialized() and game.collection.owned_count() == 0, "A reset application returns to genuine empty ownership")
	game._action("begin_collection")
	check(game.screen == "starter_ceremony", "Explicit reset permits first-save ceremony testing again")
	game.queue_free()
	await process_frame

func _test_reset_and_blocked_flow() -> void:
	var path: String = _path("explicit-main-reset")
	var fixture = Collection.new(path)
	fixture.load_save()
	check(fixture.initialize_starter("vane").ok, "Reset fixture owns a genuine saved Vane assembly")
	var preferences_path: String = path + ".prototype.cfg"
	test_paths.append(preferences_path)
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("settings", "volume", 0.37)
	preferences.set_value("settings", "screen_shake", false)
	preferences.set_value("build", "blade", "guard")
	check(preferences.save(preferences_path) == OK, "Isolated old-prototype preferences fixture is saved")
	var preferences_bytes: String = _raw(preferences_path)
	var game: QuietMain = _game(path)
	check(not game.reset_collection_requested and game.collection.starter_id == "vane", "Default application startup cannot reset a valid collection")
	game.queue_free()
	await process_frame
	game = _game(path, true)
	check(game.reset_collection_requested and not game.collection.is_initialized() and game.collection.owned_count() == 0, "Only explicit reset request enters Main's collection reset path")
	check(_raw(preferences_path) == preferences_bytes, "Collection reset preserves unrelated prototype preferences")
	game._action("begin_collection")
	check(game.screen == "starter_ceremony", "Explicit reset allows a real first-save ceremony")
	game.queue_free()
	await process_frame
	for kind: String in ["corrupt", "future"]:
		var blocked_path: String = _path(kind)
		var bytes: String = '{"schema_version":' if kind == "corrupt" else JSON.stringify({"schema_version":99,"starter_selected":"breaker","owned_part_ids":["blade:smash","ratchet:high","bit:flat"],"equipped_build":Starters.build_for("breaker")})
		var file: FileAccess = FileAccess.open(blocked_path, FileAccess.WRITE)
		file.store_string(bytes)
		file.close()
		game = _game(blocked_path)
		check(game.collection.read_only and not game.collection.can_launch(), "Unsafe %s data blocks normal mutation/launch" % kind)
		game._action("begin_collection")
		check(game.screen == "collection_error", "Unsafe %s data shows a restrained recovery message" % kind)
		game._action("select_first_starter", "bastion")
		game._action("confirm_first_starter", "bastion")
		game._action("launch_owned_run")
		game._action("start_run")
		check(game.screen == "collection_error" and game.run_context.status == "empty", "Blocked data cannot be bypassed with stale ceremony/Run actions")
		check(_raw(blocked_path) == bytes and game.collection.owned_count() == 0, "Blocked %s file remains intact without secretly granting a catalogue" % kind)
		game.queue_free()
		await process_frame

func _test_stale_window_flow() -> void:
	var path: String = _path("two-fresh-windows")
	var first: QuietMain = _game(path)
	var second: QuietMain = _game(path)
	check(not first.collection.is_initialized() and not second.collection.is_initialized(), "Two windows may inspect the same genuinely fresh collection")
	first._action("begin_collection")
	first._action("select_first_starter", "breaker")
	first._action("confirm_first_starter", "breaker")
	check(first.screen == "starter_owned" and first.collection.owned_count() == 3, "The first window successfully commits its chosen machine")
	var committed: String = _raw(path)
	second._action("begin_collection")
	second._action("select_first_starter", "bastion")
	second._action("confirm_first_starter", "bastion")
	check(second.screen == "collection_error" and second.collection.read_only, "A stale second-window confirmation displays an error instead of false ownership")
	check(second.collection.owned_count() == 0 and not second.collection.is_initialized(), "Rejected stale choice acquires no replacement components")
	check(_raw(path) == committed, "Stale starter confirmation cannot overwrite the winning first choice")
	second._action("retry_collection")
	check(second.screen == "garage" and not second.collection.read_only, "Retry safely reloads the latest collection into Workshop")
	check(second.collection.starter_id == "breaker" and second.collection.owned_count() == 3 and second.build == Starters.build_for("breaker"), "Reloaded second window respects the actual first owner's machine")
	check(second.run_context.status == "empty" and _raw(path) == committed, "Retry reloads ownership without starting a Run or writing grants")
	first.queue_free()
	second.queue_free()
	await process_frame
func _run() -> void:
	for starter: String in Starters.IDS: await _test_starter(starter)
	await _test_future_build_and_practice()
	await _test_reset_and_blocked_flow()
	await _test_stale_window_flow()
	for path: String in test_paths:
		for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("COLLECTION_FLOW_TEST_%s checks=%d failures=%d all_starters=3 isolated_saves=true" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
