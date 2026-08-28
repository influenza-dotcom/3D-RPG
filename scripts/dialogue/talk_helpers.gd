class_name TalkHelpers
extends RefCounted

## Shared helpers for the look-at talk system. A "talk target" is any node that exposes
## start_talk(player) + set_look_highlight(on); the player's interaction ray (ray_cast.gd)
## finds it by walking up from whatever talk-layer hitbox its ray hits. Both Talkable (an
## Area3D component) and DialogueNPC (a script on a node) route through these statics so they
## highlight, turn, and trigger identically -- the ray doesn't care which one it found.

## Dedicated physics layer for look-at talk hitboxes (editor layer 5 = bit value 16). The ray
## masks ONLY this for its talk query, so it never clashes with world / character / pickup
## collision, and a stray hit on this layer that ISN'T a talk target just resolves to null.
const TALK_LAYER: int = 16

## The collision-layer BIT a prop sits on while a player CARRIES it (PickupRay parks a held prop on
## PhysicsDamageSettings.pickup_held_collision_layer and floats it in front of the camera). Sight / perception /
## look-at rays mask this OUT — `& ~held_prop_collision_layer()` — so an item held in front of the face can't
## shield its carrier from being SEEN or block what a look-at verb aims at. Needed because a raycast ignores the
## collision EXCEPTION the player gets with the held prop, so otherwise the floating prop reads as a solid wall.
## Returns the RAW bitmask PickupRay assigns: the carry code does `collision_layer = pickup_held_collision_layer`
## directly, so the value IS the bit to clear — do NOT treat it as a 1<<index. NOTE this is intentionally NOT
## masked out of line-of-FIRE rays (bullets, the NPC clear-shot test, grapple): a carried prop stays solid cover.
## Read defensively: these rays run every frame per NPC, so a momentary autoload re-resolve (reimport / hot-reload)
## yields 0 here — clearing no bit and degrading to the old maskless behaviour for that frame, never throwing
## (see the per-frame-autoload-read canary).
static func held_prop_collision_layer() -> int:
	var pd: Variant = GameSettings.physics_damage
	if pd == null:
		return 0
	var v: Variant = pd.get(&"pickup_held_collision_layer")
	return int(v) if v is int else 0

# The NPC turn-to-face duration + the pre-speech buffer beat are designer knobs on GameSettings.dialogue
# (npc_turn_to_face_duration / talk_prompt_buffer_duration), read by the Talkable / DialogueNPC start_talk
# flow and the NPC-side prompt_talk (talk_approach.gd / npc.gd).

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

## May `player` PICKPOCKET this handler right now? Unlike is_talkable_now this is offered EVEN on a hostile
## NPC (you can lift an unaware enemy's pockets), so the ray checks it ALONGSIDE is_talkable_now when deciding
## whether to highlight + allow the interact. A handler opts in via can_pickpocket(player); anything that
## doesn't expose it (a corpse, a car, a pickup) is never pickpocketable.
static func is_pickpocketable_now(handler: Node, player: Node) -> bool:
	return handler != null and handler.has_method(&"can_pickpocket") and handler.can_pickpocket(player)

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
## trigger), so the white "talkable" outline can be toggled on the host's visible body. `include_root`
## also collects `host` itself when it IS a MeshInstance3D (matches the old per-script collectors that
## recursed from-and-including the root — e.g. an overlay applied to a body that's itself the mesh node).
## `stop_at` (optional) is a Callable(Node) -> bool that PRUNES a child subtree before it is walked —
## LookAtInteractable passes `owns_its_overlay` so a highlight can never adopt meshes another system drives.
## An InkOutline tint duplicate (meta `npc_tint_dup`) is NEVER collected — as a child (see `_collect`) and, since
## a caller may hand one straight in as the root, as `host` itself under `include_root`.
static func collect_meshes(host: Node, skip: Node = null, include_root: bool = false, stop_at: Callable = Callable()) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if include_root and host is MeshInstance3D and host != skip and not host.has_meta(&"npc_tint_dup"):
		# Same shield as `_collect`'s, applied to the ROOT: a generic clear_tint(root) / overlay pass handed a
		# duplicate would otherwise treat InkOutline's infrastructure as a highlight target — overwrite its shared
		# tint material or its layer and the raw log-depth bytes render as moving stripe bands on the MAIN camera
		# (reported 2026-08-25; see scripts/effects/body_part_gib.gd). A duplicate has no children, so the walk
		# below finds nothing further under it.
		out.append(host)
	_collect(host, skip, out, stop_at)
	return out

