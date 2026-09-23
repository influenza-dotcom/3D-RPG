extends GutTest

## WorldSpawn — the one parent for runtime world spawns (gore, corpses, decals, drops, projectiles, world FX): the
## streamed chunk under the spawn point, else the active level, else the caller's old parent / the tree root. Plus the
## ratchet that keeps new spawn sites from going back to the tree root, and the stealth-light carve-out.

const WorldSpawn = preload("res://scripts/world/world_spawn.gd")
const STREAMER := "res://scripts/world/chunk_streamer.gd"


## A stand-in for game.tscn: a node in Groups.GAME_ROOT with a "Level" child — all Groups.level_node needs. NOT a real
## GameRoot: its _ready would boot the player's saved level into the test.
func _game_with_level(level_offset: Vector3 = Vector3.ZERO) -> Dictionary:
	var game := Node3D.new()
	game.name = "Game"
	game.add_to_group(Groups.GAME_ROOT)
	var level := Node3D.new()
	level.name = "Level"
	level.position = level_offset
	game.add_child(level)
	add_child_autofree(game)
	return {"game": game, "level": level}


func test_without_a_level_the_old_parent_is_kept() -> void:
	var spawner := Node3D.new()
	add_child_autofree(spawner)
	assert_eq(WorldSpawn.parent_for(spawner, Vector3.ZERO), get_tree().root, "no GameRoot level -> the tree root, as every site did before")
	var old_parent := Node.new()
	add_child_autofree(old_parent)
	assert_eq(WorldSpawn.parent_for(spawner, null, old_parent), old_parent, "...or the caller's own old parent when it names one")


func test_with_a_level_spawns_go_into_it() -> void:
	var ctx := _game_with_level()
	var spawner := Node3D.new()
	add_child_autofree(spawner)  # the spawner can live anywhere — the Player sits beside the level, not in it
	var decal := Node3D.new()
	var parent := WorldSpawn.add(spawner, decal, Vector3(3, 0, 4))
	assert_eq(parent, ctx.level, "a world spawn goes under the active Level")
	assert_eq(decal.get_parent(), ctx.level, "...really parented there")
	assert_true(decal.has_meta(WorldSpawn.META), "and is stamped as a runtime world spawn")
	var fallback := Node.new()
	add_child_autofree(fallback)
	assert_eq(WorldSpawn.parent_for(spawner, null, fallback), ctx.level, "a level beats the caller's fallback")


func test_add_keeps_the_world_transform_under_a_moved_parent() -> void:
	var ctx := _game_with_level(Vector3(100, 5, -20))
	var spawner := Node3D.new()
	add_child_autofree(spawner)
	var corpse := Node3D.new()
	corpse.position = Vector3(7, 1, 2)  # authored in WORLD space, the root-parented contract every site was written for
	corpse.rotation.y = 1.0
	WorldSpawn.add(spawner, corpse, corpse.position)
	assert_true(corpse.global_position.is_equal_approx(Vector3(7, 1, 2)), "the spawn stays where it was put in the world (%s)" % corpse.global_position)
	assert_almost_eq(corpse.global_rotation.y, 1.0, 0.0001, "...facing the way it was put")


func test_a_streamed_world_puts_the_spawn_in_the_chunk_under_it() -> void:
	var ctx := _game_with_level()
	var streamer: Node3D = load(STREAMER).new()
	streamer.chunk_size = 16.0
	ctx.level.add_child(streamer)
	# Stand in for a loaded chunk: chunk_at reads the streamer's live map, so register a node the way _add_chunk does.
	var chunk := Node3D.new()
	chunk.name = "Chunk_1_0"
	streamer.add_child(chunk)
	streamer._live[Vector2i(1, 0)] = chunk
	var spawner := Node3D.new()
	add_child_autofree(spawner)
	assert_eq(WorldSpawn.parent_for(spawner, Vector3(20, 0, 5)), chunk, "a spawn inside a loaded cell belongs to that chunk — it unloads with the ground it lies on")
	assert_eq(WorldSpawn.parent_for(spawner, Vector3(-40, 0, 5)), ctx.level, "a cell that isn't loaded falls back to the level")
	assert_eq(WorldSpawn.parent_for(spawner), ctx.level, "no position -> the level (a trail or spark that crosses cells)")
	streamer._live.clear()


