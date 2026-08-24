@tool
extends RefCounted

## ONE resource/id picker model for the CYBER SUNDAY docks. Every dock that offers "pick an authored .tres (or a
## known id) from a dropdown" needs the same four behaviours, and each one was about to be hand-copied from
## `inspectors/npcdata_inspector.gd` (`_sync_faction` / `_sync_weapon` / `_index_of_metadata`):
##   1. a "(none)" row at index 0 that means "clear the field",
##   2. a TRANSIENT row for a value the scan can't represent — an off-disk id, a .tres outside the scanned folder,
##      an inline SubResource — because a set field that silently renders "(none)" invites an accidental clobber,
##   3. an index -> intent decision that REFUSES to mutate the model when the pick can't be represented, and
##   4. the widget fill (labels + metadata + disabled flags + width guards).
## Copying that three more times means three chances to drop the anti-clobber rule, so it lives here ONCE, as pure
## statics over plain Arrays/Dictionaries — no EditorInterface, no scene tree — which makes it headless-testable
## (`OptionButton.new()` is enough to exercise `apply`).
##
## NO class_name on purpose — const-preloaded by path from each dock, mirroring `content_save_guard.gd` /
## `inspectors/inspector_calc.gd`, so there's nothing for the global script class cache to miss.
##
## NOT IN SCOPE: `npcdata_inspector.gd` is deliberately NOT refactored onto this module. It ships and works; this
## is the extraction of its idiom for NEW callers. Folding the inspector onto these statics is a later, deliberate
## pass (it would want its own re-verification in a live editor) — not a drive-by of this one.
##
## Every string here is a DEVELOPER surface (editor tooling), so labels are literals and must never be routed
## through `PlayerText`. Rows stay JSON-safe (String / bool) — note `JSON.stringify` silently COERCES a StringName
## into a quoted string instead of failing, so a StringName id must be `String(...)`-ed by the CALLER before it
## reaches `id_rows`, or a round-trip would look fine while the type quietly drifted.

## Row 0's label. Selecting it always means "clear the field" (see `resolve_pick`).
const NONE_LABEL := "(none)"

## Appended to an id that isn't in the known set: "raider  (off-disk)". Two spaces, verbatim from
## `npcdata_inspector.gd:223`, so the marker reads as a separate annotation rather than part of the id.
const OFF_DISK_SUFFIX := "  (off-disk)"

## The label for an in-memory resource with no `resource_path` (an inline SubResource authored in the inspector).
## There is no path to round-trip, so the row exists purely to say "something IS set here" — never "(none)".
const INLINE_LABEL := "(inline / unsaved)"

## Minimum width for a picker filled by `apply`, in pixels. See the width-guard note on `apply` for WHY this is a
## floor rather than the widget's default fit-to-content behaviour.
const PICKER_MIN_WIDTH := 140.0


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# Row builders — pure model, no widget
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## Rows for an ID picker (faction ids, quest ids, item ids...): "(none)" + every id in `known`, then — ONLY when
## `current` is set and matches nothing in `known` — a trailing "(off-disk)" row carrying it.
## Behaviour lifted verbatim from `npcdata_inspector.gd._sync_faction`: a stored id whose file was renamed or
## deleted would otherwise render as "(none)" while the field is non-empty, so the next unrelated edit + save
## silently wipes it. Surfacing it as a real (selectable) row makes the mismatch visible instead.
## An id that IS in `known` is never appended twice.
static func id_rows(known: PackedStringArray, current: String) -> Array:
	var rows: Array = [{"label": NONE_LABEL, "value": ""}]
	for id in known:
		var sid: String = id
		rows.append({"label": sid, "value": sid})
	if current != "" and not known.has(current):
		rows.append({"label": current + OFF_DISK_SUFFIX, "value": current})
	return rows


