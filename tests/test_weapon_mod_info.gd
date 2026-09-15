extends GutTest

## WeaponModInfo (scripts/ui/weapon_mod_info.gd) — the WEAPON-PART text formatter behind two player-facing
## surfaces: part_line() (the one labeled line ItemInfo appends to every part tooltip — inventory, shop, loot AND
## bench) and compare_block() / change_rows() (the bench footer's BEFORE → AFTER preview, built over
## WeaponModKit.diff). Pure statics over hand-built WeaponData / WeaponMod / WeaponStatDelta resources, so
## everything here is off-tree (`.new()`, released with `= null`) — the test_weapon_mods.gd mold.
##
## ⭐What this file really guards is the DISPLAY POLICY the header comments promise and nothing else enforces:
##   • a no-op line (MULT 1.0 / ADD 0 / a delta below display resolution) is DROPPED, never printed as "+0";
##   • a MULT line ALWAYS reads as a percent, while a fitted change reads as a percent ONLY for PERCENT_STATS;
##   • a BOOL target reads as a state word ("Muzzle Flash off"), never arithmetic;
##   • compare_block is ALWAYS exactly `max_lines` lines (blank-padded, overflow folded into the last row) —
##     the fixed-height footer that keeps the bench lists from re-flowing under the cursor;
##   • the value columns deepen to 3/4 decimals rather than print a self-contradicting "0.01 → 0.01  (-25%)".
## Every number is expected through TextFormat (num / signed / signed_pct), so a change to that seam shows up
## here as a wording diff, not a silent drift.

const WeaponFields = preload("res://scripts/items/weapon_fields.gd")
const WeaponModKit = preload("res://scripts/items/weapon_mod_kit.gd")


# --- Fixtures ------------------------------------------------------------------------------------------------

## Round numbers so an assertion reads as arithmetic (the test_weapon_mods.gd _template).
func _block() -> WeaponData:
	var w := WeaponData.new()
	w.damage = 1.0
	w.effective_range = 20.0
	w.pellet_spread = 0.012
	w.pellet_count = 1
	w.max_ammo = 10
	w.attack_speed = 0.1
	w.reload_time = 1.5
	w.has_muzzle_flash = true
	return w

func _delta(prop: StringName, op: WeaponStatDelta.Op, amount: float = 0.0, flag: bool = false) -> WeaponStatDelta:
	var d := WeaponStatDelta.new()
	d.property = prop
	d.op = op
	d.amount = amount
	d.flag = flag
	return d

## A weapon PART item: MISC category carrying a WeaponMod (is_weapon_mod gates on the mod, never the category).
func _part(slot: WeaponData.ModSlot, deltas: Array, min_gunplay: int = 0) -> Item:
	var mod := WeaponMod.new()
	mod.slot = slot
	var typed: Array[WeaponStatDelta] = []
	typed.assign(deltas)
	mod.deltas = typed
	mod.min_gunplay = min_gunplay
	var part := Item.new()
	part.id = &"test_mod_info_part"
	part.display_name = "Test Part"
	part.category = Item.Category.MISC
	part.weapon_mod = mod
	return part

func _slot_word(slot: WeaponData.ModSlot) -> String:
	return PlayerText.mod_slot_name(slot) + " part"


# --- The vocabulary ------------------------------------------------------------------------------------------

func test_stat_label_uses_the_table_and_degrades_to_the_capitalized_id() -> void:
	assert_eq(WeaponModInfo.stat_label(&"damage"), "Damage", "a listed property renders its short table label")
	assert_eq(WeaponModInfo.stat_label(&"max_ammo"), "Clip", "max_ammo reads as Clip — the word ItemInfo's gun block uses")
	assert_eq(WeaponModInfo.stat_label(&"bullet_gravity_scale"), "Bullet Gravity Scale",
		"an unlisted property degrades to its capitalized id, never a blank row")
	assert_eq(WeaponModInfo.stat_label(&""), "", "an empty property name has nothing to capitalize")

