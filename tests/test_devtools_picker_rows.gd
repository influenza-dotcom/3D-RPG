extends GutTest

## Phase 0 of the CYBER SUNDAY dock work: `core/picker_rows.gd` is the ONE picker model three docks will share
## instead of each hand-copying `inspectors/npcdata_inspector.gd`'s `_sync_faction` / `_sync_weapon` /
## `_index_of_metadata`. Every behaviour that a hand-copy could quietly drop is pinned here:
##   * the TRANSIENT row — an off-disk id / an unscanned .tres / an inline SubResource must never render as
##     "(none)", because a field that reads "(none)" while it is actually SET invites an accidental clobber on the
##     next unrelated save, and
##   * `resolve_pick`'s decision ORDER, whose whole reason to exist is that re-picking the "(inline / unsaved)"
##     row (an empty `value` at a NON-zero index) must return "keep", never "clear".
## Pure statics over plain Arrays/Dictionaries — no EditorInterface, no scene tree — so a `preload` is safe here
## and `OptionButton.new()` off-tree is enough to exercise `apply`. The buttons go through GUT's `autofree()` so
## they are released in teardown even if an assert path bails early, rather than by a trailing `.free()` that a
## mid-test failure could skip.
##
## Two GUT/engine traps this file deliberately avoids — do not "tidy" them back in:
##   * `assert_string_contains(text, search, match_case)` has NO message parameter (`addons/gut/test.gd:1844`).
##     Passing an invariant string as the 3rd arg silently lands in `match_case` and the message is DISCARDED from
##     the failure output, so substring claims here are made with `assert_true(... .ends_with(...), "why")` instead.
##   * `String(x)` COERCES — `String(StringName)` and `String(null)` both succeed — so an assertion whose message
##     claims a TYPE must check `typeof(...)`, never compare a `String(...)`-wrapped value and call it proof.
##
## NOT covered here on purpose: `npcdata_inspector.gd` is deliberately NOT refactored onto this module (it ships and
## works), so its own tests still pin its copy of the idiom. Folding it over is a later, deliberate pass.

const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")

const FIND_DOG := "res://resources/quests/find_dog.tres"
const PAY_RENT := "res://resources/quests/pay_rent.tres"
## A path OUTSIDE the scanned folder — the "assigned but unscanned" case that must become a DISABLED transient.
const OUTSIDER := "res://mods/extra/secret_quest.tres"


# ── helpers ────────────────────────────────────────────────────────────────────────────────────────────────

