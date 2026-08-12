class_name Player
extends Character

var current_speed: float = 0.0
# (The wallet — money / money_changed / add_money / reward_kill — was HOISTED to Character so every NPC
# carries one too. The player's fresh-game 100 zm default is set in _ready, before the loadout override.)

## --- Unlockable mechanics: each gateable ability (grapple, laser sight, wall climb, air dash, slide) is a
## drag-drop Ability CHILD NODE -- its presence (+ `enabled`) IS the grant, discovered in _ready. To choose what
## a FRESH game starts with, drop the ability scenes you want (scenes/components/abilities/*.tscn) under the
## Player; "start with nothing" = add none. An UpgradePickup grants one at runtime by ADDING its node; a loaded
## save replaces the live set by id. starting_unlocks below is only an OPTIONAL string fallback (empty default). ---
signal mechanic_unlocked(id: StringName)
## An INSTALLED implant was switched off / back on from the Implants tab (set_mechanic_active). Relay of the
## ability subsystem's mechanic_toggled, mirroring the mechanic_unlocked relay above. The Implants tab listens
## for its live refresh; deliberately NOT mechanic_unlocked (that means "granted" — ChipInstaller autosaves on it).
signal mechanic_toggled(id: StringName, active: bool)
@export_group("Unlockable Mechanics")
## OPTIONAL fallback: mechanics to grant on a FRESH game WITHOUT placing an Ability node (each builds its node from
## the registry). Pick each from the DROPDOWN -- no more typo'd ids. PREFER dropping the ability scenes under the
## Player; this stays empty by default. A loaded save replaces this whole set. Stored as plain strings (the registry
## keys); unlock_mechanic takes String or StringName interchangeably.
@export_enum("grapple", "laser_sight", "wall_climb", "air_dash", "slide") var starting_unlocks: Array[String] = []
## The ability SUBSYSTEM: grant / revoke / persistence bookkeeping + the live ability list live in AbilityManager
## (scripts/components/abilities/ability_manager.gd), not here. Built at var-init and wired in _init so the bare-
## Player unit tests (no _ready) can drive it. The Player keeps ONLY the three typed hot-path refs below + the
## physics-step beats that call them; every id-based op (has_mechanic / unlock_mechanic / grant_ability /
## revoke_ability / unlocked_list / set_unlocks) is a thin forwarder to the manager.
var _abilities_mgr: AbilityManager = AbilityManager.new()
var _wall_climb: WallClimb = null    ## hot-path refs resolved in _register_ability (null = ability not present)
var _slide: Slide = null
var _grapple_ability: Grapple = null  ## owns the GrappleHook; pull forwarded at the physics beat

signal stamina_changed(current: float, maximum: float)
var stamina: float = GameSettings.player_movement.max_stamina
var _stamina_regen_delay_left: float = 0.0
var _sprint_lockout_left: float = 0.0
const STAMINA_EPS := 0.001

## The zero-sum allocator, for its STAT_MIN/STAT_MAX pair ONLY — the bounds the Ledger's credit rating
## normalizes against, so the live re-rating can never drift from the builder that produced the sheet.
## Preloaded BY PATH (it has no class_name — the implant_choice.gd idiom).
const StatBudgetRef := preload("res://scripts/ui/stat_budget.gd")
## The two payment RAIL keys (GameState.payment_method). Keys, never display strings — PlayerText selects the
## caption from these, so re-wording a rail can never change which rail a save means.
const PAY_DEBIT := "debit"
const PAY_CREDIT := "credit"

## XP progression (rank 29): xp accrues from kills/quests; crossing an XpSettings threshold grants skill (perk)
## points. `level` is XP-derived (NOT LevelUp's stat-sum total_level) and cached so a save survives an XpSettings
## retune. Skill points live on the PerkManager (the perk-owning component); Player just forwards via add_xp.
signal xp_changed(xp: float, level: int)
signal leveled_up(new_level: int, points_gained: int)
var xp: float = 0.0
var level: int = 0

@onready var white_flash: Sprite3D = $"Head/ScreenShake/Camera3D/white flash"
@onready var _nv_rect: ColorRect = get_node_or_null("UI/ColorRect")
@onready var _player_emitting_light: OmniLight3D = get_node_or_null("PlayerEmittingLight") as OmniLight3D

## Night vision (NightVision action, N): toggles the post-process `night_vision` look, faded in/out at this
## rate. This drives the keybind, shader parameter, and options-row state together.
## How fast the night-vision look fades in/out (per second) — higher = snappier toggle, lower = a slower bleed.
@export var night_vision_fade_rate: float = 9.0
var _nv_on: bool = false
var _nv_t: float = 0.0

@export_group("Health Light")
## The player-carried light keeps its scene-authored colour at full HP and blends toward this as HP falls.
@export var player_health_light_damaged_color: Color = Color(1.0, 0.05, 0.02, 1.0)
var _player_health_light_full_color: Color = Color(0.003921569, 1.0, 1.0, 1.0)

@export_group("Spawn")
## On every (re)spawn, drop the player straight down onto the floor beneath the spawn/respawn point so they
## START standing on the ground instead of falling in from a marker floating above it. Turn OFF for a deliberate
## fall-into-the-level arrival. Applied on the first physics frame after spawn (so it runs AFTER GameRoot has
## placed the player) and again on the in-place death revive.
@export var snap_to_ground_on_spawn: bool = true
## Frames left to KEEP trying the spawn ground-snap. Set on spawn/revive; each physics frame retries the snap and
## stops the instant it lands one. A budget (not a one-shot) because on the INITIAL spawn GameRoot loads the level
## DEFERRED — the floor collider isn't in the physics space yet on the first frame, so a single-shot snap misses
## and the player falls in. Retrying catches the floor the moment it exists. A frame-late snap is invisible (spawn
## fades up from black). On a death revive the level is already loaded, so it lands on frame one.
var _ground_snap_frames_left: int = 0
const GROUND_SNAP_RETRY_FRAMES := 120  ## ~2 s at 60 fps — long enough for any level load; then give up (a genuine void/pit spawn falls)
## Begin play with the weapon PUT AWAY (holstered) rather than drawn — you take it out on demand with a fire-click or
## the hold-R draw (FNV-style), matching how every armed NPC also spawns holstered (see WeaponStance, "start with the
## gun put away"). Applied at the END of _ready, AFTER the starting/loaded loadout is equipped — equipping a weapon
## DRAWS it (Attack._on_swap_weapons_equip_this → set_holstered(false)), so the holster must run last to win. Covers a
## New Game and a Continue; a full-reload death mode re-runs _ready so it re-holsters, while the in-place checkpoint
## revive keeps your pre-death stance. Turn OFF for a gun-out start (e.g. a combat test level). Designer knob.
@export var start_holstered: bool = true

var _carrying: bool = false  ## true while a physics prop is held (PickupRay)
var _holster_before_carry: bool = false  ## weapon holster state to restore when the prop is dropped
## The BACKPACK item currently pulled out into your hands via the hotbar's "hold" action (Player.hold_item), or
## null when empty-handed / carrying a world prop you grabbed off the ground. It was REMOVED from the bag on the
## pull, so the hotbar RESERVES its slot while this is set (Hotbar._sync_slots) and the save folds it back into
## the snapshot (GameState) so it's never lost. Stashing it back re-adds this SAME instance; dropping/throwing it
## clears this (the prop becomes a world object with its own CanPickUp). Runtime-only — carry state isn't saved.
var _held_inv_item: Item = null
var _held_inv_prop: Node3D = null  ## the world node spawned for _held_inv_item, freed on stash-back
## The carried Throwable inside _held_inv_prop, made NON-destructible while held so a 1-HP holdable (the Dog Crate)
## can't be shot out of your hands — it floats at arm's length blocking fire — and the bag item silently lost. Its
## prior `destructible` flag is restored when you drop/throw it, so a released prop is destructible again in the world.
var _held_inv_throwable: Throwable = null
var _held_inv_prev_destructible: bool = true
## True while the prop in your hands is the weapon H pulled OUT OF YOUR OWN HOLSTER (hold_equipped_weapon), as
## opposed to a hotbar-pulled bag prop or a world-grabbed crate. It makes the H verb a real TOGGLE on your own
## weapon: the second press RE-WIELDS the knife instead of dropping it on the floor (see
## return_held_weapon_to_hands + the re-draw at the end of stash_held_item). Cleared on every carry-end path —
## the put-back itself, and a genuine drop/throw/prop-freed release (_on_carry_changed). Runtime-only.
var _held_from_weapon_slot: bool = false
## Up for the span of a put-back that immediately REWIELDS the weapon (stash_held_item, the H toggle's second
## stage): armed before the carry release, dropped once the rewield's equip request has gone out. While armed,
## FirstPersonBody._unarmed_hands_wanted() refuses (it READS this latch off its host; the latch itself is pure
## weapon-flow state and stays here) — the release's synchronous holster restore reads "FISTS equipped, unholstered"
## (the real weapon is only re-equipped afterwards), and without this the bare fists rise into the weapon's own
## re-draw. Never armed by a genuine drop/throw or a non-weapon stash, so the carry→fists handoff stays seamless.
var _rewield_in_flight: bool = false

@export_group("Audio")
## The ONE-SHOTS (bowling / jump / land) play through AudioManager.play_sfx — a fresh self-freeing spatial player
## per hit, so rapid jumps/lands layer instead of cutting each other off. The stream lives here as an @export
## AudioStream (was a per-node AudioStreamPlayer3D; the nodes are gone). volume_db is passed through play_sfx.
## ⭐These *_volume_db knobs sit far above the CEILING that actually decides loudness: a spawned one-shot outputs
## min(volume_db + distance attenuation, max_db), and at the 40-80 dB authored here the sum is pinned to max_db
## at every playable range. So the ceiling is the loudness, and any per-hit MODULATION has to ride it — see
## land_sound_max_db, which is why the touchdown's impact softening is audible at all (Landing.on_land).
## The two LOOPS stay node-driven (play_sfx is fire-and-forget and can't model them): WalkingSFX (crouch/climb-aware
## footstep cadence) and FallingAirSFX (a volume-modulated wind loop that slide.gd also borrows).
## Bowling-strike "STRIKE!" stream played ONLY on a body-ram KILL (a non-lethal ram plays ram_thud_sound instead).
@export var bowling_sound: AudioStream
@export var bowling_sound_volume_db: float = 40.702  ## was the BowlingSFX node's volume_db
## Played once each jump (and each bunnyhop).
@export var jump_sound: AudioStream
@export var jump_sound_volume_db: float = 80.0
## Touchdown stream; its volume + pitch scale with landing impact (a hard fall is louder + lower) off these bases.
@export var land_sound: AudioStream
@export var land_sound_base_volume_db: float = 80.0  ## was captured from the LandSFX node's volume_db
## The touchdown's LOUDEST ceiling — a full-impact fall plays at exactly this, and a softer one at this MINUS
## (1 - impact) * AudioSettings.land_sfx_volume_db_reduction, which is the cut you actually hear (see the group
## note above: the 80 dB base is pinned to the ceiling at any playable range, so cutting it alone did nothing and
## a kerb thudded like a lethal fall). Defaults to AudioManager.DEFAULT_MAX_DB, the engine ceiling the one-shot
## used before — so the hardest landing is as loud as it has always been.
@export var land_sound_max_db: float = 3.0
@export var land_sound_base_pitch: float = 1.0       ## was captured from the LandSFX node's pitch_scale
## Looping footstep step played on the footstep cadence while moving on foot or climbing; quieter while crouched. Wire to a 3D player on the body.
@export var walking_sfx: AudioStreamPlayer3D
## Wind-rush loop whose volume swells with vertical OR horizontal speed (falls, launches, blitzing). A 2D (non-positional) player — it's the player's own ears, not a world sound.
@export var falling_air_sfx: AudioStreamPlayer

@export_group("Components")
## The Crouch component that drives crouching (lowers head + shrinks the collider, runs stand-up clearance). Wire to the player's Crouch child.
@export var crouch: Crouch
## The Head camera rig (Head -> ScreenShake -> Camera3D); the camera + screen-shake are read off it and it's handed back this player. Wire to the player's Head child.
@export var head: Head
## The Weapon system that owns the inventory, attack, ammo, scope and swap logic. Wire to the player's Weapon child.
@export var weapon_system: Weapon

## The CoyoteTime grace-window component (lets you still jump for a beat after leaving a ledge). Wire to the player's CoyoteTime child.
@export var coyote_time: CoyoteTime
## The JumpBuffer component (a jump pressed just before landing still fires on touchdown). Wire to the player's JumpBuffer child.
@export var jump_buffer: JumpBuffer
## The BulletTime component (slows the world while scoped / air-dashing). Wire to the player's BulletTime child.
@export var bullet_time: BulletTime
## The Bunnyhop component (chained jumps build speed). Wire to the player's Bunnyhop child.
@export var bunnyhop: Bunnyhop
## The Landing component (M13 residual): owns the touchdown burst + the footstep cadence, both POST-move.
## Wire to the player's Landing child. Null (an off-tree test Player) simply means no landing FX / no footsteps.
@export var landing: Landing
## The FirstPersonBody component: the whole cosmetic first-person self — the FP legs + torso rig, the carry
## hands / bare-fists rig, and all their draw/stow/guard/punch/bob machinery (scripts/player/first_person_body.gd,
## the Landing idiom; its authored fp_* pose overrides live on that node in Player.tscn). Wire to the player's
## FirstPersonBody child. Null (an off-tree test Player) simply means no first-person body — every forward
## below null-guards, and the weapon half of the carry dance (_on_carry_changed) works without it.
@export var fp_body: FirstPersonBody
## The MouseInput component that turns mouse motion into look/aim and feeds this player's yaw. Wire to the player's MouseInput child.
@export var mouse_input: MouseInput

## The HUD/UI layer (HP bar, ammo, crosshair, toasts, look-at readout); this player + its ammo clip are injected into it. Wire to the player's UI child.
@export var ui: UI

## The player's capsule collider, handed to Crouch so it can shrink/restore the body shape while crouching. Wire to the player's body CollisionShape3D.
@export var player_collision_shape: CollisionShape3D

## The world-space point the grapple rope fires FROM (the hook anchors here on the player). Wire to a Marker3D positioned at the gun/hand muzzle.
@export var grapple_hook_origin: Marker3D 

# Resolved/derived in _enter_tree off the extracted component interfaces, not wired in the
# scene: the camera + screen-shake come off the camera rig (head.camera / head.screen_shake),
# the muzzle off the gun rig (gun_mesh.muzzle), and gun_mesh is resolved from the tree. Their
# scene NodePaths pointed into instanced sub-scenes, so the Save-Branch extractions cleared
# them from Player.tscn entirely.

var camera_effects: CameraEffects
var screen_shake: ScreenShake
var muzzle: Marker3D

var gun_mesh: GunMesh

## The fake blob shadow (a Decal child) projects straight DOWN on the ground; while wall-climbing we
## rotate it to project onto the WALL instead, easing back when grounded. Cached + driven in code.
## How fast the blob shadow rotates onto the climbed wall / back to the ground (per second) — higher = it snaps onto the wall sooner.
@export var shadow_lerp_speed: float = 6.0
var _shadow: Decal
var _shadow_rest_local: Transform3D  ## the decal's authored local transform (projects down) — the ground pose
var _shadow_wall_blend: float = 0.0  ## 0 = grounded (down), 1 = fully projected onto the climbed wall

var _was_on_floor: bool = false
## The last spot we were actually STANDING on. Sole consumer: the unclaimed-death purse spill
## (_death_purse_anchor), where it is the anchor for the one death that has no floor under it — a long fall. The
## ledge you walked off is the place a player goes back to look, so that is where the money waits.
var _last_grounded_position: Vector3 = Vector3.ZERO
var _has_last_grounded: bool = false   ## false until we touch floor once, so a never-grounded death falls through to the next rung
var _continuous_fall_time: float = 0.0
var input_dir: Vector2 = Vector2.ZERO
var _step_assist_launch_block_timer: float = 0.0

## Hurt feedback ("getting rocked"): a hit hard-dips the global time-scale, slaps a low-pass
## "muffle" on the master bus, punches the camera, and drains the screen to a dark red
## desaturation + tunnel vignette — all eased back together over the recovery time. The feel
## numbers are designer knobs on GameSettings.player_feedback (hurt_*); only the bus index
## stays here (engineering, not tuning).
const MASTER_BUS: int = 0

# Single-responsibility components, built in code in _ready and handed a host ref right after .new()
# (mirrors the @export-wired controllers above). Each owns one slice of what was this god-file: the
# code-built HUD overlays, the ram/thump/bounce impact reactions, the noise emission enemies hear, the
# scope reactions + music duck, the "getting rocked" hurt feedback, and the conversation camera/weapon
# handling. Null off-tree (a bare .new() in a test skips _ready), so every facade below null-guards
# them and returns the monolith's old value.
var _hud: PlayerHud
var _ram_reactor: RamReactor
var _noise: NoiseEmitter
var _takedown: SilentTakedown  ## Slice 6b silent-takedown verb (HOLD Takedown behind an unaware NPC); runs its own _physics_process
var _pet: PetInteraction  ## Friendly twin of the takedown: HOLD Takedown aimed at a Pettable object to pet it; runs its own _physics_process
var _claim: ClaimInteraction  ## Ownership twin of pet: TAP Claim aimed at a Claimable object to adopt + name it (it then follows); runs its own _physics_process
var _aim_sway: AimSway  ## Deus Ex aim wander: drifts get_aim_direction around the camera centre (aim_sway.gd)
var _scope: ScopeCoordinator
var _hurt: HurtFeedback
var _death_mix: DeathMix  ## the death cinematic's MIX: ducks the world buses + plays the death sting (death_mix.gd)
var _dialogue: DialogueController

@export_group("Ram")
## Heavy thud played when you body-ram an enemy but DON'T kill it (a ram kill
## plays the bowling-strike sfx instead). Swap this for your preferred sound.
@export var ram_thud_sound: AudioStream = preload("uid://budx7vymim0j0")
## Pinball rebound: ramming a wall/object/enemy this fast (m/s, into the surface)
## bounces you back off it. Kept high so only real rams bounce, not walking.
@export var ram_bounce_min_speed: float = 7.0
## Rebound bounciness — 1.0 ≈ fully elastic, lower = softer.
@export var ram_bounce_factor: float = 0.2
## Min seconds between bounces (stops jitter against a single wall).
@export var ram_bounce_cooldown: float = 0.15
## Screen-shake punch (0..1) on a bounce.
@export var ram_bounce_shake: float = 0.15
## Pinball "bumper" sfx played the moment a bounce fires (metallic clang default).
@export var ram_bounce_sound: AudioStream = preload("uid://c3ilkdwchpnhy")

@export_group("Air Thump")
## Loud "thump" played when you slam into something mid-air at speed (a 2D impact cue). Swap for your preferred sound.
@export var thump_sound: AudioStream = preload("uid://c23166qlxcvbi")
## Minimum speed LOST in a single frame (m/s — sudden decel from a real impact, not a
## glancing slide) required to play the thump. Higher = only harder slams thump.
@export var thump_min_speed_lost: float = 7.0
## Volume (dB) of the thump sound; raise to make mid-air slams louder.
@export var thump_volume_db: float = 6.0
## Min seconds between thumps, so one impact can't machine-gun the sound.
@export var thump_cooldown: float = 0.2

@export_group("Jump")
## Variable jump (2D-platformer feel): release jump while still rising and the upward velocity is cut by
## this factor for a shorter hop — tap for a low hop, hold for the full jump_velocity arc. 1.0 = no cut.
@export var jump_cut_factor: float = 0.4

func gravity(delta: float) -> void:
	if is_on_floor():
		return
	var fall_mult := maxf(GameSettings.player_movement.fall_gravity_mult, 0.0) if velocity.y < 0.0 else 1.0
	velocity += get_gravity() * fall_mult * delta

# NOTE: slide + wall-climb tuning moved onto their drag-drop Ability nodes (scripts/components/abilities/
# slide.gd, wall_climb.gd). Tune them THERE now — re-tune on the node if you had overrides on the Player.

@export_group("Noise")
# --- Noise (drives enemy hearing) ---
## Audible radius (m) added per m/s of ground speed while not crouching — higher = enemies hear you moving from further off.
@export var noise_move_per_speed: float = 1.2
## Audible radius (m) of a gunshot, which then decays back to 0 — higher = a shot alerts enemies further away.
@export var noise_gunfire_radius: float = 28.0
## How fast the gunshot noise radius shrinks (m/s) — higher = the gunshot alert fades sooner.
@export var noise_gunfire_decay: float = 45.0
# Current audible radius (read by enemy Perception.can_hear); 0 = silent. The NoiseEmitter component
# WRITES this each frame; it stays declared here so enemy Perception can read player.noise_radius.
var noise_radius: float = 0.0
# How LIT we are (0 = pitch dark, 1 = fully lit), read by enemy Perception (via light_falloff) so shadow slows
# detection. The optional PlayerLightLevel drop-in WRITES this each sample; default 1.0 = fully lit, so with no
# PlayerLightLevel (or no enemy light_falloff curve) light has no effect and detection behaves exactly as today.
var light_exposure: float = 1.0
# Whether a roof/ceiling is currently overhead (we're "indoors"). The optional IndoorAmbienceDucker drop-in WRITES
# this each sample; default false, so with no ducker in the scene nothing reads a changed value. It's the shared
# "is there a roof over me" seam other systems can read (ambience duck, a future reverb/rain/interior-music swap)
# instead of each re-casting an up-ray.
var is_indoors: bool = false

var target_speed: float = GameSettings.player_movement.max_speed

# Host-owned ADS flag: ScopeCoordinator WRITES host._is_scoped; GroundMovement reads it off the host for the
# scope slow, and sprint_blocked_by_scope() reads it here for the run lockout.
var _is_scoped: bool = false
# Stealth HUD throttle: the full nearby-NPC awareness scan is heavy, so run it ~10x/sec and reuse the last
# snapshot on the in-between frames (the HUD readout doesn't need per-frame precision). Behaviour-preserving —
# it just re-pushes the cached level/meter between recomputes.
const _STEALTH_HUD_INTERVAL: float = 0.1
var _stealth_hud_accum: float = 0.0
var _stealth_hud_snap: Dictionary = {}
@export_group("Abilities")
## SFX chirped when the air-dash becomes available again (placeholder ding — swap in the inspector).
@export var air_dash_recharge_sfx: AudioStream
# (The dash-flash feel — peak alpha + fade time — is a designer knob on GameSettings.player_feedback;
# PlayerHud reads it for the flash it builds + drives.)
## Grapple config (.tres): the rope texture/colour, the hook-tip sprite, the SFX, and the feel tuning. The
## GRAPPLE ABILITY node reads this scene-wired slot when it builds its GrappleHook (its own `config` export
## overrides it), so a runtime-granted grapple still picks up the authored config. Null = the hook's defaults.
@export var grapple_resource: GrappleHookResource

func get_hit_flash() -> Node3D:
	return white_flash

func _enter_tree() -> void:
	if not gun_mesh:
		gun_mesh = get_node_or_null("Head/ScreenShake/Camera3D/GunMesh") as GunMesh
	if gun_mesh:
		muzzle = gun_mesh.muzzle
		if mesh == null and mesh_asset == null:
			mesh = gun_mesh
	# Resolve the HUD root if extraction cleared its export, then inject the player whose
	# HP it shows + the ammo clip it reads. Resolved before the rig below so head.setup()
	# can hand the HUD layer to the view-model camera (its composite container lives there).
	if not ui:
		ui = get_node_or_null("UI") as UI
	if ui:
		ui.setup(self, weapon_system.ammo)
	# Same for the camera rig (Head -> ScreenShake -> Camera3D): resolve the rig root if
	# its export was cleared, read the camera + screen-shake off the rig interface, and
	# inject this player into the rig parts that point back out (camera + pickup raycast).
	if not head:
		head = get_node_or_null("Head") as Head
	if head:
		camera_effects = head.camera
		screen_shake = head.screen_shake
		head.setup(self, mouse_input, ui)
	crouch.player = self
	crouch.head = head
	crouch.collision_shape = player_collision_shape
	weapon_system.setup(self, camera_effects, muzzle)
	coyote_time.character = self
	# The view model self-wires its gun-mesh pose anims + muzzle FX from these refs.
	# (The Slice-1 host-side signal bridge now lives inside GunMesh.setup().)
	gun_mesh.setup(self, weapon_system.inventory, weapon_system.attack, weapon_system.ammo, mouse_input, weapon_system.scope_in)
	bullet_time.character = self
	bullet_time.scope_in = weapon_system.scope_in
	bullet_time.attack = weapon_system.attack
	bunnyhop.character = self
	mouse_input.player = self

