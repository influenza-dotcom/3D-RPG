extends GutTest

## Dialogue addressing by ID (the New-Vegas-scale data-model change): DialogueLine.id + DialogueChoice.target_id /
## target_on_fail_id, resolved by the PURE DialogueResource.resolve_target, with the int `target` / `target_on_fail`
## kept as the LEGACY fallback so every existing .tres and inline .tscn conversation keeps playing unedited.
##
## This file is deliberately SEPARATE from tests/test_dialogue.gd: that suite pins the int-era contract (sentinel
## values, target defaults / types) and is co-edited by other work; nothing here re-pins it. Sections:
##   1. LEGACY CONTRACT (written BEFORE the refactor, against the raw ints) — the two shipped conversations route
##      where the int-addressed manager sent them. `_route` now goes through the resolver; the assertions did not
##      change, which is the proof the migration moved no destination. Kept as the "still plays" pin.
##   2. The new fields' defaults (blank = legacy, so an old file reads as before).
##   3. The resolver matrix: blank id -> the int; END / CONTINUE sentinels; a known id; an unknown id; duplicates.
##   4. DialogueManager._resolve_target — the runtime seam over the pure resolver (no view is touched).
##   5. The shipped content contract after migration: unique non-blank line ids, every choice resolves by id.

const OLD_MAN := "res://resources/dialogue/old_man.tres"
const RELAY := "res://resources/dialogue/slice_relay_terminal.tres"
const MANAGER_PATH := "res://scripts/dialogue/dialogue_manager.gd"


func _load_dialogue(path: String) -> DialogueResource:
	var r := load(path)
	assert_true(r is DialogueResource, "%s must load as a DialogueResource" % path.get_file())
	return r as DialogueResource


## Where a choice goes, in _jump_to's int space. Pre-refactor this returned the raw int; now it is the resolver,
## and sections 1 + 5 must agree.
func _route(lines: Array, target_id: StringName, legacy: int) -> int:
	return DialogueResource.resolve_target(lines, target_id, legacy)


# ---------------------------------------------------------------------------------------------------------------
# 1. LEGACY CONTRACT — the two shipped conversations, as the int-addressed manager routed them.
# ---------------------------------------------------------------------------------------------------------------

func test_old_man_shape_two_lines_second_branches_with_two_continue_choices() -> void:
	var r := _load_dialogue(OLD_MAN)
	assert_eq(r.lines.size(), 2, "old_man.tres is the two-line shell the authoring guide's worked example describes")
	assert_false(r.lines[0].has_choices(), "line 0 plays linearly")
	assert_eq(r.lines[1].choices.size(), 2, "line 1 is the branch point with two replies")
	for ch in r.lines[1].choices:
		assert_eq(_route(r.lines, ch.target_id, ch.target), DialogueLine.CONTINUE,
			"both old_man replies CONTINUE past the last line (the conversation ends by running off the end) -- the migration must not change where they go")
		assert_eq(_route(r.lines, ch.target_on_fail_id, ch.target_on_fail), DialogueLine.END,
			"an old_man reply's fail branch is END (the field default) -- ungated, so never taken, but the value must round-trip")


func test_relay_terminal_transmit_choice_routes_to_the_done_line() -> void:
	var r := _load_dialogue(RELAY)
	assert_eq(r.lines.size(), 2, "slice_relay_terminal.tres is prompt + done")
	assert_eq(r.lines[0].choices.size(), 1, "the prompt line offers the one Transmit choice")
	var ch: DialogueChoice = r.lines[0].choices[0]
	assert_eq(_route(r.lines, ch.target_id, ch.target), 1,
		"Transmit jumps to line 1 (the done line) -- authored as `target = 1` before ids existed, and the migrated file must resolve to the SAME index")
	assert_eq(_route(r.lines, ch.target_on_fail_id, ch.target_on_fail), DialogueLine.END,
		"a failed Transmit (no package / quest not active) ENDS the conversation")
	assert_eq(ch.complete_quest_id, &"recover_package", "the turn-in consequence rides along untouched")


