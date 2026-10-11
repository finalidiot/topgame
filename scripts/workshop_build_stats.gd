extends RefCounted
## Presentation descriptions of the production assembly. No Run modifiers or
## independent stat formula are applied at this pre-run boundary.
const Catalog = preload("res://scripts/parts.gd")
const Starters = preload("res://scripts/starters.gd")

static func inspect(build: Dictionary) -> Dictionary:
	var clean: Dictionary = Catalog.validate_build(build)
	var ratings: Dictionary = Catalog.derive(clean)
	var physical: Dictionary = Catalog.derive_physics(clean)
	var notes: Array[String] = []
	var compact: Array[String] = []
	if float(ratings.power) >= 7.0: compact.append("Heavy attack")
	elif float(ratings.speed) >= 7.0: compact.append("Fast travel")
	if float(physical.rpm_drain) < 0.98:
		compact.append("Spin retention")
		notes.append("Passive and movement spin drain reduced by the assembled efficiency modifier; this does not restore RPM.")
	elif float(physical.rpm_drain) > 1.02:
		notes.append("The assembled efficiency modifier increases passive and movement spin drain.")
	if float(physical.acceleration) < 0.98 or float(physical.control) < 0.98 or float(physical.inertia) > 1.05:
		compact.append("Slower control")
		notes.append("Acceleration and steering are limited by the assembled control and rotational inertia modifiers.")
	elif float(physical.acceleration) > 1.02 or float(physical.control) > 1.02:
		notes.append("Assembly modifiers strengthen acceleration or steering; grip and low RPM still limit control.")
	if float(physical.brake) < 0.98:
		notes.append("Reduced braking drag: more momentum carries through Brake, so stopping takes longer.")
	elif float(physical.brake) > 1.02:
		notes.append("Stronger braking drag helps shed motion while Brake is held.")
	if float(physical.imbalance) > 0.001 or float(physical.sway) > 0.01:
		compact.append("Imbalance")
		notes.append("Off-centre mass adds real sway and wobble during travel; corrections remain necessary.")
	if float(physical.wobble_recovery) < 0.98:
		notes.append("The part recovery modifier slows wobble settling. Rotational inertia also contributes to the production recovery calculation.")
	elif float(physical.wobble_recovery) > 1.02:
		notes.append("The part recovery modifier helps wobble settle; it restores balance, not RPM.")
	if float(ratings.mass) >= 8.0:
		notes.append("High mass resists displacement through the collision solver, with greater momentum to redirect. Mass is a rating, not a defence score.")
	var starter_identity: String = Starters.identity_for_build(clean)
	var run_handling: Dictionary = Starters.HANDLING.get(starter_identity,{}).duplicate()
	if not run_handling.is_empty():
		var changes: Array[String] = []
		for row: Array in [["mass","heavier mass","lighter mass"],["acceleration","stronger acceleration","gentler acceleration"],["speed","a higher cruising limit","a lower cruising limit"],["impact","stronger hits","gentler hits"],["spin_drain","higher spin drain","reduced spin drain"],["recovery","faster wobble recovery","slower wobble recovery"]]:
			var modifier: float = float(run_handling.get(row[0],1.0))
			if modifier > 1.01: changes.append(row[1])
			elif modifier < .99: changes.append(row[2])
		notes.append("RUN ONLY / %s: %s. These handling modifiers are separate from the base ratings above; Quick Duel uses the ordinary parts." % [Starters.display_name(starter_identity),", ".join(changes)])
	if compact.is_empty(): compact.append("Inspect physical notes")
	return {"build":clean,"ratings":ratings,"physical":physical,"notes":notes,"summary":" / ".join(compact),"starter_identity":starter_identity,"run_handling":run_handling}

static func compare(equipped: Dictionary, preview: Dictionary) -> Dictionary:
	var current: Dictionary = inspect(equipped)
	var candidate: Dictionary = inspect(preview)
	var deltas: Dictionary = {}
	for stat: String in Catalog.STAT_IDS:
		deltas[stat] = float(candidate.ratings[stat]) - float(current.ratings[stat])
	return {"current":current,"preview":candidate,"deltas":deltas,"is_preview":current.build != candidate.build}
