class_name DamageNumberPopup

## World-space damage-number feedback for player shots. The combat callers pass the
## post-mitigation HP loss, so the label shows what the enemy actually lost.

const MIN_LOSS: float = 0.5
const HIT_OFFSET_Y: float = 0.25
const BODY_OFFSET_Y: float = 1.35
const RISE: float = 0.75
const SPREAD: float = 0.18
const LIFETIME: float = 0.65
const FONT_SIZE: int = 48
const PIXEL_SIZE: float = 0.004
const OUTLINE_SIZE: int = 20
const RENDER_PRIORITY: int = 6
const START_SCALE: float = 1.12
const END_SCALE: float = 0.88
const BODY_COLOR: Color = Color(1.0, 0.33, 0.2, 1.0)
const CRIT_COLOR: Color = Color(1.0, 0.92, 0.22, 1.0)
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.78)


static func should_show(victim: Object, loss: float, attacker: Node) -> bool:
	if loss < MIN_LOSS:
		return false
	if victim == null or not is_instance_valid(victim) or not (victim is Character):
		return false
	if (victim as Character).is_in_group(&"Player"):
		return false
	return attacker != null and is_instance_valid(attacker) and attacker is Player


static func text_for(loss: float) -> String:
	return str(maxi(1, int(round(loss))))


static func show(victim: Object, loss: float, hit_pos: Vector3, was_crit: bool, attacker: Node) -> void:
	if not should_show(victim, loss, attacker) or not (victim is Node3D):
		return
	var victim_node := victim as Node3D
	if not victim_node.is_inside_tree():
		return
	var parent := victim_node.get_tree().current_scene if victim_node.get_tree().current_scene != null else victim_node.get_tree().root
	if parent == null:
		return

	var label := Label3D.new()
	label.name = "DamageNumber"
	label.text = text_for(loss)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.font_size = FONT_SIZE
	label.pixel_size = PIXEL_SIZE
	label.outline_size = OUTLINE_SIZE
	label.outline_modulate = OUTLINE_COLOR
	label.modulate = CRIT_COLOR if was_crit else BODY_COLOR
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.render_priority = RENDER_PRIORITY
	label.scale = Vector3.ONE * (START_SCALE if was_crit else 1.0)

	parent.add_child(label)
	var start := _spawn_position(victim_node, hit_pos)
	var drift := Vector3(randf_range(-SPREAD, SPREAD), RISE, randf_range(-SPREAD, SPREAD))
	label.global_position = start

	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", start + drift, LIFETIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE * END_SCALE, LIFETIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(label, "outline_modulate:a", 0.0, LIFETIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


static func _spawn_position(victim: Node3D, hit_pos: Vector3) -> Vector3:
	if hit_pos.is_finite():
		return hit_pos + Vector3.UP * HIT_OFFSET_Y
	return victim.global_position + Vector3.UP * BODY_OFFSET_Y
