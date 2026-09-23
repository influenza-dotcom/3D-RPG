extends GutTest

## P0-1: a fresh game must start with ZERO abilities — the microchip-install economy (ChipInstaller ->
## GameState.unlocks) requires it. Player.tscn correctly sets starting_unlocks = []; scenes/game.tscn is the scene
## StartMenu boots for New Game, so ITS Player override is the surface the contract hinges on. This pins that the
## override is empty and that any id it does carry is a real AbilityRegistry id (a stale/bogus id like the removed
## "grapple_hook" would otherwise pre-grant a broken ability). Instantiated WITHOUT add_child so no _ready runs (the
## test_level_door_prefab idiom); a reimport-empty PackedScene degrades to a skip, not a crash.

const GAME_SCENE := "res://scenes/game.tscn"
const ABILITY_REGISTRY := "res://scripts/components/abilities/ability_registry.gd"
## A StartMenu whose boot is swapped for a recorder: _on_continue runs for REAL up to the boot, and the recorder
## captures GameState.loaded at the instant the boot begins — exactly what the fresh Player._ready would read.
const CONTINUE_SPY_SOURCE := "extends \"res://scripts/ui/start_menu.gd\"\n\nvar boots: Array = []\n\nfunc _start_game(_show_quote := false) -> void:\n\tboots.append(GameState.loaded)\n"

var _prev_loaded: bool
var _prev_profile: bool


func before_each() -> void:
	_prev_loaded = GameState.loaded
	_prev_profile = GameState.profile_active


func after_each() -> void:
	GameState.loaded = _prev_loaded
	GameState.profile_active = _prev_profile


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
## and the bill that bought them cannot separate.
##
## KEPT AS A SOURCE PIN, deliberately: every branch here is INLINE in Player._ready, which a unit test may never run
## (it instantiates weapons / nav / audio — CLAUDE.md), and there is no pure helper to call instead. So the scan is
## scoped to _ready's own body and pins the exact gate expressions IN ORDER, not bare tokens anywhere in the file.
func test_fresh_boot_applies_a_seeded_unlock_set() -> void:
	# Normalize line endings: the scan matches "\n\t..." anchors, so a CRLF write must not read as a lost branch.
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd").replace("\r\n", "\n")
	var start := src.find("\nfunc _ready() -> void:")
	assert_gt(start, -1, "player.gd must still define _ready")
	var end := src.find("\nfunc ", start + 1)
	var body := src.substr(start, end - start) if end > start else src.substr(start)
	# The escape hatch must span BOTH implant lists, joined by OR. `unlocks` is only the ACTIVE projection, so a run
	# whose implants are ALL switched off (Implants tab) reaches this branch with an EMPTY unlocks and a populated
	# disabled_unlocks — and this boot mode is reached mid-run (Options -> Main Menu -> Continue never loads from disk).
	# Gating on unlocks alone (or AND-ing the two) fell through to _seed_unlocks() and permanently UNINSTALLED them.
	var disk := body.find("\n\tif GameState.loaded:\n")
	var hatch := body.find("not GameState.unlocks.is_empty() or not GameState.disabled_unlocks.is_empty()")
	assert_gt(disk, -1, "_ready still branches the unlock restore on GameState.loaded")
	assert_gt(hatch, disk,
		"on a loaded=false boot, _ready applies a seeded implant set when EITHER list is non-empty — the purchased cart, or a run whose implants are all switched OFF")
	var apply_on := body.find("set_unlocks(GameState.unlocks)", hatch)
	var apply_off := body.find("set_disabled_unlocks(GameState.disabled_unlocks)", hatch)
	var seed_at := body.find("_seed_unlocks()", hatch)
	assert_true(apply_on > hatch and apply_off > apply_on and seed_at > apply_off,
		"inside the hatch: restore the active implants, THEN re-disable the switched-off ones, and only otherwise take the fresh-game seed (on=%d off=%d seed=%d)" % [apply_on, apply_off, seed_at])
	# The created-run CASH branch: read GameState.money rather than re-seeding it, so an in-memory run never gets
	# refunded what it spent.
	var cash := body.find("\n\telif GameState.profile_active:\n")
	assert_gt(cash, -1, "_ready keeps the created-run CASH branch")
	assert_gt(body.find("money = GameState.money", cash), cash,
		"...and that branch reads the live wallet from GameState.money instead of the starting-money knob")
	# The other end of the Continue promotion below: `loaded` is what routes the backpack to the SAVED bag.
	var bag := body.find("if GameState.loaded and GameState.has_inventory:")
	assert_gt(bag, -1, "_ready routes the backpack on GameState.loaded — that is what the Continue promotion buys")
	assert_true(body.find("_restore_saved_inventory()", bag) > bag
			and body.find("_seed_starting_inventory()", bag) > body.find("_restore_saved_inventory()", bag),
		"a loaded boot RESTORES the saved bag, and only otherwise seeds the authored starting loadout")


## ⭐CONTINUE ON AN IN-MEMORY RUN. The same loaded=false boot mode as above, reached the other way: a New-Game
## session never runs a disk load, so `loaded` stays false for its whole life, and Options -> Main Menu drops the
## player back on the start menu with that live run still sitting in the GameState autoload. Pressing Continue
## booted it UN-PROMOTED, and Player._ready routes the backpack on `GameState.loaded and GameState.has_inventory`
## — so the fresh Player re-seeded the authored starting loadout OVER the live bag and skipped perks / xp / level
## / reputation / status effects, silently discarding the run before the next autosave wrote the wreckage to disk.
## StartMenu._on_continue promotes `loaded` for a profile_active run, in the ONE caller that knows it is RESUMING.
## Driven for real through a spy subclass that only replaces the boot.
func test_continue_promotes_an_in_memory_run_onto_the_saved_path() -> void:
	var spy_script := GDScript.new()
	spy_script.source_code = CONTINUE_SPY_SOURCE
	assert_eq(spy_script.reload(), OK, "the Continue spy (a StartMenu with a recording boot) must compile")
	var menu = spy_script.new()  # never added to the tree: no _ready, no menu build — only the handler runs
	# Control: a bare dev boot has no run to resume, so Continue must NOT pretend a save was loaded.
	GameState.profile_active = false
	GameState.loaded = false
	menu._on_continue()
	# The case that lost runs: a created run still in memory, never loaded from disk.
	GameState.profile_active = true
	GameState.loaded = false
	menu._on_continue()
	var boots: Array = menu.boots
	assert_eq(boots.size(), 2, "each Continue press must boot exactly once (got %s)" % str(boots))
	assert_true(boots.size() == 2 and boots[0] == false,
		"control: with no created profile the boot sees loaded=false — a dev boot takes the fresh seed, never a phantom save (got %s)" % str(boots))
	assert_true(boots.size() == 2 and boots[1] == true,
		"Continue on an in-memory created run must boot with loaded=true ALREADY set — Player._ready reads it as it comes up, so a promotion after the boot (or none) re-seeds a default build over the live run (got %s)" % str(boots))
	menu.free()
	spy_script = null