## Rows for a RESOURCE-PATH picker: "(none)" + one row per scanned path, plus AT MOST ONE transient row for the
## currently assigned resource when the scan can't represent it.
## `labels` is parallel to `paths` (the display label for each); a short/blank `labels` entry falls back to the
## path's filename stem, so a caller that hasn't got nice labels yet still gets readable rows instead of blanks.
## `current` is the assigned resource's `resource_path` ("" when it has none), `has_ref` is "a resource IS
## assigned" — the two together separate the three states the picker must not conflate:
##   * `current` set but unscanned (a .tres in another folder) -> a DISABLED row, mirroring
##     `npcdata_inspector.gd:232-248`. Shown so it can never read "(none)"; disabled because the picker cannot
##     legitimately re-pick it — edit that field via the native inspector property row instead.
##   * `has_ref` with no path (an inline SubResource) -> the "(inline / unsaved)" row, mirroring
##     `quest_editor.gd:378-399`. It carries an EMPTY value on purpose: there is no path to write back, which is
##     exactly what `resolve_pick` keys on to refuse the write.
##   * nothing assigned -> no transient row at all; "(none)" is the honest answer.
static func path_rows(paths: PackedStringArray, labels: PackedStringArray, current: String, has_ref: bool) -> Array:
	var rows: Array = [{"label": NONE_LABEL, "value": ""}]
	for i in paths.size():
		var p: String = paths[i]
		var lbl: String = labels[i] if i < labels.size() else ""
		if lbl == "":
			lbl = _stem(p)
		rows.append({"label": lbl, "value": p})
	if current != "" and not paths.has(current):
		rows.append({"label": _stem(current), "value": current, "disabled": true})
	elif has_ref and current == "":
		rows.append({"label": INLINE_LABEL, "value": "", "keep": true})
	return rows


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# Selection + write-back intent
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## The index of the row whose `value` equals `value` exactly, else 0 (the "(none)" row) — the same fallback as
## `npcdata_inspector.gd._index_of_metadata`, so an unrepresentable value points at a harmless row rather than -1.
## A blank `value` short-circuits to 0, which is also what the scan would return (row 0 holds ""). That means the
## "(inline / unsaved)" transient — which deliberately carries "" — is NEVER auto-selected here; a caller that
## wants it highlighted selects it by index (`rows.size() - 1`) itself. Either way `resolve_pick` protects the
## model if the user picks it.
static func index_of(rows: Array, value: String) -> int:
	if value == "":
		return 0
	for i in rows.size():
		var row: Dictionary = rows[i] if rows[i] is Dictionary else {}
		if String(row.get("value", "")) == value:
			return i
	return 0


