extends "res://tests/test_shop_progression.gd"
## Presentation contracts use isolated production saves and real GUI input.
const Inspector = preload("res://scripts/ability_inspection.gd")
const Transfer = preload("res://scripts/credit_transfer.gd")
const Powers = preload("res://scripts/run_powers.gd")

func _inspection_contract() -> void:
	await _boot_fixture("polish-reading", 180)
	var original: String = FileAccess.get_sha256(profile)
	for id: String in Powers.IDS:
		if Powers.max_rank(id) == 0: continue
		for rank: int in range(Powers.max_rank(id) + 1):
			var details: Dictionary = Inspector.describe(id, rank)
			check(details.rank == rank and details.power_id == id, "Inspection uses actual family and current owned rank")
			for field: String in ["name", "type", "what", "trigger", "limit", "next"]:
				check(not str(details[field]).is_empty(), "Every active family has a structured readable field: " + id + "/" + field)
			check(str(details.mutations).is_empty() if rank < 2 else true, "Locked mutations remain absent from early inspection")
			var panel: Control = Inspector.new()
			panel.position = Vector2(430, 65)
			panel.size = Vector2(188, 242)
			game.menus._content.add_child(panel)
			panel.inspect(id, rank)
			await _settle()
			_check_layout("Ability " + id + " rank " + str(rank))
			panel.get_parent().remove_child(panel)
			panel.queue_free()
		for branch: String in Powers.mutation_choices(id):
			var details: Dictionary = Inspector.describe(id, 2, branch, true)
			check(details.branch_preview and not str(details.mutations).is_empty(), "Mutation inspection explicitly previews its branch")
	check(Inspector.describe("bogus", 1).is_empty(), "Unknown inspection cannot invent a power")
	check(Inspector.describe("redline", 1, "runaway").mutations == "", "A locked branch is not presented as owned")
	game.menus.show_reward(["crash_guard", "predator_line", "clutch"], [], 0, "reading-fixture", 421, "", {"title":"CHOOSE YOUR FIRST POWER"})
	await _settle()
	_check_layout("Three-power draft")
	var first: Button
	var second: Button
	for node: Node in _descendants(game.menus):
		if node is Button and node.get_meta("power_id", "") == "crash_guard": first = node
		if node is Button and node.get_meta("power_id", "") == "predator_line": second = node
	check(root.gui_get_focus_owner() == first and game.menus._ability_inspector.current_rank == 0, "Draft starts with a NEW structured keyboard inspection")
	await _key_tap(KEY_RIGHT)
	check(root.gui_get_focus_owner() == second and game.menus._ability_inspector.power_id == "predator_line", "Keyboard focus updates the anchored inspection")
	await _tap(JOY_BUTTON_DPAD_RIGHT)
	check(game.menus._ability_inspector.power_id == "clutch", "Mapped controller focus updates the same inspection")
	var anchor: Rect2 = game.menus._ability_inspector.get_global_rect()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = first.get_global_rect().get_center()
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await _settle()
	check(game.menus._ability_inspector.power_id == "crash_guard" and game.menus._ability_inspector.get_global_rect() == anchor, "Mouse hover uses the same fixed structured reading panel")
	check(FileAccess.get_sha256(profile) == original, "Reading, hovering and focusing have no economic write")
	for id: String in Powers.IDS:
		if Powers.max_rank(id) == 0: continue
		for rank: int in range(Powers.max_rank(id)):
			game.menus.show_reward([id], [], 0, "reading-fixture", 421, "", {"power_ranks":{id:rank}, "title":"POWER INVESTMENT"})
			await _settle()
			_check_layout("Offer " + id + " rank " + str(rank))
		if not Powers.mutation_choices(id).is_empty():
			game.menus.show_mutation(id, Powers.mutation_choices(id), "reading-fixture", 421)
			await _settle()
			_check_layout("Mutation " + id)

func _payout_presentation() -> void:
	await _boot_fixture("polish-payout", 0)
	var started: Dictionary = game.collection.begin_reward_run()
	game._run_reward_token = str(started.run_id)
	game._pending_run_payout = {"reward_provenance":"earned-clear-v1", "reward_fixture":false, "aborted":false, "earned_threats_cleared":2, "earned_elites_cleared":0, "earned_bosses_cleared":0}
	game.last_result = {"is_run":true, "continuous_run":true, "build":game.collection.equipped_build(), "starter_id":"breaker", "credits_earned":0, "wallet_credits":0, "owned_power_ids":["redline", "clutch"], "power_ranks":{"redline":2, "clutch":1}}
	game.screen = "result"
	check(game._pay_pending_run_payout() and game.collection.credits == 24, "Reward settlement completes before the visual transfer exists")
	var saved: String = FileAccess.get_sha256(profile)
	game.menus.show_result(game.last_result)
	await _settle()
	var transfer: Control = game.menus._credit_transfer
	check(transfer.running and transfer.old_balance == 0 and transfer.new_balance == 24, "Credit transfer starts from actual old and persisted new balances")
	_check_layout("Animated Results")
	await _key_tap(KEY_ENTER)
	check(game.screen == "result" and not transfer.running and transfer.displayed_wallet == 24, "Fresh Confirm settles the visual without navigating")
	check(FileAccess.get_sha256(profile) == saved and game.collection.credits == 24, "Skip cannot settle or debit a second economic transaction")
	await _key_tap(KEY_UP)
	check(game.menus._ability_inspector.visible and game.menus._ability_inspector.current_rank == 2, "Results power focus reads its actual Rank II")
	_check_layout("Results focused ability")
	var marker: Control = Transfer.new()
	marker.configure(1000000, 1000024)
	game.menus._content.add_child(marker)
	marker._process(0.9)
	check(not marker.running and marker.displayed_wallet == 1000024, "Large payouts finish in the same bounded visual duration")
	check(marker.get_child_count() == 2, "Large payouts do not create one node per credit")
	marker.queue_free()

func _run() -> void:
	root.size = Vector2i(640, 360)
	root.content_scale_size = Vector2i(640, 360)
	Input.use_accumulated_input = false
	player_before = _fingerprint()
	await _inspection_contract()
	await _payout_presentation()
	if is_instance_valid(game): game.queue_free(); await process_frame
	check(_fingerprint() == player_before, "Polish verification leaves the actual player profile unchanged")
	print("HUMAN_FEEDBACK_UI_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
