extends GutTest

## The NPC "go home" LEASH (scripts/npc/npc_home_return.gd): NPCs return to the spot they were authored at when the
## PLAYER DIES, or after they've been off-screen for a while — the dog/companion hidden-blink trick aimed at the
## spawn point instead of at the player.
##
## HOW THE RULES ARE DRIVEN HEADLESS. The component duck-types its host (`host` is Node-typed), so the leash rules run
## here against LeashHost: an IN-TREE stand-in exposing exactly the NPC facade the leash reads (a real NPC must never
## enter a unit-test tree — its _ready can't run). The component itself stays OFF-tree and its _physics_process is
## pumped by hand, so nothing ticks on its own. What the player can SEE and how FAR away they stand come from the
## Player node, which can't be in the tree either, so ObservedLeash overrides exactly those two world queries and
## nothing else. The heal and the ammo restock also run against the REAL Character and the real NPC -> Weapon -> Ammo
## ledger chain off-tree.
##
## Still pinned by SOURCE, because neither can be driven headless: the Player's death-cinematic tween order (a Player
## can't be in the tree and a tween needs one) and NPC._build_components' parse-safe build-by-script-path wiring.

const HOME_RETURN := "res://scripts/npc/npc_home_return.gd"
const CAL := &"pistol"
## The post LeashHost was authored at, and where it has wandered off to (far outside home_slack).
const HOME := Vector3(2.0, 0.0, -3.0)
const AWAY := Vector3(40.0, 0.0, 25.0)
const HOME_YAW := 1.25


## The NPC facade the leash duck-types, and nothing more. Starts ALIVE but WOUNDED (10 / 40 hp), calm (no
## perception, no target), not exempt, and records every seam the leash calls into `calls`.
class LeashHost extends CharacterBody3D:
	var hp: float = 10.0
	var max_hp: float = 40.0
	var _dead: bool = false
	var _cutscene_control: bool = false
	var _guarding: Variant = null
	var _talk: Variant = null
	var _perception: Variant = null
	var _target: Variant = null
	var _spawn_position: Vector3 = Vector3.ZERO
	var _spawn_yaw: float = 0.0
	var wanders: bool = false
	var wander_radius: float = 0.0
	var _nav: Variant = null
	var _locomotor: Variant = null
	var _locomotion: Variant = null
	var following: bool = false
	var calls: Array[String] = []

	func is_following() -> bool:
		return following

	func stand_down() -> void:
		calls.append("stand_down")

	func heal(amount: float) -> void:
		calls.append("heal")
		hp = minf(hp + amount, max_hp)

	func heal_limbs() -> void:
		calls.append("heal_limbs")

	func restore_spent_ammo() -> bool:
		calls.append("restore_spent_ammo")
		return true


## Perception as the leash reads it: a `state` and the optional committed-hearing-reaction probe.
class PerceptionStub extends RefCounted:
	var state: int = Perception.State.UNAWARE
	var reaction_pending: bool = false

	func hearing_pending() -> bool:
		return reaction_pending


## A TalkApproach mid walk-up to a conversation.
class ApproachingTalk extends RefCounted:
	func is_approaching() -> bool:
		return true


## A steering child (Locomotor / NpcLocomotion) — counts the per-life resets a blink landing must issue.
class SteeringChild extends RefCounted:
	var resets: int = 0

	func reset_for_reuse() -> void:
		resets += 1


## The NavigationAgent3D surface the landing re-seeds.
class NavStub extends RefCounted:
	var target_position: Vector3 = Vector3.ZERO


## The real leash with the two PLAYER queries injected (can the player see this point / how far away is the player),
## since the Player node that answers them can't be in a unit-test tree. Every rule layered on top is production code.
class ObservedLeash extends NpcHomeReturn:
	var visible_points: Array[Vector3] = []
	var player_distance: float = INF

	func _visible_to_player(point: Vector3) -> bool:
		for seen in visible_points:
			if seen.is_equal_approx(point):
				return true
		return false

	func _flat_distance_to_player() -> float:
		return player_distance


var _hr


func before_each() -> void:
	_hr = load(HOME_RETURN).new()  # bare .new(): _init only, no _ready -> no autoload signal connection


func after_each() -> void:
	if _hr != null:
		_hr.free()
		_hr = null


## An in-tree, alive, wounded, calm host standing far from its post, so a return is due.
func _host_away_from_home() -> LeashHost:
	var host := LeashHost.new()
	add_child_autofree(host)
	host._spawn_position = HOME
	host._spawn_yaw = HOME_YAW
	host.global_position = AWAY
	return host


## Swap the fixture for an ObservedLeash on `host` (after_each frees it like the default one).
func _observed_leash(host: Node) -> ObservedLeash:
	_hr.free()
	var leash := ObservedLeash.new()
	leash.host = host
	_hr = leash
	return leash


