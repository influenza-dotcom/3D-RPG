@tool
class_name ChunkStreamer
extends Node3D

## @system World Streaming
## @seam ChunkStreamer is the drop-in that turns a level into a streamed WORLDSPACE: it keeps the chunk scenes within load_radius of the player in the tree (threaded loads while walking, synchronous on an arrival) and frees chunks past unload_radius, naming each Chunk_<x>_<z> so every save key inside it is stable.
## @risk The player's own chunk MUST be in the tree before the Player's physics tick (process_physics_priority below + the synchronous centre load): a threaded-only centre drops the player through a floor that hasn't streamed in yet.
## @risk A threaded request that is never collected with load_threaded_get stays in ResourceLoader forever; an unload mid-flight parks the path in _abandoned, which _poll collects — dropping that bookkeeping leaks a whole chunk per border crossing.
## @seam Each chunk root carries WorldSnapshot.SCOPE_META, giving it its OWN world-ledger bucket: the bucket is applied (deferred, queued before add_child — the GameRoot order) when the chunk streams in, captured right before it streams out, and captured for every loaded chunk by each save (GameState.capture_level_state walks Groups.CHUNK_STREAMER.ledger_chunks).
## @risk A chunk whose bucket apply is still queued must not be captured (ledger_chunks and _unload skip it): its nodes still hold the authored seed, and capturing them would overwrite the saved state — a looted crate restocks.
## @test res://tests/test_chunk_streamer.gd
## @test res://tests/test_chunk_grid.gd
##
## THE FALLOUT MODEL, in Godot terms. A worldspace is an ordinary LevelData whose scene is the PERSISTENT layer — the
## WorldEnvironment / sun / day-night sky, the PlayerSpawns and LevelDoors, anything quest-critical that must exist
## wherever the player stands — plus this node. The world's actual ground, buildings, props and NPCs live in CHUNK
## scenes, one per grid cell, in `chunk_folder`, named by `file_pattern` ("chunk_{x}_{z}.tscn" -> chunk_0_0.tscn,
## chunk_-1_0.tscn ...). Only the chunks around the player are in memory; walk and the world streams in ahead of you
## and drops behind you. Missing files are simply gaps (ocean, the map edge) — nothing is requested for them.
##
## SETUP: drop a ChunkStreamer into the worldspace's LevelRoot scene, point `chunk_folder` at the chunk scenes, set
## `chunk_size` to the cell width you authored them at. The streamer's own position is the grid origin. Each chunk
## scene's root should be a `WorldChunk` (scripts/world/world_chunk.gd) so it gets the PS1 warp + the brush z-fight
## pass and a chunk-shaped validator; a plain Node3D root works too, just without those.
##
## AUTHORING SPACE (`offset_chunks_to_grid`): OFF (default) = every chunk scene shares the WORLD origin and holds its
## content at its real world position, so two neighbouring chunks opened side by side (or instanced into one test scene,
## or built from TrenchBroom maps that share a coordinate space) line up exactly. ON = each chunk is authored around its
## own corner — (0,0,0) .. (chunk_size, *, chunk_size) — and the streamer moves it into its cell: reusable tiles.
##
## NAVIGATION: give each chunk its own NavigationRegion3D baked over that chunk's ground. Regions on the same navigation
## map knit together at runtime wherever their border edges line up (within the map's edge_connection_margin), so an
## NPC paths across a seam once both chunks are in. Bake each chunk with the SAME NavigationMesh cell_size / agent
## settings, and extend the floor a hair past the cell edge so neighbouring bakes meet.
##
## ACTORS: an NPC belongs to the chunk it was authored in, and unloads with it. So an actor never vanishes in front of
## you, a chunk is NOT unloaded while any of its NPCs stands within load_radius of the player (a guard who chased you
## two cells over keeps his home chunk alive until he is far away again).
##
## SAVES: nothing here writes a save. A chunk's doors / pickups / destroyed props persist through GameState.world_objects
## exactly like any level's (their keys fold in the level path and the stable Chunk_<x>_<z> node path). Its authored
## NPCs (alive, position, hp, deaths) and containers (exact contents) ride the per-level world ledger in a bucket of
## the chunk's own — captured when it streams out and by every save, handed back when it streams in — so a crate
## looted three cells ago is still empty when you walk back, and a raider you killed stays dead.

