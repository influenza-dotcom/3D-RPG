extends GutTest

## The thrown-weapon white STREAK (`ThrowTrail`, scripts/components/throw_trail.gd) — the tracer any thrown
## weapon drags behind it (knife-only when it shipped; game-wide since).
##
## SCOPE, in three layers, because the middle one is where this class of effect actually dies:
##   1. The pure ribbon math (taper / fade / side_vector / width_compensation) and the 0-inherits-tuning
##      resolution chain — off-tree, no camera, no physics.
##   2. THE CHAIN ACTUALLY RUNS: a real Throwable, in the real tree, actually thrown, actually laying geometry,
##      and cleaning it up afterwards. The PIN kill shipped once with every unit test green and did nothing in
##      game (see tests/test_pin_kill_integration.gd); a per-frame cosmetic effect has the identical failure mode
##      — nothing is wrong with any piece, the chain just never fires — and no static test can see it.
##   3. The authoring seam: WeaponData.thrown_trail -> a ThrowTrail child on the drop, for EVERY weapon (the
##      flag defaults ON; the negative case is a weapon that deliberately opts out).
##
## NOT covered here (and deliberately): how it LOOKS. Width, tail length and the "does the Borderlands ink pass
## draw a black line around it" question are answered by a windowed render against the real driver, never headless
## — headless has no camera and never compiles a shader.
##
## `Throwable` is safe in-tree (unlike NPC / Player — see CLAUDE.md): its _ready arms contact monitoring, auto-fits
## the collider and builds the overlay chain, touching no weapon scene, nav agent or audio.

const TRAIL_PATH := "res://scripts/components/throw_trail.gd"
const ThrowableScript := preload("res://scripts/components/Throwable.gd")
## Preloaded by PATH rather than used through its `ThrowTrail` class_name: a brand-new class_name is not in the
## engine's global script cache until an import pass has run, and a test that only compiles after a reimport is a
## test that fails the first time anyone runs it.
const TrailScript := preload("res://scripts/components/throw_trail.gd")
const RIBBON_NAME := "ThrowTrailRibbon"

const FLIGHT_TICKS := 8   ## physics ticks of flight — enough samples for a strip several segments deep
const DECAY_TICKS := 30   ## comfortably past the 0.22 s default lifetime at 60 Hz

# --- 1. The ribbon math ---------------------------------------------------------------------------------

func test_taper_runs_from_a_point_at_the_tail_to_full_width_at_the_head() -> void:
	# The streak is widest where it leaves the prop and comes to a point behind it — the shape that reads as
	# motion. Index 0 is the OLDEST sample (see ThrowTrail._age_points), so the taper must start there at 0.
	assert_eq(TrailScript.taper(0, 5), 0.0, "the oldest sample is the tail point — zero width")
	assert_eq(TrailScript.taper(4, 5), 1.0, "the newest sample is full width, at the prop")
	assert_gt(TrailScript.taper(3, 5), TrailScript.taper(1, 5), "width grows monotonically toward the head")
	assert_eq(TrailScript.taper(0, 1), 1.0,
		"a single sample degrades to full width rather than dividing by count - 1 == 0")

func test_fade_empties_a_sample_over_its_lifetime() -> void:
	assert_eq(TrailScript.fade(0.0, 0.2), 1.0, "a sample just laid is fully opaque")
	assert_almost_eq(TrailScript.fade(0.1, 0.2), 0.5, 0.0001, "a half-aged sample is at half alpha")
	assert_eq(TrailScript.fade(0.2, 0.2), 0.0, "a sample at its lifetime has faded out")
	assert_eq(TrailScript.fade(0.4, 0.2), 0.0, "and never goes negative past it")
	assert_eq(TrailScript.fade(0.05, 0.0), 0.0,
		"a zero lifetime draws NOTHING rather than dividing by zero — a mis-authored 0 must fail invisibly, not weld a permanent streak across the level")

