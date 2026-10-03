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

Task 002B adds six functional Run Powers: Impact Wake, Second Wind, Redline,
Iron Comet, Afterimage, and Chain Impact. Your physical assembly stays locked
through the eight-slot Run. Six rewards offer up to three unowned powers;
the last two offers contain two and one card as this prototype pool is exhausted.
A short acquisition beat leads straight into the next launch.

Slot 3 is **Ammunition Waves**: 24 lightweight small tops in waves of 6/8/10,
with at most 12 active. Throw them into each other, use pressure waves to clear
space, and build bounded knockout cascades. The other seven slots retain ordinary
duel fixtures. Specialist AI, bosses, arena events and the other six catalogue
powers remain deferred. Quick Duel retains ordinary no-power combat.

See [TASK-002B.md](TASK-002B.md) for the implementation and measured validation,
[TASK-002B-PLAYTEST.md](TASK-002B-PLAYTEST.md) for human acceptance checks, and
[TASK-002A.md](TASK-002A.md) for the preserved architectural history.

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
```

Run `tests/test_prototype.gd` only in a disposable copy: the preserved baseline
harness overwrites `QA.txt` and `tests/balance-results.json`. Those tracked files
remain historical Task 001 evidence. For rendered integration captures, launch
with `-- --smoke-test --capture-dir=<absolute-directory>`; victories in that smoke
loop are explicitly injected flow fixtures, not evidence of played Run balance.
