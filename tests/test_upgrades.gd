extends GutTest

## Unlockable player mechanics + the UpgradePickup that grants them. The in-tree gating (grapple/laser/
## wall-climb/air-dash/slide actually firing or not) is playtested; here we drive the unlock set, the grant and
## save/load paths, the fall-damage and void-fall gates and the AirDash verb on off-tree actors. A bare Player
## (no _ready) starts with an EMPTY set, so we test the methods directly without seeding starting_unlocks.

const PLAYER_PATH := "res://scripts/player/player.gd"
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")
const ABILITY_DIR := "res://scenes/components/abilities/"
const FallImmunityScript := preload("res://scripts/components/abilities/fall_immunity.gd")  # loaded by path (no class_name dep)
## The item a ChipInstaller installs to grant the stealth kill.
const TAKEDOWN_CHIP := "res://resources/items/chip_takedown.tres"
## A landing speed (m/s) far past any lethal fall the shipped fall-damage profile allows, so a landing that bills
## nothing proves a gate — never a soft profile.
const LETHAL_FALL := 99.0
## A hard touchdown speed (m/s), past the shipped safe landing speed, so it costs HP (the test asserts it does).
const HARD_LANDING := 30.0


## An off-tree Player whose two death-flow exits are LEDGERS instead of the real thing: take_damage (the HP hit a
## landing bills — the real one reaches the HUD / sky flash / hurt feedback, which need the live prefab) and
## _die_from_continuous_fall (the death sequence needs the tree). Everything that DECIDES whether those fire — the
## fall-immunity gate, FallDamage, Landing.on_land, the void-fall timer — is the real production code.
class _LedgerPlayer extends Player:
	var damage_taken: Array[float] = []
	var void_deaths: Array[float] = []
	var on_wall: bool = false
	func take_damage(amount: float, _was_crit: bool = false, _attacker: Node = null, _hit_pos: Vector3 = Vector3.INF) -> void:
		damage_taken.append(amount)
	func _die_from_continuous_fall(fall_speed: float) -> void:
		void_deaths.append(fall_speed)
		_dying = true  # what the real death sequence latches first
	func is_climbing() -> bool:
		return on_wall


## Shared tuning some tests move — the Landing test parks the land-SFX / dust thresholds out of reach (those channels
## read global_position, which errors off-tree) and the void-fall test zeroes the budget. Restored after every test.
var _saved_land_sfx_min: float = 0.0
var _saved_dust_min: float = 0.0
var _saved_void_limit: float = 0.0


func before_each() -> void:
	_saved_land_sfx_min = GameSettings.audio.land_sfx_min_impact_to_play
	_saved_dust_min = GameSettings.effects.dust_land_min_impact_to_spawn
	_saved_void_limit = GameSettings.player_movement.max_continuous_fall_time


func after_each() -> void:
	GameSettings.audio.land_sfx_min_impact_to_play = _saved_land_sfx_min
	GameSettings.effects.dust_land_min_impact_to_spawn = _saved_dust_min
	GameSettings.player_movement.max_continuous_fall_time = _saved_void_limit


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
	assert_true(u.look_name().contains("Grappling Hook"), "the hover readout must name the upgrade the player is about to take")
	u.display_name = "Fall Immunity"
	assert_true(u.look_name().contains("Fall Immunity") and not u.look_name().contains("Grappling Hook"),
		"the hover readout must follow the authored display_name, not a name baked in at build time")
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
	assert_true(p.grant_ability(g), "an off-tree grant must still adopt the Grapple node")  # off-tree -> no GrappleHook build
	assert_true(p.has_mechanic(&"grapple"), "the grapple GATE must open on an off-tree grant even though the hook is never built")
	assert_false(g.is_attached(), "no hook off-tree -> never attached")
	assert_false(p.is_grappling(), "...and the player never reads as grappling")
	p.velocity = Vector3(1.0, -2.0, 3.0)
	g.apply_pull(0.016)  # the physics-beat forwarder must null-guard the missing hook (an engine error fails this test)
	assert_eq(p.velocity, Vector3(1.0, -2.0, 3.0), "with no hook there is no rope to yank: the pull must leave the player's velocity alone")
	p.free()  # frees the adopted Grapple child too


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
	assert_gt(checked, 0, "the ability scene folder must hold at least one Ability scene, or this convention check proved nothing")
	assert_eq(checked, AbilityRegistry.ids().size(),
		"every scene the registry offers in the unlock_id dropdown must have an Ability root that was checked above — none may be silently skipped")

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


