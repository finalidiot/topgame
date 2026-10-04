SPINNING METAL — GODOT SOURCE / TASK 003A

Open project.godot in Godot 4.7.2 (standard GDScript), allow imports to finish,
and press F6/F5. No add-ons or external runtime dependencies are required.
Run releases/windows/SpinningMetal.exe without the editor; game data is embedded.
Task report, save/API details, validation and checkpoint limitations: TASK-003A.md.

First machine and permanent collection
- A new collection owns nothing. BEGIN opens Breaker / Bastion / Vane inspection.
- Select, then confirm separately. Only that machine's Blade, Ratchet and Bit
  become permanently owned. The ownership moment opens the Workshop.
- The wider catalogue stays visible: NOT OWNED parts cannot be equipped.
- Launch uses your currently equipped owned assembly. Later Runs go directly to
  their starting power draft, without another first-starter selection.
- Permanent ownership/equipment survives deaths, restarts and application reload.
- Run powers, ranks, mutations, XP, RPM and director state reset for each Run.
- Quick Duel and the clearly labeled Practice Garage use separate test builds;
  practice never grants parts or changes collection equipment.

Playable Run
Launch once into continuous fixed-camera isometric combat. The seeded pressure
Director admits rival roles, dynamic swarms, elites and boss tops into the same
arena. Ordinary wins never return to results or relaunch the player. Live XP
pauses for power upgrades/ranks/mutations and resumes the same physical machine.
The RPM economy charges real costs and permits bounded recovery through credited
combat. Redline, Dead Centre and Afterimage use authored signature visual progress.
Only player defeat ends the Run. There is no fixed encounter or survival limit.

Controls
WASD/arrows steer; Space bursts; Shift brakes; Esc pauses; F11 toggles fullscreen.
Mouse or Tab/Enter operates menus. Gamepad: left stick steers; bottom face
bursts/confirms; shoulders/triggers brake; Menu/Start pauses; east face goes back;
D-pad/stick moves focus. Keyboard and gamepad share named Godot InputMap actions.
New collection UI has automated synthetic controller/keyboard/mouse coverage;
physical controller and subjective human acceptance remain pending.

Save and deliberate development reset
Collection: user://collection.json (schema 1), with a previous-valid .bak.
Settings and legacy practice build: user://prototype.cfg, preserved independently.
Existing prototype preferences do not confer ownership; without a collection,
BEGIN starts the ceremony. Damaged saves never grant the catalogue automatically.
An unrecoverable/future-version file is preserved and blocks collection writes.

For a fresh isolated review save, in PowerShell from releases/windows:
  .\SpinningMetal.exe -- --collection-path=user://review/003a.json
To deliberately reset that isolated collection only:
  .\SpinningMetal.exe -- --collection-path=user://review/003a.json --reset-collection
To deliberately reset the normal collection:
  .\SpinningMetal.exe -- --reset-collection
This deletes only collection.json and its named backup/staging files, not settings.
Close other game instances first. The historical first choice cannot be changed
through normal UI. No shop, packs, currency economy or boss drops exist yet.

Source map
scripts/main.gd             Screen flow, Run integration and preferences
scripts/collection_save.gd  Permanent stable-ID ownership and safe persistence
scripts/menus.gd            Native 640x360 menus, owned Workshop and battle HUD
scripts/top_preview.gd      Layered assembly preview and motion identity
scripts/parts.gd            Stable part catalogue and physical stats
scripts/starters.gd         Exact starter assemblies and handling compatibility
scripts/run_context.gd      Temporary power/XP/draft commitments
scripts/continuous_run.gd   One-launch lifecycle and enemy admissions
scripts/threat_director.gd  Seeded pressure tiers, budgets and bounded populations
scripts/spin_economy.gd     Source-aware RPM costs, earned gains and telemetry
scripts/battle.gd           Fixed-step physics, rendering and combat outcomes
scripts/power_runtime.gd    Actual powers, mutations and combat attribution
scripts/signature_visuals.gd / power_visuals.gd  Authored visual composition
scripts/sound.gd            Bounded cue pool, volume and mute
assets/source-art/          Editable original Aseprite masters and art handoffs
tests/                     Regression suites and isolated collection/full-flow QA

Validation
  Godot --headless --path . --script res://tests/test_collection_save.gd
  Godot --headless --path . --script res://tests/test_collection_flow.gd
  Godot --headless --path . --script res://tests/test_collection_ui.gd
All accepted relevant suites are retained; see TASK-003A.md for the final run.
The old prototype/balance harness writes artifacts: use a disposable copy for it.

Rendering and exports
640x360 native canvas, nearest filtering, integer scaling, fixed isometric camera.
Matching 4.7.2 export templates rebuild the Windows x86_64 single-file checkpoint.
Web preset is retained but was not rebuilt in this task. Web exports need HTTP.
Original arena, top, power Aseprite masters and previous task reports are retained.
Godot and third-party notices: GODOT-LICENSE.txt and GODOT-COPYRIGHT.txt.
