# Parts art for 002C.5.2

The new production masters are the twenty individual files in
`assets/source-art/parts_002c5_2/`. Every master is a native 48×48 RGBA Aseprite
document. Blades have eight independently projected top-plane spin cels with a
`spin` tag and 100 ms timing. Ratchets and Bits have one `assembly` cel with
200 ms timing. Each master retains three or four named physical layers, a named
material palette, metadata and the `contact_pivot` slice at (24, 40). Blade hubs
remain at (24, 25). Nothing in the historical component or power art is repainted.

The small isometric sprites depict cast top parts: steel contact plates, visible
front rim thickness, locking hubs, structural collars and floor contact feet.
Material inserts are clipped to their physical plates. Rarity does not colour
the sprites. The new Blade constructions are a heavy two-block waist, a toothed
ring, a compact dense disc, three broad open paddles, a disc with eccentric mass,
a continuous crescent scoop and opposed forked strike points. Fork's initial
shallow gaps were rejected during review; deeper recesses now stay readable in
its horizontal phase. No new part is a recolour of an existing silhouette.

Runtime exports live in `assets/top/parts/{blades,ratchets,bits}/`. Each new Blade
has a static `<id>.png` and an eight-column `<id>_spin.png`; each connector or foot
has one `<id>.png`. The art manifest at
`assets/top/parts/catalogue_002c5_2_art.json` stores source/runtime hashes, layers,
tags, timing, dimensions and pivots. Rendering remains nearest neighbour.

Normal exports read the editable master without recreating it:

```powershell
python tools/art/parts_catalogue_art.py
python tools/art/parts_catalogue_art.py --validate --report <external-QA-manifest.json>
python tools/art/parts_catalogue_art.py --validate --native-out <external-QA-temp-dir> --report <external-QA-manifest.json>
python tools/art/parts_catalogue_art.py --validate --review-metadata assets/data/parts_catalogue.json --review-out <external-QA-images-dir>
```

The native check opens and exports all twenty masters in the actual Aseprite
executable, verifies every RGBA pixel against the Python export and checks named
layers, tags and the contact pivot from Aseprite's own JSON. It uses
`TOPGAME_ASEPRITE`, PATH or the documented local installation. `--author` is an
explicit reconstruction operation for these twenty initial masters only; do not
use it after editing a master unless deliberately replacing the artist's edits.

Ratchet Blade offsets are +3 Ballast, 0 Flex, −2 Kickback, −1 Offset, +1 Flywheel
and +2 Scrap. `PartCatalog.visual_height(build)` supplies those values to the
workshop preview and combat renderer so the same collar fit survives mixed builds.
The outer mass can be eccentric while the locking hub and floor pivot stay aligned.

The review sheets show the complete old and new catalogue, then all eleven
Blades in material, grayscale and solid silhouette with native 48-pixel rotation
samples. These external images support shape review; actual 640×360 combat
captures remain the gameplay readability evidence.

Validation completed with Aseprite 1.3.18.6: all twenty masters opened and exported
with exact RGBA pixel parity, named layers, tags, timing and pivot intact. The
structural pass checked all 1,089 legal assemblies across 8,712 authored poses;
every Blade joined its collar and every Bit joined its socket (minimum overlaps
31 and 27 opaque pixels). This supplements visual review of the entire Blade
phase set and the seven actual combat capture scenarios at the fixed game scale.
The source masters remain editable; the historical sprites and masters retain
their original bytes.
