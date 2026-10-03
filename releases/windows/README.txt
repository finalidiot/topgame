SPINNING METAL - TASK 002A - WINDOWS

Double-click SpinningMetal.exe. Windows x86_64; no Godot installation required.
Game data is embedded in the executable. Keep the license notices with copies
of this distribution.

Keyboard: WASD/arrows steer, Space bursts, Shift brakes, Escape pauses.
Gamepad: left stick steers, bottom face bursts/confirms, shoulders/triggers
brake, Menu/Start pauses, east face goes back, D-pad/stick navigates menus.
Mouse and keyboard menu controls are also available.

Quick Duel and the eight-encounter Run are playable. Run Powers can be drafted
and collected, but their combat effects and special encounters are not active
in Task 002A.

Gameplay source: 9467e5b383714ee1fda84cb6346cbb8018917e0c
Engine: Godot 4.7.2 stable, official Windows x86_64 release template.
Export preset: Windows Desktop, embedded game data.

Package validation: the executable launched by itself in a separate folder,
rendered live combat and menus, and completed the eight-slot/six-draft smoke
flow with exit code 0. Run victories in that smoke loop are injected fixtures.

Rebuild from the repository with matching Godot export templates installed:
Godot --headless --path . --export-release "Windows Desktop"
