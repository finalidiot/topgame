# Motion-family final art correction handoff

This is the final correction pass on the existing Task002C.5 branch. Human
review rejected the `d0d37e5` Clutch, High Gear, Orbit Drive and Iron Comet
subjects as ambiguous machinery. Those illustrations and their detached
mechanical accents have been replaced with physical top scenes. Redline's
accepted asymmetric hot fragments and existing four card/icon states are
preserved; this correction does not reconstruct its masters.

The four corrected families use the actual accepted starter's native blade,
ratchet and bit pixels as their literal subject. They do not scale that body,
turn a small icon into an illustration, or invent housings, weapons, spacecraft
or external bearing devices. The original component cels remain separate
editable layers inside the new card masters. New scene/action clusters are
scripted pixel authorship, saved as normal native Aseprite cels. This is not
a claim of manual mouse painting.

## Historical comparison inspected

The actual native masters were extracted from Git, composited and inspected at
native size, together with their real exported card/icon/runtime PNGs. The
review evidence is in
`C:\GPT GAME BUILDING\task-002c5-qa\art-correction-v2\motion-history`.

| Family | Best prior physical cue examined | Human-rejected d0d37e5 version | Chosen correction |
| --- | --- | --- | --- |
| Clutch | `bdcc24e` Second Wind card shows broken races closing into a bearing; `32bb56e` Clutch is a tiny rotor plus surrounding marks. | Large abstract bearing/pawl device; the top no longer reads as the subject. | Keep the native `d551867` top wobble/normal blade, ratchet and bit poses. Show scrape, bite and upright settlement. Do not restore the obsolete Second Wind revival-ring promise. |
| High Gear, Terminal, Flow | `32bb56e` speed spacing, Terminal's long interrupted marks and Flow's open retained curve. | Forward projecting housing reads like a vehicle; blade and transmission parts become ambiguous. | Restore those prior motion cues around the real round top. I has one compact prior rotor; II adds another spaced echo/lane; Terminal opens long gaps; Flow retains an open bent contact route. |
| Orbit Drive | `32bb56e` curved movement cue, despite the generic central rotor/ring composition. | Large sideways object with a very small floor hook. | Literal top moves around a wide C-shaped contact-tip path. II deepens the outside grooves and displaced grit, rather than adding a badge. |
| Iron Comet | `bdcc24e` wall scene is stronger causal context but its knife-like mass and `f72526e` giant wedge runtime are not physical tops; `32bb56e` retains the wall but tiny generic rotor. | Wall, pseudo-rotor and separated plates look unrelated to a committed physical attack. | Retain the wall, actual native player top and native hostile target. Six poses show wall compression, alignment, launch, impact, target recoil and exit/scar. No wedge restored. |

Actual historical files inspected:

- `bdcc24e`: `assets/source-art/power_cards_002b1.aseprite`,
  `power_icons_002b.aseprite`; `assets/powers/cards.png`, `icons.png`.
- `f72526e`: `assets/source-art/power_fx_002b.aseprite`;
  `assets/powers/effects.png`, including `comet_headings`.
- `32bb56e`: `assets/source-art/roster_cards_002c5.aseprite`,
  `roster_icons_002c5.aseprite`, `roster_fx_002c5.aseprite`;
  `assets/powers/roster_cards.png`, `roster_icons.png`, `roster_effects.png`.
- `d0d37e5`: current identity card/icon/FX masters and their real PNGs for all
  four families, including the High Gear mutations.
- Accepted physical subject from `d551867`, unchanged since the baseline:
  `assets/source-art/starter_balance_mid_ball.aseprite` normal/high RPM and
  heavy wobble poses. The hostile target is the existing native
  `assets/source-art/small_top_002b.aseprite`. Neither historical original was
  overwritten; their original component cels are copied into editable layers.

Older does not automatically mean better either: the recovery ring, Comet
wedge and generic rotor decorations are recorded as rejected historical
alternatives. The accepted native physical top and stronger historical causal
motion cues are restored without changing their style into a new machine.

## Corrected source/runtime correspondence

For each of `iron_comet`, `high_gear`, `orbit_drive`, and `clutch`, modified:

- `<family>_cards.aseprite`, `<family>_icons.aseprite`, `<family>_fx.aseprite`
  in this directory: **12 editable masters**.
- `assets/powers/identity/<family>_{cards,icons,fx}.png`: **12 runtime atlases**.
- `<family>_design.json`, `<family>_manifest.json` in that runtime directory;
  the aggregate `assets/powers/identity_manifest.json`.
- One-time construction recipe `tools/author_identity_motion.py`. Normal
  source export reads the saved masters and never reauthors them.

Cards retain 64x64 cells, pivot(32,32), catalogue tags and 12 timed cels per
state, but use **six deliberately held key poses**, not more interpolation.
Icons are separately drawn 16x16 silhouettes with pivot(8,8), not card crops.
Runtime FX retain 96x80 cells, pivot(48,48), eight timed cels per meaningful
tag and authored upright headings. The corrected families total ten card/icon
states, 120 card cels, ten icons and 1,040 FX cels in 130 tags. Native CLI exports
match all visible source RGBA pixels exactly. Nearest filtering is mandatory.

