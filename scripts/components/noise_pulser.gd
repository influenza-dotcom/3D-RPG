@tool
class_name NoisePulser
extends Node

## Drop-in that drops a one-shot NoiseSource BURST on the shared &"noise" channel whenever pulse() is called
## — so ANY object can be HEARD by listening NPCs and draw them to investigate, with no bespoke sensing code:
## an NPC's gunfire + death, a breaking window, a tripped alarm, a dropped crate. Attach it under a Node3D and
## call pulse() from whatever event should make a sound. An NPC auto-builds one (npc.gd _build_components) so
## its combat is audible out of the box; drop your own under any prop to make that prop noisy.
##
## Contrast NoiseEmitter (scripts/player/noise_emitter.gd): that mirrors a CONTINUOUS live radius into a
## PERSISTENT source every frame (the player's ongoing footstep / gunfire loudness). NoisePulser is the
## EVENT / one-shot half — discrete bursts that fade and self-free. Both feed the SAME NoiseSource &"noise"
## channel that a distraction-scanning NPC listens to.
##
## Host reads are duck-typed (get_parent() as Node3D for the spawn position), so it NEVER hard-depends on a
## host type — the LocomotionFx drop-in idiom. Inert by default: nothing consumes the &"noise" channel unless
## an NPC opts into it (NpcAiSettings.hearing_initiates), so pulse() spawns nothing until then.

## The tuning resource GameSettings preloads. Keep the preloaded fallback for editor warnings, but read through
## load() at call time so tests / live tuning edits that mutate the cached resource are seen before spawning.
const _NPC_AI := preload("res://resources/tuning/NpcAiSettings.tres")

## Default audible radius (m) of a pulse when pulse() is called without an override. 0 = silent.
@export var radius: float = 12.0
## Radius lost per second as the burst fades. 0 = it holds full radius for its whole lifetime.
@export var decay: float = 0.0
## Seconds until the spawned source frees itself. Floored just above 0 so a pulse is ALWAYS one-shot — never a
## leaking persistent (never-freed) source.
@export var lifetime: float = 0.35
## Minimum seconds between THROTTLED pulses, so a full-auto burst emits a steady pulse instead of one source per
## bullet. Applies ONLY to pulse(throttled = true); an un-throttled pulse (e.g. a death cry) ignores it. 0 = no throttle.
@export var min_interval: float = 0.4

## Emitted right after a pulse actually spawns a source (skipped when silent / throttled / off-tree / unheard).
## Lets a designer chain other feedback off a noise without re-deriving when it fired.
signal pulsed(source: NoiseSource)

var _last_pulse_ms: int = -100000

## Drop a one-shot NoiseSource at the host's position on the &"noise" channel. `radius_override` >= 0 wins over
## the @export `radius` (an NPC passes its own gunfire vs death radius); `throttled` gates on min_interval
## (gunfire yes, a one-off death cry no). Returns the spawned source, or null when the pulse is silent (radius 0),
## throttled, off-tree, or nothing is listening (the channel is inert). Safe to call every frame.
func pulse(radius_override: float = -1.0, throttled: bool = false) -> NoiseSource:
	var r := radius_override if radius_override >= 0.0 else radius
	if r <= 0.0:
		return null
	var host := get_parent() as Node3D
	if host == null or not host.is_inside_tree():
		return null  # off-tree: nowhere to place the sound
	if throttled:
		var now := Time.get_ticks_msec()
		if now - _last_pulse_ms < int(min_interval * 1000.0):
			return null  # within the throttle window — fold this pulse into the last one
		_last_pulse_ms = now
	# Inert unless a listener is enabled: the channel's only consumer is the hearing_initiates distraction scan,
	# so don't spawn a node nobody can hear (avoids per-bullet node churn in a firefight when nothing listens).
	if not _hearing_initiates_enabled():
		return null
	var src := NoiseSource.new()
	src.radius = r
	src.decay = decay
	src.lifetime = maxf(lifetime, 0.05)  # always one-shot — never a persistent (leaking) source
	# Parent to the host's PARENT (a sibling of the host), not under the host, so the sound OUTLIVES the emitter
	# being freed this frame — an NPC's death pulse must survive the NPC's own queue_free. Fall back to under the
	# host if it has no parent (it's a scene root).
	var holder: Node = host.get_parent()
	if holder == null:
		holder = host
	holder.add_child(src)
	src.global_position = host.global_position
	pulsed.emit(src)
	return src

## Editor warning: a NoisePulser does nothing unless NPCs are listening to the distraction channel, which isn't
## visible in the scene tree. Mirrors NoiseSource's warning so a placed pulser explains its own silence.
func _get_configuration_warnings() -> PackedStringArray:
	if not _hearing_initiates_enabled():
		return PackedStringArray([
			"Noise is INERT: NPCs only investigate sound when hearing_initiates is ON (NpcAiSettings.tres, default off). This NoisePulser does nothing until you enable it."
		])
	return PackedStringArray()

func _hearing_initiates_enabled() -> bool:
	var live := load("res://resources/tuning/NpcAiSettings.tres") as NpcAiSettings
	if live != null:
		return live.hearing_initiates
	return _NPC_AI.hearing_initiates
