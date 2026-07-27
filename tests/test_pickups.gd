extends GutTest

## World pickups (this batch): the new money pickup's pure surface, and the per-item world-model wiring —
## the grant + free + toast side effects are in-tree behaviour (playtested), so we pin only the pure logic.
## Plus the stashable-crate prefab's dual-item wiring (a Throwable that E stashes / Z throws).

const STASHABLE_CRATE := preload("res://scenes/throwable/stashable_crate.tscn")
const CRATE_ITEM := preload("res://resources/items/crate_item.tres")
const DOG_SCENE := preload("res://scenes/enemies/dog.tscn")
const DOG_ITEM := preload("res://resources/items/dog_item.tres")
const DogPickupScript := preload("res://scripts/components/dog_pickup.gd")
const RandomSizeScript := preload("res://scripts/components/random_size.gd")
const ModelResource = preload("res://scripts/components/model_resource.gd")

## Stand-in for the dog Throwable host: a Node3D that exposes the verb-less name resolver claim()/look_name read, plus
## a settable display_name so claiming can rename it. Lets us drive DogPickup.look_name OFF-TREE (no _ready) with a
## claimed Claimable child under it. Mirrors test_claimable's _DogHost.
class _NamedHost extends Node3D:
	var display_name := ""
	func resolved_display_name() -> String:
		return display_name if not display_name.is_empty() else "Dog"


func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}

func test_money_pickup_label_and_gate() -> void:
	var m := MoneyPickUp.new()
	m.amount = 50
	assert_eq(m.look_name(), "[PH] Take 50 zorkmids", "the default hover readout shows the amount")
	assert_true(m.can_be_talked_to(), "a pickup holding money is interactable")
	m.amount = 0
	assert_false(m.can_be_talked_to(), "an empty money pickup can't be interacted with")
	m.amount = 50
	m.pickup_label = "Loose change"
	assert_eq(m.look_name(), "Loose change", "a custom label overrides the amount readout")
	m.free()


func test_money_pickup_defaults_to_the_chaching_jingle() -> void:
	# The collect cue is designer-swappable but ships wired to the coin "cha-ching" out of the box, so a bare
	# MoneyPickUp (and every dropped money bag's Reclaim child) already sounds right on pickup. Export defaults are
	# set at construction, so this needs no _ready / AudioManager — a pure surface check.
	var m := MoneyPickUp.new()
	assert_eq(m.pickup_sound, MoneyPickUp.CHACHING, "a fresh money pickup plays the cha-ching jingle by default")
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


func test_money_and_upgrade_pickups_persist_collected_by_default() -> void:
	# F-C16: a HAND-PLACED money / upgrade pickup records its "gone" bit so it doesn't respawn (money) or re-grant
	# (upgrade) on Continue — persist_collected defaults true, and both expose a save_id (StringName) so an authored
	# pickup's collected-state survives layout edits, mirroring CanPickUp/CanDestroy. Pure surface check (no _ready).
	var m := MoneyPickUp.new()
	var u := UpgradePickup.new()
	assert_true(m.persist_collected, "a fresh MoneyPickUp persists its collected 'gone' bit by default")
	assert_true(u.persist_collected, "a fresh UpgradePickup persists its collected 'gone' bit by default")
	assert_eq(_property(m, "save_id").get("type", -1), TYPE_STRING_NAME, "MoneyPickUp exposes a StringName save_id")
	assert_eq(_property(u, "save_id").get("type", -1), TYPE_STRING_NAME, "UpgradePickup exposes a StringName save_id")
	m.free()
	u.free()


func test_money_bag_reclaim_child_opts_out_of_persistence() -> void:
	# A dropped money bag is a DYNAMIC spawn with no stable identity, so its Reclaim MoneyPickUp must NOT enter the
	# world_objects ledger — MoneyBag sets persist_collected=false on it. build() adds children to an OFF-TREE bag, so
	# no _ready fires: a side-effect-free structural check that pins the opt-out so a dropped bag never persists.
	var bag := MoneyBag.build(100.0)
	assert_true(bag is Throwable, "a money bag is a Throwable shell")
	var reclaim: MoneyPickUp = null
	for c in bag.get_children():
		if c is MoneyPickUp:
			reclaim = c as MoneyPickUp
			break
	assert_not_null(reclaim, "the money bag carries a MoneyPickUp reclaim child")
	if reclaim != null:
		assert_false(reclaim.persist_collected,
			"a dropped bag's reclaim child opts OUT of world_objects persistence (dynamic spawn, no stable identity)")
	bag.free()


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
# Stashable dogs -- live dog pickup keeps its rolled size as item data
# ---------------------------------------------------------------------------

