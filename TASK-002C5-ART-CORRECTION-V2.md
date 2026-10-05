# Task 002C.5 — Final art correction V2

This is a correction to the rejected art checkpoint `d0d37e505f6d6582486f7e039b87643d084457c1`, on the existing `task-002c5-ability-roster` branch. The power mechanics, thirteen-family roster, collection and launch flow remain the accepted implementation scope. Do not merge to `main` before the human art checkpoint.

**The previous report's A2 / B11 / C0 acceptance is superseded.** The human review rejected several new presentations as pseudo-mechanical objects. Distinct shapes, editable native sources, source/export agreement and bounded rendering did not establish that a player could understand the power. The earlier agent grades were too generous. V2 must show spinning tops doing the relevant action, rather than attach a differently shaped machine or diagram to each family.

This report records the completed historical audit, native/static review and actual-motion review. The correction expanded to ten families: Crosscut's artificial blade and Centre's held clamp/platform also required replacement. Three families retain their existing sources after review. The first motion review also requested a further High Gear trail correction and a more readable Bank held state. All eight affected windows have since been re-recorded and independently inspected in colour and grayscale at native size. Human acceptance remains pending; no new A/B grades are assigned.

## Preserved rejected checkpoint

The exact Git checkpoint was archived before replacement work under:

`C:\GPT GAME BUILDING\task-002c5-qa\art-correction-v2\before`

- `d0d37e5-source-assets.zip`: exact tracked source/assets from the rejected commit.
- `snapshot`: all power PNGs/manifests, all historical power sources and all 39 per-family native masters, relevant renderer/catalogue modules, capture/export/authoring tools and the superseded report.
- `snapshot-manifest.json`: SHA256 inventory of 228 preserved files, exact commit and archive checksum.
- `review-media`: the rejected matrix, grayscale matrix, before/after images, showcase, blind movie and their provenance/index records.

The earlier `d882923` historical audit remains under `C:\GPT GAME BUILDING\task-002c5-qa\art-addendum\before`. Neither snapshot is overwritten by V2. The synced ChatGPT project `sources/` mirror is read-only and was not edited.

## Historical versions actually inspected

The audit extracted actual Git `.aseprite` sources and PNG/manifests. Cards/icons were exported by native Aseprite and reviewed at their intended 64px/16px size, with separate nearest-neighbour enlargements. FX source cels and actual renderer routing were inspected separately. A source-cel sheet is labelled as source art; it is not presented as historical gameplay footage.

| Revision | What was inspected | Finding |
| --- | --- | --- |
| `8fa737b` — Task 002B | Original independent icons, 128px effect source and renderer | No illustrated 64px card existed yet. Chain used warm event-local pressure plus the initial contact core. |
| `bdcc24e` — Task 002B.1 | Six-pose illustrated cards, revised compact icons and unchanged effect source/routing | Chain's three recognizable rotors and triangular contact relay are the strongest actual historical card/icon reference. Wake's accepted card remains the quality reference. |
| `3267ef3` — Task 002C | Rank II/mutation cards/icons and escalation FX | Added Centre and developed Redline/Afterimage states. The original Chain card/icon remained intact. |
| `0c6225f` — accepted Task 002C.4 main | Signature masters and runtime routing, including fragmented Redline and true Afterimage paths | Successful sustained combat language is preserved where it tells actual state or geometry. Chain card/icon still came from 002B.1. |
| `32bb56e` — initial Task 002C.5 | Thirteen-family roster sheets and native new-family states | New families had generic repeated rotor/glyph framing. These are historical comparison material, not a blanket restoration target. |
| `d882923` — collection restoration | Power asset tree and mappings | Its power asset tree is identical to `32bb56e`; collection restoration did not create a new power-art version. |
| `d0d37e5` — rejected identity addendum | All thirteen independent family card/icon/FX sources, mappings and preserved runtime evidence | Several replacements traded a recognizable top/action for an attached mechanism, vehicle-like silhouette or schematic. Its prior artistic acceptance is withdrawn. |

The audit produced native exports for **33 unique card/icon masters and 19 FX masters**. Exact commit IDs, source hashes, source tags and exported paths are recorded in `historical\historical-native-inventory.json` and `historical\runtime-native-inventory.json`.

