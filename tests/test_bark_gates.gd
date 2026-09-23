extends GutTest

## Designer bark gates: NpcData.damage_barks / death_barks / search_barks toggle whether an NPC voices the HURT
## cry (_cry_wounded), the death-witness reaction (_witness_death), and the active-search mutter (bark_searching).
## Seeded onto the code-built NpcVoice in NPC._build_components (default ON, so an unprofiled NPC is unchanged).
## Every gate test pairs a MUTED NPC with an otherwise identical VOCAL one: the stand-in host (GatedHost) is alive,
## has a Talkable, stands in the player's earshot and has one authored line per pool, so every other filter on the
## trigger passes and only the designer gate decides whether the NPC speaks. A muted bark must also leave the
## shared bark cooldown untouched, or one silent archetype setting would starve that NPC's OTHER barks.
## One test drives the REAL NPC host (bare, no _ready per CLAUDE.md) so the duck-typed host API the stubs imitate
## can't drift from npc.gd unnoticed.

const NPC_PATH := "res://scripts/npc/npc.gd"

class StubHost extends Node3D:
	var HURT_LINES: Array[String] = ["I'm hit!"]
	var AGGRO_LINES: Array[String] = ["You asked for it!"]
	var hostile := false
	var _dead := false
	var hp := 10.0
	var emitted_line := ""
	var emitted_voice: VoiceData = null

	func is_hostile() -> bool:
		return hostile

	func _find_talkable() -> Talkable:
		return null

	func _pick_bark(default_lines: Array[String], _override_lines: Array[String]) -> String:
		return default_lines[0] if not default_lines.is_empty() else ""

	func _emit_bark(line: String, voice: VoiceData) -> void:
		emitted_line = line
		emitted_voice = voice

	func _clear_bark_bubble() -> void:
		pass


## A speaking NPC stand-in for the gate tests. is_hostile() derives from the disposition exactly as NPC.is_hostile
## does, _bark_pool / _pick_bark return the host's own (single-line) pool so the emitted line names the pool the
## trigger chose, and every emitted line is recorded in order.
class GatedHost extends Node3D:
	var HURT_LINES: Array[String] = ["I'm hit!"]
	var WARN_ATTACK_LINES: Array[String] = ["Cut that out!"]
	var SEARCH_LINES: Array[String] = ["Where are you?"]
	var LOST_INTEREST_LINES: Array[String] = ["Must be gone now."]
	var DEATH_ALLY_LINES: Array[String] = ["Murderer!"]
	var DEATH_APPROVE_LINES: Array[String] = ["Good riddance."]
	var DEATH_QUESTION_LINES: Array[String] = ["Was that necessary?"]
	var disposition: Disposition.Kind = Disposition.Kind.NEUTRAL
	var ally: Node = null
	var _dead := false
	var hp := 10.0
	var talkable: Node = null
	var player: Node3D = null
	var emitted: Array = []

	func is_hostile() -> bool: return disposition == Disposition.Kind.HOSTILE
	func is_in_combat() -> bool: return false
	func resolved_disposition() -> Disposition.Kind: return disposition
	func _is_ally_of(other) -> bool: return other != null and other == ally
	func _find_talkable(): return talkable
	func _real_player(): return player
	func _bark_pool(fallback: Array[String], _override: Array[String]) -> Array[String]: return fallback
	func _pick_bark(fallback: Array[String], _override: Array[String]) -> String:
		return fallback[0] if not fallback.is_empty() else ""
	func _emit_bark(line: String, _voice) -> void: emitted.append(line)


## Counts bark REQUESTS reaching NpcVoice.emit (the body behind the real NPC._emit_bark facade) without starting the
## awaited bubble / TTS path, so a bare off-tree NPC can be the host.
class _RequestCountingVoice extends NpcVoice:
	var requested := 0

	func emit(_line: String, _voice: VoiceData) -> void:
		requested += 1


## An in-tree GatedHost with a Talkable and the listening player beside it (in-tree because the search mutter's
## earshot check reads global_position).
func _speaking_host() -> GatedHost:
	var h := GatedHost.new()
	h.talkable = FakeTalkable.new()
	h.add_child(h.talkable)
	add_child_autofree(h)
	var listener := Node3D.new()
	add_child_autofree(listener)
	listener.position = Vector3(1.0, 0.0, 0.0)
	h.player = listener
	return h


