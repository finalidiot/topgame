# Human feedback: physical runtime accents

These are focused runtime additions to the provisional 002C.5.2 checkpoint.
Existing ability cards, HUD icons, top bodies and accepted source masters remain
unchanged. Human visual and gameplay acceptance is still pending.

Editable production source is `assets/source-art/feedback_002c5_2/`. Native
runtime exports are in `assets/powers/feedback_002c5_2/`. Each master has named
normal RGBA layers, frame tags, per-frame timing, a named `contact_pivot` slice
and its own palette. There is no baked substitute top or enemy in the effects.

| Master | Runtime | Cell / pivot | Authored keys |
| --- | --- | --- | --- |
| `centre.aseprite` | `centre.png` | 96×80 / (48,48), six columns | 24 |
| `impact.aseprite` | `impact.png` | 96×80 / (48,48), six columns | 18 |
| `pickup.aseprite` | `pickup.png` | 24×16 / (12,10), one column | 1 |

`manifest.json` exposes `effects.centre`, `effects.impact` and `effects.pickup`.
Each has a `res://` texture path, repository-relative source path, `cell`,
`pivot`, `columns`, `frame_count`, `durations_ms`, named `tags` and content
hashes. Tags include `from`, `to`, total `duration_ms`, `loop`, `hold_last`,
description and the required runtime cause. Use the per-frame timing from the
master when selecting the cel; do not treat every pose as an equal duration.

## Floor anchoring

All Centre effects use the real bit's arena-floor position, under the top's
ordinary sprite. The initial two staggered white/grey pressure sweeps settle
inward toward that contact. Draw them only while actual anchor state is present.
Their strength follows the implemented bounded inward gravity; art cannot move
an enemy or fabricate recovery.

| Tag | Frames | Timing (ms) | Runtime use |
| --- | --- | --- | --- |
| `centre_seek` | 0–5 | 110,90,90,110,130,160 | Loop while charge exceeds 0.07; amplitude follows charge/maturity. |
| `centre_brace` | 6–11 | 90,100,110,100,100,180 | Charge 0.35–0.70 deploys short feet; hold final key after full deployment. |
| `centre_brace_full` | 12–17 | 90,100,110,100,100,180 | Rank II/Bulwark mature hold extends larger grounded supports. |
| `centre_recoil` | 18–23 | 30,35,45,55,65,90 | Actual accepted anchored collision, at most 0.32 seconds. |

The four articulated arms start at the bit collar. Their hinged elbows lead to
flat floor pads and short compression seams. Back arms are naturally hidden
by the blade; front arms and feet remain readable. The extended form retains
an open centre and never covers the complete rotor with a device or glow.
The seeker pulse may continue around held hardware. Deployment should not
loop and repeatedly retract a top that is already fully anchored.

## Contact blast waves

Light, heavy and extreme tags use the actual accepted collision location and
event age. An initial contact knuckle leads into two unequal broken pressure
fronts, followed by short divergent fragments. The heavy variants have a second
wave and a larger white contact; the top's ordinary body remains the subject.
There is no fullscreen flash, filled projectile wedge or synthetic enemy
reaction. Select intensity from actual impulse/ramp state, with the existing
bounded event budget. Do not spawn impacts merely because a timer advanced.

| Tag | Frames | Timing (ms) | Total |
| --- | --- | --- | --- |
| `impact_light` | 0–5 | 30,35,45,55,65,90 | 320 ms |
| `impact_heavy` | 6–11 | 30,40,55,70,90,125 | 410 ms |
| `impact_extreme` | 12–17 | 35,45,65,90,120,155 | 510 ms |

These are fixed projected floor waves. They do not require rotating a raster
texture. Their radius stays inside the 96×80 cell. Central sparks correspond
to the contact point between rigs, rather than a marker floating beside them.

## Reroll floor pickup

The single `reroll_chip` pose is a low steel token with two opposed stamped
recycle arrows, a pale cyan/white face and a physical front rim. Draw at the
actual collectible floor position with pivot (12,10). The gameplay pickup
radius is independent of this visual silhouette. Collection, count gain and
removal must follow the real pickup state; the sprite never grants a reroll.

## Export and evidence

```powershell
python tools/art/feedback_effects.py
```

Normal export reads the artist-edited masters. `--author` deliberately
reconstructs only these three original masters and is not a runtime step.
The tool honours `TOPGAME_ASEPRITE`, `TOPGAME_QA_ROOT` and an explicit
`--aseprite` or `--qa-root`. Native Aseprite opens and exports every master.
Layers, tags, slice pivots, dimensions, timing and nonempty keys are checked.
The exported runtime pixels match native Aseprite's decoded RGBA exactly.
The independent Pillow source reader differs by at most one RGB least
significant bit at overlapping translucent pixels because of compositor
rounding; alpha must still match exactly. Native Aseprite is the production
blend authority, and a larger discrepancy fails validation.

External evidence remains under `GyroBrothers-QA/002C.5.2/`:

- `manifests/002c5_2_feedback_effect_art.json`: actual native export validation.
- `images/002c5_2_feedback_effect_keys.png`: all authored poses at native scale.
- `images/002c5_2_feedback_effect_keys_2x.png`: nearest-neighbour comparison.
- `images/002c5_2_feedback_native_fit.png`: explicitly labelled static 640×360
  fit reference using actual Guard/Low/Needle and Puck/Ballast/Tripod pixels.
- `images/002c5_2_reroll_chip_detail.png`: enlarged stamped-arrow inspection.

Those static art sheets are not presented as gameplay evidence. Real battle
captures must verify that runtime charge, gravity, accepted impacts and actual
pickup positions drive the final presentation. These accent assets do not
claim human acceptance of the provisional checkpoint.
