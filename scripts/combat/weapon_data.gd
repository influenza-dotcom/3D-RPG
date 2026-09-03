@tool
class_name WeaponData
extends Resource

## A weapon definition — every knob the firing pipeline reads. Make a new weapon by creating a WeaponData
## .tres and filling these in; the @export_groups below are how they're laid out in the Inspector.
## @tool only so the `caliber` field self-populates its dropdown (see _validate_property) — no editor lifecycle.

## Drives the `caliber` dropdown from the ammo calibers on disk (const-preloaded, NO class_name — see calibers.gd).
const Calibers = preload("res://scripts/items/calibers.gd")

## THE FO4 slot vocabulary — and the SAVE vocabulary: each entry has exactly one @export_storage
## StringName field below holding the fitted part's Item.id. One mod per slot, by construction.
## ⭐Adding a seventh slot is THREE coordinated edits, all in this file: an enum entry, a new
## @export_storage field, and a MOD_SLOT_PROPS row (in the same ordinal position). Nothing else in
## the game hardcodes the mapping — mod_id()/set_mod_id() index the array.
##
## It lives on WeaponData ON PURPOSE: WeaponData is what STORES the six ids, so the save vocabulary and
## the save fields sit together, and WeaponData gains no new class dependency (WeaponMod -> WeaponData,
## one direction only — the part names the slot, the slot never names the part).
enum ModSlot { RECEIVER, BARREL, MAGAZINE, SIGHT, MUZZLE, STOCK }

## Enum ordinal -> the @export_storage property that stores that slot's fitted part id. MUST stay in
## enum order and the same length; tests/test_weapon_mods.gd pins both.
const MOD_SLOT_PROPS: Array[StringName] = [
	&"mod_receiver", &"mod_barrel", &"mod_magazine", &"mod_sight", &"mod_muzzle", &"mod_stock",
]

