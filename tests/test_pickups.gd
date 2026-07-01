extends GutTest

## World pickups (this batch): the new money pickup's pure surface, and the per-item world-model wiring —
## the grant + free + toast side effects are in-tree behaviour (playtested), so we pin only the pure logic.
## Plus the stashable-crate prefab's dual-item wiring (a Throwable that E stashes / Z throws).

const STASHABLE_CRATE := preload("res://scenes/throwable/stashable_crate.tscn")
const CRATE_ITEM := preload("res://resources/items/crate_item.tres")
const ModelResource = preload("res://scripts/components/model_resource.gd")

func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}

func test_money_pickup_label_and_gate() -> void:
	var m := MoneyPickUp.new()
	m.amount = 50
	assert_eq(m.look_name(), "Take 50 zorkmids", "the default hover readout shows the amount")
	assert_true(m.can_be_talked_to(), "a pickup holding money is interactable")
	m.amount = 0
	assert_false(m.can_be_talked_to(), "an empty money pickup can't be interacted with")
	m.amount = 50
	m.pickup_label = "Loose change"
	assert_eq(m.look_name(), "Loose change", "a custom label overrides the amount readout")
	m.free()


func test_money_pickup_builds_a_default_coin() -> void:
	var m := MoneyPickUp.new()
	var coin := m._default_coin()
	assert_not_null(coin.mesh, "the fallback coin carries a mesh, so a bare MoneyPickUp is visible in the world")
	coin.free()
	m.free()


func test_money_pickup_world_model_accepts_mesh_resource() -> void:
	var m := MoneyPickUp.new()
	var mesh := SphereMesh.new()
	m.world_model = mesh
	add_child_autofree(m)
	var visual := m.highlight_target as MeshInstance3D
	assert_not_null(visual, "MoneyPickUp can wrap a raw Mesh resource as its world model")
	if visual != null:
		assert_eq(visual.mesh, mesh, "MoneyPickUp uses the assigned Mesh resource")


func test_canpickup_does_not_auto_body_authored_pickups() -> void:
	var cp := CanPickUp.new()
	assert_false(cp.build_model_from_item,
		"the item-model build is OPT-IN — an authored CanPickUp keeps its own visual unless asked")
	cp.free()


func test_item_world_model_is_opt_in() -> void:
	var it := Item.new()
	assert_null(it.world_model, "an item has no world model until one is assigned (inventory UI uses name/icon)")
	it = null


func test_world_model_fields_accept_scene_or_mesh() -> void:
	var item := Item.new()
	var money := MoneyPickUp.new()
	var upgrade := UpgradePickup.new()
	for entry in [
		{"obj": item, "label": "Item.world_model"},
		{"obj": money, "label": "MoneyPickUp.world_model"},
		{"obj": upgrade, "label": "UpgradePickup.world_model"},
	]:
		var prop := _property(entry["obj"], "world_model")
		assert_eq(prop.get("hint", -1), PROPERTY_HINT_RESOURCE_TYPE,
			"%s uses a resource-type hint" % entry["label"])
		assert_eq(prop.get("hint_string", ""), ModelResource.HINT,
			"%s accepts scene models and raw mesh imports" % entry["label"])
	money.free()
	upgrade.free()
	item = null


func test_canpickup_builds_item_world_model_from_mesh_resource() -> void:
	var it := Item.new()
	var mesh := BoxMesh.new()
	it.world_model = mesh
	var cp := CanPickUp.new()
	cp.item = it
	cp.build_model_from_item = true
	add_child_autofree(cp)
	var visual := cp.highlight_target as MeshInstance3D
	assert_not_null(visual, "CanPickUp can build an item world model from a raw Mesh resource")
	if visual != null:
		assert_eq(visual.mesh, mesh, "CanPickUp uses item.world_model's Mesh resource")
	it = null


