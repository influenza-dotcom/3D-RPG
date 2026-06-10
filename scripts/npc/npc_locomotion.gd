class_name NpcLocomotion
extends Node

## NPC NON-COMBAT movement states, split off npc.gd (Wave 3 SRP #6, final piece). Owns WHERE an off-duty NPC
## goes: the idle update (companion-tail delegation -> wander -> return-to-post / hold), the wander roam
## (destination + dwell bookkeeping), and the flee run. Called from npc.gd's _physics_process state machine
## via 1-line facades (_idle / _act_flee), so the call-sites are unchanged.
##
## DELIBERATELY NOT here (the roadmap's "locomotion + anti-stuck" boundary didn't survive contact):
## apply_velocity / _update_stuck / wall_slide_dir are a Character override + test-pinned anti-stuck state,
## and _move_toward / the _face_* helpers / _desired_velocity are SHARED with combat pursuit — all stay on
## npc.gd. _pick_wander_point also stays there: it's pure math pinned by test_ranged_behavior on an off-tree
## NPC (where no component children exist). This component only picks destinations and drives host._move_toward.
##
## `host` is typed Node (not NPC) to break the NpcLocomotion <-> NPC class cycle, so every host.X is a
## dynamic call — vars built from host.* use explicit type annotations (`: Vector3 =`), never `:=`
## (GDScript can't infer a type from a Variant). Built in NPC._build_components like the other children.

var host: Node = null  ## the NPC we move (Node-typed to avoid the class cycle)

## Wander bookkeeping (used only when host.wanders): the current roam destination + a dwell pause.
var _wander_target: Vector3
var _has_wander_target: bool = false
var _wander_dwell: float = 0.0


## Non-combat idle update. A recruited COMPANION tails its leader (overriding wander/hold); otherwise
## wanderers roam near spawn, and a plain NPC either returns to its post (return_to_post, when knocked
## away) or holds still — so a non-following FIGHT combatant is unchanged.
func _idle(delta: float, return_to_post: bool) -> void:
	if host.is_following() and host._follow != null:
		host._follow.act(delta)  # tail the leader (+ the hidden teleport) — the CompanionFollow child owns the drive
		return
	if host.wanders:
		_wander(delta)
		return
	if not return_to_post:
		return
	if host._move_toward(host._spawn_position):
		host._face_travel(delta)
	else:
		host._face_yaw(host._spawn_yaw, delta)


## Roam: walk to a random point within wander_radius of spawn, dwell a beat on arrival, then pick a
## fresh one. Reuses the same navmesh pathing + facing as combat pursuit, so it routes around walls.
func _wander(delta: float) -> void:
	if _wander_dwell > 0.0:
		_wander_dwell -= delta  # lingering at a stop, standing where we arrived
		return
	if not _has_wander_target:
		_wander_target = host._pick_wander_point()
		_has_wander_target = true
	if host._move_toward(_wander_target):
		host._face_travel(delta)
	else:
		# Arrived, or the navmesh wouldn't route there: pause, then choose a new spot next time.
		_has_wander_target = false
		_wander_dwell = randf_range(host.wander_dwell_min, host.wander_dwell_max)


## Flee: each frame, head for a point flee_distance straight away from the threat. Recomputed every
## frame so the destination keeps running ahead of us; we face the way we run and never fire.
func _act_flee(delta: float) -> void:
	var away: Vector3 = host.global_position - host._aim_point()
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(sin(host._spawn_yaw), 0.0, cos(host._spawn_yaw))  # standing on the threat: bolt spawn-ward
	var flee_to: Vector3 = host.global_position + away.normalized() * host.flee_distance
	if host._move_toward(flee_to):
		host._face_travel(delta)
	else:
		host._face_point(flee_to, delta)
