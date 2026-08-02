extends GutTest

## Pure-logic coverage for pickup item lights (no tree, no autoloads): the item -> Kind classifier, the loot-sack
## count -> scale curve, and the per-kind palette. The visual build is runtime-only and verified by playtest -- see
## scripts/components/pickup_beacon.gd.

const BeaconSettings = preload("res://resources/tuning/PickupBeaconSettings.gd")

# --- kind_for_item: most-specific role wins ---

func _item(category: int) -> Item:
	var it := Item.new()
	it.category = category
	return it

func test_kind_weapon() -> void:
	var it := _item(Item.Category.WEAPON)
	it.weapon = WeaponData.new()
	assert_eq(PickupBeacon.kind_for_item(it), PickupBeacon.Kind.WEAPON, "a WEAPON item with WeaponData -> WEAPON")
	it = null

func test_kind_ammo() -> void:
	var it := _item(Item.Category.AMMO)
	it.caliber = &"9mm"
	assert_eq(PickupBeacon.kind_for_item(it), PickupBeacon.Kind.AMMO, "an AMMO item with a caliber -> AMMO")
	it = null

func test_kind_consumable() -> void:
	var it := _item(Item.Category.CONSUMABLE)
	assert_eq(PickupBeacon.kind_for_item(it), PickupBeacon.Kind.CONSUMABLE, "a CONSUMABLE item -> CONSUMABLE")
	it = null

func test_kind_chip_beats_everything() -> void:
	# A microchip upgrade is classified CHIP even though its category is MISC (installs_ability is the tell).
	var it := _item(Item.Category.MISC)
	it.installs_ability = &"wall_climb"
	assert_eq(PickupBeacon.kind_for_item(it), PickupBeacon.Kind.CHIP, "installs_ability -> CHIP regardless of category")
	it = null

func test_kind_passive_from_held_effect() -> void:
	# The Chrome Grin idiom: MISC category, but a held_passive_effect makes it a PASSIVE buff item.
	var it := _item(Item.Category.MISC)
	it.held_passive_effect = StatusEffect.new()
	assert_eq(PickupBeacon.kind_for_item(it), PickupBeacon.Kind.PASSIVE, "held_passive_effect -> PASSIVE")
	it = null

func test_kind_plain_misc() -> void:
	assert_eq(PickupBeacon.kind_for_item(_item(Item.Category.MISC)), PickupBeacon.Kind.MISC, "bare item -> MISC")

func test_kind_null_is_misc() -> void:
	assert_eq(PickupBeacon.kind_for_item(null), PickupBeacon.Kind.MISC, "null item -> MISC (never crashes)")

# --- fade_amount: 0 near, ramps to 1 far ---

func test_fade_off_when_close() -> void:
	assert_eq(PickupBeacon.fade_amount(1.0, 3.0, 9.0), 0.0, "inside near_distance -> fully off")

func test_fade_full_when_far() -> void:
	assert_eq(PickupBeacon.fade_amount(20.0, 3.0, 9.0), 1.0, "beyond full_distance -> fully on")

func test_fade_midpoint() -> void:
	assert_almost_eq(PickupBeacon.fade_amount(6.0, 3.0, 9.0), 0.5, 0.0001, "halfway between near and full -> 0.5")

func test_fade_degenerate_range_is_step() -> void:
	# full <= near collapses to a hard step at full_distance (no divide-by-zero).
	assert_eq(PickupBeacon.fade_amount(5.0, 9.0, 9.0), 0.0, "below the step -> 0")
	assert_eq(PickupBeacon.fade_amount(9.0, 9.0, 9.0), 1.0, "at/above the step -> 1")

# --- brightness_for: the full policy, including the always-lit override ---

func test_brightness_follows_the_fade_for_a_normal_light() -> void:
	assert_eq(PickupBeacon.brightness_for(false, 1.0, 3.0, 9.0, 0.0), 0.0, "normal light inside near_distance -> off")
	assert_eq(PickupBeacon.brightness_for(false, 20.0, 3.0, 9.0, 0.0), 1.0, "normal light past full_distance -> on")

func test_brightness_normal_light_is_culled_past_max_distance() -> void:
	assert_eq(PickupBeacon.brightness_for(false, 40.0, 3.0, 9.0, 25.0), 0.0, "past the hard cull -> off")

