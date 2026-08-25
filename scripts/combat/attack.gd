class_name Attack
extends Node3D

## The Weapon's firing coordinator + the signal hub external code connects to. It owns the shot
## RESOLUTION (input gating, ammo, the penetration raycast loop, recoil, auto-reload), the reload /
## swap / holster / scope state machine, and the secondary (scoped-attack) launch — but delegates the
## stateless bits to helpers and the side systems to child components, so it stays a thin coordinator:
##   - ShotResolver (static): per-pellet math — spread, damage, hitstop scale, crit rule, decal cap.
##   - GunFX (static): the throwaway tracer / hit-spark / muzzle-flash visuals.
##   - SprayPainter (child): the spray colour picker UI + palette state.
##   - WeaponAudio (child): fire / dry-fire / shell / reload / impact sound playback.
## The components are built code-side in _ready, so off-tree (a unit-test Attack via .new() with no
## add_child) they stay null and every facade that touches them null-guards back to the monolith's
## old value.

## Per-pellet round spawn, consumed by ProjectileSpawner (weapon.tscn wires it). _visual_only=true means the
## hitscan trace already resolved this pellet's damage and the round is cosmetic — that is every in-range
## PLAYER hit. _visual_only=false is a LIVE damaging round: a player pellet whose trace missed (the
## beyond-effective_range case), and — since 2026-08-25 — EVERY ranged AI pellet (enemies never hitscan; see
## ShotResolver.ai_fires_live_projectile and the fire loop below).
signal spawn_projectile(_from, _direction, _visual_only: bool, _apply_status: bool)
signal play_animation
signal reload_started
signal swap_started
signal swap_finished
signal flash_muzzle
signal shell_particle
signal holster_changed(on: bool)  ## weapon put away / brought back out (hold-R toggle, or dialogue)

@export_group("Wielder & Weapon Source")
## The wielder this weapon is mounted on (player or enemy). Source of aim (origin/direction/basis), fire
## feedback (screen shake), knockback, and the air-dash floor check — the whole fire path routes through it.
@export var character: Character
## The equipped-weapon source. Attack listens to its weapon_changed to reseed current_weapon + spread,
## and reads equipped_weapon on _ready; the live WeaponData drives every per-shot tunable.
@export var inventory: Inventory
## The barrel tip node — bullets spawn and tracers/muzzle flash originate here. If unset, shots fall back
## to the wielder's aim origin (an enemy with no view-model muzzle).
@export var muzzle: Node3D
## The ShellDrop emitter (the ejected-casing particle burst). Wired so a per-weapon
## casing_size_scale can resize the shell right before it's ejected. Optional — if unset (e.g. an
## enemy wielder with no view-model), the casing simply ejects at its authored size.
@export var shell_drop: GPUParticles3D
## The magazine state (current/reserve ammo). Consumed per shot and topped up on reload; gates firing
## when empty and drives the foreground/background reload logic.
@export var clip: Ammo
## The aim-down-sights (ADS) controller. Attack reads its scoped state to launch the dash-attack instead
## of firing, and calls force_unscope on a launch so dashing snaps you out of the scope.
@export var scope_in: ScopeIn

@export_group("Fire Timers")
## Per-shot cooldown timer — its wait_time is set to the weapon's attack_speed (seconds) on each fire, and
## firing is blocked until it stops. Shorter = faster fire rate.
@export var attack: Timer
## The reload timer — runs for the weapon's reload_time (seconds); firing/swapping is blocked until it
## stops, at which point the clip refills.
@export var reload: Timer
## The weapon-swap timer — covers both the lower (holster) and raise phases of a swap (seconds); firing is
## blocked until the gun is fully back up.
@export var swap: Timer

@export_group("Audio")
## The gunfire sound player. Handed to WeaponAudio; plays the weapon's fire stream (pitched by remaining
## ammo) each shot, and the spray-paint hiss.
@export var attack_audio: AudioStreamPlayer3D
## The reload sound player. Handed to WeaponAudio; plays the per-weapon reload stream (or its authored
## default) when a reload starts.
@export var reload_sfx: AudioStreamPlayer3D
@onready var shell_impact: AudioStreamPlayer3D = $ShellImpact

## The generic impact sound player (a hit on a wall/prop, and an AI wielder's hit on a character). Handed
## to WeaponAudio; retargeted per shot to the weapon's impact_sound, played positionally at the hit point.
@export var impact: AudioStreamPlayer3D
## The player's hit-against-a-character sound player. Handed to WeaponAudio; retargeted per shot to the
## weapon's impact_enemy_sound and played at the hit point — the "you hit someone" feedback for the player.
@export var impact_enemy_hit: AudioStreamPlayer3D

## The dry-fire click player (empty clip / nothing chambered). Handed to WeaponAudio; played when you try
## to fire or reload with no ammo to chamber.
@export var empty_clip: AudioStreamPlayer3D

## Side systems, built code-side in _ready (null off-tree, so every facade that uses them null-guards):
## the spray colour picker + palette, and the gunfire sound playback.
var _spray: SprayPainter
var _audio: WeaponAudio

