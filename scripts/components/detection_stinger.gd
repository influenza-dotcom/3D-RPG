@tool
class_name DetectionStinger
extends Node

## Drop-in "YOU'VE BEEN SEEN" audio sting. Plays its parent AudioStreamPlayer's one-shot the instant an NPC
## first locks onto the player (Perception -> ALERTED), polled like MusicDirector. Latches so one sustained
## engagement stings exactly ONCE, re-arms when every NPC disengages, and a cooldown stops a flickering line of
## sight from spamming the cue. Inert until an NPC actually goes ALERTED on the player.
##
## Pairs with MusicDirector (which fades the COMBAT BED in/out): this is the sharp one-shot ON the detection
## edge, that the continuous bed underneath.
##
## SETUP: drop it as a CHILD of an AudioStreamPlayer / AudioStreamPlayer3D / AudioStreamPlayer2D whose stream is
## the detection sting (leave that player NON-autoplay, non-loop — this calls play() on the edge). PROCESS_MODE_ALWAYS
## so it still fires the very moment combat begins.

## Minimum seconds between stings — a detection that flickers (LOS lost then regained) won't replay the cue.
@export var cooldown: float = 5.0

const POLL_INTERVAL: float = 0.3  ## seconds between group scans (a per-frame scan would be waste; mirrors MusicDirector)

var _player: Node = null         ## the parent audio player (loose-typed; AudioStreamPlayer + ...3D/2D all expose play())
var _poll_t: float = 0.0
var _cooldown_t: float = 0.0
var _was_detected: bool = false  ## latch: detection was active last poll — sting only on the rising edge

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only _get_configuration_warnings runs in-editor; never play() there
	process_mode = Node.PROCESS_MODE_ALWAYS  # fire the instant combat starts, even mid pause/dialogue (like MusicDirector)
	var parent := get_parent()
	if not (parent is AudioStreamPlayer or parent is AudioStreamPlayer3D or parent is AudioStreamPlayer2D):
		push_warning("DetectionStinger: parent isn't an audio player — drop this under the sting AudioStreamPlayer; doing nothing")
		return
	_player = parent

func _process(delta: float) -> void:
	if _player == null:
		return
	_cooldown_t = maxf(0.0, _cooldown_t - delta)
	_poll_t -= delta
	if _poll_t > 0.0:
		return
	_poll_t = POLL_INTERVAL
	if _eval(_any_npc_alerted_on_player()):
		_player.play()

## Edge + cooldown decision: sting on the RISING edge of detection, but only when the cooldown has elapsed.
## Arms the cooldown and updates the latch. Returns true when the caller should play the sting. Pure (no tree/audio).
func _eval(detected: bool) -> bool:
	var sting := detected and not _was_detected and _cooldown_t <= 0.0
	if sting:
		_cooldown_t = cooldown
	_was_detected = detected
	return sting

## True if any NPC has locked onto the player (Perception ALERTED on a live target). Mirrors MusicDirector's
## combat scan; Perception is the player-detection system, so ALERTED means "has spotted the player". Off-tree safe.
func _any_npc_alerted_on_player() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(&"npc"):
		if n is NPC and (n as NPC).is_in_combat():
			return true
	return false

func _get_configuration_warnings() -> PackedStringArray:
	var p := get_parent()
	if p == null or not (p is AudioStreamPlayer or p is AudioStreamPlayer3D or p is AudioStreamPlayer2D):
		return PackedStringArray([
			"Parent isn't an audio player — drop DetectionStinger UNDER an AudioStreamPlayer (2D/3D) whose stream is the detection sting; otherwise it does nothing.",
		])
	return PackedStringArray()
