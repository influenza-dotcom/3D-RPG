extends GutTest

## AiEventLog (2026-08-18, in-game debug suite iter 4): the PURE helpers — line formatting, the ring cap, the
## snapshot diff, lines() filter + count over the shared STATIC ring, the enum-word mapping — plus the panel
## (built by a real in-tree instance with no NPCs around) and the channel mute mask. The live sweep (group polling, duck-typed NPC reads, signal edges) is
## play-verified: it needs real NPCs, and a unit test must never _ready() one (CLAUDE.md, Tests).

## Preloaded by PATH, never by class_name: a not-yet-rescanned editor cache would fail the whole file to parse
## with "Could not find type AiEventLog" (the new-classname-not-registered cascade).
const AiEventLogScript := preload("res://scripts/components/ai_event_log.gd")
const PerceptionScript := preload("res://scripts/npc/perception.gd")


## Duck-typed stand-ins for archetype_of: an NpcData-shaped profile and an NPC-shaped handle carrying it.
class _Profile extends Resource:
	var id: String = ""
	var display_name: String = ""


class _NpcStub extends Node:
	var profile: Resource = null
	var display_name: String = ""


func before_each() -> void:
	# The ring is STATIC and shared across every test in the run — start each one empty.
	AiEventLogScript.clear()


func after_all() -> void:
	# Leave the shared ring empty and at the default cap for whatever test file runs next.
	AiEventLogScript.clear()
	var n = AiEventLogScript.new()
	n.max_lines = AiEventLogScript.DEFAULT_MAX_LINES
	n.free()


# --- format_line / format_event ---------------------------------------------------------------------------------

func test_format_line_layout() -> void:
	var line := AiEventLogScript.format_line(123.4, "raider", "target", "-", "Player")
	assert_eq(line, "T+123.4s  raider  target: - -> Player", "stamp, two-space gutters, channel colon, old -> new")


func test_format_line_stamp_is_one_decimal() -> void:
	var line := AiEventLogScript.format_line(7.0, "a", "b", "x", "y")
	assert_true(line.begins_with("T+7.0s"), "a whole-second stamp still paints one decimal: %s" % line)
	var rounded := AiEventLogScript.format_line(0.04, "a", "b", "x", "y")
	assert_true(rounded.begins_with("T+0.0s"), "sub-decisecond rounds, never truncates to garbage: %s" % rounded)


func test_format_event_layout() -> void:
	var line := AiEventLogScript.format_event(5.0, "raider", "just_spotted")
	assert_eq(line, "T+5.0s  raider  signal: just_spotted", "an edge line carries the signal word under the `signal` channel and no arrow")


# --- push_capped --------------------------------------------------------------------------------------------------

func test_push_capped_keeps_the_last_n() -> void:
	var ring := PackedStringArray()
	for i in 5:
		ring = AiEventLogScript.push_capped(ring, "l%d" % i, 3)
	assert_eq(ring.size(), 3, "the ring keeps only `cap` lines")
	assert_eq(ring[0], "l2", "oldest kept is the 3rd-from-last")
	assert_eq(ring[2], "l4", "newest is the last pushed")


func test_push_capped_under_cap_keeps_all() -> void:
	var ring := PackedStringArray()
	ring = AiEventLogScript.push_capped(ring, "a", 10)
	ring = AiEventLogScript.push_capped(ring, "b", 10)
	assert_eq(ring.size(), 2, "below the cap nothing is dropped")


func test_push_capped_floors_the_cap_at_one() -> void:
	var ring := PackedStringArray(["old"])
	ring = AiEventLogScript.push_capped(ring, "new", 0)
	assert_eq(ring.size(), 1, "a cap of 0 still keeps the newest line (floored at 1), never an empty ring")
	assert_eq(ring[0], "new", "the survivor is the newest line")


# --- diff_snapshot ------------------------------------------------------------------------------------------------

