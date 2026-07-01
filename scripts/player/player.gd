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
@export_group("Unlockable Mechanics")
## OPTIONAL fallback: mechanics to grant on a FRESH game WITHOUT placing an Ability node (each builds its node from
## the registry). Pick each from the DROPDOWN -- no more typo'd ids. PREFER dropping the ability scenes under the
## Player; this stays empty by default. A loaded save replaces this whole set. Stored as plain strings (the registry
## keys); unlock_mechanic takes String or StringName interchangeably.
@export_enum("grapple", "laser_sight", "wall_climb", "air_dash", "slide") var starting_unlocks: Array[String] = []
var _abilities: Array[Ability] = []  ## the live drag-drop ability components (the gate + the save iterate this)
var _wall_climb: WallClimb = null    ## hot-path refs resolved in _register_ability (null = ability not present)
var _slide: Slide = null
var _grapple_ability: Grapple = null  ## owns the GrappleHook; pull forwarded at the physics beat

## XP progression (rank 29): xp accrues from kills/quests; crossing an XpSettings threshold grants skill (perk)
## points. `level` is XP-derived (NOT LevelUp's stat-sum total_level) and cached so a save survives an XpSettings
## retune. Skill points live on the PerkManager (the perk-owning component); Player just forwards via add_xp.
signal xp_changed(xp: float, level: int)
signal leveled_up(new_level: int, points_gained: int)
var xp: float = 0.0
var level: int = 0

@onready var white_flash: Sprite3D = $"Head/ScreenShake/Camera3D/white flash"
@onready var _nv_rect: ColorRect = get_node_or_null("UI/ColorRect")

## Night vision (NightVision action, N): toggles the post-process `night_vision` look, faded in/out at this
## rate. This drives the keybind, shader parameter, and options-row state together.
## How fast the night-vision look fades in/out (per second) — higher = snappier toggle, lower = a slower bleed.
@export var night_vision_fade_rate: float = 9.0
var _nv_on: bool = false
var _nv_t: float = 0.0

@export_group("First-Person Body")
## Show your own legs in first person (body-awareness). They reuse the NPC leg model + walk gait, rendered with
## REAL world depth on the main camera (the gun keeps its separate view-model layer). Only legs are shown -- a
## full torso/head would clip into the camera. Tune the offset/scale live on this node.
@export var first_person_legs: bool = true
## The leg model shown in first person (defaults to the same leg mesh the NPCs use).
@export var fp_leg_model: PackedScene = preload("res://leg.blend")
## Uniform scale of each first-person leg.
@export var fp_leg_scale: float = 0.44
## Where the leg rig sits relative to the player origin -- lower Y drops the legs toward your feet. PLAYTEST + TUNE.
@export var fp_leg_offset: Vector3 = Vector3(0.0, -0.55, 0.0)
## Tint for both legs (WHITE = the model's own colour). Character creation will override this per-save later.
@export var fp_leg_color: Color = Color(0.486, 0.184, 0.224)
## How far (degrees) the first-person legs LEAN toward the wall they're clinging to, at a full wall-climb cling.
## Keep it SMALL — the rig pivots at the hip, so a big angle drives the FEET through the wall (75° buried them).
## The direction comes from the actual wall normal, so they angle at the real surface no matter which way you look;
## this only sets how far. Lower it toward 0 if the feet still clip into the wall. PLAYTEST + TUNE.
@export var fp_leg_wall_pitch: float = 20.0
var _fp_legs: BodyModelSwap = null
## Show your own HANDS holding a carried object in first person. They appear ONLY while you're carrying a physics
## prop (PickupRay.held_object): grabbing one HOLSTERS the weapon first, then the hands come out; dropping it hides
## the hands and restores the weapon. Rendered in the gun's view-model camera pass (no wall clipping), parented to
## the camera. PLAYTEST + TUNE the offset/spread/rotation/scale below to frame the held object.
@export var first_person_arms: bool = true
## The arm model for the hands (defaults to the same arm mesh the NPCs use).
@export var fp_arm_model: PackedScene = preload("res://assets/models/arm.blend")
## Uniform scale of each hand/arm.
@export var fp_arm_scale: float = 1.0
## Where the arm rig sits relative to the camera -- forward + down, toward where a held prop floats. TUNE.
@export var fp_arm_offset: Vector3 = Vector3(0.0, -0.16, -0.4)
## Sideways spread of the pair (the LEFT hand's shoulder X; the RIGHT mirrors across X). Bigger = hands further apart.
@export var fp_arm_spread: float = 0.2
## Rotation (degrees) of the arms -- pitch the forearms forward to reach the object. TUNE alongside the offset.
@export var fp_arm_rotation: Vector3 = Vector3(-35.0, 0.0, 0.0)
## Tint for the arms (WHITE = the model's own colour). Defaults to match the first-person legs' skin.
@export var fp_arm_color: Color = Color(0.486, 0.184, 0.224)
## Seconds to wait after the weapon holsters before the hands appear, so the holster reads first. TUNE.
@export var fp_arm_draw_delay: float = 0.18
var _fp_arms: BodyModelSwap = null
var _carrying: bool = false  ## true while a physics prop is held (PickupRay)
var _holster_before_carry: bool = false  ## weapon holster state to restore when the prop is dropped

@export_group("Audio")
## AudioManager migration: the ONE-SHOTS (bowling / jump / land) now play through AudioManager.play_sfx — a fresh
## self-freeing spatial player per hit, so rapid jumps/lands layer instead of cutting each other off — reading the
## stream + volume off these nodes, which are kept as the designer-editable SOURCE (never .play()'d themselves).
## The two LOOPS stay node-driven: WalkingSFX (crouch/climb-aware footstep cadence) and FallingAirSFX (a volume-
## modulated wind loop that slide.gd also borrows) — play_sfx is a fire-and-forget one-shot and can't model them.
## FOLLOW-UP (needs the editor CLOSED, so not done here): move the three one-shot streams to @export AudioStream
## slots and DELETE the BowlingSFX / JumpSFX / LandSFX nodes from Player.tscn — the code no longer .play()s them.
## Bowling-strike "STRIKE!" sound played ONLY on a body-ram KILL (a non-lethal ram plays ram_thud_sound instead). Wire to a 3D player on the body.
@export var bowling_sfx: AudioStreamPlayer3D
## Played once each jump (and each bunnyhop). Wire to a 3D player on the body.
@export var jump_sfx: AudioStreamPlayer3D
## Played on touchdown; its volume + pitch scale with landing impact (a hard fall is louder + lower). Wire to a 3D player on the body.
@export var land_sfx: AudioStreamPlayer3D
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

