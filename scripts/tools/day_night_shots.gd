extends SceneTree
## QA probe: boot the MAIN level bare (no player), freeze the WorldClock at key times of day, and save a PNG
## per stop so DayNightSky's lighting can be judged by eye without a playthrough (the menu_qa_shots idiom).
## WINDOWED on purpose — headless never compiles shaders, so a headless shot would show fallback materials.
##
## Run (from the project root):
##   & "C:\Users\dalla\bin\godot.cmd" --path . -s scripts/tools/day_night_shots.gd -- --shots-dir=<dir>
## Omit --shots-dir to write user://day_night_shots. Each stop waits ~45 frames before shooting so the
## volumetric fog's temporal accumulation settles on the new lighting; expect a ~20 s windowed run.
##
## Console noise is expected: the level boots without a Player, so player-group lookups miss (null-guarded).
##
## ⭐A `-s` script COMPILES BEFORE AUTOLOADS REGISTER, so WorldClock must be resolved from /root at runtime —
## naming it as an identifier here is a hard compile fail (the house harness gotcha).

const LEVEL := "res://scenes/levels/trenchboom_test_level.tscn"
## time_of_day stops: midnight (deep night), a risen morning sun, noon peak, golden-hour dusk. Dawn 0.25 itself
## is deliberately NOT a stop — the sun sits exactly ON the horizon there (day factor 0), which shoots like night.
const STOPS := [["0_midnight", 0.0], ["1_morning", 0.3], ["2_noon", 0.5], ["3_dusk", 0.7]]
## ⭐PER-STOP SETTLE, AND IT MUST BE GENEROUS. This world's scene fill is VOLUMETRIC FOG, which is temporally
## reprojected — it converges over time rather than per frame. Jumping the clock straight from midnight to noon
## is the largest lighting change the level can make, and at 45 frames the noon shot still rendered essentially
## as night: the probe LIED about a correct implementation (the live sun/ambient values were exactly right).
## If you shorten this, re-verify against a stop whose previous stop was much darker.
const SETTLE_FRAMES := 150
const FIRST_EXTRA := 60        ## extra frames before the first shot: shader compiles + StarSky repaint

var _frame := 0
var _stop := 0
var _wait := 0
var _dir := "user://day_night_shots"
var _clock: Node = null

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		for a in OS.get_cmdline_user_args():
			if String(a).begins_with("--shots-dir="):
				_dir = String(a).trim_prefix("--shots-dir=")
		DirAccess.make_dir_recursive_absolute(_dir)
		_clock = root.get_node("/root/WorldClock")
		_clock.set(&"day_length_seconds", 0.0)  # freeze: each stop holds its exact time while fog settles
		var lvl: Node = (load(LEVEL) as PackedScene).instantiate()
		root.add_child(lvl)
		var spawn := lvl.find_child("PlayerSpawn", true, false)
		var eye: Vector3 = (spawn.global_position if spawn is Node3D else Vector3(0, 3, 0)) + Vector3(0, 1.6, 0)
		var cam := Camera3D.new()
		root.add_child(cam)
		# Aim down the street toward the building cluster (map metres -29,-15) so the shot has sky + sunlit
		# facades + a lamp fixture in frame — the three things the cycle drives.
		cam.look_at_from_position(eye, Vector3(-29.0, 4.0, -15.0))
		cam.current = true
		_clock.call(&"set_time_of_day", STOPS[_stop][1])
		_wait = SETTLE_FRAMES + FIRST_EXTRA
		return false
	if _stop >= STOPS.size():
		quit()
		return true
	_wait -= 1
	if _wait > 0:
		return false
	var img := root.get_viewport().get_texture().get_image()
	var path: String = _dir.path_join(STOPS[_stop][0] + ".png")
	img.save_png(path)
	print("day_night_shots: wrote ", path)
	_stop += 1
	if _stop < STOPS.size():
		_clock.call(&"set_time_of_day", STOPS[_stop][1])
		_wait = SETTLE_FRAMES
	return false
