@echo off
REM Fast GUT suite (res://tests). Run from anywhere: tests\run.cmd
pushd "%~dp0\.."
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
REM A .cmd exits with the status of its LAST command, so a bare trailing `popd` (which always succeeds)
REM silently swallows a failing run and reports success to whatever called this. Capture first, restore
REM the directory, then re-raise. Same shape in tests_soak\run_soak.cmd and scripts\tools\validate.cmd.
set "_rc=%ERRORLEVEL%"
popd
exit /b %_rc%
