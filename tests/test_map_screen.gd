extends GutTest

## MapScreen behaviour (scripts/ui/map_screen.gd) — the MAP tab, sixth member of the Pip-Boy tab group,
## default key M. The authored-scene WIRING half is tests/test_map_screen_scene.gd; what is pinned here is the
## live autoload's boot state, the CODE-BUILT chrome _bind_ui adds inside the authored host (the pointer
## overlay, the on-plan tutorial, the floating pin card, the footer's three pad buttons), and the verbs the
## screen owns — zoom, pan, recentre, place, select, deselect, track, delete.
##
## The UX pass added a second family of pins here, and they are all about what the player can SEE: the wheel
## zooms about the cursor rather than the view centre, Next Pin and a click on a rim-pinned glyph both bring
## their pin into view (while a click on a pin that is really on the plan must NOT move the map), right-click
## and the first Esc both deselect, and the gesture tutorial is an EMPTY STATE over the plan rather than a
## footer line that never fitted. The screenshot pass that followed added one more, in the most literal sense
## of "what the player can see": every label this screen floats OVER the plan is inked for the map rather than
## for the parchment panel, because the panel's ink on a near-black map is text nobody can read.
##
## These run against the REAL MapScreen autoload rather than a fresh instantiate, because the fact worth
## pinning is that _bind_ui really ran at boot and really built what it claims — an instantiate-without-
## add_child never runs _ready, so it could only re-assert the .tscn the scene test already reads.
##
## ⭐open()/close() are deliberately NOT driven: they want a live human Player in-tree, which CLAUDE.md forbids
## a unit test from building, so the open PATH stays playtest-verified (and its refusal gates are pinned by
## source in test_modal_registry.gd). The gesture tests below flip the `_is_open` latch by hand and restore it
## the same way, never through close() — close() would drive PlayerMenus.leave() over a screen that never
## entered, which is a different bug being invented to test this one.
##
## ⭐THEY MUTATE LIVE AUTOLOADS. Settings.map_zoom persists to settings.cfg and GameState's waypoint ledger is
## the running profile, so every test restores the rows it touched and clears the pins it placed (the
## autoload-split isolation rule).

const SOURCE := "res://scripts/ui/map_screen.gd"
const LEVEL := "res://tests/_fake_map_screen_level.tscn"  ## never loaded — the ledger keys on the PATH STRING alone

var _was_map_zoom: float = 1.0
var _was_minimap_zoom: float = 1.0
var _was_level: String = ""

func before_each() -> void:
	_was_map_zoom = Settings.map_zoom
	_was_minimap_zoom = Settings.minimap_zoom
	_was_level = GameState.current_level_path
	GameState.current_level_path = LEVEL  # written directly: set_current_level() has side effects
	GameState.waypoints.clear()
	MapScreen._select(-1)
	MapScreen._reset_view()

func after_each() -> void:
	# The zoom rows PERSIST (set_map_zoom saves settings.cfg), so a test that left one moved would follow the
	# user home into their next play session. The ledger and the selection are the same argument in memory.
	Settings.set_map_zoom(_was_map_zoom)
	Settings.set_minimap_zoom(_was_minimap_zoom)
	if MapScreen._prompt != null and MapScreen._prompt.is_open():
		MapScreen._prompt.close()
	# The latch is cleared DIRECTLY rather than through close(): only _arm() can have set it here (open()
	# refuses without a live Player), and close() would call PlayerMenus.leave() for an enter() that never ran.
	MapScreen._is_open = false
	GameState.waypoints.clear()
	GameState.current_level_path = _was_level
	MapScreen._select(-1)
	MapScreen._reset_view()
	MapScreen._set_pan_cursor(false)  # a test that faked a drag must not leave the overlay wearing a grab hand
	var vp := get_viewport()
	if vp != null:
		vp.gui_release_focus()  # a card that grabbed focus must not hand it to the next test


func test_the_autoload_bound_its_widget_and_built_its_chrome_at_boot() -> void:
	assert_not_null(MapScreen._map, "_bind_ui resolved %Map — a rename in the editor would leave the tab drawing nothing")
	assert_not_null(MapScreen._zoom_value, "_bind_ui resolved the zoom readout")
	assert_not_null(MapScreen._input,
		"the pointer overlay was built into %MapHost — without it NOTHING on the plan is clickable, which is exactly the bug this rebuild fixed")
	assert_not_null(MapScreen._card, "the floating pin card was built")
	assert_not_null(MapScreen._tutorial, "the on-plan empty-state tutorial was built")
	assert_not_null(MapScreen._prompt, "the editor card was built")
	assert_not_null(MapScreen._next_btn, "the footer's pad selection path exists")
	assert_not_null(MapScreen._place_btn, "...and its placement path")
	assert_not_null(MapScreen._recentre_btn, "...and the pad's way back to the player after a pan")
	assert_false(MapScreen.is_open(), "the tab ships closed")


## ⭐THE MAP IS THE PAGE. The pin bar + note row that used to be code-inserted here squeezed the plan into a
## ~120 px ribbon on the 792x444 canvas (a real windowed QA run measured it), so the body between the tab strip
## and the footer belongs to the map and to nothing else. Anything that wants to sit over the plan floats
## INSIDE %MapHost instead — see the card test below.
func test_the_map_body_is_the_only_thing_between_the_tab_strip_and_the_footer() -> void:
	var vbox := MapScreen.get_node("%VBox") as VBoxContainer
	var names: Array[String] = []
	for child in vbox.get_children():
		names.append(String((child as Node).name))
	var want: Array[String] = ["TabSlot", "MapHost", "Footer"]
	assert_eq(names, want,
		"%VBox holds the tab slot, the map and the footer — a fourth row costs the plan its height on every open, whether or not anything is selected")


