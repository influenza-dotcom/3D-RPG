extends GutTest

## Contract tests for PassiveItemBuffs — the Dota-style "carry it, get the buff" pool. Built OFF-TREE per the
## project test rules (never run a Character/_ready in a unit test): a Node stub host + a real
## CharacterInventory, then _recompute() is driven directly. Covers the seams a held-item buff depends on:
## count-scaling, the `unique` cap, the speed-multiplier product, the strength re-stamp onto max_hp + carry
## (including the wounded-removal clamp), and the id/no-buff guards.

## Minimal duck-typed host — PassiveItemBuffs only reads _host.inventory and re-stamps max_hp/hp/carry_capacity
## via get/set, exactly like PerkManager, so these four fields are all it needs. A Node (PassiveItemBuffs._host is
## typed Node), built off-tree and freed explicitly (it has no `damaged` signal, so the re-stamp's HUD emit no-ops).
class _StubHost:
	extends Node
	var inventory
	var max_hp: float = 10.0
	var hp: float = 10.0
	var carry_capacity: float = 5.0

var _inv: CharacterInventory
var _pib: PassiveItemBuffs
var _host_stub: _StubHost

func before_each() -> void:
	_inv = CharacterInventory.new()  # off-tree: add()/contents()/count_of_id() need no _ready, grid stays off

func after_each() -> void:
	if _pib != null:
		_pib.free()
		_pib = null
	if _host_stub != null:
		_host_stub.free()  # a Node stub isn't ref-counted — free it explicitly
		_host_stub = null
	if _inv != null:
		_inv.free()
		_inv = null

## Build a MISC item whose held_passive_effect carries `mods` (+ optional unique / speed_multiplier).
func _make_item(id: StringName, mods: Dictionary, unique := false, speed := 1.0) -> Item:
	var fx := StatusEffect.new()
	fx.id = StringName("held_" + String(id))
	fx.duration = 0.0
	fx.stat_modifiers = mods
	fx.speed_multiplier = speed
	var it := Item.new()
	it.id = id
	it.display_name = String(id)
	it.category = Item.Category.MISC
	it.max_stack = 9
	it.held_passive_effect = fx
	it.passive_unique = unique
	return it

## Fresh pool over the current _inv, recomputed once. Read back host fields via _pib._host.
func _recompute() -> PassiveItemBuffs:
	_host_stub = _StubHost.new()
	_host_stub.inventory = _inv
	_pib = PassiveItemBuffs.new()
	_pib._host = _host_stub
	_pib._recompute()
	return _pib

func test_live_stat_sums_by_count() -> void:
	_inv.add(_make_item(&"charm", {"agility": 1}), 2)
	var pib := _recompute()
	assert_almost_eq(pib.stat_modifier(&"agility"), 2.0, 0.001, "two copies -> 2x agility (additive stacking)")

func test_endurance_is_exposed_as_live_stat() -> void:
	_inv.add(_make_item(&"cell", {"endurance": 2}), 1)
	var pib := _recompute()
	assert_almost_eq(pib.stat_modifier(&"endurance"), 2.0, 0.001, "held endurance stays in the live stat pool for stamina_max")

func test_unique_flag_caps_at_one() -> void:
	_inv.add(_make_item(&"boots", {"gunplay": 2}, true), 3)
	var pib := _recompute()
	assert_almost_eq(pib.stat_modifier(&"gunplay"), 2.0, 0.001, "a unique item counts once regardless of stack size")

func test_speed_multiplier_is_product() -> void:
	_inv.add(_make_item(&"haste", {}, false, 1.5), 2)
	var pib := _recompute()
	assert_almost_eq(pib.speed_multiplier(), 2.25, 0.001, "two 1.5x speed items compound to 2.25x")

func test_strength_restamps_max_hp() -> void:
	_inv.add(_make_item(&"locket", {"strength": 2}), 1)  # +2 strength -> +2*HP_PER_STRENGTH = +3 max HP
	var pib := _recompute()
	assert_almost_eq(pib._host.max_hp, 13.0, 0.001, "+2 strength adds 3 max HP (matches a level-up of the same size)")
	assert_almost_eq(pib._host.hp, 13.0, 0.001, "held +HP heals up to the new max on a full-HP carrier")

