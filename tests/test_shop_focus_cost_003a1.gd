extends "res://tests/test_collection_ui.gd"
## A constrained isolated wallet checks live quantity affordability and focus.
const Save = preload("res://scripts/collection_save.gd")
var observations: Array[Dictionary] = []

func record(label: String) -> void:
	var focused: Control = root.gui_get_focus_owner()
	observations.append({"label":label,"quantity":game.menus.selected_shop_quantity("standard"),"focused_intent":focused.get_meta("intent","") if focused != null else "NONE","focused_disabled":focused.disabled if focused is Button else false})

func _run() -> void:
	root.size = Vector2i(800,480)
	root.content_scale_size = Vector2i(800,480)
	var qa_root: String = OS.get_environment("TOPGAME_QA_ROOT")
	if qa_root.is_empty(): qa_root = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("GyroBrothers-QA")
	var profile: String = qa_root.path_join("003A.1/temp/shop-focus-cost-%d-%d.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	var report: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="): report = argument.trim_prefix("--report=")
	var fixture = Save.new(profile)
	check(fixture.load_save().ok and fixture.initialize_starter("breaker").ok,"Fresh isolated short-wallet starter")
	var state: Dictionary = fixture._data.duplicate(true)
	state.progression.credits = 100
	state.progression.salvage = 100
	check(fixture._commit(state,"declared_short_wallet_fixture").ok,"Declared100/100 wallet persists")
	game = QuietMain.new()
	game.smoke_mode = true
	game.collection_path = profile
	root.add_child(game)
	game.set_process(false)
	await _settle()
	await _click(_button("open_shop"))
	var wallet: Dictionary = game.collection.wallet()
	var buy: Button = _button("request_packet_purchase","standard")
	check(not buy.disabled,"x1 is affordable with100 credits")
	if await _navigate(buy): await _tap(JOY_BUTTON_DPAD_RIGHT)
	check(game.menus.selected_shop_quantity("standard") == 3 and buy.disabled,"Right immediately disables an unaffordable x3 purchase")
	record("x3_unaffordable")
	var focused: Control = root.gui_get_focus_owner()
	check(focused != null and (not focused is Button or not focused.disabled),"Changing quantity cannot strand focus on a disabled Buy")
	check(await _navigate(_button("inspect_shop_product","reclaimed")),"D-pad still reaches the other product after affordability changes")
	check(game.menus.selected_shop_product() == "reclaimed" and game.menus.selected_shop_quantity("reclaimed") == 1,"Moving products never substitutes shared quantity")
	record("reclaimed_reachable")
	await _click(_button("inspect_shop_product","standard"))
	check(game.screen == "shop" and game.collection.wallet() == wallet,"Unaffordable focused Standard cannot debit")
	game.menus.select_shop_quantity({"kind":"standard","quantity":1})
	check(not buy.disabled,"Reducing quantity re-enables lawful purchase")
	check(await _navigate(buy),"The re-enabled Buy returns to controller focus graph")
	record("x1_affordable_again")
	if not report.is_empty():
		var file: FileAccess = FileAccess.open(report,FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"profile":profile,"observations":observations,"scope":"Isolated100-CREDIT/100-SALVAGE wallet fixture; actual D-pad and mouse, no physical hardware acceptance."},"\t"));file.close()
	game.queue_free()
	await process_frame
	print("SHOP_FOCUS_COST_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(1 if failures else 0)
