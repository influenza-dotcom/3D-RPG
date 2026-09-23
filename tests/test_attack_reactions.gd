extends GutTest

## Player-attack reactions + the on-floor dialogue gate.
## - NpcVoice.warn_attack / bark_aggro / bark_flee are the lines NPC._on_damaged_by fires (the DECISION of which one
##   fires is driven in test_provoke_on_attack.gd; this file drives the triggers themselves): an under-threshold hit
##   on a FRIENDLY warns ("Cut that out!"), the hit that actually provokes snaps ("Alright, that does it!"), and a
##   fighter whose temperament breaks under fire panics ("Forget this!"). Each is driven through the real NpcVoice on
##   a stand-in host (ReactionHost) that records what it was asked to say, in order; one test drives the real npc.gd
##   host (bare, no _ready per CLAUDE.md) so the duck-typed host API the stand-in imitates can't drift unnoticed.
## - The pools ship UNAUTHORED (empty = silent): speech is designer content via a BarkSet .tres (the AI-text scrub).
## - TalkApproach must NEVER open dialogue while the NPC is airborne: the close-range shortcut is gated on
##   is_on_floor() (checked FIRST, so the off-tree test below never touches global_position), and an airborne
##   prompt defers to the tick() wait (is_approaching) until the landing.

const NPC_PATH := "res://scripts/npc/npc.gd"

const WARN := "Cut that out!"
const AGGRO := "Alright, that does it!"
const FLEE := "Forget this!"


## A living, non-hostile speaker with one authored default line per reaction pool. `events` records every
## _clear_bark_bubble ("clear") and every line handed to _emit_bark, in call order. _pick_bark resolves through the
## REAL NPC._pick_bark (override-or-default), so a profile BarkSet is honoured exactly as on a real NPC.
class ReactionHost extends Node3D:
	var WARN_ATTACK_LINES: Array[String] = ["Cut that out!"]
	var AGGRO_LINES: Array[String] = ["Alright, that does it!"]
	var FLEE_LINES: Array[String] = ["Forget this!"]
	var _dead := false
	var hp := 10.0
	var player: Node3D = null
	var events: Array = []

	func is_hostile() -> bool: return false
	func is_fleeing() -> bool: return true  # the panic line IS the flee moment; no trigger here may mute a fleer
	func _find_talkable(): return null
	func _real_player(): return player
	func _pick_bark(fallback: Array[String], override: Array[String]) -> String: return NPC._pick_bark(fallback, override)
	func _clear_bark_bubble() -> void: events.append("clear")
	func _emit_bark(line: String, _voice) -> void: events.append(line)


## Records the line each bark REQUEST reaching NpcVoice.emit carries (the body behind the real NPC._emit_bark
## facade) without starting the awaited bubble / TTS path, so a bare off-tree NPC can be the host.
class _RecordingVoice extends NpcVoice:
	var requested: Array = []

	func emit(line: String, _voice: VoiceData) -> void:
		requested.append(line)


## An in-tree ReactionHost with the listening player 1 m away (in-tree because bark_flee's earshot check reads
## global_position).
func _speaking_host() -> ReactionHost:
	var h := ReactionHost.new()
	add_child_autofree(h)
	var listener := Node3D.new()
	add_child_autofree(listener)
	listener.position = Vector3(1.0, 0.0, 0.0)
	h.player = listener
	return h


func _voice_for(h: Node, profile: BarkSet = null) -> NpcVoice:
	var v := NpcVoice.new()
	v.host = h
	if profile != null:
		v._bark_set = profile  # reassign only: the preloaded default_barks.tres is shared and must never be mutated
	autofree(v)
	return v


func test_a_burst_of_stray_fire_draws_one_warning_per_cooldown() -> void:
	assert_true(GameSettings.npc_bark.bark_cooldown_ms > 0, "precondition: a non-hostile NPC's bark cooldown is positive")
	var h := _speaking_host()
	var v := _voice_for(h)
	for i in 3:
		v.warn_attack()
	assert_eq(h.events, [WARN],
		"an ally clipped by three stray rounds in a row must say its warning once, not once per hit")


func test_the_provoking_hit_snaps_even_on_top_of_a_fresh_warning() -> void:
	var h := _speaking_host()
	var v := _voice_for(h)
	v.warn_attack()
	v.bark_aggro()
	assert_eq(h.events, [WARN, "clear", AGGRO],
		"the hit that turns an ally hostile must always get its payoff line: aggro ignores the cooldown the warning just started, and clears the warning bubble BEFORE speaking so the bubble's overlap gate can't swallow it")


func test_the_aggro_snap_holds_the_shared_cooldown() -> void:
	var h := _speaking_host()
	var v := _voice_for(h)
	v.bark_aggro()
	v.warn_attack()
	assert_eq(h.events, ["clear", AGGRO],
		"skipping the cooldown READ must not skip the STAMP: a cooldown-paced line right after the snap stays quiet instead of talking over it")