func test_player_starting_unlocks_dropdown_covers_registry() -> void:
	# Player.starting_unlocks is the ONE ability dropdown that is still a hand-kept @export_enum (Player is not
	# @tool, so it cannot self-populate the way UpgradePickup.unlock_id does above). It drifted once: laser_sight
	# shipped as an ability scene while the dropdown never offered it. Pin the hand-kept list to the scenes on
	# disk in BOTH directions. Bare Player.new(), off-tree, no _ready (the CLAUDE.md rule); the typed-array enum
	# hint reads "<type>/<hint>:<csv>", so the ids are everything after the first colon.
	var player := Player.new()
	var p := _property(player, "starting_unlocks")
	player.free()
	assert_false(p.is_empty(), "Player must expose a starting_unlocks property")
	var hint := String(p.get("hint_string", ""))
	var csv := hint.substr(hint.find(":") + 1) if hint.find(":") >= 0 else hint
	var offered := PackedStringArray(csv.split(","))
	offered.sort()
	var on_disk := AbilityRegistry.ids()
	for id in on_disk:
		assert_true(offered.has(id),
			"ability scene '%s' exists under scenes/components/abilities/ but Player.starting_unlocks' @export_enum does not offer it -- add it to the hand-kept list in player.gd" % id)
	for id in offered:
		assert_true(on_disk.has(id),
			"Player.starting_unlocks offers '%s' but no ability scene of that name exists on disk -- a fresh game picking it would build nothing" % id)

# --- Fall-immunity upgrade (review HIGH #2): the player takes fall damage unless this upgrade is granted ---

func test_player_fall_immunity_skips_fall_damage() -> void:
	# A granted FallImmunity makes the player's _apply_fall_damage override bail before any HP math, so a hard landing
	# costs nothing. The CONTROL comes first: the identical landing on a player WITHOUT the implant must bill damage,
	# or the immunity assert below would stay green on a fall-damage path that bills nobody.
	var control := _LedgerPlayer.new()
	control._apply_fall_damage(LETHAL_FALL)
	assert_eq(control.damage_taken.size(), 1, "control: without the implant this landing must bill fall damage exactly once")
	if control.damage_taken.size() == 1:
		assert_gt(control.damage_taken[0], 0.0, "control: ...and the bill must be real HP")
	control.free()
	var p := _LedgerPlayer.new()
	p.grant_ability(FallImmunityScript.new())  # adopt the FallImmunity node through the real grant path (its presence gates immunity)
	p._apply_fall_damage(LETHAL_FALL)
	assert_eq(p.damage_taken.size(), 0, "with the fall-immunity upgrade, the same hard landing must cost no HP")
	p.free()  # frees the granted FallImmunity child too

func test_fall_immunity_from_a_pickup_survives_a_save_reload() -> void:
	# The upgrade arrives as a SCENE (an UpgradePickup's `grants` slot) but a save stores only ids, and the load path
	# rebuilds the ability from its SCRIPT by the naming convention. The immunity must come back through that round
	# trip, or a Continue silently hands the player their fall damage back.
	var pickup := UpgradePickup.new()
	pickup.grants = load(ABILITY_DIR + "FallImmunity.tscn") as PackedScene
	var before := _LedgerPlayer.new()
	assert_true(pickup._grant_to(before), "an UpgradePickup holding FallImmunity.tscn must grant it")
	var saved: Array = before.unlocked_list()
	before.free()
	pickup.free()
	var reloaded := _LedgerPlayer.new()
	reloaded.set_unlocks(saved)  # the save-load rebuild: load(script).new() by id, never the .tscn
	reloaded._apply_fall_damage(LETHAL_FALL)
	assert_eq(reloaded.damage_taken.size(), 0,
		"after a save/load the pickup's fall immunity must still waive a hard landing (saved unlocks: %s)" % [saved])
	reloaded.free()


# --- Silent-takedown upgrade: the stealth kill is now an unlockable ability, earned via the Takedown Chip ---

func test_the_takedown_chip_unlocks_the_stealth_kill_and_it_survives_a_reload() -> void:
	# scripts/player/silent_takedown.gd stays inert until its wielder has_mechanic(&"silent_takedown"). Drive the
	# REAL chip's installs_ability through the install path, then round-trip the unlock set through a fresh player the
	# way a save load does, and check the exact gate that component polls.
	var chip := load(TAKEDOWN_CHIP) as Item
	assert_true(chip != null and chip.is_upgrade_chip(), "chip_takedown.tres must load as an upgrade chip")
	if chip == null:
		return
	var p = load(PLAYER_PATH).new()
	assert_false(p.has_mechanic(&"silent_takedown"), "the stealth kill is locked until the Takedown Chip is installed")
	assert_true(p.can_grant_mechanic(chip.installs_ability),
		"the chip's installs_ability '%s' must resolve to a buildable ability, or the installer refuses (or charges for nothing)" % chip.installs_ability)
	p.unlock_mechanic(chip.installs_ability)
	assert_true(p.has_mechanic(&"silent_takedown"), "installing the Takedown Chip must open the gate the SilentTakedown component polls")
	var saved: Array = p.unlocked_list()
	p.free()
	var reloaded = load(PLAYER_PATH).new()
	reloaded.set_unlocks(saved)
	assert_true(reloaded.has_mechanic(&"silent_takedown"),
		"the installed takedown must survive a save/load (saved unlocks: %s)" % [saved])
	reloaded.free()
	chip = null


