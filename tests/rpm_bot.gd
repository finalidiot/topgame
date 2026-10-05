extends RefCounted
## Reproducible sampled controls only; never edits physics or director state.
static func input(b: Node2D, style: String, tick: int) -> Dictionary:
	var p: Dictionary = b.player_entity()
	var target: Dictionary = b._target_for(p)
	var aim: Vector2 = Vector2.ZERO
	var distance: float = INF
	if not target.is_empty():
		var offset: Vector2 = Vector2(target.pos)-Vector2(p.pos)
		distance = offset.length()
		aim = (offset+Vector2(target.vel)*0.12-Vector2(p.vel)*0.08).normalized().rotated(sin(float(tick)*0.047)*0.10)
	var intensity: float = 0.86
	var burst: bool = float(p.cooldown) <= 0.0 and distance < 85.0
	var brake: bool = Vector2(p.pos).length() > 153.0
	if style == "defensive" or (style == "hybrid" and float(p.rpm) < 0.40):
		# Small deliberate corrections around centre; receive rather than chase.
		aim = (-Vector2(p.pos)*0.9-Vector2(p.vel)*0.35+aim*24.0).normalized()
		intensity = 0.25
		burst = false
	elif style == "hybrid":
		intensity = 0.64
		burst = burst and distance < 55.0 and fmod(b.elapsed,9.0) < 0.3
	if Vector2(p.pos).length() > 138.0: aim = -Vector2(p.pos).normalized(); intensity = 0.85
	if style == "afk": aim = Vector2.ZERO; intensity = 0.0; burst = false; brake = false
	if style == "reckless": aim = Vector2.RIGHT.rotated(b.elapsed*0.7); burst = float(p.cooldown) <= 0.0; brake = false
	return {"direction":Vector2(aim.x-aim.y,(aim.x+aim.y)*0.5).normalized()*intensity,"burst":burst and not brake,"brake":brake}
