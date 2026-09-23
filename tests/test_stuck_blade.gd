extends GutTest

## END-TO-END for the STUCK BLADE: a thrown weapon the victim SURVIVES is left embedded in the body part it
## struck and rides that part until they die or someone pulls it out. Driven through the real classes in the real
## tree — a live Character with a stubbed BodyModelSwap, a real Throwable blade, the real strike-time decision —
## because `tests/test_part_pinner.gd` pins the arithmetic and pure statics cannot catch "the chain never runs".
## That is not a hypothetical here: the PIN kill, this feature's sibling, shipped once with every unit test green
## and did nothing in game (see the note atop tests/test_pin_kill_integration.gd).
##
## Two seams are covered separately, on purpose:
##   * the DECISION + the RIDE — driven by calling _try_stick_in_body / _follow_stuck_part directly, which is
##     every line of the feature except its one call site, so each degrade can be staged without a damage roll.
##   * the CALL SITE — driven at the bottom through the real contact callback (`_on_body_entered`) with the
##     velocity the solver would have latched, exactly the test_throwable_inert_gore.gd idiom. That is the guard
##     against the bug the pin kill shipped with: every piece correct, and nothing ever calling them — and it
##     also catches a call that exists but sits behind the wrong gate (a blade that sticks only in corpses).
##
## The base `Character` is safe to build in-tree (unlike NPC / Player — see CLAUDE.md): its _ready stamps stats,
## builds the GoreSpawner / DustSpawner / DamageThud helpers and an inventory, and touches no weapon scene, nav
## agent or audio. The part source is duck-typed on `character_parts()`, which is what lets the stub stand in for
## the whole rig — the same seam GoreSpawner finds a real BodyModelSwap through.

const ThrowableScript := preload("res://scripts/components/Throwable.gd")

## `Character` is @abstract, so the test needs a concrete actor. This adds NOTHING — the base class's own
## behaviour is the subject, deliberately without NPC's weapon hub / nav agent / perception or Player's controller.
class StickTestActor extends Character:
	pass

## A stand-in for BodyModelSwap: the ONE method the blade duck-types on, over real in-tree part nodes carrying
## real geometry (the part choice measures a visual AABB, so a part with no mesh is not a part). `view_model_layer`
## is declared because the real rig publishes it and the blade reads it — a bare `set()` on an undeclared property
## is silently dropped, which would make the first-person guard below pass for the wrong reason.
class SwapStub extends Node3D:
	var parts: Array = []
	var view_model_layer: int = 0
	func character_parts() -> Array:
		return parts

const CHEST := Vector3(0.0, 1.1, 0.18)     ## where a knife thrown at the chest comes to a stop
const HEAD := Vector3(0.0, 1.66, 0.18)
const THROW_DIR := Vector3(0.0, 0.0, 1.0)  ## travelling +Z, into the victim

var _victim: Character
var _swap: SwapStub
var _blade: Throwable
var _parts: Dictionary = {}


func _make_part(key: String, at: Vector3, size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = key
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	root.add_child(mi)
	root.position = at
	return root


func _make_blade() -> Throwable:
	var t := ThrowableScript.new() as Throwable
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 0.1, 0.46)  # melee.tres dropped_collision_size
	cs.shape = box
	t.add_child(cs)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = box.size
	mi.mesh = m
	t.add_child(mi)
	t.collision_shape = cs
	t.mesh_instance = mi
	t.auto_fit_collider = false  # keep the authored blade extents; the auto-fit would refit to the placeholder mesh
	t.sticks_in_body = true
	t.thrown_weapon = load("res://resources/weapons/melee.tres") as WeaponData
	return t


func before_each() -> void:
	_victim = StickTestActor.new()
	add_child_autofree(_victim)
	_victim.global_position = Vector3.ZERO
	_victim.max_hp = 100.0   # deliberately beefy: this feature is about the hits people SURVIVE
	_victim.hp = 100.0

	_swap = SwapStub.new()
	_victim.add_child(_swap)
	_parts = {}
	# Roughly the shipped rig's proportions: head high and small, torso at chest height, limbs to the sides.
	var rig := [
		{"key": "torso", "at": Vector3(0.0, 1.1, 0.0), "size": Vector3(0.5, 0.7, 0.3)},
		{"key": "head", "at": Vector3(0.0, 1.65, 0.0), "size": Vector3(0.3, 0.3, 0.3)},
		{"key": "arm_l", "at": Vector3(-0.38, 1.15, 0.0), "size": Vector3(0.14, 0.6, 0.14)},
		{"key": "arm_r", "at": Vector3(0.38, 1.15, 0.0), "size": Vector3(0.14, 0.6, 0.14)},
		{"key": "leg_l", "at": Vector3(-0.16, 0.45, 0.0), "size": Vector3(0.18, 0.8, 0.18)},
		{"key": "leg_r", "at": Vector3(0.16, 0.45, 0.0), "size": Vector3(0.18, 0.8, 0.18)},
	]
	for e in rig:
		var part := _make_part(String(e["key"]), e["at"], e["size"])
		_swap.add_child(part)
		_swap.parts.append({"key": e["key"], "node": part})
		_parts[e["key"]] = part

	_blade = _make_blade()
	add_child_autofree(_blade)
	_blade.global_position = CHEST


