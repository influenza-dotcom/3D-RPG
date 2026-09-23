extends GutTest

## WeaponBench (scripts/components/weapon_bench.gd) — the gunsmith station: pay to FIT a weapon part into one
## of a gun's six FO4 slots, BUY & FIT one off the shelf, or REMOVE one and keep the part.
##
## Tested OFF-TREE, the test_chip_install / test_merchant mold: WeaponBench.new() WITHOUT add_child (so _ready
## never runs — `stock` and the multipliers are hand-set) and a bare Player built with
## load("res://scripts/player/player.gd").new(), likewise never added to the tree (CLAUDE.md: a Player's _ready
## instantiates weapon.tscn, nav and audio and mutates shared statics). The success tail is already an off-tree
## no-op: GameState.autosave early-returns off-tree and notify_toast needs a `ui`, so a bare-Player fit never
## touches disk.
##
## ⭐WHAT THIS FILE IS REALLY GUARDING: every guard in fit_mod / buy_and_fit / remove_mod runs BEFORE the
## charge. A refusal that happens after take_payment is a player who paid for nothing, so each refusal test
## below asserts the wallet as well as the bool — that pairing is the point, not the bool on its own.
##
## ⭐ItemDb is the REAL autoload (the id resolver both the fold and the template gate go through, so it cannot
## be faked off-tree). The minted test parts are registered into ItemDb._by_id and erased again in after_each,
## so a later test in the same run can never resolve an id that does not exist in the shipped game.
## Parts are MINTED rather than taken from resources/items/ on purpose: keying a fee assertion to a shipped
## part's `value` would turn a balance retune into a red suite.

const PLAYER_PATH := "res://scripts/player/player.gd"
const BENCH_SCENE := "res://scenes/characters/weapon_mechanic.tscn"
## The authored bench CARD — test_a_paid_fit_shows_up_on_the_card_immediately drives the real thing.
const SCREEN_SCENE := "res://scenes/ui/weapon_bench_screen.tscn"
## The level the player actually plays — the one place a WeaponBench is instanced for real.
const LEVEL_SCENE := "res://scenes/levels/trenchboom_test_level.tscn"
## The shipped weapon this file mods. A REAL registered template, because rebuild_weapon_mods and the bench's
## template gate both resolve the pristine base through ItemDb.item_by_id(gun.id).
const GUN_ID := &"pistol"

## Minted part ids — namespaced so they cannot collide with a shipped mod_*.tres id.
const P_BARREL := &"test_bench_barrel"
const P_MUZZLE := &"test_bench_muzzle"
const P_SIGHT := &"test_bench_sight"

## ⭐The bench gates on the PAYMENT SEAM (Player.can_pay / charge), which reads the SHARED GameState banking
## fields — a stale positive account left by another test would fund a fit the wallet could not cover.
var _prev_account: float
var _prev_method: String


func before_each() -> void:
	_prev_account = GameState.account
	_prev_method = GameState.payment_method
	GameState.account = 0.0
	GameState.payment_method = "debit"

func after_each() -> void:
	for id in [P_BARREL, P_MUZZLE, P_SIGHT]:
		ItemDb._by_id.erase(id)
	GameState.account = _prev_account
	GameState.payment_method = _prev_method


# --- fixtures ------------------------------------------------------------------------------------------------

## A bench with a hand-built stock (off-tree, so _ready never seeded one) and predictable rates.
func _bench(fit_mult: float = 0.4, remove_mult: float = 0.2, buy_mult: float = 1.25, min_fee: int = 10) -> WeaponBench:
	var b := WeaponBench.new()
	b.stock = CharacterInventory.new()
	b.fit_mult = fit_mult
	b.remove_mult = remove_mult
	b.buy_mult = buy_mult
	b.min_fee = min_fee
	return b

func _player(money: float = 5000.0) -> Player:
	var p = load(PLAYER_PATH).new()  # no _ready -> bare backpack, no weapon component
	p.inventory = CharacterInventory.new()
	p.money = money
	return p

## A minted weapon part, REGISTERED with ItemDb so the fold's resolver and the removal's "give the shared
## template back" both find it. One SET/ADD/MULT line is enough — the fold itself is pinned in
## tests/test_weapon_mods.gd; here the delta only has to be observable.
func _part(id: StringName, slot: int, value: float = 100.0, fits: Array[StringName] = [],
		min_gunplay: int = 0, labour_mult: float = 1.0) -> Item:
	var line := WeaponStatDelta.new()
	line.property = &"effective_range"
	line.op = WeaponStatDelta.Op.ADD
	line.amount = 8.0
	var lines: Array[WeaponStatDelta] = []
	lines.append(line)
	var mod := WeaponMod.new()
	mod.slot = slot
	mod.deltas = lines
	mod.fits_weapon_ids = fits
	mod.min_gunplay = min_gunplay
	mod.fit_labour_mult = labour_mult
	var part := Item.new()
	part.id = id
	part.display_name = "Test Part"
	part.category = Item.Category.MISC
	part.max_stack = 10
	part.value = value
	part.weapon_mod = mod
	ItemDb._by_id[id] = part
	return part

## A UNIQUE pistol Item — its own WeaponData, so a fit never writes through to the registered template.
func _gun() -> Item:
	var tmpl := ItemDb.item_by_id(GUN_ID)
	assert_not_null(tmpl, "resources/items/ must still ship a '%s' weapon item — the whole file mods it" % GUN_ID)
	return tmpl.clone_unique()

## A minimal weapon component the bench can read `attack.draw_locked` through. Built off-tree with .new()
## (never add_child): Weapon._ready does nothing, but Attack's does, and Ammo's null-derefs an unset inventory.
## ⭐`inventory.equipped_weapon` is set here only so the component is coherent — the bench does NOT read it to
## decide what is drawn. That is `player.inventory.equipped_item`, per WeaponBench._is_drawn, so a test that
## wants the draw-lock gate to fire must ALSO mark the gun equipped on the PLAYER's bag.
func _weapon_system(drawn: WeaponData, draw_locked: bool) -> Weapon:
	var ws := Weapon.new()
	ws.inventory = Inventory.new()
	ws.inventory.equipped_weapon = drawn
	ws.attack = Attack.new()
	ws.attack.draw_locked = draw_locked
	return ws

