class_name DialogueResource
extends Resource

## A full conversation — an ordered list of lines. Make these as .tres files and assign one to a
## DialogueNPC; DialogueManager plays it back top to bottom.
##
## ADDRESSING. A choice names its destination by a DialogueLine.id (`DialogueChoice.target_id`, or the sentinel
## words END / CONTINUE) — or, when that is blank, by the LEGACY int `DialogueChoice.target` (an index into
## `lines`). `resolve_target` below is the ONE resolver that folds both forms into the int space DialogueManager
## _jump_to consumes; the manager, the Dialogue Edit tab, the Graphs viewer and the audit all go through it (or
## through `find_line`), so the resolution order ("id if non-blank, else the int") is defined exactly once. Ids are
## what make a conversation survive inserting / deleting / reordering lines; the int path exists so every
## conversation authored before ids — every shipped .tres AND the inline ones inside .tscn levels — plays unedited.
## PURE: no autoload, no tree, no side effects, so GUT drives it on throwaway resources.

## The conversation's lines, played top to bottom. A choice jumps to a line by its `id` (or, legacy, by INDEX into
## this array); linear play and the CONTINUE sentinel are still positional — "the next line" is the next element.
@export var lines: Array[DialogueLine] = []


## The index of the FIRST line whose `id` equals `id`, or -1 when `id` is blank or names no line. A blank id is
## "legacy / unnamed", never a name, so it can never match an id-less line. -1 here is plain NOT-FOUND — it happens
## to equal DialogueLine.END numerically, which is why callers that need the distinction (the audit, the editor's
## dangling-id row) call THIS and callers that just need a destination call resolve_target. With duplicate ids the
## first wins; the audit reports the duplicate as an ERROR so a designer never relies on that.
static func find_line(lines_in: Array, id: StringName) -> int:
	if id == &"":
		return -1
	for i in lines_in.size():
		var ln: Variant = lines_in[i]
		if ln != null and ln.id == id:
			return i
	return -1


## THE resolver: a choice's destination in DialogueManager._jump_to's int space (a line index, DialogueLine.END,
## or DialogueLine.CONTINUE). Order is fixed and is the whole contract:
##   * `target_id` blank            -> `legacy`, UNCHANGED (an out-of-range int passes through so _jump_to still
##                                     maps it to _finish() and the audit still sees it; masking it here as END
##                                     would hide a real authoring error).
##   * `target_id` == END / CONTINUE -> the matching int sentinel (the words win over any stale int).
##   * a known line id              -> that line's index (the id wins over the int).
##   * an UNKNOWN id                -> END. Deliberately NOT the int: a typo'd id must end the conversation cleanly
##                                     (the same soft failure an out-of-range int gets), never CONTINUE into a
##                                     wrong line, and never silently trust an int the author stopped maintaining.
##                                     DialogueManager._resolve_target warns with the id; the audit flags it.
static func resolve_target(lines_in: Array, target_id: StringName, legacy: int) -> int:
	if target_id == &"":
		return legacy
	if target_id == DialogueLine.ID_END:
		return DialogueLine.END
	if target_id == DialogueLine.ID_CONTINUE:
		return DialogueLine.CONTINUE
	var idx := find_line(lines_in, target_id)
	return idx if idx >= 0 else DialogueLine.END


## The default id for a line about to be APPENDED to `lines_in`: "line_<its index at creation>", bumped past any id
## already in use so it is unique on arrival. Shared by the Dialogue Edit tab's Add (dialogue_edit_ops.add_line) and
## the New tab's conversation scaffold (content_scaffold.build_dialogue), so every conversation authored from now on
## is born id-addressed and never needs Migrate to Ids. Lives here rather than in the plugin because both callers
## are addon modules that must not preload each other. The name reads like the list's position ONLY at creation —
## an id is stable and the number is not, which is why the tab shows the id beside the number in its lines list.
static func next_line_id(lines_in: Array) -> StringName:
	var n := lines_in.size()
	var candidate := StringName("line_%d" % n)
	while find_line(lines_in, candidate) >= 0:
		n += 1
		candidate = StringName("line_%d" % n)
	return candidate


## Instance forms of the two statics, for callers that hold the resource.
func line_index(id: StringName) -> int:
	return find_line(lines, id)


func resolve(target_id: StringName, legacy: int) -> int:
	return resolve_target(lines, target_id, legacy)


## The NON-BLANK line ids in line order (an id-less legacy line contributes nothing). The Dialogue Edit tab's
## target dropdown and the audit's "ids here: …" message read this.
func line_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for ln in lines:
		if ln != null and ln.id != &"":
			out.append(ln.id)
	return out


## True when the conversation is fully id-addressed: at least one line, and every line has an id. An EMPTY
## conversation answers false on purpose (vacuous truth would make the audit's migrate nudge fire on a blank file).
## Consumers: the Dialogue Edit tab greys Migrate to Ids on true; the audit only WARNs about a by-number choice
## when this is true (a wholly legacy conversation stays quiet).
func all_lines_have_ids() -> bool:
	if lines.is_empty():
		return false
	for ln in lines:
		if ln == null or ln.id == &"":
			return false
	return true
