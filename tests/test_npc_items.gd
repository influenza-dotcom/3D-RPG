extends GutTest

## NPC item intelligence (round 8): weapon ranking (power_score / best_weapon_item), the equip-the-strongest
## draw (_ensure_armed_from_backpack), the low-HP medkit reflex (now the SelfHealer drop-in, driven against a
## bare NPC here), and the healing-consumable lookup the reflex uses. The container-raid walk (NpcScavenge.act)
## is in-tree behaviour — playtested — but
## its off-tree no-op safety is pinned so the state machine can never crash on a bare NPC.
## Also pins the ranking's SPRAY PAINT exclusion: the can's raw power_score outguns real guns while its fire
## path (Attack._do_spray_paint) deals zero damage, so an AI must never draw it as its "best" weapon.

const NPC_PATH := "res://scripts/npc/npc.gd"


func _weapon_item(dmg: float, speed: float = 0.5) -> Item:
	var it := Item.new()
	it.category = Item.Category.WEAPON
	it.weapon = WeaponData.new()
	it.weapon.damage = dmg
	it.weapon.attack_speed = speed
	return it


## A stand-in with the SHIPPED spray_paint.tres combat numbers — the exact stats whose raw power_score
## (0.1 x 8 / 0.15 = 5.33) outranks every real gun on the roster, which is what made the bug reachable.
func _spray_paint_item() -> Item:
	var it := Item.new()
	it.category = Item.Category.WEAPON
	it.weapon = WeaponData.new()
	it.weapon.damage = 0.1
	it.weapon.pellet_count = 8
	it.weapon.attack_speed = 0.15
	it.weapon.is_spray_paint = true
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


func test_spray_paint_never_ranks_above_a_real_gun() -> void:
	var inv := CharacterInventory.new()
	var spray := _spray_paint_item()
	var pistol := _weapon_item(0.5, 0.22)  # the shipped pistol's ballpark: score ~2.27, well UNDER the can's 5.33
	assert_gt(spray.weapon.power_score(), pistol.weapon.power_score(),
		"precondition: the can's RAW power_score really does outgun the pistol — the ordering the exclusion exists to override")
	inv.add(spray, 1)
	inv.add(pistol, 1)
	assert_eq(inv.best_weapon_item(), pistol,
		"the AI equip ranking must skip spray paint (its fire path is the damage-free _do_spray_paint short-circuit) and pick the real gun")
	inv.free()
	spray = null
	pistol = null


func test_bag_of_only_spray_paint_ranks_as_unarmed() -> void:
	var inv := CharacterInventory.new()
	var spray := _spray_paint_item()
	inv.add(spray, 1)
	assert_null(inv.best_weapon_item(),
		"a bag holding ONLY spray paint has no best weapon — the NPC stays on fists (real damage) and NpcScavenge still sees it as unarmed, so it loots a real gun")
	inv.free()
	spray = null


func test_shipped_spray_paint_tres_carries_the_flag_the_ranking_filters_on() -> void:
	# Contract pin against the AUTHORED resource: the exclusion keys on is_spray_paint, so if a rework of
	# spray_paint.tres ever dropped the flag, NPCs looting the real can (LootScreen deposit / scavenged
	# crate) would silently start drawing it again. Read-only — never mutate the cached shared resource.
	var spray_w: WeaponData = load("res://resources/weapons/spray_paint.tres")
	assert_not_null(spray_w, "the shipped spray-paint WeaponData loads")
	assert_true(spray_w.is_spray_paint,
		"spray_paint.tres must keep is_spray_paint = true — it is both the damage-free fire short-circuit AND the AI ranking exclusion")


func test_melee_weapons_still_rank_for_ai_equip() -> void:
	# The exclusion must stay spray-paint-only: act_alerted supports melee (the engage range scales to the
	# weapon and the point-blank override lets a crowding attacker swing), so a knife-armed NPC closes and
	# lands REAL damage — short reach is not the zero-damage problem the spray can has.
	var inv := CharacterInventory.new()
	var knife := _weapon_item(1.0, 0.5)
	knife.weapon.is_melee = true
	inv.add(knife, 1)
	assert_eq(inv.best_weapon_item(), knife,
		"a melee weapon still ranks as a best weapon — only spray paint is excluded from AI equip ranking")
	inv.free()
	knife = null


func test_ensure_armed_never_draws_spray_paint_over_a_gun() -> void:
	# The reachable bug path end-to-end: a LootScreen deposit / gear exchange (or a scavenged crate) puts a
	# spray can in a live NPC's bag, and the disarmed-NPC rearm draws the bag's "strongest". The can's raw
	# score outguns the pistol, but equipping it means ZERO combat damage — the rearm must take the gun.
	var n = load(NPC_PATH).new()
	n.inventory = CharacterInventory.new()
	var spray := _spray_paint_item()
	var gun := _weapon_item(0.5, 0.22)
	n.inventory.add(spray, 1)  # added FIRST and scoring HIGHER — the unfiltered ranking would draw this
	n.inventory.add(gun, 1)
	n._ensure_armed_from_backpack()
	assert_eq(n.inventory.equipped_item, gun,
		"an NPC rearming from its backpack must never wield the zero-damage spray can over a real gun")
	n.inventory.free()
	n.free()
	spray = null
	gun = null


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
	# The medkit reflex now lives in the SelfHealer drop-in (self_healer.gd) — auto-built on a live NPC, but
	# here we drive one directly against a BARE NPC (off-tree, no _ready) so the NPC.inventory/heal integration
	# is exercised. The component's own gates (threshold/cooldown/enabled) are unit-tested in test_self_healer.gd.
	var n = load(NPC_PATH).new()
	n.inventory = CharacterInventory.new()
	n.max_hp = 100.0
	n.hp = 30.0  # below the 0.5 heal fraction (the SelfHealer default, matching the old global)
	var kit := _medkit(30.0)
	n.inventory.add(kit, 2)
	var healer := SelfHealer.new()  # defaults: heal_at_hp_frac 0.5, cooldown_ms 4000 (the seeded values)
	healer.react(n)
	assert_almost_eq(n.hp, 60.0, 0.0001, "a hurt NPC chugs a carried medkit (rules b/d)")
	assert_eq(n.inventory.count_of(kit), 1, "one medkit is consumed")
	healer.react(n)
	assert_eq(n.inventory.count_of(kit), 1, "the cooldown blocks an immediate second chug")
	healer._last_heal_msec = -100000  # cooldown elapsed
	n.hp = 90.0  # above the threshold
	healer.react(n)
	assert_eq(n.inventory.count_of(kit), 1, "a lightly-scratched NPC saves its medkits")
	healer.free()
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