## A REAL off-tree NPC with a real Weapon hub + Ammo ledger: 4 spare clips at spawn, ONE burned by a reload, and 6
## rounds of the fresh magazine fired (4 left in the gun).
func _npc_that_burned_a_clip() -> NPC:
	var npc: NPC = load("res://scripts/npc/npc.gd").new()
	npc.max_hp = 40.0
	npc.hp = 40.0
	npc.inventory = CharacterInventory.new()
	var gun := WeaponData.new()
	gun.max_ammo = 10
	gun.caliber = CAL
	var hub := Weapon.new()
	hub.ammo = Ammo.new()
	hub.ammo.character = npc
	hub.ammo.current_weapon = gun
	npc.inventory.add(ItemDb.ammo_item_for(CAL), 4)
	hub.ammo.current_ammo = 0
	hub.ammo.reload()
	hub.ammo.current_ammo = 4
	npc._weapon = hub
	return npc


func _free_npc(npc: NPC) -> void:
	var hub: Weapon = npc._weapon
	npc._weapon = null
	hub.ammo.free()
	hub.free()
	npc.inventory.free()
	npc.free()


# --- The on-screen guard (pure geometry) ------------------------------------------------------------------------

func test_view_cone_sees_straight_ahead_and_not_behind() -> void:
	# Camera at origin looking down -Z (Godot's camera forward). The rule is a dot vs threshold, identical to
	# CompanionFollow._in_view_cone — it is what forbids a blink that would pop on screen.
	var fwd := Vector3(0, 0, -1)
	assert_true(_hr.in_view_cone(Vector3.ZERO, fwd, Vector3(0, 0, -5), 0.35),
		"a point straight ahead of the camera is IN the view cone (blink forbidden)")
	assert_false(_hr.in_view_cone(Vector3.ZERO, fwd, Vector3(0, 0, 5), 0.35),
		"a point directly behind the camera is OUT of the view cone (blink allowed)")
	assert_false(_hr.in_view_cone(Vector3.ZERO, fwd, Vector3(5, 0, 0), 0.35),
		"a point 90 degrees off to the side is OUT of the cone (dot 0 < 0.35)")

func test_view_cone_ignores_height() -> void:
	# The cone is HORIZONTAL only (to_point.y is zeroed): an NPC on a roof directly ahead is still "on screen",
	# so the guard never blinks something the player is looking up at.
	var fwd := Vector3(0, 0, -1)
	assert_true(_hr.in_view_cone(Vector3.ZERO, fwd, Vector3(0, 30, -5), 0.35),
		"height is ignored — a point ahead but far above is still in the cone")

func test_view_cone_treats_a_point_on_the_camera_as_visible() -> void:
	# Degenerate case: no direction to test, so it must fail SAFE (visible => refuse the blink), never divide by ~0.
	assert_true(_hr.in_view_cone(Vector3.ZERO, Vector3(0, 0, -1), Vector3.ZERO, 0.35),
		"a point on top of the camera reads as visible (fail safe: refuse to move it)")

func test_view_cone_threshold_is_honoured() -> void:
	# A tighter threshold shrinks the "on screen" cone, so the same off-axis point flips to blink-allowed.
	var fwd := Vector3(0, 0, -1)
	var diagonal := Vector3(5, 0, -5)  # dot ~= 0.707
	assert_true(_hr.in_view_cone(Vector3.ZERO, fwd, diagonal, 0.35), "45 degrees off-axis is inside a 0.35 cone")
	assert_false(_hr.in_view_cone(Vector3.ZERO, fwd, diagonal, 0.9), "the same point is outside a 0.9 cone")


# --- Defaults: the dropped-in leash vs the species-wide seeds ---------------------------------------------------

func test_an_unconfigured_dropped_in_leash_matches_the_species_wide_defaults() -> void:
	# NPC._build_components seeds the AUTO-BUILT leash from GameSettings.npc_ai, but a leash a designer DROPS under one
	# NPC keeps its own code default for every knob they didn't touch. The two must agree, or a shopkeeper who only had
	# off_screen_delay tuned would silently stop healing / restocking / blinking like the rest of the cast. Each seed
	# is read BY NAME, so a renamed NpcAiSettings field (which would only fail at spawn) fails here too.
	var s := NpcAiSettings.new()
	var seeds := {
		"enabled": "home_return",
		"return_on_player_death": "home_return_on_player_death",
		"death_return_delay": "home_return_death_delay",
		"heal_on_player_death": "home_return_heal_on_player_death",
		"restore_ammo_on_player_death": "home_return_restore_ammo_on_player_death",
		"return_when_off_screen": "home_return_off_screen",
		"off_screen_delay": "home_return_off_screen_delay",
		"off_screen_requires_calm": "home_return_requires_calm",
		"home_slack": "home_return_slack",
		"blink_home": "home_return_blink",
		"min_blink_distance": "home_return_min_blink_distance",
	}
	for knob in seeds:
		var field: String = seeds[knob]
		assert_true(field in s, "NpcAiSettings exposes %s (NPC._build_components seeds the leash's %s from it)" % [field, knob])
		assert_eq(_hr.get(knob), s.get(field),
			"a dropped-in leash's %s default must match NpcAiSettings.%s, or it behaves unlike the auto-built cast" % [knob, field])
	s = null