@export_group("General")
## Max hitscan reach (metres) — the raycast stops here, so beyond it a hip/scoped shot hits nothing.
## Also the NPC standoff distance when this weapon sets it (>0). 0 = unranged: AI falls back to npc_ai.unranged_aim_fallback.
@export var effective_range: float = 20.0
## Movement-speed multiplier applied to the wielder WHILE THIS WEAPON IS DRAWN (not holstered).
## 1.0 = no penalty; a heavier weapon sets this lower (e.g. 0.8) to slow the holder down, FNV-style.
@export var move_speed_multiplier: float = 1.0
## Multiplies how far this weapon's GUNSHOT carries (Player.noise_gunfire_radius) — the one weapon-side
## stealth lever. 1.0 = a normal gun; a suppressor MULTs this down. ⭐is_infinite_ammo is NOT this knob:
## it silences the noise emission AND the reckless-fire remark, but it also stops the clip depleting, so it
## can never be repurposed. Threaded at exactly one site: Player.on_weapon_fired -> NoiseEmitter.gunfire(mult).
@export var noise_radius_mult: float = 1.0

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
# and left-click / a Z-hold throws it; throw_on_scoped_attack (the last field here) folds that
# whole sequence into one ADS + trigger gesture. A weapon drop carries NO ThrowableData, so these are its authoring surface.
# MOST of them (thrown_impact_damage_mult / thrown_faces_travel / thrown_face_rotation_degrees / thrown_impulse_mult /
# thrown_sound / held_faces_aim / dropped_item_light_always_lit) are stamped onto the drop's Throwable — or, for
# the item light, onto its CanPickUp, and for thrown_trail / thrown_trail_color onto a ThrowTrail CHILD it adds —
# by WorldItem._make_throwable; the other two shape the drop itself in
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
## A thrown hit the victim SURVIVES leaves a dropped copy of this weapon EMBEDDED in the body part it struck,
## riding that part until they die or someone pulls it out (stamped onto Throwable.sticks_in_body; the effect lives
## in Throwable.stick_in_body and the "Blades left in the body" group on GameSettings.effects).
## The other half of `thrown_pins_body_part`, on the far side of the kill line: that one is what a LETHAL throw
## does, this is what a survivable one does, and one hit can never do both — the stick is gated on the victim
## still being alive one line after the damage lands, which is the same instant the pin marker is left behind.
## Same two requirements as the pin, and for the same reasons: `thrown_uses_weapon_damage` (the located contact
## point is what names the part) and a BodyModelSwap on the victim (its live parts are what the blade rides). With
## neither, the throw simply rebounds and drops. OFF by default — a thrown PISTOL should clatter to the floor, not
## hang out of somebody's ribs.
@export var thrown_sticks_in_body: bool = false
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
## Mesh-front correction (Euler degrees) for BOTH poses a drop of this weapon can take — the thrown facing AND the
## carry pose — stamped onto Throwable.face_carrier_rotation_degrees, the one field Throwable shares between them.
## Either aim basis points the drop's LOCAL -Z at the target (travel for the throw, your look for the carry), so a
## model whose business end isn't -Z *in the drop's local space* needs a correction here.
## DEFAULT Y=+90 — the project's gun convention: every gun view_model in the repo points its BARREL down mesh +X
## (its `Muzzle` marker sits at +X, and the NPC hand mount's `weapon_mesh_rotation` defaults to the mirror -90
## because an NPC's forward is +Z), and +90 is what swings that +X onto the aim's -Z. So a new gun authored from a
## clean import is held and thrown pointing the right way with nothing to tick.
## The knife overrides it with Y=180: its blade points mesh -X, and npc_hold_rotation's (0,90,0) maps that onto the
## drop's +Z — the TAIL of the aim — so uncorrected it would fly (and be held) HANDLE-first.
@export var thrown_face_rotation_degrees: Vector3 = Vector3(0.0, 90.0, 0.0)
## Multiplier on the LAUNCH SPEED of a real throw of a dropped copy (stamped onto Throwable.throw_impulse_mult, which
## PickupRay._release applies to GameSettings.physics_damage.pickup_throw_impulse). 1.0 (default) = a gun tumbles away
## at the same speed as a tossed crate; raise it for a weapon meant to be HURLED — the knife should leave the hand
## fast enough to read as a thrown blade, not a lobbed object. Only a real throw is scaled: the H tap-drop and the
## death/quickload release stay gentle. A value > 1.0 ALSO turns on continuous collision detection for the drop
## (WorldItem._make_throwable), because a fast, slender body can otherwise tunnel through thin geometry in one
## physics tick.
@export var thrown_impulse_mult: float = 1.0
## Drag a bright STREAK behind a dropped copy while it FLIES — the thrown-weapon tracer. Stamped by
## WorldItem._make_throwable as a `ThrowTrail` child on the drop (see scripts/components/throw_trail.gd); the
## component samples the prop's path each physics frame and draws a tapering, fading ribbon through it. Only a real
## THROW streaks — the H tap-drop and the death/quickload release never do, because the arm rides the same
## `is_throw` decision as the thrown facing and the throw sound. ON BY DEFAULT, for EVERY weapon: the streak reads
## as "the thing you threw went THERE", which is as useful for a hurled pistol as for a blade — a throw is a
## deliberate verb here, and the arc plus the landing spot are what the player needs back from it. (It shipped
## knife-only on the theory that a tracer on a gun would read as a bug; in play it reads as a throw.) Tumbling is
## no obstacle: the ThrowTrail sits at the drop's ORIGIN, so a gun spinning end over end still lays a smooth line
## — only a weapon with `thrown_faces_travel` gets the extra "leads with its point" read. Turn it OFF for a
## weapon whose flight should NOT be readable — a decoy meant to be lost track of, or a stealth throw that
## shouldn't paint a line back to where you threw it from. Shape (width / tail length / the speed it stops at) is
## global tuning on
## GameSettings.effects → "Thrown weapon trail" so every streak in the game matches — and note that
## `throw_trail_min_speed` now has to stay UNDER the ~12 m/s of an ordinary throw or only the HURLED knife (2.5x)
## would still streak, which is pinned by tests/test_managers_tuning.gd.
@export var thrown_trail: bool = true
## Colour of that streak, alpha included — stamped onto the drop's `ThrowTrail.color`. WHITE (the default) is the
## shipped tracer, on every weapon: unshaded, so it reads the same in a lit street and an unlit basement. Tint it
## per weapon for a signature throw (a green-glowing blade); inert unless `thrown_trail` is on.
@export var thrown_trail_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Sound played when a dropped copy is really THROWN (stamped onto Throwable.throw_sound), instead of its release
## sound. Null (default) = a throw is as quiet as a drop, which is right for a gun you toss aside; author it for a
## weapon with a signature throw (the knife's whip). Distinct from `audio`, the SWING/fire sound of the wielded weapon.
@export var thrown_sound: AudioStream
## While the drop is CARRIED in your hands (the H verb), pose it so its business end points DOWN YOUR LOOK DIRECTION,
## PITCH INCLUDED — a weapon held ready to throw, lying along the throw it is about to make. Stamped onto
## Throwable.face_carrier_while_held + face_carrier_reversed (a weapon has only one sensible carry pose, so the one
## flag sets both: it uses the dog's face-carrier machinery, REVERSED — the dog turns to present its face to you, a
## weapon points away from you).
## ON BY DEFAULT, for EVERY weapon. It shipped knife-only, on the theory that only a blade reads as "held ready";
## in play the opposite is true — a gun frozen at whatever angle you happened to grab it at reads as a bug, and a
## held weapon that ignores your look is exactly as wrong when the look is UP or DOWN as when it is sideways. Turn
## it OFF only for a weapon that should keep the rotation it was grabbed at. It reuses thrown_face_rotation_degrees
## as the mesh-front correction (Throwable shares one field between the carry and thrown poses) — do NOT try to flip
## the held facing by adding 180 there, since that same value is what makes a nosing weapon lead in FLIGHT and it
## would spin in the air too.
@export var held_faces_aim: bool = true
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
## ADS + ATTACK THROWS this weapon instead of swinging it: aim down sights with the knife, pull the trigger, and you
## hurl the blade down your look ray in one gesture — no H press, no carry step. Hip-fire is untouched (a SCOPED
## attack is the only trigger) and ADS on its own still just zooms, so nothing leaves your hand until you fire.
## It is the SAME launch a left-click gives a weapon you are already carrying: Player.throw_equipped_weapon pulls the
## wielded item out of the bag as a physics drop and hands it straight to PickupRay.throw_held. So every knob in this
## group applies exactly as it does to a hand-thrown copy — the nosing, the trail, the throw sound,
## thrown_uses_weapon_damage, the pin kill — and there is nothing extra to author for the gesture.
## The weapon really LEAVES you: the item is out of the backpack and lying in the world until you walk over and pick
## it back up, and you drop to bare fists (which are no_ads, so the sights come down with the throw).
## Priced and paced like a swing — stamina_melee_attack_cost, and this weapon's own attack_speed as the cooldown,
## both read BEFORE the throw because it swaps the fists in synchronously. A throw that cannot be built (nothing
## equipped, hands already full, off-tree) falls through to the ordinary scoped attack rather than eating the click.
## OFF by default: only a weapon meant to be thrown away mid-fight should give up its trigger while you are aiming.
## ⭐ Pointless alongside no_ads — no ADS means no scoped attack, so the gesture can never fire.
@export var throw_on_scoped_attack: bool = false

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
## BURST FIRE — AI WIELDERS ONLY: how many rounds an NPC answers ONE trigger pull with. 1 (the default) is the
## single aimed shot every weapon fired before this existed; >1 fires a short string of rounds spaced by
## npc_burst_interval below, and only THEN pays the full telegraphed cadence (NPC._shot_interval, floored by
## GameSettings.npc_ai.min_shot_interval) before the next burst. The PLAYER's trigger is untouched — a human holds
## the button and `auto_fire` decides what that does.
## ⭐ WHY IT EXISTS: min_shot_interval paces every NPC's ranged fire to a 0.9 s breathing rhythm so the telegraph
## package (lock-on sting, laser/aim-radial ramp, incoming beep) has an off-beat to sit in — right for the pistol,
## but it turned the SMG, a gun whose entire identity is its 0.125 s cyclic rate, into a slow single-shot pistol
## with a big magazine. The burst gives the gun its VOICE back INSIDE that rhythm: brrrp, breathe, brrrp — with one
## charge sting and one incoming beep per BURST, not per round, so the warning still means something.
## The burst ABORTS mid-string the moment the shot stops being takeable (LOS broken, target out of range, clip run
## dry), so an NPC never keeps spraying at a wall the target just ducked behind.
## ⭐ It MULTIPLIES this weapon's AI damage output — three rounds per cadence is ~3x the DPS of one. Rebalance a
## bursting weapon with this count (and its `damage`), not by fighting the shared cadence floor.
@export var npc_burst_count: int = 1
## Seconds between the rounds INSIDE an NPC's burst. 0 (the default) = this weapon's own attack_speed, i.e. the
## gun's real cyclic rate — an SMG bursts at 8 rounds/sec because that is what the gun does. Set it only to slow a
## burst down for readability: it can never make one fire FASTER than attack_speed, because Attack refuses a shot
## while its own cadence timer is still running (NpcCombat waits for it rather than dropping the owed round).
## Inert while npc_burst_count is 1.
@export var npc_burst_interval: float = 0.0
## Does a round from this weapon EXPLODE on impact? Purely a stamina-pricing / authoring FACT — it does not make
## anything blow up (whether a round blasts is decided inside its projectile_scene: rock_projectile.tscn wires its
## Explosion node to the full blast path, Projectile.tscn to a cosmetic spark that hardcodes force 0 and the global
## spark radius). Tick it on a weapon whose projectile really does blast, so stamina_effort() below charges for the
## payload.
## ⭐ This exists because NOTHING else on WeaponData can tell an explosive weapon from a hitscan one:
## explosion_radius defaults to 4.0 on EVERY weapon, max_explosion_force defaults to 20.0 (so the PISTOL nominally
## out-blasts the grenade launcher's authored 10.0), and explosion_damage is the -1 "use the global" sentinel on all
## eight shipped weapons. Those three fields are simply INERT on a non-explosive gun — the spark path never reads
## them — which is exactly why they cannot be used as the signal. Default false keeps every ordinary gun correct
## with zero authoring.
@export var projectile_explodes: bool = false
## TRIM on this weapon's DERIVED per-shot stamina price — not the price itself. The cost falls out of
## stamina_effort() below (damage, pellets, blast), so a designer who authors a weapon's combat stats gets a sane
## stamina price for free and it cannot drift out of sync with a rebalance. This knob only nudges the result:
## 1.0 = ship the derived price, 0.75 = a 25% discount, 0 = this gun's fire is free.
##
## Use it ONLY for something the per-shot formula structurally cannot see, and say why in a comment on the .tres.
## Exactly one weapon needs it today: smg.tres authors 0.75. Effort is per-SHOT, but what a player feels on a
## held trigger is per-SECOND, and at 8 shots/sec the SMG multiplies its cost harder than anything else on the
## roster — at 1.0 it would drain 12.7/sec (74% of the 17.1/sec clamp) while firing the WEAKEST round in the
## game, which reads as a punishment for choosing the light weapon. The trim buys back that cadence asymmetry.
## Reach for a damage/cadence change before you reach for this; a trim that drifts far from 1.0 means the formula
## and your intent have diverged.
@export var stamina_cost_mult: float = 1.0

