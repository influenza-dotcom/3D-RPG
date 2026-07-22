@tool
## @system Run And Level Flow
## @seam GameRoot is game.tscn's level-load seam: resolve_boot_level picks the boot level (saved-by-path beats export); load_level swaps the single "Level" child and seeds PlayerSpawn + respawn.
## @risk resolve_boot_level diverging from the line-38 respawn_level_matches gate boots the WRONG level yet keeps the saved respawn — silent, no crash (game_root.gd:38, :93-96).
## @risk A should_place_at_spawn regression either clobbers a loaded game's restored respawn with the export spawn, or strands the player at stale wrong-level coords (game_root.gd:44, :157-172).
## @risk If the load_level detach-rename-queue_free swap regresses, two "Level" children stack or refs to the freed level dangle mid-frame — silent stale geometry (game_root.gd:108-120).
## @test res://tests/test_level_flow.gd
## @test res://tests/test_level_boot_lifecycle.gd
## @test res://tests/test_level_data.gd
class_name GameRoot
extends Node3D

## The root script for game.tscn — decouples "which level" from a hardcoded Level child so a second level is
## one LevelData assignment. Assign `level` and GameRoot instantiates its
## scene as the "Level" child at _ready; load_level() swaps it at runtime while the Player (and its Music /
## Ambience nodes) live on.
##
## SAFE TO ADOPT INCREMENTALLY: with no `level` assigned it's a NO-OP, so you can attach it to game.tscn's
## root before migrating the hardcoded Level child — nothing changes until a LevelData is set. And RESPAWN is
## preserved: death still calls reload_current_scene(), which reloads game.tscn and re-runs this _ready, so the
## level re-instantiates from `level` exactly as the hardcoded child used to re-instantiate on a reload.

## The level to load on start: GameRoot instantiates its scene as the "Level" child (and applies its music /
## ambience). Leave unset for a no-op so the existing hardcoded Level child is used unchanged.
@export var level: LevelData = null

## DEV ONLY: the editor's play-from-spawn toolbar writes a PlayerSpawn entry_id here; _ready consumes it ONCE so the
## first level loads with the player placed at that spawn instead of the default first one. Absent in normal play.
const DEV_START_FILE := "user://_dev_start_entry.txt"
## Exact-snapshot serializer applied after a manual quickload (preloaded, NOT class_name — matches the codebase's
## helper-script idiom so there's no global-class-cache dependency to miss). See _apply_world_snapshot.
const WorldSnapshot = preload("res://scripts/world/world_snapshot.gd")


func _ready() -> void:
	add_to_group(Groups.GAME_ROOT)  # so a LevelDoor / trigger can find us without a hardcoded path
	if Engine.is_editor_hint():
		return  # @tool: never instantiate the level into the scene at EDIT time (it would pollute / could be saved)
	# A loaded game reloads the SAVED level (resolved from GameState) over the exported default, so Continue /
	# quickload / a load-death return you to the level you saved in. On a loaded game the Player restores the SAVED
	# respawn, so we normally DON'T re-place it at the level's default spawn — UNLESS the editor's Play-From-Spawn
	# toolbar requested a specific spawn (a one-shot dev override that must win over the saved respawn).
	# M3 respawn-level gate: decide (SYNCHRONOUSLY — before the deferred load_level overwrites current_level_path, and
	# before Player._ready reads it; GameRoot is the earlier sibling in game.tscn) whether the saved respawn's level was
	# honored. A blank saved path (legacy / pre-[level] save) is NOT a mismatch — we don't second-guess a save with no
	# recorded level identity. A recorded-but-unbootable path IS a mismatch -> the Player skips the stale respawn and
	# should_place_at_spawn flips true so we place at the export's spawn + re-seed a valid respawn instead.
	var saved_path := GameState.current_level_path
	GameState.respawn_level_matches = saved_path == "" or saved_level_is_bootable(GameState.loaded, saved_path)
	var to_load := resolve_boot_level(level, GameState.loaded, saved_path)
	if to_load != null:
		var dev_entry := _dev_start_entry()  # consume the one-shot editor Play-From-Spawn request (read + delete) once
		# Defer: add_child() is blocked while THIS node is still in its own _ready ("parent busy setting up
		# children"). Runtime callers (a LevelDoor swap) aren't in _ready, so load_level() stays synchronous there.
		load_level.call_deferred(to_load, dev_entry, should_place_at_spawn(GameState.loaded, dev_entry, GameState.respawn_level_matches))
	else:
		# No LevelData assigned and no bootable saved level (the adopt-incrementally no-op): the hand-placed "Level"
		# child, if any, is used as-is. load_level never runs, so cover THAT child with the PS1 warp here — the way
		# the old tree-wide node_added listener used to catch it. Deferred to run after this _ready returns (we're
		# still mid the parent's child-setup); the child is already fully in the tree, and the applier walks it on
		# its own first _process frame regardless.
		_cover_existing_level_with_ps1.call_deferred()


