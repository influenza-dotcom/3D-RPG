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

@export_group("Carried light (the flashlight penalty)")
## Multiplier on an enemy's SIGHT RANGE while the target carries a fully-lit lamp (their `carried_light` reads 1),
## lerped by that strength. This is the half of the trade the exposure curve above CANNOT express: exposure clamps
## at 1.0, so being lit can only ever cancel the darkness discount — carrying your own light has to be able to make
## you WORSE than baseline, or a flashlight is free. 1.6 = spotted 60% further out while the torch is on. 1.0 = a
## torch costs you nothing at range (the pre-flashlight behaviour).
@export_range(1.0, 4.0, 0.05) var carried_light_sight_mult: float = 1.6
## Multiplier on how fast an enemy's DETECTION METER fills while the target carries a fully-lit lamp, lerped by
## strength. Applied outside the visibility curve (which clamps to 1.0 and can only ever slow detection down).
## 2.0 = a lit torch locks them on twice as fast. 1.0 = no fill penalty.
@export_range(1.0, 8.0, 0.05) var carried_light_detect_mult: float = 2.0

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

## The sight-range multiplier in effect for a target carrying light at `strength` (0..1). Returns exactly 1.0 at
## strength 0, so a target carrying nothing — every NPC, and a player with the torch off — is spotted at exactly
## today's range. Kept HERE rather than lerped at the call site so both halves of the penalty share one shape and a
## designer sees the two knobs together. Pure; unit-tested.
func carried_sight_mult(strength: float) -> float:
	return lerpf(1.0, maxf(carried_light_sight_mult, 0.0), clampf(strength, 0.0, 1.0))

## The detection-fill multiplier for a target carrying light at `strength` (0..1); 1.0 at strength 0. Pure.
func carried_detect_mult(strength: float) -> float:
	return lerpf(1.0, maxf(carried_light_detect_mult, 0.0), clampf(strength, 0.0, 1.0))
