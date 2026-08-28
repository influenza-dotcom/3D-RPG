extends GutTest

## THE SCANNER IMPLANT — the gate that stopped the map showing every body in the level at any range.
##
## Before this, scripts/ui/minimap.gd dotted every living Groups.NPC member the view happened to cover. On the
## HUD corner box (40 m) that read as "near you"; on the Map tab it did not — that widget draws 120 m, zooms
## out to 240 and pans 400, so the body channel was a free through-wall census of the whole level. Now the
## channel is gated on an installed, switched-on SCANNER implant and reaches exactly as far as the chip the
## player bought: BioScanner 22 m, DeepScanner 55 m.
##
## THREE THINGS CARRY THE RISK HERE, and each has a test below:
##
##  1. ⭐A RUNTIME GRANT NEVER TOUCHES THE SCENE. AbilityManager._build does
##     `load(script_path_for(id)).new()` — a bare script instance with DEFAULT exports — so a paid chip
##     install, a save load and an UpgradePickup all get the SCRIPT's default, not the .tscn's authored value.
##     Every other shipped ability is a pure presence flag, so nothing was ever lost there; a scanner whose
##     range lived on the scene alone would install at 0 m, and the player would have paid for a map that
##     stays blank with no error anywhere. test_a_runtime_built_scanner_matches_its_authored_scene is the
##     tripwire, and it is written to cover a THIRD scanner nobody has authored yet.
##  2. THE THREE-OWNER GATE being read in ONE place (Minimap._sample_scan_range), so the idle gate, the paint
##     site and the rim fade cannot drift apart. Same lesson, same shape, as the noise ring's two-owner gate —
##     see tests/test_minimap_noise.gd and test_minimap.gd's "the idle gate asks the same question" test.
##  3. THE TRAILING EDGE. Installing a chip, or flipping a scanner off in the Implants tab, changes what the
##     map draws while the player is standing still in a menu — the exact state the idle gate withholds
##     repaints in. Without the _drawn_scan_r stamp the dots you just paid for appear only once you walk.
##
## Loaded BY PATH, never by class_name, for the stale-global-class-cache reason test_minimap.gd documents.

const MINIMAP_SCRIPT := "res://scripts/ui/minimap.gd"
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")
const BIO := &"bio_scanner"
const DEEP := &"deep_scanner"
const BIO_CHIP := "res://resources/items/chip_bio_scanner.tres"
const DEEP_CHIP := "res://resources/items/chip_deep_scanner.tres"


## The Player surface this channel consumes: ONE duck-typed float. Deliberately not a Player — Player._ready
## builds weapons, nav and audio and mutates shared statics (the house rule) — because minimap.gd asks
## has_method(&"body_scan_range") and nothing else.
class ScannerStub extends Node3D:
	var reach: float = 40.0
	func body_scan_range() -> float:
		return reach


## A host that cannot answer at all: the fail-CLOSED case, and the one every pre-existing test stub is in.
class MuteStub extends Node3D:
	pass


## Off-tree Player SUBCLASS stub, the sanctioned actor-in-a-test pattern (test_movement_helpers' _StanceStub):
## never add_child'd, so _ready() never runs and the unset @export wiring is never dereferenced. unlock_mechanic
## still works — AbilityManager.unlock -> _build -> host.add_child() is legal on a parentless node.
class PlayerStub extends Player:
	pass


func _mm():
	var mm = load(MINIMAP_SCRIPT).new()
	autofree(mm)
	return mm


## An in-tree, PAINTING minimap in the state the bug lives in — test_minimap.gd's _idle_minimap, copied for the
## same reason it exists there: a bare .new() answers TRUE on three terms that have nothing to do with this
## channel (_deck_dirty ships true, _drawn_zoom is seeded NAN and _drawn_skin_id 0).
func _idle_minimap():
	var mm = load(MINIMAP_SCRIPT).new()
	mm._source_region_id = 0
	mm._deck_dirty = false
	add_child_autofree(mm)
	mm.size = GameSettings.hud.minimap_size
	return mm