func test_the_encounter_reset_ships_on() -> void:
	# SHIP DECISIONS (player-facing), read off the shipped GameSettings.npc_ai the auto-build seeds from. Under the
	# default CHECKPOINT_RESPAWN in-place revive the world is not reloaded, so these are what make a lost fight reset.
	var shipped: NpcAiSettings = GameSettings.npc_ai
	assert_true(shipped.home_return, "SHIP DECISION: the leash is ON for the whole cast")
	assert_true(shipped.home_return_on_player_death,
		"SHIP DECISION: dying sends the survivors home instead of leaving them parked where they killed you")
	assert_true(shipped.home_return_heal_on_player_death,
		"SHIP DECISION: dying tops the survivors back up — a lost fight must not get easier every retry")
	assert_true(shipped.home_return_restore_ammo_on_player_death,
		"SHIP DECISION: dying hands back the ammo enemies burned — a lost fight must not leave them progressively disarmed")
	assert_true(shipped.home_return_off_screen,
		"SHIP DECISION: an NPC a chase stranded off-screen is leashed back to its post")


# --- Off-tree / no-host inertness -------------------------------------------------------------------------------

func test_return_home_is_a_no_op_without_a_host() -> void:
	# GUT builds these bare; every entry point must be inert rather than null-deref.
	assert_false(_hr.return_home(true), "no host -> nothing to send home, even when the view guard is skipped")
	assert_false(_hr.return_home(false), "no host -> false")

func test_home_position_without_a_host_is_the_origin() -> void:
	assert_eq(_hr.home_position(), Vector3.ZERO, "no host and no marker -> a harmless origin, not a crash")
	assert_eq(_hr.home_yaw(), 0.0, "no host and no marker -> yaw 0")

func test_disabled_component_refuses_even_with_a_host() -> void:
	var host := _host_away_from_home()
	_hr.host = host
	_hr.enabled = false
	assert_false(_hr.return_home(true), "enabled = false makes the component inert, even for the death reset")
	assert_eq(host.global_position, AWAY, "a disabled leash never moves its NPC")
	assert_true(host.calls.is_empty(), "a disabled leash never stands its NPC down either")
	_hr.enabled = true
	assert_true(_hr.return_home(true), "control: the same NPC with the leash enabled IS sent home")
	assert_eq(host.global_position, HOME, "control: ...and lands on its post")


# --- The aggro rule (an enemy must never evaporate because you broke line of sight) -----------------------------

func test_an_engaged_npc_is_never_teleported_by_the_off_screen_leash() -> void:
	# THE rule: an NPC with aggro must not pop because the player ducked out of view. It is a HARD refusal, NOT behind
	# off_screen_requires_calm (that knob only paces the clock) — so even a HARD leash (calm not required) may only
	# stand an engaged NPC down and let it walk home.
	var host := _host_away_from_home()
	var threat := Node3D.new()
	add_child_autofree(threat)
	host._target = threat
	_hr.host = host
	_hr.off_screen_requires_calm = false
	_hr.off_screen_delay = 0.5
	_hr.scan_interval = 0.25
	for _tick in 8:
		_hr._physics_process(0.3)
	assert_true(host.calls.has("stand_down"),
		"the hard leash did pull on the engaged NPC (stood it down so it walks back) — the clock really ran out")
	assert_eq(host.global_position, AWAY,
		"but an NPC holding a target is NEVER teleported by the off-screen leash, however long it is out of view")
	# Control: the very same NPC with nothing to fight — and no player in the scene, so nobody could notice.
	host._target = null
	for _tick in 8:
		_hr._physics_process(0.3)
	assert_eq(host.global_position, HOME,
		"control: once calm, the same off-screen NPC blinks home (no player in the tree degrades to 'far enough, unseen')")

func test_only_the_black_screen_death_reset_may_teleport_an_engaged_npc() -> void:
	var host := _host_away_from_home()
	var threat := Node3D.new()
	add_child_autofree(threat)
	host._target = threat
	_hr.host = host
	assert_true(_hr.return_home(false), "an engaged NPC asked home still reports it was sent (on foot)")
	assert_true(host.calls.has("stand_down"), "a refused blink still stands the NPC down so the idle floor walks it home")
	assert_eq(host.global_position, AWAY, "...but it is not popped out from under the player")
	assert_true(_hr.return_home(true), "the player-death reset (ignore_view) runs on a fully black screen")
	assert_eq(host.global_position, HOME, "so it alone is allowed past the aggro rule, or a lost fight would half-reset")

