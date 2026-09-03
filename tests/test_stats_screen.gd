extends GutTest
## Smoke tests for the StatsScreen autoload — it binds its AUTHORED scene chrome at startup (see
## tests/test_stats_screen_scene.gd for the scene-wiring contract) and stays closed/inert when there's
## no player present (the start-menu path; opening requires a real player; it never pauses — real-time tab).

func after_each() -> void:
	if StatsScreen.is_open():
		StatsScreen.close()

func test_autoload_present_and_starts_closed() -> void:
	assert_not_null(StatsScreen, "StatsScreen autoload should be registered")
	assert_false(StatsScreen.is_open(), "starts closed")

func test_open_is_noop_without_a_player() -> void:
	# No node in the &"Player" group during a test -> open() must bail BEFORE pausing / showing (no crash).
	StatsScreen.open()
	assert_false(StatsScreen.is_open(), "open() with no player keeps the screen closed")
	assert_false(get_tree().paused, "and never leaves the tree paused without a player")

func test_stat_readout_includes_live_bonus() -> void:
	assert_eq(StatsScreen._stat_value_text(0, 3.0), "3 (+3)",
		"a carried +3 streetwise item like Chrome Grin should be visible on the Stats screen")
	assert_eq(StatsScreen._stat_value_text(5, -2.0), "3 (-2)",
		"negative live modifiers show the effective value and the signed penalty")

func test_inspect_is_reachable_without_a_mouse() -> void:
	# CONTROLLER PARITY. The tab strip is FOCUS_NONE by cross-screen contract and the scene authors Inspect
	# focus-less, which between them left this tab with ZERO focusable controls — a pad player could open Stats
	# and never reach Character Inspect. _bind_ui promotes the button at boot (the scene's own value stays as the
	# designer authored it — tests/test_stats_screen_scene.gd pins that half), so this reads the LIVE autoload,
	# whose _ready has already run. open() then seeds focus on it once %Root is visible, which needs a real
	# player and so stays a playtest.
	var btn := StatsScreen.get_node("%InspectButton") as Button
	assert_not_null(btn, "the Inspect button is bound")
	assert_eq(btn.focus_mode, Control.FOCUS_ALL,
		"Inspect is focusable at runtime — it is the tab's only control, so focus-less means pad-unreachable")

func test_agility_effect_names_all_three_speeds() -> void:
	# The agility block gained a SECOND clause when agility started driving stamina recovery (2026-08-28), and a
	# THIRD when it started driving melee cadence + reload time (2026-09-02). Pinned because this readout is the
	# only place a player is ever told the stat does more than move them faster.
	# ⭐ ONE percentage covers both hands effects on purpose: melee_time_mult and reload_time_mult ride the same
	# per-point rate, so a fourth clause would spend a line of a cramped cell restating the number beside it.
	var s := CharacterStats.new()
	s.agility = 4
	assert_eq(StatInfo._effect(&"agility", s), "+20% move speed, +20% stamina recovery, +20% attack & reload speed",
		"agility reads out its move speed, its stamina recovery AND the hands speed (melee cadence + reload)")


func test_agility_effect_hands_clause_reads_less_is_better() -> void:
	# The hands clause is a TIME multiplier, so it must be printed the gunplay-sway / larceny-takedown way:
	# a POSITIVE percentage means LESS time per swing and per magazine change. A negative agility must read as a
	# real penalty rather than a stray double sign — character creation lets a stat go to -5.
	var slow := CharacterStats.new()
	slow.agility = -3
	assert_eq(StatInfo._effect(&"agility", slow), "-15% move speed, -15% stamina recovery, -15% attack & reload speed",
		"a NEGATIVE agility reads as a penalty on all three clauses — slower on foot AND slower with the hands")


func test_agility_effect_hands_clause_folds_a_live_buff() -> void:
	# A carried +agility trinket (Featherframe Weave) must move the printed hands number too, not just the legs —
	# StatInfo passes the same `bonus` into melee_time_mult that Attack passes into the real swing.
	var s := CharacterStats.new()
	assert_eq(StatInfo._effect(&"agility", s, 3.0), "+15% move speed, +15% stamina recovery, +15% attack & reload speed",
		"a held +3 agility buff shows up on the hands clause exactly as it does on the movement ones")


func test_stat_effect_includes_live_bonus() -> void:
	var s := CharacterStats.new()
	assert_eq(StatInfo._effect(&"streetwise", s, 3.0), "buys +12%, sales +12%, rep gains +24%",
		"Chrome Grin's +3 streetwise should alter the visible derived effects, not just hidden merchant math")