## ⭐THE POINTER PATH, and the ORDER that makes the card usable. The overlay is a STOP Control over the plan's
## own rect (bubbling to %Root was measured dead), and the card is added AFTER it: Godot picks the mouse
## against the LAST matching child first, so a card built before the overlay would have every press on its
## three buttons land on the plan and place a pin instead.
func test_the_pointer_overlay_owns_the_plan_and_the_card_sits_above_it() -> void:
	var host := MapScreen.get_node("%MapHost") as Control
	assert_eq(MapScreen._input.get_parent(), host, "the overlay lives inside the map host, so its rect IS the plan's")
	assert_eq(MapScreen._input.mouse_filter, Control.MOUSE_FILTER_STOP,
		"it must EAT the mouse — a PASS/IGNORE overlay is the dead bubbling path again")
	assert_eq(MapScreen._input.anchor_right, 1.0, "full-rect (right)")
	assert_eq(MapScreen._input.anchor_bottom, 1.0, "full-rect (bottom)")
	assert_eq(MapScreen._card.get_parent(), host, "the card floats over the plan rather than stacking under it")
	assert_eq(MapScreen._card.mouse_filter, Control.MOUSE_FILTER_STOP,
		"a click that misses a card button must DIE on the card, not fall through and pin the map under it")
	assert_gt(MapScreen._card.get_index(), MapScreen._input.get_index(),
		"the card is picked BEFORE the overlay — build order is what makes its buttons clickable at all")
	assert_false(MapScreen._card.visible, "...and it is hidden while nothing is selected")
	assert_eq(MapScreen._tutorial.get_parent(), host, "the tutorial floats over the plan too")
	assert_eq(MapScreen._tutorial.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"...but it must be mouse-TRANSPARENT: it sits on the surface whose whole job is receiving clicks, and a tutorial that ate the click it teaches is its own punchline")
	assert_gt(MapScreen._card.get_index(), MapScreen._tutorial.get_index(),
		"the card draws OVER the tutorial (they can never be up together, but tree order is the guarantee, not the timing)")


## ⭐THE CURSOR IS THE AFFORDANCE, and it is the only thing on this screen that says "this surface takes a
## point" before the player has clicked anything. The grab hand while dragging is the other half: it is how
## every map application the player has ever used reports a live pan.
func test_the_overlay_wears_a_cross_and_a_grab_hand_while_dragging() -> void:
	assert_eq(MapScreen._input.mouse_default_cursor_shape, Control.CURSOR_CROSS,
		"at rest the plan reads as placeable")
	_arm()
	MapScreen._on_map_gui_input(_press(Vector2(40, 30)))
	MapScreen._on_map_gui_input(_motion(Vector2(80, 30), Vector2(40, 0)))
	assert_eq(MapScreen._input.mouse_default_cursor_shape, Control.CURSOR_DRAG,
		"past the slop window the gesture is a PAN, and the cursor says so")
	MapScreen._on_map_gui_input(_release(Vector2(80, 30)))
	_disarm()
	assert_eq(MapScreen._input.mouse_default_cursor_shape, Control.CURSOR_CROSS,
		"the hand opens again when the button comes up — a drag cursor left armed over a map nobody is dragging is a lie")


## FINDING 3, pinned: MenuStyle.cap_button sets clip_text, which drops a Button's minimum width to nothing —
## the four pin-bar buttons this card replaces rendered as literal blank squares in the QA shots. A caption
## needs a width to draw in, and EXPAND_FILL inside the row is what hands it one.
func test_every_pin_button_has_a_caption_and_a_width_to_draw_it_in() -> void:
	for btn: Button in [MapScreen._track_btn, MapScreen._edit_btn, MapScreen._delete_btn]:
		assert_eq(btn.size_flags_horizontal, Control.SIZE_EXPAND_FILL,
			"every card button EXPANDs — without a share of the row its caption clips to nothing")
		assert_false(btn.text.is_empty(), "...and carries a real caption from PlayerText")
	assert_false(MapScreen._edit_btn.clip_text, "Edit's caption is fixed, so it sizes itself")
	assert_false(MapScreen._delete_btn.clip_text, "...and so does Delete's")
	assert_true(MapScreen._track_btn.clip_text,
		"only Track is capped: its caption SWAPS between two words, and a row button that resized with its text would jiggle the card every time the player tracked a pin")
	assert_gt(MapScreen._track_btn.custom_minimum_size.x, 0.0,
		"...which is why the capped one is the ONLY one that must also carry a pinned width")
	for btn: Button in [MapScreen._next_btn, MapScreen._place_btn, MapScreen._recentre_btn]:
		assert_false(btn.clip_text, "the footer's own buttons are never capped — that is what made the old row blank")
		assert_false(btn.text.is_empty(), "...and all three carry a caption")
	# The three are appended and then moved in front of %ZoomOut one at a time, each read of the anchor's index
	# taken fresh — a cached index would file the second and third in the wrong slots, which is invisible except
	# as a jumbled row.
	var zoom_out_at := (MapScreen.get_node("%ZoomOut") as Control).get_index()
	assert_lt(MapScreen._next_btn.get_index(), MapScreen._place_btn.get_index(),
		"Next Pin then Place Pin — the two PIN verbs stay adjacent")
	assert_lt(MapScreen._place_btn.get_index(), MapScreen._recentre_btn.get_index(),
		"...then Recentre, the VIEW verb, next to the zoom pair it belongs with")
	assert_lt(MapScreen._recentre_btn.get_index(), zoom_out_at,
		"...and all three sit between the hint and the zoom pair, not after them")


## THE SPAN PUSH, the one view knob the .tscn cannot carry: it is a designer number on HudSettings.tres, so
## _bind_ui reads it at boot. If this ever silently stops happening the map tab draws the HUD box's 40 m room
## at panel size — a magnifier, not a map — and nothing errors.
func test_the_widget_draws_the_map_span_not_the_minimap_span() -> void:
	assert_almost_eq(MapScreen._map.world_span_override, GameSettings.hud.map_world_span, 0.001,
		"the widget carries the authored MAP span")
	assert_almost_eq(MapScreen._map.effective_world_span(), GameSettings.hud.map_world_span, 0.001,
		"...and answers with it rather than falling back to minimap_world_span")
	assert_gt(MapScreen._map.effective_world_span(), GameSettings.hud.minimap_world_span,
		"the tab must show MORE world than the corner box, or it is just the minimap enlarged")


## The three waypoint view knobs that make this instance the EDITING surface. The HUD corner box ships all
## three off (a 5.5 px glyph has no room for a caption, and rim-pinning every pin turned that box into six
## overlapping glyph stacks) — here they are the whole point: a pin you cannot see is a pin you cannot click.
func test_the_tab_names_every_pin_and_shows_the_ones_off_the_view() -> void:
	assert_true(MapScreen._map.waypoint_labels, "the page-sized map names its pins")
	assert_true(MapScreen._map.dot_waypoints, "...draws the channel at all")
	assert_true(MapScreen._map.waypoint_pin_offscreen,
		"...and rim-pins the ones off the view, because this is the surface you SELECT them on")


