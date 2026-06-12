class_name Reload
extends Node3D

## Reload + holster input adapter for the "Reload" action (R). A TAP reloads (emits `reload`,
## which attack.gd's _on_reload_reload validates); HOLDING past HOLD_THRESHOLD instead toggles the
## weapon holster (emits `holster_toggle`), Fallout: New Vegas style. An AI wielder's copy is
## process-disabled by Weapon.setup, so only the player ever drives these.

signal reload
signal holster_toggle  ## hold R past HOLD_THRESHOLD = holster / unholster

const HOLD_THRESHOLD: float = 0.3  ## seconds; a tap (<) reloads, a hold (>=) toggles the holster

var _press_us: int = -1
var _held_fired: bool = false  ## the holster already toggled during the current hold

func reload_weapon() -> void:
	reload.emit()

func _unhandled_input(event: InputEvent) -> void:
	# No reload / holster input during a conversation — the DialogueController holsters the weapon for it,
	# and a held R crossing the threshold during the (unpaused) dialogue intro would visibly fight that.
	if DialogueManager.is_active():
		return
	if event.is_action_pressed("Reload"):
		_press_us = Time.get_ticks_usec()
		_held_fired = false
	elif event.is_action_released("Reload"):
		# Short press = reload. A hold already fired the holster toggle in _process, so skip it.
		if _press_us > 0 and not _held_fired:
			var held := (Time.get_ticks_usec() - _press_us) / 1_000_000.0
			if held < HOLD_THRESHOLD:
				reload_weapon()
		_press_us = -1

func _process(_delta: float) -> void:
	if DialogueManager.is_active():
		_press_us = -1  # drop any in-flight hold so it can't fire a stale toggle the moment the talk ends
		return
	# Fire the holster toggle the instant a hold crosses the threshold (while the key is still down).
	if _press_us > 0 and not _held_fired:
		var held := (Time.get_ticks_usec() - _press_us) / 1_000_000.0
		if held >= HOLD_THRESHOLD:
			_held_fired = true
			holster_toggle.emit()
