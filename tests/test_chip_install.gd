extends GutTest

## Microchip UPGRADE CHIPS (Item.installs_ability) + the ChipInstaller mechanic that installs them. Pure logic,
## tested OFF-TREE like test_merchant: ChipInstaller.new() WITHOUT add_child (so _ready never runs — we set
## `stock` / the multipliers by hand) and a bare Player with a hand-set backpack + money. The install tail's
## autosave + toast are already off-tree no-ops (GameState.autosave early-returns off-tree; notify_toast needs a
## `ui`), so a bare-Player install doesn't touch disk. Also pins the 7 authored chip .tres + the mechanic scene.

const PLAYER_PATH := "res://scripts/player/player.gd"
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")
const ITEMS_DIR := "res://resources/items/"
const MECHANIC_SCENE := "res://scenes/chip_mechanic.tscn"

func _installer(install_mult: float = 0.5, buy_mult: float = 1.25, min_fee: int = 10) -> ChipInstaller:
	var m := ChipInstaller.new()
	m.stock = CharacterInventory.new()  # _ready never ran (off-tree) — hand-build the stock, like test_merchant
	m.install_mult = install_mult
	m.buy_mult = buy_mult
	m.min_fee = min_fee
	return m

func _player(money: float = 1000.0) -> Player:
	var p = load(PLAYER_PATH).new()  # no _ready -> empty unlock set, bare backpack
	p.inventory = CharacterInventory.new()
	p.money = money
	return p

## A chip Item that installs `ability`, priced at `value`. Ability defaults to a real registry id so unlock works.
func _chip(ability: StringName = &"grapple", value: float = 400.0) -> Item:
	var it := Item.new()
	it.id = StringName("chip_" + String(ability))
	it.display_name = "Test Chip"
	it.category = Item.Category.MISC
	it.value = value
	it.installs_ability = ability
	return it

func _teardown(m: ChipInstaller, p: Player) -> void:
	m.stock.free()
	m.free()
	p.inventory.free()
	p.free()

## Safety: any test that opens the overlay closes it so its modal/pause state never leaks into the next test.
func after_each() -> void:
	if ChipInstallScreen.is_open():
		ChipInstallScreen.close()

## First entry in get_property_list() whose name matches, else {}.
func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}


# --- Item: the upgrade-chip field + its self-populating dropdown -------------------------------------------

func test_is_upgrade_chip_helper() -> void:
	var chip := _chip(&"grapple")
	assert_true(chip.is_upgrade_chip(), "an item with installs_ability set is an upgrade chip")
	var plain := Item.new()
	assert_false(plain.is_upgrade_chip(), "a blank installs_ability means an ordinary item, not a chip")
	chip = null
	plain = null

func test_installs_ability_dropdown_is_dynamic() -> void:
	# Item is @tool with _validate_property, so installs_ability's dropdown is built from disk (AbilityRegistry)
	# at property-list time — the SAME source UpgradePickup.unlock_id uses. Built off-tree (no add_child).
	var it := Item.new()
	var p := _property(it, "installs_ability")
	assert_false(p.is_empty(), "Item must expose an installs_ability property")
	assert_eq(p.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
		"installs_ability must be a PROPERTY_HINT_ENUM_SUGGESTION dropdown (set in _validate_property)")
	assert_eq(p.get("hint_string", ""), AbilityRegistry.ids_csv(),
		"installs_ability dropdown must auto-populate from the ability scenes on disk (AbilityRegistry.ids_csv)")
	it = null


# --- ChipInstaller: pricing --------------------------------------------------------------------------------

func test_install_fee_and_buy_cost() -> void:
	var m := _installer(0.5, 1.25, 10)
	var chip := _chip(&"grapple", 400.0)
	assert_eq(m.install_fee(chip), 200, "install fee = value x install_mult (400 x 0.5)")
	assert_eq(m.buy_and_install_cost(chip), 700, "buy & install = value x buy_mult + install fee (500 + 200)")
	m.stock.free()
	m.free()
	chip = null

