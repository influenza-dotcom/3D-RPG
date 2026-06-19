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

func test_look_name_reflects_state() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.locked = false
	assert_eq(door.look_name(), "Open door", "closed + unlocked -> Open door")
	door.open()
	assert_eq(door.look_name(), "Close door", "open -> Close door")
	door.locked = true
	assert_eq(door.look_name(), "Locked", "locked (no flag) -> Locked")
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
