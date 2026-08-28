@tool
class_name IndoorAmbienceDucker
extends Node3D

## Drop-in on the PLAYER: casts a small fan of rays STRAIGHT UP each tick and, when enough of them hit geometry
## (a roof / ceiling / overhang) within `ceiling_scan_height`, applies three "you're indoors" treatments — a
## VOLUME duck and a low-pass MUFFLE on a target ambient bed, plus the ROOM ECHO on the `world` bus — and
## reverses all of them under open sky:
##  - VOLUME: it fades the target player's own `volume_db` from `outdoor_db` to `indoor_db`. It touches the node,
##    NOT the `ambient` bus, so the player's Ambient volume slider still governs the overall level and the two
##    compose in dB — the same "fade a node, leave the bus for the slider" split `AudioZone` uses.
##  - MUFFLE: it sweeps the `cutoff_hz` of a low-pass filter on the `muffle_bus` (the bed's own bus) from
##    `outdoor_cutoff_hz` (transparent) down to `indoor_cutoff_hz`, so the top-end "air" rolls off a touch behind a
##    roof. A low-pass in Godot is a per-BUS effect, so the bed lives on its own `ambient_bed` bus (which sends into
##    `ambient`, keeping the slider) — mirroring how the `radio` bus carries its own low-pass. Disable via
##    `enable_muffle` (then it's a pure volume duck and needs no dedicated bus).
##  - ROOM ECHO: it switches the authored-DISABLED tight-room chain (AudioEffectDelay slap + AudioEffectReverb)
##    on the diegetic `room_bus` (`world`) ON while covered and OFF under sky, so every world sound — footsteps,
##    weapon foley, doors, impacts, gunfire — picks up a close indoor echo behind a roof. Tuning lives in
##    default_bus_layout.tres (Audio panel); this only flips `enabled`. UI cues/stings/jingles play on plain
##    `sfx`, which never passes through `world`, so they stay dry by construction.
## The ray + throttle + LOS-mask idiom is lifted from `PlayerLightLevel`.
##
## SHARED SEAM: it also WRITES `host.is_indoors` (a bool on the player) each sample, so other systems can read one
## authoritative "is there a roof over me" flag instead of each re-casting — a rain/particle cutoff, an interior
## music swap. Live consumer: WeaponAudio.listener_indoors() reads it so gunfire skips its outdoor `gunshots`
## billow bus indoors (the indoor room itself is this component's ROOM ECHO toggle on `world`, above). Default
## (no ducker in the scene) leaves `is_indoors` at its `false` default and the room chain at its authored OFF,
## so this is purely additive: nothing changes until you drop one in (gunfire then always billows, dry rooms).
##
## PLACEMENT: drop it as a CHILD of the Player, next to the `Ambience` AudioStreamPlayer3D. `host` auto-wires to the
## parent; `target` points at the bed to duck (or leave it blank to auto-find the first sibling on `bus`). Zero-config
## when it sits beside a lone ambient-bus player.

## The player — gets `is_indoors` (bool) written each sample. Blank -> auto-wired to the parent in _ready.
@export var host: Node3D
## The AudioStreamPlayer / AudioStreamPlayer3D to duck. Blank -> auto-find the first sibling on `bus`.
@export var target: NodePath
## Bus used only to AUTO-FIND the target (when `target` is blank) and for the config warning. The city bed's bus.
@export var bus: StringName = &"ambient"
## Volume (dB) the bed rests at under open sky (no roof). 0 = the bed's authored level, so outdoors is unchanged.
@export var outdoor_db: float = 0.0
## Volume (dB) the bed ducks to while a roof is overhead. Below `outdoor_db` = quieter indoors (the intent).
@export var indoor_db: float = -12.0
## Cross-fade speed in dB per second between the two levels (so an awning doesn't snap the volume).
@export var fade_speed: float = 12.0
## How far up (m) to look for a roof. A hit within this distance counts; open sky (no hit) does not.
@export var ceiling_scan_height: float = 6.0
## Horizontal spread (m) of the up-ray fan. A fan (not one ray) so a doorway gap / skylight directly overhead
## doesn't flicker you "outdoors" while a ceiling clearly surrounds you.
@export var probe_radius: float = 0.6
## Fraction of the fan's rays that must hit to count as "indoors" (0..1]. 0.5 = at least half of them.
@export_range(0.0, 1.0) var coverage_threshold: float = 0.5
## Seconds between roof scans (you move slowly relative to rooms; throttle the rays like PlayerLightLevel).
@export var sample_interval: float = 0.15
## Ray origin height above the host's origin (m) — cast from ~head height, not the feet.
@export var eye_height: float = 1.6

