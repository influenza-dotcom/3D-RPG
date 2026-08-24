@tool
extends TabContainer

## Single host for every CYBER SUNDAY tool Control, each an inner tab (24 in all): the palette, the item + scene
## placers, level, the content generators, blueprint + icon viewers, tuning, factions, audit, the save inspector,
## the dialogue/quest graph viewers, the Dialogue/Quest/Loot/Text editors, the content browser, the ref viewer,
## the encounter / stats / scene-diff / arch views, the Reach report, and the AI Bridge.
## plugin.gd adds THIS as ONE collapsible bottom panel instead of several right-side docks --
## right-side docks contribute to the editor's MINIMUM height (and Godot restores their saved sizes on relaunch),
## which on a short/HiDPI display forces the whole editor taller than the screen and squishes the 3D viewport. A
## bottom panel is collapsible and out of the dock column, so it never forces the editor taller. Each child Control
## sets its own `name`, which TabContainer uses as the tab title.

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
## Sits beside the other read-only reporters (Stats / Refs / Audit) in spirit, but is appended rather than inserted
## so no existing tab shifts index. Answers the one question none of them do: what can a PLAYER actually reach from
## the boot scene — the check that stays green on a quest nothing starts.
const ReachView := preload("res://addons/cybersunday_tools/dock_reach/reach_view.gd")
## LAST tab on purpose: the Bridge is meta-tooling (it exposes the OTHER tabs' read-only data to an external AI
## client), not an authoring surface, and appending keeps every existing tab at the index the user already knows.
const BridgeView := preload("res://addons/cybersunday_tools/dock_bridge/bridge_view.gd")


func _init() -> void:
	name = "CYBER SUNDAY"
	# EDITOR UI: never run the game's automatic Control-text translation over the dock. Every tab paints
	# project data — resource names, dialogue prose, save contents, user-typed search text — and none of it
	# may be looked up as a translation msgid if the project ever ships locales. DISABLED here inherits to
	# every child tab (AUTO_TRANSLATE_MODE_INHERIT is the child default), so one line covers the whole dock.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(PaletteDock.new())
	add_child(ItemPlacerDock.new())
	add_child(LevelDock.new())
	add_child(ContentDock.new())
	add_child(BlueprintView.new())
	add_child(IconView.new())
	add_child(TuningBrowser.new())
	add_child(FactionDock.new())
	add_child(AuditPanel.new())
	add_child(SaveInspector.new())
	add_child(GraphsPanel.new())
	add_child(DialogueEditor.new())
	add_child(QuestEditor.new())
	add_child(LootEditor.new())
	add_child(TextEditor.new())
	add_child(ScenePlacer.new())
	add_child(ContentBrowser.new())
	add_child(RefViewer.new())
	add_child(EncounterView.new())
	add_child(StatsView.new())
	add_child(SceneDiffView.new())
	add_child(ArchView.new())
	add_child(ReachView.new())
	add_child(BridgeView.new())