func test_engaged_counts_a_proximity_target_not_just_alerted_perception() -> void:
	# NpcTargeting acquires by pure proximity with NO line-of-sight test, so a hostile holds the player as _target
	# before perception has noticed them; and a committed hearing reaction reads UNAWARE for its whole reaction
	# window. Each of those is "about to attack you" and must block the blink ON ITS OWN.
	var host := _host_away_from_home()
	var perception := PerceptionStub.new()
	host._perception = perception
	_hr.host = host
	var threat := Node3D.new()
	add_child_autofree(threat)

	host._target = threat
	_hr.return_home(false)
	assert_eq(host.global_position, AWAY, "a live proximity target blocks the blink while perception still reads UNAWARE")
	host._target = null

	for state in [Perception.State.DETECTING, Perception.State.ALERTED, Perception.State.INVESTIGATING]:
		perception.state = state
		_hr.return_home(false)
		assert_eq(host.global_position, AWAY,
			"perception past UNAWARE (state %d) blocks the blink with no target held" % state)
	perception.state = Perception.State.UNAWARE

	perception.reaction_pending = true
	_hr.return_home(false)
	assert_eq(host.global_position, AWAY, "a committed hearing reaction (still reading UNAWARE) blocks the blink")
	perception.reaction_pending = false

	# A target that has since been FREED is no aggro at all — and must be checked for validity before anything else,
	# or reading it crashes the game (the ordering slip npc.gd's _notify_peers_forget_me note records).
	var gone := Node3D.new()
	host._target = gone
	gone.free()
	assert_true(_hr.return_home(false), "a freed target neither crashes the leash nor holds the NPC")
	assert_eq(host.global_position, HOME, "control: with nothing live to fight, the calm NPC blinks home")

func test_blink_needs_distance_from_the_player() -> void:
	# Out of the view cone is not the same as unnoticeable: a body vanishing a few metres behind the player is felt,
	# and they're one turn from looking at where it was. Below min_blink_distance it WALKS back instead.
	var host := _host_away_from_home()
	var leash := _observed_leash(host)
	leash.min_blink_distance = 8.0
	leash.player_distance = 5.0
	assert_true(leash.return_home(false), "a too-close NPC is still sent home")
	assert_true(host.calls.has("stand_down"), "...by standing down so the idle floor walks it back")
	assert_eq(host.global_position, AWAY, "...never by vanishing 5 m from the player")
	leash.player_distance = 8.0
	leash.return_home(false)
	assert_eq(host.global_position, HOME, "at min_blink_distance the hidden blink is allowed")

	host.global_position = AWAY
	leash.min_blink_distance = 20.0
	leash.player_distance = 12.0
	leash.return_home(false)
	assert_eq(host.global_position, AWAY, "the knob is honoured: 12 m is too close once min_blink_distance is 20 m")

func test_the_blink_is_refused_while_the_npc_or_its_post_is_on_screen() -> void:
	# Never move a body the player can see — neither out of view (the NPC) nor into view (its post).
	var host := _host_away_from_home()
	var leash := _observed_leash(host)
	leash.visible_points = [AWAY]
	assert_false(leash.return_home(false), "the NPC itself is on screen: refuse (false = the caller retries later)")
	assert_eq(host.global_position, AWAY, "the NPC does not vanish in front of the player")
	leash.visible_points = [HOME]
	assert_false(leash.return_home(false), "its post is on screen: refuse")
	assert_eq(host.global_position, AWAY, "the NPC does not pop INTO view at its post")
	assert_true(leash.return_home(true), "the death reset skips the view guard — the screen is black")
	assert_eq(host.global_position, HOME, "so it lands home even with its post in the (covered) view cone")

func test_a_blink_lands_facing_home_with_the_steering_state_cleared() -> void:
	# Landing with the old velocity, nav route or wander goal would walk the NPC straight back out of its post.
	var host := _host_away_from_home()
	host.velocity = Vector3(3.0, 0.0, -2.0)
	var nav := NavStub.new()
	nav.target_position = AWAY
	host._nav = nav
	var locomotor := SteeringChild.new()
	var locomotion := SteeringChild.new()
	host._locomotor = locomotor
	host._locomotion = locomotion
	_hr.host = host
	assert_true(_hr.return_home(false), "a calm, unobserved NPC is sent home")
	assert_eq(host.global_position, HOME, "it lands on its spawn spot")
	assert_almost_eq(host.rotation.y, HOME_YAW, 0.001, "facing the way it was authored")
	assert_eq(host.velocity, Vector3.ZERO, "with no momentum carried over from the chase")
	assert_eq(nav.target_position, HOME, "the nav agent is re-seeded so it doesn't path back to where it was")
	assert_eq(locomotor.resets, 1, "the Locomotor's anti-stuck latches + cached path are dropped")
	assert_eq(locomotion.resets, 1, "the stale wander destination near the OLD spot is dropped")