func _free_ws(ws: Weapon) -> void:
	if ws == null:
		return
	ws.inventory.free()
	ws.attack.free()
	ws.free()

func _teardown(b: WeaponBench, p: Player) -> void:
	b.stock.free()
	b.free()
	p.inventory.free()
	p.free()


# --- Pricing -------------------------------------------------------------------------------------------------

func test_fit_fee_buy_and_fit_cost_remove_fee() -> void:
	var b := _bench()
	var part := _part(P_BARREL, WeaponData.ModSlot.BARREL, 100.0)
	# value 100: fit 0.4 -> 40, remove 0.2 -> 20, buy 1.25 -> 125 + the 40 fit fee.
	assert_eq(b.fit_fee(part), 40, "fit = value x fit_mult, in whole zorkmids")
	assert_eq(b.remove_fee(part), 20, "removal is cheaper than fitting — experimenting must not be punished")
	assert_eq(b.buy_and_fit_cost(part), 165, "buy & fit = the marked-up part PLUS the fit fee, so finding a part is always cheaper")
	# The per-part labour trim rides ON TOP of the bench's rates, and only touches LABOUR (not the shelf price).
	var fiddly := _part(P_SIGHT, WeaponData.ModSlot.SIGHT, 100.0, [], 0, 1.4)
	assert_eq(b.fit_fee(fiddly), 56, "fit_labour_mult 1.4 scales the labour: 100 x 0.4 x 1.4")
	assert_eq(b.buy_and_fit_cost(fiddly), 125 + 56, "the markup is untouched by fit_labour_mult — only the labour half moves")
	# The min_fee floor: a cheap part still costs something to work on.
	var cheap := _part(P_MUZZLE, WeaponData.ModSlot.MUZZLE, 5.0)
	assert_eq(b.fit_fee(cheap), b.min_fee, "a fee below min_fee is floored at min_fee")
	assert_eq(b.remove_fee(cheap), b.min_fee, "the floor applies to removal too")
	b.stock.free()
	b.free()
	part = null
	fiddly = null
	cheap = null

func test_zero_value_part_prices_zero_and_is_never_offered() -> void:
	# A 0 fee would paint a permanently-disabled "0 zm" row (fit_mod refuses cost <= 0), so the list builders
	# must drop the part instead of offering a row that can only refuse.
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var free_part := _part(P_BARREL, WeaponData.ModSlot.BARREL, 0.0)
	assert_eq(b.fit_fee(free_part), 0, "a worthless part prices no labour")
	assert_eq(b.buy_and_fit_cost(free_part), 0, "...and no shelf price either")
	p.inventory.add(free_part, 1)
	b.stock.add(free_part, 1)
	assert_eq(b.fittable_parts(gun, p).size(), 0, "a 0-value part is never offered in the carried section")
	assert_eq(b.stock_parts(gun, p).size(), 0, "...nor on the shelf")
	assert_false(b.fit_mod(gun, free_part, p), "and fitting one is refused outright")
	_teardown(b, p)
	gun = null
	free_part = null


# --- Slots offered -------------------------------------------------------------------------------------------

func test_slots_offered_bitmask_gates_fit_and_the_fitted_list() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL)
	p.inventory.add(barrel, 1)
	# All six by default: every slot gets a Fitted row (empty ones included — the section never collapses).
	assert_eq(b.fitted_parts(gun).size(), 6, "the default bench works all six slots, so it shows all six rows")
	assert_eq(b.fittable_parts(gun, p).size(), 1, "a fitting carried part is offered")
	# A sights-only optician: barrels are not its business.
	b.slots_offered = 1 << WeaponData.ModSlot.SIGHT
	var rows := b.fitted_parts(gun)
	assert_eq(rows.size(), 1, "a one-slot bench shows exactly one Fitted row")
	assert_eq(int(rows[0]["slot"]), int(WeaponData.ModSlot.SIGHT), "...and it is the slot it actually works on")
	assert_eq(b.fittable_parts(gun, p).size(), 0, "a part for an unworked slot is not offered")
	assert_false(b.fit_mod(gun, barrel, p), "...and cannot be fitted through a duck-call either")
	assert_eq(p.money, 5000.0, "a slot this bench does not work on costs the player nothing")
	assert_eq(gun.weapon.mod_id(WeaponData.ModSlot.BARREL), &"", "and stamps no slot")
	_teardown(b, p)
	gun = null
	barrel = null


# --- fit_mod: every guard, PRE-CHARGE ---------------------------------------------------------------------

func test_fit_requires_the_part_in_the_bag() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL)  # minted but never added to the pack
	assert_false(b.fit_mod(gun, barrel, p), "you cannot fit a part you are not carrying")
	assert_eq(p.money, 5000.0, "and the refusal costs nothing")
	_teardown(b, p)
	gun = null
	barrel = null

func test_fit_refuses_an_occupied_slot() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var first := _part(P_BARREL, WeaponData.ModSlot.BARREL)
	var second := _part(P_MUZZLE, WeaponData.ModSlot.BARREL)  # same slot, different part
	p.inventory.add(first, 1)
	p.inventory.add(second, 1)
	assert_true(b.fit_mod(gun, first, p), "the first barrel goes in")
	var after_first := p.money
	assert_false(b.fit_mod(gun, second, p), "ONE part per slot — pull the occupant out first")
	assert_eq(p.money, after_first, "the refused second fit charges nothing")
	assert_eq(gun.weapon.mod_id(WeaponData.ModSlot.BARREL), P_BARREL, "and the fitted part is untouched")
	assert_true(p.inventory.has(second), "the refused part stays in the pack")
	assert_eq(b.refusal_reason(gun, second, p), &"slot_taken", "the row can say why")
	_teardown(b, p)
	gun = null
	first = null
	second = null

