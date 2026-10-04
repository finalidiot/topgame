# Task 002C.1 - continuous Run foundation

A Run now launches once and remains one live arena session until player defeat.
Ordinary rival or swarm clears acknowledge progress in the HUD, allow two active
seconds of breathing room, then introduce the next threat. They do not produce
a victory menu, relaunch, player reset, RPM refill or Run-clear state.

## Baseline and branch inspection

Before edits, the local checkout was clean on `task-002b1-roguelite-ramp` at
`bdcc24e5c3717486eaabaa4e9bac67e1dcc351b2`. All local branches and freshly fetched
remote branches were inspected. The branch history was:

- `main`: `d551867`, original prototype baseline.
- `task-002a-run-architecture`: `d80752d`, Run/controller architecture.
- `task-002b-first-broken-build`: `8fa737b`, powers and swarm.
- `task-002b1-roguelite-ramp`: `bdcc24e`, starters, opening draft and live XP.
- Newly discovered `origin/task-002c-build-escalation`: latest relevant experimental work, adding investments and mutations directly on B.1.

**Exact starting branch:** `origin/task-002c-build-escalation`.
**Exact starting SHA:** `3267ef3e89d964e7344c4c1c4d103058b8c8aed0`.
**Task branch:** `task-002c1-continuous-run`.
The exact final SHA is supplied in the delivery message/Git history rather than
embedded recursively in its own commit. No merge to main. The existing 002A
worktree, historical reports, art masters, power mutations and practice modes
are preserved. Nineteen relevant suites passed on the starting SHA before edits.

## Architecture

`continuous_run.gd` is a small lifecycle runtime attached to the existing Battle.
It is explicit validation scaffolding, not a procedural Threat Director. It
tracks threat index, phase, entry time, next enemy ID and accumulated counts.
The temporary four-threat catalogue repeats: standard balance rival, hook rival,
Ammunition Waves, smash rival. Threat IDs and catalogue seeds use the absolute
index; cycling content never recycles enemy IDs or implies a final threat.

`Battle.begin_run()` initializes the arena/player/power runtime exactly once.
After that, `enter_threat()` changes only threat-owned state. The same player
dictionary, position, momentum, RPM, wobble, build, starter identity, power
ownership/ranks/mutations, cooldowns and semantic power runtime continue.
Surviving player traces and stored force remain live. Second Wind is once per
launch; a spent recovery stays spent across normal clears. Quick Duel and the
existing standalone build-practice presets still use `begin_encounter()` and
retain ordinary single-battle results.

Ordinary clear and next-entry signals are separate from `round_finished`.
Continuous Battle terminal checks recognize player defeat only; opponent wins,
old timeout rules and reaching a catalogue index cannot end a Run. Main accepts
a Run result only when it is the current simulation's actual terminal loss,
with matching Run identity. Stale ordinary results and stale enemy records are
rejected, including an old record whose numerical ID exists again after restart.
Player defeat during a breathing interval still terminates the Run.

`Battle.elapsed` is the authoritative active survival clock. It advances only
inside a live fixed simulation tick. Countdown/launch presentation, pause,
draft/mutation/acquisition menus, hit-stop and terminal animation are excluded.
Breathing intervals count because movement, power clocks and RPM remain live.
The swarm reads `threat_elapsed()` for due times and cleanup, preventing a late
swarm from inheriting an already-expired global clock.

XP is published after a complete fixed tick, before normal clear/entry handling.
A level-up freezes the full Battle and lifecycle together; claims resume the
same bodies and state. `RunContext` retains XP, levels, powers, investments and
draft guards while its threat index grows without a fixed maximum. The existing
seven-power/thirteen-investment pool still reaches MAX; this never ends the Run.
Retired threat deduplication records are released without resetting XP.

## Enemy lifecycle

Rivals enter at the deterministic furthest of four safe interior points, at
least 60 world units from the player, with an entry ring and existing landing
cue. Each receives a fresh ID and independent deterministic AI stream. Swarms
reserve 24 fresh IDs per repetition and retain their original 6/8/10 waves,
12-active cap, telegraphs, finite scheduler and no-credit natural retirement.

Defeated bodies have a brief 0.65-second retirement interval. Removal releases
body, AI RNG and obsolete contact/attribution records. Power cleanup removes
retired enemy states, obsolete trace target records and chain roots no live
state/effect can reference. It preserves the player's cooldowns, recovery use,
Anchor/force, active power timers and paid traces. No new pooling or director
framework was added. A 200-transition fixture confirms bounded body/state/claim
storage; real combat samples peaked at 10-11 total retained bodies/power states.

## Temporary RPM/testing compromise

`ContinuousRun.TUNING.player_rpm_loss_scale = 0.12` is the one temporary economy
setting. Each live fixed tick records starting player reserve, then scales its
net negative reserve change to 12% before Second Wind recovery. This covers
natural/movement/wobble/brake decay, Burst/power expenditure and contact/wall
losses together. Positive net gains are not multiplied. Enemy economy is
unchanged. The rule applies to all continuous Runs, including custom starters;
it does not apply to Quick Duel or standalone practice.

There is no passive regeneration, threat-completion heal, reset or invulnerability.
Ring-out remains fatal. RPM can still fall through the spin-out threshold.
This intentionally generous scale allows multiple-minute architecture tests
without distributing temporary multipliers through every combat/power function.
It is not final balance: netting same-tick gains/losses is a coarse compromise,
and Rank II/mutation costs are substantially discounted along with base costs.
Task 002C.3 should replace this single boundary rule with the intended economy.

