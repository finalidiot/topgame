extends RefCounted
class_name RunPowerCatalog

const IdentityArt = preload("res://scripts/power_identity.gd")
const DefenceArt = preload("res://scripts/defence_art.gd")
const CardStyle = preload("res://scripts/ability_card_style.gd")

## Catalogue identity stays stable as the implemented draft pool grows.
## Physical Blade / Ratchet / Bit ratings remain exclusively in parts.gd.
const IDS: Array[String] = [
	"impact_wake", "second_wind", "redline", "iron_comet", "dead_centre", "afterimage",
	"reversal", "chain_impact", "slip_gear", "rim_runner", "flywheel_cache", "crosscut",
	"clutch", "high_gear", "orbit_drive", "crash_guard", "momentum_bank", "predator_line",
	"gyro_lock", "impact_sink", "anchor_exchange"
]
const ACTIVE_IDS: Array[String] = ["impact_wake", "redline", "iron_comet", "dead_centre", "afterimage", "chain_impact", "clutch", "high_gear", "orbit_drive", "crash_guard", "momentum_bank", "predator_line", "crosscut", "gyro_lock", "impact_sink", "anchor_exchange"]
const VERTICAL_IDS: Array[String] = ["redline", "dead_centre", "afterimage", "high_gear", "gyro_lock", "impact_sink", "anchor_exchange"]
const FAMILY_CAP: int = 7
# Retired IDs remain readable for historical fixtures; normal drafts use ACTIVE_IDS.
const LEGACY_OWNED_IDS: Array[String] = ["second_wind"]
const ROSTER_ART_IDS: Array[String] = ["clutch","high_gear","orbit_drive","crash_guard","momentum_bank","predator_line","crosscut","clutch_ii","high_gear_ii","orbit_drive_ii","crash_guard_ii","momentum_bank_ii","predator_line_ii","crosscut_ii","terminal_velocity","flow_state","iron_comet","iron_comet_ii"]
const ROSTER_ICON_SHEET: String = "res://assets/powers/roster_icons.png"
const ROSTER_CARD_SHEET: String = "res://assets/powers/roster_cards.png"
const ART_ALIASES: Dictionary = {"impact_wake_ii":"impact_wake","chain_impact_ii":"chain_impact"}
# Existing production atlas indexes remain stable as the active pool grows.
const LEGACY_ART_IDS: Array[String] = ["impact_wake", "second_wind", "redline", "iron_comet", "afterimage", "chain_impact"]
const ESCALATION_ART_IDS: Array[String] = ["dead_centre", "redline_ii", "dead_centre_ii", "afterimage_ii", "runaway", "breakneck", "bulwark", "counterweight", "ghost_circuit", "slipstream"]
const ICON_SHEET: String = "res://assets/powers/icons.png"
const CARD_SHEET: String = "res://assets/powers/cards.png"
const ESCALATION_ICON_SHEET: String = "res://assets/powers/escalation_icons.png"
const ESCALATION_CARD_SHEET: String = "res://assets/powers/escalation_cards.png"
const MUTATION_BRANCHES: Dictionary = {
	"redline":["runaway", "breakneck"],
	"dead_centre":["bulwark", "counterweight"],
	"afterimage":["ghost_circuit", "slipstream"],
	"high_gear":["terminal_velocity", "flow_state"],
	"gyro_lock":["keel", "flywheel"],
	"impact_sink":["shock_bleed", "return_spring"],
	"anchor_exchange":["deep_footing", "slip_anchor"]
}
# Native 64px, six discrete poses per row. Presentation reads source timing.
const CARD_DURATIONS_MS: Array[int] = [110, 90, 75, 75, 100, 170]
const CARD_STATIC_FRAMES: Dictionary = {"impact_wake":2, "second_wind":3, "redline":2, "iron_comet":4, "afterimage":3, "chain_impact":4}
const CARD_COPY: Dictionary = {
	"impact_wake": {"category":"IMPACT", "copy":"Heavy hits shove nearby rivals."},
	"second_wind": {"category":"RECOVERY", "copy":"Once per launch, recover from near spin-out."},
	"redline": {"category":"OVERCLOCK", "copy":"Burst. Move fast. Hit hard. Heat risks control."},
	"iron_comet": {"category":"RICOCHET", "copy":"Hard wall rebound. Spend the next hit quickly."},
	"dead_centre": {"category":"ANCHOR", "copy":"Hold centre. Weather hits. Reposition to vent Stress."},
	"afterimage": {"category":"MOBILITY", "copy":"Fast travel lays paid trails that shove rivals."},
	"chain_impact": {"category":"CHAIN", "copy":"Hard hits shove nearby rivals. Burst to follow up."},
	"clutch": {"category":"COMEBACK", "copy":"Low spin: steer gently and land hits to recover."},
	"high_gear": {"category":"SPEED", "copy":"More thrust and speed. Plan your line."},
	"orbit_drive": {"category":"DRIFT", "copy":"Build DRIVE. Carve at 100% to earn RPM."},
	"crash_guard": {"category":"BRAWL", "copy":"Weather a heavy hit. Use the brief guarded window."},
	"momentum_bank": {"category":"BRAKE", "copy":"Steer + Brake to bank. Burst to release."},
	"predator_line": {"category":"PRESSURE", "copy":"Keep hitting one rival. Chase its growing mark."},
	"crosscut": {"category":"SHEAR", "copy":"Steer across a glance. Pay RPM for a sideways cut."},
	"gyro_lock": {"category":"CONTROLLED DEFENCE", "copy":"Steer smoothly while moving. Build a moving brace."},
	"impact_sink": {"category":"SHOCK STORAGE", "copy":"Store real recoil. Tap Brake slowly to recover."},
	"anchor_exchange": {"category":"ACTIVE BRACE", "copy":"Hold Brake near rest. Pay RPM for heavy footing."}
}
const CONDITIONS: Dictionary = {
	"impact_wake":"Heavy hit / brief cooldown",
	"second_wind":"Low spin or severe wobble / once per launch",
	"redline":"Burst with 13%+ RPM / fast movement and hard hits / heat and spin cost",
	"iron_comet":"Hard wall rebound / next contact / charge expires after 2 seconds",
	"dead_centre":"Settled centre hold / pressure builds Stress / steer away to vent / outside movement reloads finite recovery",
	"afterimage":"Fast movement / each new trail costs RPM / trails expire",
	"chain_impact":"Accepted hard hit / nearby physical shove / Burst within the short follow-up window / owner cooldown",
	"clutch":"Low RPM window / controlled movement and meaningful hits / finite recovery",
	"high_gear":"Movement / hard turns and braking still cost RPM",
	"orbit_drive":"Moving curves build DRIVE / Brake + turn builds faster / 100% DRIVE with fast active steering earns capped RPM / straightening, slowing and reversal lose charge",
	"crash_guard":"Heavy incoming hit / brief damper / cooldown",
	"momentum_bank":"Controlled braking outside a drift / capped leaking storage / Burst spends store and RPM",
	"predator_line":"Repeated meaningful hits on one full rival / switching or waiting loses pursuit",
	"crosscut":"Moving glancing contact / lateral steering / RPM cost and recoil",
	"gyro_lock":"Smooth moving steering off Brake / idle, sharp turns or Burst break lock",
	"impact_sink":"Stored recoil / fresh Brake below high speed / finite storage and vent cooldown",
	"anchor_exchange":"Held Brake below 78 speed / ongoing RPM cost / release to move"
}
const DEFINITIONS: Dictionary = {
	"impact_wake": {"id":"impact_wake", "name":"Impact Wake", "description":"Land a heavy hit to shove nearby rivals with a pressure ring. Small taps do not trigger it; each ring has a short cooldown.", "short_label":"WAKE", "tags":["impact"], "icon":"", "active":true},
	"second_wind": {"id":"second_wind", "name":"Second Wind", "description":"Once each launch, near spin-out triggers a dramatic recovery.", "short_label":"WIND", "tags":["recovery"], "icon":"", "active":true},
	"redline": {"id":"redline", "name":"Redline", "description":"Burst to overclock. Fast controlled movement and hard hits earn excess RPM; heat makes steering, braking and recovery worse. The overclock spends RPM. Anchoring during Redline builds extra Anchor Stress.", "short_label":"RED", "tags":["burst", "risk"], "icon":"", "active":true},
	"iron_comet": {"id":"iron_comet", "name":"Iron Comet", "description":"Rebound hard off a wall, then hit a rival before the charge fades. The charged contact delivers an extra shove.", "short_label":"COMET", "tags":["wall", "impact"], "icon":"", "active":true},
	"dead_centre": {"id":"dead_centre", "name":"Dead Centre", "description":"Settle near the middle to brace, recover limited RPM and pull rivals inward. Hits and anchor work build Stress, weakening the hold. Steer away with the anchor released to vent; moving outside reloads recovery.", "short_label":"CENTRE", "tags":["position", "defence"], "icon":"", "active":true},
	"afterimage": {"id":"afterimage", "name":"Afterimage", "description":"Move fast to leave live trails that push crossing rivals sideways. Every trail spends RPM and expires after a few seconds.", "short_label":"ECHO", "tags":["mobility"], "icon":"", "active":true},
	"reversal": {"id":"reversal", "name":"Reversal", "description":"Brake after a hard unstable hit to turn recoil into recovery.", "short_label":"REV", "tags":["brake", "recovery"], "icon":"", "active":false},
	"chain_impact": {"id":"chain_impact", "name":"Chain Impact", "description":"An accepted hard hit sends a physical shove through nearby rivals and opens a short Burst follow-up. Burst near the struck rival before the window expires. Each chain has an owner cooldown; knockouts alone do not trigger it.", "short_label":"CHAIN", "tags":["impact", "burst"], "icon":"", "active":true},
	"slip_gear": {"id":"slip_gear", "name":"Slip Gear", "description":"Brake, turn, then Burst to release stored momentum.", "short_label":"SLIP", "tags":["brake", "mobility"], "icon":"", "active":false},
	"rim_runner": {"id":"rim_runner", "name":"Rim Runner", "description":"Brake along a solid wall to ride its edge and choose your exit.", "short_label":"RIM", "tags":["brake", "wall"], "icon":"", "active":false},
	"flywheel_cache": {"id":"flywheel_cache", "name":"Flywheel Cache", "description":"Bank a little early spin and release it when reserve gets low.", "short_label":"CACHE", "tags":["reserve", "recovery"], "icon":"", "active":false},
	"crosscut": {"id":"crosscut", "name":"Crosscut", "description":"Steer sideways through a moving, glancing hit to shear the rival away. Each cut costs RPM and gives your own top some recoil.", "short_label":"CUT", "tags":["impact", "mobility"], "icon":"", "active":true},
	"clutch": {"id":"clutch", "name":"Clutch", "description":"Low RPM opens a short recovery window. Gentle controlled movement saves spin; meaningful moving hits reclaim a limited amount. Clutch cannot revive a defeated top.", "short_label":"CLUTCH", "tags":["recovery", "defence"], "icon":"", "active":true},
	"high_gear": {"id":"high_gear", "name":"High Gear", "description":"Steer to accelerate harder and reach a higher speed. Plan your line: hard steering and braking still spend RPM.", "short_label":"GEAR", "tags":["mobility", "speed"], "icon":"", "active":true},
	"orbit_drive": {"id":"orbit_drive", "name":"Orbit Drive", "description":"Steer a sustained curve to build DRIVE. Brake and turn while moving to build it faster. DRIVE adds speed, thrust and efficiency. At exactly 100%, fast active carving earns capped RPM recovery. Straightening, slowing or reversing loses charge; idle movement earns nothing.", "short_label":"ORBIT", "tags":["mobility", "efficiency"], "icon":"", "active":true},
	"crash_guard": {"id":"crash_guard", "name":"Crash Guard", "description":"A heavy incoming contact triggers a brief damper that reduces collision loss. Use the guarded window before its cooldown.", "short_label":"GUARD", "tags":["defence", "impact"], "icon":"", "active":true},
	"momentum_bank": {"id":"momentum_bank", "name":"Momentum Bank", "description":"Steer while braking to bank some lost motion. Burst to release it along your chosen line. Storage leaks, is capped, and its release costs extra RPM.", "short_label":"BANK", "tags":["brake", "burst"], "icon":"", "active":true},
	"predator_line": {"id":"predator_line", "name":"Predator Line", "description":"Keep landing meaningful hits on the same full-size rival to strengthen pursuit and follow-up hits. Switching targets or waiting loses the pressure.", "short_label":"HUNT", "tags":["impact", "pressure"], "icon":"", "active":true},
	"gyro_lock": {"id":"gyro_lock", "name":"Gyro Lock", "description":"Steer smoothly while moving off Brake to build a displacement-resistant lock. Watch it steady your line; idle, sharp correction and Burst break it.", "short_label":"GYRO", "tags":["defence", "control"], "icon":"", "active":true},
	"impact_sink": {"id":"impact_sink", "name":"Impact Sink", "description":"Take real incoming recoil to fill a finite STORED FORCE reservoir. Tap Brake at low speed to spend it on RPM and wobble recovery. Unused force leaks; holding Brake cannot vent again.", "short_label":"SINK", "tags":["defence", "recovery", "brake"], "icon":"", "active":true},
	"anchor_exchange": {"id":"anchor_exchange", "name":"Anchor Exchange", "description":"Hold Brake near rest to pay RPM for heavy portable footing. Braces resist shoves but slow you. Release Brake and steer to reposition; a developed paid brace can ease Dead Centre Stress.", "short_label":"BRACE", "tags":["defence", "brake"], "icon":"", "active":true}
}

