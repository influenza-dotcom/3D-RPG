## @system NPC AI
## @seam AiLod is the ONE cadence gate on npc.gd's decision layer: NPC._physics_process asks think_delta() each
## @seam tick whether to run its brain, and moves (gravity / move_and_slide) regardless of the answer.
## @risk A force_full regression throttles a FIGHTING NPC — the one case that must never degrade.
## @risk Banding off Groups.PLAYER instead of Groups.human_player silently disables LOD near any companion.
## @test res://tests/test_ai_lod.gd
class_name AiLod
extends Node

## Drop-in AI level-of-detail: how often a distant, unaware NPC is allowed to THINK.
##
## WHY THIS EXISTS (measured, 2026-08-13, GTX 1660 / i5-9400F, 40 spawned NPCs):
##   40 NPCs                                       -> 66.7 ms/frame (15 fps)
##   same, npc.gd's own _physics_process disabled  -> 12.5 ms/frame (80 fps)
## So ~81% of a crowd's cost is npc.gd's own tick, NOT its ~91-node component entourage (disabling every
## component child left the frame at 62 ms) and NOT navigation (the NavigationServer measured 0.1-0.4 ms).
## Three plausible culprits were REFUTED by measurement and must not be re-blamed: RVO avoidance
## (`avoidance_enabled = false` changed nothing), the huge `sight_range = 500` (dropping it to 15 changed
## nothing), and pathing (`wanders = false` changed nothing). The cost is the baseline per-tick decision work
## that runs in EVERY state, so the only lever is to run it less often.
##
## WHAT IT DELIBERATELY DOES NOT DO: it never throttles an NPC that is aware, investigating, being talked to,
## or following you (see NPC._ai_force_full_think). A crowd of 40 hostiles all engaging you at once is still
## 40 full-rate brains — LOD cannot help there by construction, and pretending otherwise would be worse than
## the cliff. What it fixes is the realistic shape: a populated map whose cast is mostly idle and far.
##
## AUTHORING: every NPC auto-builds one from the species-wide defaults on `GameSettings.npc_ai`. Drop a
## configured `AiLod` under a specific NPC to override it there (the NpcHomeReturn idiom) — e.g. a
## story-critical NPC you want thinking at full rate no matter how far away it is (`enabled = false`).

## Master switch. OFF = this NPC always thinks every physics tick (the pre-LOD behaviour, exactly).
@export var enabled: bool = true
## Within this many metres of the player the NPC ALWAYS thinks every tick — no throttling at all. Covers the
## "you can see its face" range where a stutter in reaction time would read as the NPC being broken.
@export var near_distance: float = 20.0
## Beyond `near_distance` and within this, the NPC thinks every `mid_interval` seconds. Beyond it, `far_interval`.
@export var far_distance: float = 45.0
## Seconds between thinks in the middle band. 0.1 = 10 Hz, still far quicker than human reaction time.
@export var mid_interval: float = 0.1
## Seconds between thinks in the far band. These NPCs are ambient set-dressing; 4 Hz is plenty to wander.
@export var far_interval: float = 0.25

## Real time banked since the last think. Handed BACK to the brain as its delta so every timer it owns
## (_fire_timer, _retarget_timer, perception, GOAP) advances by true elapsed seconds — a throttled NPC reacts
## less OFTEN, never in slow motion. This is always honest elapsed time; the stagger lives in `_threshold`.
var _accum: float = 0.0
## Seconds to bank before the next think, or < 0 when we are running at full rate. The FIRST threshold after
## entering a throttled band is a fraction of the interval (this NPC's stagger slot); every one after is the
## full interval. Keeping the offset here rather than pre-loading `_accum` is what lets `_accum` stay honest.
var _threshold: float = -1.0
## Cached human-player handle — see player_distance() for why this must not be a per-tick group scan.
var _player: Node3D = null


## The delta the NPC should THINK with this tick, or 0.0 to skip thinking. Call exactly once per physics tick.
##
## `distance` is metres to the human player (npc.gd feeds it player_distance()); `force_full` is the caller's
## "this NPC must not be throttled" verdict. Takes distance rather than looking it up so the whole cadence
## contract is exercisable off-tree, which the project's "no NPC _ready in a unit test" rule requires.
func think_delta(delta: float, distance: float, force_full: bool) -> float:
	var interval := cadence_for(distance, force_full, enabled, near_distance, far_distance,
			mid_interval, far_interval)
	if interval <= 0.0:
		# Full rate. Drop the bank AND the threshold: an NPC walking in from the far band must get a normal
		# delta on its first close tick, not one fat catch-up tick (a visible lurch).
		_accum = 0.0
		_threshold = -1.0
		return delta
	if _threshold < 0.0:
		# Entering a throttled band. Wait only OUR slice of the first window, so a cohort that crossed the
		# boundary together fans out instead of marching in lockstep. Re-seeding on every ENTRY (not once at
		# _ready) is what stops a group that walks out of near range together from re-forming a convoy.
		_threshold = interval * (1.0 - phase())
	_accum += delta
	if _accum < _threshold:
		return 0.0
	var spent := _accum
	_accum = 0.0
	_threshold = interval  # staggered first wait done; steady state from here
	return spent


