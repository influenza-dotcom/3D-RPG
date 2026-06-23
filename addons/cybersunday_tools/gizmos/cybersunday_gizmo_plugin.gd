@tool
extends EditorNode3DGizmoPlugin

## Viewport gizmos for the game's spatial authoring components -- draws their currently-invisible extents / ranges
## / routes / facing in the 3D editor so a designer places by eye instead of guessing numbers.
##
## NOTE: a gizmo draws for any matching Node3D regardless of whether the TARGET's script is @tool -- the editor
## drives this plugin, and it reads serialized exports / child shapes / transforms (all available at edit time).
## So none of the game classes needed @tool added; only PlayerSpawn.tscn lost its stopgap cone child (the real
## facing arrow replaces it).
##
## Geometry recipe (source-verified): zones read their first child CollisionShape3D's shape; NavBlocker uses its
## _footprint()+mode (CARVE box / AVOID cylinder); PatrolPath strings its Node3D children into a route; PlayerSpawn
## arrows along local -Z (place() faces yaw -Z); EncounterSpawner rings each SpawnDefinition.spawn_radius (or marks
## resolved spawn_points); ExplosiveBarrel spheres blast_radius; NPC draws a sight cone + alert ring (and a
## link line to a child PatrolBehavior's PatrolPath); InvestigatePoint rings its radius; NoiseSource rings its
## radius only when audible (> 0); WorldMarker draws a small 3-axis cross at its origin.

const Shapes := preload("res://addons/cybersunday_tools/gizmos/gizmo_shapes.gd")


func _init() -> void:
	create_material("zone", Color(0.2, 0.9, 1.0))     # cyan -- trigger / audio / shadow volumes
	create_material("danger", Color(1.0, 0.35, 0.1))  # orange-red -- hazard zone, blast radius
	create_material("carve", Color(0.62, 0.42, 1.0))  # purple -- NavBlocker CARVE box
	create_material("avoid", Color(1.0, 0.8, 0.2))    # amber -- NavBlocker AVOID cylinder
	create_material("route", Color(0.3, 1.0, 0.45))   # green -- patrol route
	create_material("spawn", Color(1.0, 0.5, 0.9))    # pink -- encounter scatter / points
	create_material("facing", Color(0.2, 1.0, 0.65))  # spawn arrival arrow
	create_material("sight", Color(1.0, 0.95, 0.3))   # yellow -- NPC sight cone
	create_material("noise", Color(0.4, 0.6, 1.0))    # blue -- NPC alert / noise radius
	create_material("investigate", Color(1.0, 0.6, 0.2))  # amber -- InvestigatePoint reach ring
	create_material("sound", Color(0.5, 0.85, 1.0))   # pale blue -- NoiseSource audible radius
	create_material("marker", Color(1.0, 0.85, 0.3))  # gold -- WorldMarker point-of-interest cross
	create_material("link", Color(0.6, 0.7, 0.8))     # grey-blue -- PatrolBehavior -> PatrolPath link


func _get_gizmo_name() -> String:
	return "CyberSundayTools"


func _has_gizmo(node: Node3D) -> bool:
	return (node is TriggerVolume or node is AudioZone or node is HazardZone or node is ShadowVolume
		or node is NavBlocker or node is PatrolPath or node is PlayerSpawn
		or node is EncounterSpawner or node is ExplosiveBarrel or node is NPC
		or node is InvestigatePoint or node is NoiseSource or node is WorldMarker)


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	# HazardZone first (danger tint); the other three zones share the cyan material. TutorialPrompt is a
	# TriggerVolume subclass and falls into the cyan group, which is correct.
	if node is HazardZone:
		_draw_zone(gizmo, node, "danger")
	elif node is TriggerVolume or node is AudioZone or node is ShadowVolume:
		_draw_zone(gizmo, node, "zone")
	elif node is NavBlocker:
		_draw_navblocker(gizmo, node)
	elif node is PatrolPath:
		_draw_patrol(gizmo, node)
	elif node is PlayerSpawn:
		gizmo.add_lines(Shapes.arrow(Vector3.FORWARD, 1.0), get_material("facing", gizmo))
	elif node is EncounterSpawner:
		_draw_encounter(gizmo, node)
	elif node is ExplosiveBarrel:
		gizmo.add_lines(Shapes.sphere(_getf(node, &"blast_radius", 4.0)), get_material("danger", gizmo))
	elif node is NPC:
		_draw_npc(gizmo, node)
	elif node is InvestigatePoint:
		var ir := _getf(node, &"radius", 20.0)
		if ir > 0.0:
			gizmo.add_lines(Shapes.ring(ir), get_material("investigate", gizmo))
	elif node is NoiseSource:
		var nr := _getf(node, &"radius", 0.0)
		if nr > 0.0:  # a silent source (radius 0) has no authored extent to draw
			gizmo.add_lines(Shapes.ring(nr), get_material("sound", gizmo))
	elif node is WorldMarker:
		gizmo.add_lines(Shapes.cross(0.5), get_material("marker", gizmo))


