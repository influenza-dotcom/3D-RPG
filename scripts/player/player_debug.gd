class_name PlayerDebug
extends Node3D

## Dev-only helper: press End (ui_end) to hard-reload the current scene. Not shipping
## gameplay — a quick manual reset while iterating.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_end"):
		reset()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_HOME:
		audit_null_material_meshes()

func reset():
	get_tree().reload_current_scene()

## Dev audit (press Home): walks every MeshInstance3D under the root and reports any that casts
## shadows yet has no material on a surface — the cause of the "material_*: Parameter material is
## null" RenderingServer spam. Prints each offender's node path so it can be fixed (assign a
## material, or set its cast_shadow to OFF). If it reports 0, the spam is just a transient during
## the End hard-reload's teardown and is safe to ignore.
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
