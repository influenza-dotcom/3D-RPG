@tool
class_name WeaponData
extends Resource

## A weapon definition — every knob the firing pipeline reads. Make a new weapon by creating a WeaponData
## .tres and filling these in; the @export_groups below are how they're laid out in the Inspector.
## @tool only so the `caliber` field self-populates its dropdown (see _validate_property) — no editor lifecycle.

## Drives the `caliber` dropdown from the ammo calibers on disk (const-preloaded, NO class_name — see calibers.gd).
const Calibers = preload("res://scripts/items/calibers.gd")

@export_group("General")
## Max hitscan reach (metres) — the raycast stops here, so beyond it a hip/scoped shot hits nothing.
## Also the NPC standoff distance when this weapon sets it (>0). 0 = unranged: AI falls back to npc_ai.unranged_aim_fallback.
@export var effective_range: float = 20.0
## Movement-speed multiplier applied to the wielder WHILE THIS WEAPON IS DRAWN (not holstered).
## 1.0 = no penalty; a heavier weapon sets this lower (e.g. 0.8) to slow the holder down, FNV-style.
@export var move_speed_multiplier: float = 1.0

@export_group("Damage")
## MELEE weapon? A melee weapon's damage scales with the wielder's STRENGTH (CharacterStats.melee_damage_mult) and
## skips the gunplay headshot bonus; a ranged one scales with GUNPLAY. This is an EXPLICIT flag, NOT inferred from
## effective_range — a hitscan melee weapon still needs a POSITIVE effective_range so its raycast actually reaches
## (a 0-range ray hits nothing; see DamageTrace seg_range). Set true on knives/fists/bats; false (default) for guns.
@export var is_melee: bool = false
## Damage per hit (per pellet for shotguns). In HP — the player has 4 HP by default, so 1.0 = a quarter health.
@export var damage: float = 1.0
## Damage multiplier when a shot lands in a target's head zone (see Character.head_local_y).
@export var headshot_multiplier: float = 2.0
## Damage multiplier for a sneak attack — hitting an enemy that hasn't noticed you yet (not ALERTED).
## Stacks with headshot_multiplier, so a stealth headshot is multiplier x multiplier.
@export var sneak_attack_multiplier: float = 2.0
## Damage multiplier for a BACKSTAB — a hit landed within backstab_arc_degrees of the victim's REAR. 1.0 =
## no backstab bonus (the default; the mechanism is inert until a designer raises it). Stacks with crit + sneak.
@export var backstab_multiplier: float = 1.0
## Rear-arc width (degrees) that counts as a backstab — wider = easier to land. 90 = the back quarter.
@export var backstab_arc_degrees: float = 90.0
## When a shot deals MORE damage than the victim's remaining HP, the excess "overkill" pierces through
## and carries on to hit whoever's behind them (hitscan + projectiles). Default on. The overkill passes
## through as flat damage (no re-applied crit/sneak multipliers).
@export var overkill_penetration: bool = true