var footstep_interval: float = GameSettings.player_movement.footstep_base_interval
var _footstep_timer: float = 0.0

## The fake blob shadow (a Decal child) projects straight DOWN on the ground; while wall-climbing we
## rotate it to project onto the WALL instead, easing back when grounded. Cached + driven in code.
## How fast the blob shadow rotates onto the climbed wall / back to the ground (per second) — higher = it snaps onto the wall sooner.
@export var shadow_lerp_speed: float = 6.0
var _shadow: Decal
var _shadow_rest_local: Transform3D  ## the decal's authored local transform (projects down) — the ground pose
var _shadow_wall_blend: float = 0.0  ## 0 = grounded (down), 1 = fully projected onto the climbed wall

var _was_on_floor: bool = false
var input_dir: Vector2 = Vector2.ZERO

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

var target_speed: float = GameSettings.player_movement.max_speed

var _walking_sfx_base_db: float
var _land_sfx_base_db: float
var _land_sfx_base_pitch: float
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

## Build the first-person "legs" rig: a BodyModelSwap configured legs-ONLY (no body/head/arms -- those would clip
## the camera at head height), parented to the Player so it reads our `velocity` / `is_on_floor()` for the walk
## gait and inherits body yaw (not camera pitch, which lives on Head). Rendered on the default layer with real
## depth, so looking down shows your legs and world geometry occludes them correctly. The gun's separate
## view-model layer is untouched. Per-leg hip pose comes from the shipped NPC rig; the whole rig's drop is the
## tunable `fp_leg_offset`.
func _build_first_person_legs() -> void:
	if not first_person_legs or fp_leg_model == null:
		return
	var legs := BodyModelSwap.new()
	legs.name = "FirstPersonLegs"
	legs.casts_shadow = false  # FP legs would cast a shadow from under the camera — looks wrong; suppress it
	legs.leg_model = fp_leg_model
	legs.leg_scale = fp_leg_scale
	legs.leg_position = Vector3(0.095, -0.265, -0.02)  # per-leg hip offset, from scenes/enemies/enemy.tscn
	legs.leg_rotation = Vector3(0.0, -90.0, 0.0)
	legs.leg_color = fp_leg_color
	legs.animate_legs = true
	legs.legs_follow_movement = true
	legs.velocity_driven_legs = true  # your legs track your velocity (run gait in the air), not the NPC mid-air flail
	legs.velocity_leg_ref_speed = GameSettings.player_movement.max_speed  # walk-cycle cadence matches your real run speed
	add_child(legs)
	legs.position = fp_leg_offset
	_fp_legs = legs

## Build the first-person HANDS (a mirrored arm pair) for carrying objects: a BodyModelSwap parented to the CAMERA
## and forced onto the view-model render layer so the gun's dedicated camera draws it over the world with no wall
## clipping. Built HIDDEN -- the hands only show while a physics prop is held (see _on_carry_changed), and grabbing
## one holsters the weapon first. Held STEADY (no NPC walk/flail swing). No-op if disabled / no model / no camera yet.
func _build_first_person_arms() -> void:
	if not first_person_arms or fp_arm_model == null or camera_effects == null:
		return
	var arms := BodyModelSwap.new()
	arms.name = "FirstPersonArms"
	arms.casts_shadow = false  # view-model hands under the camera shouldn't cast a world shadow
	arms.animate_arms = false  # held steady on the object, not the NPC walk/flail swing
	arms.view_model_layer = ViewModelCamera.VIEW_MODEL_LAYER  # draw in the gun pass: over the world, no clipping
	arms.arm_model = fp_arm_model
	arms.arm_scale = fp_arm_scale
	arms.arm_position = Vector3(fp_arm_spread, 0.0, 0.0)  # LEFT shoulder offset; the RIGHT arm mirrors across X
	arms.arm_rotation = fp_arm_rotation
	arms.arm_color = fp_arm_color
	camera_effects.add_child(arms)
	arms.position = fp_arm_offset
	arms.visible = false  # hands appear only while carrying an object
	_fp_arms = arms
	# Drive show/hide off the carry ray. The PickupRay lives under the camera (Head/ScreenShake/Camera3D/RayCast).
	var ray := camera_effects.get_node_or_null(^"RayCast") as PickupRay
	if ray != null and not ray.carry_changed.is_connected(_on_carry_changed):
		ray.carry_changed.connect(_on_carry_changed)

## Grabbing/dropping a carried prop drives the hands. On grab: holster the weapon FIRST, then (after a short beat so
## the holster reads) bring the hands out. On drop: hide the hands and restore the weapon's prior holster state (so a
## manual hold-R holster before the grab is respected). Mirrors the holster-stashing the dialogue camera does.
func _on_carry_changed(holding: bool) -> void:
	_carrying = holding
	if not is_instance_valid(_fp_arms):
		return
	if holding:
		if weapon_system != null and weapon_system.attack != null:
			_holster_before_carry = weapon_system.attack.holstered
			weapon_system.attack.set_holstered(true)  # weapon away FIRST
		await get_tree().create_timer(fp_arm_draw_delay).timeout
		# Still holding after the holster beat AND not dead — don't pop hands into the death cinematic
		# (dying mid-carry would otherwise show the FP arms over the keel-over/fade-to-black).
		if _carrying and not _dying and not _dead and is_instance_valid(_fp_arms):
			_fp_arms.visible = true
	else:
		_fp_arms.visible = false
		# Don't re-arm the weapon mid-death-cinematic — dying while carrying would otherwise pop the gun up over the keel-over.
		if weapon_system != null and weapon_system.attack != null and not _dying and not _dead:
			weapon_system.attack.set_holstered(_holster_before_carry)

