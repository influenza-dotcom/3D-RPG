extends GutTest

## Tests for SprayPaintable — the "the spray can recolours this prop" drop-in. The pure bits (the blend-toward-colour
## maths and the find-on-hit-body scan) are unit-tested here off-tree; the actual in-tree material recolour on a real
## dog needs a live MeshInstance3D + Throwable, so it's playtest-verified (mirrors RandomCoat).

const SprayPaintable := preload("res://scripts/components/spray_paintable.gd")


func test_defaults() -> void:
	# Off-tree field read — no add_child, so nothing recolours. The component ships ready to use out of the box.
	var p = SprayPaintable.new()
	assert_true(p.enabled, "SprayPaintable ships enabled — dropping it on a prop makes it sprayable by default")
	assert_true(p.suppress_decal, "by default a spray hit recolours the prop instead of ALSO leaving a splat decal")
	assert_eq(p.blend, 1.0, "by default one spray snaps the coat fully to the sprayed colour")
	p.free()


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