# ---------------------------------------------------------------------------------------------------------------
# 2. Field defaults — blank means legacy.
# ---------------------------------------------------------------------------------------------------------------

func test_line_id_defaults_blank_so_an_old_file_reads_as_before() -> void:
	var ln := DialogueLine.new()
	assert_eq(ln.id, &"", "DialogueLine.id defaults to blank: a .tres written before ids existed carries no id field and must load as an id-less (int-addressed) line")
	assert_eq(typeof(ln.id), TYPE_STRING_NAME, "id is a StringName, the same type every other stable key in this project uses (NpcData.id, Quest.id)")
	ln.id = &"greet"
	assert_eq(ln.id, &"greet", "id is a writable @export")


func test_choice_id_targets_default_blank_and_the_ints_keep_their_defaults() -> void:
	var c := DialogueChoice.new()
	assert_eq(c.target_id, &"", "target_id defaults blank -> the resolver falls through to the int (legacy)")
	assert_eq(c.target_on_fail_id, &"", "target_on_fail_id defaults blank -> falls through to the int")
	assert_eq(c.target, DialogueLine.CONTINUE, "the int target keeps its CONTINUE default (the legacy path is untouched)")
	assert_eq(c.target_on_fail, DialogueLine.END, "the int fail target keeps its END default")


func test_id_sentinels_are_the_documented_words() -> void:
	assert_eq(DialogueLine.ID_END, &"END", "the END sentinel a designer types into target_id is the word END")
	assert_eq(DialogueLine.ID_CONTINUE, &"CONTINUE", "the CONTINUE sentinel is the word CONTINUE")
	assert_ne(DialogueLine.ID_END, DialogueLine.ID_CONTINUE, "the two id sentinels are distinct words")


func test_choice_id_targets_suggest_the_sentinels_in_the_inspector() -> void:
	# A sub-resource cannot see its owning resource's lines, so the raw inspector can only suggest the two
	# sentinels; the Dialogue Edit tab has the real per-line dropdown. SUGGESTION, never a closed enum -- a line id
	# must stay typable.
	var c := DialogueChoice.new()
	for pname in ["target_id", "target_on_fail_id"]:
		var prop := {"name": pname, "hint": PROPERTY_HINT_NONE, "hint_string": ""}
		c._validate_property(prop)
		assert_eq(prop["hint"], PROPERTY_HINT_ENUM_SUGGESTION, "%s is a suggestion dropdown (typable)" % pname)
		assert_true(String(prop["hint_string"]).contains("END") and String(prop["hint_string"]).contains("CONTINUE"),
			"%s suggests both sentinel words" % pname)


# ---------------------------------------------------------------------------------------------------------------
# 3. The pure resolver.
# ---------------------------------------------------------------------------------------------------------------

func _three_lines() -> Array:
	var a := DialogueLine.new()
	a.id = &"greet"
	var b := DialogueLine.new()
	b.id = &"refuse"
	var c := DialogueLine.new()  # id-less (a legacy line in a half-migrated conversation)
	return [a, b, c]


func test_resolver_blank_id_returns_the_legacy_int_unchanged() -> void:
	var lines := _three_lines()
	assert_eq(DialogueResource.resolve_target(lines, &"", DialogueLine.CONTINUE), DialogueLine.CONTINUE, "blank id + CONTINUE int -> CONTINUE")
	assert_eq(DialogueResource.resolve_target(lines, &"", DialogueLine.END), DialogueLine.END, "blank id + END int -> END")
	assert_eq(DialogueResource.resolve_target(lines, &"", 2), 2, "blank id + a line index -> that index (the legacy jump)")
	assert_eq(DialogueResource.resolve_target(lines, &"", 99), 99,
		"blank id + an OUT-OF-RANGE int passes through UNCHANGED: _jump_to already maps out-of-range to _finish(), and the audit reports it -- the resolver must not mask it as END")