# --- The landing and void-fall beats that feed the death flow ---

func test_landing_bills_fall_damage_for_the_raw_fall_speed_even_crouched() -> void:
	# The exact regression that prompted this: the landing block silently never called _apply_fall_damage, so the
	# player took zero fall damage and the inherited knobs were dead. Driven through the real Landing.on_land on an
	# off-tree host. Crouching softens how a landing LOOKS (every presentation channel) — never what the fall COSTS.
	GameSettings.audio.land_sfx_min_impact_to_play = 2.0  # impact is 0..1 -> the land SFX (global_position) never plays
	GameSettings.effects.dust_land_min_impact_to_spawn = 2.0  # ...nor the dust puff
	var landing := Landing.new()
	var standing := _LedgerPlayer.new()
	landing.host = standing
	landing.on_land(-HARD_LANDING, Vector3(0.0, -HARD_LANDING, 0.0))
	assert_eq(standing.damage_taken.size(), 1, "a hard touchdown must bill fall damage exactly once")
	if standing.damage_taken.size() == 1:
		assert_gt(standing.damage_taken[0], 0.0, "...and a %.0f m/s landing must cost real HP" % HARD_LANDING)
	var crouched := _LedgerPlayer.new()
	var crouch := Crouch.new()
	crouch.crouch_t = 1.0  # a full crouch: every presentation channel of the landing goes quiet
	crouched.crouch = crouch
	landing.host = crouched
	landing.on_land(-HARD_LANDING, Vector3(0.0, -HARD_LANDING, 0.0))
	assert_eq(crouched.damage_taken, standing.damage_taken,
		"a fully crouched landing must cost exactly what a standing one does — crouching softens the look, not the fall")
	landing.free()
	crouch.free()
	standing.free()
	crouched.free()

func test_player_physics_beat_calls_the_landing_and_void_fall_hooks() -> void:
	# KEPT AS A SOURCE PIN, narrowed: Player._physics_process cannot be driven headless (CLAUDE.md — a Player's
	# _ready/prefab never runs in a unit test), so the two hand-offs it owns are checked on its CODE lines (comments
	# stripped, so a mention in prose can't satisfy it). What each hook DOES is driven in the tests either side.
	var code := _function_code("res://scripts/player/player.gd", "_physics_process")
	assert_false(code.is_empty(), "player.gd must define _physics_process")
	assert_true(code.contains("landing.on_land("),
		"Player._physics_process must hand touchdown to the Landing component, or fall damage silently stops")
	assert_true(code.contains("_update_continuous_fall_death("),
		"Player._physics_process must tick the void-fall timer, or a fall off the world never ends")

func test_a_void_fall_kills_once_the_continuous_fall_budget_runs_out() -> void:
	var limit: float = GameSettings.player_movement.max_continuous_fall_time
	assert_gt(limit, 0.0, "the shipped void-fall budget must be positive for this test to mean anything")
	var p := _LedgerPlayer.new()
	p.velocity = Vector3(0.0, -40.0, 0.0)
	for i in 3:
		assert_false(p._update_continuous_fall_death(limit * 0.3), "no death while the budget remains (frame %d)" % i)
	assert_eq(p.void_deaths.size(), 0, "90% of the budget spent falling must not kill yet")
	assert_true(p._update_continuous_fall_death(limit * 0.2),
		"the frame that exhausts the budget must enter the death flow and tell the physics beat to stop")
	if p.void_deaths.size() == 1:
		assert_almost_eq(p.void_deaths[0], 40.0, 0.001, "the death card must be handed the speed the player was falling at")
	for _i in 3:
		p._update_continuous_fall_death(limit)
	assert_eq(p.void_deaths.size(), 1, "an already-dying player must never be killed again while the body keeps falling")
	p.free()

