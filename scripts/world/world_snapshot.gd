extends RefCounted

## Preloaded as a const where needed (NO class_name — nothing for the global script class cache to miss, so
## headless GUT compiles it without a prior --import, matching WorldSaveId / Factions / GoapLibrary / ItemIds).
## Consumers: `const WorldSnapshot = preload("res://scripts/world/world_snapshot.gd")` (GameState, GameRoot, tests).
##
## @system Save Model — the PER-LEVEL WORLD LEDGER (authored-NPC alive/pos/hp + deaths + container contents, for every visited level)
## NOTE: each @seam/@risk below must stay on ONE line — ArchScan only reads lines that start with a @tag, so a
## wrapped continuation line is DROPPED and the statement renders truncated in docs/SYSTEM_MAP.md.
## @seam GameState.world_snapshot is ONE long-lived instance holding a bucket per visited level: GameRoot.load_level captures the OUTGOING level before freeing it and applies the INCOMING level's bucket after it spawns; every save (autosave, Continue, quicksave, slots) captures the current level + folds the death ledger and writes the whole ledger as [world_snapshot].
## @risk A capture that runs BEFORE a freshly loaded level's bucket is applied overwrites the saved bucket with the level's authored seed (a looted safe restocks) — GameState._level_apply_pending is the guard; never capture a level whose apply is still queued.
## @risk The ledger and GameState.world_objects are two separate stores keyed differently (snapshot_key vs WorldSaveId.key_for); never merge them — doors/pickups ride world_objects, actors/containers ride this.
## @risk NPC identity is POSITION-INDEPENDENT (NPC.snapshot_key), NOT WorldSaveId.key_for — an NPC moves, so a position-keyed match would fail against the reloaded node sitting at its authored .tscn spot.
## @test res://tests/test_world_snapshot.gd
## @test res://tests/test_level_boot_lifecycle.gd
##
## The per-level WORLD LEDGER. One bucket per level the player has visited this run, each holding the level's authored
## NPCs (alive + pos/yaw/hp), the authored NPCs killed there, and every authored ItemContainer's exact contents (stacks
## incl. the coin tile, the grid-bounded bit + cell layout, a Lock child's state). A bucket is written by capture() —
## when the player LEAVES the level through GameRoot.load_level, and for the CURRENT level at every save — and read
## back by apply() every time that level loads again (a door return, Continue, a quickload, a death reload). So a safe
## looted in one building stays looted after the player has been through five other interiors, saved, quit and come
## back. Levels not in the tree keep whatever bucket they had; fold_dead_ledger adds deaths recorded since.
##
## HISTORY (policy, 2026-09-16): this used to be a SEPARATE product riding the manual quicksave/slots only, applied as a
## one-shot for the boot level, while autosave/Continue stayed a lean profile. It is now the ordinary save's world
## state. The profile fields and the additive GameState.world_objects ledger are unchanged and stay separate code.
## Still NOT in the ledger: corpses (a dead authored NPC just stays gone), loot drops / money bags, dynamic
## (EncounterSpawner) NPCs, NPC backpacks — the roadmap in docs/CURRENT_ARCHITECTURE.md (Save Model).
##
## SIZE (the autosave-storm budget): a capture REPLACES its level's bucket, so the payload is bounded by the authored
## content of the visited levels, never by play time or by how many times you save. See the measured per-entry sizes
## in docs/CURRENT_ARCHITECTURE.md (Save Model); tests/test_world_snapshot.gd pins that re-capturing does not grow it.
##
## SHAPE (round-trips through ConfigFile as a nested Dictionary, exactly like GameState.world_objects):
##   { "<level_res_path>": {
##       "authored_npcs": { "<snapshot_key>": { alive: true, pos: Vector3, yaw: float, hp: float } },
##       "dead_authored": [ "<snapshot_key>", ... ],
##       "containers": { "<snapshot_key>": { stacks: [{id, count, ...}], grid: bool, locked: bool? } } } }
## LIVE npcs go in authored_npcs (a dead NPC has already freed itself, so it can't be seen at capture time — its
## key rides in dead_authored instead, sourced from GameState's live per-level death ledger).
##
## Own version stamp, DECOUPLED from GameState.SAVE_VERSION: a snapshot-schema change bumps this alone, and a
## snapshot the running code doesn't understand is simply ignored (the profile still loads). The shape has only
## ever grown ADDITIVELY (v2 added "containers"; from_dict shape-filters whatever is absent/junk), so every
## version back to SNAPSHOT_MIN_COMPAT still loads — a pre-container quicksave keeps its NPC state instead of
## being dropped on update. The 2026-09-16 policy change did NOT bump it: the SHAPE is identical (a bucket per level
## always existed); only which levels carry live data changed, and an old single-level quicksave is simply a ledger
## that knows one level. Raise SNAPSHOT_MIN_COMPAT only for a genuinely BREAKING reshape.
const SNAPSHOT_VERSION := 2
const SNAPSHOT_MIN_COMPAT := 1

