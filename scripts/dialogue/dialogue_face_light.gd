class_name DialogueFaceLight
extends Node3D

## A soft KEY LIGHT on the face of the NPC you're talking to, so its face stays readable during a conversation even
## in a dark scene. Built in code and owned by the DialogueManager autoload (added as a PROCESS_MODE_ALWAYS child
## alongside DialogueView / MusicDucker) — ONE light, retargeted to whoever the current speaker is, rather than a
## per-NPC node a designer has to place on every NPC. It fades in as the conversation opens and fades out when it
## ends; it's hidden entirely at rest. All feel/placement is tuned on GameSettings.dialogue (the "Face Light" group).
## Runtime only — there's nothing to preview in the editor.
##
## STATIC light: the pose is resolved ONCE — on the first frame the speaker's head is available — and then held
## FIXED in world space for the whole conversation. It deliberately does NOT track the head frame-to-frame: the
## speaker's head-look turns its head toward the player mid-talk, and a light that rode along with the head (as it
## did when it re-pinned every frame) read like a light welded to the head. Placing it once, at the face's rest
## pose, keeps it a steady key light the head can look around under. The SpotLight3D is top_level (its transform is
## independent of this node / the autoload — we set global_* directly) and sits IN FRONT of the head, on the side
## facing the player so it keys the face the player actually sees, aimed back at the head. This node is
## PROCESS_MODE_ALWAYS so the FADE keeps running while dialogue PAUSES the world (the pose is already latched by then).
##
## PUSH-DRIVEN, deliberately: DialogueManager calls begin(speaker) / end() from its own lifecycle rather than this
## node reaching back into the DialogueManager autoload. That keeps the dependency one-way (DialogueManager ->
## DialogueFaceLight, like it owns DialogueView / MusicDucker) with no parse cycle, and mirrors how the manager
## drives its other presentation children (_ducker.set_ducked, _view.open/close).

## The NPC currently being talked to (the light's subject), or null between conversations. A plain Node — the head
## anchor is resolved by duck-typed method (head_world_position / head_visual), so a speaker with no head (a note /
## terminal) simply gets no light.
var _target: Node = null
## The world-space spotlight we steer onto the face. Built in _ready, top_level so its transform is independent of
## this node / the autoload. Hidden until a conversation fades it in.
var _spot: SpotLight3D = null
## Smoothed fade envelope (0 -> face_light_energy). The light hides once this eases back to ~0 with no target.
var _energy: float = 0.0
## True once we've placed the light for the CURRENT conversation. The pose is latched exactly once (see class doc):
## the first frame the head resolves, we _place() and set this; thereafter the light stays put and we only fade.
## Reset by begin()/end() so each conversation re-latches fresh. A headless speaker never resolves -> never latches
## -> never lights (the note / terminal case).
var _pose_latched: bool = false

func _ready() -> void:
	# Keep keying the face while the world is PAUSED for dialogue (the same mode DialogueManager / its other
	# presentation children use). DialogueManager also sets this before add_child; set it here too for safety.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_spot = SpotLight3D.new()
	_spot.top_level = true            # world-space: ignore this node's / the autoload's transform, we set global_* directly
	_spot.visible = false
	_spot.light_energy = 0.0
	_spot.shadow_enabled = false      # a fill/key on the face, not a shadow-caster (cheaper, and face shadows look off)
	add_child(_spot)

## Aim the face light at `speaker` (the NPC being talked to). It fades in over the next frames; its pose is latched
## STATIC on the first frame the head resolves and then held fixed (see class doc). A speaker with no resolvable head
## (a Readable note / terminal — see _face_anchor) gets no light. Called by DialogueManager.start once the speaker is
## known. Clears any latch from a prior conversation so this one re-places from scratch.
func begin(speaker: Node) -> void:
	_target = speaker
	_pose_latched = false

