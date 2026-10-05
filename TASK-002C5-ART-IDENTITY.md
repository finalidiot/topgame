# Task 002C.5 — Power art identity addendum

**Historical V1 checkpoint, superseded by the human correction pass.** The human
review rejected several presentations and the internal A2/B11/C0 grades were
overgenerous. See `TASK-002C5-ART-CORRECTION-V2.md` for the current checkpoint.
This report and its videos remain evidence of the rejected V1 direction.

This addendum continues the existing `task-002c5-ability-roster` branch. It preserves the completed power mechanics, thirteen-family roster, draft progression, collection, and normal launch flow. It stops at a human-review checkpoint; do not merge to `main`.

## Audit and review outcome

The before audit found **A: 1 / B: 3 / C: 9**. Impact Wake was the quality reference. The nine C families shared small centred subjects, simple perimeter symbols, or generic event geometry that did not tell their mechanics clearly enough. Chain Impact also reused Wake's radial pressure sheet in a warm palette.

Before evidence is preserved outside Git at `C:\GPT GAME BUILDING\task-002c5-qa\art-addendum\before`: original native sources and exported assets, SHA256 snapshot inventory, native card/icon and grayscale matrices, original card animation poses, real gameplay clips and selected motion frames. The audit distinguishes authored asset quality from runtime behaviour; a static fixture cannot prove a paid gameplay proc.

The first revised native review uses 64px cards, independently drawn 16px icons, and 192×112 crops of actual 640×360 arena rendering. The 34 explicit fixture states passed **68 draw-isolation assertions**: rendering changed neither the player physics dictionary nor roster counters/cooldowns. These are presentation fixtures, not balance or natural-run evidence.

The final audit is **A: 2 / B: 11 / C: 0** after native card/icon review, the roster/grayscale matrices, and actual input-only gameplay motion review. A means flagship quality; B means individual, polished secondary presentation. These are agent review grades, not a substitute for the human checkpoint. Secondary effects intentionally remain smaller than Wake's major pressure event.

| Family | Before | Final assessment | Motion evidence |
| --- | --- | --- | --- |
| Impact Wake | A | A: accepted card preserved; independent icon; Rank II develops backed counter-pressure panels and retains readable physical contact. | Paid Rank II motion reviewed at 50ms intervals; pass |
| Redline | B | B: broken hot rotor/wake and coherent endings; Runaway frays after paid contact, Breakneck strikes and recoils. Rank icons remain close at 16px. | Redline, Runaway and Breakneck actual motion/grayscale pass |
| Iron Comet | C | B: wall-bank card and metal charge tell a committed physical launch; no wedge. Ordinary contact sparks partly dominate the final impact. | Real wall charge, launch/contact and grayscale pass |
| Dead Centre | B | B: wide bearing jaws carry a compact load at the floor; Bulwark meets an attacker, Counterweight compresses then releases in the actual direction. | Grounding, Bulwark and Counterweight paid motion/grayscale pass |
| Afterimage | B | A: environmental scar/crossing cards and icons correspond to the strong live path. Ghost's irregular enclosed route locks; Slipstream snaps at a real crossing. | Real paid Ghost closure/activation and Slipstream crossing/surge pass |
| Chain Impact | C | B: unequal receivers and sequential card relay correspond to brief sparse transmitted contact; secondary visual weight, no Wake ring. | Three real transmitted events in the six-second window; paid motion/grayscale pass |
| Clutch | C | B after the second composition pass: larger strained machine, asymmetric catch pawl and staggered Rank II stop. | Actual danger/catch contact and grayscale pass |
| High Gear | C | B after the second pass: larger forward subject and spaced wake lanes; Terminal discontinuities differ from retained Flow rails. | Moving-speed states, paid Terminal surge and grayscale pass |
| Orbit Drive | C | B after the second pass: sideways machine and compact floor hook; scuff settles on the floor after the top moves on. | Actual drift entry/scuff/follow-through and grayscale pass |
| Crash Guard | C | B: exposed contact-side piston visibly shortens, then clears. A discovered facing-vector mismatch was corrected and re-recorded. | Corrected real contact-side compression/ending and grayscale pass |
| Momentum Bank | C | B: large loaded spring cassette and brake shoe clearly store, extend and release; the cassette remains somewhat diagrammatic. | Real store/release timing and grayscale pass |
| Predator Line | C | B: unequal quarry/hunter composition and subtle repeated teeth follow one real rival; no HUD reticle. | Actual pursuit/contact and grayscale pass; expiry not shown in this six-second window |
| Crosscut | C | B: narrow lateral shear and unequal exits are distinct; ordinary contact stars dominate its first instant. | Actual paid shear/skid, clean ending and grayscale pass |

