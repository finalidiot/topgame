extends SceneTree
const Starters = preload("res://scripts/starters.gd")
const Parts = preload("res://scripts/parts.gd")
var failures: int = 0
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	for id: String in Starters.IDS:
		var starter: Dictionary = Starters.get_starter(id)
		check(starter.id == id and starter.name == id.to_upper(), "Starter identity is stable")
		check(starter.assembly == Parts.validate_build(starter.assembly), "Starter selects valid physical parts")
		check(starter.stats == Parts.derive(starter.assembly), "Starter stats come exclusively from its physical assembly")
		starter.assembly.blade = "balance"
		check(Starters.build_for(id).blade != "balance", "Starter lookup cannot mutate authored data")
	var red: Dictionary = Starters.get_starter("breaker").stats
	var blue: Dictionary = Starters.get_starter("bastion").stats
	var green: Dictionary = Starters.get_starter("vane").stats
	check(red.power > green.power and red.power > blue.power, "Breaker delivers the strongest impacts")
	check(red.speed > green.speed and red.stamina < blue.stamina, "Breaker runs fast and burns reserve")
	check(blue.stability > red.stability and blue.mass > green.mass and blue.speed < green.speed, "Bastion is stable, heavy and deliberate")
	check(green.grip > red.grip and green.grip > blue.grip, "Vane steers with the strongest grip")
	check(Starters.get_starter("missing").is_empty() and Starters.display_name("custom") == "CUSTOM", "Unknown identities fail safely")
	print("STARTER_TEST_%s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(1 if failures else 0)