## ⭐THE FOOTER HINT AND THE TUTORIAL SWAPPED JOBS. The footer used to carry the whole gesture line and could
## never fit it — the QA shots caught it ellipsized to "[PH] Click to pi…", which teaches nothing while still
## costing the row its width. The footer now states the one fact it can say in three words (the tab is
## north-up while the corner box is heading-up), and the gestures moved onto the plan, where they have the
## panel's whole width.
func test_the_footer_states_the_bearing_and_the_gestures_live_on_the_plan() -> void:
	var hint := MapScreen.get_node("%Hint") as Label
	assert_eq(hint.text, PlayerText.MAP_NORTH_UP,
		"the footer hint names the BEARING — the one thing down there the player genuinely needs")
	assert_eq(hint.autowrap_mode, TextServer.AUTOWRAP_OFF,
		"...and it still may not wrap: this label is the footer's height, and a wrapped one starves the map")
	assert_eq(MapScreen._tutorial.text, PlayerText.MAP_HINT,
		"the gesture tutorial is the label OVER THE PLAN now")
	assert_false(PlayerText.MAP_HINT.contains(PlayerText.PH_PREFIX),
		"both are authored copy — a '[PH]' on the loudest line of the screen is the 'unfinished' signal this pass exists to kill")
	assert_false(PlayerText.MAP_NORTH_UP.contains(PlayerText.PH_PREFIX), "...and so is the footer's")


## ⭐THE TUTORIAL IS AN EMPTY STATE, NOT CHROME. Three conditions, and each one is the difference between
## teaching and wallpaper: the tab is up, this LEVEL's ledger is empty, and nothing is selected. The first pin
## takes it away for good on that level; a fresh level with no pins teaches again.
func test_the_tutorial_shows_only_on_an_empty_map_with_nothing_selected() -> void:
	_arm()
	MapScreen._refresh_card()
	assert_true(MapScreen._tutorial.visible, "an open tab over a level with no pins teaches the gestures")
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	assert_false(MapScreen._tutorial.visible,
		"the first pin proves the player knows the gesture — the line has done its job and goes")
	MapScreen._select(0)
	assert_false(MapScreen._tutorial.visible, "...and a selection puts the card in the same corner of the picture")
	assert_true(GameState.remove_waypoint(LEVEL, 0), "clear the level back down")
	assert_eq(MapScreen._selected, -1, "the ledger emptied, so the selection went with it")
	assert_true(MapScreen._tutorial.visible, "an empty level teaches again — the state is the LEVEL's, not the profile's")
	_disarm()
	MapScreen._refresh_card()
	assert_false(MapScreen._tutorial.visible, "and a shut tab teaches nobody")


## ⭐DARK-ON-DARK, the regression this pins. FOUR of this screen's labels are drawn over the widget's near-black
## plan rather than on the panel's parchment — the on-plan tutorial, the "no plan for this floor" notice and the
## floating card's name and note — and every one of them shipped wearing MenuStyle's PANEL ink, a dark plum
## authored for paper. The QA shots read the screen's only tutorial line and the selected pin's own name as
## invisible smudges (wp_shots7/01, wp_shots7/05). They take the MINIMAP's caption ink instead, outline
## included, because that is the paint the widget already uses to keep a caption legible over both the dark
## backing and the bright wall strokes — one skin family for everything drawn on the plan.
##
## Pinned as a LIST rather than one label at a time: the defect was systemic (four labels, one wrong habit), so
## the invariant worth holding is "nothing this screen floats over the map wears the panel's ink", and a fifth
## overlay added later should have to pass the same bar.
func test_every_label_over_the_plan_wears_the_maps_ink_not_the_panels() -> void:
	var ink: Color = MenuStyle.hud.minimap_waypoint_label_color  # a duck-typed autoload read is a Variant, never `:=`
	var rim: Color = MenuStyle.hud.label_outline_color
	var outline := int(MenuStyle.hud.minimap_waypoint_label_outline_size)
	for l: Label in [MapScreen._tutorial, MapScreen._empty, MapScreen._card_name, MapScreen._card_note]:
		var got: Color = l.get_theme_color(&"font_color")
		# Compared on the HUE alone (alpha carries the dim/full weight, asserted separately below).
		assert_eq(Color(got.r, got.g, got.b), Color(ink.r, ink.g, ink.b),
			"%s is inked from the MAP family — it is drawn on the plan, not on the panel's paper" % l.name)
		assert_ne(got, MenuStyle.dim_color(),
			"%s no longer wears the parchment panel's dim plum, which over a near-black map is an invisible smudge" % l.name)
		assert_ne(got, MenuStyle.text_color(), "...nor its full-strength ink, which is that same plum at a=1 (%s)" % l.name)
		assert_eq(l.get_theme_color(&"font_outline_color"), rim,
			"%s carries the house outline colour" % l.name)
		assert_eq(l.get_theme_constant(&"outline_size"), outline,
			"...at the minimap's own caption outline width — the outline is what carries pale ink across the BRIGHT cyan wall strokes (%s)" % l.name)
	assert_lt(MapScreen._card_note.get_theme_color(&"font_color").a,
		MapScreen._card_name.get_theme_color(&"font_color").a,
		"the card's note is the FOOTNOTE half of the pairing and its name the subject: one ink, two weights")


