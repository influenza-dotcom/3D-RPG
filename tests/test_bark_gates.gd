extends GutTest

## Designer bark gates: NpcData.damage_barks / death_barks / search_barks toggle whether an NPC voices the HURT
## cry (_cry_wounded), the death-witness reaction (_witness_death), and the active-search mutter (bark_searching).
## Seeded onto the code-built NpcVoice in NPC._build_components (default ON, so an unprofiled NPC is unchanged).
## The gate is the FIRST check in each trigger, so a muted bark short-circuits BEFORE any host read — verified
## here by calling with host == null.

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


func test_npc_data_bark_gates_default_on() -> void:
	var d := NpcData.new()
	assert_true(d.damage_barks, "NpcData.damage_barks must default ON so a profiled NPC keeps its hurt cry unless muted")
	assert_true(d.death_barks, "NpcData.death_barks must default ON so a profiled NPC keeps death-witness reactions unless muted")
	assert_true(d.search_barks, "NpcData.search_barks must default ON so a profiled NPC keeps its hunt mutter unless muted")
	d = null


func test_npc_voice_gate_defaults_on() -> void:
	var v := NpcVoice.new()
	assert_true(v.damage_barks_enabled, "NpcVoice.damage_barks_enabled must default ON (unprofiled NPC unchanged)")
	assert_true(v.death_barks_enabled, "NpcVoice.death_barks_enabled must default ON (unprofiled NPC unchanged)")
	assert_true(v.search_barks_enabled, "NpcVoice.search_barks_enabled must default ON (unprofiled NPC unchanged)")
	v.free()

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


func test_damage_bark_gate_short_circuits_before_host() -> void:
	# host left null: if the gate weren't the FIRST check, host._dead would crash. No crash == gate is first.
	var v := NpcVoice.new()
	v.damage_barks_enabled = false
	v._cry_wounded()
	assert_true(true, "a muted damage bark must return before touching host (gate checked first)")
	v.free()


func test_death_bark_gate_short_circuits_before_host() -> void:
	var v := NpcVoice.new()
	v.death_barks_enabled = false
	v._witness_death(null)
	assert_true(true, "a muted death-witness bark must return before touching host (gate checked first)")
	v.free()


func test_search_bark_gate_short_circuits_before_host() -> void:
	# host left null: bark_searching's gate is the FIRST check, so a muted hunt mutter returns before host._dead.
	var v := NpcVoice.new()
	v.search_barks_enabled = false
	v.bark_searching()
	assert_true(true, "a muted search bark must return before touching host (gate checked first)")
	v.free()


func test_gated_voice_offtree_safe_when_enabled() -> void:
	# Gates ON (default) + a bare NPC (no _ready -> hp 0): both triggers still early-return on the hp/null
	# guards, so enabling the gate didn't break the existing off-tree safety the damage handler relies on.
	var n = load(NPC_PATH).new()
	var v := NpcVoice.new()
	v.host = n
	v._cry_wounded()
	v._witness_death(null)
	assert_true(true, "enabled barks must stay off-tree safe on a bare (hp 0) host")
	v.free()
	n.free()


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