func test_dog_item_is_a_stashable_size_based_misc_item() -> void:
	assert_eq(DOG_ITEM.id, &"dog", "the dog item carries a stable id")
	assert_false(DOG_ITEM.is_weapon(), "a dog stashes as a plain MISC item, not a weapon")
	assert_eq(DOG_ITEM.category, Item.Category.MISC, "the dog is a MISC inventory item")
	assert_eq(DOG_ITEM.max_stack, 1, "dogs are unique inventory items, not stackable piles")
	assert_false(DOG_ITEM.world_prop.is_empty(), "dropping a dog item should restore the authored dog scene")
	assert_gt(DOG_ITEM.grid_width * DOG_ITEM.grid_height, 1,
		"a normal dog is bulky enough to occupy multiple backpack cells")


func test_dog_pickup_item_scales_value_weight_and_footprint_from_size() -> void:
	var small := DogPickupScript.build_item_for_size(DOG_ITEM, 0.8)
	var large := DogPickupScript.build_item_for_size(DOG_ITEM, 1.25)
	assert_not_null(small, "a dog pickup can build an inventory item from the dog template")
	assert_not_null(large, "a dog pickup can build an inventory item from the dog template")
	if small != null and large != null:
		assert_lt(small.value, DOG_ITEM.value, "smaller dogs are worth less than the normal template")
		assert_lt(small.weight, DOG_ITEM.weight, "smaller dogs weigh less than the normal template")
		assert_eq(Vector2i(small.grid_width, small.grid_height), Vector2i(1, 1),
			"small dogs take a single backpack cell")
		assert_gt(large.value, DOG_ITEM.value, "larger dogs are worth more than the normal template")
		assert_gt(large.weight, DOG_ITEM.weight, "larger dogs weigh more than the normal template")
		assert_eq(Vector2i(large.grid_width, large.grid_height), Vector2i(3, 3),
			"large dogs take a bigger backpack footprint")
		assert_true(large.has_meta(RandomSizeScript.SIZE_META),
			"the generated item remembers the dog's exact size for later drops")
		assert_almost_eq(float(large.get_meta(RandomSizeScript.SIZE_META)), 1.25, 0.0001,
			"the exact dog size is stored on the generated item")
	small = null
	large = null


func test_dog_pickup_value_scales_with_coat_multiplier() -> void:
	# The request: different coats are worth different money. build_item_for_size folds a per-coat value multiplier on
	# TOP of the size curve — a rarer coat prices an otherwise-identical dog higher WITHOUT touching its weight/footprint.
	var plain := DogPickupScript.build_item_for_size(DOG_ITEM, 1.0, 2.0, 3.0, 1.0)
	var rare := DogPickupScript.build_item_for_size(DOG_ITEM, 1.0, 2.0, 3.0, 3.0)
	assert_not_null(plain, "a plain-coat dog item builds")
	assert_not_null(rare, "a rare-coat dog item builds")
	if plain != null and rare != null:
		assert_gt(rare.value, plain.value, "a rarer coat multiplier makes the same-size dog worth more zorkmids")
		assert_almost_eq(rare.value, plain.value * 3.0, 0.01, "the coat multiplier scales value linearly on top of size")
		assert_almost_eq(rare.weight, plain.weight, 0.0001, "the coat prices the dog but does NOT change its weight")
		assert_eq(rare.grid_width, plain.grid_width, "the coat does not change the backpack footprint")
		assert_eq(rare.grid_height, plain.grid_height, "the coat does not change the backpack footprint")
	plain = null
	rare = null


func test_dog_pickup_default_coat_multiplier_is_neutral() -> void:
	# Omitting the coat multiplier (old callers, or a dog whose coats aren't priced) must price exactly as before —
	# the 5th arg defaults to 1.0, so the size-only value is unchanged.
	var default_arg := DogPickupScript.build_item_for_size(DOG_ITEM, 1.1)
	var explicit_one := DogPickupScript.build_item_for_size(DOG_ITEM, 1.1, 2.0, 3.0, 1.0)
	assert_not_null(default_arg)
	assert_not_null(explicit_one)
	if default_arg != null and explicit_one != null:
		assert_almost_eq(default_arg.value, explicit_one.value, 0.0001,
			"a missing coat multiplier prices identically to ×1.0 (backwards-compatible)")
	default_arg = null
	explicit_one = null