func test_install_fee_floored_at_min_fee() -> void:
	var m := _installer(0.5, 1.25, 10)
	var cheap := _chip(&"grapple", 10.0)  # 10 x 0.5 = 5 -> floored at min_fee
	assert_eq(m.install_fee(cheap), 10, "a cheap chip still costs at least min_fee to fit")
	var worthless := _chip(&"grapple", 0.0)
	assert_eq(m.install_fee(worthless), 0, "a 0-value item has no fee (the screen won't offer it)")
	m.stock.free()
	m.free()
	cheap = null
	worthless = null


# --- ChipInstaller: install a carried chip -----------------------------------------------------------------

func test_install_carried_charges_consumes_unlocks() -> void:
	var m := _installer(0.5, 1.25, 10)
	var p := _player(1000.0)
	var chip := _chip(&"grapple", 400.0)
	p.inventory.add(chip, 1)
	assert_true(m.install_carried(chip, p), "install succeeds with the chip held + affordable")
	assert_eq(p.money, 800.0, "the player paid the 200 install fee (1000 -> 800)")
	assert_false(p.inventory.has(chip), "the chip is consumed into the machine")
	assert_true(p.has_mechanic(&"grapple"), "the encapsulated ability is granted immediately")
	_teardown(m, p)
	chip = null

func test_install_carried_refused_when_broke() -> void:
	var m := _installer(0.5, 1.25, 10)
	var p := _player(100.0)  # 100 < 200 fee
	var chip := _chip(&"grapple", 400.0)
	p.inventory.add(chip, 1)
	assert_false(m.install_carried(chip, p), "install refused when the wallet can't cover the fee")
	assert_eq(p.money, 100.0, "no zorkmids spent on a refused install")
	assert_true(p.inventory.has(chip), "the chip stays in the bag")
	assert_false(p.has_mechanic(&"grapple"), "no ability granted")
	_teardown(m, p)
	chip = null

func test_install_carried_refused_when_not_held() -> void:
	var m := _installer()
	var p := _player(1000.0)
	var chip := _chip(&"grapple", 400.0)  # never added to the bag
	assert_false(m.install_carried(chip, p), "can't install a chip the player isn't carrying")
	assert_eq(p.money, 1000.0, "no zorkmids spent")
	_teardown(m, p)
	chip = null

func test_install_refused_when_already_installed() -> void:
	var m := _installer()
	var p := _player(1000.0)
	p.unlock_mechanic(&"grapple")  # already has it
	var chip := _chip(&"grapple", 400.0)
	p.inventory.add(chip, 1)
	assert_false(m.install_carried(chip, p), "installing an ability you already have is refused")
	assert_eq(p.money, 1000.0, "no double charge")
	assert_true(p.inventory.has(chip), "the redundant chip stays in the bag")
	_teardown(m, p)
	chip = null

func test_install_refused_when_ability_unresolvable() -> void:
	# C21: a chip whose installs_ability isn't a real ability (a typo'd id absent from Player.ABILITY_SCRIPTS) would
	# build NOTHING via unlock_mechanic — but the old flow charged + consumed the chip first. The pre-charge
	# can_grant_mechanic guard now refuses it with no money spent and the chip kept.
	var m := _installer(0.5, 1.25, 10)
	var p := _player(1000.0)
	var chip := _chip(&"nonexistent_ability", 400.0)
	p.inventory.add(chip, 1)
	assert_false(m.install_carried(chip, p), "an unresolvable chip id is refused")
	assert_eq(p.money, 1000.0, "no zorkmids spent on a chip that installs nothing")
	assert_true(p.inventory.has(chip), "the chip is kept, not consumed into the machine")
	assert_false(p.has_mechanic(&"nonexistent_ability"), "nothing was granted")
	_teardown(m, p)
	chip = null


# --- ChipInstaller: buy & install a stocked chip -----------------------------------------------------------

