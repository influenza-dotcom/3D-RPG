@tool
class_name DialogueChoice
extends Resource

## One selectable option on a branching DialogueLine: a button label plus where picking it jumps.
## `target` is an INDEX into the owning DialogueResource.lines -- the same integer space the
## DialogueManager already addresses lines with via its _index cursor. The DEFAULT, DialogueLine.CONTINUE,
## carries the conversation on to the NEXT line (so a freshly-authored choice doesn't dead-end the convo);
## use DialogueLine.END (-1) to FINISH instead, or a line index >= 0 to BRANCH to a specific line.
##
## Authorable as a sub-resource nested in DialogueLine.choices, exactly like DialogueLine nests in
## DialogueResource.lines, so whole branching scripts are still .tres files.

## Drives the give_item_id dropdown from the item ids on disk (const-preloaded — see item_ids.gd).
const ItemIds = preload("res://scripts/items/item_ids.gd")
## Faction registry (preloaded by path) for the reputation gate / reward dropdowns (WR-1/WR-3).
const Factions = preload("res://scripts/faction/factions.gd")
## Perk registry (preloaded by path — like the two above it carries NO class_name) for the perk gate dropdown.
const Perks = preload("res://scripts/player/perks.gd")

## Which tracked state a quest gate (required_quest_id) checks for: ANY = the player merely KNOWS the quest
## (active OR completed OR failed); ACTIVE / COMPLETED / FAILED = exactly that state (WR-6 adds FAILED).
enum QuestGate { ANY, ACTIVE, COMPLETED, FAILED }

## The button label the player sees and clicks for this option.
@export var text: String = ""
## Where picking this leads. DialogueLine.CONTINUE (-2, the default) advances to the NEXT line; DialogueLine.END
## (-1) finishes the conversation; an INDEX >= 0 jumps to that specific line in DialogueResource.lines.
@export var target: int = -2  # -2 == DialogueLine.CONTINUE (literal to avoid a mutual class_name dep in this default): keep the convo going
## Where a FAILED skill/flag check leads (rank 22): a gated choice stays SELECTABLE (FNV-style), so you can
## attempt it and fail. DialogueLine.END (-1, the default) finishes the conversation; an INDEX >= 0 branches to
## a fail line; DialogueLine.CONTINUE (-2) carries on. Ignored by a choice with no gate. (Literal -1, like `target`.)
@export var target_on_fail: int = -1  # -1 == DialogueLine.END

## OPTIONAL skill check: when `required_stat` names a CharacterStats stat (e.g. &"streetwise"), this choice is
## only shown while the player's stat is >= required_value. When shown, the button includes the gate on its
## label ("[Streetwise 6] ..."). Empty = no check, the choice behaves exactly as before.
@export var required_stat: StringName = &""
## The minimum stat value the player needs to pass the check above. Only matters when required_stat is set; higher = a harder gate.
@export var required_value: int = 0

## OPTIONAL story-flag gate: when `required_flag` names a GameState flag, this choice only passes when
## `str(GameState.get_flag(required_flag)) == required_flag_value`; failed picks route to target_on_fail.
## Empty = no gate. Evaluated at runtime in DialogueView.set_choices (not here — this @tool Resource never
## touches the autoload). Lets a conversation branch on quest/world state, not just stats.
@export var required_flag: StringName = &""
## The flag value (stringified) this choice needs to be selectable — a String so it reads in the inspector (a
## bool flag set via GameState.set_flag stringifies to "true", the default). Only matters when required_flag is set.
@export var required_flag_value: String = "true"

