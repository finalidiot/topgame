# 003A physical packet sources

The original packet is a small opaque matte laminate hobby pouch: a warm paper
body, pale printed label, heat-crimped top and bottom margins, four placed folds,
an easy-tear notch and a independently moving sealed strip. The Reclaimed Packet
uses muted olive packaging; components retain their accepted physical pixels.
There are no reward silhouettes, pseudo-mechanical decorations or AI images in
the packet source. Real catalogue sprites are supplied by `packet_view.gd`.

`assets/source-art/shop_003a/packet.aseprite` and `reclaimed_packet.aseprite`
contain thirteen individually authored native 96×96 poses each, on six named
editable layers. Their fixed contact pivot is `(48,86)`. The separate
`reveal_mat.aseprite` is 272×134 with three editable surface/lip/wear layers and a
contact pivot at `(136,124)`. Runtime PNGs and metadata are in
`assets/ui/shop_003a/`.

| Native animation tag | Frames (zero based) | Frame durations, ms |
| --- | --- | --- |
| SEALED | 0 | 500 |
| CRINKLE | 1–3 | 100,90,100 |
| TEAR_START | 4–5 | 120,120 |
| TEAR_OPEN | 6–8 | 110,110,180 |
| SPILL | 9–11 | 130,130,180 |
| EMPTY_PACKET | 12 | 1000 |

Normal `python tools/art/packet_art.py` exports saved artist edits. `--author`
explicitly reconstructs and overwrites these three masters from the original
pixel recipe; it is not the normal export command. `--check` reads production
sources without writing them and compares runtime PNG pixels and JSON with a
real Aseprite CLI export, named layers, frame tags, pivot slices and timings.
`--report` and `--preview` accept external QA destinations. Pixel output uses
nearest filtering. The preview includes both exact 1× and integer 2× inspection.

The packet choreography reads exported frame timings, then adds small position
motion. Land/crinkle wait for a deliberate Tear action; fast opening and skipping
use the same persisted receipt. The source poses never encode a particular part
or rarity. Results and real part motion belong to the production view.

The eight original finite foley cues are in `assets/audio/shop_003a/`: land,
crinkle, tear, spill, clink, new, rare and recycle. `packet_score.json` contains
editable grain timings, amplitudes and physical mode frequencies, with fixed
offline excitation seeds. `tools/audio/compose_packet.py` renders the saved score
to exact mono 32 kHz, signed 16-bit PCM. It uses NumPy; use the bundled workspace
Python when the default interpreter lacks it. `--author` reconstructs the score;
`--verify-only` verifies frozen PCM, file hashes, metrics, non-clipping and finite
endpoints without modifying assets. `--audition` accepts an external joined WAV.
The manifest records each exact PCM grid/hash and gain measurements. Import
settings preserve PCM with no normalization, trimming, looping or compression.

The accepted eight-channel SFX pool handles these cues with short cooldowns and
restrained gains. A rare part gets two short damped metal strikes. Tear and rare
cues briefly duck the existing Music bus; they do not replace the accepted C6
score or restart its synchronized transport. Shop uses the workshop arrangement.

`tests/test_packet_art_audio.gd` inspects actual Godot imports and mixes actual
PCM. It checks the frame grid, all required tags, distinct poses, native pivots,
opaque sealed body, cue hashes/grids, unclipped audio, production dispatch,
cooldowns, settings isolation and the continuing synchronized workshop cursor.
It opens no save and starts no native audio device. Native review remains a
separate input-driven game capture.
