extends GutTest

## UI Copy tab — the parser and rewriter for `scripts/ui/player_text.gd`.
##
## This tab rewrites a `.gd` file, which is the riskiest write in the plugin, so the load-bearing test is
## `test_rewriting_every_value_back_to_itself_is_byte_identical`: parse the REAL file, feed every parsed value
## straight back in as an edit, and require the result to equal the original byte for byte. If escaping, line
## indexing or the constant regex is wrong in any way, that test fails — on the actual ~2,300-line file rather
## than on a fixture that happens to be easy.
##
## Everything else here is a pure static over a small literal fixture, so a failure names one rule.

const Ops := preload("res://addons/cybersunday_tools/dock_uicopy/ui_copy_ops.gd")
const UiCopyEditor := preload("res://addons/cybersunday_tools/dock_uicopy/ui_copy_editor.gd")

## A miniature player_text.gd: a doc-commented constant, a plain one, a skipped marker, a templated one, a
## dictionary constant and a preload — the six shapes the rewriter must tell apart.
const FIXTURE := """@tool
class_name PlayerText
extends RefCounted

const PH_PREFIX := "[PH]"
const PH_PREFIX_SPACE := "[PH] "
const Perks := preload("res://scripts/player/perks.gd")

## Shown under the crosshair.
## Keep it short.
const PROMPT_PICK_UP := "Pick up"

const HUD_OWED := "You owe {amount}."

const ALIGNMENT_TEMPLATES := {
	ALIGNMENT_A: ALIGNMENT_B,
}

static func greeting(name: String) -> String:
	return TextFormat.subst("Evening, {name}. Card or credit?", {"name": name})
"""


func test_ui_copy_dock_constructs_off_tree() -> void:
	var d = UiCopyEditor.new()
	assert_not_null(d, "UI Copy tab should construct off-tree")
	assert_eq(d.name, "UI Copy", "dock tab name -- cyber_panel routes show_tab / open_in_editor by this exact name")
	d.free()


func test_parse_finds_only_single_line_string_constants() -> void:
	var entries := Ops.parse(FIXTURE)
	var names: Array = []
	for e in entries:
		names.append(String(e["name"]))
	assert_eq(names, ["PROMPT_PICK_UP", "HUD_OWED"], "only the one-line string constants are editable, got %s" % str(names))


func test_parse_skips_the_marker_constants_and_the_preload_and_the_dictionary() -> void:
	var entries := Ops.parse(FIXTURE)
	for e in entries:
		var n := String(e["name"])
		assert_ne(n, "PH_PREFIX", "the marker definition is machinery, not copy")
		assert_ne(n, "PH_PREFIX_SPACE", "the marker definition is machinery, not copy")
		assert_ne(n, "Perks", "a preload is not copy")
		assert_ne(n, "ALIGNMENT_TEMPLATES", "a dictionary constant is a lookup table, not copy")


func test_parse_carries_the_doc_comment_as_help() -> void:
	var entries := Ops.parse(FIXTURE)
	assert_eq(String(entries[0]["doc"]), "Shown under the crosshair. Keep it short.", "the ## block above a constant becomes its help text")
	assert_eq(String(entries[1]["doc"]), "", "a constant with no doc block gets no help text")


func test_group_of_uses_the_prefix_convention() -> void:
	assert_eq(Ops.group_of("OPTIONS_CB_NONE"), "OPTIONS", "the prefix is the section")
	assert_eq(Ops.group_of("HUD_OWED"), "HUD", "the prefix is the section")
	assert_eq(Ops.group_of("BACK"), "General", "a name with no underscore falls into General")


# --- the safety proof -------------------------------------------------------------------------------------

func test_rewriting_every_value_back_to_itself_is_byte_identical() -> void:
	var text := FileAccess.get_file_as_string(Ops.SOURCE_PATH)
	assert_ne(text, "", "player_text.gd should be readable")
	var entries := Ops.parse(text)
	assert_true(entries.size() > 300, "expected the real file's several hundred copy constants, got %d" % entries.size())
	var edits := {}
	for e in entries:
		edits[String(e["name"])] = String(e["value"])
	var result := Ops.apply(text, edits)
	assert_eq(int(result["count"]), 0, "re-writing a value to itself must change no line")
	assert_eq(String(result["text"]), text, "a full parse + rewrite round trip must be byte-identical to the source")


func test_an_edit_changes_exactly_one_line_and_leaves_the_rest_alone() -> void:
	var before := FIXTURE.split("\n").size()
	var result := Ops.apply(FIXTURE, {"HUD_OWED": "You owe {amount} now."})
	assert_eq(int(result["count"]), 1, "one edited constant is one changed line")
	var after := String(result["text"])
	assert_eq(after.split("\n").size(), before, "the rewrite must not add or remove lines")
	assert_true(after.contains("const HUD_OWED := \"You owe {amount} now.\""), "the new value lands on its own line")
	assert_true(after.contains("const PROMPT_PICK_UP := \"Pick up\""), "an untouched constant is preserved")
	assert_true(after.contains("TextFormat.subst(\"Evening, {name}."), "code is copied through untouched")


func test_apply_refuses_to_touch_the_marker_constants() -> void:
	var result := Ops.apply(FIXTURE, {"PH_PREFIX": "[NOPE]"})
	assert_eq(int(result["count"]), 0, "the marker definition is not editable through this tab")
	assert_eq(String(result["text"]), FIXTURE, "and the file is untouched")


func test_apply_skips_a_name_that_is_no_longer_in_the_file() -> void:
	var result := Ops.apply(FIXTURE, {"GONE_AWAY": "whatever"})
	assert_eq(int(result["count"]), 0, "an edit whose constant vanished is skipped, never guessed at")