## --- Derived per-shot stamina price ---------------------------------------------------------------------

## Exponent on pellet_count in stamina_effort(). A shell is ONE trigger pull absorbing ONE recoil impulse, and its
## pellets diverge over pellet_spread so the nominal Nx only all land at contact range — charging N full shots
## double-counts, charging one ignores the payload, so effort grows as sqrt(pellets).
const PELLET_EFFICIENCY := 0.5
## Effort credited to a blast at the reference radius below. Tuned so the shipped grenade launcher (damage 4.0,
## radius 4.0) scores 4.0 direct + 4.0 blast = 8.0 — twice the shotgun, eight times the pistol.
const BLAST_PAYLOAD := 4.0
## The blast radius BLAST_PAYLOAD is quoted at; a wider blast scales linearly from here. Deliberately LINEAR rather
## than area-of-effect: an area term flattens against a cap almost immediately above the shipped 4.0m, so widening
## a blast would stop moving the price with no warning.
const BLAST_REF_RADIUS := 4.0

## How much offensive output ONE trigger pull puts out — the "how big is this bang" proxy the stamina price scales
## from, so a grenade launcher costs more per shot than a pistol without anyone hand-pricing either. Normalised so a
## plain 1.0-damage single-projectile round scores exactly 1.0, which makes GameSettings.player_movement's
## stamina_shot_cost readable as "what one baseline shot costs".
##
## Shipped roster: smg 0.88, pistol 1.00, sniper 1.25, shotgun 4.00, grenade launcher 8.00.
##
## ⭐ PURE over this resource's own @exports, by contract. weapon_data.gd is loaded by the @tool CYBER SUNDAY
## inspector, which runs in the EDITOR where the GameSettings autoload does not exist — so this must never read a
## global. That is also why the blast term is a flat credit scaled by radius rather than a read of explosion_damage
## (whose -1 sentinel would need GameSettings.physics_damage to resolve). The economy half of the price — the
## global cost per unit of effort and the sustained-drain clamp — lives in Attack._shot_stamina_cost().
##
## Distinct from power_score() below, which is a RATE for AI equip-ranking: dividing by cadence would price the
## SMG's bullet highest and the one-shot-kill sniper lowest, which is backwards for a PER-SHOT cost.
func stamina_effort() -> float:
	var direct := damage * pow(maxf(float(pellet_count), 1.0), PELLET_EFFICIENCY)
	var blast := 0.0
	if projectile_explodes:
		blast = BLAST_PAYLOAD * (maxf(explosion_radius, 0.0) / BLAST_REF_RADIUS)
	return maxf(direct + blast, 0.0)

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
## Multiplier on projectile_speed ONLY when an AI wielder fires this weapon (ProjectileSpawner checks the
## wielder's group). Enemy rounds fly slower than the player's identical gun so incoming fire is visibly
## dodgeable — the classic AI-fairness trick — without touching the player's feel. 1.0 (default) = NPC rounds
## fly at the authored speed. Matters because AI ranged fire is ALWAYS live projectiles (never hitscan, the
## 2026-08-25 design rule — see ShotResolver.ai_fires_live_projectile): this is the dodge-window dial per
## weapon. Leave 1.0 on a lobbed/ballistic weapon (the grenade launcher) whose arc is tuned to its speed, and
## on the sniper (its terror IS the fast bolt; the charge/beep telegraph is the counterplay). NOTE a value
## well below 1.0 also multiplies gravity DROP at a given distance (drop ~ 1/speed²) while launch_angle still
## compensates for the FULL authored speed — keep bullet_gravity_scale low or re-aim launch_angle if rounds
## start landing short.
@export var npc_projectile_speed_mult: float = 1.0
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
## Extra local offset (metres) applied to the held model AT THE NPC'S HAND ONLY, in the hand anchor's own frame
## (+Z is the way the NPC — and so the barrel — points; +Y is up). The knob for pulling an ENLARGED view-model
## back into the fist: these scenes bake their first-person pose into the model's child chain, so
## `npc_held_display_scale` grows the model AND pushes it forward by the same factor. A weapon boosted much past
## its authored size therefore floats ahead of the hand until it is trimmed back here. ZERO = the model sits
## exactly where its own pose puts it (the pre-trim behaviour for every weapon that doesn't need one).
##
## Applied in BOTH mount branches, so an npc_hold_override weapon can be trimmed too. Read ONLY by
## npc.gd._build_weapon_mesh — the player's FP rig, ground drops (world_item) and the character preview never
## see it, so trimming an NPC's hold can never disturb those. (For a DROP's re-centring use
## `dropped_model_offset`, which is the same idea on the other side of the fence.)
@export var npc_hold_trim: Vector3 = Vector3.ZERO
## Readability boost for the held-out NPC display: multiplies the mesh's surviving scale (a gun's baked FP root
## scale on the rotation-only mount; `npc_hold_scale` on an override weapon). View-models are first-person-tuned,
## and at NPC viewing distance that FP world size reads squint-small against this project's deliberately chunky
## character rig — whose HEAD alone is 0.68 m and whose arm is a 0.75 m plank — so a life-scale gun disappears
## into the fist and the player cannot tell WHAT an enemy is holding.
## Consulted ONLY by npc.gd._build_weapon_mesh (the hand display): the player's own view-model, ground drops
## (world_item), inventory icons, and the inspect preview never read this field, so it is safe to retune per
## weapon. It scales the model's baked forward OFFSET as well as its size (see `npc_hold_trim`), and it moves
## the child "Muzzle" marker outward with the barrel tip — which is intended (fire leaves the gun's real
## muzzle) but is also why the long guns are boosted less than the short ones: that marker is the shot,
## tracer, laser and clear-shot-ray ORIGIN, and pushing it metres in front of the NPC would start shots
## past cover. 1.0 = off.
@export var npc_held_display_scale: float = 2.6