## What was replaced and what was retained

Active presentation now has artist-owned per-family masters instead of editing another shared roster sheet. Each family supplies its own card, icon and FX source. Its exported design and manifest select actual art IDs and existing semantic events. The first C candidates were not protected because they were new: Chain/Centre/Afterimage, Momentum/Predator and Clutch/High Gear/Orbit received further composition passes after native-size comparison showed undersized foreground subjects. The second card/grayscale review and the final actual-motion review have no remaining C family. The human identity checkpoint remains open.

The nine C families found were Iron Comet, Chain Impact, Clutch, High Gear, Orbit Drive, Crash Guard, Momentum Bank, Predator Line and Crosscut. Their active shared-sheet card/icon mappings and generic FX treatments are replaced by the corresponding family sources listed below. This replaces active mapping; old historical masters are preserved as evidence and fallback material rather than destructively overwritten. **No active major family remains C or is classified as temporary art.**

- **Momentum Bank:** a broad brake shoe holds an open loaded spring cassette. Coil pitch compresses as real charge rises; the stored state selects charge poses, rather than automatically animating a fake fill. Release extends along the actual movement vector. Rank II adds physical structure.
- **Predator Line:** a larger foreground hunter follows a smaller quarry. A serrated pressure comb repeats toward that one real rival and reflects the actual hunt stage. It is a pursuit illustration and contact response, not an arbitrary target symbol or radial reticle.
- **Iron Comet:** the physical rotor is compressed at a wall bank, then committed to a separated directional launch/contact sequence. The old triangle is not an active effect in this addendum. Wall, machine and aftermath carry the story.
- **Chain Impact:** three unequal illustrated receivers pass contact in sequence. Runtime snapshots eligible real receiver positions for short sparse links and local compressed teeth. It no longer borrows Wake's circular blast.
- **Dead Centre:** substantial floor-bearing jaws approach and support the load. Bulwark and Counterweight develop planted impact and stored-force stories. Counterweight release has eight authored heading variants; the isometric sprite is never rotated.
- **Afterimage:** the leading machine moves across environmental scars; its Rank II illustration develops aged crossings. Ghost encloses a physical rival within an irregular latched route. Gameplay preserves the actual recorded route, while new cels accent endpoints/locks. Slipstream accents a real crossing and uses eight authored directional snap variants.
- **Impact Wake:** Rank I keeps the accepted five editable card layers and all six original authored poses. Each pose is held for two half-duration keys, preserving its pixels and total rhythm in the twelve-key convention. The original 128px paid pressure runtime remains; Rank II adds a structural response rather than a palette copy.

Redline's strong fragmented runtime language and Afterimage's real bounded route geometry are developed or retained deliberately. Retaining a successful native master is part of the audit, not a claim that everything old needs replacement.

Exact retained active references are:

- Wake I: `assets/source-art/power_cards_002b1.aseprite` tag `impact_wake`, preserved layer-by-layer in the new card master. Runtime `assets/source-art/power_fx_002b.aseprite` tags `pressure` and `contact_arc` export to `assets/powers/effects.png` with `assets/powers/manifest.json`. There is deliberately no new Rank I `wake` FX tag; identity routing falls through to these accepted paid-pressure cels.
- Redline's live fragmented aura: `assets/source-art/redline_fx_002c4.aseprite` → `assets/powers/signature_redline.png`, tags `rank1_active`, `rank2_active`, `runaway_low`, `runaway_high` and `breakneck_charge`. `breakneck_hit` / `breakneck_recovery` remain fallback references while the new family master supplies paid strike/recoil accents. The existing aura follows actual velocity/heat state, rather than a new clean ring.
- Afterimage's true recorded-path node treatment: `assets/source-art/afterimage_fx_002c4.aseprite` → `assets/powers/signature_afterimage.png`, tags `rank1_trace`, `rank2_trace`, `ghost_closure`, `ghost_active` and `slipstream_cross`. The connected route, endpoint bridge and activated irregular path remain live geometry in `scripts/power_visuals.gd` / `scripts/signature_visuals.gd`; new family cels add local locks and directional crossing accents, not a replacement pre-drawn circuit.