## This NPC's stable slot in [0, 1) within the think window — the stagger.
##
## WHY IT EXISTS: without it every throttled NPC banks the same interval from the same zero and they all think
## on the SAME tick, converting a steady cost into a periodic spike — which reads WORSE than the flat cost it
## replaced (one hitching frame in four beats four uniformly slower ones).
##
## Derived lazily from instance_id rather than randf(), and NOT in _ready(): a run stays reproducible, a bare
## off-tree `.new()` still staggers (so this is testable under the no-_ready-in-tests rule), and a POOLED NPC
## keeps its id and therefore its slot, so a reused wave stays spread instead of inheriting a convoy.
func phase() -> float:
	return stagger_seed(get_instance_id())


## Pure form of `phase()`.
##
## ⭐ MUST BE A HASH, NOT A MODULO. Godot hands out CONSECUTIVE instance ids to NPCs spawned in the same wave —
## exactly the cohort that would otherwise think in lockstep. `id % N / N` maps consecutive ids to consecutive
## slots, so a wave of 40 lands inside a 40/N slice of the window and is still, for practical purposes, a
## convoy: the first cut of this shipped `% 977` and `tests/test_ai_lod.gd` caught 40 NPCs sharing ONE of ten
## phase buckets. Hashing first decorrelates neighbours, which is the whole point of the stagger.
static func stagger_seed(instance_id: int) -> float:
	return float(absi(hash(instance_id)) % 65536) / 65536.0


## Metres from `from_position` to the HUMAN player, or INF when there is none (a soak-harness level, a bare
## fixture). INF means FULL RATE, not the far band — see the is_inf branch in cadence_for for why.
##
## ⭐ Groups.human_player, NOT a raw Groups.PLAYER scan. A recruited companion JOINS &"Player" (npc.gd's
## start_following does add_to_group(Groups.PLAYER)), and groups.gd names human_player() as the ONE home for
## that rule. Banding off the nearest group member would pin every NPC near a wandering companion to full
## rate and silently switch this feature off wherever the player has an ally.
##
## ⭐ The handle is CACHED on purpose. This runs per NPC per physics tick — 4800 calls/second at 40 NPCs and
## 120 Hz — and a group scan ALLOCATES a fresh Array every call. Re-scanning here would pay for the LOD's
## savings with new allocation churn in the very hot path it exists to thin. The cache self-heals: the scan
## only re-runs once the handle goes invalid (player death/respawn frees and rebuilds it).
func player_distance(from_position: Vector3) -> float:
	if not is_instance_valid(_player):
		_player = null
		if is_inside_tree():
			_player = Groups.human_player(get_tree())
	if _player == null:
		return INF
	return from_position.distance_to(_player.global_position)


## Seconds between thinks for a given distance/state, or 0.0 meaning "every tick". PURE + static so the band
## table is unit-testable without building an NPC.
static func cadence_for(distance: float, force_full: bool, is_enabled: bool, near: float, far: float,
		mid_interval_s: float, far_interval_s: float) -> float:
	if not is_enabled or force_full:
		return 0.0
	# ⭐ NO PLAYER (INF) => FULL RATE, not the far band. This is the tests_soak contract, and it is the
	# opposite of the "cheapest when unobserved" intuition. soak_harness.gd boots a level with NO player and
	# spawns wandering NPCs to catch nav stranding, counting each NPC's own _stranded_cycles. Those cycles
	# accrue in the BRAIN, so throttling to 4 Hz would make them accrue ~30x slower and the harness would
	# under-report stranding inside its time budget — a silent loss of QA fidelity, traded for a saving in the
	# one scenario (headless, unrendered) that has no frame-rate problem to solve.
	if is_inf(distance):
		return 0.0
	if distance <= near:
		return 0.0
	if distance <= far:
		return maxf(mid_interval_s, 0.0)
	return maxf(far_interval_s, 0.0)


## Pooling: NPC bodies are reused (see npc_pooling), and a body that comes back from the pool must not inherit
## the previous life's banked time or band state. The instance id — and therefore the stagger slot — is
## deliberately NOT reset: it is the thing that keeps a reused wave spread out.
func reset_for_reuse() -> void:
	_accum = 0.0
	_threshold = -1.0
	_player = null
