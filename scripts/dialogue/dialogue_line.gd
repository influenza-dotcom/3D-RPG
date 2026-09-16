class_name DialogueLine
extends Resource

## One line in a conversation: the spoken text, plus optional branching choices. The speaker's NAME
## is not stored here — DialogueManager shows the talking character's display_name (NPC / Talkable /
## DialogueNPC), so there is no per-line speaker field to fill in.
## A line with an empty `choices` array plays linearly (DialogueManager advances to the next line
## on input). A line WITH choices is a branch point: the manager shows one Button per choice and
## jumps to the chosen DialogueChoice's destination — by `target_id` (this line's `id`, or a sentinel word)
## when that is set, else by the legacy int `target` (an index into DialogueResource.lines, or END/CONTINUE).
## The resolver that turns either form into a line index is DialogueResource.resolve_target.

const END: int = -1  # legacy INT choice-target sentinel: a choice whose target == END finishes the conversation
const CONTINUE: int = -2  # legacy INT sentinel (the int DEFAULT): picking the choice carries on to the NEXT line
## The ID-form sentinels a DialogueChoice.target_id / target_on_fail_id may carry instead of a line id. Words, not
## numbers, so a designer can type them in the inspector; a line must never be GIVEN one of these as its id (the
## resolver checks the sentinels first, so such a line would be unaddressable — the audit reports it as an ERROR).
const ID_END: StringName = &"END"
const ID_CONTINUE: StringName = &"CONTINUE"

## This line's stable address. A DialogueChoice.target_id names a line by THIS, so inserting, deleting or reordering
## lines never re-points a choice (the failure the int `target` had at scale). Blank = LEGACY: the line can only be
## reached by its array index through the int fields, exactly as every conversation authored before ids existed.
## The Dialogue Edit tab assigns a unique id to every new line and can migrate an old conversation in one click;
## in the raw inspector you type one. Must be unique within the conversation and must not be END / CONTINUE.
@export var id: StringName = &""
## The spoken text shown for this line (multiline). The speaker's name is supplied by the talking character, not here.
@export_multiline var text: String = ""
## LEGACY / redundant for a character speaker: simply OPENING a conversation now ends "Stranger" status — the act
## of talking to someone IS the introduction (DialogueManager.start calls GameState.reveal_name on any real
## character speaker), so a character is already named by the time their first line paints. Ticking this on a line
## where the speaker states their name (e.g. "The name's Marcus.") still calls reveal_name, it just has nothing
## left to unlock. Kept so authored .tres files keep loading and a future non-auto-reveal flow has a per-line hook.
## Only real character speakers are masked; an inanimate DialogueNPC (terminal / sign) is never a Stranger.
@export var reveals_name: bool = false
## Branch options offered at this line. Empty = the line plays linearly and advances to the next on input.
@export var choices: Array[DialogueChoice] = []

## True when this line presents choices (a branch point) rather than continuing linearly.
## Pure (no tree / side effects) so DialogueManager and the tests can share it.
func has_choices() -> bool:
	return not choices.is_empty()