## ⭐PANNING IS THE ONE GESTURE THAT CANNOT UNDO ITSELF: drag far enough and the player caret is off the view,
## so nothing left on screen points home. Recentre is the way back, and it reports what HAPPENED rather than
## that a button was pressed — a press on an already-centred map claims no move (the _nudge_zoom rule).
func test_recentre_walks_the_view_home_and_refuses_when_it_is_already_there() -> void:
	MapScreen._pan_by(Vector2(25.0, -10.0))
	assert_ne(MapScreen._map.view_offset, Vector2.ZERO, "precondition: the view is off the player")
	MapScreen._on_recentre_pressed()
	assert_eq(MapScreen._map.view_offset, Vector2.ZERO, "Recentre puts the pan back on the player")
	MapScreen._on_recentre_pressed()
	assert_eq(MapScreen._map.view_offset, Vector2.ZERO, "...and a second press moves nothing")
	# The CUE half is pinned off the source: MenuStyle plays into the audio bus and records nothing a test can
	# read back, and "which sound did that press make" is exactly the fact this button gets wrong if anyone
	# simplifies it (a confirm on a refused press claims a move the player then looks for and cannot find).
	var src := FileAccess.get_file_as_string(SOURCE)
	var from := src.find("func _on_recentre_pressed(")
	var to := src.find("func _centre_view_on(")
	assert_gt(from, 0, "_on_recentre_pressed exists")
	assert_gt(to, from, "...and _centre_view_on follows it")
	var body := src.substr(from, to - from)
	assert_true(body.contains("MenuStyle.play_denied()"),
		"an already-centred map REFUSES out loud rather than sounding a move that did not happen")
	assert_true(body.contains("MenuStyle.play_select()"), "...and a real move confirms")


## The zoom is a PLAYER value (Settings.map_zoom) rather than screen state: it persists, and the Options ->
## Accessibility "Map Zoom" slider writes the same field. _apply_zoom is the single place the stored value
## reaches the widget.
func test_a_zoom_step_writes_the_player_row_and_reaches_the_widget() -> void:
	Settings.set_map_zoom(1.0)
	MapScreen._apply_zoom()
	assert_almost_eq(MapScreen._map.zoom_override, 1.0, 0.0001, "the widget starts on the stored zoom")
	MapScreen._nudge_zoom(1)
	var step: float = GameSettings.hud.map_zoom_wheel_step
	assert_almost_eq(Settings.map_zoom, 1.0 + step, 0.0001, "one notch moves the stored row by one authored step")
	assert_almost_eq(MapScreen._map.zoom_override, Settings.map_zoom, 0.0001,
		"...and _apply_zoom pushes it onto the widget — a write that never lands leaves the picture on the old zoom")
	MapScreen._nudge_zoom(-1)
	assert_almost_eq(Settings.map_zoom, 1.0, 0.0001, "and the step is symmetric")


## Scrolling the page-sized map must not re-zoom the corner box the player is also looking at. They are the
## same widget but two instances with two stored values, which is the whole reason map_zoom exists.
func test_zooming_the_map_leaves_the_hud_minimap_alone() -> void:
	Settings.set_minimap_zoom(1.0)
	Settings.set_map_zoom(1.0)
	MapScreen._nudge_zoom(1)
	assert_almost_eq(Settings.minimap_zoom, 1.0, 0.0001,
		"the HUD minimap's own zoom row is untouched by the map tab's wheel")


## The clamp is the setter's (shared with the minimap row). A step the clamp swallows is a REFUSAL, not a
## step — the cue must not claim a move that never happened (the implants-tab refused-flip rule), and the
## value must stay put rather than drifting past the end of the range.
func test_a_step_past_the_end_of_the_range_is_refused_not_silently_clamped_forward() -> void:
	Settings.set_map_zoom(Settings.MINIMAP_ZOOM_MAX)
	MapScreen._nudge_zoom(1)
	assert_almost_eq(Settings.map_zoom, Settings.MINIMAP_ZOOM_MAX, 0.0001,
		"zooming in at maximum leaves the map exactly where it was")
	Settings.set_map_zoom(Settings.MINIMAP_ZOOM_MIN)
	MapScreen._nudge_zoom(-1)
	assert_almost_eq(Settings.map_zoom, Settings.MINIMAP_ZOOM_MIN, 0.0001,
		"...and likewise at minimum")


## The readout paints through PlayerText + TextFormat (a whole template with the number substituted as a
## VALUE), never a hand-built string — the text-debt ratchet owns every painted literal in this project.
func test_the_zoom_readout_is_a_substituted_template() -> void:
	Settings.set_map_zoom(1.5)
	MapScreen._apply_zoom()
	assert_eq(MapScreen._zoom_value.text,
		TextFormat.subst(PlayerText.MAP_ZOOM_READOUT, {"zoom": TextFormat.num(1.5, 2)}),
		"the readout is PlayerText.MAP_ZOOM_READOUT with the live zoom substituted")
	assert_string_contains(MapScreen._zoom_value.text, "1.5")
	Settings.set_map_zoom(1.0)
	MapScreen._apply_zoom()
	assert_string_contains(MapScreen._zoom_value.text, "1")


## The "no plan for this floor" line is the map's answer to minimap.gd's documented silent degrade (an
## unbaked level draws nothing at all). It keys off the widget's own deck_count() introspection seam, and it
## must be HIDDEN whenever there is a deck — a permanently-visible notice over a working map is worse than
## none. In the GUT scene there is no level and no player, so the widget has sliced nothing: the honest
## answer here is "shown".
func test_the_empty_notice_tracks_the_widgets_deck_count() -> void:
	assert_eq(MapScreen._map.deck_count(), 0, "precondition: the GUT scene has no baked level to slice")
	MapScreen._refresh_empty()
	assert_true(MapScreen._empty.visible, "with nothing sliced the map says so instead of showing a blank panel")
	# Fake a sliced deck the way the widget itself would hold one, and the notice must get out of the way.
	MapScreen._map._decks[0] = {"fill": PackedVector2Array(), "idx": PackedInt32Array(),
			"walls": PackedVector2Array(), "y_lo": 0.0, "y_hi": 2.6}
	MapScreen._refresh_empty()
	assert_false(MapScreen._empty.visible, "a floor with a deck draws the plan, with no notice over it")
	MapScreen._map._decks.clear()
	MapScreen._refresh_empty()


# ---------------------------------------------------------------------------------------------------
# The pan (Minimap.view_offset, written from here and nowhere else)
# ---------------------------------------------------------------------------------------------------

