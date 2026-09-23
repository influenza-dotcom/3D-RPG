@tool
class_name RainFall
extends GPUParticles3D

## @system Rendering
## @seam Drop-in weather: one RainFall anywhere in a level fills it with rain that follows the camera — a slab of emitter riding overhead, drops whose STREAKS lie along the direction they are really falling and foreshorten as you look up them (rain_drop.gdshader), a looping rain bed on the `ambient` bus, and an overhead test (its own fan of up-rays, OR'd with the player's `is_indoors`) that stops the fall and ducks the sound under anything solid. No collider, nothing saved.
## @risk The shelter probe is a fan of rays straight up from the camera; a level whose roofs have no COLLISION
## (visual-only brushes) will rain indoors regardless. Author roofs with colliders, or turn `stop_when_sheltered`
## off and place rain per-area instead.
## @risk The sky heightfield is a GRID: roof edges are ragged at `volume_extents * 2 / sky_grid_cells` metres
## (about a metre by default), and anything thinner than a cell — a wire, a railing, a sign — either shelters a
## whole cell or none of it. Raise `sky_grid_cells` for a crisper eave at the cost of more rays per sweep.
## @risk The field is only `volume_extents` wide and rides the camera, so you can never see rain further than
## about 14 m away whatever the weather is doing. Standing deep inside a building looking out of a distant
## window shows a dry world for that reason and not because of the occlusion above — widening `volume_extents`
## buys reach and spends it on density, since `drops` is a fixed budget.
## @test res://tests/test_rain_fall.gd
##
## The twin of `AmbientDust` (scripts/components/ambient_dust.gd): the same "one emitter, world-space particles,
## re-centred on whatever camera is rendering" idea, but for weather instead of motes. Drop ONE anywhere in the
## level — it needs no parent in particular, because it moves itself to the camera every frame.
##
## ⭐ WHY IT FOLLOWS THE CAMERA INSTEAD OF COVERING THE MAP. A level-sized rain volume spends its whole particle
## budget on drops nobody can see. Riding the camera means every drop is in frame, so a few thousand of them read
## as heavy rain where a hundred thousand map-wide would not. The particles are simulated in WORLD space
## (`local_coords = false`), so they fall straight down past you rather than being dragged along with the emitter
## as you walk — the same reason AmbientDust does it.
##
## ⭐ THE STREAK POINTS WHERE THE DROP IS GOING, NOT WHERE THE SCREEN'S UP IS. A plain camera-facing billboard
## draws every drop as a vertical line in screen space, so looking UP gives you a wall of parallel verticals
## instead of streaks turning with the weather — the single loudest tell that the rain is a sprite effect.
## `transform_align = TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY` fixes the DIRECTION at the source: the quad
## still turns its FACE to the camera (Z billboard) but its length now lies along the particle's own world
## velocity. The cost is that the lean has to be REAL — a sideways velocity, not a roll of the sprite (see
## `_fall_direction`) — because an aligned streak can only show a lean the drop actually has.
##
## ⭐ AND THE LENGTH NEEDS A SHADER, BECAUSE THE ENGINE THROWS THAT HALF AWAY. Godot's Y-to-velocity alignment
## flattens the velocity into the screen plane and then NORMALISES it, so a drop coming straight at the lens
## still draws at full length: with alignment alone, looking up at rain falling straight down gives a sky full of
## full-size streaks that perspective says should have collapsed to points. `rain_drop.gdshader` puts that term
## back — it scales the quad by |sin| of the angle between the line of fall and the line of sight to that drop —
## and floors the collapse so end-on rain becomes short fat dashes rather than deleting itself. Measured by
## scripts/tools/probes/__rain_look_probe.gd, which shoots the fixed look and the old one from the same camera.
##
## ⭐ RAIN STOPS AT THE ROOF LINE, NOT AT THE PLAYER. The first version of the cutoff switched the whole emitter
## off under a roof — and because the field rides the camera, that deleted the weather EVERYWHERE, including the
## street you can see through the doorway you are standing in. So the cutoff moved down to the individual drop:
## `_update_sky_grid` keeps a small rolling heightfield around the camera, one cell holding the height of the
## topmost thing over that patch of world, and `rain_drop.gdshader` collapses any drop that is below it. Rain
## then stops at the eave and keeps falling one cell further out, with no emitter state involved at all.
##
## The grid is WORLD-ANCHORED and the texture wraps, so a texel is a fixed patch of ground and the field scrolls
## under you like a virtual texture rather than shimmering as you walk. It is refreshed a slice at a time
## (`sky_cells_per_frame`) so the raycasts never land in one frame, and rebuilt whole on the first frame and
## after a teleport, where a stale grid would be visibly wrong rather than slightly late.
##
## ⭐ THE PROBE STILL EXISTS, BUT ONLY THE SOUND LISTENS TO IT NOW. "Am I under cover" is still the right
## question for the rain BED (you hear rain on a roof, ducked), and it is a bad question for the pixels. With
## `occlude_under_roofs` on, the emitter never stops; turning it off falls back to the old all-or-nothing cut.
##
## ⭐ AND THAT PROBE ASKS TWICE, BECAUSE "AM I INDOORS" IS THE SMALLER QUESTION. `IndoorAmbienceDucker`
## rides the player casting a fan of rays at the ceiling and publishes `is_indoors`, and this used to take that
## flag as the whole answer whenever a player existed. It isn't: the ducker is tuned for ROOMS (6 m of scan, from
## the player), so a bridge, a gantry, an awning or an atrium roof above its reach is honestly `is_indoors ==
## false` — and the rain fell straight through it onto your head. Worse, a level with no ducker leaves the flag
## at its `false` default forever, which made the private ray below dead code rather than a fallback. So the flag
## is now one INPUT: indoors implies sheltered, and this node's own taller fan catches everything else.

