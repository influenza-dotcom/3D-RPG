extends GutTest

## DeepScanner (scripts/components/abilities/deep_scanner.gd) — the long-range body scanner: the SAME mechanic as
## BioScanner at a longer reach, under its OWN ability id (a chip installs one id, an id resolves to one
## script/scene pair, the range is a property of the pair). Pinned on a bare `.new()` — the object a runtime
## grant actually builds — so the SCRIPT default is the number a paid install grants:
##   * ability_id &"deep_scanner", the script default 55 m, scan_range_m() with the zero clamp;
##   * it OUT-REACHES the bio tier (AbilityManager.scan_range takes the widest enabled one, so "owning both is
##     simply the deep one" only holds while 55 > 22);
##   * the registry resolves the id to this script, the authored scene agrees with the default, the chip
##     installs the id. The widest-wins / fall-back behaviour is exercised in tests/test_minimap_scan.gd.

const SCRIPT_PATH := "res://scripts/components/abilities/deep_scanner.gd"
const BIO_SCRIPT_PATH := "res://scripts/components/abilities/bio_scanner.gd"
const CHIP := "res://resources/items/chip_deep_scanner.tres"
const ID := &"deep_scanner"
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")


func _bare():
	return load(SCRIPT_PATH).new()


func test_is_an_ability_with_its_own_id() -> void:
	var a = _bare()
	assert_true(a is Ability, "extends Ability so discovery + bookkeeping see it")
	assert_eq(a.ability_id(), ID, "ability_id must be &\"deep_scanner\" — a SEPARATE id from the bio tier, which is what the chip economy can express")
	assert_true(a.enabled, "ships enabled")
	a.free()


func test_the_script_default_is_the_range_a_chip_install_grants() -> void:
	var a = _bare()
	assert_eq(a.scan_range, 55.0, "a bare .new() must grant 55 m — the number the chip is sold on")
	assert_true(a.has_method(&"scan_range_m"), "AbilityManager.scan_range duck-types on scan_range_m()")
	assert_eq(a.scan_range_m(), 55.0, "scan_range_m() reports the export")
	a.scan_range = -1.0
	assert_eq(a.scan_range_m(), 0.0, "a negative clamps to no scanner")
	a.free()


func test_it_out_reaches_the_bio_tier() -> void:
	var deep = _bare()
	var bio = load(BIO_SCRIPT_PATH).new()
	assert_gt(deep.scan_range_m(), bio.scan_range_m(), "the deep tier must reach further than bio — widest-enabled-wins makes owning both 'simply the deep one' only while this holds")
	assert_ne(deep.ability_id(), bio.ability_id(), "the two tiers must not share an id")
	assert_false(deep.get_script() == bio.get_script(), "deliberately two scripts (no shared base can redeclare the export default)")
	deep.free()
	bio.free()


func test_registry_resolves_the_id_to_this_script_and_scene() -> void:
	assert_eq(AbilityRegistry.script_path_for(ID), SCRIPT_PATH, "the id must resolve to deep_scanner.gd by the naming convention")
	assert_true(AbilityRegistry.can_build(ID), "a runtime grant must be able to build it")
	var scene_path := AbilityRegistry.scene_path_for(ID)
	assert_true(ResourceLoader.exists(scene_path), "the authored scene %s must exist" % scene_path)
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return
	var authored = ps.instantiate()
	var bare = _bare()
	assert_eq((authored.get_script() as Script).resource_path, SCRIPT_PATH, "the authored scene runs deep_scanner.gd")
	assert_eq(authored.scan_range, bare.scan_range, "the authored scene must agree with the script default (built-vs-authored)")
	assert_ne(str(authored.display_name).strip_edges(), "", "the scene authors a display_name for the Implants tab")
	authored.free()
	bare.free()


func test_the_chip_installs_this_id() -> void:
	var chip = load(CHIP)
	assert_not_null(chip, "chip_deep_scanner.tres must load")
	if chip == null:
		return
	assert_eq(chip.installs_ability, ID, "the Deep-Scan chip must install &\"deep_scanner\"")