# How a DROPPED copy of this weapon behaves as a physics prop — the H verb takes the wielded weapon into your hands,
# and left-click / a Z-hold throws it. A weapon drop carries NO ThrowableData, so these are its authoring surface.
# MOST of them (thrown_impact_damage_mult / thrown_faces_travel / thrown_face_rotation_degrees / thrown_impulse_mult /
# thrown_sound / held_faces_aim / dropped_item_light_always_lit) are stamped onto the drop's Throwable — or, for
# the item light, onto its CanPickUp — by WorldItem._make_throwable; the other two shape the drop itself in
# WorldItem.build — and those two are read ONLY in its case 3 (a weapon whose view_model is the drop's visual), with
# dropped_model_offset additionally gated on npc_hold_override. Plain `#`, not `##`: a bare @export_group isn't a
# member, so a doc comment here would attach to the wrong thing.
@export_group("Thrown")
## Resolve a THROWN hit on a Character as a real WEAPON hit — this weapon's `damage`, its `headshot_multiplier` on a
## hit in the head zone, and its melee/ranged stat scaling — instead of the generic speed-based prop bludgeon (stamped
## onto Throwable.thrown_weapon). ON is what makes a thrown knife hit for what a knife SWING hits for, headshots
## included, and it also forwards the located hit so limb/zone damage applies. Turn it on for any weapon whose thrown
## form should read as the weapon rather than as a heavy object; leave it OFF (default) for a gun, which really is
## just a lump when you throw it. Why it matters beyond flavour: the blunt formula scales with IMPACT SPEED, so a
## weapon tuned to fly faster silently hit far harder — a 2.5x launch speed took the knife from ~10 to ~50 damage.
## Weapon damage is speed-independent, so the two knobs stop fighting.
@export var thrown_uses_weapon_damage: bool = false
## A LETHAL thrown hit from a dropped copy staples the body part it struck to the surface behind the victim, with
## the blade left embedded through it, while the rest of the body slumps (stamped onto Throwable.pins_body_part;
## the effect lives in GoreSpawner._resolve_pin and the "Pinned body parts" group on GameSettings.effects).
## REQUIRES `thrown_uses_weapon_damage` — the pin needs that path's located contact point to know which part was
## struck, and the blunt speed path deliberately carries no location at all. It also needs a BodyModelSwap on the
## victim (it re-routes one of the limbs the death burst already flings) and something solid behind them; with no
## surface in range the kill silently plays as an ordinary burst. OFF by default: it is a signature move for a
## thrown BLADE, not something a tossed pistol should do.
@export var thrown_pins_body_part: bool = false
## Multiplier on the IMPACT damage a DROPPED copy of this weapon deals to a Character when THROWN (stamped onto the
## drop's Throwable.impact_damage_mult). Applies on BOTH damage paths, so it keeps one meaning — "how hard this prop
## hits when thrown" — whether the hit is the speed-based bludgeon or a `thrown_uses_weapon_damage` weapon hit. It is
## DISTINCT from `damage` (the melee/gunplay swing). 1.0 = no change: a gun tumbles and thuds, and a weapon-damage
## thrower lands exactly its swing damage. Raise it for a weapon that should hit HARDER thrown than swung. A dropped
## weapon is also made indestructible by that same stamp, independent of this number.
@export var thrown_impact_damage_mult: float = 1.0
## Nose a THROWN copy toward its TRAVEL direction so a thrown knife leads with its point instead of tumbling (stamped
## onto Throwable.face_travel_when_thrown). Throwable._integrate_forces then re-aims the body each physics step and
## hands it back to physics once it slows below DEFAULT_FACE_TRAVEL_MIN_SPEED (2.0 m/s). It arms ONLY on a real THROW —
## left-click while carrying, or a long Z/E hold — never on the H tap-drop or a death/quickload release.
## FALSE (default) = the drop tumbles end over end, which is right for a gun.
@export var thrown_faces_travel: bool = false
## Mesh-front correction (Euler degrees) for that thrown facing, stamped onto Throwable.face_carrier_rotation_degrees
## — the SAME field the CARRY pose uses, because Throwable shares one correction between the two. Whether it ALSO
## poses the drop in your hands is decided by `held_faces_aim` below: OFF (guns) leaves this thrown-only, ON (the
## knife) reuses it for the carry pose too. The aim basis points the drop's LOCAL -Z along travel,
## so a model whose business end isn't -Z *in the drop's local space* needs a correction here. The knife needs Y=180:
## its blade points mesh -X, and npc_hold_rotation's (0,90,0) maps that onto the drop's +Z — the TAIL of the aim — so
## uncorrected it would fly HANDLE-first.
@export var thrown_face_rotation_degrees: Vector3 = Vector3.ZERO
## Multiplier on the LAUNCH SPEED of a real throw of a dropped copy (stamped onto Throwable.throw_impulse_mult, which
## PickupRay._release applies to GameSettings.physics_damage.pickup_throw_impulse). 1.0 (default) = a gun tumbles away
## at the same speed as a tossed crate; raise it for a weapon meant to be HURLED — the knife should leave the hand
## fast enough to read as a thrown blade, not a lobbed object. Only a real throw is scaled: the H tap-drop and the
## death/quickload release stay gentle. A value > 1.0 ALSO turns on continuous collision detection for the drop
## (WorldItem._make_throwable), because a fast, slender body can otherwise tunnel through thin geometry in one
## physics tick.
@export var thrown_impulse_mult: float = 1.0
## Sound played when a dropped copy is really THROWN (stamped onto Throwable.throw_sound), instead of its release
## sound. Null (default) = a throw is as quiet as a drop, which is right for a gun you toss aside; author it for a
## weapon with a signature throw (the knife's whip). Distinct from `audio`, the SWING/fire sound of the wielded weapon.
@export var thrown_sound: AudioStream
## While the drop is CARRIED in your hands, yaw it so its business end points DOWN YOUR LOOK DIRECTION — a knife held
## blade-forward, ready to throw. Stamped onto Throwable.face_carrier_while_held + face_carrier_reversed (a weapon has
## only one sensible carry pose, so the one flag sets both: it uses the dog's face-carrier machinery, REVERSED — the
## dog turns to present its face to you, a weapon points away from you). OFF (default) = the drop keeps whatever
## rotation it was grabbed at, which is right for a gun. Because the pose already matches where the throw will send
## it, releasing doesn't visibly snap the model around. It reuses thrown_face_rotation_degrees as the mesh-front
## correction (Throwable shares one field between the carry and thrown poses) — do NOT try to flip the held facing by
## adding 180 there, since that same value is what makes the blade lead in FLIGHT and it would spin in the air too.
@export var held_faces_aim: bool = false
## Keep the dropped copy's red weapon ITEM LIGHT burning at full brightness at every range, instead of fading out as
## you close on it (stamped onto CanPickUp.item_light_always_lit -> PickupBeacon.always_lit). The normal fade is built
## for loot on the ground and is fully OFF inside 3 m, so a weapon in your hands or just leaving them has no glow at
## all. Turn ON for a weapon you actually carry and throw — the knife then reads with the same red pickup glow held,
## in flight, and on the floor. Governed by the player's Loot Beacons option like every other item light.
@export var dropped_item_light_always_lit: bool = false
## Extra LOCAL offset (metres) that re-centres the DROPPED copy's view_model on the drop's body, added on top of
## npc_hold_position by WorldItem.build. Read NOWHERE else — the NPC hand mount (npc.gd _build_weapon_mesh), the FP
## rig, the icon baker and the inspect preview all ignore it — so a drop can be nudged without disturbing any
## authored hand/FP pose. GATED TWICE: only in build()'s case 3 (the weapon's view_model IS the drop's visual, i.e. no
## world_model) AND only when npc_hold_override is ON, since it rides that same re-pose block; it is a silent no-op
## otherwise. Worth authoring because the THROWN facing rotates the BODY about its own origin, so any residual offset
## between the posed model and that origin becomes the spin's pivot arm and the prop wobbles instead of nosing
## cleanly. Author it as the NEGATED centre of the model's posed bounds. Usually a small trim: the knife's re-pose
## already lands within a few cm (its GLB nodes bake a +44.33 translation that knife.tscn's -0.4285 child origin
## cancels), so do NOT assume a large value is needed — measure the posed bounds.
@export var dropped_model_offset: Vector3 = Vector3.ZERO
## Collision box (metres) for the DROPPED copy, replacing the shared default 0.7 x 0.3 x 0.3 slab that suits a gun
## lying flat. ZERO (the default) keeps that slab. Author it for a weapon that sets thrown_faces_travel: the facing
## pins the drop's local +Z along travel, so a mis-shaped box is DETERMINISTICALLY broadside to every throw — a
## thrown knife in the default box would clip geometry ~0.35 m to its side while its tip pokes out the front. Match
## the posed model's own extents (the knife is a slender ~0.44 m blade along local Z). Read only in WorldItem.build
## case 3; the pickup hitbox is derived from it, so it keeps its easy-to-aim-at margin automatically.
@export var dropped_collision_size: Vector3 = Vector3.ZERO

