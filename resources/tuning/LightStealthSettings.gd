class_name LightStealthSettings
extends Resource

## Global light-stealth tuning: the default curve mapping the player's light EXPOSURE (0 = pitch dark, 1 = fully
## lit) to a visibility factor an enemy Perception multiplies its detection-fill rate by. Read as
## GameSettings.light_stealth; an NPC's own Perception.light_falloff overrides this per-archetype. With this one
## curve, painting a ShadowVolume (or dropping a PlayerLightLevel) slows detection in the dark GAME-WIDE — no
## per-NPC authoring. The feature stays inert until a writer actually lowers light_exposure below 1.0 (no shadow
## painted -> exposure 1.0 -> the curve samples 1.0 -> detection behaves exactly as before).

## OPTIONAL hand-authored visibility-vs-exposure curve. NULL = use the built-in ramp from dark_visibility (at
## exposure 0) up to 1.0 (at exposure 1).
@export var light_falloff: Curve = null
## The built-in ramp's value at pitch dark (exposure 0) when light_falloff is null. 1.0 = light never matters;
## lower it so a target in shadow fills the meter slower (0.25 = quarter-rate detection in pitch dark).
@export_range(0.0, 1.0) var dark_visibility: float = 0.25

var _default_curve: Curve = null

## The effective curve: the authored light_falloff, else a cached built-in ramp (dark_visibility -> 1.0). Always
## non-null, so Perception's global fallback (rank 27.2) can rely on it.
func falloff() -> Curve:
	if light_falloff != null:
		return light_falloff
	if _default_curve == null:
		_default_curve = Curve.new()
		_default_curve.add_point(Vector2(0.0, dark_visibility))
		_default_curve.add_point(Vector2(1.0, 1.0))
	return _default_curve
