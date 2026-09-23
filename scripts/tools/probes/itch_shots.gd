extends Node
## MARKETING SCREENSHOT HARNESS for the itch.io store page — boots the real game into the MAIN level
## (alive.map, authored as scenes/levels/trenchboom_test_level.tscn) in HIGH FIDELITY, parks the PLAYER at
## chosen vantage points, and photographs the shipped first-person frame: view model, HUD, ink outline, lens
## warp, grain, the DayNightSky lighting. These are the pictures a customer sees, so nothing is faked — no
## synthetic scene, no bare camera, no debug overlay.
##
## WINDOWED on purpose, and 1920x1080 BORDERLESS: --headless never compiles a .gdshader, never renders a
## shadow map and skips the effect prewarm, so a headless "screenshot" would show fallback materials. The
## window is placed rather than the project's exclusive fullscreen so the run does not seize the desktop.
##
## TWO MODES, because framing cannot be guessed from coordinates:
##   --mode=recon  walks a ring of vantage points around every point of interest in the level, shoots each one
##                 small, and composites them into ONE contact-sheet PNG (plus the tiles) so a whole level of
##                 candidate framings can be judged from a single image. Prints a `TILE <n> ...` line per tile
##                 so a winner can be named by its number.
##   --mode=final  shoots the hand-picked SHOTS list below at full 1920x1080, one PNG per entry, at that
##                 entry own time of day.
##
## Run from the project root (a REAL windowed run, never --headless):
##   & "C:\Users\dalla\bin\godot.cmd" --path . res://scripts/tools/probes/itch_shots.tscn --
##       --mode=recon --shots-dir="C:/some/dir"
##
## Driver-copy pattern, copied from presentation_qa_shots.gd: this scene is the boot scene but the run
## switches current_scene to game.tscn (which frees the current scene), so _ready re-attaches a COPY of this
## script on a bare Node parented to root, which survives the change and drives the run.
##
## (*) NEVER call a Settings.set_* here: those setters call save_settings() and would rewrite the developer
## real user://settings.cfg. Plain vars are assigned directly and the two Window properties apply_video would
## touch are written by hand — apply_video itself would also re-assert the SAVED window mode (fullscreen on
## this dev machine) over the placement above.

const QaShots := preload("res://scripts/tools/probes/qa_shot_helpers.gd")

## Points of interest in the main level, read off the authored node transforms in the level scene (the
## content, not the brushwork): the spawn plaza and its ATM, the street furniture, each streetlight cluster,
## the two service NPCs (chip installer, merchant), the weapon bench + Door at the south end, and the lower
## tutorial/pickup pocket at y = -5. Recon rings every one of these. Third field is the ring radius in metres.
const POIS: Array = [
	["plaza_atm", Vector3(-5.9, 4.6, 2.0), 9.0],
	["street_cube", Vector3(-1.4, 2.6, -6.0), 9.0],
	["tall_lamp", Vector3(-8.1, 8.0, -7.1), 12.0],
	["mid_street", Vector3(-17.6, 2.5, 0.9), 10.0],
	["west_lamps", Vector3(-22.3, 4.4, -8.3), 11.0],
	["chip_npc", Vector3(-30.2, 6.0, 6.3), 8.0],
	["low_pocket", Vector3(-26.5, -4.6, -9.0), 8.0],
	["merchant", Vector3(-44.7, 2.5, -10.1), 8.0],
	["radio_row", Vector3(-4.0, 1.5, -50.0), 9.0],
	["bench_door", Vector3(-48.5, 6.5, -62.0), 9.0],
]
## Yaw offsets (degrees) around each POI: three approaches per point, so a POI that only reads from one side
## still lands one usable tile.
const RECON_YAWS: Array = [35.0, 145.0, 250.0]
## Time of day the recon pass runs at. NOON, deliberately: the first recon ran at dusk (0.8) and every tile came
## back a murky blue-on-blue in which neither the geometry nor a candidate framing could be judged. Mood is a
## FINAL-pass decision (each SHOTS entry carries its own time); recon only has to show what is where.
const RECON_TIME := 0.5
## Look pitch (degrees, positive = up) the recon pass holds at every vantage point. Slightly ABOVE level: it
## lifts the horizon off the bottom third, which is the difference between a tile that shows a street and a
## tile that shows pavement. Holding ONE pitch across the survey is also what makes the tiles comparable.
const RECON_PITCH := 3.0

