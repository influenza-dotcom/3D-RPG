class_name DebugRoundtrip
extends Node

## The in-game SAVE/LOAD ROUND-TRIP FUZZER behind the console's `roundtrip` (danger) row: capture the live run,
## write a SCRATCH save, hard-reload the scene through the REAL load path, wait for the fresh Player/GameRoot to
## settle, capture again, and print a field-by-field IDENTITY diff plus every push_warning/push_error raised in
## the window. It runs in the game you are standing in, on the level you are standing in — the LIVE re-apply
## contract that only the OFF-TREE disk round trip (tests/test_game_save.gd) covers today, with its known soft-fail
## points that surface only at runtime: an unknown item id skipped, a placement that "no longer fits -> auto-place"
## (silent Tetris drift), "the save's equipped weapon didn't restore — falling back to fists", the held-item fold-back,
## capture()'s zorkmids skip, and the quicksave->quickload NPC-position/container seam.
##
## LIFETIME + PARENTING (the whole trick): the command adds one of these at `get_tree().root` — the
## menu_qa_shots.gd "driver at root" idiom. reload_current_scene() frees the CURRENT SCENE (the console, the level,
## the player, every debug overlay in game.tscn) but never a root child, so this node's coroutine keeps running
## across the reload and can find the FRESH console (Groups.DEBUG_SURFACE, duck-typed `echo`) to print into. It
## queue_free()s itself once the report is out. NEVER parent it inside the level or the console.
##
## FLOW (begin() runs (a)-(c) SYNCHRONOUSLY and returns "" once the reload is in flight; the coroutine
## _await_and_report does (d)-(f)). ⭐reload_current_scene() is NOT a pure end-of-frame request in Godot 4.2+: it
## REMOVES the current scene from the tree right there (root.remove_child + queue_free — the fresh scene is added at
## the next SceneTree flush), so the console that typed the command has ALREADY had its _exit_tree (which runs both
## action modules' release_scene_scoped_state) by the time begin() returns; its Object still exists until the frame
## ends, so the caller's "started" lines land in a detached scrollback (+ the stdout mirror), never on screen — the
## report below recaps everything into the FRESH console for that reason.
##   (a) GameState.capture(player) — FIRST, or save_to_disk writes the stale in-memory mirror (ALL-GOTCHAS) — then
##       flatten_profile() + flatten_world() + flatten_live() into ONE flat { key -> value } Dictionary (capture A).
##   (b) build the EXACT-SNAPSHOT tier exactly like GameState._capture_and_write does (WorldSnapshot.capture of the
##       live level + fold_dead_ledger of the others), assign it to GameState.world_snapshot and save_to_disk(SCRATCH_PATH).
##       Why the snapshot tier and not the lean profile: a profile-only load CLEARS GameState._dead_authored and re-seeds
##       every authored NPC at its .tscn spot with full hp (load_from_disk / GameRoot), which is BY DESIGN for the
##       Continue tier — but it would drown the diff in resurrections and repositionings that are not defects. The
##       manual quick/slot save is the tier whose live re-apply is still "playtest-PENDING", so that is the one fuzzed.
##       SCRATCH_PATH is a NON-CANONICAL user:// path: GameState.resolve_save_path is an exact-path allowlist over the
##       five real files, so it passes through UNCHANGED, sandbox on or off — the real profile is never touched.
##       Unlike quicksave the CHECKPOINT is not moved for good: the respawn triple is banked, pointed at the player's
##       current spot for the save (so the fresh Player lands where you stood — Player._ready restores from it), and
##       restored in (e). If no checkpoint existed before, the spot stays as the new one (blanking it would send the next
##       death to the origin).
##   (c) GameState._load_and_reload(SCRATCH_PATH) — the quickload body (load_from_disk + close_all_modals +
##       time_scale 1.0 + the _reload_pending latch + reload_current_scene). Called through `call` because it is
##       private-by-underscore; `sandbox off` reaches for it the same way (debug_actions_world.gd) — the one place that
##       knows how to swap profiles safely stays the one place.
##   (d) poll per PHYSICS frame (SETTLE_FRAME_CAP): a NEW human Player exists (instance id != the old one) and is
##       is_node_ready(), GameState.reload_pending() is false (set_current_level ran = load_level ran) and the "Level"
##       node exists; then SETTLE_EXTRA_FRAMES more so GameRoot's deferred _apply_world_snapshot /
##       _suppress_dead_authored have run AND their queue_free()s have resolved (a dead NPC is still in the tree —
##       and still is_alive() — for a frame after apply()).
##   (e) restore the banked checkpoint, GameState.capture(fresh) and flatten the same way (capture B).
##   (f) diff_snapshots(A, B, DEFAULT_IGNORE) -> lines, plus the ErrorSink window; echo() into the console AND print().
##
## PURE HALF (unit-tested in tests/test_debug_roundtrip.gd, no tree, no autoload writes): flatten_profile /
## flatten_world / flatten_live / merged_keys / diff_snapshots / values_equal / is_ignored / value_text. Every read
## is DUCK-TYPED (`gs.get(&"field")`, has_method) so a bare `load("res://managers/GameState.gd").new()` drives it and
## an API drift degrades to a missing key, never a crash. Every stored value is a DEEP COPY (_freeze): capture() and
## load_from_disk() clear-and-refill the SAME Dictionaries/Arrays on GameState (stat_values.clear(),
## world_objects.clear() ...), so a snapshot that aliased them would silently turn into capture B.
##
## WARNINGS IN THE WINDOW: this node installs its OWN ErrorSink (error_sink.gd, preloaded by path) for the window
## rather than reading the F3 overlay's — that sink is uninstalled/reinstalled with game.tscn, so its counters reset
## mid-window. QuestTracker.take_load_warnings() is consume-once and ui.gd eats it in _ready, so the sink is the only
## honest record. Paired uninstall in _exit_tree (the engine keeps a raw pointer to a live Logger).
##
## GUARDS: one round trip at a time (a static latch that survives the reload — the node itself does too, but a second
## command mid-flight must be refused before it touches GameState), an in-tree living Player, no quickload in flight,
## an unpaused tree (a dialogue pause would stall the fresh scene forever), a recorded level identity (a blank
## current_level_path could not boot back into this level).
##
## DEV-ONLY: it prints developer copy through print() and the console's echo(); it never paints a Label or toast, so
## it is not a paint site and needs no ScanText.SKIP_FILES entry — keep it that way.

