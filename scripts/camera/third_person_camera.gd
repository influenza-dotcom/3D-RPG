class_name ThirdPersonCamera
extends SpringArm3D

## THE THIRD-PERSON CAMERA — "let me see myself". A drop-in child of the camera rig (camera_rig.tscn's
## `CameraArm`, a sibling of ScreenShake) that pulls the view BACK AND OVER THE SHOULDER without touching a
## single line of the first-person stack. Toggled with the `ToggleView` action (middle mouse / P / BACK) — that
## bind is the ONLY way in: there is no Options row, because a menu toggle for a mode you flip mid-fight, and
## which deliberately never persists, was only a slower second door onto the same key.
##
## ⭐WHY THIS IS AN ARM BESIDE THE CAMERA AND NOT A PARENT OF IT. The obvious build — a SpringArm3D inserted
## between Head and ScreenShake with the camera as its child — would have renamed the rig's one stable path.
## `Head.camera` / `Head.screen_shake` resolve "ScreenShake/Camera3D" and "ScreenShake" BY NAME, and half the
## project reaches the camera through those two getters. So this node hangs off Head as a SIBLING and is used
## purely as a PROBE: the engine still does the shape cast and the wall-avoidance math for us (`get_hit_length`),
## and we write the result onto `ScreenShake.position` ourselves. Nothing is reparented, no path moves, and a
## build with `distance = 0` is bit-identical to the game before this file existed.
##
## ⭐WHY ScreenShake IS THE NODE WE MOVE. It is the only node in the chain whose POSITION nobody owns:
## ScreenShake writes its own `rotation` (and only rotation), and CameraEffects owns the camera's `position`
## (rest + bob + landing dip + stair smoothing) one level below. Writing the pull-back here therefore composes
## with shake and bob for free instead of fighting either. Never move the Camera3D itself — CameraEffects
## reassigns `position` every frame and would erase it.
##
## ⭐THE PLAYER BODY YAWS WITH THE LOOK, so this is a SHOOTER third person (Resident Evil 4 / Gears), not a
## free-orbit adventure camera. That falls out of the existing rig rather than being a decision made here:
## MouseInput yaws the Player BODY and Head owns pitch, so pulling back along Head's +Z automatically orbits
## the character it is already attached to. Aim is unaffected — `Player.get_aim_origin/direction` project the
## ray from the SCREEN CENTRE, and `DamageTrace` excludes the wielder, so shots still go exactly where the
## crosshair points with the camera 2 m behind your head.
##
## Wired by `Head.setup()` (the rig's injection point, like CameraEffects.player and PickupRay.player).
## The matching body you actually see is `ThirdPersonBody` on the Player; it polls `blend` from here.

## Emitted the moment the INTENT flips — not when the blend finishes — so the first-person cosmetics
## (FirstPersonBody's legs/torso/hands, the view model) can get off the screen before the camera has slid far
## enough back to see them. Player relays it to FirstPersonBody / ThirdPersonBody.
signal view_changed(third_person: bool)

@export_group("Third Person")
## How far behind the eye the camera sits at full pull-out (metres, before wall collision), READ LIVE from the
## one source of truth rather than stored here.
##
## ⭐DO NOT TURN THIS BACK INTO AN EXPORT. The player MOVES it — the mouse wheel steps it while the view is
## pulled out (the one way in; the Options slider that used to mirror it is gone) — through
## `Settings.set_third_person_distance`, which writes `GameSettings.camera.third_person_distance` and persists
## it. A cached copy here would be a second writer of the same number, which is precisely the bug
## `CameraEffects.base_fov` documents at length (an initializer nothing re-seeded, fighting the live setting
## every frame). Retune the DEFAULT on `CameraSettings.third_person_distance`; clamp limits are
## `Settings.TP_DISTANCE_MIN/MAX`, the wheel's travel.
var distance: float:
	get:
		return GameSettings.camera.third_person_distance

## How far to the RIGHT of the eye-line the camera sits at full pull-out. This is the knob that keeps the
## character out of the middle of the screen: at zero your own head sits exactly on the crosshair and eats the
## thing you are aiming at. Negative puts the camera over the left shoulder.
@export var shoulder: float = 0.45
## How far ABOVE the eye the camera sits at full pull-out — a small lift so the view looks slightly down over
## the character instead of straight through the back of their skull.
@export var height: float = 0.3
## Exponential rate the view eases between first and third person (per second; higher = snappier). ~9 reads as
## a quick, deliberate push-out of about a third of a second — fast enough not to feel like a cutscene, slow
## enough that the reveal of your own body is not a pop.
@export var blend_speed: float = 9.0
## Metres the mouse wheel moves the camera per notch while the view is pulled out. The wheel is the hotbar's
## the rest of the time — see `owns_wheel()` for the hand-off, which is the hotbar's own explicit-yield contract
## rather than a race between `_unhandled_input` handlers.
@export var zoom_step: float = 0.2

