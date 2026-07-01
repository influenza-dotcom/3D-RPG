class_name GoapActionSearch
extends GoapAction

## INVESTIGATING-state action: go CHECK the last-known spot, then SWEEP the view hunting the target. The action
## NAME stays &"Investigate" because the planner contract is the behavior's public identity. The write-order
## matters: while traveling, hold the give-up clock OFF (refresh_investigation) so forget_time measures time
## actually SEARCHING there, not the walk; on arrival, slow-sweep via _search_sweep_t. No laser (investigating
## a noise, not aiming). Always RUNNING. is_runtime_valid
## re-checks the live Perception.State.INVESTIGATING so a state flip replans to the matching arm the same tick.
##
## When the search feature is dialed on (SearchSettings.max_search_radius > 0 & sample_points > 1) the action walks
## a WIDENING breadcrumb ring (Perception.searching_area / _search); at the inert defaults it stays the simple
## single-point walk + in-place sweep.

func _init() -> void:
	super(&"Investigate", 0.2, {&"state_investigating": true}, {&"spot_searched": true})

func act(host, delta: float) -> int:
	var p = host._perception
	if p.searching_area():
		_walk_search(host, p, delta)
	else:
		_walk_point(host, delta)
	host._hide_laser()
	return Status.RUNNING

## Single-point investigation (the inert / radius-0 path): walk to the last-known spot, holding the give-up
## clock while traveling (refresh_investigation), then sweep the view IN PLACE on arrival.
func _walk_point(host, delta: float) -> void:
	if host._move_toward(host._perception.last_known_position, host.is_hostile()):  # a HOSTILE hunter hops up to where you were last seen; a neutral corpse-inspector just walks
		host._face_travel(delta)
		host._perception.refresh_investigation()
	else:
		host._search_sweep_t += delta
		var sweep: Vector3 = Vector3(sin(host._search_sweep_t * host.search_sweep_rate), 0.0, cos(host._search_sweep_t * host.search_sweep_rate))
		host._face_point(host.global_position + sweep * 4.0, delta)

## Breadcrumb sweep (the feature dialed on): walk the ordered ring of sample points around the last-known spot,
## widening + thinning each lap (intensity drives crumb density), until the give-up clock expires. While still
## walking OVER to the area (reached_origin false) the give-up clock is held, mirroring _walk_point's travel branch;
## once in the area it ticks, and a crumb unreachable within crumb_timeout is skipped. On ARRIVAL the NPC dwells
## (looks around in place) for an intensity-scaled beat — brief when frantic, lingering as it gives up — then moves
## on. Perception.advance_search / tick_crumb_travel / dwell_elapsed own the trail + timer state.
func _walk_search(host, p, delta: float) -> void:
	if host._move_toward(p._search.current_target(), host.is_hostile()):  # a HOSTILE hunter hops up to a raised breadcrumb; a neutral inspector just walks
		host._face_travel(delta)
		if p._search.reached_origin:
			p.tick_crumb_travel(delta)
		else:
			p.refresh_investigation()
	else:
		p._search.reached_origin = true
		host._search_sweep_t += delta
		var sweep: Vector3 = Vector3(sin(host._search_sweep_t * host.search_sweep_rate), 0.0, cos(host._search_sweep_t * host.search_sweep_rate))
		host._face_point(host.global_position + sweep * 4.0, delta)
		if p.dwell_elapsed(delta):
			p.advance_search()

func is_runtime_valid(host) -> bool:
	return host._perception != null and host._perception.state == Perception.State.INVESTIGATING
