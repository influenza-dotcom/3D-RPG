extends GutTest

## B-F7: ModalMenu — the shared mouse-capture save/restore the standalone modal screens use. Pins the CONTRACT
## (grab returns the prior mode; grab-then-restore round-trips back to it) relative to whatever mode is active, so it
## holds regardless of what a headless run allows Input.mouse_mode to be. Input is a global singleton — runs off-tree.

func after_all() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # leave a sane mode for the rest of the suite


func test_grab_returns_the_prior_mode() -> void:
	var before := Input.mouse_mode
	var returned := ModalMenu.grab_mouse()
	assert_eq(returned, before, "grab_mouse returns the mode that was active before the call (so the caller can restore it)")
	ModalMenu.restore_mouse(before)


func test_grab_then_restore_round_trips() -> void:
	var before := Input.mouse_mode
	var prev := ModalMenu.grab_mouse()
	ModalMenu.restore_mouse(prev)
	assert_eq(Input.mouse_mode, before, "grab then restore returns the mouse to the original mode")
