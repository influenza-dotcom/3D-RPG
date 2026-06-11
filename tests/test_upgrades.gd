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


func test_upgrade_pickup_surface() -> void:
	var u := UpgradePickup.new()
	u.unlock_id = &"grapple"
	u.display_name = "Grappling Hook"
	assert_eq(u.look_name(), "Take Grappling Hook", "the hover readout names the upgrade")
	assert_true(u.can_be_talked_to(), "an upgrade with an unlock_id is interactable")
	u.unlock_id = &""
	assert_false(u.can_be_talked_to(), "an upgrade with no unlock_id is inert")
	u.free()


func test_upgrade_pickup_builds_emblem() -> void:
	var u := UpgradePickup.new()
	var e := u._default_emblem()
	assert_not_null(e.mesh, "the fallback emblem carries a mesh, so a bare UpgradePickup is visible in the world")
	e.free()
	u.free()