func test_fit_refuses_a_gun_with_no_registered_template_and_charges_nothing() -> void:
	# ⭐The template gate. A weapon whose .tres has left resources/items/ has no PRISTINE base to fold from —
	# without this guard the bench takes the money and hands WeaponModKit.rebuild a null template.
	var b := _bench()
	var p := _player()
	var orphan := Item.new()
	orphan.id = &"test_bench_orphan_gun"   # deliberately NOT registered with ItemDb
	orphan.category = Item.Category.WEAPON
	orphan.weapon = WeaponData.new()
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL)
	p.inventory.add(orphan, 1)
	p.inventory.add(barrel, 1)
	assert_false(b.fit_mod(orphan, barrel, p), "an unregistered weapon has no pristine template to fold from")
	assert_eq(p.money, 5000.0, "⭐and the refusal happens BEFORE the charge")
	assert_true(p.inventory.has(barrel), "the part is not consumed either")
	assert_eq(orphan.weapon.mod_id(WeaponData.ModSlot.BARREL), &"", "and no slot is stamped")
	assert_eq(b.moddable_weapons(p).size(), 0, "the cycler never offers a gun every row would refuse")
	_teardown(b, p)
	orphan = null
	barrel = null

func test_fit_refuses_below_min_gunplay_and_charges_nothing() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var scope := _part(P_SIGHT, WeaponData.ModSlot.SIGHT, 100.0, [], 4)
	p.inventory.add(scope, 1)
	p.stats_or_default().gunplay = 3
	assert_false(b.fit_mod(gun, scope, p), "hardware below the Gunplay gate is refused")
	assert_eq(p.money, 5000.0, "⭐and the stat gate is checked before the charge")
	assert_eq(b.refusal_reason(gun, scope, p), &"stat_gate", "the Notice band can name the gate")
	p.stats_or_default().gunplay = 4
	assert_eq(b.refusal_reason(gun, scope, p), &"", "meeting the gate clears the refusal")
	assert_true(b.fit_mod(gun, scope, p), "...and the fit goes through")
	_teardown(b, p)
	gun = null
	scope = null

func test_fit_refuses_while_draw_locked_and_charges_nothing() -> void:
	# ⭐Attack.set_holstered(false) is REFUSED while draw_locked, and the swap chain a refit starts calls exactly
	# that — so a fit here would swap the model in behind a locked holster: visible in hand, unable to fire.
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL)
	p.inventory.add(barrel, 1)
	var ws := _weapon_system(gun.weapon, true)
	p.weapon_system = ws
	# ⭐"In the player's hands" is the BAG'S `equipped_item` marker, not ws.equipped_weapon — see
	# WeaponBench._is_drawn for the two ways the WeaponData comparison lies. The gun must be in the pack and
	# marked equipped for the draw-lock gate to see it at all.
	p.inventory.add(gun, 1)
	p.inventory.equipped_item = gun
	assert_false(b.fit_mod(gun, barrel, p), "a locked draw refuses the fit")
	assert_eq(p.money, 5000.0, "⭐and refuses before the charge")
	assert_eq(b.refusal_reason(gun, null, p), &"draw_locked", "the gun-level Notice band names it for the whole card")
	# The gate is scoped to the DRAWN gun: a holstered one in the same pack is still workable.
	var other := _gun()
	assert_eq(b.refusal_reason(other, null, p), &"", "a gun that is not in the player's hands is unaffected")
	ws.attack.draw_locked = false
	assert_true(b.fit_mod(gun, barrel, p), "hands free -> the fit goes through")
	p.weapon_system = null
	_free_ws(ws)
	_teardown(b, p)
	gun = null
	other = null
	barrel = null


## ⭐REGRESSION — "drawn" is ITEM identity, never WeaponData identity. ItemDb.make_weapon_item SHARES the
## template WeaponData across every unmodded copy of a gun (its own doc says duplicate() does not deep-copy
## sub-resources), so the old `ws.equipped_weapon == gun.weapon` test was TRUE for a holstered spare while the
## player held a different one — and a fit on that spare force-swapped the gun out of their hands mid-menu.
## This test deliberately uses make_weapon_item, NOT _gun()/clone_unique: the unique-WeaponData fixture is
## precisely why the whole file missed this.
func test_a_holstered_twin_sharing_the_template_weapondata_is_not_drawn() -> void:
	var b := _bench()
	var p := _player()
	var tmpl := ItemDb.item_by_id(GUN_ID)
	var held := ItemDb.make_weapon_item(tmpl.weapon)
	var spare := ItemDb.make_weapon_item(tmpl.weapon)
	assert_eq(held.weapon, spare.weapon,
		"the trap this guards: two unmodded copies of one gun SHARE a single WeaponData object")
	assert_ne(held, spare, "...but they are distinct Items, which is the identity that actually means 'this gun'")
	p.inventory.add(held, 1)
	p.inventory.add(spare, 1)
	p.inventory.equipped_item = held
	assert_true(b._is_drawn(held, p), "the Item the bag marks equipped IS the drawn gun")
	assert_false(b._is_drawn(spare, p),
		"⭐a holstered twin must NOT read as drawn — it shares the WeaponData but not the Item")
	_teardown(b, p)
	held = null
	spare = null


## ⭐REGRESSION — refusal_reason takes the DIRECTION; it must not infer it from the part id. Parts STACK, so a
## spare copy in the pack (or the bench's own shelf copy) carries the same Item.id as the fitted one. The old
## inference sent that duplicate down the REMOVE branch, which answered "nothing wrong" — so the screen painted
## a live, priced FIT row that the occupied-slot guard rejected on every press, with a blank Notice band.
func test_refusal_reason_takes_the_direction_so_a_spare_copy_reads_as_slot_taken() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var muzzle := _part(P_MUZZLE, WeaponData.ModSlot.MUZZLE)
	p.inventory.add(gun, 1)
	p.inventory.add(muzzle, 2)          # fit one, keep a SPARE of the same id
	assert_true(b.fit_mod(gun, muzzle, p), "the first copy fits")
	assert_eq(gun.weapon.mod_id(WeaponData.ModSlot.MUZZLE), P_MUZZLE, "...and the slot now holds it")
	assert_eq(b.refusal_reason(gun, muzzle, p, false), &"slot_taken",
		"⭐asked as a FIT row, the spare names the occupied slot — the same cause _transact_fit refuses on")
	assert_eq(b.refusal_reason(gun, muzzle, p, true), &"",
		"asked as the REMOVE row, the fitted part is workable")
	_teardown(b, p)
	gun = null
	muzzle = null

