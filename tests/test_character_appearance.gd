extends GutTest

## Character customizer contract: the CharacterAppearanceCatalog (the designer-editable head/body catalog), the
## configure_swap() wiring that turns a chosen appearance into BodyModelSwap exports, and the GameState save/load
## round-trip of the appearance dict.
##
## configure_swap is tested on an OFF-TREE BodyModelSwap: its export setters still store the value, but _rebuild()
## early-returns when not inside the tree, so NO model .glb is instantiated — the test asserts the pure wiring
## (which model/colour landed on which field) without spinning up any 3D. Resources are released with `= null`.

const APPEARANCE_SAVE := "user://__test_appearance_roundtrip.cfg"

func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(APPEARANCE_SAVE))

# --- Catalog ---------------------------------------------------------------------------------------------------

func test_default_catalog_ships_valid_heads_and_bodies() -> void:
	var cat := CharacterAppearanceCatalog.default()
	assert_gte(cat.valid_heads().size(), 4, "the shipped catalog offers at least the four head models")
	assert_gte(cat.valid_bodies().size(), 1, "the shipped catalog offers at least the standard torso body")
	for h in cat.valid_heads():
		assert_true(h.is_valid(), "head '%s' has an id and a real model" % h.id)
	assert_not_null(cat.arm_model, "the shared arm model is loaded")
	assert_not_null(cat.leg_model, "the shared leg model is loaded")
	cat = null

func test_lookup_by_id_and_default_and_unknown() -> void:
	var cat := CharacterAppearanceCatalog.default()
	var def_id := String(cat.default_head_id())
	assert_false(def_id.is_empty(), "there is a default head id")
	assert_not_null(cat.head_option(def_id), "the default head resolves by its id")
	assert_null(cat.head_option("does_not_exist"), "an unknown head id resolves to null")
	assert_null(cat.body_option(""), "an empty body id resolves to null")
	cat = null

# --- configure_swap (off-tree: asserts wiring, instantiates no models) -----------------------------------------

func test_empty_appearance_yields_the_full_default_look() -> void:
	var cat := CharacterAppearanceCatalog.default()
	var swap := BodyModelSwap.new()  # NOT add_child'd -> setters store values, _rebuild no-ops (no .glb instanced)
	cat.configure_swap(swap, {})
	assert_not_null(swap.body_model, "empty appearance still sets a body (the default torso)")
	assert_not_null(swap.head_model, "empty appearance composes the default head")
	assert_not_null(swap.arm_model, "empty appearance sets the shared arms")
	assert_not_null(swap.leg_model, "empty appearance sets the shared legs")
	swap.free()
	cat = null

func test_torso_body_composes_head_and_tints() -> void:
	var cat := CharacterAppearanceCatalog.default()
	var head_id := String(cat.valid_heads()[1].id)  # a non-default head to prove the id is honoured
	var swap := BodyModelSwap.new()
	cat.configure_swap(swap, {
		"body": "standard", "head": head_id,
		"skin": Color(0.7, 0.5, 0.3), "arm": Color(0.1, 0.2, 0.3), "leg": Color(0.3, 0.2, 0.1),
	})
	assert_not_null(swap.head_model, "a torso body composes the chosen head")
	assert_eq(swap.body_color, Color(0.7, 0.5, 0.3), "skin tints the body")
	assert_eq(swap.head_color, Color(0.7, 0.5, 0.3), "skin tints the head too")
	assert_eq(swap.arm_color, Color(0.1, 0.2, 0.3), "the arm colour is applied")
	assert_eq(swap.leg_color, Color(0.3, 0.2, 0.1), "the leg colour is applied")
	swap.free()
	cat = null

func test_whole_body_option_clears_the_composed_parts() -> void:
	# whole_body is still SUPPORTED (an authored catalog can add one) though the shipped default no longer ships one,
	# so author a whole-body option here and prove configure_swap renders it alone (own head/arms/legs -> cleared).
	var cat := CharacterAppearanceCatalog.default()
	var whole := CharacterPartOption.new()
	whole.id = &"whole_test"
	whole.display_name = "Whole"
	whole.model = load("res://assets/models/Man.glb")
	whole.scale = 0.34
	whole.whole_body = true
	cat.bodies.append(whole)
	var swap := BodyModelSwap.new()
	cat.configure_swap(swap, {"body": "whole_test"})
	assert_not_null(swap.body_model, "the whole-body model is the body")
	assert_null(swap.head_model, "a whole-body model brings its own head — the composed head is cleared")
	assert_null(swap.arm_model, "...and its own arms")
	assert_null(swap.leg_model, "...and its own legs")
	swap.free()
	cat = null

func test_unknown_ids_fall_back_to_defaults() -> void:
	var cat := CharacterAppearanceCatalog.default()
	var swap := BodyModelSwap.new()
	cat.configure_swap(swap, {"body": "gone", "head": "also_gone"})
	assert_not_null(swap.body_model, "an unknown body id falls back to the default body")
	assert_not_null(swap.head_model, "an unknown head id falls back to the default head")
	swap.free()
	cat = null

# --- GameState round-trip --------------------------------------------------------------------------------------

func test_appearance_round_trips_through_save_and_load() -> void:
	var want := {
		"head": "chrysalis", "body": "standard",
		"skin": Color(0.9, 0.8, 0.7), "arm": Color(0.2, 0.3, 0.4), "leg": Color(0.4, 0.3, 0.2),
	}
	GameState.appearance = want.duplicate()
	assert_eq(GameState.save_to_disk(APPEARANCE_SAVE), OK, "the profile (with an appearance) saves")
	GameState.appearance = {}
	assert_true(GameState.load_from_disk(APPEARANCE_SAVE), "the profile loads back")
	assert_eq(String(GameState.appearance.get("head", "")), "chrysalis", "the head id round-trips")
	assert_eq(String(GameState.appearance.get("body", "")), "standard", "the body id round-trips")
	assert_eq(GameState.appearance.get("skin"), Color(0.9, 0.8, 0.7), "the skin colour round-trips")
	assert_eq(GameState.appearance.get("arm"), Color(0.2, 0.3, 0.4), "the arm colour round-trips")

func test_empty_appearance_writes_no_section_and_loads_empty() -> void:
	GameState.appearance = {}
	assert_eq(GameState.save_to_disk(APPEARANCE_SAVE), OK, "a never-customised profile saves")
	GameState.appearance = {"head": "stale"}  # something to prove load clears it
	assert_true(GameState.load_from_disk(APPEARANCE_SAVE), "it loads back")
	assert_true(GameState.appearance.is_empty(), "no [appearance] section -> the loaded appearance is empty (catalog default)")

func test_reset_for_new_game_clears_appearance() -> void:
	GameState.appearance = {"head": "headblue", "body": "man"}
	GameState.reset_for_new_game()
	assert_true(GameState.appearance.is_empty(), "a fresh run starts un-customised")
