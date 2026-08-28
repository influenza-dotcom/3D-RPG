extends Node
## HUD-COMPASS QA screenshot harness — stands the top-centre heading tape (scripts/ui/hud_compass.gd) up on a
## bare canvas at a series of controlled headings and saves one shot each, plus a tight CROP of the band,
## because at the 792x444 canvas the whole instrument is 300x24 px and nothing about it is judgeable in a
## full-frame screenshot.
##
## WHY THIS EXISTS: the tape is a `_draw`, and ⭐ a CanvasItem's _draw NEVER RUNS under --headless (the dummy
## rasterizer has nothing to draw into), so tests/test_hud_compass.gd can pin every bearing and every offset
## and still tell you nothing about whether the rose letters collide with the tick row, whether the edge fade
## reaches far enough, or whether the index caret lands on the graduation it claims. This pins what it LOOKS
## like; that suite pins what it MEANS.
##
## THE FIVE QUESTIONS IT ANSWERS, in this order:
##   0. Does the bare rose survive a BRIGHT backdrop? (every shot — the plate behind the band is split dark
##      left / near-white right, because the tape ships with no track and its legibility is the outline's job
##      alone. A glyph that vanishes into the right half is a compass_outline_size regression.)
##   1. Does a cardinal sit dead under the index caret when you face it? (01, heading due north — the caret
##      and the N must share a pixel column, because that is the tape's entire promise.)
##   2. Do the three rows clear each other? (02, an off-cardinal heading, which is the busiest case: ticks
##      hanging from the top edge, an intercardinal's TWO glyphs on the baseline, and a marker chevron on the
##      bottom edge, all in 24 px. This is the shot that catches a compass_label_baseline_px regression.)
##   3. Does the rose SLIDE rather than POP? (01-05 are 45 deg apart across a full turn; letters must enter
##      and leave through the edge fade, never appear at full strength against the band's end.)
##   4. Do marker pips land on their true bearings? (every shot carries four WorldMarkers placed at exact
##      compass points around the camera — N/E/S/W — so a pip must sit under the matching letter, and a sign
##      flip in bearing_between shows up as east/west swapped rather than as anything erroring.)
##   5. Does the seam hold? (05 faces 315 with markers straddling 0 — the 360->0 wrap is where a tape without
##      HudCompass.delta_deg's wrap flings its pips off the band.)
##
## Run from the project root as a REAL WINDOWED RUN — not --headless, the GPU must render:
##   & "C:\Users\dalla\bin\godot.cmd" --path . res://scripts/tools/hud_compass_qa_shots.tscn -- --shots-dir="C:/some/dir"
## Without --shots-dir it writes to user://hud_compass_qa. Prints one QA_SHOT line per capture and quits.

const COMPASS_SCRIPT := preload("res://scripts/ui/hud_compass.gd")
const MARKER_SCRIPT := preload("res://scripts/components/world_marker.gd")

## The headings shot, in degrees clockwise from north. 0 is the caret-alignment shot; 22 is the deliberately
## AWKWARD one (no graduation at the centre, an intercardinal mid-band); the rest walk the rose.
const HEADINGS: Array[float] = [0.0, 22.0, 90.0, 180.0, 315.0]
## Frames to let settle before each capture: the widget's own heading gate needs one _process to see the new
## yaw and one more for the queued redraw to land.
const SETTLE_FRAMES := 4

var _dir := "user://hud_compass_qa"
var _cam: Camera3D
var _compass: Control


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-dir="):
			_dir = arg.substr("--shots-dir=".length()).strip_edges().trim_prefix("\"").trim_suffix("\"")
	DirAccess.make_dir_recursive_absolute(_dir)
	_build()
	_shoot_all.call_deferred()


