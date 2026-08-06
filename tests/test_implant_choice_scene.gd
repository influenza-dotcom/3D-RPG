extends GutTest

## AUTHORED-SCENE wiring contract for the implant-purchase (on-credit) step (scenes/ui/implant_choice.tscn +
## scripts/ui/implant_choice.gd). Like character creation, the screen is NOT an autoload — StartMenu preloads
## the SCENE and instances it when creation's "Begin" is clicked — so the "autoload points at the scene" test
## becomes: the HOST const points at the scene, and the scene root carries the script. The rest mirrors
## test_character_creation_scene.gd: every %node the script binds exists, no text is authored in the scene
## (strings belong to PlayerText / l10n, never a .tscn), and the screen-specific layout contracts hold.
## BEHAVIOUR (the roster build, cart toggling + tally/debt math, the never-gated Begin, the StartMenu flow
## seams) lives in tests/test_implant_choice.gd — these tests only instantiate() off-tree, never _ready.

const SCENE := "res://scenes/ui/implant_choice.tscn"
const SCRIPT_PATH := "res://scripts/ui/implant_choice.gd"
const HOST_SCRIPT := "res://scripts/ui/start_menu.gd"

## Every unique name implant_choice.gd binds in _bind_ui (plus %ChipScroll, whose layout the pins below hang
## off) — a rename in the editor breaks the bind at boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Dim", "Column", "Title", "Hint", "ChipScroll", "ChipList",
	"Tally", "Buttons", "BackButton", "BeginButton"]


func test_host_points_at_the_authored_scene() -> void:
	# The conversion contract: StartMenu preloads the SCENE (root carries the script) — a bare-script .new()
	# would silently skip the authored layout and _bind_ui would null-deref the moment the step is raised.
	var host_src := FileAccess.get_file_as_string(HOST_SCRIPT)
	assert_true(host_src.contains("preload(\"%s\")" % SCENE),
		"StartMenu preloads the authored implant-choice scene")
	assert_false(host_src.contains("preload(\"%s\")" % SCRIPT_PATH),
		"StartMenu never preloads the bare script")
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_true(inst is Control, "root is the full-rect Control overlay StartMenu add_child's")
	assert_not_null(inst.get_script(), "the root carries a script")
	assert_eq(String(inst.get_script().resource_path), SCRIPT_PATH, "the root carries implant_choice.gd")
	inst.free()


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. The roster rows are runtime content and never live in the scene.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
		elif n is LineEdit:
			assert_eq((n as LineEdit).placeholder_text, "", "%s ships with an empty placeholder" % n.name)
	inst.free()


func test_bound_chrome_keeps_the_layout_contracts() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()

	# The overlay eats clicks so the suspended creation overlay / hidden menu behind it never get them.
	var root := inst as Control
	assert_eq(root.mouse_filter, Control.MOUSE_FILTER_STOP, "the root eats clicks over the overlays behind it")
	assert_eq(root.anchor_right, 1.0, "the root spans the screen (anchor_right)")
	assert_eq(root.anchor_bottom, 1.0, "the root spans the screen (anchor_bottom)")
	var dim := inst.get_node("%Dim") as Control
	assert_eq(dim.anchor_right, 1.0, "the dim spans the screen (anchor_right)")
	assert_eq(dim.anchor_bottom, 1.0, "the dim spans the screen (anchor_bottom)")

	# The roster scrolls vertically ONLY (rows are width-fitted) and takes the panel's slack, while the
	# Back/Begin row stays PINNED outside it — the character-creation "can't-progress" contract: at the tiny
	# UI canvas the buttons must stay reachable however long the chip list grows.
	var scroll := inst.get_node("%ChipScroll") as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"the roster scroll is vertical-only — rows fit the width")
	assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the roster scroll takes the panel's slack")
	assert_true(scroll.is_ancestor_of(inst.get_node("%ChipList")), "the roster rows live inside the scroll")
	assert_eq((inst.get_node("%Buttons") as Control).get_parent(), inst.get_node("%Column"),
		"Back/Begin stay pinned in the column, outside the scroll")
	assert_eq((inst.get_node("%Tally") as Control).get_parent(), inst.get_node("%Column"),
		"the bill/balance tally stays pinned in the column too — visible however long the roster grows")

	inst.free()
