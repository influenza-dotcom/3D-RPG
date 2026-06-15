extends GutTest

## MusicQuality: the pure, deterministic song/playlist scorer that NPC music reactions key off. Every method is a
## static on a RefCounted taking only String/float -- zero tree access -- so we load() the script and assert
## directly (no .new() of an NPC/Radio/Player, no _ready), releasing the ref per CLAUDE.md.

const MQ := preload("res://scripts/components/music_quality.gd")

const CORPUS := [
	"spotify:track:7ccI9cStQbQdystvc6TvxD",
	"spotify:playlist:37i9dQZF1DXcBWIGoYBM5M",
	"spotify:album:1DFixLWuPkv3KT3TnV35m3",
	"spotify:artist:0k17h0D3J5VfsdmQ1iZtE9",
	"Bohemian Rhapsody - Queen",
	"Jukebox",
	"",
	"   ",
	"Café del Mar",
]


func test_score_is_deterministic() -> void:
	for s in CORPUS:
		assert_eq(MQ.score(s), MQ.score(s), "the same string must always score identically: %s" % s)


func test_score_is_bounded_0_to_1() -> void:
	for s in CORPUS:
		var q: float = MQ.score(s)
		assert_between(q, 0.0, 1.0, "score must stay in 0..1 for: %s" % s)


func test_empty_and_whitespace_score_the_neutral_floor() -> void:
	assert_almost_eq(MQ.score(""), 0.5, 0.0001, "an empty string scores the neutral middle (never a crash)")
	assert_almost_eq(MQ.score("   "), 0.5, 0.0001, "whitespace strips to empty -> the same neutral middle")


func test_tier_buckets_around_the_actual_score() -> void:
	# Build thresholds around a string's real score so the boundary mapping is pinned without predicting the hash.
	var s := "Bohemian Rhapsody - Queen"
	var q: float = MQ.score(s)
	assert_eq(MQ.tier(s, q + 0.01, 1.0, 1.0), MQ.Tier.AWFUL, "score below meh -> AWFUL")
	assert_eq(MQ.tier(s, 0.0, q + 0.01, 1.0), MQ.Tier.MEH, "score in [meh, good) -> MEH")
	assert_eq(MQ.tier(s, 0.0, 0.0, q + 0.01), MQ.Tier.GOOD, "score in [good, great) -> GOOD")
	assert_eq(MQ.tier(s, 0.0, 0.0, q), MQ.Tier.GREAT, "score at/above great -> GREAT")