const RANK_II: Dictionary = {
	"redline": {"name":"Redline II", "description":"Burst for stronger thrust and impacts than Rank I. Activation costs more RPM and wobble; heat still worsens control, especially while anchored.", "card_copy":"Hotter thrust and hits. Higher RPM and control cost.", "category":"HOT OVERDRIVE", "short_label":"RED II", "art_id":"redline_ii"},
	"dead_centre": {"name":"Dead Centre II", "description":"Build a stronger central brace sooner and hold a larger finite recovery reserve. Stress still weakens anchoring; steer out to vent and reload before returning.", "card_copy":"Stronger brace. More recovery. Manage Stress.", "category":"GROUND LOCK", "short_label":"CENTRE II", "art_id":"dead_centre_ii"},
	"afterimage": {"name":"Afterimage II", "description":"Fast travel leaves longer, stronger trails. Cross your own live old trail for a small speed surge. New trails still cost RPM.", "card_copy":"Longer trails. Cross yours for a speed surge.", "category":"LIVE ROUTE", "short_label":"ECHO II", "art_id":"afterimage_ii"},
	"impact_wake": {"name":"Impact Wake II", "description":"Heavy hits make wider, stronger pressure rings with a shorter cooldown. Small taps still do nothing.", "card_copy":"Wider, stronger wakes. Shorter cooldown.", "category":"IMPACT", "short_label":"WAKE II", "art_id":"impact_wake_ii"},
	"iron_comet": {"name":"Iron Comet II", "description":"A hard wall rebound holds charge longer. Spend the next contact on a rival for a stronger shove before the charge expires.", "card_copy":"Stronger rebound strike. Charge lasts longer.", "category":"REBOUND STRIKE", "short_label":"COMET II", "art_id":"iron_comet_ii"},
	"chain_impact": {"name":"Chain Impact II", "description":"Accepted hard hits send wider, stronger physical shoves and open a longer, stronger nearby Burst follow-up. The owner cooldown is shorter than Rank I; knockouts alone do not trigger a chain.", "card_copy":"Hard hits: wider chains, stronger Burst follow-up.", "category":"CHAIN", "short_label":"CHAIN II", "art_id":"chain_impact_ii"},
	"clutch": {"name":"Clutch II", "description":"Low RPM opens a longer recovery chance. Controlled movement conserves more spin; meaningful moving hits earn a larger finite catch.", "card_copy":"Longer Clutch window. More earned recovery.", "category":"COMEBACK", "short_label":"CLUTCH II", "art_id":"clutch_ii"},
	"high_gear": {"name":"High Gear II", "description":"Gain more thrust and speed than Rank I, with better retained motion on a committed line. Steering and braking still cost RPM.", "card_copy":"More thrust, speed and retained motion.", "category":"HIGH SPEED", "short_label":"GEAR II", "art_id":"high_gear_ii"},
	"orbit_drive": {"name":"Orbit Drive II", "description":"DRIVE adds more speed and RPM efficiency; Brake-turn drifts carve more strongly. At exactly 100%, fast active carving earns more capped RPM recovery than Rank I. Sustained curves still build charge at the same rate as Rank I; idle movement earns nothing.", "card_copy":"Stronger carve. More RPM at 100% DRIVE.", "category":"DRIFT FLOW", "short_label":"ORBIT II", "art_id":"orbit_drive_ii"},
	"crash_guard": {"name":"Crash Guard II", "description":"A heavy contact engages a deeper damper for longer than Rank I. Protection remains temporary and has a cooldown.", "card_copy":"Deeper damper. Longer guarded window.", "category":"BRAWL DEFENCE", "short_label":"GUARD II", "art_id":"crash_guard_ii"},
	"momentum_bank": {"name":"Momentum Bank II", "description":"Controlled braking captures more lost motion and holds a larger bank. Burst releases it on your line; storage still leaks and release costs RPM.", "card_copy":"Store more motion. Release a stronger Burst.", "category":"BRAKE STORAGE", "short_label":"BANK II", "art_id":"momentum_bank_ii"},
	"predator_line": {"name":"Predator Line II", "description":"Repeated meaningful hits on one full-size rival grant stronger pursuit damage and last longer. Switching or waiting still loses the hunt.", "card_copy":"Stronger pursuit hits. Longer target memory.", "category":"PURSUIT", "short_label":"HUNT II", "art_id":"predator_line_ii"},
	"crosscut": {"name":"Crosscut II", "description":"Steer across a glance to cut harder and more often than Rank I. Each cut spends more RPM and recoils on your top.", "card_copy":"Stronger cuts. Shorter cooldown. More RPM cost.", "category":"SHEAR", "short_label":"CUT II", "art_id":"crosscut_ii"},
	"gyro_lock": {"name":"Gyro Lock II", "description":"Smooth moving steering builds a heavier displacement lock sooner. Idle, Brake, sharp turns and Burst still break it.", "card_copy":"Build a heavier moving lock sooner.", "category":"CONTROLLED DEFENCE", "short_label":"GYRO II", "art_id":"gyro_lock_ii"},
	"impact_sink": {"name":"Impact Sink II", "description":"Catch more incoming recoil and hold a larger force reservoir. Tap Brake slowly to vent; unused force still leaks and recovery stays bounded.", "card_copy":"Catch more recoil. Hold more stored force.", "category":"DEEP SHOCK STORAGE", "short_label":"SINK II", "art_id":"impact_sink_ii"},
	"anchor_exchange": {"name":"Anchor Exchange II", "description":"Held Brake builds heavier footing sooner than Rank I. The brace still pays RPM and slows travel; release and steer to reposition.", "card_copy":"Build heavier portable footing sooner.", "category":"HEAVY ACTIVE BRACE", "short_label":"BRACE II", "art_id":"anchor_exchange_ii"}
}
const MUTATIONS: Dictionary = {
	"runaway": {"id":"runaway", "power_id":"redline", "name":"Runaway", "description":"Burst, move and keep landing hard hits to extend Redline and build more heat. Higher impact power brings growing control risk; misses end the sustaining chain.", "card_copy":"Hard moving hits sustain heat. Keep attacking.", "category":"SUSTAINED OVERLOAD", "short_label":"RUNAWAY", "condition":"Heavy contacts during Redline / misses end the chain"},
	"breakneck": {"id":"breakneck", "power_id":"redline", "name":"Breakneck", "description":"Build Redline heat or excess RPM, then Burst again to spend it on one committed strike. Recoil costs RPM and wobble; missing is worse.", "card_copy":"Overclock, then Burst again. One brutal strike.", "category":"CATASTROPHIC CHARGE", "short_label":"BREAKNECK", "condition":"Overclock first / Burst again at 32% heat or 2.5% excess RPM"},
	"bulwark": {"id":"bulwark", "power_id":"dead_centre", "name":"Bulwark", "description":"Fully anchor near centre to resist displacement and throw heavy attackers back. Counterforce builds Anchor Stress, so steer out to vent before your hold weakens.", "card_copy":"Plant fully. Throw attackers back. Vent Stress.", "category":"IMMOVABLE DEFENCE", "short_label":"BULWARK", "condition":"Full Anchor / heavy incoming contacts"},
	"counterweight": {"id":"counterweight", "power_id":"dead_centre", "name":"Counterweight", "description":"Take incoming force while anchored, then aim a Burst to release stored retaliation. The discharge breaks the anchor and, with steering, vents some Stress.", "card_copy":"Anchor. Store hits. Aim a Burst to strike and vent.", "category":"STORED RETALIATION", "short_label":"COUNTER", "condition":"Incoming force while Anchored / Burst releases storage"},
	"ghost_circuit": {"id":"ghost_circuit", "power_id":"afterimage", "name":"Ghost Circuit", "description":"Move fast to physically close your own or a hostile live Afterimage route. The route must be paid, visible and geometrically valid. The closer's enemies receive the pulse; used sections are consumed and the closer waits 3.5 seconds.", "card_copy":"Close own or enemy live routes. Hijack against enemies.", "category":"CIRCUIT HIJACK", "short_label":"CIRCUIT", "condition":"Physically close an owned or hostile live paid route / closer cooldown / used sections consumed"},
	"slipstream": {"id":"slipstream", "power_id":"afterimage", "name":"Slipstream", "description":"Cross your own live old trail for a stronger speed and efficiency surge. The route had to be paid for; repeated crossings have limits.", "card_copy":"Lay a trail. Cross it for speed and efficiency.", "category":"ROUTE ENGINE", "short_label":"STREAM", "condition":"Re-enter or cross your own active Afterimage path"},
	"terminal_velocity": {"id":"terminal_velocity", "power_id":"high_gear", "name":"Terminal Velocity", "description":"Commit to extreme thrust and speed. Hard steering and braking spend extra RPM, so plan the line before accelerating.", "card_copy":"Extreme speed. Expensive corrections.", "category":"RAW SPEED", "short_label":"TERMINAL", "condition":"High-speed movement / steering and brake expenditure"},
	"flow_state": {"id":"flow_state", "power_id":"high_gear", "name":"Flow State", "description":"Keep moving through smooth turns to retain speed and spend less RPM. It has less raw thrust than Terminal Velocity but smoother control.", "card_copy":"Carry speed through turns. Spend less RPM.", "category":"MAINTAINED SPEED", "short_label":"FLOW", "condition":"Sustained movement / smooth velocity retention"},
	"keel": {"id":"keel", "power_id":"gyro_lock", "name":"Keel", "description":"Smooth moving steering builds exceptionally heavy ballast while reducing speed. Tight turns break it sooner; idle, Brake and Burst still clear the lock.", "card_copy":"Move smoothly. Heavy ballast trades away speed.", "category":"MOVING FORTRESS", "short_label":"KEEL", "condition":"Smooth low-angle steering / reduced speed and stricter turning"},
	"flywheel": {"id":"flywheel", "power_id":"gyro_lock", "name":"Flywheel", "description":"Keep a Gyro Lock through wider controlled curves and faster travel. Idle, Brake and Burst still clear it; it has less footing than Keel.", "card_copy":"Carry moving defence through wider, faster curves.", "category":"CURVED DEFENCE", "short_label":"FLYWHEEL", "condition":"Smooth curves / deliberate steering and motion remain required"},
	"shock_bleed": {"id":"shock_bleed", "power_id":"impact_sink", "name":"Shock Bleed", "description":"Take recoil, then tap Brake slowly to spend stored force on stronger RPM and wobble recovery. Only accepted stored force pays, and recovery remains capped.", "card_copy":"Store recoil. Tap Brake for stronger recovery.", "category":"STORED RECOVERY", "short_label":"BLEED", "condition":"Stored incoming force / fresh Brake / shared recovery budget"},
	"return_spring": {"id":"return_spring", "power_id":"impact_sink", "name":"Return Spring", "description":"Take recoil, then tap Brake slowly to spend stored force on a physical pulse against nearby rivals. This replaces recovery and spends a little RPM.", "card_copy":"Store recoil. Tap Brake for a close counter pulse.", "category":"ACTIVE COUNTER PULSE", "short_label":"SPRING", "condition":"Stored force / fresh Brake / six nearby targets maximum"},
	"deep_footing": {"id":"deep_footing", "power_id":"anchor_exchange", "name":"Deep Footing", "description":"Almost stop and hold Brake to build extreme portable footing. It costs more RPM than normal Anchor Exchange and sharply limits movement.", "card_copy":"Almost stop. Hold Brake. Pay for extreme footing.", "category":"PORTABLE FORTRESS", "short_label":"FOOTING", "condition":"Brake below 34 speed / extra spin cost / limited movement"},
	"slip_anchor": {"id":"slip_anchor", "power_id":"anchor_exchange", "name":"Slip Anchor", "description":"Build a brace, then release Brake to carry some footing into your repositioning. The carry fades in 0.35 seconds; Burst clears it.", "card_copy":"Brace, release and move. Carry brief footing.", "category":"BRACED REPOSITION", "short_label":"SLIP", "condition":"Release a developed brace / 0.35 s carry / Burst clears it"}
}

