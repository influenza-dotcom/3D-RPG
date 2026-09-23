extends GutTest

## GunPose's IDLE LOWER — the "you haven't fired in a while, so the weapon isn't pointed at anyone" pose.
##
## ⭐WHY THIS FILE EXISTS. The droop shipped for a long time as `target_rot.x -= idle_lower_pitch_deg`, which
## reads correct and is not: GunMesh carries a baked 90° YAW (weapon meshes run their barrel down local +X),
## and under Node3D's YXZ euler order that yaw hands `.x` the CAMERA-FORWARD axis. So the "droop" spun the
## gun about its own barrel — a pure screen roll, muzzle unmoved — and the feature read as "the gun tilts
## over to the left" for every player who saw it. Nothing errored, nothing was off-screen, and no assertion
## on the export could see it, because the export was fine; the CHANNEL was wrong.
##
## So this suite never asserts on euler components. It asks the only question that can't be fooled — where
## does the BARREL end up pointing — through GunPose.barrel_direction(), and it asks it over arbitrary
## poses rather than the one clean pose, because the pose solve stacks sway / bob / breath / recoil into the
## same triple every frame. (Same lesson as Player.fp_arm_stow_target: a view-model defect that only
## reproduces at the authored pose needs a pose-agnostic pure static to pin, not an export assertion.)

const AUTHORED_YAW := 90.0

## The camera-rig pose plus a spread of the junk the per-frame solve really adds on top: strafe roll, walk
## bob, breath pitch, mouse sway, a landing kick. Every one of these must still leave the droop drooping.
const POSE_NOISE: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(3.0, 0.0, 0.0),
	Vector3(-6.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 2.5),
	Vector3(0.0, 0.0, -4.0),
	Vector3(1.2, 0.0, 0.6),
	Vector3(-8.0, 0.0, 5.0),
	Vector3(0.5, 2.0, -1.5),
]


func _pose(noise: Vector3) -> Vector3:
	return Vector3(0.0, AUTHORED_YAW, 0.0) + noise


## The whole point of the feature: after the droop the barrel must be aimed further DOWN than before it,
## from whatever pose the frame's sway/bob/recoil left behind. Camera forward is -Z, so "down" is a smaller
## y on the barrel vector.
func test_idle_lower_aims_the_barrel_downward_from_any_pose() -> void:
	for noise in POSE_NOISE:
		var rest := _pose(noise)
		var lowered := GunPose.apply_idle_lower(rest, 18.0, 1.0)
		var before := GunPose.barrel_direction(rest).y
		var after := GunPose.barrel_direction(lowered).y
		assert_lt(after, before - 0.2,
			"the idle-lower must drop the muzzle from pose %s — barrel y went %.3f -> %.3f (a droop that " \
			% [rest, before, after] + "leaves the barrel where it was is the roll bug this feature shipped with)")


## The regression itself, pinned as an executable statement rather than a comment: at the authored yaw the
## `.x` channel — the one the droop USED to be written into — cannot pitch the muzzle at all. If someone
## "simplifies" apply_idle_lower back to `rot.x -= pitch`, this is the test that explains why not.
func test_the_x_channel_cannot_droop_this_rig() -> void:
	var rest := _pose(Vector3.ZERO)
	var x_channel := rest - Vector3(18.0, 0.0, 0.0)
	assert_almost_eq(GunPose.barrel_direction(x_channel).y, GunPose.barrel_direction(rest).y, 0.001,
		"writing the droop into rotation_degrees.x must NOT move the muzzle — with GunMesh's baked 90 deg " +
		"yaw that channel rolls the gun about its own barrel, which is exactly how 'the gun tilts over to " +
		"the left instead of pointing down' shipped")