## Chain restoration choice

The chosen Rank I card is the actual `bdcc24e` source:

`assets/source-art/power_cards_002b1.aseprite`, tag `chain_impact`, source keys **30–35**. Five editable layers depict three real rotors along a rising/falling triangular ricochet route. The bright stepped contact response moves between the three receivers. Its six durations are **110 / 90 / 75 / 75 / 100 / 170ms**, total **620ms**. The twelve-key convention may hold each original pose twice with half-duration keys; that must preserve the original pixels, layers, order and rhythm. Rank II should develop the contact response while preserving this readable composition.

The chosen Rank I icon is the actual `bdcc24e` source `assets/source-art/power_icons_002b.aseprite`, tag `chain_impact`, key **5**: a compact triangular relay. It is independently authored at 16px. The rejected diagonal ladder/cassette silhouette is not the restoration reference.

The historical gameplay source is `assets/source-art/power_fx_002b.aseprite`, tag **`pressure` keys 6–13**, with **`contact_arc` keys 0–5** for the early contact core. The actual 002B/002B.1 renderer uses warm tint `Color(3.2, 1.25, 0.60)` for a finite paid event at its source. There is no historical Chain-specific FX tag. Restoring a supposed `chain_impact` FX filename would misidentify this evidence.

The original source burst improves paid-event visibility, but by itself shares Wake's radial source. The V2 direction therefore keeps the finite local burst and shows sequential contact reactions at the **actual eligible receivers**, using the existing presentation-only receiver provenance. The source and at most two recipient accents have a **three-native-cel ceiling**, explaining a causal chain without a persistent network or invented target. The actual six-second window shows the source burst followed by receiver reactions; the source atlas alone would not prove that progression. `validation/chain-restoration-proof.json` verifies exact Rank I card/icon pixels, paired original holds and each pose/total duration against `bdcc24e`.

Native comparison evidence:

- `historical\roster-historical-native-page-2.png` and its grayscale companion: original Chain versus the rejected native card/icon, beside Afterimage, Clutch and High Gear.
- `chain-history\chain-history-native.png`: the detailed chronological native Chain comparison.
- `historical\chain-fx-historical-native.png` and grayscale companion: actual old pressure/contact keys versus rejected receiver teeth.
- `historical\chain-fx-history-proof.json`: exact sources, tags and key ranges.

## Family audit and correction direction

All thirteen families were checked at native card64/icon16 scale, in grayscale, and in the actual input-only motion windows. Ten required the focused correction. Wake, Redline and Afterimage retain their sources; their inclusion in the final native/grayscale roster review does not imply human acceptance.

| Family | Rejected-checkpoint finding | V2 choice and evidence needed |
| --- | --- | --- |
| Impact Wake | Accepted Rank I illustration is preserved. Paid pressure is an impact treatment rather than independent hardware. | Retain accepted card/pressure reference and developed Rank II; check the final roster without assuming the old agent grade. |
| Redline | Strong fragmented runtime follows real heat, overcap and motion. The newer card is less dominant than the historical large rotor illustration. | Retain after review; card readability remains a human checkpoint question, and the successful torn-rotor runtime is preserved. |
| Iron Comet | Large wall hardware above a small wing-like top does not clearly show a committed physical attack. | Correct: a recognizable top, wall contact, charged commitment and an attack/contact aftermath. No wedge or vehicle story. |
| Dead Centre | First motion review exposed a held four-foot clamp/platform, including Bulwark/Counterweight; it still read as hardware. Historical complete cards retained feet or spring/box treatment too. | Correct: actual accepted Bastion/Breaker bodies, Bit/floor load, compression and returned contact; remove every leg, clamp and side cylinder. Refreshed native/grayscale motion shows physical top contact with small unequal floor seams and no held platform. Load contrast remains restrained. |
| Afterimage | Cards use top + scar/crossing/enclosure; gameplay uses real bounded routes and paid endpoints. | Retain after review; preserve true geometry and distinguish Ghost closure from Slipstream crossing/surge. |
| Chain Impact | Diagonal ladder-like bodies lose the earlier three-top relay silhouette; isolated small teeth understate the paid event. | Correct: restore the strongest actual historical card/icon and show finite source → real receiver reactions. |
| Clutch | Attached pawl/blocks explain a mechanism more readily than a struggling top regaining useful spin. | Correct: low-spin struggle, meaningful-contact catch and restrained recovery of the same top. |
| High Gear | Wing/rail composition can read as a vehicle; equal open lanes alone do not tell the top's speed. | Correct: unmistakable spinning top, forward movement and speed spacing. Develop Terminal/Flow within that top movement story. |
| Orbit Drive | A hardware hook beside a similar winged subject does not clearly depict curved movement. | Correct: a top carving a deliberate curve, outside floor contact and released arc/scuff. |
| Crash Guard | Literal piston attachment reads as an added machine. The prior facing fix did not solve this artistic mismatch. | Correct: a top taking a heavy hit, resisting displacement and continuing to spin. Keep the response at the real impact. |
| Momentum Bank | Literal spring cassette communicates a box/device more readily than stored movement; the first correction hid its low-charge hold under the top. | Correct: braking/storing motion, an exposed connected held fold, then a chosen directional release by the same top. Final actual footage shows the low-charge fold in colour/grayscale and its replacement on release. |
| Predator Line | Pursuit card and repeated teeth remain schematic rather than clearly showing one hunter closing on one rival. | Correct: recognizable hunter/quarry, narrowing pursuit and accepted contact toward exactly one real rival. |
| Crosscut | The artificial blade was an unnecessary separate object even though its event was finite. | Correct: offset actual tops, glancing contact, divergent displacement and brief narrow shear/scar. The first revised motion window has no artificial blade. |