func test_fit_charges_consumes_and_stamps_the_slot() -> void:
	var b := _bench()
	var p := _player(1000.0)
	var gun := _gun()
	var base_range: float = gun.weapon.effective_range
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL)  # +8 effective_range
	p.inventory.add(barrel, 1)
	var before: WeaponData = gun.weapon
	assert_true(b.fit_mod(gun, barrel, p), "a carried, fitting, affordable part goes in")
	assert_almost_eq(p.money, 960.0, 0.001, "the fit fee (100 x 0.4) left the wallet")
	assert_false(p.inventory.has(barrel), "the part went into the gun, not back in the pack")
	assert_eq(gun.weapon.mod_id(WeaponData.ModSlot.BARREL), P_BARREL, "the slot carries the part's Item.id — THE save value")
	assert_almost_eq(gun.weapon.effective_range, base_range + 8.0, 0.001, "and the delta landed on the folded block")
	# ⭐The fold hands back a NEW object; the Item instance itself survives. Attack's swap identity gate
	# (`if _weapon == current_weapon: return`) depends on the first half, and every reference held to the gun
	# depends on the second.
	assert_ne(gun.weapon, before, "the refit replaces the WeaponData object — the swap chain's identity gate needs that")
	assert_almost_eq(ItemDb.item_by_id(GUN_ID).weapon.effective_range, base_range, 0.001,
			"⭐and the registered TEMPLATE is untouched — mutating it would buff every pistol in the world")
	_teardown(b, p)
	gun = null
	barrel = null

func test_buy_and_fit_takes_from_stock_and_never_enters_the_bag() -> void:
	var b := _bench()
	var p := _player(1000.0)
	var gun := _gun()
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL)
	b.stock.add(barrel, 1)
	assert_eq(b.stock_parts(gun, p).size(), 1, "the shelf offers a fitting part the player does not carry")
	assert_true(b.buy_and_fit(gun, barrel, p), "buy & fit is one press")
	assert_almost_eq(p.money, 1000.0 - 165.0, 0.001, "the marked-up part (125) plus the fit fee (40)")
	assert_false(b.stock.has(barrel), "the part came off the shelf")
	assert_false(p.inventory.has(barrel), "⭐and NEVER entered the pack — it went straight into the gun")
	assert_eq(gun.weapon.mod_id(WeaponData.ModSlot.BARREL), P_BARREL, "the slot is stamped")
	# A part the player already carries is dropped from the shelf section: fitting your own is strictly cheaper.
	var muzzle := _part(P_MUZZLE, WeaponData.ModSlot.MUZZLE)
	b.stock.add(muzzle, 1)
	p.inventory.add(muzzle, 1)
	assert_eq(b.stock_parts(gun, p).size(), 0, "the shelf hides a part the player is already carrying")
	assert_eq(b.fittable_parts(gun, p).size(), 1, "...because the cheaper carried row covers it")
	_teardown(b, p)
	gun = null
	barrel = null
	muzzle = null


# --- remove_mod ----------------------------------------------------------------------------------------------

func test_remove_gates_on_bag_space_BEFORE_charging() -> void:
	# ⭐The one path that moves goods TO the player, so the one that needs Merchant.buy's precedent: a full pack
	# would otherwise eat the fee AND destroy the part, because the fold clears the slot either way.
	var b := _bench()
	var p := _player(1000.0)
	var gun := _gun()
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL)
	p.inventory.add(barrel, 1)
	assert_true(b.fit_mod(gun, barrel, p), "fit it first so there is something to pull")
	var purse := p.money
	# Bound the pack to ONE cell and fill it with something else. can_accept then has no matching stack to top
	# up and no free footprint, which is exactly the state a real full Tetris bag is in.
	p.inventory.enable_grid(1, 1)
	var filler := Item.new()
	filler.id = &"test_bench_filler"
	filler.category = Item.Category.MISC
	p.inventory.add(filler, 1)
	assert_false(p.inventory.can_accept(barrel), "sanity: the pack really is full")
	assert_false(b.remove_mod(gun, WeaponData.ModSlot.BARREL, p), "a full pack refuses the removal")
	assert_eq(p.money, purse, "⭐the removal fee never left the wallet")
	assert_eq(gun.weapon.mod_id(WeaponData.ModSlot.BARREL), P_BARREL, "and the part is still on the gun, not destroyed")
	# ⭐`removing` is PASSED, never inferred (see refusal_reason's own header, and the spare-copy regression test
	# above): this is a REMOVE row's question, so the direction has to come with it. Asked without the flag it is
	# the FIT question about a part already in that slot, and the honest answer to THAT is &"slot_taken".
	assert_eq(b.refusal_reason(gun, barrel, p, true), &"bag_full", "the row can say why")
	_teardown(b, p)
	gun = null
	barrel = null
	filler = null

func test_remove_returns_the_shared_template_part_and_clears_the_slot() -> void:
	var b := _bench()
	var p := _player(1000.0)
	var gun := _gun()
	var base_range: float = gun.weapon.effective_range
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL)
	p.inventory.add(barrel, 1)
	assert_true(b.fit_mod(gun, barrel, p), "fit it first")
	assert_true(b.remove_mod(gun, WeaponData.ModSlot.BARREL, p), "and pull it back out")
	assert_almost_eq(p.money, 1000.0 - 40.0 - 20.0, 0.001, "the fit fee then the (cheaper) removal fee")
	assert_eq(gun.weapon.mod_id(WeaponData.ModSlot.BARREL), &"", "the slot is blank again")
	# ⭐LOSSLESS: the fold restarts from the pristine template every time, so a stripped gun is the authored gun
	# to the last bit — no accumulated float drift, however many times it is fitted and pulled.
	assert_almost_eq(gun.weapon.effective_range, base_range, 0.0001, "stripping returns EXACTLY the authored value")
	# What comes back is the SHARED registered template: a part is a stacking MISC item, and a duplicate would
	# quietly stop stacking with the ones already in the pack.
	assert_true(p.inventory.has(barrel), "the part is back in the pack")
	assert_same(ItemDb.item_by_id(P_BARREL), barrel, "and it is the shared template, so it still stacks")
	# Nothing fitted -> nothing to remove.
	assert_false(b.remove_mod(gun, WeaponData.ModSlot.BARREL, p), "an empty slot has nothing to give back")
	_teardown(b, p)
	gun = null
	barrel = null