## ...and the flip side: the droop must not sneak a roll in either, or the fix would just trade one wrong
## axis for two. A pure pitch leaves the gun's own up vector in the camera's vertical plane (no x component).
func test_idle_lower_adds_no_screen_roll() -> void:
	var lowered := GunPose.apply_idle_lower(_pose(Vector3.ZERO), 18.0, 1.0)
	var rads := Vector3(deg_to_rad(lowered.x), deg_to_rad(lowered.y), deg_to_rad(lowered.z))
	var gun_up: Vector3 = Basis.from_euler(rads, EULER_ORDER_YXZ) * Vector3.UP
	assert_almost_eq(gun_up.x, 0.0, 0.001,
		"the idle-lower must be pitch only — a non-zero x on the gun's up vector means it is leaning " +
		"sideways on screen again")


## The blend is the ease GunPose runs every frame (_idle_lower_t), so the helper has to be linear in it and
## a strict no-op at rest — a droop that bites at t = 0 would droop a weapon that is being aimed or fired.
func test_idle_lower_scales_with_the_blend() -> void:
	var rest := _pose(Vector3(2.0, 0.0, -1.0))
	assert_eq(GunPose.apply_idle_lower(rest, 18.0, 0.0), rest,
		"at blend 0 the idle-lower must return the pose untouched — the weapon is up")
	assert_almost_eq(GunPose.apply_idle_lower(rest, 18.0, 0.5).z, rest.z - 9.0, 0.001,
		"the droop must scale linearly with the eased blend so the pose can tween in and out")


## apply_idle_lower's whole premise is GunMesh's authored ±90 deg yaw. Re-author that transform (a re-import
## that lands the barrel down -Z, say) and the static silently starts writing the droop into a roll again —
## with no error anywhere. Read the authored value straight out of the scene TEXT (str_to_var parses the
## Transform3D literal, the preview_fists_frame.gd idiom) so this stays a pure off-tree contract check: no
## PackedScene instantiate, no Player._ready, no autoloads.
func test_camera_rig_still_mounts_the_gun_at_the_yaw_this_maths_assumes() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/player/camera_rig.tscn")
	assert_false(src.is_empty(), "camera_rig.tscn must be readable — it is where the GunMesh pose is authored")
	var marker := '[node name="GunMesh" parent="ScreenShake/Camera3D"'
	var at := src.find(marker)
	assert_gt(at, -1, "camera_rig.tscn must still mount a GunMesh under ScreenShake/Camera3D")
	if at < 0:
		return
	var line_at := src.find("transform = ", at)
	var literal := src.substr(line_at + 12, src.find("\n", line_at) - line_at - 12).strip_edges()
	var xform: Variant = str_to_var(literal)
	assert_true(xform is Transform3D, "the GunMesh node must carry a Transform3D — got '%s'" % literal)
	if not (xform is Transform3D):
		return
	var yaw := rad_to_deg((xform as Transform3D).basis.get_euler(EULER_ORDER_YXZ).y)
	assert_almost_eq(absf(yaw), AUTHORED_YAW, 0.5,
		"GunMesh must stay mounted at a 90 deg yaw (got %.2f) — that yaw is what makes rotation_degrees.z " \
		% yaw + "the muzzle-pitch channel, which is the assumption baked into GunPose.apply_idle_lower")


## --- The SPRINT pose (GunPose's Sprint group) ---
## Same rule as the droop above: never assert on an euler channel, ask where the barrel points. The sprint pose's
## whole look is "carried across the body", so at the SHIPPED knobs the muzzle must swing clearly LEFT of where
## it rests, from any of the poses the per-frame solve stacks up.
func test_sprint_pose_swings_the_muzzle_across_the_body() -> void:
	var gp := GunPose.new()
	for noise in POSE_NOISE:
		var rest := _pose(noise)
		var sprint := GunPose.apply_sprint_pose(rest, gp.sprint_pitch_deg, gp.sprint_yaw_deg, gp.sprint_roll_deg, 1.0)
		var before := GunPose.barrel_direction(rest).x
		var after := GunPose.barrel_direction(sprint).x
		assert_lt(after, before - 0.3,
			"the shipped sprint pose must swing the muzzle across the body (left) from pose %s — barrel x went " \
			% rest + "%.3f -> %.3f" % [before, after])
	gp.free()