func test_dog_scene_authors_aligned_coat_prices() -> void:
	# The shipped dog must price its coats index-for-index with its tints (a mismatch silently mis-prices). This pins the
	# scene wiring so re-authoring the tint pool without the multiplier pool can't slip through.
	var dog := DOG_SCENE.instantiate()
	var coat: RandomCoat = null
	for n in dog.find_children("*", "", true, false):
		if n is RandomCoat:
			coat = n as RandomCoat
			break
	assert_not_null(coat, "the dog scene carries a RandomCoat")
	if coat != null:
		assert_gt(coat.coat_value_mults.size(), 0, "the shipped dog prices its coats (rarer coats sell for more)")
		assert_eq(coat.coat_value_mults.size(), coat.coat_tints.size(),
			"the dog's coat prices are index-aligned with its coat tints (no silent ×1.0 fallback)")
		assert_eq(coat._get_configuration_warnings().size(), 0,
			"the shipped dog's aligned pools raise no config warning")
	dog.free()


func test_dog_scene_is_a_throwable_with_a_pickup_child() -> void:
	var dog := DOG_SCENE.instantiate()
	assert_true(dog is Throwable, "the dog root stays Throwable so Z still carries/throws it")
	var cp: CanPickUp = null
	for n in dog.find_children("*", "", true, false):
		if n is CanPickUp and n.get_script() == DogPickupScript:
			cp = n as CanPickUp
			break
	assert_not_null(cp, "a DogPickup is wired onto the dog")
	if cp != null:
		assert_true(dog.is_ancestor_of(cp),
			"the DogPickup is a descendant of the Throwable so E stashes while Z carries")
		assert_not_null(cp.item, "the DogPickup has a dog item template")
		if cp.item != null:
			assert_eq(cp.item.id, DOG_ITEM.id, "the stashed item is the dog item")
		var has_shape := false
		for c in cp.get_children():
			if c is CollisionShape3D:
				has_shape = true
				break
		assert_true(has_shape, "the DogPickup has its own look-at hitbox")
	dog.free()


func test_world_prop_dog_drop_preserves_item_size() -> void:
	var dynamic_dog := DogPickupScript.build_item_for_size(DOG_ITEM, 1.25)
	var dropped := WorldItem.build(dynamic_dog, 1)
	assert_not_null(dropped, "a size-stamped dog item builds a dropped dog scene")
	if dropped != null:
		var random_size: Node = null
		for n in dropped.find_children("*", "", true, false):
			if n.get_script() == RandomSizeScript:
				random_size = n
				break
		assert_not_null(random_size, "the dropped dog keeps its RandomSize component")
		if random_size != null:
			assert_almost_eq(float(random_size.get(&"preset_scale_mult")), 1.25, 0.0001,
				"dropping a dog item restores the same size instead of rerolling")
		dropped.free()
	dynamic_dog = null


func test_world_prop_dog_drop_restores_coat_and_befriend() -> void:
	# The reported bug: a stashed dog dropped back into the world re-rolled a NEW coat colour and forgot it was
	# befriended. Fix: DogPickup stamps the live coat tint + claim state/name onto the item's meta on pickup, and
	# WorldItem.build pushes those onto the rebuilt dog's RandomCoat.preset_tint / Claimable.preset_* so the drop
	# reproduces the SAME dog. Structural (instantiate runs no _ready), mirroring the size test above.
	var dog_item := DogPickupScript.build_item_for_size(DOG_ITEM, 1.0)
	var coat := Color(0.62, 0.44, 0.26, 1.0)
	dog_item.set_meta(RandomCoat.COAT_META, coat)
	dog_item.set_meta(Claimable.CLAIMED_META, true)
	dog_item.set_meta(Claimable.CLAIMED_NAME_META, "Rex")
	var dropped := WorldItem.build(dog_item, 1)
	assert_not_null(dropped, "a captured-state dog item builds a dropped dog")
	if dropped != null:
		var coat_node: RandomCoat = null
		var claim_node: Claimable = null
		for n in dropped.find_children("*", "", true, false):
			if n is RandomCoat:
				coat_node = n as RandomCoat
			elif n is Claimable:
				claim_node = n as Claimable
		assert_not_null(coat_node, "the dropped dog keeps its RandomCoat")
		if coat_node != null:
			assert_eq(coat_node.preset_tint, coat,
				"dropping restores the stashed coat tint instead of re-rolling a new colour")
		assert_not_null(claim_node, "the dropped dog keeps its Claimable")
		if claim_node != null:
			assert_true(claim_node.preset_claimed, "dropping restores the befriended state")
			assert_eq(claim_node.preset_claim_name, "Rex", "dropping restores the name you gave the dog")
		dropped.free()
	dog_item = null


