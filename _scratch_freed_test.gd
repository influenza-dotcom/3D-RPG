extends SceneTree

func _initialize() -> void:
	var n := Node.new()
	get_root().add_child(n)
	var held = n
	n.queue_free()
	await process_frame
	await process_frame
	print("RESULT is_instance_valid=", is_instance_valid(held))
	if not held:
		print("RESULT branch=IF_NOT_HELD_TRUE_early_return_no_emit")
	else:
		print("RESULT branch=falls_through")
		if not is_instance_valid(held):
			print("RESULT recovery=REACHED_would_emit_false")
	print("RESULT bool_held=", bool(held))
	quit()
