extends GutTest

## SaveLoadScreen (the player-facing manual save/load slot menu, scripts/ui/save_load_screen.gd) — narrow
## OFF-TREE pins in the suite's idiom: the script loads and exposes the modal surface (open/close/is_open),
## the pure slot_metadata helper degrades gracefully on a missing/blank file, and the PlayerText consts +
## whole templates its rows paint exist and substitute via TextFormat (never the % operator). The in-tree
## behaviour (mouse modes, modal exclusion, the quickload scene-reload sweep) rides the shared InputManager
## registry — pinned by tests/test_modal_registry.gd.
##
## The last two tests are the exception and drive the LIVE autoload (whose _ready already ran _bind_ui): the
## exit row and the per-row button rail are CODE-BUILT, so the scene-wiring suite cannot see them at all and
## a regression in either would surface only as a screenshot nobody took. They read structure, never pixels —
## the visual layout itself is still playtested.

const SCREEN_PATH := "res://scripts/ui/save_load_screen.gd"
const TMP_SAVE := "user://test_saveloadscreen_tmp.cfg"
const TMP_MISSING := "user://test_saveloadscreen_definitely_absent.cfg"


func after_each() -> void:
	for f in [TMP_SAVE, TMP_MISSING]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func test_screen_script_loads_and_exposes_modal_surface() -> void:
	# Method-surface pin WITHOUT entering the tree (the UI builds in _ready; an autoload screen is never
	# unit-instanced in-tree — the prefab-wiring idiom). open/close/is_open is the modal-registry contract
	# (InputManager drives them duck-typed); slot_metadata is the pure display seam pinned below.
	var script: GDScript = load(SCREEN_PATH)
	assert_not_null(script, "save_load_screen.gd should load (a parse error would null this)")
	var names: Array = []
	for m in script.get_script_method_list():
		names.append(String(m.get("name", "")))
	for required in ["open", "close", "is_open", "slot_metadata"]:
		assert_has(names, required, "SaveLoadScreen exposes %s()" % required)


func test_fresh_instance_starts_closed() -> void:
	# Off-tree .new(): _ready never runs, so this pins only the pure default state, not any UI construction.
	var screen = load(SCREEN_PATH).new()
	assert_false(screen.is_open(), "a fresh SaveLoadScreen reports closed")
	screen.free()


func test_slot_metadata_missing_file_is_graceful() -> void:
	# The Empty-row path: a nonexistent file must report exists = false with blank facts — never an error,
	# never a half-filled dict the row painter would render as garbage.
	assert_false(FileAccess.file_exists(TMP_MISSING), "precondition: the temp path has no file")
	var meta: Dictionary = load(SCREEN_PATH).slot_metadata(TMP_MISSING)
	assert_false(bool(meta["exists"]), "a missing file reports exists = false")
	assert_eq(String(meta["level_name"]), "", "...with a blank level name")
	assert_eq(String(meta["time_text"]), "", "...and a blank time")


func test_slot_metadata_reads_a_real_file() -> void:
	# A real (level-less) cfg: exists = true, a formatted modified time, and the blank level degrade — the
	# caption then selects the time-only whole template (save_slot_caption, pinned below).
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	assert_eq(cfg.save(TMP_SAVE), OK, "precondition: the temp save wrote")
	var meta: Dictionary = load(SCREEN_PATH).slot_metadata(TMP_SAVE)
	assert_true(bool(meta["exists"]), "an existing file reports exists = true")
	assert_ne(String(meta["time_text"]), "", "an existing file carries a formatted modified time")
	assert_eq(String(meta["level_name"]), "", "no [level] section -> blank level name (caption degrades to time-only)")


func test_player_text_consts_exist_and_are_nonempty() -> void:
	# The screen's painted surface — every const it (and its two launch buttons) reads must exist and be
	# non-empty. Reflected off the script like test_player_text.gd, so a renamed const fails HERE by name
	# instead of as a mystery blank label in a playtest.
	var script: GDScript = load("res://scripts/ui/player_text.gd")
	var consts: Dictionary = script.get_script_constant_map()
	for cname in ["SAVE_LOAD_TITLE", "SAVE_LOAD_QUICKSAVE_ROW", "SAVE_LOAD_SLOT", "SAVE_LOAD_EMPTY",
			"SAVE_LOAD_SAVE", "SAVE_LOAD_LOAD", "SAVE_LOAD_OVERWRITE_TITLE", "SAVE_LOAD_SAVE_FAILED",
			"SAVE_LOAD_LOAD_FAILED", "SAVE_SLOT_CAPTION", "SAVE_SLOT_CAPTION_NO_LEVEL",
			"START_MENU_LOAD_GAME", "OPTIONS_SAVE_LOAD", "BACK"]:
		assert_true(consts.has(cname), "PlayerText.%s exists (the SaveLoadScreen paints it)" % cname)
		assert_ne(String(consts.get(cname, "")), "", "PlayerText.%s is non-empty" % cname)


