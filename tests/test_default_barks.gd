extends GutTest

## The NPC's default bark lines live in resources/barks/default_barks.tres: the BarkSet an NPC with no profile BarkSet
## (NpcData.bark_set) speaks from, so filling a category there gives every such NPC that line. A profile's own BarkSet
## replaces it, and each EMPTY category of whichever set is in charge falls back to the npc.gd *_LINES const. Since the
## AI-text scrub every const ships EMPTY, so authored bark text lives only in BarkSet .tres files.
## Covers: the default file loads and is what a profile-less NPC resolves; a fresh BarkSet overrides no category; the
## pardon pool's fleeing-variant fallback and the music pool's per-tier routing (npc.gd _pardon_lines / _music_lines,
## tested nowhere else); and a pardon with no authored line staying silent (NpcVoice.bark_pardon). The empty-category
## fallback onto an npc.gd const is not re-checked through _pardon_lines / _music_lines: every const ships empty, so
## that fallback is indistinguishable from the override there; _bark_pool's fallback is driven with a non-empty
## default in test_a_fresh_bark_set_overrides_no_category.

const NPC_PATH := "res://scripts/npc/npc.gd"
const MQ := preload("res://scripts/components/music_quality.gd")
const DEFAULT_BARKS := "res://resources/barks/default_barks.tres"

## The shared (cached) default_barks instance the authoring test writes into, and the arrays it replaced, so
## after_each puts them back: every NpcVoice in this process speaks from that one resource.
var _shared_defaults: BarkSet = null
var _saved_pardon: Array[String] = []
var _saved_music_great: Array[String] = []


## Stand-in for the NPC members NpcVoice.bark_pardon reads, recording what it says and every bubble it clears.
class PardonHost extends Node3D:
	var _dead := false
	var hp := 10.0
	var player: Node3D = null
	var emitted: Array = []
	var cleared := 0

	func _find_talkable():
		return null

	func _real_player():
		return player

	func _clear_bark_bubble() -> void:
		cleared += 1

	func _emit_bark(line: String, _voice) -> void:
		emitted.append(line)


func after_each() -> void:
	if _shared_defaults != null:
		_shared_defaults.pardon = _saved_pardon
		_shared_defaults.music_great = _saved_music_great
		_shared_defaults = null


func test_default_barks_loads_as_a_bark_set() -> void:
	var b := load(DEFAULT_BARKS) as BarkSet
	assert_not_null(b, "default_barks.tres loads as a BarkSet")


func test_lines_authored_in_default_barks_reach_an_npc_with_no_profile() -> void:
	# The supported route for shared barks (REMEDIATION_PLAN "Do not fill the empty bark arrays"): author a category in
	# default_barks.tres and every NPC without its own BarkSet says it. Authored here on the loaded, cached instance
	# (the one NpcVoice preloads) and restored in after_each.
	_shared_defaults = load(DEFAULT_BARKS) as BarkSet
	if _shared_defaults == null:
		fail_test("default_barks.tres must load as a BarkSet")
		return
	_saved_pardon = _shared_defaults.pardon
	_saved_music_great = _shared_defaults.music_great
	var pardon_lines: Array[String] = ["Fine. Walk away."]
	var great_lines: Array[String] = ["Now THAT is a song."]
	_shared_defaults.pardon = pardon_lines
	_shared_defaults.music_great = great_lines
	var n = load(NPC_PATH).new()
	var v := NpcVoice.new()  # as NPC._build_components leaves it when the NPC has no NpcData.bark_set
	n._voice = v
	assert_eq(n._pardon_lines(false), pardon_lines,
		"a pardon line authored in default_barks.tres must reach an NPC that has no profile BarkSet")
	assert_eq(n._pardon_lines(true), pardon_lines,
		"...and still cover that NPC when the pardon catches it mid-run (its fleeing variant is unauthored)")
	assert_eq(n._music_lines(MQ.Tier.GREAT), great_lines,
		"a music comment authored in default_barks.tres must reach an NPC that has no profile BarkSet")
	n._voice = null
	v.free()
	n.free()


