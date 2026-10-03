SPINNING METAL - TASK 002C - WINDOWS

Double-click SpinningMetal.exe. Windows x86_64; no Godot installation required.
Game data is embedded. Keep the license notices with distributed copies.

Keyboard: WASD/arrows steer, Space bursts, Shift brakes, Escape pauses.
Gamepad: left stick steers, bottom face bursts/confirms, shoulders/triggers
brake, Menu/Start pauses, east face goes back, D-pad/stick navigates menus.

The eight-encounter Run has seven powers. Redline, Dead Centre and Afterimage
support Rank I, Rank II and one mutually exclusive Rank III mutation each.
Earned choices mix new powers and investments in owned powers. Seeded offers
do not guarantee a specific power or mutation. All starters may use all powers.

Practice-*.bat starts an isolated comparison with seven powers already owned.
Six launchers test individual mutations; Hybrid combines three defining paths.
These are human checkpoint fixtures, not earned pacing evidence. Rematch keeps
the practice preset. Combat uses ordinary physics and AI.
F2 hides/restores the HUD during combat for the five-second visual test.
Choices, pause and results restore visibility. Release controls after choices.

Source branch: task-002c-build-escalation, based on verified Task 002B.1
bdcc24e5c3717486eaabaa4e9bac67e1dcc351b2. No branch was merged.
Engine: Godot 4.7.2 stable, official Windows x86_64 release template.
See PLAYTEST.md for all nine human checkpoint questions and ../../TASK-002C.md
for exact implementation rules and evidence. Physical-controller/human feel
acceptance remains pending. The simple bot failed twelve complete seeded Runs;
practice setup does not prove normal-run balance or late-run reachability.
Package smoke victories are injected flow fixtures; bot combat is separate.

Rebuild with matching Godot export templates installed:
Godot --headless --path . --export-release "Windows Desktop"
