@echo off
REM Opt-in SOAK suite — boots a real level and runs SoakHarness (real wandering NPCs) headless to catch
REM stranded-on-bad-bake NPCs and node/orphan leaks. Kept SEPARATE from tests/run.cmd so the heavy harness
REM never runs in the default fast suite (.gutconfig points at res://tests; this points at res://tests_soak).
REM Run from anywhere: tests_soak\run_soak.cmd
pushd "%~dp0\.."
REM -gconfig points at the soak-only config so the default res://.gutconfig.json (dirs=res://tests) is NOT loaded
REM — otherwise GUT would run the whole fast suite too.
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=res://tests_soak/soak.gutconfig.json -gexit
popd
