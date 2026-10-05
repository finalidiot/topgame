# Task 002C.5 — roster, draft and accepted baseline evidence

This supplement records the catalogue and draft decisions. The main Task 002C.5
report supplies gameplay, art, Windows, performance and video evidence. Human
gameplay acceptance remains pending.

## Accepted baseline

The accepted checkout was exactly
`0c6225f5428e874621f14837e37df47bad505fa7`. Before implementation, the working
tree was clean and all 24 C.4 regression suites passed on Godot
`4.7.2.stable.official.ed1daf0bf`. Import-generated metadata was restored before
the dedicated branch was created. Baseline logs and compact results are outside
Git at `C:\GPT GAME BUILDING\task-002c5-qa\baseline`.

Reports B.1, C, C.1, C.2, C.3 and C.4 were inspected alongside catalogue,
progression, drafting, art, physics and regression contracts. The actual baseline
was **seven active families**, not twelve: Impact Wake, Second Wind, Redline,
Iron Comet, Dead Centre, Afterimage and Chain Impact. The old catalogue also
contained five inactive ideas. It supported thirteen investments: seven
acquisitions and six further investments in three flagships. New offers had
weight 1.0; owned development had weight 1.2. There was no family cap or starter
restriction.

The accepted C.3 primary natural matrix contains 18 real combat Runs. Their
first earned choice had median **11.35 active seconds**, mean 13.80, range
7.52–31.37. First Rank II had median **30.11 s**, range 8.00–121.33. Seventeen
reached a mutation; its first timing had median **124.77 s**, range
22.02–185.40. Rank and mutation identities were reconstructed from the exact
accepted catalogue/context, recorded seed and original bot preferences; every
reconstructed final ownership/rank/mutation matched the recorded result. This
is a reconstruction of existing natural timing, not a fresh balance experiment.
Detailed evidence is `baseline/timing-reconstruction.json` outside Git.

The C.4 capture-location sample contained a Vane ring-out at 65.87 s and a
Bastion spin-out at 407.67 s. Its Bastion finished with all seven families and
all three flagship mutations. The much broader C.3 matrix included 15
spin-outs, five ring-outs and four live 1200-second diagnostic ceilings across
24 primary/control samples; a diagnostic ceiling is not a game victory.

## Final catalogue

The draft pool now contains **thirteen core families**. Every starter can select
every family. Every family has Rank I and Rank II; four flagships have two
mutually exclusive behavioural branches at their third investment.

| Family | Distinct play pattern | RPM relationship | Structure |
|---|---|---|---|
| Impact Wake | Heavy contacts physically disperse nearby machines | Trigger expenditure; impact success also uses ordinary reclamation | I / II |
| Redline | Active overclock creates excess RPM while heat worsens control | Active movement/contact gains; activation, running and consequences spend RPM | I / II / Runaway or Breakneck |
| Iron Comet | A real wall rebound stores a committed next strike | Wall cost remains; stored strike spends RPM | I / II |
| Dead Centre | Controlled central movement plants a physical Anchor | Conserves movement/collision loss through existing physical grounding | I / II / Bulwark or Counterweight |
| Afterimage | Movement writes hostile pressure routes and reusable lanes | Paid trace emission; route reuse can improve motion efficiency | I / II / Ghost Circuit or Slipstream |
| Chain Impact | Credited eliminations propagate pressure; heavy contact primes Burst | Paid chain/follow-through effects and ordinary earned combat recovery | I / II |
| Clutch | In low-spin danger, conserve movement and earn a catch through meaningful contact | Temporary conservation and bounded earned reclamation; no revive or full refill | I / II |
| High Gear | Immediately stronger acceleration and physical speed ceiling | Baseline movement costs remain; mutations change steering/braking cost or efficiency | I / II / Terminal Velocity or Flow State |
| Orbit Drive | Brake and turn into a drift; maintain a deliberate curved route | Sustained arc conserves movement cost; reversals break flow | I / II |
| Crash Guard | A heavy hit engages a short damper, encouraging the next close exchange | Bounded temporary collision-loss reduction; no generation | I / II |
| Momentum Bank | Controlled braking banks lost motion for the next directed Burst | Braking still costs RPM; release spends additional RPM | I / II |
| Predator Line | Repeated contacts with one full rival build pursuit pressure | No separate generation; greater successful contact can earn ordinary reclamation | I / II |
| Crosscut | Steering through a glancing contact creates a lateral shear | Each accepted cut spends RPM; cooldown bounds repeated use | I / II |

Clutch replaces normal draftable Second Wind. The historical `second_wind` ID,
legacy card rows and owned metadata remain readable for migration and accepted
standalone regression fixtures, but `get_offer("second_wind")` returns empty.
It cannot appear in a normal new Run draft. There is no Run-save migration
system because Run ownership does not persist between Runs.

Seven newly active/replacement families are Clutch, High Gear, Orbit Drive,
Crash Guard, Momentum Bank, Predator Line and Crosscut. Crosscut develops an
inactive catalogue idea. Removing Second Wind makes the net expansion six.
Impact Wake, Iron Comet and Chain Impact now have meaningful Rank II development
of their existing physical triggers. Impact Wake and Chain Impact retain their
stable original sources; Iron Comet I/II use dedicated new machine card/icon rows
that replace the old wedge depiction. Family/rank/speed-branch cards now map to
eighteen new native art rows.

## Depth preference and seven family slots

The catalogue has **thirty total content investments**. A single machine has
**seven family slots**, with 14–18 possible investments depending on which
flagships it owns. Before all slots are filled the progression ceiling is 18,
the largest possible seven-family build. Selecting the seventh family fixes
the exact ceiling to the sum of those families' maximum ranks.

