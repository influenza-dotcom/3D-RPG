@tool
class_name Quest
extends Resource

## An authored quest: its objectives plus the rewards granted on completion. Author it as a .tres; a QuestGiver /
## trigger / dialogue starts it via GameState.start_quest(quest). When all NON-optional objectives are done it
## auto-completes (if auto_complete) and QuestTracker grants the rewards (money + items + XP + reputation).
##
## TWO SHAPES, one contract:
##   * STAGE-LESS (the default, `stages` empty): `objectives` is the whole quest -- one implicit stage. Every quest
##     authored before stages existed is this shape and plays unchanged.
##   * STAGED (`stages` filled): the quest is always IN exactly one QuestStage, starting at stages[0]; the CURRENT
##     stage's objectives are the live ones, its journal_text is the journal entry, and a stage hands off to its
##     next_stage_id (or completes the quest when that is blank). `objectives` on the Quest itself is IGNORED for a
##     staged quest (the Audit warns when both are filled). See quest_stage.gd for the stage rules.
## The helpers below are the ONE place that difference is resolved -- the tracker, the journal, the HUD, the markers
## and the debug console all ask `objectives_for_stage(stage_id)` instead of reading `objectives` directly.

@export var id: StringName = &""
@export var title: String = ""
## The journal's summary of the quest. For a staged quest it shows only while the current stage has no journal_text.
@export_multiline var description: String = ""
## The quest's objectives when it has NO stages. Ignored once `stages` is filled (the stages carry their own).
@export var objectives: Array[QuestObjective] = []
## OPTIONAL stages (New Vegas-style beats). Empty = a stage-less quest (above). Order matters for ONE thing only: the
## quest starts in stages[0]; after that it moves by next_stage_id / set_quest_stage_id, never by position.
@export var stages: Array[QuestStage] = []

@export_group("Rewards (on completion)")
## Items handed to the player — reuses ItemStack.seed_into (the same seeding the rest of the loot pipeline uses).
@export var rewards: Array[ItemStack] = []
## Zorkmids added to the player's wallet.
@export var reward_money: float = 0.0
## XP added to the player on completion (rank 29). 0 = no XP reward.
@export var reward_xp: float = 0.0
## Faction id -> reputation delta granted on completion (GameState resolves each id via the Factions registry and
## calls Reputation.add_reputation). e.g. { "townsfolk": 15, "raiders": -10 } — help the town, anger the raiders.
@export var reward_reputation: Dictionary = {}

@export_group("Flow")
## Auto-finish + grant the moment all non-optional objectives are done; off = requires an explicit turn-in.
@export var auto_complete: bool = true
## A quest that must be COMPLETED before this one can start (start_quest refuses otherwise). Empty = none.
@export var prereq_quest_id: StringName = &""
## A quest auto-STARTED when this one completes — chains separate quests into a storyline. (Beats WITHIN one quest are
## `stages`.) Null = none.
@export var next_quest: Quest
## WR-6 OPTIONAL expiry: while this quest is ACTIVE, setting this GameState story flag auto-FAILS it (the "you
## missed the window" trigger — fire the flag when the hostage dies, the bomb detonates, the deadline passes).
## Empty = the quest never expires. A failed quest can't be re-started and opens a FAILED dialogue gate.
@export var expire_on_flag: StringName = &""


# --- stage helpers (pure: no tracker, no tree) ---------------------------------------------------------------------

## True when this quest is authored with stages.
func has_stages() -> bool:
	return not stages.is_empty()


## The stage whose id is `stage_id` (FIRST match), or null -- blank ids never match, and a stage-less quest has none.
func stage_by_id(stage_id: StringName) -> QuestStage:
	if stage_id == &"":
		return null
	for st in stages:
		if st != null and st.id == stage_id:
			return st
	return null


## The stage a quest STARTS in: stages[0]'s id (&"" for a stage-less quest, or a first slot that is null).
func first_stage_id() -> StringName:
	if stages.is_empty() or stages[0] == null:
		return &""
	return stages[0].id


## The live objectives while the quest is in `stage_id`. A stage-less quest answers its own `objectives` whatever id
## is passed; a staged quest answers that stage's objectives, or an EMPTY array for an unknown id (never the Quest's
## ignored `objectives`, which would advance steps the player is not on).
func objectives_for_stage(stage_id: StringName) -> Array[QuestObjective]:
	if stages.is_empty():
		return objectives
	var st := stage_by_id(stage_id)
	if st == null:
		var none: Array[QuestObjective] = []
		return none
	return st.objectives


## Every objective the quest can ever ask for, in authored order (the quest's own for a stage-less quest; every
## stage's, stage by stage, for a staged one). What the Audit resolves an advance_objective_id against.
func all_objectives() -> Array[QuestObjective]:
	if stages.is_empty():
		return objectives
	var out: Array[QuestObjective] = []
	for st in stages:
		if st != null:
			out.append_array(st.objectives)
	return out


## The non-blank stage ids, in authored order.
func stage_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for st in stages:
		if st != null and st.id != &"":
			out.append(st.id)
	return out


## The journal entry while the quest is in `stage_id`: that stage's journal_text when it has one, else the quest's
## description. Pure, so the Journal and its tests share one rule.
func journal_text_for(stage_id: StringName) -> String:
	var st := stage_by_id(stage_id)
	if st != null and st.journal_text.strip_edges() != "":
		return st.journal_text
	return description
