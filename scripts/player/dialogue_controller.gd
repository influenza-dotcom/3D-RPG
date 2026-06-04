class_name DialogueController
extends Node

## Conversation-time camera + weapon handling: swings the camera onto a dialogue target (FNV-style
## distance zoom timed to the letterbox bars), holsters the weapon for the duration and restores it
## after, and drives the weapon holster/unholster swing (incl. the de-escalation that makes provoked
## NPCs stand down when you put the gun away). Built in code under the Player and given a host ref
## right after .new().
##
## The Player keeps the externally-probed focus_camera_on() NAME (talkable.gd / dialogue_npc.gd call
## it via player.focus_camera_on) and forwards here; the dialogue + holster signal handlers are
## connected straight to this component in Player._ready.

const FOCUS_DURATION: float = 0.4  ## seconds to swing the camera onto a dialogue target
const DIALOGUE_FRAME_HEIGHT: float = 3.0  ## world-space vertical extent the dialogue zoom frames
const DIALOGUE_MIN_FOV: float = 25.0      ## floor so distant targets don't zoom to a pinhole

var host: Player

var _holster_before_dialogue: bool = false  ## weapon holster state before a conversation, restored after
var _zoom_tween: Tween  ## drives the dialogue FOV zoom, timed to the letterbox bars

## Swing the gun down out of view (holster) or back up into the ready pose (unholster), FNV-style.
## Driven by Attack.holster_changed (hold-R toggle / dialogue).
func on_weapon_holstered(on: bool) -> void:
	if on:
		# FNV-style de-escalation: holstering signals you mean no harm, so any NPC you PROVOKED into
		# hostility (a neutral/friendly you attacked) forgives you and stands down. Genuinely-hostile
		# factions (which were never provoked) are unaffected.
		for n in get_tree().get_nodes_in_group(&"npc"):
			if n.has_method(&"forgive_provoke"):
				n.forgive_provoke()
	if host.gun_mesh == null:
		return
	if on:
		host.gun_mesh.holster()
	else:
		host.gun_mesh.unholster()

## Put the weapon away for a conversation, remembering its prior state to restore afterward.
func on_dialogue_started() -> void:
	if host.weapon_system and host.weapon_system.attack:
		_holster_before_dialogue = host.weapon_system.attack.holstered
		host.weapon_system.attack.set_holstered(true)

func on_dialogue_finished() -> void:
	if host.weapon_system and host.weapon_system.attack:
		host.weapon_system.attack.set_holstered(_holster_before_dialogue)
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	if host.camera_effects:
		host.camera_effects.dialogue_fov = 0.0  # release the dialogue zoom; the FOV eases back to normal

## Smoothly aim the body yaw + head pitch at `target_pos` so the camera frames whatever the player
## is talking to. Called by the talk handler on conversation start; control returns afterward with
## the camera left facing the target.
func focus_camera_on(target_pos: Vector3) -> void:
	var camera_effects := host.camera_effects
	var head := host.head
	if camera_effects == null or head == null:
		return
	var to := target_pos - camera_effects.global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-flat.x, -flat.z)  # body forward (-Z) faces the target horizontally
	var max_pitch := deg_to_rad(GameSettings.camera.pitch_max_deg)
	var target_pitch := clampf(atan2(to.y, flat.length()), -max_pitch, max_pitch)  # + = look up
	var yaw_target := host.rotation.y + wrapf(target_yaw - host.rotation.y, -PI, PI)  # shortest path
	var tw := create_tween().set_parallel()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(host, "rotation:y", yaw_target, FOCUS_DURATION)
	tw.tween_property(head, "rotation:x", target_pitch, FOCUS_DURATION)
	# Distance-based zoom (FNV-style): narrow the FOV so the target frames similarly whatever the
	# range — the farther away, the more zoom. CameraEffects eases toward this while it's set.
	var dist := to.length()
	if dist > 0.01:
		var zoom_fov := clampf(rad_to_deg(2.0 * atan((DIALOGUE_FRAME_HEIGHT * 0.5) / dist)), DIALOGUE_MIN_FOV, camera_effects.base_fov)
		# Zoom in over the SAME time the letterbox bars take to slide in, so they land together.
		camera_effects.dialogue_fov = camera_effects.base_fov  # start un-zoomed
		if _zoom_tween and _zoom_tween.is_valid():
			_zoom_tween.kill()
		_zoom_tween = create_tween()
		_zoom_tween.tween_property(camera_effects, "dialogue_fov", zoom_fov, DialogueManager.letterbox_time())