## Visual grammar

| Power family | Primary silhouette | Motion language | Where the effect lives | Persistence | Main palette | Unique identifying feature |
| --- | --- | --- | --- | --- | --- | --- |
| Impact Wake | Central physical hit with outward pressure teeth | Contact flash, spreading fronts, staggered counter-pressure | Actual heavy contact near the floor | Short paid contact event | Cyan pressure, steel, sparse amber tips | Physical impact and a distinct spreading pressure structure |
| Redline | Off-centre rotor and unequal broken fragment banks | Ignition, heat stutter, increasingly torn wake; loaded strike/recoil | Rotor edges and actual velocity wake | Actual active/overcap/heat state plus finite events | Oxide, orange, hot pale flashes, cold steel | Asymmetric instability; Runaway frays while Breakneck commits and recoils |
| Iron Comet | Compressed whole rotor beside a wall bank | Squeeze, separated launch positions, contact, scrape | Wall, rebound vector, target contact | Armed rebound lifetime and bounded reactions | Iron, silver, brass, short white/gold keys | The machine and wall tell the slingshot story; no wedge |
| Dead Centre | Heavy compact load on inward bearing jaws | Approach, settle, take a strike, compress/release stored force | Ground contact and low braces | Real charge-stage lock plus impact/release events | Slate, steel, restrained cyan, stored-force amber | Broad jaws visibly carry weight; mutations change the load mechanism |
| Afterimage | Leading machine with scarred routes; latched irregular enclosure | Record route, age crossing, local snap, endpoint closure/path lock | Recorded routes, crossings and endpoints | Bounded route history and finite local reactions | Cyan/ice scars; green route teeth for Ghost | The actual route becomes the structure; Ghost closure differs from Slipstream surge |
| Chain Impact | Unequal receivers connected by a diagonal relay | One contact lights a tooth, then the next receiver reacts | Actual elimination origin and eligible receiver links | Discrete transmitted event | Steel, copper stress, pale amber contact | Sequential physical transmission rather than another radial blast |
| Clutch | Strained leaning machine and asymmetric stepped pawl | Slips/misses, catch, brief stutter, restrained settlement | Low bearing side and contact scrape | Actual danger window and successful-contact catch | Dull steel/brass, small gold tips, oxide strain | A pawl catches useful spin without a recovery ring |
| High Gear | Forward machine and spaced wake lanes; open Flow rails | Intervals stretch; Terminal breaks spacing; Flow retains a smooth bend | Behind the rotor along actual velocity | Actual moving-speed state and finite surge | Steel, ice/blue, muted mint rails, sparse brass | Discontinuous raw speed versus continuous retained flow |
| Orbit Drive | Sideways machine and concave hooked floor skid | Enter turn, carve outside hook, throw grit, release arc | Floor/contact outside the turn | Actual brake-turn drift with short scuff settlement | Worn steel, muted teal, brass grit | Compact floor hook instead of High Gear's open rotor wake |
| Crash Guard | Telescoping twin rods with broad end-stop | Compression, visible shortening, damped rebound | Incoming contact side of the real top | Contact response, no automatically orbiting shield | Gray steel, pale mint, brass seals | Physical piston length changes instead of aura expansion |
| Momentum Bank | Open rear spring cassette and brake shoe | Compression, held load, abrupt directed extension | Rear braking/contact side and actual release vector | Real stored-charge poses plus load/release events | Brass, graphite, ivory, steel mount | Coil pitch communicates stored force |
| Predator Line | Unequal quarry/hunter chase and serrated comb | Quarry leads, hunter closes, repeated pressure teeth | Actual hunter-to-rival axis | Real target chase and brief accepted-contact pressure | Oxidized iron, vermilion hunter, cool steel quarry | Pressure repeats toward exactly one physical rival |
| Crosscut | Offset glancing bodies and stepped shear ribbon | Narrow lateral contact, unequal divergent exits | Glancing contact and actual displacement vector | Brief paid shear and sparse scar | Sea green, bone, desaturated steel | Asymmetric slash and split skid, without a symmetric X or ring |

