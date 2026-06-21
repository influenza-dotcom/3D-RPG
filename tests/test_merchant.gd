extends GutTest

## Merchant — the shop component's pricing + buy/sell transactions (markup / markdown, the till, and the
## wallet gates). Pure logic, tested OFF-TREE: Merchant.new() WITHOUT add_child (so _ready never runs — we
## set `stock` / `money` / the multipliers by hand), and a bare Player with a hand-set backpack + money,
## exactly the pattern test_loot_drop uses. Item is a Resource (RefCounted) -> .new() + `= null`.

const Factions = preload("res://scripts/faction/factions.gd")  # WR-5: resolve a faction id -> Faction for the rep tests

func _merchant(money: float = 1000.0, buy: float = 1.0, sell: float = 0.5) -> Merchant:
	var m := Merchant.new()
	m.stock = CharacterInventory.new()
	m.money = money
	m.buy_mult = buy
	m.sell_mult = sell
	return m

func _player(money: float = 100.0) -> Player:
	var p = load("res://scripts/player/player.gd").new()
	p.inventory = CharacterInventory.new()
	p.money = money
	return p

func _item(value: float) -> Item:
	var it := Item.new()
	it.id = &"goods"
	it.display_name = "Goods"
	it.value = value
	it.max_stack = 99
	return it

func _teardown(m: Merchant, p: Player) -> void:
	m.stock.free()
	m.free()
	p.inventory.free()
	p.free()

## Safety: a ShopScreen test that opens the overlay closes it here so its modal state never leaks into the
## next test (the pure-logic tests never open it, so this is a no-op for them).
func after_each() -> void:
	if ShopScreen.is_open():
		ShopScreen.close()


func test_stock_counts_seed_quantities() -> void:
	# stock_counts is the counted authoring path: N of an item per StockEntry line — stackables stack to
	# the count, weapons stock one UNIQUE instance per count, and the legacy x1 starting_stock seeds too.
	var m := Merchant.new()
	var packs := _item(25)  # stackable goods
	var gun := Item.new()
	gun.id = &"shotgun"
	gun.category = Item.Category.WEAPON
	gun.weapon = WeaponData.new()
	var entry_packs := StockEntry.new()
	entry_packs.item = packs
	entry_packs.count = 3
	var entry_guns := StockEntry.new()
	entry_guns.item = gun
	entry_guns.count = 2
	var entries: Array[StockEntry] = [entry_packs, entry_guns]
	m.stock_counts = entries
	var legacy: Array[Item] = [packs]  # legacy list still seeds x1 on top
	m.starting_stock = legacy
	var inv := CharacterInventory.new()
	m._seed_stock(inv)
	assert_eq(inv.count_of(packs), 4, "3 from the counted entry + 1 from the legacy list (stackables stack)")
	var weapon_instances := 0
	for s in inv.contents():
		var it: Item = s["item"]
		if it != null and it.is_weapon():
			weapon_instances += 1
			assert_true(it != gun, "each stocked weapon is a UNIQUE duplicate, never the authored template")
			assert_eq(it.weapon, gun.weapon, "...wrapping the same shared WeaponData")
	assert_eq(weapon_instances, 2, "a count-2 weapon entry stocks exactly two distinct instances")
	inv.free()
	m.free()
	packs = null
	gun = null
	entry_packs = null
	entry_guns = null


func test_prices_use_markup_and_markdown() -> void:
	var m := _merchant(1000, 1.0, 0.5)
	var p := _player()
	var it := _item(100)
	assert_eq(m.buy_price(it), 100, "buy price = value x buy_mult (100 x 1.0)")
	assert_eq(m.sell_price(it), 50, "sell price = value x sell_mult (100 x 0.5)")
	var worthless := _item(0)
	assert_eq(m.buy_price(worthless), 0, "a 0-value item has no buy price")
	assert_eq(m.sell_price(worthless), 0, "a 0-value item can't be sold")
	_teardown(m, p)
	it = null
	worthless = null


