# Task 002C.2 - Endless Threat Director

## Provenance and scope

Fetched and verified accepted `origin/main` at exactly
`27cb5f1e6dfbcb1641b5071bb237fc2e15807f36`, matching the requested accepted merge.
The starting checkout was clean. Main and current branch history, Task 002C.1
report/runtime, encounter/swarm/progression/power/battle architecture and relevant
regression tests were inspected before edits. All 20 baseline suites passed.

Task branch: `task-002c2-endless-threat-director`, created from that accepted main.
The final SHA is in Git history and the delivery message (not recursively in this
commit). No merge to main. The separate Task 002A worktree, historical test
artifacts, art masters and standalone practice modes are preserved.

## Architecture

`threat_director.gd` is a scene-independent seeded pressure policy. It consumes
active time, a census, current investment level and its own recent history. Its
`threat_director/v1` RNG domain never consumes combat, AI or cosmetic streams.
A fixed seed plus identical observed combat state produces identical decisions.
Time unlocks eligibility; it does not assign a boss/event to an exact timestamp.

`continuous_run.gd` owns admissions, warnings, independent active event records,
unique enemy IDs, cleanup, counters and Run results. An event is one rival or one
Ammunition Waves schedule. Multiple full-top events and one swarm schedule may
coexist. Pending arrivals reserve pressure immediately. An unsafe port waits and
rechecks separation after a fresh warning; no player teleport is used.

Battle still initializes the player/power runtime only once. Adding an event
preserves every surviving fighter, velocity, RPM, wobble, cooldown, active power,
trace and mutation. It neither clears contact attribution nor restarts the swarm.
Swarm scheduling now has its own start time. XP uses a stable Run scope so a new
event cannot bypass global contact cooldowns or duplicate an old elimination.
Wave identities include their event serial. Retired entity observers and power
state are released; director history holds at most 128 decisions, recent-choice
history six entries. Pending/active event records are bounded by population caps.

The old four-entry catalogue survives only as an explicit standalone/UI fixture
seam. Production admissions use `for_run_event()` plus the director definition;
no production tick calls the scripted `_spawn_next()` QA helper. Existing finite
catalogue tests still validate useful standalone fixtures, not production pacing.
`RunContext.admit_event()` advances a display/event identity without resolving
other enemies or discarding XP. Ordinary and boss clears never emit Run victory.
Loss remains the only terminal Run event. Stale runtime, enemy record, result,
entry and duplicate-clear guards are covered by regression tests.

## Tier, budget and pacing model

| Tier | Eligible from active time | Base pressure | Full-top cap | New possibilities |
| --- | ---: | ---: | ---: | --- |
| 0 | launch | 2.8 | 1 | Hunter/Bulwark, solo pressure |
| 1 | 35 s | 6.0 | 2 | Flanker/Harasser, small swarm, overlaps |
| 2 | 100 s | 10.0 | 3 | Elites, ten-small swarm capacity, either boss |
| 3 | 210 s | 13.0 | 4 | More mixed support, shorter event intervals |
| 4 | 360 s | 16.0 | 5 | Two distinct bosses may coexist |
| 5+ | every further 120 s | +1.25 per tier | 5 | Algorithmic pressure/cadence/handling scaling |

Investment contributes at most 0.6 pressure after the launch tier; it does not
unlock early bosses or rewrite enemy stats in response to an individual power.
Costs: Hunter 2.6, Bulwark 2.8, Flanker/Harasser 3.0, Ballast 4.6, Hotwire 4.5,
either boss 7.0. Swarms reserve 0.5 per peak active small top: 3.0 at tier 1,
5.0 thereafter. The entire scheduled peak is reserved, even between waves.

Hard caps, including pending reservations: five full tops total (bosses and
elites count toward this), two elites, one boss before tier 4/two afterward,
ten small tops, sixteen total active physics bodies including the player.
The original standalone swarm cap remains twelve. Corpses retire in 0.65 seconds
and do not collide; they are measured separately from active bodies.
Existing visual/audio ceilings remain: 32 power FX, 120 particles, 72 total
power traces and eight audio channels. No unbounded enemy count is used.

Normal decision intervals are randomized from 12-17 seconds at launch toward
5-8 seconds at tier 4. After tier 4, intervals asymptotically approach 60% of that
cadence; acceleration approaches a modest +16% through the role handling policy.
Pressure budget keeps growing without a final tier or Run duration. At extreme
tiers, hard safety caps deliberately constrain the realized pressure.

A full clear gives 2-4 live recovery seconds, then a normal 0.65-second warning.
Boss warnings last 2.2 seconds. After 55 seconds without a recovery window, the
director stops injecting until reserved pressure falls to 45% of budget, then
allows 3-5 seconds of relative calm. Boss defeat also delays new decisions. The
player, timer, RPM and existing enemies continue throughout. No heal is granted.
Draft/pause freezes the director and warnings along with the complete arena.