@export_group("Muffle")
## Roll off the bed's high end with a low-pass while indoors (a subtle "behind a roof" feel on top of the duck).
@export var enable_muffle: bool = true
## The bus whose low-pass filter gets swept. The bed's OWN bus (a low-pass is per-bus, not per-player). It should
## send into `ambient` so the Ambient slider still governs it — see the `ambient_bed` bus in default_bus_layout.tres.
@export var muffle_bus: StringName = &"ambient_bed"
## Low-pass cutoff (Hz) under open sky — at/near 20500 the filter is effectively transparent (no muffle).
@export var outdoor_cutoff_hz: float = 20500.0
## Low-pass cutoff (Hz) while a roof is overhead. ~2500 = a clearly-audible "stepped indoors" muffle (the radio bus
## sits at 5000 for reference); raise toward ~6000 for lighter, drop toward ~1200 for a heavy "sealed room / next
## room" muffle. Much above ~8000 is nearly inaudible on broadband ambience — that's why the first pass "did nothing".
@export var indoor_cutoff_hz: float = 2500.0
## How fast the cutoff eases between the two (per-second exponential rate; higher = snappier). Frame-rate independent.
@export var muffle_smoothing: float = 4.0

@export_group("Room Echo")
## Switch the room-echo chain on `room_bus` with the roof state: ON under cover, OFF under open sky. The chain
## is authored DISABLED in default_bus_layout.tres (the resting state IS outdoors), so a scene with no ducker
## never echoes. Consumed by everything on the `world` bus; see WeaponAudio.fire_bus_for for how gunfire
## additionally swaps off its outdoor billow bus indoors.
@export var enable_room_echo: bool = true
## The bus carrying the disabled-at-rest AudioEffectDelay + AudioEffectReverb to switch — the diegetic `world`
## bus (sends into `sfx`, keeping the Effects slider and the death duck). A bus without those effects, or a
## missing bus, is a silent no-op (the duck + muffle still run).
@export var room_bus: StringName = &"world"

## The up-ray fan, in host-local metres before scaling by `probe_radius`: centre + the four cardinals. Straight up
## is world-up for every one; only the ORIGIN is spread, so a partial ceiling with one gap still reads as covered.
const PROBE_OFFSETS: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(1.0, 0.0, 0.0),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, 0.0, -1.0),
]

var _target_player: Node = null   ## resolved lazily (deferred children / level swap re-parenting the bed)
var _t: float = 0.0               ## countdown to the next roof scan
var _covered: bool = false        ## last sampled roof state; also mirrored to host.is_indoors
var _primed: bool = false         ## false until the first frame snaps the bed to its correct level (no boot fade)
var _lowpass: AudioEffectLowPassFilter = null  ## the muffle filter on muffle_bus, resolved lazily
var _muffle_primed: bool = false  ## false until the first frame snaps the cutoff to its correct value (no boot sweep)

