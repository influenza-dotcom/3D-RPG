extends GutTest

## Loadout (Wave 0) — the player's starting loadout as data (weapons + clips + money), an OPTIONAL override
## of SwapWeapons.weapon_slots + the player's defaults. Everything is built off-tree with no _ready: a bare
## SwapWeapons, a bare Weapon (weapon_system.gd) holding it under the "SwapWeapons" name it looks up, and a bare
## Player whose _starting_clips_per_caliber() reads the Loadout through weapon_system.loadout() exactly as its
## backpack seed does in play. The authored weapon_slots are POPULATED in every fallback test, so "fell back to
## the authored kit" can never pass by comparing an empty list with an empty list.

const PISTOL_PATH := "res://resources/weapons/pistol.tres"
const MELEE_PATH := "res://resources/weapons/melee.tres"
const PLAYER_SOURCE := "res://scripts/player/player.gd"


## A SwapWeapons whose designer-authored slots hold `kit` (the typed Array[Resource] the inspector writes).
func _swap_with_slots(kit: Array) -> SwapWeapons:
	var sw := SwapWeapons.new()
	var slots: Array[Resource] = []
	for w in kit:
		slots.append(w)
	sw.weapon_slots = slots
	return sw


## A code-built Loadout whose weapons list is `kit`.
func _loadout_with(kit: Array) -> Loadout:
	var ld := Loadout.new()
	var weapons: Array[WeaponData] = []
	for w in kit:
		weapons.append(w)
	ld.weapons = weapons
	return ld


## A bare Weapon component carrying `sw` under the child name weapon_loadout() / loadout() resolve.
func _weapon_system_with(sw: SwapWeapons) -> Weapon:
	var ws := Weapon.new()
	sw.name = "SwapWeapons"
	ws.add_child(sw)
	return ws


func test_no_loadout_returns_the_authored_weapon_slots() -> void:
	var melee: WeaponData = load(MELEE_PATH)
	var sw := _swap_with_slots([melee])
	var slots := sw.effective_slots()
	assert_eq(slots.size(), 1,
		"with no Loadout assigned, the player's starting kit must be the weapons authored on the SwapWeapons node")
	assert_true(slots.size() == 1 and slots[0] == melee,
		"with no Loadout assigned, slot 1 must be the authored weapon, or the designer's kit never reaches the backpack")
	sw.free()


func test_loadout_with_no_weapons_falls_back_to_the_authored_slots() -> void:
	# A Loadout assigned only to tune clips/money has an EMPTY weapons list. It must not wipe the authored kit.
	var melee: WeaponData = load(MELEE_PATH)
	var sw := _swap_with_slots([melee])
	sw.loadout = Loadout.new()
	var slots := sw.effective_slots()
	assert_eq(slots.size(), 1,
		"a Loadout with no weapons must fall back to the authored slots; returning its empty list spawns the player empty-handed")
	assert_true(slots.size() == 1 and slots[0] == melee,
		"the fallback must hand back the authored weapon itself, not some other list")
	sw.free()


func test_loadout_weapons_replace_the_authored_slots() -> void:
	var melee: WeaponData = load(MELEE_PATH)
	var pistol: WeaponData = load(PISTOL_PATH)
	var sw := _swap_with_slots([melee])
	var ld := _loadout_with([pistol])
	sw.loadout = ld
	var slots := sw.effective_slots()
	assert_eq(slots.size(), 1,
		"a Loadout's weapons REPLACE the authored slots; they must not be appended to them")
	assert_true(slots.size() == 1 and slots[0] == pistol,
		"slot 1 must be the Loadout's weapon when a non-empty Loadout is assigned")
	assert_false(slots.has(melee), "the authored weapon must not leak into a Loadout-driven kit")
	# Emptying the Loadout's list later hands the authored kit back (a blank Loadout is a no-op for weapons).
	var empty: Array[WeaponData] = []
	ld.weapons = empty
	var after := sw.effective_slots()
	assert_true(after.size() == 1 and after[0] == melee,
		"once the Loadout's weapons are cleared, the authored slots must come back instead of an empty kit")
	sw.free()
	ld = null


func test_weapon_system_seeds_the_backpack_from_the_loadout_kit() -> void:
	# weapon_loadout() is what Player._seed_starting_inventory reads; it must honour the Loadout override.
	var melee: WeaponData = load(MELEE_PATH)
	var pistol: WeaponData = load(PISTOL_PATH)
	var sw := _swap_with_slots([melee])
	var ws := _weapon_system_with(sw)
	var control := ws.weapon_loadout()
	assert_true(control.size() == 1 and control[0] == melee,
		"control: with no Loadout the weapon component reports the authored slots")
	var ld := _loadout_with([pistol])
	sw.loadout = ld
	var kit := ws.weapon_loadout()
	assert_true(kit.size() == 1 and kit[0] == pistol,
		"with a Loadout assigned, the kit the player's backpack is seeded from must be the Loadout's weapons, not the authored slots")
	assert_true(ws.loadout() == ld,
		"the weapon component must expose the assigned Loadout so the Player can read its clips and money")
	ws.free()
	ld = null


func test_weapons_only_loadout_keeps_the_players_default_clip_count() -> void:
	var pistol: WeaponData = load(PISTOL_PATH)
	var p = load(PLAYER_SOURCE).new()  # off-tree: no _ready
	var sw := SwapWeapons.new()
	var ws := _weapon_system_with(sw)
	p.weapon_system = ws
	var no_loadout_clips: int = p._starting_clips_per_caliber()
	assert_gt(no_loadout_clips, 0, "control: the no-loadout player starts with some spare clips per caliber")
	# A kit authored only to pick the starting WEAPONS leaves starting_clips_per_caliber at its default.
	var ld := _loadout_with([pistol])
	sw.loadout = ld
	var kit_clips: int = p._starting_clips_per_caliber()
	assert_eq(kit_clips, no_loadout_clips,
		"opting into a Loadout for its weapons must not silently change the player's spare-clip reserve: the Loadout default must match the player's own default")
	ld.starting_clips_per_caliber = no_loadout_clips + 3
	var authored_clips: int = p._starting_clips_per_caliber()
	assert_eq(authored_clips, no_loadout_clips + 3,
		"a Loadout's authored clips-per-caliber must override the player's default when the player seeds its reserve")
	p.free()
	ws.free()
	ld = null


func test_default_loadout_purse_is_a_valid_starting_wallet() -> void:
	# Player._ready copies a Loadout's money straight into the wallet with no snap, so the default purse must
	# already be a legal wallet: never negative (GameState's legacy fold reads negative cash as pre-ATM debt and
	# moves it onto the account) and on the smallest-coin grid every wallet lands on.
	var ld := Loadout.new()
	assert_true(ld.money >= 0.0,
		"a default Loadout purse must not be negative, or a fresh run would start in debt")
	assert_almost_eq(ld.money, snappedf(ld.money, Zorkmids.QUANTUM), 0.0001,
		"a default Loadout purse must be a whole number of the smallest coin, since the loadout copy path skips add_money's snap")
	ld = null
