class_name CombatSmokeReport
extends RefCounted

## The result of one CombatSmokeHarness run (Wave 4 / T1 — the in-tree combat smoke gate). A SMOKE check: did the
## whole armed-NPC chain — perceive -> acquire -> plan -> aim -> FIRE -> hit -> take_damage — actually deal damage to
## an opposed dummy, and did the combatants close to engage, without leaking nodes? `nav_ready` false =
## INCONCLUSIVE (the navmesh never synced — a headless reimport in flight or a bad bake), NOT a failure.

var nav_ready: bool = false
var initial_distance: float = 0.0
var min_distance: float = INF          ## closest the two combatants got — < initial means they closed to engage
var dummy_start_hp: float = 0.0
var min_dummy_hp: float = INF          ## lowest dummy hp seen — < start means the shooter landed damage
var dummy_died: bool = false           ## dummy killed inside the window = maximal damage landed
var shooter_alive: bool = false
var orphan_baseline: int = 0
var orphan_final: int = 0
var orphan_slack: int = 8              ## tolerated orphan drift (constant headless overhead), like SoakReport's leak_slack
var notes: Array[String] = []
## SHOT TIMELINE (only filled when the harness runs with sample_shots on): the physics-frame index of every round
## that left the shooter's muzzle, in order — sampled as a magazine DECREMENT, so it counts real rounds rather than
## trigger pulls. Empty on an ordinary smoke run. Exists for the BURST gate (WeaponData.npc_burst_count): a burst is
## the one NPC-firing behaviour whose whole shape is a timing pattern, so the only honest check is a live timeline.
var shot_frames: Array[int] = []


## The shot timeline grouped into BURSTS: consecutive rounds no more than `gap_frames` apart become one run, and the
## returned array is each run's LENGTH (round count). An SMG raider should read [3, 3, 3, ...]; a pistol raider
## [1, 1, 1, ...]. `gap_frames` is the split threshold — comfortably above the intra-burst spacing and far below the
## between-bursts cadence (min_shot_interval), the wide valley the two live either side of.
func burst_lengths(gap_frames: int) -> Array[int]:
	var out: Array[int] = []
	for i in shot_frames.size():
		if i > 0 and shot_frames[i] - shot_frames[i - 1] <= gap_frames:
			out[out.size() - 1] += 1
		else:
			out.append(1)
	return out


## The combatants closed the gap (either approached the other) — a smoke proxy for "they engaged", robust to which
## one moved (the unarmed dummy is also hostile, so it closes to melee).
func converged() -> bool:
	return min_distance < initial_distance - 0.5


## The shooter's combat chain dealt damage to the dummy: its hp dropped, or it was killed outright.
func damage_landed() -> bool:
	return dummy_died or min_dummy_hp < dummy_start_hp


func orphan_delta() -> int:
	return orphan_final - orphan_baseline


func leaking() -> bool:
	return orphan_delta() > orphan_slack


func summary() -> String:
	var shots := "" if shot_frames.is_empty() else " | shots=%d frames=%s" % [shot_frames.size(), str(shot_frames)]
	return "CombatSmoke: nav_ready=%s | dist %.1f->%.1f converged=%s | dummy_hp %.0f->%.0f died=%s damage=%s | shooter_alive=%s | orphan_delta=%d%s\n%s" % [
		nav_ready, initial_distance, min_distance, converged(), dummy_start_hp, min_dummy_hp, dummy_died, damage_landed(), shooter_alive, orphan_delta(), shots, "\n".join(notes)]