## Preloaded by PATH (no class_name on world_snapshot.gd at all; groups.gd's is old but preloading keeps this file
## free of any global-class-cache dependency, like debug_actions_world.gd does). ErrorSink is loaded LAZILY by path
## in _install_sink for the same reason DebugOverlay preloads it untyped: a stale cache must never take this file down.
const WorldSnapshotScript := preload("res://scripts/world/world_snapshot.gd")
const GroupsScript := preload("res://scripts/world/groups.gd")
const ERROR_SINK_PATH := "res://scripts/components/error_sink.gd"

## The scratch save. user:// only, and deliberately NOT one of the five canonical profile basenames (gamestate /
## quicksave / save_slot_N) so resolve_save_path passes it through unchanged and the Saves dock / recovery ladder /
## sandbox never see it as a profile. Its .tmp/.bak siblings rotate beside it on every run (the atomic-write funnel
## treats every path the same) — they are left in place so a dev can `savediff`/inspect them by hand.
const SCRATCH_PATH := "user://debug_roundtrip.cfg"
## The node name the command mounts under tree.root (its "already running" find keys on it).
const NODE_NAME := &"DebugRoundtrip"
## Physics frames to wait for the fresh scene before giving up with a "never settled" report (~15 s at 60 Hz — a
## level load plus a slow disk is seconds, not minutes). Frame-counted, not a timer, so a hitch cannot fake a settle.
const SETTLE_FRAME_CAP := 900
## Extra physics frames AFTER the settle condition: GameRoot's deferred _apply_world_snapshot / _suppress_dead_authored
## run a flush later than load_level, and their queue_free()s resolve a frame after that.
const SETTLE_EXTRA_FRAMES := 6
## Two Vector3 values closer than this are NOT a diff: an NPC restored to its saved spot re-snaps to the navmesh and
## keeps wandering for the settle frames, and the fresh Player ground-snaps — sub-metre drift is not identity.
const POSITION_TOLERANCE := 1.0
## Diff lines print at most this many characters per value (a container's stacks Array is long, and the console
## scrollback is finite).
const MAX_VALUE_CHARS := 160
## At most this many captured error/warning entries are listed under the diff (the counts are always printed).
const MAX_SINK_LINES := 20

## The free-running fields, ignored by default (each is a PATTERN for is_ignored: exact key, key prefix, or a
## String.match glob — `*` spans `/`):
##   time_of_day           the WorldClock free-runs between the two captures (a settle takes real seconds)
##   status/*/remaining    a status timer ticks down across the window; the effect PATH is still compared
##   respawn               rewritten by design (quick/slot saves move it; this harness banks + restores its own move)
##   world/*/npc/*/yaw     a live NPC turns its head while wandering; heading is not identity (position IS, within
##                         POSITION_TOLERANCE, and hp is exact)
const DEFAULT_IGNORE: PackedStringArray = ["time_of_day", "status/*/remaining", "respawn", "world/*/npc/*/yaw"]

## The one-at-a-time latch. STATIC on purpose: it must survive the reload the harness itself triggers, and it must be
## checkable by a fresh command BEFORE a second node touches GameState. Cleared when the report lands and in _exit_tree
## — but ONLY by the instance that set it (`_owns_latch`): a second harness refused with "already running" and then
## queue_free()d must not drop the running one's latch on its way out.
static var _running: bool = false
var _owns_latch: bool = false

var _old_player_id: int = 0
var _level_path: String = ""
var _snapshot_a: Dictionary = {}
## {has, position, yaw} as they were before begin() pointed the checkpoint at the player (see the FLOW note on (b)).
var _banked_respawn: Dictionary = {}
var _sink = null  ## an ErrorSink while installed (untyped: the class_name is never referenced here)
var _started_msec: int = 0


func _ready() -> void:
	# The fresh scene boots under DialogueManager's pause only if a conversation was up — refused in begin() — but a
	# root-parented harness must never depend on the tree's pause state to finish its coroutine.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Tear down the sink BEFORE this object frees (Logger is engine-referenced), and drop the latch so an externally
