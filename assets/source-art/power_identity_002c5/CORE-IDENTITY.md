# Bank, Predator, Crosscut and Guard: native identity handoff

These four families were Tier C before this addendum. Their old roster cards
shared a centered small rotor, and their FX used bars, sockets, an X or a
segmented rim. The replacement sources tell four separate physical stories.
Old masters remain intact for before/after review. Final A/B classification
requires the whole-roster runtime motion review; source quality alone does not
establish muted-gameplay recognition.

| Family | Card composition and motion | Rank II physical development |
|---|---|---|
| Momentum Bank | Large foreground open spring cassette and cast rear brake shoes; separate forward top. Coils compress, hold a load, then extend as the top releases forward. | Second exposed spring chamber and a wider cast mount. |
| Predator Line | Cropped 34px foreground hunter pursues a smaller high-right quarry. Mechanical pressure teeth appear sequentially in the actual pursuit gap. | Paired heavy leading jaws on the hunter and a second pressure lane. |
| Crosscut | Large upper-left subject descends into a glancing contact, then shears sideways past a medium rival. One bright offset shear and unequal exit scars replace the old symmetric X. | Extended physical outer blade, parallel shear edge and developed skid structure. |
| Crash Guard | A 40px foreground machine receives a cropped incoming top. Exposed guide rods shorten behind a broad stop plate, then rebound. | A substantial second lower shock cylinder, rather than a bigger aura. |

The first card pass was reviewed at native scale and in grayscale, then revised
when Bank/Predator still underfilled their 64px space. Crosscut's original
rising diagonal was also revised because it was too close to Predator's chase.
The final Crosscut approach descends; Predator climbs. Colors reinforce those
differences rather than supplying them.

The art uses individually directed native pixel clusters through Python's
technical drawing primitives and the existing Aseprite file writer. It is not
a claim of manual mouse painting. It does not clone or recolor earlier masters.
The saved Aseprite cels are the authority for subsequent artist editing.

## Native masters and playback

Each family owns `<family>_cards.aseprite`, `<family>_icons.aseprite` and
`<family>_fx.aseprite` in this folder. There are twelve masters total.

- Cards: 64×64, pivot (32,32), five named normal RGBA layers, two actual family
  ID tags with twelve deliberately keyed cels each. Card timings differ by
  family and preserve anticipation, action, reaction and follow-through.
- Icons: 16×16, pivot (8,8), two named normal layers and one independently drawn
  cel per rank. Icons are not reduced cards or shrunk runtime FX.
- FX: 96×80, pivot (48,48), four named normal layers, eight cels per tag. Every
  force/charge tag has all eight projected heading suffixes
  `e,se,s,sw,w,nw,n,ne`, at both ranks. Machinery remains upright in the fixed
  projection. Directional strokes and tooth placements use native integer
  coordinates; no runtime or authoring image rotation/resampling is used.

FX contain no replacement rotor. Bank lives behind the actual contact plane;
Guard lives on the actual incoming side; Crosscut lives on the paid lateral
contact; Predator uses the real pursued rival's link. Runtime sources remain
the existing mechanic events and live fields; rendering does not create a
charge, rival, collision or outcome.

Bank FX: `bank_load`, `bank_stored`, `bank_release` plus rank/heading suffixes.
`bank_stored` is **eight real charge stages**, never an automatic filling loop.
Predator FX: `predator_pressure`, `predator_tracking`; tracking stages expose
actual hunt stacks and must stay on the real hunter-target relationship.
Crosscut FX: `shear_slice`. Guard FX: `damper_contact`, contact event only;
there is no persistent floor fortress or automatically orbiting shield.

Plain-base FX duplicates are omitted because every actual heading has a
variant. Bank's largest eight-column sheet remains 768×3840, below a 4096px
height, and the new identities keep existing finite event/state drawing rules.

## Runtime paths and editing

For each family, runtime sheets are
`assets/powers/identity/<family>_cards.png`, `_icons.png` and `_fx.png`.
`<family>_design.json` records grammar, representative frames, semantic tags
and state-stage notes. `<family>_manifest.json` records native layers, tags,
durations, pivots and runtime paths.

Normal editing: open/save the relevant `.aseprite` source, retaining its
canvas, named layers, tags and pivot. Export using:

```powershell
python tools/export_power_identity.py --family momentum_bank --family predator_line --family crosscut --family crash_guard --aseprite 'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe'
```

This export opens each master in native Aseprite and verifies every visible
RGBA pixel against the layered native-source readback. Nearest-neighbour
filtering and original timing are preserved. It never authors source cels.

`tools/author_identity_core.py` is initial authoring/revision history. Its
default refuses artist overwrite. Do not run `--revise` after an artist edits
the masters. During this pass `--cards-only` revised compositions while keeping
HUD icons and arena FX unchanged; `--fx-only` added all eight force headings
while preserving the reviewed cards/icons.

Native-scale color/grayscale sheets and 8× nearest single-frame inspections
live outside Git in `C:\GPT GAME BUILDING\task-002c5-qa\art-core`. They are art
inspection aids, not natural gameplay evidence. Root supplies the whole-roster
matrix, before/after comparison and actual motion showcase.
