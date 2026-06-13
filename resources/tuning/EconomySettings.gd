class_name EconomySettings
extends Resource

## The economy's designer knobs — every bounty, trick-shot reward, and seed value on ONE inspector page
## (edit resources/tuning/EconomySettings.tres, no code). Read everywhere as GameSettings.economy.<field>,
## like the other tuning groups. Zorkmids are FRACTIONAL (0.5 = half a zorkmid), so every knob here is too.

@export_group("Kill bounties")
## Paid to whoever downs a character (player AND NPCs — winnings sit in an NPC's lootable wallet).
@export var kill_bounty: float = 1.0
## ...when the KILLING blow was a headshot.
@export var headshot_kill_bounty: float = 2.0
## ...when EVERY point of damage the victim took was a headshot (the applause kill).
@export var all_headshots_kill_bounty: float = 4.0

@export_group("Trick shots")
## EXTRA on a collateral kill — carried overkill piercing out of one kill into another victim.
@export var collateral_bounty: float = 2.0
## ...when the collateral blow itself was a headshot.
@export var collateral_headshot_bounty: float = 4.0
## Swatting a fresh gore gib out of the air (the confetti pop).
@export var confetti_bounty: float = 1.0

@export_group("Kill credit")
## A hit older than this (ms) no longer earns its shooter the kill bounty when the victim dies.
@export var kill_credit_window_ms: int = 5000

@export_group("Reputation")
## Disposition boost toward whoever killed this NPC's attacker (the rescue thank-you).
@export var save_rep_reward: float = 15.0

@export_group("Seeds")
## The player's fresh-game wallet (a SwapWeapons Loadout overrides it; a loaded save wins over both).
@export var player_starting_money: float = 100.0
