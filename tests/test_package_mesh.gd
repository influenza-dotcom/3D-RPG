extends GutTest

## package_mesh.gd (scenes/levels/package_mesh.gd) — the spin-and-bob idle on a pickup mesh (SliceTestLevel's
## package). Pure per-frame math, so it pins by driving _process by hand:
##   * _ready captures the AUTHORED local position as the bob's reference (so a placed prop bobs around where the
##     designer put it, not around the origin);
##   * the bob is a sine on Y only — X/Z stay exactly authored, amplitude peaks at a quarter cycle and returns at
##     a full one, and it is frame-rate independent (many small deltas == one big delta);
##   * the spin is rotation_speed rad/s about the local Y.

const SCRIPT_PATH := "res://scenes/levels/package_mesh.gd"
const ORIGIN := Vector3(2.0, 1.0, -3.0)


func _package(freq: float = 1.5, amp: float = 0.5, spin: float = 2.0):
	var p = load(SCRIPT_PATH).new()
	p.bobbing_frequency = freq
	p.bobbing_amplitude = amp
	p.rotation_speed = spin
	p.position = ORIGIN
	add_child_autofree(p)  # _ready captures the authored position
	return p


func test_exported_defaults() -> void:
	var p = load(SCRIPT_PATH).new()
	assert_eq(p.rotation_speed, 2.0, "2 rad/s spin")
	assert_eq(p.bobbing_amplitude, 0.5, "0.5 m bob")
	assert_eq(p.bobbing_frequency, 1.5, "1.5 bobs/s")
	assert_true(p is Node3D, "a Node3D (it moves and rotates itself)")
	p.free()


func test_ready_captures_the_authored_position_as_the_bob_reference() -> void:
	var p = _package()
	assert_eq(p._original_position, ORIGIN, "the reference is the position at _ready, not the origin")
	p._process(0.0)
	assert_almost_eq(p.position, ORIGIN, Vector3.ONE * 0.0001, "at t=0 the prop sits exactly where it was placed")


func test_bob_is_a_sine_on_y_only() -> void:
	var p = _package(1.0, 0.5)  # 1 bob/s: quarter cycle = 0.25 s
	p._process(0.25)
	assert_almost_eq(p.position.y, ORIGIN.y + 0.5, 0.0001, "a quarter cycle in, the bob peaks at +amplitude")
	assert_eq(p.position.x, ORIGIN.x, "X never moves")
	assert_eq(p.position.z, ORIGIN.z, "Z never moves")
	p._process(0.5)  # t = 0.75
	assert_almost_eq(p.position.y, ORIGIN.y - 0.5, 0.0001, "three quarters in, the bob bottoms at -amplitude")
	p._process(0.25)  # t = 1.0
	assert_almost_eq(p.position.y, ORIGIN.y, 0.0001, "a full cycle returns to the authored height")


func test_bob_is_frame_rate_independent() -> void:
	var a = _package(1.5, 0.5)
	var b = _package(1.5, 0.5)
	a._process(0.3)
	for i in 30:
		b._process(0.01)
	assert_almost_eq(a.position.y, b.position.y, 0.001, "thirty 10 ms frames land where one 300 ms frame does — the timer sums deltas")


func test_spin_advances_rotation_by_speed_times_delta() -> void:
	var p = _package(1.5, 0.5, 2.0)
	p._process(0.5)
	assert_almost_eq(p.rotation.y, 1.0, 0.0001, "2 rad/s for 0.5 s = 1 rad about local Y")
	assert_almost_eq(p.rotation.x, 0.0, 0.0001, "no pitch")
	assert_almost_eq(p.rotation.z, 0.0, 0.0001, "no roll")
	p._process(0.5)
	assert_almost_eq(p.rotation.y, 2.0, 0.0001, "the spin accumulates (endless)")


func test_zero_amplitude_holds_the_authored_position_while_still_spinning() -> void:
	var p = _package(1.5, 0.0, 2.0)
	p._process(0.4)
	assert_almost_eq(p.position, ORIGIN, Vector3.ONE * 0.0001, "amplitude 0 = no bob at all")
	assert_gt(p.rotation.y, 0.0, "…but it still spins")