func test_buy_and_install_consumes_stock_and_unlocks() -> void:
	var m := _installer(0.5, 1.25, 10)
	var p := _player(1000.0)
	var chip := _chip(&"air_dash", 400.0)
	m.stock.add(chip, 1)
	assert_true(m.buy_and_install(chip, p), "buy & install succeeds when stocked + affordable")
	assert_eq(p.money, 300.0, "charged the bundled 700 (1000 -> 300)")
	assert_false(m.stock.has(chip), "the chip is taken off the shelf")
	assert_false(p.inventory.has(chip), "the chip never enters the player's bag — it's fitted straight in")
	assert_true(p.has_mechanic(&"air_dash"), "the ability is granted")
	_teardown(m, p)
	chip = null

func test_buy_and_install_refused_when_not_stocked() -> void:
	var m := _installer()
	var p := _player(1000.0)
	var chip := _chip(&"air_dash", 400.0)  # not in stock
	assert_false(m.buy_and_install(chip, p), "can't buy & install a chip the mechanic doesn't stock")
	assert_eq(p.money, 1000.0, "no zorkmids spent")
	assert_false(p.has_mechanic(&"air_dash"), "no ability granted")
	_teardown(m, p)
	chip = null

func test_buy_and_install_refused_when_ability_unresolvable() -> void:
	# The buy path mirrors install_carried: an unresolvable stocked chip is refused before any charge.
	var m := _installer(0.5, 1.25, 10)
	var p := _player(1000.0)
	var chip := _chip(&"nonexistent_ability", 400.0)
	m.stock.add(chip, 1)
	assert_false(m.buy_and_install(chip, p), "an unresolvable stocked chip is refused")
	assert_eq(p.money, 1000.0, "no zorkmids spent")
	assert_true(m.stock.has(chip), "the chip stays on the shelf, not consumed")
	assert_false(p.has_mechanic(&"nonexistent_ability"), "no ability granted")
	_teardown(m, p)
	chip = null


# --- ChipInstaller: the two screen sections (filtering + dedup) --------------------------------------------

func test_installable_carried_excludes_installed_and_dedups() -> void:
	var m := _installer()
	var p := _player()
	p.inventory.add(_chip(&"grapple", 400.0), 1)
	p.inventory.add(_chip(&"grapple", 400.0), 1)  # a second, distinct grapple chip
	p.inventory.add(_chip(&"slide", 200.0), 1)
	p.unlock_mechanic(&"slide")  # already installed -> its chip drops out of the list
	var carried := m.installable_carried(p)
	assert_eq(carried.size(), 1, "installed abilities are excluded and duplicate chips dedupe to one row")
	assert_eq((carried[0] as Item).installs_ability, &"grapple", "only the not-yet-installed grapple chip remains")
	_teardown(m, p)

func test_installable_stock_excludes_carried_and_installed() -> void:
	var m := _installer()
	var p := _player()
	m.stock.add(_chip(&"grapple", 400.0), 1)   # also carried below -> install it cheaply instead
	m.stock.add(_chip(&"air_dash", 350.0), 1)  # not carried, not installed -> for sale
	m.stock.add(_chip(&"slide", 200.0), 1)     # already installed -> excluded
	p.inventory.add(_chip(&"grapple", 400.0), 1)
	p.unlock_mechanic(&"slide")
	var forsale := m.installable_stock(p)
	assert_eq(forsale.size(), 1, "stock excludes chips you carry (grapple) and abilities you have (slide)")
	assert_eq((forsale[0] as Item).installs_ability, &"air_dash", "only the buyable air_dash chip remains for sale")
	_teardown(m, p)