Crosscut became the ninth correction during integration review; the actual Centre motion made it the tenth. Its historical native comparisons are retained in `historical/centre-card-icon-history-native.png`, `centre-fx-history-native.png` and their grayscale companions. A whole historical Centre restoration would preserve hardware grammar, so the stronger rotor anatomy informs the new physical-body correction without restoring its old props. This is not an artistic pass for the retained three or automatic acceptance of the revised ten.

## Runtime location, persistence and motion gate

The renderer must read existing state and presentation payloads. It must not alter collision responses, RPM, charge, timers, target selection, physics positions, RNG or draft progression. A mechanical regression pass and a native parity pass remain necessary checks; neither is an art acceptance test.

| Corrected family | Where it lives | How long it lives | Motion that must be visible |
| --- | --- | --- | --- |
| Chain Impact | Paid elimination/contact source and actual eligible receiver contacts | One finite transmitted event | Source reaction, transmitted receiver reactions, clean removal |
| Dead Centre | Actual top, Bit contact and floor beneath its real anchored location | Actual charge/load stage and finite contact/release | Settle into load; Bulwark receives the strike; Counterweight compresses and returns contact; no held platform |
| Clutch | The struggling top and its low contact/rotation response | Actual low-spin danger and bounded successful-contact recovery | Struggle → catch → useful continued spin; no recovery ring or spare top |
| High Gear | The moving top and its real velocity wake | Actual moving-speed state and finite surge | Fast entry/spacing; Terminal acceleration versus Flow retention; clean slowdown |
| Orbit Drive | Outside contact of the actual turning top and floor scuff | Actual brake-turn drift plus bounded floor settlement | Curved movement → grit/scuff → released arc; do not orbit a machine around the top |
| Crash Guard | Actual incoming contact and the struck top | Finite heavy-hit response and existing brief guarded state | Accepted impact → resist/compress → continued spin; no automatically circling shield |
| Momentum Bank | Braking top, held motion cue and actual release vector | Existing stored charge; finite storage/release reactions | Brake/store → hold → chosen release; stored stage reflects real charge |
| Predator Line | Hunter, one live rival and their real chase axis | Existing target pressure; bounded accepted-contact reaction | Close the gap → pressure/contact → switch/disengage/expiry clears it |
| Iron Comet | Wall contact, charged top and real committed attack/contact | Existing rebound-charge lifetime and finite reactions | Wall charge → committed movement/strike → aftermath/expiry; no permanent flight object |
| Crosscut | Real glancing contact and the two separating tops | One finite narrow shear/scar | Offset approach → glancing impact → diverging bodies; no separate blade |