## Native source and runtime paths

All rows below use `assets/source-art/power_identity_002c5/` as the source directory. The three listed files are real editable normal-RGBA Aseprite masters with named layers and meaningful tags. All thirteen families are covered; mutations live in the same family master under their actual art IDs.

| Family | Card master | Independent icon master | FX master |
| --- | --- | --- | --- |
| Impact Wake | `impact_wake_cards.aseprite` | `impact_wake_icons.aseprite` | `impact_wake_fx.aseprite` |
| Redline | `redline_cards.aseprite` | `redline_icons.aseprite` | `redline_fx.aseprite` |
| Iron Comet | `iron_comet_cards.aseprite` | `iron_comet_icons.aseprite` | `iron_comet_fx.aseprite` |
| Dead Centre | `dead_centre_cards.aseprite` | `dead_centre_icons.aseprite` | `dead_centre_fx.aseprite` |
| Afterimage | `afterimage_cards.aseprite` | `afterimage_icons.aseprite` | `afterimage_fx.aseprite` |
| Chain Impact | `chain_impact_cards.aseprite` | `chain_impact_icons.aseprite` | `chain_impact_fx.aseprite` |
| Clutch | `clutch_cards.aseprite` | `clutch_icons.aseprite` | `clutch_fx.aseprite` |
| High Gear | `high_gear_cards.aseprite` | `high_gear_icons.aseprite` | `high_gear_fx.aseprite` |
| Orbit Drive | `orbit_drive_cards.aseprite` | `orbit_drive_icons.aseprite` | `orbit_drive_fx.aseprite` |
| Crash Guard | `crash_guard_cards.aseprite` | `crash_guard_icons.aseprite` | `crash_guard_fx.aseprite` |
| Momentum Bank | `momentum_bank_cards.aseprite` | `momentum_bank_icons.aseprite` | `momentum_bank_fx.aseprite` |
| Predator Line | `predator_line_cards.aseprite` | `predator_line_icons.aseprite` | `predator_line_fx.aseprite` |
| Crosscut | `crosscut_cards.aseprite` | `crosscut_icons.aseprite` | `crosscut_fx.aseprite` |

Cards use 64×64 cells and twelve keyed frames per state with a documented (32,32) pivot. Icons use separately authored 16×16 silhouettes, one frame per state, pivot (8,8). FX use 96×80 cells and eight keyed frames per tag, pivot (48,48). Their floor plane remains upright and isometric; native heading tags select directional placements without sprite rotation/resampling.

For each family the runtime files are `assets/powers/identity/<family>_cards.png`, `<family>_icons.png`, `<family>_fx.png`, `<family>_manifest.json`, and `<family>_design.json`. `assets/powers/identity_manifest.json` collects the family metadata. `scripts/power_identity.gd` reads those metadata, authored frame timing, actual heading and existing live state. The catalogue carries art metadata; cards/icons/runtime come from related mechanical grammar at their own intended scale.

Historical sources such as `power_cards_002b1.aseprite`, `power_icons_002b.aseprite`, `power_fx_002b.aseprite`, `escalation_*_002c.aseprite`, `roster_*_002c5.aseprite` and the C.4 signature masters remain in the repository. Their presence does not mean every legacy tag is still selected. Wake's accepted pressure and strong live-route/fallback references are deliberately retained; the active mapping is documented in the identity manifests. Legacy Second Wind remains historical compatibility material and is not a normal draft family.

## Editing and export workflow

