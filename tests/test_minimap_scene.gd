extends GutTest

## AUTHORED-SCENE wiring contract for the HUD minimap (scenes/ui/hud_minimap.tscn + scripts/ui/minimap.gd).
## The "menus are scenes" conversion, applied to a HUD widget: the box, its draw order and its two art slots
## are authored in the editor now instead of being computed in ui.gd.
##
## The widget is NOT an autoload — ui.gd instances it into the HUD — so the "autoload points at the scene"
## test becomes "the HOST points at the scene", greped out of ui.gd. The rest mirrors
## test_character_creation_scene.gd: every slot the script adopts exists, no text is authored, and the
## screen-specific contracts hold.
##
## THE ONE CONTRACT THIS FILE OWNS THAT NO OTHER DOES: the authored box and GameSettings.hud's minimap knobs
## must describe the SAME rectangle. The knobs are the fallback the whole top-right stack falls back to, and
## tests/test_minimap_hud_layout.gd + tests/test_hud_settings.gd pin their clearance rules — so if an artist
## drags the box in the editor without mirroring it into HudSettings.tres, those pins quietly stop describing
## the corner the game actually draws. test_the_authored_box_is_the_box_the_stack_measures is that tie.
##
## These tests instantiate() off-tree and never run _ready, except the one marked otherwise. BEHAVIOUR (the
## deck cache, the idle gate, the underlay stamp) stays in tests/test_minimap.gd.

const SCENE := "res://scenes/ui/hud_minimap.tscn"
const SCRIPT_PATH := "res://scripts/ui/minimap.gd"
const HOST_SCRIPT := "res://scripts/ui/ui.gd"

## Every unique name minimap.gd reaches for in _ready. A rename in the editor silently drops the slot (the
## reads are get_node_or_null, deliberately, so a bare .new() stays legal) — so pin the roster here, where it
## fails loudly, instead of discovering it as art that renders on the wrong side of the map.
const BOUND := ["MapUnder", "MapOver", "EditorPreview"]


## The conversion contract, both halves: ui.gd reaches for the SCENE, and no longer preloads the bare script.
## Greps for the PATH rather than for `preload("…tscn")` because the safe form here is a runtime load() — see
## the MINIMAP_SCENE const's own note in ui.gd about the class_name cyclic-reference trap.
func test_host_instances_the_authored_scene() -> void:
	var host_src := FileAccess.get_file_as_string(HOST_SCRIPT)
	assert_true(host_src.contains(SCENE), "ui.gd points at the authored minimap scene")
	assert_false(host_src.contains("preload(\"%s\")" % SCRIPT_PATH),
		"ui.gd no longer preloads the bare minimap script (a half-done conversion)")
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_true(inst is Control, "root is the Control ui.gd parents into the HUD-weight carrier")
	assert_not_null(inst.get_script(), "the root carries a script")
	assert_eq(String(inst.get_script().resource_path), SCRIPT_PATH, "the root carries minimap.gd")
	inst.free()


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (minimap.gd adopts it in _ready)" % n)
	inst.free()