Each must be watched without cards, text or HUD explanation at logical native 640×360. Colour and grayscale inspection must cover entry, reaction and follow-through, with removal where the recorded state genuinely ends. A six-second window that ends while a state is active cannot prove its expiry; a separate genuine ending would be needed to establish that claim. Synthetic static fixtures are labelled as fixtures, not natural gameplay or paid-proc proof.

## Native source workflow

Family masters remain under `assets/source-art/power_identity_002c5/`:

`<family>_cards.aseprite`, `<family>_icons.aseprite`, `<family>_fx.aseprite`.

Cards are independently composed 64×64 illustrations with twelve timed keys per state, icons are separately drawn 16×16 silhouettes, and FX are upright 96×80 native keys with authored direction tags where needed. Named editable layers, tags and fixed pivots remain required. Historical Chain restoration is performed from actual original native cels/layers, not from a screenshot or enlarged export.

Runtime exports and routing metadata remain under `assets/powers/identity/`, with aggregate `assets/powers/identity_manifest.json`. Export saved artist-edited masters through `tools/export_power_identity.py` using native Aseprite; inspect source/export agreement and nearest filtering. Construction recipes are not the export authority and should not overwrite subsequent artist edits.

The actual source/export diff contains **29 changed native masters and 29 changed PNG exports across ten families**; the total family-master inventory remains 39. Orbit Drive's FX source and PNG are byte-unchanged from `d0d37e5`: the existing floor arc/grit already serves the corrected actual-top curve story; its cards/icons changed. Counts come from actual Git paths and SHA256 comparison, not three planned files per family. `validation/modified-art-source-inventory.json` records the exact path set and hashes, refreshed after the final art freeze.

The changed family stems are `chain_impact`, `clutch`, `crash_guard`, `crosscut`, `dead_centre`, `high_gear`, `iron_comet`, `momentum_bank`, `orbit_drive` and `predator_line`. Each has changed `_cards.aseprite` and `_icons.aseprite` masters; all except `orbit_drive` also have a changed `_fx.aseprite`. Their matching `_cards.png`, `_icons.png` and `_fx.png` exports are in `assets/powers/identity/`. Impact Wake, Redline and Afterimage per-family masters/PNGs are retained; historical source masters are also retained. Routing/manifests and the review pipeline are separately recorded in the Git diff rather than counted as native art.

The new Centre construction recipe is `tools/author_identity_centre.py`; historical masters remain untouched. This audit/report author makes no asset, catalogue, renderer or gameplay edits. Correction artists and the integration owner produce the V2 replacements and their captures.

## Review evidence and final status

Completed audit evidence is under `C:\GPT GAME BUILDING\task-002c5-qa\art-correction-v2`:

- `before`: the immutable rejected checkpoint and checksum inventory.
- `historical\roster-historical-native-page-{1..4}.png` and `roster-historical-gray-page-{1..4}.png`: actual native card/icon comparison across 002B.1, 002C, initial C5 and rejected V1, with source/tag/key provenance.
- `historical\untouched-mutations-historical-native.png` and grayscale companion: actual Redline, Centre and Afterimage mutation comparisons.
- `historical\rejected-runtime-native-page-{1..4}.png` and grayscale companions: rejected native FX key samples, explicitly labelled source cels rather than gameplay.
- `historical\historical-native-inventory.json`, `runtime-native-inventory.json`, `roster-history-card-icon-proof.json` and `runtime-source-sample-proof.json`: exact audit provenance.

The first revised full matrix and grayscale matrix were inspected at native size using separate unscaled page crops. They used explicit posed fixtures. All 34 posed states passed 68 draw-isolation checks; those assertions establish presentation isolation, not actual-motion or artistic acceptance. Initial V2 actual six-second AVI/JSON windows exist for all 21 selections; independent chronological native/grayscale sequences are under `independent-motion-review`, with timing/state provenance in `dense-motion-proof.json`. These first sequences identified Centre's held platform, High Gear/Terminal's opaque rack-shaped trail and Bank's weak held cue. The first independent sheets are preserved in `independent-motion-review/first-review-preserved`; changed footage replaces them for final review.

