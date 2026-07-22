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

# --- Drawn shirt (the "Shirt" tab paints a custom torso texture) ------------------------------------------------

func test_default_catalog_ships_a_shirt_palette() -> void:
	var cat := CharacterAppearanceCatalog.default()
	assert_gt(cat.shirt_palette.size(), 0, "the shipped catalog offers a brush palette for the Shirt tab")
	cat = null

func test_authored_catalog_ships_a_shirt_palette() -> void:
	# The runtime prefers the AUTHORED .tres over default() — a field added to the script but never authored into
	# the .tres silently ships empty (exactly how the Shirt tab once launched with ZERO paint chips). Pin the file.
	var cat: CharacterAppearanceCatalog = load(CharacterAppearanceCatalog.OVERRIDE_PATH)
	assert_not_null(cat, "the authored PlayerAppearanceCatalog.tres exists (get_catalog prefers it)")
	if cat != null:
		assert_gt(cat.shirt_palette.size(), 0, "the AUTHORED catalog offers Shirt-tab paints (not just default())")
		assert_gt(cat.limb_palette.size(), 0, "the AUTHORED catalog offers arm/leg swatches")
	cat = null

func test_shirt_texture_resolves_none_texture_and_bytes() -> void:
	assert_null(CharacterAppearanceCatalog.shirt_texture({}), "no shirt key -> null (use the base shirt)")
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var tex := ImageTexture.create_from_image(img)
	assert_eq(CharacterAppearanceCatalog.shirt_texture({"shirt": tex}), tex, "a live ImageTexture passes straight through")
	var decoded := CharacterAppearanceCatalog.shirt_texture({"shirt": img.save_png_to_buffer()})
	assert_not_null(decoded, "PNG bytes decode to a texture")
	assert_true(decoded is Texture2D, "the decoded shirt is a Texture2D")
	assert_null(CharacterAppearanceCatalog.shirt_texture({"shirt": PackedByteArray()}), "empty bytes -> null")

func test_shirt_texture_normalises_to_combined_front_back() -> void:
	# The planar shader samples a 1:2 (front over back) stack. A LEGACY square save must decode to that shape (the
	# design duplicated onto both halves); a modern combined save must stay 1:2.
	var square := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	square.fill(Color(0.2, 0.9, 0.4))
	var from_square := CharacterAppearanceCatalog.shirt_texture({"shirt": square.save_png_to_buffer()})
	assert_not_null(from_square, "a legacy square shirt decodes")
	assert_eq(from_square.get_height(), from_square.get_width() * 2, "...normalised to a 1:2 front/back stack")
	var combined := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	var from_combined := CharacterAppearanceCatalog.shirt_texture({"shirt": combined.save_png_to_buffer()})
	assert_eq(from_combined.get_height(), from_combined.get_width() * 2, "an already-combined shirt stays 1:2")

func test_configure_swap_applies_a_custom_shirt_untinted() -> void:
	var cat := CharacterAppearanceCatalog.default()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.2, 0.9))
	var tex := ImageTexture.create_from_image(img)
	var swap := BodyModelSwap.new()
	cat.configure_swap(swap, {"body": "standard", "skin": Color(0.7, 0.5, 0.3), "shirt": tex})
	assert_eq(swap.body_texture, tex, "a custom shirt replaces the torso's own texture")
	assert_eq(swap.body_color, Color.WHITE, "a custom shirt shows untinted (body_color forced white)")
	assert_eq(swap.head_color, Color(0.7, 0.5, 0.3), "the head still takes the chosen skin tone")
	assert_true(swap.body_texture_planar, "a DRAWN shirt projects planar (the torso's atlas UVs would shred it)")
	swap.free()
	cat = null

func test_no_shirt_keeps_the_base_body_texture() -> void:
	var cat := CharacterAppearanceCatalog.default()
	var swap := BodyModelSwap.new()
	cat.configure_swap(swap, {"body": "standard", "skin": Color(0.7, 0.5, 0.3)})
	assert_eq(swap.body_color, Color(0.7, 0.5, 0.3), "without a drawn shirt, skin still tints the body")
	assert_false(swap.body_texture_planar, "the AUTHORED base texture keeps the mesh UVs (painted for the atlas)")
	swap.free()
	cat = null