@export_group("Firing")
## Shots fired per trigger pull. 1 = single bullet; >1 = a shotgun spread (each pellet rolls damage + knockback independently).
@export var pellet_count: int = 1
## Cone half-angle the pellets scatter within (radians-ish spread factor). Higher = wider buckshot pattern; 0 = dead-on. Only matters when pellet_count > 1.
@export var pellet_spread: float = .1
## Hold to keep firing (full-auto)? false = one attack per click (semi-auto).
@export var auto_fire: bool = true # hold to keep firing? false = one attack per click (semi-auto)
## Wind-up delay (seconds) between the click and the swing actually landing, for weight. 0 = instant
## (the default for all ranged weapons).
@export var attack_windup: float = 0.0
## Cooldown between shots (seconds) — the fire-rate timer. LOWER = faster gun (0.1 = 10 shots/sec); higher = slower.
@export var attack_speed: float = 0.1

## Rough combat power for AI weapon RANKING (the NPC "equip the strongest" rule + container scavenging):
## damage per attack cycle times pellets, over the cadence — a consistent ordering, not a balance number.
func power_score() -> float:
	return damage * maxf(float(pellet_count), 1.0) / maxf(attack_speed, 0.05)

@export_group("Recoil & Bloom")
## Degrees the aim kicks UP per shot (the muzzle climbs) — a transient offset that recovers over time. The
## PLAYER's AimSway reads these (NPCs never do); 0 = no recoil, so an unconfigured weapon behaves exactly as before.
@export var recoil_kick_deg: float = 0.0
## Max degrees of RANDOM horizontal kick per shot (the gun also wanders sideways under fire). 0 = purely vertical.
@export var recoil_horizontal_deg: float = 0.0
## How fast the recoil kick recovers back to centre, per second (higher = snappier return). Only bites when recoil is set.
@export var recoil_recovery: float = 8.0
## Degrees of extra SPREAD added to the aim wander per shot — sustained fire blooms wider. 0 = no bloom (inert).
@export var bloom_per_shot_deg: float = 0.0
## Cap on accumulated bloom spread (degrees); sustained fire can't widen past this. 0 = no bloom.
@export var bloom_max_deg: float = 0.0
## How fast bloom recovers back to zero when not firing, per second (higher = tightens up faster).
@export var bloom_recovery: float = 6.0