# --- The player-death beat --------------------------------------------------------------------------------------

func test_reset_for_reuse_clears_the_timers() -> void:
	# NpcPool reuses the body without rebuilding children, so a stale off-screen clock / pending death return would
	# leak into the next life and yank a freshly-spawned NPC back to the previous life's post.
	_hr._off_screen_t = 99.0
	_hr._death_due_msec = 5000
	_hr._scan_t = 3.0
	_hr.reset_for_reuse()
	assert_eq(_hr._off_screen_t, 0.0, "the off-screen clock rewinds")
	assert_eq(_hr._death_due_msec, -1, "a pending player-death return is dropped (-1 = none armed)")
	assert_eq(_hr._scan_t, 0.0, "the scan throttle rewinds")

func test_player_death_handler_is_inert_when_every_trigger_is_off() -> void:
	# The cue drives THREE independent pieces of the encounter reset (go home + full heal + ammo restock); it must
	# arm when ANY is wanted, and only stay dark when none is. Driven on a LIVE in-tree host, so the flags decide.
	var host := _host_away_from_home()
	_hr.host = host
	_hr.return_when_off_screen = false
	var triggers := ["return_on_player_death", "heal_on_player_death", "restore_ammo_on_player_death"]
	for trigger in triggers:
		_hr.set(trigger, false)
	_hr._on_player_died()
	_hr._physics_process(0.016)
	assert_eq(host.global_position, AWAY, "with every trigger off, the death cue moves nothing")
	assert_eq(host.hp, 10.0, "...heals nothing")
	assert_true(host.calls.is_empty(), "...and restocks / stands down nothing")
	for trigger in triggers:
		for other in triggers:
			_hr.set(other, other == trigger)
		_hr.reset_for_reuse()
		_hr._on_player_died()
		assert_gt(_hr._death_due_msec, -1, "control: %s alone is enough to arm the death beat" % trigger)

func test_a_restock_only_leash_restocks_without_healing_or_moving() -> void:
	# Restock-only is a valid configuration: the cue must arm for it with the return and the heal both off.
	var host := _host_away_from_home()
	_hr.host = host
	_hr.return_on_player_death = false
	_hr.heal_on_player_death = false
	_hr.restore_ammo_on_player_death = true
	_hr.return_when_off_screen = false
	_hr._on_player_died()
	_hr._physics_process(0.016)
	assert_eq(host.calls.count("restore_spent_ammo"), 1, "the death beat hands the burned ammo back")
	assert_eq(host.hp, 10.0, "the heal is off, so the NPC stays wounded")
	assert_false(host.calls.has("stand_down"), "the return is off, so its engagement is untouched")
	assert_eq(host.global_position, AWAY, "...and it is not moved")
	_hr._physics_process(0.016)
	assert_eq(host.calls.count("restore_spent_ammo"), 1, "the beat is one-shot: the next tick restocks nothing more")

func test_restore_spent_ammo_is_inert_without_a_host() -> void:
	assert_false(_hr.restore_spent_ammo(), "no host -> nothing to restock, not a null-deref")

func test_restore_spent_ammo_never_restocks_a_corpse() -> void:
	# A dead NPC's backpack is the LOOT the player earned by winning that trade. This NPC really did burn a clip, so
	# the corpse gate is the only thing between the reset and minting ammo onto a body the player is about to search.
	var npc := _npc_that_burned_a_clip()
	npc._dead = true
	npc.hp = 0.0
	_hr.host = npc
	assert_false(_hr.restore_spent_ammo(), "a corpse is not restocked")
	assert_eq(npc.inventory.ammo_count(CAL), 3, "the burned clip stays burned in the bag the player will loot")
	assert_eq(npc._weapon.ammo.current_ammo, 4, "and the corpse's magazine is not topped up")
	npc._dead = false
	npc.hp = 40.0
	assert_true(_hr.restore_spent_ammo(), "control: the same NPC alive IS restocked")
	assert_eq(npc.inventory.ammo_count(CAL), 4, "control: its burned clip comes back")
	_hr.host = null
	_free_npc(npc)

func test_the_death_restock_returns_only_what_was_fired_never_what_was_stolen() -> void:
	# The restock goes through the NPC facade to the Ammo LEDGER, which books each clip as it is spent. A "top the bag
	# back up to the loadout" refill would also return ammo the player PICKPOCKETED, and stripping an NPC of ammo to
	# disarm it is a real mechanic (npc.gd _can_fight_with_gun).
	var npc := _npc_that_burned_a_clip()
	npc.inventory.take_ammo(CAL, 3)  # the player pickpockets every spare clip left
	_hr.host = npc
	assert_true(_hr.restore_spent_ammo(), "the clip the NPC fired off is owed back")
	assert_eq(npc.inventory.ammo_count(CAL), 1,
		"ONLY the burned clip returns — the three the player stole stay stolen, so disarm-by-theft survives your death")
	assert_eq(npc._weapon.ammo.current_ammo, 10, "and the magazine it fired from is full again")
	assert_false(_hr.restore_spent_ammo(), "the debt is settled: a second death beat owes nothing")
	assert_eq(npc.inventory.ammo_count(CAL), 1, "...and gives nothing more")
	_hr.host = null
	_free_npc(npc)

