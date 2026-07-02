extends GutTest

## P2 (level flow): the drop-in components + GameRoot's no-arg / null-load surface. Pure / off-tree: PlayerSpawn
## and LevelDoor are inspected via .new() (no _ready), and GameRoot's load_level(null) is a guarded no-op needing
## no tree. The actual level swap + teleport drive the tree and a real LevelData, so they're playtest-verified.

func test_player_spawn_defaults_and_place() -> void:
	var ps := PlayerSpawn.new()
	assert_eq(ps.entry_id, &"", "entry_id defaults empty (the level's default arrival)")
	add_child_autofree(ps)  # in-tree: a Node3D's global_transform is invalid (errors + identity) off-tree
	ps.global_position = Vector3(5, 0, 3)
	ps.global_rotation = Vector3(0, 1.2, 0)
	var p := Node3D.new()
	add_child_autofree(p)
	ps.place(p)
	assert_eq(p.global_position, Vector3(5, 0, 3), "place() moves the player to the spawn position")
	assert_almost_eq(p.rotation.y, 1.2, 0.001, "place() faces the player along the spawn yaw")

func test_level_door_defaults() -> void:
	var d := LevelDoor.new()
	assert_null(d.target_level, "target_level defaults null")
	assert_eq(d.entry_id, &"", "entry_id defaults empty")
	assert_false(d.can_be_talked_to(), "a LevelDoor with no target_level isn't usable")
	assert_eq(d.look_name(), "Enter", "look_name falls back to 'Enter' with no target")
	d.free()

func test_game_root_surface_and_null_load_noop() -> void:
	var gr = load("res://scripts/world/game_root.gd").new()
	assert_true(gr.has_method("load_assigned_level"), "GameRoot exposes a no-arg load_assigned_level for triggers")
	assert_true(gr.has_method("load_level"), "GameRoot exposes load_level(data, entry_id)")
	gr.load_level(null)  # null data -> guarded no-op, no crash (off-tree)
	assert_null(gr.get_node_or_null(^"Level"), "load_level(null) adds no Level child")
	gr.free()

const TMP_LEVEL := "user://test_leveldata_tmp.tres"

func after_each() -> void:
	if FileAccess.file_exists(TMP_LEVEL):
		DirAccess.remove_absolute(TMP_LEVEL)

## P1 level-identity: GameRoot reloads the SAVED level (resolved by path) over its exported default on a loaded game.
func test_resolve_boot_level_prefers_saved_over_export() -> void:
	var exported := LevelData.new()
	var saved := LevelData.new()
	saved.scene = load("res://scenes/components/door.tscn")  # a saved level needs a scene to be boot-viable + preferred
	ResourceSaver.save(saved, TMP_LEVEL)  # give it a resource_path so resolve_boot_level's load() can resolve it
	var got = GameRoot.resolve_boot_level(exported, true, TMP_LEVEL)
	assert_eq(got.resource_path, TMP_LEVEL, "a loaded game reloads the SAVED level (by path), not the export")
	assert_eq(GameRoot.resolve_boot_level(exported, false, TMP_LEVEL), exported, "a fresh game (not loaded) uses the exported level")
	assert_eq(GameRoot.resolve_boot_level(exported, true, ""), exported, "a blank saved path falls back to the exported level")
	assert_eq(GameRoot.resolve_boot_level(exported, true, "res://nope_missing.tres"), exported, "an unresolvable saved path falls back to the export")
	exported = null
	saved = null

## A saved LevelData with no scene would boot into NO level (load_level no-ops on a null scene) — resolve must
## reject it and fall back to the exported level instead of stranding the player in an empty world.
func test_resolve_boot_level_rejects_sceneless_saved_level() -> void:
	var exported := LevelData.new()
	var broken := LevelData.new()  # no `scene` assigned
	ResourceSaver.save(broken, TMP_LEVEL)
	assert_eq(GameRoot.resolve_boot_level(exported, true, TMP_LEVEL), exported, "a scene-less saved level falls back to the export, not into nothing")
	exported = null
	broken = null