@export_group("Downpour")
## Drops alive at once. Everything is in frame (see above), so this number is much smaller than it looks.
@export var drops: int = 3400
## Metres per second. Real rain is 5–9 m/s; games lie upward because a streak reads as speed.
@export var fall_speed: float = 22.0
## Half-extents of the slab the drops are born in (metres), and how far above the camera it rides. Wide enough to
## cover the view, thin because a drop's life starts at the top and ends below you.
@export var volume_extents: Vector2 = Vector2(14.0, 14.0)
@export var spawn_height: float = 11.0
## How far below the camera a drop keeps falling before it is recycled.
@export var fall_depth: float = 14.0

@export_group("Look")
## A drop is a thin vertical streak, not a dot: this is its size in metres.
@export var drop_length: float = 0.5
@export var drop_width: float = 0.018
## Streaks lean with the wind. ⭐ A REAL sideways velocity, not a roll of the sprite: the streak is aligned to
## the direction the drop actually travels (see the class docs), so the lean has to exist in the world for the
## streak to show it. Degrees from vertical — `fall_speed` stays the DOWNWARD speed, the lean is added on top.
@export_range(0.0, 60.0, 0.5) var lean_degrees: float = 12.0
## The compass heading the weather drives TOWARD, degrees clockwise about +Y (0 = toward -Z, 90 = toward +X).
## Match the clouds. Irrelevant while `lean_degrees` is 0.
@export_range(0.0, 360.0, 1.0) var wind_heading_degrees: float = 30.0
## Rain is not white — it is a smear of whatever light is behind it. Low alpha, slightly cool.
@export var drop_color: Color = Color(0.66, 0.72, 0.85, 0.4)
## Variation in streak length between drops, as a fraction. Uniform streaks read as a texture.
@export var length_variation: float = 0.45
## What a drop looks like when you stare straight along its fall — up into the weather, or down it. Length is a
## fraction of `drop_length`, width a multiple of `drop_width`. ⭐ NOT zero: a streak seen exactly end-on is
## geometrically a point, and rain that ERASES itself the moment you look up is a worse lie than rain that never
## turned. These keep it the short thick dash a drop coming at your face actually reads as.
@export_range(0.02, 1.0, 0.01) var end_on_length: float = 0.16
@export_range(1.0, 8.0, 0.1) var end_on_width: float = 3.0