func _voice_for(h: Node) -> NpcVoice:
	var v := NpcVoice.new()
	v.host = h
	autofree(v)
	return v


## The line(s) a fresh witness says on seeing the player kill a victim of `victim_disposition`.
func _witness_reaction(witness_disposition: Disposition.Kind, victim_disposition: Disposition.Kind, allied: bool) -> Array:
	var witness := _speaking_host()
	witness.disposition = witness_disposition
	var victim := GatedHost.new()
	autofree(victim)
	victim.disposition = victim_disposition
	if allied:
		witness.ally = victim
	_voice_for(witness)._witness_death(victim)
	return witness.emitted


func test_hostile_npc_uses_shorter_bark_cooldown() -> void:
	var h := StubHost.new()
	var v := NpcVoice.new()
	v.host = h
	assert_eq(v._bark_cooldown_ms(), GameSettings.npc_bark.bark_cooldown_ms,
		"non-hostile NPCs keep the standard bark cooldown")
	h.hostile = true
	assert_eq(v._bark_cooldown_ms(), GameSettings.npc_bark.enemy_bark_cooldown_ms,
		"hostile NPCs use the shorter enemy bark cooldown")
	assert_lt(GameSettings.npc_bark.enemy_bark_cooldown_ms, GameSettings.npc_bark.bark_cooldown_ms,
		"enemy barks are intentionally paced faster than generic NPC chatter")
	v.free()
	h.free()

func test_combat_barks_do_not_require_talkable() -> void:
	var h := StubHost.new()
	var v := NpcVoice.new()
	v.host = h
	v._cry_wounded()
	assert_eq(h.emitted_line, "I'm hit!",
		"combat hurt barks must emit even when the enemy has no Talkable child")
	assert_null(h.emitted_voice,
		"without a Talkable voice, combat barks fall back to SpeechTts' default voice")
	v.free()
	h.free()

func test_aggro_bark_does_not_require_talkable() -> void:
	var h := StubHost.new()
	var v := NpcVoice.new()
	v.host = h
	v.bark_aggro()
	assert_eq(h.emitted_line, "You asked for it!",
		"the become-hostile aggro bark must emit even when the NPC has no Talkable child")
	v.free()
	h.free()


func test_unprofiled_npc_voices_every_gated_bark() -> void:
	# No gate touched: the NpcVoice an unprofiled NPC gets must cry out, react to a death and mutter while hunting.
	var hurt := _speaking_host()
	_voice_for(hurt)._cry_wounded()
	assert_eq(hurt.emitted, ["I'm hit!"], "an unprofiled NPC must cry out when wounded (damage barks ship ON)")
	assert_eq(_witness_reaction(Disposition.Kind.NEUTRAL, Disposition.Kind.NEUTRAL, true), ["Murderer!"],
		"an unprofiled NPC must react when the player kills its ally (death barks ship ON)")
	var hunter := _speaking_host()
	_voice_for(hunter).bark_searching()
	assert_eq(hunter.emitted, ["Where are you?"], "an unprofiled NPC must mutter while it hunts (search barks ship ON)")


func test_muting_one_profile_bark_gate_mutes_only_that_bark_on_the_built_npc() -> void:
	# NPC._build_components seeds each NpcData bark gate onto the code-built NpcVoice. Driven on a bare, off-tree NPC
	# (no _ready, as tests/test_npc_data.gd does). Muting ONE gate at a time catches a dropped copy (the designer's
	# muted archetype still barks) AND a cross-wired copy (muting the hurt cry silences death reactions instead).
	var gate_pairs := [
		[&"damage_barks", &"damage_barks_enabled", "the hurt cry"],
		[&"death_barks", &"death_barks_enabled", "the death-witness reaction"],
		[&"search_barks", &"search_barks_enabled", "the hunt mutter"],
	]
	for pair in gate_pairs:
		var profile := NpcData.new()
		profile.set(pair[0], false)
		var npc = load(NPC_PATH).new()
		npc.profile = profile
		npc._build_components()
		assert_eq(npc._voice.get(pair[1]), false,
			"an archetype whose profile sets %s = false must not voice %s in game" % [pair[0], pair[2]])
		for other in gate_pairs:
			if other == pair:
				continue
			assert_eq(npc._voice.get(other[1]), true,
				"muting %s must not also mute %s (profile gates copied onto the wrong voice flag)" % [pair[0], other[2]])
		npc.free()
		profile = null


