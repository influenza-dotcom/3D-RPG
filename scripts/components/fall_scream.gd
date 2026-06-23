class_name FallScream
extends Node

## Drop-in: plays a SCREAM once the host actor has been FALLING for more than a moment, then re-arms on landing.
## Drop it under any CharacterBody3D (an NPC -- the Enemy root -- or the player) and it polls the host's fall
## state: airborne AND descending faster than min_fall_speed for min_fall_time seconds -> one positional yell on
## the sfx bus. Inert if `scream` is cleared. Duck-typed (is_on_floor + velocity), so it never hard-depends on a type.
##
## SETUP: drop under the NPC. The default scream is a placeholder hurt grunt (Augh) -- swap for a proper falling
## yell. Tune min_fall_time / min_fall_speed / volume_db to taste.

## The yell played once a fall lasts longer than min_fall_time. Null -> inert. Placeholder = a hurt grunt; swap it.
@export var scream: AudioStream = preload("res://assets/audio/sfx/Augh.mp3")
## Seconds of continuous FALLING (airborne + descending faster than min_fall_speed) before the scream fires.
@export var min_fall_time: float = 1.1
## Minimum downward speed (m/s) to count as a real plummet -- filters a slow slope-slide or a small step-off.
@export var min_fall_speed: float = 1.5
## Playback volume (decibels); 0 = unchanged, negative = quieter.
@export var volume_db: float = 0.0
## Master switch — uncheck to make this component inert (no polling, no scream) without removing it.
@export var enabled: bool = true

const POLL_INTERVAL: float = 0.2  ## seconds between fall-state polls (a per-frame poll on every actor is waste; mirrors DetectionStinger)

var _fall_time: float = 0.0   ## seconds spent continuously falling (reset on landing / on slowing below the speed gate)
var _screamed: bool = false   ## latched so one fall yells once; cleared on landing so the next fall can scream again
var _poll_t: float = 0.0      ## counts down to the next poll; the elapsed interval is fed to the fall timer

func _process(delta: float) -> void:
	if not enabled:
		return
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	# Seconds that actually elapsed since the previous poll fired (POLL_INTERVAL plus any overshoot), so the
	# fall timer stays accurate regardless of frame rate / how the polls land. Then re-arm.
	var elapsed := POLL_INTERVAL - _poll_t
	_poll_t = POLL_INTERVAL
	var host := get_parent()
	if host == null:
		return
	var grounded := HostMethodHelper.try_call_bool(host, &"is_on_floor")
	var vy := 0.0
	var v: Variant = host.get(&"velocity")
	if v is Vector3:
		vy = v.y
	# On the ground, or not descending fast enough -> reset the timer and re-arm for the next fall.
	if grounded or vy > -min_fall_speed:
		_fall_time = 0.0
		_screamed = false
		return
	_fall_time += elapsed
	if not _screamed and _fall_time >= min_fall_time and scream != null and host is Node3D:
		_screamed = true
		AudioManager.play_sfx((host as Node3D).global_position, scream, volume_db)
