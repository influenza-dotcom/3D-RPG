extends GutTest

## NPC inventory wiring (Phase C of the inventory feature). GUT unit suite.
##
## SCOPE — follows the firm repo convention (see test_enemies.gd): an NPC's _ready() is NEVER run in a
## unit test (it instantiates weapon.tscn, add_childs a muzzle/nav, writes FreezeFrame, plays audio, and
## mutates a shared static cooldown). So we build the NPC off-tree via load().new() WITHOUT add_child and
## exercise only the new, side-effect-free seam:
##   - _equip_initial_weapon() SEEDS the backpack from weapon_data (the part that makes a corpse
##     lootable): a registered weapon -> its ItemDb item lands in the backpack; an unregistered
##     WeaponData seeds nothing (and doesn't crash on the direct-equip fallback while _weapon is null).
##   - _on_equip_weapon_requested() is null-safe before a weapon hub exists (the _weapon guard).
##   - Both equip-bridge methods are present (surface check, like the AI-method surface tests).
##
## DELIBERATELY SKIPS (verified by manual playtest, as the repo does for all _ready behaviour): the
## actual draw-from-backpack on spawn and the _weapon.inventory.equip routing — both need a real Weapon
## (weapon.tscn) under the tree. Off-tree, _equip_initial_weapon's equip_item() emits to an UNCONNECTED
## signal (Character._ready, which wires it, never ran), so only the backpack-seed line has any effect.

const RANGED_PATH := "res://scripts/npc/npc.gd"
const PISTOL := preload("res://resources/weapons/pistol.tres")


func test_equip_initial_weapon_seeds_backpack_from_registered_weapon() -> void:
	var n: NPC = load(RANGED_PATH).new()  # no add_child: _ready MUST NOT run
	n.weapon_data = PISTOL
	var inv := CharacterInventory.new()   # stand in for the backpack Character._ready would build
	n.inventory = inv
	n._equip_initial_weapon()
	# Seeds a UNIQUE weapon item + reserve ammo of its caliber (corpse loot fodder).
	var found_weapon := false
	for s in inv.contents():
		var it: Item = s["item"]
		if it.is_weapon() and it.weapon == PISTOL:
			found_weapon = true
	assert_true(found_weapon,
		"A combatant NPC seeds its backpack with its (unique) weapon item, so the corpse can drop it")
	assert_eq(inv.ammo_count(&"9mm"), NPC.NPC_AMMO_DROP,
		"It also stashes reserve ammo of the weapon's caliber, so the corpse yields ammo to loot")
	inv.free()
	n.free()


func test_equip_initial_weapon_unregistered_weapon_seeds_nothing() -> void:
	var n: NPC = load(RANGED_PATH).new()  # no add_child
	n.weapon_data = WeaponData.new()      # a stray weapon, not one of the 7 registered .tres
	var inv := CharacterInventory.new()
	n.inventory = inv
	# witem is null -> the direct-equip fallback runs, but _weapon is null so it's a guarded no-op.
	n._equip_initial_weapon()
	assert_true(inv.is_empty(),
		"An unregistered WeaponData has no ItemDb item, so nothing is added to the backpack (it equips directly instead)")
	inv.free()
	n.free()


func test_on_equip_weapon_requested_is_null_safe_without_weapon_hub() -> void:
	var n: NPC = load(RANGED_PATH).new()  # no add_child: _weapon stays null
	# Must not crash dereferencing the absent weapon hub — the guard short-circuits.
	n._on_equip_weapon_requested(PISTOL)
	assert_true(n._weapon == null,
		"With no weapon hub yet, _on_equip_weapon_requested must be a guarded no-op (no _weapon created)")
	n.free()


func test_npc_equip_bridge_method_surface() -> void:
	var n: NPC = load(RANGED_PATH).new()  # no add_child
	assert_true(n.has_method("_equip_initial_weapon"),
		"NPC must define _equip_initial_weapon() — seeds + draws the assigned weapon from the backpack")
	assert_true(n.has_method("_on_equip_weapon_requested"),
		"NPC must override _on_equip_weapon_requested() — routes a backpack equip to its weapon hub")
	n.free()
