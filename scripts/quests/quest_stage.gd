@tool
class_name QuestStage
extends Resource

## One STAGE of a Quest -- a New Vegas quest beat: its own journal entry, its own objectives, and where the quest goes
## next. A Quest whose `stages` array is EMPTY has no stages at all and plays exactly as quests always have (its own
## `objectives` are the one implicit stage); fill `stages` and the quest is always IN exactly one of them, starting at
## stages[0].
##
## HOW A STAGE ENDS (QuestTracker owns it):
##   * every non-optional objective done -> the quest moves to `next_stage_id`, or, when that is blank (a TERMINAL
##     stage), completes -- if the quest `auto_complete`s; otherwise it waits for its turn-in exactly like a legacy
##     quest. An objective-less stage never ends on its own: it is a waiting beat that moves only on a jump.
##   * a JUMP: DialogueChoice.set_quest_stage_id (with advance_quest_id naming the quest) or
##     QuestTracker.set_quest_stage moves the quest to a named stage from ANY stage. Two routes converge by jumping
##     (or chaining via next_stage_id) into the same later stage.
## Entering a stage re-seeds progress for ITS objectives only (the save stores the current stage's progress), fires
## `set_flag_on_enter`, and back-fills FLAG objectives whose flag is already set.
##
## IDENTITY: `id` is persisted in the save (QuestTracker writes the current stage id per active quest), so it is a
## primary key like Quest.id -- renaming a stage a saved game is sitting in sends that save back to stages[0] on its
## next load (with a warning). The Quest tab's rename carries every next_stage_id in the quest along with it;
## references in OTHER files (a conversation's set_quest_stage_id) are what the Audit tab checks.

## This stage's id, unique within the quest (e.g. &"find_the_vault", &"bribe_route"). What next_stage_id and
## DialogueChoice.set_quest_stage_id name, and what the save remembers. Never blank.
@export var id: StringName = &""
## The journal entry while the quest is IN this stage -- the Journal shows it under the quest title in place of the
## quest's description. Blank = the quest description shows instead.
@export_multiline var journal_text: String = ""
## What this stage asks of the player. Same QuestObjective resources a stage-less quest carries; the ids must be unique
## within this stage (the Quest tab keeps them unique across the whole quest so a trigger's advance_objective_id is
## never ambiguous).
@export var objectives: Array[QuestObjective] = []
## Where the quest goes when this stage's required objectives are all done. Blank = this is a TERMINAL stage: the quest
## completes (auto_complete) or waits for its turn-in. Must name another stage of the same quest -- the Audit reports
## one that doesn't as an ERROR, and at runtime the quest stays put (with a warning) rather than completing by mistake.
@export var next_stage_id: StringName = &""
## OPTIONAL: set this GameState story flag (to true) the moment the quest enters this stage -- so a conversation, a
## door or a later quest can key off "the player reached this beat". Blank = none.
@export var set_flag_on_enter: StringName = &""

## The story-flag catalog, for the flag dropdown below (preloaded, no class_name — the ItemIds / Factions idiom).
const StoryFlags = preload("res://scripts/quests/story_flags.gd")

## Suggest the catalogued story flags for the flag entering this stage sets — a SUGGESTION, so a flag not yet in
## resources/story/FlagCatalog.tres stays typable; the Audit tab / validate_all WARN on it instead.
func _validate_property(property: Dictionary) -> void:
	if property.name == "set_flag_on_enter":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = StoryFlags.names_csv()
