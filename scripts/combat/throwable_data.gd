class_name ThrowableData
extends Resource

## Data resource for a destructible / grabbable physics prop (crates, gore gibs, etc.) — the Throwable
## analogue of WeaponData. Throwable.gd reads these to set HP, mass, look, sounds, and destruction FX, so
## one Throwable scene can be reskinned into many object types purely by swapping the .tres.

@export_group("Stats")
## Hit points before the prop is destroyed. Higher = takes more hits/impacts to break.
@export var max_hp: int = 5
## Physics mass (kg). Heavier = harder to shove and throws/falls with more momentum. Only applied when > 0.
@export var mass: float = 1.0
## Optional PhysicsMaterial — sets bounce and friction. Null = keep the Throwable scene's default surface feel.
@export var physics_material: PhysicsMaterial

@export_group("Appearance")
## Mesh shown for this prop. Null = keep whatever the Throwable scene ships with.
@export var mesh: Mesh
## Material override painted onto the mesh. Null = use the mesh's own material.
@export var material: Material

@export_group("Audio")
## Sound played when the prop takes a hard knock (collision impact). Null = silent on impact.
@export var impact_sound: AudioStream
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
## Whether a high-speed impact from this prop hurts the PLAYER. Gore gibs set this false so being pelted
## by your own kill's flying chunks can't chip your health. Other characters still take it.
@export var damages_player: bool = true
## Marks this prop as a gore gib (a flying body chunk) rather than a crate/barrel. A gib the PLAYER shoots
## out of the air bursts into confetti + a party horn instead of the usual gore puff.
@export var is_gib: bool = false

@export_group("Stealth")
## When ON, a THROWN copy of this prop drops a one-shot NoiseSource where it lands, luring NPCs that hear it
## (only does anything with GameSettings.npc_ai.hearing_initiates on). OFF (default) -> no decoy. The "lob a
## rock to distract a guard" verb. Loudness/duration come from GameSettings.distraction unless overridden below.
@export var noise_on_land: bool = false
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
