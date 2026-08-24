extends GutTest

## The DebugEventTicker drop-in (2026-08-18, loop iteration 4): the PURE helpers behind the on-screen event column
## and the console's `events` dump — line formatting, the capped ring (both parallel arrays), the fade/window
## slice, the per-row alpha ramp, the corner layout math — plus the static ring's public API (record / lines /
## clear / set_ring_cap) and an off-tree construct. The live half (autoload + player + rent connections, the
## per-frame paint) needs a running game and is play-verified: nothing here adds a real Player, NPC or autoload
## signal source to the tree, and no _ready runs (a `.new()` is never add_child'ed).
##
## Preloaded BY PATH and held untyped: DebugEventTicker is a brand-new class_name and a not-yet-rescanned editor
## cache would fail this whole file to parse on a typed reference (new-classname-not-registered-cascade).
##
## The ring is STATIC (it must survive the drop-in being freed by a death reload) — so every test that touches it
## clears it first and last, and never assumes another test left it empty.

const TickerScript := preload("res://scripts/components/debug_event_ticker.gd")


func before_each() -> void:
	TickerScript.clear()


func after_each() -> void:
	TickerScript.clear()
	# A fresh instance's own default is the honest reset value (never a hand-typed 300 that could drift).
	var t = TickerScript.new()
	TickerScript.set_ring_cap(t.max_lines)
	t.free()


# --- format_line -----------------------------------------------------------------------------------------------

func test_format_line_is_stamp_channel_colon_text() -> void:
	assert_eq(TickerScript.format_line(12.3, "quest", "started recover_package"),
		"T+12.3s  quest: started recover_package",
		"the documented shape: T+<seconds to 0.1>s, two spaces, channel colon text — the console filter keys on it")
	assert_eq(TickerScript.format_line(0.0, "rent", "notice 250.00"), "T+0.0s  rent: notice 250.00",
		"a zero stamp still prints one decimal (fixed column width per magnitude)")
	assert_eq(TickerScript.format_line(1234.56, "save", "ok"), "T+1234.6s  save: ok",
		"rounds to a tenth, never truncates")


# --- push_capped (both parallel arrays) ---------------------------------------------------------------------------

func test_push_capped_keeps_only_the_last_cap_lines() -> void:
	var ring := PackedStringArray()
	for i in 5:
		ring = TickerScript.push_capped(ring, "line %d" % i, 3)
	assert_eq(ring.size(), 3, "the rolling window keeps only `cap` lines")
	assert_eq(ring[0], "line 2", "the oldest kept is the 3rd-from-last")
	assert_eq(ring[2], "line 4", "the newest is the last pushed")


func test_push_capped_under_cap_keeps_all_and_cap_floors_at_one() -> void:
	var ring := PackedStringArray()
	ring = TickerScript.push_capped(ring, "a", 10)
	ring = TickerScript.push_capped(ring, "b", 10)
	assert_eq(ring.size(), 2, "below the cap nothing is dropped")
	ring = TickerScript.push_capped(ring, "c", 0)
	assert_eq(ring.size(), 1, "a cap of 0 floors to 1 (never an empty ring after a push)")
	assert_eq(ring[0], "c", "and the one kept is the newest")


func test_push_capped_stamps_stays_in_lockstep_with_the_lines() -> void:
	var ring := PackedStringArray()
	var stamps := PackedFloat32Array()
	for i in 7:
		ring = TickerScript.push_capped(ring, "l%d" % i, 4)
		stamps = TickerScript.push_capped_stamps(stamps, float(i), 4)
	assert_eq(ring.size(), stamps.size(), "same cap -> same length: the two arrays are indexed together")
	assert_eq(ring[0], "l3", "oldest kept line")
	assert_eq(stamps[0], 3.0, "…and its stamp, at the same index")
	assert_eq(stamps[3], 6.0, "newest stamp last")


# --- visible_indices / visible_slice (the fade + window as pure data) -----------------------------------------------

