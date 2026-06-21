extends GutTest

## ML-4: the difficulty mults applied at the seams. Every mult is inert at the 1.0 default (Normal), so the rest
## of the suite is unaffected; here we set a non-1.0 mult, verify the seam scales, and RESTORE the shared
## GameSettings.difficulty autoload after (it's a global). The damage-in/out + kill-bounty seams are player-gated
## in-tree paths (playtested at the default); the spawn-count + loot-count math is pure enough to pin here.

var _saved := {}

func before_each() -> void:
	var d = GameSettings.difficulty
	_saved = {"enemy": d.enemy_count_mult, "loot": d.loot_mult}

func after_each() -> void:
	var d = GameSettings.difficulty
	d.enemy_count_mult = _saved.get("enemy", 1.0)
	d.loot_mult = _saved.get("loot", 1.0)


func test_enemy_count_scales_with_difficulty() -> void:
	var s := EncounterSpawner.new()
	GameSettings.difficulty.enemy_count_mult = 1.0
	assert_eq(s._scaled_count(3), 3, "Normal (1.0) leaves the authored count")
	GameSettings.difficulty.enemy_count_mult = 2.0
	assert_eq(s._scaled_count(3), 6, "a denser difficulty doubles the wave")
	GameSettings.difficulty.enemy_count_mult = 0.5
	assert_eq(s._scaled_count(3), 2, "a thinner difficulty reduces it (round(1.5) = 2)")
	assert_eq(s._scaled_count(1), 1, "...but never empties an authored wave (floored at 1)")
	assert_eq(s._scaled_count(0), 0, "an empty def stays empty")
	s.free()


func test_loot_count_scales_with_difficulty() -> void:
	var t := LootTable.new()
	var ammo := Item.new()
	ammo.id = &"ammo9mm"
	ammo.max_stack = 99
	var e := LootEntry.new()
	e.item = ammo
	e.chance = 1.0
	e.min_count = 4
	e.max_count = 4
	var es: Array[LootEntry] = [e]
	t.entries = es
	GameSettings.difficulty.loot_mult = 2.0
	var inv := CharacterInventory.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	t.grant(inv, rng)
	assert_eq(inv.count_of(ammo), 8, "loot_mult 2.0 doubles a count-4 drop to 8")
	inv.free()
	t = null
	ammo = null
	e = null