Recent selection weighting penalizes the last six choices and prohibits three
identical selections consecutively. Swarm cooldown is 34 seconds, elite 18,
boss 78 (56 after tier 4), same named boss 180. Repeated clears under 12 seconds
can accelerate cadence by at most 20%; slower clears remove this small adjustment.
There is no reactive enemy invulnerability, damage scaling or power cancellation.

## Content identity

- **Hunter:** Smash/Low/Flat; predicts a short present-velocity lead and commits
  to direct collisions/Bursts. Opening rival uses the original Balance/Mid/Ball.
- **Flanker:** Hook/Mid/Rubber; sustained tangential movement around a preferred
  distance, with oblique approach and occasional Burst.
- **Bulwark:** Guard/Low/Ball; slow central interception and space holding, higher
  mass/recovery and no ordinary Burst. Forces the player to approach or displace it.
- **Harasser:** Balance/High/Needle; cycles glancing approaches and tangential
  withdrawal, with bursts confined to the approach beat.
- **Ballast elite:** Bulwark with extra mass/recovery and reduced speed/acceleration.
- **Hotwire elite:** Hunter with faster acceleration/speed but less mass/recovery
  and greater spin expenditure. Both elites carry yellow markers.
- **The Anvil:** heavy Guard/Low/Ball boss, enlarged collision radius, centre hold
  punctuated by a six-second shove rhythm, sustained reserve and red crown.
- **Red Reaper:** Hook/Mid/Rubber boss, broad orbit interrupted by committed cutting
  approaches, more speed/less mass than Anvil, sustained reserve and red crown.

Bosses retain legal part combinations with authored handling/radius modifiers;
there is no HP bar or HP multiplication system. A ring, short title and lowered
existing audio cue announce arrival. Boss defeat has a short callout and win cue
while other enemies keep fighting. Full-top rewards are 18 XP, elites 27, bosses
45; small tops remain 3, credited wave completion 6. Existing global/pair collision
limits, level costs, ranks/mutations and thirteen-investment cap are unchanged.

## Central tuning and temporary RPM rule

- `scripts/threat_director.gd`: EVENTS and TUNING, eligibility, pressure, caps,
  anti-repeat cooldowns, breathing and adaptation.
- `scripts/enemy_roles.gd`: modular assemblies, elite/boss handling and movement.
- `scripts/run_progression.gd`: centralized XP values, attribution and cooldowns.
- `scripts/continuous_run.gd`: entry positions, corpse retirement, temporary RPM.
- `scripts/swarm_runtime.gd`: existing wave scheduler, entry safety and small physics.

**The Task 002C.1 RPM compromise is unchanged: 0.12 of each fixed tick's net
negative player reserve change is charged, before Second Wind recovery.** This
includes natural/movement/Burst/power/contact/wall costs; positive net gains are
not amplified. There is no between-event refill. Ring-out remains fatal. This
coarse net-spend discount is architecture testing, not a final sustain economy.
Second Wind remains once per launch. Task 002C.3 owns the eventual replacement.

## Diagnostics and reproducibility

`tests/task002c2-director-results.json` is the compact combined evidence artifact,
with clearly separated scopes:

1. Nine ordinary combat samples: three starters x seeds 421/7341/2026, varied
   opening power preferences with actual starting choices recorded. Real physics,
   AI, enemy outcomes and earned drafts; no reserve refill or injected victory.
   Ceiling 900 active seconds, not a game limit. All ended naturally before it.
2. Eight 900-second policy occupancy models with seeded, explicit synthetic enemy
   lifetimes. These validate decisions/pressure/history, not combat survival.
3. Three 900-second real-physics load fixtures, one per starter. A full build is
   installed, player reserve held at 0.8 and ring-outs intercepted explicitly.
   These test extended load and late tiers, not natural survival or final balance.

| Natural sample | Survival | Clears | Bosses entered / defeated | Level |
| --- | ---: | ---: | ---: | ---: |
| breaker / 421 | 217.78 s | 9 | 1 / 0 | 9 |
| breaker / 7341 | 222.37 s | 10 | 1 / 1 | 9 |
| breaker / 2026 | 253.23 s | 12 | 2 / 1 | 11 |
| bastion / 421 | 465.50 s | 26 | 2 / 2 | 13 |
| bastion / 7341 | 425.42 s | 23 | 3 / 2 | 13 |
| bastion / 2026 | 455.97 s | 24 | 4 / 3 | 13 |
| vane / 421 | 356.28 s | 16 | 1 / 0 | 13 |
| vane / 7341 | 367.82 s | 17 | 2 / 1 | 13 |
| vane / 2026 | 223.15 s | 9 | 1 / 1 | 10 |

