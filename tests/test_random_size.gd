extends GutTest

## Tests for RandomSize, the dog-size roller. The live dog scene uses it once
## per spawned dog; these pure/off-tree checks pin the size and damage math.

const RandomSize := preload("res://scripts/components/random_size.gd")
const Throwable := preload("res://scripts/components/Throwable.gd")
const DogScene := preload("res://scenes/characters/dog.tscn")
const DogCrateScene := preload("res://scenes/props/dogcrate.tscn")


func test_roll_scale_interpolates_between_bounds() -> void:
	assert_almost_eq(RandomSize.roll_scale(0.75, 1.35, 0.0), 0.75, 0.0001,
		"a zero roll should pick the minimum authored size")
	assert_almost_eq(RandomSize.roll_scale(0.75, 1.35, 0.5), 1.05, 0.0001,
		"a middle roll should land halfway between min and max")
	assert_almost_eq(RandomSize.roll_scale(0.75, 1.35, 1.0), 1.35, 0.0001,
		"a one roll should pick the maximum authored size")


func test_roll_scale_sorts_bounds_and_clamps_roll() -> void:
	assert_almost_eq(RandomSize.roll_scale(1.35, 0.75, -1.0), 0.75, 0.0001,
		"reversed bounds still use the smaller value as the minimum")
	assert_almost_eq(RandomSize.roll_scale(1.35, 0.75, 2.0), 1.35, 0.0001,
		"rolls above one clamp to the maximum")


func test_damage_multiplier_tracks_size_linearly_by_default() -> void:
	assert_almost_eq(RandomSize.damage_mult_for_size(0.8), 0.8, 0.0001,
		"smaller dogs should deal proportionally less impact damage")
	assert_almost_eq(RandomSize.damage_mult_for_size(1.3), 1.3, 0.0001,
		"larger dogs should deal proportionally more impact damage")


func test_pitch_multiplier_inverts_size_by_default() -> void:
	assert_almost_eq(RandomSize.pitch_mult_for_size(0.8), 1.25, 0.0001,
		"smaller dogs should pitch their sounds up")
	assert_almost_eq(RandomSize.pitch_mult_for_size(1.25), 0.8, 0.0001,
		"larger dogs should pitch their sounds down")


func test_apply_size_scales_throwable_and_impact_damage() -> void:
	var dog := Throwable.new()
	dog.scale = Vector3(0.3, 0.3, 0.3)
	dog.impact_damage_mult = 2.0
	dog.sound_pitch_mult = 1.0
	RandomSize.apply_size(dog, 1.25)
	assert_almost_eq(dog.scale.x, 0.375, 0.0001, "the authored X scale is multiplied by the dog size")
	assert_almost_eq(dog.scale.y, 0.375, 0.0001, "the authored Y scale is multiplied by the dog size")
	assert_almost_eq(dog.scale.z, 0.375, 0.0001, "the authored Z scale is multiplied by the dog size")
	assert_almost_eq(dog.impact_damage_mult, 2.5, 0.0001,
		"impact damage keeps any authored multiplier and then scales by dog size")
	assert_almost_eq(dog.sound_pitch_mult, 0.8, 0.0001,
		"vocal sound pitch is inverse to size, so a larger dog sounds lower")
	dog.free()


func test_dog_scene_wires_random_size_component() -> void:
	var dog := DogScene.instantiate()
	var random_size := dog.get_node_or_null("RandomSize")
	assert_not_null(random_size, "dog.tscn should carry the RandomSize component")
	assert_true(random_size is RandomSize, "the dog component should use the RandomSize script")
	dog.free()


func test_spawn_reveal_bark_uses_spawned_dog_pitch() -> void:
	var dog := Throwable.new()
	dog.sound_pitch_mult = 0.8
	assert_almost_eq(SpawnOnDestroy.spawn_sound_pitch(dog), 0.8, 0.0001,
		"the dog-crate reveal bark should inherit the revealed dog's rolled vocal pitch")
	assert_almost_eq(SpawnOnDestroy.spawn_sound_pitch(dog, 1.0, false), 1.0, 0.0001,
		"the spawned pitch hook can be disabled for non-vocal drops")
	dog.free()


func test_dog_crate_moves_reveal_bark_to_spawn_on_destroy() -> void:
	var crate := DogCrateScene.instantiate()
	var throwable := crate.get_node("Throwable") as Throwable
	var spawner := crate.get_node("Throwable/SpawnOnDestroy") as SpawnOnDestroy
	assert_not_null(spawner.spawn_sound,
		"the dog crate reveal bark should play from SpawnOnDestroy after the dog rolls size")
	assert_true(throwable.data.destroy_sound == null,
		"the crate itself should not play an unpitched bark as its destroy sound")
	crate.free()