func test_faction_favor_discounts_buy_and_boosts_sell() -> void:
	# WR-2: a favoured faction sells to the player cheaper AND pays them more. A constant 0.2-favor curve isolates
	# the effect from the standing value, so the test doesn't depend on the exact rep min/max.
	Reputation.reset()
	var m := _merchant(1000, 1.0, 1.0)  # markdown neutralised so the favor is what we measure
	m.faction_id = "townsfolk"
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(1.0, 0.2))  # 0.2 favor at ANY standing
	m.reputation_discount_curve = curve
	var it := _item(100)
	assert_almost_eq(m.buy_price(it), 80.0, 0.01, "favor 0.2 -> buys 20% cheaper (100 -> 80)")
	assert_almost_eq(m.sell_price(it), 120.0, 0.01, "favor 0.2 -> sells 20% dearer (100 -> 120)")
	var p := _player()
	_teardown(m, p)
	it = null
	curve = null
	Reputation.reset()


func test_no_faction_pricing_is_inert() -> void:
	# Default (no faction_id / null curve) leaves pricing exactly as before.
	var m := _merchant(1000, 1.0, 0.5)
	var it := _item(100)
	assert_almost_eq(m.buy_price(it), 100.0, 0.01, "no faction pricing -> list buy price")
	assert_almost_eq(m.sell_price(it), 50.0, 0.01, "no faction pricing -> markdown sell price")
	var p := _player()
	_teardown(m, p)
	it = null


# --- WR-5: rep-gated stock — a StockEntry.required_reputation gates the line at seed + refill ----------------

func test_stock_entry_reputation_gate() -> void:
	# A line with required_reputation stays OFF the shelf below the standing, and stocks once it's earned. Uses a
	# tiny requirement (1.0) + a huge add (clamps to rep_max, certainly >= 1) so the test doesn't depend on the scale.
	Reputation.reset()
	var m := Merchant.new()
	m.faction_id = "townsfolk"
	var goods := _item(25)
	var entry := StockEntry.new()
	entry.item = goods
	entry.count = 2
	entry.required_reputation = 1.0
	var entries: Array[StockEntry] = [entry]
	m.stock_counts = entries
	var inv := CharacterInventory.new()
	m._seed_stock(inv)
	assert_eq(inv.count_of(goods), 0, "below the required standing the rep-gated line is withheld")
	inv.free()
	Reputation.add_reputation(Factions.by_id("townsfolk"), 1_000_000.0)  # clamps to rep_max (>= 1.0) -> gate met
	var inv2 := CharacterInventory.new()
	m._seed_stock(inv2)
	assert_eq(inv2.count_of(goods), 2, "once standing meets the requirement, the line stocks")
	inv2.free()
	m.free()
	goods = null
	entry = null
	Reputation.reset()


func test_stock_entry_gate_inert_without_faction() -> void:
	# No faction_id -> the gate can't be measured, so a rep-gated line still stocks (lenient, never silently empty).
	Reputation.reset()
	var m := Merchant.new()
	var goods := _item(25)
	var entry := StockEntry.new()
	entry.item = goods
	entry.count = 1
	entry.required_reputation = 50.0
	var entries: Array[StockEntry] = [entry]
	m.stock_counts = entries
	var inv := CharacterInventory.new()
	m._seed_stock(inv)
	assert_eq(inv.count_of(goods), 1, "a rep gate with no merchant faction is ignored — the line stocks")
	inv.free()
	m.free()
	goods = null
	entry = null
	Reputation.reset()


func test_stock_entry_zero_requirement_always_stocks() -> void:
	# The default required_reputation 0 is inert: stocks regardless of standing (the existing behaviour).
	Reputation.reset()
	var m := Merchant.new()
	m.faction_id = "townsfolk"
	var goods := _item(25)
	var entry := StockEntry.new()
	entry.item = goods
	entry.count = 3
	var entries: Array[StockEntry] = [entry]
	m.stock_counts = entries
	var inv := CharacterInventory.new()
	m._seed_stock(inv)
	assert_eq(inv.count_of(goods), 3, "the default required_reputation 0 stocks at any standing")
	inv.free()
	m.free()
	goods = null
	entry = null
	Reputation.reset()


func test_buy_moves_item_and_exchanges_money() -> void:
	var m := _merchant(1000, 1.0, 0.5)
	var p := _player(100)
	var it := _item(40)
	m.stock.add(it, 1)
	assert_true(m.buy(it, p), "buy succeeds when the item is stocked and affordable")
	assert_eq(p.money, 60, "the player paid 40 (100 -> 60)")
	assert_eq(m.money, 1040, "the till gained 40 (1000 -> 1040)")
	assert_true(p.inventory.has(it), "the item is now in the player's backpack")
	assert_false(m.stock.has(it), "the item left the shop stock")
	_teardown(m, p)
	it = null