func test_stat_labels_share_item_infos_gun_vocabulary() -> void:
	# The five words a player already reads on a gun's tooltip — one vocabulary across the tooltip and the preview.
	var expected := {&"damage": "Damage", &"attack_speed": "Rate", &"effective_range": "Range",
		&"headshot_multiplier": "Headshot", &"max_ammo": "Clip"}
	for prop in expected:
		assert_eq(WeaponModInfo.stat_label(prop), expected[prop],
			"'%s' must keep the ItemInfo._weapon_block word '%s'" % [prop, expected[prop]])

func test_every_stat_label_names_a_real_weapon_data_scalar() -> void:
	# A label keyed to a field WeaponData no longer declares is dead vocabulary a designer can never reach — and
	# the fold could never write. Pin the table against the live property list.
	for prop in WeaponModInfo.STAT_LABELS:
		assert_ne(WeaponModInfo._declared_type(prop), TYPE_NIL,
			"STAT_LABELS names '%s' but WeaponData declares no such property" % prop)
		assert_false(String(WeaponModInfo.STAT_LABELS[prop]).is_empty(), "'%s' must carry a non-empty label" % prop)

func test_the_three_scope_fields_all_read_zoom() -> void:
	for prop in [&"scoped_fov_override", &"scoped_zoom_fov_max", &"scoped_zoom_fov_min"]:
		assert_eq(WeaponModInfo.stat_label(prop), "Zoom", "'%s' is one concept to the player: Zoom" % prop)

func test_percent_stats_are_a_subset_of_the_mod_targetable_fields() -> void:
	var ids := WeaponFields.ids()
	for prop in WeaponModInfo.PERCENT_STATS:
		assert_true(ids.has(String(prop)),
			"PERCENT_STATS lists '%s' but no part can target it (WeaponFields.ids())" % prop)
		assert_true(WeaponModInfo.is_percent_stat(prop), "is_percent_stat must answer true for every listed stat")
	assert_false(WeaponModInfo.is_percent_stat(&"effective_range"), "range reports its absolute metres, not a percent")
	assert_false(WeaponModInfo.is_percent_stat(&"max_ammo"), "clip size reports its absolute delta")
	assert_true(WeaponModInfo.is_percent_stat(&"damage"), "damage sits on a 0.9-vs-1.17 scale — it reads as a percent")

func test_declared_type_reads_the_property_type_off_weapon_data() -> void:
	assert_eq(WeaponModInfo._declared_type(&"has_muzzle_flash"), TYPE_BOOL, "has_muzzle_flash is a bool field")
	assert_eq(WeaponModInfo._declared_type(&"max_ammo"), TYPE_INT, "max_ammo is an int field")
	assert_eq(WeaponModInfo._declared_type(&"damage"), TYPE_FLOAT, "damage is a float field")
	assert_eq(WeaponModInfo._declared_type(&"no_such_field_xyz"), TYPE_NIL, "an unknown property reads TYPE_NIL")


# --- part_line -----------------------------------------------------------------------------------------------

func test_part_line_is_blank_for_null_and_for_a_non_part() -> void:
	assert_eq(WeaponModInfo.part_line(null), "", "null is not a part — ItemInfo appends the result unconditionally")
	var plain := Item.new()
	plain.id = &"test_plain"
	plain.category = Item.Category.MISC
	assert_eq(WeaponModInfo.part_line(plain), "", "a MISC item with no weapon_mod is not a part")
	plain = null