var current_weapon: WeaponData
var base_spread: float
var current_spread: float
var _swap_raising: bool = false
var holstered: bool = false  ## weapon put away (hidden; can't fire or reload) until brought back out
## While true the weapon is LOCKED away — set_holstered may still PUT it away but refuses to bring it back OUT, so
## every draw vector (fire-click draw, hold-R holster toggle, weapon swap) is blocked at the one chokepoint. The
## Player engages this while CARRYING a physics prop (hands full — the first-person arms are out), enforcing "you
## can't take your gun out while your arms are out." Defaults off; only the player's carry path touches it, so AI
## wielders and normal empty-handed play are unaffected. Cleared on drop / on the in-place revive (die/revive symmetry).
var draw_locked: bool = false
var gun_raised: bool = true  ## false while the view-model tweens into view (set by GunMesh); blocks firing mid-raise
var _drew_on_press: bool = false  ## the click that drew the weapon must not also fire; cleared on release
var _is_scoped: bool = false
## Emitted the instant the air-dash lock clears on landing — i.e. the dash just became available
## again. The player listens to flash the screen + chirp a "dash ready" cue.
signal air_dash_recharged

var _did_air_dash: bool = false
var _last_fire_msec: int = 0  ## Time.get_ticks_msec() of the last shot; 0 = never fired (reads as long-idle)

## Seconds since this weapon last fired (huge if it never has) — drives the view-model idle-lower in GunPose.
func seconds_since_fire() -> float:
	return float(Time.get_ticks_msec() - _last_fire_msec) / 1000.0

func _ready() -> void:
	inventory.weapon_changed.connect(_on_weapon_changed)
	# Spray colour picker + palette — its own child so this stays a thin firing hub.
	_spray = SprayPainter.new()
	_spray.host = self
	add_child(_spray)
	# Gunfire sound playback — its own child, handed the scene's audio players (our @export slots).
	_audio = WeaponAudio.new()
	add_child(_audio)
	_audio.setup(attack_audio, reload_sfx, impact, impact_enemy_hit, empty_clip, shell_impact)
	current_weapon = inventory.equipped_weapon
	# A wielder may add this Weapon before equipping a WeaponData (enemies do), so current_weapon
	# can be null here — the equip fires weapon_changed a beat later and seeds the spread then.
	if current_weapon:
		base_spread = current_weapon.pellet_spread
		current_spread = base_spread

func _on_weapon_changed(_weapon: WeaponData) -> void:
	current_weapon = _weapon
	base_spread = _weapon.pellet_spread
	current_spread = base_spread
	if _is_color_picker_open():
		_close_color_picker()  # swapping weapons dismisses the spray's colour picker

## Holster (put away + hide) the weapon, or bring it back out. Hold-R toggles it; dialogue forces it.
## While holstered the weapon can't fire or reload; gun_mesh hides via the holster_changed signal.
func toggle_holster() -> void:
	set_holstered(not holstered)

func set_holstered(on: bool) -> void:
	# Hands full (carrying a prop): allow PUTTING the weapon away, refuse bringing it back OUT. This is the single
	# gate that stops the fire-click draw, the hold-R toggle, and a weapon swap from taking the gun out mid-carry.
	if draw_locked and not on:
		return
	if on == holstered:
		return
	holstered = on
	if on and _is_color_picker_open():
		_close_color_picker()  # putting the can away dismisses its colour picker
	holster_changed.emit(on)

func _physics_process(_delta: float) -> void:
	# The press that drew a holstered weapon must not fire; clear that block once it's released.
	if _drew_on_press and not Input.is_action_pressed("Attack"):
		_drew_on_press = false
	# Reset the per-airtime dash lock once we're back on the ground so the next
	# airtime gets a fresh launch (single_air_dash weapons, e.g. melee).
	if character and character.is_on_floor() and _did_air_dash:
		_did_air_dash = false
		air_dash_recharged.emit()

## A carried prop was just released while the fire button MAY still be held — e.g. LEFT-CLICK throws the prop
## (see PickupRay's alternate-throw). Dropping the prop re-draws the holstered weapon, so treat this exactly like
## the FNV draw-click: that same held click must not ALSO fire the gun the instant it raises — require a release +
## fresh click. Guarded on the button actually being held, so a normal Z/E throw or a death release (fire button
## up) is a no-op; the flag clears itself on release in _physics_process. Called from Player._on_carry_changed.
func suppress_fire_for_carry_release() -> void:
	if Input.is_action_pressed("Attack"):
		_drew_on_press = true

## Which fist / hand threw the most recent attack: true = the ALT button (right click), false = primary.
## Read by FirstPersonBody.on_attack_play_animation to lead with the matching hand.
var last_attack_alt: bool = false

## The action bound to alt fire. Set by Player when it wires MouseInput.alt_attack, so the semi-auto
## once-per-click check below tests the button that actually fired rather than always testing "Attack".
var alt_attack_action: StringName = &"Zoom"

func can_fire() -> bool:
	return current_weapon != null and attack.is_stopped() and reload.is_stopped() and swap.is_stopped()

