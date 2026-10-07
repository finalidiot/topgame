# Beast manifestations — 002C.5.2

Four native pixel apparitions share a 128×128 cell and a contact pivot at
`[64, 96]`. They emerge from the equipped spinning top and render behind its
opaque part stack. The sprites contain no replacement rotor, target reaction,
gameplay text or colour-coded class restriction. Their identifying contours
remain distinct in grayscale.

| Identity | Authored anatomy and action |
| --- | --- |
| Black Arrow | A compact muscular **human**, with broad shoulders, a narrow waist, thick thighs and a short hair tail attached to the back of the head. The backward arch leads to an inverted tuck, asymmetric crossed shoulders in the axial corkscrew, a partial opening hold and a chest-down landing. No bird or arrow projectile. |
| Iron Bull | A broad bovine forehead and muzzle, two wide raised horns, a heavy shoulder hump, a tufted tail and four hoof chains. The head lowers while the shoulder and legs commit to the charge. |
| Stone Tortoise | A low domed shell with broad organic scutes, a neck and head, and four feet. Travel transfers weight between limbs; guard spreads the feet and retracts the neck into the dome. |
| Coil Dragon | A long tapering serpent spine curls around an open centre. Two swept horns, an upper/lower jaw gap and clawed limbs identify the dragon. The neck uncoils into the strike and returns to a defensive curl. |

The main body uses translucent charcoal, a one-pixel silver contour and a few
large anatomical planes. Broken low-opacity wisps gather into the contact
pivot. Smoke does not define the creature silhouette. The giant bodies are
larger than the normal equipped rotor; horns, hands, feet and jaws have room
within the cell. Every final native cell has a clear border, verified by the
exporter.

All eighty keys are independently authored anatomy or shell/spine poses. The
Black Arrow sequence changes projection through the somersault and axial twist;
it is not a rigid sprite rotated around a spindle. No raster rotation, smooth
resampling, blur or procedural runtime repainting is used.

Each master has four editable normal RGBA layers, five forward tags, a named
`contact_pivot` slice, a grayscale palette and per-cel durations. The layer names
separate rotor smoke, far anatomy, the main body and large anatomical highlights.

| Tag | Frames | Durations in milliseconds | Total |
| --- | --- | --- | --- |
| prepare | 0–3 | 65, 60, 60, 65 | 250 ms |
| travel | 4–7 | 135, 110, 115, 140 | 500 ms |
| strike | 8–11 | 60, 70, 80, 90 | 300 ms |
| recovery | 12–15 | 55, 65, 80, 100 | 300 ms |
| guard | 16–19 | 140, 110, 110, 140 | 500 ms |

Prepare, travel, strike and recovery play once. Travel holds its last key while
the real committed movement continues, so one commitment produces one
somersault. Guard loops while the real guard state remains active. The renderer
must select a cell by its exported durations, then use its declared column count
and pivot. A real collision selects strike; a missed attack proceeds to recovery.
The apparition can rise while the physical top retains the implemented floor
model. These assets do not grant an actual jump or invulnerability.

The master files live in `assets/source-art/beasts_002c5_2/`; the four runtime
sheets and `manifest.json` live in `assets/powers/beasts_002c5_2/`. The manifest's
`effects` keys are `black_arrow`, `iron_bull`, `stone_tortoise`, and `coil_dragon`.
Each entry exposes `texture`, `source`, `cell`, `pivot`, `columns`, `frame_count`,
`durations_ms`, `tags`, `label`, `description`, and source/texture SHA-256 hashes.
Tag records contain `from`, `to`, `duration_ms`, and `loop`.

Edit the `.aseprite` masters in native Aseprite, preserving the tags and pivot,
then export and verify with:

```powershell
python tools/art/beast_manifestations.py
```

`--aseprite` overrides the executable; otherwise the exporter uses the workspace
finder and `TOPGAME_ASEPRITE`. `--qa-root` redirects external QA. `--author` is an
explicit reconstruction of this family’s original key-pose recipe and overwrites
only these four new masters. Normal export does not reconstruct any source file.
No older art family is regenerated.

Native Aseprite is the blend authority. The exporter reads source layers/tags,
invokes Aseprite's native sheet export and checks native cell size, pivot, layers,
tags and every frame duration. Source and native alpha match exactly; visible RGB
channels can differ by at most one rounding step between Aseprite and Pillow.
Runtime RGBA is copied from the native result and checked for exact equality.
All keys must be nonempty, pixel-distinct and clear of the cell boundary.

