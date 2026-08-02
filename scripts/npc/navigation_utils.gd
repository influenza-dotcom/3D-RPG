class_name NavigationUtils
extends RefCounted

## Shared navigation helpers (static-only; never instanced).

## True once a navigation map has finished its FIRST synchronization (RID valid AND iteration_id != 0). Querying a
## map before then — map_get_closest_point() on an early frame, or a freshly (re)baked map — ERRORS ("query made
## before first map synchronization"), so gate every nav-map query on this. See [[nav-map-query-before-sync]].
static func is_nav_map_ready(map: RID) -> bool:
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) != 0

## STRONGER gate than is_nav_map_ready — use it before any query whose answer you only get ONE chance to act on.
##
## Measured on Godot 4.7.1 (headless, one region, one polygon): map_get_iteration_id() flips to 1 a full sync pass
## BEFORE the map's regions carry queryable polygons. At iteration 1 the query no longer ERRORS, but answers the
## ORIGIN for every probe; it only becomes truthful at iteration 2 (frame 6 vs frame 3 in that measurement).
##
##   frame 3  iteration_id=1  is_nav_map_ready=true   closest_point(5,0,5)=(0,0,0)   <-- ready, but lying
##   frame 6  iteration_id=2  is_nav_map_ready=true   closest_point(5,0,5)=(5,0,5)
##
## For a query that RETRIES every frame (npc.gd's _snap_to_navmesh) that window is harmless — it self-corrects. For a
## ONE-SHOT it is fatal: NavLink.auto_project spent its single attempt against an empty map, measured every endpoint
## as |world position| off-mesh, kept the authored point, and disabled itself forever. Gate one-shots on this instead.
##
## `probe` is a world point you expect to be near the mesh. A probe at (or within a metre of) the origin can't be told
## apart from the "answered origin" failure, so we optimistically pass it rather than block a legitimately-centred map.
static func map_answers_queries(map: RID, probe: Vector3) -> bool:
	if not is_nav_map_ready(map):
		return false
	if probe.length_squared() < 1.0:
		return true
	return NavigationServer3D.map_get_closest_point(map, probe) != Vector3.ZERO
