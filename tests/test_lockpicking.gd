extends GutTest

## Lockpicking — the reusable Lock component (a child of any interactable: containers now, doors later),
## CharacterInventory.find_by_id (the by-KIND item lookup locks/keys rely on), and the ItemContainer
## integration ("Unlock X" hover prompt; E attempts the pick before the loot screen opens).

## A minimal opener: carries a backpack, has no toast surface (Lock null-guards both).
class _Opener extends Node:
	var inventory: CharacterInventory


func _pick_item() -> Item:
	var it := Item.new()
	it.id = &"lockpick"
	it.display_name = "Lockpick"
	it.max_stack = 10
	return it


func test_find_by_id_locates_a_carried_kind() -> void:
	var inv := CharacterInventory.new()
	var pick := _pick_item()
	inv.add(pick, 2)
	assert_eq(inv.find_by_id(&"lockpick"), pick, "find_by_id resolves a carried item by its Item.id")
	assert_null(inv.find_by_id(&"keycard_red"), "an id the bag doesn't hold reads null")
	assert_null(inv.find_by_id(&""), "the empty id never matches")
	inv.free()
	pick = null


func test_lock_defaults_and_discovery() -> void:
	var host := Node.new()
	assert_null(Lock.of(host), "a host with no Lock child reads null (unlocked behaviour)")
	var lock := Lock.new()
	host.add_child(lock)
	assert_eq(Lock.of(host), lock, "Lock.of finds the host's Lock child — how any interactable checks itself")
	assert_true(lock.locked, "a fresh Lock starts locked")
	assert_eq(lock.requires_item_id, &"lockpick", "the default lock wants a lockpick")
	assert_true(lock.consumes_item, "picking snaps the pick by default")
	host.free()


func test_try_unlock_needs_and_consumes_a_pick() -> void:
	var lock := Lock.new()
	var opener := _Opener.new()
	opener.inventory = CharacterInventory.new()
	assert_false(lock.try_unlock(opener), "no pick carried -> the lock holds")
	assert_true(lock.locked, "...and stays locked")
	var pick := _pick_item()
	opener.inventory.add(pick, 2)
	watch_signals(lock)
	assert_true(lock.try_unlock(opener), "carrying a pick -> the lock opens")
	assert_false(lock.locked, "the lock is now PERMANENTLY open")
	assert_eq(opener.inventory.count_of(pick), 1, "one pick is consumed (snapped) on success")
	assert_signal_emitted(lock, "unlocked", "unlocked fires once — a future door swings open on this")
	assert_true(lock.try_unlock(opener), "an already-open lock is a free pass (no further picks consumed)")
	assert_eq(opener.inventory.count_of(pick), 1, "...and consumes nothing more")
	opener.inventory.free()
	opener.free()
	lock.free()
	pick = null


func test_keyed_lock_does_not_consume_the_key() -> void:
	var lock := Lock.new()
	lock.requires_item_id = &"keycard_red"
	lock.consumes_item = false
	var opener := _Opener.new()
	opener.inventory = CharacterInventory.new()
	var key := Item.new()
	key.id = &"keycard_red"
	opener.inventory.add(key, 1)
	assert_true(lock.try_unlock(opener), "carrying the matching key opens a keyed lock")
	assert_eq(opener.inventory.count_of(key), 1, "a reusable key is NOT consumed — the door-flexibility contract")
	opener.inventory.free()
	opener.free()
	lock.free()
	key = null


func test_locked_container_prompts_unlock() -> void:
	var c := ItemContainer.new()
	c.container_name = "Footlocker"
	assert_eq(c.look_name(), "Loot: Footlocker", "no Lock child -> the plain loot prompt")
	var lock := Lock.new()
	c.add_child(lock)
	assert_eq(c.look_name(), "Unlock Footlocker", "a locked container's hover prompt says what E will attempt")
	lock.locked = false
	assert_eq(c.look_name(), "Loot: Footlocker", "once opened it reads as a normal container forever")
	c.free()


func test_authored_lockpick_tres_loads() -> void:
	var lp = load("res://resources/items/lockpick.tres")
	assert_not_null(lp, "lockpick.tres loads (lives in resources/items/, so ItemDb auto-registers it)")
	assert_true(lp is Item, "lockpick.tres deserializes as an Item")
	assert_eq(lp.id, &"lockpick", "its id matches the Lock default, so a bare Lock just works")
	assert_gt(lp.max_stack, 1, "lockpicks stack")