## One painted frame — a queued redraw lands at the end of the frame, so two process frames.
func _repaint(mm) -> void:
	mm.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame


func _scanner(reach: float) -> Node3D:
	var s := ScannerStub.new()
	s.reach = reach
	autofree(s)
	return s


# --- the implant itself ------------------------------------------------------------------------------------

## THE SHIPPED STATE OF A FRESH GAME. Player.starting_unlocks is empty, so a new character owns no scanner and
## the map draws no bodies at all. If this ever reads non-zero the whole feature is off and the census is back.
func test_a_fresh_player_reads_no_bodies() -> void:
	var p := PlayerStub.new()
	assert_eq(p.body_scan_range(), 0.0,
		"a player with no scanner implant must read NO bodies — a fresh game ships with zero abilities, so map presence is earned exactly like the silent takedown is")
	p.free()


## The grant path end to end: the id resolves a buildable script by the AbilityRegistry naming convention, and
## the range that arrives is the one the chip is sold on.
func test_installing_the_bio_scanner_grants_its_authored_range() -> void:
	var p := PlayerStub.new()
	p.unlock_mechanic(BIO)
	assert_true(p.has_mechanic(BIO), "unlock_mechanic must build the scanner node from the registry")
	assert_eq(p.body_scan_range(), 22.0,
		"the installed Bio-Scanner must grant its own 22 m — a chip install that grants 0 m is a paid upgrade with no effect and no error")
	p.free()


## WIDEST WINS, and switching the wide one off falls back rather than blanking the map. That fallback is why
## two tiers can coexist at all: the Implants-tab toggle stays a real choice instead of a light switch.
func test_the_deep_scanner_wins_and_switching_it_off_falls_back() -> void:
	var p := PlayerStub.new()
	p.unlock_mechanic(BIO)
	p.unlock_mechanic(DEEP)
	assert_eq(p.body_scan_range(), 55.0, "owning both tiers is simply the deep one — max, not first-hit and not a sum")
	p.set_mechanic_active(DEEP, false)
	assert_eq(p.body_scan_range(), 22.0,
		"switching the deep scanner off must fall back to the short read, not blank the map: scan_range is the ACTIVE predicate, like has_mechanic")
	p.set_mechanic_active(BIO, false)
	assert_eq(p.body_scan_range(), 0.0, "...and with every scanner off, no bodies at all")
	assert_true(p.mechanic_installed(DEEP),
		"switched off must stay INSTALLED — it rides GameState.disabled_unlocks, so one autosave cannot uninstall what the player paid for")
	p.free()


## ⭐THE ONE THAT MATTERS. A runtime grant (paid chip install / save load / UpgradePickup) builds the ability
## from its SCRIPT and never sees the .tscn, so a range authored on the scene alone would silently install as
## the script default. Written over every ability scene on disk rather than over a hardcoded pair, so a third
## scanner authored later is covered the day it lands.
func test_a_runtime_built_scanner_matches_its_authored_scene() -> void:
	var checked := 0
	for id in AbilityRegistry.ids():
		var sid := StringName(id)
		var ps := load(AbilityRegistry.scene_path_for(sid)) as PackedScene
		assert_not_null(ps, "ability scene for '%s' must load" % id)
		if ps == null:
			continue
		var inst := ps.instantiate()
		if not inst.has_method(&"scan_range_m"):
			inst.free()   # not a scanner — every other ability is a pure presence flag
			continue
		checked += 1
		assert_true(AbilityRegistry.can_build(sid), "scanner '%s' must be runtime-buildable" % id)
		var built = load(AbilityRegistry.script_path_for(sid)).new()
		assert_eq(float(built.scan_range_m()), float(inst.scan_range_m()),
			"scanner '%s' must grant the SAME range whether it was built from its script (a chip install, a save load) or instanced from its scene — AbilityManager._build never touches the .tscn, so a range authored only there installs as nothing" % id)
		assert_gt(float(built.scan_range_m()), 0.0,
			"scanner '%s' must actually reach somewhere: a 0 m scanner is an implant that draws no bodies" % id)
		built.free()
		inst.free()
	assert_eq(checked, 2,
		"expected the 2 shipped scanner implants (BioScanner 22 m / DeepScanner 55 m); update this count when a tier is added or retired")