1. Open the family `.aseprite` master in native Aseprite. Edit its named layers and meaningful state/event tags; preserve the cell size, normal blend modes, pivots and tag ranges. Compose the illustration at 64px, and inspect its single native-size card beside Impact Wake before judging a giant atlas.
2. Edit the independent icon master at 16px. Preserve negative space and mechanic-specific recognition; do not shrink a card or FX sheet into an icon.
3. Edit eight-key FX poses at the fixed contact pivot. Anticipation, contact, reaction and follow-through use deliberate timing. Keep moving-direction variants authored upright; active charge stages must describe real charge rather than auto-fill it.
4. Update the family design metadata only where tags, static-key selection or semantic routing actually change. Runtime metadata must read existing state and avoid advancing mechanics, timers or RNG.
5. Export using `C:\Python313\python.exe tools\export_power_identity.py --family <family> --aseprite "F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe"`. The exporter reads saved masters, obtains native Aseprite PNGs, verifies visible RGBA/alpha parity, and updates family and aggregate manifests. Nearest-neighbour sampling remains enabled.
6. Re-run presentation checks and native gameplay captures. Compare card → icon → actual gameplay, grayscale silhouettes, rank development and muted entry/exit/contact motion. A parity pass confirms source/export agreement, not artistic quality.

`tools/author_identity_foundation.py`, `tools/author_identity_motion.py` and `tools/author_identity_core.py` are explicit construction recipes for distinct pixel-cluster compositions. They are not the export authority. Saved Aseprite masters are authoritative after artist edits; regenerating a recipe deliberately can overwrite those edits and is not part of ordinary export.

## Review artifacts, validation and limits

All review artifacts below are under `C:\GPT GAME BUILDING\task-002c5-qa\art-addendum`:

- `002c5_power_visual_matrix.png` and `002c5_power_visual_matrix_grayscale.png`: all thirteen core families, native card/icon and representative Rank I/II/mutation arena states.
- `002c5_power_before_after.png` and `002c5_power_before_after_grayscale.png`: direct comparison of the redone presentations, including Momentum Bank, Predator Line and Iron Comet.
- `002c5_power_art_showcase.mp4`: **39 seconds**, thirteen card → gameplay segments, a review artifact with a labelled footer rather than a trailer.
- `002c5_power_blind_review.mp4`: **23.4 seconds**, corresponding gameplay with names, cards and footer removed for the human identity gate.
- `motion\<selection>.avi` and matching JSON: **21 unique six-second actual gameplay windows** covering all thirteen families and eight mutations. The input-only opening-build contract, actual start time, proc counts and state samples are retained with each recording.
- `showcase-provenance.json` and `motion-review-index.json`: selected source windows, card IDs and observed event counts. The full input-only diagnostics remain separate from synthetic static/stress fixtures.
- `foundation-review` and `independent-motion-review`: native card/icon comparisons, dense 50–100ms paid-event sequences, grayscale motion inspection and exact proof paths. The second reviewer made no source or asset edits.

The source inventory contains **39 native masters / 34 card-icon states / 408 card keys / 34 independent icons / 2,840 FX keys**. Exports were checked against native Aseprite visible RGBA/alpha, not reconstructed from screenshots. `foundation-review\foundation-native-source-proof.json` additionally verifies that Wake I's mapped twelve keys and total duration match its six accepted original poses exactly.

Authoring review evidence is under `C:\GPT GAME BUILDING\task-002c5-qa\art-addendum\foundation-review`. It includes full twelve-key card poses, eight-key FX poses, native 64px/16px plus 4× comparisons beside accepted Wake, grayscale comparisons and three native card/icon/gameplay fixture pages. `art-addendum\matrix` holds explicit 34-state native fixtures. These materials remain distinguishable from real paid-proc gameplay clips.

The first underfilled Clutch, High Gear and Orbit Drive card-size candidates were revised and passed the second native/grayscale comparison and actual motion review as B. A fresh reviewer independently assessed Redline/mutations, Iron Comet, Momentum Bank, Predator Line, Crash Guard and Crosscut. The Crash Guard audit found a real correspondence bug: the incoming-force vector pointed toward the owner, while the authored piston expected a direction facing the rival. Only the presentation vector was inverted; collision normals and power mechanics stayed unchanged. The corrected dense recording faces the right-hand incoming rival and the hardware clears by about clip 1.133s. Its prior bad-vector frames are retained as before evidence.

