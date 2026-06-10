class_name LootEntry
extends Resource

## One row of a LootTable: an item with an independent drop CHANCE and a count RANGE. Each entry rolls on
## its own, so a table can mix "always 1-3 ammo" with a "10% keycard".

@export var item: Item                              ## the item to drop (weapon-item, ammo, or any Item)
@export_range(0.0, 1.0) var chance: float = 1.0     ## probability (0..1) this entry drops at all
@export var min_count: int = 1                      ## fewest dropped when it hits
@export var max_count: int = 1                      ## most dropped when it hits