## A bare stage: one camera, four markers at exact cardinal bearings around it, and the tape at its AUTHORED
## rect on its own layer, PINNED. Deliberately NOT the real HUD — every other overlay would just be noise in a
## crop of a 24 px band, and the geometry here is read from the same GameSettings.hud knobs ui.gd builds from.
## The live tape rides the `_weighted` sway carrier; this harness deliberately does not reproduce that, because
## these shots are about the tape's OWN ink and a spring offset would just make every crop land differently.
func _build() -> void:
	var world := Node3D.new()
	add_child(world)
	_cam = Camera3D.new()
	world.add_child(_cam)
	_cam.current = true
	# Markers at 20 m due north / east / south / west of the camera, in the project's basis (north = -Z,
	# east = +X). Tinted per point so a swapped pair is obvious in the crop rather than needing a count.
	for spec: Array in [[Vector3(0, 0, -20), Color(0.4, 1.0, 0.5)], [Vector3(20, 0, 0), Color(1.0, 0.5, 0.4)],
			[Vector3(0, 0, 20), Color(0.5, 0.6, 1.0)], [Vector3(-20, 0, 0), Color(1.0, 0.9, 0.4)]]:
		var m: Node3D = MARKER_SCRIPT.new()
		m.color = spec[1]
		world.add_child(m)
		m.global_position = spec[0]
	var layer := CanvasLayer.new()
	add_child(layer)
	# A SPLIT plate behind the band: dark on the left half, near-white on the right. The tape ships with NO
	# track (MenuStyle.hud.compass_track_color alpha 0), so the rose is bare outlined glyphs on the world and
	# the only question that matters about its ink is whether the outline carries it over a BRIGHT backdrop
	# as well as a dark one. One split backdrop puts both answers in every band crop; a uniformly dark plate
	# would have flattered the shipped colours and told us nothing.
	for half: Array in [[0.0, 0.5, Color(0.11, 0.12, 0.15)], [0.5, 1.0, Color(0.88, 0.89, 0.92)]]:
		var back := ColorRect.new()
		back.color = half[2]
		layer.add_child(back)
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		back.anchor_left = half[0]
		back.anchor_right = half[1]
	var h := GameSettings.hud
	_compass = COMPASS_SCRIPT.new()
	layer.add_child(_compass)
	_compass.anchor_left = 0.5
	_compass.anchor_right = 0.5
	_compass.offset_left = -h.compass_size.x * 0.5
	_compass.offset_right = h.compass_size.x * 0.5
	_compass.offset_top = h.compass_top
	_compass.offset_bottom = h.compass_top + h.compass_size.y


func _shoot_all() -> void:
	var i := 0
	for heading: float in HEADINGS:
		i += 1
		# The inverse of HudCompass.bearing_from_yaw: the harness drives the CAMERA, and the widget reads the
		# camera — so the round trip through the yaw basis is itself part of what these shots verify.
		_cam.rotation = Vector3(0.0, deg_to_rad(-heading), 0.0)
		for _f in range(SETTLE_FRAMES):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var name := "%02d_heading_%03d" % [i, int(heading)]
		_save(img, name)
		# The crop is the shot that actually gets read: the band plus a few px of margin, scaled up 4x with
		# NEAREST so a 1 px tick stays a hard edge instead of being resampled into a smudge.
		_save(_crop(img), name + "_band")
	print("QA_SHOTS_DONE ", _dir)
	get_tree().quit()


## The band's rect in RENDERED pixels, grown by a margin, blown up 4x nearest. The viewport may be rendering
## at a multiple of the 792-wide canvas (Settings.presentation / the window size), so the crop is derived from
## the image's own width rather than from the canvas constant.
func _crop(img: Image) -> Image:
	var h := GameSettings.hud
	var scale := float(img.get_width()) / 792.0
	var margin := 10.0 * scale
	var r := Rect2i(
		int((392.0 - h.compass_size.x * 0.5) * scale - margin),
		int(maxf(0.0, h.compass_top * scale - margin)),
		int(h.compass_size.x * scale + margin * 2.0),
		int(h.compass_size.y * scale + margin * 2.0))
	var out := img.get_region(r.intersection(Rect2i(Vector2i.ZERO, img.get_size())))
	out.resize(out.get_width() * 4, out.get_height() * 4, Image.INTERPOLATE_NEAREST)
	return out


func _save(img: Image, name: String) -> void:
	var path := "%s/%s.png" % [_dir, name]
	img.save_png(path)
	print("QA_SHOT ", path)