func test_visible_slice_hides_lines_older_than_max_age() -> void:
	var ring := PackedStringArray(["old", "mid", "new"])
	var stamps := PackedFloat32Array([0.0, 5.0, 9.0])
	var shown := TickerScript.visible_slice(ring, stamps, 10.0, 6.0, 6)
	assert_eq(shown.size(), 2, "at now=10 with a 6 s window, the 0 s line (age 10) is hidden")
	assert_eq(shown[0], "mid", "oldest visible first")
	assert_eq(shown[1], "new", "newest last")
	# The hidden line is a DISPLAY choice — the ring passed in is untouched.
	assert_eq(ring.size(), 3, "visible_slice never mutates the ring (the ring is the log; the column is a view)")


func test_visible_slice_windows_to_the_newest_count() -> void:
	var ring := PackedStringArray(["a", "b", "c", "d", "e"])
	var stamps := PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var shown := TickerScript.visible_slice(ring, stamps, 5.0, 0.0, 3)
	assert_eq(shown, PackedStringArray(["c", "d", "e"]), "count 3 -> the three newest, oldest first")
	assert_eq(TickerScript.visible_slice(ring, stamps, 5.0, 0.0, 0).size(), 0, "count 0 -> nothing")


func test_visible_slice_max_age_zero_never_hides() -> void:
	var ring := PackedStringArray(["ancient", "new"])
	var stamps := PackedFloat32Array([0.0, 1000.0])
	var shown := TickerScript.visible_slice(ring, stamps, 1000.0, 0.0, 6)
	assert_eq(shown.size(), 2, "max_age <= 0 means no age limit (the `line_seconds` = 0 knob)")


func test_visible_slice_age_exactly_max_age_is_still_shown() -> void:
	var shown := TickerScript.visible_slice(PackedStringArray(["edge"]), PackedFloat32Array([4.0]), 10.0, 6.0, 6)
	assert_eq(shown.size(), 1, "age == max_age is inclusive (hidden only once OLDER than the window)")


func test_visible_slice_does_not_let_an_old_entry_hide_a_younger_one_behind_it() -> void:
	# A caller-supplied `t` (record() is public) can land out of order; the scan must not stop at the first old
	# stamp it meets from the tail, or a younger line further back would vanish.
	var ring := PackedStringArray(["young-a", "stale", "young-b"])
	var stamps := PackedFloat32Array([9.0, 1.0, 9.5])
	var shown := TickerScript.visible_slice(ring, stamps, 10.0, 6.0, 6)
	assert_eq(shown, PackedStringArray(["young-a", "young-b"]), "the stale middle entry is skipped, both young ones survive")


func test_visible_slice_empty_and_mismatched_inputs() -> void:
	assert_eq(TickerScript.visible_slice(PackedStringArray(), PackedFloat32Array(), 1.0, 6.0, 6).size(), 0,
		"empty ring -> empty slice")
	# Sizes can only disagree by a stale HEAD (the arrays only ever grow together), so they align from the tail.
	var ring := PackedStringArray(["orphan", "x", "y"])
	var stamps := PackedFloat32Array([5.0, 6.0])
	var shown := TickerScript.visible_slice(ring, stamps, 6.0, 0.0, 6)
	assert_eq(shown, PackedStringArray(["x", "y"]), "tail-aligned: the extra head line is ignored, never mis-paired")


func test_visible_indices_are_oldest_first_and_bounded_by_count() -> void:
	var stamps := PackedFloat32Array([1.0, 2.0, 3.0, 4.0])
	var idx := TickerScript.visible_indices(stamps, 4.0, 0.0, 2)
	assert_eq(idx, PackedInt32Array([2, 3]), "the two newest indices, in ring order (oldest first)")
	assert_eq(TickerScript.visible_indices(PackedFloat32Array(), 4.0, 0.0, 2).size(), 0, "no stamps -> no indices")


# --- line_alpha ------------------------------------------------------------------------------------------------

func test_line_alpha_ramps_out_over_the_fade_tail() -> void:
	assert_eq(TickerScript.line_alpha(0.0, 6.0, 1.5), 1.0, "a fresh line is fully opaque")
	assert_eq(TickerScript.line_alpha(4.5, 6.0, 1.5), 1.0, "opaque right up to max_age - fade")
	assert_almost_eq(TickerScript.line_alpha(5.25, 6.0, 1.5), 0.5, 0.001, "half way through the fade tail -> half alpha")
	assert_eq(TickerScript.line_alpha(6.0, 6.0, 1.5), 0.0, "at max_age the row is gone")
	assert_eq(TickerScript.line_alpha(60.0, 6.0, 1.5), 0.0, "…and stays gone")


