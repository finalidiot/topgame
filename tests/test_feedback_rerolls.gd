extends SceneTree
## Run-only charges, deterministic drafts, actual UI routing and swept pickups.
const Run = preload("res://scripts/run_context.gd")
const Main = preload("res://scripts/main.gd")
const Menus = preload("res://scripts/menus.gd")
const Pickups = preload("res://scripts/run_pickups.gd")
const FX = preload("res://scripts/feedback_effects.gd")
const BUILD: Dictionary = {"blade":"balance", "ratchet":"mid", "bit":"ball"}
var checks: int = 0
var failures: int = 0

class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void: pass

func _initialize() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _same_cards(first: Array, second: Array) -> bool:
	if first.size() != second.size(): return false
	for id: String in first:
		if not id in second: return false
	return true

func _test_run_contract() -> void:
	for seed_value: int in range(1, 65):
		var first = Run.new()
		var second = Run.new()
		first.start(BUILD, seed_value)
		second.start(BUILD, seed_value)
		check(first.reroll_charges == 1 and first.can_reroll(), "Each new Run starts with one charge and alternatives")
		var previous: Array = first.pending_offer
		check(first.pending_offer == second.pending_offer, "Original offer remains seeded")
		check(not first.reroll_offer("stale", 0) and first.reroll_charges == 1, "Wrong claim cannot spend a charge")
		check(first.reroll_offer(first.pending_draft_id, 0) and second.reroll_offer(second.pending_draft_id, 0), "Valid matching claim rerolls")
		check(first.pending_offer == second.pending_offer and first.reroll_snapshot() == second.reroll_snapshot(), "Rerolls reproduce exactly from independent seed domain")
		check(not _same_cards(previous, first.pending_offer), "Paid reroll changes at least one card")
		check(first.reroll_charges == 0 and first.rerolls_used == 1 and not first.can_reroll(), "One charge is spent once")
		check(not first.reroll_offer(first.pending_draft_id, 0), "Repeated old button is harmless")
		check(first.collect_reroll_pickup("physical-chip/1"), "A physical pickup adds a Run charge")
		check(not first.collect_reroll_pickup("physical-chip/1"), "A pickup receipt cannot pay twice")
		check(not first.reroll_offer(first.pending_draft_id, 0) and first.reroll_charges == 1, "Old revision cannot consume a new pickup")
		check(first.reroll_offer(first.pending_draft_id, 1), "Fresh revision can spend the collected charge")
		check(first.choose_power(first.pending_draft_id, first.pending_offer[0]), "Rerolled card grants one real investment")
		for id: int in range(12): first.collect_reroll_pickup("physical-chip/%d" % (id + 2))
		check(first.reroll_charges == Run.MAX_REROLLS and not first.collect_reroll_pickup("overflow"), "Charges are capped and a full pouch cannot consume chips")
		first.fail_run()
		check(not first.collect_reroll_pickup("after-death") and not first.can_reroll(), "A lost Run cannot gain or spend charges")
		first.clear()
		check(first.reroll_charges == 0 and first.rerolls_used == 0 and first.rerolls_collected == 0, "Run inventory does not persist")

func _test_hud() -> void:
	var menus = Menus.new()
	root.add_child(menus)
	menus.show_hud({"player_rpm":1.16, "redline_active":true, "redline_heat":0.7, "is_run":true, "rerolls":3})
	check(is_equal_approx(menus._hud.player_bar.value, 1.0) and is_equal_approx(menus._hud.player_bar.max_value, 1.0), "Normal reserve fills the whole base bar")
	check(menus._hud.rpm_overflow.visible and is_equal_approx(menus._hud.rpm_overflow.value, 0.16), "Actual excess builds a separate layer over full normal RPM")
	check(not menus._hud.has("normal_rpm_tick"), "No permanent notch implies a limiter on ordinary RPM")
	check("10440 RPM" in menus._hud.player_rpm.text and "+16% OVERDRIVE" in menus._hud.player_rpm.text, "Label matches actual increased reserve")
	menus._menu_clock = 0.0
	menus._animate_rpm_meter()
	var first_color: Color = menus._hud.rpm_overflow.get_theme_stylebox("fill").bg_color
	menus._menu_clock = 0.10
	menus._animate_rpm_meter()
	check(first_color != menus._hud.rpm_overflow.get_theme_stylebox("fill").bg_color and is_equal_approx(menus._hud.rpm_overflow.value, 0.16), "Red/orange pulse never fabricates RPM")
	check(menus._hud.rerolls.text == "REROLLS  3", "HUD reflects current Run charges")
	menus.show_hud({"player_rpm":0.7, "is_run":false})
	check(menus._hud.player_rpm.text == "6300 RPM" and not menus._hud.rerolls.visible and not menus._hud.anchor.visible, "Ordinary duel clears prior Run/overdrive state")
	check(is_equal_approx(menus._hud.player_bar.value, 0.7) and not menus._hud.rpm_overflow.visible, "Ordinary reserve uses the full width without showing empty overdrive capacity")
	menus.show_hud({"player_rpm":1.0,"redline_active":true})
	check(is_equal_approx(menus._hud.player_bar.value,1.0) and not menus._hud.rpm_overflow.visible,"Activation alone cannot create a fake excess layer")
	menus.show_hud({"player_rpm":1.24,"redline_active":true})
	check(is_equal_approx(menus._hud.rpm_overflow.value,0.24) and is_equal_approx(menus._hud.player_bar.value,1.0),"Maximum real excess fills the upper layer while retaining full normal reserve")
	menus.show_hud({"player_rpm":0.6,"dead_centre_owned":true,"dead_centre_central_hold":true,"dead_centre_charge":0.8,"dead_centre_maturity":0.5,"dead_centre_recovery_rate":0.009})
	check("+81 RPM/s" in menus._hud.anchor.text, "Anchor recovery indicator follows actual eligible rate")
	menus.show_hud({"player_rpm":0.6,"dead_centre_owned":true,"dead_centre_recovery_remaining":0.0,"dead_centre_rearm_progress":0.4})
	check(menus._hud.anchor.text == "MOVE OUT / REARM  40%", "Exhausted recovery tells the player how to renew it")
	menus.queue_free()
	await process_frame
	await process_frame

