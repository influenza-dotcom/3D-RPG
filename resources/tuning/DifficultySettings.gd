class_name DifficultySettings
extends Resource

## Global DIFFICULTY tuning (ML-3): the LIVE multipliers the combat / spawn / reward seams read
## (GameSettings.difficulty.<field>), plus the Easy / Hard PRESETS that Settings.set_difficulty() copies into the
## live fields when the player picks a difficulty. NORMAL = every live mult at 1.0 (no change — today's balance),
## so the whole system is inert until a non-Normal level is chosen. Read LIVE every frame, so a mid-run change
## takes effect immediately. The presets are designer-tunable here; apply_level() is the only writer of the live set.

enum Level { EASY, NORMAL, HARD }

@export_group("Current (written by Settings.set_difficulty)")
## Damage the PLAYER TAKES, scaled (>1 = harder). The mult is gated on `is_in_group(&"Player")` in take_damage (ML-4).
@export var damage_taken_mult: float = 1.0
## Damage the PLAYER DEALS to enemies, scaled (>1 = easier). Applied on the player's shots (ML-4).
@export var damage_dealt_mult: float = 1.0
## How many enemies an EncounterSpawner spawns, scaled (>1 = denser). Rounded at the spawn count (ML-4).
@export var enemy_count_mult: float = 1.0
## Loot quantity / drop scaling (>1 = more). Applied in the loot reward hook (ML-4).
@export var loot_mult: float = 1.0
## Money rewards scaled (>1 = richer). Applied in the money reward hook (ML-4).
@export var money_mult: float = 1.0
## XP gain scaled (>1 = faster leveling). Applied at the Player.add_xp inflow (ML-5).
@export var xp_gain_mult: float = 1.0

@export_group("Easy preset")
@export var easy_damage_taken_mult: float = 0.5
@export var easy_damage_dealt_mult: float = 1.5
@export var easy_enemy_count_mult: float = 0.7
@export var easy_loot_mult: float = 1.25
@export var easy_money_mult: float = 1.25
@export var easy_xp_gain_mult: float = 1.0

@export_group("Hard preset")
@export var hard_damage_taken_mult: float = 1.75
@export var hard_damage_dealt_mult: float = 0.85
@export var hard_enemy_count_mult: float = 1.35
@export var hard_loot_mult: float = 1.0
@export var hard_money_mult: float = 1.0
@export var hard_xp_gain_mult: float = 1.25

## Copy the chosen level's preset into the LIVE fields (NORMAL resets every live mult to 1.0). The single writer
## of the current set — Settings.set_difficulty() calls this. Out-of-range levels fall to NORMAL.
func apply_level(level: int) -> void:
	match level:
		Level.EASY:
			damage_taken_mult = easy_damage_taken_mult
			damage_dealt_mult = easy_damage_dealt_mult
			enemy_count_mult = easy_enemy_count_mult
			loot_mult = easy_loot_mult
			money_mult = easy_money_mult
			xp_gain_mult = easy_xp_gain_mult
		Level.HARD:
			damage_taken_mult = hard_damage_taken_mult
			damage_dealt_mult = hard_damage_dealt_mult
			enemy_count_mult = hard_enemy_count_mult
			loot_mult = hard_loot_mult
			money_mult = hard_money_mult
			xp_gain_mult = hard_xp_gain_mult
		_:  # NORMAL — the neutral baseline (today's balance)
			damage_taken_mult = 1.0
			damage_dealt_mult = 1.0
			enemy_count_mult = 1.0
			loot_mult = 1.0
			money_mult = 1.0
			xp_gain_mult = 1.0
