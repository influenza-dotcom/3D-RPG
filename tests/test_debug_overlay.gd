extends GutTest

## The runtime DebugOverlay (#10 profiler + #12 graphs): the PURE graph math (push_capped / graph_points) is
## unit-tested; the live sampling + draw are play-verified (they need a running game + renderer). Construct check
## confirms the component compiles off-tree.

const DebugOverlay := preload("res://scripts/components/debug_overlay.gd")


func test_push_capped_keeps_the_last_n() -> void:
	var b := PackedFloat32Array()
	for i in 5:
		b = DebugOverlay.push_capped(b, float(i), 3)
	assert_eq(b.size(), 3, "the rolling window keeps only `cap` samples")
	assert_eq(b[0], 2.0, "oldest kept is the 3rd-from-last")
	assert_eq(b[2], 4.0, "newest is the last pushed")


func test_push_capped_under_cap_keeps_all() -> void:
	var b := PackedFloat32Array()
	b = DebugOverlay.push_capped(b, 1.0, 10)
	b = DebugOverlay.push_capped(b, 2.0, 10)
	assert_eq(b.size(), 2, "below the cap nothing is dropped")


func test_graph_points_maps_range_and_spread() -> void:
	var s := PackedFloat32Array([0.0, 50.0, 100.0])
	var pts := DebugOverlay.graph_points(s, Rect2(0, 0, 100, 10), 0.0, 100.0)
	assert_eq(pts.size(), 3, "one point per sample")
	assert_almost_eq(pts[0].x, 0.0, 0.01, "first sample at the left edge")
	assert_almost_eq(pts[2].x, 100.0, 0.01, "last sample at the right edge")
	assert_almost_eq(pts[0].y, 10.0, 0.01, "value at vmin -> rect bottom")
	assert_almost_eq(pts[2].y, 0.0, 0.01, "value at vmax -> rect top")
	assert_almost_eq(pts[1].y, 5.0, 0.01, "value at the midpoint -> rect middle")


func test_graph_points_clamps_out_of_range() -> void:
	var s := PackedFloat32Array([200.0])  # above vmax
	var pts := DebugOverlay.graph_points(s, Rect2(0, 0, 10, 10), 0.0, 100.0)
	assert_almost_eq(pts[0].y, 0.0, 0.01, "an over-range value clamps to the top, never above the rect")
	assert_eq(DebugOverlay.graph_points(PackedFloat32Array(), Rect2(), 0.0, 1.0).size(), 0, "no samples -> no points")


func test_debug_overlay_constructs() -> void:
	var o = DebugOverlay.new()
	assert_not_null(o, "the overlay compiles + constructs off-tree (no _ready until added to a tree)")
	o.free()


# --- the live game-state block (2026-08-18) -------------------------------------------------------------------

func test_player_state_text_formats_known_facts() -> void:
	var txt := DebugOverlay.player_state_text({
		"hp": 3.0, "max_hp": 4.0,
		"stamina": 80.0, "max_stamina": 100.0,
		"money": 250.0, "account": -40.0,
		"pos": Vector3(1.25, 2.0, -3.75),
		"time": 0.5, "level": "trenchboom",
	})
	assert_string_contains(txt, "HP 3/4")
	assert_string_contains(txt, "Stam 80/100")
	assert_string_contains(txt, "z 250")
	assert_string_contains(txt, "bank -40")
	assert_string_contains(txt, "@ 1.3 2.0 -3.8")  # %.1f rounds half away from zero: 1.25 -> 1.3
	assert_string_contains(txt, "12:00")
	assert_string_contains(txt, "trenchboom")


func test_player_state_text_degrades_per_missing_fact() -> void:
	assert_eq(DebugOverlay.player_state_text({}), "no player", "no facts -> the no-player line")
	var partial := DebugOverlay.player_state_text({"hp": 4.0, "max_hp": 4.0})
	assert_string_contains(partial, "HP 4/4")
	assert_false(partial.contains("@"), "a missing position paints nothing, not a zero that reads as the origin")


func test_clock_text_wraps_instead_of_clamping() -> void:
	assert_eq(DebugOverlay.clock_text(0.0), "00:00")
	assert_eq(DebugOverlay.clock_text(0.5), "12:00")
	assert_eq(DebugOverlay.clock_text(0.75), "18:00")
	assert_eq(DebugOverlay.clock_text(1.25), "06:00", "a drifted fraction wraps to a real clock face")
	assert_eq(DebugOverlay.clock_text(-0.25), "18:00", "negative wraps too (fposmod, not clamp)")