First earned costs remain 18/22/36/56/84 XP and subsequent costs remain 84.
Attribution, rewards, overflow behaviour and starter legality are preserved.
XP history stays intact when the final capacity is determined; unavailable
overflow and queue entries beyond that capacity close, while every valid
remaining upgrade or mutation entitlement stays claimable. Once all chosen
families are developed, MAX ends drafting and the same continuous Run continues.

Eligible rank upgrades have weight **2.15** and mutation offers **2.60**. New
families have weight 1.0 before five are owned, then decay by 0.55 per additional
family, with a 0.10 floor until the seventh slot is occupied. Once three families
are owned, one card always develops an eligible owned family when one exists.
Its UI slot is seeded and shuffled. Other cards can still invite combinations.
At seven families, all remaining cards develop those families.

The cap was introduced after study, not assumed. The initial soft-only design
passed early draft checks but exploratory natural late Runs still reached
eleven/twelve families as existing development exhausted. That failed the
intended coherent late-build identity. Synthetic comparisons also show the
same exhaustion problem at greater investment depth.

## Seeded policy comparison

`tests/test_roster_draft.gd` compares 256 seeds per policy/preference. These are
synthetic investment-choice models, not combat survival or human pacing tests.
The older enlarged policy uses new 1.0/development 1.2. Hard five/six/seven
comparisons isolate the cap using those older weights. The chosen policy combines
seven slots with the tested soft depth preference.

| Twelve investments | Mean families, random choices | Mean mutations, random | Mean families, prefer depth | Mean mutations, prefer depth |
|---|---:|---:|---:|---:|
| Enlarged pool, older weights | 8.05 | 0.41 | 6.33 | 1.09 |
| Soft depth only | 6.58 | 0.78 | 5.50 | 1.45 |
| Hard five, older weights | 5.00 | 1.45 | 5.00 | 1.52 |
| Hard six, older weights | 6.00 | 0.88 | 5.92 | 1.32 |
| Hard seven, older weights | 6.95 | 0.53 | 6.29 | 1.11 |
| **Chosen: seven plus soft depth** | **6.51** | **0.80** | **5.50** | **1.45** |

At eighteen requested investments, soft-only random-choice builds averaged
8.78 families (range seven–ten), with 1.81 mutations. The chosen policy finishes
at exactly seven families, average 2.14 mutations. Five slots made every random
sample finish at five and unnecessarily constrained hybrid room. Seven preserves
the intended early depth pattern while allowing more combinations and preventing
late all-family convergence.

The suite also executes 256 actual attributed-XP RunContext builds through
complete capped ownership, tests seeded twin Runs across different starters,
checks three/five/seven-family offer states, and exercises sixteen late seventh-
family choices after large pre-earned XP queues. It verifies no duplicate offers,
valid mutation branches, deterministic claims, exact final available capacity,
no empty pending-claim deadlock, preservation of XP history and restart reset.
Twelve additional full builds pass through the actual Main acquisition screens,
checking Battle ownership/ranks/mutations after every claim and preserving the
same player dictionary. Every one of the thirteen Rank II paths is installed in
live Battle, including support families. The final draft suite passes
**21,791 checks**. Compact policy evidence is
`tests/results/task002c5-draft-results.json`; detailed logs are outside Git.

The cap and stronger upgrade selection are deliberate build rules. They remain
subject to the human check of whether seven slots, upgrade cadence and late MAX
feel satisfying. No class locks, rarity, meta ownership or permanent power save
system were added.

## Deliberate natural Ghost execution

`tests/roster_route_bot.gd` uses ordinary steering to draw a route and pursue the
visible valid closure socket. It never edits RPM, ownership, enemies, losses or
proc state. `tests/diagnose_route_execution.gd` retains the real director, natural
earned drafts and continuous economy while measuring route speed, chronological
trace span and preview gaps.

This exposed a real preview failure in the first implementation. Twenty-eight
traces, emitted about once per 0.15 active seconds, retained only 4.05 seconds of
route even though their individual lifetime was 5.5 seconds. A natural Vane Run
had a valid 22.422-pixel preview gap at 148.56 speed, but emitting the required
paid closing trace evicted its oldest socket. The recalculated gap became 45.215,
outside the unchanged 38-pixel snap distance. The preview had promised a closure
the actual emission could not retain. Read-only instrumentation around the
production closure call reproduced the uninstrumented outcome and counters
exactly, then recorded this transition directly.

The bounded correction is **forty modern Ghost traces and six-second lifetime**;
the 72-global-trace cap, 224 candidate-point cap, eight-target cap, 70-pixel preview
distance, 38-pixel snap distance, area/perimeter checks and 3.5-second cooldown
stay intact. Legacy standalone Ghost keeps its original count/lifetime. The same
natural Vane seed 421, same 108-radius controller and same earned three-family
build now closes at that exact 122.15-second tick. It finishes with six real
closures and ten enclosed-enemy activations, without High Gear.

Before the larger buffer was applied, a deliberately tighter 85-radius route
with preview pursuit already produced eleven natural closures/thirteen enemy
activations for Vane and two closures/three enemy activations for Breaker, also
without High Gear. Those examples establish execution viability; the buffer
fix makes broader routes match their preview. Slow low-RPM Bastion samples did
not maintain the required trace speed and therefore did not close; no protection,
RPM injection or artificial proc was used to improve that outcome.

These targeted route samples supplement the main final natural matrix. They
are bot execution evidence rather than final human comfort or readability
acceptance. Compact provenance is in `tests/results/task002c5-route-results.json`.