func test_side_vector_is_a_unit_axis_across_travel_even_when_degenerate() -> void:
	var side := TrailScript.side_vector(Vector3.FORWARD, Vector3.RIGHT)
	assert_almost_eq(side.length(), 1.0, 0.0001, "the ribbon's side axis is a unit vector")
	assert_almost_eq(side.dot(Vector3.FORWARD), 0.0, 0.0001, "and is perpendicular to the direction of travel")
	# Looking straight down the streak's own axis: any side is equally correct, but a zero vector would collapse
	# the ribbon to nothing (and normalizing it is a NaN). A knife thrown straight up hits exactly this.
	assert_almost_eq(TrailScript.side_vector(Vector3.UP, Vector3.UP).length(), 1.0, 0.0001,
		"a degenerate view direction still yields a unit side via the UP -> FORWARD -> RIGHT fallback chain")
	assert_almost_eq(TrailScript.side_vector(Vector3.ZERO, Vector3.ZERO).length(), 1.0, 0.0001,
		"and so does a fully degenerate pair")

func test_width_compensation_only_ever_widens_a_distant_streak() -> void:
	# The GunFX.spawn_tracer clamp, and for the same reason: a far-off ribbon that thins below a pixel breaks up
	# into a flickering dotted line. It may never make a streak THINNER than authored, or the close-range look
	# (which is what the width is tuned against) would change with camera distance.
	assert_eq(TrailScript.width_compensation(2.0, 6.0), 1.0, "inside the reference distance nothing changes")
	assert_eq(TrailScript.width_compensation(6.0, 6.0), 1.0, "and at exactly the reference distance")
	assert_almost_eq(TrailScript.width_compensation(18.0, 6.0), 3.0, 0.0001,
		"three times the reference distance widens three times, holding screen-space thickness")
	assert_eq(TrailScript.width_compensation(50.0, 0.0), 1.0,
		"a non-positive reference distance disables compensation instead of dividing by zero")

func test_shape_knobs_inherit_the_global_tuning_until_overridden() -> void:
	# The Throwable.face_travel_min_speed sentinel idiom: 0 means "inherit", so every streak in the game tunes
	# from EffectsSettings and a single prop can still opt out.
	var t = TrailScript.new()
	assert_eq(t.width, 0.0, "width defaults to 0 = inherit the global tuning")
	assert_eq(t.lifetime, 0.0, "lifetime defaults to 0 = inherit")
	assert_eq(t.min_speed, 0.0, "min_speed defaults to 0 = inherit")
	assert_eq(t.max_points, 0, "max_points defaults to 0 = inherit")
	assert_eq(t.color, Color(1.0, 1.0, 1.0, 1.0), "the shipped streak is WHITE")
	assert_true(t.require_thrown,
		"a streak needs a real THROW by default — a knife nudged off a table must not draw one")
	assert_almost_eq(t._resolved_width(), GameSettings.effects.throw_trail_width, 0.0001,
		"an unset width resolves to GameSettings.effects.throw_trail_width")
	assert_almost_eq(t._resolved_lifetime(), GameSettings.effects.throw_trail_lifetime, 0.0001,
		"an unset lifetime resolves to the tuning value")
	assert_almost_eq(t._resolved_min_speed(), GameSettings.effects.throw_trail_min_speed, 0.0001,
		"an unset min_speed resolves to the tuning value")
	t.width = 0.5
	assert_almost_eq(t._resolved_width(), 0.5, 0.0001, "a per-instance width wins over the tuning value")
	t.free()

func test_resolved_max_points_is_floored_at_a_drawable_pair() -> void:
	var t = TrailScript.new()
	t.max_points = 1
	assert_eq(t._resolved_max_points(), 2,
		"one sample cannot make a strip — a 0/1 cap would do all the sampling work and never draw")
	t.free()

# --- 2. The arm, on the Throwable ----------------------------------------------------------------------

