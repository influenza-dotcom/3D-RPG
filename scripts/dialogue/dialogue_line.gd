class_name DialogueLine
extends Resource

## One line in a conversation: the spoken text, plus optional branching choices. The speaker's NAME
## is not stored here — DialogueManager shows the talking character's display_name (NPC / Talkable /
## DialogueNPC), so there is no per-line speaker field to fill in.
## A line with an empty `choices` array plays linearly (DialogueManager advances to the next line
## on input). A line WITH choices is a branch point: the manager shows one Button per choice and
## jumps to the chosen DialogueChoice.target (an index into DialogueResource.lines, or END to finish).

const END: int = -1  # choice target sentinel: a choice whose target == END finishes the conversation
const CONTINUE: int = -2  # choice target sentinel (the DEFAULT): picking the choice carries on to the NEXT line

## The spoken text shown for this line (multiline). The speaker's name is supplied by the talking character, not here.
@export_multiline var text: String = ""
## Tick this on the line where the speaker tells you their name (e.g. "The name's Marcus."). When the line plays,
## DialogueManager calls GameState.reveal_name on the speaker, so from that moment on the NPC shows their REAL name
## instead of "Stranger" — in this box, on the look-at readout, on their corpse, everywhere (and it sticks across a
## save). Until some line flips this, the NPC stays a Stranger. Only real character speakers are masked; an
## inanimate DialogueNPC (terminal / sign) is never a Stranger, so this is a no-op there.
@export var reveals_name: bool = false
## Branch options offered at this line. Empty = the line plays linearly and advances to the next on input.
@export var choices: Array[DialogueChoice] = []

## True when this line presents choices (a branch point) rather than continuing linearly.
## Pure (no tree / side effects) so DialogueManager and the tests can share it.
func has_choices() -> bool:
	return not choices.is_empty()