func _ready() -> void:
	# Continue (a loaded autosave) swaps in the SAVED stat sheet BEFORE super._ready, so Character._apply_stats
	# stamps max_hp / carry_capacity from the saved build (endurance/strength) and hp seeds from that max. New
	# Game keeps the scene's authored sheet. (Money / unlocks / the teleport are applied at the end of _ready,
	# after the loadout's starting-money override, so the save wins.)
	if GameState.loaded:
		stats = GameState.make_stats()
	super._ready()  # Character._ready: _apply_stats (endurance/strength) THEN seed hp = max_hp
	_discover_abilities()  # register editor-placed Ability children BEFORE the seed/load so they aren't duplicated
	if GameState.loaded:
		set_unlocks(GameState.unlocks)  # restore the saved mechanic set (replaces the fresh-game seed wholesale)
		_restore_perks()  # re-record the saved perk ledger (bonuses + abilities already restored via stats + unlocks)
		xp = GameState.xp
		level = GameState.level
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
	_walking_sfx_base_db = walking_sfx.volume_db
	_land_sfx_base_db = land_sfx.volume_db
	_land_sfx_base_pitch = land_sfx.pitch_scale
	# Scope reactions + music duck: drive the crosshair/optics/DoF and duck music on ADS in/out.
	_scope = ScopeCoordinator.new()
	_scope.host = self
	add_child(_scope)
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
	# Silent takedown (Slice 6b): HOLD the Takedown key behind an unaware NPC for a quiet kill. Self-ticking; it
	# just needs a host. The verb / arc / range live on GameSettings.takedown (SilentTakedownSettings.tres).
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
	# First-person legs (body-awareness): build the legs-only rig so looking down shows your own legs.
	_build_first_person_legs()
	# First-person hands: built hidden; they appear only while carrying a physics prop (weapon holsters first).
	_build_first_person_arms()
	# (The grapple hook moved into the Grapple ABILITY node — it builds + owns the GrappleHook when granted,
	# reading grapple_resource/grapple_hook_origin off us. The pull still runs at its _physics_process beat.)
	# Conversation camera/weapon handling: focus-on-target zoom + holster-for-dialogue + the holster
	# swing (and its provoke-forgiveness). Built last; its signal handlers are wired straight to it.
	_dialogue = DialogueController.new()
	_dialogue.host = self
	add_child(_dialogue)
	# Holster: hide the gun mesh whenever Attack reports holstered (hold-R toggle / dialogue).
	weapon_system.attack.holster_changed.connect(_dialogue.on_weapon_holstered)
	# Put the weapon away for conversations (restored on finish), reusing the holster.
	DialogueManager.dialogue_started.connect(_dialogue.on_dialogue_started)
	DialogueManager.dialogue_finished.connect(_dialogue.on_dialogue_finished)
	# A fresh life must start on a NORMAL screen. The death cinematic's grayscale + fade-to-black ride a
	# shader sub-resource the scene reload leaves dirty (it's reused from the cached PackedScene), and the
	# slow-mo touches the global Engine.time_scale — so clear them all explicitly on (re)spawn.
	_reset_screen_post_process()
	_fade_in_from_black()  # (re)spawn EMERGES from black instead of a jarring hard cut to the world
	# Cache the blob-shadow decal + its authored (ground-projecting) pose so the climb can swing it onto
	# the wall and back. Null-guarded everywhere — a Player scene without a "Shadow" decal just skips it.
	_shadow = get_node_or_null("Shadow") as Decal
	if _shadow:
		_shadow_rest_local = _shadow.transform
	# Turn the backpack's Tetris-style spatial cap ON for the PLAYER (only the player's bag is bounded — NPC /
	# corpse / container bags stay unlimited). Done BEFORE seeding/restoring so every stack auto-places into the
	# grid as it lands. Grid size is a designer knob (resources/tuning/InventorySettings.tres).
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
		if GameState.has_respawn:
			global_position = GameState.respawn_position
			rotation = Vector3(0.0, GameState.respawn_yaw, 0.0)
	# Restore the day/night clock onto the free-running WorldClock autoload, but ONLY after a genuine disk-load or New
	# Game (the one-shot flag) — NOT a death-respawn reload, which should carry the LIVE clock forward instead of
	# rewinding it to the last autosave. set_time_of_day is silent, so loading can't fire a synthetic dawn (e.g. rent).
	if GameState.consume_clock_apply():
		WorldClock.set_time_of_day(GameState.time_of_day)
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
		var cnt := int(entry.get("count", 1))
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
func _drop_position() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var from := global_position + forward * 1.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return (hit["position"] + Vector3.UP * 0.2) if not hit.is_empty() else from

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

## id -> ability script, so a RUNTIME grant (pickup / save load) can build the right node. Editor-placed nodes
## don't need this; only created-on-demand ones do.
const ABILITY_SCRIPTS := {
	&"wall_climb": "res://scripts/components/abilities/wall_climb.gd",
	&"slide": "res://scripts/components/abilities/slide.gd",
	&"air_dash": "res://scripts/components/abilities/air_dash.gd",
	&"laser_sight": "res://scripts/components/abilities/laser_sight.gd",
	&"grapple": "res://scripts/components/abilities/grapple.gd",
	&"fall_immunity": "res://scripts/components/abilities/fall_immunity.gd",
}

## Scan our children for Ability nodes (a designer drag-drops them in) and register each. Called once in _ready
## before the unlock seed/load, so an editor-placed ability isn't duplicated by the seed.
func _discover_abilities() -> void:
	for child in get_children():
		if child is Ability:
			_register_ability(child)

## Wire one ability: inject the host, add it to the live set (deduped), and resolve the typed refs the physics
## step calls every frame (wall climb / slide).
func _register_ability(a: Ability) -> void:
	a.setup(self)
	if not _abilities.has(a):
		_abilities.append(a)
	if a is WallClimb:
		_wall_climb = a as WallClimb  # explicit downcast (GDScript won't narrow Ability -> WallClimb on assign)
	elif a is Slide:
		_slide = a as Slide
	elif a is Grapple:
		_grapple_ability = a as Grapple

## True while an ENABLED ability child grants `id`. Gated abilities (air_dash / laser_sight / grapple) call this;
## wall_climb / slide are driven through their typed refs instead.
func has_mechanic(id: StringName) -> bool:
	for a in _abilities:
		if a != null and a.enabled and a.ability_id() == id:
			return true
	return false

## Player override of Character._apply_fall_damage: the fall-immunity UPGRADE (a FallImmunity Ability granted by an
## UpgradePickup) makes a hard landing cost nothing. Without it, defers to the shared base (FallDamage speed->HP +
## take_damage), so a profiled fall-damage knob on the player is finally live.
func _apply_fall_damage(fall_speed: float) -> void:
	if has_mechanic(&"fall_immunity"):
		return
	super(fall_speed)