@export_group("Third Person: free look")
## HOLD the view-toggle control (middle mouse by default) and move the mouse to swing the camera AROUND your
## character without turning them — the Fallout: New Vegas camera. Releasing eases it back behind you.
## A TAP of the same control still toggles first/third person; the split is the Reload tap-vs-hold idiom.
@export var free_look: bool = true
## Seconds a press may last and still count as a TAP (a toggle). Longer and it becomes a free-look hold.
## The same shape as `GameSettings.weapon_general.reload_hold_threshold`, kept local because this one is a
## camera feel rather than a weapon one.
@export var free_look_hold_threshold: float = 0.22
## Radians of orbit per screen pixel of mouse movement while free-looking. Independent of look sensitivity on
## purpose: this is a camera gesture, not aiming, and it wants to cover the full circle in a short drag.
@export var free_look_speed: float = 0.005
## How far up / down the free orbit may swing (degrees). Past the poles the camera tips over the character.
@export var free_look_pitch_limit: float = 70.0
## Exponential rate the orbit eases back to centre once you let go (per second; higher = it snaps back sooner).
@export var free_look_return_speed: float = 8.0

@export_group("Third Person: when it gives way")
## Aiming down sights drops back to FIRST person for the length of the aim. The sight picture in this game IS
## the view model — iron sights and scopes are authored on the gun under the camera — so an over-the-shoulder
## ADS would be aiming with a gun you cannot see. Off = stay pulled out while aiming (the camera keeps its
## offset and you aim off the crosshair alone).
@export var first_person_when_aiming: bool = true
## A CONVERSATION drops back to first person too. `DialogueManager` pitches the camera at the speaker and the
## letterbox frames a face — a shot composed for an eye-height lens, which is not where this camera is. Same
## reason FirstPersonBody hides the whole FP body for a conversation (`fp_body_hide_in_dialogue`).
@export var first_person_in_dialogue: bool = true

## The wielder, injected by `Head.setup()`. Read for the death gate and the aim gate, and its collider is
## excluded from the spring cast. Null (an off-tree rig, a unit test) leaves this node inert but harmless.
var _player: Character

## The eased 0..1 pull-out. 0 = first person (this node contributes NOTHING — `ScreenShake.position` is left at
## the origin it has always had), 1 = the full authored offset. ThirdPersonBody polls it to fade the character
## in, so it is the ONE value the two halves of the feature agree on.
var blend: float = 0.0

## Last INTENT (see wants_third_person), kept only to spot the flip that fires view_changed.
var _wanted: bool = false

## FREE LOOK (the held-middle-mouse orbit). `_orbit` is the live yaw/pitch swing in RADIANS around the pivot —
## x = pitch, y = yaw — eased back to zero the moment the button comes up. `_press_us` is the press timestamp
## the tap-vs-hold split reads (< 0 = nothing held); `_free_looking` latches once a press has outlived
## free_look_hold_threshold, which is also what suppresses the toggle on release.
var _orbit: Vector2 = Vector2.ZERO
var _press_us: int = -1
var _free_looking: bool = false

## ⭐RIG NODES WHOSE LOCAL Z MEANS "THIS FAR IN FRONT OF THE EYE", and which therefore have to be pushed back
## out to the eye when the lens moves away from it. This is the one non-obvious consequence of pulling the
## camera back: everything hanging under it went along for the ride.
##   • RayCast (PickupRay) — its `target_position` IS the interaction reach. Left alone, a 2.2 m pull-out eats
##     2.2 m of a 3 m ray and you can no longer pick up anything that isn't pressed against your face.
##   • HoldAnchor — where a CARRIED prop floats. Left alone it ends up BEHIND the player's head, i.e. between
##     the camera and the character, so carrying a crate would black out the screen.
##   • LightPosition — the flashlight's beam origin (the torch is top_level and snaps to it). Left alone the
##     beam comes from two metres behind the character and lights their back.
## Each is rebased to `authored_z - pull_out`, which leaves its WORLD placement exactly what first person had.
## The one thing deliberately NOT rebased is the laser sight's beam mesh — it is a cosmetic emitter whose
## convergence already reads `get_aim_direction()`, so it points true; only its origin sits at the lens.
const REBASED_NODES := {
	"ScreenShake/Camera3D/RayCast": &"target_position",
	"ScreenShake/Camera3D/HoldAnchor": &"position",
	"ScreenShake/Camera3D/LightPosition": &"position",
}
## Resolved REBASED_NODES with their AUTHORED z captured once — {node, prop, z}.
var _rebased: Array[Dictionary] = []