## A death here runs the real gore burst, which parents limbs under the tree ROOT (they outlive the level on
## purpose — see GoreSpawner). Left alone they would pile up across tests, so clear them the way
## tests/test_pin_kill_integration.gd does.
func after_each() -> void:
	for g in get_tree().get_nodes_in_group(Groups.GIB):
		if is_instance_valid(g):
			g.free()


## Fire the real strike-time decision the way _try_damage_character does, with the contact point and the travel
## direction a landed throw carries.
func _strike(contact: Vector3, dir: Vector3 = THROW_DIR) -> void:
	_blade.global_position = contact
	_blade._try_stick_in_body(_victim, contact, dir)


# --- The headline ---------------------------------------------------------------------------------------------

func test_a_survived_thrown_hit_leaves_the_blade_in_the_body() -> void:
	_strike(CHEST)
	assert_true(_blade.is_stuck_in_body(),
		"a chest hit the victim walks away from must leave the knife IN them, not bouncing onto the floor")
	assert_true(_blade.freeze,
		"the embedded blade stops being simulated — its pose is written from the part, not solved")
	assert_almost_eq(_blade.gravity_scale, 0.0, 0.0001,
		"...and it does not sag out of the wound under gravity")
	assert_eq(_blade.collision_mask, 0,
		"it detects nothing while riding a body: it must not thud, lure or stab from inside the victim")
	assert_gt(_blade.collision_layer, 0,
		"but it KEEPS its layer — that is what lets PickupRay's aim ray still find it to pull it out")

## A DISTINCT displacement per part of the stub rig. Where a stuck blade sits right after the strike cannot say which
## part it chose (it is seated at the strike point whichever part it then rides), but where it goes when every part
## moves differently can: it travels exactly as far as the part it is buried in.
const PART_NUDGES := {
	"torso": Vector3(0.0, -0.2, 0.0),
	"head": Vector3(0.0, 0.3, 0.0),
	"arm_l": Vector3(-0.25, 0.0, 0.0),
	"arm_r": Vector3(0.25, 0.0, 0.0),
	"leg_l": Vector3(0.0, 0.0, -0.3),
	"leg_r": Vector3(0.0, 0.0, 0.3),
}

## Move every part by its PART_NUDGES offset, replay the ride once, put the parts back, and return how far the blade
## moved — i.e. the nudge of the part it is riding.
func _blade_travel_when_every_part_moves() -> Vector3:
	var before := _blade.global_position
	for key in PART_NUDGES:
		(_parts[key] as Node3D).position += PART_NUDGES[key]
	_blade._follow_stuck_part()
	var moved := _blade.global_position - before
	for key in PART_NUDGES:
		(_parts[key] as Node3D).position -= PART_NUDGES[key]
	return moved

func test_the_blade_ends_up_in_the_part_it_struck() -> void:
	_strike(HEAD)
	assert_true(_blade.is_stuck_in_body(), "a head-height hit sticks")
	assert_almost_eq(_blade_travel_when_every_part_moves(), PART_NUDGES["head"], Vector3.ONE * 0.0001,
		"a head-height strike leaves the knife riding the HEAD — not the torso just below it, not some fixed part")
	_blade.unstick()
	_strike(Vector3(-0.42, 1.15, 0.18))
	assert_true(_blade.is_stuck_in_body(), "an arm hit sticks — arms ship ON for this effect, unlike the wall pin")
	assert_almost_eq(_blade_travel_when_every_part_moves(), PART_NUDGES["arm_l"], Vector3.ONE * 0.0001,
		"...and it rides the LEFT arm it struck, not the right one: the choice resolves LEFT vs RIGHT, which Character.body_part_at cannot")

func test_the_blade_is_driven_into_the_body_not_left_on_its_surface() -> void:
	_strike(CHEST)
	var along := (_blade.global_position - CHEST).dot(THROW_DIR)
	assert_almost_eq(along, GameSettings.effects.stuck_blade_embed, 0.0001,
		"the blade carries on down the throw by exactly the embed depth, so the point is inside the wound")
	assert_lt(_blade.global_basis.z.dot(THROW_DIR), 0.0,
		"and it is posed by the thrown-flight facing, so it goes in point-first rather than hilt-first")


