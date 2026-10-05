extends "res://tests/test_collection_flow.gd"
## The actual first-choice/save/owned-launch route with normal seeded opening
## offers. Rank II/III installation is an explicit live-upgrade integration
## fixture, not claimed as earned progression or natural-combat evidence.
const C5Powers = preload("res://scripts/run_powers.gd")
const C5Context = preload("res://scripts/run_context.gd")
var rows: Array[Dictionary] = []
var entropy: int = 1

func opening_seed(power: String) -> int:
	for candidate: int in range(entropy, entropy + 4096):
		var random = RandomNumberGenerator.new()
		random.seed = candidate
		var probe = C5Context.new()
		probe.start(Starters.build_for("bastion"), random.randi(), "bastion")
		if power in probe.pending_offer:
			entropy = candidate + 1
			return candidate
	check(false, "Find a legitimate seeded opening offer for " + power)
	return entropy

func owned_launch(game: QuietMain, power: String, branch: String = "") -> void:
	game.rng.seed = opening_seed(power)
	var before: Dictionary = game.collection.snapshot().duplicate(true)
	var disk: String = _raw(game.collection_path)
	game._action("launch_owned_run")
	check(game.screen == "reward" and power in game.run_context.pending_offer, "Owned machine gets an ordinary C5 seeded opening offer: " + power)
	check("second_wind" not in game.run_context.pending_offer, "Retired comeback family stays out of owned opening drafts")
	game._action("choose_power", {"encounter_id":game.run_context.pending_draft_id,"run_seed":game.run_context.run_seed,"power_id":power})
	game._process(1.2)
	game.battle.set_physics_process(false)
	var b: Node2D = game.battle
	var p: Dictionary = b.player_entity()
	var identity: Dictionary = p
	var runtime_id: int = b.powers.get_instance_id()
	check(game.screen == "battle" and game.run_context.owned_power_ids == [power], "Actual opening selection launches the owned machine: " + power)
	check(p.build == before.equipped_build and p.starter_id == "bastion", "Owned parts and authored handling reach the C5 battle unchanged")
	check(b.continuous != null and b.powers._modern(p), "Owned collection launch selects modern continuous ability rules")
	check(b.powers.rank(p, power) == 1 and p.powers == [power], "Opening C5 family is actually installed: " + power)
	check(b.acquire_run_power(power, 2) and b.powers.rank(p, power) == 2, "Live Rank II installs on the same owned Top: " + power)
	if not branch.is_empty():
		check(b.acquire_run_power(power, 3, branch) and str(p.power_mutations.get(power, "")) == branch, "High Gear mutation installs after owned launch: " + branch)
	check(is_same(identity, b.player_entity()) and runtime_id == b.powers.get_instance_id(), "C5 upgrades preserve the same owned player and power runtime")
	check(game.collection.snapshot() == before and _raw(game.collection_path) == disk, "Temporary C5 powers never alter permanent collection data")
	rows.append({"power":power,"branch":branch,"seed":game.run_context.run_seed,"build":p.build.duplicate(),"live_rank":b.powers.rank(p,power),"modern":b.powers._modern(p),"permanent_owned":game.collection.owned_count()})
	game._pause()
	game._action("end_run")
	check(game.screen == "garage" and game.run_context.status == "empty", "End C5 Run returns to owned Workshop")
	check(game.collection.snapshot() == before and _raw(game.collection_path) == disk, "End Run preserves equipped parts and historical first choice")

func _run() -> void:
	var path: String = _path("c5-owned-launch")
	var game: QuietMain = _game(path)
	game.set_process(false)
	check(not FileAccess.file_exists(path) and game.collection.owned_count() == 0, "Combined check begins with a missing isolated save")
	game._action("begin_collection")
	game._action("select_first_starter", "bastion")
	check(game.screen == "starter_confirm" and game.collection.owned_count() == 0, "Confirmation grants no components early")
	game._action("confirm_first_starter", "bastion")
	check(game.screen == "starter_owned" and game.collection.owned_count() == 3, "Normal confirmation saves exactly three owned components")
	game._process(1.6)
	check(game.screen == "garage" and game.collection.can_launch(), "Ownership ceremony reaches launchable owned Workshop")
	for power: String in C5Powers.ACTIVE_IDS:
		owned_launch(game, power)
	for branch: String in ["terminal_velocity", "flow_state"]:
		owned_launch(game, "high_gear", branch)
	var before: Dictionary = game.collection.snapshot().duplicate(true)
	game.free()
	var reloaded: QuietMain = _game(path)
	reloaded.set_process(false)
	check(reloaded.collection.snapshot() == before and reloaded.collection.starter_id == "bastion", "Fresh application reload preserves the collection after every C5 family")
	reloaded._action("begin_collection")
	check(reloaded.screen == "garage", "Persisted ownership skips the first-choice ceremony on reload")
	check(reloaded.collection.owned_count() == 3 and reloaded.run_context.owned_power_ids.is_empty(), "Reload restores only permanent parts, never temporary powers")
	reloaded.free()
	var report: Dictionary = {"scope":"Actual isolated first-save ceremony and owned launch with legitimate seeded opening offers; explicit live Rank II/III installation fixtures only. No natural efficacy claim, fabricated permanent grants or production-save access.","checks":checks,"failures":failures,"isolated_save":ProjectSettings.globalize_path(path),"runs":rows,"reloaded_collection":before}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify(report,"\t"))
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("COLLECTION_C5_INTEGRATION_%s checks=%d failures=%d families=13 mutations=2 isolated_save=true" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
