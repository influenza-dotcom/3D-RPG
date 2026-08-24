extends Node
## Menu layout-size probe — the DIAGNOSTIC twin of tests/test_menu_layout_stability.gd. The test tells you a
## card stopped fitting; this tells you WHICH node drives the minimum, which is the part you need to fix it.
## It measures whether a menu screen CHANGES SIZE as its tabs / states change, and whether any screen's
## content MINIMUM beats the band its panel is anchored into — the exact failure that makes Godot grow a panel
## past its anchors instead of clipping or scrolling ("the menu got bigger when I clicked Shirt").
## Every screen is hosted in a SubViewport pinned to the real 792x444 UI canvas (base 396x216 + stretch
## scale 0.5), so the numbers match what the player sees. Headless-safe: reads layout only, never renders.
##   godot --headless --path . res://scripts/tools/menu_size_probe.tscn
##   godot --headless --path . res://scripts/tools/menu_size_probe.tscn -- --tree=ShirtTab
## Prints PROBE_SCREEN / OVERFLOW / per-tab lines, plus a per-node minimum tree for --tree=<node name>.
## A screen whose content is built from live gameplay context (a merchant, a corpse, the player) measures
## EMPTY here — those are menu_qa_shots.gd's job (it boots the real game and prints QA_RECT per open card).

const CANVAS := Vector2i(792, 444)

## Screens to measure. Autoload-hosted screens are instanced fresh here (same .tscn the autoload wears).
const SCREENS: Array[String] = [
	"res://scenes/ui/character_creation.tscn",
	"res://scenes/ui/options_menu.tscn",
	"res://scenes/ui/implant_choice.tscn",
	"res://scenes/ui/chip_install_screen.tscn",
	"res://scenes/ui/implants_screen.tscn",
	"res://scenes/ui/inventory_screen.tscn",
	"res://scenes/ui/stats_screen.tscn",
	"res://scenes/ui/quest_journal.tscn",
	"res://scenes/ui/reputation_screen.tscn",
	"res://scenes/ui/character_inspect_screen.tscn",
	"res://scenes/ui/save_load_screen.tscn",
	"res://scenes/ui/heal_screen.tscn",
	"res://scenes/ui/respec_screen.tscn",
	"res://scenes/ui/level_up_screen.tscn",
	"res://scenes/ui/shop_screen.tscn",
	"res://scenes/ui/loot_screen.tscn",
	"res://scenes/ui/atm_screen.tscn",
	"res://scenes/ui/name_entry_dialog.tscn",
	"res://scenes/ui/terms_of_service_screen.tscn",
	"res://scenes/ui/chess_screen.tscn",
]

var _tree_filter := ""

func _ready() -> void:
	_run()

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tree="):
			_tree_filter = a.get_slice("=", 1)
	print("PROBE_CANVAS=", CANVAS)
	for path in SCREENS:
		await _probe(path)
	print("PROBE_DONE")
	get_tree().quit()

func _probe(path: String) -> void:
	var ps: PackedScene = load(path)
	if ps == null:
		print("PROBE_FAIL missing ", path)
		return
	var vp := SubViewport.new()
	vp.size = CANVAS
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var inst: Node = ps.instantiate()
	vp.add_child(inst)
	_force_open_state(inst)
	await _frames(4)
	print("PROBE_SCREEN ", path)
	var root := inst as Control
	if root != null:
		print("  root size=", root.size, " min=", root.get_combined_minimum_size())
	# Any Control anchored into a FRACTIONAL band: if its combined minimum beats that band, Godot grows it
	# past the anchors (off-centre / off-screen). That is the whole bug class this probe hunts.
	# ⚠ FALSE POSITIVES on a screen that ships HIDDEN and only lays out when it opens: an autowrap Label
	# measured at ~1px of width reports the height of ~90 wrapped lines (the chess screen's blindfold hint
	# reads 1556px tall here and ~30px once the screen is actually up). Confirm any OVERFLOW on a hidden
	# screen against a real open — menu_qa_shots.gd prints QA_RECT for every visible card.
	for c in _controls(inst):
		var band := Vector2(
			(c.anchor_right - c.anchor_left) * float(CANVAS.x),
			(c.anchor_bottom - c.anchor_top) * float(CANVAS.y))
		if band.x <= 0.0 or band.y <= 0.0:
			continue
		var m := c.get_combined_minimum_size()
		if m.x > band.x + 0.5 or m.y > band.y + 0.5:
			print("  OVERFLOW ", c.get_path(), " min=", m, " band=", band)
	for t in inst.find_children("*", "TabContainer", true, false):
		await _probe_tabs(t as TabContainer, inst)
	if _tree_filter != "":
		var hit := inst.find_children(_tree_filter, "", true, false)
		if not hit.is_empty():
			_dump(hit[0] as Control, 1)
	vp.queue_free()
	await _frames(2)

