class_name CrouchLightDouse
extends Node

## Drop-in on the player: fades the host's own emitting light out while CROUCHED (a Thief-style lantern douse) and
## back in on stand. The player's body light (Player.tscn's PlayerEmittingLight, the HP glow) is a real Light3D at
## the player's origin, so while STANDING it feeds PlayerLightLevel's meter at full strength -- walking around with
## your lamp lit is a deliberate stealth liability. Crouching drives the light's energy toward crouched_energy
## (default 0); PlayerLightLevel weights every lamp by its LIVE energy, so a doused light contributes ~nothing and
## light_exposure finally drops to whatever the ENVIRONMENT casts -- darkness stealth turns on exactly while
## sneaking. Crouched beside a street lamp you are still lit; the douse hides only your own glow.
##
## Crouch depth is read duck-typed from host.crouch.crouch_t (the same seam enemy Perception reads for
## crouch_sight_mult), so the fade tracks the crouch animation continuously with no signal wiring; a host without a
## crouch component reads as standing (full energy), so the drop-in is inert on anything but the player. Only
## light_energy is touched -- the HP colour blend player.gd runs on the same node (light_color) is untouched.

@export var host: Node3D   ## the player; unset -> auto-wires to the parent (the zero-config drop-in idiom)
@export var light: Light3D ## the body light to douse (Player.tscn wires PlayerEmittingLight); null -> inert
## Energy while fully crouched. 0 = fully doused (the glow vanishes and stops feeding the stealth meter); a small
## value keeps a dim visual tell that still leaks a little exposure.
@export_range(0.0, 16.0) var crouched_energy: float = 0.0
## Seconds for a full douse/relight fade between the authored standing energy and crouched_energy. 0 = snap.
## The target also tracks crouch DEPTH, so a slow crouch animation can stretch the fade beyond this.
@export var fade_time: float = 0.35

## The scene-authored standing energy, captured lazily on the first tick before any fade touches it (-1 = unset) --
## so the douse restores exactly the brightness a designer authored on the light node, whatever it is.
var _full_energy: float = -1.0

func _ready() -> void:
	if host == null:
		host = get_parent() as Node3D

func _physics_process(delta: float) -> void:
	if light == null or not is_instance_valid(light):
		return
	if _full_energy < 0.0:
		_full_energy = light.light_energy
	var target := doused_target(_full_energy, crouched_energy, _crouch_depth())
	light.light_energy = stepped_energy(light.light_energy, target, _full_energy, crouched_energy, fade_time, delta)

## Crouch depth 0..1, duck-typed off host.crouch.crouch_t -- perception.gd's exact idiom (absence = standing, the
## neutral fallback, so a bare host or a crouch node without the field leaves the light at full energy).
func _crouch_depth() -> float:
	if host == null:
		return 0.0
	var crouch: Variant = host.get(&"crouch")
	if not is_instance_valid(crouch) or not (crouch is Object):  # validity FIRST — `is` on a freed instance crashes
		return 0.0
	var raw: Variant = (crouch as Object).get(&"crouch_t")
	if not (raw is float or raw is int):
		return 0.0
	return clampf(float(raw), 0.0, 1.0)

## Pure target energy: the authored standing energy at crouch depth 0 lerped to the doused energy at full crouch,
## depth clamped. Unit-tested.
static func doused_target(full: float, doused: float, crouch_t: float) -> float:
	return lerpf(full, doused, clampf(crouch_t, 0.0, 1.0))

## Pure per-tick step toward `target` at the constant rate that crosses the whole standing<->crouched span in
## `seconds` (so douse and relight take the same designer-authored time). seconds <= 0 or a zero span snaps.
## move_toward never overshoots. Unit-tested.
static func stepped_energy(current: float, target: float, full: float, doused: float, seconds: float, delta: float) -> float:
	if seconds <= 0.0:
		return target
	var span := absf(full - doused)
	if span <= 0.0:
		return target
	return move_toward(current, target, span / seconds * delta)