@export_group("Muzzle & Casing")
## Show the muzzle flash mesh/light + sparks on fire? Cosmetic; off for muzzle-less weapons (rock, fists).
@export var has_muzzle_flash: bool = true # show the muzzle flash mesh/light + sparks on fire?
## Show the laser sight beam for this weapon? Off for melee / thrown / unsighted weapons.
## ⭐BOTH SIDES READ THIS ONE FLAG. It gates the NPC aiming laser (npc.gd `_current_weapon_has_laser_sight`, the
## red beam an armed enemy sweeps at you) AND the PLAYER's own laser sight (scenes/player/laser_sight_rig.gd),
## which is back after a spell in retirement. Turning it off on a weapon hides the beam for whoever holds it —
## which is the point: a laser has to hang off a gun, so fists, melee and the spray can author it false.
## ⭐The player's sight is ALSO gated on the `laser_sight` implant, so this flag alone never puts a dot on screen.
@export var has_laser_sight: bool = true # show the laser sight for this weapon (player AND NPC)?
## Eject a physical shell casing on fire? Off for weapons that don't shell out (melee, energy, thrown).
@export var spawns_casing: bool = true   # eject a shell casing on fire?
## Scales the ejected shell casing — its mesh (and the RigidBody casing's collision). 1.0 = unchanged;
## > 1 = a bigger shell (e.g. the sniper's fat round), < 1 = a daintier one. Only matters when
## spawns_casing is true.
@export var casing_size_scale: float = 1.0
## Size of the barrel-smoke trail (scenes/effects/muzzle_smoke.tscn) this weapon leaves after a shot.
## 1.0 = the authored wisp; > 1 = a big-bore belch (shotgun, sniper, launcher), < 1 = a thinner thread,
## 0 = this weapon never smokes. Only matters when has_muzzle_flash is true — that flag already means "this
## thing goes bang", so melee / fists / the spray can are dry without needing a value here. The player's
## Options dial (Settings.muzzle_smoke_scale) multiplies on top, so 0 there turns every gun's smoke off at once.
@export var muzzle_smoke_scale: float = 1.0

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
## weapon with no sight to raise: the fists / bare hands. Leave false for guns, and for any melee weapon you want
## to be able to raise. Mirrors is_spray_paint's no-ADS handling.
@export var no_ads: bool = false
## scoped_fov_override: FOV this weapon zooms to while scoped (ADS). 0.0 = use the global ADS zoom (which is
## SOLVED from the player's rest FOV via GameSettings.camera.scope_magnification); > 0.0 = this weapon's own
## scope FOV. Deliberately an ABSOLUTE angle, unlike the global: a scope is a fixed optic, so a sniper's
## magnification belongs to the weapon and must not drift with the player's Field of View setting. That also
## means it does NOT get the FOV-invariance the global path has — authoring a very small number here pins a
## very deep zoom at every FOV. ScopeIn clamps it to Camera3D's legal 1..179 range, so anything below 1 degree
## is the SAME ~75x scope; author the angle you actually want to look through.
@export var scoped_fov_override: float = 0.0
## Variable-zoom scope (the sniper): the WIDEST (most zoomed-out) FOV the mouse wheel can dial while scoped,
## in degrees. Author BOTH ends (0 < scoped_zoom_fov_min < scoped_zoom_fov_max) to turn the wheel zoom on —
## while AIMING, the wheel then steps the scope between them (ScopeIn owns the notch; the Hotbar yields,
## exactly like the spray can's palette) instead of switching weapons. Leave both 0 for a fixed optic: the
## wheel keeps switching weapons straight through the scope. Like scoped_fov_override these are ABSOLUTE
## angles (a variable scope is still a real optic), so the range does not ride the player's FOV setting.
## Scope-in lands on the authored resting zoom (scoped_fov_override clamped into the range; with NO
## override, the global magnification solve — kept LIVE and FOV-slider-invariant until the wheel's first
## notch, after which the dialed angle is absolute). The dial lasts until the player rig is rebuilt (level
## reload / quickload resets it) and is never saved.
@export var scoped_zoom_fov_max: float = 0.0
## The DEEPEST (most zoomed-in) FOV the wheel can dial while scoped, degrees. Clamped like
## scoped_fov_override (Camera3D's legal 1..179), so an end under 1 degree pins at the same ~75x floor.
## See scoped_zoom_fov_max above for how the pair switches the wheel zoom on.
@export var scoped_zoom_fov_min: float = 0.0
## When true the camera's depth-of-field blur is turned OFF while scoped (a clear, crisp scope picture);
## when false, scoping merely LESSENS the DoF.
@export var disable_dof_while_scoped: bool = false
## Multiplier on the player's aim wander while firing this weapon FROM THE HIP (not scoped). 1.0 = the
## normal wander; a sniper sets this high so it's wildly inaccurate un-scoped and steady only down the scope.
## (Scoped, the wander is governed by PlayerAimSettings.sway_ads_mult instead, so this doesn't apply.)
@export var hip_sway_mult: float = 1.0

