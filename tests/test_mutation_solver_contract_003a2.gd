extends "res://tests/test_mutation_physics_003a2.gd"
## Actual accepted collision verifies retired Damper cannot reduce THIS hit.
func run() -> void:
	for owner: int in [1,2]:
		for branch_id: String in ["reactive_plating","sacrificial_damper"]:
			var retired: Node2D = Fixture.create(root,"crash_guard",branch_id,owner,7341)
			var parent: Node2D = Fixture.create(root,"crash_guard","",owner,7341,2)
			for b: Node2D in [retired,parent]:
				var p: Dictionary=b.entity(owner);var target: Dictionary=b.entity(2 if owner==1 else 1)
				p.pos=Vector2.ZERO;p.vel=Vector2.ZERO;target.pos=Vector2(20,0);target.vel=Vector2(-260,0)
				b.resolve_pair(owner,2 if owner==1 else 1)
			check(retired.hits==1 and parent.hits==1,branch_id+" fixture reaches one canonical full-top collision")
			check(physical(retired)==physical(parent),branch_id+" actual severe solver response equals ordinary Crash Guard II for owner "+str(owner))
			check(not retired.entity(owner).has("reactive_force") and not retired.entity(owner).has("damper_time"),branch_id+" has no obsolete loaded mechanism state")
			rows.append({"branch":branch_id,"owner":owner,"actual_hits":retired.hits,"final":physical(retired)})
			retired.free();parent.free()
	write_and_quit("MUTATION_RETIREMENT_SOLVER")
