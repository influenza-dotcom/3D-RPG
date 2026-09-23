extends GutTest

## PickupRay (ray_cast.gd) T2 liveness bails — a DEAD or DYING player's interaction ray must refuse to act and must not
## keep painting hover cues. The player node stays IN-TREE through the whole death cinematic (take_damage latches
## Character._dead before die(); the in-place revive clears it), so without the bails raw input and the per-frame update
## still route here: an E over a shop / heal / chess freezes the cinematic (C14), and the corpse camera keeps outlining,
## reading out and greeting whatever it sweeps across. Three gates read `(player as Character).is_alive()`: the top of
## _unhandled_input, the top of _physics_process (which swaps the hover updates for _clear_look_cues), and
## interact_available (the E half of the lean / flashlight contextual-key rule).
##
## Every gate test drives the RAY with a LIVE player first as the control, so a gate that refuses everyone fails as
## surely as one that refuses no one. "Not alive" is checked both ways the game presents it: the _dead latch with HP
## still on the frozen corpse, and 0 HP before any latch. The player is a bare concrete Character built via .new() and
## never added to the tree (Character._ready is not run, so the live HP is stamped by hand — an un-readied Character
## has hp 0). The ray is in-tree where the code needs a viewport (the handled-input call) or a physics space (the talk
## query), with its own physics_process OFF so only the frames a test drives by hand run.

## Concrete stand-in for the @abstract Character base (mirrors test_smoke._ConcreteCharacter / test_character._Stub).
class _Stub extends Character:
	pass


## A look-at talk target: the duck-typed handler surface the ray calls by name (start_talk / set_look_highlight, the
## LookAtInteractable seam), recording what the ray did to it. No can_be_talked_to, so TalkHelpers treats it as
## talkable — it is a target a LIVE player can always act on.
class _TalkSpy extends Node3D:
	var talk_calls: int = 0
	var talked_with: Node = null
	var lit: bool = false
	var times_lit: int = 0

	func start_talk(who: Node) -> void:
		talk_calls += 1
		talked_with = who

	func set_look_highlight(on: bool) -> void:
		lit = on
		if on:
			times_lit += 1


var _root: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)


func _live_player() -> Character:
	var c: Character = autofree(_Stub.new())
	c.hp = c.max_hp  # _ready (which seeds this) is intentionally not run off-tree
	return c


## An in-tree PickupRay at the origin looking down -Z, wielded by `c`.
func _make_ray(c: Character) -> PickupRay:
	var ray := PickupRay.new()
	_root.add_child(ray)
	ray.global_transform = Transform3D.IDENTITY
	ray.set_physics_process(false)
	ray.player = c
	return ray


## A talk spy with a real talk-layer hitbox at `pos`, so the ray's own look-at query finds it.
func _talk_target_at(pos: Vector3) -> _TalkSpy:
	var spy := _TalkSpy.new()
	_root.add_child(spy)
	spy.global_position = pos
	var hitbox := Area3D.new()
	hitbox.collision_layer = TalkHelpers.TALK_LAYER
	hitbox.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	shape.shape = box
	hitbox.add_child(shape)
	spy.add_child(hitbox)
	return spy


## `c` presses Interact while the ray already has a talkable under the crosshair; returns the target to inspect.
func _press_interact_over_a_talkable(c: Character) -> _TalkSpy:
	var ray := _make_ray(c)
	var spy := _TalkSpy.new()
	_root.add_child(spy)
	ray._talk_handler = spy
	var press := InputEventAction.new()
	press.action = InputManager.action_pickup
	press.pressed = true
	ray._unhandled_input(press)
	return spy


func test_interact_press_starts_a_talk_for_the_living_but_not_for_a_dead_or_dying_player() -> void:
	var live := _live_player()
	var control := _press_interact_over_a_talkable(live)
	assert_eq(control.talk_calls, 1,
		"CONTROL: a live player's E over a talkable must start the talk — otherwise the refusals below prove nothing")
	assert_true(control.talked_with == live, "CONTROL: the ray hands the talk its own player")

	var latched := _live_player()
	latched._dead = true  # take_damage latches this before die(); HP is still on the frozen corpse
	assert_eq(_press_interact_over_a_talkable(latched).talk_calls, 0,
		"an E pressed during the death cinematic must not open a talk / shop / heal / chess over it (C14)")

	var bled_out := _live_player()
	bled_out.hp = 0.0  # no latch yet, but no HP either
	assert_eq(_press_interact_over_a_talkable(bled_out).talk_calls, 0,
		"an E pressed at 0 HP must not start a talk either — the bail reads liveness, not just the latch")