# --- The payment seam ------------------------------------------------------------------------------------

func test_can_afford_is_fed_the_RAW_base_and_agrees_with_the_till() -> void:
	# ⭐Fed the RAW base: Player.can_pay folds the ledger service charge in itself, so passing quoted_total's
	# output would fee the fee and falsely refuse a purchase the till would actually serve.
	var b := _bench()
	var p := _player(100.0)
	assert_true(b.can_afford(0.0, p), "a free service always clears (the Character.charge convention)")
	assert_true(b.can_afford(100.0, p), "exactly affordable in cash")
	assert_false(b.can_afford(101.0, p), "a zorkmid over is refused")
	assert_false(b.can_afford(10.0, null), "a null player affords nothing")
	# ⭐THE RAW-BASE EDGE, made executable: a player whose savings hold EXACTLY the all-in number the row quotes
	# must be served. Fee-the-fee (can_afford fed the quote) refuses precisely this player.
	p.money = 0.0
	GameState.account = 10000.0  # quote under a comfortable balance; the service charge depends on the split, not the balance
	var all_in := b.quoted_total(100.0, p)
	assert_gt(all_in, 100.0, "precondition: an account-funded job carries a service charge, or this edge proves nothing")
	GameState.account = all_in
	assert_true(b.can_afford(100.0, p),
			"⭐a player holding exactly the quoted all-in total must NOT be dimmed out — the bench feeds the raw base, never the quote")
	assert_true(b.take_payment(100.0, p), "...because the till really does serve them")
	assert_almost_eq(GameState.account, 0.0, 0.001, "and it takes exactly the quoted all-in total, no more")
	# ⭐accepts_ledger rides through as can_pay's `allow_credit`: cash and banked savings are reachable either
	# way, and what the flag gates is whether the till will LEND (LevelUp.accepts_credit's semantics).
	p.money = 100.0
	GameState.account = 500.0
	assert_true(b.can_afford(400.0, p), "a bench reaches banked savings")
	b.accepts_ledger = false
	assert_true(b.can_afford(400.0, p), "...and still does with credit refused — savings are not borrowed money")
	var purse_before: float = p.money + GameState.account
	assert_true(b.take_payment(400.0, p), "a non-lending till still actually charges a job its savings cover")
	assert_true(GameState.account >= 0.0, "...without carrying the account past zero (%s)" % GameState.account)
	assert_lt(p.money + GameState.account, purse_before, "...and the money really left")
	p.money = 100.0
	# Now put the account in the red and arm CREDIT: only a lending bench can serve.
	GameState.account = 0.0
	GameState.payment_method = "credit"
	p.money = 0.0
	var on_the_line := p.credit_left()
	if on_the_line > 1.0:
		b.accepts_ledger = true
		assert_true(b.can_afford(1.0, p), "a lending bench reaches the armed credit line")
		b.accepts_ledger = false
		assert_false(b.can_afford(1.0, p), "⭐a non-lending bench refuses to put the player in the red")
	_teardown(b, p)

func test_quoted_total_is_the_all_in_number() -> void:
	var b := _bench()
	var p := _player(0.0)
	GameState.account = 1000.0
	# All of it rides the ledger, so the quote carries the service charge the dim does NOT price.
	var base := 100.0
	var quote := b.quoted_total(base, p)
	assert_gte(quote, base, "an account-funded charge is never cheaper than its sticker price")
	# ROUND TRIP: the number painted on the row is the number that leaves the player when the till runs.
	assert_true(b.take_payment(base, p), "the quoted job is served")
	assert_almost_eq(1000.0 - GameState.account, quote, 0.001, "the row paints exactly what actually leaves the player (all-ledger)")
	# ...and on a SPLIT tender too: cash first (fee-free), the rest off the account.
	p.money = 40.0
	GameState.account = 1000.0
	var split_quote := b.quoted_total(base, p)
	assert_true(split_quote < quote, "cash covers part of the job fee-free, so the split quote is cheaper than the all-ledger one")
	assert_true(b.take_payment(base, p), "the split job is served")
	assert_almost_eq((40.0 - p.money) + (1000.0 - GameState.account), split_quote, 0.001,
			"cash spent plus account spent is exactly the quoted total")
	p.money = 0.0
	GameState.account = 1000.0
	assert_eq(b.quoted_total(0.0, p), 0.0, "a free service quotes nothing")
	assert_eq(b.quoted_total(base, null), base, "a null player degrades to the raw base, never to a crash")
	_teardown(b, p)

func test_sell_price_is_invariant_across_a_refit() -> void:
	# ⭐THE WHOLE CREDIT-SAFETY ARGUMENT for accepts_ledger = true, made executable. Merchant prices entirely
	# off Item.value, which a refit never touches — so a gun bought on credit and modded up cannot be sold back
	# for more than a stock one. If anyone ever prices vendor trades off WeaponData.power_score(), this fails
	# and the buy-on-credit / sell-back laundering loop is caught here rather than in a live economy.
	var b := _bench()
	var p := _player(1000.0)
	var gun := _gun()
	var shop := Merchant.new()
	var before_sell := shop.sell_price(gun, null)
	var before_buy := shop.buy_price(gun, null)
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL, 400.0)
	p.inventory.add(barrel, 1)
	assert_true(b.fit_mod(gun, barrel, p), "mod the gun up")
	assert_gt(gun.weapon.power_score(), 0.0, "sanity: the folded block is a real weapon")
	assert_eq(shop.sell_price(gun, null), before_sell, "a modded gun resells for EXACTLY what a stock one does")
	assert_eq(shop.buy_price(gun, null), before_buy, "...and costs exactly the same to buy back")
	shop.free()
	_teardown(b, p)
	gun = null
	barrel = null


