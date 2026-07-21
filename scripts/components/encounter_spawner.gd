@tool
class_name EncounterSpawner
extends Node3D

## Drop into a level to spawn enemies on cue — wire a TriggerVolume (action = "trigger_spawn", target = this) or
## call trigger_spawn() from anything. Each SpawnDefinition instances `count` NPCs scattered within its
## spawn_radius of this node, stamping the archetype / faction / weapon overrides and (optionally) aggroing them
## onto the player. The foundation of authored encounters — no more hand-placing every enemy alive from frame 1.

signal spawned(npc: Node)
## Every NPC this spawner produced is now dead or despawned — wire an exit Door's unlock to it for a
## "clear the room to proceed" gate. Only fires after at least one spawn existed (never on an empty spawner).
signal cleared
## The live-spawn count changed (after each spawn and each death) — drive a "3 enemies left" HUD counter.
signal alive_count_changed(count: int)

@export var spawn_definitions: Array[SpawnDefinition] = []
## OPTIONAL exact spawn markers (Marker3D NodePaths): spawns are placed at these points IN ORDER, cycling,
## instead of the random scatter. Empty = scatter within each definition's spawn_radius (the default).
@export var spawn_points: Array[NodePath] = []
## OPTIONAL components instanced under EVERY spawned NPC — e.g. a GuardDuty (bodyguard a VIP), a PatrolBehavior,
## a CutsceneActor. So a whole wave arrives pre-configured with behaviour, no per-NPC editing.
@export var attach_scenes: Array[PackedScene] = []
## OPTIONAL NpcPool NodePath: when set, this spawner's NPCs are POOLED — a fixed fleet is warmed at boot and REUSED
## across spawns (no per-spawn instantiation hitch, flat memory) instead of instantiated fresh + freed on death.
## Empty (the default) = the classic instantiate / queue_free path, completely unchanged. See NpcPool. NOTE: pooled
## reuse does NOT reset an `attach_scenes` component's per-life state (they're added once, on the first life), so a
## stateful attach component + pooling is flagged as a configuration warning.
@export var pool: NodePath

var _pool: NpcPool = null       ## resolved from `pool` in _ready when set — the fleet this spawner draws from
var _alive: Array[Node] = []  ## spawns still alive — each leaves on its died OR tree_exited (whichever first)
var _spawn_index: int = 0     ## cycles through spawn_points when markers drive placement
## Waves currently mid-stagger (spawn_delay > 0). `cleared` is SUPPRESSED while > 0 so killing an early spawn
## before its reinforcements arrive can't fire the "room cleared" gate prematurely. A counter, not a bool, because
## trigger_spawn() launches every definition's wave concurrently (no await between them).
var _spawning: int = 0
var _ever_spawned: bool = false  ## has a tracked spawn ever existed? — `cleared` never fires on an empty spawner

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only _get_configuration_warnings runs in the editor
	if pool.is_empty():
		return
	_pool = get_node_or_null(pool) as NpcPool
	if _pool == null:
		push_warning("EncounterSpawner: `pool` is set but doesn't resolve to an NpcPool — falling back to un-pooled spawning.")
		return
	# Warm the pool with THIS spawner's loadouts (deferred so the whole level is in the tree first). Each definition
	# gets `count` bodies pre-built; difficulty scaling that pushes a wave above `count` at runtime is covered by the
	# acquire-miss path (a fresh instance is instanced + adopt()ed, growing the pool rather than failing a spawn).
	call_deferred(&"_warm_pool")

## Pre-build the pooled fleet for every definition (deferred from _ready).
func _warm_pool() -> void:
	if _pool == null:
		return
	for def in spawn_definitions:
		if def != null and def.npc_scene != null:
			_pool.warm(def, def.count, attach_scenes)  # warmed bodies get the attach components ONCE, kept across reuse

## Spawn EVERY definition (the common case — one trigger fires this once).
func trigger_spawn() -> void:
	for i in spawn_definitions.size():
		trigger_spawn_wave(i)

## Spawn just one definition by index (a WaveManager steps these one at a time).
func trigger_spawn_wave(index: int) -> void:
	if index < 0 or index >= spawn_definitions.size():
		return
	var def := spawn_definitions[index]
	if def == null or def.npc_scene == null or get_parent() == null:
		return
	_spawning += 1  # suppress `cleared` until this whole wave finishes spawning (a death mid-stagger can't fire it early)
	var count := _scaled_count(def.count)  # ML-4: difficulty scales wave density (1.0 at Normal)
	for i in count:
		_spawn_one(def)
		if def.spawn_delay > 0.0 and i < count - 1 and is_inside_tree():
			await get_tree().create_timer(def.spawn_delay).timeout
			# Bail if the spawner / level unloaded during the stagger — else get_parent().add_child on a freed node.
			if not is_inside_tree():
				_spawning -= 1
				return
	_spawning -= 1
	# A spawn may have DIED during the stagger while `cleared` was suppressed — resolve the gate now the wave is done
	# (covers the last spawn dying synchronously / during the final non-awaited step).
	if _spawning == 0 and _ever_spawned and _alive.is_empty():
		cleared.emit()

