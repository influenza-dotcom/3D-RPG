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
## arrows along local -Z (place() faces yaw -Z); EncounterSpawner rings each resolved spawn_point at its
## definition's real spawn_radius (or rings each SpawnDefinition.spawn_radius at the spawner); ExplosiveBarrel
## spheres blast_radius; NPC draws a sight cone + alert ring (and a link line to a child PatrolBehavior's
## PatrolPath); InvestigatePoint rings its radius; NoiseSource rings its radius only when audible (> 0);
## WorldMarker draws a small 3-axis cross at its origin.
##
## LINK LINES (associations a plain Node can't host its own gizmo for): TriggerVolume -> its `target` and
## `activate_node_path` nodes; AlarmPanel -> its `spawner_path` (plus a small cross at the panel); GuardDuty
## (a child Node of an NPC, mirroring the PatrolBehavior child-scan) -> its `protectee_path` (skipped when only
## `protectee_group` is set — unresolvable at edit time).
##
## SPATIAL EXTENTS added later: AmbientSound / Radio draw their max_distance falloff sphere; a Door draws its
## swing arc (closed -> open_angle around the pivot).

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
	create_material("trigger_link", Color(0.2, 0.9, 1.0))  # cyan -- TriggerVolume -> target / activate link
	create_material("alarm", Color(1.0, 0.3, 0.25))   # red -- AlarmPanel marker + spawner link
	create_material("guard_link", Color(0.4, 0.9, 0.6))  # green -- GuardDuty -> protectee link
	create_material("falloff", Color(0.5, 0.85, 1.0))  # pale blue -- ambient/radio audible falloff sphere
	create_material("swing", Color(0.7, 0.7, 0.95))    # lavender -- Door swing arc


func _get_gizmo_name() -> String:
	return "CyberSundayTools"


func _has_gizmo(node: Node3D) -> bool:
	return (node is TriggerVolume or node is AudioZone or node is HazardZone or node is ShadowVolume
		or node is NavBlocker or node is PatrolPath or node is PlayerSpawn
		or node is EncounterSpawner or node is ExplosiveBarrel or node is NPC
		or node is InvestigatePoint or node is NoiseSource or node is WorldMarker
		or node is AlarmPanel or node is AmbientSound or node is Radio or node is Door)
		# NOTE: GuardDuty is a plain Node (no gizmo of its own); its protectee link is drawn from the parent
		# NPC's _redraw via _draw_guard_link (the PatrolBehavior child-scan idiom).


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	# HazardZone first (danger tint); the other three zones share the cyan material. TutorialPrompt is a
	# TriggerVolume subclass and falls into the cyan group, which is correct.
	if node is HazardZone:
		_draw_zone(gizmo, node, "danger")
	elif node is TriggerVolume:
		# A TriggerVolume IS a zone (cyan), AND it routes to its target / activate nodes — draw both.
		_draw_zone(gizmo, node, "zone")
		_draw_trigger_links(gizmo, node)
	elif node is AudioZone or node is ShadowVolume:
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
	elif node is AlarmPanel:
		_draw_alarm(gizmo, node)
	elif node is AmbientSound or node is Radio:
		_draw_audio_falloff(gizmo, node)
	elif node is Door:
		_draw_door_swing(gizmo, node)


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
		# Markers are shared across all definitions; ring each resolved marker at the FIRST definition's real
		# spawn_radius (the representative scatter), so a designer sees the actual landing disc, not a fixed dot.
		var r := maxf(0.1, _first_spawn_radius(spawner))
		for np in points:
			var m := spawner.get_node_or_null(np)
			if m is Node3D:
				var local := spawner.to_local((m as Node3D).global_position)
				gizmo.add_lines(Shapes.ring(r, Transform3D(Basis(), local)), get_material("spawn", gizmo))
		return
	for def in spawner.spawn_definitions:
		if def != null:
			gizmo.add_lines(Shapes.ring(maxf(0.1, _getf(def, &"spawn_radius", 2.0))), get_material("spawn", gizmo))


## The first non-null SpawnDefinition's spawn_radius (the representative scatter for marker placement), or 2.0
## if the spawner has no usable definition yet.
func _first_spawn_radius(spawner: Node3D) -> float:
	for def in spawner.spawn_definitions:
		if def != null:
			return _getf(def, &"spawn_radius", 2.0)
	return 2.0


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
	_draw_guard_link(gizmo, npc)


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


