extends GutTest

## Scene-wiring contract for scenes/effects/gore_gib.tscn — the GENERIC MEAT CHUNK every bloody death flings
## (the body-part gib, a real severed limb, is the separate chassis pinned by tests/test_body_part_gibs.gd).
##
## This file exists because the meat gib shipped for a long time with `mesh_instance` and `collision_shape`
## UNWIRED (its root declared only `node_paths=PackedStringArray("impact_sfx")`), which made two Throwable
## features silent no-ops on every gib in the game:
##   * the DESPAWN FADE — Throwable._fade_out_for_despawn returns immediately with no mesh_instance, so after
##     GameSettings.effects.gib_lifetime a chunk POPPED instead of fading over gib_fade_time. A designer knob
##     that did nothing.
##   * the collider AUTO-FIT — _autofit_collision_shape early-returns with no mesh_instance.
## Wiring the mesh fixes the fade but newly ACTIVATES the auto-fit, and here that is a regression rather than
## an improvement: the auto-fit resizes the BoxShape3D only, never the CollisionShape3D's own transform, and
## this gib's collider is deliberately tilted ~14.5 deg and raised +0.237 m off the body origin. Fitting it to
## model.obj's ~1.0 x 1.0 x 1.08 bounds while KEEPING that offset yields a box spanning roughly y -0.26..0.74
## against a mesh spanning -0.5..0.5 — a quarter-metre of collider above the chunk and none under it.
## So the scene wires BOTH refs and opts OUT via `auto_fit_collider`, and these tests pin all three facts
## together: drop any one and the gib silently regresses in a way only a playtest would catch.
##
## Verified STRUCTURALLY, WITHOUT add_child (the no-_ready rule): off-tree instantiate() skips Throwable._ready
## — no physics, no overlay chain, no auto-fit — while node-path exports ARE resolved, which is what makes the
## wiring assertable at all. The auto-fit is then invoked DIRECTLY, since it needs no tree.

const GIB_SCENE := "res://scenes/effects/gore_gib.tscn"
const ThrowableScript := preload("res://scripts/components/Throwable.gd")

## The hand-authored collider the opt-out is there to protect. Not the mesh's AABB, on purpose.
const AUTHORED_BOX := Vector3(0.38433838, 0.32025146, 1.0)


func _instantiate_gib() -> Node:
	var scene: PackedScene = load(GIB_SCENE)
	assert_not_null(scene, "gore_gib.tscn (the generic meat chunk) must load")
	if scene == null:
		return null
	return scene.instantiate()


# --- the wiring that makes the despawn fade real -----------------------------------------------------------

func test_gib_wires_mesh_instance_so_the_despawn_fade_can_run() -> void:
	var gib := _instantiate_gib()
	if gib == null:
		return
	assert_true(gib is Throwable, "the meat gib's root carries the Throwable script")
	var mi = gib.get("mesh_instance")
	assert_true(mi is MeshInstance3D,
		"`mesh_instance` must be wired — Throwable._fade_out_for_despawn tweens its transparency, so an unwired one makes GameSettings.effects.gib_fade_time a silent no-op and the chunk pops out of existence instead of fading")
	if mi is MeshInstance3D:
		assert_eq(mi, gib.get_node_or_null(^"Model"), "`mesh_instance` points at the Model child (the chunk's visual)")
		assert_not_null((mi as MeshInstance3D).mesh, "the visual carries a mesh, so there is something to fade")
	gib.free()


func test_gib_wires_collision_shape_with_the_authored_box() -> void:
	var gib := _instantiate_gib()
	if gib == null:
		return
	var cs = gib.get("collision_shape")
	assert_true(cs is CollisionShape3D, "`collision_shape` must be wired — an unwired one leaves the prop with no editor-visible collider contract and trips Throwable._get_configuration_warnings")
	if cs is CollisionShape3D:
		assert_eq(cs, gib.get_node_or_null(^"CollisionShape3D"), "`collision_shape` points at the CollisionShape3D child")
		var shape := (cs as CollisionShape3D).shape
		assert_true(shape is BoxShape3D, "the meat chunk collides as a box")
		if shape is BoxShape3D:
			assert_true((shape as BoxShape3D).size.is_equal_approx(AUTHORED_BOX),
				"the HAND-AUTHORED box must survive scene load (want %s, got %s)" % [AUTHORED_BOX, (shape as BoxShape3D).size])
	gib.free()


# --- the opt-out that keeps that box from being auto-fitted ------------------------------------------------