## freed harness (a dev deleting the node, the game quitting mid-flight) can never wedge `roundtrip` for the session.
func _exit_tree() -> void:
	_uninstall_sink()
	if _owns_latch:
		_running = false
		_owns_latch = false


# =============================================================================================================
# entry point — the command calls begin() right after add_child at root, then releases its scene-scoped state
# =============================================================================================================

## Steps (a)-(c). Returns "" once the reload is IN FLIGHT (the coroutine has been started and will report), else a
## one-line refusal — and on a refusal NOTHING was reloaded and every GameState field this touched is put back
## (checkpoint, world_snapshot; capture()'s refresh of the in-memory mirror is the same one every autosave does).
## Synchronous up to and including reload_current_scene() — which DETACHES the caller's scene on the spot (see the
## FLOW note): the console's _exit_tree has already run when this returns, its Object survives only to frame end.
func begin(player: Node) -> String:
	if _running:
		return "roundtrip REFUSED — one is already running (its report lands in the console after the reload)"
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return "roundtrip REFUSED — no in-tree player (the capture reads the live one)"
	if _truthy(player.get(&"_dying")):
		return "roundtrip REFUSED — the player is mid-death; capture would read a corpse"
	var body := player as Node3D
	if body == null:
		return "roundtrip REFUSED — the player is not a Node3D (no position to bank the checkpoint from)"
	if GameState.reload_pending():
		return "roundtrip REFUSED — a quickload is in flight (GameState.reload_pending); let the fresh scene boot first"
	if not GameState.has_method(&"_load_and_reload"):
		return "roundtrip REFUSED — GameState has no _load_and_reload(path) (API drift); the real load path could not be driven"
	var tree := get_tree()
	if tree == null:
		return "roundtrip REFUSED — the harness is off-tree (mount it at tree.root before begin())"
	if tree.paused:
		return "roundtrip REFUSED — the tree is paused (a dialogue?); the fresh scene could never settle under it — finish the conversation first"
	_level_path = String(GameState.current_level_path)
	if _level_path == "":
		return "roundtrip REFUSED — GameState.current_level_path is BLANK (a code-built LevelData / no level loaded): the reload could not boot back into THIS level"

	# --- the window opens: our own sink, so the counts cannot be reset by game.tscn's overlay going with the scene
	_install_sink()

	# (a) capture A. capture() FIRST — every field below is the in-memory MIRROR capture refreshes from the live player.
	GameState.capture(player)
	var level := _level_node(tree)
	var snap = _build_world_snapshot(tree)
	_snapshot_a = flatten_profile(GameState, QuestTracker)
	_snapshot_a.merge(flatten_world(snap.to_dict()))
	_snapshot_a.merge(flatten_live(player, level))

	# Bank the checkpoint, then point it at the player's spot so the fresh Player lands where you stood (it restores
	# global_position from GameState.respawn_position when has_respawn and respawn_level_matches).
	_banked_respawn = {
		"has": bool(GameState.has_respawn), "position": GameState.respawn_position, "yaw": float(GameState.respawn_yaw),
	}
	GameState.set_respawn(body.global_position, body.rotation.y)

	# (b) the exact-snapshot tier + the scratch write. world_snapshot is banked too so a refusal leaves it as found.
	var prev_snapshot: Variant = GameState.get(&"world_snapshot")
	GameState.set(&"world_snapshot", snap)
	var err := int(GameState.save_to_disk(SCRATCH_PATH))
	if err != OK:
		GameState.set(&"world_snapshot", prev_snapshot)
		_restore_respawn(true)
		_uninstall_sink()
		return "roundtrip REFUSED — save_to_disk(%s) returned Error %d (%s); nothing was reloaded" % [SCRATCH_PATH, err, error_string(err)]

	# (c) the real load path. Its own existence gate resolves the path exactly as load_from_disk will (identity here).
	_old_player_id = player.get_instance_id()
	var ok := bool(GameState.call(&"_load_and_reload", SCRATCH_PATH))
	if not ok:
		# _load_and_reload returns false only when the existence gate or load_from_disk's ladder refused the file (an
		# off-tree GameState returns TRUE without reloading — the autoload is always in-tree, so that case never lands here).
		GameState.set(&"world_snapshot", prev_snapshot)
		_restore_respawn(true)
		_uninstall_sink()
		return "roundtrip REFUSED — GameState._load_and_reload(%s) returned false (the scratch just written did not read back as a profile); nothing was reloaded" % SCRATCH_PATH

	_running = true
	_owns_latch = true
	_started_msec = Time.get_ticks_msec()
	_await_and_report()  # a coroutine: it suspends on its first await and finishes on its own after the reload
	return ""


# =============================================================================================================
# the coroutine — (d) settle, (e) capture B, (f) report; then self-free
# =============================================================================================================

