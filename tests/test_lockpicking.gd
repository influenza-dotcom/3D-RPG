extends GutTest

## Locks — the Lock component + the shared LockRules decision that Lock AND Door both apply. A lock separates two
## independent capabilities: a KEY (an optional item that opens it outright) and PICKABILITY (whether a lockpick
## works at all). So a lock is pickable-only (the default), key-only, BOTH (a carried key TAKES PRECEDENCE over a
## lockpick), or SEALED (no key, not pickable — flag/script only). This pins that rule so key-vs-pick can't regress.

const LockRules = preload("res://scripts/components/lock_rules.gd")

## A minimal opener: carries a backpack, no toast surface (the lock null-guards notify_toast).
class _Opener extends Node:
	var inventory: CharacterInventory

func _item(id: StringName) -> Item:
	var it := Item.new()
	it.id = id
	it.display_name = String(id).capitalize()
	it.max_stack = 10
	return it

func _opener_with(ids: Array) -> _Opener:
	var o := _Opener.new()
	o.inventory = CharacterInventory.new()
	for id in ids:
		o.inventory.add(_item(id), 1)
	return o


# ---------------------------------------------------------------------------
# LockRules.decide — the pure, shared rule (no autoloads, no mutation).
# ---------------------------------------------------------------------------

func test_find_by_id_locates_a_carried_kind() -> void:
	var inv := CharacterInventory.new()
	inv.add(_item(&"lockpick"), 2)
	assert_not_null(inv.find_by_id(&"lockpick"), "find_by_id resolves a carried item by its Item.id")
	assert_null(inv.find_by_id(&"keycard_red"), "an id the bag doesn't hold reads null")
	assert_null(inv.find_by_id(&""), "the empty id never matches")
	inv.free()

func test_decide_pickable_only() -> void:
	var inv := CharacterInventory.new()
	assert_eq(int(LockRules.decide(inv, &"", true, &"lockpick")["outcome"]), LockRules.Outcome.DENY_PICK,
		"pickable, no pick carried -> DENY_PICK")
	inv.add(_item(&"lockpick"), 1)
	var d := LockRules.decide(inv, &"", true, &"lockpick")
	assert_eq(int(d["outcome"]), LockRules.Outcome.OPEN_PICK, "pickable + a lockpick -> OPEN_PICK")
	assert_eq(d["item"].id, &"lockpick", "...and hands back the pick to consume")
	inv.free()

func test_decide_key_only() -> void:
	var inv := CharacterInventory.new()
	inv.add(_item(&"lockpick"), 1)  # holding a lockpick must NOT open a non-pickable key lock
	assert_eq(int(LockRules.decide(inv, &"keycard_red", false, &"lockpick")["outcome"]), LockRules.Outcome.DENY_KEY,
		"key-only lock, no key (a lockpick doesn't count) -> DENY_KEY")
	inv.add(_item(&"keycard_red"), 1)
	assert_eq(int(LockRules.decide(inv, &"keycard_red", false, &"lockpick")["outcome"]), LockRules.Outcome.OPEN_KEY,
		"the matching key -> OPEN_KEY")
	inv.free()

func test_decide_key_takes_precedence_over_pick() -> void:
	var inv := CharacterInventory.new()
	inv.add(_item(&"keycard_red"), 1)
	inv.add(_item(&"lockpick"), 1)
	var d := LockRules.decide(inv, &"keycard_red", true, &"lockpick")  # BOTH keyed and pickable, carrying BOTH
	assert_eq(int(d["outcome"]), LockRules.Outcome.OPEN_KEY,
		"carrying the key AND a lockpick -> the KEY opens it (precedence), never the pick")
	assert_eq(d["item"].id, &"keycard_red", "...and the KEY is handed back to (optionally) consume, not the pick")
	inv.free()

func test_decide_key_or_pick_fallback_and_deny() -> void:
	var inv := CharacterInventory.new()
	inv.add(_item(&"lockpick"), 1)  # keyed+pickable, no key but a pick -> pick it
	assert_eq(int(LockRules.decide(inv, &"keycard_red", true, &"lockpick")["outcome"]), LockRules.Outcome.OPEN_PICK,
		"keyed AND pickable, no key but a lockpick -> fall back to picking")
	inv.free()
	var empty := CharacterInventory.new()
	assert_eq(int(LockRules.decide(empty, &"keycard_red", true, &"lockpick")["outcome"]), LockRules.Outcome.DENY_KEY_OR_PICK,
		"keyed AND pickable, carrying neither -> DENY_KEY_OR_PICK (the toast names both)")
	empty.free()

func test_decide_sealed_and_null_inventory() -> void:
	var inv := CharacterInventory.new()
	inv.add(_item(&"lockpick"), 1)
	assert_eq(int(LockRules.decide(inv, &"", false, &"lockpick")["outcome"]), LockRules.Outcome.DENY_SEALED,
		"no key + not pickable = sealed, even holding a lockpick")
	assert_eq(int(LockRules.decide(null, &"", true, &"lockpick")["outcome"]), LockRules.Outcome.DENY_PICK,
		"a null inventory is safe (never crashes) — just can't produce the item")
	inv.free()