@export_group("Sound")
## The rain bed. ⭐ Loaded by PATH at runtime rather than `preload`ed into a default: a `preload` of an asset whose
## .import has not been generated yet fails the whole SCRIPT to parse, which would take the visual rain down with
## the audio. Leave it null to get the shipped loop; assign one to override; clear `use_default_sound` for silence.
@export var sound: AudioStream = null
## OFF = no rain bed at all (for a level that wants its own ambience authored with `AmbientSound`).
@export var use_default_sound: bool = true
## Level of the bed outdoors, and under a roof. It ducks rather than stops, because you still hear rain on a roof.
## ⭐ The bed is AMBIENCE, not an event: it plays continuously for as long as the weather lasts, so it sits well
## under gunfire, footsteps and dialogue by default. A level that wants a downpour to dominate raises these.
@export var sound_volume_db: float = -22.0
@export var sheltered_volume_db: float = -32.0
## dB per second the bed moves between those two. Slow enough that a doorway is a transition, not a switch.
@export var sound_fade_db_per_second: float = 14.0
## ⭐ The `ambient` bus, never Master: that is the bus the player's Ambient volume slider governs, and the bus
## `IndoorAmbienceDucker` muffles behind a roof. A bare AudioStreamPlayer defaults to Master and escapes both.
@export var sound_bus: StringName = &"ambient"

@export_group("Shelter")
## Stop raining when something solid is overhead (see the class docs).
@export var stop_when_sheltered: bool = true
## How far up to look for a roof (metres), and how often to look (seconds — this is a raycast, not free).
## ⭐ Reach GENEROUSLY: this is "is anything between me and the sky", not "am I in a room", so it has to clear
## bridges and atrium roofs that the player's own 6 m indoors scan never sees.
@export var shelter_probe_height: float = 60.0
@export var shelter_check_interval: float = 0.2
## Horizontal spread (m) of the up-ray fan, and the fraction of it that must hit to count as covered. A FAN, not
## one ray, for the same reason the ducker uses one: a skylight, a rafter gap or a light fitting directly
## overhead would otherwise flicker you back out into the rain while a roof clearly surrounds you.
@export var shelter_probe_radius: float = 0.9
@export_range(0.05, 1.0, 0.05) var shelter_coverage: float = 0.4
## Collision mask the shelter ray uses. Default 1 = the world layer this project's level geometry lives on.
@export_flags_3d_physics var shelter_mask: int = 1

@export_group("Sky occlusion")
## Cull each drop against what is actually above it, instead of stopping the whole field under a roof (see the
## class docs). ⭐ OFF goes back to the all-or-nothing cut, which also blanks the rain you can see out of a
## doorway — it is here for a level that cannot spare the rays, not as a preference.
@export var occlude_under_roofs: bool = true
## Cells across the heightfield. The footprint is the emitter's, so this sets the cell size directly: 24 cells
## over a 28 m field is about 1.2 m, which is how ragged a roof edge is allowed to look.
@export_range(8, 64, 1) var sky_grid_cells: int = 24
## How far ABOVE the camera each downward probe starts. It has to clear whatever you might be standing under, so
## it is generous; a roof higher than this reads as open sky and rains into the room below it.
@export var sky_probe_headroom: float = 100.0
## Cells re-probed per frame. The whole grid sweeps in `sky_grid_cells^2 / this` frames — about a sixth of a
## second at the defaults, measured at 0.26 ms a frame in the main level (576 rays cost 2.3 ms there, so a
## 64-cell slice is 0.26). ⭐ Size it by how fast NEW cells scroll in, not by the sweep: the grid is
## world-anchored, so a cell you have already probed stays correct while you walk past it, and only the row
## appearing at the leading edge is stale. Walking brings in one row every ~0.2 s, which even a quarter of this
## budget stays ahead of. The full sweep rate matters for geometry that MOVES — a door, a shutter, a lift.
@export_range(4, 256, 1) var sky_cells_per_frame: int = 64
## Collision mask the downward probes use. Same default as the shelter fan, and for the same reason.
@export_flags_3d_physics var sky_mask: int = 1