## Permanently grant a mechanic (an UpgradePickup / a loaded save). Idempotent. Re-enables a disabled ability if
## one's already present; otherwise builds the ability node from the registry and adds it. Emits once.
func unlock_mechanic(id: StringName) -> void:
	if has_mechanic(id):
		return
	for a in _abilities:
		if a != null and a.ability_id() == id:
			a.enabled = true                       # had it as a disabled node — switch it back on
			mechanic_unlocked.emit(id)
			return
	var made := _make_ability(id)
	if made == null:
		return
	add_child(made)
	_register_ability(made)
	mechanic_unlocked.emit(id)

## Build the ability node for `id` from the registry (a runtime grant). Unknown id -> null (grants nothing).
func _make_ability(id: StringName) -> Ability:
	var path: String = ABILITY_SCRIPTS.get(id, "")
	if path.is_empty():
		return null
	return load(path).new() as Ability

## Adopt a ready-built Ability NODE and grant its mechanic -- a scene-based UpgradePickup hands one over, so the
## node's own authored tuning/config rides along (unlike the registry-built unlock_mechanic). Idempotent by id:
## if the mechanic is already live the incoming node is discarded; a same-id DISABLED node is re-enabled instead
## of stacking a second. Otherwise the node becomes our child + is registered, so its presence grants the
## mechanic and it serializes by id like any other ability.
## Returns TRUE only when it actually introduced a NEW ability node — so a grantor (a perk) knows whether it
## OWNS the ability for later revocation. A dup (already granted) or a re-enabled editor-placed node returns
## false, so respec never deletes an ability the perk didn't bring.
func grant_ability(a: Ability) -> bool:
	if a == null:
		return false
	var id := a.ability_id()
	if has_mechanic(id):
		a.free()  # already granted + enabled -> drop the duplicate (the incoming node never entered the tree)
		return false
	for existing in _abilities:
		if existing != null and existing.ability_id() == id:
			existing.enabled = true  # had it as a disabled node -> switch it back on, discard the incoming dupe
			a.free()
			mechanic_unlocked.emit(id)
			return false  # re-enabled an existing (editor-placed) node — not a NEW grant; respec must not delete it
	a.enabled = true
	add_child(a)
	_register_ability(a)
	mechanic_unlocked.emit(id)
	return true

## Revoke a granted mechanic (rank 29 respec): NULL the hot-path refs (_wall_climb / _slide / _grapple_ability)
## BEFORE freeing the node so a freed ability never dangles, then drop it from the live set. Unlike set_unlocks
## (which only DISABLES, so an editor-placed node survives a load), this truly REMOVES the ability so it leaves
## has_mechanic / unlocked_list. No-op for an unknown/absent id; idempotent.
func revoke_ability(id: StringName) -> void:
	var keep: Array[Ability] = []
	for a in _abilities:
		if a != null and a.ability_id() == id:
			if a == _wall_climb:
				_wall_climb = null
			elif a == _slide:
				_slide = null
			elif a == _grapple_ability:
				_grapple_ability = null
			a.enabled = false
			a.queue_free()
		elif a != null:
			keep.append(a)
	_abilities = keep

## The granted (enabled) ability ids — for the save system to serialize. Deduped (two same-id nodes count once).
func unlocked_list() -> Array:
	var ids: Array = []
	for a in _abilities:
		if a != null and a.enabled and not ids.has(a.ability_id()):
			ids.append(a.ability_id())
	return ids

## Replace the live unlock set wholesale (loading a save). Enable wanted abilities, disable the rest, and build
## any wanted ability we don't have yet. Disables rather than frees, so an editor-placed node survives a load.
func set_unlocks(ids: Array) -> void:
	var want := {}
	for id in ids:
		want[StringName(id)] = true
	for a in _abilities:
		if a != null:
			a.enabled = want.has(a.ability_id())
	for id in want.keys():
		if not has_mechanic(id):
			unlock_mechanic(id)

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
			notify_toast("Level %d! +%d skill point%s" % [level, pts, "" if pts == 1 else "s"], Color(0.7, 0.9, 1.0))
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
			notify_toast("+%d HP" % int(round(item.heal_amount)), Color(0.4, 1.0, 0.45))
	if item.consumable_effect != null:
		apply_status_effect(item.consumable_effect)  # CT-3: shared Character entry point (weapons/consumables/NPCs)
		did = true
	if not did:
		# A heal-only pack at full HP with no effect — don't waste it on a click.
		if item.heal_amount > 0.0 and hp >= max_hp and ui != null:
			notify_toast("Already at full health", Color(0.85, 0.85, 0.85))
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

const RECKLESS_LINES: Array[String] = ["Watch where you're firing!", "Hey! Careful with that thing!", "Easy on the trigger!", "Whoa — mind where you point that!"]
const AIM_LINES: Array[String] = ["Hey, point that somewhere else.", "Watch where you're aiming.", "I'd lower that if I were you.", "Easy there, friend."]

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

## True while scaling a wall (wall-climb). The camera + view model read this to treat the climb as
## "walking" — running the walk-bob and the grounded FOV rules instead of the airborne/rising ones. Backed by
## the WallClimb ability node: false when it's absent / disabled.
func is_climbing() -> bool:
	return _wall_climb != null and _wall_climb.is_climbing()

## True while sliding — backed by the Slide ability node (false when absent / disabled). The footstep +
## falling-air gates read this; the slide-wind fade is internal to the Slide node itself.
func is_sliding() -> bool:
	return _slide != null and _slide.is_active()

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

## Point the first-person legs AT the wall they're clinging to (not just "ahead") while climbing, so they press the
## real surface instead of dangling. Takes the WALL DIRECTION (-wall_normal) into the rig's local frame, flattens it,
## and pitches the whole rig from straight-DOWN toward it — eased by the wall-climb blend the shadow already computes
## (_shadow_wall_blend: 0 grounded -> 1 clinging). So it orients to the actual wall regardless of where you're
## looking. The gait is separately told (via is_climbing()) not to air-flail. Null-safe.
func _update_fp_leg_wall_pose() -> void:
	if _fp_legs == null:
		return
	# Off the wall (or no real wall normal this frame -- it reads ~zero as contact drops): legs rest (hang down).
	var wn := get_wall_normal()
	if _shadow_wall_blend <= 0.001 or not is_on_wall() or wn.length_squared() < 0.0001:
		_fp_legs.transform.basis = Basis()
		return
	# Bring the wall direction into the rig's local frame. The player basis is an orthonormal yaw, so
	# orthonormalized().transposed() equals its inverse() but can NEVER raise a det==0 invert on a transient
	# degenerate transform (the engine error this guards against).
	var into_local := global_transform.basis.orthonormalized().transposed() * (-wn.normalized())  # toward the wall, local space
	into_local.y = 0.0  # flatten — pitch the legs toward the wall horizontally, not up/down it
	var axis := Vector3.DOWN.cross(into_local)  # horizontal pitch axis, perpendicular to the wall direction
	if axis.length() < 0.001:
		_fp_legs.transform.basis = Basis()
		return
	# Swing the rig's local-DOWN (where the legs extend) toward the wall by up to fp_leg_wall_pitch, eased by the cling.
	_fp_legs.transform.basis = Basis(axis.normalized(), deg_to_rad(fp_leg_wall_pitch) * _shadow_wall_blend)

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
	if screen_shake:
		screen_shake.shake(weapon.launch_screen_shake)
	camera_effects.fov_punch()

