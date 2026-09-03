class_name AirDash
extends Ability

## AIR DASH ability — drop one under a Player to grant the Cruelty-Squad launch: TAP the AirDash key (default LEFT
## ALT) to fling yourself where you are LOOKING, once per airtime.
##
## OWNS THE WHOLE VERB. It used to be a bare GATE, with the behaviour living in the WEAPON
## (Attack._do_launch_attack), fired by ATTACKING WHILE SCOPED with a `launch_on_scoped_attack` weapon — i.e. you
## had to ADS the knife and swing to dash. That gesture is gone: the dash is its own key, it needs no weapon, and
## it works with a gun out, empty-handed, or mid-reload. The tuning that lived on WeaponData (launch_force /
## launch_upward / launch_screen_shake) moved to the exports below, seeded with melee.tres's tuned numbers so the
## dash FEELS identical to the one it replaces.
##
## ⭐The defaults MUST live in THIS SCRIPT, not just in AirDash.tscn: a paid chip install / a save reload rebuilds
## the ability through AbilityManager._build's `load(script).new()`, which NEVER reads the .tscn — an editor-only
## default would install a 0-force dash. (The same trap the scanner implants hit.)
##
## The Player calls tick() at its physics beat (before apply_blast, so the impulse decays from this very frame like
## any other blast) and forwards the recharge cue. No AirDash node = the key does nothing; a DISABLED node (the
## Implants-tab switch-off) refuses to dash, through the host's has_mechanic gate.

const DASH_ACTION := &"AirDash"

@export_group("Impulse")
## Speed flung along the AIM direction (m/s), stacked onto explosion_velocity like a blast so it DECAYS and lets
## you ram people. Was melee.tres's launch_force.
@export var dash_force: float = 8.0
## Extra straight-UP speed mixed into the dash so it ARCS instead of firing flat — this is what lets you dash a gap
## and still clear the lip. Was WeaponData.launch_upward's default.
@export var dash_upward: float = 4.0

@export_group("Cadence")
## Seconds before the dash can fire again, grounded or airborne. Was the melee weapon's attack_speed (0.88), which
## doubled as the launch cooldown; the dash owns its own clock now that no weapon is involved.
@export var cooldown: float = 0.88
## Only ONE dash per airtime — the lock clears on landing (and chirps air_dash_recharged). Off = the cooldown is
## the only limit in the air. Was melee.tres's single_air_dash.
@export var single_air_dash: bool = true

@export_group("Feedback")
## Screen-shake trauma on the launch. Was WeaponData.launch_screen_shake's default.
@export var screen_shake: float = 0.6
## The whoosh. Preloaded as the SCRIPT default (see the header) so a chip-installed dash is never silent.
@export var dash_sound: AudioStream = preload("res://assets/audio/sfx/Whoosh.mp3")

## Emitted the instant the per-airtime lock clears on landing — i.e. the dash just became available again. The
## Player listens to flash the screen + chirp a "dash ready" cue. (Moved here from Attack with the rest of the
## dash; the Player's handler is unchanged.)
signal air_dash_recharged

var _did_air_dash: bool = false   ## the one airborne dash is spent; cleared on landing
var _cooldown_left: float = 0.0
var _has_action: bool = false     ## false when the InputMap has no AirDash action (a stripped test project)

func ability_id() -> StringName:
	return &"air_dash"

func setup(player: Node) -> void:
	super.setup(player)
	_has_action = InputMap.has_action(DASH_ACTION)

func _ready() -> void:
	# Editor-placed nodes register in Player._ready (setup runs after this), so resolve the action here too — the
	# GrappleHook idiom. Cheap and idempotent.
	_has_action = InputMap.has_action(DASH_ACTION)