## The hand-picked keepers, chosen off the recon contact sheet. Each entry is
## [name, eye_position, yaw_target, pitch_deg, time_of_day, hud_visible]. `yaw_target` only sets which way the
## body faces; the pitch is dictated (see _set_pitch).
##
## The eye/yaw_target pairs are the RECON values VERBATIM, not retuned by hand: the recon tile IS the frame that
## was judged, so reproducing it exactly is what makes the pick mean anything. What the final pass adds is
## resolution, the time of day each view flatters, and the HUD decision.
##
## ORDERED BY TIME OF DAY on purpose — every change of `time_of_day` costs a full FIRST_SETTLE while the
## volumetric fog reconverges, so grouping the list keeps the run to one settle per distinct time.
##
## No MIDNIGHT entry, deliberately. The cycle does reach it and the level is genuinely near-black there — the
## first final pass proved it with a 00:00 frame that read as an unlit rectangle. Honest, and useless on a store
## page; dusk (0.78-0.85) is where the streetlights carry the scene with sky colour still behind them.
const SHOTS: Array = [
	# --- noon: the wide, readable establishing views -------------------------------------------------------
	["01_plaza_wide", Vector3(-25.6, 9.5, 12.9), Vector3(-30.2, 6.0, 6.3), 3.0, 0.5, true],
	# The same frame with the HUD stripped — the one to crop for the itch cover image / header, where an ammo
	# counter and a compass would only fight the title text.
	["02_plaza_clean", Vector3(-25.6, 9.5, 12.9), Vector3(-30.2, 6.0, 6.3), 3.0, 0.5, false],
	["03_city_terrace", Vector3(-15.1, 4.0, 0.5), Vector3(-22.3, 4.4, -8.3), 3.0, 0.5, true],
	["04_courtyard_npc", Vector3(-40.1, -0.5, -3.5), Vector3(-44.7, 2.5, -10.1), 3.0, 0.5, true],
	["05_scaffold", Vector3(-57.0, 6.5, -65.1), Vector3(-48.5, 6.5, -62.0), 3.0, 0.5, true],
	# --- dusk: the streetlights come up while the sky still has colour in it -------------------------------
	# All three share 0.78 (~18:45) so the run pays ONE fog settle for the set. 0.85 was tried for the lamp row
	# and came back nearly black — past this point the level loses its sky light faster than the lamps fill in.
	["06_dusk_backstreet", Vector3(-42.5, 5.5, -56.1), Vector3(-48.5, 6.5, -62.0), 3.0, 0.78, true],
	["07_dusk_corridor", Vector3(-14.4, 4.0, 0.0), Vector3(-5.9, 4.6, 2.0), 3.0, 0.78, true],
	["08_lamp_row", Vector3(1.2, 0.0, -42.6), Vector3(-4.0, 1.5, -50.0), 3.0, 0.78, true],
]

const TILE := Vector2i(320, 180)   ## contact-sheet tile size
const SHEET_COLS := 6

## Generous FIRST settle: the scene fill of this world is VOLUMETRIC FOG, which is temporally reprojected and
## converges over time rather than per frame — the day_night_shots lesson, where 45 frames after a big
## lighting change still rendered essentially as night and the probe LIED about a correct implementation.
const FIRST_SETTLE := 150
## Per-shot settle: the teleport has to ground the player through physics, the view model has to finish its
## raise, and the ghost/ink accumulators have to flush the previous vantage point out of their history.
const SHOT_SETTLE := 24

