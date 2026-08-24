extends GutTest

## MyLight's electrical hum, specifically the 3D MIX of it.
##
## The regression being pinned: `scenes/levels/Light.tscn`'s emitter shipped with `max_distance = 0` — which
## Godot reads as UNLIMITED, not silent — plus the engine's default air-absorption shelf (5000 Hz / -24 dB).
## With inverse-distance falloff off a ~4 m unit size, a fixture 20 m away still plays only ~14 dB down, so the
## main level's four buzzing fixtures (spaced ~19-23 m apart) summed into a permanent, dull, unlocalised hum a
## few dB under whichever one you were standing beside. It read as "buzzing coming from somewhere outside", and
## it was loudest-feeling INDOORS, where IndoorAmbienceDucker drops the city bed 12 dB and rolls its top end off
## — unmasking the wash the bed had been covering. So MyLight now owns the emitter's mix and bounds it.
##
## These run the fixture in-tree (it is cheap — two lights and one AudioStreamPlayer3D, no nav/weapons/autoload
## churn) because the push happens in `_process`, and off-tree there is no `_process`.

const LIGHT_SCENE := "res://scenes/levels/Light.tscn"

func _spawn_lit_fixture() -> Node3D:
	var fixture: Node3D = load(LIGHT_SCENE).instantiate()
	fixture._range_omni = 5.0        # a fixture that actually emits, so the config-warning path is the buzz one
	fixture._electric_buzz = true
	add_child_autofree(fixture)
	return fixture

func test_the_buzz_emitter_is_bounded_and_local() -> void:
	var fixture := _spawn_lit_fixture()
	await get_tree().process_frame
	await get_tree().process_frame
	var buzz: AudioStreamPlayer3D = fixture.get_node("LightSource/LightBuzz")

	assert_gt(buzz.max_distance, 0.0,
		"the fixture's hum has NO distance limit (0 = unlimited in Godot), so every buzzing light in the level "
		+ "stacks into one map-wide wash — the exact bug that made a light you stand under sound like it is outside")
	assert_almost_eq(buzz.max_distance, fixture.buzz_radius, 0.001,
		"buzz_radius must reach the emitter — MyLight is the single owner of the child's mix")
	assert_almost_eq(buzz.unit_size, fixture.buzz_falloff_distance, 0.001, "buzz_falloff_distance drives unit_size")
	assert_almost_eq(buzz.volume_db, fixture.buzz_volume_db, 0.001, "buzz_volume_db drives the emitter's level")

func test_the_buzz_keeps_its_high_end() -> void:
	# A buzz IS its high harmonics. Godot's attenuation filter shelves everything above `cutoff` down by up to
	# -24 dB as the source recedes; leaving it at the 5000 Hz default is what stripped a nearby fixture of the
	# very frequencies that make it read as "right here" instead of "somewhere else". 20500 Hz = off.
	var fixture := _spawn_lit_fixture()
	await get_tree().process_frame
	var buzz: AudioStreamPlayer3D = fixture.get_node("LightSource/LightBuzz")
	assert_gte(buzz.attenuation_filter_cutoff_hz, 20000.0,
		"the air-absorption shelf is engaged on a fixture hum — it dulls the buzz's harmonics with distance, "
		+ "which is what made a light two metres away sound like it was outdoors")

func test_the_buzz_rides_the_ambient_bus_not_the_muffled_bed() -> void:
	# The roof duck's low-pass is a per-BUS effect on `ambient_bed`, and `ambient_bed` sends INTO `ambient`, so
	# an emitter on `ambient` is upstream of that filter and cannot be muffled by walking under a roof.
	var fixture := _spawn_lit_fixture()
	await get_tree().process_frame
	var buzz: AudioStreamPlayer3D = fixture.get_node("LightSource/LightBuzz")
	assert_eq(buzz.bus, &"ambient", "the fixture hum belongs on the plain `ambient` bus")
	assert_ne(buzz.bus, &"ambient_bed",
		"`ambient_bed` is the bus IndoorAmbienceDucker muffles under a roof — a fixture-local sound must not ride it")

func test_a_zeroed_radius_warns_instead_of_going_global() -> void:
	# A designer clearing the field to mean "silent" would silently re-create the map-wide wash, so the fixture
	# says so in the scene tree rather than waiting for a playtest.
	var fixture := _spawn_lit_fixture()
	fixture.buzz_radius = 0.0
	assert_true(_has_warning(fixture._get_configuration_warnings(), "buzz_radius"),
		"a buzzing fixture with buzz_radius 0 (Godot's 'unlimited') must warn")

func test_a_silent_fixture_does_not_nag_about_its_radius() -> void:
	var fixture := _spawn_lit_fixture()
	fixture._electric_buzz = false
	fixture.buzz_radius = 0.0
	assert_false(_has_warning(fixture._get_configuration_warnings(), "buzz_radius"),
		"a fixture that does not hum has no radius to complain about")

func _has_warning(w: PackedStringArray, needle: String) -> bool:
	for s in w:
		if needle in s:
			return true
	return false
