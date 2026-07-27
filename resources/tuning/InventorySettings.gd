class_name InventorySettings
extends Resource

## Tuning for the Tetris-style spatial backpack (inventory T2). Read via GameSettings.inventory.* when an actor
## turns its bag's spatial cap on (CharacterInventory.enable_grid). A global *Settings.tres group, NOT a per-actor
## @export, because the SAME grid size is shared: the player (Player._ready) AND every NPC (NPC._ready) are
## bounded to grid_cols×grid_rows, so an NPC carries no more than the player and the bag it drops (its corpse copy)
## renders at that size. Only a persistent CONTAINER (a hand-placed crate / chest) gets the separate, roomier
## container_grid below — and a MERCHANT's stock now shares it, since ShopScreen grids the shelf on first open
## exactly as the loot screen grids a crate. A fresh corpse-copy bag stays OFF until the loot screen grids it. Pure
## feel: the grid is a SPATIAL affordance (how many cells), deliberately separate from carry_capacity (WEIGHT /
## encumbrance), so a designer tunes the two independently.

@export_group("Character backpack grid")
## Columns (cells wide) of the player's AND every NPC's backpack grid. Each STACK occupies item.grid_width ×
## grid_height cells (rotatable), so cols × rows is the hard cap on how much physically fits. Weight is a
## SEPARATE, soft cap. Keep this at least big enough for an NPC's authored loadout (weapon + ammo + carried
## items) or that overflow is left unplaced on the corpse (kept, but it won't render in the loot grid).
@export var grid_cols: int = 10:
	set(value):
		grid_cols = maxi(1, value)
## Rows (cells tall) of the player's / every NPC's backpack grid. cols × rows cells total (default 10×8 = 80 —
## generous; shrink for a tighter, more Tetris-y squeeze — but see grid_cols on NPC loadout overflow). Clamped to at least 1.
@export var grid_rows: int = 8:
	set(value):
		grid_rows = maxi(1, value)

@export_group("Loot container grid")
## Columns of a persistent CONTAINER's grid (a hand-placed crate / chest) — enabled lazily when the loot screen
## opens it (T4). A corpse / dropped bag / pickpocketed NPC does NOT use this — those render at the character grid
## above (an NPC's stash is capped to the player's size). A crate is a fixed cache that can hold more, so keep this
## GENEROUS so its whole stock always auto-places (an unplaced stack wouldn't render). Clamped to at least 1.
@export var container_grid_cols: int = 10:
	set(value):
		container_grid_cols = maxi(1, value)
## Rows of a persistent container's grid (default 10×8 = 80 cells — plenty for a crate's stock). Clamped to at least 1.
@export var container_grid_rows: int = 8:
	set(value):
		container_grid_rows = maxi(1, value)