func test_zero_value_chip_is_not_installable() -> void:
	# F-C51: a value<=0 chip has a 0 install fee (install_fee returns 0) -> it must NOT appear in either
	# installable list, or the screen renders a permanently-disabled '0 zm' row. A priced chip alongside it shows.
	var m := _installer()
	var p := _player()
	p.inventory.add(_chip(&"grapple", 0.0), 1)  # worthless -> excluded from the carried section
	assert_true(m.installable_carried(p).is_empty(), "a 0-value carried chip is not offered for install")
	p.inventory.add(_chip(&"air_dash", 350.0), 1)  # priced -> shows
	var carried := m.installable_carried(p)
	assert_eq(carried.size(), 1, "only the priced chip is installable")
	assert_eq((carried[0] as Item).installs_ability, &"air_dash", "...the air_dash chip, not the free grapple one")
	# A 0-value STOCKED chip is likewise absent from the buy-&-install section (same shared filter).
	m.stock.add(_chip(&"slide", 0.0), 1)
	assert_true(m.installable_stock(p).is_empty(), "a 0-value stocked chip is not offered for buy & install")
	_teardown(m, p)

func test_seed_stock_keeps_only_chips() -> void:
	# An installer's shelf is chips only — a stray non-chip StockEntry line is ignored (never appears for install).
	var m := ChipInstaller.new()
	var chip := _chip(&"grapple", 400.0)
	var junk := Item.new()  # no installs_ability
	junk.id = &"junk"
	var e_chip := StockEntry.new()
	e_chip.item = chip
	e_chip.count = 1
	var e_junk := StockEntry.new()
	e_junk.item = junk
	e_junk.count = 5
	var entries: Array[StockEntry] = [e_chip, e_junk]
	m.stock_counts = entries
	var inv := CharacterInventory.new()
	m._seed_stock(inv)
	assert_eq(inv.count_of(chip), 1, "the chip line stocks")
	assert_eq(inv.count_of(junk), 0, "a non-chip line is ignored — an installer only stocks upgrade chips")
	inv.free()
	m.free()
	chip = null
	junk = null
	e_chip = null
	e_junk = null

func test_installer_exposes_dialogue_duck_type_surface() -> void:
	# DialogueManager._speaker_installer finds the mechanic by has_method(install_carried) + has_method(install_fee).
	# Pin that surface so a rename can't silently drop the "Install" dialogue option.
	var m := ChipInstaller.new()
	assert_true(m.has_method(&"install_carried"), "DialogueManager keys the Install option on install_carried()")
	assert_true(m.has_method(&"install_fee"), "...and on install_fee()")
	m.free()


# --- The authored content: 7 chip .tres + the reusable mechanic scene --------------------------------------

func test_all_chip_resources_are_valid() -> void:
	# Every chip_*.tres must be a real upgrade chip whose ability EXISTS on disk (else the install grants nothing),
	# and must carry the microchip world_model so it looks like a chip in the world + inventory.
	var known := AbilityRegistry.ids()
	var dir := DirAccess.open(ITEMS_DIR)
	assert_not_null(dir, "the items folder must exist")
	if dir == null:
		return
	var count := 0
	for f in dir.get_files():
		var fn := f.trim_suffix(".remap")
		if not fn.begins_with("chip_") or fn.get_extension() != "tres":
			continue
		var item := load(ITEMS_DIR + fn) as Item
		assert_not_null(item, "chip resource '%s' must load as an Item" % fn)
		if item == null:
			continue
		count += 1
		assert_true(item.is_upgrade_chip(), "'%s' must set installs_ability" % fn)
		assert_true(known.has(String(item.installs_ability)),
			"'%s' installs '%s', which must be a real ability on disk" % [fn, item.installs_ability])
		assert_not_null(item.world_model, "'%s' must carry a world_model (the microchip look)" % fn)
	assert_eq(count, 7, "expected 7 authored upgrade chips (one per shipped ability, incl. the Board Visualizer)")

func test_mechanic_scene_loads_and_can_instantiate() -> void:
	# The hand-authored mechanic scene must resolve its whole resource graph (NPC + Talkable dialogue +
	# ChipInstaller + stocked chips). can_instantiate() verifies the wiring without spinning up the NPC's _ready.
	var scene := load(MECHANIC_SCENE) as PackedScene
	assert_not_null(scene, "chip_mechanic.tscn must load")
	if scene != null:
		assert_true(scene.can_instantiate(), "chip_mechanic.tscn must be instantiable (all ext_resources resolve)")
