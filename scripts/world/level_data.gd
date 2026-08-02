class_name LevelData
extends Resource

## @system Run And Level Flow
## @seam resource_path persists as GameState.current_level_path for Continue; a non-null `scene` gates boot-viability, else GameRoot uses the exported level.
## @risk A LevelData with a blank/unstable resource_path persists no resolvable path, so Continue silently boots the export, losing the saved level (GameRoot.load_level's set_current_level, read back by resolve_boot_level).
## @risk A saved LevelData whose `scene` is null is rejected by resolve_boot_level, which silently boots the export instead of the saved level (GameRoot.saved_level_is_bootable's scene != null check).
## @test res://tests/test_level_data.gd
## @test res://tests/test_level_flow.gd
## A LEVEL definition — the data-driven alternative to game.tscn hardcoding a single Level child. Bundles the
## level scene with its presentation (display name + optional music / ambience overrides), so shipping a
## second level is one .tres assignment on GameRoot instead of duplicating a 1500-line game.tscn. Mirrors the
## WeaponData / NpcData / LootTable pattern: author content as resources, load it through a small seam.

@export var scene: PackedScene = null      ## the level geometry/content, instantiated as the "Level" child
@export var display_name: String = ""      ## for a level-select / loading screen
@export var music: AudioStream = null      ## optional: override the Player's Music stream for this level
@export var ambience: AudioStream = null   ## optional: override the Player's Ambience stream for this level
