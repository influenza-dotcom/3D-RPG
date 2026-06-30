class_name SoakReport
extends RefCounted

## Result of one SoakHarness run (scripts/tools/soak_harness.gd) — a plain data object plus the PURE verdict
## helpers, split out so the pass/fail LOGIC is unit-tested off-tree (tests/test_soak_report.gd) while the heavy
## in-tree soak itself lives in the opt-in tests_soak/ suite. The harness fills the fields; callers read ok() /
## summary(). Reference it via preload, not the global class_name, from the harness/tests so a not-yet-rescanned
## editor cache can't cascade (see [[new-classname-not-registered-cascade]]).

## Mirrors NPC._tick_stranded's threshold: it flags an NPC as STRANDED once it has given up in the SAME spot this
## many times in a row (~10 s wedged). The soak must use the SAME number or it would disagree with the engine's
## own "looks STRANDED" warning. If npc.gd changes its threshold, this const (guarded by a unit test) must follow.
const STRANDED_THRESHOLD := 3

var level_name: String = ""
var npc_count: int = 0

## True once the level's navmesh finished its first sync. A run that never reached this is INCONCLUSIVE (not a
## pass) — usually a missing/edited bake or a headless reimport still in flight.
var nav_ready: bool = false

## NPCs whose own _stranded_cycles crossed STRANDED_THRESHOLD during the wander phase — each is a likely bad-bake
## island (a prop/car roof the bake made walkable). Entries: { name:String, pos:Vector3, cycles:int }.
var stranded: Array = []
var peak_stranded_cycles: int = 0

## Leak phase: live OBJECT_NODE_COUNT sampled AFTER each spawn/free wave's cleanup settled. A clean run is flat;
## an upward trend across waves = nodes that spawning leaked (failed .free(), a dangling signal keeping a ref).
var node_baseline: int = 0
var leak_post_wave_nodes: PackedInt32Array = PackedInt32Array()
var leak_slack: int = 12
var orphan_baseline: int = 0
var orphan_final: int = 0

var notes: Array = []


## A monotonic upward trend across the post-wave node counts (beyond `slack`) means spawning leaked nodes. Compares
## the LAST settled wave to the FIRST: any constant headless overhead (dummy renderer / audio) is present in both
## and cancels, so only genuine growth shows. < 2 samples = not enough to judge a trend (never a false positive).
static func leak_detected(post_wave: PackedInt32Array, slack: int) -> bool:
	if post_wave.size() < 2:
		return false
	return (post_wave[post_wave.size() - 1] - post_wave[0]) > slack


func has_stranded() -> bool:
	return not stranded.is_empty()


func is_leaking() -> bool:
	return leak_detected(leak_post_wave_nodes, leak_slack)


## A run is OK only if it actually exercised the navmesh (nav_ready), no NPC stranded, and spawning didn't leak.
## nav_ready=false is deliberately NOT ok() — an inconclusive run must not read as green.
func ok() -> bool:
	return nav_ready and not has_stranded() and not is_leaking()


## Human-readable one-screen verdict — printed by the test and any editor/CLI caller so a failure points straight
## at the offending NPC + spot (so a designer can carve that prop or re-bake).
func summary() -> String:
	var lines := PackedStringArray()
	lines.append("SOAK [%s]  npcs=%d  nav_ready=%s  ok=%s" % [level_name, npc_count, str(nav_ready), str(ok())])
	if has_stranded():
		for s in stranded:
			var p: Vector3 = s.get("pos", Vector3.ZERO)
			lines.append("  STRANDED  %s  @ (%.1f, %.1f, %.1f)  cycles=%d  (likely a bad-bake navmesh island)"
				% [str(s.get("name", "?")), p.x, p.y, p.z, int(s.get("cycles", 0))])
	else:
		lines.append("  stranded: none  (peak cycles=%d / threshold %d)" % [peak_stranded_cycles, STRANDED_THRESHOLD])
	lines.append("  leak: baseline_nodes=%d  post_wave=%s  slack=%d  orphans %d->%d  -> %s"
		% [node_baseline, str(leak_post_wave_nodes), leak_slack, orphan_baseline, orphan_final, str(is_leaking())])
	for n in notes:
		lines.append("  note: " + str(n))
	return "\n".join(lines)
