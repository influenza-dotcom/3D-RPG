@tool
extends TabContainer

## Single host for every CYBER SUNDAY tool Control. The tools are grouped by the JOB a designer is doing -- five
## outer tabs, each an inner TabContainer of related tools -- instead of one flat strip of 24 titles:
##
##   Build     Palette / Place / Place Item / Level                 -- put things into the open scene
##   Create    New / Blueprints / Browse / Dialogue / Quests / Loot / Text / Graphs / Icons -- author content files
##   Tune      Tuning / Factions / Encounter                         -- global numbers + relationships
##   Check     Audit / Reach / Refs / Stats                          -- is it valid, can the player reach it
##   Advanced  Saves / Scene Diff / Architecture / AI Bridge         -- developer + AI tooling, ignorable
##
## WHY groups: 24 titles need ~1800 px of tab strip, and the editor's bottom panel only spans the centre column
## (~1200 px on a 1920 display between the Scene and Inspector docks), so a third of the tools -- including Reach,
## the one that answers "why can't the player start my quest" -- sat behind scroll arrows. Five short outer titles
## can never overflow, and each inner strip holds at most nine. The price is one extra tab-bar row (~30 px), paid
## back by the height fences on the tallest tabs.
##
## Each tool keeps its Control `name` (tests pin those: "Quest Edit", "Items", "Content", ...) -- the DISPLAY title a
## designer reads is set per tab with set_tab_title, so a friendlier title never breaks a test or a docs anchor.
##
## This panel is also the HANDOFF HOST: `open_in_editor(path)` routes a content file to the tab that edits it and
## `show_tab(name)` switches to any tool by its Control name (expanding the bottom panel). Tabs reach it ONLY through
## core/host.gd (`Host.find(self)` -- null off-tree), never by get_parent() chains, so the nesting depth stays a
## private layout detail.
##
## plugin.gd adds THIS as ONE collapsible bottom panel instead of several right-side docks -- right-side docks
## contribute to the editor's MINIMUM height (and Godot restores their saved sizes on relaunch), which on a
## short/HiDPI display forces the whole editor taller than the screen and squishes the 3D viewport. A bottom
## panel is collapsible and out of the dock column. NOTE the real height mechanism: a TabContainer's minimum is
## the CURRENT tab's minimum (use_hidden_tabs_for_min_size is false), and the editor's bottom splitter KEEPS the
## height it grew to when a tall tab was shown -- so every tab must be short when SELECTED, not just on average.

const PaletteDock := preload("res://addons/cybersunday_tools/dock_palette/palette_dock.gd")
const ItemPlacerDock := preload("res://addons/cybersunday_tools/placer/item_placer_dock.gd")
const LevelDock := preload("res://addons/cybersunday_tools/dock_level/level_dock.gd")
const ContentDock := preload("res://addons/cybersunday_tools/dock_content/content_dock.gd")
const BlueprintView := preload("res://addons/cybersunday_tools/dock_blueprint/blueprint_view.gd")
const IconView := preload("res://addons/cybersunday_tools/dock_icons/icon_view.gd")
const TuningBrowser := preload("res://addons/cybersunday_tools/dock_tuning/tuning_browser.gd")
const FactionDock := preload("res://addons/cybersunday_tools/dock_faction/faction_matrix.gd")
const AuditPanel := preload("res://addons/cybersunday_tools/panel_audit/audit_panel.gd")
const SaveInspector := preload("res://addons/cybersunday_tools/dock_saves/save_inspector.gd")
const GraphsPanel := preload("res://addons/cybersunday_tools/panel_graph/dialogue_graph.gd")
const DialogueEditor := preload("res://addons/cybersunday_tools/dock_dialogue/dialogue_editor.gd")
const QuestEditor := preload("res://addons/cybersunday_tools/dock_quest/quest_editor.gd")
const LootEditor := preload("res://addons/cybersunday_tools/dock_loot/loot_editor.gd")
const TextEditor := preload("res://addons/cybersunday_tools/dock_text/text_editor.gd")
const ContentBrowser := preload("res://addons/cybersunday_tools/dock_browser/content_browser.gd")
const RefViewer := preload("res://addons/cybersunday_tools/dock_refs/ref_viewer.gd")
const EncounterView := preload("res://addons/cybersunday_tools/dock_encounter/encounter_view.gd")
const StatsView := preload("res://addons/cybersunday_tools/dock_stats/stats_view.gd")
const SceneDiffView := preload("res://addons/cybersunday_tools/dock_scenediff/scene_diff_view.gd")
const ScenePlacer := preload("res://addons/cybersunday_tools/dock_place/scene_placer.gd")
const ArchView := preload("res://addons/cybersunday_tools/dock_arch/arch_view.gd")
const ReachView := preload("res://addons/cybersunday_tools/dock_reach/reach_view.gd")
## The Bridge is meta-tooling (it exposes the OTHER tabs' read-only data to an external AI client), so it is the last
## tool of the Advanced group; a designer who is not running an AI assistant never needs it.
const BridgeView := preload("res://addons/cybersunday_tools/dock_bridge/bridge_view.gd")