func _await_and_report() -> void:
	var tree := get_tree()
	var frames := 0
	var settled := false
	while frames < SETTLE_FRAME_CAP:
		await tree.physics_frame
		frames += 1
		if _settled(tree):
			settled = true
			break
	if settled:
		for _i in SETTLE_EXTRA_FRAMES:
			await tree.physics_frame

	var lines := PackedStringArray()
	var fresh: Node = GroupsScript.human_player(tree)
	if not settled or fresh == null or not is_instance_valid(fresh):
		lines.append("roundtrip FAILED — the fresh scene never settled within %d physics frames (reload_pending %s, fresh player %s, level %s)." % [
			SETTLE_FRAME_CAP, str(GameState.reload_pending()), ("yes" if fresh != null else "no"), ("yes" if _level_node(tree) != null else "no")])
		lines.append("capture B was skipped. The scratch save is at %s; the checkpoint %s." % [SCRATCH_PATH, _restore_respawn_text()])
		_restore_respawn()
		lines.append_array(_sink_lines())
		_finish(lines)
		return

	# (e) capture B — the checkpoint goes back FIRST so B carries the restored triple (respawn/* is ignored anyway).
	_restore_respawn()
	GameState.capture(fresh)
	var b := flatten_profile(GameState, QuestTracker)
	b.merge(flatten_world(_build_world_snapshot(tree).to_dict()))
	b.merge(flatten_live(fresh, _level_node(tree)))

	# (f) the report
	var diff := diff_snapshots(_snapshot_a, b, DEFAULT_IGNORE)
	var compared := merged_keys(_snapshot_a, b, DEFAULT_IGNORE).size()
	var elapsed := float(Time.get_ticks_msec() - _started_msec) / 1000.0
	lines.append("roundtrip: capture A -> scratch save -> GameState._load_and_reload -> fresh scene settled after %d (+%d) physics frames, %.1f s -> capture B" % [frames, SETTLE_EXTRA_FRAMES, elapsed])
	if diff.is_empty():
		lines.append("IDENTICAL over %d fields" % compared)
	else:
		lines.append("%d of %d fields DIFFER (key: A -> B):" % [diff.size(), compared])
		for line in diff:
			lines.append("  " + line)
		# The profile never carried HP (a load is a full heal — Dark Souls, by design), so a damaged player ALWAYS
		# shows this line; say so once rather than let it read as a save defect.
		for line in diff:
			if line.begins_with("live/hp:"):
				lines.append("  (live/hp is not a profile field — a load is a full heal by design, not a fidelity defect)")
				break
	lines.append("ignored: %s — positions compared within %.1f m, floats approx, everything else exact" % [", ".join(DEFAULT_IGNORE), POSITION_TOLERANCE])
	# The two-inventories tell (memory: TWO inventories with confusable names): the hub's drawn WeaponData vs the
	# backpack's equipped Item, read off capture B, printed regardless of the diff so a desync is visible even when
	# both sides changed together.
	lines.append("post-reload hands: hub-drawn %s · bag-equipped %s · held %s" % [
		value_text(b.get("live/drawn_weapon", "")), value_text(b.get("live/bag_equipped", "")), value_text(b.get("live/held_item", ""))])
	lines.append_array(_sink_lines())
	lines.append("tier: the EXACT-SNAPSHOT save (profile + [world_snapshot]: authored-NPC alive/pos/hp, cross-level deaths, container contents) — the same product F5/F9 write and read; the checkpoint %s." % _restore_respawn_text())
	lines.append("scratch save left at %s (+ .tmp/.bak siblings from earlier runs) — a non-canonical path, so the sandbox rewrite never touched it and the scratch WRITE never touched the real profile (the fresh scene's own autosaves behave exactly as after F9). GameState.loaded is now true (as after any death reload)." % SCRATCH_PATH)
	_finish(lines)


## Print the lines to stdout AND into the FRESH console (any Groups.DEBUG_SURFACE member with echo() — the console
## re-joins the group in its _ready; DebugMenu has no echo, so at most one surface prints), then self-free. echo()
## appends whether or not the panel is open, so the report waits in the scrollback for the next backtick.
func _finish(lines: PackedStringArray) -> void:
	for line in lines:
		print("[roundtrip] " + line)
	var tree := get_tree()
	if tree != null:
		for surface in tree.get_nodes_in_group(GroupsScript.DEBUG_SURFACE):
			if is_instance_valid(surface) and surface.has_method(&"echo"):
				surface.call(&"echo", lines)
				break
	if _owns_latch:
		_running = false
		_owns_latch = false
	queue_free()


## The settle condition — see FLOW (d). All three must hold in the SAME frame.
func _settled(tree: SceneTree) -> bool:
	if tree == null or GameState.reload_pending():
		return false
	var fresh: Node = GroupsScript.human_player(tree)
	if fresh == null or not is_instance_valid(fresh):
		return false
	if fresh.get_instance_id() == _old_player_id or not fresh.is_node_ready():
		return false
	return _level_node(tree) != null


# =============================================================================================================
# checkpoint bank / sink / world snapshot helpers (instance side)
# =============================================================================================================

