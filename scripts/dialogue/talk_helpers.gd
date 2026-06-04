class_name TalkHelpers
extends RefCounted

## Shared helpers for the look-at talk system. A "talk target" is any node that exposes
## start_talk(player) + set_look_highlight(on); the player's interaction ray (ray_cast.gd)
## finds it by walking up from whatever talk-layer hitbox its ray hits. Both Talkable (an
## Area3D component) and DialogueNPC (a script on a node) route through these statics so they
## highlight, turn, and trigger identically -- the ray doesn't care which one it found.

const OUTLINE_SHADER := preload("res://resources/shaders/outline.gdshader")

## Dedicated physics layer for look-at talk hitboxes (editor layer 5 = bit value 16). The ray
## masks ONLY this for its talk query, so it never clashes with world / character / pickup
## collision, and a stray hit on this layer that ISN'T a talk target just resolves to null.
const TALK_LAYER: int = 16

## Seconds for an NPC to rotate to face the player when talked to.
const TURN_DURATION: float = 0.35

## Beat between the player's interact press and the NPC actually beginning to speak — the NPC
## "gathers" (turns / closes the last step into frame) first, so talking PROMPTS a response rather
## than instantly forcing the dialogue box open. Used by the NPC-side prompt_talk flow (npc.gd) and
## the inanimate fallback in Talkable/DialogueNPC.start_talk.
const TALK_BUFFER: float = 0.4

## Walk up from a ray-hit collider to the nearest node that can be talked to (Talkable returns
## itself; a DialogueNPC's hitbox Area3D returns the DialogueNPC parent). null if none.
static func resolve_handler(collider: Object) -> Node:
	var n := collider as Node
	while n != null:
		if n.has_method(&"start_talk"):
			return n
		n = n.get_parent()
	return null

## May this talk handler be spoken to RIGHT NOW? The ray uses this to both suppress the look-at
## highlight and refuse the interact on a hostile NPC. A handler opts in by exposing
## can_be_talked_to() (Talkable / DialogueNPC resolve their host NPC and refuse if it's hostile);
## anything that doesn't (a car, a terminal) defaults to talkable, so existing targets are unchanged.
static func is_talkable_now(handler: Node) -> bool:
	if handler == null:
		return false
	if handler.has_method(&"can_be_talked_to"):
		return handler.can_be_talked_to()
	return true

## Resolve the name shown on the dialogue speaker label. An explicit `own` name (set on the Talkable
## / DialogueNPC) wins; otherwise read a `display_name` off `node` (an NPC exposes one, so a talkable
## NPC is named once on the NPC itself). Empty string => no name, and the label stays hidden.
static func speaker_name(own: String, node: Node) -> String:
	if not own.is_empty():
		return own
	if node != null:
		var dn: Variant = node.get(&"display_name")
		if dn is String:
			return dn
	return ""

## Gather every MeshInstance3D under `host`, skipping `skip`'s subtree (e.g. a component's own
## trigger), so the white "talkable" outline can be toggled on the host's visible body.
static func collect_meshes(host: Node, skip: Node = null) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(host, skip, out)
	return out

static func _collect(node: Node, skip: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child == skip:
			continue
		if child is MeshInstance3D:
			out.append(child)
		_collect(child, skip, out)

## THE shared outline-material builder. Single source of truth for "make an outline ShaderMaterial":
## used by the talk look-at highlight (Talkable / DialogueNPC) AND the NPC combat outline (npc.gd),
## so the two never drift. Sets the two uniforms the outline shader actually exposes -- outline_color
## and outline_width (NOT 'outline_thickness'; that name was a latent no-op bug, see npc.gd). Callers
## that need a chained pass (e.g. NPC's outline -> flash) set `next_pass` on the returned material.
static func make_outline_material(color: Color, width: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	mat.set_shader_parameter("outline_color", color)
	mat.set_shader_parameter("outline_width", width)
	return mat

## Add (mat) or remove (null) the look-at highlight overlay on every gathered mesh. The overlay
## slot is SHARED with an NPC's combat outline, so on highlight-ON we stash whatever overlay was
## already there and on highlight-OFF we RESTORE it (not null) — otherwise looking at an outlined
## enemy once would permanently wipe its black combat outline.
static func set_overlay(meshes: Array[MeshInstance3D], mat: ShaderMaterial) -> void:
	for m in meshes:
		if not is_instance_valid(m):
			continue
		if mat != null:
			if not m.has_meta(&"talk_prev_overlay"):
				m.set_meta(&"talk_prev_overlay", m.material_overlay)  # stash combat outline (or null)
			m.material_overlay = mat
		elif m.has_meta(&"talk_prev_overlay"):
			m.material_overlay = m.get_meta(&"talk_prev_overlay")  # restore it on look-away
			m.remove_meta(&"talk_prev_overlay")
		else:
			m.material_overlay = null

## Smoothly yaw `host` (Y-axis only) so its forward (-Z) points at the player -- the "NPC turns
## to face you" beat. Uses GLOBAL rotation (so a parented host turns correctly) on the shortest
## path, and runs the tween on the PLAYER: the host is frozen (PROCESS_MODE_DISABLED) for the
## conversation, which would pause a tween bound to it. No-op if the player is right on the host.
static func face_player(host: Node3D, player: Node3D, duration: float) -> void:
	var to := player.global_position - host.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	# Aim the model's FRONT at the player. These imported meshes face +Z (not Godot's default -Z
	# forward), so we point +Z at `to`. If a future model ends up backwards, negate both args.
	var target_yaw := atan2(to.x, to.z)
	var current := host.global_rotation.y
	var shortest := current + wrapf(target_yaw - current, -PI, PI)  # shortest-path target
	var tw := player.create_tween()
	tw.tween_property(host, "global_rotation:y", shortest, duration)