func test_part_line_leads_with_the_slot_and_joins_labeled_effects() -> void:
	# The header's own example: "Barrel part  ·  Range +8  ·  Spread -25%  ·  Move -4%  ·  Hip Sway +10%".
	var part := _part(WeaponData.ModSlot.BARREL, [
		_delta(&"effective_range", WeaponStatDelta.Op.ADD, 8.0),
		_delta(&"pellet_spread", WeaponStatDelta.Op.MULT, 0.75),
		_delta(&"move_speed_multiplier", WeaponStatDelta.Op.MULT, 0.96),
		_delta(&"hip_sway_mult", WeaponStatDelta.Op.MULT, 1.10),
	])
	var line := WeaponModInfo.part_line(part)
	assert_eq(line, _slot_word(WeaponData.ModSlot.BARREL) + "  ·  Range +8  ·  Spread -25%  ·  Move -4%  ·  Hip Sway +10%",
		"slot first, then one labeled fragment per delta in authored order, joined with the ItemInfo glyph. Got: %s" % line)
	part = null

func test_part_line_uses_the_join_glyph_of_item_info() -> void:
	assert_eq(WeaponModInfo.JOIN, "  ·  ", "the separator is U+00B7 with two spaces each side — ItemInfo's exact glyph")

func test_part_line_mult_always_reads_as_a_percent_even_off_the_percent_list() -> void:
	# effective_range is NOT a percent stat, but a MULT is a ratio by construction — "Range -25%" is the truth
	# about the LINE even though a fitted range change reports as "+8".
	var part := _part(WeaponData.ModSlot.BARREL, [_delta(&"effective_range", WeaponStatDelta.Op.MULT, 0.75)])
	var line := WeaponModInfo.part_line(part)
	assert_true(line.ends_with("Range -25%"), "a MULT line is a percent regardless of PERCENT_STATS. Got: %s" % line)
	part = null

func test_part_line_add_on_a_percent_stat_reads_as_a_signed_absolute() -> void:
	# The part line's ADD branch is the absolute delta (2 decimals, trimmed) — PERCENT_STATS only governs the
	# bench's before/after CHANGE rows, not a part's own authored line.
	var part := _part(WeaponData.ModSlot.RECEIVER, [_delta(&"damage", WeaponStatDelta.Op.ADD, 0.25)])
	var line := WeaponModInfo.part_line(part)
	assert_true(line.ends_with("Damage +0.25"), "an ADD line prints its signed amount. Got: %s" % line)
	part = null

func test_part_line_bool_target_reads_as_a_state_word_and_ignores_op() -> void:
	# The fold ignores `op` for a BOOL and writes `flag` — the line must say the resulting STATE.
	var off := _part(WeaponData.ModSlot.MUZZLE, [_delta(&"has_muzzle_flash", WeaponStatDelta.Op.MULT, 0.0, false)])
	var off_line := WeaponModInfo.part_line(off)
	assert_true(off_line.ends_with("Muzzle Flash " + WeaponModInfo.FLAG_OFF),
		"flag=false reads 'Muzzle Flash off' whatever op says. Got: %s" % off_line)
	var on := _part(WeaponData.ModSlot.RECEIVER, [_delta(&"auto_fire", WeaponStatDelta.Op.SET, 0.0, true)])
	var on_line := WeaponModInfo.part_line(on)
	assert_true(on_line.ends_with("Automatic " + WeaponModInfo.FLAG_ON), "flag=true reads 'Automatic on'. Got: %s" % on_line)
	off = null
	on = null

func test_part_line_set_shows_the_destination_in_the_fields_declared_voice() -> void:
	# A SET has no delta to sign: an INT field prints bare ("Clip 20"), a FLOAT trims ("Zoom 25", "Rate 0.08").
	var part := _part(WeaponData.ModSlot.MAGAZINE, [
		_delta(&"max_ammo", WeaponStatDelta.Op.SET, 20.4),
		_delta(&"scoped_fov_override", WeaponStatDelta.Op.SET, 25.0),
		_delta(&"attack_speed", WeaponStatDelta.Op.SET, 0.08),
	])
	var line := WeaponModInfo.part_line(part)
	assert_true(line.contains("Clip 20"), "an INT SET rounds and prints bare (20.4 -> 20). Got: %s" % line)
	assert_false(line.contains("20.4"), "an INT field never shows a fraction. Got: %s" % line)
	assert_true(line.contains("Zoom 25"), "a whole-number FLOAT SET trims its decimals. Got: %s" % line)
	assert_true(line.contains("Rate 0.08"), "a FLOAT SET keeps up to two decimals. Got: %s" % line)
	part = null