## Grabbing/dropping a carried prop drives the weapon AND the view-model hands. On grab: holster + LOCK the weapon
## away (you can't take a gun out with your hands full), then (after a short beat so the holster reads) bring the hands
## out. On drop: unlock + restore the weapon's prior holster state (so a manual hold-R holster before the grab is
## respected) and hide the hands. Mirrors the holster-stashing the dialogue camera does.
## This handler keeps the GAMEPLAY half (the `_carrying` latch, the holster capture/restore, `draw_locked`,
## the release bookkeeping) and TAILS into the FirstPersonBody's cosmetic half at the end — see the relay note there.
func _on_carry_changed(holding: bool) -> void:
	_carrying = holding
	# A prop pulled from the backpack (Hotbar hold) that gets DROPPED/THROWN (E/Z/left-click) rather than stashed
	# back leaves our reservation stale: the prop is now a world object with its OWN CanPickUp, so restore its
	# destructibility (it's out of your protected hands) and release the reservation (the hotbar slot then vacates —
	# the item is gone from the bag and lives in the world until re-collected). stash_held_item() clears _held_inv_item
	# BEFORE it force-releases, so this only ever catches a genuine drop/throw, never our own put-back.
	if not holding and _held_inv_item != null:
		_restore_held_prop_destructible()
		_held_inv_item = null
		_held_inv_prop = null
		_held_from_weapon_slot = false  # it's on the floor / in flight now — the H toggle has nothing left to put back
	# WEAPON STATE first, and INDEPENDENT of whether the cosmetic FP-arms rig was built (first_person_arms off /
	# no camera / no model — the component's own guards). Carrying always puts the gun away and LOCKS it there;
	# dropping unlocks and restores the pre-carry holster. Kept ABOVE the fp_body relay so the lock can never get
	# stuck if the arms rig is absent or torn down mid-carry — the "no gun while your hands are full" rule
	# doesn't depend on the hands being drawn (the connect in _ready is unconditional for the same reason).
	if weapon_system != null and weapon_system.attack != null:
		if holding:
			_holster_before_carry = weapon_system.attack.holstered
			weapon_system.attack.set_holstered(true)  # weapon away FIRST...
			weapon_system.attack.draw_locked = true   # ...and LOCKED away: no drawing the gun while carrying
		else:
			# Hands free: LIFT the lock FIRST — always, even mid-death (die() force-releases the prop, routing here
			# while _dying is true), so a carry cut short by death can't leave the gun locked into the in-place revive.
			weapon_system.attack.draw_locked = false
			# ...THEN restore the prior holster — but not mid-death-cinematic (it would pop the gun up over the keel-over).
			if not _dying and not _dead:
				# A LEFT-CLICK throw (PickupRay's alternate-throw) re-draws the gun on the SAME held click that
				# launched the prop; suppress that click's fire so it can't also shoot the instant the gun raises
				# (FNV draw-click rule). No-op unless the fire button is actually held now, so Z/E throws are unaffected.
				weapon_system.attack.suppress_fire_for_carry_release()
				weapon_system.attack.set_holstered(_holster_before_carry)
	# COSMETIC view-model hands: the FirstPersonBody's half of this same event, called as this handler's TAIL —
	# ONE connection on carry_changed, relayed, so the holster restore above has always landed synchronously by
	# the time the component's _unarmed_hands_wanted() reads attack.holstered. A second connection on the signal
	# would re-open a connection-order dependency (children's _ready runs before the parent's — the component
	# would have connected first and read the STALE holster).
	if fp_body != null:
		fp_body.on_carry_changed(holding)

## The character's chosen name, from character creation (mirrors GameState.player_name). Display-only — the Stats
## screen shows it; the save's source of truth is GameState.player_name. "" for an unnamed / older character.
var player_name: String = ""

## The character's chosen APPEARANCE (head/body customizer), mirrored from GameState.appearance. Display-only — the
## Stats screen's portrait reads it; the save's source of truth is GameState.appearance. EMPTY for a never-customised
## / older character (the preview then shows the catalog's default look). This game is first-person, so the look is
## only ever SEEN in the menu portrait today; the field is kept on the Player as the natural hook for a future
## third-person body. See CharacterAppearanceCatalog.
var appearance: Dictionary = {}

func _ready() -> void:
	# Continue (a loaded autosave) OR a freshly CREATED character (character creation populated GameState.stat_values)
	# swaps in that stat sheet BEFORE super._ready, so Character._apply_stats stamps max_hp / carry_capacity from the
	# build (strength) and hp seeds from that max. A bare new game with no creation (empty stat_values —
	# e.g. a dev boot straight into game.tscn) keeps the scene's authored baseline sheet. (Money / unlocks / the
	# teleport are applied at the end of _ready, after the loadout's starting-money override, so the save wins.)
	if GameState.loaded or not GameState.stat_values.is_empty():
		stats = GameState.make_stats()
	player_name = GameState.player_name  # loaded save, the just-created character, or "" for a bare / dev boot
	appearance = GameState.appearance.duplicate()  # mirror the saved look for the Stats portrait (empty -> catalog default)
	super._ready()  # Character._ready: _apply_stats (strength) THEN seed hp = max_hp
	_setup_health_light()
	floor_snap_length = maxf(0.0, GameSettings.player_movement.step_down_snap)
	_set_stamina(stamina_max(), false)
	_discover_abilities()  # register editor-placed Ability children BEFORE the seed/load so they aren't duplicated
	if GameState.loaded:
		set_unlocks(GameState.unlocks)  # restore the saved mechanic set (replaces the fresh-game seed wholesale)
		set_disabled_unlocks(GameState.disabled_unlocks)  # then the switched-OFF implants: built if missing, kept installed-but-off
		_restore_perks()  # re-record the saved perk ledger (bonuses + abilities already restored via stats + unlocks)
		xp = GameState.xp
		level = GameState.level
	else:
		# A CREATED character can carry pre-boot grants while loaded is still false: the implant cart bought
		# ON CREDIT on the New Game implant screen (StartMenu stamps the ids into GameState.unlocks — the
		# stat_values escape hatch above is the same idiom; the BILL rides GameState.account — the SIGNED
		# Ledger balance _stamp_new_game_profile drives NEGATIVE — and NOTHING in _ready re-seeds that field,
		# so these boots re-apply the goods while the debt simply stays where it already sits. It is never in
		# the wallet). Apply them here or the never-granted chips would be silently ERASED by the first
		# autosave's capture() (which rebuilds GameState.unlocks from the live ability set). A bare/dev boot
		# (empty unlocks) still takes the plain fresh-game seed.
		# The pre-boot implant set spans BOTH lists. `unlocks` is only the ACTIVE projection, so a run whose
		# implants are ALL switched off (Implants tab) carries an EMPTY unlocks and a populated
		# disabled_unlocks — and this branch IS reached mid-run, not just at New Game: `loaded` stays false
		# for a whole New-Game session, and Options -> Main Menu -> Continue re-enters _ready without any
		# disk load. Gating on unlocks alone sent that run to _seed_unlocks() (which grants nothing —
		# starting_unlocks ships empty), UNINSTALLING the implants; the next autosave then rebuilt both
		# lists from the empty live set and erased them from disk, with the paid-for chips already consumed.
		var has_profile_implants := not GameState.unlocks.is_empty() or not GameState.disabled_unlocks.is_empty()
		if has_profile_implants:
			set_unlocks(GameState.unlocks)
			set_disabled_unlocks(GameState.disabled_unlocks)  # ...then re-disable the switched-off ones (builds their nodes first)
		else:
			_seed_unlocks()  # grant the fresh-game mechanics (a loaded save replaces this set via set_unlocks)
		# Seed the default respawn point (this spawn) the first time, so a death before reaching any bonfire still
		# brings you back here. A bonfire overrides it; a no-reload respawn doesn't re-run _ready, so this runs once.
		if not GameState.has_respawn:
			GameState.set_respawn(global_position, rotation.y)
	# Hurt-feedback component: owns the "getting rocked" slow-mo + screen-drain + bus muffle. Built
	# first so its master-bus low-pass is set up before anything else (matches the old _setup_hurt_lpf
	# being the first call here).
	_hurt = HurtFeedback.new()
	_hurt.host = self
	add_child(_hurt)
	_hurt.setup_lpf()
	# Scope reactions + music duck: drive the crosshair/optics/DoF and duck music on ADS in/out.
	_scope = ScopeCoordinator.new()
	_scope.host = self
	add_child(_scope)
	# Death-cinematic MIX: owns what you HEAR while dying — the per-bus world duck AND the death sting. One
	# object composes both because the sting IS the cinematic's soundtrack: it only reads right if the world
	# ducks out from under it (see death_mix.gd). Built AFTER _hurt.setup_lpf() so Master's low-pass — which
	# is a filter, not a level, and so cannot be undone downstream — is already installed.
	_death_mix = DeathMix.new()
	_death_mix.host = self
	add_child(_death_mix)
	weapon_system.scope_in.scoped_in.connect(_scope.on_scoped_in)
	weapon_system.attack.air_dash_recharged.connect(_on_air_dash_recharged)
	# Body-impact reactions (ram damage / air thump / pinball bounce), ticked from _physics_process.
	_ram_reactor = RamReactor.new()
	_ram_reactor.host = self
	add_child(_ram_reactor)
	# Noise emitter: writes our audible radius (enemy hearing) each frame; the gunfire spike is fed in
	# from on_weapon_fired.
	_noise = NoiseEmitter.new()
	_noise.host = self
	add_child(_noise)
	# Silent takedown (Slice 6b): HOLD the Takedown key behind an unaware NPC for a quiet kill. Self-ticking; it just
	# needs a host. Built unconditionally, but it stays INERT until the player installs the Takedown Chip — its
	# _can_run() gates on has_mechanic(&"silent_takedown"), granted by the SilentTakedownAbility node (air_dash idiom).
	# The verb / arc / range live on GameSettings.takedown (SilentTakedownSettings.tres).
	_takedown = SilentTakedown.new()
	_takedown.host = self
	add_child(_takedown)
	# Pet verb (friendly twin of the takedown): HOLD the Takedown key aimed at a Pettable object to pet it (a ♥
	# floats up). Self-ticking; just needs a host. The same Q is contextual — pet an object, take down an NPC — and
	# each verb owns its own HUD cue. Added AFTER _takedown so when aimed at an NPC the takedown's cue wins the frame.
	_pet = PetInteraction.new()
	_pet.host = self
	add_child(_pet)
	# Claim verb (ownership twin of pet): TAP the Claim key aimed at a Claimable object (a stray dog) to adopt it —
	# name it and make it follow you. Self-ticking on its own key; just needs a host. Pet and Claim can both apply to
	# the same object (the dog), so each owns its own key + HUD cue.
	_claim = ClaimInteraction.new()
	_claim.host = self
	add_child(_claim)
	# Deus Ex aim wander: the true shot direction drifts around the camera centre; STANCE steadies it
	# (standing still tighter, crouched tighter again — see AimSway / GameSettings.player_aim).
	_aim_sway = AimSway.new()
	_aim_sway.host = self
	add_child(_aim_sway)
	# Low-HP heartbeat (#11): a 2D pulse whose rate + volume rise as HP drops, driven in _update_low_hp.
	_heartbeat = AudioStreamPlayer.new()
	_heartbeat.stream = heartbeat_sound
	_heartbeat.bus = &"sfx"
	add_child(_heartbeat)
	# (The slide-wind player moved into the Slide ability node — it builds + drives its own looping sfx now.)
	# HUD overlays (speed vignette, dash flash, damage arcs, aim radials, sniper glints, hitmarker):
	# built onto the UI layer in the original draw order, with the active camera wired in.
	_hud = PlayerHud.new()
	_hud.host = self
	add_child(_hud)
	_hud.build(ui, camera_effects)
	# First-person body (legs + torso + the carry hands / bare fists): built by the FirstPersonBody component,
	# but called from HERE, not its own _ready — a child's _ready runs BEFORE the parent's, and `appearance` is
	# only mirrored from GameState near the top of THIS _ready, so a self-building component would tint the
	# legs and stamp the torso from an empty appearance dict. Legs show on look-down; the hands are built
	# hidden and appear while carrying a physics prop (weapon holsters first) or as the bare fists.
	if fp_body != null:
		fp_body.build()
	# Drive the carry dance off the pickup ray (PickupRay lives under the camera: Head/ScreenShake/Camera3D/RayCast).
	# ONE connection, on the PLAYER: _on_carry_changed keeps the weapon-state half (holster + draw-lock) and
	# tails into the component's cosmetic half, so the holster restore always lands before the fists decision.
	# UNCONDITIONAL — deliberately NOT gated on the cosmetic arms rig having been built (it used to live inside
	# _build_first_person_arms, so first_person_arms = false skipped the connect entirely and a carried crate
	# left the gun drawable; the "no gun while your hands are full" rule must not depend on the hands existing).
	if camera_effects != null:
		var carry_ray := camera_effects.get_node_or_null(^"RayCast") as PickupRay
		if carry_ray != null and not carry_ray.carry_changed.is_connected(_on_carry_changed):
			carry_ray.carry_changed.connect(_on_carry_changed)
	# (The grapple hook moved into the Grapple ABILITY node — it builds + owns the GrappleHook when granted,
	# reading grapple_resource/grapple_hook_origin off us. The pull still runs at its _physics_process beat.)
	# Conversation camera/weapon handling: focus-on-target zoom + holster-for-dialogue + the holster
	# swing (and its provoke-forgiveness). Built last; its signal handlers are wired straight to it.
	_dialogue = DialogueController.new()
	_dialogue.host = self
	add_child(_dialogue)
	# Holster: hide the gun mesh whenever Attack reports holstered (hold-R toggle / dialogue).
	weapon_system.attack.holster_changed.connect(_dialogue.on_weapon_holstered)
	# ...and the RETICLE goes away with it (GameSettings.hud.hide_crosshair_when_holstered): nothing is
	# aimed, so nothing annotates the aim point. Connected straight to the HUD's own latch — the signal's
	# `on: bool` matches the setter 1:1, and routing it there (rather than writing crosshair.visible here)
	# is what lets it COMPOSE with the dialogue hide instead of fighting it. See ui.gd's two latches.
	if ui != null:
		weapon_system.attack.holster_changed.connect(ui.set_crosshair_holstered)
	# UNARMED HANDS: the bare fists are the SAME rig as the carry hands (FirstPersonBody), so they follow the
	# same three state changes — putting the weapon away, swapping to/from a real weapon, and picking a prop up
	# or dropping it (that last one rides the carry relay in _on_carry_changed). Punching drives the rig's own
	# strike. Wired HERE, not in the component: Weapon/Attack readiness and the holster_changed connection
	# ORDER (dialogue → crosshair → this fists refresh) are established in this _ready.
	weapon_system.attack.holster_changed.connect(func(_on: bool) -> void:
		if fp_body != null:
			fp_body.refresh_unarmed_hands())
	if fp_body != null:
		weapon_system.attack.swap_finished.connect(fp_body.refresh_unarmed_hands)
		weapon_system.attack.play_animation.connect(fp_body.on_attack_play_animation)
	# TWO-FISTED input: left click throws the LEFT fist, right click the RIGHT. MouseInput polls the second
	# button; Attack refuses it for anything that isn't a punch weapon, so right-click stays ADS for guns.
	if mouse_input != null:
		weapon_system.attack.alt_attack_action = mouse_input.alt_attack_action
		mouse_input.alt_attack.connect(weapon_system.attack._on_mouse_input_attack.bind(false, true))
	if fp_body != null:
		fp_body.refresh_unarmed_hands.call_deferred()  # deferred so the inventory has equipped its first weapon
	# Put the weapon away for conversations (restored on finish), reusing the holster.
	DialogueManager.dialogue_started.connect(_dialogue.on_dialogue_started)
	DialogueManager.dialogue_finished.connect(_dialogue.on_dialogue_finished)
	# A fresh life must start on a NORMAL screen. The death cinematic's grayscale + fade-to-black ride a
	# shader sub-resource the scene reload leaves dirty (it's reused from the cached PackedScene), and the
	# slow-mo touches the global Engine.time_scale — so clear them all explicitly on (re)spawn.
	_reset_screen_post_process()
	_fade_in_from_black()  # (re)spawn EMERGES from black instead of a jarring hard cut to the world
	_ground_snap_frames_left = GROUND_SNAP_RETRY_FRAMES  # drop onto the floor once the (deferred-loaded) level exists under us
	# Cache the blob-shadow decal + its authored (ground-projecting) pose so the climb can swing it onto
	# the wall and back. Null-guarded everywhere — a Player scene without a "Shadow" decal just skips it.
	_shadow = get_node_or_null("Shadow") as Decal
	if _shadow:
		_shadow_rest_local = _shadow.transform
	# Turn the backpack's Tetris-style spatial cap ON for the PLAYER. Done BEFORE seeding/restoring so every stack
	# auto-places into the grid as it lands. NPCs share the SAME grid size but enable it DEFERRED (after seeding —
	# see NPC._ready); a fresh corpse-copy / container bag stays unbounded until the loot screen grids it. Grid size
	# is a designer knob (resources/tuning/InventorySettings.tres).
	if inventory != null:
		inventory.enable_grid(GameSettings.inventory.grid_cols, GameSettings.inventory.grid_rows)
	# Stock the backpack: Continue with a saved bag RESTORES it (items + the drawn weapon); otherwise seed the
	# authored starting loadout. (A save written before inventory persisted carries no bag — it seeds, exactly
	# as it behaved when written.) The hub keeps whatever it equipped on spawn; the restore re-draws the saved
	# weapon over it (or falls back to fists if nothing was equipped when saved).
	if GameState.loaded and GameState.has_inventory:
		_restore_saved_inventory()
	else:
		_seed_starting_inventory()
	# The player's fresh-game wallet (a designer knob — resources/tuning/EconomySettings.tres; the Character
	# export defaults 0, the NPC default). A Loadout, if assigned, overrides it; a loaded save wins over both.
	money = GameSettings.economy.player_starting_money
	var ld := weapon_system.loadout() if weapon_system != null else null
	if ld != null:
		money = float(ld.money)
	# Continue: the SAVED wallet wins over the loadout's starting money, and the player resumes AT the saved
	# respawn point (the last bonfire) in the SAME world — Dark Souls. Done after the loadout override so it isn't
	# clobbered. From here on every wallet change autosaves the run (stats / unlocks / respawn each autosave at
	# their own milestone — level-up, upgrade pickup, bonfire rest).
	if GameState.loaded:
		money = GameState.money
		Reputation.restore(GameState.reputation)  # re-apply saved faction standings (a fresh game starts neutral)
		_restore_status_effects()  # re-apply saved buffs/debuffs with their REMAINING time (anti quicksave-scum)
		# M3: only restore the saved respawn when the booted level is the one it belongs to. On a mismatched boot
		# (the saved level's .tres was deleted/renamed, so GameRoot booted the export instead) respawn_level_matches
		# is false — GameRoot places us at the export's spawn + re-seeds a valid respawn, so skip the stale coords here.
		if GameState.has_respawn and GameState.respawn_level_matches:
			global_position = GameState.respawn_position
			rotation = Vector3(0.0, GameState.respawn_yaw, 0.0)
	elif GameState.profile_active:
		# A CREATED run booted WITHOUT a disk load — the fresh New Game boot itself, a menu-and-back Continue
		# on the in-memory run, or a death reload that found no readable save. The live CASH wallet lives on
		# GameState.money: reset_for_new_game seeded it from the player_starting_money knob and every capture()
		# has kept it current since, so reading it here instead of re-seeding from the economy knob/loadout is
		# what preserves whatever this in-memory run has already earned or spent.
		# ⭐The implant bill is NOT in this number. It rides GameState.account, the ONE signed Ledger balance
		# (+ savings / - debt), which no death path and no branch in _ready touches — so the goods the unlocks
		# escape hatch above re-applies and the debt that bought them can never separate on a loaded=false
		# reboot, and a created run's wallet stays CASH-ONLY and >= 0. Keep that invariant: GameState's
		# load-time legacy fold reads a negative `money` as pre-ATM debt and MOVES it onto the account, so any
		# path that let a live wallet go negative would have the next load quietly eat it. Settled BEFORE the
		# MoneyPurse build below, so the coin tile mirrors the final cash (the debt is never in that tile — the
		# HUD's OWED row reads the account). A bare dev boot (profile_active false) keeps the knob/loadout seed.
		money = GameState.money
	# Restore the day/night clock onto the free-running WorldClock autoload, but ONLY after a genuine disk-load or New
	# Game (the one-shot flag) — NOT a death-respawn reload, which should carry the LIVE clock forward instead of
	# rewinding it to the last autosave. set_time_of_day is silent, so loading can't fire a synthetic dawn (e.g. rent).
	if GameState.consume_clock_apply():
		WorldClock.set_time_of_day(GameState.time_of_day)
	# ZORKMIDS AS A REAL ITEM: mirror the (now-finalized) wallet into a coin stack in the backpack, so money
	# shows up as a genuine draggable/droppable grid tile. Built AFTER the wallet is settled (seed / loadout /
	# saved value all applied above) and BEFORE the autosave hookups below, so its initial sync — which emits
	# inventory.changed — can't trigger a spurious end-of-frame save. Player-only (an NPC wallet stays a float).
	if inventory != null:
		_money_purse = MoneyPurse.new()
		_money_purse._host = self
		_money_purse.name = &"MoneyPurse"
		add_child(_money_purse)
	# Autosave seams, connected LAST so the in-_ready seeding/restoring above can't trigger them: any wallet
	# change and any bag change (buy/sell, loot, drop, reload taking reserve ammo, consumable use) queue the
	# one-frame-deferred flush below.
	money_changed.connect(_on_money_autosave)
	if inventory != null:
		inventory.changed.connect(_on_inventory_autosave)
	# Falling back to fists: when the drawn weapon leaves the bag (dropped / deposited / looted away) or is
	# unequipped from the UI, the backpack clears equipped_item and fires this — we re-arm bare fists so the
	# player is never left wielding a gun that isn't in the inventory.
	if inventory != null:
		inventory.equipped_item_lost.connect(_on_equipped_item_lost)
	# Begin holstered (start_holstered): put the just-equipped weapon away so play OPENS with the gun stowed —
	# drawn on demand by a fire-click or the hold-R toggle (FNV-style), like every armed NPC. MUST run after the
	# seed/restore equip above: equipping a weapon DRAWS it (set_holstered(false)), so holstering last wins. The
	# gun-mesh hides itself off the holster_changed signal (wired to _dialogue.on_weapon_holstered above); a swap
	# the restore/empty-loadout equip may still be raising can't re-reveal it (GunMesh._on_ammo_finished_reloading
	# now bails while holstered, mirroring GunMesh.land).
	if start_holstered and weapon_system != null and weapon_system.attack != null:
		weapon_system.attack.set_holstered(true)
	# Seed the HUD's holster latch from the FINAL state, once all of the above has settled. The signal alone
	# can't do it: set_holstered early-returns (emitting nothing) when the value is unchanged, so a restore
	# that was already holstered — or a Player authored start_holstered = false — would leave the reticle
	# stuck on the latch's `false` default. Cheap and idempotent; the connection above carries it from here.
	if ui != null and weapon_system != null and weapon_system.attack != null:
		ui.set_crosshair_holstered(weapon_system.attack.holstered)
	_consume_pending_holster_forgiveness_tutorial.call_deferred()

## Spare CLIPS to start with per DISTINCT caliber the loadout uses ("start with some reserve").
const START_CLIPS_PER_CALIBER: int = 4

## Spare clips per caliber to seed: a data-driven Loadout's value when one is assigned, else the default above.
func _starting_clips_per_caliber() -> int:
	var ld := weapon_system.loadout() if weapon_system != null else null
	return ld.starting_clips_per_caliber if ld != null else START_CLIPS_PER_CALIBER

## The bare-hands fallback weapon — equipped whenever nothing else is (the drawn weapon was dropped /
## deposited / unequipped). Same resource the NPCs use for unarmed strikes (issue 3b: default to fists).
const FISTS: WeaponData = preload("res://resources/weapons/fists.tres")

## Rebuild the backpack from the autosave (GameState.inventory_stacks: {id, count, x, y, w, h} in saved stack
## order, ids resolved through ItemDb.restore_item — weapons come back as fresh UNIQUE items, ammo/consumables
## as the shared template so stacking works). Each entry rebuilds as ONE stack at its saved grid spot via
## restore_stack (so the Tetris layout survives a reload); an OLD save with no placement keys auto-places, and a
## spot that no longer fits (grid shrank / footprint changed) falls back to auto-place too. An id that's no
## longer registered (an item removed from the game) is skipped with a warning rather than failing the whole
## load. The saved equipped stack is re-drawn through the normal equip path; nothing saved equipped -> bare FISTS
## (the hub's spawn-drawn default may not even be in the restored bag, and the player must never wield a gun
## that isn't in the inventory).
func _restore_saved_inventory() -> void:
	if inventory == null:
		return
	var equipped: Item = null
	var stacks: Array = GameState.inventory_stacks
	for i in stacks.size():
		# A hand-edited save can hold any Variant per entry — a non-Dictionary would crash the typed access
		# below (and entry.get on e.g. an int). Skip junk entries; the rest of the bag still restores.
		var entry = stacks[i]
		if not (entry is Dictionary):
			push_warning("Player: malformed save stack entry %d (%s) — skipped" % [i, str(entry)])
			continue
		var it: Item = ItemDb.restore_item_from_save(entry)  # str() + weapon_delta handling live in ItemDb
		if it == null:
			push_warning("Player: the save references unknown item id '%s' — skipped" % str(entry.get("id", "")))
			continue
		# `count` is type-guarded for the SAME reason x/y/w/h are below (and with the same idiom as
		# CharacterInventory.restore_serialized_stacks, the snapshot tier's twin of this loop): a hand-edited
		# save can hold any Variant here, and int([3]) is a hard runtime ERROR, not a coercion — it would abort
		# this loop mid-restore inside _ready, dropping every LATER stack AND skipping the equip / fists-fallback
		# below it. No in-game path writes a non-numeric count today; this keeps the two loaders' junk-tolerance
		# identical rather than leaving one of them one bad key away from a half-restored bag.
		var cnt_v: Variant = entry.get("count", 1)
		if not (cnt_v is int or cnt_v is float):
			push_warning("Player: save stack '%s' has a non-numeric count (%s) — skipped" % [str(entry.get("id", "")), str(cnt_v)])
			continue
		var cnt := int(cnt_v)
		# Placement (x,y,w,h) only when ALL four are numeric — a junk-typed value (Array under "x", …) falls back
		# to auto-place instead of erroring int(). No "x" at all = an old, placement-less save -> auto-place.
		if _entry_has_placement(entry):
			inventory.restore_stack(it, cnt, int(entry["x"]), int(entry["y"]), int(entry["w"]), int(entry["h"]))
		else:
			inventory.restore_stack(it, cnt)  # old / placement-less save: auto-place top-left-first
		if i == GameState.equipped_index:
			equipped = it
	if equipped != null and equipped.is_weapon():
		inventory.equip_item(equipped)  # routes through SwapWeapons so the drawn weapon matches the save
	else:
		# A saved equip that didn't restore (its stack was skipped as unknown, or the index is bad) falls back
		# to fists like an unequipped save — but say so, since the player DID have something drawn when saving.
		if GameState.equipped_index >= 0:
			push_warning("Player: the save's equipped weapon (stack %d) didn't restore — falling back to fists" % GameState.equipped_index)
		if weapon_system != null:
			weapon_system.equip_weapon(FISTS)

