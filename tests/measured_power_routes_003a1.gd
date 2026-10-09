extends "res://scripts/power_runtime.gd"
## Read-only wall-clock instrumentation; all mechanics call the production base.
var movement_us: int=0
var circuit_us: int=0
var circuit_calls: int=0
func reset_sample() -> void:
	movement_us=0;circuit_us=0;circuit_calls=0
func after_movement() -> void:
	var began: int=Time.get_ticks_usec()
	super.after_movement()
	movement_us+=Time.get_ticks_usec()-began
func _modern_circuit(owner: Dictionary, trace_emitted: bool) -> void:
	var began: int=Time.get_ticks_usec()
	super._modern_circuit(owner,trace_emitted)
	circuit_us+=Time.get_ticks_usec()-began;circuit_calls+=1
