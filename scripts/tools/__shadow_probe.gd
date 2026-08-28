extends SceneTree
## THROWAWAY QA probe: boot the MAIN level bare, freeze the clock at several times of day, and shoot the
## street + ground from a few angles so the sun/moon SHADOW quality can be judged by eye (the day_night_shots
## idiom). WINDOWED on purpose — headless never compiles shaders and never renders a shadow map.
##
## Run (from the project root):
##   & "C:\Users\dalla\bin\godot.cmd" --path . -s scripts/tools/__shadow_probe.gd -- --shots-dir=<dir>
##
## ⭐A `-s` script COMPILES BEFORE AUTOLOADS REGISTER — WorldClock is resolved from /root at runtime.

const LEVEL := "res://scenes/levels/trenchboom_test_level.tscn"
## Sun pitch per time t (drive_sun_rotation): -elev(t) * 58°. Low stops (0.30, 0.80) are the grazing-angle
## regime where directional shadow texels stretch; 0.5 noon is the steepest; 0.0 is the 17° authored moon.
## Dusk moved 0.72 -> 0.80 for the main level's authored daylight window (dusk_time 0.8333): 0.72 now renders
## a -33° mid-afternoon sun, while 0.80 is the ~-10° grazing regime this probe exists to stress.
const TIMES := [["t000_midnight", 0.0], ["t030_morning", 0.3], ["t050_noon", 0.5], ["t080_dusk", 0.8]]
const SETTLE_FRAMES := 150     ## shadows render immediately; the settle is for volumetric fog reprojection
const FIRST_EXTRA := 90        ## shader compiles + StarSky repaint on first frames

var _frame := 0
var _shot := 0
var _wait := 0
var _dir := "user://shadow_probe"
var _clock: Node = null
var _cam: Camera3D = null
var _sun: DirectionalLight3D = null
var _eye := Vector3.ZERO
var _shots: Array = []   ## [name, time_of_day, cam_pos, cam_target, fov]

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		for a in OS.get_cmdline_user_args():
			if String(a).begins_with("--shots-dir="):
				_dir = String(a).trim_prefix("--shots-dir=")
		DirAccess.make_dir_recursive_absolute(_dir)
		_clock = root.get_node("/root/WorldClock")
		_clock.set(&"day_length_seconds", 0.0)
		var lvl: Node = (load(LEVEL) as PackedScene).instantiate()
		root.add_child(lvl)
		_sun = lvl.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
		var spawn := lvl.find_child("PlayerSpawn", true, false)
		_eye = (spawn.global_position if spawn is Node3D else Vector3(0, 3, 0)) + Vector3(0, 1.6, 0)
		_cam = Camera3D.new()
		root.add_child(_cam)
		_cam.current = true
		# Three angles per time stop: the known-good street composition, a ground-level look at the street
		# floor where building shadow edges lie, and a narrow-FOV zoom on the near ground for texel detail.
		var cluster := Vector3(-29.0, 0.0, -15.0)
		var toward := (cluster - Vector3(_eye.x, 0.0, _eye.z))
		for t in TIMES:
			var base := Vector3(_eye.x, 0.0, _eye.z)
			_shots.append([String(t[0]) + "_street", t[1], _eye, Vector3(-29.0, 4.0, -15.0), 75.0])
			_shots.append([String(t[0]) + "_ground", t[1], _eye, base + toward * 0.45 + Vector3(0, 0.05, 0), 75.0])
			_shots.append([String(t[0]) + "_zoom", t[1], _eye, base + toward * 0.22 + Vector3(0, 0.05, 0), 35.0])
		_apply(0)
		_wait = SETTLE_FRAMES + FIRST_EXTRA
		return false
	if _shot >= _shots.size():
		quit()
		return true
	_wait -= 1
	if _wait > 0:
		return false
	var img := root.get_viewport().get_texture().get_image()
	var path: String = _dir.path_join(String(_shots[_shot][0]) + ".png")
	img.save_png(path)
	var rot := _sun.global_rotation_degrees if _sun != null else Vector3.ZERO
	print("shadow_probe: wrote ", path, "  sun_rot=", rot)
	_shot += 1
	if _shot < _shots.size():
		var prev_t: float = _shots[_shot - 1][1]
		_apply(_shot)
		# A time-of-day jump needs the full fog settle; a camera-only move needs far less.
		_wait = SETTLE_FRAMES if not is_equal_approx(prev_t, float(_shots[_shot][1])) else 20
	return false

func _apply(i: int) -> void:
	_clock.call(&"set_time_of_day", _shots[i][1])
	_cam.fov = _shots[i][4]
	_cam.look_at_from_position(_shots[i][2], _shots[i][3])
