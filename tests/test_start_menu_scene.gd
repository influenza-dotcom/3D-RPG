extends GutTest

## AUTHORED-SCENE wiring contract for the main menu (scenes/start_menu.tscn + scripts/ui/start_menu.gd).
## StartMenu is NOT an autoload — it is the boot menu the computer-room host (project main_scene) instances
## at runtime and every back-to-menu path change_scene_to_file's into — so the "autoload points at the scene"
## test becomes: the HOST const points at the scene, and the scene root carries the script. The rest mirrors
## test_heal_screen_scene.gd: every %node the script binds exists, no text is authored in the scene (strings
## belong to PlayerText / l10n, never a .tscn), and the screen-specific layout contracts hold. Boot BEHAVIOUR
## (warning cards, TOS gate, threaded load) stays in tests/test_start_menu.gd + playtest.

const SCENE := "res://scenes/start_menu.tscn"
const SCRIPT_PATH := "res://scripts/ui/start_menu.gd"
const HOST_SCRIPT := "res://scripts/ui/computerroom.gd"

## Every unique name start_menu.gd binds in _bind_ui — a rename in the editor breaks the bind at boot,
## so pin the roster here where it fails loudly instead.
const BOUND := ["ButtonRow", "Buttons", "ContinueButton", "LoadGameButton", "NewGameButton",
	"SettingsButton", "QuitButton", "Black", "QuoteRoot", "QuoteLabel", "AttribLabel", "MenuInputShield"]


func test_hosts_point_at_the_authored_scene() -> void:
	# The conversion contract: everything that raises the menu loads the SCENE (root carries the script) —
	# the computer-room host's const and the scene itself. A bare-script instantiation would silently skip
	# the authored layout and _bind_ui would null-deref at boot.
	var host_src := FileAccess.get_file_as_string(HOST_SCRIPT)
	assert_true(host_src.contains("const START_MENU_SCENE := \"%s\"" % SCENE),
		"the computer-room host instances the authored scene")
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_true(inst is Control, "root is the full-rect Control the computer-room canvas expects")
	assert_not_null(inst.get_script(), "the root carries a script")
	assert_eq(String(inst.get_script().resource_path), SCRIPT_PATH, "the root carries start_menu.gd")
	inst.free()


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. The scene must hold only structure.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
	inst.free()


func test_bound_chrome_keeps_the_layout_contracts() -> void:
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	# The button column hugs the RIGHT edge (full-rect row, END alignment) and is vertically centred —
	# the computer-room intro fills the frame and the menu drops into the room's empty right side.
	var row := inst.get_node("%ButtonRow") as HBoxContainer
	assert_eq(row.anchor_right, 1.0, "the button row spans the screen (anchor_right)")
	assert_eq(row.anchor_bottom, 1.0, "the button row spans the screen (anchor_bottom)")
	assert_eq(row.alignment, BoxContainer.ALIGNMENT_END, "the column hugs the right edge (END alignment)")
	var col := (inst.get_node("%Buttons") as Control).get_parent() as VBoxContainer
	assert_eq(col.alignment, BoxContainer.ALIGNMENT_CENTER, "the buttons are vertically centred in the column")
	# ALL five buttons are authored (the script HIDES Continue/Load Game when no save exists — the
	# authored-scene equivalent of "not built"), in the fixed menu order.
	var buttons := inst.get_node("%Buttons") as VBoxContainer
	assert_eq(buttons.get_child_count(), 5, "the column authors exactly the five menu buttons")
	var order := ["ContinueButton", "LoadGameButton", "NewGameButton", "SettingsButton", "QuitButton"]
	for i in order.size():
		assert_eq(buttons.get_child(i).name, StringName(order[i]), "button %d is %s (menu order)" % [i, order[i]])
	# The boot cover: full-screen, BLACK, ships hidden, swallows clicks, and is authored AFTER the button
	# row so it draws above the menu when shown.
	var black := inst.get_node("%Black") as ColorRect
	assert_eq(black.anchor_right, 1.0, "the boot cover spans the screen (anchor_right)")
	assert_eq(black.anchor_bottom, 1.0, "the boot cover spans the screen (anchor_bottom)")
	assert_false(black.visible, "the boot cover ships hidden until a game starts / the warning plays")
	assert_eq(black.mouse_filter, Control.MOUSE_FILTER_STOP, "the boot cover swallows clicks during the intro")
	assert_eq(black.color, Color.BLACK, "the load happens behind pure black (no loading bar)")
	assert_lte(row.get_index(), black.get_index(), "the cover is authored after the buttons (draws above them)")
	# The quote card: %QuoteRoot is the SINGLE fade handle (ships fully transparent — the tweens own its
	# modulate.a) and the quote label wraps inside the gutters instead of clipping both edges.
	var quote_root := inst.get_node("%QuoteRoot") as MarginContainer
	assert_eq(quote_root.modulate.a, 0.0, "the quote card starts invisible (the fade tweens own modulate.a)")
	var quote := inst.get_node("%QuoteLabel") as Label
	assert_eq(quote.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "a long authored quote wraps in the gutters")
	assert_eq(quote.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "the quote text is centred")
	# The reveal input shield: full-rect click-eater, ships hidden, authored LAST so it sits above everything.
	var shield := inst.get_node("%MenuInputShield") as Control
	assert_false(shield.visible, "the input shield ships hidden until the menu reveal arms it")
	assert_eq(shield.mouse_filter, Control.MOUSE_FILTER_STOP, "the shield eats the skip click that revealed the menu")
	assert_eq(shield.get_index(), inst.get_child_count() - 1, "the shield is the last child (covers the whole menu)")
	inst.free()
