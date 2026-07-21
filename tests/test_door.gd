extends GutTest

## Slice 3 (Door): open/close/toggle mechanics + the pivot swing + the look-at label. Built off-tree with a
## manually-assigned pivot, so _swing_to takes its off-tree branch (snap, no tween) — pure + tree-free. The
## lock gate (Lock child / keyed item / unlock_flag) reuses lock.gd's proven path and is playtest-verified.

func test_open_close_toggle_swings_pivot() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.open_angle = 90.0
	assert_false(door.is_open(), "starts closed")
	door.open()
	assert_true(door.is_open(), "open() opens it")
	assert_almost_eq(pivot.rotation.y, deg_to_rad(90.0), 0.001, "pivot swung to open_angle")
	door.close()
	assert_false(door.is_open(), "close() closes it")
	assert_almost_eq(pivot.rotation.y, 0.0, 0.001, "pivot swung back closed")
	door.toggle()
	assert_true(door.is_open(), "toggle from closed -> open")
	pivot.free()
	door.free()

func test_open_is_idempotent() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.open()
	door.open()  # second open is a no-op (already open)
	assert_true(door.is_open(), "stays open")
	pivot.free()
	door.free()

func test_area_hitbox_follows_pivot_swing() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	var hitbox := CollisionShape3D.new()
	door.add_child(pivot)
	door.add_child(hitbox)
	door.pivot = pivot
	door.open_angle = 90.0
	hitbox.position = Vector3(0.5, 1.0, 0.0)
	door.open()
	assert_almost_eq(hitbox.rotation.y, deg_to_rad(90.0), 0.001, "the look-at hitbox rotates with the door panel")
	door.close()
	assert_almost_eq(hitbox.rotation.y, 0.0, 0.001, "the look-at hitbox returns to its closed rotation")
	assert_almost_eq(hitbox.position, Vector3(0.5, 1.0, 0.0), Vector3(0.001, 0.001, 0.001), "the closed hitbox returns to its authored offset")
	door.free()

func test_look_name_reflects_state() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.locked = false
	assert_eq(door.look_name(), "[PH] Open door", "closed + unlocked -> Open door")
	door.open()
	assert_eq(door.look_name(), "[PH] Close door", "open -> Close door")
	door.locked = true
	assert_eq(door.look_name(), "[PH] Locked", "locked (no flag) -> Locked")
	pivot.free()
	door.free()

func test_config_warning_without_pivot() -> void:
	var door := Door.new()
	assert_false(door._get_configuration_warnings().is_empty(), "warns when pivot is unassigned")
	var pivot := Node3D.new()
	door.pivot = pivot
	assert_true(door._get_configuration_warnings().is_empty(), "no warning once a pivot is assigned")
	pivot.free()
	door.free()


# --- Built-in key/lockpick gate (the same shared LockRules rule the Lock component uses) ---

## A minimal opener: a backpack, no toast surface (the door null-guards notify_toast). Built off-tree, so _try_unlock
## runs without the door entering the tree (no _ready / talk-layer setup needed to exercise the lock decision).
class _Opener extends Node:
	var inventory: CharacterInventory

func _stub_item(id: StringName) -> Item:
	var it := Item.new()
	it.id = id
	it.max_stack = 10
	return it

func test_door_pickable_gate_consumes_a_lockpick() -> void:
	var door := Door.new()
	door.locked = true
	door.pickable = true  # opt IN to lockpicking (default off = dead bolt)
	var opener := _Opener.new()
	opener.inventory = CharacterInventory.new()
	assert_false(door._try_unlock(opener), "locked + pickable but no lockpick -> stays locked")
	assert_true(door.locked)
	opener.inventory.add(_stub_item(&"lockpick"), 1)
	assert_true(door._try_unlock(opener), "a lockpick picks a pickable door")
	assert_false(door.locked, "the door is unlocked")
	assert_eq(opener.inventory.count_of_id(&"lockpick"), 0, "the pick is consumed (consumes_pick default true)")
	opener.inventory.free()
	opener.free()
	door.free()

func test_door_key_takes_precedence_over_a_lockpick() -> void:
	var door := Door.new()
	door.locked = true
	door.key_item_id = &"keycard_red"
	door.pickable = true  # keyed AND pickable — the "have the key OR pick it" door
	var opener := _Opener.new()
	opener.inventory = CharacterInventory.new()
	opener.inventory.add(_stub_item(&"keycard_red"), 1)
	opener.inventory.add(_stub_item(&"lockpick"), 1)
	assert_true(door._try_unlock(opener), "carrying the key opens the keyed+pickable door")
	assert_eq(opener.inventory.count_of_id(&"keycard_red"), 1, "the reusable key is not consumed (consume_key default false)")
	assert_eq(opener.inventory.count_of_id(&"lockpick"), 1, "the lockpick is untouched — the key took precedence")
	opener.inventory.free()
	opener.free()
	door.free()

func test_door_locked_is_a_dead_bolt_unless_pickable() -> void:
	var door := Door.new()
	door.locked = true  # no key, pickable defaults FALSE -> a sealed dead bolt (preserves the old behaviour)
	var opener := _Opener.new()
	opener.inventory = CharacterInventory.new()
	opener.inventory.add(_stub_item(&"lockpick"), 1)
	assert_false(door._try_unlock(opener), "a plain locked door is a dead bolt — a lockpick can't open it unless `pickable` is ON")
	assert_true(door.locked, "it stays locked")
	opener.inventory.free()
	opener.free()
	door.free()

func test_door_delegates_entirely_to_a_child_lock() -> void:
	# A child Lock OWNS unlocking: the Door's own built-in fields are ignored (door.gd _try_unlock early-returns on it).
	var door := Door.new()
	door.locked = false                # Door's own bolt off — the child Lock provides the lock
	door.key_item_id = &"phantom_key"  # a built-in key that MUST be ignored while a child Lock is present
	var lk := Lock.new()               # child Lock: locked + pickable by default
	door.add_child(lk)
	var opener := _Opener.new()
	opener.inventory = CharacterInventory.new()
	assert_false(door._try_unlock(opener), "no lockpick -> the child Lock holds (the door's phantom built-in key is ignored)")
	opener.inventory.add(_stub_item(&"lockpick"), 1)
	assert_true(door._try_unlock(opener), "a lockpick picks the CHILD Lock (delegation), not the door's built-in gate")
	assert_false(lk.locked, "the child Lock is now open")
	assert_false(door.locked, "and the Door reflects unlocked")
	opener.inventory.free()
	opener.free()
	door.free()  # frees the child Lock too
