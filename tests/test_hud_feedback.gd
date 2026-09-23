extends GutTest

## HUD feedback (quest-tracker line + RewardStinger): the pure / loose-coupled logic, off-tree. The visual HUD
## layout (placement, fonts, the live signal wiring) is in-tree and playtest-verified; here we pin the testable bits.

func test_quest_tracker_line_single_step_omits_count() -> void:
	assert_eq(UI.quest_tracker_line("Find the key", "Search the office", 0, 1),
		"[PH] ◈ Find the key: Search the office",
		"a single-step objective (required 1) shows no (n/m) count")

func test_quest_tracker_line_multi_step_shows_count() -> void:
	assert_eq(UI.quest_tracker_line("Cull the swarm", "Kill rats", 2, 5),
		"[PH] ◈ Cull the swarm: Kill rats (2/5)",
		"a multi-step objective shows the progress count")

func test_reward_stinger_cooldown_gates_double_sting() -> void:
	# A quest-complete that ALSO levels you up must sting once, not twice — the cooldown coalesces them.
	var s := RewardStinger.new()
	s.cooldown = 0.5
	assert_true(s._consume_sting(), "the first sting passes (cooldown idle)")
	assert_false(s._consume_sting(), "an immediate second sting is gated by the cooldown")
	s._cooldown_t = 0.0  # simulate the cooldown elapsing
	assert_true(s._consume_sting(), "after the cooldown elapses, a later reward stings again")
	s.free()


func test_dialogue_gameplay_hud_visibility_includes_hotbar() -> void:
	var ui := UI.new()
	ui._hp_bar = Control.new()
	ui.add_child(ui._hp_bar)
	ui._stamina_bar = Control.new()
	ui.add_child(ui._stamina_bar)
	ui._hud_ammo = Label.new()
	ui.add_child(ui._hud_ammo)
	ui._hotbar = Hotbar.new()
	ui.add_child(ui._hotbar)

	ui._set_gameplay_hud_visible(false)
	assert_false(ui._hp_bar.visible, "dialogue hides the HP readout")
	assert_false(ui._stamina_bar.visible, "dialogue hides the stamina readout")
	assert_false(ui._hud_ammo.visible, "dialogue hides the ammo readout")
	assert_false(ui._hotbar.visible, "dialogue hides the hotbar too")

	ui._set_gameplay_hud_visible(true)
	assert_true(ui._hotbar.visible, "the hotbar returns with the rest of the gameplay HUD after dialogue")
	ui.free()


## The top-right stack reads two live Options flags; a test that writes them must hand the real values back.
var _prev_minimap_enabled: bool
var _prev_clock_enabled: bool

func before_each() -> void:
	_prev_minimap_enabled = Settings.minimap_enabled
	_prev_clock_enabled = Settings.clock_enabled

func after_each() -> void:
	Settings.minimap_enabled = _prev_minimap_enabled
	Settings.clock_enabled = _prev_clock_enabled


## THE NULL-DEREF THIS SUITE EXISTS TO CATCH. This file (and test_stamina_ring.gd) build a bare UI.new()
## WITHOUT running _ready, set a handful of members by hand and call the visibility methods directly — so
## _minimap and _quest_tracker are both null. _apply_minimap_visibility runs from _set_gameplay_hud_visible
## AND once per frame, which means an unguarded touch there takes down every suite that constructs a bare
## HUD, from a file whose author was only thinking about the real game. A GDScript runtime error stops only
## the function it happens in, so the asserts read the CLOCK: its show/hide is written AFTER the _minimap
## touch inside _apply_minimap_visibility itself, so a null deref there stops that function before the clock
## is updated and the clock keeps its stale visibility — the break shows up here, not only in the error log.
func test_gameplay_hud_visibility_tolerates_a_missing_minimap() -> void:
	var ui := UI.new()
	var clock := Control.new()
	ui.add_child(clock)
	ui._clock = clock
	Settings.clock_enabled = true             # restored in after_each
	assert_null(ui._minimap, "a bare UI has no minimap")
	assert_null(ui._quest_tracker, "...and no quest tracker")
	ui._set_gameplay_hud_visible(false)
	assert_false(clock.visible,
		"dialogue still hides the clock when the HUD has no minimap and no tracker to reflow")
	ui._set_gameplay_hud_visible(true)
	assert_true(clock.visible, "...and closing the dialogue still brings the clock back")
	clock.visible = false                     # a stale hide the per-frame pass must re-derive
	ui._apply_minimap_visibility()            # the per-frame path, called directly
	assert_true(clock.visible,
		"the per-frame top-right pass still re-shows the enabled clock on a HUD whose minimap never built")
	ui.free()


