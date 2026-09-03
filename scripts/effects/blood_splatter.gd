class_name BloodSplatter
extends Control

## Full-screen blood overlay (HUD). splash(intensity) sprays fading blob sprites
## across the viewport for a "got hit / standing in carnage" effect. Driven by
## Player.on_nearby_death — intensity scales with proximity to the death.

const BLOOD_BLOB_TEXTURE = preload("uid://cno035knsrd4j")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func splash(intensity: float = 1.0) -> void:
	intensity = clampf(intensity, 0.0, 1.0)
	if intensity <= 0.0:
		return
	var blob_count: int = int(round(lerpf(
		GameSettings.effects.blood_splatter_min_blobs,
		GameSettings.effects.blood_splatter_max_blobs,
		intensity
	)))
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	for i in blob_count:
		_spawn_blob(viewport_size, intensity)

## Spray ONE blob at a near-invisible `alpha` (the in-level EffectPrewarmer's 2D pass, on the black fade-in after a
## level loads) so the overlay's canvas draw + the blob texture are issued before the first nearby kill — 2D
## pipelines have no precompilation, and a near-transparent draw is the only warm there is. The blob is a
## full-strength splash blob with only its modulate alpha overridden (the fade tween then runs it to 0 and frees
## it, exactly like a real one), so it exercises the same draw a real splash does.
func warm_draw(alpha: float) -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var blob := _spawn_blob(viewport_size, 1.0)
	blob.modulate.a = alpha

## Spawn one fading blob; returned so warm_draw can dim it (splash ignores the return).
func _spawn_blob(viewport_size: Vector2, intensity: float) -> TextureRect:
	var blob := TextureRect.new()
	add_child(blob)
	blob.texture = BLOOD_BLOB_TEXTURE
	blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blob.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var blob_scale := randf_range(
		GameSettings.effects.blood_splatter_min_scale,
		GameSettings.effects.blood_splatter_max_scale
	) * (0.5 + 0.5 * intensity)
	var blob_size := Vector2(
		GameSettings.effects.blood_splatter_base_size,
		GameSettings.effects.blood_splatter_base_size
	) * blob_scale
	blob.size = blob_size
	blob.pivot_offset = blob_size * 0.5
	blob.position = Vector2(
		randf_range(0.0, viewport_size.x) - blob_size.x * 0.5,
		randf_range(0.0, viewport_size.y) - blob_size.y * 0.5
	)
	blob.rotation = randf_range(0.0, TAU)
	blob.modulate = Color(
		GameSettings.effects.blood_splatter_tint_r,
		GameSettings.effects.blood_splatter_tint_g,
		GameSettings.effects.blood_splatter_tint_b,
		intensity
	)
	var tween := blob.create_tween()
	tween.tween_property(blob, "modulate:a", 0.0, GameSettings.effects.blood_splatter_fade_time)
	tween.tween_callback(blob.queue_free)
	return blob