func test_any_break_in_the_fall_hands_back_the_whole_void_budget() -> void:
	var limit: float = GameSettings.player_movement.max_continuous_fall_time
	var p := _LedgerPlayer.new()
	p.velocity = Vector3(0.0, -20.0, 0.0)
	p._update_continuous_fall_death(limit * 0.9)
	p.velocity = Vector3(0.0, 3.0, 0.0)  # a bounce / grapple yank / jump pad: momentarily rising
	p._update_continuous_fall_death(0.016)
	p.velocity = Vector3(0.0, -20.0, 0.0)
	p._update_continuous_fall_death(limit * 0.9)
	assert_eq(p.void_deaths.size(), 0, "a rising frame must reset the budget — two separate 90% falls are not one lethal fall")
	p.on_wall = true  # caught a wall mid-fall
	p._update_continuous_fall_death(0.016)
	p.on_wall = false
	p._update_continuous_fall_death(limit * 0.9)
	assert_eq(p.void_deaths.size(), 0, "grabbing a wall must reset the budget too")
	# Control: the SAME player, falling on without a break, does die — so the resets above were real, not a dead timer.
	p._update_continuous_fall_death(limit * 0.2)
	assert_eq(p.void_deaths.size(), 1, "control: an unbroken fall past the budget must kill")
	p.free()

func test_fall_immunity_does_not_save_you_from_the_void() -> void:
	# The implant waives LANDINGS. A fall that never lands still has to end, or an immune player pitched off the
	# world falls forever.
	var limit: float = GameSettings.player_movement.max_continuous_fall_time
	var p := _LedgerPlayer.new()
	p.grant_ability(FallImmunityScript.new())
	p.velocity = Vector3(0.0, -40.0, 0.0)
	p._update_continuous_fall_death(limit * 0.6)
	p._update_continuous_fall_death(limit * 0.6)
	assert_eq(p.void_deaths.size(), 1, "the void-fall death must ignore fall immunity")
	p.free()

func test_a_zero_void_budget_switches_the_void_fall_death_off() -> void:
	GameSettings.player_movement.max_continuous_fall_time = 0.0  # restored in after_each
	var p := _LedgerPlayer.new()
	p.velocity = Vector3(0.0, -40.0, 0.0)
	for i in 5:
		assert_false(p._update_continuous_fall_death(1000.0), "a budget of 0 means no void-fall death at all (frame %d)" % i)
	assert_eq(p.void_deaths.size(), 0, "max_continuous_fall_time <= 0 must disable the timer, not kill on the first frame")
	p.free()


