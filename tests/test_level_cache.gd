extends GutTest

## LevelCache — GameRoot's LRU of DETACHED level instances. It never frees anything itself: put()/set_capacity()/drain()
## hand back what the caller must free, and freed entries are dropped instead of handed back.

const LevelCache = preload("res://scripts/world/level_cache.gd")


func _free_all(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()


func test_put_then_take_returns_the_same_instance() -> void:
	var c := LevelCache.new(2)
	var a := Node3D.new()
	assert_eq(c.put("res://a.tres", a).size(), 0, "nothing evicted under capacity")
	assert_true(c.has("res://a.tres"), "parked")
	assert_eq(c.take("res://a.tres"), a, "take hands back the very instance (its state is the point)")
	assert_false(c.has("res://a.tres"), "and removes it from the cache")
	assert_null(c.take("res://a.tres"), "a second take finds nothing")
	a.free()


func test_overflow_evicts_the_least_recently_used() -> void:
	var c := LevelCache.new(2)
	var a := Node3D.new()
	var b := Node3D.new()
	var d := Node3D.new()
	c.put("a", a)
	c.put("b", b)
	var ev := c.put("d", d)
	assert_eq(ev.size(), 1, "one over capacity -> one eviction")
	assert_eq(ev[0], a, "the oldest parked level goes")
	assert_eq(Array(c.keys()), ["b", "d"], "LRU first")
	_free_all(ev)
	_free_all(c.drain())


func test_capacity_zero_keeps_nothing() -> void:
	var c := LevelCache.new(0)
	var a := Node3D.new()
	var ev := c.put("a", a)
	assert_eq(ev.size(), 1, "capacity 0 is the old free-on-leave behaviour: the level comes straight back out")
	assert_eq(ev[0], a, "...and it's the level just parked")
	assert_false(c.has("a"), "and isn't parked")
	_free_all(ev)


func test_reparking_a_key_replaces_the_older_instance() -> void:
	var c := LevelCache.new(3)
	var old := Node3D.new()
	var fresh := Node3D.new()
	c.put("a", old)
	var ev := c.put("a", fresh)
	assert_eq(ev.size(), 1, "the stale instance for the same level is handed back")
	assert_eq(ev[0], old, "...and it's the older one")
	assert_eq(c.take("a"), fresh, "the new one is what's parked")
	_free_all(ev)
	fresh.free()


func test_freed_entries_are_skipped() -> void:
	var c := LevelCache.new(2)
	var a := Node3D.new()
	c.put("a", a)
	a.free()
	assert_false(c.has("a"), "a node freed while parked is not reported")
	assert_null(c.take("a"), "...nor handed back")
	assert_eq(c.keys().size(), 0, "...nor listed")


func test_set_capacity_and_drain_hand_back_live_nodes() -> void:
	var c := LevelCache.new(3)
	var a := Node3D.new()
	var b := Node3D.new()
	c.put("a", a)
	c.put("b", b)
	var ev := c.set_capacity(1)
	assert_eq(ev.size(), 1, "shrinking evicts the overflow")
	assert_eq(ev[0], a, "oldest first")
	var rest := c.drain()
	assert_eq(rest.size(), 1, "drain returns what's left")
	assert_eq(c.keys().size(), 0, "and empties the cache")
	_free_all(ev)
	_free_all(rest)


# --- GameRoot's level cache (Fallout's cell buffer) ----------------------------------------------------------------

const GAMEROOT := preload("res://scripts/world/game_root.gd")
const PATH_A := "user://test_level_cache_a.tres"
const PATH_B := "user://test_level_cache_b.tres"
const PATH_C := "user://test_level_cache_c.tres"

const WorldSnapshotScript := preload("res://scripts/world/world_snapshot.gd")

# GameRoot.load_level talks to the GameState AUTOLOAD (captures the level it leaves, records the active path): bank and
# restore everything it touches so the wider suite never inherits a test level's ledger bucket.
var _s_level_path: String
var _s_apply_pending: String
var _s_ledger: RefCounted
var _s_dead: Dictionary
var _s_has_respawn: bool
var _s_respawn_pos: Vector3
var _s_loaded: bool
var _s_matches: bool


func before_each() -> void:
	# A real GameRoot's _ready boots the SAVED level when GameState.loaded is set (the player's own autosave, in a GUT
	# run) — start every host as a fresh game so only the levels a test loads are ever live.
	_s_loaded = GameState.loaded
	_s_matches = GameState.respawn_level_matches
	_s_level_path = GameState.current_level_path
	GameState.loaded = false
	GameState.current_level_path = ""
	_s_apply_pending = GameState._level_apply_pending
	_s_ledger = GameState.world_snapshot
	_s_dead = GameState._dead_authored
	_s_has_respawn = GameState.has_respawn
	_s_respawn_pos = GameState.respawn_position
	GameState.world_snapshot = WorldSnapshotScript.new()
	GameState._dead_authored = {}


func after_each() -> void:
	GameState.loaded = _s_loaded
	GameState.respawn_level_matches = _s_matches
	GameState.current_level_path = _s_level_path
	GameState._level_apply_pending = _s_apply_pending
	GameState.world_snapshot = _s_ledger
	GameState._dead_authored = _s_dead
	GameState.has_respawn = _s_has_respawn
	GameState.respawn_position = _s_respawn_pos
	for p in [PATH_A, PATH_B, PATH_C]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## A saved LevelData (the cache keys on resource_path, so it needs a real one) whose scene is a body with a marker.
func _level(path: String, marker: String, keep: bool = true) -> LevelData:
	var body := Node3D.new()
	body.name = "Body"
	var m := Node.new()
	m.name = marker
	body.add_child(m)
	m.owner = body
	var ps := PackedScene.new()
	assert_eq(ps.pack(body), OK, "level %s packs" % marker)
	body.free()
	var d := LevelData.new()
	d.scene = ps
	d.keep_in_memory = keep
	assert_eq(ResourceSaver.save(d, path), OK, "level %s saves" % marker)
	return load(path) as LevelData


## A game.tscn-shaped host (Game > GameRoot + Player), in the tree, with no boot level.
func _host() -> Dictionary:
	var host := Node3D.new()
	host.name = "Game"
	var gr = GAMEROOT.new()
	gr.name = "GameRoot"
	var player := Node3D.new()
	player.name = "Player"
	host.add_child(gr)
	host.add_child(player)
	add_child_autofree(host)
	return {"host": host, "gr": gr}


func test_a_level_you_leave_comes_back_as_the_same_instance() -> void:
	var a := _level(PATH_A, "A")
	var b := _level(PATH_B, "B")
	var ctx := _host()
	var gr = ctx.gr
	gr.load_level(a)
	var first: Node = ctx.host.get_node(^"Level")
	var touched := Node.new()
	touched.name = "LeftBehind"  # anything the player did to the level — it must still be there on the way back
	first.add_child(touched)
	gr.load_level(b)
	assert_true(is_instance_valid(first) and not first.is_queued_for_deletion(), "leaving A PARKS it instead of freeing it")
	assert_false(first.is_inside_tree(), "...out of the tree, so nothing in it runs or shows")
	assert_true(Array(gr.cached_level_paths()).has(PATH_A), "A is listed as parked")
	gr.load_level(a)
	var back: Node = ctx.host.get_node(^"Level")
	assert_eq(back, first, "walking back into A re-attaches the very instance")
	assert_not_null(back.get_node_or_null(^"LeftBehind"), "...exactly as it was left")
	assert_eq(GameState.current_level_path, PATH_A, "the active level path follows the return")
	assert_eq(ctx.host.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Level")).size(), 1,
		"one Level child, never a stacked pair")


func test_cached_levels_zero_frees_on_leave() -> void:
	var a := _level(PATH_A, "A")
	var b := _level(PATH_B, "B")
	var ctx := _host()
	var gr = ctx.gr
	gr.cached_levels = 0
	gr.load_level(a)
	var first: Node = ctx.host.get_node(^"Level")
	gr.load_level(b)
	assert_true(not is_instance_valid(first) or first.is_queued_for_deletion(), "with no cache the old level is freed, as before")
	gr.load_level(a)
	assert_ne(ctx.host.get_node(^"Level"), first, "...and the return builds a fresh one")


func test_a_level_that_opts_out_is_freed() -> void:
	var a := _level(PATH_A, "A", false)
	var b := _level(PATH_B, "B")
	var ctx := _host()
	var gr = ctx.gr
	gr.load_level(a)
	var first: Node = ctx.host.get_node(^"Level")
	gr.load_level(b)
	assert_true(not is_instance_valid(first) or first.is_queued_for_deletion(), "keep_in_memory off -> freed on leave")
	assert_false(Array(gr.cached_level_paths()).has(PATH_A), "...and never parked")


func test_the_oldest_parked_level_is_evicted() -> void:
	var a := _level(PATH_A, "A")
	var b := _level(PATH_B, "B")
	var c := _level(PATH_C, "C")
	var ctx := _host()
	var gr = ctx.gr
	gr.cached_levels = 1
	gr.load_level(a)
	var level_a: Node = ctx.host.get_node(^"Level")
	gr.load_level(b)
	gr.load_level(c)
	assert_true(level_a.is_queued_for_deletion(), "A fell off a one-level cache when B was parked")
	assert_eq(Array(gr.cached_level_paths()), [PATH_B], "only the most recently left level stays")


func test_reloading_the_same_level_builds_a_fresh_copy() -> void:
	var a := _level(PATH_A, "A")
	var ctx := _host()
	var gr = ctx.gr
	gr.load_level(a)
	var first: Node = ctx.host.get_node(^"Level")
	gr.load_level(a, &"", false)  # the console's same-level reload
	assert_ne(ctx.host.get_node(^"Level"), first, "a same-level load is a reset, not a trip to the cache")
	assert_true(first.is_queued_for_deletion(), "...and the old copy is freed, not parked")


func test_parked_levels_are_freed_with_the_game_root() -> void:
	var a := _level(PATH_A, "A")
	var b := _level(PATH_B, "B")
	var ctx := _host()
	var gr = ctx.gr
	gr.load_level(a)
	var parked: Node = ctx.host.get_node(^"Level")
	gr.load_level(b)
	ctx.host.free()  # reload_current_scene / back to menu
	assert_true(not is_instance_valid(parked) or parked.is_queued_for_deletion(), "a parked level must not outlive its GameRoot (it is out of the tree — nothing else would free it)")


## A spawner's bodies leave the tree WITH the level when it is parked; that is not a despawn, and firing `cleared` (and
## the door wired to it) while the player is in another level would be.
func test_an_encounter_spawner_keeps_its_spawns_through_a_park() -> void:
	var level := Node3D.new()
	add_child_autofree(level)
	var spawner := EncounterSpawner.new()
	level.add_child(spawner)
	var npc := Node3D.new()
	level.add_child(npc)
	spawner._track_spawn(npc)
	var cleared := [false]
	spawner.cleared.connect(func() -> void: cleared[0] = true)
	remove_child(level)  # parked: the whole subtree leaves together
	assert_eq(spawner.alive_count(), 1, "a body that left with its level is still alive and tracked")
	assert_false(cleared[0], "...and the encounter is not cleared")
	add_child(level)
	level.remove_child(npc)  # detached ON ITS OWN (the pool parking a body) is a real departure
	assert_eq(spawner.alive_count(), 0, "a body removed by itself still counts as gone")
	npc.free()
