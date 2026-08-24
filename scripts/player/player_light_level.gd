class_name PlayerLightLevel
extends Node3D

## Drop-in on the player: estimates how LIT the host is (0 = pitch dark, 1 = fully lit) by summing nearby
## lights' contribution at the host's position each tick (throttled), and writes it to host.light_exposure for
## enemy Perception to read (dark -> slower detection, via Perception.light_falloff).
##
## LIGHT DISCOVERY (auto_collect, ON by default): finds EVERY Light3D in the running scene on a slow refresh, so a
## designer NEVER hand-tags lights — drop this under the player and any lamp you place (or spawn at runtime) counts
## automatically. Turn auto_collect OFF to read only the &"lights" group instead (an explicit, cheapest lookup for
## a huge scene where you want to curate which lights feed stealth, or to exclude decorative lamps). Either way,
## lights in the &"pickup_beacon" or &"stealth_light_exempt" groups never count (item glows / decorative lamps a
## designer opts out). The player's OWN body light (PlayerEmittingLight) deliberately DOES count -- standing, it
## lights you up; crouching fades its energy out (CrouchLightDouse), which is how darkness stealth turns on. An
## OmniLight3D
## / SpotLight3D adds energy * linear range-falloff; a DirectionalLight3D (sun/moon) adds its energy GLOBALLY — but
## only while directional_contributes is on. Turn it OFF for a SUN-LIT level: a bright sun would otherwise pin the
## meter to fully-lit everywhere and darkness could never help (live-sampling suits night / interiors; for a day
## level mark dark nooks with a hand-painted ShadowVolume instead).
##
## SECOND OUTPUT — `host.carried_light` (0..1): how strongly the host is carrying their OWN lamp, sampled from the
## &"carried_light" group (the flashlight joins it). It is a SEPARATE field because the exposure meter above
## SATURATES at 1.0 — standing in a lit room already reads 1.0, so exposure alone can never say "and I am the
## brightest thing in a dark street". Perception applies it as a straight PENALTY (wider sight range + faster
## detection fill, tuned on GameSettings.light_stealth), which is what makes the torch cost something. 0 = nothing
## lit on you = detection exactly as before.
##
## ABSENT (or nothing to sample) -> the host stays fully lit (1.0), so this is purely additive — stealth-light is
## opt-in (it also needs an enemy Perception.light_falloff curve to actually matter). The sampling is a rough
## linear approximation (not a physical light probe); tune ambient / sample_interval / require_los + playtest.

@export var host: Node3D                  ## the player — gets `light_exposure` (0..1) written each sample
@export_range(0.0, 1.0) var ambient: float = 0.2   ## base light everywhere before any lamp adds (a moonlit floor)
@export var sample_interval: float = 0.1  ## seconds between samples (lights move slowly; throttle the scan + rays)
@export var require_los: bool = true      ## a lamp blocked by geometry between it and the host doesn't count
## Auto-discover every Light3D in the scene each refresh — no &"lights" group tagging. Off -> read ONLY the group.
@export var auto_collect: bool = true
## Seconds between rescans of the scene for lights (auto_collect only). Lights rarely change, so keep this slow.
@export var recollect_interval: float = 2.0
## Whether a DirectionalLight3D (sun/moon) lights the host globally. Turn OFF for a sun-lit level so dark can matter.
@export var directional_contributes: bool = true

@export_group("Carried light (the flashlight penalty)")
## Radius (m) from the host inside which a &"carried_light" lamp counts as ON YOUR PERSON. Beyond it the lamp is
## just scenery and only feeds the exposure meter above. Sized for a first-person torch riding at camera height —
## standing OR crouched that stays well under 3 m from the player origin — so you can drop a lit lantern, walk off,
## and stop being a beacon. 0 disables the whole carried-light penalty.
@export var carried_light_radius: float = 3.0
## The light_energy at which a carried lamp reveals you at FULL strength (1.0). A dimmer lamp scales down linearly,
## so a candle is a smaller liability than a torch — and a lamp faded toward 0 (CrouchLightDouse) stops revealing
## you at all, exactly as it stops feeding the meter above.
@export var carried_light_full_energy: float = 1.0

var _t: float = 0.0
var _recollect_t: float = 0.0
var _lights: Array[Node] = []   ## cached Light3D list (auto_collect); refreshed every recollect_interval

## Zero-config drop-in: dropped as a CHILD of the player with no `host` set, it auto-wires host = parent — so the
## live-sampling writer needs no Player.tscn edit / inspector step (use it OR a painted ShadowVolume, not both).
func _ready() -> void:
	if host == null:
		host = get_parent() as Node3D

func _physics_process(delta: float) -> void:
	if host == null:
		return
	# Refresh the auto-collected light list on a slow cadence (and on the first tick, when the cache is empty) so
	# newly placed / spawned lights are picked up without any group tagging. Decoupled from sample_interval so the
	# rescan stays slow even if you sample fast.
	if auto_collect:
		_recollect_t -= delta
		if _recollect_t <= 0.0 or _lights.is_empty():
			_recollect_t = recollect_interval
			_lights = _collect_lights()
	_t -= delta
	if _t > 0.0:
		return
	_t = sample_interval
	host.set(&"light_exposure", _sample())
	host.set(&"carried_light", _sample_carried())

## Every Light3D in the running scene (auto_collect). Walks the CURRENT SCENE (so autoloads / UI overlays aren't
## scanned), falling back to the whole tree when there's no current scene or this component is outside current_scene
## (e.g. a unit test). owned=false so instanced-level lights whose owner is the level root are still included.
func _collect_lights() -> Array[Node]:
	var tree := get_tree()
	if tree == null:
		return []
	var root: Node = tree.current_scene
	if root == null or (is_inside_tree() and root != self and not root.is_ancestor_of(self)):
		root = tree.root
	if root == null:
		return []
	return root.find_children("*", "Light3D", true, false)