# Put the weapon on its normal fire cooldown without actually firing. Used by
# secondary actions (e.g. the melee launch) so they share the firing cadence.
func start_secondary_cooldown() -> void:
	if not current_weapon:
		return
	attack.wait_time = current_weapon.attack_speed
	attack.start()

# True only for "long" busy states (reload/swap) — NOT the attack cooldown
# between shots. Used to forcibly break ADS without pulsing the scope every
# time a rapid-fire weapon fires.
func is_reload_or_swap_active() -> bool:
	return not reload.is_stopped() or not swap.is_stopped()

## NPC-pooling reuse reset (NpcPool): stop the fire-cadence / reload / swap Timers and drop any in-flight swap. A body
## that died MID-RELOAD or MID-SWAP leaves these Timers running; parking removes it from the tree (Timers PAUSE), and
## on reuse (re-added) they RESUME and fire their timeout on the fresh life — a resumed swap would equip a stale
## `_pending_swap_weapon`, and a running cooldown blocks the first shot. Called from WeaponStance.reset_for_reuse
## (which holsters after). The magazine refill is Ammo.reset_for_reuse's job; `holstered` is set by holster_weapon().
func reset_for_reuse() -> void:
	if attack:
		attack.stop()
	if reload:
		reload.stop()
	if swap:
		swap.stop()
	_swap_raising = false
	_pending_swap_weapon = null

# Whether ADS may be (re)entered right now. Launch-on-scope weapons (melee) stay
# locked out of ADS after spending their one airborne dash until they land —
# otherwise you could re-scope mid-air just to dash again.
func can_enter_scope() -> bool:
	if current_weapon and current_weapon.launch_on_scoped_attack and current_weapon.single_air_dash:
		if character and not character.is_on_floor() and _did_air_dash:
			return false
	return true

## True while a fired shot is still resolving — the attack-cadence timer runs through the wind-up +
## cooldown. Lets ADS hold through a shot: a scoped sniper can't unscope until the shot finishes (see
## ScopeIn). Distinct from is_reload_or_swap_active, which force-breaks scope.
func is_shot_in_progress() -> bool:
	return not attack.is_stopped()

## Lob a paint blob from the muzzle on the weapon's attack cadence; it splashes a coloured decal
## wherever it lands (see PaintProjectile). No ammo, no damage — purely cosmetic graffiti.
func _do_spray_paint() -> void:
	attack.wait_time = current_weapon.attack_speed
	attack.start()
	var col := _resolved_paint_color()
	var proj := PaintProjectile.new()
	proj.velocity = character.get_aim_direction() * current_weapon.projectile_speed
	proj.shooter = character
	proj.paint_color = col
	get_tree().root.add_child(proj)
	var muzzle_pos: Vector3 = muzzle.global_position if muzzle else character.get_aim_origin()
	proj.global_position = muzzle_pos
	# Coloured muzzle flash to match the paint — reuses the bullet-hit spark, tinted (like the splat).
	GunFX.spawn_muzzle_flash(get_tree().root, muzzle_pos, col)
	# Spray hiss: play the weapon's audio but don't restart it every tick (that would stutter). Varied per
	# BURST, not per tick — the `playing` guard means each squeeze of the trigger gets one fresh pitch roll.
	if current_weapon.audio and not attack_audio.playing:
		attack_audio.stream = current_weapon.audio
		AudioManager.play_varied(attack_audio)

func _can_start_melee_attack() -> bool:
	if current_weapon == null or not current_weapon.is_melee:
		return true
	if character == null or not character.has_method(&"can_spend_stamina"):
		return true
	return character.can_spend_stamina(GameSettings.player_movement.stamina_melee_attack_cost)

func _spend_melee_attack_stamina() -> void:
	if current_weapon == null or not current_weapon.is_melee:
		return
	if character != null and character.has_method(&"spend_stamina"):
		character.spend_stamina(GameSettings.player_movement.stamina_melee_attack_cost)

## What a RANGED shot costs this wielder in stamina — the economy half of the price, over WeaponData's
## stamina_effort() (the "how big is this bang" half: damage, pellets, blast payload). A grenade launcher costs
## ~8x a pistol shot because its effort IS ~8x, not because anyone hand-priced it; stamina_cost_mult is only a
## per-weapon trim on the result. Melee returns 0 — a swing is priced by stamina_melee_attack_cost through the
## pair above, never here. Floored at 0 so a negative multiplier or damage authored by mistake can never REFILL
## the pool on every trigger pull.
##
## ⭐ The CLAMP is what keeps power and cadence from multiplying into an absurd drain. Cost is capped at
## stamina_shot_drain_ceiling x stamina_sprint_drain x this weapon's cadence, so cost/attack_speed can never
## exceed 0.95 x 18.0 = 17.1/sec for ANY weapon a designer can author — "shooting never costs more per second
## than sprinting" is a theorem here, not something the .tres files happen to respect. The max(attack_speed, 0.05)
## floor mirrors the divisor tests/test_combat_data.gd uses, so the bound is exact even at attack_speed 0.
## Break-even cadence for a 1.0-effort weapon is stamina_shot_cost / (ceiling x sprint_drain) = 1.8 / 17.1 =
## 0.105s — note WeaponData's DEFAULT attack_speed (0.1) sits just under it, so a bare unauthored weapon is
## mildly clamped; every shipped gun is well clear.
##
## GameSettings is an untyped autoload Node, so its property reads come back Variant — the tuning resource is
## bound to an explicitly TYPED local rather than inferred with `:=` (the house no-`:=`-from-a-Variant rule).
func _shot_stamina_cost() -> float:
	if current_weapon == null or current_weapon.is_melee:
		return 0.0
	var mv: PlayerMovementSettings = GameSettings.player_movement
	var raw := mv.stamina_shot_cost * current_weapon.stamina_effort() * current_weapon.stamina_cost_mult
	var ceiling := mv.stamina_shot_drain_ceiling * mv.stamina_sprint_drain * maxf(current_weapon.attack_speed, 0.05)
	return maxf(minf(raw, ceiling), 0.0)

