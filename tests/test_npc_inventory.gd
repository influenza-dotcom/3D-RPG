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
##   - _on_equip_weapon_requested() routes a backpack equip onto the weapon hub's Inventory, and is a guarded
##     no-op before a hub (or its Inventory) exists.
##   - Both equip-bridge methods are present (surface check, like the AI-method surface tests).
##
## DELIBERATELY SKIPS (verified by manual playtest, as the repo does for all _ready behaviour): the
## actual draw-from-backpack on spawn — off-tree, _equip_initial_weapon's equip_item() emits to an UNCONNECTED
## signal (Character._ready, which wires it, never ran), and the held-mesh build needs the in-tree muzzle rig.

const RANGED_PATH := "res://scripts/npc/npc.gd"
const PISTOL := preload("res://resources/weapons/pistol.tres")
## The SHIPPED backpack-grid tuning (real dims, not the .gd defaults) — NPCs are hard-capped to the same
## grid the player carries (NPC._ready enable_grid), so a normal NPC loadout must fit it or the overflow is
## kept-but-unplaced and never renders in the loot screen. test_npc_loadout_fits_the_shipped_grid guards that.
const INVENTORY_SETTINGS := preload("res://resources/tuning/InventorySettings.tres")


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
	# The oracle is the SHIPPED knob _equip_initial_weapon reads (GameSettings.npc_ai, the .tres), not the .gd default.
	var clips: int = GameSettings.npc_ai.starting_clips
	assert_gt(clips, 0, "shipped NpcAiSettings.starting_clips must be positive or every combatant spawns with no reserve and no ammo loot")
	assert_eq(inv.ammo_count(&"pistol"), clips,
		"It also stashes its starting clips (combat reserve + corpse loot) of the weapon's caliber")
	inv.free()
	n.free()


func test_is_armed_tracks_equipped_weapon_item() -> void:
	# An NPC wields its gun ONLY while the equipped weapon-item is in its backpack — so pickpocketing the
	# weapon out (which clears equipped_item) disarms it and it stops drawing/firing the gun.
	var n: NPC = load(RANGED_PATH).new()
	n.inventory = CharacterInventory.new()
	assert_false(n.is_armed(),
		"no equipped weapon item -> unarmed (a civilian, or a combatant stripped of its gun)")
	var witem := ItemDb.make_weapon_item(PISTOL)
	n.inventory.add(witem)
	n.inventory.equip_item(witem)  # marks equipped_item (the signal is unwired off-tree; the marker still sets)
	assert_true(n.is_armed(),
		"with the weapon item equipped + in the backpack -> armed")
	n.inventory.remove(witem)  # pickpocketed out -> remove() clears equipped_item
	assert_false(n.is_armed(),
		"pickpocketing the weapon out (equipped_item cleared) -> disarmed, so it fights unarmed")
	n.inventory.free()
	n.free()


func test_can_wield_weapons_is_the_hub_not_the_held_gun() -> void:
	# Cross-system contract: LootScreen._plant_target_cannot_wield duck-types can_wield_weapons() off the
	# deposit receiver to warn when you PLANT a gun on an NPC that can never use it (a hub-less civilian).
	# The rule is "has a weapon HUB", deliberately NOT is_armed(): a DISARMED combatant (gun pickpocketed) must still
	# report it can wield, because it re-arms from the backpack on its next combat tick -- warning there would lie.
	var n: NPC = load(RANGED_PATH).new()  # no add_child: _ready never builds the hub -> _weapon stays null
	n.inventory = CharacterInventory.new()
	assert_false(n.can_wield_weapons(),
		"a civilian NPC (no weapon hub) reports it can't wield -> planting a weapon on it warns the player")
	var hub := Weapon.new()  # bare Node3D stand-in for the hub _ready builds only for a combatant (weapon_data set)
	n._weapon = hub
	assert_false(n.is_armed(), "precondition: the combatant holds no weapon item (it was disarmed)")
	assert_true(n.can_wield_weapons(),
		"a DISARMED combatant with a weapon hub still reports it CAN wield -> no futile-plant warning, it re-arms from the backpack")
	var witem := ItemDb.make_weapon_item(PISTOL)
	n.inventory.add(witem)
	n.inventory.equip_item(witem)
	assert_true(n.is_armed() and n.can_wield_weapons(), "an armed combatant can wield too")
	hub.free()
	n.inventory.free()
	n.free()


