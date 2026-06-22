@tool
extends EditorInspectorPlugin

## NpcData inspector add-on: injects a resolved-archetype summary card at the top of an NpcData's inspector and
## flags conflicts inline -- chiefly the faction_id + faction both-set ambiguity -- so an authored NPC profile
## reads at a glance and dual-source mistakes are caught in the inspector. conflicts() is pure -> unit-tested.


func _can_handle(object: Object) -> bool:
	return object is NpcData


func _parse_begin(object: Object) -> void:
	if object is NpcData:
		add_custom_control(_build_card(object as NpcData))


func _build_card(nd: NpcData) -> Control:
	var box := VBoxContainer.new()
	var head := Label.new()
	head.text = "NpcData — %s" % (nd.display_name if nd.display_name != "" else "(unnamed)")
	box.add_child(head)
	var stats := Label.new()
	stats.modulate = Color(1, 1, 1, 0.8)
	stats.text = "  HP %.0f   sight %.0fm   faction: %s" % [nd.max_hp, nd.sight_range, _faction_label(nd)]
	box.add_child(stats)
	for w in conflicts(nd):
		var warn := Label.new()
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		warn.text = "⚠ " + w
		box.add_child(warn)
	return box


## Authoring conflicts on an NpcData (pure -> unit-testable). The headline one: both a faction_id string AND a
## faction resource set, which is ambiguous (the runtime usually resolves the resource, silently ignoring the id).
static func conflicts(nd: NpcData) -> PackedStringArray:
	var w := PackedStringArray()
	if nd == null:
		return w
	if nd.faction_id != "" and nd.faction != null:
		w.append("Both faction_id ('%s') and a faction resource are set — pick one to avoid an ambiguous faction." % nd.faction_id)
	return w


static func _faction_label(nd: NpcData) -> String:
	if nd.faction != null:
		var fid: Variant = nd.faction.get("id")
		return str(fid) if (fid != null and str(fid) != "") else "(resource)"
	if nd.faction_id != "":
		return nd.faction_id
	return "(none)"
