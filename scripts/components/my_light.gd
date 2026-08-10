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
@export var _electric_buzz: bool

func _process(_delta: float) -> void:
	# The refs are authored children of Light.tscn; a designer who renames or deletes one would otherwise fault
	# this every frame. is_instance_valid() covers null AND a freed node (a freed Object is falsy and reading a
	# property off it crashes), and the two lights are guarded apart from the buzz so losing one child doesn't
	# take the others down with it.
	if is_instance_valid(light_source):
		light_source.light_color = _color
		light_source.omni_range = _range_omni
		light_source.light_energy = _energy
	if is_instance_valid(spotlight):
		spotlight.light_color = _color
		spotlight.spot_range = _range_spotlight
		spotlight.light_energy = _energy

	if Engine.is_editor_hint():
		return  # @tool: only the light preview above runs in-editor; the buzz is runtime-only
	# Two-directional so `_electric_buzz` really controls the hum, but written only on a CHANGE: assigning
	# `playing = true` to an already-playing stream restarts it from 0. The stream loops (loop=true in its
	# .import), so once started `playing` stays true until this clears it.
	if is_instance_valid(light_buzz) and light_buzz.playing != _electric_buzz:
		light_buzz.playing = _electric_buzz


## The other half of the "0 DISABLES one half" contract: 0 on BOTH halves is not a spot-only or omni-only
## fixture, it is an invisible one -- which is exactly what a freshly dropped Light looks like. Say so in the
## scene tree instead of shipping a default that would light the disabled half of every authored instance.
func _get_configuration_warnings() -> PackedStringArray:
	if is_zero_approx(_range_omni) and is_zero_approx(_range_spotlight):
		return PackedStringArray(["Both ranges are 0, so this fixture emits no light. Set _range_omni (point light) and/or _range_spotlight (spotlight); leave the other at 0 to disable that half."])
	return PackedStringArray()