func test_buy_refused_when_player_cant_afford() -> void:
	var m := _merchant(1000, 1.0, 0.5)
	var p := _player(30)
	var it := _item(40)
	m.stock.add(it, 1)
	assert_false(m.buy(it, p), "buy refused when the player can't afford it (30 < 40)")
	assert_eq(p.money, 30, "no zorkmids spent on a refused buy")
	assert_true(m.stock.has(it), "the item stays in stock")
	_teardown(m, p)
	it = null


func test_buy_refused_when_not_in_stock() -> void:
	var m := _merchant(1000, 1.0, 0.5)
	var p := _player(100)
	var it := _item(40)  # never added to stock
	assert_false(m.buy(it, p), "can't buy what the merchant doesn't stock")
	assert_eq(p.money, 100, "no zorkmids spent")
	_teardown(m, p)
	it = null


func test_sell_moves_item_and_pays_player() -> void:
	var m := _merchant(1000, 1.0, 0.5)
	var p := _player(100)
	var it := _item(40)
	p.inventory.add(it, 1)
	assert_true(m.sell(it, p), "sell succeeds when the player holds it and the till can pay")
	assert_eq(p.money, 120, "the player received 20 (40 x 0.5 markdown)")
	assert_eq(m.money, 980, "the till paid 20 (1000 -> 980)")
	assert_true(m.stock.has(it), "the item is now in the shop stock")
	assert_false(p.inventory.has(it), "the item left the player's backpack")
	_teardown(m, p)
	it = null


func test_sell_refused_when_till_cant_pay() -> void:
	var m := _merchant(10, 1.0, 0.5)  # only 10 zorkmids in the till
	var p := _player(100)
	var it := _item(40)  # sell price 20 > 10
	p.inventory.add(it, 1)
	assert_false(m.sell(it, p), "the merchant can't buy what its till can't afford (20 > 10)")
	assert_eq(p.money, 100, "no zorkmids paid")
	assert_true(p.inventory.has(it), "the item stays with the player")
	_teardown(m, p)
	it = null


func test_sell_refused_for_worthless_item() -> void:
	var m := _merchant(1000, 1.0, 0.5)
	var p := _player(100)
	var it := _item(0)  # worthless
	p.inventory.add(it, 1)
	assert_false(m.sell(it, p), "a 0-value item can't be sold")
	assert_eq(p.money, 100, "no zorkmids paid for junk")
	assert_true(p.inventory.has(it), "the junk stays with the player")
	_teardown(m, p)
	it = null


func test_price_rounding_ceil_buy_floor_sell() -> void:
	# Zorkmids are FRACTIONAL now: rounding lands on the smallest COIN (a hundredth), not whole zorkmids —
	# buying CEILS to the coin (the margin never rounds away), selling FLOORS (the cut never rounds up).
	var m := _merchant(1000, 1.1, 0.5)
	var p := _player()
	var it := _item(15)
	assert_almost_eq(m.buy_price(it), 16.5, 0.0001, "15 x 1.1 = 16.5 — already on the coin grid, no round-up")
	assert_almost_eq(m.sell_price(it), 7.5, 0.0001, "15 x 0.5 = 7.5 — fractional prices stand")
	var odd := _item(0.33)
	assert_almost_eq(m.buy_price(odd), 0.37, 0.0001, "0.33 x 1.1 = 0.363 -> CEILS to the coin: 0.37")
	assert_almost_eq(m.sell_price(odd), 0.16, 0.0001, "0.33 x 0.5 = 0.165 -> FLOORS to the coin: 0.16")
	_teardown(m, p)
	it = null
	odd = null


func test_buy_price_never_below_one_coin_for_a_valued_item() -> void:
	var m := _merchant(1000, 0.4, 0.5)  # a steep discount multiplier
	var p := _player()
	var it := _item(1)
	assert_almost_eq(m.buy_price(it), 0.4, 0.0001, "1 x 0.4 = 0.4 — fractional prices are real now")
	var dust := _item(0.01)  # 0.01 x 0.4 = 0.004 -> would round to 0; floored at one COIN
	assert_almost_eq(m.buy_price(dust), 0.01, 0.0001, "a valued item always costs at least one coin (0.01 zm)")
	_teardown(m, p)
	it = null
	dust = null