func test_resolver_sentinel_words_win_over_any_int() -> void:
	var lines := _three_lines()
	assert_eq(DialogueResource.resolve_target(lines, DialogueLine.ID_END, 1), DialogueLine.END, "END id -> END, even with a stale int pointing at line 1")
	assert_eq(DialogueResource.resolve_target(lines, DialogueLine.ID_CONTINUE, DialogueLine.END), DialogueLine.CONTINUE, "CONTINUE id -> CONTINUE, even with a stale END int")


func test_resolver_known_id_returns_that_lines_index() -> void:
	var lines := _three_lines()
	assert_eq(DialogueResource.resolve_target(lines, &"greet", DialogueLine.CONTINUE), 0, "greet is line 0")
	assert_eq(DialogueResource.resolve_target(lines, &"refuse", 0), 1,
		"refuse is line 1 -- the id wins over an int that says line 0 (id if non-blank, else the int)")


func test_resolver_unknown_id_ends_the_conversation_never_the_int() -> void:
	var lines := _three_lines()
	assert_eq(DialogueResource.resolve_target(lines, &"gret", 1), DialogueLine.END,
		"a typo'd id ENDS cleanly (like an out-of-range int does) rather than falling back to the int -- silently CONTINUING into the wrong line is the worse failure, and the audit flags the typo")


func test_resolver_ignores_a_blank_line_id_and_takes_the_first_duplicate() -> void:
	var lines := _three_lines()
	# The id-less third line must never match a blank lookup (blank is "legacy", not a name).
	assert_eq(DialogueResource.find_line(lines, &""), -1, "a blank id never resolves to the id-less line")
	var dup := DialogueLine.new()
	dup.id = &"greet"
	lines.append(dup)
	assert_eq(DialogueResource.find_line(lines, &"greet"), 0, "with a duplicate id the FIRST line wins (the audit reports the duplicate as an ERROR)")
	assert_eq(DialogueResource.find_line(lines, &"nope"), -1, "find_line answers -1 for an unknown id -- plain not-found, distinct from the END sentinel the resolver maps it to")
	assert_eq(DialogueResource.find_line([null, lines[0]], &"greet"), 1, "a null slot in the array (a .tres null-row) is skipped, never dereferenced")


func test_next_line_id_is_the_creation_index_bumped_past_taken_ids() -> void:
	var lines: Array = []
	assert_eq(DialogueResource.next_line_id(lines), &"line_0", "an empty conversation's first line is line_0")
	var a := DialogueLine.new()
	a.id = &"line_0"
	lines.append(a)
	var b := DialogueLine.new()
	b.id = &"line_1"
	lines.append(b)
	assert_eq(DialogueResource.next_line_id(lines), &"line_2", "the next default is the index the new line will land on")
	var hand := DialogueLine.new()
	hand.id = &"line_3"  # hand-authored ahead of time
	lines.append(hand)
	assert_eq(DialogueResource.next_line_id(lines), &"line_4", "line_3 is taken (by the line at index 2!), so the default bumps -- the name is a default, never a promise about position")
	var legacy := DialogueLine.new()  # id-less
	lines.append(legacy)
	assert_eq(DialogueResource.next_line_id(lines), &"line_4", "an id-less line takes no name, so the default is unchanged")


func test_a_line_named_after_a_sentinel_word_is_unreachable_by_id() -> void:
	var lines := _three_lines()
	var trap := DialogueLine.new()
	trap.id = &"END"  # a hand-typed reserved word
	lines.append(trap)
	assert_eq(DialogueResource.resolve_target(lines, &"END", 0), DialogueLine.END,
		"the sentinel word is checked BEFORE the lines, so target_id END still ENDS -- the line named END can never be reached by id (the audit reports it)")
	assert_eq(DialogueResource.find_line(lines, &"END"), 3, "find_line itself still finds it (it is a plain lookup); only the resolver reserves the word")