## Instance one NPC from `def`, apply its overrides (BEFORE add_child so the NPC's _ready stamps them), place it
## within the scatter radius, and — when auto_aggro is set — aggro it onto the player REP-NEUTRALLY (an authored
## ambush costs the player no faction reputation; see _aggro_spawn).
func _spawn_one(def: SpawnDefinition) -> void:
	var pos := _spawn_position(def)
	var npc: Node = null
	if _pool != null:
		npc = _pool.acquire(def, get_parent(), pos)  # a reset, placed reuse — or null when the bucket is drained
	if npc == null:
		# Fresh instance: the classic path, and the pool's miss/overflow fallback. Stamp overrides BEFORE add_child
		# so NPC._ready reads them; place; add the per-spawn attach components (fresh bodies only — a reused body
		# already carries them from its first life, and re-adding would STACK duplicate GuardDuty/patrol components).
		npc = def.npc_scene.instantiate()
		if npc == null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
			return
		def.apply_overrides(npc)  # shared with NpcPool warming so fresh + pooled bodies stamp identically
		get_parent().add_child(npc)  # into the level, as a sibling of the spawner
		if npc is Node3D:
			(npc as Node3D).global_position = pos
		_attach_components(npc)  # GuardDuty / patrol / etc. — added in-tree so their _ready resolves the world
		if _pool != null:
			_pool.adopt(npc, def)  # a bucket-miss instance joins the pool so it, too, returns on death (pool grows under load)
	if def.auto_aggro:
		_aggro_spawn(npc, _player())
	spawned.emit(npc)
	_track_spawn(npc)

## Make a spawned member hostile onto the player WITHOUT dropping faction reputation. Static + duck-typed +
## injectable so a test can drive it with a stub (mirrors AlarmPanel.aggro_faction_members). apply_rep=false is
## load-bearing: provoke()'s default drops the whole faction's rep once per member, so an N-member auto_aggro wave
## would multiply the faction-rep hit by the squad size (the GA-3 multiplication provoke()'s own docstring guards
## against). An authored ambush should cost the player NO rep — the tripping event (e.g. an AlarmPanel) owns any
## one-time faction-rep hit, applied exactly once. Kills still apply kill_penalty later via the death path.
static func _aggro_spawn(npc: Node, player: Node) -> void:
	if npc != null and npc.has_method(&"provoke"):
		npc.provoke(player, false)

## Track a freshly-spawned NPC for the cleared / alive_count_changed signals: it leaves _alive the moment it
## dies OR is freed (whichever fires first), so an encounter still counts as cleared if a body is despawned
## rather than killed. Split out so a test can drive it with a stub node (no real NPC _ready).
func _track_spawn(npc: Node) -> void:
	if npc == null or _alive.has(npc):
		return
	_alive.append(npc)
	_ever_spawned = true
	# Idempotent connects: a POOLED body is REUSED, not freed, so its prior-life died/tree_exited connections to us
	# survive into this life — re-connecting the same bound Callable would push an "already connected" error. The
	# guard is harmless for the classic free-on-death path (a fresh node has no prior connection). `died` stays the
	# reliable de-track (die() emits it before the body is parked); tree_exited only covers a non-death despawn.
	var gone := _on_spawn_gone.bind(npc)
	if npc.has_signal(&"died") and not npc.died.is_connected(gone):
		npc.died.connect(gone)
	if not npc.tree_exited.is_connected(gone):
		npc.tree_exited.connect(gone)
	alive_count_changed.emit(_alive.size())

## A tracked spawn died or left the tree — drop it once (died + tree_exited can both fire for the same NPC)
## and announce the new count; when the last one goes, the encounter is cleared.
func _on_spawn_gone(npc: Node) -> void:
	if not _alive.has(npc):
		return
	_alive.erase(npc)
	alive_count_changed.emit(_alive.size())
	if _alive.is_empty() and _spawning == 0:  # don't fire mid-stagger — wait until the wave has finished spawning
		cleared.emit()

## How many tracked spawns are still alive (0 once the encounter is cleared).
func alive_count() -> int:
	return _alive.size()

## ML-4: a spawn count scaled by the difficulty enemy_count_mult (1.0 at Normal = unchanged). An authored
## wave of >= 1 still spawns at least 1 — Easy thins waves, it never empties an encounter the designer placed.
func _scaled_count(base: int) -> int:
	if base <= 0:
		return 0
	return maxi(1, roundi(float(base) * GameSettings.difficulty.enemy_count_mult))

## Where to place the next spawn: the next spawn_points marker (cycling) if any are set, else a random scatter
## within def.spawn_radius (the default). Increments the cycle only when markers actually drive placement.
func _spawn_position(def: SpawnDefinition) -> Vector3:
	if spawn_points.is_empty():
		return global_position + _random_offset(def.spawn_radius)
	var mp := get_node_or_null(spawn_points[_spawn_index % spawn_points.size()]) as Node3D
	_spawn_index += 1
	return mp.global_position if mp != null else global_position + _random_offset(def.spawn_radius)

## Instance each attach_scenes component under `npc` so the spawn arrives pre-configured (GuardDuty, patrol, …).
func _attach_components(npc: Node) -> void:
	for scene in attach_scenes:
		if scene != null:
			var c := scene.instantiate()
			if c != null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
				npc.add_child(c)

## A random horizontal offset within `radius` (uniform over the disc) to scatter the spawns. Pure.
func _random_offset(radius: float) -> Vector3:
	var ang := randf() * TAU
	var dist := sqrt(randf()) * maxf(0.0, radius)
	return Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)

func _player() -> Node:
	return get_tree().get_first_node_in_group(Groups.PLAYER) if is_inside_tree() else null

func _get_configuration_warnings() -> PackedStringArray:
	if spawn_definitions.is_empty():
		return PackedStringArray(["EncounterSpawner has no spawn_definitions — it will spawn nothing."])
	if not pool.is_empty() and not attach_scenes.is_empty():
		return PackedStringArray(["EncounterSpawner uses a `pool` AND `attach_scenes`: a pooled body keeps its attach components across lives, and their per-life state is NOT reset on reuse. Only pool spawners whose attach components are stateless (or drop attach_scenes)."])
	return PackedStringArray()
