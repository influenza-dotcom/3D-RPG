class_name PlayerLightLevel
extends Node3D

## Drop-in on the player: estimates how LIT the host is (0 = pitch dark, 1 = fully lit) by summing nearby
## lights' contribution at the host's position each tick (throttled), and writes it to host.light_exposure for
## enemy Perception to read (dark -> slower detection, via Perception.light_falloff). "Live" = reads the scene's
## actual Light3D nodes, no hand-painted volumes. Lights must be in the &"lights" group (a cheap lookup); a
## DirectionalLight3D (sun/moon) contributes its energy globally.
##
## ABSENT (or no grouped lights) -> the host stays fully lit (1.0), so this is purely additive — stealth-light
## is opt-in (it also needs an enemy Perception.light_falloff curve to actually matter). The sampling is a rough
## linear approximation (not a physical light probe); tune ambient / sample_interval / require_los + playtest.

@export var host: Node3D                  ## the player — gets `light_exposure` (0..1) written each sample
@export_range(0.0, 1.0) var ambient: float = 0.2   ## base light everywhere before any lamp adds (a moonlit floor)
@export var sample_interval: float = 0.1  ## seconds between samples (lights move slowly; throttle the scan + rays)
@export var require_los: bool = true      ## a lamp blocked by geometry between it and the host doesn't count

var _t: float = 0.0

## Zero-config drop-in: dropped as a CHILD of the player with no `host` set, it auto-wires host = parent — so the
## live-sampling writer needs no Player.tscn edit / inspector step (use it OR a painted ShadowVolume, not both).
func _ready() -> void:
	if host == null:
		host = get_parent() as Node3D

func _physics_process(delta: float) -> void:
	if host == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = sample_interval
	host.set(&"light_exposure", _sample())

## Sum ambient + every grouped light's contribution at the host, clamped to 0..1.
func _sample() -> float:
	var at := host.global_position
	var lit := ambient
	for n in get_tree().get_nodes_in_group(&"lights"):
		lit += _light_contribution_for(n, at)
		if lit >= 1.0:
			break
	return clampf(lit, 0.0, 1.0)

## One light's contribution at `at`: a DirectionalLight3D adds its flat energy; an OmniLight3D / SpotLight3D adds
## energy * linear range-falloff (optionally LOS-gated). Anything else / invisible -> 0.
func _light_contribution_for(light, at: Vector3) -> float:
	if not (light is Light3D) or not (light as Node3D).visible:
		return 0.0
	var energy: float = (light as Light3D).light_energy
	if light is DirectionalLight3D:
		return maxf(energy, 0.0)  # a global sun/moon (its own shadows handle occlusion; not sampled here)
	if not (light is OmniLight3D or light is SpotLight3D):
		return 0.0
	var lpos := (light as Node3D).global_position
	var rng: float
	if light is OmniLight3D:
		rng = (light as OmniLight3D).omni_range
	else:
		rng = (light as SpotLight3D).spot_range
	var dist := lpos.distance_to(at)
	if rng <= 0.0 or dist >= rng:
		return 0.0
	if require_los and _occluded(lpos, at):
		return 0.0
	return light_contribution(energy, rng, dist)

## Pure linear range-falloff contribution: full `energy` at the lamp, 0 at the edge of `light_range`. Unit-tested.
static func light_contribution(energy: float, light_range: float, dist: float) -> float:
	if light_range <= 0.0 or dist >= light_range:
		return 0.0
	return maxf(energy, 0.0) * (1.0 - dist / light_range)

## True when geometry sits between the lamp and the host (the lamp can't light it). World-guarded for tests.
func _occluded(from: Vector3, to: Vector3) -> bool:
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if host is CollisionObject3D:
		q.exclude = [(host as CollisionObject3D).get_rid()]
	return not world.direct_space_state.intersect_ray(q).is_empty()
