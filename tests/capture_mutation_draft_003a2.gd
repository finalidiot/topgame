extends SceneTree
## Ordinary Main claim handlers and live controls; XP awards are declared inputs.
class QuietMain extends "res://scripts/main.gd":
	func _smoke_test() -> void:pass
const Run = preload("res://scripts/run_context.gd")
const Starters = preload("res://scripts/starters.gd")
const Battle = preload("res://scripts/battle.gd")
const Draft = preload("res://tests/mutation_draft_policy_003a2.gd")
var output: String=""
var prefix: String=""
var frame_dir: String=""
var diagnostic: bool=false
var movie_frames: int=0
var failures: Array[String]=[]
var rows: Array[Dictionary]=[]
var features: Dictionary={}
var claims: Array[Dictionary]=[]
var xp_events: Array[Dictionary]=[]
var serial: int=0
var clock_failures: int=0
var game: QuietMain

func _initialize() -> void:call_deferred("run")
func xp_event(r: RefCounted) -> Dictionary:
	serial+=1
	return {"kind":"elimination","encounter_id":r.current_encounter().id,"time":float(serial)/60.0,"entity_id":100000+serial,"combatant_type":"full_top","reason":"spin_out","player_attributed":true}
func model_level(r: RefCounted) -> void:
	for tick: int in range(200):
		if not r.pending_offer.is_empty():return
		r.award_xp(xp_event(r))
func find_seed() -> int:
	for seed_value: int in range(1,513):
		var r: RefCounted=Run.new();r.start(Starters.build_for("vane"),seed_value,"vane")
		if not "momentum_bank" in r.pending_offer:continue
		r.choose_power(r.pending_draft_id,"momentum_bank");model_level(r)
		if not "momentum_bank" in r.pending_offer:continue
		r.choose_power(r.pending_draft_id,"momentum_bank");model_level(r)
		if "momentum_bank" in r.pending_offer:return seed_value
	return -1
func choose_power() -> void:
	var r: RefCounted=game.run_context
	claims.append({"token":r.pending_draft_id,"offer":r.pending_offer.duplicate(),"rank_before":r.power_ranks.get("momentum_bank",0),"chosen":"momentum_bank"})
	game._action("choose_power",{"encounter_id":r.pending_draft_id,"power_id":"momentum_bank","run_seed":r.run_seed,"offer_revision":r.reroll_snapshot().revision})
	game.battle.set_physics_process(false)
func actual_level() -> void:
	for tick: int in range(200):
		if not game.run_context.pending_offer.is_empty():return
		var event: Dictionary=xp_event(game.run_context);xp_events.append(event)
		game._progression_events([event])

func render(feature: String="") -> void:
	game.battle.queue_redraw();game.top_status_bars.queue_redraw()
	if movie_frames%6==0 or not feature.is_empty():
		rows.append({"frame":movie_frames,"screen":game.screen,"battle_status":game.battle.battle_status,"progress":game.run_context.progression_snapshot(),"powers":game.battle.player_entity().get("power_ranks",{}).duplicate(true),"public":game.battle.powers.public_state(game.battle.player_entity()),"economy":game.battle.continuous.economy.snapshot()})
	if not diagnostic:
		await process_frame;await RenderingServer.frame_post_draw
		if not feature.is_empty():
			var path: String=frame_dir.path_join(feature+".png")
			if root.get_texture().get_image().save_png(path)!=OK:failures.append("Could not save "+feature)
			features[feature]={"path":path,"frame":movie_frames}
	movie_frames+=1
