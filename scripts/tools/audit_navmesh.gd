@tool
extends EditorScript

## NAVMESH AUDIT — in the editor, File > Run this (Ctrl/Cmd+Shift+X) to print a navmesh health report for your
## levels to the Output panel. It flags the two bake faults that wreck NPC pathing: DISCONNECTED ISLANDS (an NPC on
## one can't reach another) and ELEVATED POLYGONS (walkable navmesh baked on top of cars/props — the "NPC stuck on a
## car roof" you keep seeing). Leave LEVELS empty to scan every scenes/levels/*.tscn, or list specific scenes.
## Positions are region-LOCAL (add the NavigationRegion3D's own position if it's offset). The analysis lives in
## NavMeshAudit.analyze() (reused + unit-tested); this is just the File -> Run entry point.

const LEVELS: Array[String] = []  ## empty = scan all scenes/levels/*.tscn; else e.g. ["res://scenes/TestLevel.tscn"]

func _run() -> void:
	var paths := LEVELS
	if paths.is_empty():
		paths = _all_level_scenes()
	if paths.is_empty():
		print("[NavMeshAudit] no level scenes found under res://scenes/levels.")
		return
	for path in paths:
		_audit(path)

func _all_level_scenes() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://scenes/levels")
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".tscn"):
			out.append("res://scenes/levels/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out

func _audit(path: String) -> void:
	var ps := load(path) as PackedScene
	print_rich("[b]-- %s --[/b]" % path)
	if ps == null:
		print("   could not load.")
		return
	var root := ps.instantiate()
	var regions: Array[NavigationRegion3D] = []
	_collect(root, regions)
	if regions.is_empty():
		print("   (no NavigationRegion3D in this scene)")
		root.free()
		return
	for region in regions:
		var rep := NavMeshAudit.analyze(region.navigation_mesh)
		var tag := "[color=lime]OK[/color]" if rep.ok else "[color=orange]ISSUES[/color]"
		var s: Dictionary = rep.get("settings", {})
		var setstr := ""
		if not s.is_empty():
			setstr = " | climb %.2f, slope %.0f, radius %.2f" % [s.agent_max_climb, s.agent_max_slope, s.agent_radius]
		print_rich("   %s  %s — %d polys, %d verts, %d island(s), floor y~%.1f, area %.0f%s" % [tag, region.name, rep.poly_count, rep.vertex_count, rep.islands.size(), rep.floor_y, rep.total_area, setstr])
		for w in rep.warnings:
			print("      ! ", w)
	root.free()

func _collect(node: Node, out: Array[NavigationRegion3D]) -> void:
	if node is NavigationRegion3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