## The chips are what the player actually buys, so they must install REAL scanners — a typo'd installs_ability
## would take the money and grant nothing (the C21 hole test_chip_install.gd pins generally, re-checked here
## for these two because the mechanic they gate is INVISIBLE when it fails).
func test_the_scanner_chips_install_real_scanners() -> void:
	for pair in [[BIO_CHIP, BIO], [DEEP_CHIP, DEEP]]:
		var chip := load(pair[0]) as Item
		assert_not_null(chip, "%s must load" % pair[0])
		if chip == null:
			continue
		assert_eq(chip.installs_ability, pair[1], "%s must install its own scanner ability" % pair[0])
		assert_true(chip.is_upgrade_chip(), "%s must read as an upgrade chip" % pair[0])
		assert_gt(chip.value, 0.0,
			"%s needs a price: Item.value IS the creation-screen bill and the ChipInstaller fee base, and <= 0 fails closed" % pair[0])


# --- the sampler: the three-owner gate, read in ONE place ---------------------------------------------------

## ALL THREE OWNERS, and each of them alone is enough to blank the channel. The point of reading them here and
## nowhere else is that the idle gate and the paint site then ask literally the same question — the defect
## test_minimap.gd's "the idle gate asks the same question the paint site does" was written for.
func test_the_sampler_needs_all_three_owners() -> void:
	var mm = _mm()
	var was: bool = Settings.minimap_show_npcs
	Settings.minimap_show_npcs = true
	mm.dot_npcs = true
	assert_eq(mm._sample_scan_range(_scanner(30.0)), 30.0, "all three on: the implant's reach, in metres")
	mm.dot_npcs = false
	assert_eq(mm._sample_scan_range(_scanner(30.0)), 0.0, "the DESIGNER switch alone blanks the channel")
	mm.dot_npcs = true
	Settings.minimap_show_npcs = false
	assert_eq(mm._sample_scan_range(_scanner(30.0)), 0.0, "...and so does the player's Options row")
	Settings.minimap_show_npcs = true
	assert_eq(mm._sample_scan_range(_scanner(0.0)), 0.0, "...and so does having no scanner implant")
	Settings.minimap_show_npcs = was


## FAILS CLOSED. A host that cannot answer body_scan_range reads as NO SCANNER, which is the safe direction for
## a channel whose whole job is to withhold information — and it is the state every pre-existing test stub, and
## any future non-Player carrier, is in.
func test_a_host_that_cannot_answer_reads_as_no_scanner() -> void:
	var mm = _mm()
	var was: bool = Settings.minimap_show_npcs
	Settings.minimap_show_npcs = true
	var mute := MuteStub.new()
	autofree(mute)
	assert_eq(mm._sample_scan_range(mute), 0.0,
		"a host with no body_scan_range() must read as no scanner, never as an unlimited one")
	Settings.minimap_show_npcs = was


## A mis-authored NEGATIVE range must read as "no scanner" rather than inverting the rim fade's maths.
func test_a_negative_range_reads_as_no_scanner() -> void:
	var mm = _mm()
	var was: bool = Settings.minimap_show_npcs
	Settings.minimap_show_npcs = true
	assert_eq(mm._sample_scan_range(_scanner(-5.0)), 0.0, "a negative reach is not a scanner pointing backwards")
	Settings.minimap_show_npcs = was


# --- the rim -------------------------------------------------------------------------------------------------