## The shipped rain loop. A path rather than a preload, for the reason on the `sound` export.
const DEFAULT_SOUND_PATH := "res://assets/audio/sfx/liecio-calming-rain-257596.mp3"

## The drop's own shader (the foreshortening half of the fix — see the class docs). A `preload` is safe here
## where it is not for the audio: a .gdshader is a plain text resource with no import step to be missing.
const DROP_SHADER: Shader = preload("res://resources/shaders/rain_drop.gdshader")

## The up-ray fan, on the XZ plane before scaling by `shelter_probe_radius`: centre plus the four cardinals.
## Deliberately the same shape as `IndoorAmbienceDucker.PROBE_OFFSETS` — same question, same failure mode.
const SHELTER_OFFSETS: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(1.0, 0.0, 0.0),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, 0.0, -1.0),
]

## Height stored for a cell with nothing over it. Large and negative so no drop is ever below it, which is also
## what the shader assumes when occlusion is switched off.
const SKY_OPEN := -1.0e9

## Re-probe early once the camera has moved this far (m) since the last sample, whatever the throttle says.
## A doorway taken at a run is most of `shelter_check_interval` worth of stride, and a fixed interval is exactly
## what makes rain keep falling through the ceiling for the first step inside.
const SHELTER_RESAMPLE_DISTANCE := 1.2

var _shelter_timer: float = 0.0
var _sheltered: bool = false
var _shelter_primed: bool = false      ## false until the first probe; that one samples the CURRENT roof, see _process
var _shelter_sample_pos: Vector3 = Vector3.ZERO
var _emitter_offset: Vector3 = Vector3.ZERO   ## camera -> emitter: up `spawn_height`, and half a drift upwind
var _bed: AudioStreamPlayer = null
var _drop_material: ShaderMaterial = null     ## the live drop material, kept so the grid can be handed to it
var _sky_img: Image = null                    ## R32F heightfield; texel (cx mod N, cz mod N) = top of world cell
var _sky_tex: ImageTexture = null
var _sky_cell_size: float = 1.0
var _sky_cursor: int = 0                      ## rolling sweep position, so the rays never land in one frame
var _sky_swept: bool = false                  ## false until one full sweep has happened; see _update_sky_grid
var _sky_last_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	local_coords = false     # drops fall through the world, not with the emitter
	randomness = 1.0
	# ⭐ The streak's length follows the drop's own velocity while its face stays turned to the camera. This is
	# the whole fix for "look up and the rain is still vertical lines" — see the class docs. It only works while
	# the drop material's own billboard mode is DISABLED (it would otherwise overwrite this basis), which is why
	# `_build_drop_mesh` turns billboarding off.
	transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	# `fall_speed` is the DOWNWARD speed even when the rain leans, so the column below still takes the time the
	# lifetime says it does; the lean is speed added sideways, not stolen from the fall.
	lifetime = maxf((spawn_height + fall_depth) / maxf(fall_speed, 0.01), 0.05)
	# Ride half a drift UPWIND of the camera: leaning drops are born upwind and land downwind, so an emitter
	# centred overhead would thin out the upwind half of the view by the time the drops reach eye level.
	var drift := _fall_direction() * _fall_speed_along_lean() * lifetime * 0.5
	_emitter_offset = Vector3(-drift.x, spawn_height, -drift.z)
	# Preprocess a full lifetime so the air is already full of rain on the first frame instead of filling in
	# from the top over a second — the same reason AmbientDust preprocesses its motes.
	preprocess = lifetime
	process_material = _build_process_material()
	# BEFORE the mesh: the drop material is handed the heightfield as it is built, and nothing re-assigns it
	# afterwards — the texture object stays the same for the node's whole life, only its contents change.
	_build_sky_grid()
	draw_pass_1 = _build_drop_mesh()
	# Generous, because the emitter chases the camera and the particles do not follow it: a tight box pops the
	# whole field out of view the moment you turn around.
	var pad := Vector3(volume_extents.x, spawn_height, volume_extents.y) * 2.0 + Vector3(10.0, 10.0, 10.0)
	visibility_aabb = AABB(-pad, pad * 2.0)
	amount = maxi(1, drops)   # last: setting amount restarts the system with everything above applied
	_shelter_timer = 0.0
	_shelter_primed = false
	_start_bed()

