extends GutTest

## Unlockable player mechanics + the UpgradePickup that grants them. The in-tree gating (grapple/laser/
## wall-climb/air-dash/slide actually firing or not) is playtested; here we pin the pure unlock-set surface
## on the Player and the pickup's interface. A bare Player (no _ready) starts with an EMPTY set, so we test
## the methods directly without seeding starting_unlocks.

const PLAYER_PATH := "res://scripts/player/player.gd"
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")
const ABILITY_DIR := "res://scenes/components/abilities/"


func test_player_unlock_set() -> void:
	var p = load(PLAYER_PATH).new()
	assert_false(p.has_mechanic(&"grapple"), "a gated mechanic is locked until granted")
	p.unlock_mechanic(&"grapple")
	assert_true(p.has_mechanic(&"grapple"), "unlock_mechanic grants the mechanic")
	p.unlock_mechanic(&"grapple")
	assert_eq(p.unlocked_list().size(), 1, "re-granting the same mechanic is a no-op")
	p.set_unlocks([&"laser_sight", &"wall_climb"])
	assert_true(p.has_mechanic(&"laser_sight"), "set_unlocks installs the loaded ids")
	assert_false(p.has_mechanic(&"grapple"), "set_unlocks replaces the set, clearing anything not loaded")
	p.free()


func test_player_grant_ability_node() -> void:
	# The drop-in path: a scene-based UpgradePickup hands the player a ready-built Ability NODE, and its presence
	# grants the mechanic -- no string id. AirDash is a pure gate (no in-tree build), so this is off-tree-safe.
	var p = load(PLAYER_PATH).new()
	assert_false(p.has_mechanic(&"air_dash"), "a gated mechanic is locked until granted")
	p.grant_ability(AirDash.new())
	assert_true(p.has_mechanic(&"air_dash"), "grant_ability adopts the node so its presence grants the mechanic")
	assert_eq(p.unlocked_list().size(), 1, "the granted ability serializes by id like any other")
	p.grant_ability(AirDash.new())
	assert_eq(p.unlocked_list().size(), 1, "granting an ability already present is a no-op (no stacked duplicate)")
	p.free()


func test_upgrade_pickup_surface() -> void:
	var u := UpgradePickup.new()
	u.display_name = "Grappling Hook"
	assert_eq(u.look_name(), "Take Grappling Hook", "the hover readout names the upgrade")
	assert_false(u.can_be_talked_to(), "a bare pickup (no scene, no unlock_id) is inert")
	u.unlock_id = &"grapple"
	assert_true(u.can_be_talked_to(), "a legacy unlock_id still makes a pickup interactable")
	u.unlock_id = &""
	u.grants = PackedScene.new()
	assert_true(u.can_be_talked_to(), "a pickup holding an ability scene is pickable without any string id")
	u.free()


func test_upgrade_pickup_builds_emblem() -> void:
	var u := UpgradePickup.new()
	var e := u._default_emblem()
	assert_not_null(e.mesh, "the fallback emblem carries a mesh, so a bare UpgradePickup is visible in the world")
	e.free()
	u.free()


func test_grapple_ability_offtree_grants_without_hook() -> void:
	# The Grapple ability OWNS the GrappleHook, but only builds it in-tree (the rope/visuals need the live
	# camera/muzzle rig). Off-tree (a bare unit-test grant) the GATE works while the hook stays absent — and
	# the physics-beat forwarders must null-guard it rather than crash.
	var p = load(PLAYER_PATH).new()
	var g := Grapple.new()
	assert_eq(g.ability_id(), &"grapple", "the Grapple ability grants the grapple mechanic")
	g.setup(p)  # off-tree -> no GrappleHook build
	assert_false(g.is_attached(), "no hook off-tree -> never attached")
	g.apply_pull(0.016)  # must no-op safely with no hook
	g.free()
	p.free()


# --- AbilityRegistry: the unlock_id dropdown self-populated from the ability scenes on disk ---

## First entry in get_property_list() whose name matches, else {}.
func _property(obj: Object, prop_name: String) -> Dictionary:
	for p in obj.get_property_list():
		if p.get("name", "") == prop_name:
			return p
	return {}

func test_ability_registry_scans_disk_sorted() -> void:
	var ids := AbilityRegistry.ids()
	assert_true(ids.size() >= 5, "AbilityRegistry.ids() must find the shipped ability scenes under %s" % ABILITY_DIR)
	for known in ["air_dash", "grapple", "laser_sight", "slide", "wall_climb"]:
		assert_true(ids.has(known), "AbilityRegistry.ids() must include shipped mechanic '%s'" % known)
	var resorted := Array(ids).duplicate()
	resorted.sort()
	assert_eq(Array(ids), resorted, "AbilityRegistry.ids() must be sorted so the dropdown order is stable")

func test_ability_scene_filename_matches_ability_id() -> void:
	# The registry snake-cases the scene FILENAME to get the mechanic id; pin that convention against each
	# ability's real ability_id(), so a future scene whose name doesn't match its id (which would make the
	# unlock_id dropdown suggest a wrong id) fails loudly here. Instanced off-tree (.instantiate, no add_child).
	var dir := DirAccess.open(ABILITY_DIR)
	assert_not_null(dir, "the ability scene folder must exist")
	if dir == null:
		return
	var checked := 0
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		var scene := load(ABILITY_DIR + f) as PackedScene
		assert_not_null(scene, "ability scene '%s' must load" % f)
		if scene == null:
			continue
		var inst := scene.instantiate()
		assert_true(inst is Ability, "ability scene '%s' root must be an Ability" % f)
		if inst is Ability:
			checked += 1
			assert_eq(String((inst as Ability).ability_id()), f.trim_suffix(".tscn").to_snake_case(),
				"ability scene '%s' filename must snake-case to its ability_id() (the unlock_id dropdown relies on it)" % f)
		inst.free()
	assert_eq(checked, 5, "expected the 5 shipped ability scenes (AirDash/Grapple/LaserSight/Slide/WallClimb)")

func test_upgrade_unlock_id_dropdown_is_dynamic() -> void:
	# UpgradePickup is @tool with _validate_property, so unlock_id's dropdown is built from disk (AbilityRegistry)
	# at property-list time -- no hand-maintained suggestion list. Built off-tree (no add_child -> no _ready).
	var u := UpgradePickup.new()
	var p := _property(u, "unlock_id")
	assert_false(p.is_empty(), "UpgradePickup must expose an unlock_id property")
	assert_eq(p.get("hint", -1), PROPERTY_HINT_ENUM_SUGGESTION,
		"unlock_id must be a PROPERTY_HINT_ENUM_SUGGESTION dropdown (set in _validate_property)")
	assert_eq(p.get("hint_string", ""), AbilityRegistry.ids_csv(),
		"unlock_id dropdown must auto-populate from disk (AbilityRegistry.ids_csv) -- no hand-maintained list")
	u.free()
