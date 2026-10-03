# Task 002A — Run architecture and combat generalisation

Implementation starts from verified canonical commit
`d551867966a1711d83ddf064f06d5f6f6ffc56ae` on `main`. Work is isolated on
`task-002a-run-architecture`; no merge to `main` is part of this task.

## Delivered scope

Quick Duel retains its opponent selection, rematch, ordinary full-top physics,
60-second live-time limit, result rules and physical assembly catalogue. The old
three-fight gauntlet is replaced by the eight-slot Run, avoiding two competing
progression systems. Its useful flow tests are adapted and expanded.

All eight Run slots are ordinary full-top duel fixtures. Descriptors retain the
intended Standard / Vane / Swarm / Elite / Arena / Rematch / Redline Elite / Boss
identities, but expose `fixture: true`, `fixture_type: duel` and the ordinary
`pursuit` profile. No specialist AI, arena rule, small top or boss is activated.
The final fixture uses the same 60-second limit as other normal duels.

Twelve power IDs and cards are available in a separate catalogue. They can be
collected and displayed, but all effects are inactive and the UI states this.
**Task 002B has NOT been implemented.**

## Architecture

`battle.gd` records an encounter-local positive `entity_id`, explicit `team_id`,
`owner_id` and `combatant_type`. Launch velocity, AI timing and AI direction live
on each entity. Player lookup, targeting, controls, HUD, snapshot, rendering and
results use these fields instead of storage positions. Runtime IDs are not reused
within an encounter. Only `full_top` is active; `neutral` is available as a team.
The legacy `winner` value is retained as a 0/1 team result for Quick Duel/tests,
with explicit `winner_entity_id` and `winner_team_id` added. The old positional
test setter remains solely as a compatibility seam; new tests address IDs.

Contacts enumerate unordered pairs in stable ID order and resolve their actual
two entities. The original full-top contact, movement, bank and wall coefficients
are preserved. Damage uses a 0.24-second cooldown keyed by canonical entity-ID
pair; separation and momentum response retain their prior ordering. Each accepted
contact exposes both IDs. Another pair's cooldown or presentation throttle cannot
suppress its gameplay. Impact/height state affects only the contacting pair.
Canonical order supplies the deterministic rightward normal for exact overlaps.
Hit-stop remains the authored gameplay hold, independent of particle settings.
Full-top team elimination and timeout results commit once; one retired hostile
does not finish an encounter while others survive.

`seed_utils.gd` derives unsigned 32-bit seeds with explicitly versioned FNV-1a
over UTF-8 `topgame-seed-v1|<base>|<domain>`. Combat/simulation, per-entity AI,
drafting, encounter selection and cosmetic presentation have separate streams or
derived seeds. Simulation currently requires no random draws; its stream is
reserved independently. Particle creation and spin-phase variation use cosmetics
only. Explicit seed zero is deterministic. Fresh Run entropy is sampled once at
start/restart; encounter and reward seeds never depend on frame or menu timing.

`run_context.gd` owns the validated locked assembly, Run seed, 1-based slot,
owned IDs, pending offer, result/reward commitments and active/failed/complete
state. Public collection/build access returns copies. Settings and saved garage
build remain separate; encounter state is recreated at every launch. RPM, wobble,
Burst readiness, pair cooldowns and all transient battle state reset.

Wins after slots **1, 2, 3, 4, 6 and 7** generate exactly one stored offer. The
draft uses a local RNG derived from Run seed and stable slot ID, and Fisher-Yates
selection from the fixed twelve-ID catalogue after removing owned IDs. Each offer
has three distinct unowned powers. Rendering or Escape never generates a new
offer. A valid card commits one acquisition and proceeds to the next encounter;
slot 5 has a simple continuation and slot 8 ends the Run without a draft.

Result callbacks must match the current descriptor ID and seed; card callbacks
also carry the Run seed. State and commitment guards reject duplicate/stale
callbacks, including callbacks from a restarted Run at the same slot. Active Run
routes cannot reach the garage or change the physical build. Escape preserves
combat, rewards and the slot-5 result through Resume / Restart Run / End Run.
Loss ends the whole Run. Restart keeps the assembly, gets a fresh seed and clears
all claims. Explicit exit and terminal-result navigation clear Run-only state.

