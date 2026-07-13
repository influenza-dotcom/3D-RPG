class_name PickpocketSettings
extends Resource

## Global tuning for PICKPOCKETING a live NPC (the LootScreen pickpocket mode reached by crouch-interacting an
## off-guard NPC). These are the encounter/balance knobs; the player's PICKPOCKET stat bends them per lift via the
## pure formulas on CharacterStats (pickpocket_catch_chance / pickpocket_value_allowance). Edit in the inspector on
## GameSettings.pickpocket (resources/tuning/PickpocketSettings.tres) — never hardcode these at the seam.
##
## THE RULES, at the LootScreen._take seam:
##   * VALUE GATE — a loose item is liftable only if its value <= pickpocket_value_allowance(base, per_point). A
##     master thief can eventually pocket anything; a novice only worthless scraps.
##   * EQUIPPED GATE — the weapon they're actively HOLDING is liftable only once pickpocket >= equipped_threshold
##     (below that it stays padlocked, as before — you can't pluck a drawn gun from an amateur's reach).
##   * CATCH ROLL — every successful lift (item OR pocketed cash) rolls pickpocket_catch_chance(base, per_point).
##     On a caught roll the NPC is provoked (turns hostile + faction rep drops) and the screen slams shut.

## Catch probability per lifted item at pickpocket 0 (0..1). Higher = riskier world; the stat subtracts from this.
@export_range(0.0, 1.0) var base_catch_chance: float = 0.35
## Flat catch-chance reduction per pickpocket point (linear). At 0.03, ~12 points reaches a flawless 0% at base 0.35.
@export var catch_chance_per_point: float = 0.03
## Max item VALUE (zorkmids) liftable unnoticed at pickpocket 0. A cheap-scraps ceiling for an unskilled thief.
@export var base_value_allowance: float = 10.0
## Extra liftable-value ceiling per pickpocket point (linear, unbounded up). At 5.0, pickpocket 10 lifts value <= 60.
@export var value_allowance_per_point: float = 5.0
## PICKPOCKET needed to lift the weapon the NPC is actively HOLDING. Below it the drawn weapon stays padlocked
## (steal their ammo to disarm instead); at/above it the weapon becomes liftable (and still rolls the catch check).
@export var equipped_pickpocket_threshold: int = 8
