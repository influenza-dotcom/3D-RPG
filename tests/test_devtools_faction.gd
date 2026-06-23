extends GutTest

## Faction-matrix dock: PURE round-trip on the relation helpers + a construct smoke test. Instantiating the dock
## forces GDScript to compile the WHOLE script (catching errors --import misses for addon-only scripts). The
## relation helpers are tested on throwaway Faction.new()s with NO disk write and NO EditorInterface, exactly the
## code path a cell edit uses MINUS ResourceSaver.save().

const FactionMatrix := preload("res://addons/cybersunday_tools/dock_faction/faction_matrix.gd")


func _faction(id: String) -> Faction:
	var f := Faction.new()
	f.id = StringName(id)
	f.display_name = id.capitalize()
	return f


func test_faction_dock_constructs() -> void:
	var d = FactionMatrix.new()
	assert_not_null(d, "faction dock should construct (compiles + builds its grid off-tree)")
	assert_eq(d.name, "Factions", "dock tab name")
	d.free()


func test_set_relation_round_trips_enemy() -> void:
	var a := _faction("raiders")
	var b := _faction("townsfolk")
	FactionMatrix.set_relation(a, b, -1.0)
	assert_eq(FactionMatrix.get_relation(a, b), -1.0, "enemy relation reads back")
	# The relation is stored under b.id, matching Faction.relation_to.
	assert_eq(a.relation_to(StringName("townsfolk")), -1.0, "stored under the other faction's id")
	a = null
	b = null


func test_set_relation_round_trips_ally() -> void:
	var a := _faction("raiders")
	var b := _faction("ncr")
	FactionMatrix.set_relation(a, b, 1.0)
	assert_eq(FactionMatrix.get_relation(a, b), 1.0, "ally relation reads back")
	a = null
	b = null


func test_neutral_clears_the_entry() -> void:
	var a := _faction("raiders")
	var b := _faction("townsfolk")
	FactionMatrix.set_relation(a, b, -1.0)
	assert_true(a.relations.has(StringName("townsfolk")), "non-neutral relation is stored")
	FactionMatrix.set_relation(a, b, 0.0)
	assert_false(a.relations.has(StringName("townsfolk")), "neutral (0.0) clears the entry, keeping the .tres clean")
	assert_eq(FactionMatrix.get_relation(a, b), 0.0, "neutral reads back as 0.0 (relation_to default)")
	a = null
	b = null


func test_set_relation_is_directional() -> void:
	var a := _faction("raiders")
	var b := _faction("townsfolk")
	FactionMatrix.set_relation(a, b, -1.0)
	assert_eq(FactionMatrix.get_relation(a, b), -1.0, "a -> b is set")
	assert_eq(FactionMatrix.get_relation(b, a), 0.0, "b -> a is independent (directional, not mirrored)")
	a = null
	b = null


func test_set_relation_noops_on_nulls_and_empty_id() -> void:
	var a := _faction("raiders")
	var blank := Faction.new()  # empty id
	FactionMatrix.set_relation(a, blank, -1.0)
	assert_eq(a.relations.size(), 0, "an empty-id target writes nothing (no &\"\" key)")
	FactionMatrix.set_relation(null, a, -1.0)  # must not crash
	assert_eq(FactionMatrix.get_relation(null, a), 0.0, "null read is neutral")
	a = null
	blank = null


func test_bucket_for_maps_score_to_option_index() -> void:
	assert_eq(FactionMatrix.bucket_for(-1.0), 0, "<0 => Enemy")
	assert_eq(FactionMatrix.bucket_for(-0.25), 0, "any negative => Enemy")
	assert_eq(FactionMatrix.bucket_for(0.0), 1, "0 => Neutral")
	assert_eq(FactionMatrix.bucket_for(1.0), 2, ">0 => Ally")
	assert_eq(FactionMatrix.bucket_for(0.5), 2, "any positive => Ally")
