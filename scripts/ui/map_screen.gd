extends CanvasLayer
## MapScreen — the MAP tab, opened with its own key (InputManager.action_map, default M). Registered as an
## autoload, mirroring StatsScreen / ImplantsScreen / QuestJournal, and the sixth member of the Pip-Boy tab
## group (Inventory / Stats / Implants / Map / Reputation / Journal). Like the other player menus it does NOT
## pause the world — you stay vulnerable while reading it — and it frees the mouse (restored on close).
##
## ⭐IT DRAWS NOTHING ITSELF. The body of this screen is a SECOND INSTANCE of the HUD minimap widget
## (scripts/ui/minimap.gd, authored into scenes/ui/map_screen.tscn as %Map), so the page-sized map and the
## corner box are ONE picture at two sizes: the same navmesh floor fill, the same section-cut walls, the same
## POI / station / NPC marker channels, the same skin, the same per-floor deck cache, the same idle gate. A
## bug fixed in one is fixed in both, and an artist who restyles hud_skin.tres restyles both. What this screen
## owns is the differences a full-panel read needs, all authored on the widget's "Instance view" exports:
##   * world_span_override = GameSettings.hud.map_world_span — a district, not a room (pushed in _bind_ui,
##     because a .tscn cannot reference a tuning resource);
##   * zoom_override = Settings.map_zoom — its OWN zoom, so scrolling the map never moves the HUD box;
##   * heading = NORTH_UP — a map you READ wants a fixed bearing (the corner box stays heading-up);
##   * zoom_key_enabled = false — the "Cycle Minimap Zoom" key belongs to the HUD box alone; this screen's
##     zoom is the wheel plus the two footer buttons;
##   * waypoint_labels / waypoint_pin_offscreen = true — this is the EDITING surface for the player's pins, so
##     it names every pin and rim-pins the ones off the view; the 108 px corner box does neither (see D5 in
##     minimap.gd's waypoint_pin_offscreen note — every pin rim-pinning on the HUD box was a bug);
##   * view_offset — the pan, written here and nowhere else (see THE MAP IS THE PAGE below).
## Everything else about the plan is the widget's; do not add a second draw path here.
##
## THE MAP IS THE PAGE. %VBox holds exactly three children — the tab strip's slot, %MapHost (which EXPANDs and
## takes everything between them), and the footer. Nothing is ever stacked between them again: the pin bar and
## note row this screen used to code-insert there squeezed the plan down to a ~120 px letterboxed ribbon on the
## 792x444 canvas (caught by scripts/tools/waypoint_qa_shots.gd, a real windowed run), which is a map you
## cannot navigate by. Pin details FLOAT over the plan instead — see _build_pin_card.
##
## KNOWN COST, accepted: the two instances keep SEPARATE FloorplanSource gathers and deck caches, so the FIRST
## open of this tab in a level pays one wall-geometry gather (the same one the HUD box already paid at level
## load) as a single-frame hitch, and the two caches then hold duplicate vertex buffers for the floors you
## have visited. Sharing them would mean a per-level cache with its own staleness question, which is exactly
## what minimap.gd's region-instance-id rebake exists to avoid; the duplicate is small and self-heals on a
## level swap. If the hitch ever becomes visible, warm the gather rather than merging the caches.
##
## AUTHORED SCENE: the layout lives in scenes/ui/map_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters) on top — with ONE documented exception: a Label drawn OVER
## the plan takes its COLOUR from _ink_over_the_plan instead, because the MenuStyle adopters ink for the
## parchment panel and this screen's overlays sit on a near-black map. NO text is authored in the scene — every string is
## set here from PlayerText (l10n + the text-debt ratchet own strings, never a .tscn). The PlayerMenus tab
## strip stays CODE-BUILT into the authored %TabSlot (the strip's one-Button-per-tab structure is a
## cross-screen contract owned by player_menus.gd, not this scene), and so are the three runtime surfaces this
## script adds inside %MapHost — the input overlay, the on-plan tutorial and the floating pin card, in that
## child order — plus the editor card, which goes on %Root because it must cover the whole screen.
## tests/test_map_screen_scene.gd pins the authored wiring; tests/test_map_screen.gd covers the pure rules.
##
## THE SECOND VERB: PLAYER WAYPOINTS. Beyond zoom and pan this screen is where map pins are authored — click
## empty plan to DROP one immediately (no name box: the pin is seeded with its ordinal and the card is for
## re-authoring it afterwards), click a pin to select it, click the selected pin to open its editor. The pins
## themselves live in GameState's per-level waypoint ledger (records shaped by scripts/world/waypoint_book.gd)
## and are PAINTED by the same widget that draws everything else here, so this script owns only the gestures
## and the selection. Nothing is spawned into the world for a pin — the HUD box and the heading tape read the
## same ledger — so there is no lifecycle here either; see Minimap._paint_waypoints for why that is the design
## rather than a shortcut.
##
## ⭐ALL POINTER INPUT ARRIVES THROUGH ONE CODE-BUILT OVERLAY (%MapHost/MapInput — see _build_map_input), never
## by bubbling. This screen used to hang gui_input on %Root and rely on clicks over the plan walking up the
## container stack to it; the QA harness proved they never arrive (`QA_CLICK card_open=false` on a real
## injected click), and the wheel-over-plan claim in the comments beside it had never been live-verified
## either. A Control that owns the rect owns the events — there is nothing to reason about.
##
## THE FULL POINTER VOCABULARY, so the next reader does not have to assemble it from five handlers: LEFT click
## empty plan places, LEFT click a pin selects, LEFT click the selected pin edits, LEFT drag pans, RIGHT click
## deselects, the WHEEL zooms ABOUT THE CURSOR (the footer's zoom buttons keep centre-zoom — they have no
## cursor to zoom about), and Esc STAGES: it closes an open editor card, else drops the selection, else closes
## the tab. The overlay wears a CROSS cursor to say the surface is placeable and swaps to DRAG while panning.
## Between them these are the whole reason the tab is usable with one hand on the mouse.
##
## ⭐THE SELECTION IS A PLAIN INDEX INTO A MUTABLE ARRAY, which means it goes stale the moment anything else
## changes the ledger (the in-world Mark key while this tab is open, a delete, a level swap). It is re-validated
## on GameState.waypoints_changed rather than trusted — see _on_waypoints_changed.

signal opened
signal closed


const PANEL_MARGIN := 0.12  ## same border as the other inventory-style screens — shared chrome (authored on the scene's Panel anchors; tests pin the band)
const PlayerMenus := preload("res://scripts/ui/player_menus.gd")  ## tab-group helper (Inventory/Stats/Implants/Map/Reputation/Journal)
## The pin editor card, and the record rules its fields clamp against. Both preloaded BY PATH and left
## untyped: neither carries a class_name, so this autoload's parse never waits on the editor's class cache
## (the same guard `_map` itself is kept untyped for).
const WAYPOINT_PROMPT := preload("res://scripts/ui/waypoint_prompt.gd")
const WAYPOINT_BOOK := preload("res://scripts/world/waypoint_book.gd")

## How far the pointer must travel, in CANVAS pixels, before a held left button stops being a click and becomes
## a pan. Without a slop window a drag of one or two pixels — which every real click has — would either place a
## pin you meant to drag or drag a map you meant to click. Six is about the wobble of a deliberate click at
## 792x444 and still well under any intentional drag.
const PAN_DRAG_SLOP_PX := 6.0
## The floating pin card's inset from the map's bottom-left corner, and the width it never shrinks below (a
## card that hugged its content would jump every time the selection moved between a short name and a long one
## — the house "menus don't shift OR resize with text" rule applied to an overlay).
const CARD_MARGIN_PX := 8.0
const CARD_MIN_WIDTH_PX := 220.0
## Note lines the card shows — as a FLOOR (custom_minimum_size) and as a CEILING (max_lines_visible), so the
## card is exactly this tall whether the pin carries no note or three sentences. The overflow ellipsizes; the
## whole note is always readable in the editor card, which is where notes are for.
const CARD_NOTE_LINES := 2
## Opacity of the card's panel over the plan. The card sits ON the map and hides whatever it covers, so it is
## deliberately see-through enough to read the floorplan under it while still backing its own text.
const CARD_PANEL_ALPHA := 0.82
## Width floor for the Track button alone. Its caption SWAPS between two words of different lengths, and a row
## button whose width follows its caption would resize the card every time the player tracked a pin — so this
## one is capped (clip_text) and pinned instead. Its two neighbours carry fixed captions and size themselves.
const TRACK_BTN_MIN_PX := 96.0
## The on-plan tutorial's distance up from the map's bottom edge. It sits LOW rather than dead centre so it
## cannot overprint %Empty ("no map data for this floor"), which is centred and can be up at the same time —
## an unbaked level with no pins would otherwise paint two lines through each other. Low is also where the
## eye already is: the footer and its controls are down there.
const TUTORIAL_BOTTOM_PX := 14.0
## How much of the plan's ink a FOOTNOTE keeps — the floating card's note body against the pin name above it.
## The parchment skin states the same pairing as text_color a=1.0 against text_dim_color a=0.72; borrowed
## rather than re-picked so both families keep the same relationship if an artist re-inks either of them.
## See _ink_over_the_plan, which is where the number is spent.
const PLAN_INK_DIM := 0.72

