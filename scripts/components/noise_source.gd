@tool
class_name NoiseSource
extends Node3D

## A point of SOUND in the world that NPCs can hear and walk over to investigate (the stealth distraction
## channel). Anything in the &"noise" group with a positive `radius` draws a nearby UNAWARE, hearing NPC to
## investigate THIS node's position (NPC._react_unaware -> Perception.investigate_point). One shared channel:
## the player emits one live (NoiseEmitter mirrors player.noise_radius into it each frame), a thrown decoy or a
## beeping machine drops or holds another -- so "lob a crate to lure a guard" needs no new sensing code.
##
## Two modes, by config:
##  - PERSISTENT (decay == 0 AND lifetime == 0): `radius` is driven EXTERNALLY each frame (the player's live
##    noise). This node just sits in the group; whoever owns it sets `radius`. _physics_process is a no-op.
##  - ONE-SHOT (decay > 0 and/or lifetime > 0): a self-contained burst -- `radius` shrinks by `decay`/sec and
##    the node frees itself after `lifetime` seconds. A thrown decoy spawns one of these and forgets it.
##
## Hearing here is distance-only (sound rounds corners, like Perception.can_hear); wall occlusion is a later
## slice. Nothing reads this channel unless an NPC's distraction scan is enabled
## (GameSettings.npc_ai.hearing_initiates), so a NoiseSource is inert by default.

const GROUP := Groups.NOISE  ## same value (&"noise") as before; NpcSenses' NoiseSource.GROUP read is unaffected

# The same tuning resource the GameSettings autoload preloads (Godot caches it by path -> SAME instance).
# Read directly so the editor warning can see the gate value; the GameSettings autoload node isn't present
# in the editor, so GameSettings.npc_ai would be null when _get_configuration_warnings runs.
const _NPC_AI := preload("res://resources/tuning/NpcAiSettings.tres")

@export var radius: float = 0.0    ## current audible radius (m); 0 = silent. Driven live (persistent) or decayed (one-shot)
@export var decay: float = 0.0     ## radius lost per second (one-shot fade); 0 = constant
@export var lifetime: float = 0.0  ## seconds until the node frees itself (one-shot); 0 = persistent (never self-frees)

var _age: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: the editor only evaluates _get_configuration_warnings, never the runtime noise channel
	add_to_group(GROUP)

## One-shot sources fade their radius and expire; a persistent (externally driven) source does nothing here.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return  # @tool: never decay/expire in the editor
	if decay <= 0.0 and lifetime <= 0.0:
		return
	if decay > 0.0:
		radius = maxf(0.0, radius - decay * delta)
	if lifetime > 0.0:
		_age += delta
		if _age >= lifetime:
			queue_free()

## Pure: is a listener at `listener_pos` within `radius_m` of a source at `source_pos`? (a positive radius is
## required, so a silent source is never heard). Static + Vector3-only so it unit-tests off-tree.
static func audible(radius_m: float, source_pos: Vector3, listener_pos: Vector3) -> bool:
	return radius_m > 0.0 and source_pos.distance_to(listener_pos) <= radius_m

## Can a listener at `listener_pos` hear THIS source right now (at its current radius + position)?
func heard_by(listener_pos: Vector3) -> bool:
	return audible(radius, global_position, listener_pos)

## Editor warning: a NoiseSource does nothing unless NPCs are listening to the distraction channel, which
## isn't visible in the scene tree. Surfaces WHY a placed noise has no effect. (Reads the saved flag straight
## from NpcAiSettings.tres -- see _NPC_AI -- so it's accurate without the runtime autoload.)
func _get_configuration_warnings() -> PackedStringArray:
	if not _NPC_AI.hearing_initiates:
		return PackedStringArray([
			"Noise is INERT: NPCs only investigate sound when hearing_initiates is ON (NpcAiSettings.tres, default off). This NoiseSource does nothing until you enable it."
		])
	return PackedStringArray()