## #2: after a gunshot, the nearest calm (non-hostile, out-of-combat) talker within reckless_remark_radius
## remarks on the reckless discharge. Just the closest, so a crowd doesn't all pipe up at once.
func _remark_reckless_fire() -> void:
	var nearest: NPC = null
	var best := reckless_remark_radius * reckless_remark_radius
	for n in get_tree().get_nodes_in_group(Groups.NPC):
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
	if Input.is_action_just_pressed("NightVision"):
		_nv_on = not _nv_on
	if not _nv_rect:
		return
	var mat := _nv_rect.material as ShaderMaterial
	if not mat:
		return
	var target := 1.0 if _nv_on else 0.0
	_nv_t = lerpf(_nv_t, target, 1.0 - exp(-night_vision_fade_rate * delta))
	mat.set_shader_parameter("night_vision", _nv_t)

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
	notify_toast("Your head is crippled!", GameSettings.player_feedback.cripple_toast_color)

var _last_sneak_toast_msec: int = -100000

## Quicksave (F5) / quickload (F9) — the immersive-sim core loop (ML-1). Polled here so it only fires during
## live gameplay (a Player exists); suppressed during a conversation (the _physics_process early-return above)
## and while the tree is paused for a transaction screen (_physics_process doesn't run then). Quicksave snapshots
## the run + your position; quickload reloads the scene and the fresh Player re-applies the saved build — we
## never mutate THIS live player, so a quickload mid-frame is safe.
func _update_save_input() -> void:
	if Input.is_action_just_pressed("Quicksave"):
		# quicksave() returns true ONLY when the file actually persisted; a failed write (disk full / permission)
		# now toasts the failure instead of a false "Quicksaved". (We're always in-tree here, so false == write error.)
		if GameState.quicksave(self):
			notify_toast("Quicksaved", Color.WHITE)
		else:
			notify_toast("Quicksave failed", Color(1.0, 0.5, 0.4))
	elif Input.is_action_just_pressed("Quickload"):
		if GameState.has_quicksave():
			_force_release_carried_prop()
		GameState.quickload()  # reloads the scene on success; no toast — the reload IS the feedback

func _force_release_carried_prop() -> void:
	if head != null and head.pickup_ray != null:
		head.pickup_ray.force_release_held()

## The physics prop the player is CURRENTLY carrying (PickupRay.held_object), or null when empty-handed.
## PetInteraction reads this to refuse petting an object you're holding (it's at arm's length, so the aim ray
## hits it — but you can't pet what's in your hands).
func held_prop() -> Node:
	if head != null and head.pickup_ray != null:
		return head.pickup_ray.held_object
	return null

## Push a one-off HUD toast (top-left) via the UI layer. Player-facing notifications (sneak result, limb
## cripples, ...) route through here. No-op off-tree (no UI).
func notify_toast(text: String, color: Color) -> void:
	if ui:
		ui.push_toast(text, color)

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
	notify_toast("Sneak Attack!", GameSettings.player_feedback.sneak_toast_color)

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

## Compute + push the look-at label/tint for `handler` (null clears it): the name (tinted green for a
## friendly NPC, prefixed "Pick Pocket" when you're crouched behind an off-guard NPC via look_name_for).
## Guards on the last shown text + colour so a per-frame refresh only touches the HUD when something changed.
func _apply_look_readout(handler: Node) -> void:
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
			label = "[%s] %s" % [InputManager.display_key(InputManager.action_throw), label]
		elif TalkHelpers.is_talkable_now(handler) or TalkHelpers.is_pickpocketable_now(handler, self):
			label = "[%s] %s" % [InputManager.display_key(InputManager.action_pickup), label]
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

