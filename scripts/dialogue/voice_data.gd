class_name VoiceData
extends Resource

## How a character's lines are read by the OS text-to-speech. Assign one to a Talkable /
## DialogueNPC `voice`. Windows ships just a male + a female voice, so the voice itself is a
## simple toggle; pitch/rate fine-tune within that to make characters sound distinct.

## Use the female system voice (e.g. Microsoft Zira) instead of the male one (e.g. David).
@export var female: bool = false
## Pitch of the voice — below 1.0 is deeper, above 1.0 is higher.
@export_range(0.0, 2.0) var pitch: float = 1.0
## Speaking rate — 1.0 is normal, higher is faster, lower is slower.
@export_range(0.1, 10.0) var rate: float = 1.0