## True when a save stack entry carries a full, NUMERIC grid placement (x,y,w,h all present and int/float). A
## junk-typed value, or any key missing, returns false so the loader auto-places instead of erroring int() on an
## Array / crashing on a partial placement — keeps the corrupt-save guard (test_load_tolerates_corrupt) honest.
func _entry_has_placement(entry: Dictionary) -> bool:
	# String keys (not StringName) — that's what GameState.capture writes and ConfigFile reads back, and the two
	# don't compare equal as Dictionary keys in GDScript.
	for key in ["x", "y", "w", "h"]:
		if not entry.has(key):
			return false
		var v = entry[key]
		if not (v is int or v is float):
			return false
	return true

## Stock the backpack with the authored starting loadout (the SwapWeapons weapon_slots) as unique weapon
## items, plus a little reserve ammo per caliber. On respawn a fresh Player rebuilds it from scratch. With the
## bounded grid on, an add can fall short if the loadout overflows the grid — warn (a designer-facing nudge to
## grow InventorySettings or shrink the loadout) rather than silently dropping a starting weapon.
func _seed_starting_inventory() -> void:
	if inventory == null or weapon_system == null:
		return
	var seeded_calibers := {}
	for res in weapon_system.weapon_loadout():
		var w := res as WeaponData
		if w == null:
			continue
		var it := ItemDb.make_weapon_item(w)  # a UNIQUE item per weapon, so identical weapons stay distinct
		if it != null and inventory.add(it) <= 0:
			push_warning("Player: starting weapon '%s' didn't fit the backpack grid — not seeded" % it.label())
		# Starting reserve: a few spare clips per DISTINCT caliber (pistol + SMG share 9mm -> seeded once).
		if w.caliber != &"" and not seeded_calibers.has(w.caliber):
			seeded_calibers[w.caliber] = true
			var ammo_item := ItemDb.ammo_item_for(w.caliber)
			if ammo_item != null and inventory.add(ammo_item, _starting_clips_per_caliber()) <= 0:
				push_warning("Player: starting %s ammo didn't fit the backpack grid — not seeded" % str(w.caliber))
	# Mark the weapon the hub drew on spawn (weapon.tscn's default) as the equipped item, so the inventory
	# shows the right row highlighted before the player ever opens it.
	var drawn := weapon_system.equipped_weapon
	if drawn != null:
		for s in inventory.contents():
			if s["item"].weapon == drawn:
				inventory.equipped_item = s["item"]
				break
	elif weapon_system != null:
		weapon_system.equip_weapon(FISTS)  # an EMPTY loadout -> start with bare fists (like an unequipped save), never a null weapon

## The backpack asked to draw `weapon` (UI click now, looted-then-equipped later). Route it through the
## weapon system's swap path so the down/up swap animation plays — the trigger just moved from keys 1-7
## to the inventory UI. Overrides Character's no-op hook.
func _on_equip_weapon_requested(weapon: WeaponData) -> void:
	if weapon_system != null:
		weapon_system.equip_weapon(weapon)

## The drawn weapon left the bag (dropped / deposited / looted away) or was unequipped from the UI — fall
## back to bare FISTS so the player always wields SOMETHING that's actually in hand (issue 3b: nothing
## equipped defaults to fists). Routed through the normal swap path so the put-away/draw animation plays.
func _on_equipped_item_lost() -> void:
	if weapon_system != null:
		weapon_system.equip_weapon(FISTS)

## True while the player is (mostly) crouched. Used by stealth checks — e.g. pickpocketing requires a
## crouch (Talkable.start_talk reads this).
func is_crouching() -> bool:
	return crouch != null and crouch.crouch_t > 0.5

## Drop `count` of `item` out of the backpack into the world as a throwable pickup the player (or anyone)
## can grab again (E to stash, Z to carry/throw) — spawned on the floor just in front of you. Dropping the
## weapon you're WIELDING is allowed: removing it clears the backpack's equipped_item -> equipped_item_lost
## -> we fall back to bare fists, so you can toss your gun on the ground and keep your (empty) hands.
func drop_item(item: Item, count: int = 1) -> void:
	if inventory == null or item == null or count <= 0:
		return
	var world := get_parent()
	if world == null:
		return  # nowhere to drop into (off-tree) — don't remove from the bag if we can't spawn the drop
	_spawn_drop(world, item, inventory.remove(item, count))

## Take the WIELDED weapon (knife/gun) out of the holster and INTO your hands as a carried physics prop — the
## DropHeld / H verb when your hands aren't already full (PickupRay._drop_held_in_hand delegates here). H is a
## TWO-STAGE TOGGLE on a weapon: the first press puts the knife in your hands READY TO THROW, and the SECOND
## press puts it back — you re-wield it (return_held_weapon_to_hands), you don't drop it. Throwing it is
## left-click or a Z-hold, and an E-tap still sets it down; there's no bespoke weapon-throw path.
## No-op with bare fists, where inventory.equipped_item is null.
## _pull_and_hold is the SAME path the hotbar's "hold from backpack" action uses: it builds the world prop, takes
## the item out of the bag — which clears equipped_item -> equipped_item_lost -> _on_equipped_item_lost re-arms
## fists — and grabs it at the hold anchor, RESERVING the item so the hotbar slot and the save can still reach it
## (a save taken mid-carry folds it back into the backpack snapshot; see GameState). It refuses with the bag
## UNTOUCHED when the weapon can't build a Throwable or we're off-tree, so the floor-drop fallback below is then
## the ONLY removal — H always does something with the weapon rather than silently no-opping.
func hold_equipped_weapon() -> void:
	if inventory == null:
		return
	var eq := inventory.equipped_item
	if eq == null or not eq.is_weapon():
		return
	if _pull_and_hold(eq):
		# Remember it came out of YOUR HOLSTER (not the hotbar / the ground) — that's what makes the next H a
		# put-back instead of a drop, and what re-draws the weapon when it goes back in the bag.
		_held_from_weapon_slot = true
		return
	drop_item(eq, 1)

## The SECOND stage of the H toggle: put the weapon in your hands back where it came from — into the bag AND back
## in your grip (stash_held_item re-wields it). Returns true when this press was CONSUMED here, so PickupRay can
## tell "H put my knife away" from "H should set this crate down": it's true ONLY for the weapon a previous H
## pulled out of your own holster. A world-grabbed prop or a hotbar-pulled prop returns false and still gets the
## ordinary tap-drop. A put-back the bag REFUSES (loot filled the footprint the pull freed) still returns true —
## stash_held_item toasts and keeps the weapon in your hands, which is what the toast promises; H must never
## turn into a surprise floor-drop of your own knife.
func return_held_weapon_to_hands() -> bool:
	if not _held_from_weapon_slot:
		return false
	stash_held_item()
	return true

## Mirrors Character.money into a real coin Item stack in the backpack (built in _ready) — see MoneyPurse.
var _money_purse: MoneyPurse
## The physics money-bag factory. Preloaded BY PATH (not the MoneyBag class_name) so player.gd never depends on that
## brand-new global class being registered — avoids the "unknown type" parse cascade on a cold cache / headless run.
const MoneyBagBuilder := preload("res://scripts/components/money_bag.gd")

## Drop `amount` zorkmids out of the wallet onto the floor in front of you as a physics MONEY BAG (MoneyBag) — a
## grabbable, throwable purse that gets BIGGER and hits HARDER the more it holds, with a MoneyPickUp child so aiming +
## Interact scoops it back into your wallet (anyone can grab it, same as loose loot). Clamped to what you actually
## carry; a non-positive amount or an off-tree player is a no-op. The wallet is debited through add_money (so the HUD
## floats a -N and the run autosaves), and MoneyPurse then clears the coin tile to match. This is what right-clicking
## the zorkmids tile in the backpack does — the coin pile IS the wallet, so it spills the whole lot into one bag.
## The OTHER producer of a money bag is dying with nobody to blame (_spill_death_purse) — it shares _place_money_bag
## below, so a purse you dumped and a purse you dropped dead are the same reclaimable object.
# --- THE PAYMENT RAILS — the Player's override of Character's four-method payment seam --------------------
# Three kinds of money, one debit order (cash, then savings, then the credit line):
#   CASH (`money`)                — free to spend, earns nothing, LOST ON DEATH.
#   SAVINGS (`GameState.account` > 0) — safe from death, earns interest, costs a service charge to spend.
#   CREDIT (`GameState.account` < 0)  — the same draw continued past zero, up to the live credit line.
# DEBIT declines rather than crossing zero; CREDIT is the identical draw order allowed to keep going. Arming
# CREDIT therefore never costs more than DEBIT for a purchase you could already afford — it only extends how
# far the same draw may go. `GameState.account` is ONE SIGNED field, so a purchase that dips below zero IS the
# debt, and there is no second ledger to reconcile.

## THE funding split for `cost` under the armed rail: {base, cash, rail, fee, total, ok}. The ONE formula —
## spendable / charge_total / can_pay / charge all read it, so the dim, the quote and the till cannot diverge.
## ⭐The fee is derived from the BASE split and simply ADDED; it never re-enters its own split, so there is no
## fixed-point iteration and the quoted number is stable across repaints.
func _split(cost: float) -> Dictionary:
	var base := maxf(0.0, snappedf(cost, Zorkmids.QUANTUM))
	if base <= 0.0:  # a free service always clears, whatever the wallet or the debt looks like
		return {"base": 0.0, "cash": 0.0, "rail": 0.0, "fee": 0.0, "total": 0.0, "ok": true}
	var cash := minf(base, maxf(0.0, money))
	var rail := snappedf(base - cash, Zorkmids.QUANTUM)  # the portion the Ledger has to cover
	var fee := snappedf(rail * maxf(0.0, GameSettings.economy.bank_noncash_fee_fraction), Zorkmids.QUANTUM)
	var total := snappedf(base + fee, Zorkmids.QUANTUM)
	var pot := snappedf(maxf(0.0, money) + maxf(0.0, GameState.account), Zorkmids.QUANTUM)
	if GameState.payment_method == PAY_CREDIT:
		pot = snappedf(pot + credit_left(), Zorkmids.QUANTUM)
	return {"base": base, "cash": cash, "rail": rail, "fee": fee, "total": total, "ok": total <= pot}

## Cash on hand plus banked savings, plus the remaining credit line when CREDIT is armed. A readout, not a
## gate — a purchase also has to clear the service charge, which only can_pay/charge_total know about.
func spendable() -> float:
	var funds := maxf(0.0, money) + maxf(0.0, GameState.account)
	if GameState.payment_method == PAY_CREDIT:
		funds += credit_left()
	return snappedf(funds, Zorkmids.QUANTUM)

func charge_total(cost: float) -> float:
	return float(_split(cost)["total"])

func can_pay(cost: float) -> bool:
	return bool(_split(cost)["ok"])

## The two-part price quote (Character.quote override) — literally the funding split, so a point-of-sale display
## can show "120 zm (+4 service charge)" instead of a single opaque total. Nothing here is recomputed: the label,
## the affordability dim and the till all read this ONE dictionary, which is what keeps the quote and the charge
## from drifting the way they did before the seam existed.
func quote(cost: float) -> Dictionary:
	return _split(cost)

## Pay `cost`: cash first (it is fee-free and earns nothing, so spending it first is always correct), then the
## account. Under CREDIT the account may cross zero into debt; under DEBIT `ok` already refused that case.
## Never pushes `money` below zero — the wallet is CASH-ONLY now, and a negative one would re-create the old
## "debt hides in the wallet" model the account exists to replace.
func charge(cost: float) -> bool:
	var s := _split(cost)
	var total := float(s["total"])
	if total <= 0.0:
		return true
	if not bool(s["ok"]):
		return false
	var pay_cash := minf(total, maxf(0.0, money))
	var rest := snappedf(total - pay_cash, Zorkmids.QUANTUM)
	if rest > 0.0:
		GameState.account = snappedf(GameState.account - rest, Zorkmids.QUANTUM)
	if pay_cash > 0.0:
		add_money(-pay_cash)  # money_changed rides the deferred autosave, which persists BOTH halves at once
	elif rest > 0.0:
		GameState.autosave_world_state()  # the wallet didn't move, so queue our own coalesced write
	return true

## What you currently OWE (0 while solvent) and what is still available on the line. The limit itself is
## recomputed live from the stat sheet and persisted NOWHERE (see credit_limit).
func credit_used() -> float:
	return maxf(0.0, -GameState.account)

func credit_left() -> float:
	return snappedf(maxf(0.0, credit_limit() - credit_used()), Zorkmids.QUANTUM)

## The Ledger re-rates you CONTINUOUSLY off the live PERMANENT stat sheet, so levelling up raises your line —
## the creditor rewards you for becoming more useful to it. get_stat() is raw, so a carried trinket or a timed
## buff can NOT inflate the line (no equip-at-the-terminal exploit) while level-ups and perks permanently can.
## Never fold in status_stat_modifier. Recomputed rather than persisted: there is no stale copy to migrate, and
## nothing for a reboot to re-seed (the failure that killed an earlier transient debt field).
func credit_limit() -> float:
	var sheet := stats_or_default()
	var values := {}
	var total := 0
	for n in CharacterStats.STAT_NAMES:  # always SIX keys — an EMPTY dict means "no application on file" to
		var v: int = sheet.get_stat(n)   # credit_rating_for and would fail OPEN to the full cap
		values[n] = v
		total += v
	return EconomySettings.credit_limit_for_sheet(values, GameSettings.economy,
			StatBudgetRef.STAT_MIN, StatBudgetRef.STAT_MAX, total, GameState.credit_standing)


## The Ledger's FULL live rating of this player — score, band, filed reason and every underwriting line —
## build AND record together. The ATM statement reads this; the implant screen deliberately does NOT (a fresh
## character has no history, so New Game rates the build alone).
func credit_rating() -> Dictionary:
	var sheet := stats_or_default()
	var values := {}
	for n in CharacterStats.STAT_NAMES:
		values[n] = sheet.get_stat(n)
	return EconomySettings.credit_rating_for(values, GameSettings.economy,
			StatBudgetRef.STAT_MIN, StatBudgetRef.STAT_MAX, GameState.credit_standing)

func drop_money(amount: float) -> void:
	amount = snappedf(minf(amount, money), Zorkmids.QUANTUM)
	if amount <= 0.0:
		return
	var world := get_parent()
	if world == null:
		return  # nowhere to drop into (off-tree) — don't debit the wallet if we can't spawn the bag
	_place_money_bag(world, amount, _drop_position())
	add_money(-amount)  # routes through the money seam -> HUD -N + autosave -> MoneyPurse re-syncs the coin tile

## Build + park a money bag holding `amount` at `at` under `world`. The ONE money-bag spawn site, shared by the
## backpack dump (drop_money) and the unclaimed-death spill (_spill_death_purse) so the two can never drift apart.
## Deliberately does NOT touch the wallet — each caller owns its own debit, and each does it exactly once.
func _place_money_bag(world: Node, amount: float, at: Vector3) -> void:
	var bag := MoneyBagBuilder.build(amount)
	world.add_child(bag)
	bag.global_position = at

## Drop the EXACT backpack stack the inventory UI right-clicked — identified by its stable grid `key` — into the
## world (the "clicked stack" contract). Goes through remove_stack (remove-BY-KEY), NOT drop_item's remove(item,
## count): a count-based remove drains the newest matching stacks first, so with two stacks of the same item it
## empties the WRONG tile (and a stackable split 5+2 would take the wrong amounts). `item` is passed only to BUILD
## the world object; the COUNT comes from the stack actually removed, so the drop and the vacated tile always agree.
## Dropping the wielded weapon's stack clears equipped_item -> equipped_item_lost -> fall back to fists, like drop_item.
func drop_stack(item: Item, key: int) -> void:
	if inventory == null or item == null:
		return
	var world := get_parent()
	if world == null:
		return  # off-tree — don't remove from the bag if we can't spawn the drop
	_spawn_drop(world, item, inventory.remove_stack(key))

## Build + place the world pickup for `removed` units of `item` under `world`, in front of the player. No-op when
## nothing was removed (empty stack / clamped to 0). Shared by drop_item (drop N of a KIND) and drop_stack (drop one
## exact TILE) so both spawn IDENTICAL objects via the one canonical WorldItem.build (also shared with the placer).
func _spawn_drop(world: Node, item: Item, removed: int) -> void:
	if removed <= 0:
		return
	var pickup := WorldItem.build(item, removed)
	world.add_child(pickup)
	pickup.global_position = _drop_position()

## The dropped/placed world item (a Throwable carrying a CanPickUp) is built by WorldItem.build() -- shared with
## the editor item-placer so a dropped item and a hand-placed one are byte-for-byte identical. (Was the
## _make_drop_pickup / _make_weapon_drop / _make_box_drop / _make_throwable_drop / _make_world_renderable helpers.)

## A point ~1 m in front of the player, dropped to the floor (down-ray on the world layer); falls back to
## the in-front point if nothing's below.
## How far a dropped thing looks DOWN from your feet for floor, and how far above that hit it rests (so it settles
## onto the surface instead of spawning half-buried). Shared by every drop; the unclaimed-death spill probes deeper
## (GameSettings.economy.death_purse_drop_ground_probe) because it has to cope with dying in mid-air.
const DROP_PROBE_DEPTH := 3.0
const DROP_PROBE_LIFT := Vector3(0.0, 0.2, 0.0)

## The point a drop is probed from: one metre in front of your feet, so items land where you're looking rather than
## inside your own capsule. Split out of _drop_position so the death spill can re-probe the same spot but tell a MISS
## from a hit (_drop_position silently hands back this mid-air point when the ray finds nothing, which is fine for an
## item you tossed while standing and very much not fine for a body falling through a void).
func _drop_probe_origin() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	return global_position + forward * 1.0

func _drop_probe_ray(from: Vector3, length: float) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * length, 1)
	q.exclude = [get_rid()]
	return q

func _drop_position() -> Vector3:
	var from := _drop_probe_origin()
	var hit := get_world_3d().direct_space_state.intersect_ray(_drop_probe_ray(from, DROP_PROBE_DEPTH))
	return (hit["position"] + DROP_PROBE_LIFT) if not hit.is_empty() else from

## Smoothly aim the body yaw + head pitch at `target_pos` so the camera frames whatever the player
## is talking to. Called externally by the talk handler (talkable.gd / dialogue_npc.gd via
## player.focus_camera_on), so the NAME stays here; the work lives in DialogueController.
func focus_camera_on(target_pos: Vector3) -> void:
	if _dialogue:
		_dialogue.focus_camera_on(target_pos)

# Weapon-host aim: the player aims its hosted Weapon down the camera's centre ray (where
# the crosshair points), so hitscan + spread match what it sees. Overrides the Character
# defaults (which fire straight forward from the body). camera_effects is the active
# Camera3D, so this reproduces exactly what Attack used to compute from the passed camera.
## --- Continuous autosave: every wallet change AND every bag change queue a ONE-FRAME-DEFERRED flush. The
## deferral makes multi-step transactions atomic on disk: a merchant buy charges money BEFORE transferring the
## item — an immediate save would snapshot charged-but-itemless — and a loot-all fires `changed` per stack.
## Coalescing to one end-of-frame write means the snapshot always holds the COMPLETED transaction. ---
var _autosave_queued: bool = false

func _on_money_autosave(_total: float, _delta: float) -> void:
	_queue_autosave()

func _on_inventory_autosave() -> void:
	_queue_autosave()

func _queue_autosave() -> void:
	if _autosave_queued:
		return
	_autosave_queued = true
	call_deferred(&"_flush_autosave")

func _flush_autosave() -> void:
	_autosave_queued = false
	GameState.autosave(self)

## --- Drag-drop ABILITY components (scripts/components/abilities): each unlockable mechanic is a CHILD Ability
## node; its presence + enabled flag IS the grant. Discovered in _ready (editor-placed), and grown at runtime by
## a pickup / a loaded save. wall_climb + slide own their logic in their node (driven via the typed refs below);
## air_dash / laser_sight / grapple still read has_mechanic (their logic lives in the weapon/gun systems). ---

## Wire the ability subsystem at CONSTRUCTION (before _ready), so the white-box unit tests — which build a bare
## Player.new() and never run _ready — can drive unlock/grant/has immediately. host = self (a member initializer
## can't reference self); the manager's unlock signal is relayed out as the Player's own mechanic_unlocked so
## existing listeners (ChipInstallScreen at chip_install_screen.gd:94) keep connecting to player.mechanic_unlocked.
func _init() -> void:
	_abilities_mgr.host = self
	_abilities_mgr.mechanic_unlocked.connect(_on_mechanic_unlocked)
	_abilities_mgr.mechanic_toggled.connect(_on_mechanic_toggled)

func _on_mechanic_unlocked(id: StringName) -> void:
	mechanic_unlocked.emit(id)

func _on_mechanic_toggled(id: StringName, active: bool) -> void:
	mechanic_toggled.emit(id, active)

## Scan our children for Ability nodes (a designer drag-drops them in) and register each. Called once in _ready
## before the unlock seed/load, so an editor-placed ability isn't duplicated by the seed.
func _discover_abilities() -> void:
	for child in get_children():
		if child is Ability:
			_register_ability(child)

## Wire one ability (the SOLE registration chokepoint): hand it to the manager to inject the host + add to the live
## set (deduped), then resolve the typed refs the physics step calls every frame (wall climb / slide / grapple).
## Called from _discover_abilities and, via a host callback, from AbilityManager.unlock / grant for runtime builds.
func _register_ability(a: Ability) -> void:
	_abilities_mgr.track(a)
	if a is WallClimb:
		_wall_climb = a as WallClimb  # explicit downcast (GDScript won't narrow Ability -> WallClimb on assign)
	elif a is Slide:
		_slide = a as Slide
	elif a is Grapple:
		_grapple_ability = a as Grapple

## True while an ENABLED ability child grants `id`. Gated abilities (air_dash / laser_sight / grapple) call this;
## wall_climb / slide are driven through their typed refs instead. Thin forwarder to the ability subsystem — kept
## on the Player because every external caller resolves the Player and duck-types has_method(&"has_mechanic").
func has_mechanic(id: StringName) -> bool:
	return _abilities_mgr.has(id)

## True while ANY ability node grants `id`, switched on or off — the INSTALLED predicate (you own the implant).
## The ChipInstaller guards key on this (an owned-but-off chip must never be re-sold or re-charged) and the
## Implants tab lists it; gameplay gates keep polling has_mechanic (ACTIVE) above. Thin forwarder.
func mechanic_installed(id: StringName) -> bool:
	return _abilities_mgr.is_installed(id)

## Switch an INSTALLED implant off / back on (the Implants-tab toggle). False for an id with no ability node.
## Emits mechanic_toggled on a real change; switching off runs the ability's on_deactivated hygiene (a live
## slide ends, a live grapple rope severs). Thin forwarder to the ability subsystem.
func set_mechanic_active(id: StringName, on: bool) -> bool:
	return _abilities_mgr.set_active(id, on)

## Player override of Character._apply_fall_damage: the fall-immunity UPGRADE (a FallImmunity Ability granted by an
## UpgradePickup) makes a hard landing cost nothing. Without it, defers to the shared base (FallDamage speed->HP +
## take_damage), so a profiled fall-damage knob on the player is finally live.
func _apply_fall_damage(fall_speed: float) -> void:
	if has_mechanic(&"fall_immunity"):
		return
	var dmg := FallDamage.hp_loss(fall_speed, fall_damage_min_speed, fall_damage_per_speed)
	if dmg <= 0:
		return
	_has_death_card_override = true
	_death_card_override_text = _compose_fall_death_message(fall_speed)
	super(fall_speed)
	if not _dying:
		_clear_death_card_override()

func _update_continuous_fall_death(delta: float) -> bool:
	var limit := GameSettings.player_movement.max_continuous_fall_time
	if limit <= 0.0 or _dying:
		_continuous_fall_time = 0.0
		return false
	if is_on_floor() or is_climbing() or velocity.y >= 0.0:
		_continuous_fall_time = 0.0
		return false
	_continuous_fall_time += maxf(delta, 0.0)
	if _continuous_fall_time < limit:
		return false
	_continuous_fall_time = 0.0
	_die_from_continuous_fall(absf(velocity.y))
	return _dying

func _die_from_continuous_fall(fall_speed: float) -> void:
	if _dead or _dying:
		return
	_has_death_card_override = true
	_death_card_override_text = _compose_fall_death_message(fall_speed)
	_took_any_hit = true
	_all_crits = false
	hp = 0.0
	damaged.emit(hp, max_hp)
	_dead = true
	_award_kill(null, false)
	var killer := _resolve_killer(null)  # one resolve shared by the wallet bequeath + the killed-by hook, as in Character.take_damage
	_bequeath_wallet(killer)
	_on_killed_by(killer)
	_begin_death()
	if not _dying:
		_clear_death_card_override()