## Sum ambient + every light's contribution at the host, clamped to 0..1. Sources are the auto-collected list, or
## the &"lights" group when auto_collect is off.
func _sample() -> float:
	var at := host.global_position
	var lit := ambient
	var sources: Array = _lights if auto_collect else get_tree().get_nodes_in_group(Groups.LIGHTS)
	for n in sources:
		lit += _light_contribution_for(n, at)
		# Per-sample work cap: once fully lit the result clamps to 1.0 anyway, so stop summing (and skip the
		# remaining per-light range/LOS rays) — a big lit scene doesn't pay for lights past saturation.
		if lit >= 1.0:
			break
	return clampf(lit, 0.0, 1.0)

## How strongly the host is CARRYING their own light (0..1) — written to host.carried_light for enemy Perception.
## Scans the &"carried_light" group DIRECTLY rather than the auto-collected list: a carried lamp is one or two
## nodes, it needs no LOS ray (it is ON you), and it must be found even with auto_collect off. Takes the MAX, not a
## sum — two torches don't make you twice as findable; the brightest one is what gives you away. An INVISIBLE lamp
## contributes nothing, which is exactly how the flashlight's off switch (and a dead player's dark beam) turns the
## penalty off with no extra bookkeeping. Deliberately independent of the exposure sum above: a torch lit inside a
## painted ShadowVolume still gives you away, because the shadow is not what you are holding.
func _sample_carried() -> float:
	var tree := get_tree()
	if tree == null or carried_light_radius <= 0.0:
		return 0.0
	var at := host.global_position
	var strongest := 0.0
	for n in tree.get_nodes_in_group(Groups.CARRIED_LIGHT):
		# is_instance_valid() FIRST, for the same reason as _light_contribution_for below: `freed is Light3D` is a
		# hard error in Godot 4, and a carried lamp can be freed between scans (a dropped prop despawning).
		if not is_instance_valid(n) or not (n is Light3D) or not (n as Node3D).visible:
			continue
		strongest = maxf(strongest, carried_reveal((n as Light3D).light_energy,
				(n as Node3D).global_position.distance_to(at), carried_light_radius, carried_light_full_energy))
		if strongest >= 1.0:
			break  # already maximally revealing — the remaining lamps cannot make it worse
	return strongest

## One light's contribution at `at`: a DirectionalLight3D adds its flat energy (when directional_contributes is on);
## an OmniLight3D / SpotLight3D adds energy * linear range-falloff (optionally LOS-gated). Anything else / a freed
## or invisible node -> 0.
func _light_contribution_for(light, at: Vector3) -> float:
	# is_instance_valid() MUST come first: a cached light can be freed mid-window (the list refreshes only every
	# recollect_interval), and `freed is Light3D` is a HARD error in Godot 4 ("Left operand of 'is' is a previously
	# freed instance"), not a quiet false. Short-circuit the dangling ref before any `is`/cast touches it.
	if not is_instance_valid(light) or not (light is Light3D) or not (light as Node3D).visible:
		return 0.0
	# Pickup item lights are cosmetic (PickupBeacon) -- they must NEVER make the player easier to detect, so a light
	# tagged into the pickup-beacon group contributes nothing to the stealth light meter.
	if (light as Node).is_in_group(Groups.PICKUP_BEACON):
		return 0.0
	# Same rule for any light a designer tags &"stealth_light_exempt" (Node dock -> Groups): a decorative glow that
	# must never feed detection. NOTE the player's own PlayerEmittingLight is deliberately NOT in this group -- the
	# lit body lamp at distance 0 saturates the sum while STANDING (a stealth liability by design), and crouching
	# fades its energy toward 0 (CrouchLightDouse), which zeroes its term here naturally because the sum below
	# weights each lamp by its live energy. Douse the player's light; exempt only true decoration.
	if (light as Node).is_in_group(Groups.STEALTH_LIGHT_EXEMPT):
		return 0.0
	var energy: float = (light as Light3D).light_energy
	if light is DirectionalLight3D:
		return maxf(energy, 0.0) if directional_contributes else 0.0  # a global sun/moon; gated by the toggle
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

## Pure reveal strength (0..1) of ONE carried lamp: full at/above `full_energy`, scaled down linearly for a dimmer
## one, and 0 once it sits further than `radius` from the host — at which point it is no longer being carried.
## Deliberately NOT distance-faded INSIDE the radius: a torch clipped to your belt gives you away exactly as much
## as one held at arm's length, and a soft edge there would only make the penalty hard to read. Unit-tested.
static func carried_reveal(energy: float, dist: float, radius: float, full_energy: float) -> float:
	if radius <= 0.0 or dist > radius or full_energy <= 0.0:
		return 0.0
	return clampf(energy / full_energy, 0.0, 1.0)

## True when geometry sits between the lamp and the host (the lamp can't light it). World-guarded for tests.
func _occluded(from: Vector3, to: Vector3) -> bool:
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to)
	if host is CollisionObject3D:
		q.exclude = [(host as CollisionObject3D).get_rid()]
	# A prop the player carries in front of their face must not cast a self-shadow that darkens them to enemies
	# (light_exposure feeds stealth detection). Mask out the held-prop layer so a carried box can't hide the player.
	q.collision_mask = 0xFFFFFFFF & ~TalkHelpers.held_prop_collision_layer()
	return not world.direct_space_state.intersect_ray(q).is_empty()