No remaining active art is labelled temporary. B-grade limits are explicit: Predator's tracking is subtle, its six-second clip ends while hunt is still live so expiry is not demonstrated there; Iron Comet/Crosscut share ordinary contact sparks in their first impact; Momentum's cassette is somewhat diagrammatic; Redline's small rank icons remain close. These are refinement opportunities for human review, not hidden C assets. No new particle budget or screen-filling effect was added to solve them.

Wake II's six-second real paid-proc recording has been inspected in a dense 50ms chronological sequence at logical native 640×360. The contact enters locally, backed panels spread, then erosion removes the pressure while the physical tops remain readable. This passes the Wake motion gate; `foundation-review\wake-paid-event-50ms-sequence.png` and its grayscale companion retain the inspection evidence. The source master is frozen after this review.

The natural steering diagnostics cover thirteen single-family opening builds and eight mutation builds. Their authenticity contract grants only the explicit opening build; after opening, steering, Burst and brake operate the real continuous director, AI, contacts and RPM accounting. These are controlled builds, not claims that their powers were naturally earned drafts. The initial 42-second Slipstream mutation sample recorded no paid crossing and was rejected as its snap proof. A revised steering window now records an actual crossing at clip 1.55s, speed 326.77, with a local snap and immediate movement surge. Ghost's six-second window records two closures and two activations. Continuous High Gear/Flow states do not require an event counter to be visible.

`art-performance.json` / `art-performance.png` retain a separate explicit held stress fixture: twelve small bodies, seven owned families and the existing **32-FX cap**. The final recording on the GTX 1660 / i3-10105F system at native 640×360 measured 419 samples: median/p95 wall frame **5.772/7.093ms**, draw submission **1.527/2.201ms**, simulation **3.364/4.286ms**, and **54 draw calls**. The pre-addendum recording measured wall 4.808/5.649ms, draw 0.742/0.965ms and 47 draw calls; the new authored cels add rendering cost while retaining the same bounds. Draw submission excludes asynchronous GPU time; the wall frame includes the harness. This is renderer stress evidence, not natural survival or a promise for every GPU.

The complete checkpoint passes **34 regression suites / 42,142 counted checks / zero failures**, including a fresh two-seed natural Run replay that reproduces exact RPM curves, events and accounting. The identity contract contributes 4,405 checks, including draw isolation, eight contact directions and actual Chain recipients. All 34 native arena fixtures pass 68 state-isolation checks. `tests/results/art_identity_002c5/` preserves compact validation, source retention and review evidence. The source proof retains 27 gameplay/collection/historical-source files byte-for-byte after canonical line endings; the sole PowerRuntime exception forwards existing Chain receiver IDs into visual metadata without changing physical requests or event ordering. Collection persistence and carried-velocity drift remain intact.

The final exported Windows executable passes the first starter selection, confirmation, permanent ownership, Workshop, opening draft and continuous-threat flow checks. Those checks use an isolated save; the real user's collection file hash matches its pre-test hash. The executable window identifies **002C.5 Art Review + Starter Collection** so this checkpoint can be distinguished from an older build. These automated checks establish delivery and regression correctness; the final visual-quality and drift-feel decisions remain the human review gate.

## Human review questions

1. Do the newer powers look as polished as Impact Wake?
2. Can you distinguish Momentum Bank from Predator Line instantly?
3. Does each flagship power have its own shape/motion language?
4. Do the cards look like actual power illustrations rather than enlarged HUD icons?
5. Do cards, HUD icons and gameplay effects feel related?
6. Do Rank II and mutation states visibly develop?
7. Are powers still distinguishable in grayscale?
8. Does the roster look deliberately authored rather than procedurally generated from one template?
9. Are effects distinct without turning late combat into visual noise?
10. Which power still looks most like placeholder art?

The final gate is the full roster together and short muted gameplay without the HUD: a familiar player should identify most important families from their shape, motion, placement and timing. Any remaining major Tier C family requires another art pass. The finished Task 002C.5 checkpoint remains on its current branch for human review and is not merged to `main`.
