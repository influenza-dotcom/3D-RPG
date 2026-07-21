extends GutTest

## Contract for the CharacterInspectScreen hero-view weapon selection: the bare-hands FISTS fallback (what the
## weapon hub wields whenever nothing is equipped) must render as UNARMED in the showcase — no weapon mesh, arms
## resting at the sides — and NOT as the melee hammer that fists.tres carries as its `view_model`. A real weapon
## must still render in-hand. Pure off-tree checks of the static `_is_unarmed_fallback` helper: the inspect screen
## is a CanvasLayer autoload, but the helper is host-free, so we load the script and call it without any _ready
## (no SubViewport / no live player needed).

const InspectScreen := preload("res://scripts/ui/character_inspect_screen.gd")


func test_fists_fallback_reads_as_unarmed() -> void:
	# Player.FISTS is the exact preloaded instance the hub equips when unarmed — the primary (instance) match.
	assert_true(InspectScreen._is_unarmed_fallback(Player.FISTS),
		"the FISTS bare-hands fallback must show as unarmed in the inspect showcase (no hammer, arms down)")


func test_loaded_fists_by_path_reads_as_unarmed() -> void:
	# Belt-and-braces: a fists.tres reached by path still counts (resource_path fallback), so a swap path that
	# ever handed back a duplicate wouldn't leak the hammer back into the 'unarmed' hero-view.
	var fists := load("res://resources/weapons/fists.tres") as WeaponData
	assert_true(InspectScreen._is_unarmed_fallback(fists),
		"a fists.tres instance (matched by resource_path) must read as the unarmed fallback")
	fists = null


func test_a_real_weapon_is_not_the_unarmed_fallback() -> void:
	# Any weapon that isn't the FISTS sentinel renders in the showcase's hand — a fresh, path-less WeaponData
	# stands in for 'some drawn weapon' without coupling the test to a specific gun .tres.
	var w := WeaponData.new()
	assert_false(InspectScreen._is_unarmed_fallback(w),
		"a real drawn weapon must render in-hand, not be suppressed as unarmed")
	w = null


func test_null_is_not_the_unarmed_fallback() -> void:
	assert_false(InspectScreen._is_unarmed_fallback(null),
		"null is 'no weapon at all' (handled by the caller) — not the FISTS sentinel")
