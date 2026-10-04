# Task 002C.4 — Signature ability animation and combat feel checkpoint

Branch: `task-002c4-signature-combat-feel`.
Exact accepted starting SHA: `d76589e6a882026d44d95518cbc28087e65707b5`.
Fetched and verified `origin/main`, inspected branch history and B.1/C/C.1/C.2/C.3
reports/runtime/art/audio, confirmed a clean tree, and passed all 23 baseline
suites before branching. Final SHA is supplied in delivery/Git history, avoiding
a self-referential commit hash. No merge to main. Human visual/feel acceptance
and physical controller testing remain pending.

## Visual progression

- **Redline I:** two small rotor exhaust accents with uneven mechanical rhythm.
  **II:** broken hot rotor rim, additional exhaust banks and directional wake
  composition. **Runaway:** real heat selects low/high overload; high heat adds
  separated fragments and irregular key flashes. **Breakneck:** compressed
  trailing charge, bright local strike key, fractured follow-through, then a
  separate scrape/recoil recovery animation and descending mechanical sound.
  Paid activation rank/mutation stays visually consistent if a draft upgrades
  ownership during that activation.
- **Dead Centre I:** sparse floor teeth draw inward with actual Anchor charge.
  **II:** four locked jaws and a clear grounded perimeter. **Bulwark:** broad
  load-bearing feet, floor contact reaction and expelled fragments; existing
  real counter-impulse moves the attacker while the player's Bit stays planted.
  **Counterweight:** five illuminated accumulator cells represent actual stored
  force; release uses a separate pressure burst and projected directional cone.
  A store event only punctuates contact, never animates a fictitious full charge.
- **Afterimage I:** sparse directional scars. **II:** connected lane, larger
  authored sockets and age-dependent contrast. **Ghost Circuit:** two terminals
  latch; the actual player-written polygon flashes and contracts inward for
  0.55 seconds, with lit route sockets. It is not an arbitrary circular blast.
  **Slipstream:** quick crossing latch and authored acceleration arrows, coupled
  to the existing crossing cue and surge state.

New `signature_visuals.gd` is a pure presentation selector/atlas renderer.
`power_visuals.gd` composes its cels with existing projected routes. Physical
power runtime still owns rank, heat, charge, storage, paths, hits and costs.
Only two presentation notifications were added there: Breakneck recovery kind
and a circuit-closure visual age. Neither changes power timing or equations.

## Impact, enemy and machine feedback

| Full-top contact | Run hold | Shake amplitude | Artwork |
|---|---:|---:|---|
| Light, severity <0.32 | 0 ms | 0 | Tiny short scrape |
| Meaningful, 0.32–0.75 | 16.7 ms | up to 0.5 px | Separated contact cut |
| Heavy, >=0.75 | 33.3 ms | 1.5 px | Bright core plus fragments |
| Breakneck/Bulwark signature | 50 ms | 3 px | Exceptional keyed contact |

Run normal holds are gated by the existing 0.24-second contact presentation
cooldown; signature holds have a separate 0.35-second gate. Small-top contacts
do not gain holds. Signature shake lasts 0.13 seconds, normal heavy shake 0.11.
Existing legacy Quick Duel hold remains two fixed ticks above severity 0.5.
The camera projection/orientation never changes; only the existing optional
draw offset uses the new amplitude hierarchy. Contact cels draw in front of
the assembled top; floor locks/routes stay below it. Actual collision recoil,
height and wobble remain authoritative. No visual changes collision geometry.

These bounded holds are the deliberate feedback-timing change in this task.
Active survival time excludes holds as before. Extra holds can change outcomes
for wall-tick-sampled bots through input timing; this is not a claim of identical
old/new bot outcomes. Collision impulses, RPM prices/rewards, director policy,
XP, cooldown progression per active tick and power mechanics are not retuned.

Elites retain compact markers: Ballast gains planted broad feet, Hotwire a split
crown accent; entry has a small projected pulse. Boss warning now has a layered
low port cue and closing projected port geometry. Existing incoming-name HUD
continues while the player moves. Both Anvil and Red Reaper use this shared
arrival language and their existing distinct physical roles. Boss death adds a
short keyed collapse and a low/rising payoff sound; counted-once lifecycle guards
prevent duplicate death effects. No arena clear, refill, teleport or result menu.

Low RPM adds uneven cosmetic body lean, intermittent contact scrape and a quiet
warning at most once per four active seconds. Real wobble/control degradation
is unchanged. Reclaim >=2% reserve produces inward fragments and a short rising
cue, globally limited to once per 0.45 seconds. Tiny rewards stay quiet. Existing
HUD reward amount remains source-aware. Second Wind bypasses ordinary reclaim
feedback: its own compression/catch/release pose and broader keyed ring remain
distinct, once per launch. Breaker leans into Burst, Bastion's cosmetic lean is
restrained, and Vane adds a small directional lateral rhythm; Bit positions and
actual handling are untouched.

Five new finite PCM cues: `boss_port`, `boss_payoff`, `rpm_reclaim`, `low_rpm`,
`breakneck_recovery`. Existing Redline, Anchor, Counterweight, Ghost, Slipstream,
heavy and Second Wind cues remain coupled to their actual events. Audio keeps
the eight-voice priority pool and per-cue cooldowns. No new constant loop.

## Production files and validation