@export_group("On-Hit Effect")
## A StatusEffect applied to a CHARACTER this weapon hits (poison / burn / slow / ...) — the chemistry substrate
## (CT-3). Null = no on-hit effect (the inert default). v1 hitscan; rolled ONCE per shot, so a shotgun's pellets
## refresh the effect's duration rather than stacking it.
@export var on_hit_effect: StatusEffect = null
## Chance [0..1] the on-hit effect lands on a connecting shot. 1.0 = always (when an effect is set); 0 = never.
@export_range(0.0, 1.0) var on_hit_chance: float = 1.0

@export_group("Ammo & Reload")
## Rounds in a full clip before a reload is needed. The HUD/NPC compare current ammo against this.
@export var max_ammo: int = 10
## When true the clip never depletes (melee, fists): consume_ammo always succeeds and the wielder makes no
## "real gun" noise / reckless-fire remark. Replaces the old INT_MIN-max_ammo two's-complement sentinel.
@export var is_infinite_ammo: bool = false
## Ammo caliber this weapon draws from the wielder's reserve on reload (e.g. &"9mm"). Weapons that share
## a caliber share reserve ammo (pistol + SMG = 9mm). EMPTY = no reserve: the clip refills for free on
## reload (melee / rock / spray paint). The player can only reload a calibered weapon if the backpack
## holds matching ammo.
@export var caliber: StringName = &""
## Automatically start a reload the instant a shot empties the clip? false = the wielder must trigger it.
@export var auto_reload: bool = false # automatically start a reload the instant a shot empties the clip?
## How long a reload takes (seconds), from start to clip-full. Higher = more exposed while reloading.
@export var reload_time: float = 1.5

@export_group("Projectile")
## The physical projectile body spawned per shot (a Bullet scene). Unset = pure hitscan, no travelling round.
@export var projectile_scene: PackedScene
## Launch speed (m/s) of the spawned projectile. Higher = flatter, faster shot; lower = lobbed and dodgeable.
@export var projectile_speed: float = 80.0
## Seconds the projectile lives before it despawns. Caps range for slow rounds; 0 or less skips the travel hit-flash.
@export var projectile_life_time: float = 10.0
## Gravity pull on the projectile, as a fraction of normal gravity. 0 = flat laser; 1 = full drop (grenade arc).
@export var bullet_gravity_scale: float = 0.1
## Upward pitch (degrees) added to the launch direction, for a lobbed arc. 0 = fire straight along aim.
@export var launch_angle: float = 0.0
## Spawn a brief tracer mesh (bullet material) from the muzzle to the shot point? Visual only.
@export var has_tracer: bool = false # spawn a brief tracer mesh (bullet material) from the muzzle to the shot point?

