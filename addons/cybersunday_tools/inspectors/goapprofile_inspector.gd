@tool
extends EditorInspectorPlugin

## GoapProfile inspector add-on: injects a resolved-planner card at the top of a GoapProfile's inspector — the
## per-goal priority and per-action cost the planner WOULD resolve (via priority_for / cost_for over the
## registered names), the validate() warnings for any stale/typo'd override row, and a banner noting that a
## non-empty `goals[]` is an enforced allow-list (this archetype pursues only those goals, plus an always-kept Idle).
## All compute lives in InspectorCalc statics + the resource's own validate(); this card is thin glue.

const InspectorCalc := preload("res://addons/cybersunday_tools/inspectors/inspector_calc.gd")
## The canonical goal/action name lists the profile's overrides are validated + resolved against.
const GoapLibrary := preload("res://scripts/npc/goap/goap_library.gd")


func _can_handle(object: Object) -> bool:
	return object is GoapProfile


func _parse_begin(object: Object) -> void:
	if object is GoapProfile:
		add_custom_control(_build_card(object as GoapProfile))


func _build_card(gp: GoapProfile) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(0, 90)
	var head := Label.new()
	head.text = "GoapProfile — resolved priorities / costs"
	box.add_child(head)
	for line in InspectorCalc.goap_priority_lines(gp, GoapLibrary.goal_names()):
		_add_dim(box, line)
	for line in InspectorCalc.goap_cost_lines(gp, GoapLibrary.action_names()):
		_add_dim(box, line)
	# validate() pushes warnings AND returns false for stale override rows; collect them as amber lines. We call it
	# only for its side-effect of revealing offenders — re-derive the offending rows here so they render in-panel.
	for warn in _validation_warnings(gp):
		var w := Label.new()
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		w.text = "⚠ " + warn
		box.add_child(w)
	if not gp.goals.is_empty():
		var banner := Label.new()
		banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		banner.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
		banner.text = "ℹ goals[] is an allow-list: this archetype pursues ONLY these goals (plus Idle, always kept). Empty = pursue all."
		box.add_child(banner)
	return box


func _add_dim(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.modulate = Color(1, 1, 1, 0.8)
	l.text = text
	box.add_child(l)


## Stale-override warnings, mirroring GoapProfile.validate's checks but RETURNING them (validate only push_warns).
## Kept in-card (not InspectorCalc) because it's pure display glue over the resource's own known-name comparison.
func _validation_warnings(gp: GoapProfile) -> PackedStringArray:
	var w := PackedStringArray()
	var goals := GoapLibrary.goal_names()
	var actions := GoapLibrary.action_names()
	for row in gp.goal_priorities:
		if row != null and not goals.has(String(row.goal)):
			w.append("goal_priorities row '%s' matches no known goal — override ignored." % String(row.goal))
	for row in gp.action_cost_overrides:
		if row != null and not actions.has(String(row.action)):
			w.append("action_cost_overrides row '%s' matches no known action — override ignored." % String(row.action))
	for g in gp.goals:
		if not goals.has(String(g)):
			w.append("goals entry '%s' matches no known goal." % String(g))
	return w