## ⭐THE LEASH IS ENFORCED AT THE WRITE SITE, not at the two gestures. Both the drag and the key/stick poll go
## through _pan_by, so neither can walk the map past GameSettings.hud.map_pan_range on its own — and the
## clamp is on the OFFSET's length, because the offset is measured from the player rather than from the world
## origin (walking drags the whole window along).
func test_the_pan_is_clamped_to_the_authored_leash() -> void:
	assert_eq(MapScreen._map.view_offset, Vector2.ZERO, "precondition: the view starts on the player")
	MapScreen._pan_by(Vector2(10.0, -4.0))
	assert_almost_eq(MapScreen._map.view_offset.x, 10.0, 0.001, "a pan inside the leash lands exactly")
	assert_almost_eq(MapScreen._map.view_offset.y, -4.0, 0.001, "...on both axes")
	MapScreen._pan_by(Vector2(100000.0, 0.0))
	assert_almost_eq(MapScreen._map.view_offset.length(), GameSettings.hud.map_pan_range, 0.05,
		"a pan past the leash stops AT it — the map can be dragged a district away, not to the origin of the coordinate system")
	MapScreen._reset_view()
	assert_eq(MapScreen._map.view_offset, Vector2.ZERO, "_reset_view pins the map back on the player")


## A pan is a GESTURE, not a preference: the zoom persists to settings.cfg on purpose and the pan must not,
## or a map reopened 300 m off the player reads as a broken screen showing the wrong place. open() cannot be
## driven from a unit test (it wants a live human Player in-tree), so the CALL is pinned off the source and
## the BEHAVIOUR by the test above.
func test_open_puts_the_view_back_on_the_player() -> void:
	var src := FileAccess.get_file_as_string(SOURCE)
	var from := src.find("func open(")
	var to := src.find("func close(")
	assert_gt(from, 0, "open() exists")
	assert_gt(to, from, "...and close() follows it")
	assert_true(src.substr(from, to - from).contains("_reset_view()"),
		"open() re-centres the view on the player — a pan must not survive the tab being shut")


# ---------------------------------------------------------------------------------------------------
# The pointer gestures (driven through the overlay's own handler)
# ---------------------------------------------------------------------------------------------------

## THE HEADLINE FIX, pinned: a press and release on empty plan PINS — quietly. It used to open a modal and
## ask for a name (and, in the shipped build, do nothing at all — the click never reached the screen). The
## card does NOT appear: a click-placed pin no longer selects itself, which is what keeps chained placement
## at one click per pin AND leaves "click empty space" free to mean dismiss (the next test).
func test_a_click_on_empty_plan_places_a_pin_immediately() -> void:
	_arm()
	MapScreen._on_map_gui_input(_press(Vector2(40, 30)))
	MapScreen._on_map_gui_input(_release(Vector2(40, 30)))
	assert_eq(GameState.waypoints_for(LEVEL).size(), 1, "the click PINS — no card, no typing, no Enter")
	assert_eq(MapScreen._selected, -1, "...and selects NOTHING: the card only appears when asked for")
	assert_false(MapScreen._card.visible, "no uninvited card over the map the player is annotating")
	assert_false(MapScreen._prompt.is_open(), "the editor card is not part of placement any more")
	var rec := GameState.waypoint_at(LEVEL, 0)
	assert_false(String(rec.get("name", "")).is_empty(), "the pin is auto-named from its ordinal")
	assert_false(String(rec.get("name", "")).contains("[PH]"),
		"...with the placeholder marker STRIPPED — a seeded name is saved player data, not copy")
	# The chain IS the point: a second click is a second pin, one click per pin, no dismissal tax between.
	MapScreen._on_map_gui_input(_press(Vector2(80, 60)))
	MapScreen._on_map_gui_input(_release(Vector2(80, 60)))
	_disarm()
	assert_eq(GameState.waypoints_for(LEVEL).size(), 2, "chained placement stays one click per pin")


## THE STUCK-BOX REGRESSION, pinned from the playtest that found it: place a pin, click the pin (the card
## comes up), then click empty plan to dismiss it — the universal popup instinct. That click must DESELECT
## and must NOT mint another pin; before this rule it did, and the only ways out of the card were gestures
## nobody guessed (right-click, staged Esc — both still work, this adds the one everyone tries first).
func test_a_click_away_dismisses_the_card_instead_of_minting_a_pin() -> void:
	_arm()
	MapScreen._on_map_gui_input(_press(Vector2(40, 30)))
	MapScreen._on_map_gui_input(_release(Vector2(40, 30)))
	MapScreen._click_select(0)
	assert_true(MapScreen._card.visible, "precondition: the card is up for the selected pin")
	MapScreen._on_map_gui_input(_press(Vector2(120, 80)))
	MapScreen._on_map_gui_input(_release(Vector2(120, 80)))
	_disarm()
	assert_eq(MapScreen._selected, -1, "the click-away DESELECTED")
	assert_false(MapScreen._card.visible, "...and the card is gone")
	assert_eq(GameState.waypoints_for(LEVEL).size(), 1,
		"...and NO pin was minted by the dismissal — the stuck-box bug was players clicking away and pinning instead")


## The pad's Place button is the ONE placement path that still selects: a pad has no cursor hovering the new
## pin, so selection is its only one-press road to Edit. The asymmetry with the click path is each input's
## own grammar, not an accident.
func test_the_place_button_selects_what_it_places() -> void:
	_arm()
	MapScreen._on_place_pressed()
	_disarm()
	assert_eq(GameState.waypoints_for(LEVEL).size(), 1, "the button placed at the view centre")
	assert_eq(MapScreen._selected, 0, "...and selected it — the pad's road to Edit")
	assert_true(MapScreen._card.visible, "...so the card is up with the verbs a pad needs next")


## The other half of the same gesture: a DRAG pans and must not also pin. Six pixels of slop is what separates
## the two, because every real click wobbles a pixel or two.
func test_a_drag_pans_the_view_and_never_places_a_pin() -> void:
	_arm()
	MapScreen._on_map_gui_input(_press(Vector2(40, 30)))
	MapScreen._on_map_gui_input(_motion(Vector2(80, 30), Vector2(40, 0)))
	MapScreen._on_map_gui_input(_release(Vector2(80, 30)))
	_disarm()
	var ppm: float = MapScreen._map.pixels_per_metre()
	assert_gt(ppm, 0.0, "precondition: the widget answers a scale")
	assert_lt(40.0 / ppm, GameSettings.hud.map_pan_range,
		"precondition: a 40 px drag is well inside the leash at this widget's scale, so the clamp is not what is being measured")
	assert_almost_eq(MapScreen._map.view_offset.x, -40.0 / ppm, 0.01,
		"dragging the paper RIGHT walks the window LEFT by the dragged distance in METRES — the plan follows the hand")
	assert_eq(GameState.waypoints_for(LEVEL).size(), 0,
		"a drag is not a click: the release that ends a pan must never drop a pin")


