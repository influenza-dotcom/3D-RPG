class_name PickpocketSettings
extends Resource

## Global tuning for PICKPOCKETING a live NPC (the LootScreen pickpocket mode reached by crouch-interacting an
## off-guard NPC). These are the encounter/balance knobs; the player's PICKPOCKET stat bends them per lift via the
## pure formulas on CharacterStats (pickpocket_catch_chance / pickpocket_value_allowance). Edit in the inspector on
## GameSettings.pickpocket (resources/tuning/PickpocketSettings.tres) — never hardcode these at the seam.
##
## THE RULES, at the LootScreen._take seam:
##   * VALUE RISK (not a gate) — anything loose is ATTEMPTABLE at any skill. Value up to the skill-scaled
##     allowance (pickpocket_value_allowance(base, per_point)) lifts at the plain catch chance; every zorkmid
##     ABOVE it adds over_value_risk to the catch chance. So a microchip reads as hopeless 0% odds for a novice
##     and a real gamble for an invested thief — larceny both widens the free band and flattens the overage.
##     (This replaced a hard "too valuable" refusal: a wall reads as a bug — "why can't I even TRY?" — where
##     terrible odds read as a skill problem the player can fix. Same knobs, one new slope.)
##   * EQUIPPED GATE — the weapon they're actively HOLDING is liftable only once pickpocket >= equipped_threshold
##     (below that it stays padlocked, as before — you can't pluck a drawn gun from an amateur's reach). The one
##     remaining hard refusal: physically out of reach, not merely risky.
##   * CATCH ROLL — every lift (item OR pocketed cash) rolls LootScreen._pickpocket_catch_for — the skill-bent
##     base chance plus the item's value-overage risk, the SAME number the hover shows. On a caught roll the NPC
##     is provoked (turns hostile + faction rep drops), SPINS to face the thief + engages, and rallies nearby
##     enemies within caught_witness_radius to turn and look; the screen slams shut. A caught mark is ALSO locked
##     out of pickpocketing FOR GOOD (NPC.pickpocket_allowed) — no retry on someone you botched.
## The hover tooltip previews the per-item odds live (LootScreen._pickpocket_success_percent = 1 - catch-for-item,
## or the padlock reason for a drawn weapon), so the player sees the risk before committing to a lift.

## Catch probability per lifted item at pickpocket 0 (0..1). Higher = riskier world; the stat subtracts from this.
@export_range(0.0, 1.0) var base_catch_chance: float = 0.35
## Flat catch-chance reduction per pickpocket point (linear). At 0.03, ~12 points reaches a flawless 0% at base 0.35.
@export var catch_chance_per_point: float = 0.03
## Max item VALUE (zorkmids) liftable unnoticed at pickpocket 0. A cheap-scraps ceiling for an unskilled thief.
@export var base_value_allowance: float = 10.0
## Extra liftable-value ceiling per pickpocket point (linear, unbounded up). At 5.0, pickpocket 10 lifts value <= 60.
@export var value_allowance_per_point: float = 5.0
## Extra CATCH chance per zorkmid of item value ABOVE the allowance (the value-RISK slope that replaced the hard
## value gate). At 0.004 (0.4%/zm) a 250-zm chip against larceny 10's 60-zm allowance adds +76% catch — near-
## hopeless; at larceny 30 (allowance 160) it adds +36% — a real gamble for a master thief. 0 = value carries no
## risk at all (any item lifts at the plain catch chance); the catch always clamps at 100%, where the tooltip
## honestly reads 0% and an attempt is a guaranteed bust.
@export var over_value_risk: float = 0.004
## PICKPOCKET needed to lift the weapon the NPC is actively HOLDING. Below it the drawn weapon stays padlocked
## (steal their ammo to disarm instead); at/above it the weapon becomes liftable (and still rolls the catch check).
@export var equipped_pickpocket_threshold: int = 8
## When a pickpocket is BLOWN (the caught roll fires), every OTHER living enemy (a nearby NPC already hostile to the
## player) within this radius (m) of the victim TURNS TO LOOK — it investigates the thief's spot with the "!" sting.
## The victim itself ALWAYS reacts (turns hostile + spins to face you); this only sets how far the commotion spreads
## to bystanding enemies. 0 = only the victim reacts. Read at LootScreen._on_pickpocket_caught -> react_to_caught_theft.
@export var caught_witness_radius: float = 12.0
