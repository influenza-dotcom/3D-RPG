extends GutTest

## The Tuning browser tab (Tune group) -- the tab constructs (compile-check, since --import skips addon-only
## scripts), and the PURE helpers behind it are pinned headless: the folder scan (_scan_tuning), the row label a
## designer reads (_display_name), and the search that finds a GROUP by the name of a SETTING it holds
## (_match_props / _matches_name). EditorInterface / edit_resource is editor-only and is NOT exercised here (it
## can't run headless), so the double-click jump to the Inspector stays a manual check.

const TuningBrowser := preload("res://addons/cybersunday_tools/dock_tuning/tuning_browser.gd")


## The scanned row for a tuning file stem ("EconomySettings"), or {} when the folder no longer holds it.
func _row_named(stem: String) -> Dictionary:
	for r in TuningBrowser._scan_tuning():
		if String(r.get("name", "")) == stem:
			return r
	return {}


func test_tuning_browser_constructs() -> void:
	var d = TuningBrowser.new()
	assert_not_null(d, "tuning browser should construct (compiles + _init builds its UI off-tree)")
	assert_eq(d.name, "Tuning", "dock tab name")
	assert_eq(d._status.text, TuningBrowser.MSG_IDLE, "the idle status is the one imperative next step")
	assert_eq(d._status.tooltip_text, d._status.text, "the status tooltip mirrors the full text on every write")
	assert_eq(d._status.max_lines_visible, 2, "the status clamps to two lines (a long group description rides the tooltip)")
	assert_eq(d._status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "and autowraps")
	assert_eq(d._refresh_btn.tooltip_text, TuningBrowser.REFRESH_TIP, "the one command explains itself, and says it is read-only")
	assert_lte(d._list.custom_minimum_size.y, 120.0, "the group list's floor stays small -- one tall tab leaves the shared panel tall")
	assert_false(d._revealed, "no folder scan at construction -- the first reveal does it")
	d.free()


## Nothing picked: both click handlers land on the same sentence rather than describing a stale row.
func test_no_pick_says_what_to_do_instead_of_describing_a_stale_row() -> void:
	var d = TuningBrowser.new()
	d._on_selected(4)  # a row index the (empty) list never had
	assert_eq(d._status.text, TuningBrowser.MSG_NO_PICK, "a stale row index reads as 'nothing picked'")
	assert_eq(d._status.tooltip_text, d._status.text, "mirrored onto the tooltip")
	d._on_empty_clicked(Vector2.ZERO, MOUSE_BUTTON_LEFT)
	assert_eq(d._status.text, TuningBrowser.MSG_IDLE, "clicking below the rows returns to the idle next step")
	d.free()


func test_scan_tuning_returns_real_tres() -> void:
	var rows := TuningBrowser._scan_tuning()
	assert_gt(rows.size(), 0, "resources/tuning/ should yield at least one tuning group")
	for r in rows:
		var path := String(r.get("path", ""))
		assert_true(path.ends_with(".tres") or path.ends_with(".res"), "every row points at a real resource file: %s" % path)
		assert_true(FileAccess.file_exists(path), "the scanned path exists on disk: %s" % path)
		assert_true(r.get("res") is Resource, "every row carries a loaded Resource (for edit_resource): %s" % path)
		assert_ne(String(r.get("name", "")), "", "every row has a display name")


func test_scan_tuning_includes_known_gamesettings_group() -> void:
	# EconomySettings.tres is a GameSettings group (GameSettings.economy) and lives in resources/tuning/.
	var rows := TuningBrowser._scan_tuning()
	var names: Array[String] = []
	for r in rows:
		names.append(String(r.get("name", "")))
	assert_true(names.has("EconomySettings"), "the browser lists the EconomySettings tuning group; got %s" % str(names))


func test_scan_tuning_describes_by_class_name() -> void:
	var rows := TuningBrowser._scan_tuning()
	var found_economy := false
	for r in rows:
		if String(r.get("name", "")) == "EconomySettings":
			found_economy = true
			assert_eq(String(r.get("desc", "")), "EconomySettings", "the row description is the resource's class_name")
	assert_true(found_economy, "EconomySettings row present to check its description")


