class_name ModalMenu

## B-F7: the shared mouse-capture bookkeeping every STANDALONE modal screen (shop / heal / level-up / respec / loot)
## repeated by hand. A modal frees the mouse so its buttons are clickable, then restores whatever mode was active
## (usually CAPTURED gameplay) on close. Extracted so the save/restore pair lives in ONE place instead of five copies.
## Pure statics — Input is a global singleton, so these are null-tree safe (no SceneTree needed).
##
## SCOPE: mouse mode ONLY. Pausing is deliberately NOT here — the four pausing modals (shop/heal/level-up/respec) set
## `get_tree().paused`, loot does not, so pause stays authored per-screen. And the player-menu GROUP screens
## (inventory / journal / stats / rep) are OUT of scope: they route the mouse through PlayerMenus.enter/leave, which
## preserves the cursor across sibling tab-switches — going through here would reset that. Only the standalone modals.

## Free the mouse for a modal's buttons and RETURN the mode that was active, so the caller stashes it to restore on
## close. Caller idiom: `_prev_mouse_mode = ModalMenu.grab_mouse()`.
static func grab_mouse() -> Input.MouseMode:
	var prev := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return prev

## Restore the mouse mode a modal stashed at open (usually CAPTURED gameplay). Caller idiom:
## `ModalMenu.restore_mouse(_prev_mouse_mode)`.
static func restore_mouse(prev: Input.MouseMode) -> void:
	Input.mouse_mode = prev
