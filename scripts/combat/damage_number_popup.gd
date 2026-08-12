class_name DamageNumberPopup

## World-space damage-number feedback for player shots. The combat callers pass the
## post-mitigation HP loss, so the label shows what the enemy actually lost.
##
## The FEEL surface (spawn offsets, rise/drift, lifetime, sizing, colours) is designer-tunable on
## GameSettings.effects — the "Damage Numbers" group on resources/tuning/EffectsSettings.tres —
## and show() reads it live, like gun_fx.gd's statics do. The const bank below stays as the
## shipped baseline + the GUT anchors (the NpcBarkSettings idiom): every damage_number_* field
## DEFAULTS to its const, so behaviour is byte-identical until a designer tunes the resource
## (test_damage_number_popup.gd pins the mirror).

## Gameplay POLICY, not feel — the post-mitigation loss below which no number shows at all. Stays
## a const (not on EffectsSettings) so should_show() remains a pure, autoload-free static the
## off-tree unit tests call bare; pinned by test_damage_number_popup.gd.
const MIN_LOSS: float = 0.5
## --- Shipped feel baseline: each const seeds the matching GameSettings.effects.damage_number_*
## default. The runtime path reads the resource; these stay as the anchors. ---
const HIT_OFFSET_Y: float = 0.25
const BODY_OFFSET_Y: float = 1.35
const RISE: float = 0.75
const SPREAD: float = 0.18
const LIFETIME: float = 0.65
const FONT_SIZE: int = 48
const PIXEL_SIZE: float = 0.004
const OUTLINE_SIZE: int = 20
const START_SCALE: float = 1.12
const END_SCALE: float = 0.88
const BODY_COLOR: Color = Color(1.0, 0.33, 0.2, 1.0)
const CRIT_COLOR: Color = Color(1.0, 0.92, 0.22, 1.0)
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 0.78)
## Draw-order CONTRACT, not feel: keeps the number above the world's transparent surfaces (decals,
## glass, smoke) — like the render-layer masks elsewhere, deliberately NOT a designer knob.
const RENDER_PRIORITY: int = 6


static func should_show(victim: Object, loss: float, attacker: Node) -> bool:
	if loss < MIN_LOSS:
		return false
	if victim == null or not is_instance_valid(victim) or not (victim is Character):
		return false
	if (victim as Character).is_in_group(Groups.PLAYER):
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
	# Live designer tuning, resolved once — and only PAST the bails above, so the pure policy statics
	# (should_show / text_for) never touch the autoload and off-tree tests keep calling them bare.
	var fx: EffectsSettings = GameSettings.effects

	var label := Label3D.new()
	label.name = "DamageNumber"
	label.text = text_for(loss)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.font_size = fx.damage_number_font_size
	label.pixel_size = fx.damage_number_pixel_size
	label.outline_size = fx.damage_number_outline_size
	label.outline_modulate = fx.damage_number_outline_color
	label.modulate = fx.damage_number_crit_color if was_crit else fx.damage_number_body_color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.render_priority = RENDER_PRIORITY
	label.scale = Vector3.ONE * (fx.damage_number_start_scale if was_crit else 1.0)

	parent.add_child(label)
	var start := _spawn_position(victim_node, hit_pos, fx)
	var drift := Vector3(randf_range(-fx.damage_number_spread, fx.damage_number_spread), fx.damage_number_rise, randf_range(-fx.damage_number_spread, fx.damage_number_spread))
	label.global_position = start

	var life: float = fx.damage_number_lifetime
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position", start + drift, life).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector3.ONE * fx.damage_number_end_scale, life).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(label, "outline_modulate:a", 0.0, life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


static func _spawn_position(victim: Node3D, hit_pos: Vector3, fx: EffectsSettings) -> Vector3:
	if hit_pos.is_finite():
		return hit_pos + Vector3.UP * fx.damage_number_hit_offset_y
	return victim.global_position + Vector3.UP * fx.damage_number_body_offset_y