[Art handoff](assets/source-art/SIGNATURE-002C4.md) documents all four masters,
28 tags/168 frames, named layers, palettes, per-frame timings, pivots, safe
editing and native export. Four runtime PNG atlases plus JSON metadata are under
`assets/powers/signature_*`. Audio builder/manifest are under `tools/` and
`assets/audio/signature_manifest.json`.

Major code changes: `signature_visuals.gd`, `power_visuals.gd`, `battle.gd`,
`power_runtime.gd`, `continuous_run.gd`, `spin_economy.gd`, `sound.gd`.
Added signature tests, native matrix, controlled capture and natural replay
diagnostics. The existing escalation integration test now waits through a
retained bounded impact hold before requiring post-draft combat advancement;
its exact-state preservation checks remain intact.

All 24 relevant final suites pass: spin economy, director, continuous Run,
RunContext, flow, combat architecture, menus, controller, powers, swarm,
presentation, progression, starters, starter physics, XP observer, ramp
integration, card assets, escalation progression/physics/integration/completion/
assets, RPM replay and signature presentation. New signature suite: **3,177
checks**, including source integrity, distinct selection, paid activation,
bounded FX, recovery threshold/debounce, pause, boss count-once, player identity,
and identical physics/events with particles/shake enabled versus disabled.
Escalation integration: **634 checks**. No regression suites were removed.

Additional verification:

- **127,776** differential physical-field comparisons across **48** Quick Duel
  assemblies against accepted C.3 battle source: zero differences.
- Two seeded natural RPM replays: exact repeatability of curves, events,
  accounting and progression.
- Native Aseprite open/export of all four masters: pixel-identical runtime sheets.
- **23** native 640×360 static visual states inspected, plus three five-active-
  second real-motion cases. Actual procs: Runaway 7, Bulwark 3, Ghost closure 1
  with an enclosed-enemy activation. Draw captures leave physics unchanged.
- Packaged Windows flow smoke passes Quick Duel, starter/draft/mutations,
  ten continuous threat fixtures, loss/restart and one launch per Run.
- Natural diagnostic sample: two 7341 aggressive-controller Runs opening with
  Dead Centre. Vane ring-out at **65.87 s**; Bastion spin-out at **407.67 s**,
  two boss defeats, Second Wind at **363.88 s**, and baseline low-RPM gains.
  These locate honest capture windows; they are not balance acceptance.

Native held-12-small-top stress fixture: 419 measured samples, 28 active FX,
median/p95 draw submission **0.643/1.016 ms**, fixed-step simulation
**1.852/2.905 ms**, wall-frame **3.132/4.735 ms** on i3-10105F/GTX1660.
CPU draw submission excludes asynchronous GPU execution. The fixture intentionally
holds bodies for stress and is NOT natural gameplay/video evidence. Existing
particle cap120 and FX cap32 remain; transient floor rings now also cap32.
Route sockets retain per-trace count limits, and no physics population cap changed.

## Checkpoint and review artifacts

Windows: `releases/windows/SpinningMetal.exe` with adjacent `.exe.sha256`.
No Godot installation is required. Branch uses existing Git LFS workflow.
External review directory: `C:\GPT GAME BUILDING\task-002c4-qa`.

| MP4 | What it demonstrates |
|---|---|
| `002c4_redline_escalation.mp4` | 18 s, three labelled opening presets: I, II, Breakneck; real paid Bursts and two Breakneck impacts. Cuts are explicit, not fake earned upgrades. |
| `002c4_dead_centre.mp4` | 14 s, Bulwark forms Anchor and receives five real repulsion contacts while planted. |
| `002c4_afterimage.mp4` | 21 s, labelled I/II/Ghost presets; real route drawing and circuit closure. The selected loop has no enemy inside at closure; the separate five-second native case verifies enclosed-enemy response. |
| `002c4_boss_combat.mp4` | 22 s, uninterrupted natural Bastion Run at 208–230 active seconds: Anvil warning/entry into existing mixed combat. |
| `002c4_low_rpm_comeback.mp4` | 22 s, same natural Run at 396–418 seconds: danger, ordinary earned reclaim, Red Reaper defeat and continuation. Second Wind was spent earlier; **no Second Wind recovery in this clip**. |

All five are H.264/AAC, 1280×720, nearest-neighbour integer2× native output,
gameplay audio included. Representative encoded frames and audio levels inspected.
No direct RPM edits, forced deaths, protected players or fabricated recovery.
The first three use disclosed initial builds/poses; after setup only steering,
Burst and brake. Last two fast-forward the same real Run and earned drafts from
launch. Large videos remain outside Git. Compact provenance/results are in
`tests/task002c4-results.json`; detailed capture manifests/logs are in the review
directory. `002c4_before_after.png` pairs full native captures for all three
families. `matrix-final/` contains explicitly labelled static QA states.

## Limits and human review

This is a focused presentation slice, not final art/audio polish. Bosses share
the new entry/collapse language; no new boss sprite library. Existing card art
and other powers remain. Not every mutation appears in the five short videos;
the static matrix and existing practice launchers cover the rest. The selected
Ghost movie proves closure rather than a trapped target. No claim that bot
inspection establishes human feel, controller comfort or low-end performance.

Play START RUN with each starter and one flagship opening power. Compare I/II,
then a mutation. Check violent Breakneck versus heavy Bulwark; readable stored
Counterweight force; understandable Ghost closure and quick Slipstream; stronger
hits without constant vibration; important bosses amid readable overlapping
pressure; low-RPM danger and earned recovery. Most importantly: does the late
machine visibly look much more dangerous than at launch? Stop here for human
acceptance before designing the next milestone.
