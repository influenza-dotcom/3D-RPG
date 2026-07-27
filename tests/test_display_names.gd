extends GutTest

## AUTHORED DISPLAY NAMES over internal ids (the "missing content fields" fix): every player-facing site that
## used to push an id through .capitalize() now reads an authored name first — StatText titles at the dialogue
## stat gate, Faction.display_name on the rep toasts, Ability.display_name behind AbilityRegistry, and
## Perk.display_name behind the new Perks registry — and a blank/missing name DEGRADES to the same capitalized
## id as before, never to a blank. Prose-agnostic like test_stat_text.gd: authored values are asserted VERBATIM
## against the resource/scene fields (the wording belongs to the designer); only the FALLBACK shape is pinned
## as literal bytes.

const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")
const Perks := preload("res://scripts/player/perks.gd")
const Factions := preload("res://scripts/faction/factions.gd")


# --- abilities: Ability.display_name authored per scene, read by id via AbilityRegistry ---------------------

func test_ability_display_names_authored_and_read_through() -> void:
	var ids := AbilityRegistry.ids()
	assert_gt(ids.size(), 0, "ability scenes exist on disk to name")
	for id in ids:
		var path := AbilityRegistry.scene_path_for(StringName(id))
		assert_true(ResourceLoader.exists(path),
			"scene_path_for('%s') must invert the ids() snake_case derivation (to_pascal_case roundtrip) — else display_name_for can't find the scene" % id)
		if not ResourceLoader.exists(path):
			continue
		var inst := (load(path) as PackedScene).instantiate()  # off-tree, no add_child — the test_upgrades drift-guard idiom
		var authored := String(inst.get("display_name"))
		inst.free()
		assert_false(authored.is_empty(),
			"ability scene %s must author a display_name — the upgrade-chip tooltip names the mechanic through it" % path)
		assert_eq(AbilityRegistry.display_name_for(StringName(id)), authored,
			"display_name_for('%s') returns the scene's authored display_name VERBATIM (whatever the designer wrote)" % id)


func test_ability_display_name_falls_back_to_capitalized_id() -> void:
	assert_eq(AbilityRegistry.display_name_for(&"rocket_boots_xyz"), "Rocket Boots Xyz",
		"an id with no ability scene degrades to the capitalized id — the pre-authoring look, never a blank")
	assert_eq(AbilityRegistry.display_name_for(&""), "", "a blank id has nothing to name")


# --- factions: Faction.display_name wins on the rep/alignment toasts --------------------------------------

func test_faction_toast_name_prefers_authored_display_name() -> void:
	var ids := Factions.ids()
	assert_gt(ids.size(), 0, "faction resources exist on disk to name")
	for id in ids:
		var fac: Faction = Factions.by_id(id)
		assert_not_null(fac, "faction id '%s' resolves" % id)
		if fac == null:
			continue
		assert_false(fac.display_name.is_empty(),
			"faction %s must author a display_name — rep toasts and the reputation screen read it" % id)
		assert_eq(UI._faction_name(fac), fac.display_name,
			"UI._faction_name returns the authored display_name VERBATIM for '%s'" % id)


func test_faction_name_blank_display_falls_back_to_capitalized_id() -> void:
	var fac := Faction.new()
	fac.id = &"neutral_wildlife"  # display_name deliberately left blank
	assert_eq(UI._faction_name(fac), "Neutral Wildlife",
		"a faction without an authored display_name degrades to the capitalized id — never a blank toast")
	fac = null


# --- perks: Perk.display_name behind the id-keyed Perks registry ------------------------------------------

func test_perk_display_label_prefers_authored_name_verbatim() -> void:
	var p := load("res://resources/perks/tough_hide.tres") as Perk
	assert_not_null(p, "the shipped tough_hide perk exists")
	if p == null:
		return
	assert_false(p.display_name.is_empty(), "tough_hide authors a display_name")
	assert_eq(Perks.display_label(&"tough_hide"), p.display_name,
		"display_label returns the authored Perk.display_name VERBATIM ([PH] marker included — composition sites strip it)")
	assert_eq(Perks.by_id(&"tough_hide"), p,
		"by_id resolves the .tres by the id==filename convention (resource-loader cached, so the same instance)")


func test_perk_display_label_falls_back_to_raw_id() -> void:
	assert_eq(Perks.display_label(&"ghost_perk_xyz"), "ghost_perk_xyz",
		"an id with no perk .tres degrades to the raw id — PlayerText.requires_perk detects the id-echo and capitalizes it itself, preserving the pre-authoring toast")
	assert_null(Perks.by_id(&""), "a blank id resolves to null, silently")


# --- dialogue: the stat-gate choice label routes through StatInfo.title -----------------------------------

func test_dialogue_stat_gate_label_routes_through_stat_info_title() -> void:
	assert_eq(DialogueView.stat_gate_label(&"strength", 6, "Threaten him"),
		"[%s 6] Threaten him" % StatInfo.title(&"strength"),
		"the stat-gate choice button shows the SAME authored StatText title as the stats screen")
	assert_eq(DialogueView.stat_gate_label(&"charisma", 3, "Charm"), "[Charisma 3] Charm",
		"an unauthored stat id degrades to the capitalized fallback inside StatInfo.title — never a blank gate tag")
	# Source pin: today's authored titles EQUAL the old capitalize output, so bytes alone can't prove the routing —
	# assert the view reads StatInfo.title and the old local capitalize bypass hasn't crept back.
	var src := FileAccess.get_file_as_string("res://scripts/dialogue/dialogue_view.gd")
	assert_true(src.contains("StatInfo.title("), "dialogue_view.gd routes the gate label through StatInfo.title")
	assert_false(src.contains("required_stat).capitalize()"),
		"the capitalized-id bypass must not return to dialogue_view.gd (the authored title is the one stat name)")