## Charge the wielder for a shot that is ALREADY committed (ammo consumed) — the ranged twin of
## _spend_melee_attack_stamina(), called from the same beat so a dry click, a blocked click, a spray-paint blob
## and the scoped air dash (which pays stamina_air_dash_cost of its own) all cost nothing. It is charged in the
## SAME beat as the round itself, so a shot the wind-up / hit-flash awaits later ABORT (dialogue opened, the
## weapon got holstered, the wielder died) forfeits its stamina exactly the way it already forfeits its ammo —
## the two stay in lockstep rather than one refunding and the other not.
##
## ⭐ Deliberately UNGATED — there is no _can_start_shot() mirroring _can_start_melee_attack(). Refusing a SHOT on
## an empty pool would leave an exhausted player with no attack at all (fists are melee, so the melee gate already
## refuses them), so firing always works and spend_stamina() no-ops once the pool is ALREADY at/below zero. The
## cost's real bite is the post-spend regen hold plus the sprint budget it eats, not a lockout.
##
## Note the one sharp edge that follows from StaminaManager.can_spend_stamina being a HAS-ANY test, not HAS-ENOUGH:
## a shot from a positive-but-insufficient pool pays in FULL and lands the pool negative (bounded at one shot's cost
## below zero). While it is in debt every GATED verb is refused — jump, slide, sprint, dash, grapple, and fists — so
## a last shell really can cost you the punch that follows it, for the ~0.35s hold plus the climb back past zero.
## That is the pre-existing overdraw melee/jump/slide already had, now reachable from the trigger; the gun itself
## still fires, which is the property that matters.
##
## Only the Player answers the has_method duck-type (player.gd forwards to StaminaManager), so an NPC — which has
## no stamina pool — keeps firing for free, exactly like the melee spend above.
func _spend_shot_stamina() -> void:
	var cost := _shot_stamina_cost()
	if cost <= 0.0:
		return
	if character != null and character.has_method(&"spend_stamina"):
		character.spend_stamina(cost, _shot_regen_hold())

## How long a shot holds off stamina recovery. NEVER shorter than the time until this weapon can physically fire
## AGAIN — that is the whole point, and it is what makes the cost mean anything: if the pool can regenerate
## between two shots, a weapon refunds its own price and no amount of firing will ever run you down. The pistol
## did exactly that before the shot hold existed (0.44s cadence against a 0.35s movement delay earned 2.16
## standing still against a 1.8 cost).
##
## ⭐ attack_speed is only the COOLDOWN, and taking it for the interval is the trap this method exists to close:
## a shot that EMPTIES the clip cannot be followed until the magazine is back, so for a small magazine the RELOAD
## is the real gap. sniper_wep.tres is the case — it cycles every 0.668s on paper, but max_ammo 1 + auto_reload
## means every single shot is followed by auto_reload_delay + reload_time = 3.5s, during which a flat 1.5s hold
## would hand back 24.0 x 2.0 = 48 stamina against a 2.25 shot. Deriving the hold from the real gap keeps
## "you never regenerate between your own shots" true BY CONSTRUCTION, for any weapon anyone authors later.
##
## Reads the post-shot clip (this runs after clip.consume_ammo() succeeded), so current_ammo == 0 means THIS shot
## was the one that emptied it.
func _shot_regen_hold() -> float:
	var base: float = GameSettings.player_movement.stamina_regen_delay_after_shot
	if current_weapon == null:
		return base
	var gap := current_weapon.attack_speed
	if clip != null and clip.current_ammo <= 0 and not current_weapon.is_infinite_ammo:
		gap = maxf(gap, GameSettings.weapon_general.auto_reload_delay + current_weapon.reload_time)
	return maxf(base, gap)

## --- Spray-paint colour picker facade (forwards to the SprayPainter child) ---

## The colour the spray paints with — delegated to the picker child; white if it isn't built yet
## (off-tree), matching the monolith's no-palette default.
func _resolved_paint_color() -> Color:
	return _spray.resolved_color() if _spray else Color.WHITE