## level_path -> { "authored_npcs": {...}, "dead_authored": [...], "containers": {...} } (the full SHAPE block
## above). Private; round-tripped via to_dict/from_dict. Every write path (capture, fold_dead_ledger, from_dict)
## stores all three buckets, so a reader can assume the keys exist — the values may be empty.
var _data: Dictionary = {}

## Walk the live tree and REPLACE `level_path`'s bucket with what is there now. The caller guarantees the tree holds
## that level and only that level (GameRoot captures the outgoing level BEFORE detaching it; a save captures the current
## one). `dead_keys` is GameState's per-level ledger of authored NPCs that have ALREADY died this run (they've freed
## themselves, so they aren't in the tree to find); it's unioned with any NPC caught mid-death-freeze (in-tree but not
## is_alive()). Duck-typed on snapshot_key / is_alive / hp so a test can drive it with lightweight stubs (and so a
## non-NPC group member can't crash it).
##
## `include_live_npcs` false records NO live NPC entries (deaths and containers still record): the fresh-world death
## reload (RELOAD_CHECKPOINT_FRESH) banks the level this way so enemies return to their authored spots at full hp while
## looted crates stay looted — the in-memory profile it keeps still holds that loot, so re-seeding the crate would
## duplicate it.
func capture(tree: SceneTree, level_path: String, dead_keys: Variant = {}, include_live_npcs: bool = true) -> void:
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
			# A DYNAMIC encounter spawn (pooled OR pool-less — the spawner default is pool-less) is excluded from the
			# exact-save tier, matching NPC._record_snapshot_death's own dynamic-spawn skip. Without this, capture would
			# write a live spawner enemy (keyed by its ephemeral runtime node_path) into authored_npcs, bloating the save
			# with entries that match nothing on reload — and a re-triggered spawn landing on a stale @path could be
			# silently freed by apply(). The encounter re-arms via its trigger, not via snapshot restore.
			if n.get(&"_pool") != null or n.get(&"_dynamic_spawn") == true:
				continue
			var key: String = str(n.snapshot_key())
			if key.is_empty():
				continue
			# _dead-but-still-in-tree (a save taken inside the death-freeze beat) counts as dead, not live.
			if n.has_method(&"is_alive") and not n.is_alive():
				dead[key] = true
				continue
			# LIVE WINS over a stale ledger entry, whether or not live state is recorded: the death ledger only ever GROWS
			# (record_npc_death never prunes), but a killed authored NPC can come back ALIVE when its level re-instantiates
			# (a console `resurrect`, or a death ledger restored older than the level). If we see it alive in the tree now,
			# it is NOT dead at capture time — drop the stale key, or apply() (which frees dead-first) would delete an NPC
			# standing in front of the player and poison every later save of this level.
			dead.erase(key)
			if not include_live_npcs:
				continue
			var hp_v: Variant = n.get(&"hp")
			live[key] = {
				"alive": true,
				"pos": n.global_position,
				"yaw": n.rotation.y,
				"hp": float(hp_v) if (hp_v is float or hp_v is int) else 0.0,
			}
	# v2: every authored container's exact contents (duck-typed on snapshot_key/snapshot_contents so a test stub
	# drives it, and so the corpse/loot-bag classes — which share no snapshot surface yet — are simply skipped). Only the
	# level being walked is captured; every OTHER level keeps the bucket it was given when the player last left it.
	var conts := {}
	if tree != null:
		for c in tree.get_nodes_in_group(Groups.CONTAINERS):
			if not is_instance_valid(c) or not c.has_method(&"snapshot_key") or not c.has_method(&"snapshot_contents"):
				continue
			var ckey: String = str(c.snapshot_key())
			# A RUNTIME-spawned container (no authored save_id, so its key falls back to a generated "@Class@N"
			# node_path) has no stable identity to re-match on reload — the same rationale as the NPC dynamic-spawn
			# skip above. Authored scene nodes never carry '@' in their paths. The '@' test is scoped to the
			# node-path FALLBACK only: an "id:<save_id>" key is authored by hand and never contains a generated
			# path, so a designer whose save_id (or level filename) happens to contain '@' must not have their
			# container silently dropped from every quicksave.
			if ckey.is_empty() or (not ckey.begins_with("id:") and ckey.contains("@")):
				continue
			conts[ckey] = c.snapshot_contents()
	_data[level_path] = {"authored_npcs": live, "dead_authored": dead.keys(), "containers": conts}

