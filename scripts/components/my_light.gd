@tool
class_name MyLight
extends Node3D

## The designer light fixture (`scenes/levels/Light.tscn`): ONE node that drives BOTH a point light and a
## spotlight from a single colour/energy, plus an optional electrical buzz. A range of 0 is how a designer
## DISABLES one half -- a spot-only fixture leaves `_range_omni` at 0, an omni-only one leaves
## `_range_spotlight` at 0 -- so an authored level's instances routinely override only the half they use.
##
## `@tool` is here for the LIVE EDITOR PREVIEW: `_process` pushes the inspector values into the two child
## lights every frame, which is the only reason a placed fixture is visible while you position it (the child
## nodes' own authored colour/range/energy are overwritten every frame and mean nothing). Everything that is
## NOT that preview -- i.e. the buzz -- is gated behind `Engine.is_editor_hint()` below: the editor stays quiet.

@onready var light_source: OmniLight3D = $LightSource
@onready var spotlight: SpotLight3D = $Spotlight
@onready var light_buzz: AudioStreamPlayer3D = $LightSource/LightBuzz

## ⭐THE RANGE DEFAULTS MUST STAY 0.0. A scene instance stores only the properties it OVERRIDES, so every
## authored single-mode fixture (the shipping level has seven) relies on the un-overridden half inheriting 0
## to stay dark -- see the "0 DISABLES one half" contract above. Giving these a "freshly dropped fixture is
## visible" default instead silently lights the disabled half of every one of those instances.
## A new fixture reading black is handled where it belongs: the configuration warning below.
@export var _color: Color = Color.WHITE
@export var _range_omni: float = 0.0
@export var _range_spotlight: float = 0.0
@export var _energy: float = 1.0

## The SOLE owner of "is this fixture humming". The write in `_process` is two-directional, so clearing this
## silences a running buzz -- which also means the authored AudioStreamPlayer3D must NOT set `autoplay`
## (autoplay started the hum on ready no matter what this flag said, and because the stream loops `playing`
## then never went false again, so this export did nothing at runtime and every light hummed).
## HOW FAR that hum carries is the separate "Buzz mix" group below — silence a fixture here, don't do it by
## zeroing its radius (0 means UNLIMITED to Godot, which is the opposite of what you wanted).
@export var _electric_buzz: bool

## Douse this fixture while the WorldClock says DAY — opt-in for streetlamps in a level running the DayNightSky
## cycle. OFF (default) = the fixture burns 24/7, so every authored instance keeps its look. Dousing flips the
## child lights' `visible` (which also removes them from PlayerLightLevel's stealth sampling) and silences the
## buzz — a powered-down lamp doesn't hum. In-editor the fixture always previews LIT (the editor has no clock).
@export var night_only: bool = false

## ⭐A FIXTURE'S HUM IS A **LOCAL** SOUND. These four knobs are pushed into the child AudioStreamPlayer3D every
## frame (same deal as the two lights above: the child's own authored values are overwritten and mean nothing),
## because a level instance cannot reach a child of an instanced scene without "editable children" — so the
## tunable numbers have to live out here on the fixture.
##
## They exist because the shipped defaults made the buzz a GLOBAL sound: `max_distance` was 0 (unbounded) and
## the engine's default air-absorption shelf (5000 Hz / -24 dB) was on. With inverse-distance falloff off a
## ~4 m unit size, a fixture 20 m away still plays only ~14 dB down — plainly audible — and heavily rolled off
## up top. The main level's four buzzing fixtures sit ~19-23 m apart, so they summed into a permanent, dull,
## unlocalised hum roughly 9 dB under the one you were standing beside: "buzzing from somewhere outside".
##
## ⭐That wash was WORST INDOORS, which is why it reads as a bug in the roof duck. `IndoorAmbienceDucker` drops
## the city bed 12 dB and rolls its top end off under a roof, which UNMASKED the wash the bed had been hiding.
## The duck never touched the buzz and still doesn't — the buzz is on `ambient`, the muffle is a bus effect on
## `ambient_bed`, and `ambient_bed` sends INTO `ambient`, so the filter cannot reach back up. It just stopped
## covering for a fixture that was audible from across the map.
@export_group("Buzz mix")
## Volume (dB) the hum plays at once you are within `buzz_falloff_distance`. Raise it for a fixture that should
## dominate a small room; the `ambient` bus adds another +6 dB on top before you hear it.
@export var buzz_volume_db: float = -6.0
## Distance (m) at which the hum sits at exactly `buzz_volume_db` — closer is louder, further falls off
## (inverse-distance). Effectively "how big is the zone where this thing is right on top of you". A ceiling
## fixture hangs 3-5 m over the player's ear, which is why the default sits there: stand under one and you are
## already at full level.
@export var buzz_falloff_distance: float = 4.0
## ⭐Radius (m) past which this fixture drops OUT of the mix. **Leave this above 0.** Godot reads 0 as "no limit",
## which is exactly the unbounded setting that turned four fixtures into one map-wide hum — a config warning
## fires if you clear it. Keep it comfortably under the spacing between your buzzing fixtures (~12 m here, vs
## ~20 m spacing) so at most the nearest one or two are ever in your ears.
@export var buzz_radius: float = 12.0
## Air absorption: the engine dulls a 3D sound's high end as it recedes, by up to `attenuation_filter_db`
## (-24 dB) above this cutoff. **20500 Hz = OFF**, which is the default here for two reasons — a buzz IS its
## high harmonics, so shelving them off is precisely what makes a fixture two metres away read as "something
## outside"; and over a bounded ~12 m radius real air absorption is negligible anyway. Drop it toward 5000 only
## if you WANT a fixture to sound weathered/distant near the edge of its radius.
@export var buzz_air_cutoff_hz: float = 20500.0