## True when this weapon authors a usable wheel-zoom range (see scoped_zoom_fov_max above). The single
## eligibility truth for BOTH sides of the wheel contract — ScopeIn's zoom stepping and the Hotbar's yield
## read it through ScopeIn.wheel_owns_scope_zoom, so wheel ownership can never split between them.
func has_variable_scope_zoom() -> bool:
	return scoped_zoom_fov_min > 0.0 and scoped_zoom_fov_max > scoped_zoom_fov_min

# The "Scoped-Attack Launch" group (launch_on_scoped_attack / launch_force / launch_upward / single_air_dash) is
# GONE: the air dash stopped being a weapon behaviour you triggered by ADS-ing a knife and swinging. It is its own
# key now (default Left Alt) and its own component — scripts/components/abilities/air_dash.gd — which carries the
# force/lift/one-per-airtime tuning as its own exports. A weapon no longer has anything to say about dashing.
# ADS + attack is not a dead gesture, though — it is throw_on_scoped_attack in the Thrown group now, and it HURLS
# the weapon down your look ray instead of launching you along it.

@export_group("Spray Paint")
## Spray-paint "graffiti" mode: hold fire to spray persistent coloured paint decals onto whatever surface
## you aim at, instead of dealing damage. Pair with auto_fire = true + a fast attack_speed.
@export var is_spray_paint: bool = false
## Tag colours the spray cycles through at random (one per splat). Edit freely.
@export var paint_colors: Array[Color] = [
	Color(0.92, 0.12, 0.15), Color(0.13, 0.45, 0.95), Color(0.18, 0.85, 0.22),
	Color(0.97, 0.85, 0.12), Color(0.93, 0.22, 0.82), Color(0.12, 0.9, 0.9),
]