## Fold the OTHER levels' death ledgers (everything except `current_level_path`, which capture() already owns with its
## live NPCs) into the snapshot as DEAD-ONLY buckets. Those levels aren't instantiated, so there's no live NPC data to
## capture — only the keys of authored NPCs the player killed while there. Without this, a quicksave stores only the level
## you saved IN, so dead_map() on load forgets cross-level kills and they resurrect when you door back. Merges into any
## existing bucket (defensive) so the current level's live data is never clobbered. `dead_authored_all` is GameState's
## live { level_path -> { key: true } } ledger; junk-typed buckets are skipped.
func fold_dead_ledger(dead_authored_all: Dictionary, current_level_path: String) -> void:
	for lvl in dead_authored_all:
		var lvl_s := str(lvl)
		if lvl_s == current_level_path:
			continue  # capture() already wrote this level (live + its dead)
		var b: Variant = dead_authored_all[lvl]
		if not (b is Dictionary):
			continue
		var merged := {}
		var existing: Variant = _data.get(lvl_s)
		if existing is Dictionary:
			for k in existing.get("dead_authored", []):
				merged[str(k)] = true
		for k in b:
			merged[str(k)] = true
		if merged.is_empty():
			continue
		var live: Dictionary = existing.get("authored_npcs", {}) if existing is Dictionary else {}
		# Containers only exist for the level capture() walked (other levels aren't in-tree), but carry any
		# existing bucket through defensively — fold must never drop sibling state while merging dead keys.
		var conts: Dictionary = existing.get("containers", {}) if existing is Dictionary else {}
		_data[lvl_s] = {"authored_npcs": live, "dead_authored": merged.keys(), "containers": conts}

## True when the ledger holds a bucket for `level_path` — GameRoot asks before queueing an apply, and GameState uses it
## to arm the capture guard (_level_apply_pending).
func has_level(level_path: String) -> bool:
	return _data.get(level_path) is Dictionary

## Central PUSH after the level subtree is ready (GameRoot.load_level, deferred — on EVERY load of a level the ledger
## has a bucket for). Match each reloaded NPC by its
## snapshot_key: a key in dead_authored -> the authored NPC had died, so free the fresh-alive spawn (a silent
## queue_free, NOT a death — no FX / loot re-roll; CORPSE REBUILD is the next unshipped item on the roadmap in
## docs/CURRENT_ARCHITECTURE.md, "The exact-snapshot tier roadmap"). A key in authored_npcs -> hand it back its
## saved transform + hp. Then every captured CONTAINER is handed its exact bag back (restore_snapshot_contents,
## which REPLACES the fresh _ready seed). Unmatched reloaded NPCs/containers (e.g. a dynamic spawn, or a crate
## added to the level after the save) are left alone. queue_free is deferred, so freeing while iterating the
## group snapshot is safe. SCOPE: only `level_path`'s bucket is applied (the only level in the tree).
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
	# v2: hand each captured container its exact bag back (it replaces its freshly-seeded contents). A container
	# NOT in the snapshot (added to the level after the save) keeps its authored seed — the graceful degrade; a
	# snapshot entry whose container no longer exists is simply unmatched.
	var conts: Dictionary = bucket.get("containers", {})
	if not conts.is_empty():
		for c in tree.get_nodes_in_group(Groups.CONTAINERS):
			if not is_instance_valid(c) or not c.has_method(&"snapshot_key") or not c.has_method(&"restore_snapshot_contents"):
				continue
			var ckey: String = str(c.snapshot_key())
			if conts.has(ckey):
				c.restore_snapshot_contents(conts[ckey])

