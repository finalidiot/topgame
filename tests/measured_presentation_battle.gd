extends "res://scripts/battle.gd"
## Instrumentation of CPU draw-command submission only, never physics.
var draw_samples: Array[float] = []

func _draw() -> void:
	var before: int = Time.get_ticks_usec()
	super._draw()
	draw_samples.append(float(Time.get_ticks_usec() - before) / 1000.0)
	if draw_samples.size() > 600:
		draw_samples.pop_front()