var _dir := "user://itch_shots"
var _mode := "recon"
var _tiles: Array[Image] = []
var _legend: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_tree().current_scene == self:
		var d := Node.new()
		d.name = "ItchShotsDriver"
		d.set_script(get_script())
		get_tree().root.add_child.call_deferred(d)
		return
	_run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots-dir="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--mode="):
			_mode = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_window().borderless = true
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	await _frames(5)

	# Plain vars, never a set_* (see the header (*) rule). The cosmetic FOV/bob animations are frozen so a
	# shot is never caught mid-bob and a re-run of the same entry reproduces the same frame.
	Settings.fov_effects_enabled = false
	Settings.view_bob_enabled = false

	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _frames(120)   # the level loads, the player spawns, the HUD builds, the nav map syncs

	_pin_mode(Settings.PRESENTATION_HIGH_FIDELITY, 1.0)
	# Freeze the clock so every shot holds exactly the time it asked for while the fog settles on it.
	WorldClock.day_length_seconds = 0.0

	var player := QaShots.find_by_script(get_tree().root, "res://scripts/player/player.gd") as Node3D
	if player == null:
		print("ITCH_FAIL no player in the booted scene")
		get_tree().quit(1)
		return
	# A gun IN HAND is most of what a store-page screenshot sells, and the player deliberately begins
	# HOLSTERED. Go through the debug command rather than poking the weapon hub: it walks the real bag ->
	# equip -> draw chain (fresh unique Item, inventory.add, request_equip), so the view model, the HUD ammo
	# readout and the crosshair all agree with what a player would see after picking up a pistol.
	for line in DebugActionsPlayer.run("weapon", {&"player": player}, PackedStringArray(["pistol", "3"])):
		print("ITCH_WEAPON ", line)
	_unholster(player)
	_hold_gun_alert()
	_hide_sky_title()
	await _frames(FIRST_SETTLE)
	_report_view_model(player)

	if _mode == "recon":
		await _recon(player)
	else:
		await _final(player)
	print("ITCH_DONE")
	get_tree().quit(0)


## RECON: ring every POI, shoot each approach small, and composite the lot into one contact sheet. The tiles
## are kept on disk too — once a tile number is chosen from the sheet, its `TILE` line carries the exact eye
## position and look target to paste into SHOTS.
func _recon(player: Node3D) -> void:
	WorldClock.set_time_of_day(RECON_TIME)
	await _frames(FIRST_SETTLE)
	var n := 0
	for poi in POIS:
		var poi_name: String = poi[0]
		var target: Vector3 = poi[1]
		var radius: float = poi[2]
		for yaw_deg in RECON_YAWS:
			var a := deg_to_rad(float(yaw_deg))
			var wish := target + Vector3(sin(a), 0.0, cos(a)) * radius
			var eye := await _stand(player, wish, target)
			var img := await _capture()
			_tiles.append(_tile_of(img))
			var line := "TILE %d %s yaw=%d eye=(%.1f, %.1f, %.1f) look=(%.1f, %.1f, %.1f)" % [
					n, poi_name, int(yaw_deg), eye.x, eye.y, eye.z, target.x, target.y, target.z]
			_legend.append(line)
			print("ITCH_", line)
			img.resize(960, 540, Image.INTERPOLATE_LANCZOS)
			_save(img, "recon_%02d_%s_%d" % [n, poi_name, int(yaw_deg)])
			n += 1
	_write_sheet()


## FINAL: the hand-picked list, full resolution, each at its own time of day.
func _final(player: Node3D) -> void:
	if SHOTS.is_empty():
		print("ITCH_FAIL SHOTS is empty — run --mode=recon and fill it from the contact sheet")
		return
	var last_time := -1.0
	for shot in SHOTS:
		var shot_name: String = shot[0]
		var eye: Vector3 = shot[1]
		var look: Vector3 = shot[2]
		var pitch: float = shot[3]
		var tod: float = shot[4]
		var hud: bool = shot[5]
		if not is_equal_approx(tod, last_time):
			WorldClock.set_time_of_day(tod)
			last_time = tod
			await _frames(FIRST_SETTLE)   # the fog must converge on the new lighting before it is honest
		_place(player, eye, look, pitch)
		_set_hud(hud)
		await _frames(SHOT_SETTLE)
		# Re-aim after the settle for the same reason the recon pass does: physics grounds the body and the eye
		# height shifts underneath the first aim, so aiming once would not reproduce the tile that was judged.
		_aim(player, look, pitch)
		await _frames(4)
		var img := await _capture()
		print("ITCH_FRAME ", shot_name, " eye=", _eye(player), " tod=", tod, " hud=", hud)
		_save(img, shot_name)
	_set_hud(true)


## Teleport the player to the nearest point ON THE BAKED NAVMESH to `wish` and aim the look at `target`.
## Snapping to the nav map is what makes a blind vantage point safe: the mesh is by definition standable
## floor, so the body never lands inside brushwork or falls out of the level. Returns the settled eye position.
func _stand(player: Node3D, wish: Vector3, target: Vector3) -> Vector3:
	var map: RID = player.get_world_3d().navigation_map
	var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, wish)
	_place(player, on_mesh + Vector3.UP * 0.3, target, RECON_PITCH)
	await _frames(SHOT_SETTLE)
	# Re-aim AFTER physics grounds the body: the eye height settled underneath the first aim.
	_aim(player, target, RECON_PITCH)
	await _frames(4)
	return _eye(player)


