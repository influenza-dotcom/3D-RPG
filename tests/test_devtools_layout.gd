extends GutTest

## THE HEIGHT / WIDTH CONTRACT of the CYBER SUNDAY bottom panel, pinned STRUCTURALLY over every tool tab.
##
## Why structural and not pixel-exact: the panel is ONE shared bottom-panel item, a TabContainer's minimum height is
## the CURRENT tab's minimum (use_hidden_tabs_for_min_size is false), and the editor's bottom splitter KEEPS whatever
## height it once grew to. So a single tab that reports a tall minimum permanently steals viewport height from every
## other tab. Combined minimum sizes are engine- and theme-dependent (font, DPI, editor theme margins) and asserting
## them would be brittle -- what IS stable is the SHAPE that keeps a tab short and narrow:
##
##   (a) an autowrapped Label outside a ScrollContainer must cap max_lines_visible -- otherwise one long status line
##       makes the head three, five, nine rows tall and the splitter never gives that height back.
##   (b) OptionButton.fit_to_longest_item defaults TRUE, so ONE long row (an item id, a line's opening words) becomes
##       the control's minimum WIDTH -- and with horizontal scrolling disabled that widens the whole panel.
##   (c) a Tree / ItemList / RichTextLabel / GraphEdit / TextEdit with a tall floor belongs INSIDE the scroll, so only
##       the ScrollContainer's own floor ever reaches the TabContainer.
##   (d) a designer reads every one of these labels all day. Nothing below MIN_LABEL_FONT px.
##
## Every tab is built OFF-TREE (script.new(), never add_child): _init is required to be free of EditorInterface /
## get_tree() / await, so construction alone is the whole fixture. Failures name the tab and the control's path.
##
## The list below IS cyber_panel.gd's preload list in its group order; the panel test at the bottom fails if the two
## drift apart (a tool added to the panel and not to this list changes the tool COUNT).

const TAB_SCRIPTS := [
	# Build
	"res://addons/cybersunday_tools/dock_palette/palette_dock.gd",
	"res://addons/cybersunday_tools/dock_place/scene_placer.gd",
	"res://addons/cybersunday_tools/placer/item_placer_dock.gd",
	"res://addons/cybersunday_tools/dock_level/level_dock.gd",
	# Create
	"res://addons/cybersunday_tools/dock_content/content_dock.gd",
	"res://addons/cybersunday_tools/dock_blueprint/blueprint_view.gd",
	"res://addons/cybersunday_tools/dock_browser/content_browser.gd",
	"res://addons/cybersunday_tools/dock_dialogue/dialogue_editor.gd",
	"res://addons/cybersunday_tools/dock_quest/quest_editor.gd",
	"res://addons/cybersunday_tools/dock_loot/loot_editor.gd",
	"res://addons/cybersunday_tools/dock_text/text_editor.gd",
	"res://addons/cybersunday_tools/panel_graph/dialogue_graph.gd",
	"res://addons/cybersunday_tools/dock_icons/icon_view.gd",
	# Tune
	"res://addons/cybersunday_tools/dock_tuning/tuning_browser.gd",
	"res://addons/cybersunday_tools/dock_faction/faction_matrix.gd",
	"res://addons/cybersunday_tools/dock_encounter/encounter_view.gd",
	# Check
	"res://addons/cybersunday_tools/panel_audit/audit_panel.gd",
	"res://addons/cybersunday_tools/dock_reach/reach_view.gd",
	"res://addons/cybersunday_tools/dock_refs/ref_viewer.gd",
	"res://addons/cybersunday_tools/dock_stats/stats_view.gd",
	# Advanced
	"res://addons/cybersunday_tools/dock_saves/save_inspector.gd",
	"res://addons/cybersunday_tools/dock_scenediff/scene_diff_view.gd",
	"res://addons/cybersunday_tools/dock_arch/arch_view.gd",
	"res://addons/cybersunday_tools/dock_bridge/bridge_view.gd",
]

