extends RefCounted

## @system World Streaming
## @seam ChunkGrid is the pure grid math behind ChunkStreamer: a world position -> Vector2i chunk coord, the load ring around a coord (nearest first), and the load/unload plan with hysteresis.
## @risk Changing chunk_node_name's shape re-keys every un-authored object in every chunk (WorldSaveId's fallback + NPC.snapshot_key both fold in the node path), so saved chunk state silently stops matching.
## @risk plan() must never unload inside unload_radius: a load ring equal to the unload ring thrashes a chunk load/free every step across a border.
## @test res://tests/test_chunk_grid.gd
##
## Preloaded as a const where needed (NO class_name — nothing for the global script class cache to miss, matching
## WorldSaveId / WorldSnapshot). Consumers: `const ChunkGrid = preload("res://scripts/world/chunk_grid.gd")`.
##
## THE GRID (the Fallout "exterior cell" model): the ground plane (X/Z) is cut into square chunks `size` metres wide,
## starting at `origin`. Chunk (0, 0) covers [origin.x, origin.x + size) x [origin.z, origin.z + size); negative coords
## run the other way. Height (Y) is ignored — a chunk is a vertical column, so a tower or a basement belongs to the chunk
## under it. Distances between chunks are CHEBYSHEV (a ring, not a circle): radius 1 = the 3x3 block around the player,
## radius 2 = 5x5 — Fallout 3's uGridsToLoad of 5 is load_radius 2.


## The chunk coord that contains `pos`. floori, not int(): int() truncates toward zero, which would fold -0.5 m and
## +0.5 m into the same chunk 0 and make the chunk left of the origin twice as wide.
static func coord_for(pos: Vector3, size: float, origin: Vector3 = Vector3.ZERO) -> Vector2i:
	var s := maxf(size, 0.001)  # a zero/negative size is an authoring fault; never divide by it
	return Vector2i(floori((pos.x - origin.x) / s), floori((pos.z - origin.z) / s))


## The world-space corner (min X, min Z, at origin.y) of `coord` — where a chunk scene's root is placed, so a chunk is
## authored around its own local origin: (0,0,0) .. (size, *, size).
static func chunk_origin(coord: Vector2i, size: float, origin: Vector3 = Vector3.ZERO) -> Vector3:
	return Vector3(origin.x + coord.x * size, origin.y, origin.z + coord.y * size)


## Chebyshev distance between two chunk coords (how many rings apart they are).
static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Every coord within `radius` rings of `center`, NEAREST FIRST (the centre, then ring 1, then ring 2 ...), so a
## streamer that requests in this order fills in outward from the player. Within a ring the order is fixed
## (row-major), which keeps a plan deterministic for tests. Negative radius -> empty.
static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if radius < 0:
		return out
	for r in range(0, radius + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) == r:
					out.append(Vector2i(center.x + dx, center.y + dz))
	return out


## What a streamer should do this step, given where the player is and what is already live. `live` is every coord
## the streamer has loaded OR has a load in flight for (a Dictionary keyed by Vector2i, or an Array of them).
##   load   — coords within `load_radius` that aren't live yet, nearest first.
##   unload — live coords FARTHER than `unload_radius`. The gap between the two radii is the hysteresis band: a chunk
##            that loaded at the edge of the load ring is not dropped again until the player has walked a whole ring
##            further away, so pacing back and forth across a border never thrashes. unload_radius is clamped to at
##            least load_radius (anything less would unload what this same step loads).
## `exists` (optional) filters the load list — a Callable(coord) -> bool, so gaps in the grid (ocean, the map edge)
## are never requested. Pure: it neither loads nor frees anything.
static func plan(center: Vector2i, live: Variant, load_radius: int, unload_radius: int, exists: Callable = Callable()) -> Dictionary:
	var keep := maxi(unload_radius, load_radius)
	var have := {}
	if live is Dictionary:
		for c in live:
			have[c] = true
	elif live is Array:
		for c in live:
			have[c] = true
	var to_load: Array[Vector2i] = []
	for c in ring(center, load_radius):
		if have.has(c):
			continue
		if exists.is_valid() and not bool(exists.call(c)):
			continue
		to_load.append(c)
	var to_unload: Array[Vector2i] = []
	for c in have:
		if c is Vector2i and distance(center, c) > keep:
			to_unload.append(c)
	return {"load": to_load, "unload": to_unload}


## The node name a chunk is added under. Deterministic on purpose: it is part of every un-authored object's save key
## inside the chunk (WorldSaveId's level|node-path|position fallback, NPC.snapshot_key's level|node-path), so the same
## chunk must come back under the same name every time it streams in. "Chunk_-1_2" for coord (-1, 2).
static func chunk_node_name(coord: Vector2i) -> String:
	return "Chunk_%d_%d" % [coord.x, coord.y]


## The scene file for `coord`: `template` with {x} / {z} replaced (by plain replace, never the % operator — a
## designer's literal % must not error), joined onto `folder`. "res://scenes/worlds/wasteland" + "chunk_{x}_{z}.tscn"
## + (-1, 2) -> "res://scenes/worlds/wasteland/chunk_-1_2.tscn".
static func chunk_path(folder: String, template: String, coord: Vector2i) -> String:
	var file := template.replace("{x}", str(coord.x)).replace("{z}", str(coord.y))
	if folder.is_empty():
		return file
	return folder.path_join(file)