var _root: Control
## The authored Minimap instance (%Map). UNTYPED on purpose, the ui.gd idiom: typing it `Minimap` would make
## this autoload's parse depend on that class_name being in the editor's global cache, and a stale cache would
## take the whole screen (and every autoload after it) down rather than degrading. Null is a legitimate state
## — a renamed node, a transient reimport — so every touch below is guarded.
var _map = null
var _empty: Label = null          ## the "this floor has no plan" line, shown OVER the widget when it has no deck
var _zoom_value: Label = null
var _is_open := false
## --- the pointer overlay (code-built into %MapHost — see _build_map_input) ---
var _input: Control = null        ## full-rect, MOUSE_FILTER_STOP: the ONLY pointer path onto the plan
var _pressing := false            ## a left button is down on the plan
var _panning := false             ## ...and it has travelled past PAN_DRAG_SLOP_PX, so the release is not a click
var _press_at := Vector2.ZERO     ## where that press landed, in overlay-local pixels
## The EMPTY-STATE tutorial, painted over the plan while this level has nothing on it — see _build_map_tutorial.
var _tutorial: Label = null
## --- the floating selection card (code-built into %MapHost — see _build_pin_card) ---
var _prompt = null                ## the WaypointPrompt editor; untyped for the preload-by-path reason above
var _card: PanelContainer = null  ## the whole card — hidden whenever nothing is selected
var _card_name: Label = null      ## the selected pin's own typed name
var _card_note: Label = null      ## its note body, height-pinned so the card cannot resize as selection moves
var _track_btn: Button = null     ## caption swaps Track <-> Untrack with the pin's state
var _edit_btn: Button = null
var _delete_btn: Button = null
## --- the footer's pad/keyboard path (code-built into the authored %Footer) ---
var _next_btn: Button = null      ## cycles the selection — see _on_next_pressed
var _place_btn: Button = null     ## places at the VIEW CENTRE, which with panning reaches the whole map
var _recentre_btn: Button = null  ## puts the pan back on the player — the one gesture panning cannot undo
## Index of the selected pin in GameState.waypoints_for(current level), or -1. Pushed onto the widget as
## `selected_waypoint` (which is part of its idle gate, so the ring repaints even while the player stands
## still) and re-validated on every ledger change.
var _selected: int = -1
## The level `_selected` indexes INTO. A bare index survives a level swap by accident whenever the new
## level's list happens to be long enough — same index, unrelated pin — so the clamp alone is not identity.
## Stamped by _select, compared by _on_waypoints_changed.
var _selected_level: String = ""

func _ready() -> void:
	layer = 120                                  # above the HUD, just under OptionsMenu (128)
	process_mode = Node.PROCESS_MODE_ALWAYS      # keep receiving input + rendering; this tab does NOT pause — the world runs real-time beneath it (Pip-Boy tabs are vulnerable by design)
	_bind_ui()
	_root.visible = false
	# The ledger can change while this tab is OPEN (the in-world Mark key is blocked under a modal, but a
	# level swap and a quickload are not) and while it is SHUT. Connected once here, for the lifetime of the
	# autoload, so a stale selection can never survive a mutation — see _on_waypoints_changed.
	GameState.waypoints_changed.connect(_on_waypoints_changed)

func is_open() -> bool:
	return _is_open

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

## Open the map. Refuses over the non-player modals, mid-death, AND when there is NO human player (start menu
## / character creation) — the plan is centred on the player, so without one there is nothing to draw. Same
## guard shape as Reputation/Journal (the read-only tabs that resolve no `_player` of their own): the widget
## finds the player itself through Groups.human_player, so this screen never holds a reference.
func open() -> void:
	# Block only the NON-player modals; the sibling player menus instead SWITCH to us via close_others.
	if _is_open or DialogueManager.is_active() \
			or InputManager.any_tab_blocking_open() \
			or not PlayerMenus.player_alive(get_tree()) \
			or not PlayerMenus.has_player(get_tree()):
		return
	PlayerMenus.enter(self)  # switch off a sibling + free the cursor (preserves cursor position across switches)
	_is_open = true
	_apply_zoom()  # re-push Settings.map_zoom onto the widget (the Options slider may have moved it while we were shut) + repaint the readout
	_reset_view()  # ...and put the view back on the player: a pan is a gesture, not a saved preference
	_refresh_empty()
	# The ledger may have moved while this tab was shut (the in-world Mark key, a level swap, a load), so the
	# selection is re-validated on every open rather than carried across one.
	_select(_selected)
	_root.visible = true
	# Seed pad/keyboard focus (the OptionsMenu `_first_focus` / implants-tab idiom) AFTER the root shows —
	# grab_focus on a hidden Control does nothing. The focusables are the two zoom buttons, the two footer pin
	# buttons and (while a pin is selected) the floating card's three (the tab strip stays FOCUS_NONE by the
	# cross-screen contract); without a seed a pad player has no focus owner and ui navigation has nowhere to
	# start.
	_focus_controls()
	opened.emit()

func close() -> void:
	if not _is_open:
		return
	# An open editor card must not survive the screen: close() is reachable from OUTSIDE this screen (the M
	# toggle, a sibling tab's hotkey via close_others, the death path) and a card left "open" behind a hidden
	# root is an ARMED INVISIBLE MODAL — its _unhandled_input keeps eating the next Esc anywhere in the game,
	# and its captured commit Callable would fire against whatever level the player is in by then. Silent
	# close (no cue): the map's own transition sound covers it.
	if _prompt != null and _prompt.is_open():
		_prompt.close()
	# A drag that was still in progress dies with the screen. Left armed, the next open would treat the first
	# mouse motion as the continuation of a pan whose button was released behind a closed map.
	_pressing = false
	_panning = false
	_set_pan_cursor(false)  # ...and the closed-hand cursor with it, or the next open opens holding one
	_is_open = false
	_root.visible = false
	PlayerMenus.leave()
	closed.emit()

## ⭐ESC IS STAGED, and the stages are listed innermost-first: the editor card (which eats Esc in its OWN
## _unhandled_input — unhandled input walks the tree bottom-up and the card is a descendant of our root, so it
## has already consumed the event by the time we are asked), then the SELECTION, then the tab. Two Escs from a
## selected pin therefore read as "drop the pin, close the map" rather than "close the map and leave a ring
## armed on a screen you can no longer see" — the Windows-explorer staging every nested selection UI has.
##
## The deselect stage CONSUMES, which is the whole point: without it one Esc would both clear the selection and
## shut the tab, and the player would never see the first half happen.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_map):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed(&"ui_cancel"):
		_on_escape()
		get_viewport().set_input_as_handled()  # consume either way, so OptionsMenu doesn't also open behind us

## One Esc, one stage. Split out of _unhandled_input so the DECISION can be driven by a test without a
## viewport in the loop (set_input_as_handled belongs to the event pump, not to the rule).
func _on_escape() -> void:
	if _selected >= 0:
		_deselect()
		return
	close()

## Two per-frame jobs while the tab is up, and NOTHING while it is shut (the same is_visible_in_tree discipline
## the widget's own _process keeps).
##
## The empty notice has to be POLLED rather than decided once on open: the widget defers its first slice by a
## frame (it rebakes on its first PROCESSED frame, which is after ours), so an open-time read would report "no
## data" on every single open. The pan poll is per-frame by nature — it is a held axis, not an event.
func _process(delta: float) -> void:
	if not _is_open:
		return
	_refresh_empty()
	_pan_from_axes(delta)

# ---------------------------------------------------------------------------------------------------
# Zoom (wheel over the plan, or the two footer buttons for the pad/keyboard path)
# ---------------------------------------------------------------------------------------------------

