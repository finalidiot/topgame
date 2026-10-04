# Motion-family art handoff

This addendum replaces the weak C5 card/icon treatment for Redline, Iron Comet,
High Gear, Orbit Drive and Clutch. Their new native masters are the editing
authority. The successful C4 fragmented Redline active signatures are
intentionally retained by the integrated renderer; the fresh card/icon and
contact/overcap/heat/commit FX grammar corresponds to those hot asymmetrical
fragment banks. Other superseded card/icon sources remain historical references.

The work is scripted pixel-cluster authorship with separate family compositions
and deliberate poses, saved as normal editable RGBA Aseprite layers. It is not
manual mouse painting and it is not a palette-only clone of an old master.
`tools/author_identity_motion.py` is a one-time construction/revision tool;
ordinary exports must not run it over artist edits. It refuses an existing
master unless construction revision is explicitly requested with `--revise`.

## Source and runtime correspondence

For each of `redline`, `iron_comet`, `high_gear`, `orbit_drive`, and `clutch`:

- Native masters: `<family>_cards.aseprite`, `<family>_icons.aseprite`,
  `<family>_fx.aseprite` in this directory.
- Runtime atlases: `assets/powers/identity/<family>_{cards,icons,fx}.png`.
- Design grammar: `assets/powers/identity/<family>_design.json`.
- Source-derived tags, pivots, durations and paths:
  `assets/powers/identity/<family>_manifest.json`.
- Aggregate read-only runtime index: `assets/powers/identity_manifest.json`.

The five families provide 15 masters, 14 card/icon states, 168 card keys,
14 separately drawn icons, and 1,688 FX keys in 211 tags. Heading tags repeat a
mechanical event at distinct authored screen-direction placements; they do not
rotate a physical isometric sprite at runtime.

| Family | Card/icon states | Card keys | FX keys / tags |
| --- | --- | ---: | ---: |
| Redline | `redline`, `redline_ii`, `runaway`, `breakneck` | 48 | 648 / 81 |
| Iron Comet | `iron_comet`, `iron_comet_ii` | 24 | 576 / 72 |
| High Gear | `high_gear`, `high_gear_ii`, `terminal_velocity`, `flow_state` | 48 | 288 / 36 |
| Orbit Drive | `orbit_drive`, `orbit_drive_ii` | 24 | 144 / 18 |
| Clutch | `clutch`, `clutch_ii` | 24 | 32 / 4 |

Cards are 64×64 with a (32,32) pivot and 12 unequal-duration keys per state.
Icons are independent 16×16 drawings with an (8,8) pivot and one cel per state.
FX are 96×80 with a (48,48) contact pivot, eight keys per tag, and a 535ms
authored sequence; Clutch's stutter sequence is 555ms. Runtime finite events
map their actual lifetime onto this sequence. Active state selection comes
from real power fields; possession alone must not activate the marks.

Cards have five named editable scene, chassis, rotor, action and highlight
layers. FX have four floor/contact, mechanism, moving-force and fragment
layers. Icons have two compact silhouette/action layers. Tags use actual
catalogue IDs or meaningful mechanical stages. Every native export was checked
against the composited source visible RGBA pixels by the native Aseprite CLI.
Nearest filtering is required.

Normal export, without reconstructing source:

```powershell
python tools/export_power_identity.py --family redline --family iron_comet --family high_gear --family orbit_drive --family clutch --aseprite 'F:\SteamLibrary\steamapps\common\Aseprite\Aseprite.exe'
```

## Mechanical grammar and authored key stories