func test_resource_id_helpers() -> void:
	var r := DialogueResource.new()
	for ln in _three_lines():
		r.lines.append(ln)
	assert_eq(r.line_index(&"refuse"), 1, "line_index is the instance form of find_line")
	assert_eq(r.resolve(&"refuse", 0), 1, "resolve is the instance form of resolve_target")
	assert_eq(r.line_ids(), [&"greet", &"refuse"], "line_ids lists the NON-BLANK ids in line order (the id-less line is skipped)")
	assert_false(r.all_lines_have_ids(), "one id-less line -> not fully id-addressed")
	r.lines[2].id = &"walk_away"
	assert_true(r.all_lines_have_ids(), "every line named -> fully id-addressed")
	var empty := DialogueResource.new()
	assert_false(empty.all_lines_have_ids(), "an EMPTY conversation is not 'all id-addressed' (vacuous truth would make the audit's migrate-nudge fire on a blank file)")


# ---------------------------------------------------------------------------------------------------------------
# 4. DialogueManager._resolve_target — the runtime seam. Loaded via load(path).new() (no class_name), never
#    _ready()'d, and the view is never touched: this is the pure decision the choice press feeds _jump_to.
# ---------------------------------------------------------------------------------------------------------------

func test_manager_resolves_ids_against_the_active_conversation() -> void:
	var m = load(MANAGER_PATH).new()
	var r := DialogueResource.new()
	for ln in _three_lines():
		r.lines.append(ln)
	m._active = r
	assert_eq(m._resolve_target(&"refuse", DialogueLine.CONTINUE), 1, "an id resolves against _active.lines")
	assert_eq(m._resolve_target(&"", 2), 2, "a blank id falls through to the legacy int")
	assert_eq(m._resolve_target(DialogueLine.ID_END, 0), DialogueLine.END, "the END word ends")
	assert_eq(m._resolve_target(&"typo", 0), DialogueLine.END, "an unknown id ends the conversation (and push_warning names it -- a warning can never fail a GUT test)")
	m._active = null
	assert_eq(m._resolve_target(&"refuse", 0), DialogueLine.END, "with no active conversation there is nothing to resolve against -> END (a stale button after _finish)")
	m.free()
	r = null


# ---------------------------------------------------------------------------------------------------------------
# 5. Shipped content after migration.
# ---------------------------------------------------------------------------------------------------------------

func test_shipped_conversations_are_fully_id_addressed_and_every_choice_resolves() -> void:
	for path in [OLD_MAN, RELAY]:
		var r := _load_dialogue(path)
		assert_true(r.all_lines_have_ids(), "%s: every line carries an id (the Migrate to Ids pass ran on it)" % path.get_file())
		var seen := {}
		for i in r.lines.size():
			var ln: DialogueLine = r.lines[i]
			assert_false(seen.has(ln.id), "%s: line %d's id %s is unique" % [path.get_file(), i, ln.id])
			seen[ln.id] = true
			for ch in ln.choices:
				assert_ne(ch.target_id, &"", "%s line %d: a choice is addressed by id, not by number" % [path.get_file(), i])
				assert_ne(ch.target_on_fail_id, &"", "%s line %d: the fail branch is addressed by id too" % [path.get_file(), i])
				var to := DialogueResource.resolve_target(r.lines, ch.target_id, ch.target)
				assert_true(to == DialogueLine.END or to == DialogueLine.CONTINUE or (to >= 0 and to < r.lines.size()),
					"%s line %d: target id %s resolves to a real line or a sentinel" % [path.get_file(), i, ch.target_id])
				var fail := DialogueResource.resolve_target(r.lines, ch.target_on_fail_id, ch.target_on_fail)
				assert_true(fail == DialogueLine.END or fail == DialogueLine.CONTINUE or (fail >= 0 and fail < r.lines.size()),
					"%s line %d: fail id %s resolves" % [path.get_file(), i, ch.target_on_fail_id])
				assert_eq(ch.target, DialogueLine.CONTINUE, "%s line %d: the legacy int was cleared to its default by the migration" % [path.get_file(), i])
				assert_eq(ch.target_on_fail, DialogueLine.END, "%s line %d: the legacy fail int was cleared to its default" % [path.get_file(), i])
