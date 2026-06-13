class_name RadioPlaybackState
extends RefCounted

## Pure, Node-free duck/settle state machine for the in-world Radio — the brain of the "fallback-only
## diegetic radio" slice, and the same logic the Spotify path reuses later. No Node, no transform, no HTTP,
## so the whole thing runs headless in GUT without tripping the engine-error wall that fails off-tree
## transform tests. Both Radio._process and the unit tests drive it via tick(); it reports the fallback
## player's target volume (current_db, faded each tick) and an edge-triggered play/pause intent
## (external_edge) for the eventual Spotify controller.
##
## The radio is OFF by default. set_playing(true) switches it on; it then sounds (current_db -> audible_db)
## EXCEPT while SUPPRESSED — combat, the post-combat settle linger, or an open dialogue/menu — during which
## it ducks toward silent_db. This is the INVERSE of MusicDirector (which fades combat music IN): here combat
## fades the radio OUT, then it breathes back in after the fight.

var audible_db: float = 0.0       ## the "on, audible" target (the fallback player's authored volume)
var silent_db: float = -60.0      ## the ducked/off floor — inaudible while the stream still plays underneath
var fade_pause_time: float = 0.4  ## seconds audible -> silent when combat hits (duck fast)
var fade_resume_time: float = 1.2 ## seconds silent -> audible once the coast clears (ease back in)
var settle_cooldown: float = 3.0  ## seconds the radio stays ducked after the last enemy disengages

var current_db: float = -60.0     ## the live, fading volume Radio applies to its fallback player each tick
var _playing: bool = false        ## the radio is switched ON
var _settle_t: float = 0.0        ## remaining post-combat linger
var _want_audible: bool = false   ## last tick's "should be sounding" decision
var _edge: int = 0                ## this tick's transition: +1 just became audible, -1 just ducked, 0 none

## Set the tunables once before ticking. Clamps the fade times above zero so a designer's 0 can't
## divide-by-zero in the move_toward step, and seeds current_db at the silent floor (the radio starts off).
func configure(p_audible_db: float, p_silent_db: float, p_fade_pause: float, p_fade_resume: float, p_settle: float) -> void:
	audible_db = p_audible_db
	silent_db = p_silent_db
	fade_pause_time = maxf(p_fade_pause, 0.001)
	fade_resume_time = maxf(p_fade_resume, 0.001)
	settle_cooldown = maxf(p_settle, 0.0)
	current_db = silent_db

## Switch the radio on/off. Turning it off clears the settle linger so a fresh power-on isn't still ducked.
func set_playing(on: bool) -> void:
	_playing = on
	if not on:
		_settle_t = 0.0

func is_playing() -> bool:
	return _playing

## Advance one frame. combat_now = any nearby NPC hunting/fighting; dialogue_active = a conversation or pausing
## menu is open; away = the listener walked out of the radio's range. Combat arms a settle linger; dialogue +
## away suppress immediately (no linger). Recomputes the audible decision + its rising/falling edge and eases
## current_db toward the target.
func tick(delta: float, combat_now: bool, dialogue_active: bool, away: bool = false) -> void:
	if combat_now:
		_settle_t = settle_cooldown
	else:
		_settle_t = maxf(0.0, _settle_t - delta)
	var suppressed: bool = combat_now or _settle_t > 0.0 or dialogue_active or away
	var want: bool = _playing and not suppressed
	if want and not _want_audible:
		_edge = 1
	elif not want and _want_audible:
		_edge = -1
	else:
		_edge = 0
	_want_audible = want
	var target: float = audible_db if want else silent_db
	var time: float = fade_resume_time if want else fade_pause_time
	var span: float = maxf(absf(audible_db - silent_db), 0.001)
	current_db = move_toward(current_db, target, span / time * delta)

## True when the radio is on AND not suppressed — i.e. it should currently be sounding.
func wants_audible() -> bool:
	return _want_audible

## This tick's audible transition: +1 = resume (tell Spotify to play), -1 = pause, 0 = none. Edge-triggered
## (recomputed every tick) so the Spotify path calls play/pause ONCE per transition, not every frame.
func external_edge() -> int:
	return _edge

## True once the duck has reached the silent floor — Radio uses this to fully stop a switched-off fallback.
func at_silent() -> bool:
	return current_db <= silent_db + 0.01
