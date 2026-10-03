SPINNING METAL - TASK 002B - WINDOWS

Double-click SpinningMetal.exe. Windows x86_64; no Godot installation required.
Game data is embedded. Keep the license notices with distributed copies.

Keyboard: WASD/arrows steer, Space bursts, Shift brakes, Escape pauses.
Gamepad: left stick steers, bottom face bursts/confirms, shoulders/triggers
brake, Menu/Start pauses, east face goes back, D-pad/stick navigates menus.

Quick Duel preserves ordinary combat. The eight-encounter Run now has six
functional powers and Ammunition Waves in Slot 3 (24 small tops, cap 12).
Later rivals, arena events and bosses remain ordinary duel fixtures.
The last two power drafts offer two and one remaining unowned power.

Source branch: task-002b-first-broken-build, based on completed local Task002A.
Engine: Godot 4.7.2 stable, official Windows x86_64 release template.
See ../../TASK-002B.md for validation and ../../TASK-002B-PLAYTEST.md for human
feel checks. Physical-controller/human feel acceptance remains pending.
Package smoke victories are injected flow fixtures; bot combat is separate.

Rebuild with matching Godot export templates installed:
Godot --headless --path . --export-release "Windows Desktop"