## The looping rain bed: NON-positional, because rain is not somewhere, it is everywhere. It loops by re-playing
## on `finished` rather than by setting the stream's own loop flag — the `AmbientSound` idiom, and the one that
## does not mutate a shared imported resource that some other scene might also be using.
func _start_bed() -> void:
	# Idempotent: `_ready` runs the moment the node enters the tree, and anything that re-runs it (a rebuild, a
	# test configuring the node and calling it again) must not leave a second player bleating underneath the
	# first — which is exactly what a test caught here.
	if _bed != null:
		_bed.queue_free()
		_bed = null
	if not use_default_sound and sound == null:
		return
	var stream: AudioStream = sound
	if stream == null:
		stream = load(DEFAULT_SOUND_PATH) as AudioStream
	if stream == null:
		push_warning("RainFall: no rain bed — `%s` did not load. The visual rain is unaffected." % DEFAULT_SOUND_PATH)
		return
	_bed = AudioStreamPlayer.new()
	_bed.stream = stream
	_bed.bus = sound_bus
	_bed.volume_db = sound_volume_db
	add_child(_bed)
	_bed.finished.connect(func() -> void:
		if _bed != null:
			_bed.play())
	_bed.play()

func _build_process_material() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# A thin SLAB, not a box: a drop is born at the top of the column and dies at the bottom, so giving the
	# emitter height would just make some drops start halfway down.
	pm.emission_box_extents = Vector3(volume_extents.x, 0.25, volume_extents.y)
	pm.direction = _fall_direction()
	pm.spread = 0.0
	var speed := _fall_speed_along_lean()
	pm.initial_velocity_min = speed * 0.9
	pm.initial_velocity_max = speed * 1.1
	pm.gravity = Vector3.ZERO   # the speed IS the initial velocity; gravity would make the field accelerate
	pm.scale_min = maxf(1.0 - length_variation, 0.05)
	pm.scale_max = 1.0 + length_variation
	pm.color = drop_color
	# ⭐ NO sprite rotation. The lean lives in `direction` above, because the streak is aligned to the velocity
	# and a screen-space roll on top of that would tilt the quad OFF the line the drop is travelling — the drop
	# would visibly slide sideways along its own streak.
	pm.angle_min = 0.0
	pm.angle_max = 0.0
	return pm

## The unit vector a drop travels along: straight down, tipped `lean_degrees` toward `wind_heading_degrees`
## (0 = -Z, 90 = +X). This is both the emission direction AND, through `transform_align`, the streak's axis.
func _fall_direction() -> Vector3:
	var lean := deg_to_rad(clampf(lean_degrees, 0.0, 75.0))
	var heading := deg_to_rad(wind_heading_degrees)
	var horizontal := sin(lean)
	return Vector3(horizontal * sin(heading), -cos(lean), -horizontal * cos(heading)).normalized()

## Speed ALONG that leaned line. `fall_speed` is the authored DOWNWARD speed, so a leaning drop has to travel
## faster than it to still descend at that rate — which is what keeps `lifetime` honest about the column.
func _fall_speed_along_lean() -> float:
	return maxf(fall_speed, 0.01) / maxf(cos(deg_to_rad(clampf(lean_degrees, 0.0, 75.0))), 0.05)

