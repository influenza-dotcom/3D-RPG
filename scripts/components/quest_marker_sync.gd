class_name QuestMarkerSync
extends Node

## Drop into a level: spawns a WorldMarker for each ACTIVE quest objective that has show_marker, and removes them
## as objectives complete / quests finish or fail — so the Compass + Minimap point at your current objectives with
## no per-quest wiring. Driven by GameState's quest signals; rebuilds the whole set on any quest change (cheap —
## there are few active objectives).

## Tint for the spawned objective markers.
@export var marker_color: Color = Color(0.4, 0.9, 1.0)

var _markers: Array[Node] = []

func _ready() -> void:
	QuestTracker.quest_started.connect(_on_quest_changed)
	QuestTracker.objective_advanced.connect(_on_objective_advanced)
	QuestTracker.quest_completed.connect(_on_quest_changed)
	# WR-6: a FAILED quest (explicit fail_quest, or its expire_on_flag firing) leaves the active set exactly like a
	# completed one, so it needs the same rebuild — without this its beacons/pips linger for the rest of the session.
	# quest_failed(quest) carries the same single arg as quest_started/quest_completed, so it shares the handler.
	QuestTracker.quest_failed.connect(_on_quest_changed)
	_rebuild()

func _on_quest_changed(_quest = null) -> void:
	_rebuild()

func _on_objective_advanced(_quest, _objective) -> void:
	_rebuild()

## Clear and re-spawn a WorldMarker for every active, not-yet-done objective that wants one.
func _rebuild() -> void:
	for m in _markers:
		if is_instance_valid(m):
			m.queue_free()
	_markers.clear()
	for qid in GameState.active_quest_ids():
		var q: Quest = GameState.active_quest(qid)
		if q == null:
			continue
		for obj in q.objectives:
			if wants_marker(obj) and not GameState.is_objective_done(qid, obj.id):
				_spawn_marker(obj.marker_position)

func _spawn_marker(pos: Vector3) -> void:
	var m := WorldMarker.new()
	m.color = marker_color
	add_child(m)
	m.global_position = pos
	_markers.append(m)

## Pure: does this objective want a world marker? (Authored show_marker on a real objective.) Unit-testable.
static func wants_marker(obj: QuestObjective) -> bool:
	return obj != null and obj.show_marker
