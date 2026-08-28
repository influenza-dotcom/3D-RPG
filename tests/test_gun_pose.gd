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