## Put the checkpoint back as it was before begin() moved it. After a SUCCESSFUL reload a run that had NO checkpoint
## keeps the roundtrip's spot (set_respawn is the only writer that flips has_respawn, and blanking it would send the
## next death to the origin); on a REFUSAL (`exact`, nothing reloaded) the "no checkpoint" state is put back
## verbatim through GameState.clear() — the forget-the-respawn method — so a refused command leaves no trace.
func _restore_respawn(exact: bool = false) -> void:
	if _banked_respawn.is_empty():
		return
	if not bool(_banked_respawn.get("has", false)):
		if exact and GameState.has_method(&"clear"):
			GameState.call(&"clear")
		return
	var pos: Variant = _banked_respawn.get("position", Vector3.ZERO)
	GameState.set_respawn(pos if pos is Vector3 else Vector3.ZERO, float(_banked_respawn.get("yaw", 0.0)))


func _restore_respawn_text() -> String:
	if _banked_respawn.is_empty():
		return "was never touched"
	if bool(_banked_respawn.get("has", false)):
		return "was banked and restored in memory (the fresh Player was placed where you stood, your old checkpoint stands; the next autosave persists it — an autosave that fired DURING the reload wrote the roundtrip spot)"
	return "did not exist before, so the spot you stood on is now the checkpoint"


## The exact-snapshot capture GameState._capture_and_write performs, minus its set_respawn: the live level's NPCs +
## containers, then every OTHER level's dead keys folded in. `_dead_authored` is read through get(): it is private
## with no public getter (the console's `resurrect` reaches for it the same way).
func _build_world_snapshot(tree: SceneTree):
	var snap = WorldSnapshotScript.new()
	var dead_v: Variant = GameState.get(&"_dead_authored")
	var dead: Dictionary = dead_v if dead_v is Dictionary else {}
	snap.capture(tree, _level_path, dead.get(_level_path, {}))
	snap.fold_dead_ledger(dead, _level_path)
	return snap


func _install_sink() -> void:
	if _sink != null or not ResourceLoader.exists(ERROR_SINK_PATH):
		return
	var script := load(ERROR_SINK_PATH) as GDScript
	if script == null:
		return
	_sink = script.new()
	if _sink != null and _sink.has_method(&"install"):
		_sink.install()


## Deregister BEFORE the object frees (the engine holds a raw pointer to a live Logger). Logger is RefCounted, so
## dropping the reference frees it; a bare-Object build is freed by hand — the DebugOverlay handles both the same way.
func _uninstall_sink() -> void:
	if _sink == null:
		return
	if _sink.has_method(&"uninstall"):
		_sink.uninstall()
	if not (_sink is RefCounted) and is_instance_valid(_sink):
		_sink.free()
	_sink = null


## "errors N warnings M in the window" plus up to MAX_SINK_LINES entries, formatted like the console's `errors` row.
func _sink_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if _sink == null:
		out.append("error sink: not installed (%s missing) — push_warnings in the window were not counted" % ERROR_SINK_PATH)
		return out
	var errors := _int_of(_sink.get(&"error_count"))
	var warnings := _int_of(_sink.get(&"warning_count"))
	out.append("in the window (capture A -> capture B): %d error(s), %d warning(s)" % [errors, warnings])
	if not _sink.has_method(&"recent"):
		return out
	var raw: Variant = _sink.call(&"recent")
	if not (raw is Array):
		return out
	var recent: Array = raw
	var n := mini(MAX_SINK_LINES, recent.size())
	for i in range(recent.size() - n, recent.size()):
		var e: Variant = recent[i]
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var tag := "W" if String(d.get("type", "")) == "WARN" else "E"
		var code := String(d.get("code", ""))
		var rationale := String(d.get("rationale", ""))
		var msg := rationale if rationale != "" else code
		if rationale != "" and code != "":
			msg += " (%s)" % code
		out.append("  [%s] %s:%d %s — %s" % [tag, String(d.get("file", "")), _int_of(d.get("line")), String(d.get("function", "")), msg])
	if recent.size() > n:
		out.append("  (%d earlier entries not shown)" % (recent.size() - n))
	return out