The refreshed High Gear, Terminal Velocity, Flow State, Iron Comet, Dead Centre, Bulwark, Counterweight and Momentum Bank recordings were independently inspected in colour and grayscale at logical native size. `validation/refreshed-eight-independent-motion-review.json` records exact AVI hashes and sampled live states/times. Gear/Terminal now leave separated fading top fragments rather than an opaque rectangular rack. Flow retains a thin curved wake. Comet's release/contact at clip 1.267s reads through the real bodies, and its charged ghost bulk is absent by approximately 1.5s. Centre and both branches no longer hold legs, a platform or a cylinder; the actual top receives contact and Counterweight moves out of its settled position on release. The Bit/floor-load cue is modest in grayscale. Bank's positive low-charge fold is exposed beside the actual top at clip 1.017s / real 2.317s, including in grayscale. Its chosen release at clip 1.417s replaces the held fold with a movement wake, which is absent by approximately 1.717s. `validation/bank-final-held/bank-held-through-release.png` records this chronological genuine store/hold/release sample. These observations do not assert later expiries that a window does not show.

The final actual-motion observations are:

| Family | Observed action and practical limit |
| --- | --- |
| Impact Wake | Finite source pressure follows actual contact and clears; Rank I preserves accepted pressure art. It is an impact treatment, not held hardware. |
| Redline | Fragmented heat follows the moving body; Runaway fray and Breakneck's committed contact/recoil remain distinct. Sustained heat at a cut is not expiry evidence. |
| Iron Comet | Wall charge, short body compression and committed real-top contact occur in sequence. The revised charged trail no longer supplies a dark replacement body. |
| Dead Centre | Real round body settles and receives contact over small floor seams. Bulwark holds against the rival; Counterweight breaks settlement and moves on return. The floor-load accent is quiet in grayscale. |
| Afterimage | Real route scars, paid Ghost endpoints/closure and Slipstream crossing/surge remain geometrically tied to gameplay. Their routes persist by the existing mechanics. |
| Chain Impact | Warm local source burst is followed by actual receiver contact accents; no arbitrary network or spare illustrated machines. Rank I card/icon exactly restore the stronger historical source. |
| Clutch | The low-spin top catches contact and settles into continued spin. The red rival wind-up reticle in its clip is the existing enemy telegraph, not Clutch art. |
| High Gear | Separated fading memories follow actual fast movement; Terminal adds acceleration and Flow retains a curved wake. The opaque rack was removed. The moving-state window does not establish slowdown expiry. |
| Orbit Drive | A continuous actual curved drift from real 13.7167–16.3167s leaves outside grit/scuff and a floor arc. Its previously authored FX source is retained because it serves this action. |
| Crash Guard | The real top receives the heavy impact and keeps spinning; no piston or orbiting shield remains. Ordinary collision sparks dominate the first instant, so the support cue is restrained. |
| Momentum Bank | Genuine storage, exposed low-charge held fold and chosen release are visible in order. The fold is connected and small; no cassette or independent charge clock remains. |
| Predator Line | The hunter pursues one real rival, with local floor contact/pressure rather than a detached target widget. Pursuit is subtle in grayscale, and this sustained window does not prove disengagement/expiry. |
| Crosscut | Actual offset tops glance and separate with a brief narrow shear/scar. The artificial blade is absent. |

Final V2 review deliverables inspected after the last revision:

- `002c5_power_before_after_v2.png` and its grayscale companion: focused **ten-family before/after cards/icons** at native size, accompanied by current actual Rank II combat crops. The runtime crops are current V2 footage, not a fabricated historical runtime comparison. Rejected runtime evidence remains in the preserved snapshot; Chain's restored card/icon come from its best historical source.
- `002c5_power_visual_matrix.png` and `002c5_power_visual_matrix_grayscale.png`: **all-thirteen native matrix**, including Rank II/mutations, so the correction does not merely improve isolated close-ups. The final human matrix uses native crops from the actual 21 input-only recordings, with `matrix-gameplay-provenance.json`; it supersedes the posed human-review matrix. Actual combat views use Rank II, and mutation views Rank III. Rank I card comparisons are explicitly labelled as art comparisons rather than Rank I gameplay proof. The 34-state posed fixture remains separate technical evidence.
- `002c5_power_art_showcase_v2.mp4`: muted **46.8 seconds / 2,808 frames** of card → icon → genuine gameplay correspondence. `002c5_power_blind_review_v2.mp4`: muted **31.2 seconds / 1,872 frames** without cards, names or editorial labels. All 21 whole-window phone clips contain six seconds / 360 frames each. Final H264/yuv420p 1280×720 60fps files fully decode without errors and use faststart; `validation/media-v2-verification.json` and `full-motion-phone-verification.json` record exact hashes. Refreshed changed-source captures replace the earlier weak windows. A cut while a real state remains active does not prove expiry.
- Exact saved native source/export paths, input-only capture provenance and presentation isolation/regression checks. All four final matrix/before-after PNGs were inspected in colour/grayscale; the mutation crop selection was corrected to show actual Bulwark impact, Counterweight release and Comet rival contact. Independent final MP4 card64/icon16/gameplay samples and source/video hashes are recorded in `validation/independent-encoded-final-review/proof.json`.

