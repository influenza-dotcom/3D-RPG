extends GutTest

## Localization (scripts/ui/localization.gd) — the locale seam — and the three things that hang off it:
## TextFormat translating a template BEFORE substituting, the "[PH]" scrub following a locale switch
## (MenuStyle.relocate_scrub), and Settings.language degrading an unknown code to System.
##
## Every test builds its own throw-away catalog for a fake locale ("xx"), registers it with the server, and
## after_each removes it and restores the locale + Settings.language it found — the one-file-red-in-the-full-
## run class of bug is a dirty global, and TranslationServer is as global as it gets. Settings persistence is
## switched off for the duration (the test_settings idiom) so nothing here touches the real settings.cfg.

const XX := "xx"

var _prev_locale: String
var _prev_language: String
var _cat: Translation


func before_each() -> void:
	_prev_locale = TranslationServer.get_locale()
	_prev_language = Settings.language
	Settings._loaded = false
	_cat = Translation.new()
	_cat.locale = XX
	_cat.add_message("Back", "Retour")
	_cat.add_message("Hello {name}!", "Salut {name} !")
	_cat.add_message("[PH] Pick Up", "NEVER SHOWN")  # a catalog line for a placeholder must be unreachable
	_cat.add_plural_message("{n} item", PackedStringArray(["{n} objet", "{n} objets"]))
	TranslationServer.add_translation(_cat)


func after_each() -> void:
	TranslationServer.remove_translation(_cat)
	_cat = null
	TranslationServer.set_locale(_prev_locale)
	MenuStyle.relocate_scrub()
	Settings.language = _prev_language
	Settings._loaded = true


func test_marker_mirrors_player_text() -> void:
	assert_eq(Localization.PH_MARK, PlayerText.PH_PREFIX,
		"Localization mirrors the placeholder marker instead of naming PlayerText (reference-cycle guard) — keep them equal")


func test_t_is_identity_without_a_catalog_line() -> void:
	assert_eq(Localization.t("No catalog has this line"), "No catalog has this line", "an unknown msgid comes back as itself")
	assert_eq(Localization.t(""), "", "empty stays empty")


func test_t_translates_under_the_active_locale() -> void:
	Localization.apply(XX)
	assert_eq(TranslationServer.get_locale(), XX, "apply switches the server's locale")
	assert_eq(Localization.t("Back"), "Retour", "a catalog line is returned in the active locale")


func test_subst_translates_the_template_before_substituting() -> void:
	Localization.apply(XX)
	assert_eq(TextFormat.subst("Hello {name}!", {"name": "Bob"}), "Salut Bob !",
		"TextFormat.subst looks the WHOLE template up first, then fills the translator's tokens")


func test_plural_uses_the_catalog_forms_and_falls_back_to_english_shape() -> void:
	Localization.apply(XX)
	assert_eq(TextFormat.plural(1, "{n} item", "{n} items"), "{n} objet", "count 1 takes the catalog's first form")
	assert_eq(TextFormat.plural(2, "{n} item", "{n} items"), "{n} objets", "count 2 takes the catalog's second form")
	assert_eq(TextFormat.plural(2, "{n} thing", "{n} things"), "{n} things",
		"a pair with no catalog entry falls back to the English rule (the engine's own fallback)")
	assert_eq(TextFormat.plural(1, "{n} thing", "{n} things"), "{n} thing", "…singular at exactly one")


func test_placeholders_are_never_translated() -> void:
	Localization.apply(XX)
	assert_eq(Localization.t("[PH] Pick Up"), "[PH] Pick Up",
		"a [PH] msgid is never looked up, even when a catalog (wrongly) carries a line for it")
	assert_eq(TextFormat.subst("[PH] Pick Up {name}", {"name": "the bag"}), "[PH] Pick Up the bag",
		"a placeholder template keeps its marker on the composed string — the scrub strips it only on paint")
	assert_eq(TextFormat.plural(2, "[PH] {n} thing", "[PH] {n} things"), "[PH] {n} things",
		"a placeholder plural pair takes the English rule without a lookup")


func test_auto_translated_controls_read_the_catalog_and_the_scrub_follows_the_locale() -> void:
	Localization.apply(XX)
	var l := Label.new()
	add_child_autofree(l)
	l.text = "Back"
	assert_eq(l.atr(l.text), "Retour", "an auto-translated Control reads the catalog through the engine's own atr")
	assert_eq(l.atr(PlayerText.PROMPT_PICK_UP), PlayerText.display(PlayerText.PROMPT_PICK_UP),
		"the [PH] scrub still answers under the new locale — MenuStyle.relocate_scrub re-keyed it")
	assert_true(TranslationServer.get_loaded_locales().has(XX), "the catalog is registered under its locale")


func test_system_language_follows_the_os_locale() -> void:
	Localization.apply(XX)
	Localization.apply(Localization.SYSTEM)
	assert_eq(TranslationServer.get_locale(), TranslationServer.standardize_locale(OS.get_locale()),
		"SYSTEM re-asserts the OS locale the engine booted with")


func test_available_locales_start_from_the_source_and_come_from_project_settings() -> void:
	var locales := Localization.available_locales()
	assert_eq(locales[0], Localization.source_locale(), "the source locale (Godot's fallback) is always offered first")
	assert_false(locales.has(XX),
		"a catalog registered at runtime is NOT a shipped language — only Project Settings → Localization → Translations counts")
	assert_eq(Localization.locale_label("fr"), "French", "captions are the engine's own language names")


func test_settings_language_round_trips_and_degrades_an_unknown_code() -> void:
	Settings.set_language(Localization.source_locale())
	assert_eq(Settings.language, Localization.source_locale(), "a shipped locale is accepted")
	assert_eq(TranslationServer.get_locale(), Localization.source_locale(), "…and applied at once")
	Settings.set_language(XX)
	assert_eq(Settings.language, Localization.SYSTEM,
		"a locale with no shipped catalog degrades to System instead of stranding the player")
	Settings.set_language("not-a-locale")
	assert_eq(Settings.language, Localization.SYSTEM, "junk degrades to System too")
