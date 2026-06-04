class_name TalkApproach
extends Node

## The NPC's PRE-TALK approach — the "talk requested" walk-up. Talking a (non-hostile) NPC is a PROMPT,
## not a force: it acknowledges the player, walks into framing range, then opens the real dialogue. Split
## off NPC so the root keeps only the public prompt_talk() / set_in_dialogue() NAMES (the dialogue stack
## calls them via has_method) and the shared locomotion; this child owns the approach STATE + drive.
##
## State: _target is the player to close on; _on_ready opens the actual DialogueManager.start once in
## range; _timeout bleeds down so a blocked approach still speaks (gives up). All cleared the instant the
## approach resolves — _target == null means "not approaching". The host's _physics_process checks
## is_approaching() and, while true, drives ONLY tick() + locomotion (nothing else) until it resolves.
##
## Host-coupled: NPC builds it in _ready and sets `host` right after .new(); it READS the host's combat
## gates (is_hostile / is_in_combat) + framing exports and CALLS back into the host's locomotion
## (_move_toward / _face_* writing _desired_velocity). Off-tree (a unit-test NPC built via .new() with no
## add_child) this child never exists, so NPC's prompt_talk facade null-guards it and simply does nothing.

## The NPC running this approach — set right after .new() in NPC._ready. The canonical actor state
## (position, facing) stays on the host; this child only holds the transient approach bookkeeping.
var host: NPC

## Pre-talk approach bookkeeping. _target is the player we're closing on; _on_ready opens the dialogue
## once framed; _timeout bleeds down so a blocked approach still speaks. All cleared the instant the
## approach resolves — _target == null means "not approaching".
var _target: Node3D = null
var _on_ready: Callable = Callable()
var _timeout: float = 0.0

## True while walking up to the player to be framed for dialogue — the host's _physics_process uses this
## to override all other AI with the approach + locomotion until it resolves.
func is_approaching() -> bool:
	return _target != null

## Abandon any in-progress approach WITHOUT speaking (e.g. the NPC just got recruited — it's escorting
## now, not parleying). Idempotent.
func abandon() -> void:
	_target = null
	_on_ready = Callable()

## "Prompt" (not force) the host to talk: it acknowledges the player, walks into framing range, and only
## THEN runs `on_ready` (which performs the real DialogueManager.start). Called from the host's prompt_talk
## facade on interact, so a talk press is a REQUEST the NPC chooses to answer, not an instant dialogue box.
## Refused outright while busy fighting or hostile (you can't parley mid-fight), and ignored if already
## mid-approach so spamming interact can't queue multiple openings. When close enough already (or approach
## disabled), just waits TALK_BUFFER then speaks in place — the buffer is the beat between the press and
## the reply. Robustness (player walking off / timeout) lives in tick(). The approach turns the NPC itself,
## so the dialogue handler must NOT also face_player.
func prompt_talk(player: Node3D, on_ready: Callable) -> void:
	if _target != null:
		return  # already gathering toward an earlier prompt — don't queue a second
	if host.is_hostile() or host.is_in_combat() or player == null or not on_ready.is_valid():
		return  # a hostile / fighting NPC won't talk; nothing to do without a player or callback
	# Close enough (or framing disabled): hold the buffer beat, then speak from here. The timer is
	# created on the tree (not the host) so it survives even if the host's processing is otherwise quiet.
	if host.talk_approach_distance <= 0.0 or host.global_position.distance_to(player.global_position) <= host.talk_approach_distance:
		host.get_tree().create_timer(TalkHelpers.TALK_BUFFER).timeout.connect(on_ready)
		return
	# Otherwise walk into range first; tick() (driven from the host's _physics_process) runs on_ready
	# once we arrive (or the approach times out). The buffer is folded into the walk-up time here.
	_target = player
	_on_ready = on_ready
	_timeout = host.talk_approach_timeout

## Pre-talk approach step: walk toward the player and open the dialogue ONLY once every condition holds —
## in framing range, on the GROUND (not mid-knockback / airborne), and actually FACING them. Combat
## PREEMPTS the parley (a busy NPC only fights): if a fight starts, the player is gone, or the approach
## times out, it abandons the prompt and opens NO dialogue. The callback + target are cleared BEFORE the
## call so a re-entrant prompt_talk during dialogue start can't double-fire. Drives the host's locomotion.
func tick(delta: float) -> void:
	host._desired_velocity = Vector3.ZERO  # default hold; _move_toward below drives it while travelling
	_timeout -= delta
	# Abandon the parley if a fight started (only-fights-while-busy), the player vanished, or we took
	# too long: drop the prompt and open NO dialogue, returning to normal behaviour.
	if host.is_in_combat() or not is_instance_valid(_target) or _timeout <= 0.0:
		_target = null
		_on_ready = Callable()
		return
	var to_player := _target.global_position - host.global_position
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	if flat.length() > host.talk_approach_distance:
		# Still closing: path toward the player, facing the way we travel (else straight at them).
		if host._move_toward(_target.global_position):
			host._face_travel(delta)
		else:
			host._face_point(_target.global_position, delta)
		return
	# In range: square up, then open the box ONLY once grounded AND FULLY facing them (our +Z front
	# within ~8 deg, so the NPC finishes its turn-to-face before talking instead of speaking mid-pivot).
	# Otherwise hold and keep turning until we are (or the timeout above gives up).
	host._face_point(_target.global_position, delta)
	var fwd := host.global_transform.basis.z
	fwd.y = 0.0
	var facing := flat.length_squared() > 0.0001 and fwd.length_squared() > 0.0001 \
			and fwd.normalized().dot(flat.normalized()) >= 0.99
	if host.is_on_floor() and facing:
		var cb := _on_ready
		_target = null
		_on_ready = Callable()
		if cb.is_valid():
			cb.call()