func _is_color_picker_open() -> bool:
	return _spray != null and _spray.is_open()

func _close_color_picker() -> void:
	if _spray:
		_spray.close()

## True when a shot queued behind a wind-up / hit-flash await must be ABORTED because the world changed while we
## waited. Death applies to any wielder (no posthumous muzzle flash / damage); the holster / carry-lock / dialogue
## gates are player-only (from_ai keeps firing — the world runs in real time for AI). Mirrors the pre-fire guards
## at the top of _on_mouse_input_attack so a delayed shot honours the same rules a fresh click would. is_inside_tree()
## is kept INLINE at each await site (not folded in here) so an off-tree unit test can exercise these branches.
func _fire_should_abort(from_ai: bool) -> bool:
	if character != null and not character.is_alive():
		return true
	if from_ai:
		return false
	return holstered or draw_locked or DialogueManager.is_active()

func _on_mouse_input_attack(_camera: Camera3D = null, from_ai := false, alt := false) -> void:
	if not current_weapon:
		return
	# ALT FIRE (the second attack button, MouseInput.alt_attack). Only a weapon that declares its swing a PUNCH
	# takes it — for everything else that button is ADS and must stay ADS. Unarmed uses it for the RIGHT fist.
	if alt and not current_weapon.view_model_punch:
		return
	# Don't fire while the spray's colour picker is open — those clicks are for the picker.
	if _is_color_picker_open():
		return
	# Don't fire from player input during a conversation — the click that advances the dialogue
	# box shouldn't also shoot. AI wielders still fire (the world keeps running in real time).
	if not from_ai and DialogueManager.is_active():
		return
	# Hands full (carrying a prop): the weapon is LOCKED away — a player click can neither draw it nor fire. Stated
	# here so the fire path reads the rule directly (set_holstered refuses the draw anyway), and so a locked-out click
	# never churns _drew_on_press on an action that can't do anything.
	if not from_ai and draw_locked:
		return
	if holstered:
		# Clicking with the weapon put away draws it (FNV-style); this click doesn't also fire.
		if not from_ai:
			set_holstered(false)
			_drew_on_press = true
		return
	if _drew_on_press:
		return  # still holding the draw click — release and click again to fire
	if not from_ai and not gun_raised:
		return  # view-model still raising in (reload / swap / draw) — don't fire from the low muzzle
	if !attack.is_stopped() or !reload.is_stopped() or !swap.is_stopped():
		return
	# Semi-auto weapons (e.g. melee) fire once per click instead of continuously
	# while held (MouseInput emits `attack` every frame the button is down). An AI
	# wielder (from_ai) sets its own cadence, so it skips the player input check.
	if not from_ai and not current_weapon.auto_fire and not Input.is_action_just_pressed(alt_attack_action if alt else &"Attack"):
		return
	# Bank WHICH button threw this attack, for anything that poses off it — the player's fists read it to pick
	# the leading hand. Set only once every gate above has passed, so a refused click never re-poses the arms.
	last_attack_alt = alt
	# Spray paint: tag the aimed surface with a coloured decal instead of attacking.
	if current_weapon.is_spray_paint:
		_do_spray_paint()
		return
	# Attacking while scoped launches the player instead of firing (e.g. melee
	# dash). Hip-fire falls through to the normal attack below. AI never scopes.
	# Air dash is an UNLOCKABLE upgrade: without it, attacking-while-scoped falls through to a normal attack
	# (duck-typed; a wielder with no unlock system — including AI — is treated as having it).
	# `character` is typed Character (no has_mechanic — only Player has it), so the has_mechanic() call resolves
	# dynamically (Variant): the `or`-chain has no inferable type, so annotate `bool` explicitly (no := here).
	var dash_ok: bool = character == null or not character.has_method(&"has_mechanic") or character.has_mechanic(&"air_dash")
	if not from_ai and current_weapon.launch_on_scoped_attack and _is_scoped and dash_ok:
		# One dash per airtime: block a second airborne launch until you land.
		if current_weapon.single_air_dash and character and not character.is_on_floor() and _did_air_dash:
			return
		if character and character.has_method(&"spend_stamina") and not character.spend_stamina(GameSettings.player_movement.stamina_air_dash_cost):
			return
		_do_launch_attack()
		return
	if not _can_start_melee_attack():
		return
	var ammo_before := clip.current_ammo
	if !clip.consume_ammo():
		if not from_ai and Input.is_action_just_pressed("Attack") and _audio:
			_audio.play_empty()
		return
	_spend_melee_attack_stamina()
	_spend_shot_stamina()
	attack.wait_time = current_weapon.attack_speed
	attack.start()
	# Wind-up: heavy weapons (melee) pause briefly after the click before the
	# swing actually lands, for weight. The cooldown already started above, so
	# this delay sits inside the normal firing cadence. 0 = instant.
	if current_weapon.attack_windup > 0.0:
		var _weapon := current_weapon
		await get_tree().create_timer(current_weapon.attack_windup).timeout
		if current_weapon != _weapon:
			return
	# The wind-up await can outlive the wielder (freed enemy) OR the world can change under us: a delayed shot must
	# honour the same rules a fresh click would — drop it if the wielder DIED, the weapon got holstered / carry-locked,
	# or dialogue started while we waited (all mirrored in _fire_should_abort). is_inside_tree() stays inline.
	if not is_inside_tree() or _fire_should_abort(from_ai):
		return
	flash_muzzle.emit()
	_last_fire_msec = Time.get_ticks_msec()  # view-model idle-lower hook (GunPose reads seconds_since_fire)
	# Fire feedback now lives on the wielder (screen shake for a player, nothing for an
	# enemy) rather than on the Weapon component.
	character.on_weapon_fired(current_weapon)

	# The player's full-screen white hit-flash on an instant-hit (hitscan) shot. Gated on the Accessibility
	# "Screen Flashes" toggle (read live) so a photosensitive player doesn't get a whole-screen white strobe
	# under automatic fire — the world muzzle light + fire audio still play, so firing keeps its feedback.
	# The 85ms hitscan beat (flash + abort window) is combat timing and runs for EVERY instant-hit shot; the Accessibility
	# "Screen Flashes" toggle gates ONLY whether the full-screen white flash is VISIBLE, never whether/when the shot lands.
	# (Gating the whole block on the toggle used to make an accessibility setting change combat outcomes: flash-off shots
	# skipped the await + abort, so the same shot could deal 0 vs full damage in the death-race window.) The world muzzle
	# light + fire audio still play, so a photosensitive player keeps firing feedback without the strobe.
	# PUNCHES never flash: fists are hitscan too, but a white screen-pop per swing reads as a strobe, not gunfire
	# feedback — so view_model_punch weapons take the same VISIBILITY-only exemption (the 85ms beat still runs).
	var _hit_flash := character.get_hit_flash()
	if _hit_flash and current_weapon.projectile_life_time <= 0.0:
		var _show_flash: bool = Settings.screen_flash_enabled and not current_weapon.view_model_punch
		# Per-weapon flash strength (WeaponData.hit_flash_opacity): the knife authors 0.5 so its fast repeat
		# swings pop softly instead of strobing (the same concern that exempts punches above, dimmed rather
		# than dropped). Applied to the sprite's modulate for THIS flash only and restored on hide, because
		# the RAM-reactor break flash reuses the same sprite and must keep its full-strength white.
		var _flash_sprite := _hit_flash as SpriteBase3D
		if _show_flash:
			if _flash_sprite:
				_flash_sprite.modulate.a = current_weapon.hit_flash_opacity
			_hit_flash.visible = true
		await get_tree().create_timer(0.085).timeout
		# This 85ms can outlive the wielder (an enemy freed mid-flash) OR the world can change (holster / carry-lock /
		# dialogue-start / wielder-death) — bail before the audio / physics below. Clear the flash FIRST so an aborted
		# shot never strands it visible (a no-op when it was never shown). _hit_flash is non-null (enclosing guard).
		if not is_inside_tree() or _fire_should_abort(from_ai):
			_hit_flash.visible = false
			if _flash_sprite:
				_flash_sprite.modulate.a = 1.0
			return
		_hit_flash.visible = false
		if _flash_sprite:
			_flash_sprite.modulate.a = 1.0

	if _audio:
		_audio.play_fire(current_weapon, ammo_before)
	if clip.current_ammo == 0 and _audio:
		_audio.play_empty()
	if _audio:
		_audio.play_shell()
	if current_weapon.spawns_casing:
		# Per-weapon casing size: resize the ejector right before it fires so this shot's shell drops at
		# the weapon's casing_size_scale (1.0 = unchanged; the sniper's fat round is authored bigger).
		if shell_drop and shell_drop.has_method(&"set_casing_scale"):
			shell_drop.set_casing_scale(current_weapon.casing_size_scale)
		shell_particle.emit()
	# Per-weapon impact sounds; fall back to the nodes' authored defaults when this weapon has none.
	if _audio:
		_audio.apply_impact_defaults(current_weapon)
	var _space_state := get_world_3d().direct_space_state
	# Aim comes from the wielder (its WeaponHost contract), not a Camera3D, so this same
	# fire path works for a player (camera aim) or an enemy (AI aim).
	var _ray_origin := character.get_aim_origin()
	var _spawn_point := muzzle.global_position if muzzle else _ray_origin
	var _direction := character.get_aim_direction()
	var _aim_basis := character.get_aim_basis()
	var _active_camera := get_viewport().get_camera_3d()  # sampled once: no awaits between pellets, same frame throughout
	# ADS extends reach: a scoped shot traces farther than the weapon's hip-fire effective_range. AI never
	# scopes, so _is_scoped is player-only. Sampled once here with the other per-shot handles.
	var _range_mult: float = GameSettings.weapon_general.scope_range_multiplier if _is_scoped else 1.0

	# Did this shot connect with an NPC (across ALL pellets)? Drives the wielder's post-shot reaction:
	# the player suppresses its reckless-fire bystander remark when the shot actually hit someone.
	var _hit_npc := false

	# CT-3: roll the on-hit status ONCE per shot (not per pellet). The null-effect short-circuit means a normal
	# weapon never calls randf(), so its shot stays deterministic; run_pellet applies it on the first character hit.
	# Computed for BOTH branches below — an AI live round carries the roll via ProjectileSpawner/projectile.gd.
	var apply_status := current_weapon.on_hit_effect != null and randf() < current_weapon.on_hit_chance

	# THE "enemies never hitscan" rule (2026-08-25): an AI wielder's RANGED shot skips the instant damage
	# trace entirely and every pellet spawns as a LIVE projectile — travel time + the wielder's aim error
	# make incoming fire dodgeable. Melee/spray/no-scene weapons keep the trace (their damage can't ride a
	# round — the default-knife NPC would deal zero); the player's path is untouched.
	var _ai_live_rounds := from_ai and ShotResolver.ai_fires_live_projectile(current_weapon)

	for i in range(current_weapon.pellet_count):
		var spread := current_spread
		if character != null and character.has_method(&"limb_spread_penalty"):
			spread += character.limb_spread_penalty()  # a crippled arm shakes the wielder's aim
		# The WIELDER's marksmanship widens RANGED shots: 0 for the player (its accuracy is AimSway/bloom's
		# job) — an NPC returns its gunplay-scaled aim-error cone (npc.gd aim_error_spread), so who an enemy
		# IS shapes how it shoots. Melee is exempt: a knife swing is reach, not marksmanship.
		if character != null and not current_weapon.is_melee and character.has_method(&"aim_error_spread"):
			spread += character.aim_error_spread()
		var pellet_direction := ShotResolver.spread_direction(_direction, _aim_basis, spread)
		if _ai_live_rounds:
			# No trace ran, so aim the round at a far point down the pellet's own eye-ray (the same
			# visual_tracer_fallback_distance endpoint run_pellet reports on a whiff) — converging the
			# muzzle-spawned round onto the aim line. visual_only=false: THIS round carries the damage;
			# projectile.gd lands crit/status/knockback/collateral/impact-audio at physical contact.
			var _far_target: Vector3 = _ray_origin + pellet_direction * GameSettings.weapon_general.visual_tracer_fallback_distance
			spawn_projectile.emit(_spawn_point, (_far_target - _spawn_point).normalized(), false, apply_status)
			if current_weapon.has_tracer:
				GunFX.spawn_tracer(get_tree().root, _spawn_point, _far_target, _active_camera)
			continue
		# The pellet's whole pierce-trace walk lives in DamageTrace (a stateless static, like ShotResolver /
		# GunFX / DamageApplier): raycast, damage application, overkill pierce-through, hit FX + impact
		# audio. Tree-dependent handles (space state, FX root, camera) were sampled ONCE above and are
		# passed in; the per-pellet RESULT comes back so the emits below stay on this Attack node
		# (weapon.tscn wires spawn_projectile from here) and the post-shot reaction sees the whole shot.
		var traced := DamageTrace.run_pellet(_space_state, get_tree().root, _active_camera, current_weapon,
				character, _ray_origin, pellet_direction, from_ai, _audio, _range_mult, apply_status)
		if traced["hit_npc"]:
			_hit_npc = true

		var _visual_target: Vector3 = traced["visual_target"]
		var _visual_direction := (_visual_target - _spawn_point).normalized()
		spawn_projectile.emit(_spawn_point, _visual_direction, traced["hit_anything"], apply_status)
		if current_weapon.has_tracer:
			GunFX.spawn_tracer(get_tree().root, _spawn_point, _visual_target, _active_camera)

	# Post-shot reaction now that every pellet's trace has resolved: the player remarks on a reckless
	# discharge ONLY if this shot didn't connect with an NPC (an enemy who needs no reaction no-ops).
	# is_instance_valid: the wind-up / hit-flash awaits above can outlive an NPC wielder freed mid-shot.
	if is_instance_valid(character):
		character.on_shot_resolved(current_weapon, _hit_npc)

	play_animation.emit()

	# Recoil shoves the wielder back (the player uses it to rocket-jump). An NPC flagged
	# immune_to_weapon_knockback skips it, so a heavy-recoil weapon doesn't fling it around. get() is
	# null (falsy) for a wielder without the field (e.g. the player), so only flagged NPCs are immune.
	if is_instance_valid(character) and not character.get(&"immune_to_weapon_knockback"):
		var knockback_dir := -_direction
		character.explosion_velocity += knockback_dir * current_weapon.self_knockback

	# Auto-reload: a weapon flagged for it starts a reload a short beat (the tunable auto_reload_delay)
	# after a shot empties the clip — a bolt-action sniper re-chambers itself, but not jarringly instantly.
	if current_weapon.auto_reload and clip.current_ammo == 0:
		var _ar_weapon := current_weapon
		await get_tree().create_timer(GameSettings.weapon_general.auto_reload_delay).timeout
		# Bail if the wielder was freed or swapped weapons during the wait; otherwise _on_reload_reload
		# self-guards (no-op if the clip is already full, or a reload/swap is underway).
		if is_inside_tree() and current_weapon == _ar_weapon:
			_on_reload_reload()


