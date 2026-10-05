# Task 002C — build escalation vertical slice

Implementation is on `task-002c-build-escalation`, created directly from the
verified `task-002b1-roguelite-ramp` tip
`bdcc24e5c3717486eaabaa4e9bac67e1dcc351b2`. No branch was merged.
The final commit is supplied in the delivery message and Git history.

The Run now mixes acquiring powers with developing owned powers. Redline,
Dead Centre and Afterimage each have three investments: Rank I, Rank II and
one mutually exclusive mutation. Impact Wake, Second Wind, Iron Comet and
Chain Impact retain their existing mechanics. All seven powers are legal
on every starter. No permanent progression, rarity, shop, part collection,
boss system or camera/arena replacement was introduced.

## Implementation facts: drafting and live state

`run_context.gd` stores unique power IDs separately from rank and mutation
dictionaries. Eligible owned powers return to the same small seeded pool.
Offers draw up to three different power IDs without replacement; new powers
have weight 1.0, further investments 1.2. There are no starter restrictions,
guaranteed powers or guaranteed mutations.

The catalogue computes capacity from each active power's maximum rank:
seven acquisitions plus six further investments, thirteen total. A full
seven-power machine is supported; HUD capacity is eight. MAX means all
available investments have been earned, rather than merely owning six powers.
XP awards, attribution, cooldowns and early incremental costs remain
18/22/36/56/84. Subsequent earned investments cost 84 each; the entire pool
requires 804 earned XP plus the free starting power. Overflow and queued
entitlements persist.

Choosing an eligible Rank II power opens a dedicated mutation event without
consuming its draft. Exactly two valid branch cards appear. Only the branch
commit consumes the entitlement and installs Rank III. Draft ID, seed and
screen guards reject stale or repeated callbacks. Pending final-result
entitlements can also finish after Encounter 8 without launching Encounter 9.

Every draft/mutation freezes positions, spin, wobble, power clocks/cooldowns,
swarm scheduling and encounter time. Acquisition updates the same combatant
and semantic runtime, retaining spent Second Wind, stored force and traces.
Cards activate on fresh Confirm press; held Confirm is blocked on the next
screen. Pause restores the selected branch, and combat requires neutral
steering plus released Burst/brake before normal input resumes.

Rank II has a 0.70s acquisition event; mutation confirmation lasts 1.0s,
with dedicated artwork/audio and cosmetic combat preview. Those previews
apply no damage, kills, reserve refill or physical impulse. The new rules
are owned immediately, with the next valid mechanic trigger showing them.
An already-running Redline activation retains the rank and branch rules it
started with until it ends; the next accepted Burst uses the new investment.
This preserves the paid timer, hit state and physical motion through a choice.

## Implementation facts: physical paths

| Investment | Final rule |
| --- | --- |
| Redline I | Preserves Burst entry at at least 35% pre-cost RPM, 0.8s overload, extra reserve cost/wobble, effective RPM above normal and first-contact recoil recovery. |
| Redline II | 1.1s overdrive, 55 extra directional velocity, acceleration ×1.30, speed ×1.15 and attack ×1.35. Entry spends 0.075 reserve/adds 0.17 wobble; active state spends 0.028 reserve/s/adds 0.075 wobble/s. |
| Runaway | Contacts of severity at least 0.35, at most once per 0.20s, extend overload by 0.42s, capped at 1.25s remaining. They refund at most 0.034 reserve and build capped heat that increases thrust, impact, deterministic steering instability and continuing costs. Missing follow-ups or dropping below 0.13 RPM ends overload. |
| Breakneck | A 0.36s committed charge, 180 extra velocity, acceleration ×2.5, attack ×2.4, only 12% steering contribution and no braking during commitment. The first meaningful strike adds 80 velocity to a full rival or 100 to a small top and ends charge. Recovery adds 0.32 wobble, spends 0.025 reserve and reduces velocity to 72%. Weak glances do not consume the strike. |
| Dead Centre I / II | Controlled central position within radius 115, speed at most 85, brake or light steering builds Anchor in 1.10s/0.85s. Actual effective mass becomes `1+3q²`/`1+8q²`; drag and wobble recovery also grow with real charge q. Aggressive movement drains Anchor; sufficiently extreme incoming force breaks it. |
| Bulwark | At full charge, effective mass reaches 81× and additional drag 16. Heavy contacts while at least 70% anchored physically repel the attacker, compress/settle the player and suppress wobble/loft. Extreme force above 480 still breaks Anchor. |
| Counterweight | Incoming anchored contacts and hostile power impulses capture 42% of charge-scaled incoming force, capped at 150. Burst releases stored force of at least 12, moving the owner along the chosen heading and pushing enemies in a 72-unit forward cone. Own impulses cannot fill storage. |
| Afterimage II | Paid paths last 2.3s instead of 0.45s, have clearer connected geometry and stronger lateral crossing impulses: 24/full top or 64/small top instead of 12/40. Target cooldown remains 0.6s. |
| Ghost Circuit | Five-second live paths, up to 28 segments and 320 closure samples. Closure is within 28 units, after at least 0.75s of route history, at least 125 path length and 650 enclosed area. Energises the connected circuit and pushes enclosed enemies by 65/full or 100/small. Closure cooldown 2.4s. |
| Slipstream | Re-enter an own trace aged at least 0.30s within 18 units at speed at least 70. Adds 75 momentum, reduces wobble 0.16 and refunds 0.006 reserve. For 0.70s, acceleration ×1.65, speed ×1.25 and spin drain ×0.55. Crossing cooldown 0.75s; remaining on a path cannot farm constant procs. |

