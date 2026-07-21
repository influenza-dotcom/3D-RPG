extends RefCounted

## Preloaded as a const where needed (NO class_name — nothing for the global script class cache to miss, so
## headless GUT compiles it without a prior --import, matching WorldSaveId / Factions / GoapLibrary / ItemIds).
## Consumers: `const WorldSnapshot = preload("res://scripts/world/world_snapshot.gd")` (GameState, GameRoot, tests).
##
## @system Save Model — the EXACT-snapshot tier (Phase 1: authored-NPC death + position)
## @seam Rides the MANUAL quicksave/slot layer ONLY: built in GameState._capture_and_write, written as a sibling
##   [world_snapshot] cfg section, applied by GameRoot.load_level (central push) gated on consume_world_snapshot().
##   The lean Dark-Souls autosave/Continue NEVER carries one — see GameState.autosave (nulls it) + save_to_disk.
## @risk This is a SEPARATE product from the profile save. Never merge it into GameState's profile fields / capture()
##   or the two blur the moment autosave runs (CLAUDE.md "Save semantics must be explicit"). world_objects is untouched.
## @risk NPC identity is POSITION-INDEPENDENT (NPC.snapshot_key), NOT WorldSaveId.key_for — an NPC moves, so a
##   position-keyed match would fail against the reloaded node sitting at its authored .tscn spot.
## @test res://tests/test_world_snapshot.gd
##
## An exact world snapshot, decoupled from the profile. Phase 1 captures the one thing that proves the whole
## capture -> reload -> apply seam end to end: which AUTHORED NPCs are alive (and where), and which have died.
## Later phases grow the same capture()/apply() entry points with containers, corpses, loot drops, money bags,
## and dynamic (EncounterSpawner) NPCs — see docs / the WorldSnapshot design brief.
##
## SHAPE (round-trips through ConfigFile as a nested Dictionary, exactly like GameState.world_objects):
##   { "<level_res_path>": {
##       "authored_npcs": { "<snapshot_key>": { alive: true, pos: Vector3, yaw: float, hp: float } },
##       "dead_authored": [ "<snapshot_key>", ... ] } }
## LIVE npcs go in authored_npcs (a dead NPC has already freed itself, so it can't be seen at capture time — its
## key rides in dead_authored instead, sourced from GameState's live per-level death ledger).
##
## Own version stamp, DECOUPLED from GameState.SAVE_VERSION: a snapshot-schema change bumps this alone, and a
## snapshot the running code doesn't understand is simply ignored (the profile still loads).
const SNAPSHOT_VERSION := 1

## level_path -> { "authored_npcs": {...}, "dead_authored": [...] }. Private; round-tripped via to_dict/from_dict.
var _data: Dictionary = {}

## Walk the live tree and record the current level's NPC state. `dead_keys` is GameState's per-level ledger of
## authored NPCs that have ALREADY died this run (they've freed themselves, so they aren't in the tree to find);
## it's unioned with any NPC caught mid-death-freeze (in-tree but not is_alive()). Duck-typed on snapshot_key /
## is_alive / hp so a test can drive it with lightweight stubs (and so a non-NPC group member can't crash it).
func capture(tree: SceneTree, level_path: String, dead_keys: Variant = {}) -> void:
	var live := {}
	var dead := {}
	if dead_keys is Dictionary:
		for k in dead_keys:
			dead[str(k)] = true
	elif dead_keys is Array:
		for k in dead_keys:
			dead[str(k)] = true
	if tree != null:
		for n in tree.get_nodes_in_group(Groups.NPC):
			if not is_instance_valid(n) or not n.has_method(&"snapshot_key"):
				continue
			# A pooled (NpcPool) body is a DYNAMIC encounter spawn — excluded from the exact-save tier, matching
			# NPC._record_snapshot_death's own pooled skip. Without this the two halves disagree: capture would write
			# a live pooled enemy (keyed by its ephemeral runtime node_path) into authored_npcs, bloating the save
			# with entries that match nothing on reload (the encounter re-arms via trigger, not restore).
			if n.get(&"_pool") != null:
				continue
			var key: String = str(n.snapshot_key())
			if key.is_empty():
				continue
			# _dead-but-still-in-tree (a save taken inside the death-freeze beat) counts as dead, not live.
			if n.has_method(&"is_alive") and not n.is_alive():
				dead[key] = true
				continue
			var hp_v: Variant = n.get(&"hp")
			live[key] = {
				"alive": true,
				"pos": n.global_position,
				"yaw": n.rotation.y,
				"hp": float(hp_v) if (hp_v is float or hp_v is int) else 0.0,
			}
	_data[level_path] = {"authored_npcs": live, "dead_authored": dead.keys()}

## Central PUSH after the level subtree is ready (GameRoot.load_level, deferred). Match each reloaded NPC by its
## snapshot_key: a key in dead_authored -> the authored NPC had died, so free the fresh-alive spawn (a silent
## queue_free, NOT a death — no FX / loot re-roll; corpse reconstruction lands in Phase 3). A key in authored_npcs
## -> hand it back its saved transform + hp. Unmatched reloaded NPCs (e.g. a dynamic spawn not yet captured) are
## left alone. queue_free is deferred, so freeing while iterating the group snapshot is safe.
func apply(tree: SceneTree, level_path: String) -> void:
	if tree == null:
		return
	var bucket: Variant = _data.get(level_path)
	if not (bucket is Dictionary):
		return
	var live: Dictionary = bucket.get("authored_npcs", {})
	var dead := {}
	for k in bucket.get("dead_authored", []):
		dead[str(k)] = true
	for n in tree.get_nodes_in_group(Groups.NPC):
		if not is_instance_valid(n) or not n.has_method(&"snapshot_key"):
			continue
		var key: String = str(n.snapshot_key())
		if dead.has(key):
			n.queue_free()
		elif live.has(key):
			var s: Dictionary = live[key]
			if n.has_method(&"restore_snapshot_state"):
				n.restore_snapshot_state(s.get("pos", Vector3.ZERO), float(s.get("yaw", 0.0)), float(s.get("hp", 0.0)))

## The dead-authored keys per level as a { level_path -> { key: true } } ledger — GameState reloads its live death
## accumulator from this on a snapshot load, so NPCs that die AFTER the load keep piling onto the right set.
func dead_map() -> Dictionary:
	var out := {}
	for lvl in _data:
		var b: Variant = _data[lvl]
		if b is Dictionary:
			var m := {}
			for k in b.get("dead_authored", []):
				m[str(k)] = true
			if not m.is_empty():
				out[str(lvl)] = m
	return out

## Nothing worth persisting? (No live NPC captured and no death recorded, for any level.) GameState skips writing
## the [world_snapshot] section when this is true, so an empty snapshot never bloats a save.
func is_empty() -> bool:
	for lvl in _data:
		var b: Variant = _data[lvl]
		if b is Dictionary:
			if (b.get("authored_npcs", {}) as Dictionary).size() > 0:
				return false
			if (b.get("dead_authored", []) as Array).size() > 0:
				return false
	return true

## Deep copy for the ConfigFile round-trip (Vector3s are value types, so a deep duplicate of the nesting is safe).
func to_dict() -> Dictionary:
	return _data.duplicate(true)

## Rebuild from a loaded cfg Dictionary; junk-typed input degrades to empty rather than crashing the boot load.
func from_dict(d: Variant) -> void:
	_data = (d as Dictionary).duplicate(true) if d is Dictionary else {}