func _compose_fall_death_message(fall_speed: float) -> String:
	var template := GameSettings.player_feedback.death_message_fall
	if template == "":
		return ""
	var mph := FallDamage.mph(fall_speed)
	if template.contains("[mph]"):
		return template.replace("[mph]", str(mph))
	# Legacy %-style templates: substitute via replace(), NEVER the `%` format operator — a designer-authored
	# line with a stray literal '%' (e.g. "100% dead") would raise "unsupported format character" on `%`.
	for spec in ["%d", "%s", "%f"]:
		if template.contains(spec):
			return template.replace(spec, str(mph))
	return template

## Permanently grant a mechanic (an UpgradePickup / a paid install / a loaded save). Idempotent — re-enables a
## disabled ability or builds it from the registry, emitting once. Thin forwarder to the ability subsystem; a
## runtime build routes its new node back through _register_ability (host callback) so the typed refs stay cached.
func unlock_mechanic(id: StringName) -> void:
	_abilities_mgr.unlock(id)

## True iff unlock_mechanic(id) would actually grant something (the runtime registry can build it, or a node with
## this id already exists to re-enable). Lets a PAID install (ChipInstaller) verify the grant resolves BEFORE
## charging, so a typo'd chip id never takes money for nothing. Thin forwarder to the ability subsystem.
func can_grant_mechanic(id: StringName) -> bool:
	return _abilities_mgr.can_grant(id)

## Adopt a ready-built Ability NODE and grant its mechanic -- a scene-based UpgradePickup / a Perk hands one over,
## so the node's own authored tuning/config rides along (unlike the registry-built unlock_mechanic). Returns TRUE
## only when it actually introduced a NEW ability node, so a grantor (a perk) knows whether it OWNS the ability for
## later revocation. Thin forwarder to the ability subsystem (see AbilityManager.grant for the idempotency rules).
func grant_ability(a: Ability) -> bool:
	return _abilities_mgr.grant(a)

## Revoke a granted mechanic (rank 29 respec): NULL the hot-path refs (_wall_climb / _slide / _grapple_ability)
## BEFORE freeing each node so a freed ability never dangles in the physics step, then let it go. The manager's
## take() removes the nodes from the live set (unfreed) so this ordering holds; unlike set_unlocks (which only
## DISABLES, so an editor-placed node survives a load), this truly REMOVES the ability. No-op for an absent id.
func revoke_ability(id: StringName) -> void:
	for a in _abilities_mgr.take(id):
		if a == _wall_climb:
			_wall_climb = null
		elif a == _slide:
			_slide = null
		elif a == _grapple_ability:
			_grapple_ability = null
		a.enabled = false
		a.queue_free()

## The granted-and-ACTIVE ability ids — for the save system's [player].unlocks. Thin forwarder to the ability
## subsystem. A player-disabled implant is deliberately absent here; it serializes via disabled_list() below.
func unlocked_list() -> Array:
	return _abilities_mgr.unlocked_ids()

## Every INSTALLED ability id, on or off — the Implants tab's roster superset. Thin forwarder.
func installed_list() -> Array:
	return _abilities_mgr.installed_ids()

## The installed-but-switched-OFF implant ids — for the save system's [player].disabled_unlocks (captured
## beside unlocked_list, restored via set_disabled_unlocks after set_unlocks). Thin forwarder.
func disabled_list() -> Array:
	return _abilities_mgr.disabled_ids()

## Restore the saved switched-off implants (loading a save; call AFTER set_unlocks). Builds any missing node
## then disables it, so an off implant survives the load INSTALLED. Thin forwarder.
func set_disabled_unlocks(ids: Array) -> void:
	_abilities_mgr.set_disabled(ids)

## Replace the live unlock set wholesale (loading a save): enable wanted abilities, disable the rest, build any
## missing. Disables rather than frees, so an editor-placed node survives a load. Thin forwarder — a missing
## build routes through _register_ability, so the typed hot-path refs are re-cached on load.
func set_unlocks(ids: Array) -> void:
	_abilities_mgr.set_unlocks(ids)

## Seed the fresh-game unlocks from starting_unlocks (builds the ability nodes). Called in _ready; a loaded save
## overrides via set_unlocks. unlock_mechanic skips any id already present as an editor-placed node.
func _seed_unlocks() -> void:
	for id in starting_unlocks:
		unlock_mechanic(id)

## Re-record the saved perk LEDGER under a PerkManager (record-only — a perk's stat bonuses ride in the saved
## stat sheet and its granted ability in the saved unlocks, so re-applying would double-count). Keeps has_perk /
## prerequisites / a non-consumed station's "already learned" correct after a reload.
func _restore_perks() -> void:
	if GameState.perk_paths.is_empty() and GameState.skill_points == 0 and GameState.points_earned == 0:
		return  # nothing to restore (widened past perk_paths so saved-but-unspent points aren't dropped)
	var pm := _perk_manager()  # find-or-create — never orphan an editor-placed PerkManager (capture reads the FIRST)
	pm.restore_paths(GameState.perk_paths, GameState.perk_grants)  # ledger -> respec after a reload revokes only what each perk truly granted
	pm.skill_points = GameState.skill_points
	pm.points_earned = GameState.points_earned

## Re-apply the saved active StatusEffects (CT-3) with their REMAINING time, so a buff/debuff survives a reload
## instead of being quicksave-scummed away. Each saved entry is {path, remaining}; the effect reloads from its .tres
## (a code-built effect with no path wasn't saved). Find-or-creates the manager, exactly like apply_status_effect.
func _restore_status_effects() -> void:
	var saved: Array = GameState.status_effects
	if saved.is_empty():
		return
	var mgr := ensure_status_manager()
	for e in saved:
		if not (e is Dictionary):
			continue  # a hand-edited / corrupt save can hold junk per entry — skip it, restore the rest
		var path := str(e.get("path", ""))
		if path == "":
			continue
		var fx := load(path) as StatusEffect
		if fx != null:
			mgr.restore_effect(fx, float(e.get("remaining", 0.0)))

## Award `amount` XP (kills, quests). Recomputes level from GameSettings.xp; each level CROSSED grants
## points_per_level skill points to the PerkManager. Autosaves the run (a milestone; a no-op off-tree). No-op
## for amount <= 0. Returns the number of levels gained.
func add_xp(amount: float) -> int:
	if amount <= 0.0:
		return 0
	amount *= GameSettings.difficulty.xp_gain_mult  # ML-5: difficulty scales XP GAINS (1.0 at Normal); a save-load restores xp directly, so only grants scale
	xp += amount
	var new_level := GameSettings.xp.level_for_xp(xp)
	var gained := new_level - level
	if gained > 0:
		var pts := gained * GameSettings.xp.points_per_level
		var pm := _perk_manager()
		pm.skill_points += pts       # spendable now
		pm.points_earned += pts      # cumulative — what a respec refunds to (free station grants never reduce it)
		level = new_level
		leveled_up.emit(level, pts)
		if is_inside_tree():
			notify_toast(PlayerText.level_up(level, pts), Color(0.7, 0.9, 1.0))
	xp_changed.emit(xp, level)
	GameState.autosave(self)
	return gained

## Find or create the player's PerkManager child (mirrors PerkStation / GameState._perk_manager_of).
func _perk_manager() -> PerkManager:
	for c in get_children():
		if c is PerkManager:
			return c as PerkManager
	var pm := PerkManager.new()
	pm.name = &"Perks"
	add_child(pm)
	return pm

## Use a CONSUMABLE from the backpack (a health pack): apply its effect and consume ONE from the stack.
## Returns false (and consumes nothing) if it isn't a consumable, isn't in the bag, or healing would do
## nothing at full HP — a click can't waste a health pack. Called by InventoryScreen on a consumable row.
func use_consumable(item: Item) -> bool:
	if item == null or not item.is_consumable() or inventory == null or not inventory.has(item):
		return false
	var did := false
	if item.heal_amount > 0.0 and hp < max_hp:
		heal(item.heal_amount)
		did = true
		if ui != null:
			notify_toast(PlayerText.gained_hp(int(round(item.heal_amount))), Color(0.4, 1.0, 0.45))
	if item.consumable_effect != null:
		apply_status_effect(item.consumable_effect)  # CT-3: shared Character entry point (weapons/consumables/NPCs)
		did = true
	if not did:
		# A heal-only pack at full HP with no effect — don't waste it on a click.
		if item.heal_amount > 0.0 and hp >= max_hp and ui != null:
			notify_toast(PlayerText.TOAST_ALREADY_FULL_HEALTH, Color(0.85, 0.85, 0.85))
		return false
	inventory.remove(item, 1)
	if item.id != &"":
		GameState.notify_use(item.id)  # advance any "use <item>" quest objective
	return true

func get_aim_origin() -> Vector3:
	return camera_effects.project_ray_origin(get_viewport().get_visible_rect().size / 2.0)

## World point an NPC's head/aim uses to "look at the player" -- the Head rig's position (the player's eye on
## their BODY). Unlike get_aim_origin (the camera RAY origin), this stays put during a dialogue camera cinematic
## (which swings/zooms the camera off to frame the NPC), so an NPC looks at where the player actually IS and tilts
## up/down to it, instead of staring level at the floating camera. Falls back to the body origin if head is unset.
func look_target_position() -> Vector3:
	return head.global_position if is_instance_valid(head) else global_position

func get_aim_direction() -> Vector3:
	var dir := camera_effects.project_ray_normal(get_viewport().get_visible_rect().size / 2.0)
	# Deus Ex aim wander (AimSway): the SHOT direction drifts around the camera centre — steadier standing
	# still, steadier again crouched, settling further the longer you hold still — instead of landing exactly
	# on the camera ray. The laser DOT (flash_light) is aimed along THIS value, so it shows the true shot
	# point while the crosshair stays fixed at centre.
	return _aim_sway.apply(dir, camera_effects.global_transform.basis) if _aim_sway != null else dir

func get_aim_basis() -> Basis:
	return camera_effects.global_transform.basis

@export_group("NPC reactions")
## A gunshot within this of a calm (non-hostile, out-of-combat) talker makes them remark on the reckless
## discharge, New Vegas style (#2).
@export var reckless_remark_radius: float = 12.0
## How often (s) to check whether you're aiming at a friendly/ally, who then comments (#3).
@export var aim_remark_interval: float = 0.35
## Max distance the aim-at-friendly check reaches.
@export var aim_remark_range: float = 25.0

const RECKLESS_LINES: Array[String] = []
const AIM_LINES: Array[String] = []

var _aim_remark_timer: float = 0.0

@export_group("Low HP feedback")
## HP fraction at/above which there's NO vignette/desaturation; below it the effect ramps in (so it's
## visible as soon as you take real damage, not only near death) to full at 0 HP.
@export var low_hp_start_frac: float = 0.85
## HP fraction at/below which the HEARTBEAT plays. 1.0 = it starts as soon as you take ANY damage (drop
## below full HP), then beats faster + louder the lower your HP falls (see _update_low_hp).
@export var heartbeat_start_frac: float = 1.0
## The heartbeat sound — a real heartbeat asset, played at natural pitch (the rate + volume convey the
## damage, not pitch).
@export var heartbeat_sound: AudioStream = preload("uid://rko1303sydde")
@export var heartbeat_interval_slow: float = 1.1   ## seconds between beats at the threshold
@export var heartbeat_interval_fast: float = 0.45  ## seconds between beats near death
@export var heartbeat_db_min: float = -16.0        ## beat volume at the threshold
@export var heartbeat_db_max: float = 2.0          ## beat volume near death

var _heartbeat: AudioStreamPlayer
var _heartbeat_timer: float = 0.0

var _last_combat_msec: int = 0  ## last time we fired / took damage / were aimed at — keeps the gun up in combat

## Mark "in combat now" so the view model stays raised (GunPose reads seconds_since_combat) for a beat.
func note_combat() -> void:
	_last_combat_msec = Time.get_ticks_msec()

func seconds_since_combat() -> float:
	return float(Time.get_ticks_msec() - _last_combat_msec) / 1000.0

func stamina_max() -> float:
	return maxf(1.0, GameSettings.player_movement.max_stamina + stats_or_default().stamina_bonus(status_stat_modifier(&"endurance")))

func apply_stamina_max_delta(old_max: float) -> void:
	var new_max := stamina_max()
	var target := stamina
	if new_max > old_max:
		target += new_max - old_max
	var before := stamina
	_set_stamina(target)
	if is_equal_approx(before, stamina) and not is_equal_approx(old_max, new_max):
		stamina_changed.emit(stamina, new_max)

func stamina_fraction() -> float:
	var maximum := stamina_max()
	if maximum <= STAMINA_EPS:
		return 1.0
	return clampf(stamina / maximum, 0.0, 1.0)

func can_spend_stamina(cost: float) -> bool:
	return cost <= 0.0 or stamina > STAMINA_EPS

func is_sprint_locked_out() -> bool:
	return _sprint_lockout_left > STAMINA_EPS

func can_sprint() -> bool:
	return stamina > STAMINA_EPS and not is_sprint_locked_out()

## Aiming down sights locks out the run tier — the ONE gate both sprint consumers share: _wants_sprint()
## (stamina drain + is_sprinting()'s FOV widen) and GroundMovement.compute_target_speed (the walk-tier
## fallback). While scoped you're pinned to the walk tier and THEN slowed again by scope_speed_mult, so
## ADS is a committed, planted stance rather than a sprint you can keep holding. Designer opt-out:
## GameSettings.weapon_general.allow_sprint_while_scoped.
func sprint_blocked_by_scope() -> bool:
	return _is_scoped and not GameSettings.weapon_general.allow_sprint_while_scoped

func is_sprinting() -> bool:
	return can_sprint() and _wants_sprint(input_dir)