## THE FADE BAND, and why it is not a hard clip: a walking body's dot blinking in and out at a fixed radius
## reads as the map glitching, and on the Map tab the rim can sit well inside the drawn view with nothing on
## screen to explain the pop. Full strength inside, zero at the rim, nothing beyond.
func test_the_rim_fades_instead_of_popping() -> void:
	var mm = _mm()
	var was: float = GameSettings.hud.minimap_scan_fade_m
	GameSettings.hud.minimap_scan_fade_m = 4.0
	mm._scan_r = 20.0
	mm._centre_xz = Vector2.ZERO
	assert_eq(mm._scan_fade(Vector3(5.0, 0.0, 0.0)), 1.0, "well inside the reach, a body reads at full strength")
	assert_eq(mm._scan_fade(Vector3(16.0, 0.0, 0.0)), 1.0, "...right up to where the band starts")
	assert_almost_eq(mm._scan_fade(Vector3(18.0, 0.0, 0.0)), 0.5, 0.001, "...then ramps down across the band")
	assert_eq(mm._scan_fade(Vector3(20.0, 0.0, 0.0)), 0.0, "...reaching nothing exactly at the rim")
	assert_eq(mm._scan_fade(Vector3(40.0, 0.0, 0.0)), 0.0, "and a body well past it is simply not there")
	GameSettings.hud.minimap_scan_fade_m = was


## The rim is measured from the PLAYER, not from the middle of the widget. Those are the same point on the
## un-panned HUD box and stop being the same the moment the Map tab drags its view away — which is exactly when
## a radius welded to the window would start scanning from wherever the player happened to be looking.
func test_the_rim_is_measured_from_the_player_not_the_box() -> void:
	var mm = _mm()
	var was: float = GameSettings.hud.minimap_scan_fade_m
	GameSettings.hud.minimap_scan_fade_m = 0.0
	mm._scan_r = 10.0
	mm._centre_xz = Vector2(100.0, 100.0)
	assert_eq(mm._scan_fade(Vector3(103.0, 0.0, 100.0)), 1.0, "3 m from the PLAYER is in range")
	assert_eq(mm._scan_fade(Vector3(0.0, 0.0, 0.0)), 0.0, "...and the world origin, 141 m away, is not")
	GameSettings.hud.minimap_scan_fade_m = was


## PLANAR X/Z, matching _marker_point's own max_marker_distance cut: this is a floorplan, so the file keeps ONE
## notion of "how far away is that marker". The vertical axis is carried separately and honestly by the
## cross-floor alpha fade and the up/down floor tick.
func test_the_rim_ignores_height_because_the_floor_channels_carry_it() -> void:
	var mm = _mm()
	var was: float = GameSettings.hud.minimap_scan_fade_m
	GameSettings.hud.minimap_scan_fade_m = 0.0
	mm._scan_r = 10.0
	mm._centre_xz = Vector2.ZERO
	assert_eq(mm._scan_fade(Vector3(0.0, 40.0, 0.0)), 1.0,
		"a body ten storeys up is still 0 m away on the PLAN — height is the floor tick's and the cross-floor fade's job, not a second distance rule")
	GameSettings.hud.minimap_scan_fade_m = was


## The documented off-switch: a zero band is the hard inside/outside clip, not a division by zero.
func test_a_zero_fade_band_is_a_hard_clip() -> void:
	var mm = _mm()
	var was: float = GameSettings.hud.minimap_scan_fade_m
	GameSettings.hud.minimap_scan_fade_m = 0.0
	mm._scan_r = 10.0
	mm._centre_xz = Vector2.ZERO
	assert_eq(mm._scan_fade(Vector3(9.99, 0.0, 0.0)), 1.0, "inside is full strength all the way to the rim")
	assert_eq(mm._scan_fade(Vector3(10.01, 0.0, 0.0)), 0.0, "and outside is nothing, with no ramp between")
	GameSettings.hud.minimap_scan_fade_m = was


