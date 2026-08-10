extends GutTest

## HUD feedback (quest-tracker line + RewardStinger): the pure / loose-coupled logic, off-tree. The visual HUD
## layout (placement, fonts, the live signal wiring) is in-tree and playtest-verified; here we pin the testable bits.

func test_quest_tracker_line_single_step_omits_count() -> void:
	assert_eq(UI.quest_tracker_line("Find the key", "Search the office", 0, 1),
		"[PH] ◈ Find the key — Search the office",
		"a single-step objective (required 1) shows no (n/m) count")

func test_quest_tracker_line_multi_step_shows_count() -> void:
	assert_eq(UI.quest_tracker_line("Cull the swarm", "Kill rats", 2, 5),
		"[PH] ◈ Cull the swarm — Kill rats (2/5)",
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


## THE NULL-DEREF THIS SUITE EXISTS TO CATCH. This file (and test_stamina_ring.gd) build a bare UI.new()
## WITHOUT running _ready, set a handful of members by hand and call the visibility methods directly — so
## _minimap and _quest_tracker are both null. _apply_minimap_visibility runs from _set_gameplay_hud_visible
## AND once per frame, which means an unguarded touch there takes down every suite that constructs a bare
## HUD, from a file whose author was only thinking about the real game.
func test_gameplay_hud_visibility_tolerates_a_missing_minimap() -> void:
	var ui := UI.new()
	ui._hp_bar = Control.new()
	ui.add_child(ui._hp_bar)
	assert_null(ui._minimap, "a bare UI has no minimap")
	assert_null(ui._quest_tracker, "...and no quest tracker")
	ui._set_gameplay_hud_visible(false)   # must not crash on either null
	ui._set_gameplay_hud_visible(true)
	ui._apply_minimap_visibility()        # the per-frame path, called directly
	assert_false(ui._hp_bar.visible == false and ui._hp_bar.visible == true, "reached without crashing")
	ui.free()


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
