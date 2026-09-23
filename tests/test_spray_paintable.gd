extends GutTest

## Tests for SprayPaintable — the "the spray can recolours this prop" drop-in. The pure bits (the blend-toward-colour
## maths and the find-on-hit-body scan) are unit-tested here off-tree, and paint() itself is driven on a bare Node3D
## host with a MeshInstance3D child (the mesh resolution MeshCoat uses for a prop with no `mesh_instance`). The
## PaintProjectile side (discovering the component on a real hit body and skipping the decal) is playtest-verified.

const SprayPaintable := preload("res://scripts/components/spray_paintable.gd")


## A prop host (Node3D) whose mesh wears `shared` as its material_override, with a SprayPaintable child.
func _paintable_prop(shared: StandardMaterial3D) -> SprayPaintable:
	var host := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.material_override = shared
	host.add_child(mesh)
	var p := SprayPaintable.new()
	host.add_child(p)
	add_child_autofree(host)
	return p


func _mesh_of(p: SprayPaintable) -> MeshInstance3D:
	return p.get_parent().get_node("Mesh") as MeshInstance3D


func _white_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	return m


func test_dropped_in_paintable_takes_the_sprayed_colour_in_one_hit() -> void:
	# Nothing configured beyond dropping the component in: one hit must repaint the coat to the sprayed colour.
	var shared := _white_material()
	var p := _paintable_prop(shared)
	watch_signals(p)
	p.paint(Color.RED)
	var worn := _mesh_of(p).material_override as StandardMaterial3D
	assert_true(worn != null, "the painted mesh wears a StandardMaterial3D coat")
	if worn == null:
		return
	assert_eq(worn.albedo_color, Color.RED,
		"a dropped-in SprayPaintable must repaint its prop fully to the sprayed colour on a single hit")
	assert_signal_emitted_with_parameters(p, "painted", [Color.RED])
	assert_ne(worn, shared, "the paint lands on a per-instance copy")
	assert_eq(shared.albedo_color, Color.WHITE,
		"the shared scene material must stay white — spraying one dog must not repaint every dog")


func test_dropped_in_paintable_suppresses_the_splat_decal() -> void:
	# Read by PaintProjectile after paint(): true stops it gluing a splatter decal on a prop that just changed colour.
	var p := SprayPaintable.new()
	assert_true(p.suppress_decal,
		"ship decision: a spray hit on a paintable prop recolours it INSTEAD of also leaving a splat decal")
	p.free()


func test_switched_off_paintable_ignores_the_spray() -> void:
	var shared := _white_material()
	var p := _paintable_prop(shared)
	p.enabled = false
	watch_signals(p)
	p.paint(Color.RED)
	assert_eq(_mesh_of(p).material_override, shared, "a disabled SprayPaintable must leave the prop's material alone")
	assert_eq(shared.albedo_color, Color.WHITE, "a disabled SprayPaintable must not recolour anything")
	assert_signal_not_emitted(p, "painted", "no repaint happened, so nothing may react to one")


func test_partial_blend_builds_the_coat_up_over_repeated_sprays() -> void:
	# blend < 1 means paint "builds up": each hit moves the CURRENT coat part of the way, so holding the trigger
	# converges on the sprayed colour instead of snapping or restarting from the scene colour every hit.
	var shared := _white_material()
	var p := _paintable_prop(shared)
	p.blend = 0.5
	p.paint(Color.BLACK)
	var first := (_mesh_of(p).material_override as StandardMaterial3D).albedo_color
	assert_almost_eq(first.r, 0.5, 0.001, "one half-strength spray moves white halfway to black")
	p.paint(Color.BLACK)
	var second := (_mesh_of(p).material_override as StandardMaterial3D).albedo_color
	assert_almost_eq(second.r, 0.25, 0.001,
		"a second half-strength spray builds on the FIRST coat (white -> 0.5 -> 0.25), not on the original white")


func test_blend_full_snaps_to_sprayed() -> void:
	assert_eq(SprayPaintable.blend_color(Color.WHITE, Color.RED, 1.0), Color.RED, "blend 1.0 snaps fully to the sprayed colour")


func test_blend_zero_keeps_current() -> void:
	assert_eq(SprayPaintable.blend_color(Color.WHITE, Color.RED, 0.0), Color.WHITE, "blend 0.0 leaves the current colour unchanged")


func test_blend_half_is_midpoint() -> void:
	var mid := SprayPaintable.blend_color(Color(0, 0, 0), Color(1, 1, 1), 0.5)
	assert_almost_eq(mid.r, 0.5, 0.001, "blend 0.5 lands the red channel halfway between current and sprayed")
	assert_almost_eq(mid.g, 0.5, 0.001, "blend 0.5 lands the green channel halfway between current and sprayed")


func test_blend_clamps_out_of_range() -> void:
	# A >1 strength must not overshoot PAST the sprayed colour (lerp with an unclamped t would).
	assert_eq(SprayPaintable.blend_color(Color.WHITE, Color.RED, 2.0), Color.RED, "an out-of-range strength clamps to a full snap, never overshoots")


func test_find_on_returns_child_component() -> void:
	# The spray blob reports the prop's physics body as the hit collider; the component sits as a child of it. find_on
	# must locate it via a descendant scan.
	var body := Node.new()
	var comp := SprayPaintable.new()
	body.add_child(comp)
	assert_eq(SprayPaintable.find_on(body), comp, "find_on locates a SprayPaintable child of the hit body")
	body.free()  # frees comp too


func test_find_on_nested_component() -> void:
	# A component buried a level deeper (under an intermediate node) is still found — the scan is depth-first.
	var body := Node.new()
	var mid := Node.new()
	body.add_child(mid)
	var comp := SprayPaintable.new()
	mid.add_child(comp)
	assert_eq(SprayPaintable.find_on(body), comp, "find_on descends into children to find a nested SprayPaintable")
	body.free()


func test_find_on_null_body_safe() -> void:
	assert_null(SprayPaintable.find_on(null), "find_on(null) — a blob that hit world geometry (no body) — returns null")


func test_find_on_no_component_returns_null() -> void:
	var body := Node.new()
	assert_null(SprayPaintable.find_on(body), "a body with no SprayPaintable child returns null (a normal decal lands instead)")
	body.free()
