extends SceneTree
## Production-source integrity and presentation isolation, including new families.
const V=preload("res://scripts/signature_visuals.gd")
const P=preload("res://scripts/power_visuals.gd")
const A=preload("res://scripts/sound.gd")
const B=preload("res://scripts/battle.gd")
const E=preload("res://scripts/encounters.gd")
const S=preload("res://scripts/starters.gd")
const C=preload("res://scripts/run_powers.gd")
const IDS: Array[String]=["clutch","high_gear","orbit_drive","crash_guard","momentum_bank","predator_line","crosscut","clutch_ii","high_gear_ii","orbit_drive_ii","crash_guard_ii","momentum_bank_ii","predator_line_ii","crosscut_ii","terminal_velocity","flow_state","iron_comet","iron_comet_ii"]
var checks: int=0
var failures: int=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for group: String in ["effects","cards","icons"]:
		var m: Dictionary=P._meta("roster_"+group)
		var bytes: PackedByteArray=FileAccess.get_file_as_bytes("res://"+str(m.source))
		check(bytes.decode_u16(4)==0xA5E0 and bytes.decode_u16(12)==32,"Native editable RGBA master "+group)
		check(bytes.decode_u32(0)==bytes.size() and bytes.decode_u16(6)==int(m.frame_count),"Source integrity "+group)
		check(m.layers.size()==(2 if group=="icons" else (5 if group=="cards" else 4)),"Named separate normal layers "+group)
		for tag: String in m.tags:
			check(int(m.tags[tag].to)-int(m.tags[tag].from)==(0 if group=="icons" else 5),"Finite keyed tags "+tag)
			check(P._frame("roster_"+group,tag,0.0)==int(m.tags[tag].from),"Tag begins "+tag)
			check(P._frame("roster_"+group,tag,99.0)==int(m.tags[tag].to),"Tag ends "+tag)
	check(V.meta("roster").pivot==[48.0,48.0],"Effects retain fixed floor contact pivot")
	check(P.ROSTER_ICONS.get_size()==Vector2(IDS.size()*16,16),"Every roster row has its native 16px icon")
	check((load(C.ROSTER_CARD_SHEET) as Texture2D).get_size()==Vector2(384,IDS.size()*64),"Eighteen native card rows with six authored poses")
	for row: int in range(IDS.size()):
		check(P.icon_region(IDS[row])==Rect2(row*16,0,16,16),"Stable new family icon "+IDS[row])
		check(P.icon_texture(IDS[row])==P.ROSTER_ICONS,"Distinct roster HUD source "+IDS[row])
		var art_id: String=IDS[row]
		var power: Dictionary=C.get_mutation(art_id) if C.MUTATIONS.has(art_id) else (C.get_owned_power(art_id.trim_suffix("_ii"),2) if art_id.ends_with("_ii") else C.get_power(art_id))
		check(power.card_row==row and power.icon_frame==row and power.source_tag==art_id and power.card_texture==C.ROSTER_CARD_SHEET and power.icon==C.ROSTER_ICON_SHEET,"Catalogue uses dedicated native roster art "+art_id)
		var meta: Dictionary=P._meta("roster_cards")
		for frame: int in range(6):
			check(int(meta.durations_ms[row*6+frame])==int(power.card_durations_ms[frame]),"Catalogue/card timing agrees "+art_id+"/"+str(frame))
	check(not FileAccess.get_file_as_string("res://scripts/power_visuals.gd").contains("comet_headings"),"Rejected filled Iron Comet wedge is absent from active renderer")
	for tag: String in ["comet_charge","comet_flight","comet_impact","comet_recovery","overcap","heat_extreme","clutch_danger","clutch_recover","orbit_drift","ghost_preview","ghost_latch"]:
		check(V.meta("roster").tags.has(tag),"Required authored machine state "+tag)
	for cue: String in ["redline_overcap","redline_heat","clutch_activate","clutch_recover","high_gear_surge","ghost_preview","ghost_closure","comet_charge","comet_release","momentum_release","crash_guard","crosscut"]:
		check(A.SOUNDS.has(cue) and A.SOUNDS[cue].get_length()<0.5,"Finite event driven cue "+cue)
		if cue not in ["comet_charge","comet_release"]: check(float(A.COOLDOWN.get(cue,0.0))>0.0,"Cue retrigger protection "+cue)
	check(A.MAX_CHANNELS==8,"Audio allocation remains capped")
	var pair: Array[Dictionary]=[]
	for i: int in range(2):
		var b=B.new();root.add_child(b);b.set_physics_process(false)
		var d: Dictionary=E.for_run_event(1,7341)
		d.player_power_ids=["redline","high_gear","orbit_drive","afterimage","clutch","iron_comet"]
		d.player_power_ranks={"redline":3,"high_gear":3,"orbit_drive":2,"afterimage":3,"clutch":2,"iron_comet":2}
		d.player_power_mutations={"redline":"runaway","high_gear":"flow_state","afterimage":"ghost_circuit"}
		d.ability_rebalance=true
		b.begin_run(S.build_for("vane"),d,7341);b.battle_status="battle"
		b.particles_enabled=i==0;b.screen_shake_enabled=i==0
		pair.append({"host":b,"player":b.player_entity()})
	for tick: int in range(360):
		for entry: Dictionary in pair: entry.host.test_step(B.FIXED_DT,Vector2(sin(tick*.021),cos(tick*.027)),tick%240==0,tick%90>75)
		for field: String in ["pos","vel","rpm","wobble","height","cooldown","redline_heat","orbit_charge","momentum_charge"]:
			check(pair[0].player.get(field)==pair[1].player.get(field),"Cosmetic quality cannot change physical state "+field)
	for entry: Dictionary in pair:
		check(entry.host._power_fx.size()<=32,"Expanded late family FX remains bounded")
		check(is_same(entry.player,entry.host.player_entity()),"Continuous player identity preserved")
		entry.host.free()
	print("ROSTER_PRESENTATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
