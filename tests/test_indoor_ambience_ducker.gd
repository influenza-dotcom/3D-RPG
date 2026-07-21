extends GutTest

## IndoorAmbienceDucker: casts an up-ray fan and, when a roof is overhead, cross-fades a target ambient bed down
## and writes host.is_indoors. Verifies the pure vote/fade math, the config warnings, host auto-wire, and — in a
## tiny in-tree scene — that a roof box above the host is DETECTED (ducks + flags indoors) while open sky is not.

const DuckerScript = preload("res://scripts/components/indoor_ambience_ducker.gd")

# --- pure helpers ---------------------------------------------------------------------------------------------

func test_coverage_fraction() -> void:
	assert_almost_eq(DuckerScript.coverage_fraction(0, 5), 0.0, 0.001, "no hits => 0")
	assert_almost_eq(DuckerScript.coverage_fraction(5, 5), 1.0, 0.001, "all hits => 1")
	assert_almost_eq(DuckerScript.coverage_fraction(2, 4), 0.5, 0.001, "half hits => 0.5")
	assert_almost_eq(DuckerScript.coverage_fraction(3, 0), 0.0, 0.001, "empty fan => 0, not a divide-by-zero")

func test_is_covered_threshold() -> void:
	assert_false(DuckerScript.is_covered(2, 5, 0.5), "2/5 = 0.4 is below a 0.5 threshold => outdoors")
	assert_true(DuckerScript.is_covered(3, 5, 0.5), "3/5 = 0.6 meets the 0.5 threshold => indoors")
	assert_true(DuckerScript.is_covered(1, 2, 0.5), "exactly at the threshold counts as covered")
	assert_false(DuckerScript.is_covered(0, 5, 0.01), "no hits is never covered")

func test_step_db_eases_and_clamps() -> void:
	assert_almost_eq(DuckerScript.step_db(0.0, 10.0, 5.0, 1.0), 5.0, 0.001, "moves 5 dB/s toward the target")
	assert_almost_eq(DuckerScript.step_db(5.0, 10.0, 5.0, 1.0), 10.0, 0.001, "clamps at the target, no overshoot")
	assert_almost_eq(DuckerScript.step_db(10.0, 0.0, 5.0, 1.0), 5.0, 0.001, "eases back down toward a lower target")
	assert_almost_eq(DuckerScript.step_db(3.0, -20.0, 0.0, 1.0), 3.0, 0.001, "zero fade speed => no movement")

func test_approach_exp_eases_toward_target() -> void:
	# Frame-rate-independent exponential approach: never overshoots, and a huge rate snaps.
	assert_almost_eq(DuckerScript.approach_exp(20500.0, 12000.0, 100000.0, 0.1), 12000.0, 1.0, "a huge rate reaches the target in one step")
	assert_almost_eq(DuckerScript.approach_exp(12000.0, 12000.0, 4.0, 0.1), 12000.0, 0.001, "already at target => stays")
	assert_almost_eq(DuckerScript.approach_exp(20500.0, 12000.0, 0.0, 0.1), 12000.0, 0.001, "rate 0 => snap to target")
	var mid := DuckerScript.approach_exp(20500.0, 12000.0, 4.0, 0.1)
	assert_lt(mid, 20500.0, "moves toward the (lower) target")
	assert_gt(mid, 12000.0, "but hasn't overshot past it in one small step")

# --- config warnings ------------------------------------------------------------------------------------------

func test_warns_on_missing_bus() -> void:
	var d = DuckerScript.new()
	d.bus = &"definitely_not_a_real_bus"
	assert_true(_has_warning(d._get_configuration_warnings(), "bus"), "an unknown bus warns")
	d.free()

func test_warns_on_unresolvable_target() -> void:
	var d = DuckerScript.new()
	d.bus = &"ambient"  # a real bus so only the target warning fires
	d.target = NodePath("NoSuchNode")
	assert_true(_has_warning(d._get_configuration_warnings(), "target"), "a target NodePath that resolves to nothing warns")
	d.free()

func test_warns_when_indoor_not_below_outdoor() -> void:
	var d = DuckerScript.new()
	d.bus = &"ambient"
	d.indoor_db = 0.0
	d.outdoor_db = -6.0
	assert_true(_has_warning(d._get_configuration_warnings(), "duck"), "indoor_db >= outdoor_db warns (it wouldn't duck)")
	d.free()

func test_warns_on_missing_muffle_bus() -> void:
	var d = DuckerScript.new()
	d.bus = &"ambient"
	d.enable_muffle = true
	d.muffle_bus = &"no_such_bus"
	assert_true(_has_warning(d._get_configuration_warnings(), "muffle"), "enable_muffle with an unknown muffle_bus warns")
	d.free()

func test_no_muffle_warning_when_disabled() -> void:
	var d = DuckerScript.new()
	d.bus = &"ambient"
	d.enable_muffle = false
	d.muffle_bus = &"no_such_bus"  # bogus, but muffle is off so it shouldn't matter
	assert_false(_has_warning(d._get_configuration_warnings(), "muffle"), "no muffle warning when enable_muffle is off")
	d.free()