## If this NPC has a GuardDuty child pointed at a protectee_path, draw a thin line from the NPC to the protected
## node (mirrors _draw_patrol_link's child-scan — GuardDuty is a plain Node, so it can't host its own gizmo). A
## GuardDuty resolving only by protectee_group is SKIPPED: that VIP can't be resolved at edit time (the group is
## populated at runtime), so there's nothing to draw a line to.
func _draw_guard_link(gizmo: EditorNode3DGizmo, npc: Node3D) -> void:
	for c in npc.get_children():
		if c is GuardDuty:
			var gd := c as GuardDuty
			if gd.protectee_path.is_empty():
				return  # only protectee_group set — unresolvable in-editor
			var who := gd.get_node_or_null(gd.protectee_path)
			if who is Node3D:
				var local := npc.to_local((who as Node3D).global_position)
				gizmo.add_lines(PackedVector3Array([Vector3.ZERO, local]), get_material("guard_link", gizmo))
			return


## TriggerVolume routing: a thin line from the volume center to its generic-action `target` and to its
## `activate_node_path` node (whichever resolve). Makes "this trigger drives THAT node" visible in the viewport.
func _draw_trigger_links(gizmo: EditorNode3DGizmo, tv: Node3D) -> void:
	for path in [tv.target, tv.activate_node_path]:
		if path != null and not (path as NodePath).is_empty():
			var n := tv.get_node_or_null(path)
			if n is Node3D:
				var local := tv.to_local((n as Node3D).global_position)
				gizmo.add_lines(PackedVector3Array([Vector3.ZERO, local]), get_material("trigger_link", gizmo))


## AlarmPanel: a small cross marker at the panel (a faction-tint POI), plus a link line to its reinforcement
## `spawner_path` so the "trip -> this spawner" wiring reads in the viewport.
func _draw_alarm(gizmo: EditorNode3DGizmo, panel: Node3D) -> void:
	gizmo.add_lines(Shapes.cross(0.4), get_material("alarm", gizmo))
	if not (panel.spawner_path as NodePath).is_empty():
		var s := panel.get_node_or_null(panel.spawner_path)
		if s is Node3D:
			var local := panel.to_local((s as Node3D).global_position)
			gizmo.add_lines(PackedVector3Array([Vector3.ZERO, local]), get_material("alarm", gizmo))


## AmbientSound / Radio audible reach: a wire sphere at the node's audible distance, so a designer sees how far
## the bed / radio carries. AmbientSound authors it as `max_distance` (0 = engine default, nothing to draw);
## Radio authors it as `audible_radius` (the NPC-hearing reach).
func _draw_audio_falloff(gizmo: EditorNode3DGizmo, node: Node3D) -> void:
	var r := 0.0
	if node is Radio:
		r = _getf(node, &"audible_radius", 0.0)
	else:
		r = _getf(node, &"max_distance", 0.0)  # 0 = AudioStreamPlayer3D default; no authored extent to draw
	if r > 0.0:
		gizmo.add_lines(Shapes.sphere(r), get_material("falloff", gizmo))


## Door swing arc: a fan from the pivot's local position out to a unit radius, sweeping from the closed panel
## (its current pivot yaw) to the open angle (closed + open_angle). Reads as "the panel swings through HERE".
## No-op without a pivot (open/close are no-ops then anyway).
func _draw_door_swing(gizmo: EditorNode3DGizmo, door: Node3D) -> void:
	var pivot := door.get(&"pivot") as Node3D
	if pivot == null:
		return
	var open_deg := _getf(door, &"open_angle", 90.0)
	# Arc angles use the atan2(x, z) convention (0 = +Z). Start at the pivot's current yaw, sweep by open_angle.
	var start_rad := pivot.rotation.y
	var pivot_pos := door.to_local(pivot.global_position)
	var radius := 1.0
	var x := Transform3D(Basis(), pivot_pos)
	gizmo.add_lines(Shapes.arc(radius, start_rad, deg_to_rad(open_deg), x), get_material("swing", gizmo))


## Read a numeric export defensively (.get() returns null if absent; non-numbers fall back to `def`).
func _getf(o: Object, prop: StringName, def: float) -> float:
	var v: Variant = o.get(prop)
	return float(v) if (v is float or v is int) else def