# --- disk-write telemetry + the sandbox warning (2026-08-18, save-sandbox iteration) ----------------------------

func test_player_state_text_saves_line_counts_and_ages() -> void:
	var txt := DebugOverlay.player_state_text({"saves": 7, "save_age": 12.4})
	assert_string_contains(txt, "saves 7")
	assert_string_contains(txt, "12s ago")


func test_player_state_text_saves_line_before_any_write() -> void:
	# save_age -1 = no _write_atomic attempt yet this session: a distinct fact from "0s ago", so it must not
	# paint an age at all.
	var txt := DebugOverlay.player_state_text({"saves": 0, "save_age": -1.0})
	assert_string_contains(txt, "saves 0")
	assert_false(txt.contains("ago"), "no write yet paints no age (\"none yet\", not \"0s ago\")")
	var no_age := DebugOverlay.player_state_text({"saves": 3})
	assert_string_contains(no_age, "saves 3")
	assert_false(no_age.contains("ago"), "a missing save_age degrades the same way as -1")


func test_player_state_text_sandbox_warning_leads_the_block() -> void:
	var txt := DebugOverlay.player_state_text({
		"sandbox": true, "hp": 4.0, "max_hp": 4.0, "saves": 1, "save_age": 3.0,
	})
	assert_true(txt.begins_with(DebugOverlay.SANDBOX_LINE),
		"the sandbox warning is the FIRST line of the block, above HP — it must never scroll under the stats")
	assert_string_contains(txt, "HP 4/4")


func test_player_state_text_sandbox_off_or_absent_paints_nothing() -> void:
	var off := DebugOverlay.player_state_text({"sandbox": false, "hp": 4.0, "max_hp": 4.0})
	assert_false(off.contains(DebugOverlay.SANDBOX_LINE), "sandbox off paints no warning")
	# An older GameState (no sandbox_active) yields no "sandbox" fact at all — same silence, no crash.
	var absent := DebugOverlay.player_state_text({"hp": 4.0, "max_hp": 4.0})
	assert_false(absent.contains(DebugOverlay.SANDBOX_LINE), "a missing sandbox fact paints no warning")


## sample_state's reads of the ADDITIVE GameState members are duck-typed so the overlay boots on any GameState
## build. Pin the contract both ways: when the autoload carries the members, the facts arrive typed; when it does
## not, they are simply absent (never a crash, never a null fact). Off-tree GUT has no player, so the player facts
## are legitimately missing here — only the GameState-sourced ones are asserted.
func test_sample_state_carries_telemetry_facts_when_gamestate_has_them() -> void:
	var facts := DebugOverlay.sample_state(get_tree())
	if GameState.get(&"save_count") is int:
		assert_true(facts.has("saves"), "save_count on GameState -> a \"saves\" fact")
		assert_true(facts["saves"] is int, "the saves fact is an int")
		assert_true(facts.has("save_age"), "save_count on GameState -> a \"save_age\" fact")
		assert_gte(float(facts["save_age"]), -1.0, "save_age is -1 (never) or a non-negative age")
	else:
		assert_false(facts.has("saves"), "no save_count on GameState -> no saves fact (never a null fact)")
	if GameState.has_method(&"sandbox_active"):
		assert_true(facts.has("sandbox"), "sandbox_active on GameState -> a \"sandbox\" fact")
		assert_true(facts["sandbox"] is bool, "the sandbox fact is a bool")
	else:
		assert_false(facts.has("sandbox"), "no sandbox_active on GameState -> no sandbox fact")
	assert_eq(DebugOverlay.sandbox_active(), bool(facts.get("sandbox", false)),
		"the overlay's own sandbox_active() reads the same latch the fact does")


# --- the STEALTH block (2026-08-18, in-game debug suite iteration 6) ------------------------------------------