## Release the light — it fades out and hides once dark. Called by DialogueManager._finish when the conversation ends
## (including the death-abort path), so the light never lingers on an NPC that's no longer talking to the player. The
## latch is cleared too so the next conversation places a fresh pose rather than reusing this one's.
func end() -> void:
	_target = null
	_pose_latched = false

func _process(delta: float) -> void:
	var cfg: DialogueSettings = GameSettings.dialogue
	# STATIC placement: resolve the face and place the light exactly ONCE per conversation — the first frame a live
	# speaker's head is available — then leave it fixed in world space. It does NOT follow the head afterwards (the
	# head-look turns the head toward the player mid-talk; the key light stays put). A headless speaker never
	# resolves an anchor, so it never latches and never lights (note / terminal case).
	var active := cfg.face_light_enabled and _target != null and is_instance_valid(_target)
	if active and not _pose_latched:
		var anchor: Variant = _face_anchor()
		if anchor != null:
			_place(anchor as Vector3)
			_pose_latched = true
	# Fade toward peak only once we've actually placed the light; otherwise toward 0 (off / ended / not yet latched).
	var target_energy := cfg.face_light_energy if (active and _pose_latched) else 0.0
	_energy = lerpf(_energy, target_energy, 1.0 - exp(-cfg.face_light_fade_speed * delta))
	# Faded out with nothing to light -> hide and stop touching the light (the common idle case, every frame).
	if _energy < 0.01 and target_energy == 0.0:
		if _spot.visible:
			_spot.visible = false
		return
	# Pose is already latched (or we're fading out on the last pose) — just drive the fade + live-tuned look.
	if not _spot.visible:
		_spot.visible = true
	_spot.light_energy = _energy
	_spot.light_color = cfg.face_light_color
	_spot.spot_range = cfg.face_light_range
	_spot.spot_angle = cfg.face_light_spot_angle

## The world position of the current speaker's face, or null when there's no speaker / no resolvable head (so an
## inanimate speaker gets no light). Prefers the NPC's own head resolution (bone / swapped head / capsule), then the
## swapped visible head node as a fallback. Duck-typed so it never hard-depends on the NPC class.
func _face_anchor() -> Variant:
	if _target == null or not is_instance_valid(_target):
		return null
	if _target.has_method(&"head_world_position"):
		var p: Variant = _target.call(&"head_world_position")
		if p is Vector3:
			return p
	if _target.has_method(&"head_visual"):
		var h: Variant = _target.call(&"head_visual")
		if h is Node3D and is_instance_valid(h):
			return (h as Node3D).global_position
	return null

## Position the spotlight in front of the face (toward the player, the visible side) and aim it back at the head.
func _place(head_pos: Vector3) -> void:
	var cfg: DialogueSettings = GameSettings.dialogue
	var front := _front_dir(head_pos)
	var light_pos := head_pos + front * cfg.face_light_distance + Vector3.UP * cfg.face_light_height
	_spot.global_position = light_pos
	var to_head := head_pos - light_pos
	# look_at rejects a target parallel to `up`; the light sits horizontally-out + slightly up from the face, so
	# to_head is never vertical in practice — but guard the degenerate case (distance/height mis-tuned to point straight down).
	if to_head.length() > 0.001 and to_head.normalized().cross(Vector3.UP).length() > 0.001:
		_spot.look_at(head_pos, Vector3.UP)

## Unit direction from the face toward the player (the side the player sees) — the key light sits between them so it
## lights the visible face. Falls back to the speaker's own forward (+Z, the axis it turned to face the player with)
## when the human player can't be found, and to world-forward as a last resort.
func _front_dir(head_pos: Vector3) -> Vector3:
	var player := Groups.human_player(get_tree())
	if is_instance_valid(player):
		var d := player.global_position - head_pos
		d.y = 0.0
		if d.length() > 0.01:
			return d.normalized()
	var spk := _target as Node3D
	if is_instance_valid(spk):
		var f := spk.global_transform.basis.z
		f.y = 0.0
		if f.length() > 0.01:
			return f.normalized()
	return Vector3.FORWARD
