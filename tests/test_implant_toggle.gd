extends GutTest

## The INSTALLED-vs-ACTIVE split behind the Implants tab's on/off switch. Switching an implant off must stop
## the mechanic (has_mechanic false — every gameplay gate polls that) WITHOUT uninstalling it: it stays owned
## (mechanic_installed), stays listed on the tab (installed_list), can't be re-sold by a ChipInstaller, and
## survives a save/load round-trip through the SEPARATE [player].disabled_unlocks key. That last one is the
## whole reason the key exists: unlocked_list() is the ACTIVE projection, so before the split one autosave
## after a toggle would have permanently deleted the implant.
##
## All off-tree (bare Player.new(), no _ready — the CLAUDE.md rule) on pure-gate abilities (air_dash /
## laser_sight / fall_immunity build no in-tree helpers); the in-tree feel of a mid-slide/mid-grapple switch-off
## is playtested. GameState is exercised on FRESH load().new() instances + a temp path, never the autoload.

const PLAYER_PATH := "res://scripts/player/player.gd"
const GAMESTATE_PATH := "res://managers/GameState.gd"
const TMP_SAVE := "user://test_implant_toggle_tmp.cfg"


func after_each() -> void:
	for f in [TMP_SAVE, TMP_SAVE + ".bak", TMP_SAVE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


## An Ability whose only job is to record that the switch-off hygiene hook fired (the real ones end a live
## slide / sever a live rope — in-tree behaviour this stub stands in for off-tree).
class _HookStub extends Ability:
	var deactivations := 0
	func ability_id() -> StringName:
		return &"air_dash"  # a real registry id, so unlock()/can_grant treat it like any other implant
	func on_deactivated() -> void:
		deactivations += 1


func test_switching_off_keeps_it_installed_but_inactive() -> void:
	var p = load(PLAYER_PATH).new()
	p.unlock_mechanic(&"air_dash")
	assert_true(p.has_mechanic(&"air_dash"), "a freshly installed implant is active")
	assert_true(p.set_mechanic_active(&"air_dash", false), "switching an installed implant off succeeds")
	assert_false(p.has_mechanic(&"air_dash"), "the gameplay gate reads OFF (every consumer polls has_mechanic)")
	assert_true(p.mechanic_installed(&"air_dash"), "...but the implant is still INSTALLED (you own it)")
	assert_false(p.unlocked_list().has(&"air_dash"), "the ACTIVE save projection omits it")
	assert_true(p.disabled_list().has(&"air_dash"), "...and the disabled projection carries it instead")
	assert_true(p.installed_list().has(&"air_dash"), "the Implants tab still lists it (so it can be switched back on)")
	p.free()


func test_switching_back_on_restores_the_mechanic() -> void:
	var p = load(PLAYER_PATH).new()
	p.unlock_mechanic(&"laser_sight")
	p.set_mechanic_active(&"laser_sight", false)
	assert_true(p.set_mechanic_active(&"laser_sight", true), "switching it back on succeeds")
	assert_true(p.has_mechanic(&"laser_sight"), "the mechanic is live again")
	assert_true(p.unlocked_list().has(&"laser_sight"), "...and back in the ACTIVE save projection")
	assert_false(p.disabled_list().has(&"laser_sight"), "...and out of the disabled one")
	p.free()


func test_toggle_refuses_an_implant_you_dont_own() -> void:
	# The toggle NEVER installs — it only flips something already fitted (the paid ChipInstaller owns installs).
	var p = load(PLAYER_PATH).new()
	assert_false(p.set_mechanic_active(&"grapple", true), "toggling an uninstalled implant on is refused")
	assert_false(p.has_mechanic(&"grapple"), "...and grants nothing")
	assert_false(p.mechanic_installed(&"grapple"), "...not even as an installed-but-off node")
	p.free()


func test_toggle_emits_only_on_a_real_change() -> void:
	var p = load(PLAYER_PATH).new()
	p.unlock_mechanic(&"fall_immunity")
	var seen: Array = []
	p.mechanic_toggled.connect(func(id: StringName, active: bool) -> void: seen.append([id, active]))
	assert_true(p.set_mechanic_active(&"fall_immunity", true), "already-on -> succeeds")
	assert_eq(seen.size(), 0, "...but a no-change toggle emits nothing (no spurious repaint/autosave)")
	p.set_mechanic_active(&"fall_immunity", false)
	assert_eq(seen.size(), 1, "a real change emits once")
	assert_eq(seen[0][0], &"fall_immunity", "...naming the implant")
	assert_false(bool(seen[0][1]), "...and its new active state")
	p.free()


func test_switch_off_runs_the_ability_hygiene_hook() -> void:
	# Slide/Grapple override on_deactivated to end a live slide / sever a live rope, so a re-enable can't
	# resume stale state. Pin that the manager actually calls it — on the OFF edge only.
	var p = load(PLAYER_PATH).new()
	var stub := _HookStub.new()
	p.grant_ability(stub)
	assert_eq(stub.deactivations, 0, "granting doesn't deactivate")
	p.set_mechanic_active(&"air_dash", false)
	assert_eq(stub.deactivations, 1, "switching OFF runs the ability's on_deactivated hygiene hook")
	p.set_mechanic_active(&"air_dash", true)
	assert_eq(stub.deactivations, 1, "switching back ON does not")
	p.free()


func test_set_disabled_unlocks_builds_the_node_then_disables_it() -> void:
	# The load path. A runtime-granted implant has NO node in a fresh Player scene, and set_unlocks only builds
	# the ids it's told to ENABLE — so without this build-then-disable step a switched-off implant would come
	# back from a save uninstalled.
	var p = load(PLAYER_PATH).new()
	p.set_unlocks([&"laser_sight"])           # the saved ACTIVE set
	p.set_disabled_unlocks([&"air_dash"])     # ...and the saved switched-OFF set
	assert_true(p.has_mechanic(&"laser_sight"), "the active implant loads active")
	assert_true(p.mechanic_installed(&"air_dash"), "the disabled implant is BUILT (installed) by the load")
	assert_false(p.has_mechanic(&"air_dash"), "...but comes back switched OFF")
	assert_true(p.set_mechanic_active(&"air_dash", true), "...and can be switched on again after the load")
	assert_true(p.has_mechanic(&"air_dash"), "...restoring the mechanic")
	p.free()


func test_disabled_implant_survives_a_save_load_round_trip() -> void:
	# The regression this whole feature turns on: capture -> disk -> load -> restore must not lose the implant.
	var gs = load(GAMESTATE_PATH).new()
	var p = load(PLAYER_PATH).new()
	p.unlock_mechanic(&"air_dash")
	p.unlock_mechanic(&"laser_sight")
	p.set_mechanic_active(&"air_dash", false)
	gs.capture(p)
	assert_false(gs.unlocks.has(&"air_dash"), "the switched-off implant is NOT in the active unlock set")
	assert_true(gs.disabled_unlocks.has(&"air_dash"), "...it rides the separate disabled key")
	assert_true(gs.unlocks.has(&"laser_sight"), "the active implant stays in the unlock set")
	assert_eq(gs.save_to_disk(TMP_SAVE), OK, "the profile writes")
	var gs2 = load(GAMESTATE_PATH).new()
	assert_true(gs2.load_from_disk(TMP_SAVE), "the profile loads back")
	assert_true(gs2.disabled_unlocks.has(&"air_dash"), "the disabled implant round-trips through the cfg")
	assert_false(gs2.unlocks.has(&"air_dash"), "...still not in the active set")
	var p2 = load(PLAYER_PATH).new()
	p2.set_unlocks(gs2.unlocks)
	p2.set_disabled_unlocks(gs2.disabled_unlocks)
	assert_true(p2.mechanic_installed(&"air_dash"), "the reloaded player still OWNS the switched-off implant")
	assert_false(p2.has_mechanic(&"air_dash"), "...and it is still switched off")
	assert_true(p2.has_mechanic(&"laser_sight"), "the active implant reloads active")
	p2.free()
	p.free()
	gs2.free()
	gs.free()


func test_older_save_without_the_key_loads_clean() -> void:
	# Additive-key back-compat (no SAVE_VERSION bump): a save written before the toggle has no
	# [player].disabled_unlocks, which must read as "nothing switched off", never as an error.
	var gs = load(GAMESTATE_PATH).new()
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 4)
	cfg.set_value("player", "money", 100.0)
	cfg.set_value("player", "unlocks", ["air_dash"])  # an old profile: unlocks only
	assert_eq(cfg.save(TMP_SAVE), OK, "the legacy-shaped profile writes")
	assert_true(gs.load_from_disk(TMP_SAVE), "it loads")
	assert_true(gs.unlocks.has(&"air_dash"), "its unlocks still restore")
	assert_true(gs.disabled_unlocks.is_empty(), "a missing disabled_unlocks key reads as nothing switched off")
	gs.free()