func test_a_fresh_bark_set_overrides_no_category() -> void:
	# The inherit-or-override rule: an EMPTY category means "use the NPC's default lines", so giving an archetype a new
	# BarkSet profile without filling a category must leave that category's default in charge.
	var fresh := BarkSet.new()
	var npc_default: Array[String] = ["the NPC's own default line"]
	var checked: Array[String] = []
	for p in fresh.get_property_list():
		if (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or int(p.type) != TYPE_ARRAY:
			continue
		var category: Array[String] = fresh.get(p.name)
		assert_eq(NPC._bark_pool(npc_default, category), npc_default,
			"a fresh BarkSet must not override '%s': an archetype given a profile keeps that category's default lines" % p.name)
		checked.append(String(p.name))
	for expected in ["spot", "check_body", "pardon", "pardon_fleeing", "music_awful", "music_meh", "music_good", "music_great"]:
		assert_has(checked, expected, "the BarkSet category '%s' must be among the categories checked" % expected)
	fresh = null


func test_pardon_fleeing_overrides_the_standing_line_but_falls_back_to_it() -> void:
	# THE ALTERNATIVE-LINE CONTRACT. A pardon that lands on a RUNNER reads differently from one that lands on
	# someone standing their ground, so pardon_fleeing overrides the standard pool when authored — but when it
	# is left EMPTY it must fall THROUGH to pardon rather than going silent. Otherwise a designer who filled
	# only the standard category would get no line when a FIRST holster catches an un-betrayed fleer mid-sprint.
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


func test_pardon_consts_ship_unauthored() -> void:
	# SHIP DECISION (the AI-text scrub, see REMEDIATION_PLAN "Do not fill the empty bark arrays"): bark text is authored
	# content that belongs in a BarkSet .tres (pardon / pardon_fleeing), never in the npc.gd consts.
	assert_eq(NPC.PARDON_LINES.size(), 0,
		"PARDON_LINES ships EMPTY: a pardoned NPC says nothing until a designer authors BarkSet.pardon")
	assert_eq(NPC.PARDON_FLEEING_LINES.size(), 0,
		"PARDON_FLEEING_LINES ships EMPTY too: the runner's variant is authored in BarkSet.pardon_fleeing")


func test_a_pardon_with_no_authored_line_stays_silent() -> void:
	var none: Array[String] = []
	var quiet := _pardon_host()
	_pardon_voice(quiet).bark_pardon(none)
	assert_eq(quiet.emitted, [], "a pardon with no authored line (the shipped default) must say nothing")
	assert_eq(quiet.cleared, 0,
		"...and must not wipe the bubble the NPC is still showing (often its flee line) for a line it never says")
	var calm: Array[String] = ["Alright... easy, now."]
	var vocal := _pardon_host()
	_pardon_voice(vocal).bark_pardon(calm)
	assert_eq(vocal.emitted, ["Alright... easy, now."], "control: the same pardoned NPC with an authored line says it")
	assert_eq(vocal.cleared, 1, "control: ...replacing whatever bubble was showing, so the payoff line always lands")


func test_each_music_tier_speaks_from_its_own_category() -> void:
	# A jukebox comment is keyed to how GOOD the song is (MusicQuality tier), so an NPC with every music category
	# authored must answer each tier with that tier's line: a crossed wire here has a raider praise an awful playlist.
	var n = load(NPC_PATH).new()
	var v := NpcVoice.new()
	n._voice = v
	v._bark_set = BarkSet.new()
	var awful: Array[String] = ["Turn that off."]
	var meh: Array[String] = ["It's music, I guess."]
	var good: Array[String] = ["Not bad at all."]
	var great: Array[String] = ["Now THAT is a song."]
	v._bark_set.music_awful = awful
	v._bark_set.music_meh = meh
	v._bark_set.music_good = good
	v._bark_set.music_great = great
	assert_eq(n._music_lines(MQ.Tier.AWFUL), awful, "an AWFUL song gets the music_awful line")
	assert_eq(n._music_lines(MQ.Tier.MEH), meh, "a MEH song gets the music_meh line")
	assert_eq(n._music_lines(MQ.Tier.GOOD), good, "a GOOD song gets the music_good line")
	assert_eq(n._music_lines(MQ.Tier.GREAT), great, "a GREAT song gets the music_great line")
	# An unauthored tier must not borrow a neighbour's comment: with music_good left empty, a GOOD song may not be
	# answered with the MEH or GREAT line (the npc.gd consts behind it ship empty, so today it is silence).
	var none: Array[String] = []
	v._bark_set.music_good = none
	var unauthored: Array[String] = n._music_lines(MQ.Tier.GOOD)
	for other: Array[String] in [awful, meh, great]:
		assert_false(unauthored.has(other[0]),
			"an unauthored music_good must not answer a GOOD song with another tier's line '%s'" % other[0])
	v.free()
	n.free()


## An in-tree PardonHost (the earshot check reads global_position) with the listening player 1 m away.
func _pardon_host() -> PardonHost:
	var h := PardonHost.new()
	add_child_autofree(h)
	var listener := Node3D.new()
	add_child_autofree(listener)
	listener.global_position = h.global_position + Vector3(1.0, 0.0, 0.0)
	h.player = listener
	return h


func _pardon_voice(h: Node) -> NpcVoice:
	var v := NpcVoice.new()
	v.host = h
	autofree(v)
	return v
