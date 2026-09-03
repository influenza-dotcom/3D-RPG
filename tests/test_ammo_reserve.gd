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


func test_ai_wielder_uses_reserve_clips() -> void:
	# NPCs now draw from their backpack reserve just like the player (so stripping an enemy of ammo strands
	# it). Empty reserve -> no supply + a reload loads nothing; a spare clip -> a reload seats a full mag and
	# spends the clip.
	var ammo := Ammo.new()
	var npc: NPC = load("res://scripts/npc/npc.gd").new()
	npc.inventory = CharacterInventory.new()  # empty reserve
	ammo.character = npc
	var w := _calibered_weapon(8, CAL)
	ammo.current_weapon = w
	ammo.current_ammo = 0
	assert_false(ammo.has_reload_supply(),
		"an NPC with no spare clips can't reload (it goes dry)")
	ammo.reload()
	assert_eq(ammo.current_ammo, 0,
		"a reload with no reserve loads nothing — even for an NPC now")
	npc.inventory.add(ItemDb.ammo_item_for(CAL), 2)  # two spare clips
	assert_true(ammo.has_reload_supply(),
		"with spare clips in the backpack, the NPC can reload")
	ammo.reload()
	assert_eq(ammo.current_ammo, 8,
		"the NPC seats a fresh full magazine")
	assert_eq(npc.inventory.ammo_count(CAL), 1,
		"the NPC spends exactly one spare clip (2 - 1)")
	ammo.free()
	npc.inventory.free()
	npc.free()
	w = null


# --- The spent-ammo ledger + player-death restore -------------------------------------------------------------
#
# The AMMO half of the player-death encounter reset (NpcHomeReturn.restore_ammo_on_player_death). Under the
# default CHECKPOINT_RESPAWN death mode the world is NOT reloaded, so an enemy's spent ammo would otherwise
# persist for the rest of the session and every retry of a fight would be against a more disarmed enemy.
# What's pinned here is the arithmetic that makes it SAFE: it gives back exactly what was fired, and never
# what the player STOLE.

func test_restore_gives_back_the_clips_reloading_burned() -> void:
	var ammo := Ammo.new()
	var npc: NPC = load("res://scripts/npc/npc.gd").new()
	npc.inventory = CharacterInventory.new()
	ammo.character = npc
	var w := _calibered_weapon(10, CAL)
	ammo.current_weapon = w
	ammo.current_ammo = 10
	npc.inventory.add(ItemDb.ammo_item_for(CAL), 4)  # 4 spare clips, like a spawned combatant
	ammo.current_ammo = 0
	ammo.reload()
	ammo.current_ammo = 0
	ammo.reload()                                     # two magazines burned through
	ammo.current_ammo = 3                             # ...and part-way into the third
	assert_eq(npc.inventory.ammo_count(CAL), 2, "two spare clips are gone (4 - 2)")
	assert_true(ammo.restore_spent_ammo(), "there is spent ammo to give back")
	assert_eq(ammo.current_ammo, 10, "the magazine is topped back up to full")
	assert_eq(npc.inventory.ammo_count(CAL), 4, "both burned clips are back — exactly the spawn loadout")
	ammo.free()
	npc.inventory.free()
	npc.free()
	w = null


func test_restore_never_returns_ammo_the_player_stole() -> void:
	# ⭐THE POINT OF THE LEDGER. Pickpocketing an NPC's ammo to strand it on fists is a real mechanic
	# (npc.gd _can_fight_with_gun), so the restore must never top the backpack back up to a baseline —
	# only clips that were actually SPENT reloading are owed back.
	var ammo := Ammo.new()
	var npc: NPC = load("res://scripts/npc/npc.gd").new()
	npc.inventory = CharacterInventory.new()
	ammo.character = npc
	var w := _calibered_weapon(10, CAL)
	ammo.current_weapon = w
	npc.inventory.add(ItemDb.ammo_item_for(CAL), 4)
	ammo.current_ammo = 0
	ammo.reload()                                       # ONE clip fired off (owed back)
	npc.inventory.take_ammo(CAL, 3)                     # ...and the other three PICKPOCKETED (not owed)
	assert_eq(npc.inventory.ammo_count(CAL), 0, "stripped bare")
	assert_true(ammo.restore_spent_ammo(), "the one burned clip is handed back")
	assert_eq(npc.inventory.ammo_count(CAL), 1,
		"ONLY the clip the reload spent comes back — the stolen three stay stolen")
	ammo.free()
	npc.inventory.free()
	npc.free()
	w = null


