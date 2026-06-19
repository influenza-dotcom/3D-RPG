class_name InventorySettings
extends Resource

## Tuning for the PLAYER's Tetris-style spatial backpack (inventory T2). Read via GameSettings.inventory.* when
## the Player turns its bag's spatial cap on (CharacterInventory.enable_grid). A global *Settings.tres group, NOT
## a per-actor @export, because only the player's bag is bounded — NPC / corpse / container / merchant-stock
## inventories leave the grid OFF and stay unlimited (so loot is never silently lost). Pure feel: the grid is a
## SPATIAL affordance (how many cells), deliberately separate from carry_capacity (WEIGHT / encumbrance), so a
## designer tunes the two independently.

@export_group("Player backpack grid")
## Columns (cells wide) of the player's backpack grid. Each STACK occupies item.grid_width × grid_height cells
## (rotatable), so cols × rows is the hard cap on how much physically fits. Weight is a SEPARATE, soft cap.
@export var grid_cols: int = 10:
	set(value):
		grid_cols = maxi(1, value)
## Rows (cells tall) of the player's backpack grid. cols × rows cells total (default 10×8 = 80 — generous; shrink
## for a tighter, more Tetris-y squeeze). Clamped to at least 1.
@export var grid_rows: int = 8:
	set(value):
		grid_rows = maxi(1, value)

@export_group("Loot container grid")
## Columns of a LOOT SOURCE's grid (corpse / container / pickpocketed NPC) — enabled lazily when the loot screen
## opens it so both sides render as grids (T4). Keep it GENEROUS so a dead NPC's whole loadout always auto-places
## (an unplaced stack wouldn't render); cols × rows must exceed any actor's stack count. Clamped to at least 1.
@export var container_grid_cols: int = 10:
	set(value):
		container_grid_cols = maxi(1, value)
## Rows of a loot source's grid (default 10×8 = 80 cells — plenty for any NPC's loot). Clamped to at least 1.
@export var container_grid_rows: int = 8:
	set(value):
		container_grid_rows = maxi(1, value)
