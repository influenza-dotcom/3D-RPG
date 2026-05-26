class_name BloodSplatter
extends Control

const BLOOD_BLOB_TEXTURE = preload("uid://cno035knsrd4j")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func splash(intensity: float = 1.0) -> void:
	intensity = clampf(intensity, 0.0, 1.0)
	if intensity <= 0.0:
		return
	var blob_count: int = int(round(lerpf(
		GameTuning.BLOOD_SPLATTER_MIN_BLOBS,
		GameTuning.BLOOD_SPLATTER_MAX_BLOBS,
		intensity
	)))
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	for i in blob_count:
		_spawn_blob(viewport_size, intensity)

func _spawn_blob(viewport_size: Vector2, intensity: float) -> void:
	var blob := TextureRect.new()
	add_child(blob)
	blob.texture = BLOOD_BLOB_TEXTURE
	blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blob.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var blob_scale := randf_range(
		GameTuning.BLOOD_SPLATTER_MIN_SCALE,
		GameTuning.BLOOD_SPLATTER_MAX_SCALE
	) * (0.5 + 0.5 * intensity)
	var blob_size := Vector2(
		GameTuning.BLOOD_SPLATTER_BASE_SIZE,
		GameTuning.BLOOD_SPLATTER_BASE_SIZE
	) * blob_scale
	blob.size = blob_size
	blob.pivot_offset = blob_size * 0.5
	blob.position = Vector2(
		randf_range(0.0, viewport_size.x) - blob_size.x * 0.5,
		randf_range(0.0, viewport_size.y) - blob_size.y * 0.5
	)
	blob.rotation = randf_range(0.0, TAU)
	blob.modulate = Color(
		GameTuning.BLOOD_SPLATTER_TINT_R,
		GameTuning.BLOOD_SPLATTER_TINT_G,
		GameTuning.BLOOD_SPLATTER_TINT_B,
		intensity
	)
	var tween := blob.create_tween()
	tween.tween_property(blob, "modulate:a", 0.0, GameTuning.BLOOD_SPLATTER_FADE_TIME)
	tween.tween_callback(blob.queue_free)
