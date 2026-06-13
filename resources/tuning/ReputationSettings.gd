class_name ReputationSettings
extends Resource

## Faction-standing balance knobs on one inspector page (resources/tuning/ReputationSettings.tres), read as
## GameSettings.reputation.<field>. The penalties + thresholds that drive HOSTILE / NEUTRAL / FRIENDLY were
## consts on the Reputation autoload; a designer now tunes how quickly the world turns on you without code.

@export_group("Thresholds")
## Standing at or below this -> the faction treats the player as HOSTILE.
@export var hostile_threshold: float = -25.0
## Standing at or above this -> the faction treats the player as FRIENDLY.
@export var friendly_threshold: float = 25.0

@export_group("Penalties")
## Standing lost when the player PROVOKES a faction member (a warning-shot / shove aggro).
@export var provoke_penalty: float = 30.0
## Standing lost when the player KILLS a faction member — even a hostile one (their people still mourn).
@export var kill_penalty: float = 12.0

@export_group("Clamp")
## Standing is clamped to [rep_min, rep_max] so it can't run away to +/- infinity. Keep well past the
## thresholds so repeated kills/rewards don't pin disposition too early.
@export var rep_min: float = -100.0
@export var rep_max: float = 100.0