func test_player_state_text_stealth_block_formats_known_facts() -> void:
	var txt := DebugOverlay.player_state_text({
		"light": 0.42, "carried": 0.35, "noise": 4.0, "crouch": true,
		"stealth_level": "DETECTED", "stealth_meter": 0.5, "spotter": "Raider",
		"aware": {"UNAWARE": 3, "DETECTING": 1, "ALERTED": 0, "INVESTIGATING": 2}, "npcs_alive": 6,
	})
	assert_string_contains(txt, "light 0.42")
	assert_string_contains(txt, "carried 0.35 PENALTY")
	assert_string_contains(txt, "noise 4.0m")
	assert_string_contains(txt, "crouch")
	assert_string_contains(txt, "stealth DETECTED 0.50")
	assert_string_contains(txt, "<- Raider")
	assert_string_contains(txt, "aware U3 D1 A0 I2")
	assert_string_contains(txt, "6 alive")


func test_player_state_text_carried_light_zero_is_no_penalty() -> void:
	# The penalty is continuous from strength 0 (LightStealthSettings lerps both multipliers), so ONLY a positive
	# value may carry the flag — 0.00 is "torch off", not a rounding of a tiny penalty.
	var txt := DebugOverlay.player_state_text({"light": 1.0, "carried": 0.0})
	assert_string_contains(txt, "carried 0.00")
	assert_false(txt.contains("PENALTY"), "carried_light 0 paints no penalty flag")
	# light_exposure RESTS at 1.0 with no sampler present: the raw value is painted as-is, never annotated as
	# "fully lit" — the block must not imply a measurement that never happened.
	assert_string_contains(txt, "light 1.00")


func test_player_state_text_stealth_facts_absent_paint_nothing() -> void:
	var txt := DebugOverlay.player_state_text({"hp": 4.0, "max_hp": 4.0})
	assert_false(txt.contains("light"), "no light fact -> no light line")
	assert_false(txt.contains("stealth"), "no stealth_level fact -> no stealth line")
	assert_false(txt.contains("aware"), "no census -> no aware line")
	# A spotter-less snapshot paints the level + meter and no arrow.
	var alone := DebugOverlay.player_state_text({"stealth_level": "HIDDEN", "stealth_meter": 0.0, "spotter": ""})
	assert_string_contains(alone, "stealth HIDDEN 0.00")
	assert_false(alone.contains("<-"), "no spotter -> no arrow")


func test_awareness_text_letters_follow_the_census_key_order() -> void:
	# The letters are the first character of each KEY, in the census's own insertion order — which _sample_stealth
	# seeds from Perception.State.keys(). Reordering the enum reorders the readout; a table copied here could lie.
	assert_eq(DebugOverlay.awareness_text({"UNAWARE": 1, "DETECTING": 2, "ALERTED": 3, "INVESTIGATING": 4}), "aware U1 D2 A3 I4")
	assert_eq(DebugOverlay.awareness_text({"UNAWARE": 1, "DETECTING": 2}, 9), "aware U1 D2 · 9 alive")
	assert_eq(DebugOverlay.awareness_text({}), "aware -", "an empty census paints a dash, not an empty word")
	assert_false(DebugOverlay.awareness_text({"UNAWARE": 0}, -1).contains("alive"), "alive < 0 omits the tail")


func test_enum_name_resolves_by_value_and_degrades_to_the_number() -> void:
	assert_eq(DebugOverlay.enum_name({"A": 0, "B": 1}, 1), "B")
	assert_eq(DebugOverlay.enum_name({"A": 0, "B": 1}, 7), "7", "an unknown value paints its number, never a wrong name")
	# The real enums the sampler reads, resolved the way it resolves them (as runtime Dictionaries).
	assert_eq(DebugOverlay.enum_name(DebugOverlay.PerceptionScript.State, DebugOverlay.PerceptionScript.State.ALERTED), "ALERTED")
	assert_eq(DebugOverlay.enum_name(DebugOverlay.StealthStatusScript.Level, DebugOverlay.StealthStatusScript.Level.DANGER), "DANGER")


# --- the INPUT / MODAL lines (2026-08-18) ----------------------------------------------------------------------

func test_player_state_text_input_lines_format_known_facts() -> void:
	var txt := DebugOverlay.player_state_text({
		"mouse": Input.MOUSE_MODE_CAPTURED, "paused": false, "suppressed": true, "frozen": false,
		"modals": PackedStringArray(["OptionsMenu"]), "dialogue": false, "surface": "DebugConsole", "focus": "LineEdit",
	})
	assert_string_contains(txt, "mouse CAPTURED")
	assert_string_contains(txt, "paused N")
	assert_string_contains(txt, "supp Y")
	assert_string_contains(txt, "frz N")
	assert_string_contains(txt, "modal OptionsMenu")
	assert_string_contains(txt, "dlg N")
	assert_string_contains(txt, "dbg DebugConsole")
	assert_string_contains(txt, "focus LineEdit")


