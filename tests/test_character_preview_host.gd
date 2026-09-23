extends GutTest

## The character-preview HOST (scripts/ui/character_preview_host.gd) — the duck-typed stand-in BodyModelSwap
## parents under on the creation screen's turntable. The swap poses its limbs and breathes off its PARENT through
## duck-typed reads (HostMethodHelper.try_call_bool for is_holding_gun / is_on_floor / has_sensed_foe / is_fists_out /
## is_climbing, and host.get for `velocity` / `hp`), and character_preview.gd flips the host's one variable with
## host.set(&"holding", show_gun) when a weapon is mounted.
##
## So the host is judged by what the REAL swap does under it. A BodyModelSwap is hung off it OFF-TREE (bare Node3D
## arm stubs, never _ready — the test_body_model_swap_strike idiom) and the swap's own gait (_animate_limbs) and
## breathing (_breathe) are driven. Poses are compared against reference hosts built here — one that answers nothing
## (the swap's neutral read), one with a gun drawn, one in the air, one dead — so a failure names what the player would
## SEE on the turntable, not a field read back off the host.

const PATH := "res://scripts/ui/character_preview_host.gd"
const SWAP_SCRIPT := preload("res://scripts/components/body_model_swap.gd")

## One gait frame long enough that every eased arm term (the slowest rate in _animate_limbs is 10/s) lands exactly on
## its target, whatever pose the rig started in.
const SETTLE_DELTA: float = 10.0
## A short gait frame, repeated, for the tests that need the walk swing or the air pose to build up over time.
const FRAME_DELTA: float = 0.1
const FRAMES: int = 6


## A host with its weapon drawn — the pose an armed NPC wears, which a mounted preview weapon must match.
class _ArmedHost extends Node3D:
	func is_holding_gun() -> bool:
		return true


## A host in mid-air — the swap throws an unarmed body's arms straight up (the roller-coaster pose).
class _AirborneHost extends Node3D:
	func is_on_floor() -> bool:
		return false


## A host whose hp reads zero — a corpse, which must not breathe.
class _DeadHost extends Node3D:
	var hp: float = 0.0


func _host() -> Node3D:
	return load(PATH).new()


## A swap under `host` wearing the shipped NPC arm placement, with two bare Node3D arm stubs — all _animate_limbs needs
## off-tree. No legs, so the leg-yaw branch (which reads global_transform) never runs.
func _rig(host: Node3D) -> BodyModelSwap:
	var s := SWAP_SCRIPT.new() as BodyModelSwap
	s.arm_scale = 0.35
	s.arm_position = Vector3(-0.27, 0.155, -0.05)
	s.arm_rotation = Vector3(90, 0, 0)
	host.add_child(s)
	for side in ["_arm_left", "_arm_right"]:
		var stub := Node3D.new()
		s.add_child(stub)
		s.set(side, stub)
	return s


## The left arm's pose after `frames` gait frames of `delta` on a fresh rig under `host`.
func _left_arm_after(host: Node3D, frames: int = 1, delta: float = SETTLE_DELTA) -> Transform3D:
	var s := _rig(host)
	for _i in frames:
		s._animate_limbs(delta, false)
	return (s._arm_left as Node3D).transform


## Where the arm's HAND points from its shoulder (the arm model's hand lies down its local +Z).
func _hand_dir(pose: Transform3D) -> Vector3:
	return (pose.basis * Vector3(0, 0, 1)).normalized()


func test_has_no_class_name() -> void:
	# A private preview helper, path-preloaded by character_preview.gd — deliberately off the global class cache.
	var script: Script = load(PATH)
	assert_eq(script.get_global_name(), StringName(""), "character_preview_host.gd must not register a class_name")

func test_a_fresh_preview_actor_stands_still_grounded_and_unarmed() -> void:
	var preview := _host()
	var neutral := Node3D.new()  # answers nothing: every read falls back to the swap's grounded / still / unarmed default
	var rest := _left_arm_after(preview, FRAMES, FRAME_DELTA)
	assert_true(rest.is_equal_approx(_left_arm_after(neutral, FRAMES, FRAME_DELTA)),
		"a fresh preview actor must wear exactly the pose of a body that is grounded, still and unarmed — no walk swing, no airborne flail, no raised arms")
	assert_lt(_hand_dir(rest).y, -0.9, "at rest the preview's arms must hang by its side")
	# Control 1: the same frames under an AIRBORNE host throw the arms up, so the rig can see a non-rest pose.
	var airborne := _AirborneHost.new()
	assert_gt(_hand_dir(_left_arm_after(airborne, FRAMES, FRAME_DELTA)).y, 0.0,
		"control: an airborne body throws its arms up — the grounded verdict above is a real one")
	# Control 2: the same preview host pushed into motion walk-swings its arms, so its zero velocity is what keeps it still.
	var walker := _host()
	walker.set(&"velocity", Vector3(2.0, 0.0, 0.0))
	assert_false(_left_arm_after(walker, FRAMES, FRAME_DELTA).is_equal_approx(rest),
		"control: a moving host swings the arms — the still pose above depends on the preview never moving")
	preview.free()
	neutral.free()
	airborne.free()
	walker.free()

func test_mounting_a_weapon_raises_the_arms_onto_it_and_unmounting_drops_them() -> void:
	# character_preview._mount_weapon writes the flag through Object.set on an Object-typed handle — a SILENT no-op if
	# the property is ever renamed — so the test writes it the same way, never through the typed field.
	var preview := _host()
	var s := _rig(preview)
	s._animate_limbs(SETTLE_DELTA, false)
	var rest := (s._arm_left as Node3D).transform
	(preview as Object).set(&"holding", true)
	s._animate_limbs(SETTLE_DELTA, false)
	var held := (s._arm_left as Node3D).transform
	var armed := _ArmedHost.new()
	assert_true(held.is_equal_approx(_left_arm_after(armed)),
		"a mounted weapon must put the preview's arms in exactly the two-handed hold an NPC with its gun drawn wears")
	assert_gt(_hand_dir(held).y, _hand_dir(rest).y, "...which lifts the hands off the side and onto the gun")
	(preview as Object).set(&"holding", false)
	s._animate_limbs(SETTLE_DELTA, false)
	assert_true((s._arm_left as Node3D).transform.is_equal_approx(rest),
		"unmounting the weapon must drop the preview's arms back to the rest pose")
	preview.free()  # frees the rig and its arm stubs
	armed.free()

func test_the_preview_actor_breathes_because_it_reads_as_alive() -> void:
	# BodyModelSwap._breathe reads host.get(&"hp") and treats a MISSING hp as alive; the preview host deliberately
	# carries none, so the showcase keeps its idle chest rise. Driven on a stub torso (the swap's `_body`).
	var preview := _host()
	var s := _rig(preview)
	var chest := Node3D.new()
	s.add_child(chest)
	s._body = chest
	s._breathe(0.5)
	assert_false(chest.scale.is_equal_approx(Vector3.ONE * s._body_base_scale),
		"the preview actor must breathe — its chest must move off the authored rest scale")
	# Control: the identical rig and frame under a host whose hp reads 0 holds the chest still.
	var corpse := _DeadHost.new()
	var cs := _rig(corpse)
	var still_chest := Node3D.new()
	cs.add_child(still_chest)
	cs._body = still_chest
	cs._breathe(0.5)
	assert_true(still_chest.scale.is_equal_approx(Vector3.ONE * cs._body_base_scale),
		"control: a host that reads as dead rests the chest at its authored scale — so the breathing above is the alive verdict")
	preview.free()
	corpse.free()
