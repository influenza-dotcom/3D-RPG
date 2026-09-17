@tool
class_name DialogueSelectorRow
extends Resource

## One row of a DialogueSelector: a conversation plus optional flag / quest gates. matches() is true when ALL
## set gates pass (an unset gate is ignored), so a row with no gates always matches. The first matching row in
## a DialogueSelector wins.

enum QuestState { ANY, ACTIVE, COMPLETED, NOT_STARTED, FAILED }  # WR-6 adds FAILED (an NPC reacts to a blown quest)

## The conversation used when this row matches.
@export var dialogue: DialogueResource
## Flag gate: matches when str(GameState.get_flag(required_flag)) == required_flag_value. Empty = no flag gate.
@export var required_flag: StringName = &""
@export var required_flag_value: String = "true"
## Quest gate: this quest id must be in `required_quest_state`. Empty = no quest gate.
@export var required_quest_id: StringName = &""
@export var required_quest_state: QuestState = QuestState.ACTIVE

## True when every SET gate passes (reads the GameState autoload at runtime). A row with no gates always matches.
func matches() -> bool:
	if required_flag != &"" and str(GameState.get_flag(required_flag)) != required_flag_value:
		return false
	if required_quest_id != &"":
		match required_quest_state:
			QuestState.ACTIVE:
				if not GameState.is_quest_active(required_quest_id):
					return false
			QuestState.COMPLETED:
				if not GameState.is_quest_completed(required_quest_id):
					return false
			QuestState.NOT_STARTED:
				if GameState.is_quest_active(required_quest_id) or GameState.is_quest_completed(required_quest_id) or GameState.is_quest_failed(required_quest_id):
					return false  # WR-6: a FAILED quest counts as "started" — it's no longer NOT_STARTED
			QuestState.FAILED:
				if not GameState.is_quest_failed(required_quest_id):
					return false
	return true

## The story-flag catalog, for the flag dropdown below (preloaded, no class_name — the ItemIds / Factions idiom).
const StoryFlags = preload("res://scripts/quests/story_flags.gd")

## Suggest the catalogued story flags for the flag this row's gate reads — a SUGGESTION, so a flag not yet in
## resources/story/FlagCatalog.tres stays typable; the Audit tab / validate_all WARN on it instead.
func _validate_property(property: Dictionary) -> void:
	if property.name == "required_flag":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = StoryFlags.names_csv()