## Set by plugin.gd to EditorPlugin.make_bottom_panel_item_visible bound to this panel, so show_tab() can EXPAND the
## bottom panel (a collapsed panel switching tabs invisibly would look like a dead button). Invalid off-tree.
var reveal_panel: Callable = Callable()

## Control `name` -> the tool Control, for show_tab / open_in_editor / on_scene_changed. Filled by _group().
var _tabs: Dictionary = {}


func _init() -> void:
	name = "CYBER SUNDAY"
	# EDITOR UI: never run the game's automatic Control-text translation over the dock. Every tab paints
	# project data -- resource names, dialogue prose, save contents, user-typed search text -- and none of it
	# may be looked up as a translation msgid if the project ever ships locales. DISABLED here inherits to
	# every child tab and inner group (AUTO_TRANSLATE_MODE_INHERIT is the child default), so one line covers the dock.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	# Explicit: the panel's minimum follows the CURRENT tab only (see the header note on the height mechanism).
	use_hidden_tabs_for_min_size = false

	_group("Build", "Put things into the open scene: components, NPCs, doors, items, CSG blockout, and level checks.", [
		[PaletteDock, "Palette", "Add a behaviour component (Talkable, QuestStarter, TriggerVolume...) under the selected node. Writes: the open scene."],
		[ScenePlacer, "Place", "Drop NPCs, spawns, doors, containers and CSG blockout pieces into the open level, in front of the camera. Writes: the open scene."],
		[ItemPlacerDock, "Place Item", "Drop any authored item into the scene as a world pickup, in front of the camera. Writes: the open scene."],
		[LevelDock, "Level", "Create a level from the template, then bake and check its navmesh. Writes: New Level only."],
	])
	_group("Create", "Create and edit content files: quests, conversations, items, loot, text, icons.", [
		[ContentDock, "New", "Create a new quest, dialogue, item, weapon, faction... from a template. Writes: one new file per press."],
		[BlueprintView, "Blueprints", "Scaffold a complete enemy pack (faction, weapon, item, loot table, archetype) in one go. Writes: five new files."],
		[ContentBrowser, "Browse", "Find any content file by name and open it in the Inspector. Read-only."],
		[DialogueEditor, "Dialogue", "Edit a conversation's lines, choices, gates and consequences. Writes: on Save only."],
		[QuestEditor, "Quests", "Edit a quest's objectives, rewards and flow. Writes: on Save only."],
		[LootEditor, "Loot", "Edit a loot table's drops with a live expected-drops readout. Writes: on Save only."],
		[TextEditor, "Text", "Edit every player-facing name and description in one list. Writes: on Save only."],
		[GraphsPanel, "Graphs", "Draw a conversation or the quest chain as a graph. Read-only."],
		[IconView, "Icons", "Render inventory icons for every item into resources/icons/. Writes: PNG files only."],
	])
	_group("Tune", "Global numbers and relationships: tuning groups, faction relations, encounter previews.", [
		[TuningBrowser, "Tuning", "Open a global tuning group (economy, camera, movement...) in the Inspector. Read-only."],
		[FactionDock, "Factions", "Set how each faction's NPCs treat other factions' NPCs. Writes: faction files."],
		[EncounterView, "Encounter", "Preview what the selected EncounterSpawner will spawn, per difficulty. Read-only."],
	])
	_group("Check", "Is it valid, and can the player reach it? Reports only.", [
		[AuditPanel, "Audit", "Scan the open scene and every content file for wiring problems. Read-only until you press Fix."],
		[ReachView, "Reach", "Can the PLAYER get to it? Walks from the boot scene to every level, quest and conversation. Read-only."],
		[RefViewer, "Refs", "What points at this file? Lists every scene, resource and script that references it. Read-only."],
		[StatsView, "Stats", "How much content exists, and which files nothing references. Read-only."],
	])
	_group("Advanced", "Developer and AI tooling. Designers can ignore this group.", [
		[SaveInspector, "Saves", "Inspect what a save file on this machine contains. Read-only."],
		[SceneDiffView, "Scene Diff", "Compare a before-copy of a scene with the edited scene. Read-only."],
		[ArchView, "Architecture", "Developer index of the code's @system annotations. Read-only."],
		[BridgeView, "AI Bridge", "Only used by an attached AI assistant (Claude Code / MCP). Nothing runs until Start."],
	])