## Put the body at `eye` (a real eye position — the head rig sits above the body origin, so the body is
## dropped by that offset) and aim it at `target`.
func _place(player: Node3D, eye: Vector3, target: Vector3, pitch_deg: float) -> void:
	var head := player.get(&"head") as Node3D
	var lift := (head.global_position.y - player.global_position.y) if head != null else 1.6
	player.global_position = eye - Vector3.UP * lift
	_aim(player, target, pitch_deg)


## Turn the BODY to face a world point. Yaw only — Player owns yaw, Head owns pitch, exactly as the mouse
## drives them. Written directly rather than through focus_camera_on, which EASES over several frames.
func _face(player: Node3D, target: Vector3) -> void:
	var dir := target - _eye(player)
	if dir.length() < 0.01:
		return
	player.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)


## Set the look pitch outright, in degrees, positive = up.
##
## ⭐Pitch is DICTATED, never derived from the look target, and that is the whole framing control. Deriving it
## points the camera at wherever the target node happens to sit, and in this level the authored content sits
## well below eye level (street furniture, a merchant on a lower walkway), so a derived pitch tipped every shot
## into the pavement — the first final pass came back with floors eating half the frame. A near-level pitch with
## a touch of UP puts the horizon high enough that the architecture and sky carry the picture, which is what a
## store page is selling.
func _set_pitch(player: Node3D, deg: float) -> void:
	var head := player.get(&"head") as Node3D
	if head != null:
		head.rotation.x = deg_to_rad(deg)


## Face `target` and hold `pitch_deg` — the pairing every shot uses.
func _aim(player: Node3D, target: Vector3, pitch_deg: float) -> void:
	_face(player, target)
	_set_pitch(player, pitch_deg)


func _eye(player: Node3D) -> Vector3:
	var head := player.get(&"head") as Node3D
	return head.global_position if head != null else player.global_position + Vector3.UP * 1.6


## Bring the drawn weapon OUT. `holstered` lives on Attack (the fire/reload gate); set_holstered(false) is the
## same call the draw press makes, so the view model raise and the HUD both run their real transitions.
func _unholster(player: Node3D) -> void:
	var ws: Object = player.get(&"weapon_system")
	if ws == null:
		return
	var attack: Object = ws.get(&"attack")
	if attack != null and attack.has_method(&"set_holstered"):
		attack.call(&"set_holstered", false)


## Hold the gun in its ALERT hip pose for the whole run. GunPose has an authored "Idle Lower": after
## `idle_lower_time` (4 s) with no shot fired, no ADS and no recent combat, the view model sinks muzzle-down to
## read as "not alert" — and a screenshot harness is idle BY CONSTRUCTION (every settle is seconds of standing
## still), so the first recon pass photographed nothing but the tip of a drooping barrel at the bottom edge.
## Pushing `idle_lower_time` out of reach selects the OTHER authored pose rather than inventing one: this is
## exactly the hip rest a player sees any time they have been active in the last few seconds.
func _hold_gun_alert() -> void:
	var pose := QaShots.find_by_script(get_tree().root, "res://scripts/effects/gun_pose.gd")
	if pose == null:
		print("ITCH_VM no GunPose — the idle lower cannot be held off")
		return
	pose.set(&"idle_lower_time", 1.0e9)


## Drop the SkyTitle for the whole run. It is the level-intro flourish — the game's name painted across the sky
## on arrival — and it FADES, so it turned up as a half-transparent ghost over the FIRST shot of each pass and
## over nothing else. A title that appears on exactly one screenshot, at whatever opacity that shot happened to
## catch, is an artefact of shot order rather than a decision; a store page puts its title on in the page
## template.
##
## ⭐FREED, not hidden. SkyTitle is a Node3D but it BUILDS its own overlay CanvasLayer (plus a BackBufferCopy)
## as a child at runtime, and a CanvasLayer does NOT inherit its Node3D parent's `visible` — so setting the
## node invisible left the title painting exactly as before, which is precisely what the first attempt did.
## Freeing the node takes the built children with it. Safe here because the only caller,
## `Player._arm_sky_title`, has already run by spawn and is written as a no-op when no SkyTitle is present.
func _hide_sky_title() -> void:
	var sky := QaShots.find_by_script(get_tree().root, "res://scripts/components/sky_title.gd")
	if sky == null:
		return
	sky.queue_free()
	print("ITCH_SKYTITLE freed ", sky.name)


