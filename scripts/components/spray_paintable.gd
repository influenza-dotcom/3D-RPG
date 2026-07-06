class_name SprayPaintable
extends Node

## Drop-in "the spray can can recolour this prop" component (designer-first: drag it under any prop that has a
## MeshInstance3D — a dog, a cat, a car door, a barrel — and spraying it with the paint gun repaints its whole coat to
## the sprayed colour instead of gluing a splatter decal onto it). The spray blob (`PaintProjectile`) discovers this
## component on whatever body it hit (`SprayPaintable.find_on`) and calls `paint()`. Purely cosmetic.
##
## It shares the runtime recolour contract with RandomCoat via `MeshCoat` (`scripts/components/mesh_coat.gd`):
## duplicate the shared material, touch `material_override` only so the look-at outline / hit-flash on
## `material_overlay` survive, and resolve the target mesh the same way. RandomCoat rolls the INITIAL coat once at
## spawn; SprayPaintable OVERWRITES it whenever the prop is sprayed — the last writer wins, so the two compose without
## knowing about each other (spray a random-coated dog and it takes the sprayed colour).
##
## NOT persisted: a repainted prop reverts to its natural / rolled coat on reload, the same as RandomCoat's roll —
## dynamic props aren't saved, and this is cosmetic-only. See [[throwable-runtime-recolor-contract]].

## Master switch. Off => this prop ignores spray paint (a normal splatter decal lands on it instead). On by default so
## dropping the component just works.
@export var enabled: bool = true
## Optional explicit target mesh. Blank => auto-resolve: the host's `mesh_instance` (a `Throwable` exposes one) else the
## first `MeshInstance3D` under the host — the same resolution RandomCoat uses. Wire it when the prop has several meshes
## and only one wears the coat.
@export var mesh_path: NodePath
## How strongly ONE spray hit shifts the coat toward the sprayed colour: 1.0 = snap fully to it in a single pass, lower
## = the coat eases toward the colour over repeated sprays (paint "builds up" the longer you hold the trigger on it).
## Clamped to 0..1.
@export_range(0.0, 1.0) var blend: float = 1.0
## When true (default) a spray hit recolours the coat and NO splatter decal is placed on this prop — the whole prop
## just changes colour. Set false to ALSO leave the usual paint decal on top of the recolour (splatter + tint).
@export var suppress_decal: bool = true

## Emitted after a successful repaint, with the colour applied. Wire it in the editor to chain a reaction — a yelp
## bark, a shake, a particle — when the prop gets painted.
signal painted(color: Color)


## Recolour this prop's coat toward `color`. Called by `PaintProjectile` when its blob lands on the host body.
## Duplicates each target mesh's material (never the shared scene resource, via MeshCoat) and blends its albedo toward
## the sprayed colour. No-op when disabled or when no target mesh resolves.
func paint(color: Color) -> void:
	if not enabled:
		return
	var meshes := MeshCoat.resolve_meshes(self, mesh_path)
	if meshes.is_empty():
		return
	for m in meshes:
		var mat := MeshCoat.writable_material(m)
		mat.albedo_color = blend_color(mat.albedo_color, color, blend)
		m.material_override = mat
	painted.emit(color)


## The new albedo after a spray: the current colour eased toward the sprayed colour by `t` (0 = unchanged, 1 = the
## sprayed colour). Pure + static so it's unit-testable with literal colours (mirrors RandomCoat.pick_index); `t` is
## clamped so an out-of-range blend can never overshoot past the sprayed colour.
static func blend_color(current: Color, sprayed: Color, t: float) -> Color:
	return current.lerp(sprayed, clampf(t, 0.0, 1.0))


## The SprayPaintable on `body` — the thing a spray blob hit — or null. Scans `body` and its descendants: a hit reports
## the prop's CollisionObject3D root (a RigidBody3D for a Throwable dog), and the component sits as a child under it, so
## a descendant scan finds it. Descendant-only by design — the collider IS the prop root, so there's no need to climb
## into unrelated ancestors (which would risk matching a component on a shared parent).
static func find_on(body: Node) -> SprayPaintable:
	if body == null:
		return null
	if body is SprayPaintable:
		return body as SprayPaintable
	return _find_in_children(body)


static func _find_in_children(n: Node) -> SprayPaintable:
	for c in n.get_children():
		if c is SprayPaintable:
			return c as SprayPaintable
		var deeper := _find_in_children(c)
		if deeper != null:
			return deeper
	return null
