class_name PhysicsDamageSettings
extends Resource

## The physics / damage / interaction tuning hub, grouped below. Consumed broadly:
## explosion damage (Explosion), player ram + body-check (player.gd), character-vs-
## rigidbody push (Character), the blast/recovery decay (Character.apply_blast), enemy
## knockback friction (Enemy), the pickup/throw system (PickupRay), and all
## Throwable impact/damage/destruction behaviour.

@export_group("Explosion")
## Base damage one explosion deals to a character caught in its radius (a default; per-explosion overrides can differ).
@export var explosion_damage: int = 1

@export_group("Player Ram")
## Min player speed (m/s) at which body-checking an enemy starts dealing ram damage — below this, contact does nothing. Lets the launch weapon / bhop hurt on contact.
@export var ram_min_speed: float = 8.0
## Legacy/minimum ram damage reference. Actual hit = round(speed * ram_damage_per_speed), floored at 1.
@export var ram_damage: int = 2
## Ram damage per m/s of impact speed — the slope of the speed-to-damage curve. Higher = faster rams hit much harder.
@export var ram_damage_per_speed: float = 0.35
## Knockback impulse applied to an enemy you ram. Bigger = they fly further.
@export var ram_knockback: float = 10.0
## Min seconds between ram hits on the same enemy so one body-check isn't counted every frame of contact.
@export var ram_cooldown: float = 0.25

@export_group("Character Push")
## Impulse multiplier when a character (player or enemy) walks into a RigidBody3D prop: impulse = into-speed * this. 0 disables the shove.
@export var character_push_force: float = 0.6

@export_group("Blast / Recovery")
## Seconds a fresh blast push survives even on the floor before ground friction can cancel it — lets rocket-jumps actually launch you. Bigger = blasts carry longer.
@export var blast_grace_timer: float = 0.2
## Per-frame fraction (at reference FPS) of leftover blast velocity bled off each tick — higher = the launch dies out faster.
@export var blast_decay_rate: float = 0.05
## Blast velocity below this magnitude is snapped to zero as negligible — the cutoff that ends a decaying launch.
@export var blast_min_magnitude: float = 0.1

@export_group("Enemy Movement Physics")
## Friction that bleeds off a knocked-back enemy's horizontal velocity while grounded (higher = they slide to a stop sooner).
@export var enemy_ground_friction: float = 8.0
## Friction applied to enemy knockback while airborne — usually much lower than ground so launched enemies keep flying.
@export var enemy_air_friction: float = 1.0
## Speed below which enemy knockback velocity is treated as stopped — the friction cutoff.
@export var enemy_friction_min_speed: float = 0.01

@export_group("Pickup / Holding")
## How fast a held object chases the hold anchor in front of the camera (higher = stiffer, snappier carry; lower = floatier).
@export var pickup_hold_follow_rate: float = 14.0
## Cap (metres) on how far a held object can be repositioned in a single frame — stops teleport-jitter on big anchor jumps.
@export var pickup_max_step_per_frame: float = 0.5
## Spin damping on a held object so it stops tumbling while carried (closer to 1 = bleeds spin off faster).
@export var pickup_hold_angular_damping: float = 0.85
## How far (metres) a held object can drift from the anchor before it's auto-dropped — yank it past this and you lose grip.
@export var pickup_max_hold_distance: float = 4.0
## Launch impulse on a quick TAP release (a gentle drop) versus a held throw.
@export var pickup_drop_impulse: float = 1.0
## Launch impulse on a charged THROW (held the release key past pickup_e_hold_threshold) — bigger = harder throws.
@export var pickup_throw_impulse: float = 12.0
## Hold time (s) on the release key that separates a soft drop from a full throw — tap under this drops, hold over it throws.
@export var pickup_e_hold_threshold: float = 0.18
## Physics collision layer a held object is moved to while carried (so it stops colliding with the world/player). RAW collision-layer BITMASK, not a 1<<index: PickupRay does collision_layer = this directly and every sight/perception ray clears it via TalkHelpers.held_prop_collision_layer() & ~mask. Value 4 = editor layer 3.
@export var pickup_held_collision_layer: int = 4
## Seconds the player keeps a no-collision exception with a just-dropped object so it doesn't immediately bump you.
@export var pickup_drop_exception_delay: float = 1.0
## Sideways nudge (metres) applied to a dropped object so it lands beside you, not on your head.
@export var pickup_drop_lateral_nudge: float = 0.6
## Horizontal clearance (metres) a drop must have from the player to be considered safe; too close triggers the slide-off push.
@export var pickup_safe_horizontal_distance: float = 1.0
## Push impulse used to slide a dropped object off the player when it lands too close.
@export var pickup_slide_off_impulse: float = 3.0
## Seconds between re-checks of a dropped object's clearance before restoring normal player collision.
@export var pickup_safe_recheck_delay: float = 0.3
## Fraction of a moving held object's velocity passed into a character it rams (a carried prop becomes a weak melee weapon). 0 disables it.
@export var pickup_ram_knockback_scale: float = 0.7

@export_group("Throwable / Crate")
## Fallback HP for a throwable/crate with no NpcData of its own — how many hits a default prop survives.
@export var interactable_max_hp_default: int = 5
## Impact speed (m/s) below which a thrown/colliding prop plays NO impact thud — quiet taps stay silent.
@export var interactable_impact_min_velocity: float = 1.5
## Impact speed (m/s) mapped to the LOUDEST impact thud — the top of the volume ramp. Keep above min_velocity.
@export var interactable_impact_max_velocity: float = 10.0
## Impact thud volume (dB) at min_velocity — the quiet end of the impact-sound ramp.
@export var interactable_impact_min_db: float = -24.0
## Impact thud volume (dB) at max_velocity — the loud end of the impact-sound ramp.
@export var interactable_impact_max_db: float = 0.0
## Min seconds between a prop's impact thuds so one tumble plays distinct hits, not a buzzing drumroll.
@export var interactable_impact_cooldown: float = 0.08
## Random pitch wobble (±) on a prop's impact thud so repeated bumps vary.
@export var interactable_impact_pitch_spread: float = 0.15
## Knockback impulse a bullet imparts to a RigidBody3D prop it hits — how much shooting a crate shoves it.
@export var bullet_interactable_knockback: float = 5.0
## Impact speed (m/s) below which a flying prop deals NO damage to a character it hits — the harm threshold.
@export var interactable_damage_min_velocity: float = 6.0
## Damage a flying prop deals per m/s of impact speed above the threshold — the slope of prop-vs-character damage.
@export var interactable_damage_per_m_per_s: float = 0.4
## Fraction of a damaging prop's velocity passed into the victim as knockback.
@export var interactable_damage_knockback_scale: float = 0.6
## Min seconds between damage ticks one prop can deal to a character — stops a resting prop from grinding HP away.
@export var interactable_damage_cooldown: float = 0.5
## Impact speed (m/s) below which a prop takes NO self-damage from slamming into things — props ignore gentle bumps.
@export var interactable_self_damage_min_velocity: float = 5.0
## Self-damage a prop takes per m/s of impact speed above its threshold — how fast hard impacts wear a crate down.
@export var interactable_self_damage_per_m_per_s: float = 0.3
## Default screen-shake punch when a prop is destroyed (a prop's own NpcData can override it). 0 = no shake.
@export var interactable_destroy_shake_amount: float = 0.4
## How close (metres) the player must be to feel a destroyed prop's screen shake; closer = stronger.
@export var interactable_destroy_shake_range: float = 8.0
