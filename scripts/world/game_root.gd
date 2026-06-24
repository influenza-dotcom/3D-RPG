@tool
class_name GameRoot
extends Node3D

## The root script for game.tscn — decouples "which level" from a hardcoded Level child so a second level is
## one LevelData assignment (review #4, the level-loading seam). Assign `level` and GameRoot instantiates its
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


func _ready() -> void:
	add_to_group(&"game_root")  # so a LevelDoor / trigger can find us without a hardcoded path
	if Engine.is_editor_hint():
		return  # @tool: never instantiate the level into the scene at EDIT time (it would pollute / could be saved)
	# A loaded game reloads the SAVED level (resolved from GameState) over the exported default, so Continue /
	# quickload / a load-death return you to the level you saved in. On a loaded game the Player restores the SAVED
	# respawn, so we normally DON'T re-place it at the level's default spawn — UNLESS the editor's Play-From-Spawn
	# toolbar requested a specific spawn (a one-shot dev override that must win over the saved respawn).
	var to_load := resolve_boot_level(level, GameState.loaded, GameState.current_level_path)
	if to_load != null:
		var dev_entry := _dev_start_entry()  # consume the one-shot editor Play-From-Spawn request (read + delete) once
		# Defer: add_child() is blocked while THIS node is still in its own _ready ("parent busy setting up
		# children"). Runtime callers (a LevelDoor swap) aren't in _ready, so load_level() stays synchronous there.
		load_level.call_deferred(to_load, dev_entry, should_place_at_spawn(GameState.loaded, dev_entry))


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
## a fresh game, OR when the editor's Play-From-Spawn toolbar requested a spawn (a dev override that must win over a
## loaded autosave's respawn — else "Play From Spawn" silently does nothing whenever a save exists). Pure + static.
static func should_place_at_spawn(loaded: bool, dev_entry: StringName) -> bool:
	return dev_entry != &"" or not loaded


## The LevelData to instantiate at boot: a loaded game's SAVED level (resolved from its resource_path) wins over the
## exported default, so Continue / quickload reload the level you saved in — not the editor's start level. Falls back
## to `exported` when it's not a loaded game, the saved path is blank/unresolvable, OR the saved LevelData has no
## scene (a scene-less level would boot into NOTHING — load_level no-ops on it). Pure + static, unit-testable.
static func resolve_boot_level(exported: LevelData, loaded: bool, saved_path: String) -> LevelData:
	# ResourceLoader.exists guards a saved path whose .tres was since deleted/renamed — load() on a missing path
	# logs a (test-failing) error; this falls back to the export cleanly instead.
	if loaded and saved_path != "" and ResourceLoader.exists(saved_path):
		var saved := load(saved_path) as LevelData
		if saved != null and saved.scene != null:  # a scene-less level would load_level-noop -> fall back to the export
			return saved
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
		existing.free()
	var inst := data.scene.instantiate()
	inst.name = &"Level"
	host.add_child(inst)
	_apply_audio(data)
	# A boot into a LOADED game skips placement: the Player's _ready restores the SAVED respawn, and re-placing it
	# at the level's default spawn here would override that. A fresh game / a runtime door-swap DOES place + re-seed.
	if place_at_spawn:
		_place_player_at_entry.call_deferred(entry_id)  # after the new level's PlayerSpawns have entered the tree


## No-arg load of the ASSIGNED `level` — so a TriggerVolume (action = "load_assigned_level") or a cutscene can
## change level with no argument. Set `level` (a LevelData) and point the trigger at us.
func load_assigned_level() -> void:
	load_level(level)

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
## freed old one. No-op without a Player or a matching spawn (the player keeps its authored transform).
func _place_player_at_entry(entry_id: StringName) -> void:
	var player := _host().get_node_or_null(^"Player") as Node3D
	if player == null:
		return
	var spawn := _find_spawn(entry_id)
	if spawn == null:
		return
	spawn.place(player)
	GameState.set_respawn(spawn.global_position, spawn.global_rotation.y)


## The PlayerSpawn whose entry_id matches (or the first one when `entry_id` is blank). Null if the level has none.
func _find_spawn(entry_id: StringName) -> PlayerSpawn:
	for s in get_tree().get_nodes_in_group(&"player_spawn"):
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
		if m != null:
			m.stream = data.music
			m.play()
	if data.ambience != null:
		var a := host.get_node_or_null(^"Player/Ambience") as AudioStreamPlayer3D
		if a != null:
			a.stream = data.ambience
			a.play()


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
