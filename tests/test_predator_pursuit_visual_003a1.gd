extends SceneTree
## Semantic motion-plan fixtures; native earned-contact movie is separate.
const Identity=preload("res://scripts/power_identity.gd")
var checks: int=0
var failures: Array[String]=[]
var report: String=""
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
	var target: Dictionary={"entity_id":2,"pos":Vector2(70,15),"outcome":""}
	var actor: Dictionary={"entity_id":1,"pos":Vector2.ZERO,"vel":Vector2(160,0),"hunt_stacks":2,"hunt_target":2,"outcome":"","powers":["predator_line"],"power_ranks":{"predator_line":2}}
	Identity.reset_motion()
	for tick: int in range(24):
		actor.pos=Vector2(tick*2.0,sin(float(tick)*.12)*5.0)
		Identity.observe_motion([actor,target],float(tick)/60.0)
	var before: Dictionary=actor.duplicate(true);var history: Dictionary=Identity.motion_history.duplicate(true)
	var plan: Dictionary=Identity.predator_plan(actor,target,23.0/60.0)
	check(history.has(1) and history[1].size()>2,"Real presentation observer supplies sampled owner motion")
	check(bool(plan.active),"Earned-stack moving pursuit has an active short motion cue")
	check(plan.points.size()>=2 and plan.points.size()<=Identity.MOTION_POINTS+1,"Cue uses bounded actual recent motion samples")
	check(Vector2(plan.points[-1])==Vector2(actor.pos),"Cue ends at its moving owner")
	check(Vector2(plan.points[0]).distance_to(actor.pos)<=52.0,"Cue stays close behind moving owner")
	check(not PackedVector2Array(plan.points).has(Vector2(target.pos)),"Pursuit cue does not form a beam or lane to hostile target")
	check(actor==before and Identity.motion_history==history,"Planning is read-only for gameplay and motion history")
	actor.hunt_stacks=0;check(not bool(Identity.predator_plan(actor,target,.4).active),"Unpaid/unearned hunt has no pursuit cue")
	actor.hunt_stacks=2;actor.vel=Vector2(12,0);check(not bool(Identity.predator_plan(actor,target,.4).active),"Slow stationary top has no misleading trailing pursuit")
	actor.vel=Vector2(160,0);actor.outcome="spin_out";check(not bool(Identity.predator_plan(actor,target,.4).active),"Eliminated owner has no pursuit cue")
	actor.outcome="";target.pos=Vector2(400,0);check(not bool(Identity.predator_plan(actor,target,.4).active),"Lost distant target removes pursuit cue")
	check(not bool(Identity.predator_plan(actor,{},.4).active),"Missing target removes pursuit cue")
	Identity.reset_motion();check(Identity.motion_history.is_empty(),"Restart discards old motion geometry")
	if not report.is_empty():
		var f:=FileAccess.open(report,FileAccess.WRITE);check(f!=null,"External visual contract report can be opened")
		if f!=null:f.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Semantic read-only motion-plan gates/bounds; renderer before/after and actual contact-earned native normal/ReducedFlashing movie provide separate visual evidence."},"\t"));f.close()
	print("PREDATOR_PURSUIT ",checks," checks, ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