func menu_frames(count: int, label: String) -> void:
	for tick: int in range(count):
		await render(label if tick==0 else "")
		game._process(Battle.FIXED_DT);game.battle.set_physics_process(false)
		if game.screen=="battle" and game.battle.battle_status=="reentry":game.battle.test_step(Battle.FIXED_DT)

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--manifest="):output=arg.trim_prefix("--manifest=")
		if arg.begins_with("--collection-prefix="):prefix=arg.trim_prefix("--collection-prefix=")
		if arg.begins_with("--frames="):frame_dir=arg.trim_prefix("--frames=")
		if arg=="--diagnostic":diagnostic=true
	if not output.is_absolute_path() or FileAccess.file_exists(output) or not prefix.is_absolute_path():quit(2);return
	root.size=Vector2i(800,480);root.content_scale_size=Vector2i(800,480);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if not frame_dir.is_empty():DirAccess.make_dir_recursive_absolute(frame_dir)
	var seed_value: int=find_seed();serial=0
	if seed_value<0:push_error("No real consecutive Bank investment seed");quit(2);return
	game=QuietMain.new();game.smoke_mode=true;game.review_audio=not diagnostic;game.qa_task_id="003A.2";game.collection_path=prefix+"_draft.json"
	if FileAccess.file_exists(game.collection_path):quit(2);return
	root.add_child(game);game.set_process(false);game.battle.set_physics_process(false)
	game.collection.initialize_starter("vane")
	game.music.configure_playback(not diagnostic)
	game.run_context.start(game.collection.equipped_build(),seed_value,"vane");game.mode="run";game._show_reward();choose_power();game._process(.6);game.battle.set_physics_process(false)
	var b: Node2D=game.battle
	while b.battle_status!="battle":b.test_step(Battle.FIXED_DT)
	actual_level();game._process(.2);choose_power()
	if game.screen!="acquisition" or int(game.run_context.power_ranks.get("momentum_bank",0))!=2:failures.append("RankII was not legally acquired")
	# One disclosed initial physical arrangement is set while RankII is paused.
	# No physical state, reserve, store or outcome is written afterward.
	b.player_entity().pos=Vector2(-70,0);b.player_entity().vel=Vector2(300,0);b.entity(2).pos=Vector2(100,35);b.entity(2).vel=Vector2.ZERO
	b.continuous.reward_fixture=true;b.continuous.director.next_decision=99999.;b.continuous.director.calm_until=99999.
	var initial: Dictionary={"seed":seed_value,"build":b.player_entity().build,"player_position":b.player_entity().pos,"player_velocity":b.player_entity().vel,"enemy_position":b.entity(2).pos,"enemy_velocity":b.entity(2).vel,"clocks":[b.elapsed,b.powers.time,b.roster.time,b.roster.ecology.time],"initial_power_state":b.powers.public_state(b.player_entity())}
	await menu_frames(150,"rank_ii_acquired")
	if game.screen!="battle" or b.battle_status!="battle":failures.append("RankII reentry did not complete normally")
	actual_level()
	if game.screen!="level_up":failures.append("XP input did not enter actual level-up seam")
	await menu_frames(14,"actual_level_up")
	if game.screen!="reward" or not "momentum_bank" in game.run_context.pending_offer:failures.append("RankIII was not a real eligible offer")
	await menu_frames(90,"rank_iii_offer");choose_power()
	var siblings: Array=game.run_context.pending_mutation_offer.duplicate()
	if game.screen!="mutation" or siblings!=["flywheel_release","countersteer"]:failures.append("Actual sibling choice pair missing")
	await menu_frames(150,"two_mutations")
	game._action("choose_mutation",{"encounter_id":game.run_context.pending_draft_id,"branch_id":"flywheel_release","run_seed":game.run_context.run_seed,"offer_revision":game.run_context.reroll_snapshot().revision})
	game.battle.set_physics_process(false)
	await menu_frames(150,"mutation_selected")
	var released: bool=false;var previous: int=0
	for tick: int in range(600):
		var p: Dictionary=b.player_entity();var direction: Vector2=Vector2.RIGHT*.8;var braking: bool=not released;var burst: bool=false
		if not released and float(p.get("momentum_charge",0.0))>=75.0:
			released=true;braking=false;burst=true;direction=(Vector2(b.entity(2).pos)-Vector2(p.pos)).normalized()
		elif released:direction=(Vector2(b.entity(2).pos)-Vector2(p.pos)).normalized()*.6
		var screen_direction: Vector2=Vector2(direction.x-direction.y,(direction.x+direction.y)*.5).normalized()*minf(1.0,direction.length())
		b.test_step(Battle.FIXED_DT,screen_direction,burst,braking);b._emit_hud();game._process(Battle.FIXED_DT)
		var count: int=int(b.roster.ecology.counters.get("flywheel_release",0))
		await render("earned_flywheel_release" if count>previous else ("runtime" if tick==0 else ""));previous=count
		if not is_equal_approx(b.elapsed,b.powers.time) or not is_equal_approx(b.elapsed,b.roster.time) or not is_equal_approx(b.elapsed,b.roster.ecology.time):clock_failures+=1
	var events: Dictionary=b.roster.ecology.counters.duplicate();var final: Dictionary={"actors":[],"economy":b.continuous.economy.snapshot(),"events":b.powers.events.duplicate(true)}
	for actor: Dictionary in b.fighters:final.actors.append({"id":actor.entity_id,"pos":actor.pos,"vel":actor.vel,"rpm":actor.rpm,"outcome":actor.outcome})
	if int(events.get("flywheel_release",0))==0:failures.append("No control-earned Flywheel release")
	if clock_failures>0:failures.append("Live clocks diverged")
	var chosen: String=str(game.run_context.power_mutations.get("momentum_bank",""));var rank: int=int(game.run_context.power_ranks.get("momentum_bank",0))
	game.review_audio=false;game.music.configure_playback(false);game.sounds.grind_provider=Callable();game.sounds._grind_player.stop()
	for channel: AudioStreamPlayer in game.sounds.channels:channel.stop();channel.stream=null
	var tail: int=0
	if not diagnostic:
		for tick: int in range(36):await process_frame;movie_frames+=1;tail+=1
	game.free();await process_frame
	var data: Dictionary={"schema":"003a2-actual-mutation-draft-v1","movie_frames":movie_frames,"tail_frames":tail,"diagnostic":diagnostic,"features":features,"rows":rows,"legal_claims":claims,"two_actual_siblings":siblings==["flywheel_release","countersteer"],"siblings":siblings,"chosen_branch":chosen,"final_rank":rank,"xp_fixture_events":xp_events,"initial":initial,"final":final,"runtime_events":events,"clock_failures":clock_failures,"failures":failures,"authenticity":"Actual Main legal BankI/II/III claim handlers and real seeded offers. Declared attributed elimination XP inputs cause ordinary level-up; both actual siblings are shown and chosen once. Isolated Vane starter profile. Only one paused initial physical pose/velocity arrangement; subsequent normal READY, scripted ordinary movement/Brake/Burst and real opponent pilot/solver earn store/release. No ongoing reserve/charge/pose/effects/outcome writes. Not natural XP timing, human input or natural survival evidence."}
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(Draft.portable(data),"\t"));file.close()
	print("MUTATION_DRAFT_CAPTURE_%s frames=%d failures=%s"%["PASS" if failures.is_empty() else "FAIL",movie_frames,failures]);quit(0 if failures.is_empty() else 1)
