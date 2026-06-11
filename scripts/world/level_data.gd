class_name LevelData
extends Resource

## A LEVEL definition — the data-driven alternative to game.tscn hardcoding a single Level child. Bundles the
## level scene with its presentation (display name + optional music / ambience overrides), so shipping a
## second level is one .tres assignment on GameRoot instead of duplicating a 1500-line game.tscn. Mirrors the
## WeaponData / NpcData / LootTable pattern: author content as resources, load it through a small seam.

@export var scene: PackedScene = null      ## the level geometry/content, instantiated as the "Level" child
@export var display_name: String = ""      ## for a level-select / loading screen
@export var music: AudioStream = null      ## optional: override the Player's Music stream for this level
@export var ambience: AudioStream = null   ## optional: override the Player's Ambience stream for this level