# --- Riding the body ------------------------------------------------------------------------------------------

func test_the_blade_rides_the_victim_as_they_move_and_turn() -> void:
	_strike(CHEST)
	var torso := _parts["torso"] as Node3D
	var before := _blade.global_position - torso.global_position
	_victim.global_position = Vector3(4.0, 0.0, -2.0)
	_victim.rotation.y = PI * 0.5
	_blade._follow_stuck_part()
	var after := _blade.global_position - torso.global_position
	assert_almost_eq(after.length(), before.length(), 0.0001,
		"the guard walks off with it: the knife holds its distance from the part it is buried in")
	assert_gt(_blade.global_position.distance_to(CHEST), 3.0,
		"...which means it is no longer anywhere near where it was thrown")

func test_the_blade_follows_the_part_not_just_the_actor() -> void:
	_strike(HEAD)
	var start := _blade.global_position
	(_parts["head"] as Node3D).position += Vector3(0.0, 0.25, 0.0)  # the head bob / head-look, body standing still
	_blade._follow_stuck_part()
	assert_almost_eq(_blade.global_position.y - start.y, 0.25, 0.0001,
		"a knife in the head swings with the HEAD — the anchor is the part, not the character root")


# --- The three ways out ---------------------------------------------------------------------------------------

func test_death_drops_the_blade_out_of_the_body() -> void:
	_strike(CHEST)
	_victim.take_damage(500.0)  # unsurvivable: is_alive() latches false
	_blade._follow_stuck_part()
	assert_false(_blade.is_stuck_in_body(),
		"the knife does not hang in the air where a dead man's chest used to be")
	assert_false(_blade.freeze,
		"it is handed back to physics so it falls with the body")
	assert_gt(_blade.linear_velocity.length(), 0.0,
		"...with the little outward pop that reads as it coming LOOSE rather than appearing on the floor")

func test_a_freed_part_releases_the_blade() -> void:
	_strike(CHEST)
	(_parts["torso"] as Node3D).queue_free()
	await get_tree().process_frame
	_blade._follow_stuck_part()
	assert_false(_blade.is_stuck_in_body(),
		"the part going away (a level swap, a rebuilt rig) releases the blade instead of stranding it frozen")

func test_unstick_is_idempotent() -> void:
	_strike(CHEST)
	_blade.unstick()
	_blade.gravity_scale = 0.42  # stand in for state a later owner (PickupRay's carry snapshot) now owns
	_blade.unstick()
	assert_almost_eq(_blade.gravity_scale, 0.42, 0.0001,
		"the death poll, the pickup and _exit_tree can all reach unstick for one blade — the second must not stomp")

func test_an_embedded_blade_cannot_restrike_the_body_carrying_it() -> void:
	# The re-touch goes through the real contact callback WITH a stabbing speed latched (_land_throw, below), so the
	# speed gate cannot be what refuses it. The control lands the same contact at the same speed from the same blade
	# once it has been pulled out, and that one wounds.
	_strike(CHEST)
	var hp_before := _victim.hp
	_land_throw(_blade.global_position)
	assert_almost_eq(_victim.hp, hp_before, 0.0001,
		"the victim's own capsule re-touches the hilt every step; the knife in their shoulder must not re-stab them")
	_blade.unstick()
	_land_throw(_blade.global_position)
	assert_lt(_victim.hp, hp_before,
		"control: the same blade, pulled out, wounds on the same fast contact — so it was the embedding that spared the victim above")


# --- The degrades: each of these rebounds and drops, exactly as a thrown prop always did ------------------------

func test_a_victim_with_no_modelled_body_never_takes_a_blade() -> void:
	_swap.parts = []
	_strike(CHEST)
	assert_false(_blade.is_stuck_in_body(),
		"no parts to ride = no stick; the throw plays as an ordinary bounce")

func test_a_first_person_rig_never_takes_a_blade() -> void:
	# The player's view-model arms are a HUD prop drawn over the world, not a body — a knife bolted to them would
	# hang in front of your face forever. Same guard, same reason, as the one that keeps them from gibbing.
	_swap.view_model_layer = 4
	_strike(CHEST)
	assert_false(_blade.is_stuck_in_body(),
		"a first-person rig is not anatomy and never takes an embedded blade")

func test_the_master_switch_turns_it_off() -> void:
	var fx := GameSettings.effects
	var was: bool = fx.stuck_blades_enabled
	fx.stuck_blades_enabled = false
	_strike(CHEST)
	fx.stuck_blades_enabled = was
	assert_false(_blade.is_stuck_in_body(),
		"stuck_blades_enabled off restores the pre-feature behaviour for every throw")

