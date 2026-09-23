extends GutTest

## The two dev-only seams the AI debug commands act through (2026-08-18, loop iteration 2):
##  * NPC.DEBUG_NOTARGET_META — the ghost gate at the top of NPC._treats_as_enemy (the ONE predicate targeting
##    acquires/keeps by and the per-frame Perception.is_hostile writer), written by DebugActionsWorld `notarget`.
##  * DebugInspector.target() / hit_point() — the physics-tick cache the per-NPC verbs (`brain`, `npc <verb>`)
##    resolve their actor and point through, never a fresh raycast.
## An NPC's _ready is never run here (CLAUDE.md). The gate is driven on an NPC built off-tree via load().new(), the
## tests/test_npc_vs_npc.gd idiom: _treats_as_enemy -> is_hostile_to -> _protectee read only plain fields (disposition,
## faction, _provoked, _guarding, _leader) plus the Reputation autoload, so the whole predicate is callable with no
## child built. The `notarget` writer is
## driven through DebugActionsWorld.run() with NO tree in ctx (so the live-NPC holder scan is skipped) and a Player
## double, and its effect is read back through that same NPC gate, never through the literal. The inspector IS
## constructed off-tree (no _ready), which is exactly the "before the first tick" state its accessors promise; its
## cache is then poked directly (white-box, the members are the contract) to drive the three lifecycles a physics
## tick cannot be made to produce here: a target parked OUT of the tree (NpcPool.reclaim), a target FREED (an NPC's
## queue_free landing), and a miss (_clear_target).

const InspectorScript := preload("res://scripts/components/debug_inspector.gd")
const WorldActions := preload("res://scripts/components/debug_actions_world.gd")
const GroupsScript := preload("res://scripts/world/groups.gd")

const NPC_PATH := "res://scripts/npc/npc.gd"

## Authored noise values on the Player double: deliberately NOT player.gd's shipped defaults, so a restore that
## re-applies a default (or the zero `notarget on` wrote) cannot pass by coincidence.
const AUTHORED_MOVE_NOISE := 2.5
const AUTHORED_GUN_NOISE := 17.5


## An NPC off-tree (no _ready). Unaligned + HOSTILE is the shipped default: it is hostile to the player.
func _hostile_npc() -> NPC:
	var npc: NPC = load(NPC_PATH).new()
	npc.disposition = Disposition.Kind.HOSTILE
	return npc


## A stand-in for the player: a plain Node in the Player group (is_hostile_to only checks the group + is_hostile()).
func _player_stub() -> Node:
	var p := Node.new()
	p.add_to_group(GroupsScript.PLAYER)
	return p


## A Player double that also carries the two AUTHORED noise exports `notarget` banks and zeroes.
func _noisy_player_double() -> Node:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar noise_move_per_speed: float = %s\nvar noise_gunfire_radius: float = %s\n" % [
		str(AUTHORED_MOVE_NOISE), str(AUTHORED_GUN_NOISE)]
	scr.reload()
	var p: Node = scr.new()
	p.add_to_group(GroupsScript.PLAYER)
	return p


func _notarget(ctx: Dictionary, word: String) -> PackedStringArray:
	var args := PackedStringArray() if word.is_empty() else PackedStringArray([word])
	return WorldActions.run("notarget", ctx, args)


func test_inspector_accessors_are_null_and_inf_before_the_first_tick() -> void:
	var insp = InspectorScript.new()
	assert_null(insp.target(), "no physics tick has run -> no target")
	assert_eq(insp.hit_point(), Vector3.INF, "no physics tick has run -> the INF sentinel, never a stale point")
	insp.free()


func test_inspector_target_refuses_off_tree_and_freed_bodies_and_hit_point_outlives_them() -> void:
	# The cache is written by _refresh_target inside a physics tick (a real raycast); here it is written by hand,
	# because what is under test is the READ side: what target()/hit_point() hand out for each state the cached
	# handle can be in between ticks. Any engine error along the way (a typed-param "previously freed" rejection, an
	# off-tree transform read) fails this test through GUT's error tracker — that IS part of the assertion.
	var insp = InspectorScript.new()
	var body := Node3D.new()
	add_child(body)  # in the tree = a live hit
	var point := Vector3(1.5, 0.0, -3.25)
	insp._target = body
	insp._hit_point = point
	assert_eq(insp.target(), body, "a live in-tree target resolves")
	assert_eq(insp.hit_point(), point, "the impact point of that hit")

	remove_child(body)  # NpcPool.reclaim parks a body OUT of the tree without freeing it (still is_instance_valid)
	assert_null(insp.target(), "an out-of-tree (pooled) body must read null — a global_position on it is an engine error")
	assert_eq(insp.hit_point(), point, "parking the target does not un-hit the point")

	body.free()  # the aimed NPC's queue_free landing: the cached handle now dangles
	assert_null(insp.target(), "a freed target reads null, with no engine error (see _usable's untyped param)")
	assert_eq(insp.hit_point(), point, "hit_point() survives the target being freed — the ray still landed there")

	insp._clear_target()  # what a MISS does on the next tick
	assert_null(insp.target(), "a miss clears the target")
	assert_eq(insp.hit_point(), Vector3.INF, "a miss resets the INF sentinel — never last hit's point")
	insp.free()


