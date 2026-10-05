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
