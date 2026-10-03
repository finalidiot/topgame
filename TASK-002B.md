# Task 002B — First Broken Build

Implemented from local completed Task 002A HEAD `d80752d5b4a954f134af01e74c64d1e4ae174837`,
branch `task-002a-run-architecture`, clean before work; remote
`https://github.com/finalidiot/topgame.git`. The requested `GyroBrothers` directory
was empty. Created it as a Git worktree on `task-002b-first-broken-build` from that
verified local HEAD. The existing Task 002A checkout and historical baseline were
preserved. No reset, merge to main, or synced project-file modification occurred.

## Delivered behavior

| Power | Actual effect and limit |
| --- | --- |
| Impact Wake | Accepted severity >=0.55, 52-world-unit pressure radius at contact, 1.25s cooldown; secondary velocity 60 small/18 full; lone-target follow-through 36 small/12 full; no RPM damage or recursive primary proc. |
| Second Wind | Once per encounter at reserve <=0.14 or wobble >=0.75 with reserve <=0.28; finite +0.18 bounded contribution (own ceiling0.40), wobble -0.25; confirmed gates win priority. Authored contraction nearly stops blade phase, followed by release and upright spin. |
| Redline | Eligible Burst at reserve >=0.35 pays extra0.04; 0.8s effective RPM=min(1.15,reserve+0.35), extended speed window and +0.10 wobble; ordinary attack Burst remains0.42s; first-hit recoil restoration capped20%; no extra reserve/timeout resource or overlapping overdrive. |
| Iron Comet | Actual solid-wall outward speed >=110, retained wall cost, charge2s and rearm1s; next accepted hit consumes bounded25 full/75 small velocity bonus. Gate exits do not charge it. |
| Afterimage | Speed>180, trace every0.18s costing0.002; maximum3 traces lasting0.45s; actual sampled world path, per-target0.6s cooldown and lateral pressure12 full/40 small. No direct reserve damage or solid barrier. |
| Chain Impact | Recent player hits/owned impulses tag small bodies for1s; thrown contacts preserve root/generation and bounded expiry. Eliminations queue next-tick42-radius pulses:65 small/15 full, maximum2 generations and12 pulses/root, once/body. Natural retirement never credits. Heavy full-target hit primes a close-range next-Burst follow-through for2s. |

All five requested synergies are tested: Redline+Comet, Wake+Chain,
Redline+Afterimage, Second Wind+Redline, Wake+Afterimage. Effects use explicit
semantic calls in stable order, independently of signals or cosmetic random draws.
Ordinary full-top equations and the Blade/Ratchet/Bit catalogue remain intact.
The twelve-ID catalogue remains; only six implemented IDs draft. Rewards are
stored, deterministic, unique and committed once. Offers become 3/3/3/3/2/1 as
the available pool is consumed. Acquisition lasts0.65s and preserves pause/focus.
Run simultaneous player elimination and exact timeout ties fail without rewards;
Quick Duel keeps its historical result behavior.

## Swarm

Slot3 is Ammunition Waves, with one full player and no full rival. Tunable waves
6/8/10 begin at live times0/9/18s; each entry gets0.65s floor telegraph. Stable
ports avoid gate mouths. Admission rechecks55-unit player clearance, tries ports
in deterministic order, defers blocked entries and accounts bounded cancellations.
Maximum12 live smalls is enforced at both schedule and entity admission.

Small records have IDs/team, radius5.8, mass1.8, reserve0.22, a9s lifetime,
sampled imperfect0.25–0.35s steering, and compact animation/attribution state.
They have no physical catalogue, six-stat derivation, Burst, brake AI, rig or HUD.
There is no pool reuse: at most24 scheduled records plus the player bound memory.

Throw velocity is capped400 with a brief preservation window. Four bounded motion
substeps protect small radii; stable all-pairs checks consider live records only.
Player incoming small-contact reserve loss is scaled down and capped0.015 per
0.24s aggregate window. Physical impulses still resolve. Small-small contacts are
quiet; small contacts never impose global hit-stop. Retiring bodies visually retain
momentum briefly while immediately leaving gameplay. Cap32 power-FX records and
8 prioritized audio channels; recovery presentation survives ordinary FX eviction.

Clear requires every scheduled entry accounted and no live small. Natural expiry
counts toward clear without elimination procs. At32s cleanup accounts all remaining
entries without credit; player elimination has priority.