func _physics_process(delta: float) -> void:
	# Frozen during a conversation (cinematic, like the NPC) so the player can't move OR fall —
	# they hold in place while the world keeps running. The camera-focus + NPC-turn tweens still
	# animate, since those run on the SceneTree rather than in this _physics_process.
	if DialogueManager.is_active():
		velocity = Vector3.ZERO
		input_dir = Vector2.ZERO  # also zero input so CameraEffects reads no stale strafe (FOV kick / tilt)
		return
	coyote_time.tick(delta)
	gravity(delta)
	_update_night_vision(delta)
	_update_save_input()
	_update_low_hp(delta)

	input_dir = Input.get_vector("left", "right", "forward", "backward")
	if InputManager.gameplay_suppressed():
		# A NON-pausing modal (options/inventory/stats/loot) is open: stand idle but keep gravity + stay vulnerable
		# (Dark Souls). ShopScreen pauses the tree, so its check never actually fires — kept as belt-and-braces.
		input_dir = Vector2.ZERO
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var bhop_engaged: bool = false
	var jumped_now := false
	if coyote_time.can_jump() and jump_buffer.wants_jump() and not InputManager.gameplay_suppressed():
		# Heavier = lower hop (gradual), instead of the old hard "can't jump while over-encumbered" block.
		# AGILITY springs you higher (jump_mult), the same stat that makes you faster on foot.
		velocity.y = GameSettings.player_movement.jump_velocity * encumbrance_jump_multiplier() * stats_or_default().jump_mult(status_stat_modifier(&"agility"))
		if jump_sfx != null:  # one-shot through AudioManager (self-freeing) reading the node's authored stream/volume
			AudioManager.play_sfx(global_position, jump_sfx.stream, jump_sfx.volume_db)
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

	target_speed = GameSettings.player_movement.max_speed
	if input_dir.y > 0:
		target_speed = GameSettings.player_movement.max_speed * GameSettings.player_movement.backward_mult
	elif abs(input_dir.x) > 0 and input_dir.y == 0:
		target_speed = GameSettings.player_movement.max_speed * GameSettings.player_movement.strafe_mult
	target_speed = lerpf(target_speed, target_speed * GameSettings.player_crouch.speed_mult, crouch.crouch_t)
	# Slow-walk (stealth Slice 3b): a quiet, mobile sneak tier between run and crouch — HELD like Crouch, applied
	# only while NOT crouched (crouch is its own slower tier; they don't stack into a crawl). Noise drops for free
	# (NoiseEmitter scales with ground speed), so walking is quieter than running without a separate noise knob.
	if crouch.crouch_t < 0.5 and Input.is_action_pressed(&"Walk"):
		target_speed *= GameSettings.player_movement.walk_speed_mult
	if _is_scoped:
		target_speed *= GameSettings.weapon_general.scope_speed_mult
	# A heavy weapon slows you WHILE IT'S DRAWN (WeaponData.move_speed_multiplier); holstered = full
	# speed, FNV-style — mirrors the NPC's _current_move_speed gating on the same holster state.
	if weapon_system and weapon_system.attack and not weapon_system.attack.holstered and weapon_system.equipped_weapon:
		target_speed *= weapon_system.equipped_weapon.move_speed_multiplier
	target_speed *= limb_move_multiplier()  # crippled legs limp (locational damage)
	target_speed *= encumbrance_move_multiplier()  # over carry_capacity -> over-encumbered slog
	target_speed *= stats_or_default().move_speed_mult(status_stat_modifier(&"agility"))  # AGILITY (+ active buff): faster on foot per point
	target_speed *= status_move_multiplier()  # active StatusEffects (slow / haste)

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

	apply_blast()

	# Wall climb: the WallClimb ability owns the grip + climb logic (same spot in the step, same operations).
	# Absent / disabled -> no climb. Drives velocity directly + the camera bob; is_climbing() reads its state.
	if _wall_climb != null:
		_wall_climb.tick(direction)

	# Swing the blob shadow onto the wall while climbing, back to the ground otherwise.
	_update_wall_shadow(delta)
	# ...and pitch the first-person legs onto the wall too, so they plant against it instead of dangling.
	_update_fp_leg_wall_pose()

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

	if is_on_floor() and !_was_on_floor:
		var impact := clampf(-pre_landing_velocity / GameSettings.player_movement.landing_impact_divisor, 0.0, 1.0)
		var dampened_impact := impact * (1.0 - crouch.crouch_t)
		camera_effects.land(dampened_impact)
		if gun_mesh and impact > 0.0:
			gun_mesh.land(impact)
		if screen_shake and dampened_impact > 0.0:
			screen_shake.shake(dampened_impact * 1.5)
		if impact >= GameSettings.audio.land_sfx_min_impact_to_play and land_sfx != null:
			# One-shot through AudioManager (spatialized + self-freeing) instead of replaying the node — reads the
			# node's authored stream + base volume/pitch (captured at _ready). See the Audio-group TODO note.
			var land_vol := _land_sfx_base_db - (1.0 - impact) * GameSettings.audio.land_sfx_volume_db_reduction
			var land_pitch := lerpf(
				_land_sfx_base_pitch + GameSettings.audio.land_sfx_pitch_spread,
				_land_sfx_base_pitch - GameSettings.audio.land_sfx_pitch_spread,
				impact
			)
			AudioManager.play_sfx(global_position, land_sfx.stream, land_vol, land_pitch)
		if impact >= GameSettings.effects.dust_land_min_impact_to_spawn:
			spawn_dust(GameSettings.effects.dust_land_base_intensity + impact * GameSettings.effects.dust_land_impact_bonus)
		if _slide != null:
			_slide.try_start(pre_velocity)  # begin a slide on a fast crouched landing (the Slide ability decides)
		# HP cost for a hard landing (FallDamage math, gated by the fall-immunity upgrade). pre_landing_velocity.y is
		# negative falling, so negate for a positive fall speed. Was silently never called — the player took no fall damage.
		_apply_fall_damage(-pre_landing_velocity)

	_was_on_floor = is_on_floor()

	_footstep_timer -= delta

	footstep_interval = GameSettings.player_movement.footstep_base_interval * (GameSettings.player_movement.max_speed / max(target_speed, 0.01))

	var on_foot := is_on_floor() and Vector2(velocity.x, velocity.z).length() > GameSettings.player_movement.footstep_min_horizontal_speed
	# Climb footsteps only while actually moving up/down the wall — a wall-hold (velocity.y == 0) is silent
	# like standing still (the into-wall grip push isn't real movement, so don't count it).
	var on_climb := is_climbing() and absf(velocity.y) > GameSettings.player_movement.footstep_min_horizontal_speed
	if (on_foot or on_climb) and not is_sliding() and _footstep_timer <= 0.0:
		walking_sfx.volume_db = lerpf(_walking_sfx_base_db, _walking_sfx_base_db + GameSettings.player_crouch.quiet_footstep_db, crouch.crouch_t)
		walking_sfx.play()
		_footstep_timer = footstep_interval

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
	if not _hud:
		return
	# Throttle the heavy full-NPC awareness scan to ~10x/sec; reuse the cached snapshot on the in-between
	# frames so the HUD still updates every frame (cheap re-push) without re-scanning every NPC each frame.
	_stealth_hud_accum -= delta
	if _stealth_hud_accum <= 0.0 or _stealth_hud_snap.is_empty():
		_stealth_hud_accum = _STEALTH_HUD_INTERVAL
		# of_player now returns {level, meter, spotter}; the HUD label still consumes the level (the detection
		# bar off `meter` is the next slice). Extract level here so behaviour is unchanged.
		_stealth_hud_snap = StealthStatus.of_player(self, get_tree().get_nodes_in_group(Groups.NPC))
	_hud.set_stealth_level(_stealth_hud_snap[&"level"], is_crouching())
	_hud.set_detection_meter(_stealth_hud_snap[&"meter"], is_crouching())

## Keep the permanent crosshair pinned to SCREEN CENTRE — a fixed reticle (Deus Ex). It deliberately does
## NOT track the shot: the swaying LASER DOT (flash_light, aimed along get_aim_direction) is what shows where
## a shot will truly land — drifting wide on the move, settling back toward centre as you stand still. Re-set
## each frame so a viewport resize keeps it centred. No-op without a HUD.
func _update_crosshair() -> void:
	if ui == null:
		return
	ui.set_crosshair_screen_pos(get_viewport().get_visible_rect().size * 0.5)


