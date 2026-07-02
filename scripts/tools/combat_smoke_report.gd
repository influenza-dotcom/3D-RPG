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
	return "CombatSmoke: nav_ready=%s | dist %.1f->%.1f converged=%s | dummy_hp %.0f->%.0f died=%s damage=%s | shooter_alive=%s | orphan_delta=%d\n%s" % [
		nav_ready, initial_distance, min_distance, converged(), dummy_start_hp, min_dummy_hp, dummy_died, damage_landed(), shooter_alive, orphan_delta(), "\n".join(notes)]