## The dead-authored keys per level as a { level_path -> { key: true } } ledger — GameState reloads its live death
## accumulator from this on every load that carries a ledger, so NPCs that die AFTER the load pile onto the right set.
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

## Nothing worth persisting? (No live NPC, death or container recorded, for any level.) GameState skips writing the
## [world_snapshot] section when this is true, so a run that has not left its first empty level writes none.
func is_empty() -> bool:
	for lvl in _data:
		var b: Variant = _data[lvl]
		if b is Dictionary:
			if (b.get("authored_npcs", {}) as Dictionary).size() > 0:
				return false
			if (b.get("dead_authored", []) as Array).size() > 0:
				return false
			if (b.get("containers", {}) as Dictionary).size() > 0:
				return false
	return true

## Deep copy for the ConfigFile round-trip (Vector3s are value types, so a deep duplicate of the nesting is safe).
func to_dict() -> Dictionary:
	return _data.duplicate(true)

## Rebuild from a loaded cfg Dictionary, SHAPE-FILTERING every level. A hand-edited / corrupt file can hold ANY Variant
## under a key, so this coerces each bucket to the exact shapes dead_map()/apply() require — dead_authored -> Array[String],
## authored_npcs -> Dictionary of {pos:Vector3, yaw:float, hp:float}. Without this, a junk inner type (e.g. dead_authored=7,
## or a String pos) raises a runtime error DEEP inside a load that has already overwritten money/stats/flags in memory,
## aborting the reload mid-mutation and leaving the run on a half-loaded profile the next autosave then persists. Junk
## degrades to empty/default, never a crash — the same corrupt-safe discipline every other save section already applies.
func from_dict(d: Variant) -> void:
	_data = {}
	if not (d is Dictionary):
		return
	for lvl in d:
		var b: Variant = d[lvl]
		if not (b is Dictionary):
			continue
		var live := {}
		var raw_live: Variant = b.get("authored_npcs", {})
		if raw_live is Dictionary:
			for k in raw_live:
				var e: Variant = raw_live[k]
				if not (e is Dictionary):
					continue
				var pos_v: Variant = e.get("pos", Vector3.ZERO)
				var yaw_v: Variant = e.get("yaw", 0.0)
				var hp_v: Variant = e.get("hp", 0.0)
				live[str(k)] = {
					"alive": true,
					"pos": pos_v if pos_v is Vector3 else Vector3.ZERO,
					"yaw": float(yaw_v) if (yaw_v is float or yaw_v is int) else 0.0,
					"hp": float(hp_v) if (hp_v is float or hp_v is int) else 0.0,
				}
		var dead := []
		var raw_dead: Variant = b.get("dead_authored", [])
		if raw_dead is Array:
			for k in raw_dead:
				dead.append(str(k))
		# v2 containers: coerce each entry to { stacks: Array-of-Dictionary, grid: bool(, locked: bool) } — the
		# shapes restore_snapshot_contents consumes. Junk entries/rows drop; a junk locked is OMITTED (absent =
		# "don't touch the lock", never a coerced default that could silently re-lock or unlock a crate). A v1
		# snapshot has no "containers" key at all -> empty, and every apply()/is_empty() path treats that as none.
		var conts := {}
		var raw_conts: Variant = b.get("containers", {})
		if raw_conts is Dictionary:
			for k in raw_conts:
				var e: Variant = raw_conts[k]
				if not (e is Dictionary):
					continue
				var stacks := []
				var raw_stacks: Variant = e.get("stacks", [])
				if raw_stacks is Array:
					for row in raw_stacks:
						if row is Dictionary:
							# duplicated, not aliased, like the fresh-rebuilt npc entries above — _data must never
							# share references with the caller's dict. Per-field junk degrades in restore_serialized_stacks.
							stacks.append((row as Dictionary).duplicate(true))
				var entry := {"stacks": stacks, "grid": bool(e.get("grid", false)) if (e.get("grid") is bool) else false}
				if e.get("locked") is bool:
					entry["locked"] = e.get("locked")
				conts[str(k)] = entry
		_data[str(lvl)] = {"authored_npcs": live, "dead_authored": dead, "containers": conts}
