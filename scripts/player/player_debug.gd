class_name PlayerDebug
extends Node3D

## Dev-only helper: press Home to run the null-material shadow-mesh audit below. Gated on OS.is_debug_build(),
## so an exported release never listens. The End-key hard reload that used to live here was REMOVED 2026-09-12:
## it shipped UNGATED (live in any build, beside the arrow cluster) and lost unsaved progress on one press.
## The debug console's `reload` is the dev reload now.

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_HOME:
		audit_null_material_meshes()

## Dev audit (press Home): walks every MeshInstance3D under the root and reports any that casts
## shadows yet has no material on a surface — the cause of the "material_*: Parameter material is
## null" RenderingServer spam. Prints each offender's node path so it can be fixed (assign a
## material, or set its cast_shadow to OFF). If it reports 0, the spam is just a transient during
## a scene reload's teardown and is safe to ignore.
func audit_null_material_meshes() -> void:
	var offenders := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.push_back(child)
		var mi := node as MeshInstance3D
		if mi == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		if mi.material_override != null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			if mi.get_surface_override_material(s) == null and mi.mesh.surface_get_material(s) == null:
				offenders += 1
				push_warning("[null-material shadow mesh] %s  (surface %d, mesh=%s)" % [mi.get_path(), s, str(mi.mesh.resource_path)])
				break
	print("[player_debug] null-material shadow-mesh audit: %d offender(s)" % offenders)
