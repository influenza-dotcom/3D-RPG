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
## stamps them AND charges the bill to GameState.account, the ONE signed Ledger balance (+ savings / - debt),
## which is what a created run starts NEGATIVE on. The wallet (GameState.money) is CASH ONLY and stays >= 0;
## it keeps the player_starting_money seed and whatever the live run has since earned or spent. Only the first
## autosave's capture() makes any of it disk-real. Player._ready must therefore, on every loaded=false boot of
## a real run: apply a NON-EMPTY GameState.unlocks (or the chips are silently erased at that first capture())
## AND read the wallet from GameState.money via the profile_active branch rather than re-seeding it (or a
## menu-and-back Continue / no-save death reload would hand back money the run had already spent). The debt
## itself needs no branch there at all — nothing in _ready touches `account`, which is precisely why the goods
## and the bill that bought them cannot separate. The behaviour can't run under GUT (Player._ready is forbidden
## in unit tests — it instantiates weapons/nav/audio), so pin the SOURCE contract instead (the test_game_save
## profile_active grep idiom).
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
		"player.gd keeps the created-run CASH branch (it reads GameState.money instead of re-seeding it, so an in-memory run never gets refunded what it spent)")


## ⭐CONTINUE ON AN IN-MEMORY RUN. The same loaded=false boot mode as above, reached the other way: a New-Game
## session never runs a disk load, so `loaded` stays false for its whole life, and Options -> Main Menu drops the
## player back on the start menu with that live run still sitting in the GameState autoload. Pressing Continue
## booted it UN-PROMOTED, and Player._ready routes the backpack on `GameState.loaded and GameState.has_inventory`
## — so the fresh Player re-seeded the authored starting loadout OVER the live bag and skipped perks / xp / level
## / reputation / status effects, silently discarding the run before the next autosave wrote the wreckage to disk.
## StartMenu._on_continue promotes `loaded` for a profile_active run, in the ONE caller that knows it is RESUMING.
##
## The contract is made inside Player._ready, which a unit test may never run (CLAUDE.md), so this is the sanctioned
## source pin (test_payment_rail_selector's idiom): assert the promotion exists, sits behind the profile_active
## gate, and happens BEFORE the boot — a promotion after _start_game() would be read too late to matter.
func test_continue_promotes_an_in_memory_run_onto_the_saved_path() -> void:
	var menu := FileAccess.get_file_as_string("res://scripts/ui/start_menu.gd")
	var fn := menu.find("func _on_continue(")
	assert_gte(fn, 0, "start_menu.gd must still carry the Continue handler")
	var fn_end := menu.find("\nfunc ", fn + 1)
	assert_gte(fn_end, 0, "...with another function after it, so the slice below is that handler alone")
	var body := menu.substr(fn, fn_end - fn)  # scope the greps to _on_continue: a match anywhere else proves nothing
	var gate := body.find("if GameState.profile_active:")
	assert_gte(gate, 0, "_on_continue must gate the promotion on profile_active — a bare dev boot has no run to resume")
	var promote := body.find("GameState.loaded = true")
	assert_gte(promote, 0, "_on_continue must promote loaded, or Continue on an in-memory run reseeds a default build over it")
	var boot := body.find("_start_game()")
	assert_gte(boot, 0, "_on_continue still boots through _start_game")
	assert_true(gate < promote and promote < boot,
		"the promotion must sit INSIDE the profile_active gate and BEFORE the boot — Player._ready reads `loaded` as it comes up")
	# The other end of the same contract: `loaded` is what routes the backpack to the SAVED bag instead of the seed.
	var player_src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_true(player_src.contains("GameState.loaded and GameState.has_inventory"),
		"player.gd still routes the backpack on GameState.loaded — that is what the Continue promotion buys")
