# Task 002C.3 — Endless RPM survival economy

Checkpoint branch: `task-002c3-rpm-survival-economy`.
Exact accepted starting commit: `33337e23bdc7d03575a89b2fc4490c1cb2a93bee`.
Fetched and verified `origin/main`; the working tree was clean before branching.
Inspected C.1/C.2 reports, all branches, continuous/battle/power/starter/director
code, historical natural telemetry, and ran all 21 relevant baseline suites.
Nothing is merged to main. Human feel and final balance acceptance are pending.

## Model and removal of the temporary rule

`ContinuousRun.TUNING.player_rpm_loss_scale = 0.12` and
`apply_testing_rpm(previous_rpm)` are removed. Previously battle captured the
player's reserve before each live tick, then refunded 88% of **net negative**
change before Second Wind. That hid most power, collision, wall and running costs.
The capture and refund call are gone from `battle.gd`.

Each Run now owns one `SpinEconomy` for its entire launch. Source-aware writes
charge real costs; combat can earn explicit gains independently. Ordinary threats,
bosses, drafts and new waves never replace that economy or player. Quick Duel and
standalone modes retain their original equations, power costs and result flow.
The director's policy, seeds, pressure budgets and XP rewards are unchanged.

Values below are fractions of a full reserve (1.0 = 9000 displayed RPM).
Central tuning is `scripts/spin_economy.gd::TUNING`; existing modular stats and
starter handling remain in `parts.gd` and `starters.gd`.

| Loss | Continuous player rule |
|---|---|
| Natural | `max(0.0008, 0.0032 - stamina * 0.00022)` per active second |
| Movement / acceleration effort | `speed / 230 * 0.0012 + steering_length_squared * 0.0010` per second |
| Braking | 0.0025 per held second |
| Wobble / instability | `wobble * 0.003` per second |
| Burst | Full 0.013 per accepted activation; same four-second cooldown |
| Enemy collisions | Existing impact/attack/defence equations, fully charged |
| Walls | Existing outward-speed loss, capped at 0.019 per rebound, fully charged |
| Redline activation | 0.025 at rank I; 0.045 at rank II/mutations, in addition to Burst |
| Sustained Redline / Runaway heat | `0.015 + heat * 0.025` per second while active |
| Breakneck crash | Existing 0.025 plus instability and loss of momentum |
| Afterimage / other power costs | Existing trace prices (0.002/0.003) and physical consequences retained |

Only the first four running terms use existing starter `spin_drain` and the
existing Slipstream running-efficiency modifier. There is no multiplier on net
loss, contacts, walls, Burst or power prices. Ratchet/bit stamina, grip, stability,
speed and mass affect conservation through real parts and movement. Dead Centre
still stabilizes/anchors; stable control avoids the additional wobble cost.
Low reserve still degrades steering, imposes wobble below 32%, and spins out at
4.5%. Natural loss is always positive. Idle play cannot generate baseline regen.

## Earned recovery and protections

- A full-size hostile contact needs severity >= 0.32, actual enemy spin damage
  >= 0.004, steering >= 0.08 and pre-contact movement >= 8 world units/second.
  It must either approach at >= 25 units/second or be a stable defensive reception
  (wobble <= 0.30, steering <= 0.65). This permits controlled defence without
  demanding constant offensive charging, but rejects no-input/stationary farming.
- Return is `damage * 2.8 + severity * 0.026`, plus 0.040 for a committed approach
  >= 65 units/second. Maximum 0.095 per contact. Same-target cooldown is 1.4s;
  global contact cooldown is 0.35s. Tiny repeated taps earn nothing.
- Recently credited full-top elimination: ordinary 0.045, elite 0.075, boss 0.12.
  Contact or valid player-owned physical power pressure must be within 12 seconds.
  Merely waiting for an old tagged enemy to decay cannot cash a stale reward.
- Small tops give no baseline contact reward and only 0.001 per attributed
  elimination. **All** small-body returns, including existing Runaway refunds,
  share a 0.008-capacity bucket replenishing at 0.002/second. An entire 30-second
  swarm can return at most 6.8% through these sources, never a full refill.
- Combat, eliminations, Runaway and Slipstream share a 0.12-capacity recovery
  bucket replenishing at 0.045/second. Elite/boss amounts are maxima: a recently
  spent bucket can reduce them. Simultaneous deaths cannot create a huge refill.
- Every gain clamps to 1.0. Rewards preserve velocity, position, cooldowns and
  wobble. Recovery improves control through the existing RPM equations; it does
  not silently clear instability.