External art review files are under
`GyroBrothers-QA/002C.5.2/images/002c5_2_beast_*` and individual
`002c5_2_<identity>_all_keys_2x.png` sheets. The full native and grayscale matrices
contain all eighty keys; the 640×360 static fit places existing opaque top parts
over two representative keys of each identity. These are explicitly static art
QA, not battle evidence. Native export metadata, commands and source/runtime
hashes are under `002C.5.2/manifests/beast-manifestations/`.

The art-parity report records human visual acceptance as pending. Gameplay
captures and the player's judgement remain separate from deterministic native
export validation.

## 003A final human colour correction

The shared grayscale treatment above records the original 002C.5.2 delivery.
Human feedback during 003A requested coloured, translucent spirit silhouettes.
The four native masters now carry separate six-role palettes:

| Identity | Native body | Anatomy/edge treatment |
| --- | --- | --- |
| Black Arrow | smoky charcoal `#454a50` | dark cool shadow, charcoal planes, restrained cool silver edge |
| Iron Bull | heated iron / rust red `#743f36` | deep red shadow, rust planes, warm silver horns and contour |
| Stone Tortoise | earthy spectral green `#416b3e` | deep green shadow, sage shell planes, pale sage silver scutes/edge |
| Coil Dragon | muted cyan blue `#36627a` | blue violet shadow, blue scale planes, ice silver jaw/edge |

No earlier Bull or Dragon colour identity was found in the native palette or
canonical art notes; their new colours follow the human's requested defaults.
Black Arrow retains the documented charcoal/silver human tribute. Silver and
edge roles remain distinct from main anatomy and smoke; none is a single tint
applied over the exported image.

`tools/art/beast_colour_identity.py --apply` is an explicit, one-time migration
of the original native RGB swatches and visible cel RGB. It first preserves all
four original masters externally and verifies their native/runtime pixel parity.
It refuses already migrated or unrecognised palettes. Every alpha byte, hidden
transparent RGB byte, cel header, layer chunk, frame tag, slice, pivot, duration,
unknown native chunk and pixel shape remains unchanged. All four masters still
contain four editable normal RGBA layers, twenty distinct keys and five tags.

The export command for current 003A evidence is:

```powershell
python tools/art/beast_manifestations.py --task 003A
```

Use `--check --task 003A` for a fresh native verification without rewriting
production source, runtime PNGs or the manifest. Every invocation writes its
native exports and parity records to fresh unique external directories;
`--check` skips static review-image creation. Normal export also gives its static
diagnostic images a unique directory, preserving previous verification evidence.

Native Aseprite remains the blend authority. The runtime manifest records the
native palette, colour identity and alpha/shape hashes. Native/runtime RGBA must
match exactly; the independent Python compositor may differ by one visible RGB
rounding step. The native layers contain authored translucency, while some
overlapping edge pixels composite to alpha 255; the renderer's bounded global
alpha keeps the entire manifestation translucent. Alpha is identical to the
original masters and sheets. Nearest-neighbour presentation remains required.

Baseline migration evidence is under
`GyroBrothers-QA/003A/manifests/beast-colour-identity/`; final native exports and
parity records are under `003A/manifests/beast-manifestations/`. The compact
original noncolour/alpha/shape fingerprints live in
`tests/fixtures/beast_003a_colour_invariants.json`, with current art tests in
`tools/art/test_beast_colour_identity.py`. Package verification checks actual
imported beast RGBA and exact palette metadata, rejecting old grayscale sheets
or colour/alpha drift.

The prior semantic travel hold/guard loop description above is historical.
003A's final correction reserves full silhouettes for extreme physical impacts,
and their once-only authored prepare/travel/strike/recovery completion takes
priority over facing response. No native frame or duration was changed for that
runtime correction. The actual gameplay colour matrix and films are separate
human review evidence; static diagnostic fit/key sheets are explicitly art QA.

The current matrix is
`GyroBrothers-QA/003A/images/003a_beast_colour_matrix.png`, with its source-frame
hashes and collision/phase/key provenance in
`003A/manifests/003a_beast_colour_matrix.json`. It contains eight complete native
640×360 game frames: Black Arrow's inverted somersault and strike, plus travel
and strike for each other beast. Every gameplay tile is pixel-identical to the
actual engine viewport capture; captions are outside gameplay. The source
collision fixtures are declared in the capture and traverse the canonical
physical solver. No sprite recomposition, runtime recolouring or resampling is
used to manufacture contrast or opacity acceptance.