func test_a_prop_only_trails_once_it_has_been_thrown() -> void:
	var t = ThrowableScript.new()
	assert_false(t.is_trailing(), "a prop sitting in the level is not trailing")
	t.mark_thrown_for_trail()
	assert_true(t.is_trailing(), "a real THROW arms the streak")
	t.on_picked_up(null)
	assert_false(t.is_trailing(), "catching it out of the air ends that throw")
	t.free()

func test_the_arm_is_unconditional_unlike_the_facing_arm() -> void:
	# mark_thrown_for_facing consults the prop's own face_travel_when_thrown opt-in; the trail arm deliberately
	# does not, because whether anything is DRAWN is the ThrowTrail child's business (and a prop without one
	# ignores the flag entirely). Pinned because the two are armed side by side at the same call site.
	var t = ThrowableScript.new()
	t.face_travel_when_thrown = false
	t.mark_thrown_for_facing()
	t.mark_thrown_for_trail()
	assert_false(t.get("_facing_travel"), "the facing arm respects its opt-in")
	assert_true(t.is_trailing(), "the streak arm does not need one")
	t.free()

# --- 3. The chain, in the tree -------------------------------------------------------------------------

func test_a_thrown_prop_lays_a_ribbon_and_takes_it_away_again() -> void:
	var body = _blade()
	add_child_autofree(body)
	body.global_position = Vector3(0.0, 20.0, 0.0)  # well clear of anything, so nothing interrupts the flight
	assert_null(_ribbon(), "a prop that has not been thrown builds nothing at all")

	body.linear_velocity = Vector3(0.0, 0.0, -30.0)  # the knife's real launch speed (12 impulse x 2.5)
	body.mark_thrown_for_trail()
	for _i in FLIGHT_TICKS:
		await get_tree().physics_frame

	var ribbon := _ribbon()
	assert_not_null(ribbon, "a thrown prop lays a ribbon — THE check no static test can make")
	if ribbon == null:
		return
	assert_eq(ribbon.get_parent(), get_tree().root,
		"the ribbon lives at the tree ROOT, not under the prop: every MeshInstance3D under a Throwable is swept by _setup_overlay_chain (black hull + ink mask bit) and by the carried-transparency fade")
	assert_eq(ribbon.layers, 1, "it renders on the world layer only — no InkOutline actor-mask bit")
	assert_true(ribbon.global_transform.is_equal_approx(Transform3D.IDENTITY),
		"and at an identity transform, because its vertices are authored in world space")
	var mat := ribbon.material_override as StandardMaterial3D
	assert_not_null(mat, "the ribbon wears its own material")
	if mat != null:
		assert_eq(mat.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA,
			"which MUST stay transparent: writing no depth is the only reason ink_outline.gdshader's edge detect can't see the streak and ring it in black")

	var mesh := ribbon.mesh as ImmediateMesh
	assert_not_null(mesh, "the ribbon carries an ImmediateMesh")
	if mesh == null:
		return
	assert_eq(mesh.get_surface_count(), 1, "one strip surface was built")
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_gte(verts.size(), 8, "the strip is several segments deep (2 vertices per sample)")
	assert_eq(verts.size() % 2, 0, "and closes every pair")
	assert_eq(colors.size(), verts.size(), "every vertex carries its own colour — the age fade rides the geometry")
	assert_gt(colors[colors.size() - 1].a, colors[0].a,
		"alpha ramps from a faded tail to a bright head, so the streak reads as direction of travel")
	assert_gt(verts[verts.size() - 1].distance_to(verts[verts.size() - 2]), verts[1].distance_to(verts[0]),
		"and so does width: widest at the prop, a point at the tail")
	var head: Vector3 = (verts[verts.size() - 1] + verts[verts.size() - 2]) * 0.5
	assert_lt(head.distance_to(body.global_position), 1.0,
		"the head of the streak is ON the prop, not left behind at the throw point")

	# Ending the throw must FADE the tail out, not cut it — and then leave nothing behind. Checked a FRAME
	# LATER, not on the line after the disarm: a same-line assert cannot fail under any implementation,
	# including one that drops the whole ribbon the instant the arm clears, which is the thing being ruled out.
	body.on_picked_up(null)
	await get_tree().physics_frame
	var surviving := _ribbon()
	assert_not_null(surviving, "the tail survives the frame after the throw ends — it fades, it doesn't cut")
	if surviving != null:
		var still := surviving.mesh as ImmediateMesh
		assert_true(still != null and still.get_surface_count() == 1,
			"and it is still DRAWING that frame, not an emptied node")
	for _i in DECAY_TICKS:
		await get_tree().physics_frame
	assert_null(_ribbon(),
		"once the last sample ages out the ribbon is freed outright — a spent streak leaves no node parked at the root")