static func get_power(power_id: String) -> Dictionary:
	var power: Dictionary = DEFINITIONS.get(power_id, {}).duplicate(true)
	if power.is_empty(): return power
	power.active = power_id in ACTIVE_IDS
	power["max_rank"] = max_rank(power_id)
	power["power_id"] = power_id
	power["rank"] = 1
	power["mutation"] = ""
	power["icon_frame"] = -1
	power["condition"] = CONDITIONS.get(power_id, "")
	if power.active or power_id in LEGACY_OWNED_IDS:
		_apply_art(power, power_id)
		power["category"] = CARD_COPY[power_id].category
		power["card_copy"] = CARD_COPY[power_id].copy
	_apply_card_semantics(power)
	return power

static func get_card_tier_style(rank: int = 1, mutation: String = "") -> Dictionary:
	return CardStyle.get_card_tier_style(rank, mutation)

static func _apply_card_semantics(power: Dictionary) -> void:
	var style: Dictionary = get_card_tier_style(int(power.get("rank", 1)), str(power.get("mutation", "")))
	power["card_tier"] = style.tier
	power["card_badge"] = style.badge

static func max_rank(power_id: String) -> int:
	return 3 if power_id in VERTICAL_IDS else (2 if power_id in ACTIVE_IDS else (1 if power_id in LEGACY_OWNED_IDS else 0))

