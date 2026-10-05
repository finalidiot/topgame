@echo off
rem Isolated Black Arrow human-review practice. No real collection/preferences opened.
rem Breaker/Smash carries the PAC apparition. Burst, then Burst again during overdrive.
if not defined TOPGAME_QA_ROOT set "TOPGAME_QA_ROOT=%~dp0..\..\..\..\GyroBrothers-QA"
for %%I in ("%TOPGAME_QA_ROOT%") do set "TOPGAME_QA_ROOT=%%~fI"
start "" "%~dp0..\..\..\builds\latest\SpinningMetal.exe" -- --practice=breakneck "--collection-path=%TOPGAME_QA_ROOT%\002C.5.2\temp\human_black_arrow_collection.json"