## Translate a picked index into an INTENT for the caller to apply to its model:
##   {"action": "keep"}                  -> do nothing; leave the field exactly as it is
##   {"action": "clear"}                 -> null / "" the field
##   {"action": "set", "value": <path/id>} -> assign that value
## The ORDER of these tests is load-bearing; do not "simplify" it:
##   1. an out-of-range index FIRST — a stale index (the widget rebuilt under a queued signal, or a caller
##      replaying an old pick) must never reach the mutation branches. Refusing beats guessing.
##   2. index 0 is the one and only "(none)" row -> the explicit, intended clear.
##   3. ONLY THEN the empty-value test, which catches the "(inline / unsaved)" transient at a NON-zero index:
##      re-picking the row that represents an in-memory resource must NOT wipe that reference. This is the whole
##      reason the module exists — it is the trap `quest_editor.gd:351-355` documents in prose today, where an
##      empty path at index > 0 falls through to `return` rather than to `next_quest = null`. Testing "value is
##      empty" before "index is 0" would collapse both into one branch and clear the field.
##   4. anything else is a real, representable pick.
## A DISABLED row can't be clicked in the widget, so it never gets here — but if a caller synthesises the index
## anyway, rule 4 hands back its own value, which is a no-op assignment rather than a clobber.
static func resolve_pick(rows: Array, idx: int) -> Dictionary:
	if idx < 0 or idx >= rows.size():
		return {"action": "keep"}
	if idx == 0:
		return {"action": "clear"}
	var row: Dictionary = rows[idx] if rows[idx] is Dictionary else {}
	var value := String(row.get("value", ""))
	if value == "":
		return {"action": "keep"}
	return {"action": "set", "value": value}


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# Widget fill
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## Fill `btn` from `rows` and point it at `value`. Idempotent (clears first), so it doubles as the model->widget
## push after every rescan/load. `select()` does NOT emit `item_selected`, so this can never trigger the
## write-back handler and loop.
##
## It also sets three WIDTH GUARDS, and they belong HERE rather than in each caller, because forgetting them in
## one dock silently deforms the whole bottom panel:
##   * `fit_to_longest_item` defaults TRUE on OptionButton — the control's minimum width grows to its LONGEST
##     item, so a dropdown holding 35 item ids (or one long "…  (off-disk)" row) sets a huge minimum.
##   * `dialogue_editor.gd:154` and `quest_editor.gd:82` both put the form in a ScrollContainer with
##     `horizontal_scroll_mode = SCROLL_MODE_DISABLED`, which PROPAGATES that content minimum width outward —
##     so the panel itself widens to fit the widest dropdown entry, shoving the editor around.
##   * `clip_text` then drops the button's OWN text from its minimum width (the `hotbar.gd` / `level_up_screen.gd`
##     idiom), so a long selected label is CHOPPED at the box edge instead of widening it. Note `clip_text` alone
##     is a hard cut, not a "…" — a caller that wants the ellipsis sets `text_overrun_behavior =
##     TextServer.OVERRUN_TRIM_ELLIPSIS` itself (it's a cosmetic choice, not a width guard, so it isn't forced here).
##   * `PICKER_MIN_WIDTH` is the floor that keeps the now-unanchored box from collapsing when every row is short.
## `fit_to_longest_item` appears NOWHERE else in this codebase, so this guard is new and load-bearing — a future
## reader must not drop it as "redundant defaults".
## Touches only the OptionButton (no EditorInterface), so `OptionButton.new()` exercises it headless.
static func apply(btn: OptionButton, rows: Array, value: String) -> void:
	if btn == null:
		return
	btn.clear()
	for i in rows.size():
		var row: Dictionary = rows[i] if rows[i] is Dictionary else {}
		btn.add_item(String(row.get("label", "")))
		btn.set_item_metadata(i, String(row.get("value", "")))
		# Variant truthiness, NEVER `bool(...)`: `rows` is a plain Array any caller (or test) can hand-build, and
		# Godot 4's bool() has constructors for bool/int/float ONLY — `bool(<String>)` throws "Nonexistent 'bool'
		# constructor" at runtime. An `if` on a Variant coerces without a constructor, so a junk flag degrades
		# quietly instead of crashing the dock. (Same trap as GameState.as_bool guards on the save path.)
		if row.get("disabled", false):
			btn.set_item_disabled(i, true)  # informational row — visible, never pickable
	btn.fit_to_longest_item = false
	btn.clip_text = true
	btn.custom_minimum_size = Vector2(PICKER_MIN_WIDTH, 0)
	if rows.is_empty():
		btn.select(-1)  # nothing to point at; select(0) on an empty popup is an engine error (and GUT fails those)
		return
	btn.select(index_of(rows, value))


## Filename stem of a resource path for a picker label: "res://resources/quests/find_dog.tres" -> "find_dog".
## Deliberately NOT `InspectorCalc.picker_label_for`, which maps "" -> "(none)": a blank stem must never mint a
## SECOND row that READS like the clear-the-field row at index 0. Both call sites feed it a real path (a scanned
## entry, or a `current` already tested non-empty), so the blank case never arises here. Kept local so this module
## stays dependency-free — three docks const-preload it and must not drag the inspector helpers along.
static func _stem(path: String) -> String:
	return path.get_file().get_basename()