# --- The screen's contract surface ---------------------------------------------------------------------------

func test_refusal_reason_returns_keys_not_labels() -> void:
	# ⭐KEYS, never display labels: PlayerText.bench_notice selects the sentence, so the band can be re-worded
	# or translated without touching a branch here. Every key the screen can receive is enumerated.
	const KEYS := [&"draw_locked", &"no_weapons", &"slot_taken", &"stat_gate", &"bag_full", &"afford", &"unfit", &""]
	var b := _bench()
	var p := _player(0.0)
	var gun := _gun()
	assert_eq(b.refusal_reason(null, null, p), &"no_weapons", "no gun selected -> the empty-pack key")
	# A part for a weapon it was not authored for.
	var wrong: Array[StringName] = [&"shotgun"]
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL, 100.0, wrong)
	p.inventory.add(barrel, 1)
	assert_eq(b.refusal_reason(gun, barrel, p), &"unfit", "a part that does not fit this weapon")
	# A fitting part with an empty wallet.
	var muzzle := _part(P_MUZZLE, WeaponData.ModSlot.MUZZLE)
	p.inventory.add(muzzle, 1)
	assert_eq(b.refusal_reason(gun, muzzle, p), &"afford", "a fitting part the player cannot pay for")
	p.money = 1000.0
	assert_eq(b.refusal_reason(gun, muzzle, p), &"", "and blank once it is affordable — blank means 'go ahead'")
	assert_eq(b.refusal_reason(gun, null, p), &"", "the gun-level question is clear too")
	for key in [b.refusal_reason(null, null, p), b.refusal_reason(gun, barrel, p), b.refusal_reason(gun, muzzle, p)]:
		assert_true(KEYS.has(key), "'%s' is not one of the enumerated refusal keys — the Notice band would render nothing" % key)
		assert_eq(typeof(key), TYPE_STRING_NAME, "a refusal reason is a StringName KEY, never a display String")
	_teardown(b, p)
	gun = null
	barrel = null
	muzzle = null

func test_duck_type_surface() -> void:
	# WeaponBenchScreen reaches the bench on a bare `Node` (a typed ref would close a Component <-> Screen
	# compile cycle), so every one of these is a has_method call whose rename fails SILENTLY at press time.
	var b := _bench()
	for m in ["fit_mod", "buy_and_fit", "remove_mod", "fit_fee", "buy_and_fit_cost", "remove_fee",
			"can_afford", "quoted_total", "moddable_weapons", "fittable_parts", "stock_parts",
			"fitted_parts", "refusal_reason"]:
		assert_true(b.has_method(m), "WeaponBenchScreen duck-calls %s() — a rename kills that surface with no compile error" % m)
	b.stock.free()
	b.free()

## A WeaponBench driven through its REAL _ready. Parented to a throwaway Node3D rather than straight to the GUT
## scene (the test_atm idiom), so _build_outline's host-mesh walk stays inside an empty two-node subtree. A bench
## is a plain station component — unlike a Player or NPC, its _ready builds only a stock inventory, a hitbox
## layer, a speaker and a map pin, all headless-safe.
func _bench_in_tree(standalone: bool) -> WeaponBench:
	var host := Node3D.new()
	var b := WeaponBench.new()
	b.standalone = standalone
	host.add_child(b)
	add_child_autofree(host)  # tree entry fires _ready
	return b

## ⭐THE ZERO-AUTHORING MINIMAP PROMISE: a station that forgets to ask for its pin is invisible on the map with
## nothing else failing. The pin is UNGATED by `standalone` (a gunsmith riding a walking NPC is still somewhere to
## modify a gun), while the talk-layer hitbox and the kiosk chirp ARE gated on it (the NPC's Talkable owns the ray,
## and people do not beep). Both flavours, so a pin moved inside the `standalone` branch fails here.
func test_both_bench_flavours_pin_the_minimap_but_only_the_kiosk_takes_the_ray_and_beeps() -> void:
	var kiosk := _bench_in_tree(true)
	var smith := _bench_in_tree(false)
	for b: WeaponBench in [kiosk, smith]:
		var flavour := "standalone" if b.standalone else "dialogue-hosted"
		var pin := StationMarker.find_marker(b)
		assert_true(pin != null,
				"⭐the %s bench must put itself on the minimap — without its pin the gunsmith is invisible on the map" % flavour)
		if pin != null:
			assert_eq(pin.kind, StationMarker.Kind.TECH, "the %s bench's pin is a TECH station glyph" % flavour)
	var kiosk_pin := StationMarker.find_marker(kiosk)
	var smith_pin := StationMarker.find_marker(smith)
	if kiosk_pin != null and smith_pin != null:
		assert_true(kiosk_pin.pin_offscreen, "a fixed bench points at itself from the minimap rim")
		assert_false(smith_pin.pin_offscreen, "a gunsmith riding an NPC is a body: clipped to the box like every other body")
	assert_eq(kiosk.collision_layer, TalkHelpers.TALK_LAYER, "a standalone bench sits on the talk layer so aiming + Interact opens it")
	assert_eq(smith.collision_layer, 0, "a dialogue-hosted bench must NOT catch the ray — the NPC's Talkable drives access")
	assert_true(StationSpeaker.find_speaker(kiosk) != null, "a self-serve bench answers with the shared panel chirp")
	assert_true(StationSpeaker.find_speaker(smith) == null, "a bench riding a talking NPC does not beep")
	assert_true(kiosk.stock != null and smith.stock != null, "both flavours build their shelf inventory in _ready")

