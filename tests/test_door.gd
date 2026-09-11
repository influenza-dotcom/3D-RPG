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


# --- NPCs open doors by walking into them (npc.gd _open_bumped_doors -> Door.of_collider + npc_try_open) ---
# The opener is a bare off-tree Node3D standing in for the NPC: npc_try_open only reads is_inside_tree /
# global_position off it, so the whole rule runs without an NPC's _ready (CLAUDE.md: never in a unit test). Off-tree,
# npc_try_open falls back to the authored swing side; the away-side pick is pinned on the pure swing_sign_away below.

func test_npc_opens_an_unlocked_door() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	var npc := Node3D.new()
	assert_true(door.npc_try_open(npc), "an unlocked door opens for an NPC that walks into it")
	assert_true(door.is_open(), "and it is now open")
	assert_true(door.npc_try_open(npc), "bumping an already-open door reports open (no re-swing)")
	npc.free()
	pivot.free()
	door.free()

func test_npc_cannot_open_a_locked_door() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.locked = true
	door.pickable = true  # even a PICKABLE lock: NPCs never pick
	var npc := Node3D.new()
	assert_false(door.npc_try_open(npc), "a locked door stays a wall to NPCs")
	assert_false(door.is_open(), "it stays closed")
	assert_true(door.locked, "the NPC never touched the lock — lock state is the player's alone")
	npc.free()
	pivot.free()
	door.free()

func test_npc_cannot_open_through_a_locked_child_lock() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	var lk := Lock.new()  # locked + pickable by default; the Door's own bolt stays off
	door.add_child(lk)
	var npc := Node3D.new()
	assert_false(door.npc_try_open(npc), "a still-locked child Lock refuses the NPC even with the Door's own bolt off")
	assert_true(lk.locked, "the NPC never picks the child Lock")
	npc.free()
	pivot.free()
	door.free()  # frees the child Lock too

func test_npc_can_open_off_makes_a_player_only_door() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.npc_can_open = false
	var npc := Node3D.new()
	assert_false(door.npc_try_open(npc), "npc_can_open OFF: NPCs treat the door as a wall")
	assert_false(door.is_open(), "it stays closed")
	door.open()
	assert_true(door.is_open(), "the player / script path (open()) ignores npc_can_open")
	npc.free()
	pivot.free()
	door.free()

func test_swing_sign_away_picks_the_side_away_from_the_opener() -> void:
	# A panel hinged at the origin, extending along +X. Derive where the AUTHORED swing ends rather than hardcoding the
	# engine's rotation handedness, then stand the opener on that side and on the other.
	var panel := Vector3(0.5, 1.0, 0.0)
	var angle := deg_to_rad(90.0)
	var authored_end := Basis(Vector3.UP, angle) * Vector3(panel.x, 0.0, panel.z)
	assert_eq(Door.swing_sign_away(Vector3.ZERO, 0.0, angle, panel, authored_end * 3.0), -1.0,
		"an opener standing where the authored swing ends gets the MIRROR swing — the panel must not sweep through them")
	assert_eq(Door.swing_sign_away(Vector3.ZERO, 0.0, angle, panel, -authored_end * 3.0), 1.0,
		"an opener on the far side keeps the authored swing")
	assert_eq(Door.swing_sign_away(Vector3.ZERO, 0.0, angle, Vector3.ZERO, authored_end * 3.0), 1.0,
		"no measurable panel (a point on the hinge) is a tie and keeps the authored side")
	# The same pick holds for a door already turned in its frame and hinged off the origin.
	var yaw := deg_to_rad(40.0)
	var hinge := Vector3(3.0, 0.0, -2.0)
	var turned_arm := Basis(Vector3.UP, yaw + angle) * Vector3(panel.x, 0.0, panel.z)
	assert_eq(Door.swing_sign_away(hinge, yaw, angle, panel, hinge + turned_arm * 3.0), -1.0,
		"closed_yaw and the hinge offset are honoured")

func test_door_opened_on_the_mirror_side_closes_back_to_rest() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.open_angle = 90.0
	door._open_toward(-1.0)  # what open_away_from does for an NPC standing on the authored side
	assert_almost_eq(pivot.rotation.y, deg_to_rad(-90.0), 0.001, "an NPC-side open swings to the mirror of open_angle")
	door.close()
	assert_almost_eq(pivot.rotation.y, 0.0, 0.001, "close() returns it to the same closed rest from either side")
	door.open()
	assert_almost_eq(pivot.rotation.y, deg_to_rad(90.0), 0.001, "a later player / script open() uses the authored side again")
	pivot.free()
	door.free()

func test_of_collider_finds_the_owning_door() -> void:
	# The prefab's shape: Door / DoorPivot / DoorBody — an NPC's slide contact reports the DoorBody.
	var door := Door.new()
	var pivot := Node3D.new()
	var body := StaticBody3D.new()
	door.add_child(pivot)
	pivot.add_child(body)
	door.pivot = pivot
	assert_eq(Door.of_collider(body), door, "the panel's blocker resolves to its Door")
	var wall := StaticBody3D.new()
	assert_null(Door.of_collider(wall), "an unrelated wall resolves to null")
	assert_null(Door.of_collider(null), "null-safe")
	wall.free()
	door.free()  # frees the pivot + body too