func test_strength_restamps_carry() -> void:
	_inv.add(_make_item(&"pack", {"strength": 3}), 1)  # +3 strength -> +3*CARRY_PER_STRENGTH = +6 carry
	var pib := _recompute()
	assert_almost_eq(pib._host.carry_capacity, 11.0, 0.001, "+3 strength adds 6 carry capacity")

func test_strength_absent_from_live_pool() -> void:
	_inv.add(_make_item(&"locket", {"strength": 5}), 1)
	var pib := _recompute()
	assert_almost_eq(pib.stat_modifier(&"strength"), 0.0, 0.001, "strength is re-stamped onto max_hp + carry, not exposed as a live modifier")

func test_dropping_hp_item_while_wounded_clamps() -> void:
	var item := _make_item(&"locket", {"strength": 2})  # +3 max HP
	_inv.add(item, 1)
	var pib := _recompute()          # max 13, hp 13
	pib._host.hp = 5.0               # take damage down to 5
	_inv.remove(item, 1)             # drop the trinket
	pib._recompute()                 # removal delta -3: max back to 10, hp = clampf(5-3, 1, 10) = 2
	assert_almost_eq(pib._host.max_hp, 10.0, 0.001, "removing the +HP item restores base max HP exactly")
	assert_almost_eq(pib._host.hp, 2.0, 0.001, "hp drops by the same delta, clamped to >= 1 (no over-heal, no death)")

func test_negative_strength_telescopes_through_hp_floor() -> void:
	# A cursed/heavy trinket with a big NEGATIVE strength drives max HP into its 1.0 floor. Because the pool tracks
	# the delta ACTUALLY applied (not the ideal -15), dropping it must restore EXACTLY the base max HP — never inflate.
	var item := _make_item(&"cursed", {"strength": -10})  # ideal -15 HP; max_hp floors at 1 (base 10)
	_inv.add(item, 1)
	var pib := _recompute()
	assert_almost_eq(pib._host.max_hp, 1.0, 0.001, "negative strength floors max HP at 1, not below")
	_inv.remove(item, 1)
	pib._recompute()
	assert_almost_eq(pib._host.max_hp, 10.0, 0.001, "dropping the cursed item restores base max HP exactly (no inflation)")

func test_negative_strength_floors_carry_and_telescopes() -> void:
	# Mirror of the HP floor case for carry_capacity (floored at 0, matching Character._apply_stats).
	var item := _make_item(&"anchor", {"strength": -10})  # ideal -20 carry; carry floors at 0 (base 5)
	_inv.add(item, 1)
	var pib := _recompute()
	assert_almost_eq(pib._host.carry_capacity, 0.0, 0.001, "negative strength floors carry capacity at 0")
	_inv.remove(item, 1)
	pib._recompute()
	assert_almost_eq(pib._host.carry_capacity, 5.0, 0.001, "dropping restores base carry capacity exactly")

func test_empty_id_passive_ignored() -> void:
	var fx := StatusEffect.new()
	fx.stat_modifiers = {"agility": 5}
	var it := Item.new()
	it.id = &""  # no id -> can't be counted by kind or save/load-tracked, so the passive is skipped
	it.category = Item.Category.MISC
	it.max_stack = 9
	it.held_passive_effect = fx
	_inv.add(it, 1)
	var pib := _recompute()
	assert_almost_eq(pib.stat_modifier(&"agility"), 0.0, 0.001, "a blank-id item grants no passive")

func test_plain_item_is_noop() -> void:
	var plain := Item.new()
	plain.id = &"junk"
	plain.category = Item.Category.MISC
	plain.max_stack = 9
	_inv.add(plain, 3)
	var pib := _recompute()
	assert_almost_eq(pib.stat_modifier(&"agility"), 0.0, 0.001, "an item with no held_passive_effect does nothing live")
	assert_almost_eq(pib._host.max_hp, 10.0, 0.001, "max HP untouched with no buff items held")

func test_exposes_ducktyped_buff_source_surface() -> void:
	# Character.status_stat_modifier / status_move_multiplier match a child exposing these three; the pool must too.
	var pib := PassiveItemBuffs.new()
	assert_true(pib.has_method(&"stat_modifier"), "buff source exposes stat_modifier")
	assert_true(pib.has_method(&"speed_multiplier"), "buff source exposes speed_multiplier")
	assert_true(pib.has_method(&"apply_effect"), "buff source exposes the apply_effect sentinel the scanner keys on")
	pib.free()