## Every scanned row carries what the tab shows: a display label, the group's own settings (what the search matches
## on) and the group's header paragraph (what a click reads into the status). Checked on a real shipped group.
func test_scan_rows_carry_label_settings_and_description() -> void:
	var eco := _row_named("EconomySettings")
	if eco.is_empty():
		pass_test("EconomySettings is no longer in resources/tuning -- nothing to pin here")
		return
	assert_eq(String(eco.get("label", "")), "Economy", "the row label drops the shared 'Settings' suffix -- no row reads the same word twice")
	var props: PackedStringArray = eco.get("props", PackedStringArray())
	assert_true(props.has("kill_bounty"), "the group's own @export settings are listed (that IS the search index): %s" % str(props))
	assert_false(props.has("resource_name"), "Resource's own properties are not settings of the group")
	assert_true(String(eco.get("summary", "")).begins_with("The economy's designer knobs"),
		"the group's header paragraph is what a click reads into the status: %s" % String(eco.get("summary", "")))


# --- pure row helpers ---------------------------------------------------------------------------------------------

func test_display_name_reads_as_words_not_a_class_name() -> void:
	assert_eq(TuningBrowser._display_name("EconomySettings"), "Economy", "the shared suffix is dropped")
	assert_eq(TuningBrowser._display_name("PlayerMovementSettings"), "Player Movement", "PascalCase is split into words")
	assert_eq(TuningBrowser._display_name("NpcAiSettings"), "NPC AI", "acronyms are spelled the way a designer writes them")
	assert_eq(TuningBrowser._display_name("punch_strike_curve"), "Punch Strike Curve", "a file without the suffix keeps its whole stem")
	assert_eq(TuningBrowser._display_name("Settings"), "Settings", "a stem that IS the suffix is left alone rather than blanked")


## The reported bug this search exists for: a designer hunting "which page holds the kill bounty?" types part of the
## SETTING's name, and the group that carries it surfaces.
func test_search_finds_a_group_by_a_setting_it_holds() -> void:
	var entry := {
		"label": "Economy", "name": "EconomySettings", "desc": "EconomySettings",
		"props": PackedStringArray(["kill_bounty", "headshot_kill_bounty", "shop_markup"]),
	}
	assert_eq(TuningBrowser._match_props(entry, "bounty"), PackedStringArray(["kill_bounty", "headshot_kill_bounty"]),
		"a partial setting name matches every setting that holds it")
	assert_eq(TuningBrowser._match_props(entry, "kill bounty"), PackedStringArray(["kill_bounty", "headshot_kill_bounty"]),
		"a typed space reads as an underscore, so 'kill bounty' finds kill_bounty")
	assert_true(TuningBrowser._match_props(entry, "").is_empty(), "a blank search matches by NAME only, so rows stay clean")
	assert_true(TuningBrowser._match_props(entry, "nothing_here").is_empty(), "a miss is a miss")


func test_name_search_ignores_spaces_underscores_and_case() -> void:
	var entry := {"label": "Player Movement", "name": "PlayerMovementSettings", "desc": "PlayerMovementSettings", "props": PackedStringArray()}
	for query in ["player movement", "playermovement", "PlayerMovementSettings", "MOVEMENT"]:
		assert_true(TuningBrowser._matches_name(entry, query), "'%s' should find Player Movement" % query)
	assert_true(TuningBrowser._matches_name(entry, ""), "a blank query matches every group")
	assert_false(TuningBrowser._matches_name(entry, "economy"), "another group's name does not match")


## The engine-side names (class name + file path) live on the row's hover text, never in the row a designer reads.
func test_row_tooltip_carries_the_path_and_the_matches() -> void:
	var entry := {"label": "Economy", "name": "EconomySettings", "desc": "EconomySettings", "path": "res://resources/tuning/EconomySettings.tres"}
	var tip := TuningBrowser._row_tooltip(entry, PackedStringArray(["kill_bounty"]))
	assert_true(tip.contains("EconomySettings.tres"), "the file the row points at is one hover away: %s" % tip)
	assert_true(tip.contains("Matching settings: kill_bounty"), "and so is every setting the search reached it through")
	assert_false(TuningBrowser._row_tooltip(entry, PackedStringArray()).contains("Matching settings"),
		"with no search hit the tooltip stays the class name + path")


func test_count_uses_a_real_plural() -> void:
	assert_eq(TuningBrowser._count(1, "group", "groups"), "1 group")
	assert_eq(TuningBrowser._count(0, "group", "groups"), "0 groups")
	assert_eq(TuningBrowser._count(3, "group", "groups"), "3 groups")