## Generic fire entry for an AI wielder (e.g. a ranged enemy): runs the same shot as a
## player click, but without the player-input gating (semi-auto, ADS launch, empty-click).
## The AI decides cadence; aim + feedback come from the wielder's Character host contract.
func try_fire() -> void:
	_on_mouse_input_attack(null, true)


func _on_reload_reload() -> void:
	if not current_weapon:
		return
	if holstered:
		return  # can't reload a holstered weapon — unholster (hold R) first
	if !reload.is_stopped() or !swap.is_stopped():
		return
	if clip.current_ammo >= current_weapon.max_ammo:
		return
	# Reserve gate: a calibered PLAYER weapon can only reload if the backpack holds matching ammo. With
	# none, click empty (out of ammo) instead of running a pointless reload. (Free-refill weapons + AI
	# wielders always pass.)
	if not clip.has_reload_supply():
		if _audio:
			_audio.play_empty()
		return
	# Fold any background top-up for this gun into the normal foreground reload the player just asked for.
	clip.cancel_background_reload(current_weapon)
	reload.wait_time = current_weapon.reload_time
	# Per-weapon reload sound; fall back to the node's authored default when this weapon has none.
	if _audio:
		_audio.play_reload(current_weapon)
	reload.start()
	reload_started.emit()


