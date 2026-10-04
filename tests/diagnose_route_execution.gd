extends "res://tests/diagnose_roster_runs.gd"
## Natural seeded earned Ghost branches with deliberate route execution.
const Route = preload("res://tests/roster_route_bot.gd")
const Observer = preload("res://tests/observed_route_power.gd")
var follow_preview: bool = true
var route_radius: float = 85.0
var route_pace: float = 145.0
var observations: Array[Dictionary] = []
var previous_proc: int = 0
var was_ghost: bool = false
var metrics: Dictionary = {}
var observe_emissions: bool = false
var observed = null
func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--ignore-preview": follow_preview = false
		if arg == "--observe-emissions": observe_emissions = true
		if arg.begins_with("--radius="): route_radius = float(arg.trim_prefix("--radius="))
		if arg.begins_with("--pace="): route_pace = float(arg.trim_prefix("--pace="))
	call_deferred("_run")
func controls(b: Node2D, playstyle: String, tick: int) -> Dictionary:
	if profile != "route": return super.controls(b,playstyle,tick)
	if observe_emissions and observed == null:
		observed = Observer.new()
		observed.setup(b)
		b.powers = observed
	var state: Dictionary = Route.inspect(b)
	if bool(state.ghost):
		metrics.ghost_control_samples += 1
		metrics.speed_sum += float(state.speed)
		metrics.trace_span_max = maxf(float(metrics.trace_span_max),float(state.trace_span))
		metrics.trace_count_max = maxi(int(metrics.trace_count_max),int(state.trace_count))
		if float(state.speed) <= 112.0: metrics.below_trace_speed_samples += 1
		if float(state.preview_gap) >= 0.0:
			metrics.preview_samples += 1
			metrics.preview_gap_min = minf(float(metrics.preview_gap_min),float(state.preview_gap))
			if observations.size() < 120: observations.append(state)
		if not was_ghost: observations.append(state)
		was_ghost = true
	var proc: int = int(b.powers.counters.get("ghost_closure",0))
	if proc > previous_proc: observations.append(state); previous_proc = proc
	return Route.input(b,tick,follow_preview,route_radius,route_pace)
func play(starter: String, seed_value: int) -> Dictionary:
	observations.clear()
	metrics = {"ghost_control_samples":0,"speed_sum":0.0,"below_trace_speed_samples":0,"preview_samples":0,"preview_gap_min":999.0,"trace_span_max":0.0,"trace_count_max":0}
	previous_proc = 0
	was_ghost = false
	observed = null
	var result: Dictionary = super.play(starter,seed_value)
	metrics["mean_speed_while_ghost"] = float(metrics.speed_sum)/maxi(1,int(metrics.ghost_control_samples))
	metrics.erase("speed_sum")
	result["route_controller"] = {"follow_preview":follow_preview,"radius":route_radius,"pace":route_pace,"metrics":metrics.duplicate(),"observations":observations.duplicate(true)}
	if observed != null: result.route_controller["emissions"] = observed.closure_rows.duplicate(true)
	return result