func test_npc_exposes_the_restore_spent_ammo_seam() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_true(npc.has_method("restore_spent_ammo"),
		"NPC.restore_spent_ammo() is the facade the leash calls (and the `npc restock` console verb)")
	assert_false(npc.restore_spent_ammo(),
		"a bare NPC has no weapon hub — the facade degrades to false instead of null-dereffing _weapon.ammo")
	npc.free()


## --- The full heal (the other half of the player-death reset) --------------------------------------------------

func test_a_heal_only_leash_heals_without_moving() -> void:
	# Heal-only is a valid configuration: an NPC can be healed without being sent home.
	var host := _host_away_from_home()
	_hr.host = host
	_hr.return_on_player_death = false
	_hr.heal_on_player_death = true
	_hr.restore_ammo_on_player_death = false
	_hr.return_when_off_screen = false
	_hr._on_player_died()
	_hr._physics_process(0.016)
	assert_eq(host.hp, host.max_hp, "the survivor is back to full HP on the death beat")
	assert_true(host.calls.has("heal_limbs"), "its limb damage is cleared with it")
	assert_false(host.calls.has("restore_spent_ammo"), "the restock is off")
	assert_false(host.calls.has("stand_down"), "heal-only never touches the engagement")
	assert_eq(host.global_position, AWAY, "heal-only heals the NPC where it stands — it is not sent home")

func test_restore_full_health_is_inert_without_a_host() -> void:
	assert_false(_hr.restore_full_health(), "no host -> nothing to heal, not a null-deref")

func test_restore_full_health_tops_a_wounded_host_up() -> void:
	# Off-tree Character (never _ready'd, per the project's test rules) — the heal seam is pure enough to run bare.
	var host = load("res://scripts/player/character.gd").new()
	host.max_hp = 40.0
	host.hp = 7.0
	_hr.host = host
	assert_true(_hr.restore_full_health(), "a wounded survivor heals")
	assert_eq(host.hp, 40.0, "back to FULL hp, clamped by Character.heal")
	assert_false(_hr.restore_full_health(), "an already-full NPC reports no work done")
	host.free()

func test_restore_full_health_never_revives_the_dead() -> void:
	# The reset restores the survivors of a fight; it must never undo one. An NPC you killed stays killed.
	var host = load("res://scripts/player/character.gd").new()
	host.max_hp = 40.0
	host.hp = 0.0
	host._dead = true
	_hr.host = host
	assert_false(_hr.restore_full_health(), "a corpse is not healed")
	assert_eq(host.hp, 0.0, "and its hp is left at 0")
	host.free()

func test_restore_full_health_goes_through_the_heal_seam_not_a_raw_write() -> void:
	# Character.heal() is the seam that emits `damaged`; a raw `hp = max_hp` would leave every listener bound to that
	# signal (a companion's HUD bar) showing the pre-reset wound. Limb damage must clear too, or the guard walks back to
	# its post permanently limping.
	var host = load("res://scripts/player/character.gd").new()
	host.max_hp = 40.0
	host.hp = 7.0
	host._crippled[Character.BodyPart.LEGS] = true
	host._limb_condition[Character.BodyPart.LEGS] = 0.0
	var heard: Array = []
	host.damaged.connect(func(current_hp: float, max_hp: float) -> void: heard.append([current_hp, max_hp]))
	_hr.host = host
	assert_true(_hr.restore_full_health(), "a wounded, limping survivor heals")
	assert_eq(heard, [[40.0, 40.0]], "listeners on `damaged` hear the restore land at full HP, exactly once")
	assert_false(host.is_limb_crippled(Character.BodyPart.LEGS), "the crippled leg is mended")
	assert_false(host.has_limb_damage(), "no limb damage survives the reset")
	# Full HP but limping again: no HP work to report, yet the limp must still be cleared.
	host._crippled[Character.BodyPart.ARMS] = true
	assert_false(_hr.restore_full_health(), "an NPC already at full HP reports no HP restored")
	assert_false(host.is_limb_crippled(Character.BodyPart.ARMS), "...but its crippled arm is still mended")
	_hr.host = null
	host.free()