func test_line_alpha_no_fade_and_hard_cut_modes() -> void:
	assert_eq(TickerScript.line_alpha(999.0, 0.0, 1.5), 1.0, "max_age <= 0 never fades (matches visible_slice's no-limit rule)")
	assert_eq(TickerScript.line_alpha(5.9, 6.0, 0.0), 1.0, "fade 0 = hard cut: opaque until max_age…")
	assert_eq(TickerScript.line_alpha(6.0, 6.0, 0.0), 0.0, "…then off")
	assert_eq(TickerScript.line_alpha(-1.0, 6.0, 1.5), 1.0, "a future stamp (negative age) clamps to exactly 1, never over")
	# fade_seconds longer than line_seconds: the ramp is clamped to the lifetime, so a fresh line is still opaque
	# (unclamped, (6 - 0) / 10 would paint every new line at 0.6 and the column would never look solid).
	assert_eq(TickerScript.line_alpha(0.0, 6.0, 10.0), 1.0, "fade > max_age clamps the ramp to max_age: a fresh line is fully opaque")
	assert_almost_eq(TickerScript.line_alpha(3.0, 6.0, 10.0), 0.5, 0.001, "…and ramps over the whole lifetime instead (half way -> half alpha)")


# --- corner layout ---------------------------------------------------------------------------------------------

func test_corner_anchor_maps_each_corner_to_its_edges() -> void:
	assert_eq(TickerScript.corner_anchor(TickerScript.ScreenCorner.TOP_LEFT), Vector2(0, 0), "top-left pins to the 0,0 anchor")
	assert_eq(TickerScript.corner_anchor(TickerScript.ScreenCorner.TOP_RIGHT), Vector2(1, 0), "top-right pins to the right edge")
	assert_eq(TickerScript.corner_anchor(TickerScript.ScreenCorner.BOTTOM_LEFT), Vector2(0, 1), "bottom-left pins to the bottom edge")
	assert_eq(TickerScript.corner_anchor(TickerScript.ScreenCorner.BOTTOM_RIGHT), Vector2(1, 1), "bottom-right pins to both")


func test_corner_offsets_inset_from_the_anchored_corner() -> void:
	var m := Vector2i(8, 216)
	var s := Vector2i(300, 90)
	var tr: Rect2i = TickerScript.corner_offsets(TickerScript.ScreenCorner.TOP_RIGHT, m, s)
	assert_eq(tr.position, Vector2i(-308, 216), "top-right: left offset = -(margin.x + width), top = margin.y")
	assert_eq(tr.size, s, "size is the column size (offset_right/bottom = position + size)")
	assert_eq(tr.position.x + tr.size.x, -8, "…so the right edge sits margin.x in from the screen edge")
	var tl: Rect2i = TickerScript.corner_offsets(TickerScript.ScreenCorner.TOP_LEFT, m, s)
	assert_eq(tl.position, Vector2i(8, 216), "top-left: both offsets are the margin itself")
	var bl: Rect2i = TickerScript.corner_offsets(TickerScript.ScreenCorner.BOTTOM_LEFT, m, s)
	assert_eq(bl.position, Vector2i(8, -306), "bottom-left: top offset = -(margin.y + height)")
	var br: Rect2i = TickerScript.corner_offsets(TickerScript.ScreenCorner.BOTTOM_RIGHT, m, s)
	assert_eq(br.position, Vector2i(-308, -306), "bottom-right: both negative")


# --- the static ring's public API (record / lines / clear / cap) ---------------------------------------------------

func test_record_then_lines_returns_oldest_first_with_filter_and_count() -> void:
	TickerScript.record(1.0, "quest", "started recover_package")
	TickerScript.record(2.0, "rep", "raiders -5.0 -> -35.0")
	TickerScript.record(3.0, "quest", "recover_package/find 1/3")
	TickerScript.record(4.0, "rent", "notice 250.00")
	var all := TickerScript.lines()
	assert_eq(all.size(), 4, "count 0 = every line")
	assert_string_contains(all[0], "T+1.0s  quest: started")
	assert_string_contains(all[3], "rent: notice")
	var quests := TickerScript.lines(0, "quest")
	assert_eq(quests.size(), 2, "the filter is a substring match over the whole line")
	var one := TickerScript.lines(1, "QUEST")
	assert_eq(one.size(), 1, "count windows AFTER filtering, to the newest")
	assert_string_contains(one[0], "1/3")
	assert_true(one[0].contains("T+3.0s"), "…and the filter is case-insensitive (QUEST matched quest)")
	assert_eq(TickerScript.lines(0, "nothing-here").size(), 0, "a filter that matches nothing -> empty, not the whole ring")