func test_a_default_profile_mutes_nothing_an_unprofiled_npc_says() -> void:
	# Control for the test above: a profile left at its defaults, seeded through the real _build_components, must set
	# every voice gate exactly as an unprofiled NPC's NpcVoice has it, so giving an archetype a profile never mutes it.
	var profile := NpcData.new()
	var npc = load(NPC_PATH).new()
	npc.profile = profile
	npc._build_components()
	var bare := NpcVoice.new()
	for flag in [&"damage_barks_enabled", &"death_barks_enabled", &"search_barks_enabled"]:
		assert_eq(npc._voice.get(flag), bare.get(flag),
			"a profile left at defaults must mute nothing an unprofiled NPC says (%s differs)" % flag)
	bare.free()
	npc.free()
	profile = null


func test_muted_hurt_cry_is_silent_and_leaves_the_shared_cooldown_free() -> void:
	var muted_host := _speaking_host()
	var muted := _voice_for(muted_host)
	muted.damage_barks_enabled = false
	muted._cry_wounded()
	assert_eq(muted_host.emitted, [], "an archetype with damage_barks off must take a hit without crying out")
	muted.warn_attack()
	assert_eq(muted_host.emitted, ["Cut that out!"],
		"the muted cry must not spend the shared bark cooldown: the same NPC's next bark still lands")
	var vocal_host := _speaking_host()
	var vocal := _voice_for(vocal_host)
	vocal._cry_wounded()
	vocal.warn_attack()
	assert_eq(vocal_host.emitted, ["I'm hit!"],
		"control: the identical NPC with the gate open cries out, and that cry holds the shared cooldown")


func test_muted_death_witness_is_silent_and_leaves_the_shared_cooldown_free() -> void:
	var muted_host := _speaking_host()
	var muted := _voice_for(muted_host)
	muted.death_barks_enabled = false
	var victim := GatedHost.new()
	autofree(victim)
	muted_host.ally = victim
	muted._witness_death(victim)
	assert_eq(muted_host.emitted, [], "an archetype with death_barks off must ignore the player killing its ally")
	muted.react_remark(["Watch where you point that."])
	assert_eq(muted_host.emitted, ["Watch where you point that."],
		"the muted reaction must not spend the shared bark cooldown: the same NPC's next remark still lands")
	var vocal_host := _speaking_host()
	var vocal := _voice_for(vocal_host)
	vocal_host.ally = victim
	vocal._witness_death(victim)
	vocal.react_remark(["Watch where you point that."])
	assert_eq(vocal_host.emitted, ["Murderer!"],
		"control: the identical witness with the gate open is outraged, and that line holds the shared cooldown")


func test_witness_line_follows_alliance_and_disposition() -> void:
	assert_eq(_witness_reaction(Disposition.Kind.NEUTRAL, Disposition.Kind.HOSTILE, true), ["Murderer!"],
		"killing a witness's ally must draw outrage, whatever the victim's disposition")
	assert_eq(_witness_reaction(Disposition.Kind.FRIENDLY, Disposition.Kind.HOSTILE, false), ["Good riddance."],
		"a friendly bystander must approve of the player killing a hostile")
	assert_eq(_witness_reaction(Disposition.Kind.NEUTRAL, Disposition.Kind.HOSTILE, false), ["Was that necessary?"],
		"a neutral bystander must question even a hostile's death (only friendlies approve)")
	assert_eq(_witness_reaction(Disposition.Kind.FRIENDLY, Disposition.Kind.NEUTRAL, false), ["Was that necessary?"],
		"a friendly bystander must question the killing of a non-hostile")
	assert_eq(_witness_reaction(Disposition.Kind.HOSTILE, Disposition.Kind.HOSTILE, true), [],
		"a hostile witness must stay silent even when its ally dies (death reactions are for non-hostiles)")


