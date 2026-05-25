@echo off
pushd "%~dp0\.."
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
popd