## Consume a one-shot dev-start entry_id (written by the editor play-from-spawn toolbar): read it, DELETE the file
## so it only applies to this launch, and return it. Blank when there's no file -> the normal first-spawn start.
func _dev_start_entry() -> StringName:
	if not FileAccess.file_exists(DEV_START_FILE):
		return &""
	var f := FileAccess.open(DEV_START_FILE, FileAccess.READ)
	var id := f.get_as_text().strip_edges() if f != null else ""
	f = null
	var d := DirAccess.open("user://")
	if d != null:
		d.remove(DEV_START_FILE.get_file())
	return StringName(id)


## Whether the boot should PLACE the player at a level spawn (vs leave the Player's restored saved respawn): yes for
## a fresh game, when the editor's Play-From-Spawn toolbar requested a spawn (a dev override that must win over a
## loaded autosave's respawn — else "Play From Spawn" silently does nothing whenever a save exists), OR when the saved
## respawn's level could NOT be honored (M3: respawn_level_matches false — a mismatched boot must place the player in
## the EXPORT level it actually loaded + re-seed a valid respawn, else the stale respawn strands them / teleports the
## first death into the wrong level). Pure + static.
static func should_place_at_spawn(loaded: bool, dev_entry: StringName, respawn_level_matches: bool = true) -> bool:
	return dev_entry != &"" or not loaded or not respawn_level_matches


## Whether a LOADED game's SAVED level (current_level_path) is boot-viable — resolvable AND scene-bearing, so
## resolve_boot_level will actually RETURN it instead of falling back to the export. The single source of truth behind
## both resolve_boot_level and the M3 respawn-level-match gate (a false here on a NON-blank path means the saved
## respawn belongs to a level we could NOT load). Pure + static, unit-testable.
static func saved_level_is_bootable(loaded: bool, saved_path: String) -> bool:
	# ResourceLoader.exists guards a saved path whose .tres was since deleted/renamed — load() on a missing path
	# logs a (test-failing) error.
	if not loaded or saved_path == "" or not ResourceLoader.exists(saved_path):
		return false
	var saved := load(saved_path) as LevelData
	return saved != null and saved.scene != null  # a scene-less level would load_level-noop -> not bootable


## The LevelData to instantiate at boot: a loaded game's SAVED level (resolved from its resource_path) wins over the
## exported default, so Continue / quickload reload the level you saved in — not the editor's start level. Falls back
## to `exported` when it's not a loaded game, the saved path is blank/unresolvable, OR the saved LevelData has no
## scene (a scene-less level would boot into NOTHING — load_level no-ops on it). Pure + static, unit-testable.
static func resolve_boot_level(exported: LevelData, loaded: bool, saved_path: String) -> LevelData:
	if saved_level_is_bootable(loaded, saved_path):  # single source of truth (shared with the M3 respawn-level gate)
		return load(saved_path) as LevelData  # ResourceLoader-cached — saved_level_is_bootable just load()ed it
	return exported


