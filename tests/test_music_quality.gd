extends GutTest

## MusicQuality: the pure, deterministic song/playlist scorer that NPC music reactions key off. Every method is a
## static on a RefCounted taking only String/float -- zero tree access -- so we load() the script and assert
## directly (no .new() of an NPC/Radio/Player, no _ready), releasing the ref per CLAUDE.md.
##
## GOLDEN VALUES below are worked BY HAND from the documented djb2 fold, never by calling the scorer:
##   s = text.strip_edges().to_lower();  h = 5381;  per char: h = (h*32 + h + codepoint) & 0x7FFFFFFF
##   score = (h % 10000) / 9999.0         codepoints: 'a'=97 'b'=98 'c'=99 'd'=100 ' '=32 'e-acute'=233
## A pinned value is what keeps one NPC's love / hatred of a given track stable across builds and platforms.

const MQ := preload("res://scripts/components/music_quality.gd")

## Tight enough that a 9999 -> 10000 divisor slip (~7.7e-5 on these inputs) is caught.
const TOL := 0.000000001

## "a": 5381*32 = 172192; + 5381 = 177573; + 97 = 177670 (< 2^31, mask no-op). 177670 % 10000 = 7670.
##      7670 / 9999 = 0.767076707670767
const SCORE_A := 0.767076707670767
## "ab": 177670*33 = 5863110; + 98 = 5863208. 5863208 % 10000 = 3208. 3208 / 9999 = 0.320832083208321
const SCORE_AB := 0.320832083208321
## "abc": 5863208*33 = 193485864; + 99 = 193485963 (< 2^31). % 10000 = 5963. 5963 / 9999 = 0.596359635963596
const SCORE_ABC := 0.596359635963596
## "abcd": 193485963*33 = 6385036779; + 100 = 6385036879, which is OVER 2^31-1 = 2147483647, so the mask bites:
##   low 31 bits = 6385036879 - 2*2147483648 = 2090069583. % 10000 = 9583. 9583 / 9999 = 0.958395839583958
##   (without the mask it would be 6879 / 9999 = 0.687968796879688)
const SCORE_ABCD := 0.958395839583958
## "é" (U+00E9 = 233): 177573 + 233 = 177806. % 10000 = 7806. 7806 / 9999 = 0.780678067806781
const SCORE_E_ACUTE := 0.780678067806781

const CORPUS := [
	"01_neon_drive.mp3",
	"midnight_static.ogg",
	"res://assets/audio/music/synthwave_loop.mp3",
	"track_07.wav",
	"Bohemian Rhapsody - Queen",
	"Jukebox",
	"",
	"   ",
	"Café del Mar",
]


func test_single_character_scores_its_hand_worked_djb2_value() -> void:
	assert_almost_eq(MQ.score("a"), SCORE_A, TOL,
		"\"a\" must fold to h=177670 -> 7670/9999; a different value means the hash changed and every NPC's taste in music silently reshuffled")


func test_two_and_three_character_scores_chain_the_fold_per_character() -> void:
	assert_almost_eq(MQ.score("ab"), SCORE_AB, TOL,
		"\"ab\" must fold to h=5863208 -> 3208/9999 (each char multiplies the running hash by 33 then adds its code point)")
	assert_almost_eq(MQ.score("abc"), SCORE_ABC, TOL,
		"\"abc\" must fold to h=193485963 -> 5963/9999; the third step of the fold drifted")


func test_the_31_bit_mask_wraps_a_long_fold_instead_of_growing_unbounded() -> void:
	assert_almost_eq(MQ.score("abcd"), SCORE_ABCD, TOL,
		"\"abcd\" overflows 31 bits on the 4th char; masked it is h=2090069583 -> 9583/9999 (unmasked would read 6879) -- the per-step 0x7FFFFFFF mask is what keeps long track names platform-stable")


func test_non_ascii_folds_its_unicode_code_point() -> void:
	assert_almost_eq(MQ.score("é"), SCORE_E_ACUTE, TOL,
		"an accented title must fold its Unicode code point (233 -> h=177806 -> 7806/9999), not UTF-8 bytes or a lossy substitute")


func test_score_ignores_case_and_surrounding_whitespace() -> void:
	# The fold runs on strip_edges().to_lower(), so every spelling below is the text "ab" and must land on its golden.
	for raw: String in ["AB", "Ab", "  ab\t", "\n AB  "]:
		assert_almost_eq(MQ.score(raw), SCORE_AB, TOL,
			"%s must score exactly like \"ab\" (3208/9999): a radio shouting a track's name in caps, or padding it, must not flip an NPC's reaction" % JSON.stringify(raw))


func test_different_inputs_score_differently() -> void:
	# "a" 7670 vs "b" 7671 (177573 + 98 = 177671): neighbouring characters must move the score.
	assert_ne(MQ.score("a"), MQ.score("b"), "\"a\" and \"b\" must score differently (7670 vs 7671 /9999) -- the character itself must feed the fold")
	# "ba": 177671*33 = 5863143; + 97 = 5863240 -> 3240, vs "ab" 3208: order matters.
	assert_ne(MQ.score("ab"), MQ.score("ba"), "\"ab\" and \"ba\" must score differently (3208 vs 3240 /9999) -- the fold must be order-sensitive")
	# "a b": 177670*33 + 32 = 5863142; *33 = 193483686; + 98 = 193483784 -> 3784, vs "ab" 3208: only EDGES are trimmed.
	assert_ne(MQ.score("a b"), MQ.score("ab"), "\"a b\" must not collapse onto \"ab\" (3784 vs 3208 /9999) -- only surrounding whitespace is stripped")


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


func test_same_thresholds_put_different_songs_in_different_tiers() -> void:
	# With cuts meh=0.33 / good=0.60 / great=0.77 the hand-worked goldens fall one per tier:
	#   "ab" 0.3208 < 0.33 -> AWFUL;  "abc" 0.5964 in [0.33, 0.60) -> MEH;
	#   "a" 0.7671 in [0.60, 0.77) -> GOOD;  "é" 0.7807 >= 0.77 -> GREAT.
	assert_eq(MQ.tier("ab", 0.33, 0.60, 0.77), MQ.Tier.AWFUL, "\"ab\" (0.3208) must be AWFUL under meh=0.33")
	assert_eq(MQ.tier("abc", 0.33, 0.60, 0.77), MQ.Tier.MEH, "\"abc\" (0.5964) must be MEH between meh=0.33 and good=0.60")
	assert_eq(MQ.tier("a", 0.33, 0.60, 0.77), MQ.Tier.GOOD, "\"a\" (0.7671) must be GOOD between good=0.60 and great=0.77")
	assert_eq(MQ.tier("é", 0.33, 0.60, 0.77), MQ.Tier.GREAT, "\"é\" (0.7807) must be GREAT at/above great=0.77")
