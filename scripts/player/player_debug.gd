class_name PlayerDebug
extends Node3D

## Dev-only helper: press End (ui_end) to hard-reload the current scene. Not shipping
## gameplay — a quick manual reset while iterating.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_end"):
		reset()

func reset():
	get_tree().reload_current_scene()