func test_each_attack_reaction_speaks_its_own_profile_category() -> void:
	var warn_lines: Array[String] = ["Hands off."]
	var aggro_lines: Array[String] = ["That's it."]
	var flee_lines: Array[String] = ["I'm out!"]
	var profile := BarkSet.new()
	profile.warn_attack = warn_lines
	profile.aggro = aggro_lines
	profile.flee = flee_lines
	var warned := _speaking_host()
	_voice_for(warned, profile).warn_attack()
	assert_eq(warned.events, ["Hands off."], "a profile's warn_attack lines must replace the default warning")
	var snapped := _speaking_host()
	_voice_for(snapped, profile).bark_aggro()
	assert_eq(snapped.events, ["clear", "That's it."], "a profile's aggro lines must replace the default snap")
	var fled := _speaking_host()
	_voice_for(fled, profile).bark_flee()
	assert_eq(fled.events, ["I'm out!"], "a profile's flee lines must replace the default panic line")
	# A profile that fills none of these categories inherits every default (BarkSet categories default EMPTY = inherit).
	var blank := BarkSet.new()
	var warned_default := _speaking_host()
	_voice_for(warned_default, blank).warn_attack()
	var snapped_default := _speaking_host()
	_voice_for(snapped_default, blank).bark_aggro()
	var fled_default := _speaking_host()
	_voice_for(fled_default, blank).bark_flee()
	assert_eq(warned_default.events, [WARN],
		"an archetype profile that authors no warn_attack lines must keep the NPC's default warning, not go silent")
	assert_eq(snapped_default.events, ["clear", AGGRO],
		"an archetype profile that authors no aggro lines must keep the NPC's default snap")
	assert_eq(fled_default.events, [FLEE],
		"an archetype profile that authors no flee lines must keep the NPC's default panic line")
	profile = null
	blank = null


func test_a_dead_npc_never_voices_an_attack_reaction() -> void:
	for state in [{"hp": 0.0, "dead": false}, {"hp": 10.0, "dead": true}]:
		var h := _speaking_host()
		h.hp = state["hp"]
		h._dead = state["dead"]
		_voice_for(h).warn_attack()
		_voice_for(h).bark_aggro()
		_voice_for(h).bark_flee()
		assert_eq(h.events, [],
			"a corpse (hp %s, dead %s) hit again must neither warn, snap, panic nor clear a bubble" % [str(state["hp"]), str(state["dead"])])
	var alive := _speaking_host()
	_voice_for(alive).warn_attack()
	_voice_for(alive).bark_aggro()
	_voice_for(alive).bark_flee()
	assert_eq(alive.events, [WARN, "clear", AGGRO, FLEE],
		"control: the same living NPC voices all three reactions")


func test_the_panic_line_needs_the_player_in_earshot() -> void:
	var reach: float = GameSettings.npc_bark.bark_distance
	assert_true(reach > 0.0, "precondition: the bark earshot distance is positive")
	var h := _speaking_host()
	var v := _voice_for(h)
	var listener := h.player
	listener.position = Vector3(reach + 1.0, 0.0, 0.0)
	v.bark_flee()
	assert_eq(h.events, [], "an NPC breaking and running beyond earshot must not shout at nobody")
	h.player = null
	v.bark_flee()
	assert_eq(h.events, [], "with no player in the level the panic line stays unspoken")
	h.player = listener
	listener.position = Vector3(reach * 0.5, 0.0, 0.0)
	v.bark_flee()
	assert_eq(h.events, [FLEE],
		"control: the same fleeing NPC with the player in earshot panics out loud (and the unheard attempts spent no cooldown)")


func test_unprofiled_npc_ships_silent_on_attack_reactions() -> void:
	# Drives the REAL npc.gd host (bare: no _ready) through its _emit_bark facade.
	var npc = load(NPC_PATH).new()
	var voice := _RecordingVoice.new()
	voice.host = npc
	npc._voice = voice
	voice.warn_attack()
	voice.bark_aggro()
	assert_eq(voice.requested, [], "a real NPC at 0 hp (a corpse) must not request a warning or a snap")
	npc.hp = 10.0
	voice.warn_attack()
	voice.bark_aggro()
	assert_eq(voice.requested, ["", ""],
		"SHIP DECISION (AI-text scrub): an unprofiled NPC's warning and snap resolve to an EMPTY line (NPC consts + default_barks.tres ship unauthored); author lines in a BarkSet .tres")
	assert_eq(NPC._pick_bark(NPC.FLEE_LINES, voice._bark_set.flee), "",
		"SHIP DECISION (AI-text scrub): an unprofiled NPC's panic line ships unauthored too")
	var shipped := NpcVoice.new()
	shipped.host = npc
	var gate_before: int = npc._bark_until_msec
	shipped.emit("", null)
	assert_eq(npc._bark_until_msec, gate_before,
		"an empty line must be dropped before it raises a bubble or holds the overlap gate, so unauthored speech is truly silent")
	npc._voice = null
	shipped.free()
	voice.free()
	npc.free()


func test_prompt_talk_defers_to_approach_while_airborne() -> void:
	# Off-tree is_on_floor() is false (no physics tick) — standing in for "airborne". The close-range
	# shortcut must NOT fire: the prompt becomes a pending approach (is_approaching), whose tick() opens the
	# dialogue only once grounded + facing. The floor gate short-circuits BEFORE any global_position read,
	# so this runs off-tree without tracked engine errors.
	var n = load(NPC_PATH).new()
	n.disposition = Disposition.Kind.FRIENDLY  # prompt_talk refuses hostile NPCs; the bare default is HOSTILE
	var ta := TalkApproach.new()
	ta.host = n
	var player := Node3D.new()
	ta.prompt_talk(player, Callable(self, &"_noop_ready"))
	assert_true(ta.is_approaching(),
		"an airborne NPC must not open dialogue from the close-range shortcut — the prompt defers to the grounded tick() wait")
	ta.free()
	player.free()
	n.free()

func test_sitting_prompt_talk_stays_seated_instead_of_approaching() -> void:
	var n = load(NPC_PATH).new()
	n.disposition = Disposition.Kind.FRIENDLY
	n.sitting = true
	var ta := TalkApproach.new()
	ta.host = n
	var player := Node3D.new()
	ta.prompt_talk(player, Callable(self, &"_noop_ready"))
	assert_false(ta.is_approaching(),
		"a seated NPC must not enter the walk-up talk approach; it speaks in place and keeps the seated pose")
	ta.free()
	player.free()
	n.free()


func _noop_ready() -> void:
	pass
