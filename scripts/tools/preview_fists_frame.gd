extends SceneTree

## Fists-frame probe — renders the unarmed GUARD framing (and any candidate retunes) straight to PNGs so pose
## changes are judged by SIGHT instead of blind number-nudging. This is how the 2026-08-05 guard was found:
## the readable "fists close to your face" pose is shoulders DROPPED + a STEEP rig tilt (foreshortening), which
## no amount of nudging the flat pose toward the lens ever produced.
##
##   godot --path <absolute project path> -s scripts/tools/preview_fists_frame.gd
##
## WINDOWED on purpose (the bake_item_icons.gd idiom): rendering needs a real renderer, so do NOT pass
## --headless — a window flashes for a couple of seconds, one PNG per CONFIGS row lands in OUT_DIR, then it
## quits. The red cross marks the exact crosshair position. -s runs before autoloads, so everything is
## load()ed lazily and the Player's values are MIRRORED below rather than read off player.gd (which cannot
## compile without autoloads in -s mode) — keep them in step with Player.tscn / player.gd when retuning.

const OUT_DIR := "res://.godot/"  ## PNGs land next to the import cache — throwaway output, never committed

# Mirror of the shipped baseline: Player.tscn overrides first, player.gd defaults for the rest.
const CAM_FOV := 75.0                             # Settings.fov default
const ARM_SCALE := 0.68                           # Player.tscn fp_arm_scale
const ARM_OFFSET := Vector3(0, -0.885, -0.35)     # Player.tscn fp_arm_offset (the carry rest)
const ARM_ROT := Vector3(0, 180, 0)               # Player.tscn fp_arm_rotation

# Candidate guard configs: [name, nudge, tilt_deg, scale_mult, spread]. First row = the SHIPPED guard;
# add rows to bracket a retune, run, and eyeball the PNGs side by side.
const CONFIGS := [
	["shipped", Vector3(0, -0.13, 0.12), 45.0, 1.15, 0.28],
]

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame  # let the root window report in-tree first (see bake_item_icons.gd)
	if DisplayServer.get_name() == "headless":
		push_error("preview_fists_frame: needs a renderer — run WITHOUT --headless.")
		quit(1)
		return
	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	root.add_child(cam)
	cam.make_current()
	# Flat ambient fill, roughly the gun pass's view-model environment, so the arms read as shapes.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.91, 0.95)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var Swap = load("res://scripts/components/body_model_swap.gd")
	var rig = Swap.new()
	rig.casts_shadow = false
	rig.animate_arms = false
	rig.arm_model = load("res://assets/models/arm.blend")
	rig.arm_rotation = ARM_ROT
	cam.add_child(rig)
	# Crosshair marker at the exact screen centre — the project's stretch makes the ROOT VIEWPORT smaller than
	# the OS window, so centre on the viewport, not the window.
	var cl := CanvasLayer.new()
	root.add_child(cl)
	var sz: Vector2 = (root as Viewport).get_visible_rect().size
	for dim in [Vector2(24, 2), Vector2(2, 24)]:
		var r := ColorRect.new()
		r.color = Color.RED
		r.size = dim
		r.position = sz / 2.0 - dim / 2.0
		cl.add_child(r)
	for cfg in CONFIGS:
		rig.position = ARM_OFFSET + (cfg[1] as Vector3)
		rig.rotation_degrees = Vector3(cfg[2] as float, 0, 0)
		rig.arm_scale = ARM_SCALE * (cfg[3] as float)
		rig.arm_position = Vector3(cfg[4] as float, 0.0, 0.0)
		for i in 6:
			await process_frame
		var img := root.get_texture().get_image()
		var path := OUT_DIR + "fists_" + String(cfg[0]) + ".png"
		img.save_png(path)
		print("preview_fists_frame: saved ", ProjectSettings.globalize_path(path))
	quit(0)