## The UI seam, driven off-tree on the AUTHORED scene (instantiate, never add_child — the scene-test idiom;
## _ready doesn't run, and _make_toggle_row/_on_row_toggled only need the MenuStyle autoload). `_player` is
## statically typed Player, so this uses a REAL off-tree Player — safe because the handler's
## GameState.autosave bails on an out-of-tree player.
const SCREEN_SCENE := "res://scenes/ui/implants_screen.tscn"

func _screen_with(player) -> Node:
	var inst: Node = (load(SCREEN_SCENE) as PackedScene).instantiate()
	inst._player = player
	return inst


func test_toggle_row_paints_the_implant_state() -> void:
	var p = load(PLAYER_PATH).new()
	var screen := _screen_with(p)
	var on_row: Button = screen._make_toggle_row(&"air_dash", "Air Dash", "Air Dash Chip", true)
	var off_row: Button = screen._make_toggle_row(&"slide", "Slide", "Slide Chip", false)
	assert_true(on_row.button_pressed, "an ACTIVE implant's row reads pressed (the accent bar = switched on)")
	assert_false(off_row.button_pressed, "a switched-off implant's row reads unpressed")
	assert_almost_eq((on_row.get_child(0) as Control).modulate.a, 1.0, 0.01, "an active row's caption is full strength")
	assert_almost_eq((off_row.get_child(0) as Control).modulate.a, 0.4, 0.01, "a switched-off row's caption dims (the broke-row look)")
	assert_gt(on_row.custom_minimum_size.y, 0.0,
		"the row routes through MenuStyle.size_row_button — an unpinned empty-text Button collapses above its labels")
	on_row.free()
	off_row.free()
	screen.free()
	p.free()