func test_a_prop_that_is_merely_dropped_never_streaks() -> void:
	# The whole point of the arm: PickupRay._release calls mark_thrown_for_trail only inside its `is_throw`
	# branch, so a tap-drop and the forced death/quickload release reach the tree at speed but draw nothing.
	var body = _blade()
	add_child_autofree(body)
	body.global_position = Vector3(0.0, 20.0, 0.0)
	body.linear_velocity = Vector3(0.0, 0.0, -30.0)  # moving fast — the ONLY thing missing is the throw
	for _i in FLIGHT_TICKS:
		await get_tree().physics_frame
	assert_null(_ribbon(), "speed alone does not draw a streak; a real throw is required")

func test_the_arm_is_released_once_the_prop_comes_to_rest() -> void:
	# The regression this exists for: with no rest release, a knife you threw and never picked up stays armed
	# for the rest of the level, so the NEXT thing to shove it past the speed gate — a blast, a grapple
	# reel-in, a fall off a ledge — draws a streak nobody threw, which is exactly what require_thrown promises
	# cannot happen. `sleeping` is the release because it cannot fire mid-flight, unlike a speed threshold
	# (a knife thrown straight up passes through zero velocity at its apex).
	var body = _blade()
	add_child_autofree(body)
	body.global_position = Vector3(0.0, 20.0, 0.0)
	body.gravity_scale = 0.0  # hold it still so the engine's sleep state is the only variable under test
	body.linear_velocity = Vector3.ZERO
	# One frame BEFORE touching `sleeping`: the body has to be registered with the physics server, or the write
	# lands on a body that does not exist yet and is lost when it is added.
	await get_tree().physics_frame
	body.mark_thrown_for_trail()
	assert_true(body.is_trailing(), "armed by the throw")
	body.sleeping = true
	await get_tree().physics_frame
	assert_true(body.sleeping, "the body really did go to sleep (guard: this test is worthless if it didn't)")
	assert_false(body.is_trailing(),
		"a prop that has come to rest is no longer mid-throw — the arm must not outlive the flight")

# --- 4. The authoring seam -----------------------------------------------------------------------------