func _ready() -> void:
	# The cast starts at the eye and reaches BACKWARD; margin keeps the lens off the surface it stops against.
	# collision_mask is authored on the node (world geometry only — the player is on layer 2 and would
	# otherwise stop the arm dead at zero length).
	top_level = false
	set_process(true)

## Inject the wielder. Called once from `Head.setup()`, the same place the camera and the pickup ray are handed
## their player — the rig has no other way to know who it belongs to. Excluding the wielder's own collider is
## belt-and-braces: the authored `collision_mask` already omits the player's physics layer, but a rig dropped on
## an actor with different layers would otherwise jam the camera at zero length with no visible cause.
func setup(player: Character) -> void:
	_player = player
	if player != null:
		add_excluded_object(player.get_rid())
	_rebased.clear()
	var head := get_parent()
	if head == null:
		return
	for path in REBASED_NODES:
		var n := head.get_node_or_null(path) as Node3D
		if n == null:
			continue  # a rig without that part simply isn't rebased
		var prop: StringName = REBASED_NODES[path]
		var v: Variant = n.get(prop)
		if v is Vector3:
			_rebased.append({"node": n, "prop": prop, "z": (v as Vector3).z})

## Is the view SUPPOSED to be third person this frame? The stored preference, minus every state that takes the
## camera back to the eye. Read live from `Settings` rather than cached — the same rule CameraEffects.base_fov
## learned the hard way, so the Options row and the key bind can never disagree about which is the truth.
func wants_third_person() -> bool:
	if not Settings.third_person_camera:
		return false
	if _player != null and _player.has_method(&"is_alive") and not _player.is_alive():
		return false  # the death cinematic is authored from the eye; let it have its camera back
	if first_person_in_dialogue and DialogueManager.is_engaged():
		return false
	if first_person_when_aiming and _is_aiming():
		return false
	return true

## True while the wielder is aiming down sights. Duck-typed through the weapon hub so a rig on an actor with no
## weapon system (or a bare unit-test Head) simply never aims.
func _is_aiming() -> bool:
	var p := _player as Player
	if p == null or p.weapon_system == null or p.weapon_system.scope_in == null:
		return false
	return p.weapon_system.scope_in.is_scoped

## Flip the stored preference (the key bind's entry point — Options writes the same field through its own
## setter). Public so a debug command or a cutscene can drive it too.
func toggle() -> void:
	Settings.set_third_person_camera(not Settings.third_person_camera)

## The key. `_unhandled_input` so an open menu or a dialogue box that has already consumed the press wins, and
## the two standard gates besides — the player menus deliberately do NOT pause the tree (see
## [[no-pause-on-menu-by-design]]), so without `gameplay_suppressed()` the camera would pop out behind an open
## inventory screen.
func _unhandled_input(event: InputEvent) -> void:
	if DialogueManager.is_active() or InputManager.gameplay_suppressed():
		return
	# THE WHEEL, while the view is out: step the distance and CONSUME the notch, so the hotbar's cycle doesn't
	# also fire. The hotbar yields to us by name as well (Hotbar._third_person_owns_wheel) rather than trusting
	# handler order — the same explicit contract it already has with the spray palette and the scope dial.
	if owns_wheel(event):
		var b := (event as InputEventMouseButton).button_index
		Settings.set_third_person_distance(distance + (-zoom_step if b == MOUSE_BUTTON_WHEEL_UP else zoom_step))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputManager.action_toggle_view):
		_press_us = Time.get_ticks_usec()
		_free_looking = false
	elif event.is_action_released(InputManager.action_toggle_view):
		# A SHORT press toggles the view; a long one was a free-look drag and must not also flip it.
		if _press_us > 0 and not _free_looking:
			toggle()
		_press_us = -1
		_free_looking = false

