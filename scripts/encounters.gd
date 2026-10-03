extends RefCounted
class_name EncounterCatalog

const Seeds = preload("res://scripts/seed_utils.gd")
const SLOT_COUNT: int = 8
# Power growth now comes from Run XP. Keep this descriptor seam available for
# future authored encounter rewards without adding a second menu cadence.
const DRAFT_SLOTS: Array[int] = []

## Slot 3 is the first real swarm. Later rival/elite/arena/boss identities
## remain ordinary duel fixtures until Task 002C.
const SLOTS: Array[Dictionary] = [
	{"type":"standard_duel", "name":"Standard Duel", "build":{"blade":"balance", "ratchet":"mid", "bit":"ball"}},
	{"type":"specialist_duel", "name":"Specialist / Vane", "build":{"blade":"hook", "ratchet":"mid", "bit":"rubber"}},
	{"type":"swarm", "name":"Ammunition Waves", "build":{"blade":"smash", "ratchet":"low", "bit":"flat"}},
	{"type":"elite_duel", "name":"Iron Comet Elite", "build":{"blade":"smash", "ratchet":"low", "bit":"flat"}},
	{"type":"arena_event", "name":"Arena Event", "build":{"blade":"balance", "ratchet":"high", "bit":"ball"}},
	{"type":"rival_rematch", "name":"Vane Rematch", "build":{"blade":"hook", "ratchet":"mid", "bit":"rubber"}},
	{"type":"elite_duel", "name":"Redline Elite", "build":{"blade":"balance", "ratchet":"high", "bit":"flat"}},
	{"type":"boss", "name":"Crown Engine", "build":{"blade":"guard", "ratchet":"high", "bit":"rubber"}}
]

static func has_draft(slot: int) -> bool:
	return slot in DRAFT_SLOTS

static func for_slot(slot: int, run_seed: int) -> Dictionary:
	if slot < 1 or slot > SLOT_COUNT: return {}
	var source: Dictionary = SLOTS[slot - 1]
	var encounter_id: String = "run_slot_%02d" % slot
	var is_swarm: bool = slot == 3
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