## The blend is _sprint_t, eased every frame, so the pose must be a strict no-op at 0 (every non-sprinting frame
## runs through it) and linear in between so it eases in and out.
func test_sprint_pose_scales_with_the_blend() -> void:
	var rest := _pose(Vector3(2.0, 0.0, -1.0))
	assert_eq(GunPose.apply_sprint_pose(rest, 3.0, 50.0, 40.0, 0.0), rest,
		"at blend 0 the sprint pose must return the pose untouched — a gun that is not sprinting")
	var half := GunPose.apply_sprint_pose(rest, 10.0, 50.0, 40.0, 0.5)
	assert_almost_eq(half.y, rest.y + 25.0, 0.001, "half the blend must be half the yaw")
	assert_almost_eq(half.z, rest.z - 5.0, 0.001, "half the blend must be half the muzzle-down pitch")
	assert_almost_eq(half.x, rest.x + 20.0, 0.001, "half the blend must be half the roll")


## sprint_pitch_deg is named for what it does: positive tips the MUZZLE DOWN, through the same channel the idle
## droop proved is the real pitch on this rig.
func test_sprint_pitch_tips_the_muzzle_down() -> void:
	var rest := _pose(Vector3.ZERO)
	assert_lt(GunPose.barrel_direction(GunPose.apply_sprint_pose(rest, 20.0, 0.0, 0.0, 1.0)).y,
		GunPose.barrel_direction(rest).y - 0.2,
		"a positive sprint_pitch_deg must aim the barrel further down, not roll the gun")


## The latch. is_sprinting() needs the floor, so it drops for every sprint-jump and for single frames on brush
## seams; the pose must hold through those or it jitters. But nothing that ends the sprint may be held over:
## landing, letting go of Run, or the lockout a trigger pull starts (all of which clear still_wants).
func test_sprint_pose_latch_holds_through_the_air_only_while_still_sprinting() -> void:
	assert_true(GunPose.sprint_pose_wanted(false, true, false, true), "sprinting on the ground wants the pose")
	assert_true(GunPose.sprint_pose_wanted(true, false, true, true),
		"airborne mid-sprint (a jump, or an is_on_floor blip) must HOLD the pose while Run is still held")
	assert_false(GunPose.sprint_pose_wanted(false, false, true, true),
		"airborne without having been sprinting must not START the pose")
	assert_false(GunPose.sprint_pose_wanted(true, false, true, false),
		"a trigger pull mid-air locks sprint out (still_wants false) — the pose must drop even in the air")
	assert_false(GunPose.sprint_pose_wanted(true, false, false, true),
		"grounded and not sprinting (slowed, crouched, scoped) must drop the pose")


## The fire gate Attack reads. While the pose is wanted you cannot fire at all; once it isn't, the gun has to come
## up past the ready blend first.
func test_sprint_lowered_gate() -> void:
	assert_true(GunPose.sprint_lowered_now(true, 0.0, 0.15),
		"a sprint in progress blocks the trigger even before the gun has eased down")
	assert_true(GunPose.sprint_lowered_now(false, 0.5, 0.15), "a gun still halfway into the sprint pose can't fire")
	assert_false(GunPose.sprint_lowered_now(false, 0.1, 0.15), "a gun back up past the ready blend can fire")


## "Stop sprinting and shoot" must stay quick: the shipped out-speed and ready blend decide how long a trigger
## pull made mid-sprint waits (an exponential ease from a full pose: ln(1 / ready) / out_speed seconds). A retune
## that pushes that wait past ~0.15 s turns the sprint-out into input lag; retune the pair together.
func test_shipped_sprint_out_wait_stays_short() -> void:
	var gp := GunPose.new()
	assert_gt(gp.sprint_fire_ready_blend, 0.0, "a ready blend of 0 never opens — the exponential ease never reaches 0")
	assert_gt(gp.sprint_out_speed, 0.0, "a zero out-speed never brings the gun up")
	var wait := log(1.0 / gp.sprint_fire_ready_blend) / gp.sprint_out_speed
	assert_lt(wait, 0.15,
		"a trigger pull made mid-sprint waits %.3f s for the gun to come up — keep it under 0.15 s" % wait)
	gp.free()