# ---------------------------------------------------------------------------
# Lock component — applies the rule, consumes the right item, toasts, persists.
# ---------------------------------------------------------------------------

func test_lock_defaults_and_discovery() -> void:
	var host := Node.new()
	assert_null(Lock.of(host), "a host with no Lock child reads null (unlocked behaviour)")
	var lock := Lock.new()
	host.add_child(lock)
	assert_eq(Lock.of(host), lock, "Lock.of finds the host's Lock child — how any interactable checks itself")
	assert_true(lock.locked, "a fresh Lock starts locked")
	assert_true(lock.pickable, "and is PICKABLE by default (the classic lockpick lock)")
	assert_eq(lock.key_item_id, &"", "with NO key required by default (key is opt-in)")
	assert_eq(lock.lockpick_item_id, &"lockpick", "picked by the generic lockpick by default")
	assert_true(lock.consumes_pick, "a pick snaps on success by default")
	assert_false(lock.consume_key, "a key is reusable by default")
	host.free()

func test_lock_pick_consumes_and_opens_once() -> void:
	var lock := Lock.new()
	var opener := _opener_with([])
	assert_false(lock.try_unlock(opener), "no pick carried -> the lock holds")
	assert_true(lock.locked, "...and stays locked")
	opener.inventory.add(_item(&"lockpick"), 2)
	watch_signals(lock)
	assert_true(lock.try_unlock(opener), "carrying a pick -> the pickable lock opens")
	assert_false(lock.locked, "the lock is now PERMANENTLY open")
	assert_eq(opener.inventory.count_of_id(&"lockpick"), 1, "one pick is consumed (snapped) on success")
	assert_signal_emitted(lock, "unlocked", "unlocked fires once — a door swings open on this")
	assert_true(lock.try_unlock(opener), "an already-open lock is a free pass")
	assert_eq(opener.inventory.count_of_id(&"lockpick"), 1, "...and consumes nothing more")
	opener.inventory.free()
	opener.free()
	lock.free()

func test_lock_keyed_and_pickable_key_wins_and_is_reusable() -> void:
	var lock := Lock.new()
	lock.key_item_id = &"keycard_red"  # keyed AND still pickable (the default) — the exact "key OR pick" case
	var opener := _opener_with([&"keycard_red", &"lockpick"])
	watch_signals(lock)
	assert_true(lock.try_unlock(opener), "carrying the key opens it")
	assert_signal_emitted(lock, "unlocked", "a key turn fires unlocked too")
	assert_eq(opener.inventory.count_of_id(&"keycard_red"), 1, "a reusable key is NOT consumed")
	assert_eq(opener.inventory.count_of_id(&"lockpick"), 1, "the lockpick is UNTOUCHED — the key took precedence")
	opener.inventory.free()
	opener.free()
	lock.free()

func test_lock_key_only_refuses_a_lockpick() -> void:
	var lock := Lock.new()
	lock.key_item_id = &"keycard_red"
	lock.pickable = false  # key-only: a lockpick must NOT open it
	var opener := _opener_with([&"lockpick"])
	assert_false(lock.try_unlock(opener), "a lockpick can't open a non-pickable key lock")
	assert_true(lock.locked, "it stays locked")
	opener.inventory.free()
	opener.free()
	lock.free()

func test_lock_one_time_key_is_consumed() -> void:
	var lock := Lock.new()
	lock.key_item_id = &"token"
	lock.consume_key = true  # a one-time token key, spent on use
	lock.pickable = false
	var opener := _opener_with([&"token"])
	assert_true(lock.try_unlock(opener), "the token key opens it")
	assert_eq(opener.inventory.count_of_id(&"token"), 0, "a one-time key IS consumed when consume_key is on")
	opener.inventory.free()
	opener.free()
	lock.free()

func test_lock_reusable_pick_is_not_consumed() -> void:
	var lock := Lock.new()
	lock.consumes_pick = false  # a reusable skeleton pick
	var opener := _opener_with([&"lockpick"])
	assert_true(lock.try_unlock(opener), "the skeleton pick opens it")
	assert_eq(opener.inventory.count_of_id(&"lockpick"), 1, "a reusable pick (consumes_pick off) is NOT consumed")
	opener.inventory.free()
	opener.free()
	lock.free()

func test_locked_container_prompts_unlock() -> void:
	var c := ItemContainer.new()
	c.container_name = "Footlocker"
	assert_eq(c.look_name(), "[PH] Loot Footlocker", "no Lock child -> the plain loot prompt")
	var lock := Lock.new()
	c.add_child(lock)
	assert_eq(c.look_name(), "[PH] Unlock Footlocker", "a locked container's hover prompt says what E will attempt")
	lock.locked = false
	assert_eq(c.look_name(), "[PH] Loot Footlocker", "once opened it reads as a normal container forever")
	c.free()

func test_authored_lockpick_tres_loads() -> void:
	var lp = load("res://resources/items/lockpick.tres")
	assert_not_null(lp, "lockpick.tres loads (lives in resources/items/, so ItemDb auto-registers it)")
	assert_true(lp is Item, "lockpick.tres deserializes as an Item")
	assert_eq(lp.id, &"lockpick", "its id matches the Lock default, so a bare Lock just works")
	assert_gt(lp.max_stack, 1, "lockpicks stack")
