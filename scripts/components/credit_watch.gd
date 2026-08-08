class_name CreditWatch
extends Node

## Drop-in CREDIT-SCORE ANNOUNCER — pushes a top-left toast whenever the Ledger's rating of you MOVES.
## Authored as a child of scenes/player/Player.tscn beside LedgerAccrual.
##
## ⭐WHY A POLL AND NOT A SIGNAL: the score has several independent inputs — the persisted record
## (GameState.credit_standing, moved by repayments, arrears and the headshot conduct dividend), the live stat
## sheet (every LevelUp raise and perk), and the economy knobs themselves. Watching the RESULT catches all of
## them through one seam; wiring a signal per source would silently miss whichever one gets added next.
## The poll is throttled, and credit_rating_for is six short loops, so this is far cheaper than it sounds.
##
## ⭐THE THROTTLE IS ALSO THE COALESCER. A headshot moves the score by a fraction of a point at the shipped
## rates (~24 headshots per point), and a firefight lands many at once — announcing per event would be either
## silent or a spam wall. Polling the integer score once a second turns a burst into ONE honest "+3".
##
## OFF-SWITCH: poll_interval <= 0 -> inert (the rent_amount / bank-rate convention).

## Seconds between checks. Lower = more responsive, and more separate toasts for a fast-moving score.
@export var poll_interval: float = 1.0
## Smallest score movement worth interrupting the player for. 1 = announce every point.
@export var min_announce_delta: int = 1

var _last_score: int = -1   ## -1 = unprimed: the FIRST reading is adopted silently, never announced
var _last_band: StringName = &""
var _accum: float = 0.0


func _process(delta: float) -> void:
	if poll_interval <= 0.0:
		return
	_accum += delta
	if _accum < poll_interval:
		return
	_accum = 0.0
	_check()


## Re-rate and announce if the score moved. Also callable directly from a test.
## The gates mirror LedgerAccrual's: a dead player gets no toast over the black death frame, a quickload in
## flight is about to throw this rating away, and a bare dev boot has no run to rate.
func _check() -> void:
	var player := get_parent() as Player
	if player == null or not GameState.profile_active or GameState.reload_pending():
		return
	if player.has_method(&"is_alive") and not player.is_alive():
		return
	var rating: Dictionary = player.credit_rating()
	var score := int(rating["score"])
	var band: StringName = rating["band"]
	if _last_score < 0:
		# PRIME. A fresh spawn, a level change and a load all start here, so none of them announces the score
		# the player already had — only a genuine in-run movement ever toasts.
		_last_score = score
		_last_band = band
		return
	var moved := score - _last_score
	if absi(moved) < maxi(1, min_announce_delta):
		return
	var band_changed := band != _last_band
	_last_score = score
	_last_band = band
	if player.has_method(&"notify_toast"):
		# Directional colour comes from CBPalette (colorblind-aware), never a HUD knob — the same contract the
		# reputation and quest toasts follow for gain/loss.
		player.notify_toast(PlayerText.credit_score_toast(score, moved, band, band_changed),
			CBPalette.gain() if moved > 0 else CBPalette.loss())


## Forget the primed score, so the NEXT check adopts silently instead of announcing. Call after anything that
## legitimately jumps the rating without the player doing something worth narrating (a load, a respawn).
func reprime() -> void:
	_last_score = -1
	_last_band = &""
