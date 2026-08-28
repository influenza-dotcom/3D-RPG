extends RefCounted

## @system Minimap
## @seam The pure RULES for player-placed map waypoints — the record shape, the two text clamps, the icon
## vocabulary and the corrupt-safe load fold. GameState owns the STORAGE (its `waypoints` ledger + the
## [waypoints] save section), scripts/ui/minimap.gd owns the PAINT — and the CLICK hit-test lives there too
## (Minimap.waypoint_at_point), in SCREEN space against the exact points the paint inked, so the two can
## never disagree about where a pin is. This file owns everything that can be decided without a tree, an
## autoload or a skin.
## @seam A record stores a PALETTE INDEX (`tint`), never a Color. Two reasons, and both are load-bearing: an
## artist who restyles minimap_waypoint_palette on hud_skin.tres restyles every pin already saved in every
## profile (a stored Color would freeze the old look into the save forever), and an int survives a ConfigFile
## round-trip with no parsing. Same argument as the icon, which stores an Icon ordinal rather than a shape.
## @risk NO class_name, deliberately. This is a NEW file and the user's editor is normally open, where a new
## class_name is not in .godot/global_script_class_cache.cfg until a rescan — and until then every consumer
## that names the type fails to parse and cascades. Every consumer preloads it BY PATH instead (the
## FLOORPLAN_SOURCE / MINIMAP_ART idiom in minimap.gd), which needs no cache entry at all.
## @test res://tests/test_waypoint_book.gd
##
## STATICS ONLY — no nodes, no tree access, no autoload reads, no Settings/GameSettings/MenuStyle — so every
## rule here is provable off-tree exactly the way FloorplanSection, MapGlyph and Compass.project_to_edge are.
## The one preload is map_glyph.gd, and only for its Shape ordinals (also a statics-only file).
##
## THE RECORD, and why it is a Dictionary rather than a Resource. It rides GameState's [waypoints] section
## straight into a ConfigFile, and ConfigFile serialises a Dictionary of built-ins natively — a Resource
## would need its own .tres path per pin, or a to_dict/from_dict pair that is this file with more ceremony.
## The world_objects ledger next door made the same call for the same reason.
##   pos  : Vector3  the marked point in WORLD space (already the map's own coordinate system)
##   name : String   the short label painted beside the pin on the map tab (clamped, single line)
##   note : String   the longer body shown when the pin is selected (clamped, may wrap over lines)
##   icon : int      an Icon ordinal -> a MapGlyph.Shape via icon_shape()
##   tint : int      an INDEX into MenuStyle.hud.minimap_waypoint_palette, wrapped at the paint site
## ...plus ONE optional sixth key that make() deliberately does not author:
##   tracked : bool  present-and-true on THE tracked pin — the single "go here" marker the HUD corner box
##                   always rim-pins and the heading tape draws a pip for. ABSENT MEANS FALSE, so a pin nobody
##                   tracked stores nothing extra and a save written before the feature is already correct.
##                   Written ONLY by GameState.set_tracked_waypoint, because "at most one across the WHOLE
##                   ledger" is a fact about the ledger and cannot be enforced from a single record.

## The marker alphabet, kept SHORT on purpose. Six shapes the player can tell apart at a ~5 px glyph on the
## 108 px HUD box — the same readability budget MapGlyph's own enum was chosen against. The names describe
## what a player MEANS by the pin, not the polygon: the shape mapping below is an implementation detail that
## an artist may re-point, while a saved profile's stored ordinal must keep meaning the same thing.
##
## ⭐ORDER IS STABLE AND APPEND-ONLY. These ordinals are written into every save file; reordering them
## silently re-icons every pin in every existing profile. New kinds go on the END.
enum Icon {
	PIN,      ## the default — "here"
	STAR,     ## somewhere worth coming back to
	CACHE,    ## a stash / loot you left behind
	DANGER,   ## somewhere that hurt you
	HOME,     ## a base, a bed, a bonfire you actually use
	TARGET,   ## something you intend to go do
}

## The shape vocabulary this file draws from (statics only, like this one). Preloaded BY PATH and kept
## untyped for the same class-cache reason this file has no class_name of its own.
const MAP_GLYPH := preload("res://scripts/ui/map_glyph.gd")