func test_player_state_text_input_lines_degrade_per_missing_fact() -> void:
	# Only the mouse mode is known: every ungathered gate paints "-" (unknown), never a reassuring "N".
	var txt := DebugOverlay.player_state_text({"mouse": Input.MOUSE_MODE_VISIBLE})
	assert_string_contains(txt, "mouse VISIBLE")
	assert_string_contains(txt, "paused -")
	assert_string_contains(txt, "supp -")
	assert_string_contains(txt, "modal -")
	assert_string_contains(txt, "dbg -")
	assert_string_contains(txt, "focus -")
	# Two open modals join with a comma; any_modal_open() true with an unreadable registry paints "?", not "-".
	var two := DebugOverlay.player_state_text({"mouse": 0, "modals": PackedStringArray(["OptionsMenu", "AtmScreen"])})
	assert_string_contains(two, "modal OptionsMenu,AtmScreen")
	var unreadable := DebugOverlay.player_state_text({"mouse": 0, "modal_open": true})
	assert_string_contains(unreadable, "modal ?")
	# No mouse fact at all -> no input lines (the flag was off, or there was no tree).
	var none := DebugOverlay.player_state_text({"hp": 1.0, "max_hp": 1.0})
	assert_false(none.contains("mouse"), "no mouse fact -> no input line")


func test_mouse_mode_name_covers_every_engine_mode() -> void:
	assert_eq(DebugOverlay.mouse_mode_name(Input.MOUSE_MODE_VISIBLE), "VISIBLE")
	assert_eq(DebugOverlay.mouse_mode_name(Input.MOUSE_MODE_HIDDEN), "HIDDEN")
	assert_eq(DebugOverlay.mouse_mode_name(Input.MOUSE_MODE_CAPTURED), "CAPTURED")
	assert_eq(DebugOverlay.mouse_mode_name(Input.MOUSE_MODE_CONFINED), "CONFINED")
	assert_eq(DebugOverlay.mouse_mode_name(Input.MOUSE_MODE_CONFINED_HIDDEN), "CONFINED_HIDDEN")
	assert_eq(DebugOverlay.mouse_mode_name(99), "?99", "an unknown mode paints its number")


## The live sampler under GUT: no player (so no stealth facts — they live inside the player branch), but the
## input/modal facts come straight off Input / the tree / the autoloads, typed. Both flags default ON for the
## one-argument call; passing them OFF must leave every gated fact out (the flags are cost knobs).
func test_sample_state_input_facts_are_typed_and_gated() -> void:
	var facts := DebugOverlay.sample_state(get_tree())
	assert_true(facts.has("mouse"), "the mouse mode is always sampled")
	assert_true(facts["mouse"] is int, "mouse mode is the raw Input.MouseMode int")
	assert_true(facts.has("paused"), "tree.paused is always sampled")
	assert_true(facts["paused"] is bool)
	if InputManager.has_method(&"gameplay_suppressed"):
		assert_true(facts.has("suppressed"), "gameplay_suppressed on InputManager -> a suppressed fact")
		assert_true(facts["suppressed"] is bool)
		assert_true(facts.has("modals"), "the modal registry read yields a modals fact")
		assert_true(facts["modals"] is PackedStringArray, "modals is a PackedStringArray of open screen names")
	assert_true(facts.has("surface"), "the debug-surface fact is always present (\"\" when none is open)")
	assert_true(facts.has("focus"), "the focus fact is always present (\"\" when nothing has focus)")
	assert_false(facts.has("light"), "no player under GUT -> no stealth facts (they live in the player branch)")
	var gated := DebugOverlay.sample_state(get_tree(), false, false)
	assert_false(gated.has("mouse"), "want_input=false leaves the input facts out")
	assert_false(gated.has("aware"), "want_stealth=false leaves the census out")
	# The formatter never crashes on the live sample, whatever it carried.
	var txt := DebugOverlay.player_state_text(facts)
	assert_true(txt.contains("mouse "), "the live sample paints the input line")
