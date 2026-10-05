# Task 002C.5 native ability art handoff

Three editable native RGBA Aseprite masters add the expanded roster. Existing
002B/002C/002C.4 masters remain intact. Initial integer pixel clusters and key
poses were authored inside Aseprite through its Lua editing API, then Ghost's
preview clamps were revised after native gameplay-scale inspection. This is
scripted native authoring, not a claim of manual mouse painting. The saved
masters are the authority for further artist edits.

| Master | Canvas / pivot | Frames / tags | Runtime atlas |
|---|---|---|---|
| `roster_fx_002c5.aseprite` | 96×80 / (48,48) | 120 / 20 | `roster_effects.png`, six columns |
| `roster_cards_002c5.aseprite` | 64×64 / (32,32) | 108 / 18 | `roster_cards.png`, six columns |
| `roster_icons_002c5.aseprite` | 16×16 / (8,8) | 18 / 18 | `roster_icons.png`, eighteen columns |

All use named `contact_pivot` slices, named normal RGBA layers and embedded
palettes. FX retain the C.4 rotor plane near (48,34), contact plane at (48,48),
and fixed 2:1 projection. Cels stay upright; motion composes small disconnected
wakes along the real projected velocity. No sprite rotation, smoothing, or
filled directional wedge is used for Iron Comet.

FX tags: `comet_charge`, `comet_flight`, `comet_impact`, `comet_recovery`,
`overcap`, `heat_extreme`, `clutch_danger`, `clutch_recover`, `gear1`, `gear2`,
`terminal_surge`, `flow_state`, `orbit_drift`, `crash_guard`, `momentum_store`,
`momentum_release`, `predator_lock`, `crosscut`, `ghost_preview`, `ghost_latch`.
Each has six key cels at **60,45,55,80,100,140 ms**. Temporal playback observes
source timing. Momentum storage selects actual charge stages rather than
pretending to fill the bank automatically.

Card/icon rows: `clutch`, `high_gear`, `orbit_drive`, `crash_guard`,
`momentum_bank`, `predator_line`, `crosscut`, then each corresponding `_ii`,
then `terminal_velocity`, `flow_state`, followed by the replacement
`iron_comet`, `iron_comet_ii` bank-wall and spinning-rotor artwork. The old
knife/wedge Iron Comet card is absent from the active draft and HUD rendering.
Cards use six deliberate poses at
**110,90,75,75,100,170 ms**, matching accepted reward-card timing. Icons have
one frame per named tag. Card artwork keeps the spinning machine as its subject:
bearing catches, velocity rails, curved floor paths, bumper segments, braking
storage cells, target pressure and crossing physical routes.

FX layers:

1. `01 floor contact and silhouette`
2. `02 mechanical structure`
3. `03 active energy`
4. `04 key flash and fragments`

Cards retain five separate industrial-backplate, ground-depth, machine,
route/stress and confirmation layers. Icons retain separate steel mechanism
and state/motion layers. The C.4 palette adds `3d6e99` and `75b9e1` for speed;
shape and event rhythm also distinguish abilities.

Edit and save the masters in Aseprite, retaining tags, canvas, layer structure
and pivot. Export without changing source cels:

```powershell
python tools/export_roster_art.py --aseprite 'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe'
```

Substitute the local Aseprite path as needed. With the executable supplied,
all native exports must match runtime sheets pixel-for-pixel. The exporter
validates native source ranges, layer counts and pivots, then writes
`assets/powers/roster_manifest.json`. Filtering remains nearest-neighbour.
`author_roster_002c5.lua` refuses to replace an existing source;
`refine_roster_preview_002c5.lua` and `refine_roster_comet_cards_002c5.lua`
record one-time source revisions and are
**not** a normal export step. Do not rerun source-construction/refinement after
artist edits. Wait for native authoring to finish before exporting.

Iron Comet's rejected old `comet_headings` wedge remains only in historical
source art and is absent from the active renderer. Real wall rebound arms the
compressed rotor state. Its release event keys contact/sparks and a short
scrape aftermath; drawing never changes collision geometry. Redline overlays
use real active time, overcap reserve and heat. Clutch shows a floor bearing
catch on the same live top, with no relaunch pose. Ghost preview reads actual
validated route endpoints; six bounded bridge dashes and two clamp sockets
announce assisted closure. The actual route polygon supplies the payoff.

Audio adds twelve original finite mechanical cues under `assets/audio/`, with
`roster_manifest.json` and reproducible `tools/build_roster_audio.py`. Existing
event keys `comet_charge`, `comet_release` and `ghost_closure` use the new
specific cues. Other new cues are debounced; the existing eight-voice priority
pool remains bounded. No music or constant power loop is added.

Validate with `tests/test_roster_presentation.gd` and the retained
`tests/test_signature_presentation.gd`. `tests/capture_roster_matrix.gd`
produces eighteen explicitly static 640×360 QA states; these are not gameplay
evidence. `capture_roster_review.gd` uses labelled opening builds followed by
real controller inputs; `capture_natural_roster.gd` replays actual earned
Main Run builds from one launch. Large movie sources/MP4s stay outside Git.
