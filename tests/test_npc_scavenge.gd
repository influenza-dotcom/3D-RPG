extends GutTest

## NpcScavenge weapon raid: grabbing a better weapon from a crate must ALSO pick up the matching ammo, so the
## upgrade is actually usable (a gun with no rounds would just drop the NPC back to fists). Integration test
## over the real ItemDb registry + real CharacterInventory (a Node, but its add/transfer/count work off-tree).

## A bare Node exposing an `inventory` property -- what NpcScavenge reads off its host and the raided container.
class _InvNode:
	extends Node
	var inventory: CharacterInventory = null

## A registered [weapon_item, ammo_item] pair from ItemDb (the game ships guns with ammo), or [] if none.
func _weapon_with_ammo() -> Array:
	for it in ItemDb.all_items():
		if it != null and it.is_weapon() and it.weapon != null:
			var ammo = ItemDb.ammo_item_for(it.weapon.caliber)
			if ammo != null:
				return [it, ammo]
	return []

func test_scavenge_grabs_weapon_and_its_ammo() -> void:
	var pair := _weapon_with_ammo()
	assert_false(pair.is_empty(), "ItemDb should register at least one weapon with matching ammo")
	if pair.is_empty():
		return
	var weapon_item: Item = pair[0]
	var ammo_item: Item = pair[1]
	var caliber: StringName = weapon_item.weapon.caliber

	var crate := CharacterInventory.new()
	crate.add(ItemDb.make_weapon_item(weapon_item.weapon), 1)  # a fresh unique gun in the crate
	crate.add(ammo_item, 3)                                    # plus 3 rounds of its caliber
	var crate_node := _InvNode.new()
	crate_node.inventory = crate

	var host_inv := CharacterInventory.new()
	var host := _InvNode.new()
	host.inventory = host_inv

	var scav := NpcScavenge.new()
	scav.host = host
	scav._take_best_weapon_from(crate_node)

	assert_not_null(host_inv.best_weapon_item(), "the better weapon was grabbed")
	assert_not_null(host_inv.equipped_item, "and drawn (equip-the-strongest)")
	assert_eq(host_inv.ammo_count(caliber), 3, "ALL its ammo came along, so the gun is usable")
	assert_eq(crate.ammo_count(caliber), 0, "the crate's ammo was MOVED, not duplicated")

	scav.free()
	host.free()
	crate_node.free()
	crate.free()
	host_inv.free()

func test_scavenge_grabs_weapon_even_when_crate_has_no_ammo() -> void:
	# No ammo in the crate -> still grab the gun (it can reload-supply later or be a melee/last-resort), and
	# don't crash on the empty ammo lookup. Pins the have > 0 guard.
	var pair := _weapon_with_ammo()
	if pair.is_empty():
		return
	var weapon_item: Item = pair[0]

	var crate := CharacterInventory.new()
	crate.add(ItemDb.make_weapon_item(weapon_item.weapon), 1)  # weapon only, no ammo
	var crate_node := _InvNode.new()
	crate_node.inventory = crate
	var host_inv := CharacterInventory.new()
	var host := _InvNode.new()
	host.inventory = host_inv

	var scav := NpcScavenge.new()
	scav.host = host
	scav._take_best_weapon_from(crate_node)

	assert_not_null(host_inv.best_weapon_item(), "the weapon is still grabbed when the crate had no ammo")
	assert_eq(host_inv.ammo_count(weapon_item.weapon.caliber), 0, "no ammo to grab -> none added")

	scav.free()
	host.free()
	crate_node.free()
	crate.free()
	host_inv.free()