@export_group("Explosion")
## Blast push at ground zero when this weapon's projectile detonates. Decays to 0 at explosion_radius. 0 = no blast.
@export var max_explosion_force: float = 20.0
## Radius (metres) of the projectile's explosion — its damage/shove reach and the size of the blast sphere.
@export var explosion_radius: float = 4.0
## Blast DAMAGE this weapon's projectile deals to a body inside explosion_radius (flat, no falloff). -1 = use the
## global GameSettings.physics_damage.explosion_damage. Author a value to make a hard-hitting rocket vs a shove-only
## grenade — force/radius are already per-weapon; damage was the last blast field stuck on the global knob (M9).
@export var explosion_damage: float = -1.0

@export_group("Knockback")
## Recoil shove applied to the SHOOTER on fire (rocket-jump style self-launch). 0 = no self-push.
@export var self_knockback: float = 0.0
## Horizontal shove (split across pellets) applied to a hit enemy along the shot direction. Higher = bigger stagger.
@export var enemy_knockback: float = 5.0
## Upward pop (split across pellets) added to a hit enemy, to launch them off the ground. 0 = purely horizontal knock.
@export var enemy_lift: float = 0.0

@export_group("View Model")
## This weapon's first-person view-model scene (e.g. ak_472.tscn). The gun rig instantiates it on equip
## so each weapon shows its own mesh + material. Unset = the rig's built-in placeholder shows.
@export var view_model: PackedScene
## TRUE when this weapon's first-person visual is NOT a mounted view model at all — the player's OWN body
## draws it. **fists.tres is the case**: unarmed shows the Player's first-person arms rig (the same hands you
## see when carrying a prop, `FirstPersonBody._build_first_person_arms`), which lives under the camera rather than
## under the gun rig, so it keeps the character's arm colour and does not tip 45° into the gun's holster park.
##
## Two effects. It suppresses the "this weapon has no view_model" authoring warning in WeaponModelSwapper —
## having none is the POINT here, not an oversight. And it makes `held_view_model()` return null, so an NPC
## hand, a dropped pickup and an inventory tile show nothing rather than guessing at a stand-in.
##
## Leave FALSE (the default) for every real weapon: a gun or a knife is a physical object that reads correctly
## in an NPC's hand, on the ground and in the grid, which is exactly what `held_view_model()` then returns.
@export var view_model_is_first_person_only: bool = false
## TRUE when this weapon's swing is a PUNCH rather than a shot. Two effects, both in GunMesh.fire(): the whole
## view model kicks FORWARD (GameSettings.effects `punch_kick_*`) instead of recoiling back into you, and the
## mounted view-model root is asked to play its own `strike()` if it exposes one — which the unarmed hands
## rig does (BodyModelSwap) and a gun mesh does not.
##
## Leave FALSE for every gun. The knife could be flagged, but its view model is a plain Node3D with no
## `strike()`, so today it would only get the forward kick — decide that as a feel change, not a default.
@export var view_model_punch: bool = false


## The view model as an OBJECT SOMEONE HOLDS — for an NPC's hand, a dropped world pickup, or an inventory
## mesh tile. Null when the scene is a first-person-only rig (see `view_model_is_first_person_only`), which
## those consumers already treat as "show nothing at all".
##
## The player's own gun rig deliberately does NOT use this: it wants the first-person rig, and it is the one
## consumer for which the arms ARE the correct visual.
func held_view_model() -> PackedScene:
	return null if view_model_is_first_person_only else view_model

