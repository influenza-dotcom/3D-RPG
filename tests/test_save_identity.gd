extends GutTest

## THE ONE IDENTITY SCHEME (workstream 4). Every persistable component — Door, ItemContainer, Corpse, CanPickUp,
## MoneyPickUp, UpgradePickup, CanDestroy, NPC — is keyed by its authored `save_id` ("id:<x>"). The old keys (the
## world_objects level|path|position fallback, the snapshot level|node_path fallback) stay ONLY as a legacy read path:
## a node that has a save_id, reading a save written before it had one, finds its state under the old key once and
## moves it to the id key in memory, so the next save writes the id key alone. A node with a blank save_id still keys
## by the fallback (nothing else identifies it), and the editor warns about it (a config warning, the Audit tab, and
## validate_all.gd). The Place tab / Palette / Item placer stamp a unique save_id so a designer never types one.
##
## This file pins that contract: the WorldSaveId helpers, the legacy adoption for each store (world_objects, corpse
## discovery, the per-level world ledger, the live death ledger), the blank/duplicate findings, and PlaceOps stamping.

const WorldSaveId := preload("res://scripts/world/world_save_id.gd")
const WorldSnapshotScript := preload("res://scripts/world/world_snapshot.gd")
const ScanScene := preload("res://addons/cybersunday_tools/panel_audit/scan_scene.gd")
const PlaceOps := preload("res://addons/cybersunday_tools/dock_place/place_ops.gd")

const LEVEL := "res://__test_identity_level.tres"


## Duck-typed authored NPC for the snapshot / death-ledger walks: the two key methods are all they read.
class IdNpcStub extends Node3D:
	var key: String = ""
	var legacy: String = ""
	var restored_hp: float = -1.0
	func snapshot_key() -> String:
		return key
	func snapshot_legacy_key() -> String:
		return legacy
	func is_alive() -> bool:
		return true
	func restore_snapshot_state(_pos: Vector3, _yaw: float, hp: float) -> void:
		restored_hp = hp


class IdContainerStub extends Node:
	var key: String = ""
	var legacy: String = ""
	var restored_with: Variant = null
	func snapshot_key() -> String:
		return key
	func snapshot_legacy_key() -> String:
		return legacy
	func snapshot_contents() -> Dictionary:
		return {"stacks": [], "grid": false}
	func restore_snapshot_contents(d: Dictionary) -> void:
		restored_with = d


var _s_level := ""
var _s_objects: Dictionary = {}
var _s_corpses: Dictionary = {}
var _s_dead: Dictionary = {}
var _s_queued := false


func before_each() -> void:
	_s_level = GameState.current_level_path
	_s_objects = GameState.world_objects
	_s_corpses = GameState.discovered_corpses
	_s_dead = GameState._dead_authored
	_s_queued = GameState._world_save_queued
	GameState.current_level_path = LEVEL
	GameState.world_objects = {}
	GameState.discovered_corpses = {}
	GameState._dead_authored = {}


func after_each() -> void:
	GameState.current_level_path = _s_level
	GameState.world_objects = _s_objects
	GameState.discovered_corpses = _s_corpses
	GameState._dead_authored = _s_dead
	GameState._world_save_queued = _s_queued


# --- WorldSaveId: the keys ----------------------------------------------------------------------------------------

func test_the_legacy_key_is_exactly_the_old_blank_id_fallback() -> void:
	var n := Node3D.new()
	n.name = "Crate"
	add_child_autofree(n)
	n.global_position = Vector3(1.234, 0.0, -5.0)
	assert_eq(WorldSaveId.legacy_key_for(n), WorldSaveId.key_for(n, &""),
		"legacy_key_for is the level|path|position key every save before save_id-primary wrote")
	assert_eq(WorldSaveId.key_for(n, &"crate_7"), "id:crate_7", "an authored save_id is still the whole key")


func test_snapshot_keys_are_the_id_else_the_level_and_node_path() -> void:
	var n := Node.new()
	n.name = "Guard"  # off-tree: the node path degrades to the name, the shape NPC.snapshot_key always used
	assert_eq(WorldSaveId.snapshot_key_for(n, &"guard_1"), "id:guard_1", "a save_id is the whole snapshot key")
	assert_eq(WorldSaveId.snapshot_key_for(n, &""), "%s|Guard" % LEVEL, "blank -> level|node_path")
	assert_eq(WorldSaveId.snapshot_legacy_key_for(n, &"guard_1"), "%s|Guard" % LEVEL,
		"with a save_id, the legacy snapshot key is the path key an older save used")
	assert_eq(WorldSaveId.snapshot_legacy_key_for(n, &""), "", "without one there is nothing to adopt")
	n.free()


