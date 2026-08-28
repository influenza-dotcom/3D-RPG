class_name NpcSenses
extends Node

## The environmental SCAN primitives an unaware NPC runs each idle frame, split off npc.gd: find the loudest audible
## &"noise" source, the nearest playing radio, and the nearest fresh body it can SEE. These are pure QUERIES (group
## scans + a line-of-sight ray) with NO host-state mutation — the stateful REACTIONS that consume them now live on
## NpcDistraction (npc_distraction.gd: react_unaware / react_music / discover_corpse; npc.gd keeps the 1-line
## facades), while their cross-consumed bookkeeping (_attending_radio, _scripted_investigating, the give-up clocks,
## the GA-1 alert latch) stays HOST-owned. Both reach these scans through NPC's
## _loudest_noise / _nearest_audible_radio / _nearest_visible_corpse facades.
##
## host is Node-typed to break the NpcSenses <-> NPC class cycle, so every host member is read DYNAMICALLY (a rename
## of one of those npc.gd members fails at RUNTIME, not compile — see scripts/npc/README.md). Every scan reads the
## live tree (group scans / raycasts) but mutates nothing, so it's re-entrant and side-effect-free; off-tree the
## component is never built and NPC's facades return null, exactly as the monolith behaved.

var host: Node = null

## The loudest &"noise" source currently reaching us, or null. Distance-based, with WALL occlusion folded in
## (Perception.hearing_attenuation cuts a source's effective radius when a wall sits between us and it — off by
## default, so it's distance-only as before). Picks by the OCCLUSION-ADJUSTED reach, so a clear soft source can
## beat a walled-off loud one. The player emits one live; thrown decoys / ambient machines add more.
func loudest_noise() -> NoiseSource:
	var me: Vector3 = host.global_position
	var best: NoiseSource = null
	var best_reach := 0.0
	for n in host.get_tree().get_nodes_in_group(NoiseSource.GROUP):
		var src := n as NoiseSource
		if src == null:
			continue
		var reach := src.radius
		if host._perception != null:
			reach *= host._perception.hearing_attenuation(src.global_position)
		if not NoiseSource.audible(reach, src.global_position, me):
			continue
		if best == null or reach > best_reach:
			best = src
			best_reach = reach
	return best

## The nearest PLAYING radio within its own audible_radius of us, or null. Duck-typed over the &"music" group (a
## radio joins it while on) so this never references the Radio class (radio.gd already references NPC -- a hard type
## both ways would be a cyclic class reference). In-tree (group scan + global_position).
func nearest_audible_radio() -> Node3D:
	var me: Vector3 = host.global_position
	var best: Node3D = null
	var best_d := INF
	for n in host.get_tree().get_nodes_in_group(Groups.MUSIC):
		if not (n is Node3D) or not n.has_method(&"is_playing") or not n.has_method(&"quality_text"):
			continue
		var radio := n as Node3D
		if not bool(radio.call(&"is_playing")):
			continue
		var radius_v: Variant = radio.get(&"audible_radius")  # duck-typed: a &"music" node may lack it -> skip (neutral)
		if not (radius_v is float or radius_v is int):
			continue
		var reach := float(radius_v)
		var d := me.distance_to(radio.global_position)
		if d <= reach and d < best_d:
			best_d = d
			best = radio
	return best

## Nearest fresh, undiscovered body this NPC can SEE (range gate + a line-of-sight ray), or null. The SCAN half of
## stealth body-discovery; the caller (NpcDistraction.discover_corpse, via NPC's facades) decides the reaction. Null when the feature is off
## (host._body_discovery_on()) or we can't sense (dead / fleeing / no Perception).
func nearest_visible_corpse() -> Corpse:
	if not host._body_discovery_on():
		return null
	if host._perception == null or host._dead or host.hp <= 0.0 or host.is_fleeing():
		return null
	var sight: float = host._perception.sight_range
	var eye: Vector3 = host.global_position + Vector3.UP * host._perception.eye_height
	for c in host.get_tree().get_nodes_in_group(Corpse.GROUP):
		if not (c is Corpse) or (c as Corpse).discovered:
			continue
		var cpos := (c as Node3D).global_position
		if not Corpse.noticeable(cpos, host.global_position, sight):
			continue
		if _corpse_occluded(eye, cpos):
			continue
		return c as Corpse
	return null

## True when solid geometry sits between our eyes and the body — a WALL blocks the sighting. A ragdoll / loot corpse
## resting AT the death spot is NOT an occluder: the ray hits it right at the end (≈ full distance), so we only count
## a hit that lands well SHORT of the body. World-guarded so off-tree callers never raycast.
func _corpse_occluded(eye: Vector3, cpos: Vector3) -> bool:
	var world = host.get_world_3d()  # plain = : dynamic host call returns Variant (no := inference off a Node-typed host)
	if world == null or not world.space.is_valid():
		return false
	var to := cpos + Vector3.UP * 0.3  # aim a touch above the floor (body height), not at the ground plane
	var q := PhysicsRayQueryParameters3D.create(eye, to)
	q.exclude = [host]  # our OWN body isn't an occluder (was [self] on the NPC; host is that same node)
	# A prop the player is CARRYING (parked on the held layer, floated in front of their face) must not hide a body
	# from our sight — raycasts ignore the carrier's collision exception, so mask the held bit out.
	q.collision_mask = 0xFFFFFFFF & ~TalkHelpers.held_prop_collision_layer()
	# SightRay, not a raw intersect_ray: a body lying behind a chain-link fence is in plain view, so see-through
	# geometry must not hide it (the caster steps past it and reports the first genuinely opaque thing).
	var hit: Dictionary = SightRay.cast(world, q)  # annotate: `world` is Variant (see above), so `:=` can't infer
	if hit.is_empty():
		return false
	var hit_pos: Vector3 = hit.get("position")
	return eye.distance_to(hit_pos) < eye.distance_to(to) - 0.5
