class_name Localization
extends RefCounted

## THE LOCALE SEAM — the one place game code asks the TranslationServer anything. Pure statics, no state.
##
## How a string reaches the screen in another language:
##   • An auto-translated Control (`label.text = PlayerText.X`) is translated by the engine itself (atr) through
##     the catalogs listed in Project Settings → Localization → Translations. No code involved.
##   • A COMPOSED string (`TextFormat.subst(TEMPLATE, tokens)`) is translated HERE, template-first, then
##     substituted — `TextFormat.subst` / `TextFormat.plural` call `t` / `t_plural`, so every PlayerText function
##     and every designer-authored `{token}` template is covered without a call-site edit. The composed result
##     is then painted either through atr (a lookup miss on the composed text — identity) or through an atr
##     opt-out surface that calls `PlayerText.display` (the "[PH]" scrub; the toast painter also calls `t` first
##     so a BARE const toast resolves its catalog line).
##   • The "[PH]" placeholder scrub (`scripts/ui/placeholder_translation.gd`, registered by MenuStyle) keeps
##     working in every locale: `apply` re-keys it to the active locale (MenuStyle.relocate_scrub) because the
##     server matches a Translation by its `locale` field.
##
## Placeholders are NEVER translated: a "[PH]"-marked string is unauthored copy, so `t` returns it untouched
## (and the POT parser never extracts it — see addons/cybersunday_tools/core/translation_extract.gd). That is also
## what keeps the marker on the `.text` PROPERTY of a composed string (tests compare it) — the scrub strips it
## only on the way to the glyphs.
##
## Catalogs: Godot's own. Generate the POT (Project Settings → Localization → POT Generation — the CYBER SUNDAY
## plugin's parser adds PlayerText's constants and every authored `.tres`/`.tscn` field), translate it into
## `translations/<locale>.po`, add the `.po` under Localization → Translations. The Options → Game → Language row
## lists exactly those catalogs (`available_locales`). No project.godot edit is needed beyond the panel.

## `Settings.language` value meaning "follow the OS locale" — the default, and the degrade for an unknown code.
const SYSTEM := ""

## The placeholder marker, mirrored from PlayerText.PH_PREFIX (pinned equal by tests/test_localization.gd).
## Mirrored rather than referenced so this script names NO class_name — PlayerText already names TextFormat,
## which names this; a third edge would close a parse-time reference cycle (the recurred trap).
const PH_MARK := "[PH]"

## The ProjectSettings keys this seam reads. Both are the engine's own (the Localization panel writes them).
const CATALOGS_SETTING := "internationalization/locale/translations"
const FALLBACK_SETTING := "internationalization/locale/fallback"


## `msg` in the active locale, or `msg` itself when no catalog carries it (the engine's own fallback) or when it
## is a "[PH]" placeholder (never looked up). Empty stays empty.
static func t(msg: String) -> String:
	if msg.is_empty() or msg.contains(PH_MARK):
		return msg
	return String(TranslationServer.translate(msg))


## The plural form of a counted template — the tr_n() seam TextFormat.plural was always waiting for. A catalog
## may carry ANY number of forms (Russian 3, Arabic 6): the engine picks by its locale's plural rule. With no
## catalog entry the engine falls back to the English shape (`one` when n == 1, else `many`), and a
## placeholder pair takes that same rule without a lookup. A negative count picks by its MAGNITUDE (CLDR plural
## rules are defined on the absolute value, so "-1" reads like "1"), and the engine rejects n < 0 outright.
static func t_plural(one: String, many: String, n: int) -> String:
	var magnitude := absi(n)
	if one.contains(PH_MARK) or many.contains(PH_MARK):
		return one if magnitude == 1 else many
	return String(TranslationServer.translate_plural(one, many, magnitude))


## The locale the source strings are written in — Godot's fallback locale ("en" here).
static func source_locale() -> String:
	return String(ProjectSettings.get_setting(FALLBACK_SETTING, "en"))


## Every locale the player can pick: the source locale first, then one entry per catalog listed under Project
## Settings → Localization → Translations (deduplicated, catalog order). Read from ProjectSettings, NOT from
## TranslationServer.get_loaded_locales(): the "[PH]" scrub is registered under whatever locale the OS reports,
## which would otherwise list, say, "de" as a language with no German in it.
static func available_locales() -> PackedStringArray:
	var out := PackedStringArray([source_locale()])
	var paths: PackedStringArray = ProjectSettings.get_setting(CATALOGS_SETTING, PackedStringArray())
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var res := load(path)
		if res is Translation and not out.has(res.locale):
			out.append(res.locale)
	return out


## The engine's own English name for a locale code ("fr" -> "French") — the Language row's captions.
static func locale_label(code: String) -> String:
	return TranslationServer.get_locale_name(code)


## Switch the game to `code` (SYSTEM = the OS locale) and re-key the "[PH]" scrub to it. Every auto-translated
## Control repaints on the engine's own translation-changed notification; composed strings already on screen
## keep their text until they are next painted.
static func apply(code: String) -> void:
	TranslationServer.set_locale(OS.get_locale() if code == SYSTEM else code)
	_relocate_scrub()


## MenuStyle owns the scrub's lifetime (it must leave the server before the script system shuts down — see
## menu_style.gd); this only asks it to follow the locale. Duck-typed through the tree so this script names no
## autoload: off-tree (a bare test, a tool script) there is nothing to relocate.
static func _relocate_scrub() -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return
	var menu_style := loop.root.get_node_or_null(^"MenuStyle")
	if menu_style != null and menu_style.has_method(&"relocate_scrub"):
		menu_style.relocate_scrub()
