class_name SearchState
extends Resource

## Per-NPC scratch for a SEARCH (the enriched INVESTIGATING behaviour, stealth Slice 8). Lives on Perception next
## to last_known_position / _investigate_t (the seed point + give-up clock it reads). Pure data + pure math: the
## breadcrumb ring takes `origin` as an ARGUMENT and never reads a node transform, so it is unit-testable via .new()
## with no tree (CLAUDE.md off-tree rule + the GUT-9.6 off-tree-transform engine-error trap). The owning action
## (GoapActionSearch) reads this every frame and caches nothing itself — GoapActions are reused across replans.
## Reset by Perception.forget() / clear() so a re-acquired target never inherits a stale widened search ring.

## Centre of the breadcrumb ring — a snapshot of last_known_position when the current search (re)began.
var origin: Vector3
## The uncertainty seed (m) captured at search start (e.g. a heard noise's audible radius); the ring grows from here.
var seed_radius: float = 0.0
## The ordered sweep points the NPC walks. Crumb 0 is always `origin` (re-check the exact last-known spot first).
var breadcrumbs: PackedVector3Array = PackedVector3Array()
## Which breadcrumb the NPC is currently walking to.
var crumb_index: int = 0
## Seconds since the search began at the spot — drives uncertainty growth + intensity falloff.
var elapsed: float = 0.0

## Lay `n` breadcrumbs on a deterministic golden-angle spiral around `p_origin`, out to `radius` metres. Crumb 0 is
## `p_origin` itself; the rest fan outward (r = radius * sqrt(i/n)) so coverage spreads evenly without clustering at
## the centre. `phase_seed` rotates the whole pattern per-NPC so neighbours hearing the same noise don't sweep
## identically. n <= 1 or radius <= 0 => just [p_origin] (the legacy single-point stare). Pure + deterministic given
## the args (no transform reads, no RNG) so a bare .new() test can assert it off-tree.
func regenerate(p_origin: Vector3, radius: float, n: int, phase_seed: float = 0.0) -> void:
	origin = p_origin
	crumb_index = 0
	breadcrumbs = PackedVector3Array()
	breadcrumbs.append(origin)
	if n <= 1 or radius <= 0.0:
		return
	for i in range(1, n):
		var ang: float = float(i) * 2.399963229728653 + phase_seed
		var r: float = radius * sqrt(float(i) / float(n))
		breadcrumbs.append(origin + Vector3(cos(ang), 0.0, sin(ang)) * r)

## The point currently being searched — the active breadcrumb, or `origin` if the trail is empty / index ran off
## the end (the caller regenerates a wider ring on wrap).
func current_target() -> Vector3:
	if crumb_index >= 0 and crumb_index < breadcrumbs.size():
		return breadcrumbs[crumb_index]
	return origin

## True once the NPC has walked past the last breadcrumb (the caller regenerates a wider ring + resets).
func exhausted() -> bool:
	return crumb_index >= breadcrumbs.size()

## Step to the next breadcrumb.
func advance() -> void:
	crumb_index += 1

## Wipe the search so the next investigation starts fresh — called from Perception.forget() / on leaving INVESTIGATING.
func clear() -> void:
	origin = Vector3.ZERO
	seed_radius = 0.0
	breadcrumbs = PackedVector3Array()
	crumb_index = 0
	elapsed = 0.0
