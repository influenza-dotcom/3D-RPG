extends GutTest

## The POT parser's pure model (addons/cybersunday_tools/core/translation_extract.gd): which entries a file
## contributes to the translation template. The editor-only shell (core/translation_parser.gd) cannot be
## instantiated headless, so every rule is pinned here on the model it delegates to — plus runs over the REAL
## files, because the whole point is that PlayerText's constants and the catalogs reach the POT.

const Extract := preload("res://addons/cybersunday_tools/core/translation_extract.gd")

const GD_FIXTURE := """class_name PlayerText
extends RefCounted

const PH_PREFIX := "[PH]"
const BACK := "Back"
const PROMPT_PICK_UP := "[PH] Pick Up"
const TWO_LINES := "First\\nSecond"
const QUOTED := "Say \\"hi\\""
const Perks := preload("res://scripts/player/perks.gd")
const ONLY_TOKEN := "{n}"
const BACK_AGAIN := "Back"
const ITEMS_ONE := "{n} item"
const ITEMS_MANY := "{n} items"

static func greeting(name: String) -> String:
	return tr("Evening, {name}.") + atr("And you?")

static func items(n: int) -> String:
	return TextFormat.subst(TextFormat.plural(n,
			ITEMS_ONE,
			ITEMS_MANY),
			{"n": n})
"""

const TRES_FIXTURE := """[gd_resource type="Resource" script_class="Item" format=3]

[resource]
resource_name = "pistol_res"
id = &"pistol"
display_name = "Pistol"
description = "Nine rounds.\\nOne at a time."
icon_path = "res://resources/icons/pistol.png"
paid_message = "Rent paid: {amount}"
title = "[PH] Clear the Block"
metadata/note = "not copy"
value = 120.0
"""

const TSCN_FIXTURE := """[gd_scene format=3]

[sub_resource type="Resource" id="Resource_1"]
text = "You deaf or just dumb, kid?"
speaker_name = "Old Man"

[node name="Talkable" type="Node3D"]
prompt_template = "Talk to {name}"

[node name="Name" type="Label"]
text = ""
tooltip_text = "Your name"
"""


func test_gdscript_constants_and_tr_calls_become_entries() -> void:
	var ids := Extract.msgids(Extract.from_gdscript(GD_FIXTURE))
	assert_eq(Array(ids), ["Back", "First\nSecond", "Say \"hi\"", "{n} item", "Evening, {name}.", "And you?"],
		"consts in declaration order (escapes unwound), then tr()/atr() arguments; placeholders, preloads, bare tokens and duplicates dropped — got %s" % [ids])


func test_a_plural_pair_becomes_one_msgid_plural_entry() -> void:
	var entries := Extract.from_gdscript(GD_FIXTURE)
	var found: PackedStringArray
	for e in entries:
		if e[0] == "{n} item":
			found = e
	assert_eq(Array(found), ["{n} item", "", "{n} items"],
		"the two consts a TextFormat.plural(n, ONE, MANY) call names (even wrapped over lines) are ONE [msgid, context, msgid_plural] entry — translate_plural finds nothing else")
	assert_false(Extract.msgids(entries).has("{n} items"), "the MANY half is never a singular entry of its own")


func test_resource_fields_become_entries_by_name_and_suffix() -> void:
	var ids := Extract.msgids(Extract.from_resource_text(TRES_FIXTURE))
	assert_eq(Array(ids), ["Pistol", "Nine rounds.\nOne at a time.", "Rent paid: {amount}"],
		"display_name/description by name, paid_message by suffix; ids (&\"\"), resource_name, paths, [PH] titles and metadata skipped — got %s" % [ids])


func test_scene_text_fields_including_inline_dialogue_become_entries() -> void:
	var ids := Extract.msgids(Extract.from_resource_text(TSCN_FIXTURE))
	assert_eq(Array(ids), ["You deaf or just dumb, kid?", "Old Man", "Talk to {name}", "Your name"],
		"a dialogue line's text, a speaker_name, a designer prompt_template and a tooltip all count; an empty Label text does not — got %s" % [ids])


func test_dispatch_by_extension() -> void:
	assert_eq(Extract.for_path("res://x/y.gd", GD_FIXTURE).size(), 6, ".gd goes through the script rules")
	assert_eq(Extract.for_path("res://x/y.tres", TRES_FIXTURE).size(), 3, ".tres goes through the field rules")
	assert_eq(Extract.for_path("res://x/y.tscn", TSCN_FIXTURE).size(), 4, ".tscn goes through the field rules")
	assert_eq(Extract.for_path("res://x/y.png", "junk").size(), 0, "an unknown extension contributes nothing")


func test_is_translatable_rules() -> void:
	assert_false(Extract.is_translatable(""), "blank")
	assert_false(Extract.is_translatable("   "), "whitespace")
	assert_false(Extract.is_translatable("[PH] Draft"), "a placeholder is unauthored")
	assert_false(Extract.is_translatable("res://scenes/x.tscn"), "a path")
	assert_false(Extract.is_translatable("uid://abc"), "a uid")
	assert_false(Extract.is_translatable("{n} / %s — "), "no letter: tokens and separators only")
	assert_false(Extract.is_translatable("{amount}"), "a lone token's NAME is not a word")
	assert_false(Extract.is_translatable("%.2f%%"), "a lone format specifier is not a word")
	assert_true(Extract.is_translatable("{amount} zm"), "a template with a word is copy")
	assert_true(Extract.is_translatable("Rent: %d"), "a sentence around a specifier is copy")
	assert_true(Extract.is_translatable("Retour"), "a plain word is copy")


func test_the_real_player_text_contributes_its_constants_and_no_placeholder() -> void:
	var text := FileAccess.get_file_as_string("res://scripts/ui/player_text.gd")
	var entries := Extract.from_gdscript(text)
	var ids := Extract.msgids(entries)
	assert_gt(ids.size(), 250, "hundreds of authored consts reach the POT (got %d)" % ids.size())
	assert_true(ids.has("Back"), "an unmarked const is a msgid")
	var plurals := 0
	for e in entries:
		if e.size() == 3:
			plurals += 1
	assert_gt(plurals, 0, "the real file's TextFormat.plural pairs come out as msgid_plural entries")
	var leaked := PackedStringArray()
	for id in ids:
		if id.contains("[PH]"):
			leaked.append(id)
	assert_eq(leaked.size(), 0, "no [PH] placeholder is ever sent to a translator: %s" % [leaked])


func test_the_real_catalogs_contribute_their_labels() -> void:
	var settings := Extract.msgids(Extract.for_path("res://resources/settings/SettingsCatalog.tres",
		FileAccess.get_file_as_string("res://resources/settings/SettingsCatalog.tres")))
	assert_true(settings.has("Window Mode"), "an Options row label is a msgid")
	assert_true(settings.has("Language"), "…including the Language row itself")
	var actions := Extract.msgids(Extract.for_path("res://resources/input/ActionCatalog.tres",
		FileAccess.get_file_as_string("res://resources/input/ActionCatalog.tres")))
	assert_gt(actions.size(), 20, "the keybind row labels reach the POT (got %d)" % actions.size())
