extends RefCounted
class_name EncounterCatalog

const Seeds = preload("res://scripts/seed_utils.gd")
const SLOT_COUNT: int = 8
const DRAFT_SLOTS: Array[int] = [1, 2, 3, 4, 6, 7]

## Intended encounter identity is retained for later implementation. Every
## Task 002A slot explicitly resolves as an ordinary duel with baseline AI.
const SLOTS: Array[Dictionary] = [
	{"type":"standard_duel", "name":"Standard Duel", "build":{"blade":"balance", "ratchet":"mid", "bit":"ball"}},
	{"type":"specialist_duel", "name":"Specialist / Vane", "build":{"blade":"hook", "ratchet":"mid", "bit":"rubber"}},
	{"type":"swarm", "name":"Swarm Event", "build":{"blade":"smash", "ratchet":"low", "bit":"flat"}},
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
	return {
		"id":encounter_id, "slot_id":encounter_id, "slot":slot,
		"type":source.type, "name":source.name,
		"fixture":true, "fixture_type":"duel", "fixture_label":"DUEL FIXTURE",
		"opponent_build":source.build.duplicate(true),
		"behavior_profile":"pursuit", "arena_modifier":"none",
		"objective":"defeat_hostiles", "live_time_limit":60.0,
		"seed":Seeds.derive(run_seed, "encounter/" + encounter_id),
		"selection_seed":Seeds.derive(run_seed, "encounter_selection/" + encounter_id),
		"boss_parameters":{}, "opponent_power_ids":[],
		"draft_after":has_draft(slot)
	}