## A chunk entered the tree (after its own _ready and the streamer's post-load passes).
signal chunk_loaded(coord: Vector2i, chunk: Node)
## A chunk left the tree and was queued for free.
signal chunk_unloaded(coord: Vector2i)

## Folder holding the chunk scenes.
@export_dir var chunk_folder: String = "":
	set(value):
		chunk_folder = value
		_exists.clear()
		update_configuration_warnings()
## File name of one chunk scene inside `chunk_folder`; {x} and {z} are replaced by the cell coords.
@export var file_pattern: String = "chunk_{x}_{z}.tscn":
	set(value):
		file_pattern = value
		_exists.clear()
		update_configuration_warnings()
## Width of one square cell, in metres (X and Z). Must match what the chunk scenes were authored at.
@export_range(4.0, 4096.0, 1.0, "or_greater", "suffix:m") var chunk_size: float = 64.0
## Rings of chunks kept loaded around the player: 1 = the 3x3 block, 2 = 5x5 (Fallout 3's uGridsToLoad 5).
@export_range(0, 6) var load_radius: int = 1
## Chunks further than this many rings from the player are unloaded. Keep it at least one more than load_radius so
## walking back and forth across a border doesn't load and free the same chunk over and over.
@export_range(0, 8) var unload_radius: int = 2
## See AUTHORING SPACE above. OFF = chunks are authored in world coordinates; ON = the streamer moves each into its cell.
@export var offset_chunks_to_grid: bool = false
## Load chunks on a background thread while walking (instantiation still happens on the main thread, one chunk per
## `max_chunks_per_frame`). Off = every load blocks — simpler to debug, hitches on every border.
@export var threaded_loading: bool = true
## On an ARRIVAL (the first step after the world loads, a door or a teleport landing the player somewhere with nothing
## loaded) load the WHOLE load ring synchronously, hidden behind the arrival's own load hitch, instead of popping the
## neighbours in over the next frames. The chunk under the player always loads synchronously regardless.
@export var sync_load_on_arrival: bool = true
## Most finished background loads to instantiate in one frame. Instantiating a chunk is the part that hitches.
@export_range(1, 16) var max_chunks_per_frame: int = 1
## Optional node the world streams around. Blank = the live human player (GameState.live_player()).
@export var target: NodePath
## Print every load / unload to the Output panel (debug builds only).
@export var verbose: bool = false

## EDITOR ACTION: instance every chunk found in `chunk_folder` under this node so you can see the whole world while
## authoring the persistent layer. The preview nodes have no owner, so they are never saved into the scene. Momentary.
@export var preview_all_chunks: bool = false:
	set(value):
		preview_all_chunks = false
		if value:
			_editor_preview(true)
## EDITOR ACTION: remove the preview chunks again. Momentary.
@export var clear_preview: bool = false:
	set(value):
		clear_preview = false
		if value:
			_editor_preview(false)

const ChunkGrid = preload("res://scripts/world/chunk_grid.gd")
const WorldSnapshot = preload("res://scripts/world/world_snapshot.gd")
## Tick before every other physics node (the Player runs at the default 0), so the chunk under a player who just
## arrived is in the tree before the Player's move_and_slide looks for a floor.
const PHYSICS_PRIORITY := -100
const PREVIEW_META := &"_chunk_preview"

var _live: Dictionary = {}        ## Vector2i -> Node: chunks in the tree
var _pending: Dictionary = {}     ## Vector2i -> String: threaded requests in flight, still wanted
var _abandoned: Dictionary = {}   ## String -> true: requests whose chunk stopped being wanted; collected + dropped
var _exists: Dictionary = {}      ## Vector2i -> bool: ResourceLoader.exists cache (files don't appear at runtime)
var _apply_pending: Dictionary = {}  ## chunk instance id -> true: its ledger bucket apply is queued, so it must not be captured yet
var _center := Vector2i.ZERO
var _has_center := false
var _target_node: Node3D = null
## True when this node entered the tree DURING a physics step: whoever added the world (GameRoot.load_level from a
## door) has a deferred player placement still queued, so the player's position this step is the OLD level's and
## streaming around it would load the wrong chunks. Skip that one step.
var _skip_step := false


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(Groups.CHUNK_STREAMER)
	_skip_step = Engine.is_in_physics_frame()
	_has_center = false  # re-entering (a cached level coming back) is an arrival too


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	process_physics_priority = PHYSICS_PRIORITY


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _skip_step:
		_skip_step = false
		return
	step()