| Family | Card sequence | Icon and runtime correspondence | Rank/mutation development |
| --- | --- | --- | --- |
| Redline | Keys 0–2 ignite, 3–6 stretch/splinter, 7–9 shed heat, 10–11 settle. No clean corona. | A dense cut metal plate and broken hot banks; runtime fragments live at rotor edges and the velocity wake. Overcap tears away an extra vent plate. | II adds a side vent. Runaway has irregular off-axis displacement and frayed contact beats. Breakneck 0–3 compresses, 4–7 commits into a rival, 8–11 scrapes and recoils. |
| Iron Comet | 0–3 visibly compresses at a wall bank, 4–6 separates into flight, 7–10 strikes and scars, 11 resets the illustration. | The icon combines wall, suspended mass and disconnected wake chips. Runtime wall-side brackets, separated heavy plates and violent local contact retain that story. | II adds a second wall brace and a third heavy separated wake. No giant triangle or wedge. |
| High Gear | 0–2 enters a velocity corridor, 3–7 stretches intervals and advances the mass, 8–11 lets the wake settle. | The icon is a forward-cropped plate with spaced wake bars; runtime intervals stretch behind actual velocity. | II adds a low transmission shoe and third lane. Terminal is sparse, long and discontinuous. Flow retains two open bent rails with a narrow guide travelling into the bend. |
| Orbit Drive | 0–2 enters a turn, 3–6 carves, 7–9 holds the contact hook, 10–11 releases toward the next entry. | The icon's concave hook maps to a compact floor scar and displaced grit. The card scar follows its actual authored contact-tip route below the body. | II adds one outside groove and more grit. Heading variants put the short floor hook behind actual movement. It is not a rotor aura or Flow's long guide rails. |
| Clutch | 0–5 slips with an irregular 10px upper-mass shift and strongly canted bit; 6–7 catches; 8–11 partially recentres but remains strained. | A single toothed L-pawl catches a leaning bearing. Runtime danger enters unevenly; a real successful catch gives a short pale tooth flash. The card contact bit stays planted throughout. | II adds a smaller staggered bearing stop. There is no expanding recovery ring, reserve reset or airborne relaunch. |

The common steel material belongs to the same physical spinning-top world.
The scene/action silhouette is family-specific. There is no shared diagonal
floor-plinth background: Comet uses its wall/scar evidence, Gear a sparse
velocity corridor, Redline heat damage, Orbit its actual compact contact
route, and Clutch a small strained bearing/contact patch.

## Review status

The author reviewed all 14 cards at native 64px, all icons at native 16px,
nearest zooms, the 12-key sequences, representative eight-key FX sequences,
and desaturated side-by-side views. The earlier cards were Tier C. The revised
families are provisionally Tier B or better under the agent's art audit;
Iron Comet's wall/compression/strike sequence is a flagship candidate. The
complete roster and actual muted HUD-free gameplay review remain the final
integration gate, and human acceptance is not claimed here.

Internal native/gray/keyframe review images are outside Git at
`C:\GPT GAME BUILDING\task-002c5-qa\identity-motion-review`.
They are an authoring check, not the final roster matrix or a natural gameplay
efficacy demonstration. No art in these five families is intentionally a
temporary placeholder. Event sizes and bounded effect limits did not change.

## Actual motion capture

`tests/capture_identity_motion.gd` starts an explicitly controlled single-family
Rank II investment at a genuine full-reserve launch. It uses only steering,
Burst and brake after that setup, including during warm-up. It does not assign
positions, velocities, enemy states, RPM, cooldowns or proc fields. The real
continuous director, AI, contacts and RPM accounting run on every combat tick.
It records timestamps for both power-runtime and roster-runtime counters plus
active-state transitions. A controlled opening build is never labelled as an
earned draft run.

Selections are actual family IDs, `all`, the eight actual mutation IDs, or
`mutations`. Mutations remain pure-family Rank III opening investments. Clutch
defaults to seed7341 and the proven sampled weak-brake-then-hunt policy;
explicit `--seed` overrides that. Bank uses a real five-second acceleration,
brake/load and directed release cycle. Crosscut uses target-relative lateral
steering, Predator uses normal pursuit, and Guard/Chain rely on real contacts.

Useful options: `--family=momentum_bank`, `--families=all`, `--rank=1`,
`--family=ghost_circuit`, `--start=...`, `--length=...`, `--seed=...`,
`--manifest=<absolute external JSON>`, `--frames=<absolute external folder>`.
`--diagnostic` simulates without rendering or sound. `--blind` omits all power
and build captions for the muted HUD-free recognition review. The battle view
does not attach the game's power HUD. The harness itself does not encode video.

The first clean pure Bank II diagnostic produced seven actual stores and seven
releases over 35 captured seconds, with a 76.53 peak charge. Representative
windows for the final review should be selected from the emitted proc moments,
not from an assumed demonstration outcome.