## Paint the top-right stack (map row / clock / objective tracker) once through the per-frame pass and read
## back where the two lower rows landed. `map_present` false is the failed-instantiate case (_minimap null).
func _top_right_stack(map_present: bool, map_enabled: bool) -> Dictionary:
	var ui := UI.new()
	if map_present:
		var map := Control.new()
		ui.add_child(map)
		ui._minimap = map
	var clock := Control.new()
	ui.add_child(clock)
	ui._clock = clock
	var tracker := Label.new()
	ui.add_child(tracker)
	ui._quest_tracker = tracker
	Settings.minimap_enabled = map_enabled
	Settings.clock_enabled = true
	ui._gameplay_hud_visible = true
	ui._apply_minimap_visibility()
	var out := {"clock_top": clock.offset_top, "clock_visible": clock.visible, "tracker_top": tracker.offset_top}
	ui.free()
	return out


## `_minimap != null` is part of the reflow QUESTION, not a crash guard: a map that failed to build must lift the
## clock into the corner and pull the tracker up under it EXACTLY as the Options "Minimap" toggle does — never
## leave a map-sized hole above them, and never skip the reflow because there is no map node to hide.
func test_a_missing_minimap_reflows_the_stack_exactly_like_switching_it_off() -> void:
	var missing := _top_right_stack(false, true)
	var switched_off := _top_right_stack(true, false)
	var shown := _top_right_stack(true, true)
	assert_gt(float(shown["clock_top"]), float(switched_off["clock_top"]),
		"control: with the map up the clock sits BELOW it, so 'lifted' is a real move and not two zeros agreeing")
	assert_almost_eq(float(missing["clock_top"]), float(switched_off["clock_top"]), 0.001,
		"a HUD whose minimap never built must lift the clock to the same corner the Options toggle lifts it to")
	assert_almost_eq(float(missing["tracker_top"]), float(switched_off["tracker_top"]), 0.001,
		"...and pull the objective tracker up to the same line, not leave a map-sized hole above it")
	assert_gt(float(missing["tracker_top"]), float(missing["clock_top"]),
		"the tracker still stacks UNDER the clock once the map row is gone")
	assert_true(bool(missing["clock_visible"]), "a missing map never takes the (enabled) clock down with it")


## The death cinematic owns HUD visibility while it runs: hide_hud_for_death remembers exactly which nodes
## it hid, so a per-frame re-show would resurrect the minimap over the fade. Same bail _apply_stamina_mode
## has, and it must be checked BEFORE the null guards or the bail is untested.
func test_minimap_visibility_bails_during_the_death_cinematic() -> void:
	var ui := UI.new()
	var map := Control.new()
	ui.add_child(map)
	ui._minimap = map
	map.visible = false                       # as if hide_hud_for_death had just hidden it
	ui._death_hidden_hud = [map] as Array[CanvasItem]
	ui._gameplay_hud_visible = true
	ui._apply_minimap_visibility()
	assert_false(map.visible, "the map stays hidden while the death list is non-empty")
	ui._death_hidden_hud.clear()
	ui._apply_minimap_visibility()
	assert_true(map.visible, "and comes back once the revive has cleared it")
	ui.free()