func test_diff_snapshot_no_change_is_empty() -> void:
	var snap := {"perception": "UNAWARE", "target": "-", "goal": "idle"}
	var diffs := AiEventLogScript.diff_snapshot(snap, snap.duplicate())
	assert_eq(diffs.size(), 0, "identical snapshots produce no transitions")


func test_diff_snapshot_reports_one_change_with_old_and_new() -> void:
	var prev := {"perception": "UNAWARE", "target": "-", "goal": "idle"}
	var cur := {"perception": "UNAWARE", "target": "Player", "goal": "idle"}
	var diffs := AiEventLogScript.diff_snapshot(prev, cur)
	assert_eq(diffs.size(), 1, "exactly the one changed key is reported")
	assert_eq(String(diffs[0]["channel"]), "target")
	assert_eq(String(diffs[0]["old"]), "-")
	assert_eq(String(diffs[0]["new"]), "Player")


func test_diff_snapshot_new_key_reports_blank_old() -> void:
	var prev := {"perception": "UNAWARE"}
	var cur := {"perception": "UNAWARE", "goal": "combat"}
	var diffs := AiEventLogScript.diff_snapshot(prev, cur)
	assert_eq(diffs.size(), 1, "a key the previous snapshot lacked is a transition")
	assert_eq(String(diffs[0]["channel"]), "goal")
	assert_eq(String(diffs[0]["old"]), "", "a field that just became readable has no old value")
	assert_eq(String(diffs[0]["new"]), "combat")


func test_diff_snapshot_ignores_keys_only_prev_has() -> void:
	var prev := {"perception": "UNAWARE", "goal": "combat"}
	var cur := {"perception": "UNAWARE"}
	assert_eq(AiEventLogScript.diff_snapshot(prev, cur).size(), 0, "a vanished field is not a transition anyone reads")


func test_diff_snapshot_walks_cur_in_key_order() -> void:
	var prev := {"perception": "UNAWARE", "target": "-", "goal": "idle"}
	var cur := {"perception": "ALERTED", "target": "Player", "goal": "idle"}
	var diffs := AiEventLogScript.diff_snapshot(prev, cur)
	assert_eq(diffs.size(), 2)
	assert_eq(String(diffs[0]["channel"]), "perception", "first key of `cur` first")
	assert_eq(String(diffs[1]["channel"]), "target")


# --- lines() over the seeded static ring --------------------------------------------------------------------------

func test_lines_returns_everything_newest_last() -> void:
	AiEventLogScript.record("a")
	AiEventLogScript.record("b")
	AiEventLogScript.record("c")
	assert_eq(Array(AiEventLogScript.lines()), ["a", "b", "c"], "count 0 = every line, oldest first / newest last")


func test_lines_count_takes_the_last_n() -> void:
	for word in ["a", "b", "c", "d"]:
		AiEventLogScript.record(word)
	assert_eq(Array(AiEventLogScript.lines(2)), ["c", "d"], "count N = the LAST N (newest), not the first")
	assert_eq(AiEventLogScript.lines(99).size(), 4, "a count beyond the size returns everything")
	assert_eq(AiEventLogScript.lines(-1).size(), 4, "a negative count reads as 0 (all)")


func test_lines_filter_is_a_case_insensitive_substring() -> void:
	AiEventLogScript.record("T+1.0s  raider  target: - -> Player")
	AiEventLogScript.record("T+2.0s  raider  goal: idle -> combat")
	AiEventLogScript.record("T+3.0s  guard  TARGET: - -> Player")
	var hits := AiEventLogScript.lines(0, "Target")
	assert_eq(hits.size(), 2, "filter matches regardless of case, anywhere in the line")
	assert_eq(AiEventLogScript.lines(0, "  ").size(), 3, "a blank/whitespace filter is no filter")
	assert_eq(AiEventLogScript.lines(0, "nothing-here").size(), 0, "no match -> empty, never the whole ring")


func test_lines_filter_applies_before_count() -> void:
	AiEventLogScript.record("t1 target")
	AiEventLogScript.record("g1 goal")
	AiEventLogScript.record("t2 target")
	AiEventLogScript.record("g2 goal")
	AiEventLogScript.record("t3 target")
	assert_eq(Array(AiEventLogScript.lines(2, "target")), ["t2 target", "t3 target"],
		"`lines(2, target)` is the last 2 TARGET lines, not the target lines among the last 2")