func test_a_dead_or_dying_players_ray_offers_no_interact_even_while_carrying() -> void:
	# Carrying is the state where E ALWAYS means something (arm the release), so it is the strongest control: the lean
	# (Q) and the flashlight (F) only claim the shared key when this says the ray has nothing to do.
	var ray := PickupRay.new()
	var c := _live_player()
	ray.player = c
	ray._holding = true
	assert_true(ray.interact_available(), "CONTROL: a live player carrying a prop has an interact on E")
	assert_eq(ray.pending_verb_action(), InputManager.action_pickup,
		"CONTROL: the ray reports Interact as its pending verb while a live player carries")

	c._dead = true
	assert_false(ray.interact_available(), "a death-latched player's E does nothing, even with a prop still flagged held")
	assert_eq(ray.pending_verb_action(), &"", "a dead player's ray reports no pending verb for the lean / torch to defer to")

	c._dead = false
	c.hp = 0.0
	assert_false(ray.interact_available(), "a player at 0 HP (no latch yet) has no interact on E either")
	ray.free()


func test_hover_cues_clear_on_death_stay_clear_through_the_cinematic_and_resume_on_revive() -> void:
	var c := _live_player()
	var ray := _make_ray(c)
	var spy := _talk_target_at(Vector3(0, 0, -2))  # 2 m straight down the look ray, well inside TALK_REACH
	await get_tree().physics_frame
	await get_tree().physics_frame

	ray._physics_process(0.016)
	assert_true(spy.lit, "CONTROL: a live player looking at a talkable 2 m ahead lights it up")
	assert_true(ray._talk_handler == spy, "CONTROL: the looked-at talkable becomes the talk handler")
	assert_true(ray._readout_shown, "CONTROL: its name readout is up")

	c._dead = true  # the cinematic begins with the target still under the crosshair
	ray._physics_process(0.016)
	assert_false(spy.lit, "the first dead frame turns the look-highlight OFF on what the corpse camera still points at")
	assert_true(ray._talk_handler == null, "the first dead frame drops the talk handler")
	assert_false(ray._readout_shown, "the first dead frame takes the name readout down")

	ray._physics_process(0.016)
	assert_eq(spy.times_lit, 1,
		"later cinematic frames hold the cues cleared — the target is still under the crosshair but is never re-lit")
	assert_true(ray._talk_handler == null, "later cinematic frames never re-adopt the target as the talk handler")

	c._dead = false  # the in-place checkpoint revive
	c.hp = c.max_hp
	ray._physics_process(0.016)
	assert_true(spy.lit, "after the revive the hover updates resume and re-light the target")
	assert_true(ray._talk_handler == spy, "after the revive the target is the talk handler again")

	c.hp = 0.0  # bled out, before any latch lands
	ray._physics_process(0.016)
	assert_false(spy.lit, "0 HP alone clears the hover cues too")
	assert_true(ray._talk_handler == null, "0 HP alone drops the talk handler")


func test_clear_look_cues_resets_hover_state() -> void:
	# The dead-player per-frame gate calls _clear_look_cues() every physics frame of the cinematic — it must drop
	# EVERY hover-cue field (talk handler, look-highlight target, distance sentinel, readout latch) so nothing
	# lingers highlighted or read out on the corpse's crosshair. Off-tree PickupRay (.new(), no _ready, no live
	# raycast): seed the look-state by hand and assert one call resets it all. `player` stays null, so
	# _drive_readout's `as Player` downcast is null and the HUD push is skipped — the STATE reset is the contract
	# pinned here. The stand-in handler is a plain Node with no set_look_highlight, exercising the has_method guard.
	var ray := PickupRay.new()
	var handler := Node.new()
	ray._talk_handler = handler
	ray._highlighted = handler
	ray._talk_distance = 2.0
	ray._readout_shown = true
	ray._clear_look_cues()
	assert_null(ray._talk_handler, "dead-player clear must drop the talk handler")
	assert_null(ray._highlighted, "dead-player clear must drop the look-highlight target")
	assert_eq(ray._talk_distance, INF, "dead-player clear must reset the talk-distance sentinel")
	assert_false(ray._readout_shown, "dead-player clear must clear the readout-shown latch")
	handler.free()
	ray.free()