## (The slide state machine — try_start / update_movement / jump_launch / end — moved into the Slide ability
## node, scripts/components/abilities/slide.gd. The Player calls those hooks at the beats above.)


func _update_falling_air(delta: float) -> void:
	if not falling_air_sfx:
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
	if distance <= GameSettings.screen_shake.death_shake_range:
		FreezeFrame.freeze(0.01, 0.1, 0.02)
	if distance <= GameSettings.effects.blood_splatter_range and ui and ui.blood_splatter:
		var splat_t := 1.0 - clampf(distance / GameSettings.effects.blood_splatter_range, 0.0, 1.0)
		ui.blood_splatter.splash(splat_t)
	if distance <= GameSettings.screen_shake.death_shake_range and screen_shake:
		var shake_t := 1.0 - clampf(distance / GameSettings.screen_shake.death_shake_range, 0.0, 1.0)
		screen_shake.shake(shake_t * GameSettings.screen_shake.death_shake_amount)

## Death cinematic (Player): on death the world eases into slow-mo while the camera slowly rolls onto its
## side (keeling over) and the screen drains to black & white then fades to black — THEN, after a beat
## on the black screen, the respawn. Every timing/feel number (sequence time, slow-mo target, camera
## roll, the black-screen beat, the spawn fade-up) is a designer knob on GameSettings.player_feedback.
var _dying: bool = false
var _death_cam_base_z: float = 0.0       ## camera roll at the instant death starts; the keel-over adds onto it
var _death_card: Label = null            ## the "You were killed." card, created lazily over the black hold (ML-2)

func take_damage(amount: float, was_crit: bool = false, attacker: Node = null, hit_pos: Vector3 = Vector3.INF) -> void:
	if _dying:
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
## on_dealt_hit (the player's "I landed a hit" callback, which NPCs override to a no-op), so an
## NPC-vs-NPC trade can never proc the player's hitsound.
const HIT_SFX: AudioStream = preload("uid://budx7vymim0j0")
## Headshot drops the ding's pitch DOWN (deeper, meatier) rather than up — sub-1.0 factor.
const HEADSHOT_PITCH_MULT := 0.7

## Flash the crosshair hitmarker AND play the hit-confirm ding — forwards to PlayerHud. Kept as a NAME
## here because a landed shot/explosion calls player.on_dealt_hit. Off-tree (_hud null) it no-ops.
func on_dealt_hit(headshot := false, hp_frac := 1.0) -> void:
	if _hud:
		_hud.on_dealt_hit(headshot, hp_frac)
	if hp_frac <= 0.0:
		StarSky.flash_kill()  # pop the whole authored sky for a beat (StarSky paints every WorldEnvironment, so it always fires)
		if _hud:
			_hud.flash_kill()  # screen-space colour pop -> the kill flash shows over the authored skybox too

## Slice 6b: forward the takedown prompt + hold-progress cue to PlayerHud. Driven every frame by SilentTakedown:
## `active` shows "[key] Take Down <name>" with the hold fill, inactive hides it. Off-tree (_hud null) it no-ops.
func set_takedown_cue(active: bool, text: String, progress: float) -> void:
	if _hud:
		_hud.set_takedown_cue(active, text, progress)

## Forward the PET prompt + hold-progress cue to PlayerHud. Driven every frame by PetInteraction: `active` shows
## "[key] Pet <name>" with the hold fill, inactive hides it. Off-tree (_hud null) it no-ops. Mirrors set_takedown_cue.
func set_pet_cue(active: bool, text: String, progress: float) -> void:
	if _hud:
		_hud.set_pet_cue(active, text, progress)

## Forward the CLAIM/UNCLAIM prompt cue to PlayerHud. Driven every frame by ClaimInteraction: `active` shows
## "[key] Claim <name>" (tap, progress 0 → no bar) or "[key] Hold to Unclaim <name>" (hold, progress fills the bar).
## Off-tree (_hud null) it no-ops.
func set_claim_cue(active: bool, text: String, progress: float = 0.0) -> void:
	if _hud:
		_hud.set_claim_cue(active, text, progress)

func die() -> void:
	if _dying:
		return
	_dying = true
	# Dying MID-CONVERSATION (shot during the dialogue's unpaused intro beat, where we're frozen on
	# is_active and can't dodge): hard-end the dialogue FIRST — once its box opens it pauses the tree,
	# which would freeze our node-bound death tween under an open conversation. Mirrors the dialogue's
	# own speaker-died teardown, from our side.
	if DialogueManager.is_active():
		DialogueManager.abort()
	# Slam any open modal shut so the cinematic plays clean and the respawn doesn't sit under stale UI
	# (the non-pausing ones — options / inventory / loot — leave the world live, so dying with them open
	# is perfectly reachable).
	_close_open_modals()
	_force_release_carried_prop()
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
	died.emit()
	# Freeze the player but keep effects (gore particles, blood, sound) running so the death is visible
	# through the cinematic before the scene reloads.
	set_physics_process(false)
	# Lock the player out + clear the HUD for a clean death cinematic: hide all the extraneous UI (crosshair /
	# health / hotbar / notifications live in `ui`; the death drain/fade is a post-process shader, untouched),
	# and kill the look + auto-fire input (mouse_input drives both; the rest of the input gates on _dead).
	if ui != null:
		ui.visible = false
	if mouse_input != null:
		mouse_input.set_process(false)
		mouse_input.set_process_unhandled_input(false)
	_run_death_sequence()

## Close every modal overlay that's open (each close() is a no-op-safe early-return when shut). Called on
## death (play the cinematic clean) and again on respawn (a modal can be OPENED mid-cinematic — the screens
## process input regardless of our death). The pausing trio can't be open while enemies act, but checking
## them costs nothing and keeps this the one exhaustive list.
func _close_open_modals() -> void:
	if OptionsMenu.is_open():
		OptionsMenu.close()
	if InventoryScreen.is_open():
		InventoryScreen.close()
	if StatsScreen.is_open():
		StatsScreen.close()
	if ReputationScreen.is_open():
		ReputationScreen.close()
	if LootScreen.is_open():
		LootScreen.close()
	if ShopScreen.is_open():
		ShopScreen.close()
	if HealScreen.is_open():
		HealScreen.close()
	if RespecScreen.is_open():
		RespecScreen.close()
	if LevelUpScreen.is_open():
		LevelUpScreen.close()