func test_a_wobble_inside_the_slop_window_is_still_a_click() -> void:
	_arm()
	MapScreen._on_map_gui_input(_press(Vector2(40, 30)))
	MapScreen._on_map_gui_input(_motion(Vector2(43, 31), Vector2(3, 1)))
	MapScreen._on_map_gui_input(_release(Vector2(43, 31)))
	_disarm()
	assert_eq(MapScreen._map.view_offset, Vector2.ZERO, "three pixels is a hand, not a drag — the view did not move")
	assert_eq(GameState.waypoints_for(LEVEL).size(), 1, "...and the release still counted as a click")


## The wheel is MAP_HINT's third promise, and the one the old %Root wiring never actually delivered (the
## shipped comment claiming it worked had never been driven by anything but a direct _nudge_zoom call).
func test_the_wheel_over_the_plan_zooms() -> void:
	Settings.set_map_zoom(1.0)
	_arm()
	MapScreen._on_map_gui_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	_disarm()
	assert_almost_eq(Settings.map_zoom, 1.0 + GameSettings.hud.map_zoom_wheel_step, 0.0001,
		"a notch over the plan steps the map's own zoom row")


## ⭐THE WHEEL ZOOMS ABOUT THE CURSOR. Centre-zoom is what it did before, and on a map it is subtly wrong every
## time: the player points at the thing they want a closer look at, and centre-zoom slides it out from under
## them, so reaching a corner of the district took a zoom-pan-zoom shuffle. The invariant is exactly one
## sentence — the world point under the pointer is the same world point after the step.
func test_the_wheel_zooms_about_the_cursor() -> void:
	# ⭐A REAL RECT, HANDED DIRECTLY. Headless GUT never lays the hidden autoload out, and
	# FloorplanSection.px_per_metre answers 1.0 for a ZERO rect at every zoom — which makes the whole
	# cursor-anchor invariant vacuously true and the pan assertion false. Writing `size` on the anchored
	# widget sticks for the synchronous body of a test (no frame is processed), the test_minimap idiom.
	MapScreen._map.size = Vector2(529.0, 191.0)
	Settings.set_map_zoom(1.0)
	MapScreen._apply_zoom()
	var at := Vector2(18.0, 12.0)  # deliberately NOT the view centre: centre-zoom would pass a centred probe
	var local := MapScreen._map_local(at)
	var was_ppm: float = MapScreen._map.pixels_per_metre()
	var before: Vector3 = MapScreen._map.point_to_world(local)
	_arm()
	MapScreen._on_map_gui_input(_wheel(MOUSE_BUTTON_WHEEL_UP, at))
	_disarm()
	assert_almost_eq(Settings.map_zoom, 1.0 + GameSettings.hud.map_zoom_wheel_step, 0.0001, "the notch landed")
	assert_ne(MapScreen._map.pixels_per_metre(), was_ppm,
		"precondition: the widget has a real rect, so a zoom step really does change its scale")
	var after: Vector3 = MapScreen._map.point_to_world(local)
	assert_almost_eq(after.x, before.x, 0.05, "the metre under the cursor is still under the cursor (X)")
	assert_almost_eq(after.z, before.z, 0.05, "...and on Z")
	assert_ne(MapScreen._map.view_offset, Vector2.ZERO,
		"...and it stayed there by PANNING, which is the only lever this screen has over the view")


## The FOOTER's zoom buttons keep centre-zoom, and that is deliberate rather than an oversight: a button press
## has no cursor over the plan to zoom about, and anchoring on wherever the pointer happens to be resting (or,
## on a pad, nowhere) would make the map lurch for no reason the player could name.
func test_the_footer_zoom_buttons_keep_centre_zoom() -> void:
	Settings.set_map_zoom(1.0)
	MapScreen._apply_zoom()
	MapScreen._nudge_zoom(1)
	assert_eq(MapScreen._map.view_offset, Vector2.ZERO,
		"a button zoom moves the scale and nothing else — there is no cursor for it to anchor on")


# ---------------------------------------------------------------------------------------------------
# The selection and its three verbs
# ---------------------------------------------------------------------------------------------------

## The card is the selection's whole UI, so it must appear and vanish WITH one — an empty details panel is
## chrome that teaches nothing, and the footer hint is this tab's only tutorial line.
func test_the_card_follows_the_selection_and_carries_the_pins_note() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "Door", "it was locked", 0, 0)
	GameState.add_waypoint(LEVEL, Vector3(5, 0, 5), "Bare", "", 0, 0)
	MapScreen._select(0)
	assert_true(MapScreen._card.visible, "a selection shows the card")
	assert_eq(MapScreen._card_note.text, "it was locked", "the note is the pin's own words")
	assert_eq(MapScreen._card_note.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED,
		"player-typed text is never looked up as a msgid")
	MapScreen._select(1)
	assert_eq(MapScreen._card_note.text, PlayerText.MAP_PIN_NO_NOTE, "a pin with no note keeps the row's height")
	assert_eq(MapScreen._card_note.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_INHERIT,
		"...and THAT line is authored copy, which a shipped locale must be able to translate")
	MapScreen._select(-1)
	assert_false(MapScreen._card.visible, "no selection, no card")


## The pad's selection path: pin -> pin -> ... -> none -> pin. The wrap through "none" is what keeps ONE
## button sufficient for both selecting and deselecting.
func test_next_cycles_through_none() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	GameState.add_waypoint(LEVEL, Vector3.ONE, "b", "", 0, 0)
	MapScreen._select(-1)
	MapScreen._on_next_pressed()
	assert_eq(MapScreen._selected, 0, "from nothing, the first pin")
	MapScreen._on_next_pressed()
	assert_eq(MapScreen._selected, 1, "...then the second")
	MapScreen._on_next_pressed()
	assert_eq(MapScreen._selected, -1, "...then back through 'none', which is how one button also deselects")