func test_restore_is_idempotent_and_reports_no_work_when_nothing_was_spent() -> void:
	# It hands back a debt, not a refill: a second call in a row owes nothing, so a repeated player-death
	# reset can never inflate an NPC's reserve past what it spawned with.
	var ammo := Ammo.new()
	var npc: NPC = load("res://scripts/npc/npc.gd").new()
	npc.inventory = CharacterInventory.new()
	ammo.character = npc
	var w := _calibered_weapon(10, CAL)
	ammo.current_weapon = w
	ammo.current_ammo = 10
	npc.inventory.add(ItemDb.ammo_item_for(CAL), 2)
	assert_false(ammo.restore_spent_ammo(), "an NPC that has fired nothing reports no work done")
	assert_eq(npc.inventory.ammo_count(CAL), 2, "and its reserve is untouched")
	ammo.current_ammo = 0
	ammo.reload()
	assert_true(ammo.restore_spent_ammo(), "the burned clip is owed")
	assert_eq(npc.inventory.ammo_count(CAL), 2, "back to the spawn loadout")
	assert_false(ammo.restore_spent_ammo(), "the debt is settled — a second pass owes nothing")
	assert_eq(npc.inventory.ammo_count(CAL), 2, "so the reserve cannot inflate on repeated deaths")
	ammo.free()
	npc.inventory.free()
	npc.free()
	w = null


func test_restore_refills_a_partly_fired_magazine_with_no_reserve_debt() -> void:
	# Rounds fired out of the mag but never reloaded are still ammo this NPC used. No clip was spent, so
	# nothing is owed to the backpack — but the magazine still comes back full.
	var ammo := Ammo.new()
	var npc: NPC = load("res://scripts/npc/npc.gd").new()
	npc.inventory = CharacterInventory.new()
	ammo.character = npc
	var w := _calibered_weapon(10, CAL)
	ammo.current_weapon = w
	ammo.current_ammo = 10
	npc.inventory.add(ItemDb.ammo_item_for(CAL), 1)
	for _i in 6:
		ammo.consume_ammo()
	assert_eq(ammo.current_ammo, 4, "six rounds fired")
	assert_true(ammo.restore_spent_ammo(), "the fired rounds are given back")
	assert_eq(ammo.current_ammo, 10, "the magazine is full again")
	assert_eq(npc.inventory.ammo_count(CAL), 1, "no clip was spent, so the reserve is unchanged")
	ammo.free()
	npc.inventory.free()
	npc.free()
	w = null


func test_reset_for_reuse_drops_the_ledger() -> void:
	# NpcPool wipes and re-seeds the whole backpack right after this, so a debt carried over from the
	# previous life would pay out as FREE clips on the fresh body's first player-death restore.
	var ammo := Ammo.new()
	var npc: NPC = load("res://scripts/npc/npc.gd").new()
	npc.inventory = CharacterInventory.new()
	ammo.character = npc
	var w := _calibered_weapon(10, CAL)
	ammo.current_weapon = w
	npc.inventory.add(ItemDb.ammo_item_for(CAL), 2)
	ammo.current_ammo = 0
	ammo.reload()
	assert_eq(npc.inventory.ammo_count(CAL), 1, "one clip burned last life")
	ammo.reset_for_reuse()
	assert_false(ammo.restore_spent_ammo(), "the previous life's debt does not survive pool reuse")
	assert_eq(npc.inventory.ammo_count(CAL), 1, "no phantom clip is minted into the re-seeded bag")
	ammo.free()
	npc.inventory.free()
	npc.free()
	w = null