## The newest equip request that arrived while a swap was already mid-flight — chained the moment the raise
## finishes, so rapid wheel-scrolls / UI clicks land on the FINAL selection instead of being silently
## dropped (the bag's equipped_item is set optimistically by the equip bridge BEFORE the request lands
## here, so dropping one desynced the bag + hotbar highlight from the hands).
var _pending_swap_weapon: WeaponData = null

func _on_swap_weapons_equip_this(_weapon: WeaponData) -> void:
	if _weapon == current_weapon:
		_pending_swap_weapon = null  # asked for what's already drawn — drop any stale queued request
		return
	if !swap.is_stopped():
		_pending_swap_weapon = _weapon  # mid-swap: queue the NEWEST request; the raise end chains into it
		return
	# Swapping while reloading is allowed: hand the in-progress reload to the clip as a slower
	# BACKGROUND reload for the OUTGOING weapon, so it keeps topping up while you fight with another gun.
	if !reload.is_stopped():
		clip.start_background_reload(current_weapon, reload.time_left)
		reload.stop()
	# Equipping a weapon DRAWS it: clear any holster (hold-R / dialogue) so the newly-shown weapon is
	# actually shootable. Otherwise the swap shows the new gun in hand but `holstered` stays true, so it
	# can't fire until you separately unholster — which reads as a bug. (No-op if already drawn.)
	set_holstered(false)
	_swap_raising = false
	swap.wait_time = GameSettings.weapon_general.swap_time
	swap.start()
	swap_started.emit()
	inventory.equip(_weapon)