Budgets remain bounded: 72 global traces, up to 28 per escalated owner,
256 diagnostic events, 32 combat effects and eight audio channels. Fixed
isometric composition, integer sprite placement, nearest filtering and
640×360 runtime are retained.

## Art and audio source handoff

New editable production masters, preserving all older source masters:

- `assets/source-art/escalation_cards_002c.aseprite`: 64×64, 60 frames,
  five named layers, ten tags, pivot (32,32).
- `assets/source-art/escalation_icons_002c.aseprite`: 16×16, ten frames,
  one named layer, ten tags, pivot (8,8).
- `assets/source-art/escalation_fx_002c.aseprite`: 128×128, 116 frames,
  four named layers, nineteen tags, pivot (64,64), baked charge directions.
- Separate `assets/powers/escalation_{cards,icons,effects}.png` and
  `escalation_manifest.json`. Legacy atlases retain their original pixels
  and row indexes. No player-top master needed modification.

`tools/build_escalation_art.py` normally reads edited sources and exports
them without rebuilding. The explicit `--author-new` switch only recreates
the new sources and must not be used after artist edits. Detailed layer,
tag, timing, pivot and export contracts are in `assets/source-art/POWER-002C.txt`.
Aseprite 1.3.18.6 opened all three masters; its exported RGBA pixels, source
timing, layer/tag metadata and pivots match the maintained exporter exactly.

Presentation reads physical states: hot jagged Runaway wakes track heat;
ground jaws track real Anchor charge and remain shut when fully locked;
Counterweight lights actual force-storage stages; Ghost Circuit shows
connected green enclosure geometry; Slipstream uses reuse chevrons and jets.
The six mutation cards have independent animated illustrations.

Seventeen added finite mono PCM16/22050Hz cues (150–660ms): `rank_up`,
`mutation_available`, `mutation_select`, `redline_ii`, `runaway`,
`runaway_hit`, `breakneck_charge`, `breakneck_impact`, `anchor`,
`anchor_break`, `bulwark_impact`, `counterweight_store`,
`counterweight_release`, `afterimage_ii`, `ghost_closure`,
`ghost_activation`, `slipstream_cross`. `tools/build_escalation_audio.py`
exports only these additions. Existing audio is preserved; priorities,
debouncing and the eight-channel ceiling remain, with no continuous loops.

## Measured and tested evidence

Existing flow/context/menu/controller/power/swarm/presentation/starter/XP
suites are preserved, with prior six-unique-power assertions updated for
investments. New deterministic suites cover all six behaviours, repeated
investment, exclusivity, stale/duplicate claims, seven-power/13-investment
state, pause/resume, controller navigation, held Confirm, art/audio contracts
and final-result queues. The delivery report includes exact final counts
and raw logs. Neutral physics also passed 127,776 field comparisons across
48 assemblies against the verified 002B.1 base battle source at `bdcc24e5`.
That differential isolates movement, boundary and collision equations; it
does not measure mutation balance or human feel.

The five-second HUD-free diagnostic uses initial build/pose fixtures, then
only ordinary steering/Burst/brake and normal AI. It injects no paths, contacts,
procs, FX, reserve refills or victories. Runaway naturally sustained seven
hits; Bulwark produced three heavy brace responses; Vane naturally closed
and activated Ghost Circuit at about 4.47 active seconds. Native captures
were inspected, and the three clips are provided for human recognition review.
Natural orbit testing exposed a too-short initial route lifetime/sample cap;
Ghost's final five-second/320-sample budget fixes that issue while preserving
Vane movement equations.

Four uninterrupted real-solver Runaway pursuits with support powers sustained
overload for 1.88–4.77 active seconds, reaching heat 1.0 in two seeds. They
produced two wins/two losses. Raw evidence: `tests/results/task002c-physics-results.json`.

The unchanged simple ramp bot's current twelve seeded Runs all eventually
failed; three survived one minute, with three/four unique powers then.
Median first earned choice was about 14.3 active seconds. Two Runs naturally
acquired Runaway through repeated investments. The new pool changes starting
offers/choices, so this is not a controlled balance comparison to 002B.1.
The bot does not deliberately exploit grounding, route reuse or mutation
commitment. This is a real limitation of current evidence, not human pacing
or balance acceptance. No XP/enemy inflation was used to mask it.

## Design judgments and remaining human checkpoint

Unequal investment, contact-fed overload, force storage and route-based
movement are intended to create recognisable machines. The native visual
review supports distinct silhouettes and clean card layouts. Whether these
are extreme, exciting, understandable and fun remains subjective human work.
Six/seven-power synergy, audio readability under real play and physical
controller feel are not accepted by automated tests.

The Windows executable is self-contained and needs no Godot installation.
Optional practice presets equip a full comparison machine without changing
ordinary Run offers or progression. F2 hides the HUD for the required visual
test. Follow `TASK-002C-PLAYTEST.md`, including all nine checkpoint questions.

Remaining tuning risks: aggression can burn out quickly; Ghost needs a broad,
fast orbit, and an enemy must actually be enclosed for its interior push;
Counterweight rewards aiming a stored-force Burst rather than passive damage;
full late-run ownership and multiple deep mutations need human validation
within the existing eight encounters. Practice setup fixtures do not prove
ordinary-run availability or earned pacing. No milestone acceptance is claimed.
