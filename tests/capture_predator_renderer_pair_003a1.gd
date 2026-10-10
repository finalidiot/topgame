extends "res://tests/capture_combat_art003a1.gd"
## Identical disclosed held presentation fixture for renderer-only comparison.
## This is not the separate actual contact-earned Predator gameplay movie.
func power_review() -> void:
	var b: Node2D=new_battle("predator_line");b.continuous.pending.clear()
	var p: Dictionary=b.player_entity();p.pos=Vector2.ZERO;p.height=0.0
	var rival: Dictionary=b.entity(2);rival.pos=Vector2(65,-28);rival.height=0.0
	captions("003A.1 PREDATOR / IDENTICAL RENDERER COMPARISON","HELD VISUAL FIXTURE / NOT NATURAL POWER OR PHYSICS EVIDENCE")
	Identity.reset_motion()
	for tick: int in range(181):
		var time: float=float(tick)/60.0;var angle: float=time*1.25;b._visual_time=time
		p.pos=Vector2(cos(angle)*48,sin(angle)*36);p.vel=Vector2(-sin(angle)*160,cos(angle)*125);p.hunt_stacks=3;p.hunt_target=2
		rival.pos=Vector2(62*cos(angle+.35),42*sin(angle+.35))
		Identity.observe_motion(b.fighters,time)
		await record(b,"predator_renderer_pair",tick,"predator_flow_turn" if tick==120 else "")
	b.free();scenes.append({"family":"predator_line","frames":181,"held_state_fixture":true,"balance_claim":false})
