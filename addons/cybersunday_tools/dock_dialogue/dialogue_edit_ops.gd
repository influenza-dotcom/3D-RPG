# NO @tool / NO extends Node: a plain script of PURE STATIC ops on a DialogueResource. These mutate the
# in-memory resource ONLY -- no EditorInterface, no ResourceSaver, no scene tree -- so the dialogue_editor.gd
# glue can call them AND a GUT test can round-trip them on throwaway .new() resources. Every op guards its
# bounds and returns a success bool (false = a no-op was refused, e.g. out-of-range index / null arg) so the
# caller can decide whether to refresh the UI. Mirrors faction_matrix.gd's "pure helpers, thin glue" split.
#
# Field/method names verified against scripts/dialogue/{dialogue_resource,dialogue_line,dialogue_choice}.gd:
#   DialogueResource.lines : Array[DialogueLine]
#   DialogueLine.text : String, DialogueLine.choices : Array[DialogueChoice]
#   DialogueChoice.text : String, DialogueChoice.target : int (DialogueLine.CONTINUE = -2 default)
extends RefCounted

# --- lines ------------------------------------------------------------------------------------------------------

## Append a fresh empty DialogueLine to res.lines. Returns the new line (null on a null resource) so the caller
## can select it. A new line has no choices, so it plays linearly until the designer adds one.
static func add_line(res: DialogueResource) -> DialogueLine:
	if res == null:
		return null
	var line := DialogueLine.new()
	res.lines.append(line)
	return line


## Remove the line at index `i`. Returns true if a line was removed; false on null / out-of-range. NOTE: removing
## a line shifts every later index down by one, so DialogueChoice.target ints that point past `i` will now
## address a different line -- the editor surfaces targets as an OptionButton so the designer can re-point them,
## and the read-only Graphs panel flags dangling targets. This op does NOT auto-rewrite targets (no silent edits).
static func remove_line(res: DialogueResource, i: int) -> bool:
	if res == null or i < 0 or i >= res.lines.size():
		return false
	res.lines.remove_at(i)
	return true


## Move the line at `i` by `dir` (-1 = up, +1 = down). Returns true if it moved; false on null / out-of-range /
## a no-op at an end / an invalid step. Same target-index caveat as remove_line (indices are positional).
static func move_line(res: DialogueResource, i: int, dir: int) -> bool:
	if res == null:
		return false
	return _swap(res.lines, i, dir)


# --- choices ----------------------------------------------------------------------------------------------------

## Append a fresh DialogueChoice to `line`.choices. Returns the new choice (null on a null line). Its target
## defaults to DialogueLine.CONTINUE (-2) per dialogue_choice.gd, so a freshly-added choice carries the convo on
## to the next line rather than dead-ending it.
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