## TRUE when this camera owns the wheel notch in `event`. Raw wheel buttons only, and only while the view is
## actually pulled out — a REBOUND key on Hotbar Next/Prev has no camera-distance meaning, and in first person
## the wheel is the hotbar's as it always was. The same "real notch only" rule Hotbar._scope_owns_wheel uses,
## for the same reason.
##
## ⭐The two existing wheel owners (the spray palette, a variable scope's magnification) both require AIMING,
## and aiming forces the view back to first person — so third-person wheel ownership is disjoint from both by
## construction, not by a priority list.
func owns_wheel(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return false
	var b := (event as InputEventMouseButton).button_index
	if b != MOUSE_BUTTON_WHEEL_UP and b != MOUSE_BUTTON_WHEEL_DOWN:
		return false
	return is_pulled_out()

## Is the view meaningfully out of first person right now? The gate for wheel ownership and free look alike.
func is_pulled_out() -> bool:
	return blend > 0.05

## SWING THE CAMERA AROUND THE CHARACTER. MouseInput routes RAW mouse motion here (screen pixels, unscaled by
## look sensitivity) instead of to the body yaw / head pitch while the free-look button is held, so the
## character keeps facing where they were while the lens travels around them. Yaw wraps, pitch clamps.
func orbit(screen_delta: Vector2) -> void:
	var limit := deg_to_rad(free_look_pitch_limit)
	_orbit.y = wrapf(_orbit.y + screen_delta.x * free_look_speed, -PI, PI)
	# ⭐PITCH SIGN: a POSITIVE `_orbit.x` swings the camera DOWN and tilts it up (Rx(+p) takes the arm's +Z
	# offset to -Y), so the mouse's own sign carries straight through — pushing the mouse UP (a negative
	# screen_relative.y) lifts the camera over the character and looks down at them, which is the way round
	# every orbit camera works. Flipping this reads as inverted-Y on a gesture that has no invert setting.
	_orbit.x = clampf(_orbit.x + screen_delta.y * free_look_speed, -limit, limit)

## True while a held press has become a free-look drag. Read by MouseInput (to route the motion here instead of
## to the body) and by Player's aim accessors (so a shot still leaves along the CHARACTER's facing, never down
## the swung camera — the Fallout rule: free look is looking, not aiming).
func free_look_active() -> bool:
	return _free_looking

func _process(delta: float) -> void:
	var want := wants_third_person()
	if want != _wanted:
		_wanted = want
		view_changed.emit(want)
	blend = lerpf(blend, 1.0 if want else 0.0, 1.0 - exp(-maxf(blend_speed, 0.01) * delta))
	if blend < 0.0005 and not want:
		blend = 0.0  # settle exactly on zero so first person is bit-identical to a build without this node
	# A press that has outlived the tap window IS a free-look drag from this frame on (latched here rather than
	# on release, so the orbit starts while the button is still down — the Reload hold idiom).
	if free_look and _press_us > 0 and not _free_looking and is_pulled_out() 			and (Time.get_ticks_usec() - _press_us) / 1_000_000.0 >= free_look_hold_threshold:
		_free_looking = true
	# ...and once it is let go (or the view drops back to first person mid-drag) the swing eases home.
	if not _free_looking and _orbit != Vector2.ZERO:
		var t := 1.0 - exp(-maxf(free_look_return_speed, 0.01) * delta)
		_orbit = _orbit.lerp(Vector2.ZERO, t)
		if _orbit.length_squared() < 0.000001:
			_orbit = Vector2.ZERO
	_apply_offset()

## Write this frame's pull-out onto the shake pivot, after letting the engine shorten it for whatever the camera
## would otherwise have been pushed through.
##
## ⭐THE LATERAL OFFSET GOES ON THE ARM, NOT JUST ON THE RESULT. The shoulder/height offset is applied to THIS
## node's own position so the shape cast starts where the camera will actually be; casting from the eye-line and
## then sliding the result sideways is how a camera ends up inside the wall it just carefully avoided.
##
## ⭐AND THE FREE-LOOK ORBIT IS TWO WRITES, NOT ONE. Moving the camera around the pivot (`position`) only slides
## it sideways — it would keep staring off in the old direction. The lens has to TURN by the same angle to keep
## the character in frame, and the node that carries the camera's rotation is ScreenShake, which owns that
## property. So the arm hands it `base_rotation` and ScreenShake composes its own shake noise on top: one writer
## of `rotation`, with a documented input, instead of two nodes fighting over it.
func _apply_offset() -> void:
	var shake := _screen_shake()
	if shake == null:
		return
	var swing := Basis.from_euler(Vector3(_orbit.x, _orbit.y, 0.0))
	rotation = Vector3(_orbit.x, _orbit.y, 0.0)  # the spring probes along the SWUNG arm, not the old one
	position = swing * Vector3(shoulder * blend, height * blend, 0.0)
	spring_length = maxf(distance * blend, 0.0)
	# get_hit_length() is the length the engine settled on after the cast (== spring_length in open air, shorter
	# against a wall). It is computed on the internal PHYSICS tick, so this reads the most recent settled value.
	var pull := get_hit_length()
	shake.position = position + swing * Vector3(0.0, 0.0, pull)
	shake.base_rotation = Vector3(_orbit.x, _orbit.y, 0.0)
	_rebase(pull)

## Push the eye-relative rig parts back out to where first person had them (see REBASED_NODES). Epsilon-skipped
## so a settled first-person frame writes nothing at all.
func _rebase(pull: float) -> void:
	for e in _rebased:
		var n: Node3D = e["node"]
		if not is_instance_valid(n):
			continue
		var v: Vector3 = n.get(e["prop"])
		var z: float = float(e["z"]) - pull
		if absf(v.z - z) > 0.0005:
			v.z = z
			n.set(e["prop"], v)

func _screen_shake() -> Node3D:
	var head := get_parent() as Head
	return head.screen_shake if head != null else null
