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

@export_group("Death")
## Fraction of the PLAYER's wallet handed to whoever kills them (0 = keep it all / feature off, 1 = lose it
## all). The zorkmids ride into the killer's wallet and drop as loot when you hunt it down — recover-your-
## losses, Dark-Souls style. Only applies when death revives you IN PLACE (a RELOAD_* death mode resets the
## world, so the transfer is skipped there). Read as GameSettings.economy.death_purse_loss_fraction.
@export_range(0.0, 1.0, 0.05) var death_purse_loss_fraction: float = 1.0

@export_group("Reputation")
## Disposition boost toward whoever killed this NPC's attacker (the rescue thank-you).
@export var save_rep_reward: float = 15.0

@export_group("Seeds")
## The player's fresh-game wallet (a SwapWeapons Loadout overrides it; a loaded save wins over both). 0 by default -> the player starts broke.
@export var player_starting_money: float = 0.0

@export_group("Restock")
## Default seconds between a Restocker's refills when its own `interval` is left at 0 — how fast vendors /
## containers replenish to their authored baseline. Read as GameSettings.economy.restock_interval.
@export var restock_interval: float = 60.0