## Swap to `data`'s level scene: free any current "Level" child, instantiate the new one as "Level", and apply
## its optional music / ambience overrides to the Player's audio nodes. The Player itself is untouched, so a
## runtime swap (vs a full reload-current-scene respawn) keeps the player alive. No-op without a packed scene.
func load_level(data: LevelData, entry_id: StringName = &"", place_at_spawn: bool = true) -> void:
	if data == null or data.scene == null:
		return
	level = data
	GameState.set_current_level(data.resource_path)  # record the active level so a save reloads THIS one, not the export
	var host := _host()
	var existing := host.get_node_or_null(^"Level")
	if existing != null:
		# B-F62: defer the old level's free (queue_free, not a synchronous free) so anything still referencing it THIS
		# frame isn't invalidated mid-swap. Detach + rename FIRST so the queued node can't collide the new "Level" name.
		existing.name = &"_LevelFreeing"
		host.remove_child(existing)
		existing.queue_free()
	var inst := data.scene.instantiate()
	if inst == null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
		push_warning("GameRoot.load_level: scene of '%s' instantiated null (editor reimport transient?) — skipping load" % data.resource_path)
		return
	inst.name = &"Level"
	host.add_child(inst)
	_apply_audio(data)
	# GameRoot owns the level-load seam (boot, a LevelDoor swap, and a death reload_current_scene all reach here), so
	# it drives the global PS1 warp directly instead of Ps1Warp watching the tree-wide node_added signal — one fewer
	# global listener (see ps1_warp.gd + tests/test_global_node_added_listeners.gd).
	_apply_ps1_warp(inst)
	# Exact-snapshot tier (WorldSnapshot): after the level subtree is in the tree, a MANUAL quickload applies its
	# snapshot as a central push — dead authored NPCs are freed, live ones repositioned (dynamic spawns land in later
	# phases). Gated ONE-SHOT via consume_world_snapshot() so Continue / a death-respawn reload / a runtime door swap
	# never applies one. Deferred so every NPC's _ready has settled (hp = max_hp, spawn anchor, target acquire) before
	# we overwrite it. Consumed synchronously here (a latch) so a later load_level can't double-apply.
	if GameState.consume_world_snapshot():
		_apply_world_snapshot.call_deferred()
	# In-session persistence (Phase 2): on EVERY level load (boot, a LevelDoor swap, a death/quickload reload), suppress
	# authored NPCs the player has already KILLED — driven by the live GameState death ledger, INDEPENDENT of any one-shot
	# [world_snapshot]. So a door A->B->A return finds a cleared level still cleared (in-session), and a quickload restores
	# cross-level kills (dead_map reloaded the full ledger). Deferred so NPC _ready has settled + snapshot_key resolves.
	_suppress_dead_authored.call_deferred()
	# A boot into a LOADED game skips placement: the Player's _ready restores the SAVED respawn, and re-placing it
	# at the level's default spawn here would override that. A fresh game / a runtime door-swap DOES place + re-seed.
	if place_at_spawn:
		_place_player_at_entry.call_deferred(entry_id)  # after the new level's PlayerSpawns have entered the tree


## No-arg load of the ASSIGNED `level` — so a TriggerVolume (action = "load_assigned_level") or a cutscene can
## change level with no argument. Set `level` (a LevelData) and point the trigger at us.
func load_assigned_level() -> void:
	load_level(level)

## Exact-snapshot tier: apply the loaded WorldSnapshot to the just-reloaded level (deferred from load_level after a
## manual quickload consumed the pending flag). No-op if there's no snapshot in memory or we're off-tree. The
## snapshot itself frees dead authored NPCs + repositions live ones (WorldSnapshot.apply). Runtime-only.
func _apply_world_snapshot() -> void:
	var snap: WorldSnapshot = GameState.world_snapshot
	if snap == null or not is_inside_tree() or get_tree() == null:
		return
	snap.apply(get_tree(), GameState.current_level_path)

## In-session + cross-level death persistence: free authored NPCs the player has already killed for the level just loaded
## (deferred from load_level, EVERY load). Driven by GameState's live death ledger — no [world_snapshot] required, so it
## also covers a plain LevelDoor door-swap with no save involved. No-op off-tree / with an empty ledger (a fresh game).
func _suppress_dead_authored() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	GameState.suppress_dead_authored(get_tree(), GameState.current_level_path)

## The node that OWNS the Player + Level children. Normally that's this GameRoot itself (the script on
## game.tscn's root). But it also works as a DROP-IN: add a GameRoot node as a CHILD of the real root, with
## Player / Level as its SIBLINGS, and the self-lookup finds no Player so we fall back to the parent. So the
## same script works whether it sits ON the root or beside the Player.
func _host() -> Node:
	# Use the PARENT as host only when we're a drop-in CHILD node with Player/Level as our SIBLINGS -- detected
	# by the parent having a "Player" child while we don't. Otherwise we ARE the host (script on the root, or a
	# standalone GameRoot), so Level is added as our own child (matching the tests + the documented design).
	if get_node_or_null(^"Player") == null:
		var p := get_parent()
		if p != null and p.get_node_or_null(^"Player") != null:
			return p
	return self