func test_a_part_switched_off_takes_no_blade() -> void:
	var fx := GameSettings.effects
	var was: bool = fx.stuck_blade_legs
	fx.stuck_blade_legs = false
	_strike(Vector3(0.16, 0.45, 0.18))
	fx.stuck_blade_legs = was
	assert_false(_blade.is_stuck_in_body(),
		"a strike nearest a LEG with legs unticked sticks nowhere — and does not stick somewhere ELSE either")

func test_a_dead_stop_never_sticks() -> void:
	_strike(CHEST, Vector3.ZERO)
	assert_false(_blade.is_stuck_in_body(),
		"with no travel direction there is no way in and no pose to author — it must degrade, not guess")

func test_a_blade_already_in_someone_does_not_stick_twice() -> void:
	_strike(CHEST)
	var first := _blade.global_position
	# A second decision on the SAME blade, at the head this time. Called directly rather than through _strike so the
	# helper's "put the prop at the contact point" setup can't be mistaken for the feature having moved it.
	_blade._try_stick_in_body(_victim, HEAD, THROW_DIR)
	_blade._follow_stuck_part()
	assert_almost_eq(_blade.global_position.distance_to(first), 0.0, 0.0001,
		"an embedded blade is inert — it cannot leave one wound for another without being pulled out first")
	assert_lt(_blade.global_position.distance_to((_parts["torso"] as Node3D).global_position), 0.5,
		"...it is still riding the TORSO it went into, not re-anchored to the head")

# --- The call site: a landed throw, through the real contact callback --------------------------------------------

## Fast enough to clear PhysicsDamageSettings.interactable_damage_min_velocity (6 m/s) with room to spare.
const THROW_SPEED := 12.0

## Land the blade on the victim the way the solver does: at `contact`, carrying the velocity latched on the step
## before, through `_on_body_entered`. Every gate between the contact and the stick runs for real. The blade is made
## indestructible so its own impact self-damage can't shatter it and turn the test into one about the prop.
func _land_throw(contact: Vector3, velocity: Vector3 = THROW_DIR * THROW_SPEED) -> void:
	_blade.destructible = false
	_blade.global_position = contact
	_blade._pre_step_velocity = velocity
	_blade._on_body_entered(_victim)

func test_a_landed_throw_the_victim_survives_leaves_the_blade_in_them() -> void:
	var hp_before := _victim.hp
	_land_throw(CHEST)
	assert_lt(_victim.hp, hp_before, "precondition: the thrown knife actually wounded the victim")
	assert_true(_victim.is_alive(), "precondition: a 100 hp victim survives one thrown knife")
	assert_true(_blade.is_stuck_in_body(),
		"a real landed throw the victim survives must leave the knife in them — the damage path has to reach the stick")
	assert_lt(_blade.global_position.distance_to((_parts["torso"] as Node3D).global_position), 0.5,
		"a chest-height throw leaves the knife in the TORSO")

func test_a_landed_throw_sticks_where_it_struck_not_at_the_victim_s_feet() -> void:
	_land_throw(HEAD)
	assert_true(_blade.is_stuck_in_body(), "a survived head-height throw sticks")
	assert_lt(_blade.global_position.distance_to((_parts["head"] as Node3D).global_position), 0.5,
		"the stick must be handed the SAME contact point the damage used, so a knife thrown at the head ends up in the head")

func test_a_killing_throw_leaves_no_blade_in_the_corpse() -> void:
	# Same throw as the survivor test above; only the victim's health differs. A kill belongs to the pin / the death
	# burst, so a knife must never be left riding a corpse.
	_victim.hp = 1.0
	_land_throw(CHEST)
	assert_false(_victim.is_alive(), "precondition: a 1 hp victim dies to the thrown knife")
	assert_false(_blade.is_stuck_in_body(),
		"a throw that KILLS must not embed the knife — sticking is only for the hits people survive")

func test_a_prop_that_did_not_opt_in_never_sticks_from_a_landed_throw() -> void:
	_blade.sticks_in_body = false
	var hp_before := _victim.hp
	_land_throw(CHEST)
	assert_lt(_victim.hp, hp_before, "control: the throw still landed and wounded")
	assert_false(_blade.is_stuck_in_body(),
		"a prop without sticks_in_body bounces off like any thrown prop, however hard it hits")

func test_an_unlocated_bludgeon_never_sticks_from_a_landed_throw() -> void:
	# No thrown_weapon = the velocity bludgeon path, which carries no contact point, so there is nowhere to embed.
	_blade.thrown_weapon = null
	var hp_before := _victim.hp
	_land_throw(CHEST)
	assert_lt(_victim.hp, hp_before, "control: the bludgeon still landed and wounded")
	assert_false(_blade.is_stuck_in_body(),
		"only the located WEAPON path can embed a blade; a tumbling prop that opted in must still bounce")
