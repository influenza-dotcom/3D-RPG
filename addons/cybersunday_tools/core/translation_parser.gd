@tool
extends EditorTranslationParserPlugin

## Feeds Godot's own POT generator (Project Settings → Localization → POT Generation) the message ids the engine
## cannot see on its own: PlayerText's `const NAME := "…"` copy and the authored fields of `.tres` / `.tscn`
## resources (item names, descriptions, quest titles, catalog labels, designer `{token}` templates, inline
## dialogue lines). Registered by plugin.gd (add_translation_parser_plugin) — so with the CYBER SUNDAY plugin on,
## adding `scripts/ui/player_text.gd` and the content files to the POT panel's file list and pressing Generate
## POT writes a complete template; a translator returns `translations/<locale>.po`, which goes under
## Localization → Translations. No custom export tool.
##
## ⭐A custom parser REPLACES the engine's own for every extension it claims. Claiming `gd` means this parser
## must also extract `tr("…")` calls (it does — translation_extract.gd TR_CALL_RE); claiming `tscn` means the
## engine's PackedScene parser (Control `text` / `tooltip_text`, honouring auto_translate_mode) is replaced by
## the field scan in translation_extract.gd, which reads the same properties plus the authored ones the engine
## skips. An atr opt-out Control's DEFAULT text (usually empty) may therefore appear in the POT — harmless.
##
## Everything that decides WHAT is a msgid lives in core/translation_extract.gd (pure, tested); this class is
## the thin editor-only shell — EditorTranslationParserPlugin cannot be instantiated headless, so it carries
## no logic a test would need.

const Extract := preload("res://addons/cybersunday_tools/core/translation_extract.gd")


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["gd", "tres", "tscn"])


func _parse_file(path: String) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return out
	for msgid in Extract.for_path(path, text):
		out.append(PackedStringArray([msgid]))
	return out
