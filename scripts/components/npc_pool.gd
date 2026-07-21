@tool
class_name NpcPool
extends Node

## Drop this under a level and point one or more EncounterSpawners at it (their `pool` NodePath) to POOL their NPCs:
## a fixed fleet is built + fully _ready()'d ONCE at boot (paying the expensive weapon.tscn instance + mesh swap +
## ~20 component build up front, hidden), then handed out on spawn and RESET (not rebuilt) instead of instantiated,
## and PARKED (not freed) on death. This eliminates the per-spawn instantiation hitch and keeps memory flat across a
## repeating encounter — at the cost of a careful per-life reset (NPC.reset_for_reuse + each component's own
## reset_for_reuse). OPT-IN and homogeneous: instances are bucketed by LOADOUT signature (scene + profile + faction +
## weapon), so a reused body already carries the right archetype/appearance and reset never re-stamps a profile or
## re-swaps a mesh. Nothing changes for a spawner that leaves its `pool` unset — it keeps the classic instantiate /
## queue_free path.
##
## LIFECYCLE / CONTRACT (see docs/AUTHORING_GUIDE "NPC pooling" + the reset-surface map):
## - warm(def, n): instance n bodies of def's loadout, run their _ready under this pool, then remove them from the
##   tree (truly idle — no processing) and bank them in def's bucket. Each is bound to this pool via set_pool(self),
##   so its die() returns it here instead of freeing.
## - acquire(def, parent, pos): pop a banked body (or null when the bucket is drained), re-parent it under `parent`,
##   place it at `pos`, and NPC.reset_for_reuse() it to a pristine post-_ready state. The caller (spawner) then
##   re-aggros + re-tracks it exactly like a fresh spawn.
## - reclaim(npc): park a just-died body back into its bucket (removed from the tree), ready for the next acquire.
## - adopt(npc, def): register a body the SPAWNER instanced on a bucket-miss so it, too, returns here on death (the
##   pool grows under load rather than ever failing a spawn).
##
## LIMITATIONS (documented, not bugs): a pooled NPC skips the "freeze-then-explode" death beat (the freeze disables
## processing irreversibly). Per-life state carried by an `attach_scenes` component or a RandomInventory / RandomCoat
## roll is NOT reset across lives — pool only homogeneous loadouts without those. Corpses/gibs from each death are
## separate world nodes and clean themselves up as normal.

## OPTIONAL boot-time prewarm for standalone use (a pool not driven by a spawner's warm()). Each entry warms `count`
## bodies of its loadout. Spawners that reference this pool warm their OWN definitions automatically, so leaving this
## empty is the common case.
@export var prewarm: Array[SpawnDefinition] = []

## loadout signature -> Array of parked (out-of-tree) NPCs ready to hand out.
var _free: Dictionary = {}
## Every NPC this pool owns (parked OR in-use), so it can free the parked ones when the pool (level) is torn down.
var _all: Array[Node] = []
var _warmed_config: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only _get_configuration_warnings runs in the editor; never build NPCs there
	# Defer the config prewarm one frame so the whole level (navmesh, geometry) is in the tree before we run NPC._ready.
	if not prewarm.is_empty():
		call_deferred(&"_warm_config")


func _warm_config() -> void:
	if _warmed_config:
		return
	_warmed_config = true
	for def in prewarm:
		if def != null and def.npc_scene != null:
			warm(def, def.count)


## Build `count` bodies of `def`'s loadout, fully _ready() them (the expensive part, paid now), then park them
## out-of-tree in def's bucket. `attach_scenes` (the spawner's per-spawn components — GuardDuty / patrol / …) are
## instanced under each body ONCE here, at warm time, and KEPT across reuse (acquire never re-attaches, so they never
## stack). Idempotent-additive: call again (a second spawner sharing this pool) to add more. Safe once the pool is in
## the tree; a fresh instance whose PackedScene reimport yields null is skipped.
func warm(def: SpawnDefinition, count: int, attach_scenes: Array = []) -> void:
	if def == null or def.npc_scene == null or not is_inside_tree():
		return
	var sig := def.loadout_signature()
	for i in maxi(0, count):
		var npc := _build_warm_instance(def, attach_scenes)
		if npc != null:
			_park(npc, sig)