| Family | Where runtime art appears | How it moves and persists | Physical distinction |
| --- | --- | --- | --- |
| Clutch | Directly under the actual struggling bit, then at its earned contact. | Uneven floor scrapes during the actual danger window; one local bite and short settled scrape during real recovery. | Floor grip loss/catch; no external pawl, reticle, ring or floating revival object. |
| High Gear | Behind the actual moving top, aligned to real velocity. | Sparse faded native blade-rim clusters separate along actual velocity while the real speed state is active. | I/II count and spacing develop; Terminal has long separated intervals; Flow keeps three disconnected bent contact-floor groups. |
| Orbit Drive | At the contact floor behind/outside the actual drifting top. | Short growing hooked scars and thrown grit exist only during actual brake-turn drift. | Curved floor carving, rather than Gear's spaced rotor echoes or Flow's long open retention path. |
| Iron Comet | Wall-facing blade edge, actual rebound wake, real target contact and floor exit. | Small squeeze ticks touch the blade; sparse blade-rim memories leave behind the true velocity; a local impact flash becomes scrape fragments. | Wall compression into the same physical top's charged contact; no projectile shape. |

The runtime never invents an impact, recovery, target reaction or proc. Source
FX pose strips are labelled authoring evidence. Final acceptance uses the real
mechanic-driven clips produced by the integration capture harness.

## Review evidence and remaining limits

Native state and grayscale authoring views:

- `C:\GPT GAME BUILDING\task-002c5-qa\art-correction-v2\motion-work\motion_v2_native_states.png`
- Same path ending `_gray.png`.
- `motion_v2_preview.png` / `_gray.png`: all twelve card keys at native scale.
- `motion_v2_fx.png` / `_gray.png`: representative eight-key runtime source
  strips, not synthetic gameplay.
- `motion_v2_before_after_native.png` / `_gray.png`: d0d37e5 versus correction
  at actual 64px card scale.
- `motion_v2_source_proof.json`: selected source keys and native-master hashes.

The internal comparison finds distinct physical scene silhouettes in grayscale:
Clutch's tight scrape/catch; Gear's stretched direction; Orbit's broad turn;
Comet's wall-to-rival collision. The source-level review is not human acceptance.
The real gameplay matrix/showcase and twelve acceptance questions remain the
human review gate. Tiny Clutch floor bites are deliberately brief; visibility
during crowded combat must be assessed in the actual clip, alongside the
body's true low-RPM wobble and earned settling. No family is intentionally
left as placeholder art.

Normal export, without reconstructing sources:

```powershell
python tools/export_power_identity.py --family iron_comet --family high_gear --family orbit_drive --family clutch --aseprite 'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe'
```

## Sustained Orbit motion proof

The earlier input policy exposed only about83ms of real drift in its chosen
window. The new explicitly labelled capture-only `--policy=long_drift` builds
real speed for two seconds, holds ordinary brake plus velocity-relative lateral
steering for4.5seconds, then releases. It edits only the controller input
dictionary; existing policies are unchanged, and no actor, position, velocity,
RPM, cooldown, rival or proc is assigned.

Pure OrbitII / Vane / seed421 produces a continuous actual `drift_active`
interval13.7167–16.3167seconds, verified twice, with a clean input-driven arc:
(142,29)→(83,68)→(8,75)→(-63,46)→(-112,-14)→(-123,-89). Actual speed remains
134–156, and RPM is paid from0.9166 to0.9073 over the sampled interval. A six
second clip beginning13.4 records exactly360frames; a2.4second excerpt from
clip offset0.5 remains inside the continuous drift.

Proof: `C:\GPT GAME BUILDING\task-002c5-qa\art-correction-v2\orbit-policy\seed421.json`
and `window13_4.json`, with clean diagnostic logs. This is active-state trigger
evidence: the earlier real curve already built Orbit charge, so this window
does not increment the optional finite `orbit_drift` counter. The sustained
visual is driven by actual brake/lateral steering and its true active field.
Do not relabel it as a fabricated discrete impact proc. Human acceptance
continues to depend on the rendered gameplay clip.

## Dense-motion refinement: Gear and Comet rear memory

The first literal-top FX pass still failed the runtime quality gate: overlapping
opaque old bodies and their dark support/shadow pixels formed a rack/vehicle
block behind High Gear during actual motion. Literal provenance alone did not
make that presentation readable. The intermediate media is preserved under
`art-correction-v2/iterations/before-final-runtime-refinement`, rather than
presented as accepted final footage.

Final GearI/II, Terminal and Comet flight FX remove the entire old bit, ratchet,
base, cast shadow and filled body. Only49–73 actual accepted blade-tip/rim
pixels form each rear memory, separated into small authored clusters with hard
steel palette fading. The real live top is the only solid subject. Continuous
cyan speed bars are removed. Flow retains three short disconnected bent
floor groups. Cards/icons remain frozen because their physical scenes passed
the independent native/grayscale review. No new animation frames were added.

Only `high_gear_fx.aseprite` and `iron_comet_fx.aseprite` plus their corresponding
FX atlases/design/manifest exports changed during this runtime refinement.
Source/CLI exact visible-pixel parity passed again. The native live-top composite
is explicitly labelled authoring evidence in
`motion-work/sparse_motion_fx_live_top.png` and its grayscale companion.
Actual refreshed speed/rebound footage must verify that the sparse memory
stays visible in battle without becoming a solid attachment.
