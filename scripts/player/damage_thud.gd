class_name DamageThud
extends Node3D

## The low, heavy "underwater car door" one-shot played under the audio-desaturation duck when the
## PLAYER takes a real, non-lethal hit — the body that gives the flinch its weight. Lifted out of
## Character so the throttle state and the play call live in one place; Character keeps a thin
## _play_damage_thud() facade that take_damage() calls on the survive branch.
##
## Code-built child of Character (added in its _ready). Reads the host's damage_thud @export and the
## DAMAGE_THUD_* consts (both stay on the root so the editor/.tscn can still set them); the only
## state — the cooldown stamp — lives here since nothing outside Character reads it by name.
##
## Gated strictly to the Player group (checked on the HOST, not this node) so NPC hits stay silent,
## and throttled so a burst (shotgun pellets, a DoT tick stack) plays ONE thud, not a machine-gun.

## The actor we belong to — set right after .new(), before add_child. We read its damage_thud stream
## and DAMAGE_THUD_* consts off it, and gate on ITS group membership.
var _host: Character

## Last time (ms) a damage thud fired, for the cooldown throttle. Mirrors the monolith's
## _last_damage_thud_ms seed so the very first hit always passes the gap check.
var _last_damage_thud_ms: int = -100000

## Play the low, heavy damage thud — but ONLY when the host is the player (Character is the shared
## base for NPCs too, so we gate on the Player group to keep enemy hits silent) and only if the
## cooldown has elapsed, so a flurry of hits in one moment doesn't machine-gun the sound. Routed 2D
## through AudioManager (which no-ops on a null stream, so a cleared slot just disables the thud).
func play() -> void:
	if not _host.is_in_group(&"Player"):
		return
	var now := Time.get_ticks_msec()
	if now - _last_damage_thud_ms < Character.DAMAGE_THUD_COOLDOWN_MS:
		return
	_last_damage_thud_ms = now
	AudioManager.play_2d_sfx(_host.damage_thud, Character.DAMAGE_THUD_VOLUME_DB)
