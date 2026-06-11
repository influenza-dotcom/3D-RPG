extends GutTest

## NPC item intelligence (round 8): weapon ranking (power_score / best_weapon_item), the equip-the-strongest
## draw (_ensure_armed_from_backpack), the low-HP medkit reflex (_try_use_medkit), and the healing-consumable
## lookup the reflex uses. The container-raid walk (NpcScavenge.act) is in-tree behaviour — playtested — but
## its off-tree no-op safety is pinned so the state machine can never crash on a bare NPC.

const NPC_PATH := "res://scripts/npc/npc.gd"


func _weapon_item(dmg: float, speed: float = 0.5) -> Item:
	var it := Item.new()
	it.category = Item.Category.WEAPON
	it.weapon = WeaponData.new()
	it.weapon.damage = dmg
	it.weapon.attack_speed = speed
	return it


func _medkit(heal: float = 30.0) -> Item:
	var it := Item.new()
	it.category = Item.Category.CONSUMABLE
	it.heal_amount = heal
	it.max_stack = 5
	return it


func test_power_score_orders_weapons() -> void:
	var pistol := WeaponData.new()
	pistol.damage = 5.0
	pistol.attack_speed = 0.5
	var sniper := WeaponData.new()
	sniper.damage = 40.0
	sniper.attack_speed = 1.5
	assert_gt(sniper.power_score(), pistol.power_score(),
		"a heavy-hitting rifle outranks a pistol even at a slower cadence")
	assert_almost_eq(pistol.power_score(), 10.0, 0.0001, "score = damage x pellets / cadence (5 / 0.5)")


func test_best_weapon_item_picks_the_strongest() -> void:
	var inv := CharacterInventory.new()
	assert_null(inv.best_weapon_item(), "an unarmed bag has no best weapon")
	var weak := _weapon_item(5.0)
	var strong := _weapon_item(25.0)
	inv.add(weak, 1)
	inv.add(strong, 1)
	inv.add(_medkit(), 1)  # non-weapons are ignored by the ranking
	assert_eq(inv.best_weapon_item(), strong, "the strongest carried weapon wins the ranking")
	inv.free()
	weak = null
	strong = null


func test_ensure_armed_draws_the_strongest_not_the_first() -> void:
	var n = load(NPC_PATH).new()
	n.inventory = CharacterInventory.new()
	var weak := _weapon_item(5.0)
	var strong := _weapon_item(25.0)
	n.inventory.add(weak, 1)    # added FIRST — the old code would have drawn this
	n.inventory.add(strong, 1)
	n._ensure_armed_from_backpack()
	assert_eq(n.inventory.equipped_item, strong,
		"a disarmed NPC re-arms with the STRONGEST carried weapon, not the first stack found (rule c)")
	n.inventory.free()
	n.free()
	weak = null
	strong = null


func test_find_healing_consumable_skips_non_healers() -> void:
	var inv := CharacterInventory.new()
	var junk := Item.new()
	junk.category = Item.Category.CONSUMABLE  # consumable but heals nothing
	inv.add(junk, 1)
	assert_null(inv.find_healing_consumable(), "a no-effect consumable isn't a medkit")
	var kit := _medkit(35.0)
	inv.add(kit, 1)
	assert_eq(inv.find_healing_consumable(), kit, "a heal_amount consumable is what a hurt NPC reaches for")
	inv.free()
	junk = null
	kit = null


func test_npc_medkit_reflex_heals_consumes_and_throttles() -> void:
	var n = load(NPC_PATH).new()
	n.inventory = CharacterInventory.new()
	n.max_hp = 100.0
	n.hp = 30.0  # below MEDKIT_HP_FRAC (0.5)
	var kit := _medkit(30.0)
	n.inventory.add(kit, 2)
	n._try_use_medkit()
	assert_almost_eq(n.hp, 60.0, 0.0001, "a hurt NPC chugs a carried medkit (rules b/d)")
	assert_eq(n.inventory.count_of(kit), 1, "one medkit is consumed")
	n._try_use_medkit()
	assert_eq(n.inventory.count_of(kit), 1, "the cooldown blocks an immediate second chug")
	n._last_medkit_msec = -100000  # cooldown elapsed
	n.hp = 90.0  # above the threshold
	n._try_use_medkit()
	assert_eq(n.inventory.count_of(kit), 1, "a lightly-scratched NPC saves its medkits")
	n.inventory.free()
	n.free()
	kit = null


func test_scavenge_is_offtree_safe() -> void:
	# Off-tree (no SceneTree) act() must simply report "not scavenging" — the state machine's
	# `if not _scavenge.act(delta)` fall-through to _idle can never crash on a bare NPC.
	var n = load(NPC_PATH).new()
	var sc := NpcScavenge.new()
	sc.host = n
	assert_false(sc.act(0.016), "no tree -> no scavenging, no crash")
	sc.free()
	n.free()