func test_whole_body_models_never_wear_the_drawn_shirt() -> void:
	# On a whole_body option the "body" IS the entire character — projecting the player's tee drawing across its
	# face/limbs would be wrong, so configure_swap drops the shirt for those bodies.
	var cat := CharacterAppearanceCatalog.default()
	cat.bodies[0].whole_body = true
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var tex := ImageTexture.create_from_image(img)
	var swap := BodyModelSwap.new()
	cat.configure_swap(swap, {"body": "standard", "skin": Color(0.7, 0.5, 0.3), "shirt": tex})
	assert_ne(swap.body_texture, tex, "a whole-body model keeps its own texture, not the drawn shirt")
	assert_false(swap.body_texture_planar, "...and never takes the planar-projection mode")
	assert_eq(swap.body_color, Color(0.7, 0.5, 0.3), "...so the skin tint still applies")
	swap.free()
	cat = null

# --- GameState round-trip --------------------------------------------------------------------------------------
## A BARE GameState (load-by-path .new(), NEVER the real autoload) so these save/load/reset tests can't clobber the shared
## autoload's in-memory run: load_from_disk latches loaded/profile_active true and wipes money/stats/flags/world_objects/
## quests to the temp file's contents, making any later test that reads autoload state pass/fail order-dependently. Mirrors
## the bare-instance convention test_world_snapshot.gd states. Node -> the caller frees it.
func _bare_gs() -> Node:
	return load("res://managers/GameState.gd").new()

func test_shirt_bytes_round_trip_through_save_and_load() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.6, 0.9))
	var bytes := img.save_png_to_buffer()
	var gs := _bare_gs()
	gs.appearance = {"body": "standard", "shirt": bytes}
	assert_eq(gs.save_to_disk(APPEARANCE_SAVE), OK, "a profile with a drawn shirt saves")
	gs.appearance = {}
	assert_true(gs.load_from_disk(APPEARANCE_SAVE), "it loads back")
	var got: Variant = gs.appearance.get("shirt")
	assert_true(got is PackedByteArray, "the shirt loads back as PNG bytes")
	assert_eq(got as PackedByteArray, bytes, "the shirt bytes round-trip byte-for-byte")
	gs.free()

func test_appearance_round_trips_through_save_and_load() -> void:
	var want := {
		"head": "chrysalis", "body": "standard",
		"skin": Color(0.9, 0.8, 0.7), "arm": Color(0.2, 0.3, 0.4), "leg": Color(0.4, 0.3, 0.2),
	}
	var gs := _bare_gs()
	gs.appearance = want.duplicate()
	assert_eq(gs.save_to_disk(APPEARANCE_SAVE), OK, "the profile (with an appearance) saves")
	gs.appearance = {}
	assert_true(gs.load_from_disk(APPEARANCE_SAVE), "the profile loads back")
	assert_eq(String(gs.appearance.get("head", "")), "chrysalis", "the head id round-trips")
	assert_eq(String(gs.appearance.get("body", "")), "standard", "the body id round-trips")
	assert_eq(gs.appearance.get("skin"), Color(0.9, 0.8, 0.7), "the skin colour round-trips")
	assert_eq(gs.appearance.get("arm"), Color(0.2, 0.3, 0.4), "the arm colour round-trips")
	gs.free()

func test_empty_appearance_writes_no_section_and_loads_empty() -> void:
	var gs := _bare_gs()
	gs.appearance = {}
	assert_eq(gs.save_to_disk(APPEARANCE_SAVE), OK, "a never-customised profile saves")
	gs.appearance = {"head": "stale"}  # something to prove load clears it
	assert_true(gs.load_from_disk(APPEARANCE_SAVE), "it loads back")
	assert_true(gs.appearance.is_empty(), "no [appearance] section -> the loaded appearance is empty (catalog default)")
	gs.free()

func test_reset_for_new_game_clears_appearance() -> void:
	var gs := _bare_gs()
	gs.appearance = {"head": "headblue", "body": "man"}
	# reset_for_new_game() also fires Reputation.reset() on the real autoload — snapshot + restore its standings so this
	# test leaves no cross-test residue (the bare instance already isolates appearance / loaded / profile_active / flags).
	var rep_before := Reputation.all_standings()
	gs.reset_for_new_game()
	assert_true(gs.appearance.is_empty(), "a fresh run starts un-customised")
	Reputation.restore(rep_before)
	gs.free()
