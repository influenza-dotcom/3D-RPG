extends GutTest

## CrouchLightDouse: the pure douse math (doused_target + stepped_energy), the duck-typed crouch-depth read's
## standing fallback, the parent auto-wire, and the per-tick douse itself (_physics_process writing light_energy) driven
## by hand off-tree with the SHIPPED knobs — a fade, not a snap; a full douse; a relight to the authored energy.
## Loaded by path, not class_name, so a stale global class cache can't fail the whole script.

const DOUSE_PATH := "res://scripts/player/crouch_light_douse.gd"


func test_doused_target_tracks_crouch_depth() -> void:
	var douse = load(DOUSE_PATH)
	assert_almost_eq(douse.doused_target(1.0, 0.0, 0.0), 1.0, 0.0001, "standing (depth 0) -> full authored energy")
	assert_almost_eq(douse.doused_target(1.0, 0.0, 1.0), 0.0, 0.0001, "fully crouched -> the doused energy")
	assert_almost_eq(douse.doused_target(1.0, 0.0, 0.5), 0.5, 0.0001, "half crouch -> halfway (fade tracks depth continuously)")
	assert_almost_eq(douse.doused_target(1.0, 0.4, 1.0), 0.4, 0.0001, "a nonzero crouched_energy keeps a dim tell at full crouch")
	assert_almost_eq(douse.doused_target(1.0, 0.0, 2.0), 0.0, 0.0001, "depth clamps above 1")
	assert_almost_eq(douse.doused_target(1.0, 0.0, -1.0), 1.0, 0.0001, "depth clamps below 0")


func test_stepped_energy_crosses_span_in_fade_time() -> void:
	var douse = load(DOUSE_PATH)
	assert_almost_eq(douse.stepped_energy(1.0, 0.0, 1.0, 0.0, 0.5, 0.1), 0.8, 0.0001,
			"span 1 over 0.5 s -> rate 2/s, so a 0.1 s tick drops 0.2 (the douse takes exactly fade_time)")
	assert_almost_eq(douse.stepped_energy(0.0, 1.0, 1.0, 0.0, 0.5, 0.1), 0.2, 0.0001,
			"relight climbs at the same rate (stand fades back in over the same fade_time)")
	assert_almost_eq(douse.stepped_energy(0.95, 0.0, 1.0, 0.0, 0.5, 10.0), 0.0, 0.0001,
			"move_toward never overshoots the target on a huge delta")
	assert_almost_eq(douse.stepped_energy(1.0, 0.0, 1.0, 0.0, 0.0, 0.016), 0.0, 0.0001,
			"fade_time 0 snaps straight to the target")
	assert_almost_eq(douse.stepped_energy(0.7, 1.0, 1.0, 1.0, 0.5, 0.016), 1.0, 0.0001,
			"a zero standing<->crouched span snaps (no divide-by-zero, nothing to fade across)")


## A doused light is invisible to the stealth meter with NO exclusion machinery: PlayerLightLevel weights each lamp
## by its live energy, so energy 0 contributes 0 even at distance 0 — the whole reason the crouch fade (not a hard
## skip) is how the player's own body light stops feeding light_exposure.
func test_doused_energy_contributes_nothing_to_light_meter() -> void:
	assert_almost_eq(PlayerLightLevel.light_contribution(0.0, 2.1, 0.0), 0.0, 0.0001,
			"energy 0 at distance 0 -> zero contribution (a doused body light frees the meter for the environment)")


## Rank 27.3 idiom: dropped under the player with no host set, it auto-wires host = parent (no inspector step).
func test_resolves_host_from_parent_when_unset() -> void:
	var parent := Node3D.new()
	var douse = load(DOUSE_PATH).new()
	parent.add_child(douse)
	add_child_autofree(parent)  # entering the tree fires douse._ready
	assert_eq(douse.host, parent, "host auto-resolves to the parent when unset (drop-in)")


