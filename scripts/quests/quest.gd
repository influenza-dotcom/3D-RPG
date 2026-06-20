@tool
class_name Quest
extends Resource

## An authored quest: an ordered list of QuestObjectives plus the rewards granted on completion. Author it as a
## .tres; a QuestGiver / trigger / dialogue starts it via GameState.start_quest(quest). When all NON-optional
## objectives are done it auto-completes (if auto_complete) and GameState grants the rewards (money + items).

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
@export var objectives: Array[QuestObjective] = []

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
## The quest-giver's display name, for the journal / UI. Informational.
@export var giver_npc: String = ""
## A quest that must be COMPLETED before this one can start (start_quest refuses otherwise). Empty = none.
@export var prereq_quest_id: StringName = &""
## A quest auto-STARTED when this one completes — chains multi-stage storylines. Null = none.
@export var next_quest: Quest
