# Signature animation production handoff

Four new native RGBA Aseprite masters; all older art remains editable and intact.
Art was authored as deliberate pixel-cluster motifs and keyed poses using
Aseprite's Lua editing API, then revised inside Aseprite via the two refinement
scripts after inspecting native gameplay captures. This was scripted pixel
placement, not a claim of manual mouse painting. The masters, not the authoring
scripts, are the production source of truth.

| Master | Frames | Tags |
|---|---:|---|
| `redline_fx_002c4.aseprite` | 42 | `rank1_active`, `rank2_active`, `runaway_low`, `runaway_high`, `breakneck_charge`, `breakneck_hit`, `breakneck_recovery` |
| `dead_centre_fx_002c4.aseprite` | 36 | `anchor_build`, `anchor_full`, `bulwark_lock`, `bulwark_contact`, `counterweight_store`, `counterweight_release` |
| `afterimage_fx_002c4.aseprite` | 30 | `rank1_trace`, `rank2_trace`, `ghost_closure`, `ghost_active`, `slipstream_cross` |
| `combat_fx_002c4.aseprite` | 60 | `light`, `meaningful`, `heavy`, `signature`, `elite_entry`, `boss_entry`, `boss_defeat`, `reclaim`, `second_wind`, `low_rpm` |

Every tag has six frames, with **60, 45, 55, 80, 100, 140 ms** source timing.
Persistent temporal playback observes these uneven timings. `anchor_build`
and `counterweight_store` are six physical state stages, selected by real charge
and stored force, not played automatically. Event cels use six lifetime phases
so the actual event window remains synchronized. Storage-contact feedback does
not pretend to fill the accumulator; only the persistent state can do that.

Every canvas is **96×80**, with named `contact_pivot` slice at **(48,48)**.
The rotor plane is approximately **(48,34)**. Floor geometry uses fixed 2:1
projection. Do not rotate the sprite or change filtering to linear. Directional
events compose upright cels along the projected physical direction; their
underlying pixel artwork stays in the fixed projection.

Each master retains four separately editable normal layers:

1. `01 floor contact and silhouette`
2. `02 mechanical structure`
3. `03 active energy`
4. `04 key flash and fragments`

Embedded palette, excluding transparent: `172b38`, `334954`, `637773`,
`b9bb91`, `f6e5ae`, `fff3d1`, `a34335`, `ef713b`, `ffc05a`, `247b79`,
`52c8b5`, `c8f5d4`. Redline uses hot broken banks/asymmetric fragments;
Dead Centre uses brass/iron floor jaws and accumulator bars; Afterimage uses
mint/teal connected sockets and terminal latches. Shape and rhythm matter as
much as hue. The revised Bulwark feet are wider than ordinary anchor jaws;
signature contact has a short solid key flash before separated fragments.

## Editing and export

Open the `.aseprite` in Aseprite, edit cels/timings on the named layers, and save.
Preserve tags, canvas, pivot and normal RGBA layers. Run:

```powershell
python tools/export_signature_art.py --aseprite 'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe'
```

The optional executable path is specific to this workstation; substitute yours.
The command **never authors or overwrites source cels**. It exports six-column
`assets/powers/signature_{redline,dead_centre,afterimage,combat}.png` sheets and
`signature_manifest.json`. With `--aseprite`, it also opens/exports each master
using native Aseprite and requires pixel-for-pixel equality. Source ranges,
timings, layer count and pivot are validated before export.

Import in Godot, then run `tests/test_signature_presentation.gd` and
`tests/capture_signature_matrix.gd -- --out=<absolute directory>` at 640×360.
Review real motion with `tests/capture_signature_review.gd`; the matrix is
explicitly static QA, not gameplay evidence. For new blend modes or layer groups,
extend the exporter or use Aseprite's native export; do not flatten the master.

`author_signature_002c4.lua` is initial construction history and refuses to
overwrite an existing master. The two `refine_signature*.lua` files are one-time
art revisions, **not normal export steps**. Do not rerun them after artist edits.
Appending frames in Aseprite can extend existing tags: seal/check tag ranges
after frame insertion. This was caught by the new integrity test during authoring.

No reward cards/icons needed replacement: the accepted C.0 card and mutation
glyph set continues to represent the same mechanics.
