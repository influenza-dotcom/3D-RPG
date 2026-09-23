extends RefCounted

## @system Run And Level Flow
## @seam WorldSpawn is THE parent for anything spawned into the 3D world at runtime — gore, corpses, gibs, blood / bullet / scorch / paint decals, dropped items and money bags, pulled props, projectiles, explosions, decoy noises, world FX: the streamed chunk under the spawn point, else the active level ("Level"), else the caller's old parent. So a spawn is parked and restored with its level (GameRoot's level cache), streams out with its chunk, and is freed by a reload — instead of outliving all three on the tree root.
## @risk A world spawn added straight to get_tree().root or current_scene outlives its level again: it hangs in the NEXT level's air after a door, survives a death reload, and floats over an unloaded chunk. Route every new spawn site through WorldSpawn.add / parent_for.
## @risk One-shot SOUNDS deliberately stay on the tree root (AudioManager, weapon_audio, the impact sfx reparented off a dying projectile, death.gd's splash): a sound must outlive its source, and an AudioStreamPlayer parked with a level stops without ever emitting `finished`, so its queue_free would never run.
## @test res://tests/test_world_spawn.gd
##
## Preloaded as a const where needed (NO class_name — several callers are @tool scripts, and a fresh class_name would
## not be in the editor's class cache yet; the WorldSaveId idiom). Consumers:
## `const WorldSpawn = preload("res://scripts/world/world_spawn.gd")`.
##
## WITHOUT A LEVEL (the start menu, a bare test scene, a scene with no GameRoot) nothing changes: the caller's
## `fallback` (its old parent — the Player's parent for a drop, current_scene for a SpawnOnDestroy) or the tree root.
## That is also why the GUT suite's "diff the root's children" spawn tests still see their spawns on the root.

## Metadata stamped on every node WorldSpawn.add places — "this came from the running game, not the level's author".
## PlayerLightLevel skips lights under it: world spawns used to live OUTSIDE current_scene, where its light scan never
## looked, and a corpse's blood-splat glow or a muzzle flash must not start giving the player away now that they
## live inside the level.
const META := &"world_spawn"


## The node a world spawn at `at` belongs under. `context` is any in-tree node (normally the spawner itself — it only
## supplies the SceneTree). `at` (a Vector3, or null when the position doesn't matter) picks the streamed chunk; the
## level root is used when there is no streamer, no position, or that cell isn't loaded. Null only when `context` is
## off-tree (nothing to spawn into).
static func parent_for(context: Node, at: Variant = null, fallback: Node = null) -> Node:
	if context == null or not is_instance_valid(context) or not context.is_inside_tree():
		return null
	var tree := context.get_tree()
	var level := Groups.level_node(tree)
	if level == null or not level.is_inside_tree():
		if fallback != null and is_instance_valid(fallback) and fallback.is_inside_tree():
			return fallback
		return tree.root
	if at is Vector3:
		var chunk := chunk_under(tree, level, at)
		if chunk != null:
			return chunk
	return level


## Add `node` to the world at `at` (see parent_for), keeping the transform the caller gave it in WORLD space — the
## contract every spawn site was written against when it parented to the root ("set position, add, local == world").
## Converted BEFORE add_child, so the node's own _ready already sees its real global position. Returns the parent.
## An off-tree `context` (a unit test's bare actor) keeps the old behaviour: straight under `fallback` when one was
## given, otherwise nothing is added and null comes back.
static func add(context: Node, node: Node, at: Vector3, fallback: Node = null) -> Node:
	if node == null:
		return null
	var parent := parent_for(context, at, fallback)
	if parent == null:
		if fallback == null or not is_instance_valid(fallback):
			return null
		parent = fallback
	if node is Node3D and parent is Node3D and parent.is_inside_tree() and not (node as Node3D).top_level:
		var n3 := node as Node3D
		n3.transform = (parent as Node3D).global_transform.affine_inverse() * n3.transform
	node.set_meta(META, true)
	parent.add_child(node)
	return parent


## The loaded chunk of `level`'s ChunkStreamer whose cell contains `at`, or null. Duck-typed on the streamer's
## coord_at / chunk_at (never `is ChunkStreamer`: this file is preloaded by @tool scripts).
static func chunk_under(tree: SceneTree, level: Node, at: Vector3) -> Node:
	for s in tree.get_nodes_in_group(Groups.CHUNK_STREAMER):
		if is_instance_valid(s) and level.is_ancestor_of(s) and s.has_method(&"chunk_at") and s.has_method(&"coord_at"):
			var chunk: Variant = s.call(&"chunk_at", s.call(&"coord_at", at))
			if chunk != null:
				return chunk
	return null


## Did WorldSpawn place `node` or one of its ancestors? (PlayerLightLevel's filter.)
static func is_spawned(node: Node) -> bool:
	var n := node
	while n != null:
		if n.has_meta(META):
			return true
		n = n.get_parent()
	return false
