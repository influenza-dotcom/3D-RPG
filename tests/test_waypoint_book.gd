extends GutTest

## WaypointBook (scripts/world/waypoint_book.gd) — the PURE rules behind player-placed map pins: the record
## shape, the two text clamps, the icon->shape mapping, the corrupt-safe load fold and the click hit-test.
## Statics only, so all of it is provable off-tree with no tree, no autoload and no skin.
##
## Loaded BY PATH rather than by class_name — that file deliberately carries none, so nothing here (and
## nothing that consumes it) waits on the editor's global class cache (the MINIMAP_SCRIPT idiom).
##
## What is pinned here is what would rot SILENTLY. A relaxed clamp paints a control character onto the map; a
## reordered enum silently re-icons every pin in every existing save; a fold that stops dropping junk lets a
## hand-edited save inject whatever it likes into a per-frame paint loop.

const WAYPOINT_BOOK := "res://scripts/world/waypoint_book.gd"
const MAP_GLYPH := "res://scripts/ui/map_glyph.gd"

func _wb():
	return load(WAYPOINT_BOOK)

func _glyph():
	return load(MAP_GLYPH)


func test_make_produces_the_full_record_shape() -> void:
	var wb = _wb()
	var rec: Dictionary = wb.make(Vector3(1, 2, 3), "Front Door", "watch the guard", 2, 3)
	assert_eq(rec.get("pos"), Vector3(1, 2, 3), "the marked point round-trips verbatim")
	assert_eq(rec.get("name"), "Front Door", "the label survives a clean name")
	assert_eq(rec.get("note"), "watch the guard", "the note survives a clean body")
	assert_eq(rec.get("icon"), 2, "the icon ordinal is stored, never a shape")
	assert_eq(rec.get("tint"), 3, "the palette INDEX is stored, never a Color — an artist restyling the palette must restyle every saved pin")
	assert_eq(rec.size(), 5,
		"exactly five keys — the ONE optional sixth ('tracked') is GameState's to write, and a make() that grew a sixth field of its own would ride into every save unnoticed")


## A label is painted on ONE line by draw_string. A raw newline or tab in it either breaks the baseline or
## renders as a box, so the clamp flattens the whole control block rather than trusting the entry field.
func test_clean_name_flattens_control_characters_and_collapses_runs() -> void:
	var wb = _wb()
	assert_eq(wb.clean_name("  Safe\tHouse\n\n  by   the   docks  "), "Safe House by the docks",
		"tabs/newlines become spaces and the runs they leave collapse to one")
	assert_eq(wb.clean_name("   "), "", "an all-whitespace label answers empty so the caller can substitute its own default")
	assert_eq(wb.clean_name("plain"), "plain", "a clean label is untouched")
	assert_eq(wb.clean_name("ab"), "a b", "C1 controls flatten too — NEL is a real line break some editors emit")
	assert_eq(wb.clean_name("a b"), "a b", "...and so do Unicode's own line/paragraph separators")


func test_clean_name_is_capped_at_name_max() -> void:
	var wb = _wb()
	var long_name: String = wb.clean_name("x".repeat(200))
	assert_eq(long_name.length(), int(wb.NAME_MAX),
		"a label is clamped to NAME_MAX — the map paints it beside a glyph, not across the panel")


## A note is read in a wrapped panel, so unlike a label it MAY hold line breaks — that is the whole
## difference between the two clamps and it must not quietly converge.
func test_clean_note_keeps_newlines_but_flattens_the_rest() -> void:
	var wb = _wb()
	assert_eq(wb.clean_note("line one\r\nline two\ttabbed"), "line one\nline two tabbed",
		"CRLF normalises to one newline, which SURVIVES; a tab still flattens")
	assert_eq(wb.clean_note("a\rb"), "a\nb", "a bare CR normalises too")
	assert_eq(wb.clean_note("x".repeat(1000)).length(), int(wb.NOTE_MAX),
		"a note is clamped to NOTE_MAX — this is the bound on what one pin adds to a save file")