## Zero-config: dropped as a CHILD of the player with no `host` set, it auto-wires host = parent — so no Player.tscn
## inspector step. Runs in-editor too (harmless) so a config warning can read the wiring.
func _ready() -> void:
	if host == null:
		host = get_parent() as Node3D
	if Engine.is_editor_hint():
		return  # @tool: only the configuration warning runs in-editor; the scan + fade are runtime-only

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or host == null:
		return
	# Resolve (or re-resolve) the bed lazily: a level swap can re-parent it, and an auto-found sibling may be added
	# a frame after us. Cheap while valid (a single is_instance_valid check), only re-scans when the ref goes stale.
	if _target_player == null or not is_instance_valid(_target_player):
		_target_player = _resolve_target()
	# Throttle the roof scan (rooms change slowly); the crossfade below still runs EVERY frame so it stays smooth
	# between samples.
	_t -= delta
	if _t <= 0.0:
		_t = sample_interval
		_covered = _sample_covered()
		host.set(&"is_indoors", _covered)  # silent no-op if the host has no such property (matches PlayerLightLevel)
		# UNGATED on enable_room_echo: with the flag off this drives the chain to OFF each sample, so flipping
		# the export at runtime (remote inspector, a debug hook) can never strand the GLOBAL bus state enabled —
		# the off-switch is a state to enforce, not a reason to stop enforcing. Idempotent; also self-heals.
		_apply_room_echo(_covered and enable_room_echo)
	if enable_muffle:
		_apply_muffle(delta)
	if _target_player == null or not is_instance_valid(_target_player):
		return
	var goal := indoor_db if _covered else outdoor_db
	if not _primed:
		# Snap on the first frame we have a bed so booting INDOORS doesn't audibly fade the city in from full then
		# duck — it starts at the right level. After this the move_toward fade owns every transition.
		_primed = true
		_target_player.set(&"volume_db", goal)
		return
	var cur := float(_target_player.get(&"volume_db"))
	if not is_equal_approx(cur, goal):
		_target_player.set(&"volume_db", step_db(cur, goal, fade_speed, delta))

## The bed this ducks: the explicit `target` if it resolves, else the first sibling AudioStreamPlayer(3D) on `bus`
## (so a ducker dropped beside a lone ambient bed needs no NodePath). Null when there's nothing to duck yet.
func _resolve_target() -> Node:
	if not target.is_empty():
		var n := get_node_or_null(target)
		if n != null:
			return n
	var scope := get_parent()
	if scope != null:
		for c in scope.get_children():
			if (c is AudioStreamPlayer or c is AudioStreamPlayer3D) and StringName(c.get(&"bus")) == bus:
				return c
	return null

## Cast the up-ray fan and vote: true when at least `coverage_threshold` of the rays hit geometry within
## `ceiling_scan_height`. Excludes the host's own body and masks OUT the held-prop layer (a box carried overhead
## must not read as a roof), exactly like PlayerLightLevel._occluded. Off-tree / no physics space -> keep the last
## state (a unit-test harness without a world doesn't thrash the flag).
func _sample_covered() -> bool:
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return _covered
	var space := world.direct_space_state
	var base := host.global_position + Vector3.UP * eye_height
	var mask := 0xFFFFFFFF & ~TalkHelpers.held_prop_collision_layer()
	var exclude: Array[RID] = []
	if host is CollisionObject3D:
		exclude = [(host as CollisionObject3D).get_rid()]
	var hits := 0
	for off in PROBE_OFFSETS:
		var from := base + off * probe_radius
		var to := from + Vector3.UP * ceiling_scan_height
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = mask
		q.exclude = exclude
		if not space.intersect_ray(q).is_empty():
			hits += 1
	return is_covered(hits, PROBE_OFFSETS.size(), coverage_threshold)

## True while a roof was detected overhead at the last sample (mirrors what's written to host.is_indoors).
func is_roof_overhead() -> bool:
	return _covered

## Ease the muffle bus's low-pass cutoff toward transparent (outdoors) or `indoor_cutoff_hz` (under a roof). No-op
## until the bus + a low-pass on it resolve, so a scene without the `ambient_bed` bus just skips the muffle (the
## volume duck still runs). Snaps on the first frame so booting indoors doesn't audibly sweep the filter down.
func _apply_muffle(delta: float) -> void:
	if _lowpass == null:
		_lowpass = _resolve_lowpass()
		if _lowpass == null:
			return
	var goal := indoor_cutoff_hz if _covered else outdoor_cutoff_hz
	if not _muffle_primed:
		_muffle_primed = true
		_lowpass.cutoff_hz = goal
		return
	if not is_equal_approx(_lowpass.cutoff_hz, goal):
		_lowpass.cutoff_hz = approach_exp(_lowpass.cutoff_hz, goal, muffle_smoothing, delta)

## Flip every AudioEffectDelay / AudioEffectReverb on `room_bus` to match the roof state. Enabled flips are a
## trivial pair of server calls at sample_interval cadence and are NOT persisted — the .tres reloads its
## authored (disabled) state next run, exactly like the muffle's cutoff.
func _apply_room_echo(on: bool) -> void:
	var idx := AudioServer.get_bus_index(room_bus)
	if idx < 0:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectDelay or fx is AudioEffectReverb:
			AudioServer.set_bus_effect_enabled(idx, i, on)

