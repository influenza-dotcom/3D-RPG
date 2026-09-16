# NO @tool / NO extends Node: a plain script of PURE STATIC ops on a DialogueResource. These mutate the
# in-memory resource ONLY -- no EditorInterface, no ResourceSaver, no scene tree -- so the dialogue_editor.gd
# glue can call them AND a GUT test can round-trip them on throwaway .new() resources. Every op guards its
# bounds and returns a success bool (false = a no-op was refused, e.g. out-of-range index / null arg) so the
# caller can decide whether to refresh the UI. Mirrors faction_matrix.gd's "pure helpers, thin glue" split.
#
# ADDRESSING. A choice points at a line by DialogueLine.id (DialogueChoice.target_id / target_on_fail_id, or the
# sentinel words END / CONTINUE) -- or, LEGACY, by the int target / target_on_fail (an index into lines). The
# resolver and the resolution order ("id if non-blank, else the int") live in DialogueResource.resolve_target;
# everything here goes through it. The id ops are the second half of this file: a unique default id for every
# added line, a rename that carries every reference with it, and the one-shot migration of a by-number
# conversation to ids. They are what let Remove / Up / Down stop being destructive: an id-addressed choice keeps
# its destination through any reorder, a by-number one does not (see remove_line / move_line).
#
# Field/method names verified against scripts/dialogue/{dialogue_resource,dialogue_line,dialogue_choice}.gd:
#   DialogueResource.lines : Array[DialogueLine]; find_line / resolve_target / next_line_id (the pure statics)
#   DialogueLine.id : StringName, DialogueLine.text : String, DialogueLine.choices : Array[DialogueChoice]
#   DialogueChoice.text : String, DialogueChoice.target_id / target_on_fail_id : StringName,
#   DialogueChoice.target : int (DialogueLine.CONTINUE = -2 default), target_on_fail : int (DialogueLine.END = -1)
extends RefCounted

## The script defaults of the two legacy ints, restored when a choice is re-addressed by id so the .tres stays
## clean (a default-valued field is omitted on save). Literals mirror dialogue_choice.gd's own literal defaults.
const INT_TARGET_DEFAULT := -2  # DialogueLine.CONTINUE
const INT_FAIL_DEFAULT := -1    # DialogueLine.END

## The Dictionary keys every result of the id ops carries. Named so the glue and the tests read the same words.
const K_OK := "ok"
const K_REASON := "reason"
const K_REWRITTEN := "rewritten"
const K_CAPTURED := "captured"
const K_LINES := "lines"
const K_CHOICES := "choices"
const K_UNRESOLVED := "unresolved"

# --- lines ------------------------------------------------------------------------------------------------------

## Append a fresh DialogueLine to res.lines, BORN WITH A UNIQUE ID (DialogueResource.next_line_id: "line_<index at
## creation>", bumped past any id already in use). Returns the new line (null on a null resource) so the caller can
## select it. A new line has no choices, so it plays linearly until the designer adds one. Adding a line to a
## by-number (legacy) conversation makes it MIXED -- the new line is id-addressed, the old choices still count by
## number -- which is exactly what Migrate to Ids and the audit's migrate nudge are for.
static func add_line(res: DialogueResource) -> DialogueLine:
	if res == null:
		return null
	var line := DialogueLine.new()
	line.id = DialogueResource.next_line_id(res.lines)
	res.lines.append(line)
	return line


## Remove the line at index `i`. Returns true if a line was removed; false on null / out-of-range. This op does NOT
## rewrite any choice (no silent edits), and the two addressing modes fail differently: a choice that pointed at the
## removed line BY ID now points at nothing (the resolver ENDS the conversation there, and the Audit reports the
## dangling id as an ERROR); a choice that pointed BY NUMBER past `i` now lands on a DIFFERENT line, since every
## later index shifts down by one. The editor's Target dropdowns are where the designer re-points either kind.
static func remove_line(res: DialogueResource, i: int) -> bool:
	if res == null or i < 0 or i >= res.lines.size():
		return false
	res.lines.remove_at(i)
	return true


## Move the line at `i` by `dir` (-1 = up, +1 = down). Returns true if it moved; false on null / out-of-range /
## a no-op at an end / an invalid step. An id-addressed choice keeps its destination through the move (ids are
## positional-free); a by-number choice does not (indices are positional) -- the remove_line caveat, again.
static func move_line(res: DialogueResource, i: int, dir: int) -> bool:
	if res == null:
		return false
	return _swap(res.lines, i, dir)


# --- choices ----------------------------------------------------------------------------------------------------