## One streaming step: work out the player's cell, load / unload toward the wanted set, and collect finished
## background loads. Public so a teleport can force it immediately instead of waiting a physics tick.
func step() -> void:
	_poll_abandoned()
	var t := _resolve_target()
	if t == null:
		return
	var c := coord_at(t.global_position)
	var arrival := not _has_center or ChunkGrid.distance(c, _center) > maxi(unload_radius, load_radius)
	_center = c
	_has_center = true
	# Never let the player stand in a cell that isn't there.
	if not _live.has(c) and chunk_exists(c):
		_load_now(c)
	var plan := ChunkGrid.plan(c, _wanted_or_live(), load_radius, unload_radius, chunk_exists)
	for coord in plan.unload:
		if not _pinned(coord, c):
			_unload(coord)
	for coord in plan.load:
		if (arrival and sync_load_on_arrival) or not threaded_loading:
			_load_now(coord)
		else:
			_request(coord)
	_poll_pending()


## The cell containing a world position (the streamer's transform is the grid's origin and orientation).
func coord_at(world_pos: Vector3) -> Vector2i:
	return ChunkGrid.coord_for(global_transform.affine_inverse() * world_pos, chunk_size)


## The cell the player was in on the last step (meaningless before the first step — see has_center()).
func current_coord() -> Vector2i:
	return _center


func has_center() -> bool:
	return _has_center


## Every cell currently in the tree.
func live_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _live:
		out.append(c)
	return out


## The chunk node for `coord`, or null when that cell isn't loaded.
func chunk_at(coord: Vector2i) -> Node:
	var n: Variant = _live.get(coord)
	return n if is_instance_valid(n) else null


## Is there a chunk scene on disk for `coord`? Cached per cell (the chunk set doesn't change at runtime).
func chunk_exists(coord: Vector2i) -> bool:
	if _exists.has(coord):
		return _exists[coord]
	var ok := chunk_folder != "" and ResourceLoader.exists(chunk_path(coord), "PackedScene")
	_exists[coord] = ok
	return ok


func chunk_path(coord: Vector2i) -> String:
	return ChunkGrid.chunk_path(chunk_folder, file_pattern, coord)


## Unload every chunk now (no pins) — for a teardown or a debug "reload the world".
func unload_all() -> void:
	for c in _live.keys():
		_unload(c)
	for c in _pending.keys():
		_abandon(c)
	_has_center = false


# --- loading ------------------------------------------------------------------------------------------------------

func _resolve_target() -> Node3D:
	if is_instance_valid(_target_node) and _target_node.is_inside_tree():
		return _target_node
	_target_node = null
	if not target.is_empty():
		_target_node = get_node_or_null(target) as Node3D
	elif GameState.has_method(&"live_player"):
		_target_node = GameState.live_player() as Node3D
	return _target_node


func _wanted_or_live() -> Dictionary:
	var all := _live.duplicate()
	for c in _pending:
		all[c] = true
	return all


func _request(coord: Vector2i) -> void:
	if _pending.has(coord) or _live.has(coord):
		return
	var path := chunk_path(coord)
	if _abandoned.has(path):
		# A load for this cell is already running from before the player turned back — adopt it instead of queueing a
		# second request (two requests for one path need two gets, and the second would never come).
		_abandoned.erase(path)
		_pending[coord] = path
		return
	var err := ResourceLoader.load_threaded_request(path, "PackedScene")
	if err != OK:
		push_warning("ChunkStreamer: couldn't queue '%s' (error %d) — loading it synchronously" % [path, err])
		_load_now(coord)
		return
	_pending[coord] = path


func _poll_pending() -> void:
	var added := 0
	for coord in _pending.keys():
		if added >= max_chunks_per_frame:
			return
		var path: String = _pending[coord]
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			ResourceLoader.THREAD_LOAD_LOADED:
				_pending.erase(coord)
				_add_chunk(coord, ResourceLoader.load_threaded_get(path) as PackedScene)
				added += 1
			_:
				# FAILED / INVALID_RESOURCE: stop asking for this cell for the rest of the session.
				_pending.erase(coord)
				_exists[coord] = false
				push_warning("ChunkStreamer: background load of '%s' failed — that cell stays empty" % path)