## The editor's Play-From-Spawn toolbar (a one-shot dev_entry) must place the player at the requested spawn EVEN
## when an autosave is loaded — otherwise the toolbar entry is consumed but never applied (P2).
func test_should_place_at_spawn_dev_override() -> void:
	assert_true(GameRoot.should_place_at_spawn(false, &""), "a fresh game places at the first spawn")
	assert_false(GameRoot.should_place_at_spawn(true, &""), "a plain loaded game keeps its saved respawn (no re-place)")
	assert_true(GameRoot.should_place_at_spawn(true, &"vault"), "Play-From-Spawn overrides a loaded autosave's respawn")
	assert_true(GameRoot.should_place_at_spawn(false, &"vault"), "Play-From-Spawn on a fresh game places at the requested spawn")


## M3 (level-identity gate): saved_level_is_bootable is the single source of truth behind resolve_boot_level AND the
## respawn-level-match gate — true ONLY when a LOADED game's saved path resolves to a scene-bearing LevelData.
func test_saved_level_is_bootable_matches_resolver() -> void:
	var saved := LevelData.new()
	saved.scene = load("res://scenes/components/door.tscn")  # scene-bearing -> boot-viable
	ResourceSaver.save(saved, TMP_LEVEL)
	assert_true(GameRoot.saved_level_is_bootable(true, TMP_LEVEL), "a loaded game with a resolvable, scene-bearing saved level is bootable")
	assert_false(GameRoot.saved_level_is_bootable(false, TMP_LEVEL), "a fresh game (not loaded) is never a saved-level boot")
	assert_false(GameRoot.saved_level_is_bootable(true, ""), "a blank saved path is NOT a saved-level boot (legacy / old save — no recorded identity)")
	assert_false(GameRoot.saved_level_is_bootable(true, "res://nope_missing.tres"), "an unresolvable saved path isn't bootable (its .tres was deleted/renamed)")
	saved = null

func test_saved_level_is_bootable_rejects_sceneless() -> void:
	var broken := LevelData.new()  # no `scene` assigned
	ResourceSaver.save(broken, TMP_LEVEL)
	assert_false(GameRoot.saved_level_is_bootable(true, TMP_LEVEL), "a scene-less saved level isn't bootable (would boot into nothing)")
	broken = null

## M3: a loaded game whose saved level could NOT be honored (respawn_level_matches=false) MUST place at the booted
## export's spawn — else the stale saved respawn strands the player / teleports the FIRST DEATH into the wrong level.
## The matched case (true) preserves the existing "keep the restored respawn, don't re-place" behavior.
func test_should_place_at_spawn_on_level_mismatch() -> void:
	assert_false(GameRoot.should_place_at_spawn(true, &"", true), "a loaded game with a HONORED saved level keeps its restored respawn (no re-place)")
	assert_true(GameRoot.should_place_at_spawn(true, &"", false), "a loaded game whose saved level was NOT honored re-places at the export's spawn")
	assert_true(GameRoot.should_place_at_spawn(false, &"", true), "a fresh game still places at the first spawn regardless of the flag")


## _host() resolves where the Player + Level live, so the script works ON the root OR as a drop-in child node.
func test_host_is_self_when_player_is_a_child() -> void:
	# Option A (script on the root): Player is a direct child -> host is GameRoot itself.
	var gr = load("res://scripts/world/game_root.gd").new()
	add_child_autofree(gr)
	var player := Node3D.new()
	player.name = "Player"
	gr.add_child(player)
	assert_eq(gr._host(), gr, "with a Player child, the host is GameRoot itself (script-on-root)")

func test_host_falls_back_to_parent_when_a_child_node() -> void:
	# Option B (script on a child node): Player is a SIBLING under the real root -> host is the parent.
	var root := Node3D.new()
	add_child_autofree(root)
	var player := Node3D.new()
	player.name = "Player"
	root.add_child(player)
	var gr = load("res://scripts/world/game_root.gd").new()
	root.add_child(gr)
	assert_eq(gr._host(), root, "as a child node with Player as a sibling, the host is the parent (drop-in)")
