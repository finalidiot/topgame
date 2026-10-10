extends SceneTree
const Director = preload("res://scripts/threat_director.gd")
const Model = preload("res://tests/director_density_model_003a1.gd")
var checks: int=0
var failures: int=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
static func count(full: int,bosses: int=0,elites: int=0,small: int=0) -> Dictionary:
	return {"full":full,"bosses":bosses,"elites":elites,"small":small,"total":1+full+small,"pressure":float(full-bosses-elites)*2.6+float(bosses)*7.0+float(elites)*4.6+float(small)*0.5,"swarm":small>0}
static func kinds(choices: Array[Dictionary]) -> Array[String]:
	var out: Array[String]=[]
	for event: Dictionary in choices:out.append(str(event.kind))
	return out
func run() -> void:
	for pair: Array in [[0.0,1],[28.0,2],[80.0,3],[170.0,3],[280.0,4],[639.999,4],[640.0,5],[879.999,5],[880.0,6],[100000.0,6]]:
		check(Director.limits(float(pair[0])).full==int(pair[1]),"Ordinary/deep full cap changes only at its authored threshold%s"%pair[0])
	check(Director.TUNING.full_caps==[1,2,3,3,4] and Director.TUNING.budgets==[2.8,6.0,10.0,13.0,16.0],"Accepted ordinary full progression and pressure budgets stay exact")
	check(Director.limits(279.999).small==10 and Director.limits(279.999).total==16 and Director.limits(280.0).small==9 and Director.limits(280.0).total==15,"Tiny clutter haircut begins in the highest ordinary tier, leaving early/mid unchanged")
	var director: RefCounted=Director.new();director.setup(421)
	check(director.candidates(639.999,count(4),13).all(func(event: Dictionary) -> bool:return event.kind=="swarm"),"No fifth full top before deep unlock; ordinary swarm variety is still eligible")
	check("rival" in kinds(director.candidates(640.0,count(4),13)),"The real candidate path admits a fifth after unlock")
	check(kinds(director.candidates(879.999,count(5),13)).is_empty(),"No sixth full top before absurd unlock")
	check("rival" in kinds(director.candidates(880.0,count(5),13)),"The real candidate path admits a sixth after unlock")
	for full: int in [4,5,6]:
		check("swarm" not in kinds(director.candidates(1000.0,count(full),13)),"Deep full compositions suppress new swarm clutter")
	check("swarm" in kinds(director.candidates(1000.0,count(2),13)),"Deep Run still allows swarm variety away from the high-full composition")
	var old_wave: Dictionary=count(4,0,0,10);var before: Dictionary=old_wave.duplicate(true)
	check(director.candidates(1000.0,old_wave,13).is_empty() and old_wave==before,"A carried wave finishes normally and cannot sit under the fifth/sixth; policy changes no live state")
	check("boss" not in kinds(director.candidates(1000.0,count(4),13)),"Deep boss admission waits for readable support room")
	check("boss" in kinds(director.candidates(1000.0,count(3),13)),"Deep boss can join three meaningful supports")
	check(director.candidates(1000.0,count(4,1),13).is_empty(),"Boss dominance caps deep composition at boss plus three supports")
	check("boss" not in kinds(director.candidates(1000.0,count(2,1),13)),"Only one new deep boss reservation")
	check("elite" not in kinds(director.candidates(1000.0,count(4,0,2),13)),"Authored elite cap remains bounded inside the shared full count")
	var old_bosses: Dictionary=count(4,2);before=old_bosses.duplicate(true)
	check(director.candidates(1000.0,old_bosses,13).is_empty() and old_bosses==before,"Two previously admitted bosses finish without retroactive despawn or further stacking")
	var reached_five: bool=false;var reached_six: bool=false
	for seed_value: int in [421,7341,2026]:
		var sample: Dictionary=Model.simulate(seed_value,"durable")
		reached_five=reached_five or sample.first_five!=null;reached_six=reached_six or sample.first_six!=null
		check(sample==Model.simulate(seed_value,"durable"),"Identical seed/census fixture reproduces every admission and density sample")
		check(sample.violations.is_empty() and sample.bounded_state.history<=128 and sample.bounded_state.recent<=6 and sample.bounded_state.active<=6,"Deep policy remains within reserved budget/body/category/memory ceilings")
		check(sample.first_five==null or float(sample.first_five)>=640.0,"Observed fifth admission remains locked until deep time")
		check(sample.first_six==null or float(sample.first_six)>=880.0,"Observed sixth admission remains locked until absurd time")
	check(reached_five and reached_six,"Actual seeded Director admissions exercise both five and six under declared durable census fixtures")
	print("DEEP_RUN_DENSITY_003A1_%s checks=%d failures=%d"%["PASS" if failures==0 else "FAIL",checks,failures]);quit(1 if failures else 0)
