class_name Reload
extends Node3D

signal reload

func reload_weapon() -> void:
	reload.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Reload"):
		reload_weapon()
