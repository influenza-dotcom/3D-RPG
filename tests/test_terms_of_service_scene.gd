extends GutTest

## AUTHORED-SCENE wiring contract for the first-launch Terms-of-Service gate
## (scenes/ui/terms_of_service_screen.tscn + scripts/ui/terms_of_service_screen.gd). The screen is NOT an
## autoload — StartMenu preloads the SCENE and instances it over the hidden menu on a fresh install — so the
## "autoload points at the scene" test becomes: the HOST const points at the scene, and the scene root carries
## the script. The rest mirrors test_heal_screen_scene.gd: every %node the script binds exists, no text is
## authored in the scene (strings belong to the TermsOfService resource / PlayerText, never a .tscn), and the
## screen-specific layout contracts hold. BEHAVIOUR (scroll-to-end Agree gate, focus policy, consent flag) stays
## in tests/test_terms_of_service.gd + playtest — these tests only instantiate() off-tree, never _ready.

const SCENE := "res://scenes/ui/terms_of_service_screen.tscn"
const SCRIPT_PATH := "res://scripts/ui/terms_of_service_screen.gd"
const HOST_SCRIPT := "res://scripts/ui/start_menu.gd"

## Every unique name terms_of_service_screen.gd binds in _bind_ui/_bind_nag — a rename in the editor breaks
## the bind at boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Dim", "Column", "Title", "Subtitle", "Scroll", "BodyLabel", "ScrollHint",
	"Buttons", "DeclineButton", "AgreeButton",
	"NagRoot", "NagDim", "NagCard", "NagButtons", "BackButton", "QuitButton"]


func test_host_points_at_the_authored_scene() -> void:
	# The conversion contract: StartMenu preloads the SCENE (root carries the script) — a bare-script .new()
	# would silently skip the authored layout and _bind_ui would null-deref on the very first launch.
	var host_src := FileAccess.get_file_as_string(HOST_SCRIPT)
	assert_true(host_src.contains("preload(\"%s\")" % SCENE),
		"StartMenu preloads the authored terms-of-service scene")
	assert_false(host_src.contains("preload(\"%s\")" % SCRIPT_PATH),
		"StartMenu no longer preloads the bare script")
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_true(inst is Control, "root is the full-rect Control overlay StartMenu add_child's")
	assert_not_null(inst.get_script(), "the root carries a script")
	assert_eq(String(inst.get_script().resource_path), SCRIPT_PATH, "the root carries terms_of_service_screen.gd")
	inst.free()


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui/_bind_nag)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in the TermsOfService resource (designer-authored, l10n-owned) — a caption typed into the
	# .tscn would bypass it and ship unauthored. The scene must hold only structure.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from TermsOfService)" % n.name)
	inst.free()


func test_bound_chrome_keeps_the_layout_contracts() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()

	# The gate eats clicks so the (hidden) menu buttons behind it never get them; root + dim span the screen.
	var root := inst as Control
	assert_eq(root.mouse_filter, Control.MOUSE_FILTER_STOP, "the root eats clicks over the hidden menu")
	assert_eq(root.anchor_right, 1.0, "the root spans the screen (anchor_right)")
	assert_eq(root.anchor_bottom, 1.0, "the root spans the screen (anchor_bottom)")
	var dim := inst.get_node("%Dim") as Control
	assert_eq(dim.anchor_right, 1.0, "the dim spans the screen (anchor_right)")
	assert_eq(dim.anchor_bottom, 1.0, "the dim spans the screen (anchor_bottom)")

	# The agreement body: vertical-only EXPAND_FILL scroll (h-scroll disabled forces the label to the container
	# width, so the wall of text WRAPS instead of running one endless line) between pinned header and buttons.
	var scroll := inst.get_node("%Scroll") as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"the body scroll is vertical-only — the label wraps to the panel width")
	assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the scroll takes the slack (pinned rows never buried)")
	assert_eq(scroll.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the scroll takes the full panel width")
	var body := inst.get_node("%BodyLabel") as Label
	assert_eq(body.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the agreement body wraps")
	assert_eq(body.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the body label fills the scroll width")

	# The Decline/Agree pair keeps FOCUS_ALL: the MOUSE-FIRST seeding in _input grabs Decline on demand for
	# pad/keyboard players — an authored FOCUS_NONE would strand them at a first-launch hard stop.
	for b in ["DeclineButton", "AgreeButton"]:
		assert_eq((inst.get_node("%" + b) as Button).focus_mode, Control.FOCUS_ALL,
			"%s stays focusable (pad/keyboard focus seeding needs it)" % b)

	# The decline nag ships HIDDEN, spans the screen, and eats clicks; its buttons EXPAND so a caption can
	# never grow the fixed-width card (style_dialog_card pins %NagCard to skin.dialog_width at runtime).
	var nag := inst.get_node("%NagRoot") as Control
	assert_false(nag.visible, "the decline nag ships hidden until Decline is pressed")
	assert_eq(nag.mouse_filter, Control.MOUSE_FILTER_STOP, "the nag overlay eats clicks over the agreement")
	assert_eq(nag.anchor_right, 1.0, "the nag overlay spans the screen (anchor_right)")
	assert_eq(nag.anchor_bottom, 1.0, "the nag overlay spans the screen (anchor_bottom)")
	for b in ["BackButton", "QuitButton"]:
		assert_eq((inst.get_node("%" + b) as Button).size_flags_horizontal, Control.SIZE_EXPAND_FILL,
			"%s splits the fixed nag-card width" % b)

	inst.free()