## ⭐THE MAP FOLLOWS THE CYCLE. Without this, Next Pin on a panned or zoomed-in map selects pins the player
## cannot see — the card names one, the ring is off the plan somewhere, and the button reads as broken on any
## level with pins in two buildings. Following turns the same button into "review my pins".
func test_next_pin_brings_each_pin_into_view() -> void:
	GameState.add_waypoint(LEVEL, Vector3(40.0, 0.0, -25.0), "far", "", 0, 0)
	GameState.add_waypoint(LEVEL, Vector3(-18.0, 0.0, 12.0), "other", "", 0, 0)
	MapScreen._select(-1)
	MapScreen._on_next_pressed()
	assert_eq(MapScreen._selected, 0, "precondition: the cycle picked the first pin")
	_assert_view_centred_on(Vector3(40.0, 0.0, -25.0), "the view walked to the pin the button just selected")
	MapScreen._on_next_pressed()
	_assert_view_centred_on(Vector3(-18.0, 0.0, 12.0), "...and follows the cycle to the next one")
	var was: Vector2 = MapScreen._map.view_offset
	MapScreen._on_next_pressed()
	assert_eq(MapScreen._selected, -1, "the wrap lands on 'none'")
	assert_eq(MapScreen._map.view_offset, was,
		"...and moves nothing: there is no pin to look at, so yanking the view would be motion without a subject")


## ⭐THE FOLLOW-UP SELECTION IS DECIDED BEFORE THE MUTATION. remove_waypoint emits waypoints_changed
## SYNCHRONOUSLY and _on_waypoints_changed re-enters _select mid-call, so a version that read `_selected`
## after the remove lost the selection on every tail delete.
func test_delete_keeps_a_selection_so_a_run_of_deletes_needs_no_re_clicking() -> void:
	for i in 3:
		GameState.add_waypoint(LEVEL, Vector3(float(i), 0, 0), "p%d" % i, "", 0, 0)
	MapScreen._select(1)
	MapScreen._on_delete_pressed()
	assert_eq(GameState.waypoints_for(LEVEL).size(), 2, "the pin is gone")
	assert_eq(MapScreen._selected, 1, "the selection moved to the pin that took its index")
	MapScreen._on_delete_pressed()
	assert_eq(MapScreen._selected, 0, "deleting the TAIL falls back to the new last pin, not to nothing")
	MapScreen._on_delete_pressed()
	assert_eq(MapScreen._selected, -1, "...and the empty list finally clears it")
	assert_false(MapScreen._card.visible, "the card goes with it")


## ONE tracked pin per profile, and the caption says what the press will DO. GameState moves the flag rather
## than setting it, so tracking a second pin unticks the first with no bookkeeping on this screen.
func test_track_moves_the_one_navigation_marker_and_swaps_the_caption() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	GameState.add_waypoint(LEVEL, Vector3.ONE, "b", "", 0, 0)
	MapScreen._select(0)
	assert_eq(MapScreen._track_btn.text, PlayerText.MAP_PIN_TRACK, "an untracked pin offers Track")
	MapScreen._on_track_pressed()
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 0}, "the flag landed on the selected pin")
	assert_eq(MapScreen._track_btn.text, PlayerText.MAP_PIN_UNTRACK, "...and the caption now offers the way back")
	MapScreen._select(1)
	MapScreen._on_track_pressed()
	assert_eq(GameState.tracked_waypoint(), {"level": LEVEL, "index": 1},
		"tracking is a MOVE — the second pin takes the marker")
	MapScreen._on_track_pressed()
	assert_eq(GameState.tracked_waypoint(), {}, "pressing it again untracks outright")
	assert_eq(MapScreen._track_btn.text, PlayerText.MAP_PIN_TRACK, "...and the caption follows")


## ⭐A CLICK ON A RIM-PINNED GLYPH FETCHES THE PIN; A CLICK ON A PIN THAT IS REALLY THERE MOVES NOTHING.
## The tab rim-pins everything off the view, so a glyph stuck to the edge of the plan is a pin that is NOT on
## the plan — selecting it would ring a marker the player cannot see and light up three verbs aimed off-screen.
## The other half matters just as much: yanking the map under a player who clicked something they were looking
## straight at is the exact opposite of the fix.
func test_clicking_a_rim_pinned_glyph_fetches_the_pin_while_an_on_plan_click_does_not() -> void:
	MapScreen._map.size = Vector2(529.0, 191.0)  # the wheel test's zero-rect note applies verbatim
	var view_px: Vector2 = MapScreen._map.size
	var ppm: float = MapScreen._map.pixels_per_metre()
	assert_gt(ppm, 0.0, "precondition: the widget answers a scale")
	# 1.3 view half-widths out: comfortably past the rect edge, and well inside the pan leash so the fetch is
	# not measuring the clamp. Derived from the LIVE rect rather than hardcoded — the GUT window is not the game's.
	var far_m: float = view_px.x * 0.5 / ppm * 1.3
	assert_lt(far_m, GameSettings.hud.map_pan_range,
		"precondition: the far pin is inside the leash, so _centre_view_on can actually reach it")
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "here", "", 0, 0)            # 0: dead centre, on the plan
	GameState.add_waypoint(LEVEL, Vector3(far_m, 0.0, 0.0), "yonder", "", 0, 0)  # 1: off the view, rim-pinned
	assert_false(MapScreen._pin_is_off_the_plan(0), "precondition: pin 0 is drawn where it actually is")
	assert_true(MapScreen._pin_is_off_the_plan(1), "precondition: pin 1 can only be drawn as a rim pin")
	MapScreen._select(-1)
	_arm()
	MapScreen._click_map(view_px * 0.5)
	assert_eq(MapScreen._selected, 0, "the centre click selected the pin that is there")
	assert_eq(MapScreen._map.view_offset, Vector2.ZERO,
		"...and did NOT move the view: the player was already looking at it")
	var rim := _click_point_for(1)
	assert_ne(rim, Vector2.INF, "precondition: the widget's own hit test accepts a click somewhere on the rim glyph")
	MapScreen._click_map(rim)
	_disarm()
	assert_eq(MapScreen._selected, 1, "the rim glyph selected its pin")
	_assert_view_centred_on(Vector3(far_m, 0.0, 0.0),
		"...and the map went and got it, so the selection ring is on a pin the player can see")