## The live level subtree ("Level"): GameRoot works in TWO layouts — script on the scene root, or a drop-in child
## with Player/Level as SIBLINGS (scenes/game.tscn — the level lands at Game/Level, NOT GameRoot/Level). Same walk as
## debug_actions_world.gd's, kept local so this harness has no dependency on the action module that mounts it.
static func _level_node(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var gr := tree.get_first_node_in_group(GroupsScript.GAME_ROOT)
	if gr != null and is_instance_valid(gr):
		var own := gr.get_node_or_null(^"Level")
		if own != null:
			return own
		var parent := gr.get_parent()
		if parent != null:
			var sibling := parent.get_node_or_null(^"Level")
			if sibling != null:
				return sibling
	if tree.current_scene != null:
		return tree.current_scene.get_node_or_null(^"Level")
	return null


# =============================================================================================================
# PURE HALF — flatten + diff (unit-tested; no tree, no writes)
# =============================================================================================================

## The profile fields of `gs` (a GameState — the autoload or a bare instance) plus the quest sections `qt` writes,
## as ONE flat { String key -> value } Dictionary. Duck-typed reads throughout; a missing member is simply a missing
## key. Keys (stable — the diff prints them verbatim):
##   money, account, payment_method, credit_standing, player_name, xp, level, current_level_path, time_of_day,
##   respawn/has, respawn/position, respawn/yaw,
##   unlocks, disabled_unlocks, known_names, discovered_corpses, perks/paths      (SORTED String arrays — order is not identity)
##   stat/<name>, reputation/<faction>, flag/<name>, perks/grant/<perk>, appearance/<k> (shirt -> its byte count),
##   world_objects/<level>/<key>                                                    (the state Dictionary, by value)
##   inventory/has, inventory/count, inventory/<id>#<ordinal>                       (the serialized stack entry {id,count,x,y,w,h,weapon_delta}
##                                                                                   keyed by item id + occurrence, so a reorder of DISTINCT
##                                                                                   ids is not a diff and a placement change is ONE line)
##   inventory/equipped                                                             (equipped_index RESOLVED to the item id, "" for fists)
##   perks/skill_points, perks/points_earned, status/<i>/path, status/<i>/remaining,
##   quests/active/<id> ({path, progress}), quests/completed/<id> (path), quests/failed/<id> (path)   (via qt.save_into(cfg))
##   quests/active_count, quests/completed_count, quests/failed_count                  (off the LIVE journal — see below)
static func flatten_profile(gs: Object, qt: Object) -> Dictionary:
	var out := {}
	if gs == null or not is_instance_valid(gs):
		return out
	for f: StringName in [&"money", &"account", &"payment_method", &"credit_standing", &"player_name", &"xp", &"level",
			&"current_level_path", &"time_of_day"]:
		out[String(f)] = _freeze(gs.get(f))
	out["respawn/has"] = _freeze(gs.get(&"has_respawn"))
	out["respawn/position"] = _freeze(gs.get(&"respawn_position"))
	out["respawn/yaw"] = _freeze(gs.get(&"respawn_yaw"))
	out["unlocks"] = _sorted_strings(gs.get(&"unlocks"))
	out["disabled_unlocks"] = _sorted_strings(gs.get(&"disabled_unlocks"))
	out["known_names"] = _sorted_strings(_keys_of(gs.get(&"known_names")))
	out["discovered_corpses"] = _sorted_strings(_keys_of(gs.get(&"discovered_corpses")))
	out["perks/paths"] = _sorted_strings(gs.get(&"perk_paths"))
	out["perks/skill_points"] = _freeze(gs.get(&"skill_points"))
	out["perks/points_earned"] = _freeze(gs.get(&"points_earned"))
	_flatten_dict(out, "stat", gs.get(&"stat_values"))
	_flatten_dict(out, "reputation", gs.get(&"reputation"))
	_flatten_dict(out, "flag", gs.get(&"flags"))
	_flatten_dict(out, "perks/grant", gs.get(&"perk_grants"))
	# Appearance: the drawn shirt is PNG BYTES — its length is identity enough for a diff line, and a 3 KB blob is not.
	var app: Variant = gs.get(&"appearance")
	if app is Dictionary:
		for k in (app as Dictionary):
			var v: Variant = (app as Dictionary)[k]
			out["appearance/%s" % str(k)] = (v as PackedByteArray).size() if v is PackedByteArray else _freeze(v)
	# world_objects: level -> key -> state
	var wo: Variant = gs.get(&"world_objects")
	if wo is Dictionary:
		for lvl in (wo as Dictionary):
			var per: Variant = (wo as Dictionary)[lvl]
			if per is Dictionary:
				for key in (per as Dictionary):
					out["world_objects/%s/%s" % [str(lvl), str(key)]] = _freeze((per as Dictionary)[key])
	# inventory: the serialized stacks capture() wrote, plus the equipped index resolved to an id.
	out["inventory/has"] = _freeze(gs.get(&"has_inventory"))
	var stacks_v: Variant = gs.get(&"inventory_stacks")
	var stacks: Array = stacks_v if stacks_v is Array else []
	var eq_index := _int_of(gs.get(&"equipped_index"), -1)
	var equipped := ""
	var seen := {}
	out["inventory/count"] = stacks.size()
	for i in stacks.size():
		var entry: Variant = stacks[i]
		var id := str((entry as Dictionary).get("id", "?")) if entry is Dictionary else "?"
		var ordinal := int(seen.get(id, 0))
		seen[id] = ordinal + 1
		out["inventory/%s#%d" % [id, ordinal]] = _freeze(entry)
		if i == eq_index:
			equipped = id
	out["inventory/equipped"] = equipped
	# status effects: [{path, remaining}] — split so the PATH stays compared while `remaining` is ignorable.
	var fx_v: Variant = gs.get(&"status_effects")
	if fx_v is Array:
		var fx: Array = fx_v
		for i in fx.size():
			var e: Variant = fx[i]
			if e is Dictionary:
				out["status/%d/path" % i] = str((e as Dictionary).get("path", ""))
				out["status/%d/remaining" % i] = _freeze((e as Dictionary).get("remaining", 0.0))
			else:
				out["status/%d/path" % i] = str(e)
	# quests: exactly what the save writes ([quests_active] {path, progress} / [quests_completed] path / [quests_failed] path).
	if qt != null and is_instance_valid(qt) and qt.has_method(&"save_into"):
		var cfg := ConfigFile.new()
		qt.call(&"save_into", cfg)
		# Typed loop variable on purpose: an Array literal iterates as Variant, and a `:=` off a Variant call does not
		# compile ("cannot infer the type") — the project's no-inference-off-Variant rule.
		for section: String in ["quests_active", "quests_completed", "quests_failed"]:
			if not cfg.has_section(section):
				continue
			var short := section.trim_prefix("quests_")
			for k in cfg.get_section_keys(section):
				out["quests/%s/%s" % [short, k]] = _freeze(cfg.get_value(section, k))
	# Counts off the LIVE journal, not the cfg: a code-built quest with no resource_path is SKIPPED by save_into (a
	# push_warning, by design), so it is absent from BOTH captures' quests/<bucket>/<id> keys above and the diff could
	# never show that the round trip dropped it — a count can (1 -> 0), and the sink lines carry the matching warning.
	if qt != null and is_instance_valid(qt):
		if qt.has_method(&"active_quest_ids"):
			out["quests/active_count"] = _count_of(qt.call(&"active_quest_ids"))
		if qt.has_method(&"completed_quests"):
			out["quests/completed_count"] = _count_of(qt.call(&"completed_quests"))
		if qt.has_method(&"failed_quests"):
			out["quests/failed_count"] = _count_of(qt.call(&"failed_quests"))
	return out


## A WorldSnapshot.to_dict() ({ level -> {authored_npcs, dead_authored, containers} }) flattened to
##   world/<level>/npc/<key>/hp | pos | yaw,  world/<level>/dead (SORTED keys),  world/<level>/container/<key> (the entry)
static func flatten_world(snapshot: Dictionary) -> Dictionary:
	var out := {}
	for lvl in snapshot:
		var bucket: Variant = snapshot[lvl]
		if not (bucket is Dictionary):
			continue
		var b: Dictionary = bucket
		var live: Variant = b.get("authored_npcs", {})
		if live is Dictionary:
			for key in (live as Dictionary):
				var e: Variant = (live as Dictionary)[key]
				if not (e is Dictionary):
					continue
				var d: Dictionary = e
				out["world/%s/npc/%s/hp" % [str(lvl), str(key)]] = _freeze(d.get("hp", 0.0))
				out["world/%s/npc/%s/pos" % [str(lvl), str(key)]] = _freeze(d.get("pos", Vector3.ZERO))
				out["world/%s/npc/%s/yaw" % [str(lvl), str(key)]] = _freeze(d.get("yaw", 0.0))
		out["world/%s/dead" % str(lvl)] = _sorted_strings(b.get("dead_authored", []))
		var conts: Variant = b.get("containers", {})
		if conts is Dictionary:
			for key in (conts as Dictionary):
				out["world/%s/container/%s" % [str(lvl), str(key)]] = _freeze((conts as Dictionary)[key])
	return out


## The LIVE-only facts the profile does not carry, read off the player node duck-typed and null-safe per hop:
##   live/hp, live/max_hp, live/pos (Vector3 -> tolerance), live/drawn_weapon (the hub's WeaponData path — the
##   weapon system's own Inventory), live/bag_equipped (the backpack's equipped Item id — the OTHER inventory),
##   live/held_item (an in-hand prop's item id), live/unlocks (sorted), live/level_scene, live/level_name.
## The drawn-vs-bag pair is the two-inventories desync tell (a hub equip leaves CharacterInventory.equipped_item stale).
static func flatten_live(player: Object, level: Object) -> Dictionary:
	var out := {}
	if player != null and is_instance_valid(player):
		out["live/hp"] = _freeze(player.get(&"hp"))
		out["live/max_hp"] = _freeze(player.get(&"max_hp"))
		var body := player as Node3D
		if body != null and body.is_inside_tree():
			out["live/pos"] = body.global_position
		var ws: Variant = player.get(&"weapon_system")
		if ws != null and is_instance_valid(ws):
			var hub: Variant = ws.get(&"inventory")
			if hub != null and is_instance_valid(hub):
				out["live/drawn_weapon"] = _resource_id(hub.get(&"equipped_weapon"))
		var bag: Variant = player.get(&"inventory")
		if bag != null and is_instance_valid(bag):
			var eq: Variant = bag.get(&"equipped_item")
			out["live/bag_equipped"] = str(eq.get(&"id")) if eq != null and is_instance_valid(eq) else ""
		if player.has_method(&"held_inventory_item"):
			var held: Variant = player.call(&"held_inventory_item")
			out["live/held_item"] = str(held.get(&"id")) if held != null and is_instance_valid(held) else ""
		if player.has_method(&"unlocked_list"):
			out["live/unlocks"] = _sorted_strings(player.call(&"unlocked_list"))
	if level != null and is_instance_valid(level):
		out["live/level_scene"] = str(level.get(&"scene_file_path"))
		out["live/level_name"] = str(level.get(&"name"))
	return out


## The SORTED union of both key sets minus the ignored ones — the fields a diff actually compares (its count is
## the "IDENTICAL over N fields" N).
static func merged_keys(a: Dictionary, b: Dictionary, ignore: PackedStringArray) -> PackedStringArray:
	var seen := {}
	for k in a:
		seen[str(k)] = true
	for k in b:
		seen[str(k)] = true
	var out := PackedStringArray()
	for k in seen:
		var key := str(k)
		if not is_ignored(key, ignore):
			out.append(key)
	out.sort()
	return out


## One line per changed key: "key: A -> B" (a key present on one side only reads "(missing)" on the other), sorted by
## key. `ignore` patterns are dropped first (see is_ignored); Vector3 values closer than `pos_tolerance` are equal
## (values_equal). Empty = identical over merged_keys().
static func diff_snapshots(a: Dictionary, b: Dictionary, ignore: PackedStringArray, pos_tolerance: float = POSITION_TOLERANCE) -> PackedStringArray:
	var out := PackedStringArray()
	for key in merged_keys(a, b, ignore):
		var in_a := a.has(key)
		var in_b := b.has(key)
		if in_a and in_b:
			if values_equal(a[key], b[key], pos_tolerance):
				continue
			out.append("%s: %s -> %s" % [key, value_text(a[key]), value_text(b[key])])
		elif in_a:
			out.append("%s: %s -> (missing)" % [key, value_text(a[key])])
		else:
			out.append("%s: (missing) -> %s" % [key, value_text(b[key])])
	return out


## Does `key` match any ignore pattern? Three spellings, so the list stays readable: the exact key ("time_of_day"),
## a PREFIX that owns a whole subtree ("respawn" covers respawn/has, respawn/position, respawn/yaw), or a
## String.match glob ("status/*/remaining" — `*` spans `/`, so "world/*/npc/*/yaw" reaches through a res:// level path).
static func is_ignored(key: String, ignore: PackedStringArray) -> bool:
	for p in ignore:
		if p == "":
			continue
		if key == p or key.begins_with(p + "/") or key.match(p):
			return true
	return false


## Structural equality with the two tolerances a round trip needs: Vector3 within `pos_tolerance` (positions
## re-snap), floats approx (a ConfigFile round trip is text), Dictionaries/Arrays recursively (a container's stacks
## carry weapon_delta floats). Anything else: same type AND ==. A bool is never a number here (`true is int` is false).
static func values_equal(a: Variant, b: Variant, pos_tolerance: float) -> bool:
	if a is Vector3 and b is Vector3:
		return (a as Vector3).distance_to(b as Vector3) <= pos_tolerance
	if _is_number(a) and _is_number(b):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k in da:
			if not db.has(k) or not values_equal(da[k], db[k], pos_tolerance):
				return false
		return true
	if a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in aa.size():
			if not values_equal(aa[i], ab[i], pos_tolerance):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


## One value for a diff line: Strings quoted, Vector3 to 2 decimals, floats trimmed, everything else str(); capped at
## MAX_VALUE_CHARS with an ellipsis (a stacks Array can be hundreds of characters).
static func value_text(v: Variant) -> String:
	var s := ""
	if v is String or v is StringName:
		s = "\"%s\"" % str(v)
	elif v is Vector3:
		var p: Vector3 = v
		s = "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]
	elif v is float:
		s = String.num(v, 4)
	else:
		s = str(v)
	if s.length() > MAX_VALUE_CHARS:
		s = s.left(MAX_VALUE_CHARS - 1) + "…"
	return s


# --- pure helpers ---------------------------------------------------------------------------------------------

## Deep copy for the snapshot: GameState clears and refills the SAME Dictionaries/Arrays on every capture()/load, so an
## aliased value in capture A would silently become capture B. Scalars, Strings and Vector3 are value types already.
static func _freeze(v: Variant) -> Variant:
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	if v is Array:
		return (v as Array).duplicate(true)
	return v


static func _flatten_dict(out: Dictionary, prefix: String, d: Variant) -> void:
	if not (d is Dictionary):
		return
	for k in (d as Dictionary):
		out["%s/%s" % [prefix, str(k)]] = _freeze((d as Dictionary)[k])


## Any Array / packed array of names -> a SORTED Array of String (order is not identity for a set of ids).
static func _sorted_strings(v: Variant) -> Array:
	var out: Array = []
	if v is Array or v is PackedStringArray:
		for e in v:
			out.append(str(e))
	out.sort()
	return out


static func _keys_of(v: Variant) -> Array:
	return (v as Dictionary).keys() if v is Dictionary else []


## A Resource's identity for a diff line: its res:// path, else its resource_name, else a marker (a looted weapon is
## a duplicated WeaponData with a blank path); null -> "".
static func _resource_id(res: Variant) -> String:
	if res == null or not is_instance_valid(res):
		return ""
	var path := str(res.get(&"resource_path"))
	if path != "":
		return path
	var rname := str(res.get(&"resource_name"))
	return rname if rname != "" else "(unpathed resource)"


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


## size() of an Array / Dictionary / packed array held in a Variant; 0 for anything else (a duck-typed call that
## answered null).
static func _count_of(v: Variant) -> int:
	if v is Array or v is Dictionary or v is PackedStringArray:
		return v.size()
	return 0


static func _int_of(v: Variant, fallback: int = 0) -> int:
	if v is int or v is float or v is bool:
		return int(v)
	return fallback


## `player.get(&"_dying")` answers null for a stand-in without the field; only a real `true` counts.
static func _truthy(v: Variant) -> bool:
	return v is bool and bool(v)
