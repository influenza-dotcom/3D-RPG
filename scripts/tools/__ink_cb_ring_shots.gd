extends SceneTree
## QA probe for the disposition RING x Colorblind-Safe Cues (the 2026-08-27 gap fix) — the permanent
## A/B, the __ink_seam_shots idiom. Four boxes on an ARC (equidistant from the lens, so every strip sits
## at the same bloom distance) wear the actor tint ids the ring paints:
##   strip 0  HOSTILE (id 1)        — red normal / ORANGE safe, black at range (the distance bloom)
##   strip 1  FRIENDLY (id 2)       — green normal / CYAN safe, black at range
##   strip 2  ENGAGED (7 + 1.0)     — the lock-on band: full hostile colour AT ANY DISTANCE
##   strip 3  NEUTRAL (id 4)        — the deliberate black ring, BOTH palettes (never a colour)
## Shot at 5 m (inside highlight_color_near_m, full bloom) and 40 m (past far_m, plain ids black), each
## under both palettes. The verdict: safe mode must paint orange/cyan where normal paints red/green —
## before the fix every safe-mode strip counted ZERO colour (the ids fell to the neutral black ring).
##
## WINDOWED on purpose — headless never compiles a shader, so a headless shot shows fallback materials
## and proves nothing. This is also the compile check for any ring/LUT edit.
##
## Run (from the project root):
##   & "C:\Users\dalla\bin\godot.cmd" --path . -s scripts/tools/__ink_cb_ring_shots.gd -- --shots-dir=<dir>
##
## ⭐ A `-s` script compiles BEFORE autoloads register, so ink_outline.gd is load()ed at RUNTIME.
## ⭐ Settings.ink_outline_intensity is PINNED to 1.0. That pin was LOAD-BEARING until 2026-08-27, when
## the ring alpha was `ring_a * ink_opacity` and a user's authored intensity rendered every ring pale
## enough for naive thresholds to count zero on a correct frame. The ring no longer rides the slider (it
## is the game's only outline now — see ink_outline.gdshader), so the pin is belt-and-braces: it keeps
## the WORLD ink at its authored strength so this probe photographs the shipped frame, not a bare one.
## ⭐ Both Settings writes are raw FIELD writes, session-local: the set_* setters call save_settings()
## and would persist the probe's palette flip into the player's real cfg. Restored before quit anyway.

const INK_PATH := "res://scripts/effects/ink_outline.gd"

const SETTLE := 60  ## frames before the first shot: shader compiles + the deferred mask/tint build
const BETWEEN := 12

## [name, colorblind_safe_cues, arc radius (m)]
const VARIANTS := [
	["near_normal", false, 5.0],
	["near_safe", true, 5.0],
	["far_normal", false, 40.0],
	["far_safe", true, 40.0],
]
## The four strips' arc angles (degrees off -Z) — projected screen order left->right at any radius.
const ANGLES := [-40.0, -14.0, 14.0, 40.0]

var _frame := 0
var _step := 0
var _wait := 0
var _dir := "user://ink_cb_ring_shots"
## Deliberately UNTYPED: the loaded GDScript's constants/statics are reached by duck-typed dot access
## (load("...").apply_tint(...)), which a hard GDScript type would reject at parse time.
var _ink_cls = null
var _boxes: Array = []
var _settings: Node = null
var _prev_cb := false
var _prev_intensity := 1.0
var _failed := false
## ⭐ SET, WAIT, THEN SHOOT — InkOutline pushes uniforms from its OWN _process (and polls the Settings
## flag there too), so a shot taken the same frame a knob moves captures the PREVIOUS palette.
var _pending := ""

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		for a in OS.get_cmdline_user_args():
			if String(a).begins_with("--shots-dir="):
				_dir = String(a).trim_prefix("--shots-dir=")
		DirAccess.make_dir_recursive_absolute(_dir)
		_settings = root.get_node_or_null(^"/root/Settings")
		print("[cb-ring-shots] settings autoload: %s" % [_settings])
		if _settings != null:
			_prev_cb = bool(_settings.get(&"colorblind_safe_cues"))
			_prev_intensity = float(_settings.get(&"ink_outline_intensity"))
			_settings.set(&"ink_outline_intensity", 1.0)
		_build()
		_wait = SETTLE
		return false
	_wait -= 1
	if _wait > 0:
		return false
	if _pending != "":
		_shoot(_pending)
		_pending = ""
		_step += 1
		_wait = 1
		return false
	if _step >= VARIANTS.size():
		if _settings != null:  # session flags back where the player had them (raw writes never persist)
			_settings.set(&"colorblind_safe_cues", _prev_cb)
			_settings.set(&"ink_outline_intensity", _prev_intensity)
		print("[cb-ring-shots] %s -> %s" % ["FAIL" if _failed else "PASS", _dir])
		quit(1 if _failed else 0)
		return true
	var v: Array = VARIANTS[_step]
	if _settings != null:
		_settings.set(&"colorblind_safe_cues", v[1])
		print("[cb-ring-shots] %s: colorblind_safe_cues read-back = %s" % [v[0], _settings.get(&"colorblind_safe_cues")])
	for i in _boxes.size():
		var rad: float = deg_to_rad(ANGLES[i])
		_boxes[i].position = Vector3(sin(rad) * float(v[2]), 2.0, -cos(rad) * float(v[2]))
	_pending = v[0]
	_wait = BETWEEN
	return false