## Instance one body, stamp def's overrides BEFORE add_child (so _ready reads them), run its _ready by adding it
## under this pool, attach the per-spawn components, capture its authored money baseline, bind it to the pool, then
## return it (still in-tree — the caller parks it). Mirrors EncounterSpawner._spawn_one's fresh-instance path.
func _build_warm_instance(def: SpawnDefinition, attach_scenes: Array) -> Node:
	var npc: Node = def.npc_scene.instantiate()
	if npc == null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
		return null
	def.apply_overrides(npc)
	add_child(npc)  # runs NPC._ready synchronously here — the expensive build we're paying up front
	_attach(npc, attach_scenes)  # GuardDuty / patrol / etc. — in-tree so their _ready resolves the world (once, kept across reuse)
	npc.set(&"_pool", self)  # bind so die() returns it to us (set directly; set_pool() also fine, this avoids a call)
	npc.set_meta(&"pool_money", npc.get(&"money"))  # authored wallet baseline, restored on every acquire
	npc.set_meta(&"pool_sig", def.loadout_signature())
	_all.append(npc)
	return npc


## Instance each attach scene under `npc`. Mirrors EncounterSpawner._attach_components; used by warming so a pooled
## body carries its GuardDuty / PatrolBehavior / CutsceneActor from birth. Kept across reuse (acquire never
## re-attaches), so a designer must NOT share ONE pool across spawners with DIFFERENT attach_scenes for the same
## loadout — a recycled body would carry the first spawner's components into the second (see AUTHORING_GUIDE).
func _attach(npc: Node, attach_scenes: Array) -> void:
	for scene in attach_scenes:
		if scene != null:
			var c: Node = scene.instantiate()
			if c != null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip
				npc.add_child(c)


## Register a body the SPAWNER instanced (on a bucket-miss) so it returns to THIS pool on death — the pool then
## grows to meet demand instead of ever failing a spawn. The spawner has already stamped + added + placed it.
func adopt(npc: Node, def: SpawnDefinition) -> void:
	if npc == null or _all.has(npc):
		return
	npc.set(&"_pool", self)
	npc.set_meta(&"pool_money", npc.get(&"money"))
	npc.set_meta(&"pool_sig", def.loadout_signature())
	_all.append(npc)


## Hand out a reset, re-parented, placed body of `def`'s loadout, or null when the bucket is drained (the caller
## then instances a fresh one and adopt()s it). The body is added under `parent`, faced forward at `pos`, its wallet
## restored to the authored baseline, and reset to a pristine post-_ready state. The spawner re-aggros + re-tracks it.
func acquire(def: SpawnDefinition, parent: Node, pos: Vector3) -> Node:
	if parent == null:
		return null
	var sig := def.loadout_signature()
	var bucket: Array = _free.get(sig, [])
	var npc: Node = null
	while npc == null and not bucket.is_empty():
		var cand: Node = bucket.pop_back()
		if is_instance_valid(cand):
			npc = cand  # skip any that were freed out from under us (defensive)
	if npc == null:
		return null
	parent.add_child(npc)
	if npc is Node3D:
		(npc as Node3D).rotation = Vector3.ZERO  # identity yaw like a fresh scene instance; reset re-anchors _spawn_yaw
		(npc as Node3D).global_position = pos
	npc.set(&"money", npc.get_meta(&"pool_money", 0.0))  # authored wallet baseline (kill bounties / looting are per-life)
	npc.reset_for_reuse()
	return npc


## Park a just-died body back into its bucket: remove it from the tree (truly idle) and bank it for the next acquire.
## Called from NPC.die() when the NPC is pooled. Guards against a body whose bucket signature is somehow missing.
func reclaim(npc: Node) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	var parent := npc.get_parent()
	if parent != null:
		parent.remove_child(npc)  # park OUT of the tree: no processing, and _ready won't re-run on the next add_child
	var sig := String(npc.get_meta(&"pool_sig", ""))
	if not _free.has(sig):
		_free[sig] = []
	(_free[sig] as Array).append(npc)


func _park(npc: Node, sig: String) -> void:
	if npc.get_parent() != null:
		npc.get_parent().remove_child(npc)
	if not _free.has(sig):
		_free[sig] = []
	(_free[sig] as Array).append(npc)


## The pool is being destroyed (level unload): free the PARKED bodies it still owns out-of-tree. In-use bodies are
## children of the level and are freed with it — freeing them here too would double-free, so only the parented-less
## (parked) ones are freed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for npc in _all:
			if is_instance_valid(npc) and npc.get_parent() == null:
				npc.free()


func _get_configuration_warnings() -> PackedStringArray:
	for def in prewarm:
		if def != null and def.npc_scene == null:
			return PackedStringArray(["NpcPool prewarm has a SpawnDefinition with no npc_scene — it will warm nothing."])
	return PackedStringArray()