Replay requires the Run seed, assembly, chosen IDs by draft slot and recorded
fixed-tick combat inputs. Seed alone does not reconstruct human choices. The
context keeps chosen IDs by slot; this task does not add replay-file persistence
or mid-Run save/resume. Historical seeded AI trajectories necessarily change
because AI no longer shares particle draws; this is not a balance retune.

## Validation

Tested with Godot `4.7.2.stable.official.ed1daf0bf` on Windows. Baseline and
regression combat harnesses run in separate disposable checkouts so historical
tracked QA and balance evidence is preserved.

- Before refactoring: 51 combat checks, all 144 seeded build bouts and 34 original
  flow checks passed. Baseline median was reproduced at 30.52 seconds (24.72–35.38).
- New Run context suite: 301 checks passed.
- Expanded flow suite: 297 checks passed.
- New combat architecture suite: 35 checks passed, including independent same-tick
  pairs, reversed storage, multi-entity fixtures, zero seeds, late contact rejection
  and identical physical/AI ticks through a completed bout with altered cosmetics.
- Native menu suite: 796 checks passed. Real keyboard navigation/activation checks
  all twelve reward cards and all 48 garage assemblies; shaped text measurements
  cover descriptions, names and six collected labels. This caught and prompted a
  fix for the longest card (Chain Impact) being clipped.
- Original combat regression: all 51 checks and 144 seeded bouts passed unchanged.
  New median 30.77 seconds, range 24.87–37.17, versus baseline 30.52 / 24.72–35.38.
  RNG isolation changes historical AI trajectories; no tuning coefficients changed.
- `tests/test_baseline_physics.gd` compares the actual pinned baseline source with
  current movement, braking, Burst, boundaries and contact under controlled inputs.
  All 127,776 exact physical field comparisons across all 48 assemblies matched.
- Rendered Windows/OpenGL smoke loops passed at 640×360 and 1280×720
  on an NVIDIA GeForce GTX 1660. Reviewed title, garage, live duel, pause, reward,
  six-power HUD, failure and completion captures. The loops exercise eight slots
  and six choices, reward Escape/reopening, restart and explicit exit.
  A requested 1920×1080 window produced a 1280×720 capture on this desktop;
  a third integer scale is therefore not claimed as validated.

Reproduce the optional baseline differential after making a separate checkout of
`d551867966a1711d83ddf064f06d5f6f6ffc56ae`:

```text
Godot --headless --path . --script res://tests/test_baseline_physics.gd -- --baseline-source=<absolute-baseline-checkout>/scripts/battle.gd
```

The differential bypasses AI deliberately to isolate unchanged physical equations.
The normal deterministic and cosmetic-independence suites also exercise AI. The
rendered smoke victories are flow fixtures, not played full-Run balance evidence.

One initial fresh baseline asset import returned exit 1 without a script error;
the retry completed with exit 0. Historical QA records a similar intermittent
native importer issue. No baseline gameplay test failure was observed.

## Arena source-art follow-up

`assets/source-art/SOURCE-ART.txt` confirms that `arena_foundry_eight.aseprite`
predates the guard-mouth revisions in the playable PNGs. The arena manifest and
runtime agree on side exits beyond `u-v = +/-264` inside `abs(u+v) <= 36`.
Production PNGs and collision alignment remain authoritative and are unchanged.

Before a later visual task exports arena layers, reconcile the current rear/front
guard mouths into a separate editable working copy of the Aseprite source, then
verify native-resolution gate registration and foreground occlusion against the
current PNGs. Do not export the preserved older source over production layers.
No reconciliation or art re-export is attempted in this architecture task.

## Limits and deferred work

Run success/completion tests and reward captures use injected victories to test
flow; they are not claims of eight naturally won fights, human balance, pacing,
swarm performance or boss fairness. The actual combat suite runs 144 seeded
ordinary bouts. Rendering smoke tests exercise the real engine/window and input,
but no exported Web build or new human playtesting is claimed.

Real power effects, Vane behaviour, swarm population/pooling, ammunition waves,
elites, pylons, boss phases, effect art, impulse/power-event machinery, new arenas,
currencies, shops and permanent progression remain deferred. Pair-ready full-top
fixtures do not establish performance for twelve enemies. No physical parts or
production art are changed.
