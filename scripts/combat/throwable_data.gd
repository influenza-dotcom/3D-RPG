@tool
class_name ThrowableData
extends Resource

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")

## Data resource for a destructible / grabbable physics prop (crates, gore gibs, etc.) — the Throwable
## analogue of WeaponData. Throwable.gd reads these to set HP, mass, look, sounds, and destruction FX, so
## one Throwable scene can be reskinned into many object types purely by swapping the .tres.

@export_group("Identity")
## Optional noun shown in the hover prompt. "Dog" renders as "[throw key] Pick Up Dog".
## Leave blank for the generic "Pick Up" prompt, or override per placed Throwable instance.
@export var display_name: String = "":
	set(value):
		display_name = "" if value == null else String(value)

@export_group("Stats")
## Hit points before the prop is destroyed. Higher = takes more hits/impacts to break.
@export var max_hp: int = 5
## Physics mass (kg). Heavier = harder to shove and throws/falls with more momentum. Only applied when > 0.
@export var mass: float = 1.0
## Optional PhysicsMaterial — sets bounce and friction. Null = keep the Throwable scene's default surface feel.
@export var physics_material: PhysicsMaterial

@export_group("Appearance")
## Model shown for this prop. Supports scene imports (.glb/.gltf/.blend) and raw Mesh imports (.obj).
## Null = keep whatever the Throwable scene ships with.
@export var mesh: Resource
## Material override painted onto the mesh. Null = use the mesh's own material.
@export var material: Material

@export_group("Audio")
## Sound played once when the player picks this prop up. Null = silent unless the placed Throwable overrides it.
@export var pickup_sound: AudioStream
## Sound looped while the player is carrying this prop. Null = silent unless the placed Throwable overrides it.
@export var held_loop_sound: AudioStream
## Sound played once when the player lets go by dropping, throwing, or forced release. Null = silent unless overridden.
@export var release_sound: AudioStream
## Sound played when the prop takes a hard knock (collision impact). Null = silent on impact.
@export var impact_sound: AudioStream
## Sound played when the prop strikes a CHARACTER (an NPC or the player) — e.g. the Dog's bite — INSTEAD of the
## generic impact thud. Null = a character hit just uses the normal impact_sound. A placed Throwable can override.
@export var character_impact_sound: AudioStream
## Sound played when the prop is destroyed. Null = silent on break.
@export var destroy_sound: AudioStream

@export_group("Destruction FX")
## Particle burst spawned on destruction. Null = fall back to the default large-dust puff.
@export var destroy_particle_scene: PackedScene
## Camera kick when this prop is destroyed (trauma units). Higher = a bigger jolt; null data uses the global interactable-destroy shake.
@export var destroy_screen_shake: float = 0.35
## Leave a scorch/blast decal on the floor when destroyed (e.g. crates). Gibs set this false since they
## spawn their own blood decals.
@export var spawns_destroy_decal: bool = true

@export_group("Behaviour")
## When ON, the prop becomes partially see-through while carried so it does not block the camera.
## Turn OFF for props that should stay opaque in the player's hands, such as Dog.
@export var fade_while_held: bool = true
## While carried, yaw the prop so its front faces back toward the player/camera (Portal-style presentation).
@export var face_carrier_while_held: bool = false
## Extra local rotation, in degrees, applied after the face-carrier yaw. Use this when an imported mesh's
## authored front is not Godot's -Z (e.g. set Y=180 if it faces backward). Also corrects the THROWN facing below.
@export var face_carrier_rotation_degrees: Vector3 = Vector3.ZERO
## When THROWN (not merely dropped), the prop noses toward its travel direction (a knife/spear leads with its
## point and tips over as it arcs). OFF for crates. A placed Throwable can also enable this per-instance. Uses
## face_carrier_rotation_degrees as the mesh-front correction.
@export var face_travel_when_thrown: bool = false
## Below this speed (m/s) the thrown-facing releases and the prop tumbles/rests naturally. A placed Throwable with
## face_travel_min_speed > 0 overrides this; both default to ~2.0.
@export var face_travel_min_speed: float = 2.0
## Living-prop idle: visually pulse the mesh scale around its authored size. Off for crates, on for things like Dog.
@export var breathe: bool = false
## Peak visual scale delta: 0.03 = the prop swells about 3% at the top of the inhale. Physics/collider stay fixed.
@export var breathe_amount: float = 0.03
## Breathing sine rate; 1.6 is the same calm idle cadence used by NPC torsos.
@export var breathe_rate: float = 1.6
## Whether a high-speed impact from this prop hurts the PLAYER. Gore gibs set this false so being pelted
## by your own kill's flying chunks can't chip your health. Other characters still take it.
@export var damages_player: bool = true
## Whether props of this type can be DAMAGED/DESTROYED at all. ON by default (crates/barrels/gibs break). Set OFF on an
## ITEM resource (dropped weapons, pickups) so every instance is indestructible in one place — a stray shot/impact
## can't break a lootable. A placed Throwable can also force it off per-instance (the two compose: either OFF = can't
## be destroyed). Read via Throwable.is_destructible().
@export var destructible: bool = true
## Marks this prop as a gore gib (a flying body chunk) rather than a crate/barrel. A gib the PLAYER shoots
## out of the air bursts into confetti + a party horn instead of the usual gore puff.
@export var is_gib: bool = false

@export_group("Stealth")
## When ON, a THROWN copy of this prop drops a one-shot NoiseSource where it lands, luring NPCs that hear it
## (only does anything with GameSettings.npc_ai.hearing_initiates on). ON (default) -> every thrown prop is a
## decoy; set OFF for a silent throwable. The "lob a rock to distract a guard" verb. Loudness/duration come
## from GameSettings.distraction unless overridden below.
@export var noise_on_land: bool = true
## Per-prop decoy-noise overrides; NEGATIVE (default) inherits GameSettings.distraction. radius/decay accept 0
## as a valid override (a silent or constant-radius source); lifetime instead requires a value > 0 to override
## -- a 0/negative lifetime inherits the default, because a non-positive lifetime would make the NoiseSource
## PERSISTENT (never frees, pins NPCs forever), which is never a sensible decoy. Lets a loud can and a quiet
## pebble differ while most props just use the default.
@export var noise_radius: float = -1.0
@export var noise_decay: float = -1.0
@export var noise_lifetime: float = -1.0

## Resolve this prop's thrown-decoy noise config against the global `defaults` (GameSettings.distraction):
## radius/decay use the override when >= 0; lifetime uses it only when > 0 (so a decoy is always one-shot).
## Else the global default. Pure -> unit-testable. Only meaningful when noise_on_land is true. {radius, decay, lifetime}.
func resolved_decoy(defaults: DistractionSettings) -> Dictionary:
	return {
		&"radius": noise_radius if noise_radius >= 0.0 else defaults.decoy_radius,
		&"decay": noise_decay if noise_decay >= 0.0 else defaults.decoy_decay,
		&"lifetime": noise_lifetime if noise_lifetime > 0.0 else defaults.decoy_lifetime,
	}

func _validate_property(property: Dictionary) -> void:
	if property.name == &"mesh":
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResourceUtil.HINT