## The player-death cinematic: ease into slow-mo, slowly roll the camera onto its side (keeling over) as
## the screen drains to black & white and fades to black, hold a beat on black, then reload. Driven by ONE
## tween in WALL-CLOCK time (ignore_time_scale) so it finishes on schedule even as it slows the world;
## _death_step maps the tween's 0..1 progress onto each effect. Off-tree it just reloads directly.
func _run_death_sequence() -> void:
	if not is_inside_tree():
		_restart_scene()
		return
	# Take the camera off its per-frame driver so the keel-over roll isn't fought (CameraEffects writes
	# rotation.z + position every frame).
	if camera_effects:
		camera_effects.set_process(false)
		_death_cam_base_z = camera_effects.rotation.z
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(_death_step, 0.0, 1.0, GameSettings.player_feedback.death_sequence_time)
	tw.tween_callback(_show_death_card)  # screen is now black — show the death card for the hold
	tw.tween_interval(GameSettings.player_feedback.respawn_delay)  # hold on the fully-black screen a beat before reloading
	tw.tween_callback(_on_death_sequence_done)

## One frame of the death cinematic: `t` runs 0..1 over death_sequence_time (wall-clock).
func _death_step(t: float) -> void:
	# Slow-mo: ease the world down over the first half of the cinematic (accessibility gate respected).
	if GameSettings.allow_timescale_changes:
		Engine.time_scale = lerpf(1.0, GameSettings.player_feedback.death_time_scale, clampf(t / 0.5, 0.0, 1.0))
	# Keel over: roll the camera onto its side with an ease-out (tips fast, then settles).
	if camera_effects:
		var roll_t := 1.0 - (1.0 - t) * (1.0 - t)
		camera_effects.rotation.z = _death_cam_base_z + GameSettings.player_feedback.death_camera_roll * roll_t
	# Black & white over the first 40%, then fade the whole frame to black over the last 60%.
	if _nv_rect:
		var mat := _nv_rect.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("death_bw", clampf(t / 0.4, 0.0, 1.0))
			mat.set_shader_parameter("death_fade", clampf((t - 0.4) / 0.6, 0.0, 1.0))

func _restart_scene() -> void:
	# Restore globals the cinematic touched BEFORE reloading: Engine.time_scale is global and a plain
	# reload won't reset it. The death_bw / death_fade uniforms are cleared on the fresh player's _ready
	# (_reset_screen_post_process) — the shader sub-resource is reused from the cached PackedScene, so a
	# reload alone leaves it dirty (this was the "respawned to a black screen" bug).
	Engine.time_scale = 1.0
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
			GameState.load_from_disk()           # revert to the last autosave (loaded=true -> the fresh Player applies it)
			get_tree().reload_current_scene()
		PlayerFeedbackSettings.DeathMode.RELOAD_CHECKPOINT_FRESH:
			get_tree().reload_current_scene()    # world resets; the in-memory profile + respawn carry to the fresh Player
		_:                                        # CHECKPOINT_RESPAWN (default): Dark-Souls in-place revive, world untouched
			if GameState.has_respawn:
				_respawn_at_checkpoint()
			else:
				get_tree().reload_current_scene()

## Bring the player back to life at GameState's respawn point WITHOUT reloading: clear the death latches,
## restore HP + limbs, teleport upright to the point, hand the camera back to its driver, re-enable physics,
## clear the death post-process, and fade up from black. Everything else in the world is left exactly as it was.
func _respawn_at_checkpoint() -> void:
	_hide_death_card()    # clear the "You were killed." card before the fade-up (a full reload frees it instead)
	_close_open_modals()  # anything opened DURING the cinematic (the screens take input while we're dead)
	_dying = false
	_dead = false                                        # clear the Character death latch -> can take damage again
	_took_any_hit = false                                # reset the all-crit kill bookkeeping for the fresh life
	_all_crits = true
	velocity = Vector3.ZERO
	hp = max_hp
	heal_limbs()
	damaged.emit(hp, max_hp)                             # refresh the HUD HP readout
	global_position = GameState.respawn_position
	rotation = Vector3(0.0, GameState.respawn_yaw, 0.0)  # upright, facing the saved yaw
	if camera_effects:
		camera_effects.set_process(true)                # hand the camera back to its per-frame driver
		camera_effects.rotation.z = _death_cam_base_z   # undo the keel-over roll
		camera_effects.reset_transients()               # don't ease out of a stale landing dip / FOV punch / dialogue zoom
	# View-state hygiene for the fresh life: un-ADS (dying while holding Zoom would respawn scoped with the
	# scoped DoF), and drop the climb/slide latches — they froze with our physics, so head pitch clamp /
	# view-model / footstep gates would read one stale frame otherwise.
	if weapon_system != null and weapon_system.scope_in != null:
		weapon_system.scope_in.force_unscope()
	if _wall_climb != null:
		_wall_climb.reset()
	if _slide != null:
		_slide.end()
	_nv_on = false  # un-toggle night vision so the fresh life starts clear, not mid-fade from the frozen timer
	_nv_t = 0.0
	set_physics_process(true)
	# Restore the HUD + look/auto-fire input the death lockout disabled (the full-reload path rebuilds them fresh).
	if ui != null:
		ui.visible = true
	if mouse_input != null:
		mouse_input.set_process(true)
		mouse_input.set_process_unhandled_input(true)
	_reset_screen_post_process()
	_fade_in_from_black()

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
	mat.set_shader_parameter("death_fade", 0.0)
	mat.set_shader_parameter("hurt", 0.0)

## Show the editable death card (GameSettings.player_feedback.death_message) over the now-black screen. Created
## lazily as a child of the post-process overlay (the parent of _nv_rect), so it sits ABOVE the fade-to-black —
## which hiding `ui` (the HUD) doesn't touch. A blank message shows nothing; off-tree (_nv_rect null) it no-ops.
func _show_death_card() -> void:
	var fb := GameSettings.player_feedback
	if fb.death_message == "" or _nv_rect == null:
		return
	if _death_card == null:
		_death_card = Label.new()
		_death_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_death_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_death_card.set_anchors_preset(Control.PRESET_FULL_RECT)
		_death_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_nv_rect.get_parent().add_child(_death_card)  # same overlay as the fade -> drawn on top (added after it)
	_death_card.text = fb.death_message
	_death_card.add_theme_color_override(&"font_color", fb.death_message_color)
	_death_card.add_theme_font_size_override(&"font_size", fb.death_message_size)
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
	var sky := get_tree().get_first_node_in_group(&"sky_title")
	if sky != null and sky.has_method(&"arm"):
		sky.call(&"arm")