## With no scanner at all the fade answers zero for every point, so nothing can draw a body even if it reached
## the painter without passing the early-out.
func test_no_scanner_fades_everything_to_nothing() -> void:
	var mm = _mm()
	mm._scan_r = 0.0
	mm._centre_xz = Vector2.ZERO
	assert_eq(mm._scan_fade(Vector3.ZERO), 0.0, "a body standing ON the player is still invisible without a chip")


# --- the trailing edge -----------------------------------------------------------------------------------------

## THE STAMP. Installing a chip (or flipping a scanner off in the Implants tab) changes what the body channel
## draws while nothing on the map moves and no Settings row changes — the player is standing still in a menu,
## which is precisely the state the idle gate withholds repaints in. Without _drawn_scan_r the dots you just
## paid for would not appear until you walked.
func test_installing_a_scanner_repaints_an_otherwise_idle_map() -> void:
	var was: bool = Settings.minimap_show_npcs
	Settings.minimap_show_npcs = true
	var mm = _idle_minimap()
	await _repaint(mm)
	assert_false(mm._needs_repaint(false), "precondition: a chip-less player standing still on an empty map is idle")
	mm._scan_r = 22.0                       # what _process samples on the frame the chip is fitted
	assert_true(mm._scan_changed(), "the frame a scanner is installed must ask for a repaint")
	assert_true(mm._needs_repaint(false), "...through the gate, not merely in the probe")
	await _repaint(mm)
	assert_eq(mm._drawn_scan_r, 22.0, "the paint stamps the reach it was made from")
	assert_false(mm._needs_repaint(false), "...and exactly ONE repaint: the stamp re-agrees and the gate shuts")
	Settings.minimap_show_npcs = was


## THE COST THE GATE BUYS BACK. A chip-less player in a level full of bodies must pay NOTHING — the common
## case, since a fresh game owns no scanner. Same term the Options row was fixed for once already.
func test_a_chipless_player_pays_nothing_for_a_level_full_of_bodies() -> void:
	var was: bool = Settings.minimap_show_npcs
	var was_stations: bool = Settings.minimap_show_stations
	Settings.minimap_show_npcs = true
	Settings.minimap_show_stations = false  # else the station clause answers for the body group as well
	var mm = _idle_minimap()
	for i in 5:
		var body := Node3D.new()
		add_child_autofree(body)
		body.add_to_group(Groups.NPC)
	mm._scan_r = 0.0
	assert_false(mm._has_live_markers(),
		"without a scanner, bodies are not something this map is showing — so nothing they do can be worth a repaint")
	Settings.minimap_show_npcs = was
	Settings.minimap_show_stations = was_stations


# --- end to end -------------------------------------------------------------------------------------------------

## THE WHOLE FEATURE, through the shipped paint: a body in the group paints a dot with a scanner and paints
## NOTHING without one. _painted is set inside _draw from the body channel itself, so it is the one observable
## that says the early-out really is wired to the sample.
func test_the_paint_site_draws_bodies_only_with_a_scanner() -> void:
	var was: bool = Settings.minimap_show_npcs
	var was_stations: bool = Settings.minimap_show_stations
	Settings.minimap_show_npcs = true
	Settings.minimap_show_stations = false
	var mm = _idle_minimap()
	var body := Node3D.new()
	add_child_autofree(body)
	body.add_to_group(Groups.NPC)   # at the origin, where the player is: as close as a body can be
	mm._scan_r = 0.0
	await _repaint(mm)
	assert_false(mm._painted,
		"a body standing on top of a chip-less player must still put NOTHING on the map — the implant is the gate, not the distance")
	mm._scan_r = 22.0
	await _repaint(mm)
	assert_true(mm._painted, "...and the same body with a scanner fitted is a dot")
	Settings.minimap_show_npcs = was
	Settings.minimap_show_stations = was_stations
