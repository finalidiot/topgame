extends "res://tests/test_collection_ui.gd"
## Actual keyboard/mouse/mapped-pad UI; economic fixtures are explicitly isolated.
const Save = preload("res://scripts/collection_save.gd")
const Economy = preload("res://scripts/packet_economy.gd")
var profile: String
var player_before: Dictionary
class InterruptedSave extends "res://scripts/collection_save.gd":
	var refuse_writes: bool = false
	func _write_save(candidate: Dictionary) -> bool:
		if refuse_writes:
			_write_status = "write_failed"
			return false
		return super._write_save(candidate)

func _fingerprint() -> Dictionary:
	var value: Dictionary = {}
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		value[suffix] = FileAccess.get_sha256(Save.DEFAULT_PATH + suffix) if FileAccess.file_exists(Save.DEFAULT_PATH + suffix) else ""
	value.preferences = FileAccess.get_sha256("user://prototype.cfg") if FileAccess.file_exists("user://prototype.cfg") else ""
	return value

func _boot_fixture(label: String, money: int = 180) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	var base: String = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA/003A/temp")
	var configured: String = OS.get_environment("TOPGAME_QA_ROOT")
	if not configured.is_empty(): base = configured.path_join("003A/temp")
	profile = base.path_join("shop-%s-%d-%d.json" % [label, OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(base)
	var fixture: RefCounted = Save.new(profile)
	fixture.load_save()
	check(fixture.initialize_starter("breaker").ok, "Labelled UI fixture starts with exactly one real starter")
	if money > 0:
		var nonce: Dictionary = fixture.begin_reward_run()
		var outcome: Dictionary = {"reward_provenance":"earned-clear-v1", "reward_fixture":false, "aborted":false, "earned_threats_cleared":money / 12, "earned_elites_cleared":0, "earned_bosses_cleared":0}
		check(fixture.pay_run_reward(str(nonce.run_id), outcome).ok, "Labelled isolated wallet fixture uses the production reward transaction")
	game = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = profile
	game.qa_task_id = "003A"
	game.packet_rng_override = RandomNumberGenerator.new()
	game.packet_rng_override.seed = 113
	root.add_child(game)
	game.set_process(false)
	await _settle()
	check(game.collection.owned_count() == 3, "Wallet fixture grants no extra parts")

func _keyboard_packet() -> void:
	await _boot_fixture("keyboard")
	var original_owned: Array = game.collection.owned_parts()
	await _click(_button("open_shop"))
	check(game.screen == "shop", "Shop is reachable from the permanent hub")
	_check_layout("Shop")
	_focus("Shop")
	await _key_tap(KEY_ENTER)
	check(game.screen == "packet_purchase", "One deliberate Confirm requests a purchase")
	check(root.gui_get_focus_owner() == _button("cancel_packet_purchase"), "Purchase starts with Cancel focused")
	await _key_tap(KEY_ESCAPE)
	check(game.screen == "shop" and game.collection.credits == 180, "Purchase cancellation costs nothing")
	await _key_tap(KEY_ENTER)
	var token: int = game._packet_purchase_token
	game._action("confirm_packet_purchase", token - 1)
	game._action("confirm_packet_purchase", float(token) + 0.5)
	check(game.screen == "packet_purchase" and game.collection.credits == 180, "Stale and fractional confirmations cannot spend")
	_check_layout("Purchase confirmation")
	await _key_tap(KEY_RIGHT)
	await _key_tap(KEY_ENTER)
	check(game.screen == "packet_open" and game.collection.credits == 180 - Economy.packet_cost("standard"), "Confirmed purchase debits exactly once before any animation")
	var committed: Dictionary = game.collection.snapshot()
	game._action("confirm_packet_purchase", token)
	check(game.collection.snapshot() == committed, "Repeated purchase Confirm cannot charge or roll again")
	await _key_tap(KEY_ENTER)
	check(game.menus._packet_view.opening, "Keyboard Confirm tears the actual pouch")
	await _key_tap(KEY_ESCAPE)
	check(game.menus._packet_view.phase == "RESULT", "Keyboard Back resolves immediately")
	check(game.collection.snapshot() == committed, "Skipping changes presentation only")
	_check_layout("Physical packet result")
	_focus("Physical packet result")
	await _key_tap(KEY_ENTER)
	check(game.screen == "garage" and game.collection.pending_packet().is_empty(), "Keyboard takes acquired designs directly to Workshop")
	var acquired: Array = game.collection.owned_parts()
	for id: String in acquired:
		if id not in original_owned:
			var fields: Dictionary = Save.split_part_id(id)
			game.menus.focus_collection_part(str(fields.category), str(fields.id))
			await _settle()
			await _key_tap(KEY_ENTER)
			check(game.collection.equipped_build()[fields.category] == fields.id, "The newly unlocked physical part can be equipped")
			break
	await _click(_button("open_shop"))
	await _click(_button("packet_odds"))
	_check_layout("Production odds")
	await _click(_button("packet_reclaimed_odds"))
	_check_layout("Ownership-conditioned Reclaimed odds")
	var probabilities: Dictionary = Economy.rarity_odds("reclaimed", game.collection.owned_parts())
	var rendered_numbers: Array[String] = []
	for label: Label in _labels(): rendered_numbers.append(label.text)
	for category: String in ["blade", "ratchet", "bit"]:
		for rarity: String in Parts.RARITIES:
			check("%.3f%%" % (float(probabilities.categories[category][rarity]) * 100.0) in rendered_numbers, "Displayed Reclaimed odds derive from the ownership-conditioned production algorithm")
	await _click(_button("packet_salvage_info"))
	_check_layout("Recycling values")
	await _key_tap(KEY_ESCAPE)
	check(game.screen == "shop", "Odds Back returns to the Shop")

func _controller_and_mouse() -> void:
	await _boot_fixture("controller-mouse")
	if await _navigate(_button("open_shop")): await _tap(JOY_BUTTON_A)
	if await _navigate(_button("request_packet_purchase", "standard")): await _tap(JOY_BUTTON_A)
	check(game.screen == "packet_purchase", "Mapped controller reaches the purchase confirmation")
	await _tap(JOY_BUTTON_B)
	check(game.screen == "shop" and game.collection.credits == 180, "Mapped controller cancels safely")
	if await _navigate(_button("request_packet_purchase", "standard")): await _tap(JOY_BUTTON_A)
	if await _navigate(_button("confirm_packet_purchase")): await _tap(JOY_BUTTON_A)
	if await _navigate(_button("packet_tear")): await _tap(JOY_BUTTON_A)
	game.menus._packet_view._process(2.5)
	await _settle()
	check(game.menus._packet_view.phase == "RESULT", "Normal opening reaches readable results within its animation budget")
	_check_layout("Controller result")
	if await _navigate(_button("packet_another")): await _tap(JOY_BUTTON_A)
	check(game.screen == "packet_purchase", "Open Another remains controller reachable and deliberate")
	await _click(_button("confirm_packet_purchase"))
	check(game.screen == "packet_open", "Pointer can confirm an ordinary production transaction")
	await _click(_button("packet_skip"))
	check(game.menus._packet_view.phase == "RESULT", "Pointer Fast Open resolves the same receipt")
	var save: Dictionary = game.collection.snapshot()
	var pending: Dictionary = game.collection.pending_packet()
	game.queue_free()
	await process_frame
	game = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = profile
	root.add_child(game)
	game.set_process(false)
	await _settle()
	check(game.screen == "packet_open" and game.menus._packet_view.phase == "RESULT", "Restart recovers resolved packet inspection")
	var reloaded: Dictionary = game.collection.snapshot()
	check(game.collection.pending_packet() == pending and reloaded.progression == save.progression and reloaded.owned_part_ids == save.owned_part_ids and reloaded.equipped_build == save.equipped_build, "Restart neither charges nor grants the saved receipt twice")
	if await _navigate(_button("packet_shop")): await _tap(JOY_BUTTON_A)
	check(game.screen == "shop" and game.collection.pending_packet().is_empty(), "Controller closes the recovered receipt and returns to Shop")
	game._start_run()
	game._action("open_shop")
	check(game.screen == "reward", "Shop cannot interrupt an active Run or draft")

func _insufficient() -> void:
	await _boot_fixture("empty-wallet", 0)
	await _click(_button("open_shop"))
	check(_button("request_packet_purchase", "standard").disabled, "Standard purchase communicates insufficient funds")
	await _key_tap(KEY_DOWN)
	check(game.menus.selected_shop_product() == "reclaimed" and _button("request_packet_purchase", "reclaimed").disabled, "Selecting Reclaimed communicates its insufficient funds")
	_focus("Empty wallet Shop")
	_check_layout("Empty wallet Shop")
	game._action("request_packet_purchase", "standard")
	game._action("confirm_packet_purchase", game._packet_purchase_token)
	check(game.screen == "shop" and game.collection.credits == 0 and game.collection.pending_packet().is_empty(), "Insufficient and stale purchase signals cannot create a packet or negative balance")

func _payout_retry() -> void:
	await _boot_fixture("payout-retry", 0)
	var interrupted: InterruptedSave = InterruptedSave.new(profile)
	interrupted.load_save()
	game.collection = interrupted
	var started: Dictionary = interrupted.begin_reward_run()
	game._run_reward_token = str(started.run_id)
	game._pending_run_payout = {"reward_provenance":"earned-clear-v1", "reward_fixture":false, "aborted":false, "earned_threats_cleared":2, "earned_elites_cleared":0, "earned_bosses_cleared":0}
	game.last_result = {"is_run":true, "continuous_run":true, "build":game.collection.equipped_build(), "starter_id":"breaker", "credits_earned":0, "wallet_credits":0}
	game.screen = "result"
	interrupted.refuse_writes = true
	check(not game._pay_pending_run_payout() and game.last_result.payout_pending, "A simulated interrupted reward write retains the verified outcome and nonce")
	game.menus.show_result(game.last_result)
	await _settle()
	_check_layout("Retry payout Results")
	game._action("open_shop")
	check(game.screen == "result" and not game._pending_run_payout.is_empty(), "Navigation cannot silently discard unpaid CREDITS")
	interrupted.refuse_writes = false
	await _click(_button("retry_run_payout"))
	check(game.collection.credits == 24 and game._pending_run_payout.is_empty() and not game.last_result.payout_pending, "Retry saves the same verified reward exactly once")
	game._action("retry_run_payout")
	check(game.collection.credits == 24, "Repeated Results retry cannot pay twice")
	await _click(_button("open_shop"))
	check(game.screen == "shop", "Successfully saved retry restores ordinary Results routes")

func _wallet_capacity_route() -> void:
	await _boot_fixture("wallet-capacity", 0)
	var maximum: Dictionary = game.collection._data.duplicate(true)
	maximum.progression.credits = Save.MAX_BALANCE
	check(game.collection._commit(maximum, "max_wallet_fixture").ok, "Explicit isolated maximum-wallet fixture remains a valid bounded save")
	var started: Dictionary = game.collection.begin_reward_run()
	game._run_reward_token = str(started.run_id)
	game._pending_run_payout = {"reward_provenance":"earned-clear-v1", "reward_fixture":false, "aborted":false, "earned_threats_cleared":4, "earned_elites_cleared":0, "earned_bosses_cleared":0}
	game.last_result = {"is_run":true, "continuous_run":true, "build":game.collection.equipped_build(), "starter_id":"breaker", "credits_earned":0, "wallet_credits":Save.MAX_BALANCE}
	game.screen = "result"
	check(not game._pay_pending_run_payout() and game.last_result.payout_status == "balance_limit", "A full wallet refuses overflow while keeping its exact reward token")
	game.menus.show_result(game.last_result)
	await _settle()
	await _click(_button("open_shop"))
	check(game.screen == "shop" and not game._pending_run_payout.is_empty(), "The full-wallet Results route allows lawful spending without discarding unpaid reward")
	await _click(_button("request_packet_purchase", "standard"))
	await _click(_button("confirm_packet_purchase"))
	await _click(_button("packet_skip"))
	await _click(_button("packet_shop"))
	check(game.screen == "shop" and game.collection.credits == Save.MAX_BALANCE and game._pending_run_payout.is_empty(), "A real packet debit makes space and settles the retained reward exactly once")

func _reset_unpaid_session() -> void:
	await _boot_fixture("reset-unpaid", 0)
	var started: Dictionary = game.collection.begin_reward_run()
	game._run_reward_token = str(started.run_id)
	game._pending_run_payout = {"reward_provenance":"earned-clear-v1", "reward_fixture":false, "aborted":false, "earned_threats_cleared":2, "earned_elites_cleared":0, "earned_bosses_cleared":0}
	game._action("settings")
	game._action("save_tools")
	game._action("request_reset_collection")
	game._action("confirm_reset_collection", game._reset_token)
	check(game.screen == "starter_ceremony" and game._run_reward_token.is_empty() and game._pending_run_payout.is_empty(), "Explicit backed-up progression reset also clears unpaid session reward guards")
	game._action("select_first_starter", "bastion")
	game._action("confirm_first_starter", "bastion")
	game._ownership_remaining = 0.0
	game._action("finish_ownership")
	check(game.screen == "garage" and game.collection.owned_count() == 3 and game.collection.credits == 0 and game.collection.salvage == 0, "After resetting an unpaid session the new starter reaches Workshop without an obsolete nonce")

func _run() -> void:
	root.size = Vector2i(800, 480)
	root.content_scale_size = Vector2i(800, 480)
	Input.use_accumulated_input = false
	player_before = _fingerprint()
	await _keyboard_packet()
	await _controller_and_mouse()
	await _insufficient()
	await _payout_retry()
	await _wallet_capacity_route()
	await _reset_unpaid_session()
	if is_instance_valid(game): game.queue_free(); await process_frame
	check(_fingerprint() == player_before, "The real player's collection and preferences remain byte-identical")
	print("SHOP_PROGRESSION_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