func test_clear_empties_the_ring() -> void:
	AiEventLogScript.record("x")
	AiEventLogScript.clear()
	assert_eq(AiEventLogScript.lines().size(), 0, "clear() drops the whole shared history")


# --- the static cap via the max_lines export ---------------------------------------------------------------------

func test_record_applies_the_static_cap_from_max_lines() -> void:
	var n = AiEventLogScript.new()
	n.max_lines = 3
	for i in 5:
		AiEventLogScript.record("l%d" % i)
	var kept := AiEventLogScript.lines()
	assert_eq(kept.size(), 3, "record() honours the cap the export applied to the static ring")
	assert_eq(kept[0], "l2", "the oldest lines are the ones evicted")
	n.max_lines = AiEventLogScript.DEFAULT_MAX_LINES
	n.free()


func test_set_max_lines_trims_immediately_and_floors_at_one() -> void:
	var n = AiEventLogScript.new()
	for i in 5:
		AiEventLogScript.record("l%d" % i)
	n.max_lines = 2
	assert_eq(AiEventLogScript.lines().size(), 2, "shrinking the cap trims the ring right away, not on the next record")
	n.max_lines = 0
	assert_eq(int(n.max_lines), 1, "the cap floors at 1 (a 0 cap would make every record() vanish)")
	assert_eq(AiEventLogScript.lines().size(), 1)
	n.max_lines = AiEventLogScript.DEFAULT_MAX_LINES
	n.free()


# --- enum words / channel table ---------------------------------------------------------------------------------

func test_state_name_maps_every_perception_state() -> void:
	assert_eq(AiEventLogScript.state_name(PerceptionScript.State.UNAWARE), "UNAWARE")
	assert_eq(AiEventLogScript.state_name(PerceptionScript.State.DETECTING), "DETECTING")
	assert_eq(AiEventLogScript.state_name(PerceptionScript.State.ALERTED), "ALERTED")
	assert_eq(AiEventLogScript.state_name(PerceptionScript.State.INVESTIGATING), "INVESTIGATING")
	assert_eq(AiEventLogScript.state_name(-1), "?", "no Perception built reads as ?, not as UNAWARE")


func test_channel_bits_cover_every_channel_and_all_channels_is_their_or() -> void:
	var bits: Dictionary = AiEventLogScript.CHANNEL_BITS
	for ch in AiEventLogScript.SNAPSHOT_CHANNELS:
		assert_true(bits.has(ch), "snapshot channel %s has a mute bit" % ch)
	assert_true(bits.has(AiEventLogScript.CH_SPAWN), "spawn/free has a mute bit")
	assert_true(bits.has(AiEventLogScript.CH_SIGNAL), "the signal edges have a mute bit")
	var all := 0
	for v in bits.values():
		all |= int(v)
	assert_eq(int(AiEventLogScript.ALL_CHANNELS), all, "ALL_CHANNELS is exactly the OR of every channel bit (nothing muted by default)")


func test_yes_no() -> void:
	assert_eq(AiEventLogScript.yes_no(true), "yes")
	assert_eq(AiEventLogScript.yes_no(false), "no")


# --- gone_word / archetype_of on plain handles ---------------------------------------------------------------------

func test_gone_word_tells_freed_from_pooled_from_left_group() -> void:
	assert_eq(AiEventLogScript.gone_word(null), "freed", "a null handle reads as freed")
	var off_tree := Node.new()
	assert_eq(AiEventLogScript.gone_word(off_tree), "pooled", "a valid but off-tree body is a pooled one")
	var in_tree := Node.new()
	add_child_autofree(in_tree)
	assert_eq(AiEventLogScript.gone_word(in_tree), "left group", "valid and in-tree but no longer in the group")
	off_tree.free()
	assert_eq(AiEventLogScript.gone_word(off_tree), "freed", "a freed handle reads as freed (untyped param — no type-check rejection first)")