## Collect finished requests nobody wants any more so ResourceLoader drops them.
func _poll_abandoned() -> void:
	for path in _abandoned.keys():
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_abandoned.erase(path)
			ResourceLoader.load_threaded_get(path)  # result discarded; this call is what releases it


func _abandon(coord: Vector2i) -> void:
	var path: String = _pending.get(coord, "")
	_pending.erase(coord)
	if path != "":
		_abandoned[path] = true


## Load `coord` right now, blocking. Adopts an in-flight background request for the same cell (load_threaded_get
## waits for it) rather than loading the file twice.
func _load_now(coord: Vector2i) -> void:
	if _live.has(coord):
		return
	var ps: PackedScene = null
	if _pending.has(coord):
		ps = ResourceLoader.load_threaded_get(_pending[coord]) as PackedScene
		_pending.erase(coord)
	else:
		var path := chunk_path(coord)
		if _abandoned.has(path):
			_abandoned.erase(path)
			ps = ResourceLoader.load_threaded_get(path) as PackedScene
		else:
			ps = ResourceLoader.load(path, "PackedScene") as PackedScene
	_add_chunk(coord, ps)


func _add_chunk(coord: Vector2i, ps: PackedScene) -> void:
	if ps == null:
		_exists[coord] = false
		push_warning("ChunkStreamer: '%s' is not a loadable scene — that cell stays empty" % chunk_path(coord))
		return
	var inst := ps.instantiate()
	if inst == null:
		push_warning("ChunkStreamer: '%s' instantiated null — skipping" % chunk_path(coord))
		return
	inst.name = ChunkGrid.chunk_node_name(coord)
	inst.set_meta(WorldSnapshot.SCOPE_META, String(inst.name))  # its own world-ledger bucket (WorldSnapshot.bucket_for)
	if offset_chunks_to_grid and inst is Node3D:
		(inst as Node3D).position = ChunkGrid.chunk_origin(coord, chunk_size)
	# The chunk's ledger bucket, queued BEFORE add_child for the same reason GameRoot.load_level does it: the deferred
	# apply then runs after every node's _ready but ahead of anything those _ready calls defer (an autosave would
	# otherwise capture the fresh authored seed over the saved state first).
	var key := WorldSnapshot.scoped_key(GameState.current_level_path, String(inst.name))
	if GameState.current_level_path != "" and GameState.world_snapshot.has_level(key):
		_apply_pending[inst.get_instance_id()] = true
		_apply_chunk_state.call_deferred(inst)
	add_child(inst)
	_live[coord] = inst
	_after_chunk_added(inst)
	if verbose and OS.is_debug_build():
		print("ChunkStreamer: + %s (%d live)" % [inst.name, _live.size()])
	chunk_loaded.emit(coord, inst)


## The per-load passes a whole level gets from GameRoot.load_level, scoped to what just streamed in.
func _after_chunk_added(chunk: Node) -> void:
	# The PS1 warp covers LevelRoots; a WorldChunk is one, so it gets its own applier (freed with the chunk).
	var warp := get_node_or_null(^"/root/Ps1Warp")
	if warp != null and warp.has_method(&"cover"):
		warp.cover(chunk)
	# Authored NPCs the player already killed stay dead — even with no bucket yet (killed, then saved-and-loaded before
	# the chunk was ever captured). Deferred like GameRoot's, so every NPC _ready has settled and snapshot_key resolves.
	_suppress_dead.call_deferred(GameState.ledger_bucket_for(chunk))


func _suppress_dead(bucket: String) -> void:
	if is_inside_tree():
		GameState.suppress_dead_authored(get_tree(), bucket)


## Deferred from _add_chunk. Untyped on purpose: a chunk unloaded before this runs arrives freed, and a freed argument
## at a TYPED parameter is rejected at the call boundary.
func _apply_chunk_state(chunk) -> void:
	if not is_instance_valid(chunk):
		return
	_apply_pending.erase(chunk.get_instance_id())
	GameState.apply_chunk_state(chunk)