func test_an_off_tree_spawner_keeps_its_fallback_or_adds_nothing() -> void:
	var bare := Node3D.new()  # a unit test's off-tree actor
	var fallback := Node3D.new()
	var drop := Node3D.new()
	assert_eq(WorldSpawn.add(bare, drop, Vector3.ZERO, fallback), fallback, "off-tree with a fallback -> the old behaviour (its parent)")
	assert_eq(drop.get_parent(), fallback, "...really added there")
	var orphan := Node3D.new()
	assert_null(WorldSpawn.add(bare, orphan, Vector3.ZERO), "off-tree with no fallback -> nothing to spawn into")
	assert_null(orphan.get_parent(), "...and the node is left unparented")
	orphan.free()
	fallback.free()
	bare.free()


func test_is_spawned_sees_descendants() -> void:
	var ctx := _game_with_level()
	var spawner := Node3D.new()
	add_child_autofree(spawner)
	var decal := Node3D.new()
	var light := OmniLight3D.new()
	decal.add_child(light)
	WorldSpawn.add(spawner, decal, Vector3.ZERO)
	assert_true(WorldSpawn.is_spawned(light), "a light carried by a spawned decal counts as spawned")
	var authored := OmniLight3D.new()
	ctx.level.add_child(authored)
	assert_false(WorldSpawn.is_spawned(authored), "a level's own light does not")


## Spawns now live INSIDE the level, where the stealth light scan looks; before, they sat on the root outside it. A
## corpse's blood glow or a muzzle flash must not start giving the player away.
func test_the_stealth_light_scan_skips_world_spawn_lights() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var meter := PlayerLightLevel.new()
	host.add_child(meter)
	var street := OmniLight3D.new()
	add_child_autofree(street)
	var decal := Node3D.new()
	var glow := OmniLight3D.new()
	decal.add_child(glow)
	WorldSpawn.add(host, decal, Vector3.ZERO)  # no level here -> the root, stamped all the same
	autofree(decal)
	var lights: Array[Node] = meter._collect_lights()
	assert_true(lights.has(street), "an authored light still counts")
	assert_false(lights.has(glow), "a runtime spawn's light never feeds the stealth meter")


## EffectFactory (an autoload, so outside the level itself) routes its point spawns through WorldSpawn too.
func test_effect_factory_spawns_into_the_level() -> void:
	var ctx := _game_with_level()
	var scene := PackedScene.new()
	var n := Node3D.new()
	scene.pack(n)
	n.free()
	var inst: Node = EffectFactory.spawn_at(scene, Vector3(1, 2, 3))
	assert_not_null(inst, "the factory spawned")
	if inst != null:
		assert_eq(inst.get_parent(), ctx.level, "into the active level, not the tree root")


# --- the ratchet -----------------------------------------------------------------------------------------------

## Production source may not add a node to the tree root / current scene or reparent one there, EXCEPT the one-shot
## sounds that must outlive their source (see WorldSpawn's @risk) and non-world code (UI, debug, tools). Everything
## else goes through WorldSpawn. Each allowed line is pinned by FILE + a substring of the line, so a new root spawn in
## an allowed file still fails.
const ROOTS := ["res://scripts", "res://managers", "res://scenes"]
const SKIP_DIRS := ["res://scripts/ui", "res://scripts/tools"]
const ALLOWED := {
	"res://managers/AudioManager.gd": ["add_child(player)", "add_child(applause)"],
	"res://scripts/combat/weapon_audio.gd": ["add_child(one_shot)"],
	"res://scripts/projectiles/projectile.gd": ["add_child(one_shot)", "sfx.reparent("],
	"res://scripts/effects/blood_drop.gd": ["impact_sfx.reparent("],
	"res://scripts/effects/explosion.gd": ["sfx.reparent("],
	"res://scripts/npc/death.gd": ["add_child(player)"],
	"res://scripts/world/world_spawn.gd": [],
}
const PATTERNS := ["get_tree().root.add_child(", "tree.root.add_child(", "get_root().add_child(", "current_scene.add_child(", "reparent(get_tree().root", "reparent(tree.root"]


func test_no_world_spawn_goes_straight_to_the_tree_root() -> void:
	var offenders: PackedStringArray = []
	for dir in ROOTS:
		_scan(dir, offenders)
	assert_eq(offenders.size(), 0, "route world spawns through WorldSpawn.add / parent_for (sounds are the only allowed root spawns):\n" + "\n".join(offenders))


func _scan(dir: String, offenders: PackedStringArray) -> void:
	if dir in SKIP_DIRS:
		return
	for sub in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(sub), offenders)
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd") or f.begins_with("debug_"):
			continue
		var path := dir.path_join(f)
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			for pat in PATTERNS:
				if not code.contains(pat):
					continue
				var ok := false
				for allowed in ALLOWED.get(path, []):
					ok = ok or code.contains(allowed)
				if not ok:
					offenders.append("%s:%d  %s" % [path, n, code])