- Second Wind remains an independent once-per-launch emergency: up to 0.18
  reserve plus its original 0.25 wobble relief. It bypasses the ordinary recovery
  bucket so earlier success cannot consume the emergency rescue. Original trigger
  conditions remain. Its source is separately recorded and labelled in the HUD.
- Current dictionary identity, current Run economy ownership, live target checks,
  once-only elimination tracking and retirement pruning prevent stale payouts.
  Menus/drafts stop simulation, accounting, cooldowns and token replenishment.
  A provisional enemy RPM threshold crossing cannot pay before its eligible Second
  Wind runs. A regression covers this lifecycle edge case; current director enemy
  configurations do not carry Second Wind, so measured pacing is unaffected.

There is no passive-only survival ceiling: renewable successful combat can exceed
running and impact costs without consuming a finite pool of healing items. This
is a potential equilibrium, not a promise that any particular bot/build survives
forever. Unsuccessful Burst/Redline expenditure and poor contacts remain costly.

## Diagnostics and presentation

The normal HUD retains its layout. Under 25% it labels **LOW SPIN** in red;
meaningful returns briefly show a green **+RPM RECLAIM**, or **SECOND WIND**.
No debug accounting is shown during normal play.

`SpinEconomy.snapshot()` records eight loss categories, seven gain categories,
starting/minimum/final reserve, time below 50%/25%/14%, recovery count/largest/total,
death reason and the last 128 recovery records. Contact/credit/paid maps are bounded
by live/retiring enemies. The normal end-of-Run diagnostic
`user://last_run_director.json` includes this ledger alongside director history,
seed and investments. Recovery occurs before Second Wind and result evaluation,
so a real hit can rescue a collapsing reserve in the same tick.

`tests/rpm_bot.gd` supplies sampled deterministic input, not physics overrides.
Aggressive pursues and frequently Bursts; defensive makes small centre corrections;
hybrid alternates approach and conservation. AFK and reckless controls test failures.
`test_rpm_playthrough.gd` uses real Main drafts, actual rivals, the unchanged director,
and ordinary earned ranks/mutations. No reserve holds/refills, spin-out interception,
injected wins, deleted enemies or teleports occur. Its 1200s ceiling is diagnostic
only. Each tick checks the same player object and director admission budgets.
Each finished sample checks `start + gains - losses == final` to within 0.000001.

Full raw iteration logs/curves are outside Git at
`C:\GPT GAME BUILDING\task-002c3-qa`. Compact final telemetry is retained in
`tests/task002c3-rpm-results.json`. Historical C.2 telemetry remains unchanged.

## Iteration evidence

1. Removed the net rebate; introduced classified running costs and capped recovery.
   The old nine-case chasing bot survived 58–376s. Aggressive Redline expenditure
   was excessive; no power or impact cost was silently refunded.
2. Nine explicit style/starter samples exposed the spread: aggressive 105–129s,
   defensive 226–1200s, hybrid 267–442s. Loss accounting identified power spending
   and unsuccessful contacts, not natural decay alone, as the aggressive problem.
3. Reduced only continuous-player Redline activation and heat prices; rewarded
   committed approaches. Added explicit stationary-contact rejection, tested again,
   and raised the committed-contact premium from 2.5% to 4%. This retained misses,
   crashes, Burst and wall costs. The director was not retuned.

Final matrix results and verification follow below. Automated control results do
not establish human balance or prove that these bots approximate expert play.

## Files and reproducibility

- `scripts/spin_economy.gd`: tuning, costs, rewards, guards and accounting.
- `scripts/battle.gd`, `continuous_run.gd`, `power_runtime.gd`: source-aware hooks,
  launch ownership, retirement and selective Redline prices.
- `scripts/menus.gd`, `main.gd`: restrained feedback and saved RPM diagnostic.
- `tests/test_spin_economy.gd`, updated `test_continuous_run.gd`: invariants.
- `tests/rpm_bot.gd`, `test_rpm_playthrough.gd`, `test_rpm_replay.gd`: natural controls,
  ledger closure and exact seeded replay.
- `tests/capture_rpm_review.gd`: real-tick replay with normal gameplay audio.
- Windows checkpoint, playtest guide, compact JSON and this report.

Run diagnostics with Godot 4.7.2:

```text
--headless --path . --script tests/test_spin_economy.gd
--headless --path . --script tests/test_rpm_replay.gd
--headless --path . --script tests/test_rpm_playthrough.gd -- --report=<output.json>
```

Use `--quick` for nine style/starter cases and `--styles=aggressive` to restrict
styles. Capture uses `--write-movie=<outside-repo.avi> --fixed-fps 60` and
`--script tests/capture_rpm_review.gd -- --style=... --starter=... --seed=...`
with `--start=<active second> --length=16 --manifest=<outside-repo.json>`.
Capture fast-forwards actual combat from launch without rendering pre-roll;
earned draft animations are skipped, as in diagnostics. It never edits RPM or
forces an outcome. The resulting AVI/audio is encoded to H.264/AAC MP4 with
nearest-neighbour scaling, and encoded frames are inspected. Videos stay outside Git.

