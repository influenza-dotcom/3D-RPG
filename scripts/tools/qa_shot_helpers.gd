extends RefCounted

## Shared helpers for the windowed QA-shot / probe scripts in this folder (the `*_qa_shots.gd` and `__*_probe.gd`
## idiom): the tree walks and image diffs that every probe used to carry as its own copy. Preload BY PATH —
## `const QaShots := preload("res://scripts/tools/qa_shot_helpers.gd")` — no class_name on purpose, so a probe never
## depends on the editor having rescanned the global class cache. Pure statics: pass the tree root in (a SceneTree
## probe has `root`, a Node probe has `get_tree().root`). Dev-only; nothing here ships.


## Hide every CanvasLayer (HUD, menus, debug overlays) and the SkyTitle, so a raw viewport grab is the 3D frame alone.
static func strip_overlays(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
		elif n.name == "SkyTitle" and n is Node3D:
			(n as Node3D).visible = false
		stack.append_array(n.get_children())


## Re-show the CanvasLayer carrying the post-process ShaderMaterial (strip_overlays hid it with the rest), so the
## SHIPPED frame — grain, quantize, dither — can be shot too. False when no post-process material is in the tree.
static func restore_post_process(root: Node) -> bool:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var mat := (n as CanvasItem).material as ShaderMaterial
			if mat != null and mat.shader != null and String(mat.shader.resource_path).contains("post_process"):
				var layer: Node = n
				while layer != null and not (layer is CanvasLayer):
					layer = layer.get_parent()
				if layer != null:
					(layer as CanvasLayer).visible = true
					return true
		stack.append_array(n.get_children())
	return false


## Set the post-process shader's `grain_amount` and RETURN the previous value (0.05 when unknown) so the caller can
## put it back — film grain is per-frame noise and would make every pixel diff nonzero.
static func set_grain(root: Node, amount: float) -> float:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem:
			var mat := (n as CanvasItem).material as ShaderMaterial
			if mat != null and mat.shader != null and String(mat.shader.resource_path).contains("post_process"):
				var was: Variant = mat.get_shader_parameter(&"grain_amount")
				mat.set_shader_parameter(&"grain_amount", amount)
				return float(was) if was != null else 0.05
		stack.append_array(n.get_children())
	return 0.05


## Per-pixel |a - b| × gain, clamped to 1 — an 8× amplified diff makes a one-count ghost visible to the eye.
static func amplify(a: Image, b: Image, gain: float = 8.0) -> Image:
	var out := Image.create_empty(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			out.set_pixel(x, y, Color(
					minf(absf(ca.r - cb.r) * gain, 1.0),
					minf(absf(ca.g - cb.g) * gain, 1.0),
					minf(absf(ca.b - cb.b) * gain, 1.0)))
	return out


## Every pixel where `lit` differs from `base` by at least `threshold` (mean absolute RGB delta): an effect's footprint.
static func footprint(base: Image, lit: Image, threshold: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in base.get_height():
		for x in base.get_width():
			var ca := base.get_pixel(x, y)
			var cb := lit.get_pixel(x, y)
			if (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0 >= threshold:
				out.append(Vector2i(x, y))
	return out


## First node under `root` whose script lives at `path` — a lookup by script FILE, so a probe needs no class_name.
static func find_by_script(root: Node, path: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() != null and String(n.get_script().resource_path) == path:
			return n
		stack.append_array(n.get_children())
	return null


## A flat-coloured box mesh at `pos` — the synthetic-scene brick the ink probes build their walls and slabs from.
static func box(pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	mi.position = pos
	return mi


## Depth-first walk of every `.gd` under `dir` (dot-entries skipped, `excluded_dirs` pruned whole), calling
## `on_file.call(path)` per script — the debt scanners' walk, shared.
static func walk_gd_files(dir: String, excluded_dirs: Array, on_file: Callable) -> void:
	if excluded_dirs.has(dir):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var full: String = dir.path_join(entry)
		if d.current_is_dir():
			walk_gd_files(full, excluded_dirs, on_file)
		elif entry.get_extension() == "gd":
			on_file.call(full)
		entry = d.get_next()
	d.list_dir_end()
