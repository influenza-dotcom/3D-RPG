extends SceneTree
## QA probe: boot the MAIN level bare (no player), hang the SHIPPED post-process ColorRect over it, and save one
## PNG per ordered-dither (Bayer) setting so the look can be judged by eye. The day_night_shots / menu_qa_shots
## idiom.
##
## ⭐WHY THIS EXISTS AT ALL: headless NEVER COMPILES SHADERS, so a broken .gdshader loads clean and passes every
## GUT test in the suite — and no unit test can see a dither pattern even when the shader IS correct. The only
## honest verification of post_process.gdshader's Bayer matrix is a rendered frame, which means a WINDOWED run.
## The source-text pins in tests/test_smoke.gd cover "the uniforms still exist"; this covers "it looks right".
##
## Run (from the project root — note: NO --headless):
##   & "C:\Users\dalla\bin\godot.cmd" --path . -s scripts/tools/dither_qa_shots.gd -- --shots-dir=<dir>
## Omit --shots-dir to write user://dither_qa_shots. Expect a ~15 s windowed run.
##
## Console noise is expected: the level boots without a Player, so player-group lookups miss (null-guarded).
##
## ⭐A `-s` script COMPILES BEFORE AUTOLOADS REGISTER, so WorldClock is resolved from /root at runtime — naming it
## as an identifier here is a hard compile fail (the house harness gotcha).

const LEVEL := "res://scenes/levels/trenchboom_test_level.tscn"
## The player's post-process overlay. We lift the ColorRect out of it rather than rebuilding a material by hand so
## the shots are of the AUTHORED values (color_steps, render_scale, grain) and can never drift from what ships.
const UI_SCENE := "res://scenes/player/ui.tscn"

## Dusk: the sky gradient is at its widest and smoothest here, which is exactly where an 8-bit frame BANDS and
## therefore where an ordered dither has the most to do. A flat noon sky would under-sell both the bug and the fix.
const TIME_OF_DAY := 0.7

## One shot per row: [name, bayer_order, dither_strength, color_steps].
##  - The first two are the honest BEFORE/AFTER at the shipped palette (16 steps). "off" is not a strawman: the
##    dither this replaced was a mathematical no-op, so `off` IS what the game rendered before this change.
##  - The 2x2/4x4/8x8 sweep is the matrix-size art choice (`bayer_order` in ui.tscn).
##  - The last pair drops the palette to 6 steps, where the pattern is unmistakable — that is the shot to look at
##    when deciding whether the matrix itself is right, because at 16 steps a correct dither is *meant* to be subtle.
const SHOTS := [
	["0_off_steps16", 0, 0.0, 16],
	["1_bayer8x8_steps16", 3, 1.0, 16],
	["2_bayer2x2_steps16", 1, 1.0, 16],
	["3_bayer4x4_steps16", 2, 1.0, 16],
	["4_off_steps6", 0, 0.0, 6],
	["5_bayer8x8_steps6", 3, 1.0, 6],
]

## The volumetric fog is temporally reprojected, so the FIRST frame after the clock jump is not the settled image
## (day_night_shots.gd learned this the hard way — at 45 frames a noon shot still rendered as night). Paid once:
## the dither variants that follow only change the post pass, which converges instantly.
const SETTLE_FRAMES := 150
const BETWEEN_FRAMES := 4      ## a couple of frames per variant so the changed uniform is definitely on screen

var _frame := 0
var _shot := 0
var _wait := 0        ## frames left before the next action (settle, then the apply->capture gap)
var _armed := false   ## true once _apply has run for the CURRENT shot, so the next expiry captures it
var _dir := "user://dither_qa_shots"
var _mat: ShaderMaterial = null

# Per shot the loop is strictly: wait -> apply the uniforms -> wait -> capture. Splitting apply and capture
# across frames is the point: a uniform written this frame is not on screen until the next one, and a probe
# that shoots in the same frame silently captures the PREVIOUS variant — the failure mode where every image
# in the set looks correct but is labelled one row off.
func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_boot()
		_wait = SETTLE_FRAMES
		return false
	if _shot >= SHOTS.size():
		quit()
		return true
	if _wait > 0:
		_wait -= 1
		return false
	if not _armed:
		_apply(_shot)
		_armed = true
		_wait = BETWEEN_FRAMES
		return false
	_capture(_shot)
	_shot += 1
	_armed = false
	_wait = BETWEEN_FRAMES
	return false


func _boot() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--shots-dir="):
			_dir = String(a).trim_prefix("--shots-dir=")
	DirAccess.make_dir_recursive_absolute(_dir)

	var clock: Node = root.get_node_or_null("/root/WorldClock")
	if clock != null:
		clock.set(&"day_length_seconds", 0.0)          # freeze, so every shot is the same lighting
		clock.call(&"set_time_of_day", TIME_OF_DAY)

	var lvl: Node = (load(LEVEL) as PackedScene).instantiate()
	root.add_child(lvl)
	var spawn := lvl.find_child("PlayerSpawn", true, false)
	var eye: Vector3 = (spawn.global_position if spawn is Node3D else Vector3(0, 3, 0)) + Vector3(0, 1.6, 0)
	var cam := Camera3D.new()
	root.add_child(cam)
	# Aim ABOVE the building cluster: sky fills the upper frame (the smooth gradient the dither is judged on) with
	# lit facades below it (the textured half, where a dither must NOT turn into visible crosshatch).
	cam.look_at_from_position(eye, Vector3(-29.0, 12.0, -15.0))
	cam.current = true

	# Lift the SHIPPED ColorRect out of ui.tscn. `instantiate()` does not run `_ready` until the node enters the
	# tree, so reparenting the rect and freeing the rest never runs ui.gd (which would go looking for a Player).
	var ui: Node = (load(UI_SCENE) as PackedScene).instantiate()
	var rect := ui.get_node_or_null("ColorRect") as ColorRect
	if rect == null:
		push_error("dither_qa_shots: ui.tscn has no ColorRect — the post-process overlay moved; fix this probe.")
		quit(1)
		return
	ui.remove_child(rect)
	ui.free()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(rect)
	_mat = rect.material as ShaderMaterial
	if _mat == null:
		push_error("dither_qa_shots: the ColorRect carries no ShaderMaterial — nothing to shoot.")
		quit(1)


func _apply(i: int) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("bayer_order", int(SHOTS[i][1]))
	_mat.set_shader_parameter("dither_strength", float(SHOTS[i][2]))
	_mat.set_shader_parameter("color_steps", int(SHOTS[i][3]))
	# Grain is NOISE, and noise over a dither is exactly what makes a dither impossible to judge. Off for every
	# shot — this probe answers "is the matrix right", not "does the shipped frame look nice".
	_mat.set_shader_parameter("grain_amount", 0.0)


func _capture(i: int) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path: String = _dir.path_join(String(SHOTS[i][0]) + ".png")
	img.save_png(path)
	print("dither_qa_shots: wrote %s  (bayer_order=%d strength=%.2f color_steps=%d)" % [
		path, int(SHOTS[i][1]), float(SHOTS[i][2]), int(SHOTS[i][3])])
