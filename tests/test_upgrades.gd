extends GutTest

## Unlockable player mechanics + the UpgradePickup that grants them. The in-tree gating (grapple/laser/
## wall-climb/air-dash/slide actually firing or not) is playtested; here we pin the pure unlock-set surface
## on the Player and the pickup's interface. A bare Player (no _ready) starts with an EMPTY set, so we test
## the methods directly without seeding starting_unlocks.

const PLAYER_PATH := "res://scripts/player/player.gd"
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")
const ABILITY_DIR := "res://scenes/components/abilities/"
const FallImmunityScript := preload("res://scripts/components/abilities/fall_immunity.gd")  # loaded by path (no class_name dep)
const SilentTakedownAbilityScript := preload("res://scripts/components/abilities/silent_takedown.gd")  # loaded by path (no class_name dep)


func test_player_unlock_set() -> void:
	var p = load(PLAYER_PATH).new()
	assert_false(p.has_mechanic(&"grapple"), "a gated mechanic is locked until granted")
	p.unlock_mechanic(&"grapple")
	assert_true(p.has_mechanic(&"grapple"), "unlock_mechanic grants the mechanic")
	p.unlock_mechanic(&"grapple")
	assert_eq(p.unlocked_list().size(), 1, "re-granting the same mechanic is a no-op")
	p.set_unlocks([&"fall_immunity", &"wall_climb"])
	assert_true(p.has_mechanic(&"fall_immunity"), "set_unlocks installs the loaded ids")
	assert_false(p.has_mechanic(&"grapple"), "set_unlocks replaces the set, clearing anything not loaded")
	p.free()


func test_player_grant_ability_node() -> void:
	# The drop-in path: a scene-based UpgradePickup hands the player a ready-built Ability NODE, and its presence
	# grants the mechanic -- no string id. AirDash needs no in-tree build (it reads its key off the host beat), so
	# this stays off-tree-safe.
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
	assert_eq(u.look_name(), "[PH] Take Grappling Hook", "the hover readout names the upgrade")
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
	for known in ["air_dash", "grapple", "fall_immunity", "slide", "wall_climb"]:
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
	assert_eq(checked, 11, "expected the 11 shipped ability scenes (AirDash/Grapple/Slide/WallClimb/FallImmunity/ChessVisualizer/SilentTakedown/Bunnyhop/BioScanner/DeepScanner/LaserSight — the laser sight is back, on its own rig node instead of the flashlight's key)")

func test_ability_scripts_covers_registry_ids() -> void:
	# C21 drift guard (post-extraction): every ability id the editor dropdown can suggest (AbilityRegistry, scanned
	# from the scenes on disk) must be RUNTIME-buildable, or a fresh chip install / save load would build null and
	# silently grant nothing. The old Player.ABILITY_SCRIPTS dict is gone — script resolution now derives from the id
	# by the shared snake_case convention (AbilityRegistry.can_build), so this pins the scene<->script naming stays in
	# sync. Disk check, no instantiate.
	for id in AbilityRegistry.ids():
		assert_true(AbilityRegistry.can_build(StringName(id)),
			"AbilityRegistry id '%s' (editor dropdown, from scenes/) must resolve a buildable ability script (naming convention) or a fresh install/save-load can't build it" % id)

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


# --- Fall-immunity upgrade (review HIGH #2): the player takes fall damage unless this upgrade is granted ---

func test_fall_immunity_ability_id() -> void:
	var fi = FallImmunityScript.new()
	assert_eq(fi.ability_id(), &"fall_immunity", "the FallImmunity upgrade grants the fall_immunity mechanic")
	fi.free()


# --- Silent-takedown upgrade: the stealth kill is now an unlockable ability, earned via the Takedown Chip ---

func test_silent_takedown_ability_id() -> void:
	var st = SilentTakedownAbilityScript.new()
	assert_eq(st.ability_id(), &"silent_takedown", "the SilentTakedown upgrade grants the silent_takedown mechanic")
	st.free()

func test_takedown_locked_until_granted_then_persists() -> void:
	# A fresh player can't take anyone down (the behaviour component gates on has_mechanic); installing the chip
	# builds the ability and the mechanic serializes by id like any other, so it survives a save/load.
	var p = load(PLAYER_PATH).new()
	assert_false(p.has_mechanic(&"silent_takedown"), "the stealth kill is locked until the Takedown Chip is installed")
	p.unlock_mechanic(&"silent_takedown")
	assert_true(p.has_mechanic(&"silent_takedown"), "installing the chip grants the silent-takedown mechanic")
	assert_true(p.unlocked_list().has(&"silent_takedown"), "the granted takedown serializes by id (survives a reload)")
	p.free()