## One drop: a thin quad whose LENGTH is local Y, drawn by `rain_drop.gdshader`.
##
## ⭐ NO StandardMaterial3D and NO billboard flag, and neither is a regression. The node's `transform_align`
## turns the quad's face to the camera already; a material billboard would overwrite that whole basis in the
## vertex shader, which is exactly what used to pin every streak to screen-vertical however you looked. The
## shader then supplies the foreshortening the engine's alignment drops on the floor (see the class docs), which
## no BaseMaterial3D flag can express — unshaded + additive + no cull are all render_modes on it instead.
func _build_drop_mesh() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(maxf(drop_width, 0.001), maxf(drop_length, 0.01))
	var mat := ShaderMaterial.new()
	mat.shader = DROP_SHADER
	# The whole field shares one fall direction (the emitter's spread is 0), so this is a uniform rather than
	# something the shader has to recover per drop — and it is the SAME vector the emitter launches them along.
	mat.set_shader_parameter("fall_direction", _fall_direction())
	mat.set_shader_parameter("end_on_length", clampf(end_on_length, 0.02, 1.0))
	mat.set_shader_parameter("end_on_width", maxf(end_on_width, 1.0))
	# The heightfield, once. `sky_occlusion_enabled` stays FALSE unless the texture really exists, because the
	# shader's fallback for a missing sampler is black — which would read as a roof at y = 0 and cull the world.
	var have_grid := occlude_under_roofs and _sky_tex != null
	mat.set_shader_parameter("sky_occlusion_enabled", have_grid)
	mat.set_shader_parameter("sky_height", _sky_tex)
	mat.set_shader_parameter("sky_cell_size", _sky_cell_size)
	mat.set_shader_parameter("sky_grid_cells", _sky_img.get_width() if _sky_img != null else 1)
	_drop_material = mat
	quad.material = mat
	return quad

## Allocate the heightfield. One texel per world cell, the field as wide as the emitter, and every cell starting
## OPEN so a grid that has not been swept yet errs toward raining rather than toward a phantom roof.
func _build_sky_grid() -> void:
	if not occlude_under_roofs:
		_sky_img = null
		_sky_tex = null
		return
	var n := clampi(sky_grid_cells, 4, 128)
	_sky_cell_size = maxf(maxf(volume_extents.x, volume_extents.y) * 2.0, 1.0) / float(n)
	_sky_img = Image.create(n, n, false, Image.FORMAT_RF)
	var open := Color(SKY_OPEN, 0.0, 0.0)
	for y in n:
		for x in n:
			_sky_img.set_pixel(x, y, open)
	_sky_tex = ImageTexture.create_from_image(_sky_img)
	_sky_cursor = 0
	_sky_swept = false

