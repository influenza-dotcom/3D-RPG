extends Translation

## RUNTIME-ONLY "[PH]" scrub. MenuStyle._enter_tree registers ONE instance with the TranslationServer (and _exit_tree / delete removes it — it must not outlive the script system). Godot's automatic
## Control-text translation (atr) asks the active locale's Translation for every Label / Button / tooltip / tab
## title / OptionButton item / Label3D string the moment it is painted; this one answers with the string minus
## its "[PH]" markers and stays SILENT (&"" = no entry, the engine hands back the source) for everything else —
## so unmarked copy is still identity, and a real catalog can sit beside it later.
##
## What this is NOT: a change to any source string. PlayerText consts and .tres/.tscn fields KEEP the marker —
## text_debt, the AI-text scrub, test_player_text and every editor surface still see it (autoloads never run in
## the editor, so @tool previews and the Text tab show "[PH]" exactly as authored). A Control's `.text` PROPERTY
## also keeps the marker (tests compare that); only the RENDERED glyphs lose it. The surfaces that opt OUT of
## atr (auto_translate_mode DISABLED, for player-typed text: the look readout, toasts, the tooltip, hotbar
## names) and the ones that draw_string themselves (GridTile, HudCompass, Minimap) call PlayerText.display().
## Engine-probed 2026-09-12 on 4.7.2: a GDScript _get_message override IS consulted by TranslationServer.translate,
## and both Label.atr and Label3D.atr return the scrubbed string.

func _init() -> void:
	# Exact-locale entry: the scrub must be THE translation for whatever locale the OS reports, or the server
	# would skip it for a non-English machine and paint the marker there.
	locale = TranslationServer.get_locale()

func _get_message(src_message: StringName, _context: StringName) -> StringName:
	var s := String(src_message)
	if not s.contains(PlayerText.PH_PREFIX):
		return &""
	return StringName(PlayerText.display(s))