## Limits

This is the first survival economy, not final balance. Two seeds per controlled
style/starter cannot establish the full distribution. Recovery is intentionally
an arcade combat reward rather than literal conservation of angular momentum.
Directional input is an intent proxy, not a measure of human skill. Passive enemy
decay still exists; stale-credit expiry limits opportunistic passive payouts.
The existing 13-investment content ceiling and finite role/boss catalogue remain;
the Run and director remain endless. No collection, unlock, shop, rarity or permanent
progression systems were added. A human controller/feel check is still required.

## Final natural results

The main matrix contains 24 natural Runs: 3 starters × 3 controlled styles × 2
seeds, plus 3 no-input and 3 reckless controls. Aggressive seed 421 prefers Redline;
7341 prefers Impact Wake. Defence prefers Dead Centre and hybrid prefers Afterimage.
Offers remain the real seeded choices; the preference is used only when offered.
Three additional natural Runs prefer Redline/Breakneck. Across four tuning passes,
these extra cases and four exact replay samples, **73 natural simulations** were executed.
Four separate capture replays are not counted as completed balance samples.

| Style | Starter | Seed 421 seconds | Seed 7341 seconds |
|---|---|---:|---:|
| Aggressive | Breaker | 69.50 | 314.25 |
| Aggressive | Bastion | 180.85 | 478.22 |
| Aggressive | Vane | 136.53 | 616.50 |
| Defensive | Breaker | 224.20 | 190.00 |
| Defensive | Bastion | 360.23 | 532.33 |
| Defensive | Vane | 1200.02* | 1200.02* |
| Hybrid | Breaker | 370.17 | 332.37 |
| Hybrid | Bastion | 663.73 | 1200.02* |
| Hybrid | Vane | 380.93 | 1200.02* |

`*` Reached the 1200-active-second diagnostic ceiling alive; not a victory or game
limit. The main matrix ended in **15 spin-outs, 5 ring-outs and 4 sample ceilings**.
AFK Breaker/Bastion/Vane died at 137.85/267.15/209.27s; reckless controls at
4.73/27.75/54.25s. Additional Breakneck runs ended naturally by spin-out at
213.00/264.73/363.75s, spending 0.602/1.211/2.277 full reserves on powers.

Aggressive median survival was 247.55s; movement spending averaged 0.001001/second
and recovered reserve 0.019581/second. Defensive median was 446.28s; movement
spending averaged 0.000236/second (about 76% less), with recovery 0.005522/second.
Hybrid median was 522.33s; movement spending 0.000572/second and recovery
0.012121/second. These are unweighted sample averages, not fitted difficulty targets.
Aggression has greater recovery opportunities but severe costs for misses; the
strongest aggressive sample reached 616.5s. Defensive Vane and two hybrid builds
reached 20 minutes. Starter/build spread is substantial and remains a playtest issue.

Across the 24 primary samples, collisions consumed 73.105 total reserves, powers
25.804, passive decay 18.481, Burst 9.087, movement 5.154, wobble 2.589, walls 1.325
and braking 0.697. Collision reclamation supplied 89.904, ordinary/small eliminations
9.101, elites 6.245, bosses 2.695, Runaway 6.788 and Second Wind 3.363. Slipstream was
not selected by the primary bot's default mutation preference; its existing
regression coverage and accounting hook remain. Small-body farming is additionally
bounded by invariant tests rather than inferred from aggregate elimination gains.

Second Wind actually helped 20/24 primary samples. Defensive Vane seed 421 reached
20 minutes without using it, so it is not a mandatory upkeep source. After the
first 30s, primary samples averaged 40–82% RPM, with no primary sample spending
more than 30% of its sampled time above 95%. Many spent meaningful time below 25%;
the aggressive Vane seed 7341 spent 75s there. Largest possible baseline return
is 12%, and largest observed overall recovery was Second Wind's 18%.

Earned-choice gaps across the 18 primary style samples had a median of 24.27s
(minimum 1.91s). XP prices/rewards were not changed; these are discrete earned
drafts rather than continuous menu churn.

The main matrix defeated 57 bosses, reached tier 11 and stayed within the existing
16-entity ceiling. Every Run kept one launch and the same player object. Maximum
ledger closure error was below 2.5e-12. No director policy interaction bug required
a retune; economy retirement and event attribution were integrated into its existing
lifecycle. Both ordinary and boss deaths leave surviving threats and physical state
live. Swarm recovery limits are shared with small-target Runaway to prevent a
second reward path from bypassing the cap.