func test_part_line_drops_lines_that_move_nothing_measurable() -> void:
	# MULT 1.0, ADD 0, an ADD rounding below 0.01 and a MULT within half a percent are ABSENT claims, never "+0".
	var part := _part(WeaponData.ModSlot.STOCK, [
		_delta(&"effective_range", WeaponStatDelta.Op.MULT, 1.0),
		_delta(&"reload_time", WeaponStatDelta.Op.ADD, 0.0),
		_delta(&"reload_time", WeaponStatDelta.Op.ADD, 0.004),
		_delta(&"hip_sway_mult", WeaponStatDelta.Op.MULT, 1.003),
	])
	assert_eq(WeaponModInfo.part_line(part), _slot_word(WeaponData.ModSlot.STOCK),
		"a part whose every line rounds away shows its slot alone — it really does nothing measurable")
	part = null

func test_part_line_skips_null_and_unnamed_deltas() -> void:
	var part := _part(WeaponData.ModSlot.SIGHT, [null, _delta(&"", WeaponStatDelta.Op.ADD, 5.0),
		_delta(&"effective_range", WeaponStatDelta.Op.ADD, 8.0)])
	assert_eq(WeaponModInfo.part_line(part), _slot_word(WeaponData.ModSlot.SIGHT) + "  ·  Range +8",
		"a null entry and a blank property are skipped without a stray separator")
	part = null

func test_part_line_appends_the_gunplay_gate_last() -> void:
	var part := _part(WeaponData.ModSlot.RECEIVER, [_delta(&"effective_range", WeaponStatDelta.Op.ADD, 8.0)], 3)
	var line := WeaponModInfo.part_line(part)
	var gate := "needs %s 3" % StatInfo.title(&"gunplay")
	assert_true(line.ends_with("  ·  " + gate),
		"the requirement is the LAST fragment (a condition, not an effect) and names the stat via StatInfo.title. Got: %s" % line)
	var ungated := _part(WeaponData.ModSlot.RECEIVER, [], 0)
	assert_false(WeaponModInfo.part_line(ungated).contains("needs"), "min_gunplay 0 adds no gate fragment")
	part = null
	ungated = null


# --- change_rows ---------------------------------------------------------------------------------------------

func test_change_rows_is_empty_for_null_or_identical_blocks() -> void:
	var a := _block()
	assert_eq(WeaponModInfo.change_rows(null, a).size(), 0, "a null BEFORE yields no rows")
	assert_eq(WeaponModInfo.change_rows(a, null).size(), 0, "a null AFTER yields no rows")
	assert_eq(WeaponModInfo.change_rows(a, a).size(), 0, "a block compared to itself changed nothing")
	a = null

func test_change_rows_absolute_percent_int_and_bool_voices() -> void:
	var before := _block()
	var after := _block()
	after.effective_range = 28.0      # absolute: metres
	after.damage = 1.17               # percent stat
	after.max_ammo = 12               # int: bare columns
	after.has_muzzle_flash = false    # bool: state words, no parenthetical
	var rows := WeaponModInfo.change_rows(before, after)
	assert_true(rows.has("Range  20 → 28  (+8)"), "an absolute stat reads Label  before → after  (delta). Rows: %s" % [rows])
	assert_true(rows.has("Damage  1 → 1.17  (+17%)"), "a PERCENT_STATS field reports its change as a signed percent. Rows: %s" % [rows])
	assert_true(rows.has("Clip  10 → 12  (+2)"), "an int field prints bare columns, never 10.00. Rows: %s" % [rows])
	assert_true(rows.has("Muzzle Flash  on → off"), "a bool row is on → off with NO delta parenthetical. Rows: %s" % [rows])
	assert_eq(rows.size(), 4, "exactly one row per changed property")
	before = null
	after = null

