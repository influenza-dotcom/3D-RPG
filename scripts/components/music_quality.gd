class_name MusicQuality
extends RefCounted

## A deterministic "quality" score for a song / playlist, derived PURELY from its text (a Spotify URI, a
## "Title - Artist" string, or a radio name). The SAME string always scores the SAME -- no RNG, no Time, no I/O --
## so NPC music reactions are stable and the whole thing is unit-testable off-tree. The number is arbitrary but
## repeatable: it does NOT judge real musical merit, it just folds the characters into a 0..1, which is enough to
## bucket a song into a reaction tier (so one NPC consistently loves a track another finds awful).

enum Tier { AWFUL, MEH, GOOD, GREAT }

## A stable 0..1 quality for `text`. Empty / whitespace -> 0.5 (a neutral middle, never a crash or a skew).
static func score(text: String) -> float:
	var s := text.strip_edges().to_lower()
	if s.is_empty():
		return 0.5
	# djb2 integer fold, masked to a positive 31-bit int every step so it can NEVER overflow int64 (h*33 stays
	# well under the max) -- explicit, so the result is pinned by the unit test and identical across platforms /
	# engine versions (unlike leaning on String.hash()).
	var h := 5381
	for i in s.length():
		h = ((h << 5) + h + s.unicode_at(i)) & 0x7FFFFFFF
	return float(h % 10000) / 9999.0

## The reaction Tier for `text` given the three cut thresholds (designer tunables on NpcAiSettings, passed in so
## this stays a pure dependency-free static). AWFUL below `meh`, MEH below `good`, GOOD below `great`, else GREAT.
static func tier(text: String, meh: float, good: float, great: float) -> int:
	var q := score(text)
	if q < meh:
		return Tier.AWFUL
	if q < good:
		return Tier.MEH
	if q < great:
		return Tier.GOOD
	return Tier.GREAT