func test_muted_search_mutter_stays_silent_for_the_whole_hunt() -> void:
	# The search loop calls bark_searching every frame, so call it repeatedly.
	var muted_host := _speaking_host()
	var muted := _voice_for(muted_host)
	muted.search_barks_enabled = false
	for i in 3:
		muted.bark_searching()
	assert_eq(muted_host.emitted, [], "a silent stalker (search_barks off) must hunt without ever giving away its progress")
	var vocal_host := _speaking_host()
	var vocal := _voice_for(vocal_host)
	for i in 3:
		vocal.bark_searching()
	assert_eq(vocal_host.emitted, ["Where are you?"],
		"control: the identical hunter with the gate open mutters, once per cooldown despite being called every frame")


func test_search_mutter_does_not_starve_the_give_up_line() -> void:
	# The give-up line fires the moment a search expires, often right after a mutter; the mutter keeps its own
	# cooldown so it can never swallow it.
	var h := _speaking_host()
	var v := _voice_for(h)
	v.bark_searching()
	v._try_lost_interest_bark()
	assert_eq(h.emitted, ["Where are you?", "Must be gone now."],
		"an NPC that just muttered while searching must still say its give-up line when the search ends")


func test_hurt_cry_gate_and_corpse_guard_hold_on_a_real_npc_host() -> void:
	# The stubs above imitate NPC's host API; this drives the real npc.gd (bare: no _ready) through its _emit_bark
	# facade, so a renamed host member breaks here instead of only in a playtest.
	var npc = load(NPC_PATH).new()
	var voice := _RequestCountingVoice.new()
	voice.host = npc
	npc._voice = voice
	voice._cry_wounded()
	assert_eq(voice.requested, 0, "an NPC at 0 hp (a corpse) must not cry out, even with the gate open")
	npc.hp = 10.0
	voice.damage_barks_enabled = false
	voice._cry_wounded()
	assert_eq(voice.requested, 0, "a living NPC whose archetype muted the hurt cry must stay silent")
	voice.damage_barks_enabled = true
	voice._cry_wounded()
	assert_eq(voice.requested, 1,
		"control: the same living NPC with the gate open must request its hurt bark through NPC._emit_bark")
	npc._voice = null
	voice.free()
	npc.free()


## A Talkable stand-in for the music-comment gate test: music_comment reads only `.voice` off the resolved
## Talkable, so a bare Node with a `voice` field is enough (no real Talkable lifecycle needed off-tree).
class FakeTalkable extends Node:
	var voice: VoiceData = null

## Idle-NPC stub for the music-comment path: HOSTILE, out of combat, alive, with a Talkable.
class MusicStubHost extends Node3D:
	var hostile := true
	var in_combat := false
	var _dead := false
	var hp := 10.0
	var emitted := 0
	var _talkable: Node = null

	func is_hostile() -> bool: return hostile
	func is_in_combat() -> bool: return in_combat
	func _find_talkable(): return _talkable
	func _emit_bark(_line: String, _voice) -> void: emitted += 1


func test_music_comment_reacts_for_hostile_idle_npc() -> void:
	# Hostile NPCs now react to songs too (a raider idling by its own radio). NpcVoice.music_comment keeps
	# react_remark's out-of-combat + Talkable + cooldown filter but DROPS the non-hostile gate. Prove the difference
	# on ONE hostile stub: react_remark stays silent (friendly-only, unchanged); music_comment speaks.
	var talkable := FakeTalkable.new()
	var h := MusicStubHost.new()
	h._talkable = talkable
	var v := NpcVoice.new()
	v.host = h
	v.react_remark(["Nice tune."])
	assert_eq(h.emitted, 0, "react_remark must STILL gate out a hostile NPC (its friendly-only self-filter is unchanged)")
	v.music_comment(["Nice tune."])
	assert_eq(h.emitted, 1, "music_comment must fire for a HOSTILE idle NPC — hostiles react to songs now")
	v.free()
	h.free()
	talkable.free()


func test_music_comment_still_gated_in_combat() -> void:
	# The one filter music_comment keeps (belt-and-braces): a comment can never slip out mid-firefight. _react_music
	# already only calls it while UNAWARE, but the gate guards a mis-call.
	var talkable := FakeTalkable.new()
	var h := MusicStubHost.new()
	h._talkable = talkable
	h.in_combat = true
	var v := NpcVoice.new()
	v.host = h
	v.music_comment(["Nice tune."])
	assert_eq(h.emitted, 0, "music_comment must stay silent while the NPC is in combat")
	v.free()
	h.free()
	talkable.free()
