extends RefCounted
class_name EncounterCatalog

const Seeds = preload("res://scripts/seed_utils.gd")
# Power growth now comes from Run XP. Keep this descriptor seam available for
# future authored encounter rewards without adding a second menu cadence.
const DRAFT_SLOTS: Array[int] = []

## Temporary continuous-run script, not a procedural director. Repeat this
## authored cycle indefinitely; threat identity and seeds use the absolute index.
const SLOTS: Array[Dictionary] = [
	{"type":"standard_duel", "name":"Standard Rival", "build":{"blade":"balance", "ratchet":"mid", "bit":"ball"}},
	{"type":"specialist_duel", "name":"Hook Rival", "build":{"blade":"hook", "ratchet":"mid", "bit":"rubber"}},
	{"type":"swarm", "name":"Ammunition Waves", "build":{"blade":"smash", "ratchet":"low", "bit":"flat"}},
	{"type":"heavy_duel", "name":"Smash Rival", "build":{"blade":"smash", "ratchet":"low", "bit":"flat"}}
]

static func has_draft(slot: int) -> bool:
	return slot in DRAFT_SLOTS

static func for_slot(slot: int, run_seed: int) -> Dictionary:
	if slot < 1: return {}
	var source: Dictionary = SLOTS[(slot - 1) % SLOTS.size()]
	var encounter_id: String = "run_slot_%02d" % slot
	var is_swarm: bool = source.type == "swarm"
	return {
		"id":encounter_id, "slot_id":encounter_id, "slot":slot,
		"type":source.type, "name":source.name,
		"fixture":not is_swarm, "fixture_type":"swarm" if is_swarm else "duel", "fixture_label":"AMMUNITION WAVES" if is_swarm else "DUEL FIXTURE",
		"opponent_build":source.build.duplicate(true),
		"behavior_profile":"pursuit", "arena_modifier":"none",
		"objective":"clear_schedule" if is_swarm else "defeat_hostiles", "live_time_limit":32.0 if is_swarm else 60.0,
		"swarm_parameters":{"waves":[6, 8, 10], "wave_times":[0.0, 9.0, 18.0], "active_cap":12, "cleanup_time":32.0} if is_swarm else {},
		"seed":Seeds.derive(run_seed, "encounter/" + encounter_id),
		"selection_seed":Seeds.derive(run_seed, "encounter_selection/" + encounter_id),
		"boss_parameters":{}, "opponent_power_ids":[],
		"draft_after":has_draft(slot)
	}
