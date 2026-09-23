extends GutTest
## The one ORDER dependency in project.godot's [autoload] section, plus two GameSettings data checks.
##
## Escape priority: autoloads join /root in [autoload] row order, and Godot delivers _unhandled_input in REVERSE
## tree order, so a LATER row hears Escape FIRST. OptionsMenu._unhandled_input marks EVERY ui_cancel press handled:
## it toggles itself, and when open() refuses because another modal is up it still eats the press. So every modal
## that closes on Escape (each InputManager registry screen, plus NameEntryDialog) must sit on a row AFTER
## OptionsMenu. Put one above it and Escape reaches Options first, Options declines to stack over the modal and
## swallows the key, and the player can no longer Escape out of that screen. Never alphabetize the section.
##
## CrashGuard FIRST / CrashReportScreen LAST are pinned in tests/test_crash_report_screen_scene.gd. Autoload
## PRESENCE is not tested anywhere on purpose: a missing autoload is a parse error in every file that names it.

## Escape-closing autoloads that are NOT modal-registry rows but still need the same priority: NameEntryDialog
## cancels on ui_cancel, and OptionsMenu.open() refuses while it is up (so Options would eat that Escape too).
const EXTRA_ESCAPE_MODALS: Array[String] = ["NameEntryDialog"]


## [autoload] row names in declaration order (ProjectSettings keeps the project.godot row order).
func _autoload_rows() -> Array[String]:
	var names: Array[String] = []
	for p in ProjectSettings.get_property_list():
		var n := str(p.get("name", ""))
		if n.begins_with("autoload/"):
			names.append(n.trim_prefix("autoload/"))
	return names


## Every autoload that closes on Escape and that OptionsMenu refuses to open over, read from the LIVE modal
## registry so a newly registered screen is covered without editing this file.
func _escape_modal_names() -> Array[String]:
	var out: Array[String] = []
	for s in InputManager._modal_screens():
		var node := s as Node
		if node != null and node != OptionsMenu:
			out.append(String(node.name))
	out.append_array(EXTRA_ESCAPE_MODALS)
	return out


func test_every_escape_closing_modal_is_declared_after_options_menu() -> void:
	var rows := _autoload_rows()
	var options_row := rows.find("OptionsMenu")
	assert_gt(options_row, -1, "OptionsMenu must be an [autoload] row, or there is no Escape order to check")
	var modals := _escape_modal_names()
	assert_gt(modals.size(), EXTRA_ESCAPE_MODALS.size(),
		"the modal registry must list screens besides OptionsMenu, or this order check covers nothing")
	for m in modals:
		var row := rows.find(m)
		assert_gt(row, -1, "%s must be an [autoload] row: only autoload rows get a place in the Escape walk" % m)
		assert_gt(row, options_row,
			("%s is [autoload] row %d but OptionsMenu is row %d: a LATER row hears Escape first, and OptionsMenu eats "
			+ "every Escape, so %s must sit BELOW OptionsMenu or Escape can no longer close it") % [m, row, options_row, m])


func test_effect_factory_blood_particle_slot_is_populated() -> void:
	# EffectFactory owns ONE effect slot after H3 (the blood-impact particle) — it must be preloaded, not null.
	assert_not_null(EffectFactory.blood_particle,
		"EffectFactory.blood_particle must be populated (a preloaded scene), not null")


func test_game_settings_all_resource_slots_populated() -> void:
	# All resource slots must be populated (preload fields, not _ready loads); a nil slot means the preload
	# wiring is broken and every reader of that tuning resource crashes.
	assert_not_null(GameSettings.player_movement,
		"GameSettings.player_movement must not be nil")
	assert_not_null(GameSettings.player_crouch,
		"GameSettings.player_crouch must not be nil")
	assert_not_null(GameSettings.bunnyhop,
		"GameSettings.bunnyhop must not be nil")
	assert_not_null(GameSettings.camera,
		"GameSettings.camera must not be nil")
	assert_not_null(GameSettings.screen_shake,
		"GameSettings.screen_shake must not be nil")
	assert_not_null(GameSettings.weapon_general,
		"GameSettings.weapon_general must not be nil")
	assert_not_null(GameSettings.effects,
		"GameSettings.effects must not be nil")
	assert_not_null(GameSettings.audio,
		"GameSettings.audio must not be nil")
	assert_not_null(GameSettings.physics_damage,
		"GameSettings.physics_damage must not be nil")


func test_game_settings_resource_values_parsed() -> void:
	# Spot-check a couple of values to ensure the resources actually parsed.
	assert_gt(GameSettings.player_movement.max_speed, 0.0,
		"player_movement.max_speed must load as a positive value")
	assert_gt(GameSettings.camera.default_fov, 0.0,
		"camera.default_fov must load as a positive value")
