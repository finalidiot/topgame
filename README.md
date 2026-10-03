# topgame

A Godot 4 spinning-top roguelite prototype, currently in early prototype development.

Core direction:

- fixed isometric gameplay camera
- modular Blade / Ratchet / Bit top construction
- physics-driven spinning-top combat
- roguelite run escalation
- Aseprite-heavy pixel-art presentation

Open `project.godot` with Godot 4.7.2, let assets import, and press **F5**.
For the ready-to-play Windows build, run
[`releases/windows/SpinningMetal.exe`](releases/windows/SpinningMetal.exe).
The executable includes the game data; no Godot installation is needed.
The executable is stored with Git LFS: after cloning, run `git lfs pull` if
needed, or use GitHub's Download raw file button on the executable page.
WASD/arrows steer, Space bursts, Shift brakes, and Esc pauses.
Gamepad: left stick steers, bottom face button bursts/confirms, either shoulder
or trigger brakes, and Menu/Start pauses. D-pad or stick navigates every menu;
the east face button goes back. Keyboard, mouse and gamepad coexist through
Godot input actions. Controller support is a core Task 002A requirement.

Editable pixel-art sources are in `assets/source-art/`. Existing prototype details
and validation notes are retained in `README.txt` and `QA.txt`.

Task 002B.1 opens a Run with three authored identities: **Breaker**
(SMASH/HIGH/FLAT), **Bastion** (GUARD/LOW/BALL), and **Vane**
(HOOK/MID/RUBBER). Choose a power before the first launch, then earn more
through meaningful combat. The visible Level bar leads to an immediate
mid-battle draft, a brief acquisition, and the exact same encounter.

Task 002C adds repeated investment: **Redline**, **Dead Centre** and
**Afterimage** progress from acquisition to Rank II, then a choice between
two mutually exclusive behavioural mutations. Owned powers can return in
the draft alongside new powers. The seven functional powers are Impact Wake,
Second Wind, Redline, Iron Comet, Dead Centre, Afterimage, and Chain Impact.
All powers are legal for every starter. The physical assembly stays locked
through the eight encounters. There are thirteen available investments;
seven owned powers are supported and the HUD has eight slots. The Level bar
becomes **FULL BUILD / MAX** only when every available investment is earned.
XP awards, early level costs and enemy schedules are preserved. Starter handling profiles make
aggression, centre control, and efficient mobility more pronounced in Runs.
Custom assemblies and Quick Duel retain the original part physics.

Slot 3 is **Ammunition Waves**: 24 lightweight small tops in waves of 6/8/10,
with at most 12 active. XP drafts freeze tops, RPM, power cooldowns and wave
scheduling, and the new ability is usable in that same wave. The other seven
slots retain ordinary duel fixtures. Further powers, specialist AI, bosses,
meta progression remain deferred.

The Garage is preserved. Select **CUSTOM ASSEMBLY RUN** below the three
starters for an advanced custom Run. D-pad or left/right chooses a starter;
Confirm selects. Menus require a fresh Confirm and a centred stick after a
transition. Release steering, Burst and brake after a draft to rearm combat.

Power cards now have 64px authored animations and editable Aseprite production
masters. Export edited art with `python tools/build_power_art.py` and
`python tools/build_starter_art.py`; export the new escalation masters with
`python tools/build_escalation_art.py`. Ordinary exports never overwrite artist
edits. See [TASK-002B1.md](TASK-002B1.md) for implementation, measured pacing,
controller results, acceptance findings and limitations. For the current
escalation rules, source-art/audio additions, tests and outstanding human
checkpoint, see [TASK-002C.md](TASK-002C.md) and
[TASK-002C-PLAYTEST.md](TASK-002C-PLAYTEST.md). Optional targeted build practice
uses `SpinningMetal.exe -- --practice=runaway` (also breakneck, bulwark,
counterweight, ghost_circuit, slipstream, hybrid). Practice presets equip
seven powers independently of ordinary Run randomness. Press F2 in combat
to hide/show the HUD for build recognition; pause restores it. Historical Task 002B
notes remain in [TASK-002B.md](TASK-002B.md).

Run automated suites with Godot 4.7.2:

```text
Godot --headless --path . --editor --import
Godot --headless --path . --script res://tests/test_flow.gd
Godot --headless --path . --script res://tests/test_run_context.gd
Godot --headless --path . --script res://tests/test_combat_architecture.gd
Godot --headless --path . --script res://tests/test_menus.gd
Godot --headless --path . --script res://tests/test_controller.gd
Godot --headless --path . --script res://tests/test_powers.gd
Godot --headless --path . --script res://tests/test_swarm.gd
Godot --headless --path . --script res://tests/test_presentation.gd
Godot --headless --path . --script res://tests/test_progression.gd
Godot --headless --path . --script res://tests/test_starters.gd
Godot --headless --path . --script res://tests/test_starter_physics.gd
Godot --headless --path . --script res://tests/test_xp_observer.gd
Godot --headless --path . --script res://tests/test_ramp_integration.gd
Godot --headless --path . --script res://tests/test_card_assets.gd
Godot --headless --path . --script res://tests/test_escalation_progression.gd
Godot --headless --path . --script res://tests/test_escalation_physics.gd
Godot --headless --path . --script res://tests/test_escalation_assets.gd
Godot --headless --path . --script res://tests/test_escalation_integration.gd
Godot --headless --path . --script res://tests/test_escalation_completion.gd
Godot --headless --path . --script res://tests/test_escalation_visual_playthrough.gd
```

Run `tests/test_prototype.gd` only in a disposable copy: the preserved baseline
harness overwrites `QA.txt` and `tests/balance-results.json`. Those tracked files
remain historical Task 001 evidence. For rendered integration captures, launch
with `-- --smoke-test --capture-dir=<absolute-directory>`; victories in that smoke
loop are explicitly injected flow fixtures, not evidence of played Run balance.

For measured seeded bot combat without injected victories, run
`tests/test_ramp_playthrough.gd` with `-- --report=<absolute-json-path>`.
It measures active combat seconds, excluding launch and choices. This is
simulation evidence, separate from human/controller feel acceptance.