## The loaded chunks a save may capture right now: every live chunk whose bucket apply isn't still queued.
## GameState.capture_level_state walks this for each streamer in the tree.
func ledger_chunks() -> Array[Node]:
	var out: Array[Node] = []
	for c in _live:
		var n: Variant = _live[c]
		if is_instance_valid(n) and not _apply_pending.has((n as Node).get_instance_id()):
			out.append(n)
	return out


func _unload(coord: Vector2i) -> void:
	if _pending.has(coord):
		_abandon(coord)
	var n: Variant = _live.get(coord)
	_live.erase(coord)
	if not is_instance_valid(n):
		return
	var chunk: Node = n
	# Bank it in the world ledger while it is still in the tree — unless its saved bucket hasn't even been applied yet
	# (it streamed in and straight back out this frame), in which case that bucket is still the truth.
	if not _apply_pending.has(chunk.get_instance_id()):
		GameState.capture_chunk_state(chunk)
	_apply_pending.erase(chunk.get_instance_id())
	# Detach first (the GameRoot swap idiom) so group scans and physics stop seeing it this frame, then free.
	remove_child(chunk)
	chunk.queue_free()
	if verbose and OS.is_debug_build():
		print("ChunkStreamer: - %s (%d live)" % [chunk.name, _live.size()])
	chunk_unloaded.emit(coord)


## A chunk past unload_radius stays loaded while one of its NPCs is within load_radius of the player — an actor that
## followed the player out of its home cell must not blink out beside them.
func _pinned(coord: Vector2i, player_coord: Vector2i) -> bool:
	var chunk := chunk_at(coord)
	if chunk == null:
		return false
	for n in get_tree().get_nodes_in_group(Groups.NPC):
		if n is Node3D and chunk.is_ancestor_of(n) \
				and ChunkGrid.distance(coord_at((n as Node3D).global_position), player_coord) <= load_radius:
			return true
	return false


# --- editor ---------------------------------------------------------------------------------------------------------

func _editor_preview(show: bool) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta(PREVIEW_META):
			c.queue_free()
	if not show:
		return
	var found := editor_list_chunks()
	for coord in found:
		var ps := load(chunk_path(coord)) as PackedScene
		if ps == null:
			continue
		var inst := ps.instantiate()
		inst.name = ChunkGrid.chunk_node_name(coord)
		inst.set_meta(PREVIEW_META, true)
		if offset_chunks_to_grid and inst is Node3D:
			(inst as Node3D).position = ChunkGrid.chunk_origin(coord, chunk_size)
		add_child(inst)  # no owner -> never saved
	print("ChunkStreamer: previewing %d chunk(s) from %s" % [found.size(), chunk_folder])


## Every cell with a chunk scene in `chunk_folder`, read from the directory listing (EDITOR / tools only — an exported
## build remaps scene files, so runtime code asks chunk_exists per cell instead).
func editor_list_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := DirAccess.open(chunk_folder) if chunk_folder != "" else null
	if d == null:
		return out
	var rx := RegEx.create_from_string("^" + _escape(file_pattern).replace("\\{x\\}", "(-?\\d+)").replace("\\{z\\}", "(-?\\d+)") + "$")
	var x_first := file_pattern.find("{x}") <= file_pattern.find("{z}")
	for f in d.get_files():
		var m := rx.search(f)
		if m == null or m.get_group_count() < 2:
			continue
		var a := int(m.get_string(1))
		var b := int(m.get_string(2))
		out.append(Vector2i(a, b) if x_first else Vector2i(b, a))
	return out


static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		if ".^$*+?()[]{}|\\".contains(ch):
			out += "\\"
		out += ch
	return out


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if chunk_folder == "":
		w.append("No `chunk_folder` — point it at the folder holding the chunk scenes (named by `file_pattern`).")
	elif not DirAccess.dir_exists_absolute(chunk_folder):
		w.append("`chunk_folder` '%s' doesn't exist." % chunk_folder)
	elif editor_list_chunks().is_empty():
		w.append("No file in '%s' matches `file_pattern` '%s' — nothing will stream in." % [chunk_folder, file_pattern])
	if not file_pattern.contains("{x}") or not file_pattern.contains("{z}"):
		w.append("`file_pattern` needs both {x} and {z} (e.g. chunk_{x}_{z}.tscn).")
	if unload_radius <= load_radius:
		w.append("`unload_radius` should be at least load_radius + 1, or a chunk on the edge loads and unloads every time you step across the border.")
	return w