## OPTIONAL reputation gate (WR-1): selectable only while the player's standing with required_faction_id is at
## or above required_reputation. The faction dropdown auto-populates from resources/factions/. Empty = no gate.
@export var required_faction_id: String = ""
@export var required_reputation: float = 0.0
## OPTIONAL perk gate (WR-3): selectable only while the player has LEARNED this perk (by Perk.id). Empty = none.
@export var required_perk_id: StringName = &""
## OPTIONAL item gate (WR-3): selectable only while the player CARRIES at least required_item_count of this item
## id — a CHECK (the item is NOT consumed, like flashing a keycard). Dropdown lists item ids on disk. Empty = none.
@export var required_item_id: StringName = &""
@export var required_item_count: int = 1
## OPTIONAL quest-state gate (WR-3): selectable only when quest required_quest_id is in required_quest_state.
## Empty quest id = no gate.
@export var required_quest_id: StringName = &""
@export var required_quest_state: QuestGate = QuestGate.ANY

@export_group("Consequences")
## Set this global story flag when this choice is picked (GameState.set_flag). Empty = none.
@export var set_flag: StringName = &""
## The value written for `set_flag`. Default true.
@export var set_flag_value: bool = true
## Start this quest when picked (GameState.start_quest). Null = none.
@export var start_quest_on_choice: Quest
## Complete this quest by id when picked — the turn-in path (GameState.complete_quest). Empty = none.
@export var complete_quest_id: StringName = &""
## Advance objective `advance_objective_id` of quest `advance_quest_id` by one when picked. BOTH are needed.
@export var advance_quest_id: StringName = &""
@export var advance_objective_id: StringName = &""
## Give the player this item (by Item.id), `give_item_count` of it, when picked. Empty = none.
@export var give_item_id: StringName = &""
@export var give_item_count: int = 1
## Add this to the player's wallet when picked — NEGATIVE for a fee/cost. 0 = none.
@export var give_money: float = 0.0
## WR-3 write: add this much reputation with reward_reputation_faction_id when picked (NEGATIVE to sour them).
## The faction dropdown auto-populates from resources/factions/. 0 / empty = none.
@export var reward_reputation_faction_id: String = ""
@export var reward_reputation: float = 0.0
## WR-3 write: turn the SPEAKER hostile when picked — a rude / threatening line provoke()s the NPC you're talking
## to, so it attacks once the conversation ends. Off by default.
@export var aggro_speaker: bool = false

## Self-populate the `required_stat` dropdown from the CharacterStats attribute names, and `give_item_id` from
## the item ids on disk (SUGGESTION hints, so blanks stay valid and custom names are still typable). Same for the
## faction ids (rep gate + rep reward) and — since the perk registry gained an id scan — `required_perk_id`, which
## until now had suggestions in NEITHER surface (the CYBER SUNDAY dialogue tab still offers none — it leaves that
## one field a bare LineEdit on purpose). The registries are plain folder scanners that touch no autoload, which
## is why const-preloading them from a @tool Resource is safe.
##
## NOT covered — do not read the list above as "every drift-prone id on this Resource is handled". Still bare:
## the quest ids (`required_quest_id` / `complete_quest_id` / `advance_quest_id`), `advance_objective_id`, and the
## flag names (`required_flag` / `set_flag`). The quest ids are the ones that would pay off most, and the drift
## they are exposed to is LIVE on disk — recover_the_package.tres carries id &"recover_package" — so a suggestion
## scan there must LOAD each resources/quests/*.tres and read Quest.id, because the filename lies. Objective ids
## nest inside a Quest rather than sitting in a folder, and flag names have no registry to scan at all.
func _validate_property(property: Dictionary) -> void:
	if property.name == "required_stat":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = CharacterStats.stat_names_csv()
	elif property.name == "give_item_id" or property.name == "required_item_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = ItemIds.ids_csv()
	elif property.name == "required_faction_id" or property.name == "reward_reputation_faction_id":
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Factions.ids_csv()
	elif property.name == "required_perk_id":
		# The gate compares against PerkManager._unlocked (keyed on Perk.id), so suggest the INTERNAL ids
		# Perks.ids() reads off resources/perks/ — not the filenames.
		property.hint = PROPERTY_HINT_ENUM_SUGGESTION
		property.hint_string = Perks.ids_csv()