func test_always_lit_ignores_the_near_fade() -> void:
	# THE point of always_lit: a weapon in your hands sits ~1 m away, deep inside near_distance, where a normal item
	# light is fully dark. That is why a carried knife had no glow at all.
	assert_eq(PickupBeacon.brightness_for(true, 1.0, 3.0, 9.0, 0.0), 1.0, "always-lit at arm's length -> full brightness")
	assert_eq(PickupBeacon.brightness_for(true, 0.0, 3.0, 9.0, 0.0), 1.0, "always-lit at zero distance -> full brightness")

func test_always_lit_also_beats_the_hard_cull() -> void:
	# Deliberate: the other thing an always-lit weapon light must stay visible for is the knife you just threw across
	# the yard, which can land past a configured max_distance.
	assert_eq(PickupBeacon.brightness_for(true, 40.0, 3.0, 9.0, 25.0), 1.0, "always-lit is not culled by max_distance")

func test_always_lit_light_is_still_gated_by_the_player_toggle() -> void:
	# Not a brightness_for concern (the Options row is checked before it in _process) — pinned here so the contract is
	# stated where the policy lives: an always-lit weapon glow is still an ITEM LIGHT and honours Loot Beacons.
	var old_enabled := Settings.loot_beacons_enabled
	Settings.loot_beacons_enabled = false
	var host := Node3D.new()
	add_child_autofree(host)
	var marker := PickupBeacon.attach_kind(host, PickupBeacon.Kind.WEAPON, true)
	assert_not_null(marker, "attach_kind takes the always-lit flag")
	if marker != null:
		assert_true(marker.always_lit, "the flag reaches the spawned light")
		marker._process(0.016)
		var lights := marker.find_children("*", "OmniLight3D", true, false)
		if lights.size() > 0:
			assert_false((lights[0] as OmniLight3D).visible, "Loot Beacons off hides an always-lit light too")
	Settings.loot_beacons_enabled = old_enabled

func test_always_lit_light_burns_at_full_energy_with_no_player_in_range() -> void:
	# The always-lit path never looks the player up at all, so the glow survives with no player resolvable (a knife
	# still in flight while the player dies / a level reloads).
	var pal := GameSettings.pickup_beacons
	var old_energy := pal.light_energy
	var old_scale := pal.always_lit_energy_scale
	var old_enabled := Settings.loot_beacons_enabled
	pal.light_energy = 2.0
	pal.always_lit_energy_scale = 0.5
	Settings.loot_beacons_enabled = true

	var host := Node3D.new()
	add_child_autofree(host)
	var marker := PickupBeacon.attach_kind(host, PickupBeacon.Kind.WEAPON, true)
	if marker != null:
		marker._process(0.016)
		var lights := marker.find_children("*", "OmniLight3D", true, false)
		assert_eq(lights.size(), 1, "an always-lit marker still builds exactly one OmniLight3D")
		if lights.size() > 0:
			var light := lights[0] as OmniLight3D
			assert_almost_eq(light.light_energy, 1.0, 0.0001,
				"always-lit energy = light_energy * always_lit_energy_scale, with no distance fade applied")
			assert_true(light.visible, "an always-lit light is visible with no player anywhere near")
			assert_almost_eq(light.position.y, 0.0, 0.0001,
				"an always-lit light sits ON the prop — the ground-pickup lift would swing around and trail a thrown blade")

	Settings.loot_beacons_enabled = old_enabled
	pal.light_energy = old_energy
	pal.always_lit_energy_scale = old_scale

# --- bag_scale_for: fuller sack -> brighter item light ---

func test_bag_scale_min_at_one() -> void:
	var s := BeaconSettings.new()
	assert_almost_eq(s.bag_scale_for(1), s.bag_min_scale, 0.0001, "a single stack -> min scale")
	s = null

func test_bag_scale_max_at_cap() -> void:
	var s := BeaconSettings.new()
	assert_almost_eq(s.bag_scale_for(s.bag_count_for_max), s.bag_max_scale, 0.0001, "count_for_max stacks -> max scale")
	assert_almost_eq(s.bag_scale_for(s.bag_count_for_max + 5), s.bag_max_scale, 0.0001, "over the cap clamps to max")
	s = null