func _process(_delta: float) -> void:
	# The refs are authored children of Light.tscn; a designer who renames or deletes one would otherwise fault
	# this every frame. is_instance_valid() covers null AND a freed node (a freed Object is falsy and reading a
	# property off it crashes), and the two lights are guarded apart from the buzz so losing one child doesn't
	# take the others down with it.
	var burn := true
	if night_only and not Engine.is_editor_hint():
		burn = WorldClock.phase() == WorldClock.Phase.NIGHT
	if is_instance_valid(light_source):
		light_source.visible = burn
		light_source.light_color = _color
		light_source.omni_range = _range_omni
		light_source.light_energy = _energy
	if is_instance_valid(spotlight):
		spotlight.visible = burn
		spotlight.light_color = _color
		spotlight.spot_range = _range_spotlight
		spotlight.light_energy = _energy

	if Engine.is_editor_hint():
		return  # @tool: only the light preview above runs in-editor; the buzz is runtime-only
	# Two-directional so `_electric_buzz` really controls the hum, but written only on a CHANGE: assigning
	# `playing = true` to an already-playing stream restarts it from 0. The stream loops (loop=true in its
	# .import), so once started `playing` stays true until this clears it. `burn` folds in so a doused
	# night-only lamp is silent as well as dark.
	var want_buzz := _electric_buzz and burn
	if is_instance_valid(light_buzz):
		_apply_buzz_mix()
		if light_buzz.playing != want_buzz:
			light_buzz.playing = want_buzz


## Push the Buzz-mix exports into the child emitter. Pushed per frame rather than once on ready for the same
## reason the two lights are: this node is the single owner of the child's settings, so a designer dragging a
## slider (in the inspector, or the remote inspector while the game runs) hears the change immediately and
## there is never a second, stale source of truth in Light.tscn. Caller guarantees `light_buzz` is valid.
func _apply_buzz_mix() -> void:
	light_buzz.volume_db = buzz_volume_db
	light_buzz.unit_size = buzz_falloff_distance
	light_buzz.max_distance = maxf(buzz_radius, 0.0)
	light_buzz.attenuation_filter_cutoff_hz = buzz_air_cutoff_hz


## The other half of the "0 DISABLES one half" contract: 0 on BOTH halves is not a spot-only or omni-only
## fixture, it is an invisible one -- which is exactly what a freshly dropped Light looks like. Say so in the
## scene tree instead of shipping a default that would light the disabled half of every authored instance.
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if is_zero_approx(_range_omni) and is_zero_approx(_range_spotlight):
		w.append("Both ranges are 0, so this fixture emits no light. Set _range_omni (point light) and/or _range_spotlight (spotlight); leave the other at 0 to disable that half.")
	# 0 is not "silent", it is Godot's "no distance limit" — the setting that let every buzzing fixture in a level
	# stack into one map-wide hum. Silence a fixture with _electric_buzz, never by zeroing its radius.
	if _electric_buzz and buzz_radius <= 0.0:
		w.append("buzz_radius is 0, which Godot reads as UNLIMITED — this fixture's hum will be audible from anywhere in the level and will pile up with every other buzzing fixture into a dull background wash. Give it a real radius (12 m is the default); to silence the fixture, clear _electric_buzz instead.")
	return w