func test_player_fall_immunity_skips_fall_damage() -> void:
	# White-box: a granted FallImmunity makes the player's _apply_fall_damage override early-return (before any HP
	# math / take_damage), so a hard landing costs nothing. (The DAMAGING path calls take_damage -> in-tree/playtest.)
	var p = load(PLAYER_PATH).new()
	p.hp = 100.0
	var fi = FallImmunityScript.new()
	p.grant_ability(fi)  # adopt the FallImmunity node through the real grant path (its presence gates immunity)
	p._apply_fall_damage(99.0)  # would be lethal damage without the upgrade
	assert_eq(p.hp, 100.0, "with the fall-immunity upgrade, a hard landing costs no HP")
	p.free()  # frees the granted FallImmunity child too

func test_player_landing_block_wires_fall_damage() -> void:
	# Guards the exact regression that prompted this: the landing block silently never called _apply_fall_damage,
	# so the player took zero fall damage and the inherited knobs were dead. Source-grep so a future refactor
	# can't quietly drop the call again.
	#
	# The touchdown burst moved to the Landing component (M13 residual), so this now pins BOTH links of the chain
	# — Player hands the landing off, and Landing makes the call. Checking only one end would let the other be
	# dropped silently, which is the very failure mode this test exists for.
	var player_src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_true("landing.on_land(pre_landing_velocity, pre_velocity)" in player_src,
		"the player touchdown branch must hand off to the Landing component")
	var landing_src := FileAccess.get_file_as_string("res://scripts/player/landing.gd")
	assert_true("_apply_fall_damage(-pre_landing_velocity)" in landing_src,
		"Landing.on_land must call _apply_fall_damage (it was silently never called once before)")

func test_player_continuous_fall_timeout_wired() -> void:
	var content := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_true("_update_continuous_fall_death(delta)" in content,
		"the player physics loop must tick the continuous-fall timeout so void falls eventually kill")
	assert_true("_die_from_continuous_fall" in content,
		"the continuous-fall timeout must enter the player death/respawn flow")


# ---------------------------------------------------------------------------
# AIR DASH — the look-direction launch, rebound onto its own key (default Left Alt).
#
# It used to be a WEAPON behaviour fired by attacking while scoped, so its only tests were on WeaponData's
# launch_* fields and Attack's source. The verb now lives on the ability node, so the behaviour is pinned here:
# the tuning defaults, the implant gate, the impulse maths, the one-per-airtime lock and its recharge cue.
#
# Driven against a stub host, never a real Player: dash() only needs explosion_velocity + get_aim_direction() +
# is_on_floor(), and a bare Player would drag the whole camera rig in. dash_sound is nulled in every case so the
# assertions don't fire AudioManager off-tree.
# ---------------------------------------------------------------------------

class _DashHost extends Node:
	var explosion_velocity: Vector3 = Vector3.ZERO
	var aim: Vector3 = Vector3.FORWARD
	var on_floor: bool = true
	var granted: bool = true
	var stamina: float = 100.0
	var shake_taken: float = -1.0
	func get_aim_direction() -> Vector3: return aim
	func is_on_floor() -> bool: return on_floor
	func has_mechanic(_id: StringName) -> bool: return granted
	func on_air_dash(trauma: float) -> void: shake_taken = trauma
	func spend_stamina(cost: float, _delay: float = -1.0) -> bool:
		if stamina < cost:
			return false
		stamina -= cost
		return true


func _dash_pair() -> Array:
	var d := AirDash.new()
	d.dash_sound = null
	var h := _DashHost.new()
	d.setup(h)
	return [d, h]


