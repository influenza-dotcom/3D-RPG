class_name ModalMenu

## B-F7: the shared OPEN/CLOSE bookkeeping every STANDALONE modal screen (shop / heal / atm / level-up /
## respec / chip-install / chess / loot) repeated by hand. A modal frees the mouse so its buttons are
## clickable, then restores whatever mode was active (usually CAPTURED gameplay) on close. Extracted so the
## pair lives in ONE place instead of eight copies. Pure statics — Input is a global singleton, so these
## stay null-tree safe (no SceneTree needed).
##
## SCOPE: mouse mode + the open/close SOUND CUE. The audio rides here deliberately, because these two calls
## are the only point ALL eight standalone modals share, and — critically — they sit PAST every refusal
## guard: a shop that refuses to open (dead merchant, no player) returns before grab_mouse and still emits
## `closed`, so hooking the signals would sting for a menu that never appeared. Screens with their own
## diegetic open sound opt out with `grab_mouse(false)` (the ATM's panel chirp).
##
## Pausing is deliberately NOT here, and as of 2026-08-09 there is nothing left to host: NO standalone modal
## pauses the tree any more (see atm_screen.gd's header — a walk-up screen must not stop the city, and a
## dialogue-hosted one is already frozen by the conversation). Dialogue's own pause is the last one in the game,
## and it stays where it is. And the player-menu GROUP screens (inventory / journal / stats / rep)
## are OUT of scope: they route the mouse AND their cues through PlayerMenus.enter/leave, which preserves
## the cursor across sibling tab-switches and distinguishes a cold open from a tab swap — going through here
## would reset the cursor and sting on every tab.

## Free the mouse for a modal's buttons and RETURN the mode that was active, so the caller stashes it to restore on
## close. Caller idiom: `_prev_mouse_mode = ModalMenu.grab_mouse()`.
## Plays the menu-open cue unless `play_cue` is false (for a screen that owns a better, diegetic open sound).
static func grab_mouse(play_cue: bool = true) -> Input.MouseMode:
	var prev := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if play_cue:
		MenuStyle.play_open()
	return prev

## Restore the mouse mode a modal stashed at open (usually CAPTURED gameplay). Caller idiom:
## `ModalMenu.restore_mouse(_prev_mouse_mode)`.
## Plays the back/close cue unless `play_cue` is false. Reached only past each close()'s `if not _is_open:
## return` guard, so a refused open never back-stings.
static func restore_mouse(prev: Input.MouseMode, play_cue: bool = true) -> void:
	Input.mouse_mode = prev
	if play_cue:
		MenuStyle.play_back()