## Sweep a slice of the heightfield: for each cell, "what is the topmost thing over this patch of world".
##
## ⭐ THE PROBE POINTS DOWN, NOT UP, and that is the whole trick. A ray cast UP from under the field finds the
## first thing above its ORIGIN — stand on the fifth floor and it reports the fourth floor's ceiling, which is
## below you and shelters nothing. Cast DOWN from well above everything and the first hit is the TOPMOST surface
## over that cell, which is exactly the height rain stops at: a street reports the street, a bridge reports its
## deck, a building reports its roof, and every drop below that is under something.
##
## ⭐ WORLD-ANCHORED, WRAPPING INDICES. A cell is `floor(world / cell_size)` and its texel is that modulo the
## grid width, so a texel is a fixed patch of ground however the camera moves; the field scrolls under the player
## like a virtual texture instead of sliding with them (which would shimmer every roof edge as they walked).
## The shader does the identical lookup with a REPEAT sampler, which is the same modulo for free.
func _update_sky_grid(cam: Camera3D) -> void:
	if _sky_img == null or _sky_tex == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var n := _sky_img.get_width()
	var total := n * n
	# ⭐ Sweep the WHOLE grid at once on the first frame and after a teleport. A slice at a time is right while
	# you walk (the rays stay off any one frame's budget) and wrong the instant the field is somewhere else
	# entirely, where every cell is stale and the error is a roomful of rain rather than a late eave.
	var jumped := not _sky_swept or cam.global_position.distance_to(_sky_last_pos) > maxf(volume_extents.x, volume_extents.y)
	_sky_last_pos = cam.global_position
	_sky_swept = true
	var budget: int = total if jumped else clampi(sky_cells_per_frame, 1, total)

	@warning_ignore("integer_division")   # the window is a whole number of cells either side
	var half := n / 2
	var base_x := int(floor(cam.global_position.x / _sky_cell_size)) - half
	var base_z := int(floor(cam.global_position.z / _sky_cell_size)) - half
	var top := cam.global_position.y + maxf(sky_probe_headroom, 1.0)
	var bottom := cam.global_position.y - maxf(fall_depth, 1.0) - 1.0
	for _i in budget:
		var slot := _sky_cursor
		_sky_cursor = (_sky_cursor + 1) % total
		var sx := slot % n
		@warning_ignore("integer_division")   # row index: slots are a flat grid, not a ratio
		var sz := slot / n
		# The one world cell inside the current window whose wrapped index lands on this texel.
		var cx := base_x + posmod(sx - base_x, n)
		var cz := base_z + posmod(sz - base_z, n)
		var from := Vector3((float(cx) + 0.5) * _sky_cell_size, top, (float(cz) + 0.5) * _sky_cell_size)
		var query := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, bottom, from.z))
		query.collision_mask = sky_mask
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		var height: float = SKY_OPEN if hit.is_empty() else (hit["position"] as Vector3).y
		_sky_img.set_pixel(sx, sz, Color(height, 0.0, 0.0))
	_sky_tex.update(_sky_img)

## The height rain stops at over this world position — the same lookup the shader does, for tests and for
## anything else that wants to know whether a spot is under cover. `SKY_OPEN` means nothing is above it.
func sky_height_at(world: Vector3) -> float:
	if _sky_img == null:
		return SKY_OPEN
	var n := _sky_img.get_width()
	var cx := int(floor(world.x / _sky_cell_size))
	var cz := int(floor(world.z / _sky_cell_size))
	return _sky_img.get_pixel(posmod(cx, n), posmod(cz, n)).r

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Ride above whatever camera is rendering. World-space particles stay where they were born, so this moves
	# only where NEW drops appear.
	global_position = cam.global_position + _emitter_offset

	# Per-drop occlusion runs on its own, whatever the shelter probe below decides: the drops cull themselves
	# against this, and the emitter is left alone.
	if occlude_under_roofs:
		_update_sky_grid(cam)

	if not stop_when_sheltered:
		emitting = true
		_fade_bed(delta, sound_volume_db)
		return
	_shelter_timer -= delta
	# Re-probe EARLY once the camera has moved far enough that the last answer cannot be trusted, whatever the
	# throttle says — a doorway taken at a run is most of an interval's worth of stride, and a fixed interval is
	# exactly what leaves rain falling through the ceiling for the first step inside.
	var moved := cam.global_position.distance_squared_to(_shelter_sample_pos) > SHELTER_RESAMPLE_DISTANCE * SHELTER_RESAMPLE_DISTANCE
	var first_sample := false
	if _shelter_timer <= 0.0 or moved:
		_shelter_timer = maxf(shelter_check_interval, 0.05)
		_shelter_sample_pos = cam.global_position
		_sheltered = _is_sheltered(cam)
		first_sample = not _shelter_primed
		_shelter_primed = true
	# ⭐ WITH OCCLUSION ON, THE EMITTER NEVER STOPS. Stopping it is what blanked the rain you could see out of a
	# doorway; the heightfield already hides exactly the drops that are under something, and the ones the roof
	# itself is in front of were always hidden by the depth test. Only the fallback path still cuts the field —
	# and there, stopping EMISSION rather than hiding the node lets the drops in flight finish falling, so cover
	# tails off instead of the rain vanishing between one frame and the next.
	emitting = true if occlude_under_roofs else not _sheltered
	# ⭐ THE FIRST PROBE IS THE ONE EXCEPTION TO THAT TAIL-OFF. `_ready` preprocesses a whole lifetime so the air
	# is already full on frame one — right under open sky, wrong under a roof, where a level that starts you
	# indoors would otherwise open with a second of rain pouring through the ceiling. Clearing the field once,
	# and only on the first sample, kills that without costing a doorway its tail.
	# ⭐ And it runs AFTER the flag above, not inside the probe block: `restart()` switches emitting back ON, so
	# clearing the field first and setting the flag second would quietly undo the cutoff.
	if first_sample and _sheltered and not occlude_under_roofs:
		restart()
		emitting = false
	# The bed DUCKS rather than stopping — you still hear rain on the roof over your head.
	_fade_bed(delta, sheltered_volume_db if _sheltered else sound_volume_db)

