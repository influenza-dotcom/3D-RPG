@tool
class_name ThrowTrail
extends Node3D

## Drop-in white STREAK for a thrown prop — the thrown-weapon tracer. Child one of these to a `Throwable`
## (or to any `RigidBody3D`) and a REAL THROW drags a tapering, fading ribbon of light behind the prop
## through its whole arc. Nothing to wire: it walks up for its host body, samples that body's position
## every physics frame while it is in flight, and rebuilds a camera-facing ribbon through those samples.
## EVERY weapon drop carries one (`WeaponData.thrown_trail` defaults ON); it started life knife-only.
##
## WHERE THE STREAK COMES FROM is THIS NODE's position, not the body origin — so a designer aims it by
## dragging the child node onto the blade's tip, and because the node rides the prop's own basis the origin
## follows the nose of a prop that noses toward its travel (`Throwable.face_travel_when_thrown`).
## The corollary matters for a prop that does NOT nose (every gun): an OFFSET node on a TUMBLING body orbits
## the centre of mass and scribbles a corkscrew instead of a line, so leave it at the body origin unless the
## prop's facing is pinned. `WorldItem._make_throwable` builds weapon drops that way on purpose — the
## component it stamps gets no offset at all.
##
## WHERE THE RIBBON LIVES, AND WHY IT IS NOT PARENTED UNDER THE PROP: the MeshInstance3D goes to the TREE
## ROOT (the `GunFX.spawn_tracer` convention). TWO sweeps over a Throwable's descendants would otherwise
## dress the streak as if it were part of the prop, and both go through `TalkHelpers.collect_meshes`:
##   * `Throwable._setup_overlay_chain` stamps the flash overlay, the outline RING (a tint duplicate under
##     every mesh) AND the `InkOutline.ACTOR_INK_MASK_LAYER` bit onto EVERY MeshInstance3D under the prop
##     — a black-outlined ribbon, re-rendered in BOTH of the ink pass's extra scene renders. Child `_ready`
##     runs BEFORE the parent's, so an eagerly-built ribbon would always be there in time to be caught.
##   * `Throwable._set_carried_transparency` fades that same set while the prop is carried.
## (`Ps1Applier` is NOT one of them and is no reason to root-parent: its walk returns on `node is Throwable`
## before recursing, so it never visits a prop's descendants — and it skips transparent materials anyway.)
## Root-parenting also means the geometry is authored in plain WORLD space against an identity transform
## (the AiDebugDraw idiom) — no `top_level` dance, and none of the stale-world-transform trap that costs
## NpcLaser a `reset_for_reuse`. `_exit_tree` frees the ribbon, so a prop destroyed, picked up into a
## backpack, or unloaded by a level swap mid-flight takes its streak with it.
##
## THE MATERIAL MUST STAY TRANSPARENT. It is `TRANSPARENCY_ALPHA` with the default depth-draw mode
## (`DEPTH_DRAW_OPAQUE_ONLY`), so it writes neither depth nor normal-roughness — and that is the ONLY
## reason `ink_outline.gdshader`'s edge detect cannot see it: writing no depth is what hides THIS mesh — the
## `bulletmat.tres` trick, not a layer trick. (The ink pass does have a layer mechanism, but it is the ACTOR
## mask, for meshes that carry an outline RING of their own; stamping a streak into it would only buy a
## second scene render.) Give this an OPAQUE material and every streak gets a black ink line drawn around it.
##
## The shape knobs default to 0 = "inherit the global tuning" (`GameSettings.effects`, the
## "Thrown weapon trail" group), the `Throwable.face_travel_min_speed` sentinel idiom, so every streak in
## the game tunes from one place and a single prop can still override.
##
## `@tool` ONLY so `_get_configuration_warnings` reports an unparented streak in the Inspector — there is no
## editor lifecycle here, and every runtime entry point returns early under `Engine.is_editor_hint()` so the
## editor never touches the `GameSettings` autoload (which an editor-side read would spam warnings over).

## Smallest distance (m) the host must cover before a new sample is taken. An epsilon, not a feel knob: two
## samples closer than this produce a zero-length span whose tangent is numerically meaningless (a NaN
## basis), and at the speeds that pass `min_speed` a 60 Hz tick covers many times this.
const MIN_STEP: float = 0.015
## Below this squared length a cross product is treated as degenerate (parallel inputs) and the next
## fallback axis is tried — the `GunFX.spawn_tracer` guard, which a throw straight up or down needs.
const DEGENERATE_SQ: float = 0.000001