func test_dialogue_order_sits_between_install_and_play_chess() -> void:
	# The free slot between ChipInstaller and ChessMatch: "Modify" (chrome for your gear) right after "Install"
	# (chrome for yourself). A const, not an @export: two authored instances must not be able to collide and
	# silently reshuffle the speaker's menu. The real sort is proven in test_dialogue_speaker_contracts.gd; here
	# the RELATION is stated against the neighbours' own consts, so renumbering the whole band stays green.
	assert_gt(WeaponBench.DIALOGUE_ORDER, ChipInstaller.DIALOGUE_ORDER, "Modify must sort after Install")
	assert_lt(WeaponBench.DIALOGUE_ORDER, ChessMatch.DIALOGUE_ORDER, "Modify must sort before Play Chess")
	var b := _bench()
	var opt := b.dialogue_station_option()
	assert_eq(int(opt.get("order", -1)), WeaponBench.DIALOGUE_ORDER, "the painted option carries the order the bench advertises")
	assert_eq(typeof(opt.get("closed")), TYPE_SIGNAL, "a suspending station must hand over a resume Signal")
	b.stock.free()
	b.free()

func test_bench_prefab_can_instantiate() -> void:
	var packed := load(BENCH_SCENE) as PackedScene
	assert_not_null(packed, "the shipped gunsmith prefab must exist at %s" % BENCH_SCENE)
	if packed != null:
		assert_true(packed.can_instantiate(), "the gunsmith prefab must instantiate (a broken ext_resource fails here)")

func test_a_modded_weapon_data_never_reaches_ItemDb_by_weapon() -> void:
	# ⭐A folded WeaponData is NOT a registered template. make_weapon_item(folded) would return null, which is
	# how a modded block written into SwapWeapons.weapon_slots or an NPC's weapon_data export would strand the
	# actor: the player seeds no starting weapon, the NPC stays is_armed() == false with an invisible gun.
	var b := _bench()
	var p := _player(1000.0)
	var gun := _gun()
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL)
	p.inventory.add(barrel, 1)
	assert_true(b.fit_mod(gun, barrel, p), "mod the gun")
	assert_null(ItemDb.weapon_item_for(gun.weapon), "a folded block is not in the _by_weapon registry")
	assert_null(ItemDb.make_weapon_item(gun.weapon), "...so make_weapon_item on it yields null, as the seeds would see")
	assert_not_null(ItemDb.item_by_id(gun.id), "but the Item.id still resolves — which is why the save keys on the ID")
	# Both production seeds must keep building from AUTHORED templates. Driven for real (both seed functions run
	# off-tree): a fresh player whose weapon hub is currently HOLDING the folded block, and whose authored
	# SwapWeapons loadout is the pistol template, must still spawn with a pistol in the pack — a seed that read the
	# live block would get null back and spawn the player unarmed.
	var tmpl_weapon: WeaponData = ItemDb.item_by_id(GUN_ID).weapon
	var fresh := _player(0.0)
	var sw := SwapWeapons.new()
	sw.name = "SwapWeapons"
	var slots: Array[Resource] = [tmpl_weapon]
	sw.weapon_slots = slots
	var ws := Weapon.new()
	ws.add_child(sw)
	ws.inventory = Inventory.new()
	ws.inventory.equipped_weapon = gun.weapon  # the live, MODDED block is what the hub holds
	fresh.weapon_system = ws
	fresh._seed_starting_inventory()
	assert_eq(_weapon_ids_in(fresh.inventory), [GUN_ID],
			"⭐a player spawned after a refit still seeds the authored pistol from the loadout, never from the live folded block")
	fresh.weapon_system = null
	ws.inventory.free()
	ws.free()  # frees the SwapWeapons child
	fresh.inventory.free()
	fresh.free()
	# ...and an NPC authored with the pistol template still arms itself after a bench has modded some other pistol.
	var npc: NPC = load("res://scripts/npc/npc.gd").new()  # never added to the tree: NPC._ready must not run
	npc.inventory = CharacterInventory.new()
	npc.weapon_data = tmpl_weapon
	npc._equip_initial_weapon()
	assert_eq(_weapon_ids_in(npc.inventory), [GUN_ID],
			"⭐an NPC authored with the pistol template still seeds its gun after a refit — a modding session must never leave an NPC unarmed")
	npc.inventory.free()
	npc.free()
	_teardown(b, p)
	gun = null
	barrel = null

## The Item ids of every WEAPON stack in `inv`, in bag order.
func _weapon_ids_in(inv: CharacterInventory) -> Array:
	var out: Array = []
	for e in inv.contents():
		var it: Item = e.get("item")
		if it != null and it.is_weapon():
			out.append(it.id)
	return out


# --- The paint the player actually sees ------------------------------------------------------------------------