func test_bag_scale_monotonic_between() -> void:
	var s := BeaconSettings.new()
	var lo := s.bag_scale_for(2)
	var hi := s.bag_scale_for(6)
	assert_gt(hi, lo, "more stacks -> a brighter item light")
	s = null

# --- color_for_kind: every concrete kind maps to its palette entry ---

func test_palette_maps_each_kind() -> void:
	var s := BeaconSettings.new()
	assert_eq(s.color_for_kind(PickupBeacon.Kind.WEAPON), s.weapon_color, "WEAPON -> weapon_color")
	assert_eq(s.color_for_kind(PickupBeacon.Kind.AMMO), s.ammo_color, "AMMO -> ammo_color")
	assert_eq(s.color_for_kind(PickupBeacon.Kind.PASSIVE), s.passive_color, "PASSIVE -> passive_color")
	assert_eq(s.color_for_kind(PickupBeacon.Kind.MONEY), s.money_color, "MONEY -> money_color")
	assert_eq(s.color_for_kind(PickupBeacon.Kind.LOOT_BAG), s.loot_bag_color, "LOOT_BAG -> loot_bag_color")
	assert_eq(s.color_for_kind(PickupBeacon.Kind.MISC), s.misc_color, "MISC -> misc_color")
	assert_eq(s.color_for_kind(PickupBeacon.Kind.AUTO), s.misc_color, "AUTO falls through to misc_color")
	s = null

# --- runtime build: light only, no beacon mesh ---

func test_runtime_builds_item_light_without_mesh_beacon() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var marker := PickupBeacon.attach_kind(host, PickupBeacon.Kind.MONEY)
	assert_not_null(marker, "attach_kind returns the spawned pickup light node")
	if marker == null:
		return
	var lights := marker.find_children("*", "OmniLight3D", true, false)
	var meshes := marker.find_children("*", "MeshInstance3D", true, false)
	assert_eq(lights.size(), 1, "a pickup marker builds exactly one OmniLight3D")
	assert_eq(meshes.size(), 0, "a pickup marker builds no mesh shaft / beacon geometry")
	if lights.size() > 0:
		assert_eq((lights[0] as Node).name, &"PickupLight", "the child light is named as an item light")

func test_runtime_light_energy_follows_distance_fade() -> void:
	var pal := GameSettings.pickup_beacons
	var old_energy := pal.light_energy
	var old_range := pal.light_range
	var old_near := pal.near_distance
	var old_full := pal.full_distance
	var old_max := pal.max_distance
	var old_enabled := Settings.loot_beacons_enabled
	pal.light_energy = 2.0
	pal.light_range = 3.0
	pal.near_distance = 3.0
	pal.full_distance = 9.0
	pal.max_distance = 0.0
	Settings.loot_beacons_enabled = true

	var host := Node3D.new()
	add_child_autofree(host)
	var player := Node3D.new()
	add_child_autofree(player)
	var marker := PickupBeacon.attach_kind(host, PickupBeacon.Kind.MONEY)
	var light: OmniLight3D = null
	if marker != null:
		var lights := marker.find_children("*", "OmniLight3D", true, false)
		if lights.size() > 0:
			light = lights[0] as OmniLight3D
	assert_not_null(light, "runtime marker exposes the item OmniLight3D")

	if marker != null and light != null:
		marker.global_position = Vector3.ZERO
		marker._player = player
		marker._find_cd = 999.0

		player.global_position = Vector3(1.0, 0.0, 0.0)
		marker._process(0.016)
		assert_almost_eq(light.light_energy, 0.0, 0.0001, "near player -> light energy fades fully off")
		assert_false(light.visible, "near player -> item light hides")

		player.global_position = Vector3(6.0, 0.0, 0.0)
		marker._process(0.016)
		assert_almost_eq(light.light_energy, 1.0, 0.0001, "mid fade distance -> half light energy")
		assert_true(light.visible, "mid fade distance -> item light is visible")

		player.global_position = Vector3(20.0, 0.0, 0.0)
		marker._process(0.016)
		assert_almost_eq(light.light_energy, 2.0, 0.0001, "far player -> full light energy")

	Settings.loot_beacons_enabled = old_enabled
	pal.light_energy = old_energy
	pal.light_range = old_range
	pal.near_distance = old_near
	pal.full_distance = old_full
	pal.max_distance = old_max