func test_archetype_of_prefers_the_profile_id_then_the_profile_name_then_the_npcs_own_name() -> void:
	var npc := _NpcStub.new()
	var prof := _Profile.new()
	prof.id = "raider_scav"
	prof.display_name = "Scavenger"
	npc.profile = prof
	npc.display_name = "Bob"
	assert_eq(AiEventLogScript.archetype_of(npc), "raider_scav", "the authored NpcData.id wins — it is the rename-proof identity")
	prof.id = ""
	assert_eq(AiEventLogScript.archetype_of(npc), "Scavenger", "no id -> the profile's display_name")
	npc.profile = null
	npc.display_name = "  Bob  "
	assert_eq(AiEventLogScript.archetype_of(npc), "Bob", "no profile -> the NPC's own name, trimmed")
	npc.display_name = "   "
	assert_eq(AiEventLogScript.archetype_of(npc), "-", "a blank own name is no name -> dash")
	npc.free()
	prof = null


func test_archetype_of_degrades_to_dash() -> void:
	assert_eq(AiEventLogScript.archetype_of(null), "-", "no handle -> dash")
	var bare := Node.new()
	assert_eq(AiEventLogScript.archetype_of(bare), "-", "a node with neither profile nor display_name -> dash")
	bare.free()


# --- the panel + the mute mask, driven on a real instance ------------------------------------------------------------
# In-tree is safe: _ready only builds the panel and starts a sweep of Groups.NPC, which is empty in a unit test.

func test_a_panel_authored_on_before_ready_is_built_visible_and_tails_the_ring() -> void:
	for i in 5:
		AiEventLogScript.record("l%d" % i)
	var n = AiEventLogScript.new()
	n.panel_lines = 3
	n.show_panel = true  # a scene-authored export lands through the setter BEFORE _ready builds the panel
	add_child_autofree(n)
	var panel: Control = n.get_node_or_null(^"Panel")
	assert_true(panel != null, "_ready builds the last-N panel")
	assert_true(panel.visible, "a panel ticked on in the scene must come up visible once built (_ready catches up from show_panel)")
	assert_true(n.is_panel_visible(), "…and reports itself visible")
	assert_eq(n._label.text, "l2\nl3\nl4", "the panel shows the last panel_lines lines, oldest on top and the newest at the bottom")


func test_toggling_the_panel_paints_lines_recorded_while_hidden_and_hides_it_again() -> void:
	var n = AiEventLogScript.new()
	add_child_autofree(n)
	var panel: Control = n.get_node_or_null(^"Panel")
	assert_true(panel != null, "_ready builds the panel even while it is hidden")
	assert_false(panel.visible, "the panel ships hidden")
	AiEventLogScript.record("T+1.0s  raider  target: - -> Player")
	n.set_panel_visible(true)
	assert_true(panel.visible, "`ailog on` shows the built panel")
	assert_true(n._label.text.contains("raider  target"), "a line recorded while hidden is painted the moment the panel opens, not a tick later")
	n.set_panel_visible(false)
	assert_false(panel.visible, "`ailog off` hides the panel again")
	assert_false(n.is_panel_visible(), "…and reports itself hidden")


func test_a_fresh_log_records_every_channel_and_a_mute_silences_only_that_channel() -> void:
	var n = AiEventLogScript.new()
	for ch in AiEventLogScript.CHANNEL_BITS:
		assert_true(n._channel_on(ch), "an untouched log records the '%s' channel — nothing ships muted" % ch)
	n.channels = int(n.channels) & ~int(AiEventLogScript.CHANNEL_BITS[AiEventLogScript.CH_TARGET])
	assert_false(n._channel_on(AiEventLogScript.CH_TARGET), "unticking target stops recording target flips")
	assert_true(n._channel_on(AiEventLogScript.CH_GOAL), "…and leaves every other channel recording")
	assert_true(n._channel_on("some_future_channel"), "a channel word with no mute bit is always on, never silently muted")
	n.free()
