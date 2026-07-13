extends GutTest

## P0-1: a fresh game must start with ZERO abilities — the microchip-install economy (ChipInstaller ->
## GameState.unlocks) requires it. Player.tscn correctly sets starting_unlocks = []; scenes/game.tscn is the scene
## StartMenu boots for New Game, so ITS Player override is the surface the contract hinges on. This pins that the
## override is empty and that any id it does carry is a real AbilityRegistry id (a stale/bogus id like the removed
## "grapple_hook" would otherwise pre-grant a broken ability). Instantiated WITHOUT add_child so no _ready runs (the
## test_level_door_prefab idiom); a reimport-empty PackedScene degrades to a skip, not a crash.

const GAME_SCENE := "res://scenes/game.tscn"
const ABILITY_REGISTRY := "res://scripts/components/abilities/ability_registry.gd"


func test_new_game_starts_with_zero_abilities() -> void:
	var packed := load(GAME_SCENE) as PackedScene
	assert_true(packed != null, "game.tscn should load as a PackedScene")
	if packed == null:
		return
	var g := packed.instantiate()
	if g == null:  # a transient reimport can yield an empty PackedScene (editor open) — skip, don't fail
		return
	var p := g.get_node_or_null("Player")
	assert_true(p != null, "game.tscn has a Player node")
	if p != null:
		assert_true(p.starting_unlocks.is_empty(),
			"game.tscn must not pre-grant abilities — the chip economy requires zero starting unlocks")
		var valid: PackedStringArray = load(ABILITY_REGISTRY).ids()
		for id in p.starting_unlocks:
			assert_true(valid.has(id), "starting_unlocks id '%s' is not a real AbilityRegistry id" % id)
	g.free()