func test_clear_wipes_the_ring() -> void:
	TickerScript.record(1.0, "save", "ok")
	assert_eq(TickerScript.lines().size(), 1, "recorded")
	TickerScript.clear()
	assert_eq(TickerScript.lines().size(), 0, "clear() empties it")
	# And the slice over the statics agrees (the two parallel arrays were wiped together).
	assert_eq(TickerScript.visible_slice(TickerScript._ring, TickerScript._stamps, 1.0, 0.0, 6).size(), 0,
		"both parallel arrays are cleared — a stamp without a line (or vice versa) would mis-pair every later row")


func test_ring_cap_applies_to_record() -> void:
	TickerScript.set_ring_cap(3)
	assert_eq(TickerScript.ring_cap(), 3, "the cap reads back")
	for i in 6:
		TickerScript.record(float(i), "money", "+1.00 -> %d.00" % i)
	var kept := TickerScript.lines()
	assert_eq(kept.size(), 3, "the ring holds only the newest `cap` lines")
	assert_string_contains(kept[0], "T+3.0s")
	assert_string_contains(kept[2], "T+5.0s")
	TickerScript.set_ring_cap(0)
	assert_eq(TickerScript.ring_cap(), 1, "the cap floors at 1")


# --- construct off-tree + gates ------------------------------------------------------------------------------------

func test_ticker_constructs_off_tree_with_the_documented_defaults() -> void:
	var t = TickerScript.new()
	assert_not_null(t, "the drop-in compiles + constructs off-tree (no _ready until added to a tree)")
	assert_eq(t.max_lines, 300, "ring default 300 lines (a full session of quest/rep/rent history, not a screen's worth)")
	assert_eq(t.visible_lines, 6, "six rows on screen by default")
	assert_eq(t.line_seconds, 6.0, "a row lives 6 s before it hides (it stays in the ring)")
	assert_eq(t.corner, TickerScript.ScreenCorner.TOP_RIGHT, "defaults to the top-right column under the minimap/clock/tracker stack")
	assert_eq(t.margin, Vector2i(8, 216), "margin.y 216 clears minimap (8..116) + clock (119..141) + a two-line tracker; x 8 lines up with that stack")
	assert_eq(t.column_width, 300, "column width = HudSettings.quest_tracker_width so the left edge lands at x 484 with it")
	assert_false(t.force_in_release, "release builds must not carry a debug surface unless a QA build ticks this")
	assert_true(t.log_money and t.log_xp, "the noisy channels ship ON — the export exists to mute them, not to hide events by default")
	t.free()


func test_column_visibility_reports_hidden_when_no_column_exists() -> void:
	var t = TickerScript.new()
	assert_false(t.is_column_visible(), "off-tree (and in a release build) no column was built — report hidden, never claim one")
	t.set_column_visible(true)
	assert_false(t.is_column_visible(), "asking for it does not conjure one: the debug gate in _ready is the only builder")
	t.set_column_visible(false)
	assert_false(t.is_column_visible(), "and off stays off")
	t.free()


func test_usable_takes_null_off_tree_and_freed_handles_without_error() -> void:
	# The untyped-param idiom (F-C46): a typed `node: Node` would make the VM reject a freed handle BEFORE the body's
	# is_instance_valid could answer. Any engine error here fails the test through GUT's error tracker — that IS the
	# assertion.
	assert_false(TickerScript._usable(null), "null is not usable")
	var n := Node.new()
	assert_false(TickerScript._usable(n), "a live but OFF-TREE node is not usable (a pooled body parked out of tree)")
	add_child(n)
	assert_true(TickerScript._usable(n), "in-tree and valid -> usable")
	remove_child(n)
	n.free()
	assert_false(TickerScript._usable(n), "a FREED handle reads false with no engine error")