func _build() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	root.add_child(light)
	_ink_cls = load(INK_PATH)

	# [tint id, blend] per strip — hostile / friendly / engaged (7 + 1.0 = the full lock-on) / neutral.
	var ids := [[1, 0.0], [2, 0.0], [7, 1.0], [4, 0.0]]
	for i in 4:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.4, 3.0, 1.4)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.62, 0.62, 0.66)
		mi.material_override = m
		# The NPC contract in miniature: actors ride the ink-suppression mask (the ring is their only
		# outline) — without the stamp the world ink double-lines the silhouette the ring wraps.
		mi.layers = 1 | int(_ink_cls.ACTOR_INK_MASK_LAYER)
		root.add_child(mi)
		_ink_cls.apply_tint(mi, ids[i][0], ids[i][1])
		_boxes.append(mi)

	var cam := Camera3D.new()
	cam.fov = 70.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.75, 0.80, 0.86)  # flat sky: ring colour reads at full contrast
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	cam.position = Vector3(0.0, 2.0, 0.0)
	cam.current = true
	root.add_child(cam)
	cam.add_child(_ink_cls.new())

## Classify a PNG pixel against the two palettes. ⭐ MEASURED, not derived: the saved frame carries the
## pushed LUT colours VERBATIM (sampled 2026-08-27 — ring px land as exactly 0.90,0.10,0.10 etc., hard
## edged, no sRGB re-encode and no AA blend under this probe's LINEAR-pinned env), so each rule is a
## tolerance window around the palette const it names. The first draft assumed sRGB-encoded values and
## its red window (g < 0.55) swallowed SAFE_HOSTILE's g = 0.55 — every orange ring counted "red".
##   red  = NORMAL_HOSTILE  (0.90, 0.10, 0.10)   orange = SAFE_HOSTILE  (0.95, 0.55, 0.00)
##   green = NORMAL_FRIENDLY (0.10, 0.80, 0.20)  cyan   = SAFE_FRIENDLY (0.00, 0.70, 0.90)
func _classify(p: Color) -> String:
	if p.r > 0.85 and p.g < 0.3 and p.b < 0.3:
		return "red"
	if p.r > 0.85 and p.g > 0.4 and p.g < 0.7 and p.b < 0.15:
		return "orange"
	if p.r < 0.35 and p.g > 0.65 and p.b < 0.4:
		return "green"
	if p.r < 0.25 and p.g > 0.55 and p.g < 0.85 and p.b > 0.75:
		return "cyan"
	return ""

func _shoot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_dir, name])
	# ⭐ NEAREST x3 for viewing — never raise content_scale_size to make lines legible (resolution trap).
	var big := Image.new()
	big.copy_from(img)
	big.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	big.save_png("%s/%s_x3.png" % [_dir, name])
	# Colour counts per quarter-screen strip (the arc projects one box per quarter, left->right).
	var counts: Array = []
	for i in 4:
		counts.append({"red": 0, "orange": 0, "green": 0, "cyan": 0})
	var w := img.get_width()
	for y in img.get_height():
		for x in w:
			var kind := _classify(img.get_pixel(x, y))
			if kind != "":
				counts[mini(int(4.0 * float(x) / float(w)), 3)][kind] += 1
	print("[cb-ring-shots] %s  strips [hostile, friendly, engaged, neutral]: %s" % [name, counts])
	_verdict(name, counts)

## The pass rules, mirrored from the feature contract so the probe self-judges. `far` shots prove the
## engaged band alone carries colour at range; `near` shots prove the whole LUT swapped.
func _verdict(name: String, counts: Array) -> void:
	var safe := name.ends_with("_safe")
	var near := name.begins_with("near")
	var hot := "orange" if safe else "red"
	var cold := "cyan" if safe else "green"
	var wrong_hot := "red" if safe else "orange"
	var checks := {
		"engaged strip paints %s" % hot: int(counts[2][hot]) > 20,
		"engaged strip has no %s" % wrong_hot: int(counts[2][wrong_hot]) == 0,
		"neutral strip stays uncoloured": int(counts[3]["red"]) + int(counts[3]["orange"]) + int(counts[3]["green"]) + int(counts[3]["cyan"]) == 0,
	}
	if near:
		checks["hostile strip paints %s" % hot] = int(counts[0][hot]) > 20
		checks["friendly strip paints %s" % cold] = int(counts[1][cold]) > 20
		checks["friendly strip has no %s" % ("green" if safe else "cyan")] = int(counts[1]["green" if safe else "cyan"]) == 0
	else:
		# Past highlight_color_far_m the plain ids are the neutral-black ring — the distance bloom.
		checks["plain hostile strip is black at range"] = int(counts[0][hot]) == 0
		checks["plain friendly strip is black at range"] = int(counts[1][cold]) == 0
	for label in checks:
		if not bool(checks[label]):
			_failed = true
			printerr("[cb-ring-shots] %s FAILED: %s" % [name, label])