## Longest label a pin may carry. Sized against the MAP TAB, which is the only surface that paints it: at the
## shipped panel width a 28-character label is comfortably shorter than the gap between two pins placed a
## room apart, so labels rarely collide. NameEntryDialog's own MAX_NAME_LENGTH (24) is stricter and clamps
## first on the in-world path; this is the ceiling for every path including a hand-edited save.
const NAME_MAX := 28

## Longest note a pin may carry. A note is a reminder, not a journal entry — the Journal tab is the place
## for prose — and this is also the bound on how much one pin can add to a save file.
const NOTE_MAX := 240

## How many pins one level may hold. A cap exists so a save cannot grow without bound and so the map cannot
## be turned into an unreadable field of glyphs; 32 is far past what a player places by hand in one district
## and still a trivial paint cost (the marker channels are already O(bodies) per frame).
const MAX_PER_LEVEL := 32


## A fresh record, with every field already through its own clamp — so a caller can never construct an
## invalid pin and nothing downstream has to re-validate. The two ints WRAP rather than clamp: they index
## cyclic vocabularies (the icon chips and the palette chips both cycle), and wrapping is what makes
## "next icon" a single expression at every call site.
##
## ⭐FIVE FIELDS, AND IT STAYS FIVE. This is the constructor every placement path reaches for (the map tab's
## click, the Mark key, the load fold), so a `tracked` parameter here would let any of them mint a second
## tracked pin behind GameState's back. The flag is written only by GameState.set_tracked_waypoint — and
## anything that REBUILDS an existing record through this function (GameState.update_waypoint does, to keep a
## pin's position immutable) must carry the old flag across the rebuild itself.
static func make(pos: Vector3, name: String, note: String, icon: int, tint: int) -> Dictionary:
	return {
		"pos": pos,
		"name": clean_name(name),
		"note": clean_note(note),
		"icon": wrap_icon(icon),
		"tint": maxi(0, tint),
	}


## A label, made safe to paint on one line. Strips every control character (a raw newline or tab in a label
## would either break the draw_string baseline or silently render as a box), collapses the runs of spaces
## that leaves behind, then clamps the length. Returns "" for an all-junk entry — callers substitute their
## own default name, because a DEFAULT is player copy and owes PlayerText, which this file may not read.
static func clean_name(s: String) -> String:
	var out := ""
	for ch in s:
		# < 0x20 is the C0 control block (newline, tab, CR, NUL...), 0x7F is DEL, 0x80-0x9F is the C1 block
		# (which includes NEL, a real line break some editors emit), and U+2028/U+2029 are Unicode's own
		# line/paragraph separators — every one of them can break a one-line draw_string or render as a box.
		# Everything else is printable text in some script, and this file must not have an opinion about which.
		var c := ch.unicode_at(0)
		out += " " if _is_control(c) else ch
	return _collapse_spaces(out).substr(0, NAME_MAX).strip_edges()


## A note body. Unlike a label this MAY hold newlines — a note is read in a wrapped panel, and a player who
## types two lines meant two lines — so only the carriage return is normalised away (a pasted CRLF would
## otherwise paint a stray box at every line end) and the tab/DEL class is still flattened.
static func clean_note(s: String) -> String:
	var out := ""
	for ch in s.replace("\r\n", "\n").replace("\r", "\n"):
		var c := ch.unicode_at(0)
		if c == 10:
			out += ch          # a real line break — a note may hold them
		elif _is_control(c):
			out += " "         # every other control character flattens rather than painting a box
		else:
			out += ch
	return out.substr(0, NOTE_MAX).strip_edges()


## The one definition of "a character that must not reach a draw_string": C0 controls, DEL, the C1 block
## (0x80-0x9F — NEL lives there), and Unicode's own line/paragraph separators. One predicate so the two
## clamps above can never drift on what counts as junk.
static func _is_control(c: int) -> bool:
	return c < 32 or c == 127 or (c >= 128 and c <= 159) or c == 0x2028 or c == 0x2029


## Runs of whitespace -> one space. Split-and-rejoin rather than a regex: RegEx must be compiled at runtime
## (it cannot be a const), and this runs on every keystroke of the name field.
static func _collapse_spaces(s: String) -> String:
	var parts := s.split(" ", false)  # false = drop the empties the runs produce
	return " ".join(parts)