## Leaving the tree (level swap, host freed) restores the chain's resting state — OFF — so a next scene
## without a ducker doesn't inherit a stranded indoor echo from exiting a level while under a roof.
## Deliberately NOT gated on enable_room_echo: the restore must run even for a ducker whose toggle was
## switched off mid-life, or the disable path itself becomes the one path that can never clean up.
func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_apply_room_echo(false)

## The first AudioEffectLowPassFilter on `muffle_bus`, or null if the bus / effect isn't there. Modulating the
## returned effect resource updates the LIVE filter (it's the same instance the bus processes) — the standard
## Godot dynamic-filter-sweep pattern. Not persisted: the .tres reloads its authored cutoff next run.
func _resolve_lowpass() -> AudioEffectLowPassFilter:
	var idx := AudioServer.get_bus_index(muffle_bus)
	if idx < 0:
		return null
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectLowPassFilter:
			return fx as AudioEffectLowPassFilter
	return null

# --- Pure helpers (unit-tested; no tree / world needed) --------------------------------------------------------

## Fraction of a fan's rays that hit. 0 when the fan is empty (avoids a divide-by-zero).
static func coverage_fraction(hits: int, total: int) -> float:
	return 0.0 if total <= 0 else float(hits) / float(total)

## True when the hit fraction meets `threshold` — the "am I under a roof" vote.
static func is_covered(hits: int, total: int, threshold: float) -> bool:
	return coverage_fraction(hits, total) >= threshold

## One frame of the dB cross-fade: ease `current` toward `goal` at `speed` dB/s, clamping at the goal.
static func step_db(current: float, goal: float, speed: float, delta: float) -> float:
	return move_toward(current, goal, maxf(speed, 0.0) * delta)

## One frame of frame-rate-independent exponential approach: `current` eases toward `goal` with time-constant
## 1/`rate` (seconds). Used for the muffle cutoff sweep (a smooth glide, not a linear dB ramp). rate <= 0 => snap.
static func approach_exp(current: float, goal: float, rate: float, delta: float) -> float:
	if rate <= 0.0:
		return goal
	return goal + (current - goal) * exp(-rate * delta)

func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if AudioServer.get_bus_index(bus) < 0:
		w.append("`bus` '%s' isn't in the project's audio bus layout — auto-find can't match a bed and the ducked player would ignore the volume slider." % str(bus))
	if not target.is_empty() and get_node_or_null(target) == null:
		w.append("`target` NodePath '%s' doesn't resolve to a node — nothing to duck. Point it at the ambient AudioStreamPlayer, or clear it to auto-find a sibling on `bus`." % str(target))
	if indoor_db >= outdoor_db:
		w.append("indoor_db (%s dB) is not below outdoor_db (%s dB), so the bed won't get quieter under a roof — lower indoor_db to actually duck." % [indoor_db, outdoor_db])
	if enable_muffle:
		if AudioServer.get_bus_index(muffle_bus) < 0:
			w.append("enable_muffle is on but muffle_bus '%s' isn't in the audio bus layout — the muffle can't engage. Route the bed to a bus that has a low-pass (e.g. `ambient_bed`), or turn off enable_muffle." % str(muffle_bus))
		elif _resolve_lowpass() == null:
			w.append("muffle_bus '%s' has no AudioEffectLowPassFilter — add one (the effect the muffle sweeps), or turn off enable_muffle." % str(muffle_bus))
	if enable_room_echo:
		var ri := AudioServer.get_bus_index(room_bus)
		if ri < 0:
			w.append("enable_room_echo is on but room_bus '%s' isn't in the audio bus layout — the indoor room echo can't engage." % str(room_bus))
		else:
			var has_chain := false
			for i in AudioServer.get_bus_effect_count(ri):
				var fx := AudioServer.get_bus_effect(ri, i)
				has_chain = has_chain or fx is AudioEffectDelay or fx is AudioEffectReverb
			if not has_chain:
				w.append("room_bus '%s' has no AudioEffectDelay/AudioEffectReverb to switch — author the (disabled) indoor chain on it in the editor's Audio panel, or turn off enable_room_echo." % str(room_bus))
	return w
