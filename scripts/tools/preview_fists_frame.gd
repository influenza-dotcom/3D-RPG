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
## load()ed lazily — and first_person_body.gd can't be load()ed even lazily (its typed `host: Player` pulls in
## player.gd, which doesn't compile without autoloads). So the shipped baseline is read off the authored
## sources as TEXT instead: Player.tscn's FirstPersonBody overrides first, the script's @export defaults for
## whatever the scene doesn't author (.tscn property values are VariantWriter syntax, so str_to_var parses
## them directly). A retune shows up here on the next run — nothing is mirrored, nothing to keep in step.

const OUT_DIR := "res://.godot/"  ## PNGs land next to the import cache — throwaway output, never committed

## The authoritative pose sources (see header). If the FP rig moves homes again, repoint these.
const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const FP_NODE_HEADER := "[node name=\"FirstPersonBody\""
const FP_SCRIPT := "res://scripts/player/first_person_body.gd"
## The camera's rest-FOV chain (what Settings.fov boots from): the tuning .tres if it authors default_fov,
## else the CameraSettings script default — then user://settings.cfg's saved fov on top (see _run).
const CAM_TUNING := "res://resources/tuning/CameraSettings.tres"
const CAM_TUNING_SCRIPT := "res://resources/tuning/CameraSettings.gd"

# Candidate guard configs: [name, nudge, tilt_deg, scale_mult, spread] — null in any slot means "the AUTHORED
# value", read live from the sources above, so the first row IS the shipped guard by construction. To bracket
# a retune, add rows overriding just the knobs you're probing, run, and eyeball the PNGs side by side.
const CONFIGS := [
	["shipped", null, null, null, null],
]

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame  # let the root window report in-tree first (see bake_item_icons.gd)
	if DisplayServer.get_name() == "headless":
		push_error("preview_fists_frame: needs a renderer — run WITHOUT --headless.")
		quit(1)
		return
	# The shipped baseline, read off the authored sources (see header). A miss means the rig's wiring moved
	# again — fail loud instead of rendering a pose the game no longer uses.
	var overrides := _section_raw(PLAYER_SCENE, FP_NODE_HEADER)
	var pose := {}
	for prop in ["fp_arm_scale", "fp_arm_offset", "fp_arm_rotation", "fp_arm_unarmed_nudge",
			"fp_arm_unarmed_tilt_deg", "fp_arm_unarmed_scale_mult", "fp_arm_unarmed_spread"]:
		var v: Variant = _authored(prop, overrides, FP_SCRIPT)
		if v == null:
			push_error("preview_fists_frame: no authored '" + prop + "' in " + PLAYER_SCENE + " or "
					+ FP_SCRIPT + " — did the FP rig move homes again? Repoint the consts above.")
			quit(1)
			return
		pose[prop] = v
	var fov: Variant = _authored("default_fov", _section_raw(CAM_TUNING, "[resource]"), CAM_TUNING_SCRIPT)
	if fov == null:
		push_error("preview_fists_frame: no authored 'default_fov' in " + CAM_TUNING + " or " + CAM_TUNING_SCRIPT)
		quit(1)
		return
	# ...overlaid with the player's SAVED fov, exactly like Settings.load_settings — the pose is tuned and
	# played at the user's FOV (110 as of 2026-08-12), and framing judged at the default 75 reads clipped:
	# the shipped guard's fists sit BELOW the frame edge at 75 and in the lower third at 110. Soft degrade:
	# no cfg (fresh machine) = the authored default, still a valid render.
	var saved := ConfigFile.new()
	if saved.load("user://settings.cfg") == OK:
		fov = saved.get_value("video", "fov", fov)
	var cam := Camera3D.new()
	cam.fov = fov
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
	rig.arm_rotation = pose["fp_arm_rotation"]
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
	# Mirrors the live rig's guard rest exactly: rest = fp_arm_offset + nudge, rotation_degrees.x = +tilt
	# (_fp_arm_rest_tilt), arm_scale = fp_arm_scale * mult (_fp_arm_rest_scale), arm_position.x = spread
	# (_fp_arm_rest_spread — the LEFT shoulder; BodyModelSwap mirrors the right).
	var arm_offset: Vector3 = pose["fp_arm_offset"]
	var arm_scale: float = pose["fp_arm_scale"]
	for cfg in CONFIGS:
		var nudge: Vector3 = pose["fp_arm_unarmed_nudge"] if cfg[1] == null else cfg[1]
		var tilt: float = pose["fp_arm_unarmed_tilt_deg"] if cfg[2] == null else cfg[2]
		var scale_mult: float = pose["fp_arm_unarmed_scale_mult"] if cfg[3] == null else cfg[3]
		var spread: float = pose["fp_arm_unarmed_spread"] if cfg[4] == null else cfg[4]
		rig.position = arm_offset + nudge
		rig.rotation_degrees = Vector3(tilt, 0, 0)
		rig.arm_scale = arm_scale * scale_mult
		rig.arm_position = Vector3(spread, 0.0, 0.0)
		for i in 6:
			await process_frame
		var img := root.get_texture().get_image()
		var path := OUT_DIR + "fists_" + String(cfg[0]) + ".png"
		img.save_png(path)
		print("preview_fists_frame: saved ", ProjectSettings.globalize_path(path))
	quit(0)

## key -> raw VariantWriter value text for every `key = value` line of ONE section of a .tscn/.tres, located
## by its header line's PREFIX (`[node name="FirstPersonBody"` / `[resource]`). Text-parsed on purpose — see
## the header for why load()ing the scene is impossible here. Values stay raw strings so rows this tool never
## asks for (script = ExtResource(...), host = NodePath(..)) never hit str_to_var; parsing happens per
## requested prop in _authored.
static func _section_raw(path: String, header_prefix: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("preview_fists_frame: can't open " + path)
		return out
	var in_section := false
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("["):
			if in_section:
				break  # the section's props ended at the next header
			in_section = line.begins_with(header_prefix)
			continue
		if not in_section:
			continue
		var eq := line.find("=")
		if eq > 0:
			out[line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges()
	return out

## The default-value text of a script's `@export var <prop> ... = <default>` line ("" if the prop is gone).
static func _export_default_raw(script_path: String, prop: String) -> String:
	var f := FileAccess.open(script_path, FileAccess.READ)
	if f == null:
		push_error("preview_fists_frame: can't open " + script_path)
		return ""
	var re := RegEx.create_from_string("(?m)^@export[^\\n]*?\\bvar\\s+" + prop + "\\b[^=\\n]*=\\s*(.+)$")
	var m := re.search(f.get_as_text())
	return "" if m == null else m.get_string(1).strip_edges()

## One authored value: the scene/resource override when the section authors the prop, else the script's
## @export default. null = found in neither (or unparseable) — callers treat that as "the wiring moved".
static func _authored(prop: String, overrides: Dictionary, fallback_script: String) -> Variant:
	var raw: String = overrides.get(prop, "")
	if raw.is_empty():
		raw = _export_default_raw(fallback_script, prop)
	return null if raw.is_empty() else str_to_var(raw)