Every natural sample launched exactly once and kept the identical player object.
All nine saw swarms and a boss; eight saw elites; seven defeated a boss and
continued. First boss entry ranged 106.62-290.08 seconds, and no boss was eligible
before 100. Natural samples peaked at four actual full rivals, ten small tops,
and fourteen total active bodies. Longest empty gaps were 2.3-4.3 seconds.
Median intervals between earned choices per Run were about 19-31 seconds
(shortest individual interval 5.69 seconds); no sample became a constant draft
loop. Five reached full investment without ending combat. Eight spun out, one
rang out. These results support pacing iteration, not human feel acceptance.

Policy models generated 69-78 total events in 15 minutes, reached tier 8, respected
every budget/cap and produced eight distinct sequences. Empty gaps peaked at
4.5 seconds. The first boss was not identical in timing across seeds. Fixing a
double recovery-window bug reduced the earlier 8-second empty gaps; swarm weight
was increased after initial samples delayed some first swarms beyond five minutes.

Protected load fixtures reached tier 8 with 74-86 additional admissions, 5-8 boss
entries and 9-11 swarms. Active bodies peaked at 15, retained bodies/power states
at 15, power FX at 11 and traces at 14. They required 9/1/6 ring-out interventions
for Breaker/Bastion/Vane respectively; the JSON makes that protection explicit.
Two simultaneous bosses are covered by policy eligibility and actual admission/
independent-death integration fixtures; the sampled natural/load runs did not
happen to reach two simultaneously. No frame-rate benchmark is claimed.

Normal defeat saves `user://last_run_director.json`: seed, starter/build, investments,
result, current census and last 128 decisions with time/tier, pressure budget,
census, investment level and pre-selection RNG state. Run seed is visible on the
result screen. `SpinningMetal.exe -- --run-seed=421` selects a seed for investigation.
Exact decisions also require identical player inputs/outcomes: this is not an
input replay system, cloud telemetry or permanent statistics system.

## Tests executed

Godot 4.7.2. All 21 relevant headless suites pass:

| Suite | Checks |
| --- | ---: |
| Threat director (including 8 long policy samples) | 83 |
| Continuous player/lifecycle | 200 |
| Run context | 332 |
| Flow | 158 |
| Combat architecture | 35 |
| Menus | 1399 |
| Synthetic controller | 670 |
| Powers | 79 |
| Swarm | 33 |
| Presentation | 72 |
| Progression | 150 |
| Starter identities / starter physics | 17 / 37 |
| XP observer | 30 |
| Ramp integration / card assets | 19 / 113 |
| Escalation progression / physics | 513 / 103 |
| Escalation integration / completion / assets | 628 / 34 / 291 |

Additional verification:

- 127,776 neutral physics comparisons over all 48 assemblies against accepted
  main: zero failures; Quick Duel uses the original unmodified AI path.
- Native menus: 1431 checks. Director visual fixtures: 13 checks; warning,
  boss/swarm/elite overlap and result captures inspected at 640x360 and 2x.
- Nine natural simulations and three protected 15-minute physics soaks pass
  identity, pressure and population assertions throughout.
- Windows release export and packaged smoke pass, exit 0, with ten injected UI
  transitions, drafts/mutations, loss/restart and Quick Duel. The smoke is a
  flow fixture; it does not replace the natural director diagnostics.
- `git diff --check` passes. No tests were removed to hide failures. The previous
  exact-two-second arrival assertion now permits the seeded breathing interval
  plus a telegraphed entry. Existing scripted swarm/flow fixtures remain explicit.

Run commands are in README. Detailed local logs/captures were retained outside
the repository at `C:\GPT GAME BUILDING\task-002c2-qa`.
Controller checks are synthetic; no physical human playtest is claimed.

## Delivery and limitations

Windows checkpoint: `releases/windows/SpinningMetal.exe` with embedded data and
SHA-256 sidecar. Human checklist: `TASK-002C2-PLAYTEST.md` and the copy next to the
executable. All content is reachable through an ordinary Run, without commands.

Major files: new `threat_director.gd` / `enemy_roles.gd`; revised `continuous_run.gd`,
Battle, encounter descriptors, Run context/progression, swarm clocks, Main, menus
and sound cue; new policy/combat/soak/visual tests, compact JSON diagnostics,
README/report/playtest documents and Windows package. Existing powers/art remain.

Known limitations: two experimental bosses, four roles, two elite modifiers and
one concurrently scheduled swarm; a finite investment pool; bounded late handling
means safety caps constrain extreme-tier realized pressure; generous temporary
RPM discount; reused art/audio with simple boss markers, not a cinematic/VFX pass.
The automatic diagnostic keeps only the most recent Run and last 128 decisions.
No procedural arenas, meta progression, boss unlocks, shop/rarity/economy, new
powers, soundtrack system or final RPM sustain were added. No known regression
remains in tested modes. Final subjective pacing, enemy recognition, boss weight,
readability under human play and controller feel await the user's playtest.

Work stops at this playable Task 002C.2 checkpoint.
