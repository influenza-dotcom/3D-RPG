extends GutTest

## The reticle's visibility rule (ui.gd). Three owners have an opinion: a conversation hides it, the weapon
## being HOLSTERED hides it (GameSettings.hud.hide_crosshair_when_holstered), and CARRYING a throwable prop
## shows it (GameSettings.hud.show_crosshair_while_carrying). They overlap — dialogue force-holsters the
## weapon and restores that state on finish, and grabbing a prop IS a holster — so the answer is DERIVED
## from latches rather than toggled. Precedence: dialogue beats everything, carrying beats the holster hide.
##
## The truth table is driven through the PURE static UI.crosshair_shown. The ORDER-dependent stories (a latch
## clearing while another still owns the reticle) are driven through a bare UI.new() that is never added to the
## tree — its set_crosshair_* latches and the single writer run for real on a stand-in reticle, while _ready
## (shaders, autoload reads, the whole corner HUD) never does.

var _prev_hide_when_holstered: bool
var _prev_show_while_carrying: bool

func before_each() -> void:
	_prev_hide_when_holstered = GameSettings.hud.hide_crosshair_when_holstered
	_prev_show_while_carrying = GameSettings.hud.show_crosshair_while_carrying

func after_each() -> void:
	# GameSettings.hud is the shared shipped resource; never leave a knob flipped for the next suite.
	GameSettings.hud.hide_crosshair_when_holstered = _prev_hide_when_holstered
	GameSettings.hud.show_crosshair_while_carrying = _prev_show_while_carrying

## A bare, never-parented UI whose reticle is a stand-in ColorRect, so the real latches + single writer run.
func _hud_with_reticle() -> UI:
	var ui: UI = autofree(UI.new())
	var reticle: ColorRect = autofree(ColorRect.new())
	ui.crosshair = reticle
	assert_true(reticle.visible, "precondition: the stand-in reticle starts visible")
	return ui

func test_a_drawn_weapon_out_of_dialogue_shows_the_reticle() -> void:
	assert_true(UI.crosshair_shown(false, false, true),
		"weapon drawn, nobody talking: the reticle is up")

func test_holstering_hides_the_reticle() -> void:
	# Also the legacy 3-arg form: the two carry params are DEFAULTED, and this call must still mean "hands empty"
	# rather than silently adopting the carry override.
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
	GameSettings.hud.hide_crosshair_when_holstered = true
	var ui := _hud_with_reticle()
	ui.set_crosshair_holstered(true)    # walked up to the NPC with the weapon already away
	ui.set_crosshair_visible(false)     # the conversation opens
	ui.set_crosshair_visible(true)      # ...and ends; the holster restore is a no-op, so nothing else fires
	assert_false(ui.crosshair.visible,
		"the conversation's latch clearing must not un-hide a reticle the HOLSTER latch still owns")
	ui.set_crosshair_holstered(false)   # control: drawing the weapon is what brings it back
	assert_true(ui.crosshair.visible, "once the holster latch clears too, the reticle is back")

## ...and the mirror: a hold-R draw taken mid-conversation must not punch the reticle through the letterbox.
func test_drawing_mid_conversation_keeps_it_hidden() -> void:
	GameSettings.hud.hide_crosshair_when_holstered = true
	var ui := _hud_with_reticle()
	ui.set_crosshair_holstered(true)
	ui.set_crosshair_visible(false)     # the conversation opens over the stowed weapon
	ui.set_crosshair_holstered(false)   # hold-R draw while still talking
	assert_false(ui.crosshair.visible,
		"clearing the holster latch must not un-hide a reticle the DIALOGUE latch still owns")
	ui.set_crosshair_visible(true)      # control: the conversation ends with the weapon out
	assert_true(ui.crosshair.visible, "the reticle returns the moment the last owner lets go")

func test_the_knob_off_restores_the_permanent_reticle() -> void:
	assert_true(UI.crosshair_shown(false, true, false),
		"hide_crosshair_when_holstered OFF: a holstered weapon no longer touches the reticle")
	assert_false(UI.crosshair_shown(true, true, false),
		"...but the knob only governs the HOLSTER reason — dialogue still hides it")

## SHIP DECISION + the knob honoured at the writer: the player spawns holstered (Player.start_holstered), so the
## shipped hide_crosshair_when_holstered is what the game OPENS on — and the live UI must actually read it.
func test_the_shipped_hud_opens_on_a_hidden_reticle_and_the_knob_is_read_live() -> void:
	assert_true(GameSettings.hud.hide_crosshair_when_holstered,
		"SHIP DECISION: hide_crosshair_when_holstered ships ON in HudSettings.tres — nothing is aimed at spawn, so no dot")
	var ui := _hud_with_reticle()
	ui.set_crosshair_holstered(true)
	assert_false(ui.crosshair.visible, "with the shipped HUD, spawning holstered hides the reticle")
	GameSettings.hud.hide_crosshair_when_holstered = false
	ui.set_crosshair_visible(true)  # any latch write re-applies — the knob is read AT the apply, not cached
	assert_true(ui.crosshair.visible,
		"flipping the knob OFF in the inspector restores the permanent reticle on the next apply, no holster round-trip")

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

## SHIP DECISION + the real grab: Player._on_carry_changed moves BOTH latches in one call, and ui.gd promises the
## answer is order-independent. With the shipped HUD, a grab shows the dot whichever latch settles first, and
## letting go hands it back to the holster rule.
func test_the_shipped_hud_shows_the_reticle_for_a_grab_whichever_latch_settles_first() -> void:
	assert_true(GameSettings.hud.show_crosshair_while_carrying,
		"SHIP DECISION: show_crosshair_while_carrying ships ON in HudSettings.tres — carrying is an aiming state (the throw goes down the look ray)")
	var holster_first := _hud_with_reticle()
	holster_first.set_crosshair_holstered(true)
	holster_first.set_crosshair_carrying(true)
	assert_true(holster_first.crosshair.visible, "grab (holster latch first): the carried prop's aim point is shown")
	var carry_first := _hud_with_reticle()
	carry_first.set_crosshair_carrying(true)
	carry_first.set_crosshair_holstered(true)
	assert_true(carry_first.crosshair.visible,
		"grab (carry latch first): same answer — the draw-lock holster landing last must not re-hide the aim point")
	carry_first.set_crosshair_carrying(false)
	assert_false(carry_first.crosshair.visible,
		"letting the prop go with the weapon still stowed hides the reticle again (the shipped holster rule)")