func test_air_dash_tuning_defaults_live_on_the_script() -> void:
	# ⭐The load-bearing one: AbilityManager._build rebuilds a chip-installed / save-loaded ability with
	# load(script).new() and NEVER reads AirDash.tscn, so a default authored only in the scene would install a
	# dead 0-force dash. These are melee.tres's old numbers, carried over so the dash feels unchanged.
	var d := AirDash.new()
	assert_eq(d.ability_id(), &"air_dash", "the id the has_mechanic gate, the chip and the save all key on")
	assert_eq(d.dash_force, 8.0, "dash_force defaults to melee.tres's old launch_force (8.0)")
	assert_eq(d.dash_upward, 4.0, "dash_upward defaults to WeaponData's old launch_upward (4.0)")
	assert_eq(d.screen_shake, 0.6, "screen_shake defaults to the old launch_screen_shake (0.6)")
	assert_eq(d.cooldown, 0.88, "cooldown defaults to the melee attack_speed that used to gate the launch")
	assert_true(d.single_air_dash, "one dash per airtime, as melee.tres authored it")
	assert_not_null(d.dash_sound, "the whoosh is preloaded as the SCRIPT default so a chip install is never silent")
	d.free()


func test_air_dash_launches_along_the_aim() -> void:
	var pair := _dash_pair()
	var d: AirDash = pair[0]
	var h = pair[1]
	h.aim = Vector3(0.0, 0.0, -1.0)
	d.dash()
	assert_eq(h.explosion_velocity, Vector3(0.0, 4.0, -8.0),
		"the dash stacks aim * dash_force plus the straight-up dash_upward onto the blast channel")
	assert_eq(h.shake_taken, 0.6, "the dash hands its OWN trauma to the host — no weapon is involved any more")
	d.free()
	h.free()


func test_air_dash_aims_where_you_look_not_where_you_move() -> void:
	# The whole point of the rebind: look UP and the dash goes UP, with no weapon equipped and no ADS.
	var pair := _dash_pair()
	var d: AirDash = pair[0]
	var h = pair[1]
	h.aim = Vector3(0.0, 1.0, 0.0)
	d.dash()
	assert_almost_eq(h.explosion_velocity.y, 12.0, 0.001,
		"looking straight up dashes straight up (dash_force along the aim, plus the lift)")
	d.free()
	h.free()


func test_air_dash_one_per_airtime_and_recharge() -> void:
	var pair := _dash_pair()
	var d: AirDash = pair[0]
	var h = pair[1]
	h.on_floor = false
	d.dash()
	d._cooldown_left = 0.0  # isolate the airtime lock from the cadence timer
	assert_false(d.can_dash(), "the airborne dash is spent until you land")
	var recharged := [false]
	d.air_dash_recharged.connect(func() -> void: recharged[0] = true)
	h.on_floor = true
	d.tick(0.016)
	assert_true(recharged[0], "landing clears the lock and chirps the recharge cue the Player flashes on")
	assert_true(d.can_dash(), "...and the next airtime gets a fresh dash")
	d.free()
	h.free()


func test_air_dash_cooldown_blocks_and_expires() -> void:
	var pair := _dash_pair()
	var d: AirDash = pair[0]
	var h = pair[1]
	d.dash()
	assert_false(d.can_dash(), "the cooldown blocks an immediate second dash, grounded or not")
	d.tick(d.cooldown)
	assert_true(d.can_dash(), "...and clears once it has run out")
	d.free()
	h.free()


func test_air_dash_refuses_when_the_implant_is_switched_off() -> void:
	# The Implants tab flips `enabled`, which the host's has_mechanic gate reports — the key must go dead, exactly
	# as a switched-off Grapple refuses to fire.
	var pair := _dash_pair()
	var d: AirDash = pair[0]
	var h = pair[1]
	h.granted = false
	assert_false(d.can_dash(), "a switched-off air-dash implant refuses the dash")
	d.on_deactivated()
	assert_false(d._did_air_dash, "switching off hands the airborne dash back, so a re-enable isn't stuck locked")
	d.free()
	h.free()


func test_air_dash_binding_exists_on_all_three_action_surfaces() -> void:
	# project.godot [input] / InputManager's action_* var / the rebindable ActionCatalog — InputManager's boot
	# audit only WARNS about drift between them, so pin the new action here.
	assert_eq(InputManager.action_air_dash, &"AirDash", "action_air_dash canonicalizes the AirDash action")
	assert_true(InputMap.has_action(&"AirDash"), "AirDash must be a real [input] action or the key does nothing")
	var listed := false
	for spec in InputManager.action_catalog().actions:
		if spec.action == &"AirDash":
			listed = true
	assert_true(listed, "AirDash must appear in ActionCatalog.tres or it can't be rebound in Options -> Controls")
