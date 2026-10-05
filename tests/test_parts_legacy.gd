extends SceneTree
## Captured against the verified 002C.5.1 parent before catalogue implementation.
## Preserve every old assembly's ratings, handling, wall response and contact.
const Parts = preload("res://scripts/parts.gd")
const Battle = preload("res://scripts/battle.gd")
const FIXTURE = "res://tests/fixtures/parts_legacy_002c5_1.json"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _pack(f: Dictionary) -> Dictionary:
	return {"pos":[f.pos.x,f.pos.y], "vel":[f.vel.x,f.vel.y], "rpm":f.rpm, "wobble":f.wobble, "mass":f.mass, "radius":f.radius}

func _sample(build: Dictionary) -> Dictionary:
	var b = Battle.new()
	root.add_child(b)
	b.set_physics_process(false)
	b.set_process(false)
	b.begin(build, {"blade":"guard", "ratchet":"mid", "bit":"ball"}, 1, 421)
	b.battle_status = "battle"
	var p: Dictionary = b.player_entity()
	p.pos = Vector2(22,31); p.vel = Vector2(75,-40); p.rpm = 0.8; p.wobble = 0.31
	for tick: int in range(60):
		b._update_fighter(p, Vector2(0.6,-0.8), tick >= 40, Battle.FIXED_DT)
	var motion: Dictionary = _pack(p)
	var enemy: Dictionary = b.entity(2)
	p.pos = Vector2(-10,0); p.vel = Vector2(160,50); p.rpm = 0.8; p.wobble = 0.1
	enemy.pos = Vector2(10,0); enemy.vel = Vector2(-60,-10); enemy.rpm = 0.8; enemy.wobble = 0.1
	b.resolve_pair(1,2)
	var contact: Dictionary = {"player":_pack(p), "enemy":_pack(enemy), "hits":b.hits}
	p.pos = Vector2(170,50); p.vel = Vector2(300,50); p.rpm = 0.8; p.wobble = 0.1
	b._resolve_boundary(p)
	var result: Dictionary = {"build":build, "stats":Parts.derive(build), "motion":motion, "contact":contact, "wall":_pack(p)}
	b.free()
	return result

func _run() -> void:
	var capture: bool = "--capture-legacy" in OS.get_cmdline_user_args()
	if capture and (Parts.BLADE_IDS.size() != 4 or Parts.RATCHET_IDS.size() != 3 or Parts.BIT_IDS.size() != 4):
		print("Refusing to replace the parent fixture with an expanded catalogue")
		quit(1)
		return
	var result: Array[Dictionary] = []
	for blade: String in ["balance","smash","guard","hook"]:
		for ratchet: String in ["low","mid","high"]:
			for bit: String in ["needle","ball","flat","rubber"]:
				result.append(_sample({"blade":blade,"ratchet":ratchet,"bit":bit}))
	if capture:
		var file = FileAccess.open(FIXTURE, FileAccess.WRITE)
		file.store_string(JSON.stringify({"source_sha":"3d52a55d9d9bc154b50b3b1c90255f7ff0e62148", "assemblies":result},"\t"))
		file.close()
		print("Captured 48 parent assemblies")
		quit(0)
		return
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for index: int in range(result.size()):
		# JSON normalises ints/floats consistently; exact serialized numbers reveal
		# even neutral-parameter regressions in the existing arithmetic.
		if JSON.stringify(JSON.parse_string(JSON.stringify(result[index]))) != JSON.stringify(expected.assemblies[index]):
			failures.append(Parts.title(result[index].build))
	print("Legacy physical parity: %d / 48 exact; failures %s" % [48-failures.size(),str(failures)])
	quit(0 if failures.is_empty() else 1)