func test_ensure_armed_equips_a_backpack_weapon() -> void:
	# A disarmed NPC handed a weapon (the player deposits one via the loot/pickpocket transfer) draws it on
	# its next combat tick — _ensure_armed_from_backpack marks equipped_item, so it's armed again. (Off-tree
	# the equip signal is unwired, so this checks the backpack-side marker; the actual draw is manual-verify.)
	var n: NPC = load(RANGED_PATH).new()
	n.inventory = CharacterInventory.new()
	assert_false(n.is_armed(), "precondition: nothing equipped -> disarmed")
	n.inventory.add(ItemDb.make_weapon_item(PISTOL))
	n._ensure_armed_from_backpack()
	assert_true(n.is_armed(),
		"a weapon sitting in the backpack is auto-equipped -> a re-armed NPC fights with the gun it was given")
	n.inventory.free()
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


func test_on_equip_weapon_requested_routes_to_the_hub_and_is_null_safe_without_one() -> void:
	# The backpack's equip request lands on the weapon hub's Inventory (what the NPC actually fires). Before a hub
	# exists -- or while the hub has no Inventory child yet -- the same call must be a guarded no-op: an unguarded
	# dereference raises a script error, which GUT fails on. A stray WeaponData (no view model) keeps the held-mesh
	# rebuild a no-op off-tree, so only the routing is observed.
	var stray := WeaponData.new()
	var n: NPC = load(RANGED_PATH).new()  # no add_child: _weapon stays null
	n._on_equip_weapon_requested(stray)   # no hub at all -> guarded
	var hub := Weapon.new()
	n._weapon = hub
	n._on_equip_weapon_requested(stray)   # a hub with no Inventory yet -> guarded
	assert_null(hub.inventory, "the guarded call must not conjure an Inventory onto the hub")
	# Control: the same request with a wired Inventory reaches the hub.
	var hub_inv := Inventory.new()
	hub.inventory = hub_inv
	n._on_equip_weapon_requested(stray)
	assert_eq(hub_inv.equipped_weapon, stray,
		"with a hub + Inventory the requested weapon is equipped on the hub -> a disarmed NPC handed a gun fires THAT gun")
	hub_inv.free()
	hub.free()
	n.free()
	stray = null


func test_npc_equip_bridge_method_surface() -> void:
	var n: NPC = load(RANGED_PATH).new()  # no add_child
	assert_true(n.has_method("_equip_initial_weapon"),
		"NPC must define _equip_initial_weapon() — seeds + draws the assigned weapon from the backpack")
	assert_true(n.has_method("_on_equip_weapon_requested"),
		"NPC must override _on_equip_weapon_requested() — routes a backpack equip to its weapon hub")
	n.free()


func test_npc_loadout_fits_the_shipped_grid() -> void:
	# NPCs are hard-capped to the player's backpack grid at spawn (NPC._ready enable_grid, deferred so seeding runs
	# unbounded first, then clamps). That only stays loot-safe if the shipped grid is big enough for a normal NPC
	# loadout — an overflow stack is KEPT but left unplaced, and an unplaced stack never renders in the loot screen,
	# so a corpse could hide a gun the player watched the NPC carry. Guard the shipped tuning against a representative
	# loaded NPC (drawn gun + a spare + reserve ammo + a handful of 1×1 carried items). If a designer shrinks the
	# grid or bloats a loadout past this, it fails HERE instead of silently swallowing loot in game.
	var inv := CharacterInventory.new()
	inv.add(ItemDb.make_weapon_item(PISTOL))            # the drawn weapon (a UNIQUE item, real authored footprint)
	inv.add(ItemDb.make_weapon_item(PISTOL))            # a spare gun (raiders often carry two)
	var ammo := ItemDb.ammo_item_for(&"pistol")
	if ammo != null:
		inv.add(ammo, GameSettings.npc_ai.starting_clips)  # the SHIPPED reserve ammo, exactly like _equip_initial_weapon
	for i in 5:
		inv.add(_junk_item("carried_%d" % i))          # keycards / stims / trinkets — 1×1 carried loot
	# Seed unbounded, THEN clamp — the NPC._ready order — and assert every stack found a home in the shipped grid.
	inv.enable_grid(INVENTORY_SETTINGS.grid_cols, INVENTORY_SETTINGS.grid_rows)
	var unplaced := 0
	for row in inv.placed_contents():
		if int(row["x"]) < 0:
			unplaced += 1
	assert_eq(unplaced, 0,
		"a representative NPC loadout must fully place in the shipped %dx%d character grid — else its overflow is unlootable"
			% [INVENTORY_SETTINGS.grid_cols, INVENTORY_SETTINGS.grid_rows])
	inv.free()


## A minimal 1×1 stackless carried item (a keycard / stim stand-in) with a distinct id so it doesn't merge.
func _junk_item(id: String) -> Item:
	var it := Item.new()
	it.id = StringName(id)
	it.grid_width = 1
	it.grid_height = 1
	it.max_stack = 1
	return it
