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

## How far below 1.0 we re-pitch the one-shot so it lands deep and bassy — a heavy body-blow, not the
## bright wooden knock the raw placeholder asset is. 0.6 drops it ~7 semitones (and stretches it
## longer), which is what gives the thud its stark, sub-heavy "felt in the chest" weight without
## authoring a new asset. Lives here, on the node that owns the play call, so it can be tuned in one
## place; passed straight to AudioManager.play_2d_sfx as the pitch_scale. Lower = deeper/longer.
const DAMAGE_THUD_PITCH: float = 0.6

## Extra dB stacked on top of the host's DAMAGE_THUD_VOLUME_DB to make the hit actually punch — the
## root const is the editor/.tscn-facing base (kept intact so tests/the inspector still read it), and
## this boost is the felt-loudness bump applied at the play site. +9 dB roughly doubles perceived
## loudness, lifting the deep, slowed thud from a background duck to a heavy impact. Tune to taste.
const DAMAGE_THUD_VOLUME_BOOST_DB: float = 9.0

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
	# Base (root, editor-tunable) volume + the felt-loudness boost, and re-pitched well below 1.0 so
	# the placeholder wooden knock lands as a deep, bassy body-blow under the audio-desaturation duck.
	AudioManager.play_2d_sfx(_host.damage_thud, Character.DAMAGE_THUD_VOLUME_DB + DAMAGE_THUD_VOLUME_BOOST_DB, DAMAGE_THUD_PITCH)