func spend_stamina(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if not can_spend_stamina(cost):
		return false
	_set_stamina(stamina - cost)
	_stamina_regen_delay_left = maxf(_stamina_regen_delay_left, GameSettings.player_movement.stamina_regen_delay_after_spend)
	return true

func drain_stamina(rate: float, delta: float) -> bool:
	if rate <= 0.0:
		return true
	if stamina <= STAMINA_EPS:
		return false
	_set_stamina(stamina - rate * maxf(delta, 0.0))
	_stamina_regen_delay_left = maxf(_stamina_regen_delay_left, GameSettings.player_movement.stamina_regen_delay_after_spend)
	return stamina > STAMINA_EPS

func _begin_sprint_lockout() -> void:
	_sprint_lockout_left = maxf(_sprint_lockout_left, GameSettings.player_movement.stamina_sprint_lockout)

func _update_sprint_lockout(delta: float) -> void:
	if _sprint_lockout_left > 0.0:
		_sprint_lockout_left = maxf(_sprint_lockout_left - maxf(delta, 0.0), 0.0)

func _wants_sprint(input_vector: Vector2) -> bool:
	if input_vector.length() <= 0.1:
		return false
	if not is_on_floor():
		return false
	if is_climbing() or is_sliding() or is_grappling():
		return false
	if crouch != null and crouch.crouch_t >= 0.5:
		return false
	if sprint_blocked_by_scope():
		return false
	return Input.is_action_pressed(InputManager.action_run)

func _drain_sprint_stamina(delta: float) -> bool:
	if not can_sprint():
		return false
	var still_has_stamina := drain_stamina(GameSettings.player_movement.stamina_sprint_drain, delta)
	if not still_has_stamina:
		_begin_sprint_lockout()
	return still_has_stamina

func _set_stamina(value: float, emit_change: bool = true) -> void:
	var maximum := stamina_max()
	var next := clampf(value, -maximum, maximum)
	if is_equal_approx(stamina, next):
		return
	stamina = next
	if emit_change:
		stamina_changed.emit(stamina, maximum)

func _stamina_recovery_rate() -> float:
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	var moving := input_dir.length() > 0.1 or horiz_speed > GameSettings.player_movement.footstep_min_horizontal_speed
	if is_climbing() or is_sliding() or is_grappling():
		return GameSettings.player_movement.stamina_regen_active
	if not is_on_floor():
		return GameSettings.player_movement.stamina_regen_airborne
	if moving:
		return GameSettings.player_movement.stamina_regen_moving
	return GameSettings.player_movement.stamina_regen_idle

func _update_stamina_recovery(delta: float) -> void:
	if _stamina_regen_delay_left > 0.0:
		_stamina_regen_delay_left = maxf(_stamina_regen_delay_left - delta, 0.0)
		return
	var maximum := stamina_max()
	if stamina > maximum + STAMINA_EPS:
		_set_stamina(stamina)
		return
	if stamina >= maximum - STAMINA_EPS:
		return
	var rate := _stamina_recovery_rate()
	if rate > 0.0:
		_set_stamina(stamina + rate * delta)

## True while scaling a wall (wall-climb). The camera + view model read this to treat the climb as
## "walking" — running the walk-bob and the grounded FOV rules instead of the airborne/rising ones. Backed by
## the WallClimb ability node: false when it's absent / disabled.
func is_climbing() -> bool:
	return _wall_climb != null and _wall_climb.is_climbing()

## True while sliding — backed by the Slide ability node (false when absent / disabled). The footstep +
## falling-air gates read this; the slide-wind fade is internal to the Slide node itself.
func is_sliding() -> bool:
	return _slide != null and _slide.is_active()

func is_grappling() -> bool:
	return _grapple_ability != null and _grapple_ability.is_active()

## Project the blob shadow onto the WALL while climbing, easing back to the ground otherwise. The decal
## casts along its local -Y, so to land it on the wall we build a basis whose +Y is the wall normal (-Y
## points INTO the wall) and blend the decal's GLOBAL transform from its ground pose to that. Grounded, we
## restore the authored LOCAL pose so it tracks the body with no lag. Null-safe (no Shadow decal -> no-op).
func _update_wall_shadow(delta: float) -> void:
	if _shadow == null:
		return
	var want_wall := is_climbing() and is_on_wall()
	_shadow_wall_blend = move_toward(_shadow_wall_blend, 1.0 if want_wall else 0.0, shadow_lerp_speed * delta)
	if _shadow_wall_blend <= 0.001:
		_shadow.transform = _shadow_rest_local  # fully grounded: track the body exactly via the local pose
		return
	var ground_global := global_transform * _shadow_rest_local
	var wall_global := ground_global
	var wn := get_wall_normal()
	if is_on_wall() and wn.length_squared() > 0.0001:  # a REAL wall normal -- it reads ~zero the frame contact drops
		var up := wn.normalized()
		var up_ref := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		var x := up_ref.cross(up).normalized()
		var z := up.cross(x).normalized()
		var s := _shadow_rest_local.basis  # keep the authored decal scale (its column lengths)
		var wall_basis := Basis(x * s.x.length(), up * s.y.length(), z * s.z.length())
		wall_global = Transform3D(wall_basis, global_position - up * 0.1)  # sit on the wall, by the body
	_shadow.global_transform = ground_global.interpolate_with(wall_global, _shadow_wall_blend)

func on_weapon_fired(weapon: WeaponData) -> void:
	note_combat()
	if _aim_sway != null:
		_aim_sway.add_recoil(weapon)  # CT-1: per-weapon recoil kick + firing bloom (inert for a weapon with none set)
	if screen_shake:
		screen_shake.shake(weapon.screen_shake_amount)
	# Real guns are loud; melee (infinite-ammo) swings + the scoped airdash stay silent.
	if not weapon.is_infinite_ammo and _noise:
		_noise.gunfire()  # loud — nearby enemies hear the shot
	# NOTE: the reckless-fire bystander remark (#2) is NOT fired here — it waits for on_shot_resolved(),
	# once we know whether the shot connected with an NPC (a hit isn't "reckless discharge").

## Post-shot outcome hook (WeaponHost): the reckless-fire bystander remark (#2) fires here, AFTER the shot's
## trace resolved — and only for a real (loud) gun whose shot did NOT connect with another NPC. A shot that
## hit or killed someone isn't careless "reckless discharge", so nearby NPCs stay quiet about the gun noise
## (they react to the fight through the normal combat path instead).
func on_shot_resolved(weapon: WeaponData, hit_npc: bool) -> void:
	if not weapon.is_infinite_ammo and not hit_npc:
		_remark_reckless_fire()

func on_weapon_launched(weapon: WeaponData) -> void:
	_step_assist_launch_block_timer = STEP_LAUNCH_ASSIST_BLOCK_TIME
	if screen_shake:
		screen_shake.shake(weapon.launch_screen_shake)
	camera_effects.fov_punch()

## #2: after a gunshot, the nearest calm (non-hostile, out-of-combat) talker within reckless_remark_radius
## remarks on the reckless discharge. Just the closest, so a crowd doesn't all pipe up at once.
func _remark_reckless_fire() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var nearest: NPC = null
	var best := reckless_remark_radius * reckless_remark_radius
	for n in tree.get_nodes_in_group(Groups.NPC):
		if not (n is NPC):
			continue
		var npc := n as NPC
		if npc.is_hostile() or npc.is_in_combat():
			continue
		var d := global_position.distance_squared_to(npc.global_position)
		if d < best:
			best = d
			nearest = npc
	if nearest != null:
		nearest.react_remark(RECKLESS_LINES)

## #3: every aim_remark_interval, if the crosshair is on a non-hostile NPC (friendly or ally), it comments.
## react_remark self-filters (non-hostile, out-of-combat, has a Talkable), so aiming at an enemy stays silent.
func _check_aim_remark(delta: float) -> void:
	if not is_inside_tree():
		return
	# Only comment when the player is AIMING DOWN SIGHTS (holding Zoom), not merely looking their way.
	if not Input.is_action_pressed("Zoom"):
		_aim_remark_timer = 0.0  # reset so it fires promptly the moment you DO aim at someone
		return
	_aim_remark_timer -= delta
	if _aim_remark_timer > 0.0:
		return
	_aim_remark_timer = aim_remark_interval
	var world := get_world_3d()
	if world == null:
		return
	var from := get_aim_origin()
	var to := from + get_aim_direction() * aim_remark_range
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [get_rid()]
	var hit := world.direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return
	var npc := hit.get("collider") as NPC
	# Only remark if the NPC can actually SEE you point the gun at it -- no "watch where you're aiming" from an
	# NPC you're aiming at from behind / through cover (gunfire is audible, but AIMING is purely visual).
	if npc != null and npc.can_see_node(self):
		npc.react_remark(AIM_LINES)



## Toggle the night-vision look (NightVision action, N by default) and fade it in/out by driving the
## post-process material's `night_vision` uniform. (Restored verbatim from the pre-reorg driver.)
func _update_night_vision(delta: float) -> void:
	if Input.is_action_just_pressed(InputManager.action_nightvision):
		_nv_on = not _nv_on
	if not _nv_rect:
		return
	var mat := _nv_rect.material as ShaderMaterial
	if not mat:
		return
	var target := 1.0 if _nv_on else 0.0
	_nv_t = lerpf(_nv_t, target, 1.0 - exp(-night_vision_fade_rate * delta))
	mat.set_shader_parameter("night_vision", _nv_t)

func _setup_health_light() -> void:
	if _player_emitting_light == null:
		return
	_player_health_light_full_color = _player_emitting_light.light_color
	if not damaged.is_connected(_on_health_light_changed):
		damaged.connect(_on_health_light_changed)
	_refresh_health_light_color(hp, max_hp)

func _on_health_light_changed(current_hp: float, maximum_hp: float) -> void:
	_refresh_health_light_color(current_hp, maximum_hp)

func _refresh_health_light_color(current_hp: float, maximum_hp: float) -> void:
	if _player_emitting_light == null:
		return
	_player_emitting_light.light_color = health_light_color_for(
			current_hp,
			maximum_hp,
			_player_health_light_full_color,
			player_health_light_damaged_color)

static func health_light_color_for(current_hp: float, maximum_hp: float, full_health_color: Color, damaged_color: Color) -> Color:
	var hp_frac := clampf(current_hp / maxf(maximum_hp, 1.0), 0.0, 1.0)
	if hp_frac <= 0.0:
		return damaged_color  # exact endpoint: float lerp at t=1 lands epsilon-off (a + (b-a) != b), and dead must show the CONFIGURED red
	var damage_frac := pow(1.0 - hp_frac, 0.75)
	return full_health_color.lerp(damaged_color, damage_frac)

## Low-HP feedback (#11): drive the post-process `low_hp` uniform (black vignette + desaturation) and a
## heartbeat that beats faster + louder as HP falls below low_hp_start_frac. Silent + cleared above the
## threshold and when dead.
func _update_low_hp(delta: float) -> void:
	var frac := clampf(float(hp) / maxf(max_hp, 1.0), 0.0, 1.0)
	# Vignette + desaturation scale from low_hp_start_frac, so they show as soon as you're hurt.
	var vis_intensity := 0.0
	if low_hp_start_frac > 0.0:
		vis_intensity = clampf((low_hp_start_frac - frac) / low_hp_start_frac, 0.0, 1.0)
	if _nv_rect:
		var mat := _nv_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("low_hp", vis_intensity)
			mat.set_shader_parameter("colorblind_mode", Settings.colorblind_mode)
			mat.set_shader_parameter("contrast", Settings.contrast)  # Video-tab setting, polled live like colorblind
	# Heartbeat is a near-death cue with its OWN, lower threshold — faster + louder the lower you go.
	# The Accessibility "Heartbeat" toggle silences JUST this pulse (the sfx bus is untouched), read live.
	var hb_intensity := 0.0
	if heartbeat_start_frac > 0.0 and Settings.heartbeat_enabled:
		hb_intensity = clampf((heartbeat_start_frac - frac) / heartbeat_start_frac, 0.0, 1.0)
	if hb_intensity <= 0.05 or hp <= 0:
		_heartbeat_timer = 0.0  # reset so the first beat fires immediately when HP next drops low
		return
	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0:
		_heartbeat_timer = lerpf(heartbeat_interval_slow, heartbeat_interval_fast, hb_intensity)
		if _heartbeat and _heartbeat.stream:
			_heartbeat.volume_db = lerpf(heartbeat_db_min, heartbeat_db_max, hb_intensity)
			_heartbeat.pitch_scale = 1.0  # natural pitch — the real asset already sounds like a heartbeat
			_heartbeat.play()

## Punchy "got hit" feedback — forwards to the HurtFeedback component (the slow-mo + screen-drain +
## bus muffle). Called from take_damage on a non-lethal hit. Off-tree (_hurt null) this no-ops, matching
## the monolith (FreezeFrame/tween/bus writes are skipped when the component never built).
func _on_head_crippled(_attacker: Node = null) -> void:
	_trigger_hurt()  # locational head cripple — pulse the hurt feedback so a concussion reads on screen
	notify_toast(PlayerText.head_crippled(), GameSettings.player_feedback.cripple_toast_color)

var _last_sneak_toast_msec: int = -100000

## Quicksave (F5) / quickload (F9) — the immersive-sim core loop (ML-1). Polled here so it only fires during
## live gameplay (a Player exists); suppressed during a conversation and while ANY overlay is up (a station
## screen, Inventory/Loot/Stats/Options/name-entry — none of them pauses the tree, so _physics_process keeps
## running and without this gate F9 would reload the scene out from under an open backpack). Quicksave
## snapshots the run + your position; quickload reloads the scene and the fresh Player re-applies the saved build.
func _update_save_input() -> void:
	if InputManager.gameplay_suppressed():
		return  # don't quicksave/quickload under an open menu / cutscene / name box (T1)
	if Input.is_action_just_pressed("Quicksave"):
		# quicksave() returns true ONLY when the file actually persisted; a failed write (disk full / permission)
		# now toasts the failure instead of a false "Quicksaved". (We're always in-tree here, so false == write error.)
		if GameState.quicksave(self):
			# Same HEAVY-commit class as a slot write (save_load_screen._do_save) — a hotkey, so there is no
			# button click to collide with. Gated on the write; the failure branch takes the DENIAL, because a
			# corner toast is the wrong channel for "your run is not on disk" — the player's eyes are on the
			# world, not the HUD, exactly when they press F5.
			MenuStyle.play_commit()
			notify_toast(PlayerText.TOAST_QUICKSAVED, Color.WHITE)
		else:
			MenuStyle.play_denied()
			notify_toast(PlayerText.TOAST_QUICKSAVE_FAILED, Color(1.0, 0.5, 0.4))
	elif Input.is_action_just_pressed("Quickload"):
		if GameState.has_quicksave():
			_force_release_carried_prop()
			# Same sweep the death path runs: the spray colour picker is Attack's own child UI, invisible to
			# InputManager.close_all_modals (which _load_and_reload calls) — the reload frees it with the scene,
			# but sweeping FIRST restores the captured cursor before the fresh scene grabs the mouse. INSIDE the
			# has_quicksave gate so an F9 with no file on disk stays a true no-op (no phantom picker dismissal).
			_close_open_modals()
		# Reloads the scene on success; no toast — the reload IS the feedback. The commit cue is the audible
		# half of that. An F9 with no file on disk is no longer a SILENT no-op: it carries no toast at all (the
		# reload was supposed to be the feedback and there is no reload), so the denial is its only possible
		# answer — otherwise the key reads as unbound. Safe to fire here: _close_open_modals' sweep already
		# dropped MenuStyle's quiet latch, the reload is deferred, and MenuStyle's players are autoload-owned so
		# the cue rings across the scene swap.
		if GameState.quickload():
			MenuStyle.play_commit()
		else:
			MenuStyle.play_denied()

func _force_release_carried_prop() -> void:
	if head != null and head.pickup_ray != null:
		head.pickup_ray.force_release_held()

## Death carry-teardown: a prop PULLED FROM THE BAG (hotbar hold, _held_inv_item set) is STASHED back into the
## backpack — not dropped — so the death-milestone autosave (wallet bequeath / respawn) persists the item WITH the
## profile. Dropping it clears the reservation and the item lives only as a non-persisted world prop → lost on the
## next load. stash_held_item() re-adds the SAME instance, then releases + frees the world copy; if the bag is full
## it REFUSES (keeps holding), and held_inventory_item() staying non-null makes the save-fold capture it instead —
## either way the item survives. A plain aimed grab (no _held_inv_item) still force-releases into the world as before.
## Called from die() BEFORE set_physics_process(false)/HUD-hide, so inventory is valid and stash's add fires the
## changed→_queue_autosave that folds the item into the save.
func _release_or_stash_carried_prop() -> void:
	if _held_inv_item != null:
		stash_held_item()
	else:
		_force_release_carried_prop()

## The physics prop the player is CURRENTLY carrying (PickupRay.held_object), or null when empty-handed.
## PetInteraction and ClaimInteraction both read this to refuse petting/claiming an object you're holding (it's at
## arm's length, so the aim ray hits it — but you can't pet/claim what's in your hands).
func held_prop() -> Node:
	if head != null and head.pickup_ray != null:
		return head.pickup_ray.held_object
	return null

## True when a holster should read as a peaceful stand-down. Carrying a throwable forcibly holsters the weapon,
## but that is not surrender; it is just trading the gun for whatever is in your hands.
func should_holster_deescalate() -> bool:
	return not _carrying and held_prop() == null

## The BACKPACK item currently pulled into your hands via the hotbar (or null). Read by the hotbar to RESERVE +
## highlight the slot the prop came from, and by the save to fold the in-hand item back into the snapshot.
func held_inventory_item() -> Item:
	return _held_inv_item

## HOTBAR "hold" action (Hotbar._activate on a holdable slot): pull `item` OUT of the backpack and carry it in
## your hands as a physics prop, or — if that SAME item is the one already held from the bag — STASH it back.
## Mirrors the weapon slot's equip/unequip toggle for props like the dog / crate. Returns true when it acted (so
## the hotbar refreshes its slot highlight). Pressing a DIFFERENT holdable slot while holding one puts the current
## prop away first, then pulls the new one.
func hold_item(item: Item) -> bool:
	if item == null or inventory == null:
		return false
	if _held_inv_item == item:
		return stash_held_item()  # toggle off: same item -> put it back in the bag
	if _held_inv_item != null and not stash_held_item():
		return false  # holding a DIFFERENT bag prop and it wouldn't put away — don't pull a second
	return _pull_and_hold(item)

## Build `item`'s world prop, take the item out of the bag, and grab the prop hands-free. Refuses (leaving the bag
## untouched) when the hands are already full of a NON-hotbar prop, the carry ray is missing, or the built prop has
## no Throwable to carry. The prop is built BEFORE the bag is touched so a malformed prop can't lose the item.
func _pull_and_hold(item: Item) -> bool:
	if not inventory.has(item):
		return false
	var ray: PickupRay = head.pickup_ray if head != null else null
	if ray == null or ray.held_object != null or ray.hold_anchor == null:
		return false  # need a free carry ray with a hold anchor
	var world := get_parent()
	if world == null:
		return false
	var prop := WorldItem.build(item, 1)
	var throwable := _find_throwable(prop)
	if throwable == null:
		prop.queue_free()  # nothing carriable inside — abort without touching the bag
		return false
	# Commit. Reserve the item as held FIRST so the inventory.changed that `remove` fires keeps the hotbar slot
	# (Hotbar._sync_slots skips the reserved item); then take it out, add the prop, and grab it AT the hold anchor
	# so PickupRay's grace ease-in has almost no distance to close.
	_held_inv_item = item
	_held_inv_prop = prop
	# Shield the prop from destruction while it's in your hands (it blocks incoming fire at arm's length; a 1-HP
	# destructible holdable would otherwise be shot out of your grasp and the bag item lost). Restored on release.
	_held_inv_throwable = throwable
	_held_inv_prev_destructible = throwable.destructible
	throwable.destructible = false
	inventory.remove(item, 1)
	world.add_child(prop)
	prop.global_position = ray.hold_anchor.global_position
	ray.carry(throwable)
	return true

## Put the currently-held backpack prop back into the bag: re-add the SAME item instance the pull removed, then
## release + free the world prop. A prop that came out of your HOLSTER (the H verb — _held_from_weapon_slot) is
## also RE-WIELDED at the end, so "put it back" means back in your hands, not merely back in the bag. No-op when
## not holding a bag prop. Returns true when it put something away, false when the bag can't take it back (a full
## grid) — the prop then stays IN HAND (still reserved + save-reachable).
func stash_held_item() -> bool:
	if _held_inv_item == null:
		return false
	var item := _held_inv_item
	var rewield := _held_from_weapon_slot  # captured before the clears below; drives the re-draw AFTER the release
	# Refuse if the bag can't take it back (a full Tetris grid — loot picked up while carrying filled the footprint
	# the pull freed). Clearing the reservation then would orphan the item from BOTH the bag and the save fold, and a
	# left-in-world prop isn't persisted — so keep holding it instead (mirrors CanPickUp refusing a pickup into a full
	# bag). Checked BEFORE we touch any state, so a refused stash leaves _held_inv_item set and the item never lost.
	if not inventory.can_accept(item):
		notify_toast(PlayerText.TOAST_BACKPACK_FULL, Color(0.85, 0.85, 0.85))
		return false
	var prop := _held_inv_prop
	# Decide the rewield NOW and arm the fists suppression BEFORE the release below: force_release's synchronous
	# holster restore fires holster_changed while the combat inventory still reads FISTS (the real weapon is only
	# re-equipped at the end), and without _rewield_in_flight that refresh raises the bare fists over the
	# weapon's re-draw (see FirstPersonBody._unarmed_hands_wanted). Mid-death stays unarmed — the equip is skipped there.
	var rewield_now := rewield and item.is_weapon() and not _dying and not _dead
	_rewield_in_flight = rewield_now
	# Clear the reservation FIRST so the carry_changed(false) that force_release fires below is treated as our
	# put-back, not a drop (see _on_carry_changed), and so held_inventory_item() reads null for the concurrent save.
	_restore_held_prop_destructible()  # back to its authored destructibility before it re-enters the bag
	_held_inv_item = null
	_held_inv_prop = null
	_held_from_weapon_slot = false
	# Re-add the SAME instance BEFORE releasing the prop. The add's bag-change re-fills the reserved hotbar slot while
	# the item is genuinely back in the bag (can_accept above guaranteed room, so it fits); if we released first, that
	# release's sync would briefly see the item neither in-bag nor reserved and vacate the slot. The window between add
	# and free runs only synchronous signal handlers (no spawns), so the item is never both in-bag AND a live world
	# prop across a frame boundary. Spray-paint / other state applied to the prop WHILE held isn't re-captured onto the
	# item here (the pull-time size / coat / befriend it already carries are preserved) — a fidelity gap only vs. the
	# drop-then-E-stash path.
	inventory.add(item, 1)
	if head != null and head.pickup_ray != null and head.pickup_ray.held_object != null:
		head.pickup_ray.force_release_held()  # let the ray restore the prop's physics bookkeeping
	if is_instance_valid(prop):
		prop.queue_free()  # it's back in the bag now — remove the world copy
	# H TOGGLE, second stage: the weapon came out of your holster, so put it back THERE too — bagging it silently
	# would leave you on bare fists (the pull cleared equipped_item -> equipped_item_lost -> FISTS). Deliberately
	# LAST, after the force_release above: carrying LOCKS the weapon away (Attack.draw_locked) and set_holstered
	# refuses to bring it out while locked, so equipping any earlier would swap the knife in behind a locked
	# holster — visible in hand but unable to fire. Skipped mid-death (die() stashes a carried prop before the
	# keel-over): the equip DRAWS the weapon, which would pop it up over the death cinematic exactly like the
	# holster restore _on_carry_changed already suppresses. The respawn re-applies the save's equip anyway.
	if rewield_now:
		inventory.equip_item(item)
	# Suppression over: the equip request is out, and from here the backpack's equipped_item (set optimistically
	# by equip_item, even when the swap QUEUES) keeps FirstPersonBody._unarmed_hands_wanted() false until the weapon is truly up.
	_rewield_in_flight = false
	return true

## Restore the currently-held prop's `destructible` flag (shielded to false on the pull) and forget the throwable ref.
## Guarded so a freed prop is a harmless no-op. Called on every carry-end path (stash + drop/throw) before the
## reservation clears, so a released prop is destructible again and no dangling Throwable ref lingers.
func _restore_held_prop_destructible() -> void:
	if is_instance_valid(_held_inv_throwable):
		_held_inv_throwable.destructible = _held_inv_prev_destructible
	_held_inv_throwable = null

## The Throwable to carry inside a freshly built world prop: the node itself when it IS one (dog.tscn roots a
## Throwable), else the first Throwable descendant (a wrapper prop like dogcrate.tscn nests one). null if none.
func _find_throwable(node: Node) -> Throwable:
	if node is Throwable:
		return node as Throwable
	for n in node.find_children("*", "", true, false):
		if n is Throwable:
			return n as Throwable
	return null

## Push a one-off HUD toast (top-left) via the UI layer. Player-facing notifications (sneak result, limb
## cripples, ...) route through here. No-op off-tree (no UI).
func notify_toast(text: String, color: Color) -> void:
	if ui:
		ui.push_toast(text, color)

func show_holster_forgiveness_tutorial(force: bool = false) -> bool:
	if not force and GameState.holster_forgiveness_tutorial_seen():
		return false
	var key := InputManager.get_action_binding(InputManager.action_reload)
	notify_toast(PlayerText.holster_forgiveness_tutorial(key), HOLSTER_FORGIVENESS_TUTORIAL_COLOR)
	if not force:
		GameState.mark_holster_forgiveness_tutorial_seen()
	return true

func _consume_pending_holster_forgiveness_tutorial() -> void:
	if GameState.consume_holster_forgiveness_tutorial_reminder():
		show_holster_forgiveness_tutorial(true)

## Toast a SUCCESSFUL sneak attack (target was off-guard); a normal hit shows nothing. Throttled by
## GameSettings.player_feedback.sneak_toast_cooldown_ms so a burst / multi-pellet shot shows ONE line.
## Called per player hit on a Character from attack.gd.
func notify_sneak_result(was_sneak: bool) -> void:
	if not was_sneak:
		return  # only a successful sneak is worth a toast — a normal hit says nothing
	var now := Time.get_ticks_msec()
	if now - _last_sneak_toast_msec < GameSettings.player_feedback.sneak_toast_cooldown_ms:
		return
	_last_sneak_toast_msec = now
	notify_toast(PlayerText.TOAST_SNEAK_ATTACK, GameSettings.player_feedback.sneak_toast_color)

var _look_text: String = ""         ## last readout label pushed to the HUD (guards the per-frame refresh)
var _look_col: Color = Color.WHITE   ## last readout colour pushed to the HUD

## Drive the FNV-style look-at hover readout when the looked-at target CHANGES: fire the one-shot NPC
## greeting (once per look), then show its name on the HUD. `handler` is the talk handler under the
## crosshair (Talkable / DialogueNPC), or null when looking at nothing. Called by the interaction ray when
## the target changes; refresh_look_readout handles same-target label changes (e.g. crouching to pickpocket).
func on_look_target_changed(handler: Node) -> void:
	if handler != null and handler.has_method(&"host_npc"):
		var npc: NPC = handler.host_npc()
		if npc != null:
			npc.greet()  # FNV-style hover greeting (cooldown-gated, non-hostile/idle only) — once per look
	_apply_look_readout(handler)

## Refresh the readout label for the SAME target (NO greeting) so it reacts to state that changes WITHOUT
## the target changing — e.g. crouching turns a name into a "Pick Pocket <name>" prompt. Called every frame
## the crosshair stays on a target; the change-guard in _apply_look_readout keeps it cheap.
func refresh_look_readout(handler: Node) -> void:
	_apply_look_readout(handler)

## Drop the player straight down onto the floor beneath the current position, so a (re)spawn starts standing on
## the ground instead of falling in from a marker floating above it. Raycasts DOWN from just above the origin
## along the player's own collision mask (what it stands on), excluding itself, and offsets the body so the
## collision capsule's FEET rest on the hit. Returns true only when it actually landed a floor — the retry
## loop in _physics_process keeps calling until then (or the budget runs out on a genuine void/pit spawn).
const GROUND_SNAP_START_UP := 1.0    ## start the ray this far ABOVE the origin, to clear a spawn that sits slightly in the floor
const GROUND_SNAP_MAX_DROP := 200.0  ## how far down to search for a floor
func _snap_to_ground() -> bool:
	if not snap_to_ground_on_spawn or not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var from := global_position + Vector3.UP * GROUND_SNAP_START_UP
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * GROUND_SNAP_MAX_DROP)
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask  # the layers the player stands on (the world/floor), same as move_and_slide uses
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	# Feet, in the (upright) body's local frame: the capsule centre minus half its height. Works whether the body
	# origin sits at the feet or the centre — either way this lands the capsule bottom exactly on the hit surface.
	var feet_local := 0.0
	if player_collision_shape != null and player_collision_shape.shape is CapsuleShape3D:
		var cap := player_collision_shape.shape as CapsuleShape3D
		feet_local = player_collision_shape.position.y - cap.height * 0.5
	var hit_pos: Vector3 = hit["position"]
	global_position.y = hit_pos.y - feet_local
	velocity.y = 0.0  # don't carry a spawn-drop velocity into the landing
	return true

## Compute + push the look-at label/tint for `handler` (null clears it): the name (tinted green for a
## friendly NPC, prefixed "Pick Pocket" when you're crouched behind an off-guard NPC via look_name_for).
## Guards on the last shown text + colour so a per-frame refresh only touches the HUD when something changed.
func _apply_look_readout(handler: Node) -> void:
	if _dying or _hud_quiet:
		handler = null  # a dying/dead player reads NOTHING — else the last-looked enemy's name freezes on the death HUD and rides into the respawn (the interaction ray can also keep firing this during the cinematic); quiet = the revive window, where a name popping over the fade-up is the same noise
	var label := ""
	var col := Color(0.92, 0.92, 0.95)  # neutral / inanimate default
	if handler != null and handler.has_method(&"look_name"):
		label = handler.look_name_for(self) if handler.has_method(&"look_name_for") else handler.look_name()
		var npc: NPC = handler.host_npc() if handler.has_method(&"host_npc") else null
		if npc != null:
			# Ally (companion) -> blue; else friendly green / hostile red; else keep the neutral default.
			col = CBPalette.disposition_color(npc.is_following(), npc.resolved_disposition(), col)
		# Key-hint prefix ("[E] Talk to Kyle" / "[Z] Pick Up"): the action's CURRENT binding, read live from
		# the InputMap so a rebind shows immediately. A Throwable is carried with the THROW key (its own,
		# unique input — E would stash a dual item into the backpack instead); anything else interacts with
		# PickUp, hinted only when it can actually be acted on RIGHT NOW (a hostile NPC's bare name gets no
		# key — pressing E at it would do nothing).
		if handler is Throwable:
			label = "[%s] %s" % [InputManager.get_action_binding(InputManager.action_throw), label]
		elif TalkHelpers.is_talkable_now(handler) or TalkHelpers.is_pickpocketable_now(handler, self):
			label = "[%s] %s" % [InputManager.get_action_binding(InputManager.action_pickup), label]
	if label == _look_text and col == _look_col:
		return
	_look_text = label
	_look_col = col
	if ui:
		ui.set_look_name(label, col)

func _trigger_hurt() -> void:
	if _hurt:
		_hurt.trigger()

## Air-dash recharge cue: a quick white screen-flash (via PlayerHud) + a chirp the instant the dash is
## available again (fired from Attack.air_dash_recharged on landing).
func _on_air_dash_recharged() -> void:
	if _hud:
		_hud.flash_dash()
	if air_dash_recharge_sfx:
		AudioManager.play_2d_sfx(air_dash_recharge_sfx)

const EDGE_MIN_SPEED: float = 0.2         ## below this gap-ward speed there's nothing meaningful to brake — skip the probe

## Quake-style edge friction — makes it harder to slide off a ledge. Detect whether the player is
## hanging over a ledge in `gap_dir` (a horizontal, normalized velocity-ward direction) and, if so,
## return the EXTRA friction lerp applied to the gap-ward velocity component this frame; 0.0 when not
## near an edge (caller then leaves movement unchanged). The probe math lives in MovementHelpers (and
## carries the EDGE_PROBE_AHEAD / EDGE_FLOOR_PROBE / EDGE_DROP_TOLERANCE / EDGE_FRICTION_MULT tuning);
## this thin wrapper keeps the call site in _physics_process unchanged.
func _edge_friction_t(gap_dir: Vector3, t_ground: float) -> float:
	return MovementHelpers.extra_brake_t(self, gap_dir, t_ground)

# The riser-climb probe consts (clearance / forward-probe / angled-probe / riser-normal / riser-dot) now live on
# Locomotor — the Player delegates the step-up kinematics to Locomotor.compute_step_up/compute_step_down (one shared
# algorithm). Only these two remain Player-side: STEP_MIN_DELTA gates the camera-ease no-op, STEP_UPWARD_VELOCITY_EPS
# gates the "don't step while rising" check in the move step.
const STEP_MIN_DELTA: float = 0.015
const STEP_UPWARD_VELOCITY_EPS: float = 0.01
const STEP_INPUT_INTENT_MIN: float = 0.1
const STEP_MAX_BLAST_TO_WALK_RATIO: float = 1.25
const STEP_MAX_WALKING_BLAST_Y: float = 1.5
const STEP_LAUNCH_ASSIST_BLOCK_TIME: float = 0.35