@export_group("NPC Hand-Hold")
## Does this weapon's view_model need a SEPARATE pose when an NPC holds it, distinct from its first-person pose?
## Set true ONLY when the view_model's ROOT bakes a first-person-only transform (position/scale/tilt tuned for the
## player's gun camera — e.g. the knife: scale 1.585, a Z-tilt, and a forward offset). An NPC hangs the SAME scene
## off its hand anchor and, by default, only corrects yaw — so it inherits that baked FP scale + offset and the
## weapon floats off-hand, oversized and mis-angled. With this true the NPC mount DISCARDS the view_model's baked
## root transform and places it fresh from the three fields below, so one scene reads right both in first person
## (its baked root) and in an NPC's hand (these). Leave FALSE (default) for a weapon whose view_model has a CLEAN
## root — identity (the AK) or a centered uniform scale with no offset/tilt (the pistol's 0.001) — it already
## mounts correctly via the per-NPC weapon_mesh_rotation (rotation only) and must not change.
@export var npc_hold_override: bool = false
## Local position of the view_model relative to the NPC hand anchor (npc.gd _muzzle) when npc_hold_override is on.
## Zero = sit exactly where a gun would (at the hand). Only consulted when the override is on.
@export var npc_hold_position: Vector3 = Vector3.ZERO
## Local rotation (Euler degrees) of the view_model at the hand when npc_hold_override is on. REPLACES the per-NPC
## weapon_mesh_rotation for this weapon — a model whose business-end points the "wrong" way needs its own yaw (the
## knife's blade points -X, the reverse of a gun's +X barrel, so it wants +90° Y to face the NPC's +Z forward,
## not the guns' -90°). Only consulted when the override is on.
@export var npc_hold_rotation: Vector3 = Vector3.ZERO
## Uniform scale of the view_model at the hand when npc_hold_override is on — the baked FP root scale is discarded,
## so this multiplies the model's OWN inherent (child-chain) size. 1.0 = the model's native size. Only consulted
## when the override is on.
@export var npc_hold_scale: float = 1.0
## Readability boost for a GUN's held-out NPC display: multiplies the baked FP root scale the rotation-only
## mount leaves on the mesh. View-models are first-person-tuned, and at NPC viewing distance that FP world
## size reads squint-small — the player couldn't tell WHAT an enemy was holding. NOT applied to
## npc_hold_override weapons: their authored npc_hold_scale IS the final held size (tune that instead).
## Consulted ONLY by npc.gd._build_weapon_mesh (the hand display): the player's own view-model, ground drops
## (world_item), inventory icons, and the inspect preview never read this field. Per-weapon so a long rifle
## can boost less than a pocket pistol (a 1.75x sniper barrel reaches ~1.6m — consider ~1.2 there); 1.0 = off.
@export var npc_held_display_scale: float = 1.75

@export_group("Muzzle & Casing")
## Show the muzzle flash mesh/light + sparks on fire? Cosmetic; off for muzzle-less weapons (rock, fists).
@export var has_muzzle_flash: bool = true # show the muzzle flash mesh/light + sparks on fire?
## Show the laser sight beam for this weapon? Off for melee / thrown / unsighted weapons.
@export var has_laser_sight: bool = true # show the laser sight for this weapon?
## Eject a physical shell casing on fire? Off for weapons that don't shell out (melee, energy, thrown).
@export var spawns_casing: bool = true   # eject a shell casing on fire?
## Scales the ejected shell casing — its mesh (and the RigidBody casing's collision). 1.0 = unchanged;
## > 1 = a bigger shell (e.g. the sniper's fat round), < 1 = a daintier one. Only matters when
## spawns_casing is true.
@export var casing_size_scale: float = 1.0

@export_group("Audio")
## Gunshot / fire sound played per shot.
@export var audio: AudioStream          # gunshot / fire sound
## Per-shot bullet snap/whiz played at the muzzle (the supersonic crack).
@export var whiz_sound: AudioStream     # per-shot bullet snap/whiz played at the muzzle
## Sound when a shot hits world/objects. null = use the scene's default impact stream.
@export var impact_sound: AudioStream        # hit on world/objects (null = scene default)
## Sound when a shot hits a character (the flesh-hit). null = use the scene's default enemy-impact stream.
@export var impact_enemy_sound: AudioStream  # hit on a character (null = scene default)
## Reload sfx. null = use the scene's default ReloadSFX stream.
@export var reload_sound: AudioStream        # reload sfx (null = scene default ReloadSFX stream)

@export_group("Feedback")
## Camera kick fired off on every shot (trauma units fed to ScreenShake). Higher = punchier recoil; 0 = no shake.
@export var screen_shake_amount: float = 0.3
## Bigger one-shot shake for a scoped-attack launch / air dash specifically (screen_shake_amount stays
## the per-shot fire shake).
@export var launch_screen_shake: float = 0.6
## Opacity of the player's full-screen white hit-flash on this weapon's instant-hit (hitscan) shots.
## 1 = full-strength white; the knife authors 0.5 so its fast repeat swings read as a soft pop instead of
## a strobe (the same concern that exempts view_model_punch weapons outright, dimmed rather than dropped).
## Cosmetic only — the 85ms hitscan combat beat in attack.gd runs regardless, and the Accessibility
## "Screen Flashes" toggle can still hide the flash entirely.
@export_range(0.0, 1.0) var hit_flash_opacity: float = 1.0
## Hitstop ("screen freeze") when this weapon hits an enemy — a brief slow-mo for punch. hitstop_duration
## = real-time hold; hitstop_recovery = how long it eases back to full speed. Set both low (or 0) on a
## fast weapon like the SMG so the per-shot freezes don't pile up.
@export var hitstop_duration: float = 0.005
## Seconds the freeze takes to ease back up to full speed after the hold. Higher = a longer, draggier slow-mo tail; 0 = snap back.
@export var hitstop_recovery: float = 0.2