## Every row's label, in order — so a test can assert on the whole visible surface in one comparison instead of
## indexing dictionaries inline (and so a regression that shifts ROW ORDER fails loudly, not just row counts).
func _labels(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for row in rows:
		out.append(String(row.get("label", "")))
	return out


## Every row's `value`, in order (the write-back payload behind each label).
func _values(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for row in rows:
		out.append(String(row.get("value", "")))
	return out


func _count_labels_containing(rows: Array, needle: String) -> int:
	var n := 0
	for l in _labels(rows):
		if l.find(needle) != -1:
			n += 1
	return n


func _count_values_equal(rows: Array, value: String) -> int:
	var n := 0
	for v in _values(rows):
		if v == value:
			n += 1
	return n


# ── id_rows: "(none)" + known ids + at most one "(off-disk)" transient ─────────────────────────────────────

func test_id_rows_blank_current_lists_none_plus_every_known() -> void:
	var known := PackedStringArray(["raider", "corpo", "nomad"])
	var rows := PickerRows.id_rows(known, "")
	assert_eq(rows.size(), 1 + known.size(), "a blank current yields exactly '(none)' + one row per known id (no transient)")
	assert_eq(String(rows[0].get("label", "")), PickerRows.NONE_LABEL, "row 0 is the '(none)' clear-the-field row")
	assert_eq(String(rows[0].get("value", "")), "", "the '(none)' row carries an EMPTY value — that's what resolve_pick keys 'clear' on")
	assert_eq(_count_labels_containing(rows, "(off-disk)"), 0, "nothing is off-disk when nothing is assigned")
	assert_eq(_values(rows), PackedStringArray(["", "raider", "corpo", "nomad"]), "the known ids keep their scan order after row 0")
	# A known id's LABEL is the bare id: the "(off-disk)" marker is an ANNOTATION for the mismatch case only, and a
	# scanned row that wore it would libel a perfectly good id (and break a designer scanning the list by name).
	assert_eq(_labels(rows), PackedStringArray([PickerRows.NONE_LABEL, "raider", "corpo", "nomad"]), "a scanned id's label is the bare id, un-annotated — label and value match for every non-transient row")


func test_id_rows_current_in_known_is_not_duplicated() -> void:
	var known := PackedStringArray(["raider", "corpo", "nomad"])
	var rows := PickerRows.id_rows(known, "corpo")
	assert_eq(rows.size(), 1 + known.size(), "a current id that IS in the known set adds NO extra row")
	assert_eq(_count_values_equal(rows, "corpo"), 1, "'corpo' must appear exactly ONCE — a second copy would be a duplicate pick for one id")
	assert_eq(_count_labels_containing(rows, "(off-disk)"), 0, "an id present on disk is never annotated '(off-disk)'")


func test_id_rows_unknown_current_appends_one_off_disk_row() -> void:
	var known := PackedStringArray(["raider", "corpo"])
	var rows := PickerRows.id_rows(known, "ghost_faction")
	assert_eq(rows.size(), 1 + known.size() + 1, "an unknown current appends exactly one trailing transient row")
	assert_eq(_count_labels_containing(rows, "(off-disk)"), 1, "exactly ONE row is marked '(off-disk)'")
	var last: Dictionary = rows[rows.size() - 1]
	# NOT assert_string_contains: its 3rd parameter is `match_case`, so the invariant below would be swallowed.
	# ends_with is also the stronger claim — the marker must TRAIL the id, not merely appear somewhere in it.
	assert_true(String(last.get("label", "")).ends_with(PickerRows.OFF_DISK_SUFFIX), "the TRAILING row is the off-disk one, and the marker trails the id rather than mangling it")
	assert_eq(String(last.get("label", "")), "ghost_faction" + PickerRows.OFF_DISK_SUFFIX, "the label is id + the shared OFF_DISK_SUFFIX")
	assert_eq(String(last.get("value", "")), "ghost_faction", "the off-disk row carries the raw id VERBATIM — the label is annotated, the value must not be")
	# typeof, not String(...): String() coerces a StringName without complaint, so a comparison through it would
	# pass on a drifted type. The module's own docstring warns that JSON.stringify does the same silent coercion,
	# which is exactly how a StringName would round-trip looking correct while the type had quietly changed.
	assert_eq(typeof(last.get("value", null)), TYPE_STRING, "the row `value` is a real String (JSON-safe), never a StringName — the key exists AND holds the right type")
	assert_eq(typeof(last.get("label", null)), TYPE_STRING, "the row `label` is a real String too")


func test_id_rows_empty_known_still_surfaces_the_current_id() -> void:
	# The DirAccess-open-failed case: the scan found nothing, but the field IS set. Rendering "(none)" here is the
	# exact silent-clobber this module exists to prevent.
	var rows := PickerRows.id_rows(PackedStringArray(), "orphan_id")
	assert_eq(rows.size(), 2, "an empty known set with a set current is '(none)' + the off-disk row, nothing else")
	assert_eq(String(rows[0].get("label", "")), PickerRows.NONE_LABEL, "row 0 is still '(none)'")
	assert_eq(String(rows[1].get("value", "")), "orphan_id", "the assigned id survives a failed scan as a real row instead of reading '(none)'")
	# ...and with nothing assigned either, "(none)" alone is the honest answer.
	var bare := PickerRows.id_rows(PackedStringArray(), "")
	assert_eq(bare.size(), 1, "an empty scan with no current is just the '(none)' row — no phantom transient")
	assert_eq(String(bare[0].get("label", "")), PickerRows.NONE_LABEL, "…and that single row is '(none)', not a blank-labelled ghost")


func test_id_rows_is_idempotent() -> void:
	# Every dock rebuilds its rows from scratch on rescan/load rather than patching them, so two identical calls
	# must be indistinguishable — otherwise a rebuild could shuffle indices out from under a queued item_selected.
	var known := PackedStringArray(["raider", "corpo"])
	var first := PickerRows.id_rows(known, "ghost_faction")
	var second := PickerRows.id_rows(known, "ghost_faction")
	# assert_eq on two Arrays compares BY VALUE (comparator.gd:53-60) and prints a deep diff when it fails, which
	# assert_true(first == second) cannot do — same verdict, far better failure output.
	assert_eq(first, second, "two identical id_rows() calls produce EQUAL arrays (Godot 4 compares Array/Dictionary by value)")
	assert_eq(_values(first), _values(second), "every row holds the same value across a rebuild — indices are stable")
	assert_eq(_labels(first), _labels(second), "…and the same label, so a rebuild can't re-order the visible list")


# ── index_of: value -> row index, with row 0 as the harmless fallback ──────────────────────────────────────

func test_index_of_blank_value_is_row_zero() -> void:
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo"]), "")
	assert_eq(PickerRows.index_of(rows, ""), 0, "a blank value points at the '(none)' row, index 0")


func test_index_of_finds_a_known_value() -> void:
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo", "nomad"]), "")
	assert_eq(PickerRows.index_of(rows, "raider"), 1, "the first known id sits at index 1 (right after '(none)')")
	assert_eq(PickerRows.index_of(rows, "nomad"), 3, "the third known id sits at index 3")


func test_index_of_finds_the_off_disk_value() -> void:
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo"]), "ghost_faction")
	assert_eq(PickerRows.index_of(rows, "ghost_faction"), rows.size() - 1, "the off-disk transient is addressable by its raw value, so the picker SHOWS the mismatch")


func test_index_of_unmatched_value_falls_back_to_row_zero() -> void:
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo"]), "")
	assert_eq(PickerRows.index_of(rows, "not_in_any_row"), 0, "a value present in NO row degrades to index 0, never -1 (a -1 would make select() an engine error)")


func test_index_of_never_auto_selects_the_inline_transient() -> void:
	# The one case where TWO rows carry an empty value: "(none)" at index 0 and "(inline / unsaved)" at the end.
	# index_of must resolve "" to row 0 — the module documents that a dock wanting the inline row highlighted has to
	# select rows.size()-1 by index ITSELF, so this is the contract the docks are written against.
	var rows := PickerRows.path_rows(PackedStringArray([FIND_DOG]), PackedStringArray(), "", true)
	assert_eq(String(rows[rows.size() - 1].get("label", "")), PickerRows.INLINE_LABEL, "precondition: the last row IS the inline transient (which also carries an empty value)")
	assert_eq(_count_values_equal(rows, ""), 2, "precondition: exactly TWO rows carry an empty value — this is the ambiguity index_of has to resolve")
	assert_eq(PickerRows.index_of(rows, ""), 0, "a blank value resolves to '(none)' at index 0, NEVER the inline transient that also carries '' — resolving to the tail would make apply() highlight a row the caller never asked for")
	var btn: OptionButton = autofree(OptionButton.new())
	PickerRows.apply(btn, rows, "")
	assert_eq(btn.selected, 0, "…so apply() points the widget at '(none)' — the documented default a dock must override deliberately, not a silent mis-highlight")


# ── resolve_pick: index -> intent. The anti-clobber decision table. ────────────────────────────────────────

func test_resolve_pick_row_zero_clears() -> void:
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo"]), "")
	var intent := PickerRows.resolve_pick(rows, 0)
	assert_eq(String(intent.get("action", "")), "clear", "index 0 is the one and only '(none)' row — the explicit, INTENDED clear")
	assert_false(intent.has("value"), "a 'clear' intent carries no value; a caller reading intent.value must find nothing to assign")


func test_resolve_pick_keeps_an_empty_value_row_and_never_clears_it() -> void:
	# THE reason this module exists. path_rows emits "(inline / unsaved)" with an EMPTY value at a NON-zero index to
	# represent an in-memory SubResource that has no resource_path. Re-picking that row must be a NO-OP: testing
	# "value is empty" BEFORE "index is 0" would collapse both branches and null out the live reference — precisely
	# the trap quest_editor.gd:351-355 documents in prose today.
	var rows := PickerRows.path_rows(PackedStringArray([FIND_DOG]), PackedStringArray(), "", true)
	var inline_idx := rows.size() - 1
	assert_eq(String(rows[inline_idx].get("label", "")), PickerRows.INLINE_LABEL, "the last row is the '(inline / unsaved)' transient")
	assert_eq(String(rows[inline_idx].get("value", "")), "", "…and it carries an EMPTY value, which is what makes it collide with the '(none)' row's payload")
	assert_gt(inline_idx, 0, "that transient sits at a NON-zero index — the whole point is that it is NOT row 0")
	var intent := PickerRows.resolve_pick(rows, inline_idx)
	assert_eq(String(intent.get("action", "")), "keep", "re-picking '(inline / unsaved)' must KEEP the in-memory reference — 'clear' here would silently destroy an unsaved SubResource the designer just authored")
	assert_ne(String(intent.get("action", "")), "clear", "…stated the other way round, because 'clear' is the specific wrong answer an empty-value-first decision order would produce")
	assert_false(intent.has("value"), "a 'keep' intent carries no value; there is nothing to write back")


func test_resolve_pick_sets_a_real_value() -> void:
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo"]), "")
	var intent := PickerRows.resolve_pick(rows, 2)
	assert_eq(String(intent.get("action", "")), "set", "a row with a real value is a representable pick -> 'set'")
	assert_eq(String(intent.get("value", "")), "corpo", "the 'set' intent carries THAT row's value for the caller to assign")
	assert_eq(typeof(intent.get("value", null)), TYPE_STRING, "the intent's value is a real String — it is assigned straight onto a resource field, so a StringName would drift the model's type silently")


func test_resolve_pick_negative_index_keeps() -> void:
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo"]), "")
	var intent := PickerRows.resolve_pick(rows, -1)
	assert_eq(String(intent.get("action", "")), "keep", "index -1 (nothing selected) must never mutate the model — refusing beats guessing")


func test_resolve_pick_index_past_end_keeps() -> void:
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo"]), "")
	assert_eq(String(PickerRows.resolve_pick(rows, rows.size()).get("action", "")), "keep", "an index one past the end is stale (the widget rebuilt under a queued signal) -> keep")
	assert_eq(String(PickerRows.resolve_pick(rows, 99).get("action", "")), "keep", "a wildly out-of-range index is refused too, not clamped into a mutation")
	assert_eq(String(PickerRows.resolve_pick([], 0).get("action", "")), "keep", "index 0 against EMPTY rows is out of range — the range test runs BEFORE the index-0 clear")


func test_resolve_pick_on_a_disabled_row_hands_back_its_own_value() -> void:
	# A disabled row can't be clicked in the widget, so this index only arrives if a caller synthesises it (replaying
	# a stored index, or driving the model from code). Rule 4 then returns THAT row's own value: re-assigning the
	# path the field already holds is a harmless no-op, whereas falling into 'clear' would wipe the one field the
	# disabled row exists to protect, and falling into a neighbour's value would swap in the wrong resource.
	var rows := PickerRows.path_rows(PackedStringArray([FIND_DOG]), PackedStringArray(), OUTSIDER, true)
	var disabled_idx := rows.size() - 1
	assert_true(rows[disabled_idx].get("disabled", false), "precondition: the last row IS the disabled unscanned-path transient")
	var intent := PickerRows.resolve_pick(rows, disabled_idx)
	assert_eq(String(intent.get("action", "")), "set", "a disabled row still resolves through rule 4 rather than falling into 'clear'")
	assert_eq(String(intent.get("value", "")), OUTSIDER, "…and it hands back its OWN path, so a synthesised pick re-assigns what is already there instead of clobbering the field")


# ── path_rows: "(none)" + scanned paths + AT MOST ONE transient ────────────────────────────────────────────

func test_path_rows_lists_none_plus_scanned_paths() -> void:
	var paths := PackedStringArray([FIND_DOG, PAY_RENT])
	var labels := PackedStringArray(["Find The Dog", "Pay The Rent"])
	var rows := PickerRows.path_rows(paths, labels, FIND_DOG, false)
	assert_eq(rows.size(), 1 + paths.size(), "a current that IS among the scanned paths adds no transient row")
	assert_eq(String(rows[0].get("label", "")), PickerRows.NONE_LABEL, "row 0 is '(none)'")
	# BOTH scanned rows are checked: `labels` is consumed in PARALLEL with `paths`, and an implementation that used
	# labels[0] for every row (or reversed the pairing) would sail past a check of row 1 alone.
	assert_eq(_labels(rows), PackedStringArray([PickerRows.NONE_LABEL, "Find The Dog", "Pay The Rent"]), "each scanned row shows its OWN parallel `labels` entry, in scan order — not the raw path, and not labels[0] repeated")
	assert_eq(_values(rows), PackedStringArray(["", FIND_DOG, PAY_RENT]), "…while every VALUE stays the full res:// path for write-back, still paired with its own label")
	assert_false(rows[1].get("disabled", false), "a scanned, representable row is pickable (not disabled)")
	assert_false(rows[2].get("disabled", false), "…and so is the second one — `disabled` belongs to the transient alone")


func test_path_rows_labels_fall_back_to_the_filename_stem() -> void:
	var paths := PackedStringArray([FIND_DOG, PAY_RENT])
	# labels SHORTER than paths (a caller that hasn't authored display names yet) plus one deliberately blank entry.
	var rows := PickerRows.path_rows(paths, PackedStringArray([""]), "", false)
	assert_eq(rows.size(), 1 + paths.size(), "a short `labels` array must not truncate or crash the row list")
	assert_eq(String(rows[1].get("label", "")), "find_dog", "a BLANK label falls back to the path's filename stem")
	assert_eq(String(rows[2].get("label", "")), "pay_rent", "a MISSING label (index past the end of `labels`) falls back to the stem too — never a blank row")
	assert_eq(_values(rows), PackedStringArray(["", FIND_DOG, PAY_RENT]), "the label fallback is cosmetic — every value is still the full path, so a stem-labelled row writes back correctly")


func test_path_rows_unscanned_current_is_a_disabled_transient() -> void:
	var paths := PackedStringArray([FIND_DOG])
	var rows := PickerRows.path_rows(paths, PackedStringArray(), OUTSIDER, true)
	assert_eq(rows.size(), 1 + paths.size() + 1, "an assigned-but-unscanned resource adds exactly one transient row")
	var last: Dictionary = rows[rows.size() - 1]
	assert_eq(String(last.get("value", "")), OUTSIDER, "the transient carries the assigned path verbatim, so the field never reads '(none)' while it is SET")
	assert_eq(String(last.get("label", "")), "secret_quest", "its label is the filename stem")
	assert_true(last.get("disabled", false), "it is DISABLED: the picker cannot legitimately re-pick a path outside its scan — edit that field in the native inspector instead")
	assert_false(last.get("keep", false), "it is NOT flagged `keep` — unlike the inline row it HAS a representable value, and resolve_pick must reach rule 4 for it")


func test_path_rows_inline_ref_gets_the_inline_unsaved_row() -> void:
	var paths := PackedStringArray([FIND_DOG])
	var rows := PickerRows.path_rows(paths, PackedStringArray(), "", true)
	assert_eq(rows.size(), 1 + paths.size() + 1, "has_ref with no resource_path adds exactly one transient row")
	var last: Dictionary = rows[rows.size() - 1]
	assert_eq(String(last.get("label", "")), PickerRows.INLINE_LABEL, "an in-memory SubResource reads '(inline / unsaved)' — 'something IS set here', never '(none)'")
	assert_eq(String(last.get("value", "")), "", "it carries an EMPTY value on purpose: there is no path to write back, which is exactly what resolve_pick keys 'keep' on")
	assert_true(last.get("keep", false), "the row is flagged `keep` so a reader can see the refusal is intentional")
	assert_false(last.get("disabled", false), "the inline row is NOT disabled — it is selectable and resolve_pick makes the pick harmless")


func test_path_rows_never_adds_two_transients() -> void:
	var paths := PackedStringArray([FIND_DOG])
	# Both conditions true at once: a resource IS assigned (has_ref) AND its path is outside the scan.
	var rows := PickerRows.path_rows(paths, PackedStringArray(), OUTSIDER, true)
	assert_eq(rows.size(), 1 + paths.size() + 1, "the unscanned-path branch and the inline branch are EXCLUSIVE — at most ONE transient, never both")
	assert_eq(_count_labels_containing(rows, PickerRows.INLINE_LABEL), 0, "an assigned path wins over the inline label (there IS a path to show)")
	assert_eq(String(rows[rows.size() - 1].get("value", "")), OUTSIDER, "…and the surviving transient is the PATH one, carrying the assigned path (not an empty-valued inline row)")
	assert_true(rows[rows.size() - 1].get("disabled", false), "…disabled, as the unscanned-path branch requires")


func test_path_rows_with_nothing_assigned_has_no_transient() -> void:
	var paths := PackedStringArray([FIND_DOG, PAY_RENT])
	var rows := PickerRows.path_rows(paths, PackedStringArray(), "", false)
	assert_eq(rows.size(), 1 + paths.size(), "nothing assigned -> no transient row at all; '(none)' is the honest answer")
	assert_eq(_count_labels_containing(rows, PickerRows.INLINE_LABEL), 0, "…specifically, no '(inline / unsaved)' row: has_ref is FALSE, so there is nothing in memory to protect")
	assert_eq(PickerRows.index_of(rows, ""), 0, "…and the picker points at '(none)'")


# ── apply: the widget fill + the width guards (headless with a bare OptionButton) ──────────────────────────

func test_apply_fills_labels_metadata_and_selects_the_value() -> void:
	var btn: OptionButton = autofree(OptionButton.new())
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo", "nomad"]), "")
	PickerRows.apply(btn, rows, "corpo")
	assert_eq(btn.item_count, 4, "one widget item per row — '(none)' included")
	assert_eq(btn.get_item_text(0), PickerRows.NONE_LABEL, "item 0 shows the '(none)' label")
	assert_eq(btn.get_item_text(2), "corpo", "each item shows its row's LABEL, in row order")
	assert_eq(String(btn.get_item_metadata(1)), "raider", "each item carries its row's VALUE as metadata")
	# The expected index is the LITERAL 2, not PickerRows.index_of(...): using the module's own lookup to compute the
	# expectation would make this assertion agree with apply() even if BOTH were wrong about where "corpo" lives.
	assert_eq(btn.selected, 2, "the widget is pointed at the requested value's row — 'corpo' is the 3rd row (index 2) of ['(none)', raider, corpo, nomad]")
	assert_eq(String(btn.get_selected_metadata()), "corpo", "the SELECTED item's metadata is the requested value")
	# typeof, not String(...): the docks read this metadata back and assign it to a resource field, and String()
	# would coerce a StringName into a passing comparison — the exact silent type drift the module warns about.
	assert_eq(typeof(btn.get_item_metadata(1)), TYPE_STRING, "the metadata is a real String, not a StringName — JSON.stringify coerces a StringName instead of failing, so the type must be pinned directly")
	assert_eq(typeof(btn.get_selected_metadata()), TYPE_STRING, "…including the selected item's, which is what a write-back handler actually reads")


func test_apply_select_does_not_emit_item_selected() -> void:
	# apply() is the model->widget push every dock runs on rescan/load. If select() emitted item_selected, that push
	# would re-enter the dock's write-back handler, which writes the model and pushes again — an infinite rebuild.
	# The module's docstring rests on "select() does NOT emit"; this is that claim under test rather than in prose.
	var btn: OptionButton = autofree(OptionButton.new())
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo"]), "")
	var emitted: Array = []
	btn.item_selected.connect(func(i: int) -> void: emitted.append(i))
	PickerRows.apply(btn, rows, "corpo")
	assert_eq(emitted.size(), 0, "filling the widget emits item_selected ZERO times — a single emission here is a write-back loop in every dock that uses this module")
	assert_eq(btn.selected, 2, "…while the selection still moved, so the silence is 'no signal', not 'no work'")
	PickerRows.apply(btn, rows, "raider")
	assert_eq(emitted.size(), 0, "a REBUILD is silent too — the rescan path is where a queued signal would do the most damage")


func test_apply_sets_the_width_guards() -> void:
	var btn: OptionButton = autofree(OptionButton.new())
	# A deliberately long "(off-disk)" label: with fit_to_longest_item left TRUE this row's width becomes the
	# control's minimum, and the docks' ScrollContainer (horizontal_scroll_mode = SCROLL_MODE_DISABLED) propagates
	# that minimum outward — widening the whole bottom panel. These three guards are the fix and must not be
	# "simplified away" as redundant defaults.
	var rows := PickerRows.id_rows(PackedStringArray(["a"]), "a_very_long_off_disk_identifier_that_would_widen_the_entire_editor_panel")
	PickerRows.apply(btn, rows, "")
	assert_false(btn.fit_to_longest_item, "fit_to_longest_item defaults TRUE on OptionButton and MUST be forced false — the longest row must not set the panel's minimum width")
	assert_true(btn.clip_text, "clip_text drops the button's own text from its minimum width, so a long selected label is chopped instead of widening the box")
	assert_eq(btn.custom_minimum_size.x, PickerRows.PICKER_MIN_WIDTH, "a width FLOOR keeps the now-unanchored box from collapsing when every row is short")
	assert_eq(btn.custom_minimum_size.y, 0.0, "only the WIDTH is guarded — height stays theme-driven")


func test_apply_disables_a_flagged_row() -> void:
	var btn: OptionButton = autofree(OptionButton.new())
	var rows := PickerRows.path_rows(PackedStringArray([FIND_DOG]), PackedStringArray(), OUTSIDER, true)
	PickerRows.apply(btn, rows, OUTSIDER)
	assert_eq(btn.item_count, 3, "'(none)' + the scanned path + the transient")
	var last := rows.size() - 1
	assert_true(btn.is_item_disabled(last), "the `disabled` row flag reaches the widget, so the unscanned path is VISIBLE but not pickable")
	assert_false(btn.is_item_disabled(0), "'(none)' stays pickable — clearing the field must always be available")
	assert_false(btn.is_item_disabled(1), "a scanned row stays pickable")
	# select() works on a disabled item by design, and that is what keeps the assigned-but-unscanned path VISIBLE in
	# the closed button instead of the widget falling back to showing "(none)" over a field that is actually set.
	assert_eq(btn.selected, last, "the disabled transient is still SELECTED, so the closed picker displays the assigned path rather than '(none)'")


func test_apply_rebuilds_without_stacking_items() -> void:
	# apply() clears first, so it doubles as the model->widget push after every rescan/load.
	var btn: OptionButton = autofree(OptionButton.new())
	var rows := PickerRows.id_rows(PackedStringArray(["raider", "corpo"]), "")
	PickerRows.apply(btn, rows, "raider")
	PickerRows.apply(btn, rows, "corpo")
	assert_eq(btn.item_count, 3, "a second apply() REPLACES the items rather than appending a second copy")
	assert_eq(btn.get_item_text(1), "raider", "…and the surviving items are the FIRST copy's labels in order, not a shifted second batch")
	assert_eq(btn.selected, 2, "…and re-points the selection at the new value")
	assert_eq(String(btn.get_selected_metadata()), "corpo", "…whose metadata is the newly requested value")


func test_apply_on_empty_rows_selects_nothing() -> void:
	# Degenerate but reachable (a caller handing over an empty model): select(0) against an empty popup is an engine
	# error, and GUT fails the suite on engine errors — so the guard is load-bearing, not defensive noise. Note this
	# test's real teeth are the absence of that engine error; the assertions below just describe the resting state.
	var btn: OptionButton = autofree(OptionButton.new())
	PickerRows.apply(btn, [], "anything")
	assert_eq(btn.item_count, 0, "an empty row list fills no items")
	assert_eq(btn.selected, -1, "nothing is selected (select(-1) deselects; select(0) on an empty popup would be an engine error)")
	# The width guards are set BEFORE the empty-rows early return, so a picker that starts empty still holds its
	# floor and cannot deform the panel the moment its first rescan lands.
	assert_false(btn.fit_to_longest_item, "the width guards are applied even on the empty path — an empty picker must not revert to fit-to-content")
	assert_eq(btn.custom_minimum_size.x, PickerRows.PICKER_MIN_WIDTH, "…including the width floor, so an empty picker still occupies its row properly")


func test_apply_tolerates_a_null_button() -> void:
	# The docks build their widgets lazily, so a refresh can land before the OptionButton exists. apply() guards on
	# null rather than letting the dock crash mid-rebuild; an engine error here would fail the run under GUT anyway.
	PickerRows.apply(null, PickerRows.id_rows(PackedStringArray(["raider"]), ""), "raider")
	pass_test("apply(null, ...) returns quietly instead of erroring — a lazily-built dock can refresh before its widget exists")