static func _collect(node: Node, skip: Node, out: Array[MeshInstance3D], stop_at: Callable = Callable()) -> void:
	for child in node.get_children():
		if child == skip:
			continue
		if child.has_meta(&"npc_tint_dup"):
			continue  # InkOutline's invisible disposition-tint duplicate (NpcOutline) — infrastructure,
			# never a highlight/overlay/gib-inheritance target; skipping HERE shields every walker at once
		if stop_at.is_valid() and bool(stop_at.call(child)):
			continue  # pruned: that subtree drives its own material_overlay (see owns_its_overlay)
		if child is MeshInstance3D:
			out.append(child)
		_collect(child, skip, out, stop_at)

## ⭐ True for a subtree that OWNS its own OUTLINE, so a look-at collect must not adopt it: an actor
## (Character/NPC — a disposition ring plus the damage flash) or a prop (Throwable — its rest/claimed ring
## plus its InkOutline actor-mask bit). A mesh carries exactly ONE outline id and the hover BORROWS it
## (InkOutline.set_tint_highlight), so adopting someone else's meshes paints white over THEIR line for as long
## as you look at YOU. Matters because the host defaults to `get_parent()`: an interactable dropped straight under the
## level root takes the whole map as its host and would otherwise collect every NPC and prop in the level.
## DUCK-TYPED on purpose — `Character` and `Throwable` both sit on the actor parse path and this file is on it
## too (character.gd calls collect_meshes), so a `class_name` edge from here would close a parse cycle; same
## reason ThrowTrail reads `is_trailing()` by name. `flash_red` is Character's, `set_outline_visible` is
## Throwable's, and each IS the API that drives the overlay we must leave alone.
static func owns_its_overlay(n: Node) -> bool:
	return n.has_method(&"flash_red") or n.has_method(&"set_outline_visible")

## ⭐ REMOVED 2026-08-27, recorded so nobody rebuilds them: `make_outline_material()` (the shared
## inverted-hull ShaderMaterial factory) and `set_overlay()` (the `talk_prev_overlay` stash that let the
## look-at highlight borrow a mesh's ONE material_overlay slot and hand it back). Both existed only to
## serve resources/shaders/outline.gdshader, which is DELETED: every outline in this game is now
## InkOutline's screen-space ring, the highlight borrows an ID instead of a material slot
## (InkOutline.set_tint_highlight — the same stash-and-restore shape, one layer down), and
## material_overlay is left to the damage flash alone. `collect_meshes` above is the half of that pairing
## that survives: the highlight components still gather the meshes they are allowed to touch (the
## owns_its_overlay prune still matters, because one mesh still carries exactly ONE outline) and hand
## that list to set_tint_highlight.

## Smoothly yaw `host` (Y-axis only) so its forward (-Z) points at the player -- the "NPC turns
## to face you" beat. Uses GLOBAL rotation (so a parented host turns correctly) on the shortest
## path, and runs the tween on the PLAYER: the host is frozen (PROCESS_MODE_DISABLED) for the
## conversation, which would pause a tween bound to it. No-op if the player is right on the host.
static func face_player(host: Node3D, player: Node3D, duration: float) -> void:
	var shortest := face_yaw(host, player)
	if is_nan(shortest):
		return  # player is right on top of the host — nothing to turn toward
	var tw := player.create_tween()
	tw.tween_property(host, "global_rotation:y", shortest, duration)

## The shortest-path target Y-rotation (radians, GLOBAL) that aims `host`'s +Z front at the player, or NAN when
## the player is right on top of the host (caller should skip the turn). Pure maths with no tween, so a caller
## that must own the tween on a specific node — e.g. the dialogue path, which owns it on the always-process
## DialogueManager autoload because the whole world is paused — can reuse the SAME yaw maths as face_player().
static func face_yaw(host: Node3D, player: Node3D) -> float:
	var to := player.global_position - host.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return NAN
	# Aim the model's FRONT at the player. These imported meshes face +Z (not Godot's default -Z
	# forward), so we point +Z at `to`. If a future model ends up backwards, negate both args.
	var target_yaw := atan2(to.x, to.z)
	var current := host.global_rotation.y
	return current + wrapf(target_yaw - current, -PI, PI)  # shortest-path target