func _on_swap_timeout() -> void:
	if not _swap_raising:
		# Down phase finished: swap the mesh + start the raise. Keep the swap
		# timer running for the raise so attacks stay blocked until the gun is
		# fully back up (can_fire() checks swap.is_stopped()).
		swap_finished.emit()
		_swap_raising = true
		swap.wait_time = GameSettings.weapon_general.swap_raise_duration
		swap.start()
	else:
		# Raise phase finished: weapon is ready, attacks re-enabled.
		_swap_raising = false
		# A request queued mid-swap chains into its own swap now, so the LAST selection wins (the equip
		# handler's own current_weapon guard drops a queue that circled back to the drawn gun).
		if _pending_swap_weapon != null:
			var next := _pending_swap_weapon
			_pending_swap_weapon = null
			_on_swap_weapons_equip_this(next)


func _on_scope_in_scoped_in(_tf: bool) -> void:
	_is_scoped = _tf
	current_spread = base_spread / GameSettings.weapon_general.scope_spread_divisor if _tf else base_spread

func _do_launch_attack() -> void:
	# Launch in the look direction with a slight upward arc (blast system, so it
	# decays and lets the player ram enemies). Goes on the normal fire cooldown.
	# Dashing snaps the wielder out of ADS immediately (the cooldown then blocks an
	# instant re-scope until the dash settles).
	if scope_in:
		scope_in.force_unscope()
	# Spend the one airborne dash so you can't launch again until you land.
	if current_weapon.single_air_dash and character and not character.is_on_floor():
		_did_air_dash = true
	if character:
		var look_dir := character.get_aim_direction()
		character.explosion_velocity += look_dir * current_weapon.launch_force + Vector3.UP * current_weapon.launch_upward
		# The dash whoosh (FOV punch + shake) is wielder feedback, same idea as
		# on_weapon_fired — the player does it, an enemy needs none.
		character.on_weapon_launched(current_weapon)
	if current_weapon.whiz_sound:
		AudioManager.play_2d_sfx(current_weapon.whiz_sound, 0.0, randf_range(0.9, 1.1))
	attack.wait_time = current_weapon.attack_speed
	attack.start()