@export_group("ADS / Scope")
## When true this weapon can't aim down sights AT ALL -- holding Zoom does nothing (no scope, no zoom). For a
## weapon with no sight to raise: the fists / bare hands. Leave false for guns and for melee weapons that ADS to
## trigger a scoped-attack launch (launch_on_scoped_attack below). Mirrors is_spray_paint's no-ADS handling.
@export var no_ads: bool = false
## scoped_fov_override: FOV this weapon zooms to while scoped (ADS). 0.0 = use the global ADS zoom (which is
## SOLVED from the player's rest FOV via GameSettings.camera.scope_magnification); > 0.0 = this weapon's own
## scope FOV. Deliberately an ABSOLUTE angle, unlike the global: a scope is a fixed optic, so a sniper's
## magnification belongs to the weapon and must not drift with the player's Field of View setting. That also
## means it does NOT get the FOV-invariance the global path has — authoring a very small number here pins a
## very deep zoom at every FOV. ScopeIn clamps it to Camera3D's legal 1..179 range, so anything below 1 degree
## is the SAME ~75x scope; author the angle you actually want to look through.
@export var scoped_fov_override: float = 0.0
## When true the camera's depth-of-field blur is turned OFF while scoped (a clear, crisp scope picture);
## when false, scoping merely LESSENS the DoF.
@export var disable_dof_while_scoped: bool = false
## Multiplier on the player's aim wander while firing this weapon FROM THE HIP (not scoped). 1.0 = the
## normal wander; a sniper sets this high so it's wildly inaccurate un-scoped and steady only down the scope.
## (Scoped, the wander is governed by PlayerAimSettings.sway_ads_mult instead, so this doesn't apply.)
@export var hip_sway_mult: float = 1.0

@export_group("Scoped-Attack Launch")
## When true, ATTACKING WHILE SCOPED (ADS) launches the player in the look direction instead of doing a
## normal attack (e.g. melee dash). Hip-fire still does the normal attack; you still zoom with the
## secondary as usual. Uses the weapon's attack_speed as the launch cooldown.
@export var launch_on_scoped_attack: bool = false
## Forward shove (m/s) along the look direction when a scoped attack launches the player. Higher = a longer lunge/dash.
@export var launch_force: float = 15.0
## Extra straight-up boost (m/s) added to the launch, so the dash also hops. 0 = a flat horizontal lunge.
@export var launch_upward: float = 4.0
## If true, only one launch/dash is allowed per airtime (must touch ground to refresh). false = dash repeatedly mid-air.
@export var single_air_dash: bool = false # if true, only one launch/dash allowed per airtime

@export_group("Spray Paint")
## Spray-paint "graffiti" mode: hold fire to spray persistent coloured paint decals onto whatever surface
## you aim at, instead of dealing damage. Pair with auto_fire = true + a fast attack_speed.
@export var is_spray_paint: bool = false
## Tag colours the spray cycles through at random (one per splat). Edit freely.
@export var paint_colors: Array[Color] = [
	Color(0.92, 0.12, 0.15), Color(0.13, 0.45, 0.95), Color(0.18, 0.85, 0.22),
	Color(0.97, 0.85, 0.12), Color(0.93, 0.22, 0.82), Color(0.12, 0.9, 0.9),
]

## Self-populate the `caliber` dropdown from the ammo calibers on disk (a SUGGESTION hint, so blank "no
## reserve" stays valid and a brand-new caliber is still typable while you're also authoring its ammo). Stops
## a typo'd caliber from silently leaving the weapon with no matching ammo — it could never reload.
func _validate_property(property: Dictionary) -> void:
	if property.name == "caliber":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Calibers.ids_csv()
