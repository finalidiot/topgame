extends "res://tests/capture_progression_003a.gd"
## Human-feedback film uses normal Main and keyboard/pad input throughout.
var first_inspection: bool = true

func matching(node: Node, metadata: Dictionary) -> Control:
	if node is Control and node.is_visible_in_tree():
		var matches: bool = true
		for field: String in metadata:
			if not node.has_meta(field): matches = false; break
			var actual: Variant = node.get_meta(field)
			if typeof(actual) != typeof(metadata[field]) or actual != metadata[field]: matches = false; break
		if matches and (not node is BaseButton or not node.disabled): return node
	for child: Node in node.get_children():
		var found: Control = matching(child, metadata)
		if found != null: return found
	return null

func image(name: String) -> void:
	await super.image(name)
	if name == "run_1_opening":
		await tap_key(KEY_ESCAPE)
		await checkpoint("pause_ability_inspection", 2.0)
		await tap_key(KEY_ESCAPE)
	elif name == "run_1_result":
		await wait_frames(70)
		await super.image("results_wallet_settled")
		await tap_key(KEY_UP)
		await checkpoint("results_ability_inspection", 2.0)
		await tap_key(KEY_DOWN)

func click(control: Control) -> void:
	assert(is_instance_valid(control))
	var metadata: Dictionary = {}
	for field: String in ["intent", "payload", "power_id", "catalogue_tab", "part_category", "part_id", "starter_id"]:
		if control.has_meta(field): metadata[field] = control.get_meta(field)
	for attempt: int in range(160):
		var target: Control = matching(game.menus, metadata)
		assert(target != null, "Keyboard target disappeared " + str(metadata))
		var focus: Control = root.gui_get_focus_owner()
		if focus == target:
			await tap_key(KEY_ENTER)
			return
		var paths: Dictionary = {focus:[]}
		var queue: Array[Control] = [focus]
		while not queue.is_empty() and not paths.has(target):
			var node: Control = queue.pop_front()
			if node == null: continue
			for side: int in range(4):
				var path: NodePath = node.get_focus_neighbor(side)
				var neighbor: Control = node.get_node_or_null(path) if not path.is_empty() else null
				if neighbor == null or paths.has(neighbor): continue
				var route: Array = paths[node].duplicate()
				route.append(side)
				paths[neighbor] = route
				queue.append(neighbor)
		if paths.has(target) and not paths[target].is_empty():
			await tap_key([KEY_LEFT,KEY_UP,KEY_RIGHT,KEY_DOWN][int(paths[target][0])])
		else: await tap_key(KEY_TAB)
	fail("Keyboard cannot reach " + str(metadata))

func boot() -> void:
	await super.boot()
	await checkpoint("title_centred", 4.0)

func fresh_starter() -> void:
	assert(not game.collection.is_initialized())
	await tap_key(KEY_ENTER)
	await checkpoint("clean_hub_fresh", 2.5)
	await click_intent("begin_collection")
	await checkpoint("three_starter_fx", 7.0)
	await tap_key(KEY_RIGHT)
	await wait_frames(60)
	await tap_key(KEY_RIGHT)
	await wait_frames(60)
	await tap_key(KEY_LEFT)
	await tap_key(KEY_LEFT)
	await tap_key(KEY_ENTER)
	await checkpoint("make_it_yours", 3.0)
	await click_intent("confirm_first_starter")
	await wait_frames(150)
	assert(game.screen == "garage" and game.collection.owned_count() == 3 and game.collection.credits == 0)
	before_collection = game.collection.snapshot()
	await checkpoint("collection_before", 2.0)
	await click_intent("main_menu")
	await checkpoint("clean_hub_owned", 3.0)
	await click_intent("settings")
	await checkpoint("options", 1.5)
	await tap_key(KEY_ESCAPE)
	await click_intent("open_workshop")
	await checkpoint("workshop", 2.0)

func choose_offer() -> void:
	if first_inspection and game.screen == "reward":
		first_inspection = false
		controls(Vector2.ZERO,false,false)
		await checkpoint("power_draft_inspection", 2.5)
		await tap_key(KEY_RIGHT)
		await checkpoint("ability_focus_second", 2.5)
		await tap_key(KEY_RIGHT)
		await checkpoint("ability_focus_third", 2.5)
	await super.choose_offer()

func buy_and_open(fast: bool = false, prefix: String = "packet") -> void:
	# Real pad list navigation previews Reclaimed, then returns to the affordable
	# ordinary pouch. Confirm still opens the production cancel-first modal.
	button(JOY_BUTTON_DPAD_DOWN,true); await wait_frames(2)
	button(JOY_BUTTON_DPAD_DOWN,false); await wait_frames(2)
	await checkpoint("shop_reclaimed_list", 2.0)
	button(JOY_BUTTON_DPAD_UP,true); await wait_frames(2)
	button(JOY_BUTTON_DPAD_UP,false); await wait_frames(2)
	await checkpoint("shop_merchant_selected", 2.0)
	await super.buy_and_open(fast,prefix)
	assert(game.menus._packet_view.phase == "RESULT")
