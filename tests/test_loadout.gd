extends GutTest

## Loadout (Wave 0) — the player's starting loadout as data (weapons + clips + money), an OPTIONAL override
## of SwapWeapons.weapon_slots + the player's defaults. Off-tree: SwapWeapons.new() (no _ready) + a code-built
## Loadout; effective_slots() reads only its members. The .tres is authored in-editor (which sidesteps the
## typed-Array[WeaponData] serialization quirk), so this covers the class + the override seam.


func test_loadout_defaults_match_player_defaults() -> void:
	var ld := Loadout.new()
	assert_eq(ld.weapons.size(), 0, "a fresh Loadout has no weapons -> falls back to the authored slots")
	assert_eq(ld.starting_clips_per_caliber, 4, "default clips-per-caliber 4 matches the player's current default")
	assert_eq(ld.money, 100, "default money 100 matches the player's current default")
	ld = null


func test_no_loadout_falls_back_to_weapon_slots() -> void:
	var sw := SwapWeapons.new()
	assert_gt(sw.effective_slots().size(), 0, "with no loadout, effective_slots() falls back to the authored weapon_slots")
	sw.free()


func test_loadout_weapons_override_the_slots() -> void:
	var sw := SwapWeapons.new()
	var defaults_size := sw.effective_slots().size()
	var ld := Loadout.new()
	var pistol: WeaponData = load("res://resources/weapons/pistol.tres")
	var ws: Array[WeaponData] = [pistol]
	ld.weapons = ws
	sw.loadout = ld
	assert_eq(sw.effective_slots().size(), 1, "an assigned Loadout's weapons REPLACE the default slots")
	assert_eq(sw.effective_slots()[0], pistol, "effective_slots() returns the loadout's weapon")
	# A loadout with NO weapons falls back to the defaults (so a blank loadout is a no-op).
	var empty: Array[WeaponData] = []
	ld.weapons = empty
	assert_eq(sw.effective_slots().size(), defaults_size, "a loadout with no weapons falls back to the authored slots")
	sw.free()
	ld = null