func test_the_heal_is_not_gated_on_the_move_exemptions() -> void:
	# _eligible() exempts a companion / bodyguard / cutscene body / one walking up to talk from being MOVED. None of
	# those is a reason to leave it wounded or dry: the death beat heals and restocks it, and only the move is refused.
	var vip := Node3D.new()
	add_child_autofree(vip)
	for exemption in ["a recruited companion", "a bodyguard on duty", "a cutscene body", "an NPC walking up to talk"]:
		var host := _host_away_from_home()
		match exemption:
			"a recruited companion":
				host.following = true
			"a bodyguard on duty":
				host._guarding = vip
			"a cutscene body":
				host._cutscene_control = true
			"an NPC walking up to talk":
				host._talk = ApproachingTalk.new()
		_hr.host = host
		_hr.reset_for_reuse()
		_hr._on_player_died()
		_hr._physics_process(0.016)
		assert_eq(host.hp, host.max_hp, "%s is healed on the death beat even though it is exempt from the move" % exemption)
		assert_true(host.calls.has("restore_spent_ammo"), "%s is restocked on the death beat too" % exemption)
		assert_eq(host.global_position, AWAY, "%s is NOT sent home — the exemption still holds for the move" % exemption)
		assert_false(host.calls.has("stand_down"), "%s keeps its engagement — nothing about the move half ran" % exemption)

func test_the_dead_are_neither_moved_nor_revived_by_the_death_reset() -> void:
	var host := _host_away_from_home()
	host._dead = true
	host.hp = 0.0
	_hr.host = host
	_hr._on_player_died()
	_hr._physics_process(0.016)
	assert_eq(host.hp, 0.0, "an NPC you killed stays killed")
	assert_true(host.calls.is_empty(), "no heal, restock or stand-down reaches a corpse")
	assert_eq(host.global_position, AWAY, "and it stays where it fell")


func test_player_death_handler_needs_a_host() -> void:
	# The handler gates on a live, in-tree host — a bare component must not arm a reset it can never run.
	_hr._on_player_died()
	assert_eq(_hr._death_due_msec, -1, "no host -> no armed reset")
	var parked := LeashHost.new()  # alive, but OFF-tree: a pooled body parked between lives
	_hr.host = parked
	_hr._on_player_died()
	assert_eq(_hr._death_due_msec, -1, "an off-tree host (a parked pool body) arms nothing either")
	_hr.host = null
	parked.free()

func test_the_death_deadline_is_wall_clock_not_scaled_delta() -> void:
	# The death cinematic runs at Engine.time_scale 0.3 (and hitstop can pin it near 0), so a delta countdown would
	# stretch the delay ~3x and fire ON the respawn fade-up. The deadline must follow REAL time: no amount of scaled
	# physics delta fires it early, and real time passing fires it even on a tick that carries no delta at all.
	var host := _host_away_from_home()
	_hr.host = host
	_hr.death_return_delay = 0.2
	_hr._on_player_died()
	_hr._physics_process(60.0)
	assert_eq(host.global_position, AWAY, "a minute of physics delta inside a 0.2 s real-time delay does not fire the return")
	assert_eq(host.hp, 10.0, "...nor the heal")
	OS.delay_msec(300)
	_hr._physics_process(0.0)
	assert_eq(host.global_position, HOME, "once 0.2 REAL seconds have passed the return fires, even on a zero-delta tick")
	assert_eq(host.hp, host.max_hp, "...together with the heal")

func test_a_death_return_refused_on_screen_fires_the_moment_the_npc_is_unobserved() -> void:
	# With death_return_ignores_view off, a refused death return is not dropped: it is handed to the off-screen path
	# with the clock already full, so it fires on the first unobserved scan instead of waiting out the whole delay.
	var host := _host_away_from_home()
	var leash := _observed_leash(host)
	leash.death_return_ignores_view = false
	leash.off_screen_delay = 30.0
	leash.visible_points = [AWAY]
	leash._on_player_died()
	leash._physics_process(0.016)
	assert_eq(host.global_position, AWAY, "holding the view guard at death: the on-screen NPC is not popped")
	assert_eq(host.hp, host.max_hp, "the invisible heal still landed on the beat")
	leash.visible_points = []
	leash._physics_process(0.016)
	assert_eq(host.global_position, HOME,
		"the refused return fires on the very next unobserved scan, not 30 s of off-screen time later")


# --- Wiring seams (silent when broken) --------------------------------------------------------------------------

func test_gamestate_declares_the_player_death_cue() -> void:
	assert_true(GameState.has_signal(&"player_died"),
		"GameState.player_died is the one broadcast NPCs connect to (no Player spawn-order handshake)")

func test_an_in_tree_leash_listens_for_the_player_death_cue() -> void:
	# Connected in _ready against the autoload, so it survives NpcPool reuse. Hostless, so its own tick no-ops here.
	var leash = load(HOME_RETURN).new()
	add_child_autofree(leash)
	assert_true(GameState.player_died.is_connected(Callable(leash, &"_on_player_died")),
		"a leash in the tree hears GameState.player_died — without it no NPC resets when the player dies")

