extends Node3D

signal reload

# Called when the node enters the scene tree for the first time.
func reload_weapon() -> void:
	reload.emit()

func _unhandled_input(event: InputEvent) -> void:
	
	if event.is_action_pressed("Reload"):
		reload_weapon()
