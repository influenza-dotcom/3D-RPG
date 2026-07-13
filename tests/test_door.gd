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
