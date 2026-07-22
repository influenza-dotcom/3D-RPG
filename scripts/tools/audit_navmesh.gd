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
	if root == null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip this scene instead of crashing
		print("   could not instantiate (empty/transient).")
		return
	var regions: Array[NavigationRegion3D] = []
	_collect(root, regions)
	if regions.is_empty():
		print("   (no NavigationRegion3D in this scene)")
		root.free()
		return
	# Links are LINK-AWARE-reported: a level's islands may be intentionally bridged by NavLinks, so we report both the
	# RAW geometric island count AND the reachability verdict after those links bridge them (see NavMeshAudit.reachability).
	var links: Array[NavigationLink3D] = []
	_collect_links(root, links)
	for region in regions:
		var rep := NavMeshAudit.analyze(region.navigation_mesh)
		var reach := NavMeshAudit.reachability(region.navigation_mesh, _links_local(region, links))
		var tag := "[color=lime]OK[/color]" if (rep.ok and reach.ok) else "[color=orange]ISSUES[/color]"
		var s: Dictionary = rep.get("settings", {})
		var setstr := ""
		if not s.is_empty():
			setstr = " | climb %.2f, slope %.0f, radius %.2f" % [s.agent_max_climb, s.agent_max_slope, s.agent_radius]
		print_rich("   %s  %s — %d polys, %d verts, %d island(s) -> %d after %d link(s), floor y~%.1f, area %.0f%s" % [tag, region.name, rep.poly_count, rep.vertex_count, rep.islands.size(), reach.effective_islands, links.size(), rep.floor_y, rep.total_area, setstr])
		for w in rep.warnings:
			# The raw "N disconnected islands" + fragment lines are SUPERSEDED by the link-aware reachability verdict
			# below (the geometric islands are expected on a link-bridged level); skip them to avoid double-reporting.
			if "disconnected navmesh islands" in w or w.begins_with("  fragment of"):
				continue
			print("      ! ", w)
		for w in reach.warnings:
			print("      ! ", w)
	root.free()

func _collect(node: Node, out: Array[NavigationRegion3D]) -> void:
	if node is NavigationRegion3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)

## Every ENABLED NavigationLink3D in the scene (links are usually siblings of the region under the level root, not
## children of it, so we sweep from root — not per-region).
func _collect_links(node: Node, out: Array[NavigationLink3D]) -> void:
	if node is NavigationLink3D and (node as NavigationLink3D).enabled:
		out.append(node)
	for c in node.get_children():
		_collect_links(c, out)

## Links as { a, b, bidirectional } in the region's LOCAL space (= navmesh space) for NavMeshAudit.reachability. The
## scene is instantiated but NOT in the tree, so Node3D.global_transform ERRORS and returns identity off-tree (verified
## on Godot 4.6.3) — which would collapse every link/region transform to origin and falsely flag hand-placed links as
## dangling. So we compose the world transform MANUALLY from the local .transform up the ancestor chain (valid off-tree).
func _links_local(region: NavigationRegion3D, links: Array) -> Array:
	var out: Array = []
	var inv := _global_xform_offtree(region).affine_inverse()
	for lk in links:
		var lk_x := _global_xform_offtree(lk)
		out.append({
			"a": inv * (lk_x * lk.start_position),
			"b": inv * (lk_x * lk.end_position),
			"bidirectional": lk.bidirectional,
		})
	return out

## World transform of an off-tree Node3D, composed from local .transform up the parent chain (get_global_transform()
## errors + returns identity when !is_inside_tree()). Stops at the first non-Node3D ancestor (the instantiated root).
func _global_xform_offtree(n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t