func test_every_weapon_drop_carries_a_streak() -> void:
	# The stamp WorldItem._make_throwable applies. Asserted end-to-end (build the actual drop and look for the
	# child) rather than by reading the flag back, because the stamp is the part that can silently go missing —
	# thrown_pins_body_part sat stamped-but-unasserted for exactly that reason.
	#
	# EVERY weapon streaks now, not just the blade — the tracer reads as "the thing you threw is over THERE",
	# which a hurled pistol needs as much as a knife does. This used to be the test that pinned the gun OFF, so it
	# is deliberately the same shape inverted: the whole droppable roster is walked and each one must produce a
	# real ThrowTrail child on a real built drop. The roster is spelled out rather than globbed so a NEW weapon
	# item is a deliberate line here (fists are absent on purpose — there is no fists Item, you cannot drop them).
	var item_paths: Array[String] = [
		"res://resources/items/melee_item.tres",
		"res://resources/items/pistol_item.tres",
		"res://resources/items/shotgun_item.tres",
		"res://resources/items/smg_item.tres",
		"res://resources/items/sniper_item.tres",
		"res://resources/items/rock_item.tres",
		"res://resources/items/spray_paint_item.tres",
	]
	for path in item_paths:
		var item := load(path) as Item
		assert_not_null(item, "%s must load as an Item" % path)
		if item == null:
			continue
		assert_true(item.is_weapon(), "%s must be a WEAPON item — the stamp only runs on is_weapon()" % path)
		assert_true(item.weapon.thrown_trail, "%s opts into the streak (thrown_trail is ON by default)" % path)
		assert_eq(item.weapon.thrown_trail_color, Color(1.0, 1.0, 1.0, 1.0),
			"%s streaks WHITE, like every other weapon" % path)
		var drop: Node3D = WorldItem.build(item, 1)
		assert_not_null(drop, "%s builds a drop" % path)
		if drop == null:
			continue
		var trail := _trail_child(drop)
		assert_not_null(trail, "%s's drop carries a ThrowTrail child" % path)
		if trail != null:
			assert_eq(trail.color, item.weapon.thrown_trail_color,
				"%s's streak wears the weapon's authored colour" % path)
		drop.free()

func test_a_weapon_that_opts_out_gets_no_streak_child() -> void:
	# The opt-out half of the same stamp. Nothing in the shipped roster turns the streak off any more, so without
	# this the `if item.weapon.thrown_trail:` branch would have no negative case at all and could rot into an
	# unconditional add — which would make the flag a lie for the first weapon that ever needs a silent throw.
	# Built from bare resources (no view_model) so it lands in WorldItem.build's case 4 placeholder box, which
	# still routes through _make_throwable — the code path under test.
	var w := WeaponData.new()
	w.thrown_trail = false
	var item := Item.new()
	item.category = Item.Category.WEAPON
	item.weapon = w
	var drop: Node3D = WorldItem.build(item, 1)
	assert_not_null(drop, "a weapon item with no model still builds a placeholder drop")
	if drop != null:
		assert_null(_trail_child(drop), "a weapon that opts OUT gets no ThrowTrail child at all")
		drop.free()
	item = null
	w = null

func test_weapon_data_defaults_turn_the_streak_on() -> void:
	var w := WeaponData.new()
	assert_true(w.thrown_trail,
		"a new weapon streaks when thrown by default — the effect is game-wide, and an author opts OUT, not in")
	assert_eq(w.thrown_trail_color, Color(1.0, 1.0, 1.0, 1.0),
		"and the colour is white out of the box, so a new weapon matches the rest without any authoring at all")
	w = null

# --- Helpers --------------------------------------------------------------------------------------------

## A knife-shaped Throwable carrying a ThrowTrail, built the way WorldItem builds a weapon drop.
## `auto_fit_collider` off because there is no visual to fit to (an empty AABB would collapse the box).
func _blade():
	var body = ThrowableScript.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 0.1, 0.46)
	shape.shape = box
	body.add_child(shape)
	body.collision_shape = shape
	body.auto_fit_collider = false
	var trail = load(TRAIL_PATH).new()
	trail.name = "ThrowTrail"
	body.add_child(trail)
	return body

## The live ribbon, found by name at the tree root (where ThrowTrail deliberately parents it), or null.
func _ribbon() -> MeshInstance3D:
	for child in get_tree().root.get_children():
		if child.name == RIBBON_NAME and child is MeshInstance3D:
			return child as MeshInstance3D
	return null

## The ThrowTrail child of a built drop, matched by SCRIPT rather than by name so a rename of the node can't
## quietly pass this test.
func _trail_child(drop: Node) -> Node:
	for child in drop.get_children():
		if child.get_script() != null and child.get_script().resource_path == TRAIL_PATH:
			return child
	return null