## Art and audio

New editable Aseprite sources:
- `assets/source-art/small_top_002b.aseprite`: native24x24,4spin+1contact+3retirement.
- `assets/source-art/power_fx_002b.aseprite`:48 authored128px frames; contact arc,
  segmented pressure/teeth, echo, corona, compression/release, floor stamp and
  eight directional comet wedges. Large cells preserve transparent negative space.
- `assets/source-art/power_icons_002b.aseprite`:six16px HUD/reward icons.

All have named layers/tags, intentional pivots and matching runtime metadata.
`tools/build_power_art.py` normally exports edited source (requires Pillow);
`--author` deliberately regenerates the originals. Actual Aseprite1.3.18.6 batch
exports loaded all three sources and matched exported pixels exactly. Original
arena art/source was not re-exported. New nine mechanical WAV cues regenerate with
`tools/build_power_audio.py`. Sound priorities suppress repeated small/chain cues.

## Validation evidence

Godot4.7.2 on Windows. Before implementation: Run301, combat35, flow297,
menus798, controller498 checks all passed on completed local002A.

Final suites:
- RunContext340; flow334; combat architecture35; powers79; swarm33;
  menus1056; controller517; presentation72: zero failures.
- Original prototype:51 checks and144 seeded ordinary bouts pass in a disposable
  copy, preserving historical QA.txt and balance-results.json. Median30.77s,
  range24.87–37.17, matching Task002A.
- Original baseline differential:127,776 physical field comparisons across all48
  assemblies, zero failures.
- Native menus1076 and controller517 checks pass. Screenshot-enabled native
  controller runs showed intermittent synthetic-input failures; the separate native
  input run without screenshot capture passed. These are reported separately.
- A mapped XInput Controller (device0) was detected. No physical actuation or
  human controller/feel acceptance is claimed. Headless tests exercise device3
  and nonzero-device input, all menus, steering/Burst/brake, pause/rewards,
  acquisition, restart, failure and completion.
- Reviewed native captures at640x360,1280x720,1920x1080, plus a12Hz sequence from
  real deterministic motion. Player rig/marker remains opaque and dominant;
  ghosts have no cap/bit/owner marker; pressure centres leave contact readable.
  These are visual QA observations, not human gameplay ratings.
- Windows executable built with embedded data. Package smoke covers menus, live
  Quick Duel and eight-slot/six-reward flow; its wins are injected flow fixtures.

The natural all-six-power swarm replay cleared in26.117s with39 accepted contacts,
5 eliminations and19 natural retirements (24 spawned,0 cancellations, peak10).
It triggered4 Redlines,36 traces,3 Comet charges,2 Wakes,5 Chain pulses and1 Wind.
Comet release is verified in targeted integration tests, not claimed in that replay.
Seed+recorded inputs reproduce physical state, proc schedule and result when
cosmetic RNG/particles/shake and backing entity storage order change.

Six unmodified-combat bot Run attempts (no injected victories/refills/teleports):
Guard/Low/Needle cleared seeds421 and7341 in246.03s and237.73s live time.
Smash/Low/Flat lost slot1 in both; Balance/Mid/Ball lost slot1 for421 and reached
slot8 before losing for7341. This is evidence of playable progression, not human
balance or proof that every build can clear.

### Performance

Intel Core i3-10105F3.70GHz, NVIDIA GTX1660, Windows compatibility renderer,
640x360, VSync disabled. Corrected held12-body +28FX fixture,419 samples:

| Measured CPU/frame component | Median ms | p95 ms | Max ms |
| --- | ---: | ---: | ---: |
| Simulation |1.848|3.003|3.987|
| Draw-command submission |0.590|1.109|1.644|
| Wall frame including harness |3.251|5.377|7.821|

No16.7ms breach in this bounded fixture. GPU execution is asynchronous and not
separately timed; HUD is excluded; this is not a Web benchmark or a guarantee on
other hardware. A normal deterministic replay measured approximately1.0–1.2ms
median simulation,1.6–2.2ms p95 after removing dead bodies/redundant ID lookups
from pair enumeration. Occasional unrelated-host spikes appeared in other runs;
no universal maximum frame-time claim is made.

## Feel assessment, concerns and remaining acceptance