func _probe_tabs(tabs: TabContainer, inst: Node) -> void:
	# The screen's OUTER card — the thing that must never change size. Named "Panel" by convention in
	# every menu scene here; fall back to the first PanelContainer.
	var panel: Control = null
	for c in _controls(inst):
		if c.name == "Panel" and c is Control:
			panel = c
			break
	if panel == null:
		for c in _controls(inst):
			if c is PanelContainer or c is Panel:
				panel = c
				break
	var band := Vector2.ZERO
	if panel != null:
		band = Vector2(
			(panel.anchor_right - panel.anchor_left) * float(CANVAS.x),
			(panel.anchor_bottom - panel.anchor_top) * float(CANVAS.y))
	print("  TabContainer ", tabs.name, " min=", tabs.get_combined_minimum_size(),
		" use_hidden=", tabs.use_hidden_tabs_for_min_size, " panel=", (panel.name if panel != null else "?"),
		" band=", band)
	for i in tabs.get_tab_count():
		var page: Control = tabs.get_tab_control(i)
		print("    page[", i, "] ", page.name, " title=", tabs.get_tab_title(i),
			" page_min=", page.get_combined_minimum_size())
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await _frames(3)
		var pmin := panel.get_combined_minimum_size() if panel != null else Vector2.ZERO
		var over := ""
		if panel != null and (pmin.x > band.x + 0.5 or pmin.y > band.y + 0.5):
			over = "  <<< OVERFLOWS BAND"
		print("    ON tab[", i, "] ", tabs.get_tab_control(i).name,
			" panel_pos=", (panel.global_position if panel != null else Vector2.ZERO),
			" panel_size=", (panel.size if panel != null else Vector2.ZERO),
			" panel_min=", pmin,
			" tabs_min=", tabs.get_combined_minimum_size(), over)

## Put a screen into the state it wears when the player is actually looking at it: a screen that ships
## hidden never lays out (autowrap Labels then report the height of ~90 wrapped lines), and a screen with
## MUTUALLY EXCLUSIVE panes must be measured in the FATTER one — the chess board (8 x BOARD_CELL of hard
## grid minimum) is only visible with the Board Visualizer chip installed, and it is that open, not the
## blindfold one, that decides whether the card fits its anchor band.
func _force_open_state(inst: Node) -> void:
	for c in _controls(inst):
		if c.name == "Root":
			c.visible = true
	var board := inst.find_children("BoardBox", "", true, false)
	var blind := inst.find_children("BlindfoldBox", "", true, false)
	if not board.is_empty() and not blind.is_empty():
		(board[0] as Control).visible = true
		(blind[0] as Control).visible = false

## Every Control under `n` (the root included), depth-first.
func _controls(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Control:
			out.append(cur as Control)
		stack.append_array(cur.get_children())
	return out

## Who is driving the minimum: print the min-size contribution of every Control in a subtree.
func _dump(c: Control, depth: int) -> void:
	var pad := "  ".repeat(depth)
	print(pad, c.name, " [", c.get_class(), "] min=", c.get_combined_minimum_size(),
		" custom_min=", c.custom_minimum_size, " size=", c.size)
	for ch in c.get_children():
		if ch is Control:
			_dump(ch as Control, depth + 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
