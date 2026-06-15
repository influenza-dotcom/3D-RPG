extends GutTest

## Unlockable player mechanics + the UpgradePickup that grants them. The in-tree gating (grapple/laser/
## wall-climb/air-dash/slide actually firing or not) is playtested; here we pin the pure unlock-set surface
## on the Player and the pickup's interface. A bare Player (no _ready) starts with an EMPTY set, so we test
## the methods directly without seeding starting_unlocks.

const PLAYER_PATH := "res://scripts/player/player.gd"


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