## THE PIXEL-IDENTICAL CONVERSION PIN. These six properties are exactly what ui.gd used to write in code, so
## the scene has to carry them or the conversion changed the shipped look. Asserted against the SYMBOLS, never
## the raw ints, because the two enums do NOT line up: MOUSE_FILTER_IGNORE is 2 while TEXTURE_FILTER_NEAREST
## is 1, and authoring `texture_filter = 2` would silently ship LINEAR filtering on the underlay, the marker
## art, the caret art and the frame.
##
## When an artist changes one of these ON PURPOSE, change this line in the same commit.
func test_the_authored_root_ships_the_code_built_look() -> void:
	var inst: Control = (load(SCENE) as PackedScene).instantiate()
	assert_almost_eq(inst.anchor_left, 1.0, 0.0001, "right-anchored: the box rides the right screen edge")
	assert_almost_eq(inst.anchor_right, 1.0, 0.0001, "both x anchors pin to the right edge")
	assert_eq(inst.z_index, 1,
		"z 1: over PlayerHud's full-screen flashes (z 0), under the crosshair (z 2)")
	assert_true(inst.clip_contents, "a marker pinned to the rim must not escape onto the quest tracker")
	assert_eq(inst.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the box must not eat clicks in the corner of the screen")
	assert_eq(inst.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
		"NEAREST: the pixel look, inherited by every art node under it")
	inst.free()


## THE TIE between the authored box and the knobs every layout invariant is still pinned against. Exact
## equality on purpose: 8 / 108 / 116 are all exactly representable, and a fractional authored offset SHOULD
## fail here — the 792x444 canvas is nearest-upscaled ~2.4x and a fractional box rasterizes into a ragged edge
## (the same rule test_minimap_hud_layout.gd's whole-pixel test states).
##
## Move the box in the scene and you must move resources/tuning/HudSettings.tres with it.
func test_the_authored_box_is_the_box_the_stack_measures() -> void:
	var inst: Control = (load(SCENE) as PackedScene).instantiate()
	var authored := UI.minimap_box_from(inst.offset_left, inst.offset_top,
			inst.offset_right, inst.offset_bottom, Rect2())
	assert_eq(authored, Rect2(GameSettings.hud.minimap_inset, GameSettings.hud.minimap_size),
		"the authored box and HudSettings' minimap_inset/minimap_size describe the same rectangle")
	inst.free()


## A degenerate box (a bare Control.new(), a failed instantiate) must answer the FALLBACK, which is how the
## knob-derived layout survives a missing map completely unchanged. Pinned here rather than in the layout
## suite because it is the scene conversion that introduced the case.
func test_a_degenerate_box_falls_back_to_the_knobs() -> void:
	var fallback := Rect2(4.0, 5.0, 6.0, 7.0)
	assert_eq(UI.minimap_box_from(0.0, 0.0, 0.0, 0.0, fallback), fallback, "an all-zero Control answers the fallback")
	assert_eq(UI.minimap_box_from(-10.0, 0.0, -10.0, 20.0, fallback), fallback, "a zero-WIDTH box answers the fallback")
	assert_eq(UI.minimap_box_from(-30.0, 0.0, -10.0, 0.0, fallback), fallback, "a zero-HEIGHT box answers the fallback")
	# And the real shape it computes: a right-anchored box's inset is -offset_right.
	assert_eq(UI.minimap_box_from(-116.0, 8.0, -8.0, 116.0, Rect2()), Rect2(8.0, 8.0, 108.0, 108.0),
		"the inset is measured from the RIGHT screen edge, the size from the offset span")


## Both art slots ship EMPTY, which is what makes the conversion pixel-identical: an artist adds the first
## node, not replaces a placeholder. %MapUnder's show_behind_parent is authored as well as forced in _ready,
## so the 2D editor's preview matches the runtime order.
func test_the_art_slots_ship_empty() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var under: CanvasItem = inst.get_node_or_null("%MapUnder")
	var over: CanvasItem = inst.get_node_or_null("%MapOver")
	assert_eq(under.get_child_count(), 0, "%MapUnder ships empty (art lands one node at a time)")
	assert_eq(over.get_child_count(), 0, "%MapOver ships empty")
	assert_true(under.show_behind_parent,
		"%MapUnder renders BEHIND the plan — the slot name is the contract, authored and re-forced in _ready")
	assert_false(over.show_behind_parent, "%MapOver renders in FRONT of the plan")
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them). ScanText is .gd-only and cannot see
	# a .tscn, so this walk is the only thing standing between a typed caption and shipping unauthored.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	var text_bearing := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			text_bearing += 1
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text" % n.name)
		elif n is LineEdit:
			text_bearing += 1
			assert_eq((n as LineEdit).placeholder_text, "", "%s ships with an empty placeholder" % n.name)
	# Asserted unconditionally so this test cannot go quietly Risky (zero asserts) the way a pure walk does on
	# a scene that legitimately has no text nodes at all — which is the SHIPPED state, and the stronger claim:
	# the map is geometry, and even the north mark is a drawn spoke rather than an "N" precisely so this widget
	# owes PlayerText nothing. A text node appearing here is a design change, not just a string to move.
	assert_eq(text_bearing, 0, "the minimap authors no text-bearing node at all — it is a drawing, not a readout")
	inst.free()


## THE ONE IN-TREE TEST. Two behaviours _ready owns, both of which only exist because the widget is a scene
## now: the editor-only backing fill is hidden at runtime, and every authored art node is swept to
## MOUSE_FILTER_IGNORE — an artist's TextureRect/NinePatchRect/ColorRect defaults to STOP and would re-open the
## "the HUD eats clicks in the corner" bug the moment the first PNG lands.
func test_ready_hides_the_editor_preview_and_makes_authored_art_click_through() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(inst)
	await get_tree().process_frame
	var preview: CanvasItem = inst.get_node_or_null("%EditorPreview")
	assert_false(preview.visible, "the editor alignment fill is hidden at runtime")
	# A freshly dropped art node, exactly as an artist would add it: STOP by default.
	var art := ColorRect.new()
	assert_eq(art.mouse_filter, Control.MOUSE_FILTER_STOP, "precondition: authored art defaults to STOP")
	inst.get_node("%MapOver").add_child(art)
	inst._adopt_authored_art(inst)
	assert_eq(art.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the sweep stomps it to IGNORE — there is no HUD art that wants the mouse")