func test_notarget_meta_makes_a_hostile_npc_refuse_that_body_only_while_it_is_set() -> void:
	var npc := _hostile_npc()
	var player := _player_stub()
	# CONTROL: without the meta, a hostile NPC engages the player — so a false below is the gate, not the setup.
	assert_true(npc._treats_as_enemy(player), "a hostile NPC must engage an un-ghosted player (control)")

	player.set_meta(NPC.DEBUG_NOTARGET_META, true)
	assert_false(npc._treats_as_enemy(player),
		"a player carrying the ghost meta must never be engaged — otherwise `notarget on` still gets you shot")
	assert_true(npc.is_hostile_to(player),
		"the ghost meta must NOT touch is_hostile_to: shooting a ghost still provokes and sours the faction")

	player.remove_meta(NPC.DEBUG_NOTARGET_META)
	assert_true(npc._treats_as_enemy(player),
		"clearing the meta makes the player a target again — the gate reads the meta live, it does not latch")

	# null is a normal call (no target); the gate must not read a meta off it, and null is never an enemy.
	assert_false(npc._treats_as_enemy(null), "a null node is never an enemy, and reading it raises no engine error")
	npc.free()
	player.free()


func test_notarget_ghost_is_not_engaged_through_the_bodyguard_branch_either() -> void:
	# A bodyguard with NO faction quarrel with the raider still engages it because the raider is hostile to its
	# charge (_treats_as_enemy's protectee branch). A ghosted raider must be refused BEFORE that branch runs.
	var bodyguard: NPC = load(NPC_PATH).new()
	bodyguard.disposition = Disposition.Kind.NEUTRAL
	var raider := _hostile_npc()
	var charge := Node3D.new()
	charge.add_to_group(GroupsScript.PLAYER)  # the raider (unaligned HOSTILE) is hostile to anyone in the Player group
	bodyguard.guard(charge)
	assert_false(bodyguard.is_hostile_to(raider), "setup: the bodyguard has no personal quarrel with the raider")
	assert_true(bodyguard._treats_as_enemy(raider),
		"CONTROL: the bodyguard engages a raider hostile to its charge through the protectee branch")

	raider.set_meta(NPC.DEBUG_NOTARGET_META, true)
	assert_false(bodyguard._treats_as_enemy(raider),
		"a ghost must not be engaged via the protectee branch — the gate has to run before it, not only before is_hostile_to")
	bodyguard.free()
	raider.free()
	charge.free()


func test_notarget_command_ghosts_the_player_for_the_npc_gate_and_off_clears_it() -> void:
	# The writer (debug console) and the reader (NPC gate) live in different files with separately spelled
	# literals; this drives the command and reads its effect through the real gate, so any drift in either
	# spelling, or a writer that stops setting / clearing the meta, shows up as an NPC still engaging the ghost.
	var npc := _hostile_npc()
	var player := _player_stub()
	var ctx := {&"player": player, &"state": {}}
	assert_true(npc._treats_as_enemy(player), "control: before `notarget`, the hostile NPC engages the player")

	var on_lines := _notarget(ctx, "on")
	assert_false(on_lines.is_empty(), "`notarget on` always explains itself (never an empty console reply)")
	assert_false(npc._treats_as_enemy(player), "after `notarget on`, no NPC may engage the player")

	_notarget(ctx, "off")
	assert_true(npc._treats_as_enemy(player), "after `notarget off`, hostiles engage the player again")

	# A bare `notarget` toggles from the CURRENT state of the body, both ways.
	_notarget(ctx, "")
	assert_false(npc._treats_as_enemy(player), "a bare `notarget` while visible turns the ghost ON")
	_notarget(ctx, "")
	assert_true(npc._treats_as_enemy(player), "a bare `notarget` while ghosted turns the ghost OFF")
	npc.free()
	player.free()


func test_notarget_zeroes_the_players_noise_once_and_off_restores_the_authored_values() -> void:
	var player := _noisy_player_double()
	var ctx := {&"player": player, &"state": {}}

	_notarget(ctx, "on")
	var move_on: float = player.get(&"noise_move_per_speed")
	var gun_on: float = player.get(&"noise_gunfire_radius")
	assert_almost_eq(move_on, 0.0, 0.0001, "a ghost's footsteps must be silent, or the noise scan still pulls hostiles to you")
	assert_almost_eq(gun_on, 0.0, 0.0001, "a ghost's gunfire must be silent too")

	_notarget(ctx, "on")  # a repeated `on` must not bank the zero it already wrote over the authored values
	_notarget(ctx, "off")
	var move_off: float = player.get(&"noise_move_per_speed")
	var gun_off: float = player.get(&"noise_gunfire_radius")
	assert_almost_eq(move_off, AUTHORED_MOVE_NOISE, 0.0001,
		"`notarget off` restores the AUTHORED footstep noise even after a repeated `on` — never leaves the player silent")
	assert_almost_eq(gun_off, AUTHORED_GUN_NOISE, 0.0001, "`notarget off` restores the AUTHORED gunfire radius")

	# The bank is spent on `off`: a designer retune between two ghost sessions is what the next `off` restores.
	player.set(&"noise_move_per_speed", 4.0)
	_notarget(ctx, "on")
	_notarget(ctx, "off")
	var move_retuned: float = player.get(&"noise_move_per_speed")
	assert_almost_eq(move_retuned, 4.0, 0.0001,
		"a second ghost session restores the value current when it began, not the first session's stale bank")
	player.free()