## Why the gun does or does not appear in frame, as greppable facts. The first recon pass came back with only a
## thin sliver of the pistol at the bottom edge, and the three candidate causes are not distinguishable by eye:
## the weapon never equipped, the view model is holstered/lowered (the raise gates firing), or the dedicated
## ViewModelCamera pass is off and the gun is being drawn by the main camera instead.
func _report_view_model(player: Node3D) -> void:
	var ws: Object = player.get(&"weapon_system")
	var attack: Object = ws.get(&"attack") if ws != null else null
	print("ITCH_VM equipped=", ws.get(&"equipped_weapon") if ws != null else "<no hub>",
		" holstered=", attack.get(&"holstered") if attack != null else "-",
		" draw_locked=", attack.get(&"draw_locked") if attack != null else "-")
	var vm := QaShots.find_by_script(get_tree().root, "res://scripts/camera/view_model_camera.gd")
	if vm == null:
		print("ITCH_VM no ViewModelCamera in the tree — the gun renders on the main camera")
		return
	var container: Control = vm.get(&"_container")
	print("ITCH_VM pass enabled=", vm.get(&"enabled"),
		" container=", (container.size if container != null else "-"),
		" visible=", (container.visible if container != null else "-"),
		" gun_cam=", vm.get(&"_gun_camera") != null)


## Show/hide the HUD — and ONLY the HUD. `UI` (scripts/ui/ui.gd) is itself the CanvasLayer that carries the whole
## instrument panel: HP and stamina bars, ammo, money, toasts, the quest tracker, the minimap, the clock, the
## hotbar and the top-centre compass tape. Toggling that one node is the entire job.
##
## ⭐NOT QaShots.strip_overlays here, which is what the first two passes reached for. It hides EVERY CanvasLayer,
## so the post-process layer (grain / quantise / dither — the shipped look) goes with it and has to be put back
## by restore_post_process; in this game the HUD rides the SAME layer as that post pass, so restoring the post
## pass restored the HUD too and the supposedly "clean" frame came back with the minimap and ammo still on it.
## Blanket-restoring afterwards was worse again: it turned the developer overlay ON (draw calls, node counts,
## the FPS graph) in frames meant for a store page, because "every CanvasLayer visible" is not the shipped state.
func _set_hud(on: bool) -> void:
	var ui := QaShots.find_by_script(get_tree().root, "res://scripts/ui/ui.gd") as CanvasLayer
	if ui == null:
		print("ITCH_HUD no UI layer found — the HUD cannot be toggled")
		return
	ui.visible = on


func _pin_mode(mode: int, scale: float) -> void:
	Settings.presentation = mode
	Settings.render_scale = scale
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if mode == Settings.PRESENTATION_HIGH_FIDELITY else Window.CONTENT_SCALE_MODE_VIEWPORT
	win.scaling_3d_scale = scale


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _tile_of(img: Image) -> Image:
	var t := img.duplicate() as Image
	t.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
	t.convert(Image.FORMAT_RGBA8)   # blit_rect needs one shared format across the sheet
	return t


## One contact sheet of every recon tile, in `TILE n` order, left to right and top to bottom.
func _write_sheet() -> void:
	if _tiles.is_empty():
		return
	var rows := int(ceil(float(_tiles.size()) / float(SHEET_COLS)))
	var sheet := Image.create_empty(TILE.x * SHEET_COLS, TILE.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 1))
	for i in _tiles.size():
		var at := Vector2i((i % SHEET_COLS) * TILE.x, (i / SHEET_COLS) * TILE.y)
		sheet.blit_rect(_tiles[i], Rect2i(Vector2i.ZERO, TILE), at)
	_save(sheet, "contact_sheet")
	var f := FileAccess.open(ProjectSettings.globalize_path(_dir.path_join("contact_sheet.txt")), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_legend) + "\n")
		f.close()


func _save(img: Image, img_name: String) -> void:
	var path := _dir.path_join(img_name + ".png")
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("ITCH_SHOT " if err == OK else "ITCH_SHOT_FAIL ", path, " ", img.get_size())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