static func investment_capacity() -> int:
	var capacity: int = 0
	for power_id: String in ACTIVE_IDS: capacity += max_rank(power_id)
	return capacity

static func run_investment_capacity() -> int:
	# Content capacity and a single machine's investment ceiling are distinct.
	var ranks: Array[int] = []
	for power_id: String in ACTIVE_IDS: ranks.append(max_rank(power_id))
	ranks.sort()
	ranks.reverse()
	var capacity: int = 0
	for index: int in range(mini(FAMILY_CAP,ranks.size())): capacity += ranks[index]
	return capacity

static func can_progress(power_id: String, rank: int = 0, mutation: String = "") -> bool:
	return power_id in ACTIVE_IDS and rank >= 0 and rank < max_rank(power_id) and mutation.is_empty()

static func mutation_choices(power_id: String) -> Array[String]:
	var choices: Array[String] = []
	for branch_id: String in MUTATION_BRANCHES.get(power_id, []): choices.append(branch_id)
	return choices

## A normal offer always identifies its original power. Rank II ownership
## opens a separate branch event; it never grants a third rank by itself.
static func get_offer(power_id: String, rank: int = 0, mutation: String = "") -> Dictionary:
	if not can_progress(power_id, rank, mutation): return {}
	var power: Dictionary = get_power(power_id)
	power["owned_rank"] = rank
	power["rank"] = rank + 1
	power["offer_kind"] = "acquire" if rank == 0 else ("tune" if rank == 1 else "mutation")
	power["offer_label"] = ["NEW POWER / I", "UPGRADE / II", "MUTATION / III"][rank]
	power["rank_label"] = ["RANK I / ACQUIRE", "RANK II / TUNE", "RANK III / MUTATE"][rank]
	if rank > 0:
		power.merge(RANK_II[power_id].duplicate(true), true)
		_apply_art(power, str(power.art_id))
	if rank == 2:
		power.name = str(DEFINITIONS[power_id].name) + " III"
		power.category = "MUTATION AVAILABLE"
		var branches: Array[String] = mutation_choices(power_id)
		power.description = "Choose %s or %s to transform this power." % [MUTATIONS[branches[0]].name, MUTATIONS[branches[1]].name]
		power.card_copy = "Choose a new behaviour: %s or %s." % [MUTATIONS[branches[0]].name, MUTATIONS[branches[1]].name]
	_apply_card_semantics(power)
	return power

