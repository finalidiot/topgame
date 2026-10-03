SPINNING METAL — GODOT SOURCE / TASK 002A

Open project.godot in Godot 4.7.2 (standard GDScript build), allow imports to finish,
and press F6/F5 to play. The project has no add-ons or external runtime dependencies.
The Windows package beside this source is ready to play without the editor.

Playable features
- Title, workshop, how-to-play, settings, pause, result and live battle HUD.
- 48 modular assemblies with live layered previews and six derived stats.
- Quick Duel with rematches, plus an eight-slot Run with a locked assembly.
- Six deterministic three-card drafts; all twelve power effects remain inactive.
- Fixed-camera isometric arena, steering, Burst, braking, AI, impacts and banks.
- RPM decay, wobble, spin-outs, collision-driven ring-outs, hit stop and screen shake.
- Original short sound cues; automatic build and settings persistence.

Controls
WASD/arrows steer; Space bursts; Shift brakes; Esc pauses; F11 toggles full screen.
Mouse or Tab/Enter operates menus. Combat gamepad inputs are experimental.

Source map
scripts/main.gd        Screen state, run progression, settings and save file
scripts/menus.gd       Native 640 x 360 menus and HUD
scripts/top_preview.gd Layered animated workshop/title top
scripts/parts.gd       Part descriptions and derived stats
scripts/battle.gd      Fixed-step world physics, AI, render order, combat outcomes
scripts/sound.gd       Sound pool, cue map and volume/mute
scripts/run_context.gd Locked Run state, committed results and stored draft choices
scripts/encounters.gd  Eight ordinary-duel fixtures with future encounter metadata
scripts/run_powers.gd  Twelve inactive power definitions, separate from physical parts
scripts/seed_utils.gd  Stable, versioned seed derivation for independent RNG streams
assets/               Production pixel layers, part sheets, arena and audio
tests/                Reproducible combat and complete run-flow checks

Rendering
640 x 360 native canvas, nearest filtering and integer viewport scaling.
Arena projection: screen_x = 320 + u - v; screen_y = 165 + (u + v) / 2 - height.
Top layers are composed from actual part sprites; the Blade cycles through eight
authored rotational phases. Foreground rails and body height control occlusion.
The playable arena adds guard rails around the two narrow physics gate mouths.
Original editable Aseprite art and visual-foundation notes remain in the earlier art package.

Historical Task 001 verification (see TASK-002A.md for current results)
Run the prototype harness only in a disposable copy: it overwrites QA/balance files.
Godot --headless --path . --script res://tests/test_prototype.gd
Godot --headless --path . --script res://tests/test_flow.gd
51 combat checks, 144 seeded bouts, 34 flow checks and 48-build UI checks passed.
Detailed combat observations are in QA.txt and tests/balance-results.json.
Normal exported Windows startup and a real Chrome/WebGL play loop were checked.
The integration capture mode uses a fixture for the victory screen; the separate
browser test plays a naturally resolved match with real keyboard input.

Exports
The presets use standard Windows x86_64 and single-threaded Web release templates.
Install matching 4.7.2 export templates in Godot to rebuild the packages.
Export paths are relative to this project and may be changed in the editor.
Web files must be served over HTTP/HTTPS; opening index.html as a file will not load Wasm.
The supplied Windows build is the easiest way to play locally.

Prototype scope and balance
One arena, one AI rival per bout and an eight-encounter Run are implemented.
Guard and Needle dominate a standardized central chase endurance test; that test
does not measure human win rates. Attack-driven ring-outs pass at both gates.
Further playtesting should tune gate-seeking AI, attack/endurance balance and controller feel.
Run rewards and drafting now work; their power effects and special encounters are
deferred. Shops, currencies and permanent unlocks remain outside the current scope.
The old three-fight gauntlet has been replaced. Quick Duel is retained separately.

Godot Engine and bundled third-party notices are in GODOT-LICENSE.txt and
GODOT-COPYRIGHT.txt. Original art, game scripts and sound cues were created for this project.
