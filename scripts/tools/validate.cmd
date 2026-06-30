@echo off
REM Headless content/wiring/navmesh validator — runs every pure validator (ContentValidator + ScanDisk[+ScanWiring]
REM + NavMeshAudit) in one shot and exits non-zero on real breakage. CI-gateable; no editor needed.
REM   validate.cmd            -> errors fail, warnings + navmesh issues are reported
REM   validate.cmd --strict   -> everything fails
REM   validate.cmd res://scenes/levels/MyLevel.tscn   -> audit specific level(s)
REM The "-- %*" forwards trailing args as Godot USER args (OS.get_cmdline_user_args()).
pushd "%~dp0\..\.."
godot --headless -s scripts/tools/validate_all.gd -- %*
popd
