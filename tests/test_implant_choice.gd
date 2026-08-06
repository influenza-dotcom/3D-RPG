extends GutTest

## BEHAVIOUR for the free-implant step (implant_choice.gd) + its StartMenu flow seams. The screen goes
## IN-TREE via add_child_autofree of the AUTHORED scene (its _ready runs _bind_ui + builds the roster; a
## bare-script .new() would null-deref the %binds — the test_character_creation idiom). The StartMenu seams
## are driven directly on a start_menu instance WITHOUT booting: _stamp_new_game_profile is split from
## _on_implant_confirmed precisely so the reset+stamp is testable without _start_game. Scene wiring lives in
## tests/test_implant_choice_scene.gd.

const SCENE := "res://scenes/ui/implant_choice.tscn"
const START_MENU_SCENE := "res://scenes/start_menu.tscn"
const ABILITY_REGISTRY := "res://scripts/components/abilities/ability_registry.gd"

# _make_menu forces the Settings boot flags, so snapshot/restore them around EVERY test (the
# test_start_menu.gd idiom) — a later suite's save_settings() flush would otherwise persist the forced
# values to the dev's real settings.cfg (recording TOS consent / clearing debug_skip_menu on disk).
var _prev_skip: bool
var _prev_tos: bool

func before_each() -> void:
	_prev_skip = Settings.debug_skip_menu
	_prev_tos = Settings.tos_accepted

func after_each() -> void:
	Settings.debug_skip_menu = _prev_skip
	Settings.tos_accepted = _prev_tos


func _make_screen() -> Control:
	var inst: Control = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(inst)
	return inst


## The roster the screen SHOULD offer: one entry per distinct BUILDABLE chip ability in the ItemDb scan —
## recomputed here from the same seams (ItemDb + AbilityRegistry.can_build) so a new chip .tres dropped in
## resources/items/ moves both sides of the assertion together.
func _expected_abilities() -> Dictionary:
	var reg := load(ABILITY_REGISTRY)
	var seen := {}
	for item: Item in ItemDb.all_items():
		if item != null and item.is_upgrade_chip() and reg.can_build(item.installs_ability):
			seen[item.installs_ability] = true
	return seen


func test_roster_offers_each_installable_ability_once_plus_the_opt_out() -> void:
	var s := _make_screen()
	var expected := _expected_abilities()
	assert_gt(expected.size(), 0, "the shipped chip catalog yields a non-empty roster")
	var rows: Array = s._rows
	assert_eq(rows.size(), expected.size() + 1,
		"one row per distinct installable ability + the No Implant opt-out")
	# Coverage, not just count: every buildable ability appears EXACTLY once, and the opt-out is LAST.
	var offered := {}
	for i in rows.size() - 1:
		var id: StringName = (rows[i] as Button).get_meta("ability_id")
		assert_false(offered.has(id), "ability '%s' is offered only once (dedupe by ability id)" % id)
		assert_true(expected.has(id), "row ability '%s' is a real buildable chip ability" % id)
		offered[id] = true
	assert_eq(offered.size(), expected.size(), "every buildable chip ability gets a row")
	assert_eq(StringName((rows[rows.size() - 1] as Button).get_meta("ability_id")), &"",
		"the explicit No Implant opt-out is the last row")


func test_begin_disabled_until_an_explicit_pick() -> void:
	var s := _make_screen()
	var begin := s.get_node("%BeginButton") as Button
	assert_true(begin.disabled, "Begin boots disabled — the free pick must be an explicit choice")
	(s._rows[0] as Button).button_pressed = true  # emits toggled -> _on_pick
	assert_false(begin.disabled, "any pick (a chip or the opt-out) arms Begin")


func test_begin_emits_the_picked_ability() -> void:
	var s := _make_screen()
	watch_signals(s)
	var row := s._rows[0] as Button
	row.button_pressed = true
	s._on_begin()
	assert_signal_emitted_with_parameters(s, "confirmed", [row.get_meta("ability_id")])


func test_opt_out_emits_an_empty_ability() -> void:
	var s := _make_screen()
	watch_signals(s)
	(s._rows[s._rows.size() - 1] as Button).button_pressed = true  # the pinned-last No Implant row
	s._on_begin()
	assert_signal_emitted_with_parameters(s, "confirmed", [&""])


func test_begin_refuses_without_a_pick() -> void:
	var s := _make_screen()
	watch_signals(s)
	s._on_begin()  # programmatic press while unpicked — the emit-guard backstop
	assert_signal_not_emitted(s, "confirmed", "Begin without a pick emits nothing")


func test_back_emits_cancelled() -> void:
	var s := _make_screen()
	watch_signals(s)
	s._on_back()
	assert_signal_emitted(s, "cancelled", "Back hands control back to StartMenu (which resumes creation)")


# --- StartMenu flow seams (no boot: _start_game is never reached) ------------------------------------------

func _make_menu() -> Node:
	# Isolate from the debug straight-to-game boot + first-launch gates (the test_start_menu idiom).
	Settings.debug_skip_menu = false
	Settings.tos_accepted = true
	var menu: Node = (load(START_MENU_SCENE) as PackedScene).instantiate()
	add_child_autofree(menu)
	return menu


func test_creation_begin_raises_the_implant_step_instead_of_booting() -> void:
	var menu := _make_menu()
	var prior_name: String = GameState.player_name
	menu._on_character_confirmed("Chooms", {&"strength": 2}, {})
	assert_not_null(menu._implant_choice, "Begin on creation raises the implant step")
	assert_false(menu._loading, "the boot is DEFERRED to the implant confirm")
	assert_eq(GameState.player_name, prior_name, "the profile is untouched until the implant confirm")
	menu._on_implant_cancelled()
	assert_null(menu._implant_choice, "Back drops the implant step")


func test_stamp_seeds_the_free_implant_after_the_reset() -> void:
	var menu := _make_menu()
	menu._pending_creation = ["Chooms", {&"strength": 2}, {}]
	menu._stamp_new_game_profile(&"air_dash")
	assert_eq(GameState.player_name, "Chooms", "the stashed name is stamped after the reset")
	assert_eq(int(GameState.stat_values.get(&"strength", 0)), 2, "the stashed stat build is stamped after the reset")
	assert_true(GameState.unlocks.has(&"air_dash"),
		"the free implant lands in GameState.unlocks AFTER reset_for_new_game (which clears unlocks)")
	assert_true(GameState.profile_active, "a created character IS an authoritative run (P0-2)")
	GameState.reset_for_new_game()  # leave the shared autoload clean for the rest of the suite


func test_stamp_with_the_opt_out_keeps_the_zero_ability_start() -> void:
	var menu := _make_menu()
	menu._pending_creation = ["Chooms", {}, {}]
	menu._stamp_new_game_profile(&"")
	assert_true(GameState.unlocks.is_empty(),
		"declining the implant keeps the zero-ability fresh start (P0-1) — nothing is seeded")
	GameState.reset_for_new_game()  # leave the shared autoload clean for the rest of the suite
