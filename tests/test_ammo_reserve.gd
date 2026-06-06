extends GutTest
## Reserve-ammo reload (ammo phase B). GUT unit suite.
##
## Ammo is built off-tree via .new() WITHOUT add_child (its _ready null-derefs an unset `inventory`, so it
## can never enter the tree bare — same convention as test_combat_data's Ammo tests). We set current_weapon
## / character / current_ammo directly and drive reload() to exercise the reserve math. The wielder is a
## real Player / NPC built off-tree (no _ready) so the `character is Player` gate resolves correctly, with
## a manual backpack standing in for the one Character._ready would build.

const CAL := &"pistol"


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
	var w := _calibered_weapon(10, CAL)
	ammo.current_weapon = w
	ammo.current_ammo = 2
	player.inventory.add(ItemDb.ammo_item_for(CAL), 3)  # 3 spare clips
	assert_true(ammo.has_reload_supply(),
		"with spare pistol clips, the pistol can reload")
	ammo.reload()
	assert_eq(ammo.current_ammo, 10,
		"reload seats a fresh FULL magazine (max_ammo)")
	assert_eq(player.inventory.ammo_count(CAL), 2,
		"exactly one spare clip is spent (3 - 1)")
	ammo.free()
	player.inventory.free()
	player.free()
	w = null


func test_reload_discards_partial_clip() -> void:
	# Magazine reload: reloading a non-empty mag still spends a WHOLE spare clip and the rounds left in the
	# ejected mag are LOST — a tactical reload wastes both the partial mag and a full clip.
	var ammo := Ammo.new()
	var player := _player_with_bag()
	ammo.character = player
	var w := _calibered_weapon(10, CAL)
	ammo.current_weapon = w
	ammo.current_ammo = 7  # a partial magazine
	player.inventory.add(ItemDb.ammo_item_for(CAL), 3)  # 3 spare clips
	ammo.reload()
	assert_eq(ammo.current_ammo, 10,
		"the seated magazine is full (a clip is always a full mag)")
	assert_eq(player.inventory.ammo_count(CAL), 2,
		"reloading spends a whole spare clip (3 - 1) even though the mag wasn't empty")
	ammo.free()
	player.inventory.free()
	player.free()
	w = null


func test_reload_one_clip_seats_full_magazine() -> void:
	var ammo := Ammo.new()
	var player := _player_with_bag()
	ammo.character = player
	var w := _calibered_weapon(10, CAL)
	ammo.current_weapon = w
	ammo.current_ammo = 0
	player.inventory.add(ItemDb.ammo_item_for(CAL), 1)  # one spare clip
	ammo.reload()
	assert_eq(ammo.current_ammo, 10,
		"a clip is a whole magazine: even one spare clip seats a FULL mag")
	assert_eq(player.inventory.ammo_count(CAL), 0,
		"the single spare clip is spent")
	ammo.free()
	player.inventory.free()
	player.free()
	w = null


func test_no_reserve_means_no_reload_supply() -> void:
	var ammo := Ammo.new()
	var player := _player_with_bag()
	ammo.character = player
	var w := _calibered_weapon(10, CAL)
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
	var w := _calibered_weapon(8, CAL)
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