func _test_main_and_pickups() -> void:
	var path: String = OS.get_temp_dir().path_join("spinning_metal_feedback_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()])
	var game = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = path
	root.add_child(game)
	check(bool(game.collection.initialize_starter("breaker").ok), "Isolated starter fixture initializes")
	var bytes_before: PackedByteArray = FileAccess.get_file_as_bytes(path)
	game._start_run()
	var seed_value: int = game.run_context.run_seed
	var old_id: String = str(game.run_context.pending_offer[0])
	var old_payload: Dictionary = {"encounter_id":game.run_context.pending_draft_id,"power_id":old_id,"run_seed":seed_value,"offer_revision":0}
	var reroll: Button = game.menus._content.get_node("RerollPower")
	check(not reroll.disabled and "1 LEFT" in reroll.text, "Draft presents an available keyboard/controller reroll button")
	check(not reroll.focus_neighbor_top.is_empty() and reroll.get_node(reroll.focus_neighbor_top) is Button, "Reroll participates in card/controller focus navigation")
	reroll.pressed.emit()
	check(game.screen == "reward" and game.run_context.reroll_charges == 0, "Actual Main route rerolls without launching battle")
	game._action("choose_power", old_payload)
	check(game.screen == "reward" and game.run_context.owned_power_ids.is_empty(), "Old visible card callback is rejected even if the power remains offered")
	game._action("choose_power", {"encounter_id":game.run_context.pending_draft_id,"power_id":game.run_context.pending_offer[0],"run_seed":seed_value,"offer_revision":1})
	game._finish_acquisition()
	game.battle.set_physics_process(false)
	game.battle.battle_status = "battle"
	game.battle.elapsed = 10.0
	game.battle.player_entity().pos = Vector2.ZERO
	game.reroll_pickups.setup(game.battle, game.run_context)
	var summary: Dictionary = {"run_seed":seed_value,"threat":1,"kind":"rival"}
	game.battle.continuous.last_clear = summary
	game.battle.continuous.threats_cleared = 1
	check(game.reroll_pickups.notify_clear(summary), "Genuine current clear fixture spawns a reachable floor chip")
	check(not game.reroll_pickups.notify_clear(summary) and game.reroll_pickups.items.size() == 1, "Repeated clear cannot spawn duplicate items")
	var point: Vector2 = Vector2(game.reroll_pickups.items[0].pos)
	check(point.length() < 166.0 and point.length() >= 30.0, "Chip lies inside safe arena and requires movement")
	game.battle.set_paused(true)
	game.battle.player_entity().pos = point * 1.1
	game.battle.elapsed += 1.0
	game.reroll_pickups.update_simulation()
	check(game.run_context.reroll_charges == 0 and game.reroll_pickups.items.size() == 1, "Paused frame cannot collect even across a contact fixture")
	game.battle.set_paused(false)
	game.reroll_pickups.update_simulation()
	check(game.run_context.reroll_charges == 1 and game.reroll_pickups.items.is_empty(), "Actual swept player segment collects once even if endpoint passes the chip")
	game.reroll_pickups.update_simulation()
	check(game.run_context.reroll_charges == 1, "A render frame without simulation advance cannot duplicate charge")
	check(FileAccess.get_file_as_bytes(path) == bytes_before and game.collection.owned_count() == 3, "Rerolls and pickups write no ownership or player collection state")
	game.queue_free()
	await process_frame
	await process_frame
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp", ".preferences.cfg", ".last_run_director.json"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _test_impact_keys() -> void:
	for strength: float in [0.2, 0.6, 1.0]:
		var tag: String = FX.impact_tag(strength)
		var duration: float = FX.impact_duration(tag)
		check(FX.impact_frame(tag, 0.0) >= 0 and FX.impact_frame(tag, duration + 0.01) == -1, "Authored blast plays anticipation/action/recovery once and expires")
	check(FX.impact_tag(0.2) != FX.impact_tag(1.0), "Real impact strength selects distinct pressure wave severity")

func _run() -> void:
	root.size = Vector2i(640, 360)
	_test_run_contract()
	await _test_hud()
	await _test_main_and_pickups()
	_test_impact_keys()
	print("FEEDBACK_REROLLS_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