## Verification

All 21 accepted-baseline suites passed before edits. All 22 final suites below
passed; no regression suite was deleted. The revised continuous test replaces the
obsolete 12% assertion with full-cost/explicit-reward assertions and adds the economy
ledger to draft continuity snapshots.

- `card_assets`: CARD_ASSETS_TEST_PASS checks=113 failures=0
- `combat_architecture`: Combat architecture: 35 checks, 0 failures
- `continuous_run`: CONTINUOUS_RUN_PASS checks=200 failures=0
- `controller`: CONTROLLER_TEST_PASS checks=670 failures=0 synthetic_device=3 physical_hardware=NOT_TESTED
- `escalation_assets`: ESCALATION_ASSETS_TEST_PASS checks=291 failures=0
- `escalation_completion`: ESCALATION_COMPLETION_PASS checks=34 failures=0
- `escalation_integration`: ESCALATION_INTEGRATION_PASS checks=628 failures=0 synthetic_gamepad=3 physical_hardware=NOT_TESTED
- `escalation_physics`: Escalation physics: 103 checks, 0 failures
- `escalation_progression`: ESCALATION_PROGRESSION_TEST_PASS checks=513 failures=0
- `flow`: FLOW_TEST_PASS checks=158 failures=0
- `menus`: MENU_TEST_PASS checks=1399 failures=0
- `powers`: Power runtime: 79 checks, 0 failures
- `presentation`: PRESENTATION_TEST_PASS checks=72 failures=0
- `progression`: PROGRESSION_TEST_PASS checks=150 failures=0
- `ramp_integration`: RAMP_INTEGRATION_PASS checks=19 failures=0
- `run_context`: RUN_CONTEXT_TEST_PASS checks=332 failures=0
- `spin_economy`: SPIN_ECONOMY_PASS checks=232 failures=0
- `starter_physics`: STARTER_PHYSICS_TEST_PASS checks=37 failures=0
- `starters`: STARTER_TEST_PASS checks=17 failures=0
- `swarm`: SWARM_TEST_PASS checks=33 failures=0
- `threat_director`: THREAT_DIRECTOR_PASS checks=83 failures=0 samples=8
- `xp_observer`: XP_OBSERVER_TEST_PASS checks=30 failures=0

Additional checks: exact natural seeded replay (two Runs, matching RPM curves,
recovery records, events and progression); natural matrix ledger/cap/object asserts;
**127,776 unchanged Quick Duel physics fields across 48 assemblies**; native menu
1399 checks; native H.264 frame inspections; all four MP4s contain gameplay audio;
Windows release export and packaged smoke passed. Packaged smoke covers Quick Duel,
starter/draft/level-up/mutation, ten continuous fixture transitions, defeat/restart
and end-run. Those flow fixtures are not presented as natural survival evidence.

## Delivery artifacts

Windows: `C:\GPT GAME BUILDING\GyroBrothers\releases\windows\SpinningMetal.exe`
(the matching SHA-256 is alongside it). Source checkpoint is on the task branch.
Playtest checklist: `TASK-002C3-PLAYTEST.md`.

Videos in `C:\GPT GAME BUILDING\task-002c3-qa\mobile`:

| File | Reproducible window | What it demonstrates |
|---|---|---|
| `002c3_aggressive.mp4` | Breaker, aggressive, seed 421, 7.02–22.82s | Burst/Redline spending, committed hits, earned returns and continued attack |
| `002c3_defensive.mp4` | Bastion, defensive, seed 7341, 150–166s | Three-rival pressure, 0 Burst/power cost, controlled conservation |
| `002c3_low_rpm_comeback.mp4` | Vane, aggressive/Impact Wake, seed 7341, 426.02–445.75s | Sub-18% impacts reclaim 7.51% and 7.64%, then a 10.96% boss payoff; no Second Wind in the clip |
| `002c3_boss_pressure.mp4` | Vane, aggressive/Impact Wake, seed 7341, 295–314.83s | Red Reaper defeat gives 12%, physical play continues and the director admits Ammunition Waves |

MP4 H.264/AAC, 1280×720 at 60fps, 16–20s, about 1.0–1.7MB each. Native 2× pixel
rendering plus nearest-neighbour encoding scale. At least two representative encoded
frames per clip were inspected, including LOW SPIN/recovery text and BOSS TOPPLED.
The manifests retain beginning/end ledgers and actual event times; no direct RPM
edits or forced outcomes were used. The comeback finishes at 42.1% RPM, still far
from full. Second Wind had occurred earlier in that Run, not during this window.