func test_world_item_drop_uses_mesh_world_model() -> void:
	var it := Item.new()
	var mesh := CapsuleMesh.new()
	it.world_model = mesh
	var dropped := WorldItem.build(it, 2)
	assert_true(dropped is Throwable,
		"an item with a plain world_model still drops as the carry/throw/stash Throwable shell")
	var visual := dropped.get_node_or_null(^"Visual") as MeshInstance3D
	assert_not_null(visual, "WorldItem wraps a raw Mesh world_model as the drop visual")
	if visual != null:
		assert_eq(visual.mesh, mesh, "WorldItem uses the assigned world_model Mesh resource")
	dropped.free()
	it = null


# ---------------------------------------------------------------------------
# Stashable physics prop — CanPickUp wired onto a Throwable (the "dual item")
# ---------------------------------------------------------------------------

func test_crate_item_is_a_stashable_misc_item() -> void:
	# A throwable becomes an inventory Item to be stashable; the crate is a plain MISC item, not a weapon.
	assert_ne(CRATE_ITEM.id, &"", "the crate item carries a stable id")
	assert_false(CRATE_ITEM.is_weapon(), "a crate stashes as a plain MISC item, not a weapon")
	assert_eq(CRATE_ITEM.category, Item.Category.MISC, "the crate is a MISC inventory item")
	assert_gt(CRATE_ITEM.grid_width * CRATE_ITEM.grid_height, 1,
		"a crate is bulky — it occupies more than one Tetris grid cell")


func test_stashable_crate_is_a_throwable_with_a_pickup_child() -> void:
	# instantiate() builds the node tree but does NOT run _ready (that fires on tree entry), so this is a
	# pure structural contract check with no side effects — safe under the no-_ready-in-unit-tests rule.
	# It pins the dual-item invariant: a Throwable ROOT (so Z still carries/throws) carrying a CanPickUp
	# DESCENDANT (so ray_cast.gd lets E stash it instead of grabbing). If either half regresses, E or Z breaks.
	var crate := STASHABLE_CRATE.instantiate()
	assert_true(crate is Throwable, "the root is a Throwable so the carry/throw (Z) verb is unchanged")
	# Find the pickup by class, not find_children's `type` filter (whose script-class_name matching is
	# unreliable across Godot versions). It's a direct child here, so get_children() is enough.
	var cp: CanPickUp = null
	for c in crate.get_children():
		if c is CanPickUp:
			cp = c as CanPickUp
			break
	assert_not_null(cp, "a CanPickUp is wired onto the crate")
	if cp != null:
		assert_true(crate.is_ancestor_of(cp),
			"the CanPickUp is a DESCENDANT of the Throwable — the dual-item rule ray_cast.gd needs so E (stash) beats Z (grab)")
		assert_not_null(cp.item, "the CanPickUp has an item, so pressing E actually stashes something")
		if cp.item != null:
			assert_eq(cp.item.id, CRATE_ITEM.id, "the stashed item is the crate item")
	crate.free()


# ---------------------------------------------------------------------------
# Item.world_prop — drop/place as an AUTHORED prop scene (keeps its behaviour)
# ---------------------------------------------------------------------------

func test_world_prop_drops_as_the_authored_scene() -> void:
	# With world_prop set, WorldItem.build spawns that EXACT authored scene (so the dropped object keeps its own
	# destructible / spawn-on-destroy behaviour) instead of the generic placeholder Throwable. Uses the
	# stashable-crate prefab as a stand-in authored prop (no GLB/asset dependency); a real dog crate is wired the
	# same way. world_prop is a PATH (load()ed at build time), not a PackedScene ref — that's what avoids the
	# item<->scene load cycle. instantiate() runs no _ready, so this stays a side-effect-free structural check.
	var it := Item.new()
	it.world_prop = "res://scenes/throwable/stashable_crate.tscn"
	var dropped := WorldItem.build(it, 1)
	assert_not_null(dropped, "an item with world_prop builds a world object")
	if dropped != null:
		assert_eq(dropped.name, &"Cube",
			"world_prop spawned the authored prop scene (its 'Cube' root), not a code-built placeholder")
		# The authored prop still carries its CanPickUp, so the dropped object is re-stashable with E.
		var has_pickup := false
		for c in dropped.get_children():
			if c is CanPickUp:
				has_pickup = true
				break
		assert_true(has_pickup, "the dropped prop keeps its CanPickUp (re-stashable)")
		dropped.free()
	it = null