@export_group("Look")
## Streak colour, alpha included. WHITE is the shipped tracer, on every weapon: it reads at any distance
## against this game's dark interiors, and (being unshaded) it is the same white in a lit street and an unlit
## basement. A weapon drop takes this from `WeaponData.thrown_trail_color`.
@export var color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Ribbon width (m) at the HEAD — the end still attached to the prop. It tapers to nothing at the tail, so
## this is the widest the streak ever gets. 0 inherits `GameSettings.effects.throw_trail_width`.
@export var width: float = 0.0
## Seconds a point of streak lingers before it ages out, i.e. how LONG the tail is in time rather than in
## metres (a faster throw draws a longer streak for the same value). 0 inherits
## `GameSettings.effects.throw_trail_lifetime`.
@export var lifetime: float = 0.0

@export_group("When It Streaks")
## Speed (m/s) the host must be moving to lay NEW streak. This is what ends the effect on landing: the
## ribbon stops growing and the existing tail ages out over `lifetime`. 0 inherits
## `GameSettings.effects.throw_trail_min_speed`.
@export var min_speed: float = 0.0
## Require a real THROW (`Throwable.mark_thrown_for_trail`, armed by PickupRay / the grapple fling) before
## anything is drawn — so a knife nudged off a table, or dropped at your feet, never streaks. Turn OFF for
## a prop with no thrower at all (a launched hazard, a prop flung by an explosion), which then streaks
## purely on the speed gate. Also OFF is the only mode a non-Throwable RigidBody3D host can use.
@export var require_thrown: bool = true
## Cap on live samples. Bounds the per-frame rebuild: the ribbon is 2 vertices per sample and is rebuilt
## from scratch each physics frame, so this is the effect's whole cost. Reached only if `lifetime` is long
## enough to hold more than this many ticks. 0 inherits `GameSettings.effects.throw_trail_max_points`.
@export var max_points: int = 0

var _ribbon: MeshInstance3D = null  ## the world-space ribbon, parented to the tree root and built on first use
var _mesh: ImmediateMesh = null
var _host: RigidBody3D = null  ## the thrown body this streak follows (nearest RigidBody3D ancestor)
var _points: PackedVector3Array = PackedVector3Array()  ## world-space samples, OLDEST first
var _ages: PackedFloat32Array = PackedFloat32Array()  ## seconds since each sample was taken, parallel to _points
var _was_armed: bool = false  ## previous frame's armed state, so a fresh throw's RISING EDGE can drop a stale tail

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_host = _nearest_body()

func _exit_tree() -> void:
	# The ribbon is not our child (see the class doc), so nothing frees it for us.
	_free_ribbon()

## Editor warning: with no RigidBody3D ancestor there is nothing whose flight to trace — the streak would
## silently never appear, which is the hardest kind of miswiring to notice on a cosmetic effect.
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if _nearest_body() == null:
		w.append("No RigidBody3D ancestor — a ThrowTrail traces a thrown BODY, so child it to the Throwable (or another RigidBody3D), not to the level.")
	return w

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not GameSettings.effects.throw_trail_enabled:
		if not _points.is_empty() or is_instance_valid(_ribbon):
			_reset_points()
			_free_ribbon()  # switching the effect off mid-flight takes any live streak with it
		_was_armed = false
		return
	var armed := _armed()
	if armed and not _was_armed:
		# Rising edge of a fresh throw. A prop caught and re-thrown inside one `lifetime` would otherwise
		# draw one long segment bridging where the last throw ended to where this one began.
		_reset_points()
	_was_armed = armed
	if _points.is_empty() and not armed:
		return  # carried, or resting: nothing to age and nothing to draw
	_age_points(delta)
	if armed and _host_speed() >= _resolved_min_speed():
		_sample_point()
	_rebuild()

# --- Gates ---------------------------------------------------------------------------------------------

## Is the host on a real throw right now? Duck-typed through `is_trailing()` rather than typed against
## `Throwable`: this component gets dropped onto props whose script sits on the actor parse path, and a
## mutual `class_name` reference between the two is how a parse cycle starts. `require_thrown` off skips
## the question entirely, leaving the speed gate as the only condition.
func _armed() -> bool:
	if not is_instance_valid(_host):
		return false
	if not require_thrown:
		return true
	if not _host.has_method(&"is_trailing"):
		return false
	return bool(_host.call(&"is_trailing"))