func test_the_death_cue_fires_on_the_black_frame_not_at_death() -> void:
	# TIMING IS THE CONTRACT here, and it's invisible to any off-tree assert: the cue must land on the death
	# cinematic's FULLY BLACK frame (where the "You were killed by X" card comes up), NOT in die(). Emitting at
	# death time — ~1.6 s earlier, while the vignette is still closing — lets the player WATCH every NPC teleport
	# away, which reads worse than not resetting at all. The cinematic is a long in-tree tween a unit test must not
	# run, so pin the wiring by source.
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_true(src.contains("func _on_death_screen_covered()"),
		"the cue has its own callback, fired from the death-sequence tween")
	assert_true(src.contains("GameState.player_died.emit()"),
		"Player broadcasts GameState.player_died so the world can reset behind the black")
	assert_true(src.contains("tw.tween_callback(_on_death_screen_covered)"),
		"the callback is wired into the death cinematic tween")
	# THREE OFFSETS THAT GET ORDERED, so each needs both guards: present (a renamed tween call answers -1 and the
	# ordering assert stops measuring the beat it names) and UNIQUE (find() reports only the first occurrence, so a
	# second tween_callback would let the pin pass on the wrong one while the real order regressed).
	var covered := src.find("tw.tween_callback(_on_death_screen_covered)")
	assert_gt(covered, -1, "tw.tween_callback(_on_death_screen_covered) no longer present — the pin is stale")
	assert_eq(src.rfind("tw.tween_callback(_on_death_screen_covered)"), covered,
		"the death cue must be wired into the tween exactly ONCE, or this ordering pin measures the wrong one")
	var phase_one := src.find("tw.tween_method(_death_step, 0.0, 1.0")
	assert_gt(phase_one, -1, "tw.tween_method(_death_step, 0.0, 1.0 no longer present — the pin is stale")
	assert_eq(src.rfind("tw.tween_method(_death_step, 0.0, 1.0"), phase_one,
		"the vignette close must be tweened exactly ONCE, or 'the cue runs after phase 1' is measured against the wrong step")
	var card := src.find("tw.tween_callback(_show_death_card)")
	assert_gt(card, -1, "tw.tween_callback(_show_death_card) no longer present — the pin is stale")
	assert_eq(src.rfind("tw.tween_callback(_show_death_card)"), card,
		"the death card must be tweened in exactly ONCE, or 'the cue runs before the card' is measured against the wrong one")
	assert_true(phase_one > -1 and covered > phase_one,
		"it runs AFTER phase 1 (the vignette close) — i.e. on full black, not while the world is still readable")
	assert_true(card > -1 and covered < card,
		"and BEFORE _show_death_card, which early-outs on a blank message — the cue must not depend on the card rendering")

func test_npc_exposes_the_stand_down_and_send_home_seams() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_true(npc.has_method("stand_down"),
		"NPC.stand_down() is the public 'break off this engagement' seam the leash calls")
	assert_true(npc.has_method("send_home"),
		"NPC.send_home() is the facade onto the NpcHomeReturn child (also the component's parent config-warning probe)")
	npc.free()

func test_stand_down_clears_the_engagement_off_tree() -> void:
	# A bare NPC has no perception / laser children, so stand_down must be null-safe — and it must NOT touch the
	# provoke latch: a guard you shot is still angry next time, it just went back to its post.
	var npc = load("res://scripts/npc/npc.gd").new()
	var foe := Node3D.new()
	npc._target = foe
	npc._last_attacker = foe
	npc._provoked = true
	npc.stand_down()
	assert_null(npc._target, "the combat target it was holding is dropped")
	assert_null(npc._last_attacker, "the sticky attacker lock it was holding is dropped")
	assert_true(npc._provoked, "hostility is DELIBERATELY preserved — standing down is not forgiveness")
	npc.free()
	foe.free()

func test_npc_builds_the_leash_by_script_path_not_by_bare_type() -> void:
	# npc.gd is a @tool root: naming a newly-added class_name at parse time can fail its parse in the live editor
	# (the new-classname reimport cascade), which is why CrippleCallout is built the same way. That failure only
	# exists in the editor, and _build_components / reset_for_reuse only run on an in-tree NPC, so pin by source.
	var src := FileAccess.get_file_as_string("res://scripts/npc/npc.gd")
	assert_true(src.contains("res://scripts/npc/npc_home_return.gd"),
		"NPC builds/matches the leash by script path")
	assert_false(src.contains("NpcHomeReturn.new()"),
		"NPC must NOT name the class at parse time — build it via load(path).new()")
	assert_true(src.contains("_home_return.host = self"),
		"the host is bound for BOTH the auto-built and the designer-dropped instance")
	assert_true(src.contains("_home_return.call(&\"reset_for_reuse\")"),
		"pool reuse resets the leash with the other stateful children")