static func get_mutation(branch_id: String) -> Dictionary:
	var branch: Dictionary = MUTATIONS.get(branch_id, {}).duplicate(true)
	if branch.is_empty(): return branch
	branch["active"] = true
	branch["rank"] = 3
	branch["max_rank"] = 3
	branch["mutation"] = branch_id
	branch["offer_kind"] = "mutation"
	branch["offer_label"] = "MUTATION / III"
	branch["rank_label"] = "RANK III / MUTATION"
	_apply_art(branch, branch_id)
	_apply_card_semantics(branch)
	return branch

## Current ownership metadata is distinct from the next investment offer.
static func get_owned_power(power_id: String, rank: int = 1, mutation: String = "") -> Dictionary:
	if not (power_id in ACTIVE_IDS or power_id in LEGACY_OWNED_IDS) or rank < 1 or rank > max_rank(power_id): return {}
	if rank == 3:
		return get_mutation(mutation) if mutation in mutation_choices(power_id) else {}
	var power: Dictionary = get_power(power_id)
	if rank == 2:
		power.merge(RANK_II[power_id].duplicate(true), true)
		_apply_art(power, str(power.art_id))
	power.rank = rank
	_apply_card_semantics(power)
	return power

static func _apply_art(power: Dictionary, art_id: String) -> void:
	var defence_art: Dictionary = DefenceArt.art(art_id)
	if not defence_art.is_empty():
		power.merge(defence_art, true)
		return
	var authored: Dictionary = IdentityArt.art(art_id)
	if not authored.is_empty():
		power.merge(authored, true)
		return
	var source_id: String = str(ART_ALIASES.get(art_id, art_id))
	var escalation: bool = source_id in ESCALATION_ART_IDS
	var roster: bool = source_id in ROSTER_ART_IDS
	power["art_id"] = art_id
	power["source_tag"] = source_id
	power["icon"] = ROSTER_ICON_SHEET if roster else (ESCALATION_ICON_SHEET if escalation else ICON_SHEET)
	power["icon_frame"] = ROSTER_ART_IDS.find(source_id) if roster else (ESCALATION_ART_IDS.find(source_id) if escalation else LEGACY_ART_IDS.find(source_id))
	power["card_texture"] = ROSTER_CARD_SHEET if roster else (ESCALATION_CARD_SHEET if escalation else CARD_SHEET)
	power["card_row"] = power.icon_frame
	power["card_frames"] = 6
	power["card_cell"] = 64
	power["card_static_frame"] = int(CARD_STATIC_FRAMES.get(art_id, 3))
	power["card_durations_ms"] = CARD_DURATIONS_MS.duplicate()

static func display_names(power_ids: Array) -> Array[String]:
	var names: Array[String] = []
	for power_id: String in power_ids:
		if DEFINITIONS.has(power_id): names.append(str(DEFINITIONS[power_id].name))
	return names