Mechanically this is materially closer to a roguelite: new inputs/positions now
create world-space lanes, wall charges, crowd throws and finite comeback events;
collected powers combine and visibly escalate. The recorded swarm demonstrates
several real cascades rather than merely showing code or forced proc artwork.
Human confirmation that the run *feels* substantially transformed remains pending.
Desktop computer-use capture failed twice with timeouts, so no hands-on agent UI
playthrough is claimed. A playable executable and focused questionnaire are ready
in `TASK-002B-PLAYTEST.md`; the user was asked for physical-controller/feel feedback.

Balance concerns: central chase still favors Guard/Needle; aggressive bot losses
at slot1 occur before powers and are not solved by secretly strengthening smalls.
The all-six-power swarm replay is a diagnostic fixture; a normal Slot3 player owns
two powers, so exact early synergies depend on draft choices. Afterimage requires
speed/route commitment; Comet requires deliberately seeking walls. No broad part
rebalance was made. No known blocking gameplay bug remains from automated review;
human pacing, sound mix, controller feel and multi-power readability in live play
are still acceptance risks. An earlier Run tie-priority defect was fixed and tested.

Deferred002C/content: other six powers, specialist Vane AI/rematch, elite enemy
power tactics, Crown Engine/phases, pylons/arena systems, final spectacle, shops,
currencies, permanent progression, unlocks, branches and additional arenas.

Evidence on this machine: `C:/GPT GAME BUILDING/topgame-task-002b-artifacts/`
(test logs, natural Run reports, package captures and presentation benchmark), plus
`C:/Users/samdf/.codex/artifacts/task002b-ui-20261003/` (UI and controller evidence).

## Files added and changed

Exact reviewed change inventory (A = added, M = changed):

```text
M	README.md
M	README.txt
A	TASK-002B-PLAYTEST.md
A	TASK-002B.md
A	assets/audio/acquire.wav
A	assets/audio/acquire.wav.import
A	assets/audio/afterimage.wav
A	assets/audio/afterimage.wav.import
A	assets/audio/chain.wav
A	assets/audio/chain.wav.import
A	assets/audio/comet_charge.wav
A	assets/audio/comet_charge.wav.import
A	assets/audio/comet_release.wav
A	assets/audio/comet_release.wav.import
A	assets/audio/power_wake.wav
A	assets/audio/power_wake.wav.import
A	assets/audio/redline.wav
A	assets/audio/redline.wav.import
A	assets/audio/second_wind.wav
A	assets/audio/second_wind.wav.import
A	assets/audio/wave.wav
A	assets/audio/wave.wav.import
A	assets/powers/effects.png
A	assets/powers/effects.png.import
A	assets/powers/icons.png
A	assets/powers/icons.png.import
A	assets/powers/manifest.json
A	assets/powers/small_top.png
A	assets/powers/small_top.png.import
A	assets/source-art/POWER-002B.txt
A	assets/source-art/power_fx_002b.aseprite
A	assets/source-art/power_icons_002b.aseprite
A	assets/source-art/small_top_002b.aseprite
M	releases/windows/README.txt
M	releases/windows/SpinningMetal.exe
M	releases/windows/SpinningMetal.exe.sha256
M	scripts/battle.gd
M	scripts/encounters.gd
M	scripts/main.gd
M	scripts/menus.gd
A	scripts/power_runtime.gd
A	scripts/power_runtime.gd.uid
A	scripts/power_visuals.gd
A	scripts/power_visuals.gd.uid
M	scripts/run_context.gd
M	scripts/run_powers.gd
M	scripts/sound.gd
A	scripts/swarm_runtime.gd
A	scripts/swarm_runtime.gd.uid
A	tests/measured_presentation_battle.gd
A	tests/measured_presentation_battle.gd.uid
M	tests/test_controller.gd
M	tests/test_flow.gd
M	tests/test_menus.gd
A	tests/test_playthrough.gd
A	tests/test_playthrough.gd.uid
A	tests/test_powers.gd
A	tests/test_powers.gd.uid
A	tests/test_presentation.gd
A	tests/test_presentation.gd.uid
M	tests/test_run_context.gd
A	tests/test_swarm.gd
A	tests/test_swarm.gd.uid
A	tools/build_power_art.py
A	tools/build_power_audio.py
```

Generated .godot caches, temporary captures and historical QA/balance output are
not staged. The Windows executable is intentionally tracked through Git LFS.
Final commit SHA and remote/working-tree verification are reported in the task
handoff; this document lives in that same commit.