func test_change_rows_follow_the_diffs_sorted_property_order() -> void:
	# Deterministic order is the property that matters: WeaponFields.ids() is sorted, so rows come alphabetically
	# by property id — "damage" before "effective_range" before "max_ammo" — however the block was edited.
	var before := _block()
	var after := _block()
	after.max_ammo = 12
	after.effective_range = 28.0
	after.damage = 1.17
	var rows := WeaponModInfo.change_rows(before, after)
	assert_eq(rows.size(), 3, "three changed properties, three rows")
	if rows.size() == 3:
		assert_true(rows[0].begins_with("Damage"), "damage sorts first. Rows: %s" % [rows])
		assert_true(rows[1].begins_with("Range"), "effective_range sorts second. Rows: %s" % [rows])
		assert_true(rows[2].begins_with("Clip"), "max_ammo sorts last. Rows: %s" % [rows])
	before = null
	after = null

func test_change_rows_negative_deltas_carry_a_single_minus() -> void:
	var before := _block()
	var after := _block()
	after.effective_range = 15.5
	after.damage = 0.9
	var rows := WeaponModInfo.change_rows(before, after)
	assert_true(rows.has("Range  20 → 15.5  (-4.5)"), "a negative absolute delta is a clean minus. Rows: %s" % [rows])
	assert_true(rows.has("Damage  1 → 0.9  (-10%)"), "a negative percent is a clean minus. Rows: %s" % [rows])
	for r in rows:
		assert_false(r.contains("+-"), "never a +- double sign: %s" % r)
	before = null
	after = null

func test_change_rows_drop_a_change_below_display_resolution() -> void:
	# ⭐The gates are on the ROUNDED value, never is_equal_approx: a 1.003 ratio would sail past an approx test
	# and render a meaningless "+0%"; a 0.004 m shift would print "+0".
	var before := _block()
	var after := _block()
	after.damage = 1.003
	after.effective_range = 20.004
	assert_eq(WeaponModInfo.change_rows(before, after).size(), 0,
		"a percent change rounding to 0% and an absolute change rounding to 0.00 are both dropped")
	before = null
	after = null

func test_change_rows_percent_stat_from_zero_falls_back_to_absolute() -> void:
	# A ratio against zero is undefined — the row degrades to the absolute voice rather than dividing by zero.
	var before := _block()
	var after := _block()
	before.damage = 0.0
	after.damage = 1.0
	var rows := WeaponModInfo.change_rows(before, after)
	assert_eq(rows, ["Damage  0 → 1  (+1)"], "damage from 0 reports an absolute +1, not a percent")
	before = null
	after = null

func test_change_rows_deepen_decimals_until_the_columns_differ() -> void:
	# pellet_spread lives around 0.01: at two decimals 0.012 and 0.009 both print "0.01", which would contradict
	# the "-25%" beside them. The pair deepens to three decimals.
	var before := _block()
	var after := _block()
	after.pellet_spread = 0.009
	var rows := WeaponModInfo.change_rows(before, after)
	assert_eq(rows, ["Spread  0.012 → 0.009  (-25%)"],
		"the value columns print at the shallowest depth that tells them apart")
	before = null
	after = null

func test_change_rows_never_mention_a_slot_bookkeeping_id() -> void:
	# The six fitted-part ids are StringNames outside WeaponFields.ids(); fitting a part changes them but the
	# preview must only ever report stats.
	var before := _block()
	var after := _block()
	after.set_mod_id(WeaponData.ModSlot.BARREL, &"mod_test_barrel")
	assert_eq(WeaponModInfo.change_rows(before, after).size(), 0,
		"a slot id change alone is not a stat change — no row")
	before = null
	after = null


# --- compare_block -------------------------------------------------------------------------------------------

