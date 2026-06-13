class_name GoapActionInvestigate
extends GoapAction

## INVESTIGATING-state combat action: go CHECK the last-known spot, then SWEEP the view hunting the target.
## Transcribed VERBATIM from the FSM INVESTIGATING arm (npc.gd:1437-1444) — the write-order matters: while
## traveling, hold the give-up clock OFF (refresh_investigation) so forget_time measures time actually SEARCHING
## there, not the walk; on arrival, slow-sweep via _search_sweep_t. No laser (investigating a noise, not aiming).
## Always RUNNING. Serves the Investigate goal (sentinel spot_searched); is_runtime_valid re-checks the live
## Perception.State.INVESTIGATING so a state flip replans to the matching arm the same tick.

func _init() -> void:
	super(&"Investigate", 0.2, {&"state_investigating": true}, {&"spot_searched": true})

func act(host, delta: float) -> int:
	if host._move_toward(host._perception.last_known_position):
		host._face_travel(delta)
		host._perception.refresh_investigation()
	else:
		host._search_sweep_t += delta
		var sweep: Vector3 = Vector3(sin(host._search_sweep_t * host.search_sweep_rate), 0.0, cos(host._search_sweep_t * host.search_sweep_rate))
		host._face_point(host.global_position + sweep * 4.0, delta)
	host._hide_laser()
	return Status.RUNNING

func is_runtime_valid(host) -> bool:
	return host._perception != null and host._perception.state == Perception.State.INVESTIGATING