# --- muffle (the low-pass sweep) ------------------------------------------------------------------------------

func test_resolve_lowpass_finds_the_ambient_bed_filter() -> void:
	# The ambient_bed bus in default_bus_layout.tres carries the muffle low-pass; the resolver must find it.
	var d = DuckerScript.new()
	var fx = d._resolve_lowpass()
	assert_not_null(fx, "the ambient_bed bus has a low-pass the ducker can sweep")
	assert_true(fx is AudioEffectLowPassFilter, "and it resolves to an AudioEffectLowPassFilter")
	d.free()

func test_muffle_snaps_cutoff_indoors_then_reopens() -> void:
	# Drives _apply_muffle directly (off-tree) so no roof/rays are needed. Mutates the shared ambient_bed low-pass,
	# so it saves and restores the authored cutoff to avoid leaking into other tests.
	var idx := AudioServer.get_bus_index(&"ambient_bed")
	assert_gte(idx, 0, "ambient_bed bus exists in the project layout")
	var lp := AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter
	var original := lp.cutoff_hz

	var d = DuckerScript.new()
	d.indoor_cutoff_hz = 8000.0
	d.muffle_smoothing = 100000.0  # snap so we can assert exact values
	d._covered = true
	d._apply_muffle(0.1)           # first call primes -> snaps to the indoor cutoff
	assert_almost_eq(lp.cutoff_hz, 8000.0, 1.0, "under a roof the cutoff drops to indoor_cutoff_hz (muffled)")

	d._covered = false
	d._apply_muffle(0.1)           # eases back toward transparent; huge smoothing => snaps
	assert_almost_eq(lp.cutoff_hz, d.outdoor_cutoff_hz, 1.0, "back outdoors the cutoff reopens to transparent")

	lp.cutoff_hz = original        # restore the authored value for other tests
	d.free()

# --- wiring ---------------------------------------------------------------------------------------------------

func test_host_autowires_to_parent() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var d = DuckerScript.new()
	parent.add_child(d)  # add to the tree -> _ready auto-wires host = parent (freed with the autofree parent)
	assert_eq(d.host, parent, "host left unset auto-wires to the parent")

# --- in-tree roof detection (the crux — proves the up-ray fan) ------------------------------------------------

func test_roof_above_marks_indoors_and_ducks() -> void:
	var roof := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 0.5, 10.0)
	cs.shape = box
	roof.add_child(cs)
	roof.position = Vector3(0.0, 3.0, 0.0)  # a ceiling ~3 m above the host, inside ceiling_scan_height
	add_child_autofree(roof)

	var host := _make_host()  # Node3D with an `is_indoors` property, at the origin
	add_child_autofree(host)
	var amb := AudioStreamPlayer3D.new()
	add_child_autofree(amb)

	var d = DuckerScript.new()
	d.host = host
	d.target = amb.get_path()
	d.sample_interval = 0.0     # scan every frame
	d.fade_speed = 100000.0     # snap so we can assert the level after a couple frames
	d.outdoor_db = 0.0
	d.indoor_db = -20.0
	d.enable_muffle = false     # this test covers the volume duck only — don't touch the global ambient_bed bus
	add_child_autofree(d)

	# let the StaticBody register in the physics space, then process a couple of ticks
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_true(d.is_roof_overhead(), "a roof box overhead is detected by the up-ray fan")
	assert_true(host.is_indoors, "the roof state is written to host.is_indoors")
	assert_almost_eq(amb.volume_db, -20.0, 0.5, "the ambient bed ducks to indoor_db under the roof")

func test_open_sky_stays_outdoors() -> void:
	var host := _make_host()
	add_child_autofree(host)
	var amb := AudioStreamPlayer3D.new()
	add_child_autofree(amb)

	var d = DuckerScript.new()
	d.host = host
	d.target = amb.get_path()
	d.sample_interval = 0.0
	d.fade_speed = 100000.0
	d.outdoor_db = 0.0
	d.indoor_db = -20.0
	d.enable_muffle = false     # volume-duck test only — leave the shared ambient_bed low-pass alone
	add_child_autofree(d)

	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_false(d.is_roof_overhead(), "no geometry overhead => not indoors")
	assert_false(host.is_indoors, "host.is_indoors stays false under open sky")
	assert_almost_eq(amb.volume_db, 0.0, 0.5, "the bed rests at outdoor_db with no roof")

# --- helpers --------------------------------------------------------------------------------------------------

func _has_warning(w: PackedStringArray, needle: String) -> bool:
	for s in w:
		if needle in s:
			return true
	return false

## A minimal Node3D that HAS an `is_indoors` property, so the ducker's host.set(&"is_indoors", ...) write is
## observable (a bare Node3D would silently drop it — Object.set ignores unknown properties). Mirrors the real
## Player seam without pulling in player.gd's heavy _ready.
func _make_host() -> Node3D:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar is_indoors: bool = false\n"
	s.reload()
	return s.new()