func _host_speed() -> float:
	if not is_instance_valid(_host):
		return 0.0
	return _host.linear_velocity.length()

# --- Sample buffer -------------------------------------------------------------------------------------

func _sample_point() -> void:
	var p := global_position
	if not _points.is_empty() and p.distance_to(_points[_points.size() - 1]) < MIN_STEP:
		return  # hasn't moved far enough to make a span worth drawing
	_points.append(p)
	_ages.append(0.0)
	var cap := _resolved_max_points()
	while _points.size() > cap:
		_points.remove_at(0)
		_ages.remove_at(0)

## Age every sample and retire the ones past `lifetime`. Samples are appended in time order, so index 0 is
## always the OLDEST and the retirement can stop at the first survivor.
func _age_points(delta: float) -> void:
	var life := _resolved_lifetime()
	for i in _ages.size():
		_ages[i] += delta
	while not _ages.is_empty() and _ages[0] >= life:
		_points.remove_at(0)
		_ages.remove_at(0)

func _reset_points() -> void:
	_points.clear()
	_ages.clear()

# --- Geometry ------------------------------------------------------------------------------------------

## Rebuild the whole ribbon from the live samples: one camera-facing quad strip, width tapering to a point
## at the tail, alpha fading with age. Cheap enough to redo every frame at these sample counts, and doing
## it from scratch is what keeps the buffer the single source of truth.
func _rebuild() -> void:
	var count := _points.size()
	if count < 2:
		# A SPENT streak leaves no node behind: once the last sample has aged out the ribbon is freed outright
		# rather than parked empty, so a knife lying on the floor costs nothing until it is thrown again (the
		# same reason it is built lazily). A single surviving sample can't make a strip, but more are coming —
		# just clear the surface for that frame.
		if _points.is_empty():
			_free_ribbon()
		elif _mesh != null:
			_mesh.clear_surfaces()
		return
	_ensure_ribbon()
	if _mesh == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var life := _resolved_lifetime()
	var half_width := _resolved_width() * 0.5
	var reference_dist: float = GameSettings.effects.throw_trail_reference_dist
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in count:
		var p := _points[i]
		# No camera (headless, or a frame with none active): fall back to a fixed view direction so the
		# ribbon still has a well-defined side vector instead of collapsing to a line.
		var to_camera := (cam.global_position - p) if cam != null else Vector3.BACK
		var side := side_vector(_tangent_at(i), to_camera)
		var half := half_width * taper(i, count) * width_compensation(to_camera.length(), reference_dist)
		var c := color
		c.a = color.a * fade(_ages[i], life)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p - side * half)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p + side * half)
	_mesh.surface_end()

## Direction the ribbon runs at sample `i`: a central difference where there are neighbours on both sides,
## a one-sided difference at the ends. Falls back to the host's travel direction (then a fixed axis) when
## the neighbours coincide, so a degenerate span can never emit a NaN vertex.
func _tangent_at(i: int) -> Vector3:
	var count := _points.size()
	var back: Vector3 = _points[maxi(i - 1, 0)]
	var forward: Vector3 = _points[mini(i + 1, count - 1)]
	var t := forward - back
	if t.length_squared() >= DEGENERATE_SQ:
		return t.normalized()
	var vel := _host.linear_velocity if is_instance_valid(_host) else Vector3.ZERO
	if vel.length_squared() >= DEGENERATE_SQ:
		return vel.normalized()
	return Vector3.FORWARD

## Ribbon half-width scale at sample `index` of `count`: 0 at the OLDEST sample, 1 at the newest. The
## streak is therefore widest where it leaves the prop and comes to a point behind it — the shape that
## reads as motion rather than as a floating stick. Pure + static so the taper is unit-testable.
static func taper(index: int, count: int) -> float:
	if count < 2:
		return 1.0
	return clampf(float(index) / float(count - 1), 0.0, 1.0)

## Alpha multiplier for a sample `age` seconds old: 1 when just laid, 0 once it has lived `lifetime`. A
## non-positive lifetime draws nothing at all (rather than dividing by zero), so a mis-authored 0 fails
## invisibly instead of leaving a permanent streak welded across the level.
static func fade(age: float, life: float) -> float:
	if life <= 0.0:
		return 0.0
	return clampf(1.0 - age / life, 0.0, 1.0)

