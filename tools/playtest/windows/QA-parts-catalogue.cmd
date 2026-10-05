@echo off
rem This grants parts only inside the external Task 002C.5.2 QA collection.
rem Production collection, preferences and Run diagnostic files stay separate.
if not defined TOPGAME_QA_ROOT set "TOPGAME_QA_ROOT=%~dp0..\..\..\..\GyroBrothers-QA"
for %%I in ("%TOPGAME_QA_ROOT%") do set "TOPGAME_QA_ROOT=%%~fI"
start "" "%~dp0..\..\..\builds\latest\SpinningMetal.exe" -- --qa-catalogue "--collection-path=%TOPGAME_QA_ROOT%\002C.5.2\temp\human_parts_collection.json"