## The physics beat, called by Player._physics_process BEFORE apply_blast(). Ticks the cooldown, clears the
## per-airtime lock on landing (chirping the recharge cue), and fires a dash on a fresh press.
##
## Deliberately NOT a self-owned _physics_process: driven from the host beat, it FREEZES with the player
## (die() calls set_physics_process(false)), so a corpse can't dash out of its own death cinematic.
func tick(delta: float) -> void:
	if host == null:
		return
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _did_air_dash and _host_on_floor():
		_did_air_dash = false
		air_dash_recharged.emit()
	if _input_locked() or not _has_action or not Input.is_action_just_pressed(DASH_ACTION):
		return
	if not can_dash():
		return
	# Stamina is spent LAST, once every other gate has passed — a refused dash must never bill the player.
	if host.has_method(&"spend_stamina") \
			and not host.spend_stamina(GameSettings.player_movement.stamina_air_dash_cost):
		return
	dash()

## Whether a dash could fire RIGHT NOW, stamina aside: the implant is switched on, the cooldown has expired, and
## the airborne dash isn't already spent. Split out so a HUD (or a test) can ask without firing one.
func can_dash() -> bool:
	if host == null or _cooldown_left > 0.0:
		return false
	# `enabled` is read through the HOST's gate, so an Implants-tab switch-off kills the key exactly as it kills a
	# grapple fire. Duck-typed: a bare test host with no ability system reads as "granted".
	if host.has_method(&"has_mechanic") and not host.has_mechanic(&"air_dash"):
		return false
	if single_air_dash and _did_air_dash and not _host_on_floor():
		return false
	return true

## Fire the dash unconditionally (every gate already passed): an aim-direction impulse with a touch of lift,
## stacked onto the BLAST channel so it decays and rams, exactly as the old scoped launch did.
func dash() -> void:
	if host == null:
		return
	if single_air_dash and not _host_on_floor():
		_did_air_dash = true
	_cooldown_left = cooldown
	# Duck-typed host reads: a stub Node without these is simply not launchable (the crash mode the .get()/
	# has_method guards exist for — see the LootScreen precedent), never a runtime error.
	var blast: Variant = host.get(&"explosion_velocity")
	if blast is Vector3 and host.has_method(&"get_aim_direction"):
		var aim: Vector3 = host.get_aim_direction()
		host.set(&"explosion_velocity", (blast as Vector3) + aim * dash_force + Vector3.UP * dash_upward)
	if host.has_method(&"on_air_dash"):
		host.on_air_dash(screen_shake)
	if dash_sound:
		AudioManager.play_2d_sfx(dash_sound, 0.0, randf_range(0.9, 1.1))

## Implants-tab switch-off hygiene: hand the airborne dash back, so switching the implant off MID-FALL and straight
## back on doesn't leave it stuck behind a lock the player can no longer clear by landing. Matches
## Grapple.on_deactivated severing its rope.
func on_deactivated() -> void:
	_did_air_dash = false
	_cooldown_left = 0.0

## No dashing THROUGH a menu or a conversation. ⭐Load-bearing: since no modal pauses the tree, the shop /
## backpack / ATM / chess screens all reach this beat for real — Player._physics_process only zeroes input_dir,
## which a key poll like ours sails straight past. Same lock GrappleHook uses, minus the death half (our beat
## stops with the player's physics). Duck-typed so a stub host with no _dead field never errors.
func _input_locked() -> bool:
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return true
	return host != null and host.get(&"_dead") == true


## Reset for a fresh life / an in-place revive: hand the airborne dash and the cooldown back, so a dash spent on
## the death frame isn't still spent after the respawn (the wall-climb reset() precedent, and the same reasoning
## as the explosion_velocity zeroing that sits beside the call sites). Same body as on_deactivated.
func reset_for_life() -> void:
	on_deactivated()


## Grounded per the host, defaulting to TRUE when it can't answer — a stub host then never engages the
## per-airtime lock (the neutral "feature off" fallback), instead of erroring on a missing method.
func _host_on_floor() -> bool:
	if host == null or not host.has_method(&"is_on_floor"):
		return true
	return bool(host.is_on_floor())