func test_compare_block_with_no_body_room_is_the_header_alone() -> void:
	var a := _block()
	var b := _block()
	b.effective_range = 28.0
	assert_eq(WeaponModInfo.compare_block(a, b, "Fit Long Barrel", 1), "Fit Long Barrel",
		"max_lines 1 leaves no body room: the header alone, no newline")
	assert_eq(WeaponModInfo.compare_block(a, b, "Fit Long Barrel", 0), "Fit Long Barrel",
		"max_lines 0 is clamped to the header alone")
	a = null
	b = null

func test_compare_block_is_always_exactly_max_lines_lines() -> void:
	# ⭐THE FIXED-HEIGHT FOOTER. Two changes in a 5-line block = header + 2 rows + 2 blank lines; no changes at
	# all = header + 4 blanks. The line count never tracks the number of changes.
	var a := _block()
	var b := _block()
	b.effective_range = 28.0
	b.max_ammo = 12
	var two := WeaponModInfo.compare_block(a, b, "Preview", 5)
	var lines := two.split("\n")
	assert_eq(lines.size(), 5, "two changes pad out to exactly max_lines. Got:\n%s" % two)
	if lines.size() == 5:
		assert_eq(lines[0], "Preview", "line one is the header")
		assert_eq(lines[1], "Range  20 → 28  (+8)", "then the diff's rows in order")
		assert_eq(lines[2], "Clip  10 → 12  (+2)", "second row")
		assert_eq(lines[3], "", "blank padding after the rows")
		assert_eq(lines[4], "", "blank padding to the full height")
	var none := WeaponModInfo.compare_block(a, a, "Pistol", 5)
	assert_eq(none.split("\n").size(), 5, "no changes still pads to max_lines (the bench's caption-only footer)")
	assert_eq(none, "Pistol\n\n\n\n", "header plus four blank lines")
	a = null
	b = null

func test_compare_block_folds_overflow_into_the_last_body_line() -> void:
	# Five changes in a 3-line block: the header, the first row, then rows 2..5 joined with "  ·  " — every change
	# is still reported, none silently truncated.
	var a := _block()
	var b := _block()
	b.damage = 1.17
	b.effective_range = 28.0
	b.has_muzzle_flash = false
	b.max_ammo = 12
	b.reload_time = 1.2
	var rows := WeaponModInfo.change_rows(a, b)
	assert_eq(rows.size(), 5, "fixture sanity: five changed properties")
	var block := WeaponModInfo.compare_block(a, b, "Fit", 3)
	var lines := block.split("\n")
	assert_eq(lines.size(), 3, "overflow never grows the block past max_lines. Got:\n%s" % block)
	if lines.size() == 3 and rows.size() == 5:
		assert_eq(lines[1], rows[0], "the first body line is the first row, unfolded")
		assert_eq(lines[2], WeaponModInfo.JOIN.join(rows.slice(1)), "the last body line carries every remaining row, joined")
		for r in rows:
			assert_true(block.contains(r), "no row is lost to the fold: %s" % r)
	a = null
	b = null

func test_compare_block_null_block_degrades_to_a_padded_header() -> void:
	var a := _block()
	assert_eq(WeaponModInfo.compare_block(null, a, "Header", 3), "Header\n\n",
		"a null side means no rows — the header still pads to height so the footer never jumps")
	a = null

func test_compare_block_agrees_with_the_folds_own_diff() -> void:
	# The preview can only ever report what WeaponModKit.diff measured: one row per diff key, no more, no less.
	var a := _block()
	var b := _block()
	b.effective_range = 28.0
	b.pellet_count = 3
	var diff := WeaponModKit.diff(a, b)
	var rows := WeaponModInfo.change_rows(a, b)
	assert_eq(rows.size(), diff.size(), "every measurable diff entry becomes exactly one row")
	for prop in diff:
		var label := WeaponModInfo.stat_label(StringName(prop))
		var found := false
		for r in rows:
			if r.begins_with(label + "  "):
				found = true
		assert_true(found, "diff key %s is painted under its label %s. Rows: %s" % [prop, label, rows])
	a = null
	b = null
