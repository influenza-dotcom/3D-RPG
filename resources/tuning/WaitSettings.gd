class_name WaitSettings
extends Resource

## Global tuning for WAITING — the Fallout-style "press T, pick some hours, they pass" screen
## (scripts/ui/wait_screen.gd). Edit in the inspector on GameSettings.wait
## (resources/tuning/WaitSettings.tres); never hardcode these at the seam.
##
## WHAT WAITING IS, AND WHAT IT DELIBERATELY IS NOT:
##   * It is TIME PASSING. The screen calls WorldClock.advance_hours, which walks the span and emits every
##     day/night boundary it crosses — so rent falls due, bank interest posts, NPC schedules move and the sky
##     rolls over exactly as if the hours had been lived. Waiting through a dawn costs what living through it
##     costs; that is the whole reason it routes through advance_by rather than a silent seek.
##   * It is NOT a rest. Resting at a Bonfire is the INSTANT full heal AND the respawn checkpoint, and it stays
##     the only thing that does either ON DEMAND. Waiting pays out only the slow trickle below — enough that a
##     long wait helps, never enough to replace finding a fire. (New Vegas draws the same line: you heal by
##     SLEEPING in a bed, not by waiting.) Set hp_per_hour to 0 for the strict New Vegas rule.
##     ⭐ SINCE 2026-08-18 there is ALSO a passive ambient regen while out of combat
##     (GameSettings.player_feedback.health_regen_*), which knits you back up slowly wherever you stand — so the
##     Bonfire is no longer the only thing that heals, only the only thing that heals INSTANTLY. That drip is
##     capped by health_regen_cap_frac; this trickle is what still makes SKIPPING the hours worth doing.
##   * It is NOT an escape hatch. Waiting is refused while hostiles are aware of you, so it can never be used
##     to blink out of a fight — see hostile_awareness_blocks.

@export_group("Span")
## Longest single wait the screen offers, in in-game hours. 24 = "up to a full day", the Fallout default.
## The screen clamps its selector to this, so raising it widens the choice with no code change.
@export var max_hours: int = 24
## Shortest wait, and the step the selector moves in. 1 = whole hours.
@export var min_hours: int = 1
## Hours the selector starts on when the screen opens.
@export var default_hours: int = 1

@export_group("Recovery")
## HP restored per in-game hour waited. ⭐DELIBERATELY A TRICKLE, not a heal: a Bonfire rest is the full
## restore and the checkpoint, and a wait that matched it would make fires pointless — you could top up
## anywhere by waiting an hour. At 2/hour a full 24-hour wait returns 48 HP, which is real help on a long
## walk home and still nothing like resting. 0 = the strict New Vegas rule (waiting never heals).
@export var hp_per_hour: float = 2.0
## Cap the trickle at this fraction of max HP (1.0 = a long enough wait can reach full). Lower it to make
## waiting top you up only to a wounded-but-walking state, so a real heal still has to be earned.
@export var hp_cap_fraction: float = 1.0
## Whether waiting also mends CRIPPLED limbs. OFF by design — limb damage is the injury the Healer and the
## Bonfire exist to clear, and letting a nap undo it removes the one lasting consequence combat leaves.
@export var heals_limbs: bool = false

@export_group("Refusal")
## Refuse to wait while a hostile NPC is aware of the player (hunting, searching, or shooting). The Fallout
## rule, and the thing that stops waiting being a free combat exit. Turning it off makes waiting always legal.
@export var hostile_awareness_blocks: bool = true
## Refuse to wait while airborne. Waiting mid-fall would land the player after the world moved on under them.
@export var airborne_blocks: bool = true