func test_world_prop_dog_drop_unclaimed_stays_unclaimed() -> void:
	# The has_meta gate: a plain (never-befriended, un-recoloured) dog item carries no coat/claim meta, so the dropped
	# dog must spawn UNCLAIMED with its coat left to re-roll — not accidentally befriended or frozen to a colour.
	var dog_item := DogPickupScript.build_item_for_size(DOG_ITEM, 1.0)
	var dropped := WorldItem.build(dog_item, 1)
	assert_not_null(dropped, "a bare dog item still builds a dropped dog")
	if dropped != null:
		for n in dropped.find_children("*", "", true, false):
			if n is Claimable:
				assert_false((n as Claimable).preset_claimed,
					"a never-befriended dog drops unclaimed (no stray auto-befriend)")
			elif n is RandomCoat:
				assert_eq((n as RandomCoat).preset_tint.a, 0.0,
					"a dog with no stashed coat re-rolls normally (preset left unset)")
		dropped.free()
	dog_item = null


func test_befriended_dog_pickup_prompt_uses_name() -> void:
	# The reported prompt bug: a befriended dog's E-stash readout should read by the NAME you gave it ("Take Brian"),
	# not its size label ("Take Large Dog"). DogPickup stays OFF-TREE (no _ready); its highlight_target points at an
	# in-tree host stub carrying a CLAIMED Claimable, and look_name resolves the name via _befriended_name -> claim_name.
	var host := _NamedHost.new()
	add_child_autofree(host)
	var claim := Claimable.new()
	claim.auto_fit_collider = false
	host.add_child(claim)
	claim.claim(null, "Brian")  # befriend -> pushes "Brian" onto the host's display_name
	var dp = DogPickupScript.new()
	dp.item = DOG_ITEM
	dp.highlight_target = host
	assert_eq(dp.look_name(), "Take Brian",
		"a befriended dog's pickup prompt reads by the name you gave it, not its size label")
	dp.free()


func test_unbefriended_dog_pickup_prompt_uses_size_label() -> void:
	# The flip side: with no befriend, the prompt falls back to super's size label so an un-named stray still reads
	# "Take Dog" / "Take Large Dog". A Claimable is present but UNCLAIMED, so _befriended_name returns "".
	var host := _NamedHost.new()
	add_child_autofree(host)
	var claim := Claimable.new()
	claim.auto_fit_collider = false
	host.add_child(claim)
	var dp = DogPickupScript.new()
	dp.item = DOG_ITEM
	dp.highlight_target = host
	assert_eq(dp.look_name(), "Take [PH] Dog",
		"an un-befriended dog falls back to the item's size label (size 1.0 -> plain 'Dog')")
	dp.free()


func test_random_coat_preset_default_rolls() -> void:
	# The alpha-0 sentinel: an unset preset_tint means "roll from the pool" (a hand-placed dog varies its coat).
	var rc := RandomCoat.new()
	assert_eq(rc.preset_tint.a, 0.0, "no preset by default -> the coat rolls from the pool")
	rc.free()


func test_random_coat_read_applied_tint() -> void:
	# read_applied_tint pulls the colour off the host's mesh material_override — the capture DogPickup stashes so a
	# re-dropped dog keeps its exact coat (works for a rolled coat OR a spray-paint recolour).
	var host := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.9, 1.0)
	mi.material_override = mat
	host.add_child(mi)
	add_child_autofree(host)
	assert_eq(RandomCoat.read_applied_tint(host), Color(0.2, 0.5, 0.9, 1.0),
		"read_applied_tint returns the mesh's current albedo tint")
	assert_eq(RandomCoat.read_applied_tint(null).a, 0.0,
		"a null host returns the alpha-0 'unset' sentinel")


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
