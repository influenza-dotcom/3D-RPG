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


## The implant-purchase seam: a CREATED character's pre-boot grants (the whole implant cart bought ON CREDIT
## after character creation) live in GameState.unlocks while GameState.loaded is still FALSE — StartMenu
## stamps them AND debits the bill from GameState.money (the balance may go negative), and only the first
## autosave's capture() makes both disk-real. Player._ready must therefore, on every loaded=false boot of a
## real run: apply a NON-EMPTY GameState.unlocks (or the chips are silently erased at that first capture())
## AND read the wallet from GameState.money via the profile_active branch (or a menu-and-back Continue /
## no-save death reload would refund the bill while re-granting the goods). The behaviour can't run under
## GUT (Player._ready is forbidden in unit tests — it instantiates weapons/nav/audio), so pin the SOURCE
## contract instead (the test_game_save profile_active grep idiom).
func test_fresh_boot_applies_a_seeded_unlock_set() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_true(src.contains("not GameState.unlocks.is_empty()"),
		"player.gd keeps the fresh-boot escape hatch that applies a seeded GameState.unlocks (the purchased implant cart)")
	# ...and the escape hatch must span BOTH implant lists. `unlocks` is only the ACTIVE projection, so a run
	# whose implants are ALL switched off (Implants tab) reaches this branch with an EMPTY unlocks and a
	# populated disabled_unlocks — and this boot mode is reached mid-run (Options -> Main Menu -> Continue
	# never loads from disk, so `loaded` stays false). Gating on unlocks alone fell through to
	# _seed_unlocks() and permanently UNINSTALLED those implants at the next capture().
	assert_true(src.contains("not GameState.disabled_unlocks.is_empty()"),
		"player.gd's fresh-boot escape hatch also fires for a profile whose implants are all switched OFF (else they're uninstalled for good)")
	assert_true(src.contains("set_disabled_unlocks(GameState.disabled_unlocks)"),
		"...and restores them switched-off rather than dropping them")
	assert_true(src.contains("elif GameState.profile_active:"),
		"player.gd keeps the created-run wallet branch (GameState.money — the implant bill and the goods must never separate)")