func test_clicking_a_row_flips_that_implant_and_no_other() -> void:
	# Pins the bound-arg wiring: Callable.bind APPENDS, so toggled(bool) + bind(id) must land as
	# _on_row_toggled(on, id). A reversed pair keeps the arity — only asserting WHICH implant moved catches it.
	var p = load(PLAYER_PATH).new()
	p.unlock_mechanic(&"air_dash")
	p.unlock_mechanic(&"laser_sight")
	var screen := _screen_with(p)
	var row: Button = screen._make_toggle_row(&"air_dash", "Air Dash", "", true)
	row.button_pressed = false  # the real click path: emits toggled(false) into the bound handler
	assert_false(p.has_mechanic(&"air_dash"), "clicking the row switched THAT implant off")
	assert_true(p.mechanic_installed(&"air_dash"), "...without uninstalling it")
	assert_true(p.has_mechanic(&"laser_sight"), "...and left the other implant alone")
	row.button_pressed = true
	assert_true(p.has_mechanic(&"air_dash"), "clicking again switches it back on")
	row.free()
	screen.free()
	p.free()


func test_a_switched_off_implant_is_not_for_sale() -> void:
	# The re-sell bug the installed predicate exists to prevent: with the old ACTIVE-flavoured guard, a
	# toggled-off implant made has_mechanic false, so the mechanic re-offered the chip and would CHARGE to
	# merely flip it back on.
	var m := ChipInstaller.new()
	m.stock = CharacterInventory.new()  # off-tree: _ready never ran (the test_chip_install idiom)
	var p = load(PLAYER_PATH).new()
	p.inventory = CharacterInventory.new()
	p.money = 1000.0
	var chip := Item.new()
	chip.id = &"chip_air_dash"
	chip.display_name = "Test Chip"
	chip.category = Item.Category.MISC
	chip.value = 400.0
	chip.installs_ability = &"air_dash"
	p.inventory.add(chip, 1)
	p.unlock_mechanic(&"air_dash")
	p.set_mechanic_active(&"air_dash", false)  # owned, switched off
	assert_eq(m.installable_carried(p).size(), 0, "a switched-off implant's chip is NOT offered for install")
	assert_false(m.install_carried(chip, p), "...and installing it is refused")
	assert_eq(p.money, 1000.0, "no zorkmids taken to re-enable something already owned")
	m.stock.add(chip, 1)
	assert_eq(m.installable_stock(p).size(), 0, "...nor is it offered on the shelf")
	assert_false(m.buy_and_install(chip, p), "...nor buyable")
	assert_eq(p.money, 1000.0, "still no charge")
	m.stock.free()
	m.free()
	p.inventory.free()
	p.free()
	chip = null