## Player-only stair assist for brush/TrenchBroom stairs. Before the normal slide,
## probe up-forward-down candidates from the grounded pose; a shallow-angle riser hit
## gets a tiny normal-directed nudge so diagonal approaches can still find the tread.
## The post-slide down pass catches descending treads.
func apply_velocity() -> void:
	if not _has_live_physics_space():
		return
	floor_snap_length = maxf(0.0, GameSettings.player_movement.step_down_snap)
	var walk_velocity := velocity
	velocity += explosion_velocity
	var pre_move_velocity := velocity
	var start_transform := global_transform
	var was_grounded := is_on_floor()
	var delta := get_physics_process_delta_time()
	var can_step := was_grounded and _can_use_step_assist(walk_velocity) \
			and not is_climbing() and not is_grappling()
	var moved_with_slide := true
	if can_step and _try_step_up(start_transform, walk_velocity, delta):
		moved_with_slide = false
	else:
		move_and_slide()
		if can_step and not _try_step_up(global_transform, walk_velocity, delta):
			_try_step_down(walk_velocity)
	if moved_with_slide:
		_push_interactables(pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor

func _can_use_step_assist(walk_velocity: Vector3) -> bool:
	if walk_velocity.y > STEP_UPWARD_VELOCITY_EPS:
		return false
	var horizontal_velocity := Vector3(walk_velocity.x, 0.0, walk_velocity.z)
	if horizontal_velocity.length() < GameSettings.player_movement.step_min_horizontal_speed:
		return false
	if _step_assist_launch_block_timer > 0.0:
		return false
	if explosion_velocity.length() <= GameSettings.physics_damage.blast_min_magnitude:
		return true
	if explosion_velocity.y > STEP_MAX_WALKING_BLAST_Y:
		return false
	if input_dir.length() <= STEP_INPUT_INTENT_MIN:
		return false
	var blast_horizontal := Vector3(explosion_velocity.x, 0.0, explosion_velocity.z)
	return blast_horizontal.length() <= horizontal_velocity.length() * STEP_MAX_BLAST_TO_WALK_RATIO

## Riser step-up: a THIN wrapper over the SHARED host-agnostic kinematics (Locomotor.compute_step_up) — the SAME algorithm
## the NPC Locomotor runs (const-identical), so a riser-climb fix reaches both instead of drifting between two copies. The
## Player adds only its own concerns: the climb/grapple guard (those drivers own the vertical) and easing the CAMERA over
## the body's instant snap. Tuning is sourced from GameSettings (the designer surface); the clamp keeps the former defensive behaviour.
func _try_step_up(start_transform: Transform3D, pre_move_velocity: Vector3, delta: float) -> bool:
	if is_climbing() or is_grappling():
		return false
	var max_step := maxf(0.0, GameSettings.player_movement.step_up_height)
	var down_snap := maxf(0.0, GameSettings.player_movement.step_down_snap)
	var step_delta := Locomotor.compute_step_up(self, start_transform, pre_move_velocity, delta, max_step, down_snap)
	if step_delta < 0.0:
		return false
	_smooth_camera_step(step_delta)  # ease the VIEW over the body's instant riser snap (see CameraEffects.step_smooth)
	return true

## Descending-tread catch: a thin wrapper over the shared Locomotor.compute_step_down. The Player adds the climb/grapple
## guard and eases the camera DOWN over the drop; the shared core owns the is_on_floor / rising / speed / snap checks.
func _try_step_down(pre_move_velocity: Vector3) -> bool:
	if is_climbing() or is_grappling():
		return false
	var down_snap := maxf(0.0, GameSettings.player_movement.step_down_snap)
	var min_speed: float = GameSettings.player_movement.step_min_horizontal_speed
	var travel_y := Locomotor.compute_step_down(self, pre_move_velocity, down_snap, min_speed)
	if travel_y >= 0.0:
		return false
	_smooth_camera_step(travel_y)  # travel_y is negative (descending) — the view eases DOWN over the drop
	return true

## Feed the camera the body's INSTANT vertical jump from an auto-step (up or down a riser) so it can smooth the
## view over it (CameraEffects.step_smooth). Below STEP_MIN_DELTA there's nothing worth easing. Null-guarded:
## off-tree (a unit test with no _enter_tree) has no resolved camera, so this stays a no-op there.
func _smooth_camera_step(step_delta_y: float) -> void:
	if absf(step_delta_y) <= STEP_MIN_DELTA or camera_effects == null:
		return
	camera_effects.step_smooth(step_delta_y)

func _physics_process(delta: float) -> void:
	_update_sprint_lockout(delta)
	# Frozen during a conversation (cinematic, like the NPC) so the player can't move OR fall —
	# they hold in place while the world keeps running. The camera-focus + NPC-turn tweens still
	# animate, since those run on the SceneTree rather than in this _physics_process.
	if DialogueManager.is_active():
		velocity = Vector3.ZERO
		input_dir = Vector2.ZERO  # also zero input so CameraEffects reads no stale strafe (FOV kick / tilt)
		_continuous_fall_time = 0.0
		_update_stamina_recovery(delta)
		return
	if _ground_snap_frames_left > 0:
		_ground_snap_frames_left -= 1  # retry each frame until a floor is under us (the initial-spawn level loads deferred), then stop
		if _snap_to_ground():
			_ground_snap_frames_left = 0
	coyote_time.tick(delta)
	gravity(delta)
	_update_night_vision(delta)
	_update_save_input()
	_update_low_hp(delta)

	input_dir = Input.get_vector("left", "right", "forward", "backward")
	if InputManager.gameplay_suppressed():
		# ⭐A modal is open: stand idle but keep gravity + stay vulnerable (Dark Souls). This gate is now the ONLY
		# thing holding the player still inside a menu — since 2026-08-09 no modal pauses the tree, so the shop /
		# heal / atm / chess screens reach here for real instead of being covered by a freeze (it used to be
		# belt-and-braces for those). Losing it would let the player walk away mid-transaction.
		input_dir = Vector2.ZERO
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var bhop_engaged: bool = false
	var jumped_now := false
	if coyote_time.can_jump() and jump_buffer.wants_jump() and not InputManager.gameplay_suppressed() \
			and spend_stamina(GameSettings.player_movement.stamina_jump_cost):
		# Heavier = lower hop (gradual), instead of the old hard "can't jump while over-encumbered" block.
		# AGILITY springs you higher (jump_mult), the same stat that makes you faster on foot.
		velocity.y = GameSettings.player_movement.jump_velocity * encumbrance_jump_multiplier() * stats_or_default().jump_mult(status_stat_modifier(&"agility"))
		# one-shot through AudioManager (self-freeing); play_sfx no-ops on a null stream
		AudioManager.play_sfx(global_position, jump_sound, jump_sound_volume_db)
		spawn_dust(GameSettings.effects.dust_jump_intensity)
		coyote_time.consume()
		jump_buffer.consume()
		jumped_now = true
		# Slide-jump: if sliding, fling forward scaled by slide speed via the decaying blast impulse and end the
		# slide (the Slide ability owns the launch math). No-op when not sliding / no Slide ability.
		if _slide != null:
			_slide.jump_launch()
		# Over-encumbered (backpack OVER carry_capacity): jumping still works — just the lowered hop above —
		# but you're too loaded to build bhop momentum, so no speed boost. Break any live chain so dropping
		# the load later doesn't resume a stale boost; you must re-earn it once back under capacity.
		if is_encumbered():
			bunnyhop.break_chain()
		else:
			bhop_engaged = bunnyhop.try_engage(input_dir != Vector2.ZERO)

	# Variable jump height: a tap gives a low hop, a hold rides the full arc. Normally we cut the rising
	# velocity on the jump's RELEASE (the elif). But a buffer-queued jump fires on LANDING, by which point
	# a TAP's release has already passed — so just_released never catches it and the tap would rocket to
	# full height. Fix: on the exact frame the jump fires, decide by whether the key is still HELD; not
	# held means it was a tap (buffered OR same-frame), so cut immediately. The elif covers held-then-let-go.
	# The if/elif are mutually exclusive so a same-frame grounded tap can't get cut twice.
	if jumped_now:
		if not Input.is_action_pressed("jump"):
			velocity.y *= jump_cut_factor
	elif Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut_factor

	if _wants_sprint(input_dir):
		_drain_sprint_stamina(delta)

	# The per-frame speed multiplier chain (direction, crouch, slow-walk, scope, a drawn heavy weapon, crippled legs,
	# encumbrance, AGILITY, slow/haste status) is extracted VERBATIM into GroundMovement (M13) — same order, same
	# value. The interleaved jump / bhop / blast-jump / slide / grapple / edge-friction beats below stay on the root.
	target_speed = GroundMovement.compute_target_speed(self, input_dir)

	var ground_ratio := GameSettings.player_movement.smoothing
	var air_ratio := GameSettings.player_movement.smoothing / GameSettings.player_movement.air_smoothing_divisor
	var fps_factor := delta * GameSettings.player_movement.smoothing_reference_fps
	var t_ground := 1.0 - pow(1.0 - ground_ratio, fps_factor)
	var t_air := 1.0 - pow(1.0 - air_ratio, fps_factor)
	if _slide != null and _slide.is_active():
		_slide.update_movement(delta, direction)  # the slide replaces normal ground control while active
	elif is_on_floor():
		if direction:
			current_speed = lerpf(current_speed, target_speed, t_ground)
		else:
			current_speed = lerpf(current_speed, 0.0, t_ground)
		velocity.x = lerpf(velocity.x, direction.x * current_speed, t_ground)
		velocity.z = lerpf(velocity.z, direction.z * current_speed, t_ground)
		# Quake edge friction: if we're sliding toward a ledge, brake the gap-ward velocity
		# component extra hard so you stick to the surface instead of skating off. Only kicks in
		# while actually moving toward an unsupported edge (the probe); flat ground is unchanged.
		var horiz := Vector3(velocity.x, 0.0, velocity.z)
		var horiz_speed := horiz.length()
		if horiz_speed > EDGE_MIN_SPEED:
			var gap_dir := horiz / horiz_speed
			var edge_t := _edge_friction_t(gap_dir, t_ground)
			if edge_t > 0.0:
				# Bleed the gap-ward speed toward zero by the extra friction lerp (the probe ray runs
				# along this same direction, so the whole horizontal velocity is heading off the ledge).
				var along := horiz.dot(gap_dir)
				var braked := lerpf(along, 0.0, edge_t)
				velocity.x += gap_dir.x * (braked - along)
				velocity.z += gap_dir.z * (braked - along)
				current_speed = lerpf(current_speed, 0.0, edge_t)
		camera_effects.bob(velocity)
	else:
		velocity.x = lerpf(velocity.x, direction.x * current_speed, t_air)
		velocity.z = lerpf(velocity.z, direction.z * current_speed, t_air)

	if bhop_engaged:
		var bhop_speed := bunnyhop.get_target_speed()
		velocity.x = direction.x * bhop_speed
		velocity.z = direction.z * bhop_speed
		current_speed = bhop_speed

	if _step_assist_launch_block_timer > 0.0:
		_step_assist_launch_block_timer = maxf(0.0, _step_assist_launch_block_timer - delta)
	apply_blast()

	# Wall climb: the WallClimb ability owns the grip + climb logic (same spot in the step, same operations).
	# Absent / disabled -> no climb. Drives velocity directly + the camera bob; is_climbing() reads its state.
	if _wall_climb != null:
		_wall_climb.tick(delta, direction)

	# Swing the blob shadow onto the wall while climbing, back to the ground otherwise.
	_update_wall_shadow(delta)
	# ...and pitch the first-person legs onto the wall too, so they plant against it instead of dangling.
	# HOST-called on purpose (the FirstPersonBody does not tick this itself): it must run AFTER
	# _update_wall_shadow wrote _shadow_wall_blend this frame, and it must FREEZE with the death cinematic —
	# die()'s set_physics_process(false) stops this beat with the rest of the step, where a component
	# _physics_process would keep pitching the legs through the keel-over.
	if fp_body != null:
		fp_body.update_leg_wall_pose()

	# Grapple yank — overrides the velocity we just built from input/gravity, before the move. The Grapple
	# ability owns the hook; absent = no grapple at all.
	if _grapple_ability != null:
		_grapple_ability.apply_pull(delta)

	var pre_landing_velocity := velocity.y
	var pre_velocity := velocity

	apply_velocity()

	# Body-impact reactions (ram damage / air thump / pinball bounce) run AFTER the move on the
	# PRE-move velocity — see RamReactor. Off-tree (_ram_reactor null) they're skipped, as in a test.
	if _ram_reactor:
		_ram_reactor.tick(delta, pre_velocity)

	# Touchdown: the whole burst (camera/gun/shake/HUD dip, land SFX, dust, slide start, fall damage) is the
	# Landing component's — see scripts/player/landing.gd. It reads the PRE-move velocity because the move
	# zeroes velocity.y on contact.
	if is_on_floor() and !_was_on_floor and landing != null:
		landing.on_land(pre_landing_velocity, pre_velocity)

	if _update_continuous_fall_death(delta):
		return

	_was_on_floor = is_on_floor()
	if _was_on_floor:
		_last_grounded_position = global_position  # the fall-death purse anchor — see _death_purse_anchor
		_has_last_grounded = true
	_update_stamina_recovery(delta)

	# Footstep cadence + its crouch/speed dB cuts — Landing owns the timer and the interval. `target_speed` sets
	# the stride rate, so the cadence quickens with the speed this frame is chasing.
	if landing != null:
		landing.tick_footsteps(delta, target_speed)

	_update_falling_air(delta)
	_update_noise(delta)
	_update_stealth_hud(delta)
	_update_crosshair()
	_check_aim_remark(delta)  # #3: comment if the player is aiming at a friendly/ally
	# (The slide-wind volume fade moved into the Slide ability node's own _physics_process.)


## How far the player's noise currently carries — forwards to the NoiseEmitter component, which writes
## our noise_radius (the value enemy Perception.can_hear() reads). Off-tree (_noise null) this no-ops;
## noise_radius then stays at its 0.0 init, matching a freshly built bare instance.
func _update_noise(delta: float) -> void:
	if _noise:
		_noise.tick(delta)

## Drive the Fallout-style stealth readout: aggregate how aware nearby NPCs are of US (the real player) and
## forward the level + whether we're sneaking (crouched) to the HUD. No-op without a HUD (off-tree).
func _update_stealth_hud(delta: float) -> void:
	# Gate on _dying like _apply_look_readout does: die() runs SYNCHRONOUSLY (a fall-damage kill fires it from
	# _apply_fall_damage earlier in this very _physics_process), so without this guard execution would fall back
	# through to here and RE-SHOW the [ DANGER ] label the same frame die()'s hide_hud_for_death() just hid it,
	# leaving it stuck on the death cinematic. Cleared on the in-place revive (_respawn_at_checkpoint) — but
	# _hud_quiet then holds the readout off through the revive's quiet window: set_stealth_level re-asserts the
	# label's visibility EVERY frame, so without this second gate a killer still searching the checkpoint would
	# pop [ CAUTION ] over the still-black screen on the fresh life's first physics frame.
	if not _hud or _dying or _hud_quiet or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	# Throttle the heavy full-NPC awareness scan to ~10x/sec; reuse the cached snapshot on the in-between
	# frames so the HUD still updates every frame (cheap re-push) without re-scanning every NPC each frame.
	_stealth_hud_accum -= delta
	if _stealth_hud_accum <= 0.0 or _stealth_hud_snap.is_empty():
		_stealth_hud_accum = _STEALTH_HUD_INTERVAL
		# of_player now returns {level, meter, spotter}; the HUD label still consumes the level (the detection
		# bar off `meter` is the next slice). Extract level here so behaviour is unchanged.
		_stealth_hud_snap = StealthStatus.of_player(self, tree.get_nodes_in_group(Groups.NPC))
	_hud.set_stealth_level(_stealth_hud_snap[&"level"], is_crouching())
	_hud.set_detection_meter(_stealth_hud_snap[&"meter"], is_crouching())

## Keep the crosshair pinned to SCREEN CENTRE — a fixed reticle (Deus Ex). It deliberately does
## NOT track the shot: the swaying LASER DOT (flash_light, aimed along get_aim_direction) is what shows where
## a shot will truly land — drifting wide on the move, settling back toward centre as you stand still. Re-set
## each frame so a viewport resize keeps it centred. No-op without a HUD.
func _update_crosshair() -> void:
	if ui == null or not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	ui.set_crosshair_screen_pos(viewport.get_visible_rect().size * 0.5)


## (The slide state machine — try_start / update_movement / jump_launch / end — moved into the Slide ability
## node, scripts/components/abilities/slide.gd. The Player calls those hooks at the beats above.)


func _update_falling_air(delta: float) -> void:
	if not is_instance_valid(falling_air_sfx):
		return
	# Wind swell from vertical speed in EITHER direction: the terminal-velocity rush
	# of a fall, but ALSO rocketing UP (blast-launch / rocket-jump). Reuses the same
	# fall-speed thresholds — a normal jump (~4.5 m/s) barely clears the min so it
	# stays near-silent, while a fast launch roars.
	var vertical_speed: float = absf(velocity.y)
	var fall_span := GameSettings.audio.falling_air_max_fall_speed - GameSettings.audio.falling_air_min_fall_speed
	var t_fall := 0.0
	if fall_span > 0.0:
		t_fall = clampf((vertical_speed - GameSettings.audio.falling_air_min_fall_speed) / fall_span, 0.0, 1.0)
	# Same swell from raw horizontal speed, so blitzing around (bhop / dash /
	# blast launch) rushes like a fall too. Skipped while sliding, which drives
	# its own looping wind player (_slide_sfx) and would otherwise double up.
	var t_move := 0.0
	if not is_sliding():
		var move_speed := Vector2(velocity.x, velocity.z).length()
		var move_span := GameSettings.audio.falling_air_max_move_speed - GameSettings.audio.falling_air_min_move_speed
		if move_span > 0.0:
			t_move = clampf((move_speed - GameSettings.audio.falling_air_min_move_speed) / move_span, 0.0, 1.0)
	var t := maxf(t_fall, t_move)
	var target_db := lerpf(GameSettings.audio.falling_air_min_db, GameSettings.audio.falling_air_max_db, t)
	# play()/stop() are only legal once the audio node is in the scene tree. Keep the
	# speed intensity math usable for bare Player instances and miswired scenes.
	if falling_air_sfx.is_inside_tree():
		if t > GameSettings.audio.falling_air_audible_t:
			if not falling_air_sfx.playing and falling_air_sfx.stream:
				falling_air_sfx.play()
		elif falling_air_sfx.playing and is_on_floor():
			falling_air_sfx.stop()
	var smooth := 1.0 - exp(-GameSettings.audio.falling_air_fade_rate * delta)
	falling_air_sfx.volume_db = lerpf(falling_air_sfx.volume_db, target_db, smooth)
	# Drive the speed vignette (PlayerHud) off the SAME speed intensity, smoothed the same way, so the
	# white air-streaks swell and fade in lockstep with the wind.
	if _hud:
		_hud.drive_speed_lines(t, smooth)


func _on_mouse_input_rotate(_amt: Vector2) -> void:
	rotate_y(_amt.y)

## Floor-ish surface-normal cutoff for the pinball bounce (kept here: a unit test reads it off a bare
## instance). RamReactor references it as Player.RAM_BOUNCE_FLOOR_DOT.
const RAM_BOUNCE_FLOOR_DOT: float = 0.7

## Pinball-style rebound facade — the body lives in RamReactor (and is driven from its tick alongside
## the ram-damage + air-thump checks). Kept as a NAMED method on the Player so the smoke suite's source
## grep for "func _check_bounce" still finds it; off-tree (_ram_reactor null) it no-ops as before.
func _check_bounce(delta: float, pre_velocity: Vector3) -> void:
	if _ram_reactor:
		_ram_reactor._check_bounce(delta, pre_velocity)

func on_nearby_death(distance: float) -> void:
	# No nearby-death juice while WE are the one dying (or fading back in): a posthumous kill — our grenade /
	# a burn tick felling someone mid-cinematic — would otherwise wobble the keeled-over camera, rumble the pad,
	# and (worst) FreezeFrame's recovery would ease Engine.time_scale back to 1.0, silently cancelling the death
	# slow-mo after phase 1 stops re-stamping it. The splatter blobs it spawns also outlive the black (their fade
	# tween runs on the slowed clock) and would pop with the restored HUD. The quiet window gets the same calm.
	if _dying or _hud_quiet:
		return
	if distance <= GameSettings.screen_shake.death_shake_range:
		FreezeFrame.freeze(0.01, 0.1, 0.02)
	if distance <= GameSettings.effects.blood_splatter_range and ui and ui.blood_splatter:
		var splat_t := 1.0 - clampf(distance / GameSettings.effects.blood_splatter_range, 0.0, 1.0)
		ui.blood_splatter.splash(splat_t)
	if distance <= GameSettings.screen_shake.death_shake_range and screen_shake:
		var shake_t := 1.0 - clampf(distance / GameSettings.screen_shake.death_shake_range, 0.0, 1.0)
		screen_shake.shake(shake_t * GameSettings.screen_shake.death_shake_amount)

## Death cinematic (Player): on death the world eases into slow-mo while the camera rolls onto its side
## (keeling over), a black vignette CLOSES over the frame and all audio fades out together; on full black
## the death card ("You were killed by <name>. They were using a <weapon>.") fades in, holds, then fades
## out; a beat later the world fades back up and you respawn. Every timing/feel number (sequence time,
## slow-mo target, camera roll, card fade/hold, the spawn fade-up) is a designer knob on
## GameSettings.player_feedback; the card LINES + fallbacks live there too.
var _dying: bool = false
var _death_cam_base_z: float = 0.0       ## camera roll at the instant death starts; the keel-over adds onto it
var _death_card: Label = null            ## the death card, created lazily over the black hold (ML-2)
var _death_card_text: String = ""        ## the death card's line, composed in die() from the killer + weapon (the attacker can free before the card shows)
var _death_card_override_text: String = ""
var _has_death_card_override: bool = false
var _death_wallet_lost: float = 0.0      ## zorkmids the last death actually moved out of the wallet (_bequeath_wallet / _spill_death_purse); the in-place revive toasts it once then clears it. A full-reload death takes nothing and rebuilds a fresh Player anyway, so it never shows there.
## WHO took it, resolved to a display STRING at the moment of death — the killer node can be freed by a rival or
## leashed home by NpcHomeReturn during the seconds-long cinematic, so holding the node would read wrong (or crash)
## by the time the revive toasts.
var _death_wallet_killer_name: String = ""
## ...and the actual BRANCH the settlement took, because a display string is never a behaviour key (CLAUDE.md).
## The name above can legitimately come back EMPTY — a designer may blank PlayerFeedbackSettings.death_unknown_killer,
## and an NPC ships with a blank display_name — and switching the toast on "" would then tell the player their purse
## is lying on the ground while it is really in a killer's pocket. This flag is the switch; the name is only wording.
var _death_wallet_to_killer: bool = false
## True when the death we're currently playing out was dealt by a hostile NPC, so the respawn should stand every
## PROVOKED NPC back down (see _on_killed_by / _settle_provoked_grudges). The VERDICT is banked at death because the
## killer can die or be leashed home during the cinematic; the sweep spends it once on the revive, like _death_wallet_lost.
var _death_settlement_pending: bool = false
## True through the revive's quiet window (the first respawn_hud_delay seconds of the fade-up): the HUD is
## still hidden and every per-frame HUD readout that gates on _dying gates on this too (_update_stealth_hud,
## _apply_look_readout, the takedown/pet/claim cue facades) — else the stealth badge / prompts would pop over
## the still-black screen the instant _dying clears, which is exactly the flash the window exists to remove.
var _hud_quiet: bool = false
## The quiet window's wall-clock timer; killed + flushed by a re-death inside the window (see die()).
var _respawn_hud_tween: Tween = null
# NOTE: the death cinematic's audio state (the fade reference + the revive fade tween) deliberately does NOT
# live here — DeathMix owns it, because the same object owns the death sting those levels are making room for.
const HOLSTER_FORGIVENESS_TUTORIAL_COLOR := Color(0.85, 0.95, 1.0)

func take_damage(amount: float, was_crit: bool = false, attacker: Node = null, hit_pos: Vector3 = Vector3.INF) -> void:
	if _dying:
		return
	# Cinematic damage immunity (F-C34): a control-locked player takes NO damage from any vector — hazard, DoT,
	# and NPC fire all route through this single override. A cutscene deliberately does NOT pause the tree (staged
	# actors keep moving), so immunity rides the predicate rather than the pause; a full conversation already pauses
	# the tree, but this additionally covers the ~0.5s unpaused dialogue-intro beat an enemy could shoot through (C66).
	# A cutscene that WANTS to script player damage must use a dedicated kill path, not incidental take_damage.
	if InputManager.world_frozen():
		return
	note_combat()  # taking fire is combat — keep the weapon up
	# Match Character.take_damage's signature (GDScript requires overrides to match the parent) and
	# forward hit_pos so the player's own locational/limb damage + crippling apply.
	super.take_damage(amount, was_crit, attacker, hit_pos)
	if _hud:
		_hud.flash_hurt()  # whole-screen red flash on every hit (lethal too — reads as the killing blow)
	if not _dying:
		_trigger_hurt()

## Ping the SINGLE aim radial toward `world_pos` (the shooter) when we actually take a hit — forwards
## to PlayerHud (see PlayerHud.indicate_damage_from for why this fills the post-shot gap). Kept as a
## NAME here because attack.gd flashes the directional arc via player.indicate_damage_from. Off-tree
## (_hud null) it no-ops, as the monolith did when its overlays never built.
func indicate_damage_from(world_pos: Vector3, source: Object = null) -> void:
	if _hud:
		_hud.indicate_damage_from(world_pos, source)

## Show the red "being aimed at" radial + distant-sniper glint toward `source` — forwards to PlayerHud.
## Kept as a NAME here because the enemy aim telegraph calls player.indicate_aimed_from.
func indicate_aimed_from(source: Object, world_pos: Vector3, charge: float, damage: float = 0.0, warning: bool = false, clear_shot: bool = true) -> void:
	note_combat()  # an enemy is drawing a bead on us — that's combat, keep the gun up
	if _hud:
		_hud.indicate_aimed_from(source, world_pos, charge, damage, warning, clear_shot)

## The player's hit-confirm "ding" + crosshair hitmarker — the body lives in PlayerHud. These consts
## stay on the Player because PlayerHud references them as Player.HIT_SFX / Player.HEADSHOT_PITCH_MULT.
## HIT_SFX is a dedicated 2D hitsound SEPARATE from the weapons' impact sounds; it fires only via
## on_dealt_hit — which is a no-op on the Character BASE (character.gd), so an NPC wielder inherits
## silence and an NPC-vs-NPC trade can never proc the player's hitsound.
const HIT_SFX: AudioStream = preload("uid://budx7vymim0j0")
## Headshot drops the ding's pitch DOWN (deeper, meatier) rather than up — sub-1.0 factor.
const HEADSHOT_PITCH_MULT := 0.7

## Flash the crosshair hitmarker AND play the hit-confirm ding — forwards to PlayerHud. Kept as a NAME
## here because a landed shot/explosion calls player.on_dealt_hit. Off-tree (_hud null) it no-ops.
func on_dealt_hit(headshot := false, hp_frac := 1.0) -> void:
	# Dead men score no hits: ordnance still in flight when we died (a grenade, a burn tick) can land during the
	# death cinematic, and the kill branch below pops the WHOLE SKY (StarSky is world-rendered — hide_hud_for_death
	# can't touch it) over the closing vignette, plus the hit ding under the ducked mix. Gate on _dying only, NOT
	# _hud_quiet: during the revive's quiet window the player is alive and shooting, and the ding is the one piece
	# of hit feedback that still works while the HUD visuals wait out the window.
	if _dying:
		return
	if _hud:
		_hud.on_dealt_hit(headshot, hp_frac)
	if hp_frac <= 0.0:
		StarSky.flash_kill()  # pop the whole authored sky for a beat (StarSky paints every WorldEnvironment, so it always fires)
		if _hud:
			_hud.flash_kill()  # screen-space colour pop -> the kill flash shows over the authored skybox too

## Slice 6b: forward the takedown prompt + hold-progress cue to PlayerHud. Driven every frame by SilentTakedown:
## `active` shows "[key] Take Down <name>" with the hold fill, inactive hides it. Off-tree (_hud null) it no-ops.
func set_takedown_cue(active: bool, text: String, progress: float) -> void:
	# The interaction drivers (SilentTakedown / PetInteraction / ClaimInteraction) are SEPARATE nodes that keep
	# ticking through the death cinematic and the revive's quiet window, re-asserting their cue every frame —
	# so the hide in die() alone can't keep a prompt down. Force the cue inactive at this ONE forwarding seam
	# (all three facades share the gate) while _dying or _hud_quiet; the driver's next frame re-shows it.
	if _hud:
		_hud.set_takedown_cue(active and not _dying and not _hud_quiet, text, progress)

## Forward the PET prompt + hold-progress cue to PlayerHud. Driven every frame by PetInteraction: `active` shows
## "[key] Pet <name>" with the hold fill, inactive hides it. Off-tree (_hud null) it no-ops. Mirrors set_takedown_cue.
func set_pet_cue(active: bool, text: String, progress: float) -> void:
	if _hud:
		_hud.set_pet_cue(active and not _dying and not _hud_quiet, text, progress)  # death/quiet gate: see set_takedown_cue

## Forward the CLAIM/UNCLAIM prompt cue to PlayerHud. Driven every frame by ClaimInteraction: `active` shows
## "[key] Claim <name>" (tap, progress 0 → no bar) or "[key] Hold to Unclaim <name>" (hold, progress fills the bar).
## Off-tree (_hud null) it no-ops.
func set_claim_cue(active: bool, text: String, progress: float = 0.0) -> void:
	if _hud:
		_hud.set_claim_cue(active and not _dying and not _hud_quiet, text, progress)  # death/quiet gate: see set_takedown_cue

## Raise the top-centre enemy health bar for whoever we just damaged, showing their HP AFTER the hit.
## Pushed by Character.take_damage on the VICTIM's side (it notifies its attacker duck-typed — see the
## on_damaged_target notify there), so this ONE entry point covers every attributed damage path at once:
## hitscan pellets and melee, fired rounds, explosions, thrown props and thrown weapons, the pinball ram,
## and a silent takedown. Ambient damage (hazard zones, status DoT, fall) carries no attacker and correctly
## never reaches here.
##
## Gated on _dying for exactly the reason _apply_look_readout is (see its comment): die() runs SYNCHRONOUSLY
## from inside _physics_process on a fall-damage kill, so a hit resolved later in that same frame would
## re-raise the bar right after die() cleared it and strand it on the death cinematic — where
## ui.hide_hud_for_death() would then remember it and restore it stale onto the fresh life.
## Off-tree (_hud null) it no-ops.
## `hp_before` is the target's HP an instant earlier — it drives the bar's chip shard, and defaults to
## "unknown" (a flat trail) so an off-tree/legacy 3-arg call still works.
func on_damaged_target(target: Node, hp: float, max_hp: float, hp_before: float = -1.0) -> void:
	if _dying or _hud == null:
		return
	_hud.show_enemy_health(target, hp, max_hp, hp_before)

## DEATH MOVES YOUR ZORKMIDS — it never destroys them. GameSettings.economy.death_purse_loss_fraction (1.0 = all of
## it, by default) leaves your pocket and goes to exactly ONE of two recoverable places:
##   * KILLED BY SOMEONE -> the killer pockets the whole purse into their live wallet, which NpcMortality reads at
##     their death and LootableCorpse.setup mints as a real zorkmids coin tile in their loot bag. Kill them, loot it
##     back. (They keep it while alive, so a pickpocket works too — see _settle_provoked_grudges.)
##   * KILLED BY NOTHING (a fall, a hazard, your own grenade, anyone _resolve_killer won't credit) -> it SPILLS on
##     the ground as a physics MoneyBag at the spot you died. Walk back and Interact to pocket the lot.
## A RELOAD_* death mode — or CHECKPOINT_RESPAWN with no respawn set, which falls back to a full reload — takes
## NOTHING at all: the world is about to be rebuilt, so neither a killer nor a dropped bag would survive to hold it,
## and the save restores this wallet anyway. Debiting there is money burnt for nobody, and worse, add_money's
## autosave flush would write the emptied wallet to the very file RELOAD_LAST_SAVE then reads back. So
## _death_revives_in_place() gates the WHOLE settlement, not just the hand-off (it used to gate only the latter).
## The AMOUNT and the KILLER'S NAME are banked for the revive toast; the killer NODE deliberately is not — it can be
## freed by a rival or leashed home by NpcHomeReturn during the seconds-long death cinematic.
func _bequeath_wallet(killer: Node) -> void:
	if is_instance_valid(killer) and killer.has_method(&"should_remind_holster_forgiveness_tutorial_on_player_death") \
			and killer.call(&"should_remind_holster_forgiveness_tutorial_on_player_death"):
		GameState.queue_holster_forgiveness_tutorial_reminder()
	_death_wallet_lost = 0.0          # nothing settled yet; each branch below banks its own toast amount
	_death_wallet_killer_name = ""
	_death_wallet_to_killer = false
	if not _death_revives_in_place():
		return
	var lost := _death_wallet_loss()
	if lost <= 0.0:
		return
	# has_method, not `is Character`: the killer is loosely typed here (a test double, a titled hazard), exactly as
	# _resolve_killer's own reward_kill duck-test treats it.
	if is_instance_valid(killer) and killer.has_method(&"add_money") and _killer_can_hold_purse(killer):
		add_money(-lost)          # routes through the money seam -> HUD -N + autosave
		killer.add_money(lost)    # ...straight into their wallet, which rides into their corpse's loot bag
		_death_wallet_lost = lost
		_death_wallet_to_killer = true
		_death_wallet_killer_name = _killer_display_name(killer,
			GameSettings.player_feedback.death_unknown_killer,
			GameSettings.player_feedback.death_stranger_killer)
		return
	if not GameSettings.economy.death_purse_drops_when_unclaimed:
		return
	var anchor: Variant = _death_purse_anchor()
	if anchor == null:
		return  # nowhere safe to put it (off-tree, or a void with no anchor at all) -> you keep it, see _death_purse_anchor
	# DEFERRED, and the wallet is debited over THERE, not here. Two reasons this can't spawn the bag inline:
	# (1) we are commonly inside a physics contact callback (Character.take_damage <- Throwable / ExplosionArea), where
	#     add_child'ing a RigidBody3D writes physics state mid-flush; (2) _begin_death() -> gore() is about to fire the
	# gib burst from this very origin, and a bag already sitting there gets punted by it. The deferred call lands at
	# the end of this frame — after gore() and die(), before the next physics step. We are still in the tree then:
	# Player.die() plays a cinematic instead of freeing, and the respawn teleport is seconds away.
	_spill_death_purse.call_deferred(lost, anchor)

## True while `killer` is still a wallet the player could actually come and take the purse back from. A DEAD killer
## is not: its corpse loot bag was already minted from `money` at the instant it died (NpcMortality.drop_loot /
## GoreSpawner._attach_loot), so anything paid in afterwards is unreachable — and a pooled body stays
## is_instance_valid forever after death, until acquire() re-stamps its authored wallet and the money is simply gone.
## That is reachable without pooling too: kill a raider, then fall off a ledge within kill_credit_window_ms and
## _resolve_killer hands that same corpse straight back as your killer. Refusing here drops us through to the ground
## spill, which is exactly right — nobody alive killed you.
## Duck-typed with ABSENCE MEANING ALIVE: every Character has is_alive(), but a titled hazard or a test double that
## exposes only add_money has no death state to be wrong about, so it stays eligible.
func _killer_can_hold_purse(killer: Object) -> bool:
	if not killer.has_method(&"is_alive"):
		return true
	return bool(killer.call(&"is_alive"))

func _death_wallet_loss() -> float:
	var wallet := maxf(0.0, money)
	var fraction := clampf(GameSettings.economy.death_purse_loss_fraction, 0.0, 1.0)
	return minf(wallet, snappedf(wallet * fraction, Zorkmids.QUANTUM))

## Where a killer-less death should rest the spilled purse — or null when there is nowhere, in which case we do NOT
## take the money at all. A ladder, most-faithful-to-"where you died" first:
##   1. the everyday feet-forward drop point, IF its short probe actually found floor (a normal on-foot death);
##   2. a DEEP probe straight down from the death spot (death_purse_drop_ground_probe) — catches dying on a catwalk
##      or roof, and the long fall that kills you in mid-air but still over real geometry;
##   3. the last ground we saw you stand on — for a fall that is the ledge you walked off, i.e. the one place a
##      player actually thinks to look;
##   4. the checkpoint you are about to respawn at (death_purse_drop_to_respawn_in_void).
## Why the ladder exists at all: this project has NO kill plane (only the player has a fall-death guard), so a bag
## spawned over a bottomless void falls forever — the money is destroyed AND an immortal RigidBody leaks into the
## sim. Refusing to drop is the strictly better bottom rung. Returns Variant (Vector3 or null); off-tree it returns
## null before touching the physics space, so a bare unit-test Player never errors and never gets debited.
func _death_purse_anchor() -> Variant:
	if not is_inside_tree() or get_parent() == null:
		return null
	# PHYSICS-FRAME GATE on the two ray probes — caution, not a hard engine rule. A hazard zone (hazard_zone.gd)
	# and a bleed/poison tick (status_effect_manager.gd) both deal their damage from _process — IDLE time — and an
	# ambient hazard passes a null attacker, so those are among the commonest deaths reaching this ground-spill
	# branch. Idle-frame space queries are not flat-out refused (the gun's hitscan fires from _process via
	# MouseInput and demonstrably hits), but this project has also shipped an idle-frame probe that returned EMPTY
	# with no error (the thrown-knife pin kill — fixed by probing at strike time), so a result here can't be
	# trusted off-physics. Skipping the probes costs nothing: a hazard or a DoT kills you standing on the floor —
	# the last-grounded rung below IS the spot you died. Shots, blasts, thrown props and the fall death all resolve
	# in physics and still get the probes.
	if Engine.is_in_physics_frame():
		var space := get_world_3d().direct_space_state
		var hit := space.intersect_ray(_drop_probe_ray(_drop_probe_origin(), DROP_PROBE_DEPTH))
		if not hit.is_empty():
			return hit["position"] + DROP_PROBE_LIFT
		var deep: float = GameSettings.economy.death_purse_drop_ground_probe
		if deep > 0.0:
			hit = space.intersect_ray(_drop_probe_ray(global_position, deep))
			if not hit.is_empty():
				return hit["position"] + DROP_PROBE_LIFT
	if _has_last_grounded:
		return _last_grounded_position + DROP_PROBE_LIFT
	if GameSettings.economy.death_purse_drop_to_respawn_in_void and GameState.has_respawn:
		return GameState.respawn_position + DROP_PROBE_LIFT
	return null

## Deferred half of the unclaimed-death spill (see _bequeath_wallet). Debits ONLY once the bag is genuinely in the
## tree, so a world that vanished between the death frame and this flush can never swallow the money — and
## _death_wallet_lost (which unlocks the revive toast) is banked here for the same reason: the toast must never
## claim a loss that did not happen.
## KNOWN LIMIT, shared with the killer branch: the debit autosaves (add_money is a save milestone) but the BAG does
## not persist — it is a dynamic spawn in neither save tier (see WorldSnapshot's roadmap), exactly like every other
## loot drop. So a quicksave/level-change/quit before the player walks back destroys the purse. Fixing it properly
## means persisting money bags (and NPC wallets, for the other branch), which is a save-format change, not a patch
## here. Until then this is a same-session errand — the AUTHORING_GUIDE Death callout says so in as many words.
func _spill_death_purse(amount: float, anchor: Vector3) -> void:
	var world := get_parent()
	if not is_inside_tree() or world == null:
		return
	_place_money_bag(world, amount, anchor)
	add_money(-amount)
	_death_wallet_lost = amount

## DEATH SETTLES A PROVOKED GRUDGE — half one: JUDGE it, here at the moment of death, and remember the verdict.
## An NPC that turned on us only because we PROVOKED it (a neutral we shot at, FNV-style) has just killed us, so
## the score is even. The rule itself (killer must be a live, hostile NPC; GameSettings.npc_ai.deaggro_on_player_death)
## lives in HostilityHelpers.death_settles_grudges; the actual stand-down waits for the respawn, in
## _settle_provoked_grudges().
##
## The VERDICT is stored, not the killer node: the death cinematic runs for seconds, in which our killer can be shot
## by a rival, despawn, or be leashed home and stood down by NpcHomeReturn — reading `is_hostile()` off it later
## would flip the answer (or dereference a freed body). Judging while it is guaranteed live keeps the outcome the
## one the player actually earned. Mirrors _death_wallet_lost: recorded at death, spent once on the revive.
##
## WHY A HOOK AND NOT A DROP-IN ON GameState.player_died (the seam NpcHomeReturn uses): this rule needs to know WHO
## killed us, and that signal is zero-arg — widening it would break every existing zero-arg handler at emit. So it
## rides the same killer-aware Character hook _bequeath_wallet does, which is also the closest precedent (a global,
## one-shot, killer-aware death reaction).
func _on_killed_by(killer: Node) -> void:
	# OR, never overwrite: the revive's quiet window DEFERS the settlement (~respawn_hud_delay), so a rapid
	# re-death can bank its verdict while the previous one is still unspent — and a non-hostile second death
	# (a fall) must not erase it. Before the window existed the pending flag was always consumed pre-re-death,
	# so plain assignment and this OR were indistinguishable; the sweep itself is group-wide + idempotent,
	# so settling "twice as one" on the next revive is exactly right.
	_death_settlement_pending = _death_settlement_pending or HostilityHelpers.death_settles_grudges(killer)

## DEATH SETTLES A PROVOKED GRUDGE — half two: APPLY it, on the respawn. Every NPC still hostile ONLY because we
## provoked it stands back down and the exact rep each provoke took is restored (the sweep is group-wide because
## that rep is a shared faction pool — see HostilityHelpers.settle_provoked_grudges). Consumes the verdict, so it
## fires exactly once per death.
##
## ON THE RESPAWN, not at death, deliberately: the world should visibly calm down for a player who is there to see
## it, not behind a fade-to-black — and the reputation toast the restored rep pushes would otherwise be swallowed by
## die()'s hide_hud_for_death(), exactly like the death wallet toast was (hence the call site next to it, AFTER
## restore_hud_after_death()). Without any of this, a town whose one-shot holster pardon is already spent stays
## hostile forever and every retry re-provokes it. Genuinely-hostile factions were never provoked, so raiders keep
## hunting us. Note the killer KEEPS the bequeathed wallet — now your WHOLE purse — even after standing down: with
## them non-hostile again you get it back by pickpocketing, or by re-provoking them (which costs the pardon), or by
## killing them anyway and looting the corpse. Hunting your killer is a choice, not a war.
##
## The RELOAD_* death modes call it too, right BEFORE reload_current_scene(): the fresh world spawns unprovoked
## NPCs, but Reputation is an autoload that survives the reload, so the provoke deltas have to be reversed while the
## NPCs holding them still exist — otherwise a faction soured below hostile_threshold by a provoke can never recover.
func _settle_provoked_grudges() -> void:
	if not _death_settlement_pending:
		return
	_death_settlement_pending = false
	if not is_inside_tree():
		return
	HostilityHelpers.settle_provoked_grudges(get_tree().get_nodes_in_group(Groups.NPC))

## True when dying RIGHT NOW would revive us in place (world untouched) — the only death mode where the killer
## still exists afterwards to hunt down. A RELOAD_* mode rebuilds the world from scratch; CHECKPOINT_RESPAWN
## (default) also needs a set respawn point, else it falls back to a full reload. Mirrors the branch in
## _on_death_sequence_done so the wallet transfer and the actual respawn always agree.
func _death_revives_in_place() -> bool:
	var mode: int = GameSettings.player_feedback.death_mode
	return mode != PlayerFeedbackSettings.DeathMode.RELOAD_LAST_SAVE \
		and mode != PlayerFeedbackSettings.DeathMode.RELOAD_CHECKPOINT_FRESH \
		and GameState.has_respawn

## Character seam: tag everything OUR death burst spawns as player gore, so the checkpoint revive can undo the
## whole thing in one sweep (_respawn_at_checkpoint -> clear_death_gore). The player is the one actor whose death
## is REVERSED — CHECKPOINT_RESPAWN brings it back in a world that is otherwise left exactly as it was — so it is
## the one actor whose remains must not outlive it. NPCs return &"" and their gore stays where it fell forever.
func death_gore_group() -> StringName:
	return Groups.PLAYER_GORE

func die() -> void:
	if _dying:
		return
	_dying = true
	# Killed again INSIDE the previous revive's quiet window (a camper at the checkpoint): flush the deferred
	# HUD restore FIRST, before this death's hide_hud_for_death() snapshot — hiding over a half-hidden HUD
	# would strand nodes invisible on every later life. Receipts stay banked for the next revive (see the
	# deliver_receipts notes on _finish_respawn_hud_restore).
	if _hud_quiet:
		_finish_respawn_hud_restore(false)
	# Dying MID-CONVERSATION (shot during the dialogue's unpaused intro beat, where we're frozen on
	# is_active and can't dodge): hard-end the dialogue FIRST — once its box opens it pauses the tree,
	# which would freeze our node-bound death tween under an open conversation. Mirrors the dialogue's
	# own speaker-died teardown, from our side.
	# is_ENGAGED, not is_active: a conversation SUSPENDED behind a sub-menu (Trade / Heal / Level Up / Install /
	# Exchange Gear) reads is_active()==false, so gating on is_active() skipped the abort — then _close_open_modals()
	# below closes the sub-menu, whose `closed` fired _resume_from_menu, re-pausing the tree + re-opening the box
	# over the death cinematic (menus/cursor/pause corrupted; the death tween frozen). is_engaged() covers the
	# suspended case; abort() -> _finish() clears _suspended, so the subsequent sub-menu close is a clean no-op.
	if DialogueManager.is_engaged():
		DialogueManager.abort()
	# Slam any open modal shut so the cinematic plays clean and the respawn doesn't sit under stale UI
	# (EVERY registered modal is real-time — dialogue owns the only tree-pause left — so the world keeps
	# running under any of them and dying with one open is perfectly reachable, not a corner case).
	_close_open_modals()
	# Carry-teardown that PRESERVES a bag-pulled prop: a hotbar-held item is stashed back into the bag (folded into the
	# death-milestone autosave) rather than dropped into the non-persisted world — see _release_or_stash_carried_prop.
	_release_or_stash_carried_prop()
	# Drop the grapple (no slingshot): dying mid-swing otherwise leaves the rope attached through the
	# cinematic and spanning the respawn teleport (the hook's _process keeps running — physics-off doesn't
	# stop it). The rope visibly retracts as you keel over instead.
	if _grapple_ability != null:
		_grapple_ability.detach()
	# Clear any in-progress hurt feedback so the ducked master bus doesn't bleed into the scene
	# reload — the bus is global, a reload won't reset it, and the next life would read it as base.
	if _hurt:
		_hurt.clear()
	# Neutralize bullet time so it stops writing Engine.time_scale: the death cinematic owns the slow-mo
	# now (its own ignore-time-scale tween), and an active air-scoped bullet time would otherwise keep
	# lerping the global time_scale every frame, fighting the death dilation. reset() forces it READY and
	# drops ownership WITHOUT touching Engine.time_scale (the death tween owns that).
	if bullet_time != null:
		bullet_time.reset()
	# Restore the scope music duck: dying while scoped (ADS) would otherwise leave the music bus ducked
	# into the next life (the bus is global; a reload won't reset it). Resets the bus to its pre-duck dB.
	if _scope != null:
		_scope.reset()
	# Same problem, the conversation's twin of it: the abort() above ends the dialogue with a 0.4 s music-bus
	# restore FADE, which would still be running as the cinematic's world duck starts writing that same bus
	# every frame. Settle it instantly so the mix has exactly one owner from here on.
	DialogueManager.reset_music_duck()
	died.emit()
	# NOTE: the world-reset cue (GameState.player_died) is deliberately NOT emitted here — it fires later, from
	# _on_death_screen_covered(), once the cinematic's vignette has closed to full black. See that method.
	# Freeze the player but keep effects (gore particles, blood, sound) running so the death is visible
	# through the cinematic before the scene reloads.
	set_physics_process(false)
	# Lock the player out + clear the HUD for a clean death cinematic: hide the extraneous UI (crosshair /
	# health / hotbar / notifications), and kill the look + auto-fire input (mouse_input drives both; the rest
	# of the input gates on _dead). CRITICAL: hide the HUD *elements*, NOT the whole `ui` CanvasLayer — the
	# death drain / closing vignette / fade is a post-process ShaderMaterial on `ui`'s ColorRect (and the death
	# card mounts on that same layer), so `ui.visible = false` would hide the ENTIRE cinematic. That was the
	# long-standing "death just snap-cuts, no fade" bug. hide_hud_for_death() spares the ColorRect.
	_apply_look_readout(null)  # clear the FNV look-at name FIRST (it's frozen showing whatever you last aimed at) so hide_hud_for_death() doesn't remember it visible and restore the stale name on the revive
	# Drop the cached stealth snapshot too, not just the label: the throttle in _update_stealth_hud re-pushes
	# the CACHED level whenever _stealth_hud_accum hasn't expired, so a stale combat snapshot would flash the
	# pre-death [ DANGER ] at full brightness for up to _STEALTH_HUD_INTERVAL on the fresh life's first un-gated
	# frame — before the 10Hz rescan replaces it with the post-leash truth. Empty snap = that first frame rescans.
	_stealth_hud_snap = {}
	_stealth_hud_accum = 0.0
	if _hud != null:
		# Force off every per-frame-driven HUD readout BEFORE hide_hud_for_death() records the visible set, so none
		# of them is remembered -> restored stale onto the fresh life (the look-at clear above does this for its name):
		_hud.clear_stealth_readout()   # the [ DANGER ]/[ CAUTION ] stealth label + detection bar
		_hud.clear_interaction_cues()  # the [key] Take Down / Pet / Claim prompts + their hold bars (driven by separate interaction nodes)
		_hud.clear_enemy_health()      # the top-centre enemy HP bar (self-expiring, but a trade where we kill and die together lands a final push at this exact instant)
		_hud.drive_speed_lines(0.0, 1.0)  # snap the speed/fall vignette to 0 so a fast/fall death doesn't freeze it high and flash it on the revive
	if ui != null:
		ui.hide_hud_for_death()
	if mouse_input != null:
		mouse_input.set_process(false)
		mouse_input.set_process_unhandled_input(false)
	# Hide your own first-person BODY (legs + bare fists) and freeze the crouch driver for the death cinematic.
	# The legs (the FirstPersonBody's body-awareness rig) would otherwise hang in view as the camera keels
	# over; and the Crouch node runs its OWN _physics_process, which the player's set_physics_process(false)
	# above does NOT stop — so without this it keeps reading the Crouch action, letting a dead player still
	# duck the camera/capsule. The FISTS need their own beat because the COMPONENT's _process is deliberately
	# left RUNNING here (set_physics_process(false) freezes only the PLAYER's physics step — a child's idle
	# processing is untouched; it keeps driving the FP arm bob + torso, and the stow slide below needs the
	# frame): _unarmed_hands_wanted() already answers false the instant `_dying` is up, but nothing RE-ASKS
	# it — so without this refresh the raised guard stayed on screen breathing through the whole cinematic.
	# The refresh drives the normal stow slide; a carry release earlier in die() has already hidden the same
	# rig instantly, which settles the latch, so this is then a no-op. All three are restored by the in-place
	# revive (_respawn_at_checkpoint); a full reload (RELOAD_* death modes) rebuilds a fresh Player instead.
	if fp_body != null:
		fp_body.set_legs_visible(false)
		fp_body.refresh_unarmed_hands()
	if crouch != null:
		crouch.set_physics_process(false)
	# Kill all residual motion so a death taken mid-launch (rocket-jump, explosion knock, melee-dash, ram)
	# doesn't linger on the frozen corpse — and, above all, doesn't survive the in-place revive. `velocity`
	# is the controller motion; `explosion_velocity` is the decaying blast impulse Character.apply_velocity
	# re-adds each physics frame. Both are re-zeroed on the revive too, because an Area3D/raycast hit can
	# still STACK explosion_velocity onto us during the cinematic (physics-off stops US moving, not other
	# bodies from touching us) — leaving it would fling the fresh life the instant physics comes back.
	velocity = Vector3.ZERO
	explosion_velocity = Vector3.ZERO
	# Compose the death card NOW, while the killer is still a live node (it can die / despawn during the
	# ~cinematic, so we can't read its name/weapon later in _show_death_card).
	_death_card_text = _compose_death_message()
	_clear_death_card_override()
	_run_death_sequence()

## Build the death-card line from the most-recent attributed attacker (_credit_attacker, set by
## Character.take_damage). An attributed killer with a known weapon → "killed by NAME. using a WEAPON.";
## killer only → "killed by NAME."; no attributed killer (a fall, a stray blast, self-inflicted) → the
## generic death_message. All three lines + the unknown-name fallback are designer knobs on player_feedback.
func _compose_death_message() -> String:
	var fb := GameSettings.player_feedback
	if _has_death_card_override:
		return _death_card_override_text
	var killer: Object = _credit_attacker
	if not is_instance_valid(killer) or killer == self:
		return fb.death_message
	var kname := _killer_display_name(killer, fb.death_unknown_killer, fb.death_stranger_killer)
	var wname := _killer_weapon_name(killer)
	if wname != "":
		return fb.death_message_killed_by_weapon % [kname, wname]
	return fb.death_message_killed_by % kname

func _clear_death_card_override() -> void:
	_has_death_card_override = false
	_death_card_override_text = ""

## The killer's human-facing name (NPC.display_name / NpcData.display_name), or `fallback` when blank —
## the same field the takedown prompt reads. Duck-typed (.get) since the attacker is loosely typed.
## `stranger_fallback` replaces the "Stranger until introduced" mask for this SENTENCE context: the
## proper-noun placeholder reads wrong mid-line ("killed by Stranger"), so the death card uses the
## indefinite form ("killed by a stranger"). Label contexts (hover, corpse, loot title) keep "Stranger".
func _killer_display_name(killer: Object, fallback: String, stranger_fallback: String) -> String:
	var raw: Variant = killer.get(&"display_name")
	if raw is String and not (raw as String).is_empty():
		# Mask until introduced — but ONLY for a real character killer (an NPC has resolved_disposition,
		# the same "is a person" gate the dialogue label uses). A non-NPC named killer (a titled hazard) shows as-is.
		if killer.has_method(&"resolved_disposition"):
			var shown: String = GameState.public_name(raw)
			# shown != raw keeps an NPC literally NAMED "Stranger" reading as-is instead of swapping.
			if shown == PlayerText.STRANGER and shown != raw:
				return stranger_fallback
			return shown
		return raw
	return fallback

## The killer's equipped-weapon label, read from the SAME source the UI's equipped marker reads — the drawn
## Item's label() off the killer's CharacterInventory BACKPACK (character.inventory.equipped_item). NOT the
## Weapon hub's Inventory (weapon_system.inventory): that one holds only equipped_weapon: WeaponData, and
## WeaponData carries no name. So this stays single-source-of-truth for the weapon name. "" when the killer
## is unarmed / holstered / not a Character, so the caller drops the weapon clause. Fully duck-typed + guarded.
func _killer_weapon_name(killer: Object) -> String:
	var inv: Variant = killer.get(&"inventory")          # the CharacterInventory backpack (Character.inventory), not the weapon hub
	if inv == null:
		return ""
	var item: Variant = inv.get(&"equipped_item")        # the drawn Item instance (set by equip_item / _ensure_armed_from_backpack)
	if item is Item:
		return (item as Item).label()
	return ""

## Close every modal overlay that's open. Called on death (play the cinematic clean) and again on respawn (a
## modal can be OPENED mid-cinematic — the screens process input regardless of our death). Delegates to the ONE
## registry-driven sweep (InputManager.close_all_modals), so a newly-registered screen is covered automatically —
## this list used to be hand-maintained and repeatedly missed the newest screen (QuestJournal, ChipInstall, Chess,
## and the NameEntry box). InputManager.close_all_modals also closes the real-time name-entry box (T1).
## ONE deliberate extra rides along below: the spray can's colour picker — a weapon-owned overlay, not a
## registered screen, so the registry sweep can't see it.
func _close_open_modals() -> void:
	InputManager.close_all_modals()
	# The spray can's colour picker is NOT a registry modal — it's Attack's own child UI (SprayPainter, opened
	# by right-click while the can is drawn) — so the sweep above misses it and it used to survive death,
	# floating over the cinematic with a freed cursor. Dismiss it through the same Attack facade the
	# weapon-swap / holster dismissals use; its close() recaptures the mouse (dialogue-guarded, and die()
	# aborts any conversation before sweeping), which is exactly what clears that floating cursor.
	if weapon_system != null and weapon_system.attack != null:
		weapon_system.attack._close_color_picker()

## The player-death cinematic: ease into slow-mo, slowly roll the camera onto its side (keeling over) as
## the screen drains to black & white and fades to black, hold a beat on black, then reload. Driven by ONE
## tween in WALL-CLOCK time (ignore_time_scale) so it finishes on schedule even as it slows the world;
## _death_step maps the tween's 0..1 progress onto each effect. Off-tree it just reloads directly.
func _run_death_sequence() -> void:
	# The MIX takes over here: DeathMix ducks the world buses and starts the death sting (death_mix.gd). It also
	# kills a still-running revive fade-up from a PREVIOUS death — a rapid re-death lands mid-fade-up, and two
	# tweens writing the same global buses every frame would fight. Called BEFORE the off-tree early-out so the
	# _restore_death_audio() on that path is always a correct no-op rather than a restore of a duck never applied.
	if _death_mix != null:
		_death_mix.begin()
	if not is_inside_tree():
		_restart_scene()
		return
	# Take the camera off its per-frame driver so the keel-over roll isn't fought (CameraEffects writes
	# rotation.z + position every frame).
	if camera_effects:
		camera_effects.set_process(false)
		_death_cam_base_z = camera_effects.rotation.z
	var fb := GameSettings.player_feedback
	var tw := create_tween().set_ignore_time_scale(true)
	# Phase 1: close the vignette to black + duck the world audio away + keel over (mapped from t in _death_step).
	tw.tween_method(_death_step, 0.0, 1.0, fb.death_sequence_time)
	# On full black, BEFORE the card: broadcast the world-reset cue while nothing is visible (see the method).
	tw.tween_callback(_on_death_screen_covered)
	# Let the black SETTLE before any text: the vignette completing still reads as mid-fade, so a card arriving
	# on that same frame lands on top of the fade-out (the information-overload complaint). The world-reset cue
	# above deliberately stays on the first black frame — the beat gives its teleports the longest cover.
	if fb.death_card_delay > 0.0:
		tw.tween_interval(fb.death_card_delay)
	# After the beat of black: create the death card (transparent) and fade it in.
	tw.tween_callback(_show_death_card)
	tw.tween_method(_set_card_alpha, 0.0, 1.0, fb.death_card_fade_time)
	# Hold the card fully visible, then fade it out — the screen stays black underneath it the whole time.
	# The hold STRETCHES to cover the death sting (DeathMix.card_hold_seconds): the clip is longer than the
	# cinematic, so a fixed beat would cut it off mid-phrase. respawn_delay stays the floor, and the stretch
	# re-derives from the clip's real length each death rather than being an authored number that goes stale.
	tw.tween_interval(_death_mix.card_hold_seconds() if _death_mix != null else fb.respawn_delay)
	tw.tween_method(_set_card_alpha, 1.0, 0.0, fb.death_card_fade_time)
	# A beat on the now-black, text-gone screen, then respawn (which fades the world + audio back up).
	tw.tween_interval(fb.death_card_gap)
	tw.tween_callback(_on_death_sequence_done)

## THE SCREEN IS NOW FULLY BLACK — phase 1's vignette just reached 1.0 and the death card ("You were killed by X
## with Y") is about to fade in. This is the ONE beat where the world may be rearranged without the player seeing
## it, so it is where the world-reset cue goes.
##
## WHY NOT AT death() TIME: the reset used to fire ~half a second into the cinematic, while the vignette was still
## closing and the world was plainly readable — you could WATCH the NPCs teleport away, which is worse than them
## staying put. The whole point is that the world settles behind the black. Everything visible is already frozen
## by now (the player's physics is off, the camera is off its driver mid-keel-over), so nothing here can be seen.
##
## Deliberately BEFORE _show_death_card, not inside it: that method early-outs when the death message is blank or
## the post-process rect is missing, and the cue must not depend on the card actually rendering.
##
## Fires on every death mode. Under RELOAD_LAST_SAVE / RELOAD_CHECKPOINT_FRESH the scene is rebuilt a beat later
## anyway, so the reset is redundant-but-harmless there; it is CHECKPOINT_RESPAWN (the default in-place revive,
## world untouched) that actually needs it. The off-tree early-out in _run_death_sequence skips the whole tween
## and reloads instead, so no cue is emitted there either — again, a reload resets the world by itself.
func _on_death_screen_covered() -> void:
	GameState.player_died.emit()

## One frame of the death cinematic's phase 1: `t` runs 0..1 over death_sequence_time (wall-clock).
func _death_step(t: float) -> void:
	# Slow-mo: ease the world down over the first half of the cinematic (accessibility gate respected).
	if GameSettings.allow_timescale_changes:
		Engine.time_scale = lerpf(1.0, GameSettings.player_feedback.death_time_scale, clampf(t / 0.5, 0.0, 1.0))
	# Keel over: roll the camera onto its side with an ease-out (tips fast, then settles).
	if camera_effects:
		var roll_t := 1.0 - (1.0 - t) * (1.0 - t)
		camera_effects.rotation.z = _death_cam_base_z + GameSettings.player_feedback.death_camera_roll * roll_t
	# Screen: drain to grayscale over the first 40%, and CLOSE the black vignette over the whole phase so the
	# darkness sweeps in from the edges and covers the frame by t=1 (death_vignette 1 = full black). death_fade
	# is left for the spawn fade-UP; the vignette owns the fade-OUT here.
	if _nv_rect:
		var mat := _nv_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("death_bw", clampf(t / 0.4, 0.0, 1.0))
			mat.set_shader_parameter("death_vignette", clampf(t, 0.0, 1.0))
	# Audio: the WORLD ducks out in lockstep with the vignette — a linear-amplitude ramp, but on the world buses
	# (death_cinematic_buses) rather than Master, so it makes ROOM for the death sting instead of silencing it
	# too. The sting rides on `sting`, which sends straight to Master and is deliberately absent from that list;
	# in Godot every bus chain ends at Master, so a Master fade is the one thing a sound cannot be routed around.
	if _death_mix != null:
		_death_mix.set_world_duck(t)

## Drive the death card's opacity (0..1) — the fade-in on full black and the fade-out before the respawn.
## Null-safe: a blank death message means no card was created, so this no-ops.
func _set_card_alpha(a: float) -> void:
	if _death_card != null:
		_death_card.modulate.a = a

## Put every bus the cinematic ducked (death_cinematic_buses) back to its CONFIGURED level, and cut the sting.
## The buses are GLOBAL, so a reload won't reset them — every death-exit path that RELOADS (the RELOAD_* modes
## + the off-tree restart) must call this or the next life boots near-silent. DeathMix restores by iterating
## the designer's bus list and re-reading Settings (not a captured value), so a volume the player changed
## mid-cinematic is honoured, a rapid re-death can't leave a stale-quiet level behind, AND adding a bus to
## death_cinematic_buses can never leave one of the four call sites below stale. The in-place revive
## cross-FADES instead (begin_revive). Kept as a thin facade under its old name because four branches call it.
func _restore_death_audio() -> void:
	if _death_mix != null:
		_death_mix.restore_world()

func _restart_scene() -> void:
	# Restore globals the cinematic touched BEFORE reloading: Engine.time_scale + the ducked world buses are
	# global and a plain reload won't reset them (a reload with them still ducked = a silent next life). The
	# death_bw / death_vignette / death_fade uniforms are cleared on the fresh player's _ready
	# (_reset_screen_post_process) — the shader sub-resource is reused from the cached PackedScene, so a
	# reload alone leaves it dirty (this was the "respawned to a black screen" bug).
	Engine.time_scale = 1.0
	_restore_death_audio()
	if not is_inside_tree():
		return
	get_tree().reload_current_scene()

## End of the death cinematic. Dark Souls respawn: brought back to LIFE at the last bonfire — reset the player
## IN PLACE and teleport to the saved point, the world UNTOUCHED (no enemy / level reset, no reload). Falls
## back to a full reload only if no respawn point was ever set (shouldn't happen — _ready seeds the spawn).
func _on_death_sequence_done() -> void:
	Engine.time_scale = 1.0  # global — a plain reload won't reset the death slow-mo; the fresh _ready re-clears post-process
	if not is_inside_tree():
		return
	match GameSettings.player_feedback.death_mode:
		PlayerFeedbackSettings.DeathMode.RELOAD_LAST_SAVE:
			_restore_death_audio()               # un-duck the (global) world buses before the reload, or the next life boots near-silent
			GameState.load_from_disk()           # revert to the last autosave (loaded=true -> the fresh Player applies it)
			# NO grudge settlement here on purpose: the save carries its own [reputation] section, so the load
			# already rewinds standing to the pre-provoke totals. Reversing the deltas as well would double-count.
			get_tree().reload_current_scene()
		PlayerFeedbackSettings.DeathMode.RELOAD_CHECKPOINT_FRESH:
			_settle_provoked_grudges()           # BEFORE the reload: the fresh world spawns unprovoked NPCs, but Reputation
												  # is an autoload that survives it — the provoke deltas must be reversed
												  # while the NPCs holding them still exist (see _settle_provoked_grudges)
			_restore_death_audio()               # un-duck the world buses before the reload (see above)
			if GameState.profile_active:
				GameState.loaded = true           # promote the in-memory run so the fresh Player APPLIES it (unlocks/xp/money/
												  # inventory) instead of reseeding a default build — matters in a New-Game
												  # session, where a disk load never ran so `loaded` was still false (P0-2)
			get_tree().reload_current_scene()    # world resets; the in-memory profile + respawn carry to the fresh Player
		_:                                        # CHECKPOINT_RESPAWN (default): Dark-Souls in-place revive, world untouched
			if GameState.has_respawn:
				_respawn_at_checkpoint()          # cross-fades the world back UP itself (no snap restore); settles the grudges too
			else:
				_settle_provoked_grudges()        # same as CHECKPOINT_FRESH: reverse the provoke rep before the world is rebuilt
				_restore_death_audio()            # falling back to a reload — un-duck first
				get_tree().reload_current_scene()

## Bring the player back to life at GameState's respawn point WITHOUT reloading: clear the death latches,
## restore HP + limbs, teleport upright to the point, hand the camera back to its driver, re-enable physics,
## clear the death post-process, and fade up from black. Everything else in the world is left exactly as it was.
func _respawn_at_checkpoint() -> void:
	_hide_death_card()    # clear the "You were killed." card before the fade-up (a full reload frees it instead)
	_close_open_modals()  # anything opened DURING the cinematic (the screens take input while we're dead)
	_clear_own_death_gore()  # wipe our remains while the screen is still fully black (see below)
	_dying = false
	_dead = false                                        # clear the Character death latch -> can take damage again
	_took_any_hit = false                                # reset the all-crit kill bookkeeping for the fresh life
	_all_crits = true
	velocity = Vector3.ZERO
	input_dir = Vector2.ZERO                             # camera FOV/tilt reads this; don't carry pre-death strafe into the first live frame
	explosion_velocity = Vector3.ZERO                    # drop any launch/blast impulse — else apply_velocity re-adds it the instant physics resumes and flings the fresh life
	_continuous_fall_time = 0.0
	hp = max_hp
	_set_stamina(stamina_max())
	_sprint_lockout_left = 0.0
	heal_limbs()
	damaged.emit(hp, max_hp)                             # refresh the HUD HP readout
	global_position = GameState.respawn_position
	rotation = Vector3(0.0, GameState.respawn_yaw, 0.0)  # upright, facing the saved yaw
	_ground_snap_frames_left = GROUND_SNAP_RETRY_FRAMES  # land on the floor beneath the checkpoint, not floating above it
	if camera_effects:
		camera_effects.reset_transients()               # don't ease out of stale bob / landing dip / FOV / death roll
		camera_effects.set_process(true)                # hand the camera back to its per-frame driver
	# View-state hygiene for the fresh life: un-ADS (dying while holding Zoom would respawn scoped with the
	# scoped DoF), and drop the climb/slide latches — they froze with our physics, so head pitch clamp /
	# view-model / footstep gates would read one stale frame otherwise.
	if weapon_system != null and weapon_system.scope_in != null:
		weapon_system.scope_in.force_unscope()
	# Belt-and-suspenders: guarantee the fresh life can draw its weapon. Dying mid-carry force-releases the prop,
	# which already clears the carry draw-lock — but clear it here too so no death path can revive you unable to
	# take your gun out (the full-reload death modes rebuild a fresh Player, so this only matters on the in-place revive).
	if weapon_system != null and weapon_system.attack != null:
		weapon_system.attack.draw_locked = false
	if _wall_climb != null:
		_wall_climb.reset()
	if _slide != null:
		_slide.end()
	if head != null:
		head.reset_pitch()
	if screen_shake != null:
		screen_shake.reset()
	_nv_on = false  # un-toggle night vision so the fresh life starts clear, not mid-fade from the frozen timer
	_nv_t = 0.0
	set_physics_process(true)
	# Hand look/auto-fire input back NOW — control returns on the revive's first frame — but hold the HUD
	# restore and the respawn receipts back respawn_hud_delay seconds (_schedule_respawn_hud_restore): all of
	# it used to land on this exact frame, popping a full HUD + a toast burst over a still-black screen while
	# the world faded in behind (the respawn half of the information-overload complaint).
	if mouse_input != null:
		mouse_input.set_process(true)
		mouse_input.set_process_unhandled_input(true)
	_schedule_respawn_hud_restore()
	# Restore the death lockout's body-awareness bits: show the first-person legs + bare fists again and hand
	# crouch input back (die() hid/stowed/froze all three). The fists come back through the SAME latch-driven
	# refresh that stowed them — `_dying`/`_dead` were cleared at the top of this function, so it re-asks
	# _unarmed_hands_wanted() and raises the guard only when the fists really are what's drawn and unholstered
	# (a revive holding a real weapon, or mid-carry, correctly leaves them down). The full-reload death modes
	# rebuild a fresh Player, so this only matters on the in-place revive.
	if fp_body != null:
		fp_body.set_legs_visible(true)
		fp_body.refresh_unarmed_hands()
	if crouch != null:
		crouch.reset()                       # snap upright first: a crouched death froze crouch_t, so re-enabling alone would revive you shrunk/low
		crouch.set_physics_process(true)
	_reset_screen_post_process()
	_fade_in_from_black()
	# Bring the ducked world buses back UP from the death silence in step with the visual fade-up. The death
	# sting is deliberately NOT touched here: the card's hold was already timed (death_sting_sync_point) so the
	# clip's final chord attacks on this very frame and rings on into the new life — forcing a
	# fade instead amputates its decay and sounds like a cut. DeathMix owns the curve (and kills any prior one
	# first, so a rapid re-death can't leave two fades fighting the same global buses); it ignores time scale
	# to ride the visual fade's clock. The RELOAD_* modes snap-restore instead — a fresh scene, no fade to
	# sync to, and the sting IS cut dead there.
	if _death_mix != null:
		_death_mix.begin_revive()

## Start the revive's QUIET WINDOW: hold the HUD restore + the respawn receipts back respawn_hud_delay
## seconds so the world fades up clean first (see _hud_quiet). Wall-clock, like every death timing, so the
## window can't stretch under a lingering time_scale. A 0 delay (or off-tree, where no tween can tick)
## degrades to the old everything-on-frame-one behaviour.
func _schedule_respawn_hud_restore() -> void:
	var delay: float = maxf(GameSettings.player_feedback.respawn_hud_delay, 0.0)
	if delay <= 0.0 or not is_inside_tree():
		_finish_respawn_hud_restore()
		return
	_hud_quiet = true
	_respawn_hud_tween = create_tween().set_ignore_time_scale(true)
	_respawn_hud_tween.tween_interval(delay)
	_respawn_hud_tween.tween_callback(_finish_respawn_hud_restore)

## End of the quiet window: bring the HUD back and (normally) deliver the respawn receipts.
##   - The wallet receipt — announced on the revive, not at death, because die()'s hide_hud_for_death() would
##     have swallowed a toast pushed under the black cinematic. Only the in-place revive can reach it: the
##     reload death modes deliberately settle nothing (see _bequeath_wallet). The move itself already happened
##     at death; this is the receipt, and it names the destination so the player knows which way to go — a
##     killer to hunt, or the spot they fell. Banked name over live node, and cleared here so it shows once.
##   - The grudge settlement, in the same beat and for the same reason: the world stands down where the player
##     can see it, and the restored-reputation toasts land on a HUD that is back on screen.
## `deliver_receipts = false` is the RE-DEATH FLUSH (die(), killed inside the window). Only the HUD restore
## runs then — ui._death_hidden_hud must be emptied before the new hide_hud_for_death() snapshot, or the
## still-hidden nodes drop off the restore list and stay invisible on every later life. The receipts are
## deliberately NOT fired and their state NOT cleared: Character.take_damage banked the NEW death's wallet
## + settlement verdict (_bequeath_wallet / _on_killed_by) BEFORE die() ran, so delivering here would toast
## the new receipt into a HUD about to be hidden and then wipe it — eating it from the next revive, where it
## belongs. Leaving everything banked hands the whole job to the next revive's quiet window.
func _finish_respawn_hud_restore(deliver_receipts: bool = true) -> void:
	_hud_quiet = false
	if _respawn_hud_tween != null and _respawn_hud_tween.is_valid():
		_respawn_hud_tween.kill()
	_respawn_hud_tween = null
	if ui != null:
		ui.restore_hud_after_death()
	if not deliver_receipts:
		return
	if _death_wallet_lost > 0.0:
		var wallet_toast := PlayerText.purse_taken(_death_wallet_killer_name, _death_wallet_lost) \
			if _death_wallet_to_killer else PlayerText.purse_dropped(_death_wallet_lost)
		notify_toast(wallet_toast, GameSettings.player_feedback.death_wallet_toast_color)
	_death_wallet_lost = 0.0
	_death_wallet_killer_name = ""
	_death_wallet_to_killer = false
	_settle_provoked_grudges()
	_consume_pending_holster_forgiveness_tutorial()

## Destroy the gore OUR OWN death flung — the meat chunks and body parts, the floor blood splat, the blood drops
## and the stains they left, the ragdoll/loot corpse if one is authored, and the secondary splatter any of those
## gibs already bled. The Dark-Souls revive deliberately leaves the WORLD untouched (enemies keep their HP and
## positions, loot stays looted), but our remains are not the world: without this the player is brought back to
## life standing in its own guts, or watching them from a checkpoint in view of the spot it died — and each
## further death piles another set on, since a gib lingers gib_lifetime seconds and its stains far longer.
##
## SURGICAL, not a blanket gore wipe: only the player's burst is tagged (Groups.PLAYER_GORE, stamped by
## GoreSpawner off death_gore_group()), so an NPC killed in the same firefight keeps every chunk and stain
## exactly where it fell. The death purse is deliberately NOT gore and NOT tagged — that MoneyBag is the wallet
## you have to walk back and reclaim (see _bequeath_wallet).
##
## Called from _respawn_at_checkpoint BEFORE _fade_in_from_black, i.e. while the screen is still fully black, so
## nothing is ever seen to blink out. Designer switch: GameSettings.effects.clear_player_gore_on_respawn.
## The RELOAD_* death modes need none of this — they rebuild the scene, which frees the lot.
func _clear_own_death_gore() -> void:
	if not GameSettings.effects.clear_player_gore_on_respawn:
		return
	clear_death_gore()

## Clear the screen post-process back to "normal" on spawn: the death cinematic's full grayscale +
## fade-to-black and any leftover hurt drain, plus the global slow-mo. Driven uniforms (low_hp, night
## vision) re-settle on their own each frame, but the death ones are only written during a death, so a
## reload after dying would otherwise keep the screen black/gray.
func _reset_screen_post_process() -> void:
	Engine.time_scale = 1.0
	if not _nv_rect:
		return
	var mat := _nv_rect.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("death_bw", 0.0)
	mat.set_shader_parameter("death_vignette", 0.0)
	mat.set_shader_parameter("death_fade", 0.0)
	mat.set_shader_parameter("hurt", 0.0)

## Show the death card (the line composed in die() from the killer + weapon) over the now-black screen. Created
## lazily as a child of the post-process overlay (the parent of _nv_rect = the `ui` CanvasLayer), added AFTER the
## ColorRect so it draws ON TOP of the fade-to-black. die() hides the HUD via ui.hide_hud_for_death(), which
## spares this ColorRect (and anything added to the layer after, like this card) — so both the fade AND the card
## render. Starts transparent (the sequence fades it in); a blank line (an unattributed death with death_message
## left "") shows nothing; off-tree (_nv_rect null) it no-ops.
func _show_death_card() -> void:
	if _death_card_text == "" or _nv_rect == null:
		return
	var fb := GameSettings.player_feedback
	if _death_card == null:
		_death_card = Label.new()
		_death_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_death_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_death_card.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Wrap long lines (a named killer + a long weapon name overflow the small 396x216 viewport) instead of
		# running off both edges, and inset from the screen edges so the wrapped text keeps a margin.
		_death_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_death_card.offset_left = 24.0
		_death_card.offset_right = -24.0
		_death_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_nv_rect.get_parent().add_child(_death_card)  # same overlay as the fade -> drawn on top (added after it)
	_death_card.text = _death_card_text
	_death_card.add_theme_color_override(&"font_color", fb.death_message_color)
	_death_card.add_theme_font_size_override(&"font_size", fb.death_message_size)
	_death_card.modulate.a = 0.0   # the sequence fades it in from here (then holds, then fades it out)
	_death_card.visible = true

## Hide the death card on the in-place revive (a full reload frees it with the old player).
func _hide_death_card() -> void:
	if _death_card != null:
		_death_card.visible = false

## Armed by StartMenu when a game launches (new game / continue) so the NEXT spawn fade-in fires the game-start
## intro (the in-sky title drop) ONCE; cleared on consume, so a death-respawn doesn't restart it. Static ->
## survives the scene load between the menu and the game.
static var _intro_armed: bool = false

## Called by StartMenu right before it loads the game scene -- the next _fade_in_from_black runs the game-start intro.
static func arm_intro() -> void:
	_intro_armed = true

## Fade the screen UP from black over GameSettings.player_feedback.spawn_fade_in_time on (re)spawn —
## reuses the death cinematic's death_fade shader uniform (1 = black). Set to black first (same frame as
## _reset clears it, so no flash), then tween to clear. Ignores time scale so a slow-mo death -> respawn
## still fades cleanly. ALSO consumes the armed game-start song here, so the intro track comes up WITH the fade.
func _fade_in_from_black() -> void:
	if _intro_armed:
		_intro_armed = false
		_arm_sky_title()  # the in-sky title drop, on the game-start timeline (lines up with the spawn fade-in)
	if _nv_rect == null:
		return
	var fade_mat := _nv_rect.material as ShaderMaterial
	if fade_mat == null:
		return
	fade_mat.set_shader_parameter("death_fade", 1.0)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(func(v: float) -> void: fade_mat.set_shader_parameter("death_fade", v), 1.0, 0.0, GameSettings.player_feedback.spawn_fade_in_time)

## Arm the in-sky title drop (SkyTitle, if one's in the scene) at game-start, so the title's cue lands with the
## spawn fade-in. No-op if no SkyTitle was dropped in the scene.
func _arm_sky_title() -> void:
	var sky := get_tree().get_first_node_in_group(Groups.SKY_TITLE)
	if sky != null and sky.has_method(&"arm"):
		sky.call(&"arm")