func test_gib_opts_out_of_the_collider_autofit() -> void:
	var gib := _instantiate_gib()
	if gib == null:
		return
	assert_false(bool(gib.get("auto_fit_collider")),
		"the meat gib must keep `auto_fit_collider` OFF: its collider is deliberately tilted and raised off the body origin, and the auto-fit resizes the shape WITHOUT touching that transform — so fitting it to the mesh bounds grows the box off-centre, poking out one side of the chunk and missing the other")
	gib.free()


func test_autofit_leaves_the_authored_box_untouched_on_the_real_scene() -> void:
	# The behavioural half of the test above: run the auto-fit exactly as Throwable._ready would and assert the
	# box did not move. This is what actually fails if someone flips the flag back on or drops the guard.
	var gib := _instantiate_gib()
	if gib == null:
		return
	gib.call(&"_autofit_collision_shape")
	var cs = gib.get("collision_shape")
	if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
		var size := ((cs as CollisionShape3D).shape as BoxShape3D).size
		assert_true(size.is_equal_approx(AUTHORED_BOX),
			"_autofit_collision_shape must be a no-op while `auto_fit_collider` is off — the authored box is the shipped gib feel (want %s, got %s)" % [AUTHORED_BOX, size])
	gib.free()


# --- the flag itself, on a bare Throwable ------------------------------------------------------------------
#
# Built off-tree with .new() + add_child on the PROP (not the scene tree), so no _ready runs anywhere — the
# auto-fit is a pure function of the two wired refs and the flag, which is the whole point of testing it here.

func _bare_throwable(fit: bool, box: Vector3, mesh_size: Vector3) -> Throwable:
	var t := ThrowableScript.new() as Throwable
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = mesh_size
	mi.mesh = bm
	t.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box
	cs.shape = shape
	t.add_child(cs)
	t.mesh_instance = mi
	t.collision_shape = cs
	t.auto_fit_collider = fit
	return t


func test_autofit_on_resizes_the_box_to_the_visual_bounds() -> void:
	# The default path every other prop rides — proves the opt-out is a real gate and not a dead flag.
	var t := _bare_throwable(true, Vector3.ONE, Vector3(2.0, 3.0, 4.0))
	t._autofit_collision_shape()
	var size := (t.collision_shape.shape as BoxShape3D).size
	assert_true(size.is_equal_approx(Vector3(2.0, 3.0, 4.0)),
		"with `auto_fit_collider` ON the box tracks the mesh's AABB, so a data-driven mesh swap can't leave a mis-sized collider (want (2,3,4), got %s)" % size)
	t.free()


func test_autofit_off_keeps_the_authored_box() -> void:
	var t := _bare_throwable(false, Vector3.ONE, Vector3(2.0, 3.0, 4.0))
	t._autofit_collision_shape()
	var size := (t.collision_shape.shape as BoxShape3D).size
	assert_true(size.is_equal_approx(Vector3.ONE),
		"with `auto_fit_collider` OFF the authored box is left exactly as the designer sized it (want (1,1,1), got %s)" % size)
	t.free()


# --- the per-spawn size variety ----------------------------------------------------------------------------
#
# Every chunk rolls its own size via the RandomSize drop-in on the scene (the dog's size roller): on ready it
# multiplies the ROOT's scale, so the mesh, the tilted collider AND its raised offset all scale together —
# which is exactly why it composes with the auto-fit opt-out above (nothing re-sizes the shape, the whole
# authored collider just scales uniformly). Wiring-only assertions, off-tree: _ready never runs here, so no
# roll happens and the asserts are deterministic. The body-part gib chassis deliberately carries NO roller —
# a flung head must stay the character's true head size.

func test_gib_carries_an_enabled_random_size_roller() -> void:
	var gib := _instantiate_gib()
	if gib == null:
		return
	var roller := gib.get_node_or_null(^"RandomSize")
	assert_true(roller is RandomSize,
		"gore_gib.tscn must carry a RandomSize child — it is what makes every meat chunk spawn at its own size; dropping it makes all chunks identical again")
	if roller is RandomSize:
		var rs := roller as RandomSize
		assert_true(rs.enabled, "the roller must be enabled or the size variety silently dies")
		assert_lte(rs.preset_scale_mult, 0.0,
			"preset_scale_mult must stay 0 (= roll normally) — a positive preset pins EVERY chunk to one fixed size; that field exists for the dog's re-drop restore, not for authoring")
		assert_gt(rs.max_scale_mult, rs.min_scale_mult,
			"the authored range must be a real spread, or the roll collapses to one size (min %s, max %s)" % [rs.min_scale_mult, rs.max_scale_mult])
		assert_gt(rs.min_scale_mult, 0.0,
			"min_scale_mult must be positive — a zero/negative scale is a degenerate (invisible or inverted) chunk")
	gib.free()
