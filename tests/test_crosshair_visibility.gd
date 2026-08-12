extends GutTest

## The reticle's suppression rule (ui.gd): the crosshair is painted only when NO reason to hide it holds.
## Two owners hide it — a conversation, and the weapon being HOLSTERED (GameSettings.hud.
## hide_crosshair_when_holstered) — and they overlap, because dialogue force-holsters the weapon and
## restores that state on finish.
##
## Driven through the PURE static UI.crosshair_shown so this runs off-tree: building the real UI CanvasLayer
## would run its _ready (shaders, autoload reads, the whole corner HUD).

func test_a_drawn_weapon_out_of_dialogue_shows_the_reticle() -> void:
	assert_true(UI.crosshair_shown(false, false, true),
		"weapon drawn, nobody talking: the reticle is up")

func test_holstering_hides_the_reticle() -> void:
	assert_false(UI.crosshair_shown(false, true, true),
		"nothing is aimed while the weapon is stowed, so nothing annotates the aim point")

func test_a_conversation_hides_the_reticle_even_with_the_weapon_drawn() -> void:
	assert_false(UI.crosshair_shown(true, false, true),
		"talking isn't an aiming moment — the dialogue latch hides it on its own")

## THE REASON THIS IS TWO LATCHES AND NOT ONE show/hide FLAG. DialogueController remembers the holster
## state at dialogue start and restores it on finish; when the player was ALREADY holstered, that restore
## is a no-op (set_holstered early-returns), so nothing re-hides the reticle. An imperative
## set_crosshair_visible(true) on dialogue end would therefore leave a reticle up over a stowed weapon.
func test_dialogue_ending_over_a_still_holstered_weapon_leaves_it_hidden() -> void:
	assert_false(UI.crosshair_shown(false, true, true),
		"the conversation's latch clearing must not un-hide a reticle the HOLSTER latch still owns")

## ...and the mirror: a hold-R draw taken mid-conversation must not punch the reticle through the letterbox.
func test_drawing_mid_conversation_keeps_it_hidden() -> void:
	assert_false(UI.crosshair_shown(true, false, true),
		"clearing the holster latch must not un-hide a reticle the DIALOGUE latch still owns")

func test_the_knob_off_restores_the_permanent_reticle() -> void:
	assert_true(UI.crosshair_shown(false, true, false),
		"hide_crosshair_when_holstered OFF: a holstered weapon no longer touches the reticle")
	assert_false(UI.crosshair_shown(true, true, false),
		"...but the knob only governs the HOLSTER reason — dialogue still hides it")

func test_the_shipped_default_hides_on_holster() -> void:
	var h := HudSettings.new()
	assert_true(h.hide_crosshair_when_holstered,
		"ships ON — the player spawns holstered (Player.start_holstered), so this is what the game opens on")
	h = null