@export_group("Modifications")
# ── The FITTED PARTS. Each holds the Item.id of the WeaponMod part in that slot (&"" = empty).
# ⭐@export_storage, NOT a plain var and NOT a visible @export — and BOTH halves are load-bearing:
#   • STORAGE usage is what makes Resource.duplicate() carry the value. A bare `var` (usage 4096) is
#     SILENTLY DROPPED by duplicate(), so every ItemDb.make_weapon_item / clone_unique would hand back
#     a stock gun with no error anywhere. (Probed on 4.7.1: @export_storage = 4098, bare var = 4096.)
#   • SCRIPT_VARIABLE usage is what ItemDb._is_saved_weapon_property requires, and TYPE_STRING_NAME is
#     already in _is_weapon_delta_type — so these ride the EXISTING weapon_delta seam with no new key.
#   • Hiding them from the inspector is what stops a designer typing a value into a TEMPLATE .tres and
#     silently giving every instance of that gun a permanent non-empty delta.
# Templates ship BLANK; only WeaponBench (via WeaponModKit.rebuild) ever writes them.
@export_storage var mod_receiver: StringName = &""
@export_storage var mod_barrel: StringName = &""
@export_storage var mod_magazine: StringName = &""
@export_storage var mod_sight: StringName = &""
@export_storage var mod_muzzle: StringName = &""
@export_storage var mod_stock: StringName = &""

