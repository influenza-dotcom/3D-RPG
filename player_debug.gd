extends Node3D

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action("ui_end"):
		reset()

func reset():
	get_tree().reload_current_scene()