## Width multiplier that keeps a far-off streak readable: 1 inside `reference_dist`, growing in proportion
## beyond it, so the ribbon holds roughly its screen-space thickness instead of thinning to a flickering
## sub-pixel line down a long street. Copied in shape from `GunFX.spawn_tracer`, INCLUDING its clamp — this
## may only ever make a streak wider than authored, never thinner, so the close-range look is untouched. A
## non-positive reference distance disables it rather than dividing by zero. Pure + static.
static func width_compensation(view_dist: float, reference_dist: float) -> float:
	if reference_dist <= 0.0:
		return 1.0
	return maxf(1.0, view_dist / reference_dist)

## The ribbon's sideways axis at a sample: perpendicular to both the direction of travel and the direction
## to the camera, which is what turns two vertices per sample into a quad that always faces the viewer.
## Degenerate inputs (looking straight down the streak's own axis, where any side is equally right) walk a
## fallback chain: to_camera -> UP -> FORWARD -> the RIGHT constant. It is the `GunFX.spawn_tracer` guard
## extended, NOT copied — that one is UP -> FORWARD with no terminator, which is exhaustive there because its
## direction is always unit-length. This one's `tangent` can arrive as ZERO (every cross is then zero), so the
## constant is what keeps a NaN out of the vertex buffer. Pure + static.
static func side_vector(tangent: Vector3, to_camera: Vector3) -> Vector3:
	var fallbacks: Array[Vector3] = [to_camera, Vector3.UP, Vector3.FORWARD]
	for axis in fallbacks:
		var s := tangent.cross(axis)
		if s.length_squared() >= DEGENERATE_SQ:
			return s.normalized()
	return Vector3.RIGHT

# --- The ribbon node -----------------------------------------------------------------------------------

## Build the ribbon on FIRST USE rather than in `_ready`. Two reasons: adding to the tree root while the
## rest of the scene is still running `_ready` races the "parent node is busy setting up children" error
## (the hazard NpcLaser documents), and a prop that is never thrown — every crate in the level — then
## costs nothing at all, not even an empty MeshInstance3D.
func _ensure_ribbon() -> void:
	if is_instance_valid(_ribbon):
		return
	if not is_inside_tree():
		return
	_mesh = ImmediateMesh.new()
	_ribbon = MeshInstance3D.new()
	_ribbon.name = "ThrowTrailRibbon"
	_ribbon.mesh = _mesh
	_ribbon.material_override = build_material()
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbon.layers = 1  # the world layer, like every other code-spawned world visual (see WorldItem._make_world_renderable)
	get_tree().root.add_child(_ribbon)
	_ribbon.global_transform = Transform3D.IDENTITY  # vertices are authored in world space; keep local == world

func _free_ribbon() -> void:
	if is_instance_valid(_ribbon):
		_ribbon.queue_free()
	_ribbon = null
	_mesh = null

## The streak's material. UNSHADED (a tracer is its own light source, and this way it is the same white in
## a lit street and an unlit basement) with per-vertex colour so the taper's fade rides the geometry, and
## CULL_DISABLED because a ribbon is a one-sided strip you can end up behind. TRANSPARENCY_ALPHA is
## load-bearing beyond the fade — see the class doc: it is what keeps the streak out of the ink pass.
## Built per instance, never a shared preloaded resource, so a per-prop colour can never bleed across props.
static func build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return mat

# --- Host + resolved tuning ----------------------------------------------------------------------------

## Nearest RigidBody3D ancestor, or null. Walks up rather than requiring a wired `@export`: this component
## is dropped in, and on a code-built weapon drop (WorldItem._make_throwable) there is no scene to wire.
func _nearest_body() -> RigidBody3D:
	var n := get_parent()
	while n != null:
		if n is RigidBody3D:
			return n as RigidBody3D
		n = n.get_parent()
	return null

## Per-instance override (> 0) else the global tuning value — the `Throwable._resolved_face_travel_min_speed`
## sentinel idiom, so the whole Look/When-It-Streaks surface tunes globally by default.
func _resolved_width() -> float:
	return width if width > 0.0 else GameSettings.effects.throw_trail_width

func _resolved_lifetime() -> float:
	return lifetime if lifetime > 0.0 else GameSettings.effects.throw_trail_lifetime

func _resolved_min_speed() -> float:
	return min_speed if min_speed > 0.0 else GameSettings.effects.throw_trail_min_speed

## Floored at 2: one sample cannot make a ribbon, and a 0/1 cap would let the buffer never hold a drawable
## pair while still doing all the sampling work.
func _resolved_max_points() -> int:
	var cap: int = max_points if max_points > 0 else GameSettings.effects.throw_trail_max_points
	return maxi(cap, 2)