## Validation and Windows checkpoint

The frozen validation records **34/34 passing suites, 42,321 counted checks**, including 4,584 identity checks, 34 draw states and one paid Ghost preview. Two seeded RPM replays match exactly. `validation/source-retention.json` verifies **72 canonical files unchanged**, including Battle, PowerRuntime, roster mechanics, collection and menu flow, historical native masters and accepted top textures. Main's only exempt change is its explicit `Physical Art V2` window title. There is no PowerRuntime exception. Art source/export parity and rendering checks establish editability and isolation; they do not establish human comprehension or acceptance.

The final idle benchmark in `art-performance.json` uses an explicitly synthetic held stress fixture: 12 small bodies, seven families, the existing 32-FX ceiling, 54 draw calls and 419 samples, native 640×360 with VSync disabled. CPU draw submission excludes asynchronous GPU work; wall time includes the harness. The final run occurred after tests, media work and the packaged smoke process finished. The earlier overlapping benchmark is preserved separately.

| Recorded metric | Rejected checkpoint median / p95 | Final V2 median / p95 |
| --- | --- | --- |
| CPU draw submission | 1.527 / 2.201ms | 1.509 / 1.707ms |
| Frame wall time | 5.772 / 7.093ms | 5.667 / 6.278ms |
| Simulation | 3.364 / 4.286ms | 3.320 / 3.721ms |

These are observations on the recorded GTX 1660 / i3-10105F system, not a paired performance guarantee or universal FPS promise. The bounded body/effect/draw counts are the relevant retained limits; this fixture is not natural combat or survival evidence.

The final Windows export succeeds. Its executable is **110,919,880 bytes**, SHA256 **`156e27539d7a527b49f94d7c42e634499f7ebf7d24e1fc1f84397138e6c55a6f`**. The exact exported binary smoke test exits 0 with empty stderr and exercises first-top selection → confirmation → ownership → Workshop, current identity draft/acquisition/HUD flow and ten threats. Packaged screenshots include the first-top choice, owned Workshop, opening Bank/Gear/restored Chain cards and later native Predator/Wake/Crosscut upgrades. `validation/packaged-smoke-result.json` records the exact binary and the fresh actual-save hash comparison. The user's real collection remains unchanged: before/after SHA256 **`21a020af0ed88331966a1c988bbe96456664e655083ee34f1b8b44123751b48c`**. Its contents were not read or reset; the smoke flow used an isolated save.

**Independent historical/native/actual-motion review and checkpoint validation are complete. Human approval remains pending, and no main merge is authorized.** The inspected checkpoint may be delivered for human review without treating delivery as human approval. No new agent art grades replace the human decision, and the previous rejected showcase/grades do not satisfy V2.

## Twelve human review questions

1. Is Chain Impact at least as clear and strong as its best historical version?
2. Does Clutch look like a struggling top recovering useful spin?
3. Does High Gear read as the speed of a spinning top, rather than a vehicle?
4. Does Orbit Drive communicate curved movement?
5. Does Crash Guard show a top surviving an impact?
6. Does Momentum Bank show stored movement?
7. Does Predator Line clearly show pursuit of one real rival?
8. Does Iron Comet look like a top committed to an attack?
9. Do the cards make sense without text?
10. Does gameplay match the cards?
11. Are the corrected families distinct in grayscale?
12. Does the work look intentionally authored rather than AI-generated?