func test_slot_label_template_substitutes() -> void:
	# The {n} token substitutes via TextFormat.subst (replace-based — a literal '%' in a reworded template can
	# never error) and the composed label carries the number, with no unfilled token left visible.
	var label := PlayerText.save_slot_label(2)
	assert_eq(label, TextFormat.subst(PlayerText.SAVE_LOAD_SLOT, {"n": 2}), "save_slot_label IS the whole SAVE_LOAD_SLOT template")
	assert_true(label.contains("2"), "the slot number lands in the label")
	assert_false(label.contains("{n}"), "the {n} token was substituted, not left visible")


func test_slot_caption_selects_whole_templates() -> void:
	# TWO whole templates selected on has-level (THE RULE: selection between templates, never a fragment
	# spliced around a dangling separator when the level name is blank).
	var full := PlayerText.save_slot_caption("Downtown", "2026-07-29 12:00:00")
	assert_eq(full, TextFormat.subst(PlayerText.SAVE_SLOT_CAPTION, {"level": "Downtown", "time": "2026-07-29 12:00:00"}),
		"a resolvable level name selects the level+time template")
	assert_true(full.contains("Downtown"), "the level name lands in the caption")
	assert_true(full.contains("2026-07-29 12:00:00"), "the time lands in the caption")
	var bare := PlayerText.save_slot_caption("", "2026-07-29 12:00:00")
	assert_eq(bare, TextFormat.subst(PlayerText.SAVE_SLOT_CAPTION_NO_LEVEL, {"time": "2026-07-29 12:00:00"}),
		"a blank level name selects the time-only whole template (no orphaned separator)")


# --- The code-built chrome (driven on the LIVE autoload, whose _ready already ran _bind_ui) ------------------
# Both pins below are code-built and therefore invisible to the scene-wiring suite: the .tscn authors neither
# the Back row nor the row rails, so a regression there would show up only as a screenshot nobody took.

func test_a_back_button_is_pinned_under_the_status_line() -> void:
	# The screen used to have NO way out at all: reached from the start menu with the cursor free, every button
	# on the panel acted on a slot, and nothing said Escape worked — so a mouse-only player with no save to load
	# was stranded on the modal. The exit row is code-built into the authored %VBox (the scene carries no text),
	# and it must stay the LAST child so it sits below the status line rather than between the rows and it.
	var vbox := SaveLoadScreen.get_node("%VBox") as VBoxContainer
	var last := vbox.get_child(vbox.get_child_count() - 1)
	assert_true(last is HBoxContainer, "the pinned exit row is the panel's last child (under %Status)")
	var back: Button = null
	for c in last.get_children():
		if c is Button:
			back = c as Button
	assert_not_null(back, "the exit row carries a Button")
	assert_eq(back.text, PlayerText.BACK, "captioned from PlayerText.BACK, like every sibling screen's exit")
	assert_eq(back.custom_minimum_size.x, float(MenuStyle.skin.dialog_button_min_width),
		"it wears the shared dialog button width, so the row matches every other menu's")
	assert_true(back.pressed.is_connected(SaveLoadScreen.close), "pressing it closes the screen")
	assert_eq(String(back.get_meta(&"_snd_semantic", "click")), "",
		"its generic click is MUTED — close() already fires play_back() for both the mouse and the Escape path")


func test_menu_mode_rows_skip_the_save_cell_so_the_caption_keeps_its_width() -> void:
	# In MENU mode no row can ever carry a Save button (there is no player to capture), so _add_rail_cell's
	# same-width spacer — which buys COLUMN ALIGNMENT between rows whose affordances differ — has nothing to
	# align, and the ~170px it reserved is what squeezed the metadata caption (level name + timestamp, the only
	# thing telling two saves apart) down to ~90px and ellipsised it to "Abb…". Driven through _rebuild rather
	# than open(), which would grab the mouse and cue the whole modal for a layout question.
	var list := SaveLoadScreen.get_node("%List") as VBoxContainer
	SaveLoadScreen._in_game = false
	SaveLoadScreen._rebuild()
	var menu_rows := _live_rows(list)
	assert_gt(menu_rows.size(), 0, "precondition: the repaint built the quicksave + slot rows")
	for row in menu_rows:
		assert_eq((row as HBoxContainer).get_child_count(), 3,
			"a menu-mode row is name | caption | [Load-or-spacer] — no Save cell at all")
	SaveLoadScreen._in_game = true
	SaveLoadScreen._rebuild()
	for row in _live_rows(list):
		assert_eq((row as HBoxContainer).get_child_count(), 4,
			"in-game the two-cell rail is unchanged (a missing Save still spaces, so the columns hold)")
	# Leave the shared autoload in its default (menu) shape — open() re-sets the mode either way.
	SaveLoadScreen._in_game = false
	SaveLoadScreen._rebuild()


## The rows _rebuild just BUILT. queue_free() does not unparent until the end of the frame, so a repaint
## driven synchronously (as above) leaves the previous paint's rows still hanging in %List — counting raw
## children here would measure both paints at once and fail for the wrong reason.
func _live_rows(list: VBoxContainer) -> Array:
	var out: Array = []
	for c in list.get_children():
		if not c.is_queued_for_deletion():
			out.append(c)
	return out
