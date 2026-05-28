class_name Reload
extends Node3D

## Thin input adapter: translates the "Reload" action into a `reload` signal.
## attack.gd's _on_reload_reload() decides whether a reload is actually allowed
## (not mid-swap, clip not already full) and starts the Reload Timer.

signal reload

func reload_weapon() -> void:
	reload.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Reload"):
		reload_weapon()