## Append a fresh DialogueChoice to `line`.choices. Returns the new choice (null on a null line). Deliberately a
## bare DialogueChoice.new(): its ids stay BLANK and its int target defaults to DialogueLine.CONTINUE (-2), so a
## fresh choice is byte-identical to one made in the raw inspector and carries the convo on to the next line
## rather than dead-ending it. It becomes id-addressed the moment the designer picks a Target (or presses Migrate
## to Ids); a sentinel int is not index-fragile, so the audit never nags about it.
static func add_choice(line: DialogueLine) -> DialogueChoice:
	if line == null:
		return null
	var choice := DialogueChoice.new()
	line.choices.append(choice)
	return choice


## Remove the choice at index `j` from `line`.choices. Returns true if removed; false on null / out-of-range.
static func remove_choice(line: DialogueLine, j: int) -> bool:
	if line == null or j < 0 or j >= line.choices.size():
		return false
	line.choices.remove_at(j)
	return true


## Move the choice at `j` within `line`.choices by `dir` (-1 up / +1 down). Returns true if it moved; false on
## null / out-of-range / a no-op at an end. Choice order is purely presentational (the button order shown), so
## reordering is always safe -- unlike line order it never shifts any addressed index.
static func move_choice(line: DialogueLine, j: int, dir: int) -> bool:
	if line == null:
		return false
	return _swap(line.choices, j, dir)


# --- ids --------------------------------------------------------------------------------------------------------

## Why a line may NOT take `id`: "" when it may, else the designer-words refusal. The three rules the resolver's
## contract needs: an id is never blank (blank means "legacy, by number"), never a sentinel word (the resolver checks
## END / CONTINUE before it looks at lines, so such a line could never be reached by id), and never another line's
## (with a duplicate the FIRST line silently wins). `owner` is the line asking, so re-taking its own id is not a
## duplicate. Whitespace is stripped by the callers before they ask, so "  " is refused as blank here.
static func id_refusal(res: DialogueResource, owner: DialogueLine, id: StringName) -> String:
	if id == &"":
		return "an id can't be blank -- a blank line is only reachable by number."
	if id == DialogueLine.ID_END or id == DialogueLine.ID_CONTINUE:
		return "'%s' is a reserved word (it means finish / next line), so no choice could ever reach a line called that." % id
	if res != null:
		var at := DialogueResource.find_line(res.lines, id)
		if at >= 0 and res.lines[at] != owner:
			return "'%s' is already line %d's id -- ids must be unique within a conversation." % [id, at]
	return ""


## Give `line` the id `new_id` (whitespace-stripped) and carry every reference with it, in ONE shot: every choice in
## the conversation whose target_id / target_on_fail_id was the OLD id is rewritten to the new one, so a rename never
## strands a branch. Returns {ok, reason, rewritten, captured}: `rewritten` counts the references that followed the
## rename; `captured` counts choices that ALREADY pointed at `new_id` before the rename -- they were dangling (the
## audit was reporting them) and now land on this line, which the designer must be TOLD, because nothing else
## distinguishes a captured choice from an authored one. A refusal (id_refusal) leaves the resource untouched.
## Renaming a line whose id was BLANK is a plain assignment (nothing can reference blank); renaming to its own id is
## an ok no-op. Single-shot on purpose: the tab commits the Id box on Enter / focus loss, never per keystroke, so
## no half-typed spelling is ever written into a reference.
static func rename_line_id(res: DialogueResource, line: DialogueLine, new_id: StringName) -> Dictionary:
	var out := {K_OK: false, K_REASON: "", K_REWRITTEN: 0, K_CAPTURED: 0}
	if res == null or line == null:
		out[K_REASON] = "nothing is picked."
		return out
	var wanted := StringName(String(new_id).strip_edges())
	var why := id_refusal(res, line, wanted)
	if why != "":
		out[K_REASON] = why
		return out
	var old := line.id
	if old == wanted:
		out[K_OK] = true
		return out
	# Count the captures BEFORE the rewrite, while "already points at wanted" is still distinguishable.
	for ln in res.lines:
		if ln == null:
			continue
		for ch in ln.choices:
			if ch == null:
				continue
			if ch.target_id == wanted:
				out[K_CAPTURED] += 1
			if ch.target_on_fail_id == wanted:
				out[K_CAPTURED] += 1
	line.id = wanted
	if old != &"":
		for ln in res.lines:
			if ln == null:
				continue
			for ch in ln.choices:
				if ch == null:
					continue
				if ch.target_id == old:
					ch.target_id = wanted
					out[K_REWRITTEN] += 1
				if ch.target_on_fail_id == old:
					ch.target_on_fail_id = wanted
					out[K_REWRITTEN] += 1
	out[K_OK] = true
	return out