func test_the_real_container_exposes_both_snapshot_keys() -> void:
	var c := ItemContainer.new()
	c.name = "Crate"
	c.save_id = &"crate_7"
	assert_eq(c.snapshot_key(), "id:crate_7", "ItemContainer keys by its save_id")
	assert_eq(c.snapshot_legacy_key(), "%s|Crate" % LEVEL, "and offers the old path key for a legacy read")
	c.save_id = &""
	assert_eq(c.snapshot_legacy_key(), "", "a blank id has no legacy key")
	c.free()
	var npc_methods: Array = (load("res://scripts/npc/npc.gd") as GDScript).get_script_method_list().map(func(m): return m["name"])
	assert_true(npc_methods.has("snapshot_legacy_key"), "NPC offers the same legacy key the ledger walks duck-type on")


func test_wants_save_id_is_every_persistable_except_the_opted_out() -> void:
	var plain := Node3D.new()
	var prop := CanDestroy.new()
	var loot_drop := CanPickUp.new()
	loot_drop.build_model_from_item = true
	var bag_child := MoneyPickUp.new()
	bag_child.persist_collected = false
	var coin := MoneyPickUp.new()
	var body := Corpse.new()
	assert_false(WorldSaveId.wants_save_id(plain), "a node without a save_id export is not persistable")
	assert_true(WorldSaveId.wants_save_id(prop), "a CanDestroy is")
	assert_true(WorldSaveId.wants_save_id(coin), "a hand-placed MoneyPickUp is")
	assert_true(WorldSaveId.wants_save_id(body), "a Corpse marker is")
	assert_false(WorldSaveId.wants_save_id(loot_drop), "a loot-dropped CanPickUp never persists, so it needs no id")
	assert_false(WorldSaveId.wants_save_id(bag_child), "a code-spawned money pickup opted out of persistence")
	for n in [plain, prop, loot_drop, bag_child, coin, body]:
		n.free()


func test_the_blank_id_warning_fires_only_for_a_persistable_authored_in_a_level() -> void:
	var level := LevelRoot.new()
	var prop := CanDestroy.new()
	level.add_child(prop)
	prop.owner = level
	assert_ne(WorldSaveId.blank_id_warning_in(prop, level), "", "a blank save_id on a prop in a level warns")
	prop.save_id = &"crate_7"
	assert_eq(WorldSaveId.blank_id_warning_in(prop, level), "", "an authored id is quiet")
	prop.save_id = &""
	assert_eq(WorldSaveId.blank_id_warning_in(level, level), "", "the edited scene's own root never warns")
	var prefab := Node3D.new()  # not a LevelRoot, no level path: editing a PREFAB, where an id would be shared by every copy
	var inner := CanDestroy.new()
	prefab.add_child(inner)
	assert_eq(WorldSaveId.blank_id_warning_in(inner, prefab), "", "a persistable inside a prefab being edited is quiet")
	prefab.scene_file_path = "res://scenes/levels/Some.tscn"
	assert_ne(WorldSaveId.blank_id_warning_in(inner, prefab), "", "a plain-Node3D level under scenes/levels still warns")
	level.free()
	prefab.free()


func test_new_save_id_is_kind_prefixed_and_never_taken() -> void:
	var prop := CanDestroy.new()
	var taken := {}
	for i in 40:
		var id := WorldSaveId.new_save_id(prop, taken)
		assert_true(String(id).begins_with("can_destroy_"), "the id names the component kind (%s)" % id)
		assert_false(taken.has(id), "never an id already used in the scene")
		taken[id] = true
	assert_eq(taken.size(), 40, "40 stamps, 40 distinct ids")
	prop.free()


# --- The legacy read path: world_objects ---------------------------------------------------------------------------

func test_a_node_given_a_save_id_adopts_its_fallback_keyed_state_once_without_saving() -> void:
	var n := Node3D.new()
	n.name = "Crate"
	add_child_autofree(n)
	var legacy := WorldSaveId.legacy_key_for(n)
	GameState.world_objects = {LEVEL: {legacy: {"gone": true}}}
	GameState._world_save_queued = false
	var st := WorldSaveId.read_object_state(n, &"crate_7")
	assert_eq(st, {"gone": true}, "the state an older save filed under the position key is found")
	var bucket: Dictionary = GameState.world_objects[LEVEL]
	assert_true(bucket.has("id:crate_7"), "and moved to the id key")
	assert_false(bucket.has(legacy), "the legacy entry is gone, so the next save writes one key per object")
	assert_false(GameState._world_save_queued, "adopting is a read: it queues no autosave of its own")
	assert_eq(WorldSaveId.read_object_state(n, &"crate_7"), {"gone": true}, "a second read hits the id key directly")