## ⭐THERE IS NOW A MOUSE WAY OUT OF A SELECTION. A left click on empty plan PLACES, so before this the only
## way to drop a selection with the mouse was to place a pin you did not want. An idle right-click refuses
## nothing, so it says nothing and changes nothing.
func test_right_click_deselects_and_an_idle_one_does_nothing() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	MapScreen._select(0)
	_arm()
	MapScreen._on_map_gui_input(_right_press(Vector2(40, 30)))
	assert_eq(MapScreen._selected, -1, "right-click drops the selection")
	assert_false(MapScreen._card.visible, "...and the card goes with it")
	MapScreen._on_map_gui_input(_right_press(Vector2(40, 30)))
	_disarm()
	assert_eq(MapScreen._selected, -1, "a second one changes nothing")
	assert_eq(GameState.waypoints_for(LEVEL).size(), 1,
		"and a right-click NEVER places — that is the left button's job on empty plan")


## ⭐ESC IS STAGED: card, then selection, then the tab. Two Escs from a selected pin read as "drop the pin,
## close the map" rather than "close the map and leave a ring armed on a screen you can no longer see".
##
## Only the DESELECT stage is driven here. The close stage wants a live Player in-tree (see the header) and is
## pinned off the source instead — what must hold there is that the branch exists at all.
func test_escape_drops_the_selection_before_it_closes_the_tab() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	MapScreen._select(0)
	_arm()
	MapScreen._on_escape()
	assert_eq(MapScreen._selected, -1, "the first Esc spends itself on the selection")
	assert_true(MapScreen.is_open(), "...and the tab is still up — a player must SEE the first half happen")
	_disarm()
	var src := FileAccess.get_file_as_string(SOURCE)
	var from := src.find("func _on_escape(")
	assert_gt(from, 0, "_on_escape exists")
	var body := src.substr(from, 260)
	assert_true(body.contains("_deselect()"), "stage one is the selection")
	assert_true(body.contains("close()"), "...and stage two closes the tab")


## ⭐EVERY VERB REFUSES WHILE THE EDITOR CARD IS UP. The card's scrim stops the MOUSE, but focus is a second
## input path: a pad that walked focus out from under the card could otherwise delete the very pin being
## edited, zoom the map out from under it, or open the card over itself.
func test_every_verb_refuses_while_the_editor_card_is_open() -> void:
	GameState.add_waypoint(LEVEL, Vector3.ZERO, "a", "", 0, 0)
	MapScreen._select(0)
	Settings.set_map_zoom(1.0)
	MapScreen._pan_by(Vector2(12.0, 0.0))
	MapScreen._on_edit_pressed()
	assert_true(MapScreen._prompt.is_open(), "precondition: the editor is up")
	MapScreen._on_delete_pressed()
	MapScreen._on_recentre_pressed()
	MapScreen._on_next_pressed()
	MapScreen._on_track_pressed()
	MapScreen._on_place_pressed()
	MapScreen._nudge_zoom(1)
	_arm()
	MapScreen._on_map_gui_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	MapScreen._on_map_gui_input(_press(Vector2(40, 30)))
	MapScreen._on_map_gui_input(_release(Vector2(40, 30)))
	_disarm()
	assert_eq(GameState.waypoints_for(LEVEL).size(), 1,
		"nothing was deleted and nothing was placed under the open card")
	assert_eq(MapScreen._selected, 0, "the selection did not move")
	assert_eq(GameState.tracked_waypoint(), {}, "and the tracked flag was not touched")
	assert_almost_eq(Settings.map_zoom, 1.0, 0.0001, "the map did not zoom out from under the pin being edited")
	assert_ne(MapScreen._map.view_offset, Vector2.ZERO,
		"...and the plan was not recentred out from under it either — the same argument as the zoom guard")
	MapScreen._prompt.close()


# ---------------------------------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------------------------------

## Flip the open latch by hand — see the header. Restored by _disarm (and by after_each, belt and braces),
## never by close(), which would drive PlayerMenus.leave() for an enter() that never happened.
func _arm() -> void:
	MapScreen._is_open = true

func _disarm() -> void:
	MapScreen._is_open = false

func _press(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	return e

func _release(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = at
	return e

func _right_press(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = at
	return e

## The wheel notch. `at` matters now that the wheel zooms ABOUT THE CURSOR — the default keeps the older tests
## reading as they did, which is exactly right for them: they are about the STEP, not about the anchor.
func _wheel(button: int, at: Vector2 = Vector2(40, 30)) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = at
	return e

func _motion(at: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.relative = rel
	return e

## "Is `pos` what the middle of the plan is showing?" — asked through the widget's OWN inverse projection
## rather than by comparing view_offset to a number this file worked out. The offset is measured off the
## player, whose position a test does not control; what the player actually SEES is the invariant, and it holds
## whatever the host's centre happens to be.
func _assert_view_centred_on(pos: Vector3, msg: String) -> void:
	var view_px: Vector2 = MapScreen._map.size
	var centre: Vector3 = MapScreen._map.point_to_world(view_px * 0.5)
	assert_almost_eq(centre.x, pos.x, 0.5, "%s (X)" % msg)
	assert_almost_eq(centre.z, pos.z, 0.5, "%s (Z)" % msg)


## Where the widget will actually ACCEPT a click for pin `index`, found by asking its own hit test
## (waypoint_at_point) along the line from the view centre out to the pin's RAW projection — which is the line
## a rim pin is clipped onto (Minimap._marker_point -> Compass.project_to_edge scales the direction, it does
## not bend it). Deliberately NOT a second copy of the rim maths: "two constructions of the same projection
## drift apart and nothing looks wrong until a player uses it" is the defect minimap.gd's view_matrix() note
## exists to warn about, and a test that re-derived the rim would agree with itself while disagreeing with the
## map. Vector2.INF means the widget never offered a clickable point, which is a failure worth seeing.
func _click_point_for(index: int) -> Vector2:
	var map: Variant = MapScreen._map
	var rec := GameState.waypoint_at(LEVEL, index)
	var pos: Variant = rec.get("pos")
	if not (pos is Vector3):
		return Vector2.INF
	var world := pos as Vector3
	var view: Transform2D = map.view_matrix()
	var view_px: Vector2 = map.size
	var centre := view_px * 0.5
	var raw: Vector2 = view * Vector2(world.x, world.z)
	# Walked from the raw point INWARD, finely enough that a step is well under the glyph's own click radius.
	for i in 513:
		var at := centre.lerp(raw, 1.0 - float(i) / 512.0)
		if int(map.waypoint_at_point(at)) == index:
			return at
	return Vector2.INF