## ⭐⭐A PAID-FOR FIT MUST BE ON THE CARD, and until 2026-09-08 it was not: you clicked, the money left, the part
## left your pack — and the FITTED row still read "— empty —".
##
## The screen used to leave its refresh entirely to the signals WeaponBenchScreen._bind subscribes to, and every
## one of them fires at the wrong moment. fit_mod commits in the order
##     take_payment()  ->  source.remove(part, 1)  ->  _refit(...)
## so the bag's `changed` lands on the MIDDLE line and the rebuild it triggers reads a gun that has not gained
## the part yet. _refit re-equips — which would emit `weapon_changed` and repaint again — ONLY when the gun is
## DRAWN, so for a gun merely sitting in the pack that stale paint was the LAST one. (And on the SHIPPED bench,
## which is dialogue-hosted, even the drawn path is not safe: the conversation pauses the tree and Attack's swap
## Timer never ticks.) The fix is WeaponBenchScreen._settle — repaint our own success instead of trusting a
## signal that fires mid-transaction.
##
## ⭐This drives the REAL authored card in a SubViewport rather than asserting the component's end state, because
## the component's end state was always correct — the defect only ever existed in what the player was LOOKING at.
## open_bench is bypassed on purpose: it wants the live modal stack and would grab the real mouse cursor out of
## a headless run. Everything below _rebuild is the genuine paint path.
func test_a_paid_fit_shows_up_on_the_card_immediately() -> void:
	var b := _bench()
	var p := _player(500.0)
	var gun := _gun()
	var barrel := _part(P_BARREL, WeaponData.ModSlot.BARREL, 100.0)
	p.inventory.add(gun, 1)
	p.inventory.add(barrel, 1)

	var vp := SubViewport.new()
	vp.size = Vector2i(792, 445)
	vp.disable_3d = true
	add_child_autofree(vp)
	var card: CanvasLayer = (load(SCREEN_SCENE) as PackedScene).instantiate()
	vp.add_child(card)
	await wait_process_frames(1)
	card._bench = b
	card._player = p
	card._sel_gun = gun
	card._is_open = true
	(card.get_node("%Root") as Control).visible = true
	card._rebuild()
	await wait_process_frames(1)

	assert_does_not_have(_fitted_names(card), barrel.label(), "the barrel slot starts EMPTY on the card")
	assert_has(_parts_names(card), barrel.label(), "and the carried barrel starts in the PARTS section")

	card._fit(barrel)
	await wait_process_frames(1)
	assert_has(_fitted_names(card), barrel.label(),
		"⭐the fitted part must appear in the FITTED section the instant the fit is paid for — the card must never show an empty slot over a transaction the player has already been charged for")
	assert_does_not_have(_parts_names(card), barrel.label(), "and it must leave the PARTS section, which no longer carries it")

	card._remove(WeaponData.ModSlot.BARREL)
	await wait_process_frames(1)
	assert_does_not_have(_fitted_names(card), barrel.label(),
		"⭐and a paid-for REMOVAL must clear the slot on the card — leaving it painted fitted offers a live remove row for a part that is already back in the pack")
	assert_has(_parts_names(card), barrel.label(), "the part is back in the PARTS section, where it can be re-fitted")

	card._is_open = false
	card._bench = null
	card._player = null
	card._sel_gun = null
	_teardown(b, p)
	gun = null
	barrel = null

## The NAME column of every row currently painted in one of the card's two sections. Reaches through the row
## Button's single HBox child (slot, name, price — the _make_row shape); a section holding only its
## "(none)" hint Label contributes nothing, which is exactly the answer those cases want.
func _row_names(list: VBoxContainer) -> Array:
	var out: Array = []
	for row in list.get_children():
		if row is Button and row.get_child_count() > 0:
			var hb: Node = row.get_child(0)
			if hb.get_child_count() >= 2 and hb.get_child(1) is Label:
				out.append((hb.get_child(1) as Label).text)
	return out

func _fitted_names(card: Node) -> Array:
	return _row_names(card.get_node("%FittedList") as VBoxContainer)

func _parts_names(card: Node) -> Array:
	return _row_names(card.get_node("%PartsList") as VBoxContainer)


# --- The bench the player can actually walk up to ---------------------------------------------------------------

## ⭐⭐THE SHIPPED BENCH MUST HAVE SOMETHING ON THE SHELF. Every other test in this file builds its own bench with
## a hand-seeded stock, so all of them stayed green while the bench the PLAYER meets was dead content: the only
## WeaponBench instanced in a level carried `standalone = false` and nothing else — no `stock_counts` — and no
## mod_*.tres appeared in any loot table or shop stock anywhere in the project. The PARTS section could only ever
## render "(none)" and FITTED was six permanently-dim empty slots, on a screen that was otherwise working.
## scenes/characters/weapon_mechanic.tscn DID author a shelf, which is exactly why nobody noticed — it is a
## prefab that is never instanced in any level.
##
## Read out of the LEVEL's SceneState rather than by instantiating it: the level is a func_godot map with a nav
## bake, far too heavy for a unit test, and the authored property is all this needs to see.
func test_the_level_bench_actually_stocks_parts() -> void:
	var st: SceneState = (load(LEVEL_SCENE) as PackedScene).get_state()
	var benches := 0
	for i in st.get_node_count():
		if st.get_node_name(i) != &"WeaponBench":
			continue
		benches += 1
		var stock: Array = []
		for j in st.get_node_property_count(i):
			if st.get_node_property_name(i, j) == &"stock_counts":
				stock = st.get_node_property_value(i, j)
		assert_gt(stock.size(), 0,
			"⭐the WeaponBench at %s ships with an EMPTY shelf — a bench with no stock and no lootable parts in the world is a menu that can never do anything" % st.get_node_path(i))
		for e in stock:
			var part: Item = e.item
			assert_not_null(part, "every StockEntry on the level bench carries an item")
			assert_true(part.is_weapon_mod(), "%s is a weapon PART (it carries a WeaponMod payload)" % part.id)
			assert_gt(part.value, 0.0,
				"%s must be priced — _offered_parts drops a value<=0 part so the fee can never be a permanently-dead '0 zm' row" % part.id)
			assert_gt(e.count, 0, "%s is stocked in a usable quantity" % part.id)
	assert_gt(benches, 0, "the level still instances a WeaponBench — if it was removed, this pin is stale")

## And the shelf must fit a gun the player can actually be holding, or every row dims for a different reason.
func test_the_level_bench_stock_fits_a_weapon_the_player_can_carry() -> void:
	var st: SceneState = (load(LEVEL_SCENE) as PackedScene).get_state()
	var b := _bench()
	var p := _player(5000.0)
	var served: Array[StringName] = []
	for i in st.get_node_count():
		if st.get_node_name(i) != &"WeaponBench":
			continue
		for j in st.get_node_property_count(i):
			if st.get_node_property_name(i, j) != &"stock_counts":
				continue
			for e in (st.get_node_property_value(i, j) as Array):
				b.stock.add(e.item, e.count)
	for gun_id: StringName in [&"pistol", &"smg", &"shotgun", &"sniper"]:
		var tmpl := ItemDb.item_by_id(gun_id)
		if tmpl == null or not tmpl.is_weapon():
			continue
		if not (b.stock_parts(tmpl.clone_unique(), p) as Array).is_empty():
			served.append(gun_id)
	assert_gt(served.size(), 0,
		"⭐the level bench's shelf must fit at least one shipped weapon — a shelf of parts that fit nothing renders the same empty card as no shelf at all. Served: %s" % str(served))
	_teardown(b, p)
