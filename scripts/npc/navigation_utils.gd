class_name NavigationUtils
extends RefCounted

## Shared navigation helpers (static-only; never instanced).

## True once a navigation map has finished its FIRST synchronization (RID valid AND iteration_id != 0). Querying a
## map before then — map_get_closest_point() on an early frame, or a freshly (re)baked map — ERRORS ("query made
## before first map synchronization"), so gate every nav-map query on this. See [[nav-map-query-before-sync]].
static func is_nav_map_ready(map: RID) -> bool:
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) != 0
