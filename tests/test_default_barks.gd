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
	assert_eq(b.pardon, NPC.PARDON_LINES, "default_barks.pardon == PARDON_LINES (the holster pardon)")
	assert_eq(b.pardon_fleeing, NPC.PARDON_FLEEING_LINES,
		"default_barks.pardon_fleeing == PARDON_FLEEING_LINES (pardoned mid-run)")
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


func test_pardon_lines_layers_override_over_default() -> void:
	# The ordinary category behaves like every other: BarkSet.pardon overrides PARDON_LINES when filled.
	var n = load(NPC_PATH).new()
	var v := NpcVoice.new()
	n._voice = v
	v._bark_set = BarkSet.new()  # empty override -> the consts
	assert_eq(n._pardon_lines(false), NPC.PARDON_LINES,
		"an empty pardon override -> the PARDON_LINES default")
	var calm: Array[String] = ["Alright... easy, now."]
	v._bark_set.pardon = calm
	assert_eq(n._pardon_lines(false), calm, "a filled pardon override wins over the default")
	v.free()
	n.free()


func test_pardon_fleeing_overrides_the_standing_line_but_falls_back_to_it() -> void:
	# THE ALTERNATIVE-LINE CONTRACT. A pardon that lands on a RUNNER reads differently from one that lands on
	# someone standing their ground, so pardon_fleeing overrides the standard pool when authored — but when it
	# is left EMPTY it must fall THROUGH to pardon rather than going silent. Otherwise a designer who filled
	# only the standard category would get no line in the exact situation fleeing_always_forgivable exists for.
	var n = load(NPC_PATH).new()
	var v := NpcVoice.new()
	n._voice = v
	v._bark_set = BarkSet.new()
	var calm: Array[String] = ["Alright... easy, now."]
	v._bark_set.pardon = calm
	assert_eq(n._pardon_lines(true), calm,
		"pardon_fleeing unauthored -> a fleeing pardon FALLS BACK to the standard pardon line")
	var winded: Array[String] = ["You're — you're not shooting?"]
	v._bark_set.pardon_fleeing = winded
	assert_eq(n._pardon_lines(true), winded,
		"once authored, the fleeing variant wins for a runner")
	assert_eq(n._pardon_lines(false), calm,
		"...and does NOT leak into the standing-ground pardon, which keeps its own line")
	v.free()
	n.free()


func test_pardon_categories_default_empty() -> void:
	# Speech ships UNAUTHORED: both new pools are empty by default, so an unprofiled NPC stays SILENT on a pardon
	# until a designer fills a BarkSet (_emit_bark drops an empty line, and bark_pardon early-returns).
	var b := BarkSet.new()
	assert_eq(b.pardon.size(), 0, "BarkSet.pardon defaults empty -> inherits PARDON_LINES")
	assert_eq(b.pardon_fleeing.size(), 0, "BarkSet.pardon_fleeing defaults empty -> falls back to pardon")
	assert_eq(NPC.PARDON_LINES.size(), 0, "the PARDON_LINES const ships empty (unauthored speech is silent)")
	assert_eq(NPC.PARDON_FLEEING_LINES.size(), 0, "...and so does PARDON_FLEEING_LINES")
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