## Nudge the map's zoom by `dir` authored steps and re-push it. Routed through Settings.set_map_zoom, which
## CLAMPS and persists, so the wheel, the buttons and the Options → Accessibility "Map Zoom" slider are one
## value that survives a quit. The cue reports what actually happened: a step that the clamp swallowed is a
## refusal, not a step — playing the up/down pair at the end of the range would claim a move that never
## happened (the implants-tab refused-flip rule).
func _nudge_zoom(dir: int) -> void:
	if _prompt != null and _prompt.is_open():
		return  # the editor card owns the screen; see the guard note on _on_place_pressed
	var before: float = Settings.map_zoom
	Settings.set_map_zoom(before + float(dir) * GameSettings.hud.map_zoom_wheel_step)
	if is_equal_approx(Settings.map_zoom, before):
		MenuStyle.play_denied()
		return
	MenuStyle.play_step(dir)
	_apply_zoom()

## Push the player's stored zoom onto the widget and repaint the readout. THIS is the only place the two are
## connected: the widget's zoom_override is a plain export, and its own _options_changed stamp (which compares
## the EFFECTIVE zoom, not Settings.minimap_zoom) is what turns the write into a repaint — so a value written
## here bites the next frame with no queue_redraw of ours.
func _apply_zoom() -> void:
	if _map != null:
		_map.zoom_override = Settings.map_zoom
	if _zoom_value != null:
		_zoom_value.text = TextFormat.subst(PlayerText.MAP_ZOOM_READOUT,
				{"zoom": TextFormat.num(Settings.map_zoom, 2)})

## Show the "no plan for this floor" line only when the widget really has nothing sliced. deck_count() is the
## widget's own introspection seam for exactly this question (an unbaked level, or a floor band with no
## walkable polys, both degrade to a blank picture in silence — see minimap.gd's @risk). On the 108 px corner
## box that blankness is ambiguous chrome; on a full panel it reads as a broken screen, so the map says so.
func _refresh_empty() -> void:
	if _empty == null:
		return
	var blank := true
	if _map != null and _map.has_method(&"deck_count"):
		blank = int(_map.deck_count()) <= 0
	_empty.visible = blank

# ---------------------------------------------------------------------------------------------------
# Panning (the drag, and the keys/stick — both write Minimap.view_offset, which is a VIEW term)
# ---------------------------------------------------------------------------------------------------

## Put the view back on the player. Called on every open, because a pan is a GESTURE (where you were looking a
## minute ago) rather than a preference (your zoom, which persists to settings.cfg on purpose): a map that
## reopened 300 m off the player would read as a broken screen showing the wrong place.
func _reset_view() -> void:
	if _map != null:
		_map.view_offset = Vector2.ZERO

## Move the view by `delta_m` WORLD METRES on the XZ plane and clamp the result.
##
## ⭐THE CLAMP LIVES HERE because this is the only write site both gestures share — the drag and the axis poll
## both come through it, so neither can walk the map past the leash on its own. GameSettings.hud.map_pan_range
## is a LEASH off the player rather than a world boundary (the offset is relative, so walking drags the window
## along); zero disables panning outright, which limit_length answers correctly with no special case.
func _pan_by(delta_m: Vector2) -> void:
	if _map == null:
		return
	var off: Vector2 = _map.view_offset  # explicitly typed: a duck-typed host read is a Variant, never `:=`
	_map.view_offset = (off + delta_m).limit_length(maxf(0.0, GameSettings.hud.map_pan_range))

## The keyboard / stick pan, polled per frame while the tab is open. The movement axes are FREE here — the tab
## is in InputManager's modal registry, so gameplay_suppressed() is true and the player is not walking — which
## is what lets the pan use the four keys the player's hand is already on rather than inventing a second set.
##
## The rate is in VIEW-HEIGHTS per second (GameSettings.hud.map_pan_speed), converted to metres against the
## LIVE pixels_per_metre: a metre rate would crawl at the district view and rocket at the room view, while a
## rate in screenfuls covers the same fraction of what the player can SEE at every zoom.
##
## Forward is screen UP is world -Z: get_vector's y is (backward - forward), and the tab is NORTH_UP, so the
## axis vector IS the world XZ delta with no sign fixing (see FloorplanSection.view_transform).
func _pan_from_axes(delta: float) -> void:
	if _map == null or (_prompt != null and _prompt.is_open()):
		return
	var speed: float = GameSettings.hud.map_pan_speed
	if speed <= 0.0:
		return
	var axes := InputManager.get_vector(InputManager.action_left, InputManager.action_right,
			InputManager.action_forward, InputManager.action_backward)
	if axes == Vector2.ZERO:
		return
	var ppm: float = _map.pixels_per_metre()
	var view_h: float = _map.size.y
	if ppm <= 0.0 or view_h <= 0.0:
		return
	_pan_by(axes * (speed * view_h / ppm * delta))

## The footer's Recentre button: the way HOME. Panning is the one gesture on this screen that cannot undo
## itself — drag far enough and the player caret is off the view entirely, so there is nothing left on screen
## pointing at where you actually are, and the only recovery was closing the tab and reopening it.
##
## The cue reports what HAPPENED rather than that a button was pressed (the _nudge_zoom rule): a press on an
## already-centred map is a refusal, and playing the confirm for it would claim a move the player would then
## look for and not find.
func _on_recentre_pressed() -> void:
	# Refuses under the editor card like every other verb — see the guard note on _on_place_pressed. Recentring
	# would drag the plan out from under the very pin being edited, which is the zoom guard's argument exactly.
	if _map == null or (_prompt != null and _prompt.is_open()):
		return
	var off: Vector2 = _map.view_offset  # explicitly typed: a duck-typed host read is a Variant, never `:=`
	if off.is_zero_approx():
		MenuStyle.play_denied()
		return
	_reset_view()
	MenuStyle.play_select()

## Slide the view so the world point `pos` sits at the MIDDLE of the plan. Expressed as a pan DELTA rather than
## as an absolute offset on purpose: `view_offset` is measured off the player (who moves), so the honest
## question is "how far is this pin from what I am looking at", and routing it through _pan_by means the leash
## clamp applies here too — a pin outside map_pan_range comes as close as the leash allows instead of silently
## teleporting the window past it.
func _centre_view_on(pos: Vector3) -> void:
	if _map == null:
		return
	var view_px: Vector2 = _map.size
	var centre: Vector3 = _map.point_to_world(view_px * 0.5)
	_pan_by(Vector2(pos.x - centre.x, pos.z - centre.z))

## Bring the CURRENT selection into view, if there is one and it carries a position. The shared tail of both
## "the selection moved and the map should follow" paths — Next Pin, and a click that landed on a rim-pinned
## glyph (see _click_map).
func _bring_selection_into_view() -> void:
	var rec := GameState.waypoint_at(GameState.current_level_path, _selected)
	var pos: Variant = rec.get("pos")
	if pos is Vector3:
		_centre_view_on(pos as Vector3)