## Teleport the Player (the "Player" child) to the PlayerSpawn matching `entry_id` (or the first, if blank) in the
## freshly-loaded level, and RE-SEED the respawn point there so a later death returns to the new level, not the
## freed old one. No Player -> no-op. No matching spawn -> the player keeps its transform; but on an M3 MISMATCH boot
## (respawn_level_matches false) the respawn is still re-seeded at the player's spot so the stale wrong-level respawn
## can't survive (a spawn-less export would otherwise leave the first death teleporting into the missing level).
func _place_player_at_entry(entry_id: StringName) -> void:
	var player := _host().get_node_or_null(^"Player") as Node3D
	if player == null:
		return
	var spawn := _find_spawn(entry_id)
	if spawn == null:
		# No PlayerSpawn in this level (e.g. an export used only as an M3 fallback — the shipping trenchboom export has
		# none). On a MISMATCH boot the loaded respawn is for the level we could NOT load, and Player._ready skipped
		# restoring it — but nothing has cleared the stale wrong-level coords, so re-seed at the player's current spot
		# here or the FIRST DEATH would teleport there (the very bug M3 fixes). A matched / fresh boot with no spawn
		# keeps its existing respawn untouched.
		if not GameState.respawn_level_matches:
			GameState.set_respawn(player.global_position, player.rotation.y)
		return
	spawn.place(player)
	GameState.set_respawn(spawn.global_position, spawn.global_rotation.y)


## The PlayerSpawn whose entry_id matches (or the first one when `entry_id` is blank). Null if the level has none.
func _find_spawn(entry_id: StringName) -> PlayerSpawn:
	for s in get_tree().get_nodes_in_group(Groups.PLAYER_SPAWN):
		var ps := s as PlayerSpawn
		if ps != null and (entry_id == &"" or ps.entry_id == entry_id):
			return ps
	return null


## Apply a level's optional music / ambience to the Player's AudioStreamPlayer3D children, when present + set.
## Left as null on the LevelData -> the scene's own autoplay streams are kept.
func _apply_audio(data: LevelData) -> void:
	var host := _host()
	if data.music != null:
		var m := host.get_node_or_null(^"Player/Music") as AudioStreamPlayer3D
		if m != null and m.stream != data.music:  # don't hard-restart an already-playing identical track on a same-music reload
			m.stream = data.music
			m.play()
	if data.ambience != null:
		var a := host.get_node_or_null(^"Player/Ambience") as AudioStreamPlayer3D
		if a != null and a.stream != data.ambience:
			a.stream = data.ambience
			a.play()


## Hand a freshly-loaded (or hand-placed) level to the global PS1 warp (the Ps1Warp autoload). GameRoot owns the
## level-load seam, so it drives the warp directly rather than having Ps1Warp watch the tree-wide node_added signal —
## one fewer global listener (see ps1_warp.gd + tests/test_global_node_added_listeners.gd). Duck-typed + null- and
## tree-guarded so a scene / test without the Ps1Warp autoload (or an off-tree GameRoot) simply skips it; Ps1Warp
## itself no-ops on anything that isn't a LevelRoot.
func _apply_ps1_warp(level_root: Node) -> void:
	if level_root == null or not is_inside_tree():
		return
	var warp := get_node_or_null(^"/root/Ps1Warp")
	if warp != null and warp.has_method(&"cover"):
		warp.cover(level_root)


## No-op adoption path (no `level` assigned): cover the hand-placed "Level" child, if one exists, with the PS1 warp
## the same way load_level covers a loaded level. Called deferred from _ready (after it returns); the hand-placed
## child is already in the tree, and the applier walks it on its own first _process frame.
func _cover_existing_level_with_ps1() -> void:
	_apply_ps1_warp(_host().get_node_or_null(^"Level"))


## EDITOR: warn when a `level` LevelData AND a hand-placed "Level" child both exist — at startup load_level
## FREES that child and replaces it with the LevelData's scene (only a child named exactly "Level" is replaced;
## other hardcoded world geometry would load on top). Surfaces the silent replace where the designer edits.
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if level != null:
		for h in [self, get_parent()]:
			if h != null and h.get_node_or_null(^"Level") != null:
				w.append("A `level` LevelData is assigned AND a child named 'Level' exists — at startup that child is FREED and replaced by the LevelData's scene. Remove one. (Any OTHER hardcoded world geometry under the root will also load on top of the loaded level.)")
				break
	return w