## Walk the bed's level toward `target_db` at `sound_fade_db_per_second`, so a doorway is a transition.
func _fade_bed(delta: float, target_db: float) -> void:
	if _bed == null:
		return
	var step := maxf(sound_fade_db_per_second, 0.0) * delta
	_bed.volume_db = move_toward(_bed.volume_db, target_db, step)

## Is anything between this camera and the sky? ⭐ THE PLAYER'S FLAG IS AN INPUT, NOT THE ANSWER.
## `IndoorAmbienceDucker` publishes `is_indoors` from a 6 m ceiling scan on the player, which answers "am I in a
## room" — a strictly smaller question than this one. Taking it as the whole verdict is what let rain fall
## through bridges, gantries, awnings and any roof higher than its scan; and since `Player.is_indoors` is a
## plain `false` by default, a level with no ducker in it made the fan below unreachable instead of a fallback.
## So indoors SHORT-CIRCUITS to sheltered (it cannot be wrong in that direction) and the fan decides the rest.
func _is_sheltered(cam: Camera3D) -> bool:
	var player := Groups.human_player(get_tree())
	if player != null and player.get(&"is_indoors") == true:
		return true
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var reach := Vector3(0.0, maxf(shelter_probe_height, 0.1), 0.0)
	var radius := maxf(shelter_probe_radius, 0.0)
	var hits := 0
	for offset: Vector3 in SHELTER_OFFSETS:
		var from: Vector3 = cam.global_position + offset * radius
		var query := PhysicsRayQueryParameters3D.create(from, from + reach)
		query.collision_mask = shelter_mask
		query.collide_with_areas = false
		if not space.intersect_ray(query).is_empty():
			hits += 1
	return float(hits) / float(SHELTER_OFFSETS.size()) >= clampf(shelter_coverage, 0.05, 1.0)

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if drops > 20000:
		w.append("%d drops is a lot for a field that is entirely on screen — this one rides the camera, so it does not need a map's worth of particles." % drops)
	if fall_depth <= 0.0 or spawn_height <= 0.0:
		w.append("`spawn_height` and `fall_depth` must both be positive — together they are the column a drop falls down, and a zero column gives every drop a zero lifetime.")
	if occlude_under_roofs and sky_grid_cells * sky_grid_cells > sky_cells_per_frame * 30:
		w.append("A %d×%d sky grid refreshed %d cells a frame takes %.1f s to sweep — long enough that a roof edge lags visibly behind you. Raise `sky_cells_per_frame` or drop `sky_grid_cells`." % [
			sky_grid_cells, sky_grid_cells, sky_cells_per_frame,
			float(sky_grid_cells * sky_grid_cells) / float(maxi(sky_cells_per_frame, 1)) / 60.0])
	if AudioServer.get_bus_index(sound_bus) < 0:
		w.append("`sound_bus` '%s' isn't in the project's audio bus layout — the bed would fall back to Master, escaping both the Ambient volume slider and the indoor muffle." % str(sound_bus))
	if drop_length <= drop_width:
		w.append("`drop_length` (%.3f) is not longer than `drop_width` (%.3f) — rain reads as rain because it is a STREAK; square drops read as snow." % [drop_length, drop_width])
	return w
