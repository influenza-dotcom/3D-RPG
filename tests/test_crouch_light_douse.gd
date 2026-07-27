extends GutTest

## CrouchLightDouse: the pure douse math (doused_target + stepped_energy), the duck-typed crouch-depth read's
## standing fallback, the parent auto-wire, and the export defaults (the designer knobs). The in-tree per-tick
## fade (physics_process writing light_energy each frame) stays manual-playtest; the harness covers the rest.
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


## Export defaults pinned (the test_component_tuning_exports idiom): these are the values every freshly
## drag-dropped instance gets, and the guide documents them — a silent drift desyncs docs and feel.
func test_export_defaults() -> void:
	var douse = load(DOUSE_PATH).new()
	assert_eq(douse.crouched_energy, 0.0,
			"crouched_energy must default to 0 — a full douse, so crouching in darkness reads as truly unlit")
	assert_eq(douse.fade_time, 0.35,
			"fade_time must default to 0.35 s — quick enough to feel responsive, slow enough to read as a fade")
	douse.free()
