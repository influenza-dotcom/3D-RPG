class_name NpcBarkSettings
extends Resource

## Global NPC BARK / voice-cadence tuning — the timings + ranges that pace an NPC's spoken barks and its detection
## stings, on one inspector page (resources/tuning/NpcBarkSettings.tres), read as GameSettings.npc_bark.<field>.
## The matching npc.gd consts (BARK_DISTANCE / BARK_COOLDOWN_MS / GREET_COOLDOWN_MS / DEATH_WITNESS_RADIUS /
## HURT_BARK_HP_FRAC / ALERT_COOLDOWN_MS / AIM_COOLDOWN_MS / AIM_SFX_DELAY) REMAIN as the terminal fallback + the
## test anchors; every field here DEFAULTS to that const's value, so behaviour is byte-identical until a designer
## tunes it. (Bark LINES are content — resources/barks/*.tres via BarkSet — not here; this page is the cadence dials.)

@export_group("Bark cadence")
## Only bark when within this (m) of the player — the listener (2D audio + world text). Mirrors NPC.BARK_DISTANCE.
@export var bark_distance: float = 14.0
## Per-NPC: each NPC barks at most this often (ms). Mirrors NPC.BARK_COOLDOWN_MS.
@export var bark_cooldown_ms: int = 6000
## Per-NPC hostile cadence (ms): enemies can bark more often in combat/search without making friendly chatter spam.
@export var enemy_bark_cooldown_ms: int = 3000
## Separate cooldown (ms) for the FNV hover greeting so glancing to-and-fro doesn't spam it. Mirrors NPC.GREET_COOLDOWN_MS.
@export var greet_cooldown_ms: int = 9000
## Grace (s) an NPC must be actively searching before it FIRST mutters the "still around here somewhere..." hunt
## line (SEARCH_LINES / bark_searching). Measured off Perception.search_elapsed(), which resets to 0 on EVERY entry
## into INVESTIGATING — so a target that flickers out of sight for a beat and back never accumulates enough to bark.
## Without this the mutter fired on the very first INVESTIGATING frame, so losing line-of-sight for a second read as
## an instant "where are you?". 0 = fire immediately (the pre-delay behaviour). Paces only the FIRST line; the bark
## cooldown paces the rest. The give-up lines (combat_end / lost_interest) are unaffected — they fire on search expiry.
## INTERACTION: an NPC whose forget_time (npc.gd's @export, default 4.0 — the designer-facing knob, mirrored onto
## the code-built Perception in _build_perception) is SHORTER than this gives up a STATIONARY search before
## the grace elapses, so it won't mutter on a point-blank loss — only during a longer chase, where walking to the
## last-known spot keeps the search alive (travel refreshes the give-up clock). Intended: a short-attention NPC (e.g.
## NPC.tscn / a civilian at forget_time 1.0) searches briefly and quietly. Keep this < a hostile's forget_time to hear it.
@export var search_bark_delay: float = 2.5

@export_group("Death witness")
## How far (m) a player-caused death is noticed by other NPCs ("Murderer!" / "Good riddance."). Mirrors NPC.DEATH_WITNESS_RADIUS.
@export var death_witness_radius: float = 18.0
## A following ally cries out once when its HP drops to/below this fraction of max. Mirrors NPC.HURT_BARK_HP_FRAC.
@export_range(0.0, 1.0) var hurt_bark_hp_frac: float = 0.35

@export_group("Detection stings")
## Shared throttle (ms) so a swarm spotting you at once plays ONE MGS "!" sting. Mirrors NPC.ALERT_COOLDOWN_MS.
@export var alert_cooldown_ms: int = 3000
## Sniper charge-sting de-dup window (ms) — dedups near-simultaneous lock + first-shot triggers. Mirrors NPC.AIM_COOLDOWN_MS.
@export var aim_cooldown_ms: int = 120
## A short beat (s) between a shot and its charge-up sting so the two don't blur together. Mirrors NPC.AIM_SFX_DELAY.
@export var aim_sfx_delay: float = 0.1
