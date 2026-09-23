extends GutTest

## BioScanner (scripts/components/abilities/bio_scanner.gd) — the entry-tier body scanner ability. It has no
## behaviour hooks: its presence + `enabled` IS the grant, and what it grants is ONE duck-typed number,
## scan_range_m(), which AbilityManager.scan_range reads by method name. Pinned on a bare `.new()` because that
## is what a runtime grant gets (AbilityManager._build -> load(script).new(), default exports — never the scene):
##   * ability_id &"bio_scanner" (the id the chip installs and the save serialises);
##   * a bare .new() grants a REAL reach (> 0 m — the tier's exact number is a designer knob, and the
##     built-vs-authored agreement below is what keeps a scene-only retune honest), scan_range_m() honours the
##     export, clamped at 0 for a mis-authored negative;
##   * the registry naming convention resolves the id to THIS script, the authored scene agrees with the script
##     default, and the chip .tres installs the id this script answers with.
## The map-side gating (what the range actually draws) lives in tests/test_minimap_scan.gd.

const SCRIPT_PATH := "res://scripts/components/abilities/bio_scanner.gd"
const CHIP := "res://resources/items/chip_bio_scanner.tres"
const ID := &"bio_scanner"
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")


func _bare():
	return load(SCRIPT_PATH).new()


func test_is_an_ability_with_its_id() -> void:
	var a = _bare()
	assert_true(a is Ability, "extends Ability so the Player's discovery + AbilityManager bookkeeping see it")
	assert_eq(a.ability_id(), ID, "ability_id must be &\"bio_scanner\" — the chip installs and the save matches on it")
	assert_true(a.enabled, "ships enabled — the Implants tab toggle is the only thing that turns it off")
	a.free()


func test_a_bare_build_grants_a_real_range_and_honours_its_export() -> void:
	var a = _bare()
	assert_gt(a.scan_range_m(), 0.0, "a bare .new() (what a paid install / save load builds) must grant a real reach — a range authored only on the scene would install as a 0 m scanner and a map that stays blank")
	a.scan_range = 13.5
	assert_almost_eq(a.scan_range_m(), 13.5, 0.0001, "scan_range_m() — the number AbilityManager.scan_range duck-reads — must report the export, so a hand-placed retune reaches the map")
	a.free()


func test_scan_range_m_clamps_a_negative_to_no_scanner() -> void:
	var a = _bare()
	a.scan_range = -5.0
	assert_eq(a.scan_range_m(), 0.0, "a mis-authored negative reads as 0 m (no scanner), never inverting the rim fade's maths")
	a.scan_range = 0.0
	assert_eq(a.scan_range_m(), 0.0, "zero stays zero")
	a.free()


func test_registry_resolves_the_id_to_this_script_and_scene() -> void:
	assert_eq(AbilityRegistry.script_path_for(ID), SCRIPT_PATH, "the snake_case id must resolve to bio_scanner.gd by the naming convention")
	assert_true(AbilityRegistry.can_build(ID), "a runtime grant must be able to build it")
	var scene_path := AbilityRegistry.scene_path_for(ID)
	assert_true(ResourceLoader.exists(scene_path), "the authored scene %s must exist" % scene_path)
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return
	var authored = ps.instantiate()
	var bare = _bare()
	assert_eq((authored.get_script() as Script).resource_path, SCRIPT_PATH, "the authored scene runs bio_scanner.gd")
	assert_eq(authored.scan_range, bare.scan_range, "the authored scene must agree with the script default — a designer retune on the .tscn alone would never reach a chip install")
	assert_ne(str(authored.display_name).strip_edges(), "", "the scene authors a player-facing display_name for the Implants tab")
	authored.free()
	bare.free()


func test_the_chip_installs_this_id() -> void:
	var chip = load(CHIP)
	assert_not_null(chip, "chip_bio_scanner.tres must load")
	if chip == null:
		return
	var bare = _bare()
	assert_eq(chip.installs_ability, bare.ability_id(), "the Bio-Scanner chip must install the id this scanner answers with — a mismatch is a paid install that grants nothing")
	assert_eq(AbilityRegistry.script_path_for(chip.installs_ability), SCRIPT_PATH, "...and that id must build THIS script at install time")
	bare.free()
