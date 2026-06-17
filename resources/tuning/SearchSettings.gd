class_name SearchSettings
extends Resource

## Tuning for the SEARCH feel (stealth Slice 8) — how an NPC hunts around a lost stimulus instead of staring at
## one spot. Read directly via GameSettings.search.* inside Perception / GoapActionSearch (a global *Settings.tres
## group, NOT a per-NPC Perception @export — a bare Perception export is not inspector-reachable without the
## npc.gd mirror chain; see docs/AUTHORING_GUIDE.md). The PARITY DEFAULTS below (max_search_radius = 0,
## sample_points = 1, intensity_curve = null) collapse the search to today's single-point in-place sweep, so the
## feature ships INERT and only activates once a designer dials it up. Pure feel — no logic depends on exact values.

@export_group("Search Area")
## Metres the uncertainty circle expands per second while actively searching (the target could have moved further the
## longer it's been). Higher = the search area widens faster. 0 = the radius never grows (stays at the seed).
@export var uncertainty_grow_rate: float = 0.0
## Cap (m) on the uncertainty circle. THE MASTER INERT SWITCH: 0 forces the search radius to 0 → a single breadcrumb
## at the last-known spot → today's in-place stare. Raise it (e.g. 6) to let the NPC sweep a real area.
@export var max_search_radius: float = 0.0
## Floor (m) on the uncertainty circle so even a tiny/zero seed still yields a small ring once the feature is on. 0 = no floor.
@export var min_search_radius: float = 0.0
## How many breadcrumb sweep points to walk within the radius (point 0 is always the exact last-known spot). 1 = the
## legacy single-point stare; >1 fans the rest outward on a golden-angle spiral. Higher = a more thorough hunt.
@export var sample_points: int = 1
## Max seconds to spend walking toward a single breadcrumb (AFTER reaching the search area) before treating it as
## unreachable (off-mesh / behind geometry) and skipping to the next. Guards against an NPC stuck pushing into a
## wall on a bad sample point. Higher = more patience per point. Only matters once sample_points > 1.
@export var crumb_timeout: float = 3.0

@export_group("Intensity")
## Search ENERGY (0..1) as a function of search PROGRESS (0 = just started, 1 = about to give up). null = flat 1.0
## (parity). Authored falling curve = frantic look first, resigned wander as it gives up. Drives breadcrumb density +
## dwell time below. Read through a null-guard, so leaving it null never crashes.
@export var intensity_curve: Curve = null
## Seconds the NPC pauses to look around AT a breadcrumb at FULL intensity (frantic) — the brief end of the range.
@export var crumb_dwell_min: float = 0.15
## Seconds the NPC pauses AT a breadcrumb at ZERO intensity (resigned) — the lingering end. Dwell lerps from max
## (giving up) to min (frantic) by intensity, so a fading search slows to a wander. Keep >= crumb_dwell_min.
@export var crumb_dwell_max: float = 1.0

@export_group("Seeding")
## Multiplier on a heard noise's audible radius when it seeds the search uncertainty (a loud crash searches a wider
## area than a faint step). Only matters once max_search_radius > 0 and the noise channel passes a seed (Slice 8.5).
@export var noise_radius_scale: float = 1.0
## Fraction of the observer's sight_range used as the uncertainty seed for a discovered body (a corpse carries no
## radius of its own). Only matters once max_search_radius > 0. 0 = a body seeds a point, not an area.
@export var corpse_radius_frac: float = 0.5
## Base uncertainty seed (m) for the combat lost-line-of-sight channel, which has no noise source to size from.
## Only matters once max_search_radius > 0. 0 = the search starts as a point and grows via uncertainty_grow_rate.
@export var seed_radius: float = 0.0