const PANEL_SCRIPT := "res://addons/cybersunday_tools/cyber_panel.gd"

## Build / Create / Tune / Check / Advanced, and the 24 tools inside them.
const GROUP_COUNT := 5
const TOOL_COUNT := 24
## Anything smaller than this is squinting territory in a dock the designer lives in.
const MIN_LABEL_FONT := 12
## A growing control may floor itself up to here; past it, it has to be inside the scroll.
const TALL_FLOOR := 120.0
## How many offending controls a failure message names before it starts counting instead.
const REPORT_LIMIT := 6


# --- helpers ----------------------------------------------------------------------------------------------------

## Build one tool tab off-tree. Returns null (after a failed assert) when the script will not load or is not a Control.
func _build(path: String) -> Control:
	var gds := load(path) as GDScript
	assert_not_null(gds, "tab script should load: %s" % path)
	if gds == null:
		return null
	var c := gds.new() as Control
	assert_not_null(c, "tab script should build a Control in _init, off-tree: %s" % path)
	return c


## Every Control at or under `node`, depth-first. get_children() skips INTERNAL children on purpose: a
## ScrollContainer's own scrollbars and a SpinBox's own LineEdit are engine plumbing, not authored UI.
func _walk(node: Node, out: Array) -> void:
	if node is Control:
		out.append(node)
	for child in node.get_children():
		_walk(child, out)