func test_the_id_key_wins_over_a_stale_legacy_entry_and_a_blank_id_reads_the_fallback() -> void:
	var n := Node3D.new()
	n.name = "Door"
	add_child_autofree(n)
	var legacy := WorldSaveId.legacy_key_for(n)
	GameState.world_objects = {LEVEL: {legacy: {"open": true}, "id:front_door": {"open": false}}}
	assert_eq(WorldSaveId.read_object_state(n, &"front_door"), {"open": false}, "the id key is primary")
	assert_true((GameState.world_objects[LEVEL] as Dictionary).has(legacy), "a legacy entry is only moved when the id key is missing")
	assert_eq(WorldSaveId.read_object_state(n, &""), {"open": true}, "a blank save_id still keys by the fallback")


func test_a_destructible_stamped_after_an_old_save_stays_destroyed() -> void:
	var probe := CanDestroy.new()
	probe.name = "Barrel"
	add_child(probe)
	var legacy := WorldSaveId.legacy_key_for(probe)
	remove_child(probe)
	probe.free()
	GameState.world_objects = {LEVEL: {legacy: {"gone": true}}}  # smashed in a save written while it had no id
	var prop := CanDestroy.new()
	prop.name = "Barrel"
	prop.save_id = &"barrel_1"  # the designer stamped an id since
	add_child_autofree(prop)
	assert_true(prop.is_queued_for_deletion(), "the stamped prop reads its old gone bit through the legacy key")
	assert_true((GameState.world_objects[LEVEL] as Dictionary).has("id:barrel_1"), "re-keyed to its id")


# --- The legacy read path: corpse discovery ------------------------------------------------------------------------

func test_a_corpse_given_a_save_id_keeps_its_old_discovery() -> void:
	var probe := Corpse.new()
	probe.name = "Body"
	add_child(probe)
	var legacy := WorldSaveId.legacy_key_for(probe)
	remove_child(probe)
	probe.free()
	GameState.discovered_corpses = {legacy: true}
	var body := Corpse.new()
	body.name = "Body"
	body.save_id = &"body_1"
	add_child_autofree(body)
	assert_true(body.discovered, "an investigated body stays investigated after it gains an id")
	assert_true(GameState.discovered_corpses.has("id:body_1"), "the marker moved to the id key")
	assert_false(GameState.discovered_corpses.has(legacy), "and left the legacy key")


# --- The legacy read path: the world ledger + the live death ledger -----------------------------------------------

func test_the_world_ledger_applies_a_bucket_filed_under_legacy_keys() -> void:
	var guard := IdNpcStub.new()
	guard.key = "id:guard_1"
	guard.legacy = "%s|/root/Guard" % LEVEL
	add_child_autofree(guard)
	guard.add_to_group(Groups.NPC)
	var ghost := IdNpcStub.new()
	ghost.key = "id:ghost_1"
	ghost.legacy = "%s|/root/Ghost" % LEVEL
	add_child_autofree(ghost)
	ghost.add_to_group(Groups.NPC)
	var crate := IdContainerStub.new()
	crate.key = "id:crate_7"
	crate.legacy = "%s|/root/Crate" % LEVEL
	add_child_autofree(crate)
	crate.add_to_group(Groups.CONTAINERS)
	var snap := WorldSnapshotScript.new()
	snap.from_dict({LEVEL: {
		"authored_npcs": {guard.legacy: {"alive": true, "pos": Vector3.ZERO, "yaw": 0.0, "hp": 12.0}},
		"dead_authored": [ghost.legacy],
		"containers": {crate.legacy: {"stacks": [], "grid": true}},
	}})
	snap.apply(get_tree(), LEVEL)
	assert_eq(guard.restored_hp, 12.0, "a live NPC saved before it had an id gets its hp back")
	assert_true(ghost.is_queued_for_deletion(), "a dead one stays dead")
	assert_eq(crate.restored_with, {"stacks": [], "grid": true}, "a container gets its exact bag back")


func test_the_death_ledger_suppresses_and_rekeys_a_legacy_death() -> void:
	var ghost := IdNpcStub.new()
	ghost.key = "id:ghost_1"
	ghost.legacy = "%s|/root/Ghost" % LEVEL
	add_child_autofree(ghost)
	ghost.add_to_group(Groups.NPC)
	GameState._dead_authored = {LEVEL: {ghost.legacy: true}}
	GameState.suppress_dead_authored(get_tree(), LEVEL)
	assert_true(ghost.is_queued_for_deletion(), "an NPC killed before it had an id stays dead")
	var dead: Dictionary = GameState._dead_authored[LEVEL]
	assert_true(dead.has("id:ghost_1") and not dead.has(ghost.legacy), "the death is re-keyed to the id for the next save")


