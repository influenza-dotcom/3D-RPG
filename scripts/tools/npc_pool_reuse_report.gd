class_name NpcPoolReuseReport
extends RefCounted

## The result of one NpcPoolReuseHarness run — the in-tree gate for NPC node POOLING (NpcPool). It proves the three
## properties that make pooling correct: (1) REUSE — killing then re-spawning hands back the SAME instances, not
## fresh ones; (2) NO GROWTH — the pool owns a constant number of bodies across kill/respawn cycles (no leak, no
## unbounded instancing); (3) CLEAN RESET — a re-acquired body is a pristine post-_ready combatant (alive, full HP,
## no stale target, UNAWARE, processing + visible, backpack re-seeded, first shot re-armed to charge). `nav_ready`
## false = INCONCLUSIVE (the navmesh never synced — a headless reimport in flight or a bad bake), NOT a failure.

var nav_ready: bool = false
var warmed: int = 0                     ## how many bodies the pool was warmed with
var pool_count_start: int = 0           ## pool bodies owned right after warm (should == warmed)
var pool_count_final: int = 0           ## pool bodies owned after all cycles (should still == warmed = no growth)
var cycles: int = 0
var reused_all_same: bool = false       ## every re-acquired body across cycles was one of the ORIGINAL warmed instances
var reset_clean: bool = false           ## a reused body passed every pristine-state check
var reset_notes: Array[String] = []     ## which specific reset checks failed (empty when reset_clean)
var notes: Array[String] = []


## The pool never grew — it owns exactly the bodies it was warmed with, across every kill/respawn cycle.
func pool_stable() -> bool:
	return pool_count_start == warmed and pool_count_final == warmed


## Verdict: reuse works, the pool didn't leak/grow, and reused bodies came back pristine.
func ok() -> bool:
	return nav_ready and warmed > 0 and reused_all_same and pool_stable() and reset_clean


func summary() -> String:
	return "NpcPoolReuse: nav_ready=%s | warmed=%d pool %d->%d stable=%s | cycles=%d reused_same=%s | reset_clean=%s%s\n%s" % [
		nav_ready, warmed, pool_count_start, pool_count_final, pool_stable(), cycles, reused_all_same,
		reset_clean, ("" if reset_notes.is_empty() else " (" + "; ".join(reset_notes) + ")"), "\n".join(notes)]