## Is pin `index` drawn OFF the plan — i.e. is the glyph the player can see a RIM PIN rather than the pin
## itself? Answered against the RAW projection (view_matrix() * its world XZ), which is where the pin would be
## if the widget drew it honestly; _marker_point replaces exactly that point with a rim position when it falls
## outside the rect, so "raw is outside the rect" IS the widget's own off-view test, asked the same way.
##
## ⭐The rim glyph is the reason this question exists at all: a rim pin is drawn at a screen point that
## corresponds to no world point, so clicking it selects a pin the player cannot actually see on the plan. The
## answer is to go and get it (see _click_map) — but only then, because recentring on a pin that was already
## on the plan would yank the map under a player who just clicked something they were looking straight at.
func _pin_is_off_the_plan(index: int) -> bool:
	if _map == null:
		return false
	var rec := GameState.waypoint_at(GameState.current_level_path, index)
	var pos: Variant = rec.get("pos")
	if not (pos is Vector3):
		return false
	var world := pos as Vector3
	var view: Transform2D = _map.view_matrix()
	var view_px: Vector2 = _map.size
	return not Rect2(Vector2.ZERO, view_px).has_point(view * Vector2(world.x, world.z))

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/map_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. The scene owns
## STRUCTURE (the full-rect Root/Dim, the PANEL_MARGIN 0.12 anchor band, the tab slot, the map host and its
## art slots, the footer row) and the widget's per-instance VIEW exports; the skin keeps owning LOOK, and
## this script owns every STRING, the tuning reads a .tscn cannot express, and the three runtime surfaces
## built into %MapHost at the end.
func _bind_ui() -> void:
	_root = %Root  # full-rect, MOUSE_FILTER_STOP authored — eats clicks so nothing falls through to gameplay behind
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)
	(%VBox as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared panel-screen rhythm (MenuSkin)
	# The tab strip is the only header (the Inventory convention, adopted across the tabs so content starts
	# at one height). CODE-BUILT by PlayerMenus into the authored slot — its one-Button-per-tab EXPAND_FILL
	# structure is a cross-screen contract (tests/test_player_menus.gd), so the scene authors only the slot.
	%TabSlot.add_child(PlayerMenus.build_tab_strip(&"map"))  # routing KEY, not the painted label

	_map = get_node_or_null(^"%Map")
	if _map != null:
		# THE VIEW KNOBS A .tscn CANNOT AUTHOR. The span is a tuning number that lives on the designer's
		# HudSettings.tres beside every other map dimension, and a scene can only hold a literal. `heading`
		# and `zoom_key_enabled` (and the widget's own `bake_delay`) ARE authored on %Map in the scene, where
		# an artist sees them next to the box they affect; `zoom_override` is authored too, but as a non-zero
		# placeholder only — _apply_zoom re-pushes the player's stored Settings.map_zoom over it on every open.
		_map.world_span_override = GameSettings.hud.map_world_span
		# ...and the three waypoint view knobs. Pushed from CODE for the same reason the span is: they belong
		# to this screen's identity rather than to the widget's defaults, and authoring them in the .tscn
		# would put half this screen's configuration in a file and half here. They are the whole difference
		# between the two hosts on this channel — a page-sized map NAMES its pins and rim-pins the ones off
		# the view, because this is the surface you select them on and a pin you cannot see is a pin you
		# cannot click; a 108 px corner box that did either drowns in glyph stacks.
		_map.waypoint_labels = true
		_map.dot_waypoints = true
		_map.waypoint_pin_offscreen = true
		# The pan starts at zero and is re-zeroed on every open (_reset_view); it lives on the widget because
		# the VIEW MATRIX is the widget's, and only one construction site may know about it.
		_map.view_offset = Vector2.ZERO
	_empty = get_node_or_null(^"%Empty") as Label
	if _empty != null:
		_empty.text = PlayerText.MAP_NO_DATA
		MenuStyle.style_hint(_empty)     # the hint SIZE and wrapping from the skin...
		_ink_over_the_plan(_empty)       # ...but NOT its ink: this notice is drawn over the widget, not on the panel's paper
		_empty.visible = false

	# THE FOOTER. Hint on the left (it EXPANDs, so the controls stay pinned right at any panel width), then the
	# three view/pin buttons — Next Pin, Place Pin, Recentre — then [− value +]. The readout is width-pinned off
	# the same skin column budget the reputation values use, so stepping 1x -> 1.25x cannot shuffle the buttons
	# sideways, and the hint's own width is whatever is left after all six controls have taken theirs.
	var footer := get_node_or_null(^"%Footer") as BoxContainer
	if footer != null:
		MenuStyle.style_button_row(footer)
	var hint := get_node_or_null(^"%Hint") as Label
	if hint != null:
		# ⭐THREE WORDS, AND THAT IS THE FIX. This label used to carry the whole gesture tutorial (MAP_HINT) and
		# lost the argument for width against five buttons every single time: the QA shots caught it ellipsized
		# to "[PH] Click to pi…", a tutorial that teaches nothing while still costing the row its space. The
		# tutorial moved onto the plan (see _build_map_tutorial) and the footer kept the one fact it can state in
		# three words and the one the player genuinely needs down here — this tab is north-up while the corner
		# box they already know is heading-up.
		hint.text = PlayerText.MAP_NORTH_UP
		MenuStyle.style_hint(hint)
		# ⭐ONE LINE, ALWAYS — this label is the FOOTER's height. style_hint turns autowrap ON, and in the
		# width the buttons leave over, a wrapped hint's minimum height sets the whole HBox row; the buttons
		# then vertical-fill into huge squares and MapHost is starved back to the exact letterbox this rebuild
		# exists to remove (QA round 2, shot 02: a five-line hint, ~140px footer, 132px map). The short caption
		# above should never reach the clip, but the clamp stays: it is what makes the FOOTER's height a
		# constant rather than a consequence of whatever copy this line is given next.
		hint.autowrap_mode = TextServer.AUTOWRAP_OFF
		MenuStyle.cap_label(hint)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT  # style_hint's twin (make_hint) centres; a footer note reads from the left rail
	_zoom_value = get_node_or_null(^"%ZoomValue") as Label
	if _zoom_value != null:
		MenuStyle.style_hint(_zoom_value)
		_zoom_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_zoom_value.custom_minimum_size.x = float(MenuStyle.skin.rep_value_col_width)
	var zoom_out := get_node_or_null(^"%ZoomOut") as Button
	if zoom_out != null:
		zoom_out.text = PlayerText.MAP_ZOOM_OUT
		# Mute the generic click: _nudge_zoom plays the cue that knows the DIRECTION of the step and whether
		# the clamp swallowed it. Without this the press would sound twice (click + step) for one action.
		MenuStyle.set_button_sound(zoom_out, &"")
		zoom_out.pressed.connect(_nudge_zoom.bind(-1))
	var zoom_in := get_node_or_null(^"%ZoomIn") as Button
	if zoom_in != null:
		zoom_in.text = PlayerText.MAP_ZOOM_IN
		MenuStyle.set_button_sound(zoom_in, &"")
		zoom_in.pressed.connect(_nudge_zoom.bind(1))
	_apply_zoom()
	_build_footer_pin_buttons(footer, zoom_out)

	_build_map_input()
	# ORDER INSIDE %MapHost, and it is load-bearing twice over: the overlay first (it must be under everything
	# that wants a click), then the tutorial (mouse-transparent, so it only has to be under the card in DRAW
	# order), then the card last of all — Godot picks the mouse against the LAST matching child.
	_build_map_tutorial()
	_build_pin_card()
	_build_prompt()
	_refresh_card()

## THE POINTER OVERLAY: one full-rect, MOUSE_FILTER_STOP Control that owns every press, drag and wheel notch
## over the plan, added INSIDE %MapHost so its rect IS the map's rect at any panel size.
##
## ⭐IT REPLACES A GUI_INPUT ON %Root THAT NEVER FIRED. The old path assumed a click over the plan would bubble
## up the container stack to the screen's root; the QA harness (scripts/tools/waypoint_qa_shots.gd) drove a
## real injected click at the map's centre and the card never opened. Whatever the exact reason (the widget
## and its host are both MOUSE_FILTER_IGNORE, and Root's own rect is the whole screen including the panel
## margin), the fix is not to re-derive the bubbling rules — it is to put a Control on the rect that cares. A
## STOP Control receives the event first and nothing above it in the tree gets a say.
##
## The widget itself stays IGNORE (minimap.gd forces it: there is no HUD readout that wants the mouse), so
## this overlay is the map's only mouth. The floating pin card is added AFTER it on purpose — see
## _build_pin_card.
func _build_map_input() -> void:
	var host := get_node_or_null(^"%MapHost") as Control
	if host == null:
		return
	_input = Control.new()
	_input.name = &"MapInput"
	_input.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_input.mouse_filter = Control.MOUSE_FILTER_STOP
	_input.focus_mode = Control.FOCUS_NONE  # the pad reaches the map through the footer's buttons, never this rect
	# THE CURSOR IS THE AFFORDANCE. A plain arrow over a full-panel picture says "this is a picture"; a CROSS
	# says "this surface takes a point", which is exactly what the plan does — and it costs no art, no hint line
	# and no screen space to say it. It swaps to the closed hand while a drag is live (_set_pan_cursor), so the
	# pan reports itself the way every map application the player has ever used does.
	_input.mouse_default_cursor_shape = Control.CURSOR_CROSS
	host.add_child(_input)
	_input.gui_input.connect(_on_map_gui_input)

## THE PLAN'S OWN INK, for every Label this screen floats OVER the map rather than on the panel's paper.
##
## ⭐WHY IT HAS TO EXIST. MenuStyle.style_hint and MenuStyle.text_color() paint the PARCHMENT skin's ink — a
## dark plum (menu_skin.tres text_color / text_dim_color) authored to sit on the panel's paper background. Four
## of this screen's labels never touch that paper: the on-plan tutorial, the "no plan for this floor" notice
## and the floating card's two lines are all drawn over the widget's near-black plan, where dark plum on
## near-black is a smudge. The QA shots caught every one of them unreadable (wp_shots7/01: the whole gesture
## tutorial invisible on a fresh level's map; wp_shots7/05: the selected pin's name and its "No note." line a
## dark blur on the card) — so the screen's ONLY tutorial line and the selected pin's own name were both text
## a player could not see. Adopting the house label styling is right for the size, the font and the wrap; it is
## wrong for the colour on exactly these four labels, and this is the one place that says so.
##
## ⭐THE PAINT IS THE MINIMAP'S, NOT A NEW ONE. The widget already solved this exact problem for its own pin
## captions: map-family ink plus a hard outline, because a caption over a vector floorplan crosses BOTH the
## dark backing AND the bright cyan wall strokes and has to read over each (see Minimap._paint_waypoint_label,
## and HudSkin.minimap_waypoint_label_outline_size's note, which states the argument verbatim). Borrowing those
## same three skin slots means one artist edit re-inks the plan's captions and this screen's overlays together,
## instead of leaving a second palette here to drift out of step with the picture it is drawn on. It is also
## why the card's name line now looks like the map's own captions — which is exactly what it is naming.
##
## `dim` is the FOOTNOTE half of the pairing (the card's note under its name), expressed as an alpha multiplier
## rather than as a second colour for the reason the parchment skin expresses it the same way: one ink, two
## weights, so a re-ink cannot leave the two halves in different families.
func _ink_over_the_plan(l: Label, dim: bool = false) -> void:
	if l == null:
		return
	# Explicitly typed, all three: MenuStyle.hud is an untyped Resource (the ui.gd class-cache idiom), so every
	# read off it is a Variant and `:=` would refuse to infer.
	var ink: Color = MenuStyle.hud.minimap_waypoint_label_color
	if dim:
		ink.a *= PLAN_INK_DIM
	l.add_theme_color_override(&"font_color", ink)
	# The outline is what carries the text over the BRIGHT half of the plan, where pale ink alone would vanish
	# as thoroughly as the plum did over the dark half. Pushed even at size 0 — the engine then draws no outline
	# at all, which is precisely the flat-text look an artist asks for by zeroing that skin slot.
	var rim: Color = MenuStyle.hud.label_outline_color
	var outline: int = int(MenuStyle.hud.minimap_waypoint_label_outline_size)
	l.add_theme_color_override(&"font_outline_color", rim)
	l.add_theme_constant_override(&"outline_size", outline)

## THE ON-PLAN TUTORIAL: the gesture line, painted over an EMPTY map instead of in the footer.
##
## ⭐IT IS AN EMPTY STATE, NOT CHROME, and that is what earns it its space. It shows only while the CURRENT
## level has no pins, nothing is selected and the tab is up (see _refresh_tutorial) — so it teaches on the map
## of a level you have never written on, the first pin you drop takes it away for good, and walking into a
## fresh level brings it back for that level. A permanent line saying "click to drop a pin" to a player with
## eleven pins on screen is wallpaper; this one is only ever on screen when there is nothing else to read.
##
## It lives here rather than in the footer because the footer could never hold it: in the strip the row's five
## buttons and its zoom readout left over, the line shipped ellipsized to "Click to pi…" (the QA shots), and
## the only way to widen it was to take the width off the controls. Over the plan it has the whole panel width
## and costs nothing at all.
##
## MOUSE_FILTER_IGNORE is non-negotiable: it sits ON the surface whose entire job is receiving clicks, and a
## tutorial that ate the click it is teaching would be its own punchline.
func _build_map_tutorial() -> void:
	var host := get_node_or_null(^"%MapHost") as Control
	if host == null:
		return
	_tutorial = Label.new()
	_tutorial.name = &"MapTutorial"
	_tutorial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tutorial.offset_bottom = -TUTORIAL_BOTTOM_PX  # low, clear of the centred %Empty notice — see the const
	_tutorial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tutorial.text = PlayerText.MAP_HINT
	MenuStyle.style_hint(_tutorial)   # the hint SIZE and wrapping: it floats over a picture, so it may take two lines freely
	# ...and then the PLAN's ink over style_hint's, at full weight. This is the only thing on screen when it is
	# up — an empty map with nothing selected — so it is the reader's whole subject, not a footnote.
	_ink_over_the_plan(_tutorial)
	_tutorial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_tutorial.visible = false
	host.add_child(_tutorial)

## THE FLOATING PIN CARD: the selected pin's name, note and verbs, overlaid on the map's bottom-left corner
## rather than stacked under it. Stacking is what broke this screen (see THE MAP IS THE PAGE) — a details row
## in the VBox costs the plan its height whether or not anything is selected, and this card costs it nothing:
## it is hidden until a pin is picked and it covers one corner when it is.
##
## ⭐ADDED AFTER THE INPUT OVERLAY, and that ORDER IS THE FEATURE. Godot picks the mouse against the LAST
## matching child first, so a card built before the overlay would sit under a STOP rect and none of its three
## buttons could ever be clicked — every press on them would land on the plan and place a pin instead.
##
## ⭐EVERY BUTTON IS EXPAND_FILL IN ITS ROW. MenuStyle.cap_button sets clip_text, which collapses a Button's
## minimum width to nothing; in an HBox with no width to give, the captions clipped to literal blank squares
## (the QA harness caught four of them on the row this card replaces). EXPAND_FILL is what hands them a share
## of the row to draw in.
##
## ⭐DARK CARD, LIGHT INK — and the pairing has to be stated here because its two halves come from opposite
## places. The BACKING is make_plain_panel_style(), i.e. MenuSkin.panel_color, which is near-black; the three
## BUTTONS wear the theme's parchment art and are fine; but the two Labels used the house label styling, which
## inks for the parchment PANEL. Dark plum on near-black is what the QA shot (wp_shots7/05) reads as a smudge
## where the selected pin's name should be. Both lines therefore take the PLAN's ink (_ink_over_the_plan) —
## which is also simply the right family for a card floating on the map, and its outline is what keeps the name
## readable where a map caption bleeds through the panel's own CARD_PANEL_ALPHA.
func _build_pin_card() -> void:
	var host := get_node_or_null(^"%MapHost") as Control
	if host == null:
		return
	_card = PanelContainer.new()
	_card.name = &"PinCard"
	# Bottom-left of the map, growing right and UP from that corner: anchors pinned to the corner, offsets
	# describing a zero-size rect there, and the grow directions deciding which way the content pushes it out.
	_card.anchor_left = 0.0
	_card.anchor_top = 1.0
	_card.anchor_right = 0.0
	_card.anchor_bottom = 1.0
	_card.offset_left = CARD_MARGIN_PX
	_card.offset_right = CARD_MARGIN_PX
	_card.offset_top = -CARD_MARGIN_PX
	_card.offset_bottom = -CARD_MARGIN_PX
	_card.grow_horizontal = Control.GROW_DIRECTION_END
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.custom_minimum_size.x = CARD_MIN_WIDTH_PX
	# STOP, not IGNORE: a click that lands on the card must DIE there. Falling through to the overlay beneath
	# would place a pin under the card the player was reading (and the click that misses a button is common —
	# the card is mostly text).
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.visible = false
	var sb: StyleBoxFlat = MenuStyle.make_plain_panel_style()  # the compact-card look; the big screen-card art is all torn border at this size
	var bg: Color = sb.bg_color
	bg.a = CARD_PANEL_ALPHA
	sb.bg_color = bg
	_card.add_theme_stylebox_override(&"panel", sb)
	host.add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", MenuStyle.skin.content_separation)
	_card.add_child(box)
	_card_name = MenuStyle.cap_label(Label.new())
	MenuStyle.style_hint(_card_name)
	_card_name.autowrap_mode = TextServer.AUTOWRAP_OFF  # one line, always — a wrapping name would grow the card
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ink_over_the_plan(_card_name)  # full weight: the name is the card's subject, not a footnote
	_card_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # player-typed: never a msgid
	box.add_child(_card_name)
	_card_note = Label.new()
	MenuStyle.style_hint(_card_note)          # style_hint turns wrapping ON, which is what a note body wants
	_ink_over_the_plan(_card_note, true)      # ...and the DIM half of the plan's ink: a note is a footnote under the name
	_card_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_card_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_card_note.max_lines_visible = CARD_NOTE_LINES                              # the CEILING
	_card_note.custom_minimum_size.y = float(MenuStyle.skin.hint_size) * 2.4    # ...and the floor: one fixed box
	box.add_child(_card_note)

	var row := HBoxContainer.new()
	MenuStyle.style_button_row(row)
	box.add_child(row)
	_track_btn = MenuStyle.cap_button(Button.new())
	_track_btn.text = PlayerText.MAP_PIN_TRACK           # the resting caption; _refresh_card swaps it per pin
	_track_btn.custom_minimum_size.x = TRACK_BTN_MIN_PX  # capped AND pinned — see the const's note
	_track_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.set_button_sound(_track_btn, &"")  # _on_track_pressed cues the direction it moved
	_track_btn.pressed.connect(_on_track_pressed)
	row.add_child(_track_btn)
	_edit_btn = Button.new()
	_edit_btn.text = PlayerText.MAP_PIN_EDIT
	_edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.set_button_sound(_edit_btn, &"")   # the card's own play_open is the cue
	_edit_btn.pressed.connect(_on_edit_pressed)
	row.add_child(_edit_btn)
	_delete_btn = Button.new()
	_delete_btn.text = PlayerText.MAP_PIN_DELETE
	_delete_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.set_button_sound(_delete_btn, &"")
	_delete_btn.pressed.connect(_on_delete_pressed)
	row.add_child(_delete_btn)

## The footer's three pad/keyboard verbs, code-built into the authored row between the hint and the zoom pair
## (Next Pin, Place Pin, Recentre — in that order, so the two PIN verbs stay adjacent and the VIEW verb sits
## beside the zoom pair it belongs with). They exist because every other path to a pin or a pan is mouse-only
## (the click selects, the drag pans, the wheel zooms), and a verb a pad can never reach is not a path — the
## atm_screen rule the zoom buttons already exist for. Place Pin marks the VIEW CENTRE, which combined with
## panning gives a pad the whole map to pin on.
##
## Deliberately NOT run through cap_button: these carry fixed PlayerText captions, and clip_text would drop
## their minimum width to nothing and render them as the blank squares the old pin bar shipped.
##
## The three are appended and then MOVED in front of `before` one at a time, each read of `before.get_index()`
## taken fresh — the index the anchor sits at shifts every time one of them is inserted ahead of it, so a
## cached index would file the second and third buttons in the wrong slots.
func _build_footer_pin_buttons(footer: BoxContainer, before: Control) -> void:
	if footer == null:
		return
	_next_btn = Button.new()
	_next_btn.text = PlayerText.MAP_PIN_NEXT
	MenuStyle.set_button_sound(_next_btn, &"")  # _on_next_pressed plays select/denied itself
	_next_btn.pressed.connect(_on_next_pressed)
	footer.add_child(_next_btn)
	_place_btn = Button.new()
	_place_btn.text = PlayerText.MAP_PIN_ADD
	MenuStyle.set_button_sound(_place_btn, &"")  # the cue is _place_at's, which knows whether the cap refused
	_place_btn.pressed.connect(_on_place_pressed)
	footer.add_child(_place_btn)
	_recentre_btn = Button.new()
	_recentre_btn.text = PlayerText.MAP_RECENTRE
	MenuStyle.set_button_sound(_recentre_btn, &"")  # _on_recentre_pressed knows whether the view actually moved
	_recentre_btn.pressed.connect(_on_recentre_pressed)
	footer.add_child(_recentre_btn)
	if before != null and before.get_parent() == footer:
		footer.move_child(_next_btn, before.get_index())
		footer.move_child(_place_btn, before.get_index())
		footer.move_child(_recentre_btn, before.get_index())

## The editor card goes on ROOT, not inside the map host: it is a full-rect scrim + centred card that must
## cover the whole screen and eat every click that misses it, exactly like AmountPrompt inside the backpack.
func _build_prompt() -> void:
	if _root == null:
		return
	_prompt = WAYPOINT_PROMPT.new()
	_root.add_child(_prompt)
	# Cancel/Esc hands focus back to this screen; the COMMIT path does it itself (it also moves the selection
	# first, which decides where the focus lands). Without either, closing the card leaves the viewport with no
	# focus owner and a pad player soft-locked on a screen full of unreachable buttons.
	_prompt.cancelled.connect(_focus_controls)

# ---------------------------------------------------------------------------------------------------
# Waypoints — the screen's second verb
# ---------------------------------------------------------------------------------------------------

## Every pointer gesture on the plan, in one handler on the one Control that receives them.
##
##   * WHEEL up/down -> a zoom step, ABOUT THE CURSOR (see _zoom_at_cursor). This is the affordance the on-plan
##     tutorial promises and the one the old Root wiring never actually delivered.
##   * LEFT PRESS arms a gesture at the press point; MOTION past PAN_DRAG_SLOP_PX turns it into a PAN and the
##     release is then swallowed; a release that never crossed the slop is a CLICK (see _click_map).
##   * RIGHT PRESS drops the selection, because nothing else could: a left click on empty plan PLACES, so
##     without this gesture the only mouse way out of a selection was to place a pin you did not want. An idle
##     right-click with nothing selected is silent — it refused nothing, so it says nothing.
##   * While the editor card is up, the overlay is deaf. The card draws its own scrim over the whole screen, so
##     nothing here can be legitimately aimed at — and a wheel notch that still zoomed under an open editor
##     would move the map out from under the pin being edited.
##
## Godot keeps sending motion and the release to the Control that took the PRESS, so a drag that leaves the
## map's rect (onto the footer, off the window) still steers and still ends here.
func _on_map_gui_input(event: InputEvent) -> void:
	if not _is_open or _map == null or _input == null:
		return
	if _prompt != null and _prompt.is_open():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at_cursor(1, mb.position)
			_input.accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at_cursor(-1, mb.position)
			_input.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# Acted on the PRESS (the half of the click a player feels), but BOTH halves are eaten: a release
			# left to travel on would reach whatever context menu the engine or a future sibling hangs off it.
			if mb.pressed and _selected >= 0:
				_deselect()
			_input.accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true
				_panning = false
				_press_at = mb.position
			elif _pressing:
				_pressing = false
				if not _panning:
					_click_map(mb.position)
				_panning = false
				_set_pan_cursor(false)  # the hand opens again wherever the drag ended
			_input.accept_event()
	elif event is InputEventMouseMotion and _pressing:
		var mm := event as InputEventMouseMotion
		if not _panning and mm.position.distance_to(_press_at) < PAN_DRAG_SLOP_PX:
			return  # still inside the slop window — this may yet turn out to be a click
		_panning = true
		_set_pan_cursor(true)
		var ppm: float = _map.pixels_per_metre()
		if ppm > 0.0:
			# The plan follows the hand: dragging the paper RIGHT moves the window LEFT, hence the negation.
			# `relative` arrives in the same canvas pixels the control is laid out in, so ppm converts it.
			_pan_by(-mm.relative / ppm)
		_input.accept_event()

## The overlay's cursor: the closed hand while a drag is live, the CROSS the rest of the time. Its own function
## because the RESTORE has two callers — the release, and close() for a drag the screen outlived — and either
## one forgotten leaves the player holding a grab cursor over a map they are no longer dragging.
func _set_pan_cursor(dragging: bool) -> void:
	if _input != null:
		_input.mouse_default_cursor_shape = Control.CURSOR_DRAG if dragging else Control.CURSOR_CROSS

## A wheel notch, zoomed ABOUT THE CURSOR: the world point under the pointer is the same world point after the
## step. Centre-zoom is what the wheel did before, and on a map it is subtly wrong every time — the player
## points at the thing they want a closer look at, and centre-zoom slides it away from under them, so reaching a
## corner of the district took a zoom-then-pan-then-zoom shuffle.
##
## The maths is the standard one, and it is deliberately expressed through the widget's OWN projection rather
## than through the zoom ratio: ask what world point sits under the cursor, take the step, ask again, and pan by
## the difference. Nothing here has to know how pixels_per_metre is built, so a change to the view matrix cannot
## silently un-anchor the cursor.
##
## The FOOTER's zoom buttons keep centre-zoom on purpose: a button press has no cursor over the plan to zoom
## about, and anchoring on wherever the pointer happens to be resting (or on a pad, nowhere) would make the map
## lurch for no reason the player could name.
func _zoom_at_cursor(dir: int, at: Vector2) -> void:
	if _map == null:
		return
	var local := _map_local(at)
	var was: float = Settings.map_zoom
	var before: Vector3 = _map.point_to_world(local)
	_nudge_zoom(dir)  # owns the clamp, the persist and the cue — including the refusal at either end of the range
	if is_equal_approx(Settings.map_zoom, was):
		return  # the clamp swallowed the notch: nothing moved, so there is nothing to compensate for
	var after: Vector3 = _map.point_to_world(local)
	_pan_by(Vector2(before.x - after.x, before.z - after.z))

## A left click on the plan that was not a drag. Clicking an EXISTING pin selects it rather than stacking a
## second pin on top — the hit test is the widget's (waypoint_at_point), because only it knows the live view
## matrix — and clicking the pin you already picked opens its editor (the double-tap affordance).
##
## Anywhere else PLACES A PIN IMMEDIATELY. The old flow opened the editor card first and made the player type
## a name for every single pin, which is a modal per placement for a mark most players never label; the card
## is now purely for re-authoring one that exists.
##
## ⭐A CLICK ON A RIM-PINNED GLYPH ALSO FETCHES THE PIN. The tab rim-pins everything off the view, so a glyph
## stuck to the edge of the plan is a pin that is NOT on the plan — selecting it would ring a marker the player
## cannot see and light up three verbs aimed somewhere off-screen. The question is asked BEFORE the selection
## moves (the view matrix is the same either way, but the reading order is what makes it obviously right), and
## a pin that was genuinely on the plan must NOT move the view: yanking the map under a player who just clicked
## something they were looking straight at is the exact opposite of the fix.
func _click_map(at: Vector2) -> void:
	var local := _map_local(at)
	var hit: int = int(_map.waypoint_at_point(local))
	if hit >= 0:
		if hit == _selected:
			_on_edit_pressed()
		else:
			var was_rim_pinned := _pin_is_off_the_plan(hit)
			_click_select(hit)
			if was_rim_pinned:
				_bring_selection_into_view()
		return
	# ⭐CLICK-AWAY DISMISSES BEFORE IT PLACES. With a pin selected, the floating card is up, and every UI a
	# player has ever used taught them that clicking empty space dismisses a popup — the first playtest did
	# exactly that and minted pins instead ("the box is stuck forever"). So an empty-plan click while
	# something is selected DESELECTS and stops; placement is what the NEXT click means. Chained placement
	# stays one click per pin because a click-placed pin no longer selects itself (see _place_at).
	if _selected >= 0:
		_deselect()
		return
	var pos: Vector3 = _map.point_to_world(local)
	_place_at(pos, false)

## Overlay-local pixels -> widget-local pixels. The two are the same rect today (both full-rect inside
## %MapHost), so this is a translation and nothing more — but the widget's hit test and world projection are
## both defined in ITS local space, and reading one control's coordinates as another's is exactly the class of
## silent drift minimap.gd's view_matrix() note warns about. One conversion, one place to fix if an artist ever
## insets the plan inside its host.
func _map_local(at: Vector2) -> Vector2:
	if _map == null or _input == null:
		return at
	return at + _input.global_position - (_map as Control).global_position

## Selection-by-click, cue included. Its own function so the cue is UNCONDITIONAL where it lives: landing on
## a pin cannot be refused (the hit test already answered), and the sound-coverage ratchet
## (test_menu_sound_coverage) rightly flags a branch-gated success cue with no denial twin as a silent
## refusal waiting to happen — the "hoist it out of the branch" case its message names.
func _click_select(hit: int) -> void:
	_select(hit)
	MenuStyle.play_select()

## Drop the selection — the card goes, the ring goes. Its own function for the same two reasons _click_select
## is: the cue is UNCONDITIONAL where it lives (its callers have already decided there IS a selection, so this
## can never be refused), and both gestures that mean "never mind" — the right-click and the first Esc — must
## sound and behave identically. play_back rather than a commit: nothing was accomplished, something was
## withdrawn.
func _deselect() -> void:
	_select(-1)
	MenuStyle.play_back()

## Drop a pin at `pos`. No name box: the pin is seeded with its ORDINAL (see _pin_seed_name), so two unnamed
## pins are still tellable apart on the map, and the player renames it from the card if it turns out to
## matter. The old flow opened the editor for EVERY placement — a modal, a field and an Enter for a mark most
## players never label.
##
## ⭐`select_after` IS THE INPUT'S GRAMMAR, not a convenience flag. The CLICK path passes false: auto-selecting
## popped the card over the map after every single placement, and dismissing it cost a gesture nobody guessed
## (the stuck-box playtest) — a mouse user who wants the card clicks the pin they just placed, which is
## already under their cursor. The FOOTER's Place button passes true: a pad has no cursor hovering the new
## pin, so selection is its only one-press road to Edit.
##
## Both refusals SAY so, because a pin that silently fails to appear reads exactly like a broken map — and a
## blank level path (a code-built LevelData never records one) gets its OWN copy, since telling that player
## "the map is full" over an empty map is a lie.
func _place_at(pos: Vector3, select_after: bool) -> void:
	var level := GameState.current_level_path
	if level.is_empty():
		MenuStyle.play_denied()
		UI.toast(PlayerText.WAYPOINT_NO_LEVEL)
		return
	if GameState.waypoints_full(level):
		MenuStyle.play_denied()
		UI.toast(TextFormat.subst(PlayerText.WAYPOINT_FULL, {"max": WAYPOINT_BOOK.MAX_PER_LEVEL}))
		return
	var idx := GameState.add_waypoint(level, pos, _pin_seed_name(GameState.waypoints_for(level).size() + 1),
			"", 0, 0)
	if idx < 0:
		MenuStyle.play_denied()  # the cap moved under us between the check and the write
		UI.toast(TextFormat.subst(PlayerText.WAYPOINT_FULL, {"max": WAYPOINT_BOOK.MAX_PER_LEVEL}))
		return
	MenuStyle.play_commit()
	if select_after:
		_select(idx)
	else:
		_refresh_tutorial()  # the tutorial's "no pins yet" condition just changed; a selection would refresh it, this path must too

## The automatic label for the pin at 1-based ordinal `n` — the name a placement seeds and the one an edit
## falls back to when the player clears the field. ONE composition site for both, because it is the one
## PlayerText string that ends up SAVED as player data: the `[PH] ` marker is stripped here (a placeholder
## marker must never outlive the session that painted it — the dog_pickup precedent), and a second copy of
## this expression would be a second chance to forget that.
##
## WAYPOINT_DEFAULT_NAME is authored now, so the strip is a NO-OP — kept deliberately, belt-and-braces: the
## guard against a marker reaching a save file must not depend on that const staying authored.
func _pin_seed_name(n: int) -> String:
	return PlayerText.strip_prefix(TextFormat.subst(PlayerText.WAYPOINT_DEFAULT_NAME, {"n": n}))

## Re-author the selected pin. Its POSITION is deliberately not editable (GameState.update_waypoint's note):
## a pin is a place you marked, and moving it by editing would make "rename" and "re-place" one gesture.
func _on_edit_pressed() -> void:
	if _prompt != null and _prompt.is_open():
		return  # the editor card owns the screen; see the guard note on _on_place_pressed
	var rec := GameState.waypoint_at(GameState.current_level_path, _selected)
	if rec.is_empty() or _prompt == null:
		MenuStyle.play_denied()
		return
	var idx := _selected
	_prompt.open(PlayerText.WAYPOINT_EDIT_TITLE,
			String(rec.get("name", "")), String(rec.get("note", "")),
			int(rec.get("icon", 0)), int(rec.get("tint", 0)),
			func(pin_name: String, note: String, icon: int, tint: int) -> void:
				# A CLEARED field falls back to the ordinal seed rather than storing a nameless pin: the card
				# and the map both paint that name, and a blank one is a pin you can no longer tell from its
				# neighbour. (The card's clamp already answered "" for an all-junk entry — WaypointBook.clean_name
				# leaves the default to the caller, because a default is player copy and owes PlayerText.)
				var used := pin_name if not pin_name.is_empty() else _pin_seed_name(idx + 1)
				# The index is CAPTURED, so a ledger change while the card was open could point it at a
				# different pin — update_waypoint answers false for an index that no longer exists, and the
				# refusal cue is what tells the player their edit did not land. (It also carries the tracked
				# flag across the rebuilt record, so a rename never drops the player's navigation marker.)
				if GameState.update_waypoint(GameState.current_level_path, idx, used, note, icon, tint):
					MenuStyle.play_commit()
					_select(idx)
				else:
					MenuStyle.play_denied()
				_focus_controls())

## Track / untrack the selected pin — the classic "set active waypoint", and the whole point of the pin
## channel: the tracked one rim-pins on the HUD corner box and draws a pip on the heading tape, so it is the
## thing you can actually navigate to. One per profile; GameState.set_tracked_waypoint moves the flag rather
## than setting it, so tracking a second pin untracks the first with no bookkeeping here.
##
## The cue splits by DIRECTION rather than by success: tracking is a commit (play_select) and untracking is a
## withdrawal (play_back), and a bad index — the ledger moved under an open screen — is a refusal.
func _on_track_pressed() -> void:
	if _prompt != null and _prompt.is_open():
		return  # the editor card owns the screen; see the guard note on _on_place_pressed
	var level := GameState.current_level_path
	var rec := GameState.waypoint_at(level, _selected)
	if rec.is_empty():
		MenuStyle.play_denied()
		return
	var want := not WAYPOINT_BOOK.is_tracked(rec)
	if not GameState.set_tracked_waypoint(level, _selected, want):
		MenuStyle.play_denied()
		return
	if want:
		MenuStyle.play_select()
	else:
		MenuStyle.play_back()

## Delete the selected pin. No confirmation card: a pin is cheap to re-place, and a modal over a modal for a
## reversible act is the friction the rest of these screens deliberately avoid. The selection moves to the pin
## that took its index (or the new last pin), so a run of deletes needs no re-clicking.
##
## ⭐THE FOLLOW-UP SELECTION IS DECIDED BEFORE THE MUTATION. remove_waypoint emits waypoints_changed
## SYNCHRONOUSLY, and _on_waypoints_changed re-enters _select mid-call — so a version that read `_selected`
## AFTER the remove found it already stomped (to -1 when the deleted pin was the tail) and a run of
## tail-deletes lost the selection every time, the exact promise the paragraph above makes.
func _on_delete_pressed() -> void:
	if _prompt != null and _prompt.is_open():
		return  # the editor card owns the screen; see the guard note on _on_place_pressed
	var level := GameState.current_level_path
	var next := mini(_selected, GameState.waypoints_for(level).size() - 2)
	if not GameState.remove_waypoint(level, _selected):
		MenuStyle.play_denied()
		return
	MenuStyle.play_back()
	_select(next)

## The pad/keyboard path to SELECTING a pin — without it the card's three verbs are mouse-only, which the
## atm_screen rule forbids. Cycles pin -> pin -> ... -> none -> pin, so the same button also deselects; the
## wrap through "none" is what keeps one button sufficient (a Prev twin would buy speed on a full level, at
## the cost of another footer control — revisit if 32-pin levels become normal).
##
## NOT ui_left/ui_right in _unhandled_input, deliberately: those actions are consumed by focus-neighbor
## navigation before the unhandled pass whenever any of this screen's buttons holds focus — which is always,
## since open() seeds one.
##
## ⭐THE MAP FOLLOWS THE CYCLE. Without that, Next Pin on a panned or zoomed-in map selects pins the player
## cannot see: the card names one, the ring is somewhere off the plan, and the button reads as broken on a
## level with pins in two buildings. Bringing each pick into view turns the same button into "review my pins" —
## press it and walk the level's marks one at a time. The wrap through "none" moves nothing, which is right:
## there is no pin to look at.
func _on_next_pressed() -> void:
	if _prompt != null and _prompt.is_open():
		return  # the editor card owns the screen; see the guard note on _on_place_pressed
	var n := GameState.waypoints_for(GameState.current_level_path).size()
	if n == 0:
		MenuStyle.play_denied()
		return
	var next := _selected + 1
	_select(next if next < n else -1)
	_bring_selection_into_view()
	MenuStyle.play_select()

## The pad/keyboard path to placing a pin. It marks the map's CENTRE — which is the player's own position
## until the view is panned, and anywhere on the level once it is. That pairing is deliberate: pan + Place Pin
## is the pad's equivalent of the mouse's click-anywhere, and without the pan it could only ever mark your feet.
func _on_place_pressed() -> void:
	# ⭐EVERY pin verb (and the zoom pair) refuses while the editor card is up. The card's scrim stops the
	# MOUSE, but focus is a second input path: a pad that walked focus out from under the card could otherwise
	# delete the very pin being edited, or open the card over itself. One guard per verb kills the whole
	# class, whatever the focus does.
	if _map == null or (_prompt != null and _prompt.is_open()):
		return
	var pos: Vector3 = _map.point_to_world(_map.size * 0.5)
	_place_at(pos, true)  # the pad's placement lands SELECTED — its only one-press road to Edit (see _place_at)

## Move the selection, clamp it to what actually exists, push it onto the widget and repaint the card.
##
## THE CLAMP IS THE POINT. `_selected` is an index into an array anything may mutate, so every path that sets
## it comes through here — including the ones that pass a deliberately out-of-range value (a delete at the end
## of the list passes size-1, which is -1 when the list just emptied).
##
## ⭐IT ALSO RESCUES THE FOCUS. The card is the only home of Track/Edit/Delete, and Godot releases focus from a
## Control the moment it hides — so a delete (or a cycle through "none") pressed with a pad would leave the
## viewport with NO focus owner and the player soft-locked on a screen full of unreachable buttons. Re-seeded
## only when the vanishing card actually HELD the focus, so a mouse player is never yanked around.
func _select(index: int) -> void:
	var had_focus := _focus_in_card()
	var list := GameState.waypoints_for(GameState.current_level_path)
	_selected = index if (index >= 0 and index < list.size()) else -1
	_selected_level = GameState.current_level_path
	if _map != null:
		_map.selected_waypoint = _selected  # part of the widget's idle gate — the ring repaints on its own
	_refresh_card()
	if had_focus and (_card == null or not _card.visible):
		_focus_controls()

## The ledger moved under us. Re-validating rather than trusting is what keeps a stale index from painting a
## selection ring on somebody else's pin: the in-world Mark key can append while this tab is open, a level
## swap replaces the whole list, and a quickload replaces the whole ledger.
##
## ⭐A LEVEL CHANGE CLEARS THE SELECTION OUTRIGHT. The range clamp alone would keep the index whenever the
## NEW level's list happens to be long enough — same number, unrelated pin, ring and Delete button silently
## pointing at it. An index is only meaningful against the list it was picked from.
func _on_waypoints_changed() -> void:
	if _selected_level != GameState.current_level_path:
		_selected = -1
	_select(_selected)

## Hand pad/keyboard focus (back) to this screen — on open, when the editor card closes, and when the floating
## card vanishes under a focused button. The card's Edit is the likeliest next verb while a pin is selected;
## with nothing selected the card is hidden (and grab_focus on a hidden Control does nothing), so the footer's
## Place Pin is the landing spot.
func _focus_controls() -> void:
	if not _is_open:
		return  # the card can close AFTER the screen did (close() closes it) — do not steal gameplay focus
	var target: Button = _place_btn
	if _selected >= 0 and _card != null and _card.visible and _edit_btn != null:
		target = _edit_btn
	if target != null:
		target.grab_focus()

## Does the floating card currently own the keyboard focus? Asked BEFORE a selection change, because after one
## the card may already be hidden and Godot will have released the focus it held.
func _focus_in_card() -> bool:
	if _card == null or not _card.visible or _root == null or not _root.is_inside_tree():
		return false
	var focused := _root.get_viewport().gui_get_focus_owner()
	return focused != null and _card.is_ancestor_of(focused)

## Paint the floating card for the current selection, or hide it outright when there is none — an empty
## details panel is chrome that teaches nothing, and the on-plan tutorial (MAP_HINT) is what fills the space a
## selection would have used.
##
## ⭐auto_translate is toggled PER CONTENT on the note, not set once: it carries player-TYPED text (never a
## msgid — DISABLED) and the PlayerText "No note." line (which a shipped locale must be able to translate —
## INHERIT) in turn, and a blanket DISABLED would freeze that authored string out of every translation
## forever. The NAME line is player text in every state, so it stays DISABLED from birth.
func _refresh_card() -> void:
	_refresh_tutorial()  # FIRST: this function has two early returns, and the tutorial owes an answer on every path
	if _next_btn != null:
		_next_btn.disabled = GameState.waypoints_for(GameState.current_level_path).is_empty()
	if _card == null or _card_name == null or _card_note == null:
		return
	var rec := GameState.waypoint_at(GameState.current_level_path, _selected)
	_card.visible = not rec.is_empty()
	if rec.is_empty():
		return
	_card_name.text = TextFormat.subst(PlayerText.MAP_PIN_SELECTED, {"name": rec.get("name", "")})
	var note := String(rec.get("note", ""))
	_card_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if not note.is_empty() \
			else Node.AUTO_TRANSLATE_MODE_INHERIT
	_card_note.text = note if not note.is_empty() else PlayerText.MAP_PIN_NO_NOTE
	if _track_btn != null:
		# ONE button, two whole words — never "Track" with an appended negation, which a locale may not build
		# the same way. The caption says what the press will DO, not what the pin currently is.
		_track_btn.text = PlayerText.MAP_PIN_UNTRACK if WAYPOINT_BOOK.is_tracked(rec) \
				else PlayerText.MAP_PIN_TRACK

## Should the on-plan tutorial be up? Three conditions, and each of them is the difference between teaching and
## wallpaper: the tab must be OPEN (it is refreshed from _refresh_card, which also runs at boot with the screen
## hidden), this level's ledger must be EMPTY (one pin proves the player already knows the gesture — and it is
## the CURRENT level's ledger, so a fresh level teaches again even for a veteran) and nothing may be SELECTED
## (a selection means a card is up in the same picture, and two overlays over one map is clutter).
##
## Driven by _refresh_card rather than polled: those three facts change exactly where the selection and the
## ledger do, and _refresh_card is already the one function every such path ends in.
func _refresh_tutorial() -> void:
	if _tutorial == null:
		return
	_tutorial.visible = _is_open and _selected < 0 \
			and GameState.waypoints_for(GameState.current_level_path).is_empty()
