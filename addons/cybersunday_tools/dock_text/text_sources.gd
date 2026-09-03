@tool
extends RefCounted

## THE registry of where player-facing TEXT lives across the game's authored content: for each content type, which
## resource folder holds it and which of its fields are editable prose. The unified Text tab (text_editor.gd)
## renders every row here into one editable panel, so a designer edits ALL flavor text in one place instead of
## hopping between two dozen .tres in the Inspector.
##
## FIELD-PRESENCE, not folder-blanket: a folder can hold MIXED resource types (resources/characters/ has NpcData
## AND CharacterAppearanceCatalog AND CharacterStats AND NpcLook). The tab therefore only shows a field on a given
## resource when that resource ACTUALLY has the property — a descriptor row is a hint about where to look, not a
## promise every file in the folder carries every field. So listing a field that some files lack is harmless.
##
## LOCALIZATION-LATER SEAM: this same table is the natural thing a future localization pass iterates to pull every
## authored string into a single translation CSV (Godot tr()/keys). Keep new text-bearing content types registered
## HERE (one row) and both the editor tab and any future exporter pick them up for free.
##
## Fields NOT covered here (by design, for now): text nested inside ARRAYS — quest objective descriptions,
## dialogue lines, bark line lists — which have their own dedicated CYBER SUNDAY editors (Quest Edit / Dialogue
## Edit). The Text tab handles flat, top-level String fields; the nested editors own the array-shaped text.

## Each entry: {
##   "label":  category name shown as the section header,
##   "dir":    res:// folder scanned for .tres,
##   "fields": Array of { "name": <property>, "multiline": <bool>, "label": <designer-facing word> }
##             — a LineEdit when multiline is false, a TextEdit when true. "label" is what the Text tab prints
##             above the widget (the designer reads "Name", never "display_name"); it is OPTIONAL — a row without
##             one degrades through field_label() below, so a hastily added row still reads as words.
## }
const SOURCES: Array = [
	{ "label": "Items", "dir": "res://resources/items/", "fields": [
		{"name": "display_name", "multiline": false, "label": "Name"},
		{"name": "description", "multiline": true, "label": "Description"},
	] },
	{ "label": "Stats", "dir": "res://resources/stats/", "fields": [
		{"name": "display_name", "multiline": false, "label": "Name"},
		{"name": "description", "multiline": true, "label": "Description"},
	] },
	{ "label": "Status Effects", "dir": "res://resources/status/", "fields": [
		{"name": "display_name", "multiline": false, "label": "Name"},
		{"name": "description", "multiline": true, "label": "Description"},
	] },
	{ "label": "Perks", "dir": "res://resources/perks/", "fields": [
		{"name": "display_name", "multiline": false, "label": "Name"},
		{"name": "description", "multiline": true, "label": "Description"},
	] },
	{ "label": "Quests", "dir": "res://resources/quests/", "fields": [
		{"name": "title", "multiline": false, "label": "Title"},
		{"name": "description", "multiline": true, "label": "Description"},
	] },
	{ "label": "Factions", "dir": "res://resources/factions/", "fields": [
		{"name": "display_name", "multiline": false, "label": "Name"},
	] },
	{ "label": "NPCs", "dir": "res://resources/characters/", "fields": [
		{"name": "display_name", "multiline": false, "label": "Name"},
	] },
	{ "label": "Levels", "dir": "res://resources/levels/", "fields": [
		{"name": "display_name", "multiline": false, "label": "Name"},
	] },
]


## The word the Text tab prints above a field's widget: the row's "label" when authored, else the property name
## turned into words ("display_name" -> "Display Name"). The capitalize() here is the missing-label DEGRADE only
## (the same rule as the runtime display-name accessors) — every shipped row above carries a real label, so the
## fallback exists for a future row added in a hurry, not as the normal path. Pure: safe headless and off-tree.
static func field_label(field: Dictionary) -> String:
	var authored: String = String(field.get("label", ""))
	if authored != "":
		return authored
	return String(field.get("name", "")).capitalize()