func test_world_prop_is_opt_in() -> void:
	var it := Item.new()
	assert_eq(it.world_prop, "", "an item has no world prop until one is assigned (defaults to the placeholder drop)")
	it = null


# ---------------------------------------------------------------------------
# Drop conservation — N units out of the bag == N recoverable back (the dog-crate item-loss regression)
# ---------------------------------------------------------------------------

## The dog-crate bug: dropping 2 crates removed BOTH from the bag but spawned only 1 recoverable crate. This pins
## the invariant it broke — a dropped stack must be fully recoverable. Uses a stackable world_MODEL item (the path
## where count flows end-to-end: _make_throwable stamps cp.amount = count). Replicates Player.drop_item's two steps
## (inventory.remove -> WorldItem.build) WITHOUT the player node, since drop_item reads get_world_3d()/get_parent().
func test_drop_conserves_full_count_no_loss() -> void:
	var it := Item.new()
	it.max_stack = 20                       # stackable, so all 5 live in ONE stack
	it.world_model = BoxMesh.new()
	var inv := CharacterInventory.new()     # grid OFF = unlimited v1 bag
	assert_eq(inv.add(it, 5), 5, "all 5 land in the bag")
	assert_eq(inv.count_of(it), 5, "the bag holds 5 before the drop")
	var removed := inv.remove(it, 5)         # what Player.drop_item pulls out of the bag
	assert_eq(removed, 5, "the drop removes exactly the requested count")
	assert_eq(inv.count_of(it), 0, "nothing is left stranded in the bag")
	var dropped := WorldItem.build(it, removed)
	var cp: CanPickUp = null
	for c in dropped.get_children():
		if c is CanPickUp:
			cp = c as CanPickUp
			break
	assert_not_null(cp, "the drop carries a CanPickUp so it can be re-stashed")
	if cp != null:
		assert_eq(cp.amount, 5, "the pickup grants the whole dropped count back — no silent loss")
		var inv2 := CharacterInventory.new()
		cp._grant(inv2)                      # split-out seam: no host-free side effect, no player needed
		assert_eq(inv2.count_of(it), 5, "5 out == 5 back — the round-trip conserves every unit")
		inv2.free()
	dropped.free()
	inv.free()
	it = null


## world_prop is a SINGLE authored object, but a count>1 drop must still be lossless: WorldItem.build stamps the
## drop count onto the prop's (possibly nested) CanPickUp so E re-stashes the whole stack. Guards against the
## dog-crate bug (drop 2, only 1 recoverable) AND against a wrong "fix" that spawns N props / N dogs. The authored
## stashable-crate CanPickUp has no `amount` (defaults 1), so this assert fails on the pre-fix build().
func test_world_prop_drop_stamps_count_on_its_pickup() -> void:
	var it := Item.new()
	it.world_prop = "res://scenes/throwable/stashable_crate.tscn"
	var dropped := WorldItem.build(it, 3)
	assert_not_null(dropped, "an item with world_prop builds a world object")
	if dropped != null:
		var cp: CanPickUp = null
		for n in dropped.find_children("*", "", true, false):
			if n is CanPickUp:
				cp = n as CanPickUp
				break
		assert_not_null(cp, "the authored prop keeps its CanPickUp")
		if cp != null:
			assert_eq(cp.amount, 3, "a stack of 3 stamps amount=3 on the one prop — the other 2 aren't destroyed")
		dropped.free()
	it = null