## Icon ordinal -> the MapGlyph.Shape the paint site draws. The mapping is HERE rather than at the paint
## site so the map tab, the HUD box and any future consumer can never disagree about what a saved ordinal
## looks like. Anything unrecognised degrades to the PIN shape rather than returning something undrawable.
##
## The shapes are chosen for silhouette spread at ~5 px, and DELIBERATELY avoid TRIANGLE: that shape is
## reserved by the NPC family for "hostile body" (MapGlyph's own @risk), and a player-placed pin that reads
## as a threat in the corner of the eye is the one confusion this alphabet cannot afford.
static func icon_shape(icon: int) -> int:
	match wrap_icon(icon):
		Icon.STAR:
			return MAP_GLYPH.Shape.HEXAGON
		Icon.CACHE:
			return MAP_GLYPH.Shape.SQUARE
		Icon.DANGER:
			return MAP_GLYPH.Shape.CROSS
		Icon.HOME:
			return MAP_GLYPH.Shape.CIRCLE
		Icon.TARGET:
			return MAP_GLYPH.Shape.CHEVRON
	return MAP_GLYPH.Shape.DIAMOND  # Icon.PIN


## Cycle an icon ordinal into range. Wrapping (not clamping) is what lets one "next icon" button walk the
## whole vocabulary from either end, and what makes a junk ordinal out of an edited save resolve to a real
## shape instead of vanishing.
static func wrap_icon(icon: int) -> int:
	return posmod(icon, int(Icon.size()))


## Does this record carry the tracked flag? THE one definition of what "tracked" reads as — the fold below,
## GameState's ledger and every paint site ask HERE, so none of them can drift on the answer. A record that
## simply has no such key (the normal case, and every save written before the feature) is not tracked.
##
## The junk cases are decided here too, because this is the only place they can be decided once: a hand-edited
## save may write `tracked=1` where ConfigFile writes `tracked=true`, so a number counts; a String, a
## Dictionary or a null is false rather than an error. ⭐Do NOT "simplify" this to bool(flag) — bool() has no
## String constructor in Godot 4 and would hard-error on exactly the hand-edited value this guards against.
static func is_tracked(rec: Variant) -> bool:
	if not (rec is Dictionary):
		return false
	var flag: Variant = (rec as Dictionary).get("tracked", false)
	if flag is int or flag is float:
		return float(flag) != 0.0
	var on: bool = flag if flag is bool else false
	return on


## THE CORRUPT-SAFE LOAD FOLD, and the ONLY way persisted waypoint data may enter memory. Everything here
## arrives from a ConfigFile the player can hand-edit, so every field is type-guarded and every bad record
## is DROPPED rather than repaired into something surprising — the world_objects ledger's own rule.
##
## The cap is applied last and by TRUNCATION, so a save that somehow carries 500 pins loads the first
## MAX_PER_LEVEL instead of failing the level's whole list.
##
## The `tracked` flag PASSES THROUGH (coerced by is_tracked, and re-written only when true so the "absent
## means false" shape survives the round trip) but is NOT de-duplicated here: this function sees ONE level's
## list, while "at most one tracked pin" spans the whole ledger. GameState's load fold enforces that across
## every level as it folds them in — see _fold_tracked there.
static func sanitize(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array):
		return out
	for entry: Variant in raw as Array:
		if not (entry is Dictionary):
			continue
		var d := entry as Dictionary
		var pos: Variant = d.get("pos")
		if not (pos is Vector3):
			continue  # a pin with no place is not a pin — there is nothing to repair it to
		if not (pos as Vector3).is_finite():
			continue  # ConfigFile happily parses Vector3(nan/inf, ...) out of a hand-edited save; a NaN
			          # position is unpaintable, unclickable and undeletable — the same "no place" case
		var name: Variant = d.get("name", "")
		var note: Variant = d.get("note", "")
		var icon: Variant = d.get("icon", 0)
		var tint: Variant = d.get("tint", 0)
		var rec := make(pos as Vector3,
				name if name is String else "",
				note if note is String else "",
				int(icon) if (icon is int or icon is float) else 0,
				int(tint) if (tint is int or tint is float) else 0)
		if is_tracked(d):
			rec["tracked"] = true  # only ever written when TRUE — absent stays the false case
		out.append(rec)
		if out.size() >= MAX_PER_LEVEL:
			break
	return out
