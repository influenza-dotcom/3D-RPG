@tool
class_name RewardStinger
extends Node

## Drop-in REWARD "sting": plays its parent AudioStreamPlayer's one-shot on a reward moment — a quest COMPLETED
## (GameState.quest_completed) and/or a LEVEL-UP (the player's leveled_up). The positive mirror of DetectionStinger
## (the "you've been seen" cue). Signal-driven (reacts to the event, no polling), with a short cooldown so a
## quest-complete that also levels you up stings once, not twice. Inert until a reward actually fires.
##
## SETUP: drop it as a CHILD of an AudioStreamPlayer / AudioStreamPlayer3D / AudioStreamPlayer2D whose stream is
## the reward sting (leave that player NON-autoplay, non-loop — this calls play() on the event). BOTH this node and
## the parent audio player are forced PROCESS_MODE_ALWAYS so the sting still plays while the world is paused (a quest
## turned in mid-dialogue, a level-up at a station) — a play() on a paused INHERIT player is silently dropped.

## Minimum seconds between stings — coalesces a simultaneous quest-complete + level-up into one cue.
@export var cooldown: float = 0.5
## Sting when a quest completes (GameState.quest_completed).
@export var on_quest_complete: bool = true
## Sting on a player level-up (the player's leveled_up signal).
@export var on_level_up: bool = true

var _audio: Node = null          ## the parent audio player (loose-typed; AudioStreamPlayer + ...3D/2D all expose play())
var _cooldown_t: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only _get_configuration_warnings runs in-editor; never connect/play there
	process_mode = Node.PROCESS_MODE_ALWAYS  # fire even while paused (a turn-in / level-up happens behind a menu)
	var parent := get_parent()
	if not (parent is AudioStreamPlayer or parent is AudioStreamPlayer3D or parent is AudioStreamPlayer2D):
		push_warning("RewardStinger: parent isn't an audio player — drop this under the reward AudioStreamPlayer; doing nothing")
		return
	_audio = parent
	# The reward moments fire during a PAUSE (a turn-in mid-dialogue, the level-up screen), so the audio player
	# ITSELF must run while paused — not just this logic node. A play() on a paused INHERIT player is dropped.
	_audio.process_mode = Node.PROCESS_MODE_ALWAYS  # mirrors MusicDirector (both the logic node + the audio node are ALWAYS)
	if on_quest_complete and not GameState.quest_completed.is_connected(_on_quest):
		GameState.quest_completed.connect(_on_quest)
	if on_level_up:
		_connect_level_up.call_deferred()  # the player may not be in the tree yet at our _ready

## Find the human player (non-NPC Player-group member) and hook its leveled_up. Deferred so the player has spawned.
func _connect_level_up() -> void:
	if not is_inside_tree():
		return
	for p in get_tree().get_nodes_in_group(Groups.PLAYER):
		if not (p is NPC) and p.has_signal(&"leveled_up") and not p.is_connected(&"leveled_up", _on_level):
			p.connect(&"leveled_up", _on_level)
			return

func _on_quest(_quest: Quest = null) -> void:
	_sting()

func _on_level(_new_level: int = 0, _points_gained: int = 0) -> void:
	_sting()

func _process(delta: float) -> void:
	_cooldown_t = maxf(0.0, _cooldown_t - delta)

func _sting() -> void:
	if _audio != null and _consume_sting():
		_audio.call(&"play")

## Cooldown gate: true (and arms the cooldown) when enough time has elapsed since the last sting, else false.
## Pure-ish (touches only _cooldown_t) so a test can drive it without an audio parent.
func _consume_sting() -> bool:
	if _cooldown_t > 0.0:
		return false
	_cooldown_t = cooldown
	return true

func _get_configuration_warnings() -> PackedStringArray:
	var p := get_parent()
	if p == null or not (p is AudioStreamPlayer or p is AudioStreamPlayer3D or p is AudioStreamPlayer2D):
		return PackedStringArray([
			"Parent isn't an audio player — drop RewardStinger UNDER an AudioStreamPlayer (2D/3D) whose stream is the reward sting; otherwise it does nothing.",
		])
	return PackedStringArray()