## The fitted part id in `slot` (&"" = empty). The ONE indexed accessor — nothing else maps enum -> field.
func mod_id(slot: int) -> StringName:
	if slot < 0 or slot >= MOD_SLOT_PROPS.size():
		return &""
	return StringName(get(String(MOD_SLOT_PROPS[slot])))

## Stamp `slot`'s fitted part id (&"" clears it). Out-of-range is a deliberate silent no-op: callers index
## with a WeaponMod.slot that a broken .tres could have left outside the enum, and a bench refit must not
## crash the whole transaction over one bad part.
func set_mod_id(slot: int, id: StringName) -> void:
	if slot < 0 or slot >= MOD_SLOT_PROPS.size():
		return
	set(String(MOD_SLOT_PROPS[slot]), id)

## How many slots are filled — the weapon-row "2/6" readout.
func fitted_mod_count() -> int:
	var n := 0
	for i in MOD_SLOT_PROPS.size():
		if mod_id(i) != &"":
			n += 1
	return n

## Self-populate the `caliber` dropdown from the ammo calibers on disk (a SUGGESTION hint, so blank "no
## reserve" stays valid and a brand-new caliber is still typable while you're also authoring its ammo). Stops
## a typo'd caliber from silently leaving the weapon with no matching ammo — it could never reload.
func _validate_property(property: Dictionary) -> void:
	if property.name == "caliber":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Calibers.ids_csv()