## The CODE lines of one top-level function in a .gd file — everything from `func <name>(` up to the next top-level
## `func`, with `#` comments stripped — so a wiring pin can't be satisfied by a mention in prose.
func _function_code(path: String, func_name: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	var start := src.find("\nfunc %s(" % func_name)
	if start < 0:
		return ""
	var end := src.find("\nfunc ", start + 1)
	var body := src.substr(start, (end - start) if end >= 0 else -1)
	var code := PackedStringArray()
	for raw in body.split("\n"):
		var line: String = String(raw).get_slice("#", 0)
		if not line.strip_edges().is_empty():
			code.append(line)
	return "\n".join(code)


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


func test_a_chip_installed_air_dash_is_a_live_dash_identical_to_the_pickup_one() -> void:
	# ⭐The load-bearing one: AbilityManager._build rebuilds a chip-installed / save-loaded ability with
	# load(script).new() and NEVER reads AirDash.tscn, so a default authored only in the scene would install a
	# dead 0-force dash. Build it through that REAL runtime path, then fire it.
	var p = load(PLAYER_PATH).new()
	p.unlock_mechanic(&"air_dash")
	assert_true(p.has_mechanic(&"air_dash"), "a paid install / save load of air_dash must open the gate the dash key checks")
	var built: AirDash = null
	for c in p.get_children():
		if c is AirDash:
			built = c as AirDash
	assert_true(built != null, "unlock_mechanic(&\"air_dash\") must build an AirDash node under the player")
	if built == null:
		p.free()
		return
	# A pickup dropping AirDash.tscn and a chip rebuilding from the script must hand the player the SAME dash — a
	# retune authored only on the scene would make the two feel different.
	var from_scene := (load(ABILITY_DIR + "AirDash.tscn") as PackedScene).instantiate() as AirDash
	for knob in ["dash_force", "dash_upward", "cooldown", "single_air_dash", "screen_shake", "dash_sound"]:
		assert_eq(built.get(knob), from_scene.get(knob),
			"AirDash.%s must be the same on a chip-installed dash as on the AirDash.tscn a pickup grants — tune it on the script" % knob)
	from_scene.free()
	assert_true(built.dash_sound != null, "the whoosh must be the SCRIPT default so a chip-installed dash is never silent")
	assert_true(built.single_air_dash, "SHIP DECISION: one air dash per airtime (melee.tres's single_air_dash) — a chip install must not allow chaining")
	var h := _DashHost.new()
	built.dash_sound = null  # keep AudioManager out of an off-tree test
	built.setup(h)
	h.aim = Vector3(0.0, 0.0, -1.0)
	built.dash()
	assert_gt(h.explosion_velocity.dot(h.aim), 0.0, "a chip-installed dash must actually fling you along your aim (a 0-force default is the regression)")
	assert_gt(h.explosion_velocity.y, 0.0, "...with lift, so a dash across a gap still clears the lip")
	assert_gt(h.shake_taken, 0.0, "...and the launch must be felt as screen shake")
	assert_false(built.can_dash(), "the chip-installed dash must carry a cooldown that refuses an immediate second grounded dash")
	h.free()
	p.free()  # frees the built AirDash child too


func test_air_dash_launches_along_the_aim() -> void:
	# The test sets its OWN tuning, so a retune of the shipped numbers can't turn it red — the launch maths is pinned.
	var pair := _dash_pair()
	var d: AirDash = pair[0]
	var h = pair[1]
	d.dash_force = 10.0
	d.dash_upward = 3.0
	d.screen_shake = 0.25
	h.explosion_velocity = Vector3(1.5, 0.0, 0.0)  # a blast already carrying the player sideways
	h.aim = Vector3(0.0, 0.0, -1.0)
	d.dash()
	assert_eq(h.explosion_velocity, Vector3(1.5, 3.0, -10.0),
		"the dash must STACK aim * dash_force plus the straight-up dash_upward onto the blast already in flight, never replace it")
	assert_eq(h.shake_taken, 0.25, "the dash hands its OWN screen_shake trauma to the host — no weapon is involved any more")
	d.free()
	h.free()


func test_air_dash_aims_where_you_look_not_where_you_move() -> void:
	# The whole point of the rebind: look UP and the dash goes UP, with no weapon equipped and no ADS.
	var pair := _dash_pair()
	var d: AirDash = pair[0]
	var h = pair[1]
	d.dash_force = 10.0
	d.dash_upward = 3.0
	h.aim = Vector3(0.0, 1.0, 0.0)
	d.dash()
	assert_almost_eq(h.explosion_velocity.y, 13.0, 0.001,
		"looking straight up dashes straight up (dash_force along the aim, plus the lift)")
	assert_almost_eq(Vector2(h.explosion_velocity.x, h.explosion_velocity.z).length(), 0.0, 0.001,
		"...with no sideways drift")
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
	assert_true(d.can_dash(), "CONTROL: the same fresh dash with the implant switched on is ready")
	h.granted = false
	assert_false(d.can_dash(), "a switched-off air-dash implant refuses the dash")
	d.free()
	h.free()


func test_switching_the_air_dash_off_mid_fall_hands_the_spent_dash_back() -> void:
	# Spend the one airborne dash, stay airborne (so landing can't clear the lock), let the cooldown run out through the
	# real beat, then switch the implant off and back on: the re-enabled dash must be usable, not stuck behind a lock the
	# player can only clear by landing.
	var pair := _dash_pair()
	var d: AirDash = pair[0]
	var h = pair[1]
	h.on_floor = false
	d.dash()
	d.tick(d.cooldown)
	assert_false(d.can_dash(), "CONTROL: spent mid-fall and still airborne, the dash is locked once the cooldown is over")
	h.granted = false
	d.on_deactivated()
	h.granted = true
	assert_true(d.can_dash(), "switching the implant off and back on mid-fall hands the airborne dash back")
	d.free()
	h.free()


func test_air_dash_binding_exists_on_all_three_action_surfaces() -> void:
	# project.godot [input] / InputManager's action_* var / the rebindable ActionCatalog — InputManager's boot
	# audit only WARNS about drift between them, so pin the new action here.
	# Keyed on AirDash.DASH_ACTION — the name the ability actually polls — so a rename on either side is caught.
	assert_eq(InputManager.action_air_dash, AirDash.DASH_ACTION, "action_air_dash must name the action the AirDash ability polls")
	assert_true(InputMap.has_action(AirDash.DASH_ACTION), "AirDash must be a real [input] action or the key does nothing")
	var listed := false
	for spec in InputManager.action_catalog().actions:
		if spec.action == AirDash.DASH_ACTION:
			listed = true
	assert_true(listed, "AirDash must appear in ActionCatalog.tres or it can't be rebound in Options -> Controls")
