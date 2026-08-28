extends GutTest

## The reticle's visibility rule (ui.gd). Three owners have an opinion: a conversation hides it, the weapon
## being HOLSTERED hides it (GameSettings.hud.hide_crosshair_when_holstered), and CARRYING a throwable prop
## shows it (GameSettings.hud.show_crosshair_while_carrying). They overlap — dialogue force-holsters the
## weapon and restores that state on finish, and grabbing a prop IS a holster — so the answer is DERIVED
## from latches rather than toggled. Precedence: dialogue beats everything, carrying beats the holster hide.
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

## CARRYING A PROP RE-SHOWS THE RETICLE. Grabbing holsters + draw-locks the weapon (Player._on_carry_changed:
## "no gun while your hands are full"), so the holster latch is ALREADY true for every carry — if the two
## reasons merely stacked, the reticle would be hidden exactly when you need it to aim the throw. Carrying
## therefore OVERRIDES the holster hide: that holster isn't "nothing is aimed", it's carrying's side effect,
## and a left-click / Z release launches the prop straight down the look ray.
func test_carrying_a_prop_shows_the_reticle_even_though_carrying_holsters_the_weapon() -> void:
	assert_true(UI.crosshair_shown(false, true, true, true, true),
		"a carried prop throws down the look ray — the reticle is its aim point")

## The mirror that proves the override is the CARRY and not just "any holster with the knob on": with the
## prop let go, the same holstered weapon hides it again.
func test_letting_the_prop_go_hands_the_reticle_back_to_the_holster_rule() -> void:
	assert_false(UI.crosshair_shown(false, true, true, false, true),
		"hands empty and the weapon still stowed: the holster reason owns the reticle again")

## Dialogue outranks the carry re-show — you can be holding a crate mid-conversation (the carry survives a
## talk; DialogueController only touches the holster), and talking still isn't an aiming moment.
func test_dialogue_hides_the_reticle_even_while_carrying() -> void:
	assert_false(UI.crosshair_shown(true, true, true, true, true),
		"a conversation hides the reticle unconditionally, carried prop or not")

## The carry knob OFF returns carrying to the plain holster rule (and can't hide a reticle nothing else hides).
func test_the_carry_knob_off_leaves_carrying_to_the_holster_rule() -> void:
	assert_false(UI.crosshair_shown(false, true, true, true, false),
		"show_crosshair_while_carrying OFF: the carry stops overriding the holster hide")
	assert_true(UI.crosshair_shown(false, false, true, true, false),
		"...and it is only ever an override — with nothing else hiding it, the reticle stays up")

## The two carry params are DEFAULTED so every pre-existing 3-arg caller keeps its exact old meaning.
func test_the_three_arg_form_still_means_not_carrying() -> void:
	assert_false(UI.crosshair_shown(false, true, true),
		"the legacy 3-arg call must still resolve as 'hands empty', not silently adopt the carry override")

func test_the_shipped_default_shows_the_reticle_while_carrying() -> void:
	var h := HudSettings.new()
	assert_true(h.show_crosshair_while_carrying,
		"ships ON — carrying is an aiming state (the throw is aimed down the look ray)")
	h = null