## The ordinals are written into save files, so their ORDER is a compatibility contract: reordering the enum
## silently re-icons every pin in every existing profile. This pins the count so an insert (rather than an
## append) fails here instead of in a player's save.
func test_icon_vocabulary_is_stable_and_append_only() -> void:
	var wb = _wb()
	assert_eq(wb.Icon.size(), 6, "six icons — NEW KINDS GO ON THE END, never inserted (the ordinals are in every save)")
	assert_eq(int(wb.Icon.PIN), 0, "PIN stays ordinal 0 — it is every unauthored pin's icon")


func test_icon_shape_maps_every_ordinal_and_degrades_junk() -> void:
	var wb = _wb()
	var glyph = _glyph()
	assert_eq(wb.icon_shape(wb.Icon.DANGER), int(glyph.Shape.CROSS), "DANGER is the plus sign")
	assert_eq(wb.icon_shape(wb.Icon.TARGET), int(glyph.Shape.CHEVRON), "TARGET is the arrowhead")
	assert_eq(wb.icon_shape(999), wb.icon_shape(999 % int(wb.Icon.size())),
		"an out-of-range ordinal WRAPS into the vocabulary rather than vanishing (a hand-edited save index must still draw)")


## TRIANGLE means "hostile body" in the NPC alphabet (MapGlyph's own @risk). A player-placed pin that reads
## as a threat in the corner of the eye is the one confusion this alphabet cannot afford.
func test_no_icon_borrows_the_hostile_triangle() -> void:
	var wb = _wb()
	var glyph = _glyph()
	for i in int(wb.Icon.size()):
		assert_ne(wb.icon_shape(i), int(glyph.Shape.TRIANGLE),
			"icon %d must not use TRIANGLE — that shape is reserved for hostile NPC bodies" % i)


func test_wrap_icon_cycles_both_ways() -> void:
	var wb = _wb()
	assert_eq(wb.wrap_icon(-1), int(wb.Icon.size()) - 1, "stepping back from the first icon lands on the last")
	assert_eq(wb.wrap_icon(int(wb.Icon.size())), 0, "stepping past the last lands on the first")


## THE LOAD FOLD. Everything it sees came from a ConfigFile the player can hand-edit, so a bad record is
## DROPPED rather than repaired into something surprising.
func test_sanitize_drops_unrepairable_records() -> void:
	var wb = _wb()
	var out: Array = wb.sanitize([
		{"pos": Vector3(1, 0, 1), "name": "keep"},
		{"pos": "not a vector"},      # a pin with no place is not a pin
		{"name": "no position"},      # ...same
		7,                            # not even a Dictionary
	])
	assert_eq(out.size(), 1, "only the one repairable record survives")
	assert_eq(out[0].get("name"), "keep", "and it is the right one")
	assert_eq(out[0].get("note"), "", "a missing field defaults rather than erroring")


## ConfigFile happily parses Vector3(nan, nan, nan) and Vector3(inf, 0, 0) out of a hand-edited save; either
## would be an unpaintable, unclickable, undeletable ghost eating a cap slot and feeding NaN into a per-frame
## paint loop.
func test_sanitize_drops_a_non_finite_position() -> void:
	var wb = _wb()
	var out: Array = wb.sanitize([
		{"pos": Vector3(NAN, NAN, NAN)},
		{"pos": Vector3(INF, 0.0, 0.0)},
		{"pos": Vector3.ZERO, "name": "real"},
	])
	assert_eq(out.size(), 1, "only the finite pin survives")
	assert_eq(out[0].get("name"), "real", "and it is the right one")


func test_sanitize_refuses_non_array_input() -> void:
	var wb = _wb()
	assert_eq(wb.sanitize("garbage").size(), 0, "a junk-typed section degrades to no pins, never a crash")
	assert_eq(wb.sanitize(null).size(), 0, "...and so does a missing one")


func test_sanitize_re_applies_the_text_clamps() -> void:
	var wb = _wb()
	var out: Array = wb.sanitize([{"pos": Vector3.ZERO, "name": "bad\tname", "note": "x".repeat(500)}])
	assert_eq(out.size(), 1, "the record is kept")
	assert_eq(out[0].get("name"), "bad name", "a hand-edited save cannot smuggle a control character onto the map")
	assert_eq(String(out[0].get("note")).length(), int(wb.NOTE_MAX), "...nor an unbounded note")


