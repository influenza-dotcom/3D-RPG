extends GutTest

## Wave 1 (resource extraction): the NPC's default bark lines now live in resources/barks/default_barks.tres (the
## authored default an unprofiled NPC resolves to), and BarkSet gained music-reaction categories. Both ship
## BYTE-IDENTICAL to the npc.gd line consts — the consts stay as the terminal fallback + the test anchor.

const NPC_PATH := "res://scripts/npc/npc.gd"
const MQ := preload("res://scripts/components/music_quality.gd")
const DEFAULT_BARKS := "res://resources/barks/default_barks.tres"


func test_default_barks_loads_as_a_bark_set() -> void:
	var b := load(DEFAULT_BARKS) as BarkSet
	assert_not_null(b, "default_barks.tres loads as a BarkSet")


func test_default_barks_match_the_npc_consts() -> void:
	# Parity: the authored default ships EXACTLY the built-in lines, so an unprofiled NPC is byte-identical.
	var b := load(DEFAULT_BARKS) as BarkSet
	if b == null:
		return
	assert_eq(b.spot, NPC.BARK_LINES, "default_barks.spot == BARK_LINES (the detection pool)")
	assert_eq(b.hurt, NPC.HURT_LINES, "default_barks.hurt == HURT_LINES")
	assert_eq(b.flee, NPC.FLEE_LINES, "default_barks.flee == FLEE_LINES")
	assert_eq(b.check_body, NPC.CHECK_BODY_LINES, "default_barks.check_body == CHECK_BODY_LINES")
	assert_eq(b.greet, NPC.GREET_LINES, "default_barks.greet == GREET_LINES")
	assert_eq(b.aggro, NPC.AGGRO_LINES, "default_barks.aggro == AGGRO_LINES")
	assert_eq(b.music_great, NPC.MUSIC_GREAT_LINES, "default_barks.music_great == MUSIC_GREAT_LINES")


func test_npc_voice_defaults_to_the_authored_default() -> void:
	# An unprofiled NPC's NpcVoice resolves its bark_set to default_barks (not an empty BarkSet), so the detection
	# pool is the authored default — still byte-identical to BARK_LINES.
	var v := NpcVoice.new()
	assert_eq(v._bark_set.spot, NPC.BARK_LINES, "an unprofiled NpcVoice resolves spot to the authored default (== BARK_LINES)")
	v.free()


func test_bark_set_music_fields_default_empty() -> void:
	# A fresh BarkSet's music categories are empty -> each inherits the NPC's MUSIC_*_LINES default (the
	# inherit-or-override rule), so adding a profile's BarkSet without music lines changes nothing.
	var b := BarkSet.new()
	assert_eq(b.music_awful.size(), 0, "BarkSet.music_awful defaults empty -> inherits MUSIC_AWFUL_LINES")
	assert_eq(b.music_great.size(), 0, "BarkSet.music_great defaults empty")
	b = null


func test_music_lines_layers_override_over_default() -> void:
	# npc._music_lines layers _voice._bark_set.music_* over the MUSIC_*_LINES consts (override-or-default).
	var n = load(NPC_PATH).new()
	var v := NpcVoice.new()
	n._voice = v
	v._bark_set = BarkSet.new()  # empty override -> the consts
	assert_eq(n._music_lines(MQ.Tier.GREAT), NPC.MUSIC_GREAT_LINES, "empty music override -> the MUSIC_GREAT_LINES default")
	var custom: Array[String] = ["Banger!"]
	v._bark_set.music_great = custom
	assert_eq(n._music_lines(MQ.Tier.GREAT), custom, "a non-empty music_great override wins over the default")
	v.free()
	n.free()