## Automated and rendered verification

All twenty relevant suites pass on Godot 4.7.2:

| Suite | Checks | Result |
| --- | ---: | --- |
| Continuous lifecycle | 200 | Pass |
| Run context | 332 | Pass |
| Flow | 158 | Pass |
| Combat architecture | 35 | Pass |
| Menus, headless / native renderer | 1394 / 1426 | Pass |
| Controller, synthetic device | 670 | Pass |
| Original power runtime | 79 | Pass |
| Swarm | 33 | Pass |
| Presentation | 72 | Pass |
| Progression | 150 | Pass |
| Starter mapping / physics | 17 / 37 | Pass |
| XP observer | 30 | Pass |
| Ramp integration | 19 | Pass |
| Card assets | 113 | Pass |
| Escalation progression | 513 | Pass |
| Escalation physics | 103 | Pass |
| Escalation integration, synthetic device | 625 | Pass |
| Full-investment continuation | 34 | Pass |
| Escalation assets | 291 | Pass |

Existing finite-completion assertions were updated to the new intended behaviour:
a full investment pool and threat eight now continue the same Run. Existing
claims, progression, art, controller, mutation and Quick Duel coverage remain.
The new suite covers exact player/runtime preservation, safe entries, retained
XP/investments, frozen level-up state, late swarm scheduling, repeated swarms,
beyond-eight continuation, no ordinary terminal event, loss during breathing,
old-Run events, old enemy object identity and bounded lifecycle state.

Neutral physics differential against the exact starting battle source passes
127,776 field comparisons across all 48 assemblies with zero failures. Native
rendered smoke exercises ten threat transitions, drafts/mutations, loss, restart,
and Quick Duel. Smoke outcomes are injected UI fixtures, not balance evidence.
Native menu captures show the elapsed clock, clear acknowledgement and distinct
Run result; 640x360 and the normal 2x game presentation remain readable.
Windows release export passes. The packaged executable also passes the rendered
ten-transition smoke with exit code 0 and no script/runtime errors.
Synthetic-controller passes are not a claimed physical-controller playtest.

## Real continuous-combat diagnostic

`tests/test_continuous_playthrough.gd` uses the real Main/Battle path with sampled
imperfect bot steering, ordinary Burst/brake, normal enemy AI and earned choices.
It injects no victories, enemy deletion, player teleports, power procs or reserve
refills. It asserts the same player dictionary throughout. The old ramp test
entry point delegates to this continuous diagnostic. Maximum sample duration is
480 active seconds; this diagnostic limit is not a game limit.

| Starter / seed | Active survival | Clears | Swarms entered | Outcome |
| --- | ---: | ---: | ---: | --- |
| Breaker / 421 | 279.70 s | 9 | 2 | Spin-out |
| Breaker / 7341 | 20.15 s | 0 | 0 | Ring-out |
| Bastion / 421 | 475.02 s | 13 | 3 | Spin-out |
| Bastion / 7341 | 480.02 s | 13 | 3 | Still active at sample limit |
| Vane / 421 | 368.37 s | 11 | 3 | Spin-out |
| Vane / 7341 | 368.73 s | 11 | 3 | Spin-out |

Every sample launches exactly once. Five of six naturally continue beyond eight
clears, through repeated swarms and later rivals. Longer samples reach levels
10-13; two fill the current investment pool without terminating. Raw evidence:
`tests/task002c1-continuous-results.json`. These are simulation observations,
not human feel or final balance acceptance. No new FPS benchmark is claimed.

## Major changed files and checkpoint

- `scripts/continuous_run.gd`: lifecycle, counts, safe entry, cleanup and centralized temporary tuning.
- `scripts/battle.gd`: one-launch entry, live threat admission, loss-only Run ending and state-safe event routing.
- `scripts/encounters.gd`: repeating deterministic scaffold with no maximum index.
- `scripts/swarm_runtime.gd`: unique ID base and threat-local schedule clock.
- `scripts/power_runtime.gd`: retired enemy/attribution cleanup without player reset.
- `scripts/run_context.gd`, `run_progression.gd`: continuing claims/progression and bounded retired-event history.
- `scripts/main.gd`, `menus.gd`: automatic threat flow, active survival HUD and Run-loss statistics.
- `scripts/run_powers.gd`: Second Wind copy now says once per launch.
- Tests: new continuous lifecycle/combat diagnostic and explicit UI fixtures; adapted finite flow/controller/progression/investment tests; raw continuous results.
- README, this report, playtest guide and Windows package/hash.

Playable checkpoint: `releases/windows/SpinningMetal.exe` (self-contained Windows
x86_64). Follow `TASK-002C1-PLAYTEST.md` or the copy beside the executable.

Known limits: the four-threat script repeats without difficulty escalation;
the temporary reserve discount makes sustained play much easier; eight minutes
is a diagnostic stop, not a validated balance target; the investment pool still
caps at thirteen; human continuity feel and physical controller acceptance of
this checkpoint remain to be tested. Historical Task 002C mutation behaviour is
preserved, not expanded. No procedural director, boss scheduler, permanent
progression, rarity/shop economy, final RPM sustain, new abilities/evolutions,
major art pass or final audiovisual escalation was implemented. Work stops at
this checkpoint before Task 002C.2 design.