func test_sanitize_truncates_past_the_per_level_cap() -> void:
	var wb = _wb()
	var raw := []
	for i in 500:
		raw.append({"pos": Vector3(i, 0, 0)})
	assert_eq(wb.sanitize(raw).size(), int(wb.MAX_PER_LEVEL),
		"a save carrying more than the cap loads the first MAX_PER_LEVEL instead of failing the level's whole list")


# --- The tracked flag: the one OPTIONAL sixth key --------------------------------------------------------
## "tracked" marks THE navigation pin — the one the HUD box always rim-pins and the heading tape draws a pip
## for. This file owns two thirds of the rule: the record never authors the flag itself, and reading it is
## defined in exactly one place so a hand-edited value cannot mean different things on different surfaces.
## The third part — at most one tracked pin across the WHOLE ledger — is GameState's, and is pinned in
## tests/test_waypoints.gd, because a single record can never see the ledger it lives in.

func test_make_never_authors_the_tracked_flag() -> void:
	var wb = _wb()
	var rec: Dictionary = wb.make(Vector3.ZERO, "fresh", "", 0, 0)
	assert_false(rec.has("tracked"),
		"a freshly placed pin is never the tracked one — every placement path goes through make(), so a flag here would let any of them mint a second marker behind GameState's back")
	assert_false(wb.is_tracked(rec), "...and it reads as untracked")


## ConfigFile writes a real bool, but the file is hand-editable, so the predicate has to survive whatever is
## in there. ⭐Never bool(flag): bool() has no String constructor in Godot 4 and would hard-error on exactly
## the value being guarded against.
func test_is_tracked_coerces_every_shape_a_save_can_hold() -> void:
	var wb = _wb()
	assert_true(wb.is_tracked({"tracked": true}), "the bool ConfigFile writes reads as tracked")
	assert_true(wb.is_tracked({"tracked": 1}), "...and so does the 1 a hand edit is likely to write instead")
	assert_false(wb.is_tracked({}), "an ABSENT key is the untracked case — which is every pin, and every save written before the feature")
	assert_false(wb.is_tracked({"tracked": false}), "an explicit false is untracked")
	assert_false(wb.is_tracked({"tracked": 0}), "...and so is a 0")
	assert_false(wb.is_tracked({"tracked": "yes"}), "a junk-typed flag degrades to untracked rather than erroring")
	assert_false(wb.is_tracked({"tracked": null}), "...and so does a null")
	assert_false(wb.is_tracked("not a record"), "a non-Dictionary is not a tracked pin, never a crash")


func test_sanitize_carries_the_tracked_flag_and_never_stores_a_false_one() -> void:
	var wb = _wb()
	var out: Array = wb.sanitize([
		{"pos": Vector3.ZERO, "name": "marked", "tracked": true},
		{"pos": Vector3.ONE, "name": "junk", "tracked": "sure"},
		{"pos": Vector3(2, 0, 0), "name": "plain"},
	])
	assert_eq(out.size(), 3, "all three records are repairable")
	assert_true(wb.is_tracked(out[0]),
		"a tracked pin comes back tracked — the player's destination is part of the profile, not a session mood")
	assert_false(out[1].has("tracked"),
		"a junk flag is not merely false, it is ABSENT: absent IS the false case, and writing false back would grow every save by a key that means nothing")
	assert_false(out[2].has("tracked"), "...and an ordinary pin stores nothing extra at all")


## Where the rule lives, pinned deliberately: this fold sees ONE level's list, while "at most one tracked
## pin" spans every level in the ledger. Enforcing it here would be a half-rule that still needs the real
## one in GameState._fold_tracked — and two places deciding it is how they drift.
func test_sanitize_leaves_the_ledger_wide_de_duplication_to_gamestate() -> void:
	var wb = _wb()
	var out: Array = wb.sanitize([
		{"pos": Vector3.ZERO, "tracked": true},
		{"pos": Vector3.ONE, "tracked": true},
	])
	assert_true(wb.is_tracked(out[0]) and wb.is_tracked(out[1]),
		"both flags pass through the per-level fold; GameState's load fold is what keeps exactly one across the whole ledger")