## Build one job group: an inner TabContainer titled `title`, holding one tool per row of `rows`
## ([script, display title, tooltip]). The tool keeps its own Control `name`; only the painted title changes.
func _group(title: String, tooltip: String, rows: Array) -> TabContainer:
	var g := TabContainer.new()
	g.name = title
	g.use_hidden_tabs_for_min_size = false
	add_child(g)
	set_tab_tooltip(get_tab_count() - 1, tooltip)
	for r in rows:
		var script: GDScript = r[0]
		var c: Control = script.new()
		g.add_child(c)
		var idx := g.get_tab_count() - 1
		g.set_tab_title(idx, str(r[1]))
		g.set_tab_tooltip(idx, str(r[2]))
		_tabs[String(c.name)] = c
	return g


# --- handoff host API (reached by tabs through core/host.gd) --------------------------------------------------------

## The tool Control registered under `tab_name` (its Control `name`, e.g. "Quest Edit"), or null.
func tab(tab_name: String) -> Control:
	return _tabs.get(tab_name, null) as Control


## Switch to the named tool -- outer group + inner tab -- expand the bottom panel, and return the Control (null when
## there is no such tool). Selecting the inner tab is what fires a lazy tool's first-reveal scan, so a handoff into
## a never-opened tab still lands on populated pickers.
func show_tab(tab_name: String) -> Control:
	var c := tab(tab_name)
	if c == null:
		return null
	var group := c.get_parent() as TabContainer
	if group != null:
		var gi := get_tab_idx_from_control(group)
		if gi >= 0:
			current_tab = gi
		var ci := group.get_tab_idx_from_control(c)
		if ci >= 0:
			group.current_tab = ci
	if reveal_panel.is_valid():
		reveal_panel.call()
	return c


## Which tool edits a content resource in-plugin. "" for types that only the Inspector edits (Item, WeaponData,
## Faction, ...). NpcData maps to Place because "open the archetype" for a designer means "put one in the level".
static func editor_tab_for(res: Resource) -> String:
	if res is Quest:
		return "Quest Edit"
	if res is DialogueResource:
		return "Dialogue Edit"
	if res is LootTable:
		return "Loot Edit"
	if res is NpcData:
		return "Place"
	return ""


## Hand a content file to the tab that edits it: switches there and asks the tab to `select_path(path)` (duck-typed;
## the tab returns true when it found + loaded the file). Anything else -- an unknown type, a tab without
## select_path, a file the tab cannot find -- falls back to opening it in the Inspector and returns false, so the
## caller's status line can say which happened.
func open_in_editor(path: String) -> bool:
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var res := load(path) as Resource
	if res == null:
		return false
	var tab_name := editor_tab_for(res)
	if tab_name != "":
		var c := show_tab(tab_name)
		if c != null and c.has_method("select_path") and bool(c.call("select_path", path)):
			return true
	EditorInterface.edit_resource(res)
	return false


## Forwarded by plugin.gd from EditorPlugin.scene_changed (and once at enable) so every tab that places into / checks
## the edited scene can grey its buttons with "Open a scene first" BEFORE the designer clicks, not after.
func on_scene_changed(root: Node) -> void:
	for c in _tabs.values():
		if c.has_method("on_scene_changed"):
			c.call("on_scene_changed", root)