## The id form of a legacy int `t`, or "" when the int has no faithful id form: END / CONTINUE for the sentinels, the
## addressed line's id for an in-range index -- but ONLY when that id round-trips, i.e. resolve_target(lines, id, t)
## lands back on `t`. It does not when the line is id-less, when its id is a duplicate (the resolver would pick the
## FIRST line with that id) or when its id is a sentinel word (the word wins). An out-of-range int has no id form at
## all. The round-trip is the invariant, not the id text: migration must never MOVE a destination.
static func id_form_of(lines: Array, t: int) -> StringName:
	if t == DialogueLine.END:
		return DialogueLine.ID_END
	if t == DialogueLine.CONTINUE:
		return DialogueLine.ID_CONTINUE
	if t < 0 or t >= lines.size() or lines[t] == null:
		return &""
	var candidate: StringName = lines[t].id
	if candidate == &"":
		return &""
	if DialogueResource.resolve_target(lines, candidate, t) != t:
		return &""
	return candidate


## True when Migrate to Ids has work to do: an id-less line (it would get one), or a choice still addressed by number
## whose int HAS a faithful id form (id_form_of: a sentinel, or a valid index onto a uniquely-id'd line). A by-number
## choice whose int is out of range, or whose line carries a duplicate / reserved-word id, is NOT migratable work --
## its fix is the Target dropdown (and the audit names it) -- so it never keeps the button lit for a no-op.
static func needs_migration(res: DialogueResource) -> bool:
	if res == null:
		return false
	for ln in res.lines:
		if ln != null and ln.id == &"":
			return true
	for ln in res.lines:
		if ln == null:
			continue
		for ch in ln.choices:
			if ch == null:
				continue
			if ch.target_id == &"" and id_form_of(res.lines, ch.target) != &"":
				return true
			if ch.target_on_fail_id == &"" and id_form_of(res.lines, ch.target_on_fail) != &"":
				return true
	return false


## Re-address the whole conversation by id, in memory: every id-less line gets DialogueResource.next_line_id-style
## default ("line_<index>", bumped past a taken id), then every choice still pointing by number is given the id form
## of its int (id_form_of) and its int is RESET to the script default so the saved .tres carries only the id. A
## choice whose int has NO faithful id form (out of range; or, only in a hand-edited file, a line whose id is a
## duplicate / a sentinel word) is LEFT AS IT IS and counted in `unresolved`, so migration can never move a
## destination -- the audit names those choices. Returns {lines, choices, unresolved}. Idempotent: a second run
## reports 0 / 0 / the same unresolved count.
static func migrate_to_ids(res: DialogueResource) -> Dictionary:
	var out := {K_LINES: 0, K_CHOICES: 0, K_UNRESOLVED: 0}
	if res == null:
		return out
	for i in res.lines.size():
		var ln: DialogueLine = res.lines[i]
		if ln != null and ln.id == &"":
			ln.id = _default_id_for_index(res.lines, i)
			out[K_LINES] += 1
	for ln in res.lines:
		if ln == null:
			continue
		for ch in ln.choices:
			if ch == null:
				continue
			var touched := false
			if ch.target_id == &"":
				var form := id_form_of(res.lines, ch.target)
				if form == &"":
					out[K_UNRESOLVED] += 1
				else:
					ch.target_id = form
					ch.target = INT_TARGET_DEFAULT
					touched = true
			if ch.target_on_fail_id == &"":
				var fail_form := id_form_of(res.lines, ch.target_on_fail)
				if fail_form == &"":
					out[K_UNRESOLVED] += 1
				else:
					ch.target_on_fail_id = fail_form
					ch.target_on_fail = INT_FAIL_DEFAULT
					touched = true
			if touched:
				out[K_CHOICES] += 1
	return out


## "line_<i>" for the line at index `i`, bumped past any id already taken (a hand-authored "line_3" elsewhere must
## not be duplicated by the migration). Mirrors DialogueResource.next_line_id's naming for an EXISTING slot.
static func _default_id_for_index(lines: Array, i: int) -> StringName:
	var n := i
	var candidate := StringName("line_%d" % n)
	while DialogueResource.find_line(lines, candidate) >= 0:
		n += 1
		candidate = StringName("line_%d" % n)
	return candidate


# --- shared ----------------------------------------------------------------------------------------------------

## Swap element `i` with its `dir` neighbour in `arr` (dir must be -1 or +1). Returns true if the swap happened;
## false on out-of-range source, an off-the-end destination, or an invalid step. Typed as Array so it works on
## both Array[DialogueLine] and Array[DialogueChoice].
static func _swap(arr: Array, i: int, dir: int) -> bool:
	if dir != -1 and dir != 1:
		return false
	if i < 0 or i >= arr.size():
		return false
	var j := i + dir
	if j < 0 or j >= arr.size():
		return false
	var tmp = arr[i]
	arr[i] = arr[j]
	arr[j] = tmp
	return true
