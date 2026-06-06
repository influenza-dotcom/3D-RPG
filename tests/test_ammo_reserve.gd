extends GutTest
## Reserve-ammo reload (ammo phase B). GUT unit suite.
##
## Ammo is built off-tree via .new() WITHOUT add_child (its _ready null-derefs an unset `inventory`, so it
## can never enter the tree bare — same convention as test_combat_data's Ammo tests). We set current_weapon
## / character / current_ammo directly and drive reload() to exercise the reserve math. The wielder is a
## real Player / NPC built off-tree (no _ready) so the `character is Player` gate resolves correctly, with
## a manual backpack standing in for the one Character._ready would build.

const NINE := &"9mm"


func _player_with_bag() -> Player:
	var p: Player = load("res://scripts/player/player.gd").new()
	p.inventory = CharacterInventory.new()
	return p


func _calibered_weapon(max_ammo: int, caliber: StringName) -> WeaponData:
	var w := WeaponData.new()
	w.max_ammo = max_ammo
	w.caliber = caliber
	return w


func test_reload_pulls_from_reserve_for_player_weapon() -> void:
	var ammo := Ammo.new()
	var player := _player_with_bag()
	ammo.character = player
	var w := _calibered_weapon(10, NINE)
	ammo.current_weapon = w
	ammo.current_ammo = 2
	player.inventory.add(ItemDb.ammo_item_for(NINE), 30)
	assert_true(ammo.has_reload_supply(),
		"with 9mm in the reserve, the pistol can reload")
	ammo.reload()
	assert_eq(ammo.current_ammo, 10,
		"reload seats a fresh full magazine from the reserve")
	assert_eq(player.inventory.ammo_count(NINE), 20,
		"a full clip (10) is drawn from the reserve (30 - 10)")
	ammo.free()
	player.inventory.free()
	player.free()
	w = null


func test_reload_discards_partial_clip() -> void:
	# Magazine reload: the rounds left in the ejected clip are LOST (not returned to reserve), replaced by
	# a fresh clip drawn from the reserve.
	var ammo := Ammo.new()
	var player := _player_with_bag()
	ammo.character = player
	var w := _calibered_weapon(10, NINE)
	ammo.current_weapon = w
	ammo.current_ammo = 7  # a partial clip
	player.inventory.add(ItemDb.ammo_item_for(NINE), 30)
	ammo.reload()
	assert_eq(ammo.current_ammo, 10,
		"the seated clip is full")
	assert_eq(player.inventory.ammo_count(NINE), 20,
		"exactly one full clip (10) is drawn from the reserve")
	assert_eq(ammo.current_ammo + player.inventory.ammo_count(NINE), 30,
		"total rounds dropped from 37 (7 clip + 30 reserve) to 30 — the 7 in the ejected clip are LOST")
	ammo.free()
	player.inventory.free()
	player.free()
	w = null


func test_reload_partial_when_reserve_low() -> void:
	var ammo := Ammo.new()
	var player := _player_with_bag()
	ammo.character = player
	var w := _calibered_weapon(10, NINE)
	ammo.current_weapon = w
	ammo.current_ammo = 0
	player.inventory.add(ItemDb.ammo_item_for(NINE), 3)  # only 3 rounds in reserve
	ammo.reload()
	assert_eq(ammo.current_ammo, 3,
		"a low reserve only partially fills the clip")
	assert_eq(player.inventory.ammo_count(NINE), 0,
		"the reserve is emptied into the clip")
	ammo.free()
	player.inventory.free()
	player.free()
	w = null


func test_no_reserve_means_no_reload_supply() -> void:
	var ammo := Ammo.new()
	var player := _player_with_bag()
	ammo.character = player
	var w := _calibered_weapon(10, NINE)
	ammo.current_weapon = w
	ammo.current_ammo = 0
	assert_false(ammo.has_reload_supply(),
		"no matching reserve -> can't reload (attack plays a dry click instead)")
	ammo.reload()
	assert_eq(ammo.current_ammo, 0,
		"a reload with no reserve loads nothing")
	ammo.free()
	player.inventory.free()
	player.free()
	w = null


func test_caliberless_weapon_reloads_free() -> void:
	# A caliber-less weapon (melee / rock / spray) always refills to max for free, even with no reserve.
	var ammo := Ammo.new()
	var player := _player_with_bag()
	ammo.character = player
	var w := _calibered_weapon(5, &"")
	ammo.current_weapon = w
	ammo.current_ammo = 0
	assert_true(ammo.has_reload_supply(),
		"a caliber-less weapon can always reload")
	ammo.reload()
	assert_eq(ammo.current_ammo, 5,
		"a caliber-less weapon free-fills to max")
	ammo.free()
	player.inventory.free()
	player.free()
	w = null


func test_ai_wielder_reloads_free_ignoring_reserve() -> void:
	# An NPC wielder (not the Player) refills free even for a calibered weapon with an empty reserve, so
	# enemies never run dry — the reserve gate is player-only by design.
	var ammo := Ammo.new()
	var npc: NPC = load("res://scripts/npc/npc.gd").new()
	npc.inventory = CharacterInventory.new()  # empty reserve
	ammo.character = npc
	var w := _calibered_weapon(8, NINE)
	ammo.current_weapon = w
	ammo.current_ammo = 0
	assert_true(ammo.has_reload_supply(),
		"an AI wielder always has reload supply (free refill)")
	ammo.reload()
	assert_eq(ammo.current_ammo, 8,
		"an AI wielder free-fills to max, ignoring the reserve")
	ammo.free()
	npc.inventory.free()
	npc.free()
	w = null