## Outline an Area3D zone from its first DIRECT child CollisionShape3D (the zones author the extent there, not
## as an export), at that child's transform relative to the zone.
func _draw_zone(gizmo: EditorNode3DGizmo, area: Node3D, mat: String) -> void:
	var cs := _first_collision_shape(area)
	if cs == null or cs.shape == null:
		return
	var lines := _shape_lines(cs.shape, cs.transform)
	if not lines.is_empty():
		gizmo.add_lines(lines, get_material(mat, gizmo))


func _first_collision_shape(area: Node) -> CollisionShape3D:
	for c in area.get_children():
		if c is CollisionShape3D:
			return c as CollisionShape3D
	return null


func _shape_lines(shape: Shape3D, x: Transform3D) -> PackedVector3Array:
	if shape is BoxShape3D:
		return Shapes.box((shape as BoxShape3D).size, x)
	elif shape is SphereShape3D:
		return Shapes.sphere((shape as SphereShape3D).radius, x)
	elif shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		return Shapes.cylinder(c.radius, c.height, x)
	elif shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		return Shapes.capsule(cap.radius, cap.height, x)
	return PackedVector3Array()


func _draw_navblocker(gizmo: EditorNode3DGizmo, nb: Node3D) -> void:
	var e: Vector3 = nb._footprint()  # half-extents in local space (@tool, so it runs in-editor)
	var h: float = maxf(0.1, _getf(nb, &"height", maxf(0.1, e.y * 2.0)))
	if nb.mode == NavBlocker.Mode.CARVE:
		gizmo.add_lines(Shapes.box(Vector3(e.x * 2.0, h, e.z * 2.0)), get_material("carve", gizmo))
	else:
		var r := maxf(0.1, maxf(e.x, e.z))
		gizmo.add_lines(Shapes.cylinder(r, h), get_material("avoid", gizmo))


func _draw_patrol(gizmo: EditorNode3DGizmo, path: Node3D) -> void:
	var pts := PackedVector3Array()
	for c in path.get_children():
		if c is Node3D:
			pts.append(path.to_local((c as Node3D).global_position))
	if pts.size() < 2:
		return
	gizmo.add_lines(Shapes.polyline(pts, bool(path.loop)), get_material("route", gizmo))


func _draw_encounter(gizmo: EditorNode3DGizmo, spawner: Node3D) -> void:
	var points: Array = spawner.spawn_points
	if points != null and not points.is_empty():
		for np in points:
			var m := spawner.get_node_or_null(np)
			if m is Node3D:
				var local := spawner.to_local((m as Node3D).global_position)
				gizmo.add_lines(Shapes.ring(0.5, Transform3D(Basis(), local)), get_material("spawn", gizmo))
		return
	for def in spawner.spawn_definitions:
		if def != null:
			gizmo.add_lines(Shapes.ring(maxf(0.1, _getf(def, &"spawn_radius", 2.0))), get_material("spawn", gizmo))


func _draw_npc(gizmo: EditorNode3DGizmo, npc: Node3D) -> void:
	var sight := _getf(npc, &"sight_range", 0.0)
	var fov := _getf(npc, &"fov_degrees", 0.0)
	var eye := _getf(npc, &"eye_height", 1.4)
	if sight > 0.0 and fov > 0.0:
		var apex := Transform3D(Basis(), Vector3(0.0, eye, 0.0))
		gizmo.add_lines(Shapes.cone_flat(sight, deg_to_rad(fov) * 0.5, Vector3.FORWARD, apex), get_material("sight", gizmo))
	var alert := _getf(npc, &"alert_radius", 0.0)
	if alert > 0.0:
		gizmo.add_lines(Shapes.ring(alert), get_material("noise", gizmo))
	_draw_patrol_link(gizmo, npc)


## If this NPC has a PatrolBehavior child pointed at a PatrolPath, draw a thin line from the NPC to that route
## so the association is visible in the viewport (the behavior is a plain Node, so it can't host its own gizmo).
func _draw_patrol_link(gizmo: EditorNode3DGizmo, npc: Node3D) -> void:
	for c in npc.get_children():
		if c is PatrolBehavior:
			var pb := c as PatrolBehavior
			if pb.patrol_path.is_empty():
				continue
			var path := pb.get_node_or_null(pb.patrol_path)
			if path is Node3D:
				var local := npc.to_local((path as Node3D).global_position)
				var line := PackedVector3Array([Vector3.ZERO, local])
				gizmo.add_lines(line, get_material("link", gizmo))
			return


## Read a numeric export defensively (.get() returns null if absent; non-numbers fall back to `def`).
func _getf(o: Object, prop: StringName, def: float) -> float:
	var v: Variant = o.get(prop)
	return float(v) if (v is float or v is int) else def