## True when some ancestor of `node` is a ScrollContainer -- i.e. its height is fenced and cannot reach the
## TabContainer. Walks parents until it runs out, which off-tree is the tab root itself.
func _inside_scroll(node: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


## "Level/VBoxContainer/HBoxContainer/Label" plus the control's text -- enough for a human to find it in source.
func _where(tab: Control, node: Node) -> String:
	var parts := PackedStringArray()
	var n: Node = node
	while n != null and n != tab:
		parts.insert(0, String(n.name))
		n = n.get_parent()
	var text := ""
	if node is Label:
		text = (node as Label).text
	elif node is Button:
		text = (node as Button).text
	if text != "":
		text = " [%s]" % text.substr(0, 40).replace("\n", " ")
	return "%s/%s%s" % [String(tab.name), "/".join(parts), text]


## The controls whose content GROWS with the project (rows, lines, nodes), so must be fenced by a scroll.
static func _is_growing(c: Control) -> bool:
	return c is Tree or c is ItemList or c is RichTextLabel or c is GraphEdit or c is TextEdit


## Offenders as one readable line. A tab that breaks a rule in one place usually breaks it in twenty (they come out
## of one shared builder), and a hundred-entry assert message buries the fix -- so name a handful and count the rest.
static func _listed(offenders: PackedStringArray) -> String:
	if offenders.size() <= REPORT_LIMIT:
		return ", ".join(offenders)
	return "%s (+%d more)" % [", ".join(offenders.slice(0, REPORT_LIMIT)), offenders.size() - REPORT_LIMIT]


# --- the contract -----------------------------------------------------------------------------------------------

func test_every_tool_tab_honours_the_height_and_width_contract() -> void:
	assert_eq(TAB_SCRIPTS.size(), TOOL_COUNT, "this list must stay in step with cyber_panel.gd's preloads")
	for path: String in TAB_SCRIPTS:
		var tab := _build(path)
		if tab == null:
			continue
		var controls: Array = []
		_walk(tab, controls)
		var unclamped := PackedStringArray()
		var wide := PackedStringArray()
		var tall := PackedStringArray()
		var tiny := PackedStringArray()
		for c: Control in controls:
			if c is Label:
				var l := c as Label
				if l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.max_lines_visible <= 0 and not _inside_scroll(l):
					unclamped.append(_where(tab, l))
				# NOTE: Control has has_theme_font_size_override() / add_theme_font_size_override() but NO
				# get_theme_font_size_override() -- read the resolved value with get_theme_font_size(), which
				# returns the override when one is set.
				if l.has_theme_font_size_override("font_size") and l.get_theme_font_size("font_size") < MIN_LABEL_FONT:
					tiny.append("%s = %d px" % [_where(tab, l), l.get_theme_font_size("font_size")])
			if c is OptionButton and (c as OptionButton).fit_to_longest_item:
				wide.append(_where(tab, c))
			if _is_growing(c) and c.custom_minimum_size.y > TALL_FLOOR and not _inside_scroll(c):
				tall.append("%s floors %d px" % [_where(tab, c), int(c.custom_minimum_size.y)])
		var who := String(tab.name)
		assert_eq(unclamped.size(), 0, "%s: an autowrapped Label outside a ScrollContainer must cap max_lines_visible (2 is the house rule), or the head grows with its text and the bottom splitter keeps that height -- %s" % [who, _listed(unclamped)])
		assert_eq(wide.size(), 0, "%s: fit_to_longest_item defaults TRUE, so one long row becomes the control's minimum width and widens the whole panel -- set it false (PickerRows.apply does) on %s" % [who, _listed(wide)])
		assert_eq(tall.size(), 0, "%s: a list/text control floored above %d px must sit inside a ScrollContainer, so only the scroll's floor reaches the TabContainer -- %s" % [who, int(TALL_FLOOR), _listed(tall)])
		assert_eq(tiny.size(), 0, "%s: a designer reads every one of these -- no Label font override below %d px -- %s" % [who, MIN_LABEL_FONT, _listed(tiny)])
		tab.free()


## The panel itself: five job groups, 24 tools, every Control name unique (cyber_panel keys _tabs by that name, so a
## collision silently makes one tool unreachable through show_tab / open_in_editor / on_scene_changed), and a title
## plus a tooltip on every tab a designer can hover.
func test_the_panel_groups_24_uniquely_named_tools_and_tips_every_tab() -> void:
	var gds := load(PANEL_SCRIPT) as GDScript
	assert_not_null(gds, "cyber_panel.gd should load")
	if gds == null:
		return
	var panel := gds.new() as TabContainer
	assert_not_null(panel, "cyber_panel should construct off-tree (its _init only adds children and sets titles)")
	if panel == null:
		return
	var groups: Array = []
	for child in panel.get_children():
		if child is TabContainer:
			groups.append(child)
	assert_eq(groups.size(), GROUP_COUNT, "the panel holds one inner TabContainer per job group")

	var tools := 0
	var untitled := PackedStringArray()
	var untipped := PackedStringArray()
	for group: TabContainer in groups:
		var gi := panel.get_tab_idx_from_control(group)
		assert_true(gi >= 0, "group %s should be registered as a tab of the panel" % group.name)
		if gi >= 0 and String(panel.get_tab_tooltip(gi)).strip_edges().is_empty():
			untipped.append("group %s" % group.name)
		for child in group.get_children():
			var leaf := child as Control
			if leaf == null:
				continue
			tools += 1
			var ti := group.get_tab_idx_from_control(leaf)
			if ti < 0:
				continue
			if String(group.get_tab_title(ti)).strip_edges().is_empty():
				untitled.append(String(leaf.name))
			if String(group.get_tab_tooltip(ti)).strip_edges().is_empty():
				untipped.append(String(leaf.name))
	assert_eq(tools, TOOL_COUNT, "the five groups hold every tool between them")

	# _tabs is keyed by Control name, so its size COLLAPSES duplicates -- comparing it with the child count is the
	# uniqueness check, and it does not depend on TabContainer's tab bookkeeping.
	var registry: Dictionary = panel.get("_tabs")
	assert_eq(registry.size(), tools, "every tool's Control name must be unique -- cyber_panel routes show_tab / open_in_editor / on_scene_changed by that name, so a collision makes one tool unreachable")
	assert_eq(untitled.size(), 0, "every tool tab needs the friendly title a designer reads -- missing on %s" % ", ".join(untitled))
	assert_eq(untipped.size(), 0, "every group tab and tool tab needs a tooltip saying what it is for and what it writes -- missing on %s" % ", ".join(untipped))
	panel.free()