# --- Findings: the Audit tab + validate_all ------------------------------------------------------------------------

func test_save_id_findings_warn_on_blank_and_error_on_a_duplicate() -> void:
	var level := LevelRoot.new()
	level.name = "Level"
	var a := CanDestroy.new()
	a.name = "A"
	a.save_id = &"shared"
	var b := CanDestroy.new()
	b.name = "B"
	b.save_id = &"shared"
	var blank := CanDestroy.new()
	blank.name = "Blank"
	var opted_out := MoneyPickUp.new()
	opted_out.name = "BagChild"
	opted_out.persist_collected = false
	for n in [a, b, blank, opted_out]:
		level.add_child(n)
		n.owner = level
	var all: Array = ScanScene.save_id_findings(level, true)
	var errors := all.filter(func(f): return f["severity"] == "ERROR")
	var warns := all.filter(func(f): return f["severity"] == "WARN")
	assert_eq(errors.size(), 1, "one duplicate id is one ERROR (two objects would share one saved state)")
	assert_true(str(errors[0]["message"]).contains("shared"), "the ERROR names the id")
	assert_eq(warns.size(), 1, "only the blank persistable warns; the opted-out pickup does not")
	assert_eq(str(warns[0]["source"]), "Blank", "the WARN points at the blank node")
	assert_eq(ScanScene.save_id_findings(level, false).size(), 1,
		"without blanks (the Audit scan, where the config warning already reports them) only the duplicate remains")
	level.free()


# --- PlaceOps: stamping on placement ---------------------------------------------------------------------------------

func test_stamp_save_ids_fills_every_blank_in_the_placed_subtree_uniquely() -> void:
	var scene_root := LevelRoot.new()
	var existing := CanDestroy.new()
	existing.save_id = &"keep_me"
	scene_root.add_child(existing)
	existing.owner = scene_root
	var placed := Node3D.new()
	var p1 := CanDestroy.new()
	var p2 := CanDestroy.new()
	var opted_out := MoneyPickUp.new()
	opted_out.persist_collected = false
	placed.add_child(p1)
	placed.add_child(p2)
	placed.add_child(opted_out)
	scene_root.add_child(placed)
	PlaceOps.own_recursive(placed, scene_root)
	assert_eq(PlaceOps.stamp_save_ids(placed, scene_root), 2, "two blank persistables were stamped")
	assert_ne(p1.save_id, &"", "stamped")
	assert_ne(p1.save_id, p2.save_id, "each gets its own id")
	assert_eq(existing.save_id, &"keep_me", "an authored id elsewhere is untouched")
	assert_eq(opted_out.save_id, &"", "an opted-out pickup is left blank")
	assert_eq(PlaceOps.stamp_save_ids(placed, scene_root), 0, "stamping again changes nothing")
	scene_root.free()


func test_stamp_save_ids_stamps_an_instance_root_but_never_its_internals() -> void:
	var scene_root := LevelRoot.new()
	var instance := CanDestroy.new()
	instance.scene_file_path = "res://scenes/components/can_destroy.tscn"  # stands in for a placed prefab
	var internal := CanDestroy.new()
	instance.add_child(internal)
	internal.owner = instance
	scene_root.add_child(instance)
	PlaceOps.own_recursive(instance, scene_root)
	assert_eq(PlaceOps.stamp_save_ids(instance, scene_root), 1, "only the instance root is stamped")
	assert_ne(instance.save_id, &"", "the instance root is saved into the level, so its id sticks")
	assert_eq(internal.save_id, &"", "a node inside the instance would not be saved into the level, so it is left alone")
	scene_root.free()


func test_missing_save_id_nodes_lists_what_the_place_tab_batch_can_stamp() -> void:
	var scene_root := LevelRoot.new()
	var blank := CanDestroy.new()
	var authored := CanDestroy.new()
	authored.save_id = &"a"
	var instance := Node3D.new()
	instance.scene_file_path = "res://scenes/props/something.tscn"
	var hidden := CanDestroy.new()
	instance.add_child(hidden)
	hidden.owner = instance
	for n in [blank, authored, instance]:
		scene_root.add_child(n)
		n.owner = scene_root
	var missing: Array = PlaceOps.missing_save_id_nodes(scene_root)
	assert_eq(missing, [blank], "only a blank persistable the level itself saves is listed")
	scene_root.free()
