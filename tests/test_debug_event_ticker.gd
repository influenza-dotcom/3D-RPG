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

## The column's view of the ring as pure data — the lines visible_indices would show, oldest first. The drop-in
## paints straight from the indices (_paint), so this composition lives with the tests that read it.
static func _slice(ring: PackedStringArray, stamps: PackedFloat32Array, now: float, max_age: float, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for idx in TickerScript.visible_indices(stamps, now, max_age, count):
		out.append(ring[idx])
	return out


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


# --- visible_indices (the fade + window as pure data, read through _slice) -----------------------------------------------

func test_visible_slice_hides_lines_older_than_max_age() -> void:
	var ring := PackedStringArray(["old", "mid", "new"])
	var stamps := PackedFloat32Array([0.0, 5.0, 9.0])
	var shown := _slice(ring, stamps, 10.0, 6.0, 6)
	assert_eq(shown.size(), 2, "at now=10 with a 6 s window, the 0 s line (age 10) is hidden")
	assert_eq(shown[0], "mid", "oldest visible first")
	assert_eq(shown[1], "new", "newest last")
	# The hidden line is a DISPLAY choice — the ring passed in is untouched.
	assert_eq(ring.size(), 3, "the slice never mutates the ring (the ring is the log; the column is a view)")


func test_visible_slice_windows_to_the_newest_count() -> void:
	var ring := PackedStringArray(["a", "b", "c", "d", "e"])
	var stamps := PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var shown := _slice(ring, stamps, 5.0, 0.0, 3)
	assert_eq(shown, PackedStringArray(["c", "d", "e"]), "count 3 -> the three newest, oldest first")
	assert_eq(_slice(ring, stamps, 5.0, 0.0, 0).size(), 0, "count 0 -> nothing")


func test_visible_slice_max_age_zero_never_hides() -> void:
	var ring := PackedStringArray(["ancient", "new"])
	var stamps := PackedFloat32Array([0.0, 1000.0])
	var shown := _slice(ring, stamps, 1000.0, 0.0, 6)
	assert_eq(shown.size(), 2, "max_age <= 0 means no age limit (the `line_seconds` = 0 knob)")


func test_visible_slice_age_exactly_max_age_is_still_shown() -> void:
	var shown := _slice(PackedStringArray(["edge"]), PackedFloat32Array([4.0]), 10.0, 6.0, 6)
	assert_eq(shown.size(), 1, "age == max_age is inclusive (hidden only once OLDER than the window)")


func test_visible_slice_does_not_let_an_old_entry_hide_a_younger_one_behind_it() -> void:
	# A caller-supplied `t` (record() is public) can land out of order; the scan must not stop at the first old
	# stamp it meets from the tail, or a younger line further back would vanish.
	var ring := PackedStringArray(["young-a", "stale", "young-b"])
	var stamps := PackedFloat32Array([9.0, 1.0, 9.5])
	var shown := _slice(ring, stamps, 10.0, 6.0, 6)
	assert_eq(shown, PackedStringArray(["young-a", "young-b"]), "the stale middle entry is skipped, both young ones survive")


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
	assert_eq(TickerScript.line_alpha(999.0, 0.0, 1.5), 1.0, "max_age <= 0 never fades (matches visible_indices' no-limit rule)")
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
	assert_eq(_slice(TickerScript._ring, TickerScript._stamps, 1.0, 0.0, 6).size(), 0,
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

## The logical UI canvas every HUD element lays out on (792x444 at 16:9; see menu_style.gd's canvas note).
const CANVAS := Vector2i(792, 444)


func test_default_column_fits_the_canvas_below_the_top_right_hud_stack() -> void:
	var t = TickerScript.new()
	var hud := GameSettings.hud
	# A rendered row is never taller than twice its font size, so this bounds the column's real height from above.
	var col_size := Vector2i(int(t.column_width), int(t.visible_lines) * int(t.font_size) * 2)
	var anchor: Vector2 = TickerScript.corner_anchor(t.corner)
	var offsets: Rect2i = TickerScript.corner_offsets(t.corner, t.margin, col_size)
	var column := Rect2i(Vector2i(int(anchor.x * CANVAS.x), int(anchor.y * CANVAS.y)) + offsets.position, offsets.size)
	assert_true(Rect2i(Vector2i.ZERO, CANVAS).encloses(column), "the default event column lies entirely on the 792x444 canvas: %s" % column)
	# The top-right stack: the minimap box, then the clock line under it (HudSettings' fallback box — the numbers the
	# shipped hud_minimap.tscn is authored from).
	var stack_w := int(maxf(hud.minimap_size.x, hud.clock_size.x))
	var stack_h := int(hud.minimap_size.y + hud.clock_map_gap + hud.clock_size.y)
	var stack := Rect2i(CANVAS.x - int(hud.minimap_inset.x) - stack_w, int(hud.minimap_inset.y), stack_w, stack_h)
	assert_false(column.intersects(stack), "the event column must not paint over the minimap + clock rows of the top-right stack: column %s vs stack %s" % [column, stack])
	# The stack's third row: the objective tracker, right-aligned under the clock (ui.gd builds it clock_tracker_gap
	# below the clock, quest_tracker_width wide, at rep_toast_font_size). Bound it as two wrapped lines, each at most
	# twice its font size tall -- a column that clears the clock but lands on the tracker still hides the objective.
	var tracker_w := int(roundf(hud.quest_tracker_width))
	var tracker := Rect2i(CANVAS.x - int(hud.minimap_inset.x) - tracker_w, stack.end.y + int(hud.clock_tracker_gap),
		tracker_w, 2 * 2 * int(hud.rep_toast_font_size))
	assert_false(column.intersects(tracker), "the event column must not paint over a two-line quest tracker under the clock: column %s vs tracker %s" % [column, tracker])
	assert_eq(int(t.column_width), int(roundf(hud.quest_tracker_width)),
		"the column is as wide as the quest tracker (HudSettings.quest_tracker_width), so both left edges line up")
	# Knob ordering the column relies on.
	assert_lte(int(t.visible_lines), int(t.max_lines), "the column shows a window of the ring, never more rows than the ring keeps")
	assert_gt(float(t.line_seconds), 0.0, "rows hide after a lifetime by default (0 would pin every event on screen forever)")
	assert_true(float(t.fade_seconds) > 0.0 and float(t.fade_seconds) <= float(t.line_seconds),
		"the fade is a soft tail INSIDE a row's lifetime (%.2f of %.2f s), not a pop and not a ramp longer than the row lives" % [float(t.fade_seconds), float(t.line_seconds)])
	assert_eq(int(t.max_lines), TickerScript.DEFAULT_MAX_LINES,
		"a never-authored ticker's ring cap equals the static cap the console dumps with before any ticker was mounted")
	# Ship decision: a release export carries no debug surface unless a QA build deliberately ticks this.
	assert_false(t.force_in_release, "SHIP DECISION: the event ticker stays out of release builds by default")
	t.free()


func test_a_muted_channel_records_nothing_and_leaves_the_others_recording() -> void:
	var t = TickerScript.new()
	t._on_money_changed(125.0, 25.0)
	t._on_xp_changed(40.0, 2)
	var heard := TickerScript.lines()
	assert_eq(heard.size(), 2, "with its channels on, each event lands one line in the ring: %s" % [heard])
	if heard.size() == 2:
		assert_true(heard[0].contains("money:") and heard[0].contains("125.00"), "the money line carries the channel and the new total: %s" % heard[0])
		assert_true(heard[1].contains("xp:") and heard[1].contains("lvl 2"), "the xp line carries the channel and the level: %s" % heard[1])
	TickerScript.clear()
	t.log_money = false
	t.log_xp = false
	t._on_money_changed(150.0, 25.0)
	t._on_xp_changed(50.0, 2)
	assert_eq(TickerScript.lines().size(), 0, "a muted channel's events are NOT recorded — the ring is the log, muting is not a display filter")
	t._on_rent_notice(250.0)
	var rent := TickerScript.lines()
	assert_eq(rent.size(), 1, "muting money and xp leaves every other channel recording")
	if rent.size() == 1:
		assert_true(rent[0].contains("rent:"), "and the line that landed is the rent one: %s" % rent[0])
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