# --- escaping ---------------------------------------------------------------------------------------------

func test_escape_round_trips_the_four_escapes_that_appear_in_the_file() -> void:
	var cases := ["plain", "two\nlines", "a\ttab", "a \"quote\"", "a \\ backslash", "all\n\"of\"\\them"]
	for original in cases:
		var round_tripped := Ops.unescape(Ops.escape(original))
		assert_eq(round_tripped, original, "escape/unescape must round trip: %s" % original.replace("\n", "<nl>"))


func test_unescape_leaves_an_escape_it_does_not_own_alone() -> void:
	assert_eq(Ops.unescape("50\\% sure"), "50\\% sure", "an unknown escape passes through rather than being eaten")


func test_unescape_handles_a_backslash_before_an_escape() -> void:
	# "\\n" in source is a literal backslash followed by an n, NOT a newline. A sentinel-based replace gets this
	# wrong; the scan must consume the escaped backslash first.
	assert_eq(Ops.unescape("a\\\\nb"), "a\\nb", "an escaped backslash must not turn the next character into an escape")


# --- validation -------------------------------------------------------------------------------------------

func test_validate_accepts_an_ordinary_rewording() -> void:
	assert_eq(Ops.validate("PROMPT_PICK_UP", "Take", "Pick up"), "", "a plain rewording is allowed")


func test_validate_refuses_an_empty_value() -> void:
	var problem := Ops.validate("PROMPT_PICK_UP", "   ", "Pick up")
	assert_ne(problem, "", "an empty constant paints an invisible blank and fails the contract test")
	assert_true(problem.contains("empty"), "the reason should say so plainly, got: %s" % problem)


func test_validate_refuses_a_script_file_name() -> void:
	var problem := Ops.validate("TOAST_OOPS", "see player.gd", "see the log")
	assert_ne(problem, "", "a .gd mention is a dev diagnostic leaking into player copy")


func test_validate_refuses_a_placeholder_marker_with_no_space() -> void:
	assert_ne(Ops.validate("QUEST_TITLE", "[PH]Clear the Block", "[PH] Clear the Block"), "", "the marker needs its space or it stops being recognised")
	assert_eq(Ops.validate("QUEST_TITLE", "[PH] Clear the Block", "[PH] Clear the Block"), "", "the marker with its space is fine")


## The rule no test elsewhere can catch: TextFormat.subst is replace-based, so a dropped token renders as nothing
## instead of erroring.
func test_validate_refuses_dropping_a_substitution_token() -> void:
	var problem := Ops.validate("HUD_OWED", "You owe money.", "You owe {amount}.")
	assert_ne(problem, "", "dropping {amount} would silently render nothing")
	assert_true(problem.contains("{amount}"), "the reason must name the token, got: %s" % problem)
	assert_eq(Ops.validate("HUD_OWED", "{amount} is owed.", "You owe {amount}."), "", "moving a token is fine")


func test_validate_allows_adding_a_token_because_that_failure_is_visible() -> void:
	assert_eq(Ops.validate("HUD_OWED", "You owe {amount} of {total}.", "You owe {amount}."), "", "an extra token renders literally, which is self-correcting")


func test_validate_refuses_losing_a_percent_slot() -> void:
	assert_ne(Ops.validate("DEATH_BY", "Killed.", "Killed by %s."), "", "a legacy %s slot is positional and must survive")


# --- the read-only half -----------------------------------------------------------------------------------

func test_inline_literals_are_found_and_attributed_to_their_function() -> void:
	var found := Ops.inline_literals(FIXTURE)
	assert_eq(found.size(), 1, "the fixture has one inline prose literal, got %d" % found.size())
	assert_eq(String(found[0]["func_name"]), "greeting", "the literal is attributed to the function holding it")
	assert_true(String(found[0]["text"]).begins_with("Evening, {name}"), "the prose itself is reported so a writer can see it")


func test_inline_literals_skip_short_strings_and_keys() -> void:
	var src := "static func f() -> String:\n\treturn TextFormat.subst(TEMPLATE, {\"name\": n})\n"
	assert_eq(Ops.inline_literals(src).size(), 0, "a dictionary key is not prose")


## A ZERO ratchet, the test_player_text baseline idiom: on 2026-09-15 every prose literal that sat inside a
## PlayerText function body was lifted to a `const NAME := "..."` declared directly above its function, so the
## tab edits all of them. A new inline literal is a regression — the writer loses it and the deferred tr() sweep
## cannot wrap it — so this names the offender rather than tolerating it.
func test_the_real_file_has_no_inline_literals_left() -> void:
	var text := FileAccess.get_file_as_string(Ops.SOURCE_PATH)
	var found := Ops.inline_literals(text)
	var names := PackedStringArray()
	for e in found:
		names.append("%s: %s" % [e["func_name"], e["text"]])
	assert_eq(found.size(), 0, "every PlayerText prose template is a const now — lift these out of their function bodies: %s" % [names])


func test_summary_counts_what_is_written_and_what_is_not() -> void:
	var entries := [{"value": "[PH] Unwritten"}, {"value": "Written"}]
	var msg := Ops.summary(entries, 3)
	assert_true(msg.contains("2 lines"), "counts the editable lines, got: %s" % msg)
	assert_true(msg.contains("1 still marked"), "counts the unwritten ones, got: %s" % msg)
	assert_true(msg.contains("3 more lines are"), "counts the code-only ones, got: %s" % msg)


func test_select_path_refuses_anything_but_its_one_file() -> void:
	var d = UiCopyEditor.new()
	assert_false(d.select_path("res://resources/items/healthpack.tres"), "this tab edits one known file only")
	assert_false(d.select_path(Ops.SOURCE_PATH), "off-tree it refuses rather than half-opening")
	d.free()