func test_buy_and_sell_are_null_safe() -> void:
	var m := _merchant()
	var p := _player(100)
	var it := _item(40)
	m.stock.add(it, 1)
	assert_false(m.buy(null, p), "buy(null item) is a safe no-op")
	assert_false(m.buy(it, null), "buy with no player is a safe no-op")
	assert_false(m.sell(null, p), "sell(null item) is a safe no-op")
	assert_false(m.sell(it, null), "sell with no player is a safe no-op")
	assert_eq(p.money, 100, "no zorkmids moved on any null call")
	_teardown(m, p)
	it = null


func test_buy_one_from_a_stack() -> void:
	var m := _merchant(1000, 1.0, 0.5)
	var p := _player(1000)
	var it := _item(40)
	m.stock.add(it, 3)
	assert_true(m.buy(it, p), "buy succeeds")
	assert_eq(m.stock.count_of(it), 2, "stock drops by exactly ONE per buy")
	assert_eq(p.inventory.count_of(it), 1, "the player gains exactly ONE")
	assert_eq(p.money, 960, "paid for one (1000 - 40)")
	_teardown(m, p)
	it = null


func test_sell_one_from_a_stack() -> void:
	var m := _merchant(1000, 1.0, 0.5)
	var p := _player(0)
	var it := _item(40)
	p.inventory.add(it, 3)
	assert_true(m.sell(it, p), "sell succeeds")
	assert_eq(p.inventory.count_of(it), 2, "the player loses exactly ONE per sell")
	assert_eq(m.stock.count_of(it), 1, "the merchant gains exactly ONE")
	assert_eq(p.money, 20, "paid for one (40 x 0.5)")
	_teardown(m, p)
	it = null


func test_selling_the_wielded_weapon_falls_back_to_fists() -> void:
	var m := _merchant(1000, 1.0, 0.5)
	var p := _player(0)
	var weapon := Item.new()
	weapon.category = Item.Category.WEAPON
	weapon.weapon = WeaponData.new()
	weapon.value = 40
	p.inventory.add(weapon, 1)
	p.inventory.equipped_item = weapon
	var lost := [false]
	p.inventory.equipped_item_lost.connect(func() -> void: lost[0] = true)
	assert_true(m.sell(weapon, p), "you can sell the weapon you're wielding")
	assert_null(p.inventory.equipped_item, "selling the wielded weapon clears the equipped marker")
	assert_true(lost[0], "equipped_item_lost fires so the player drops to bare fists")
	_teardown(m, p)
	weapon = null


# ---------------------------------------------------------------------------
# ShopScreen — the autoload overlay's open / close + guards (mirrors test_loot_drop's LootScreen cases).
# ---------------------------------------------------------------------------

func test_shop_opens_and_closes() -> void:
	var m := _merchant()
	var p := _player()
	ShopScreen.open_shop(m, p)
	assert_true(ShopScreen.is_open(), "open_shop opens on a valid merchant + player")
	ShopScreen.close()
	assert_false(ShopScreen.is_open(), "close() closes the shop")
	_teardown(m, p)


func test_shop_pauses_the_world_while_open() -> void:
	# Trading freezes the world like dialogue (get_tree().paused) so combat / physics don't run while you
	# shop. open + close are synchronous here, so the tree is paused and unpaused within this one call —
	# GUT (blocked awaiting this test) never tries to process mid-pause, and after_each closes any leak.
	var m := _merchant()
	var p := _player()
	ShopScreen.open_shop(m, p)
	assert_true(get_tree().paused,
		"opening the shop pauses the world, like dialogue (combat / physics freeze while trading)")
	ShopScreen.close()
	assert_false(get_tree().paused, "closing the shop resumes the world")
	_teardown(m, p)


func test_shop_refuses_invalid_merchant_or_player() -> void:
	var p := _player()
	ShopScreen.open_shop(null, p)
	assert_false(ShopScreen.is_open(), "open_shop(null merchant) must not open")
	var no_stock := Merchant.new()  # _ready never ran -> stock is null
	ShopScreen.open_shop(no_stock, p)
	assert_false(ShopScreen.is_open(), "a merchant with no stock must not open")
	no_stock.free()
	var m := _merchant()
	ShopScreen.open_shop(m, null)
	assert_false(ShopScreen.is_open(), "open_shop with no player must not open")
	m.stock.free()
	m.free()
	p.inventory.free()
	p.free()
