class_name Reload
extends Node3D

## Reload + holster input adapter for the "Reload" action (R). A TAP reloads (emits `reload`,
## which attack.gd's _on_reload_reload validates); HOLDING past the tunable reload_hold_threshold
## (GameSettings.weapon_general) instead toggles the weapon holster (emits `holster_toggle`),
## Fallout: New Vegas style. An AI wielder's copy is process-disabled by Weapon.setup, so only the
## player ever drives these — and a DEAD player doesn't either (see _blocked()).

signal reload
signal holster_toggle  ## hold R past the threshold = holster / unholster

## The wielder, handed over by Weapon.setup() (a cross-actor ref like Weapon's own `character` — it
## lives outside weapon.tscn, so it can't be scene-wired). Polled for liveness in _blocked(); null
## (an AI wielder, or a bare test instance) never blocks, matching ScopeIn's attack.character guard.
var character: Character

var _press_us: int = -1
var _held_fired: bool = false  ## the holster already toggled during the current hold

func reload_weapon() -> void:
	reload.emit()

## True while reload / holster input must be ignored. Three suppressors:
##   - A conversation: the DialogueController holsters the weapon for it, and a held R crossing the
##     threshold during the (unpaused) dialogue intro would visibly fight that.
##   - Any non-pausing menu (the shared gameplay_suppressed() gate): R doubles as the inventory-grid
##     "rotate item" key — don't reload behind the bag.
##   - A DEAD wielder: death is in NEITHER of the above (gameplay_suppressed() is modals/cutscenes
##     only), and Player.die() only process-disables MouseInput — that covers look/fire, while this
##     node keeps polling R in its OWN _unhandled_input/_process through the death cinematic. Without
##     this gate a tap of R reloads on the corpse, and a held R toggles the holster — a state that
##     PERSISTS into the checkpoint revive (Attack.set_holstered is the sole holster mutator, and the
##     revive doesn't reset it), so the player would respawn with the gun silently put away. Mirrors
##     the wielder-liveness condition in ScopeIn's `wants` gate.
func _blocked() -> bool:
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return true
	return character != null and not character.is_alive()

func _unhandled_input(event: InputEvent) -> void:
	if _blocked():
		return
	if event.is_action_pressed("Reload"):
		_press_us = Time.get_ticks_usec()
		_held_fired = false
	elif event.is_action_released("Reload"):
		# Short press = reload. A hold already fired the holster toggle in _process, so skip it.
		if _press_us > 0 and not _held_fired:
			var held := (Time.get_ticks_usec() - _press_us) / 1_000_000.0
			if held < GameSettings.weapon_general.reload_hold_threshold:
				reload_weapon()
		_press_us = -1

func _process(_delta: float) -> void:
	if _blocked():
		_press_us = -1  # drop any in-flight hold so it can't fire a stale toggle the moment the talk/menu/revive ends
		return
	# Fire the holster toggle the instant a hold crosses the threshold (while the key is still down).
	if _press_us > 0 and not _held_fired:
		var held := (Time.get_ticks_usec() - _press_us) / 1_000_000.0
		if held >= GameSettings.weapon_general.reload_hold_threshold:
			_held_fired = true
			holster_toggle.emit()