## The duck-typed crouch read (perception.gd's idiom): absence = standing = depth 0, so the component is inert on a
## host with no crouch component; a real Crouch's crouch_t comes through clamped. Off-tree throughout (Crouch's
## captures run in _ready, which never fires without tree entry).
func test_crouch_depth_duck_typed_read() -> void:
	var douse = load(DOUSE_PATH).new()
	assert_almost_eq(douse._crouch_depth(), 0.0, 0.0001, "no host -> standing (neutral fallback)")
	var bare := Node3D.new()
	douse.host = bare
	assert_almost_eq(douse._crouch_depth(), 0.0, 0.0001, "a host without a crouch property -> standing")
	var scripted := GDScript.new()
	scripted.source_code = "extends Node3D\nvar crouch"
	scripted.reload()
	var host: Node3D = scripted.new()
	var crouch: Node3D = load("res://scripts/player/crouch.gd").new()
	crouch.crouch_t = 0.75
	host.crouch = crouch
	douse.host = host
	assert_almost_eq(douse._crouch_depth(), 0.75, 0.0001, "a host with a Crouch reads its live crouch_t")
	crouch.crouch_t = 3.0
	assert_almost_eq(douse._crouch_depth(), 1.0, 0.0001, "crouch_t clamps to 0..1")
	crouch.free()
	host.free()
	bare.free()
	douse.free()


## The whole per-tick douse on a freshly drag-dropped instance (shipped knobs, nothing set but the wiring), ticked by
## hand off-tree. What the design needs from those defaults, rather than their numbers:
##   * crouching FADES the lamp (the first tick is not a snap) and the fade honours fade_time;
##   * the shipped douse is FULL — a ship decision: crouched in darkness your own glow is gone, not dimmed;
##   * standing relights to the energy the designer AUTHORED on the light node, not to 1.0 and not to a mid-fade value.
func test_a_dropped_in_douse_fades_the_lamp_out_and_back_to_its_authored_energy() -> void:
	var dt := 1.0 / 60.0
	var douse = load(DOUSE_PATH).new()
	var light := OmniLight3D.new()
	light.light_energy = 2.5  # a deliberately non-1.0 authored brightness
	var scripted := GDScript.new()
	scripted.source_code = "extends Node3D\nvar crouch"
	scripted.reload()
	var host: Node3D = scripted.new()
	var crouch: Node3D = load("res://scripts/player/crouch.gd").new()
	host.crouch = crouch
	douse.host = host
	douse.light = light
	var fade: float = douse.fade_time
	assert_gt(fade, dt, "the shipped fade_time must span more than one physics frame, or the douse reads as a light switch")
	var frames := int(ceil(fade / dt)) + 1
	crouch.crouch_t = 0.0
	douse._physics_process(dt)
	assert_almost_eq(light.light_energy, 2.5, 0.0001, "standing, the lamp keeps its authored energy")
	crouch.crouch_t = 1.0
	douse._physics_process(dt)
	assert_true(light.light_energy > 0.0 and light.light_energy < 2.5,
			"the first crouched tick must start a FADE (energy %s), not snap the lamp dark" % light.light_energy)
	var ticked := int(floor(fade / dt * 0.8))  # 80% of fade_time, counting the tick above
	for _i in range(ticked - 1):
		douse._physics_process(dt)
	assert_gt(light.light_energy, 0.0, "80%% of the way through fade_time the douse must still be under way (energy %s)" % light.light_energy)
	for _i in range(frames - ticked):  # ...up to one frame past fade_time in total
		douse._physics_process(dt)
	assert_eq(light.light_energy, 0.0,
			"after fade_time the shipped douse must be COMPLETE and FULL (energy exactly 0) — crouching in darkness reads as truly unlit and your glow stops feeding the stealth meter")
	crouch.crouch_t = 0.0
	for _i in range(frames):
		douse._physics_process(dt)
	assert_almost_eq(light.light_energy, 2.5, 0.0001,
			"standing back up must relight to the AUTHORED 2.5 within fade_time — never to 1.0, and never stuck at the doused value")
	crouch.free()
	host.free()
	light.free()
	douse.free()
