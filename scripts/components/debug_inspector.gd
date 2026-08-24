class_name DebugInspector
extends Node3D

## Drop-in LOOK-AT ENTITY INSPECTOR (debug builds only). Aim at anything and its live state is drawn in the
## world beside it: for an NPC its hp, resolved disposition + provoke, faction, Perception state / detection
## meter / suspicion tier, the GOAP goal+action it is executing, its combat target, its nav destination, its
## locomotion state and its stranded-cycle count; for anything else the node name, native class, script, groups
## and — when it duck-types as a Character — its hp. Aiming at a prop must never draw NOTHING, because "the
## overlay is broken" and "you are pointing at a wall" have to look different.
##
## THREE SURFACES DRIVE THIS, and they must agree:
##   - `toggle_key` (F4) — standalone, so the node works dropped into a scene with no console at all.
##   - `DebugConsole` -> `inspect on|off` -> set_enabled()/is_enabled() (debug_actions_world.gd `_cmd_inspect`).
##   - `DebugConsole` -> `who` -> describe_target(), which returns the SAME lines the floating label shows, so
##     the text dump and the live overlay can never disagree about what you are pointing at.
##   - `DebugConsole` -> `brain` / `npc <verb>` -> target() / hit_point(): the NODE and the impact POINT behind
##     that same cache, for commands that act on the aimed NPC instead of describing it.
##
## WORLD-SPACE CONTRACT (the AiDebugDraw trap). AiDebugDraw takes WORLD coordinates and its _ready forces
## `transform = Transform3D.IDENTITY` (ai_debug_draw.gd:38), so its GLOBAL transform is whatever its parent's is.
## Parent it under anything that moves and every line and label is silently offset. It is spawned as a child of
## THIS node, so this node pins itself to the world origin in _ready — `top_level = true` (ignore the parent
## transform entirely, since the console creates us under `tree.current_scene`, which may be a Node3D that
## someone later moves) plus an identity transform. Do not "tidy" either away.
##
## RAYCAST CONTRACT. `PhysicsDirectSpaceState3D` queries are only valid DURING a physics frame — off-frame they
## return an EMPTY dictionary with no error, indistinguishable from "the ray hit nothing" (the project's
## spacestate-needs-a-physics-frame trap). So the aim ray lives in _physics_process and the resolved target is
## CACHED; describe_target() re-reads that cached node's live fields and never casts a ray of its own, which is
## what lets the console call it from a button/keystroke callback.
##
## Aim comes from `player.get_aim_origin()` + `get_aim_basis()`, deliberately NOT `get_aim_direction()` — that
## one applies AimSway drift (player.gd:1410-1416), so a debug pick would wander off the crosshair. The talk-layer
## look-at chokepoint (PickupRay) is NOT reused: its reach is only 3.5 m and it queries areas on the talk layer.
##
## Nothing here writes gameplay state. It is a read-only overlay.

## Groups / Disposition are plain class scripts, NOT autoloads — preloaded by path so this file never depends on
## the editor's global-class cache being warm (the new-classname-not-registered cascade). Group NAMES must come
## from the Groups consts: tests/test_groups.gd fails any raw group literal under res://scripts.
const GroupsScript := preload("res://scripts/world/groups.gd")
const DispositionScript := preload("res://scripts/npc/disposition.gd")

## How far up the parent chain a ray hit is walked looking for the owning actor. A bound, not a tuning knob —
## it only stops a malformed tree from turning a per-frame walk into a hang.
const OWNER_WALK_LIMIT := 12
## Segment count for the little impact-point sphere. A drawing detail, not a gameplay number.
const HIT_MARKER_SEGMENTS := 8

## Escape hatch for the debug-build gate below. Ticking this in an exported build is a deliberate act (a QA or
## press build); a normal release must carry no cheat surface, so the default keeps the node inert.
@export var force_in_release: bool = false
## Master on/off. Flip it here, from the `inspect` console command, or with `toggle_key`.
@export var enabled: bool = false: set = set_enabled
## Raw dev key, deliberately NOT a rebindable InputManager action (docs/AUTHORING_GUIDE.md:1994 — a dev toggle
## must not drag in the 4-surface keybind contract). KEY_NONE unbinds it.
@export var toggle_key: Key = KEY_F4
## Keep resolving the aim target every physics frame even while the overlay is switched OFF, so the console's
## `who` has a fresh answer instead of "ask again next frame". Costs one short raycast per physics frame in a
## debug build. Turn it off to make the node fully inert until `inspect on`.
## Setter-backed because _apply() is the ONLY place the physics tick is armed: without one, flipping this box live
## in the remote inspector (the project's standard way to drive a debug node — nav_debug_overlay.gd:11-13) would be
## a dead knob until something else happened to call set_enabled().
@export var always_track: bool = true: set = set_always_track

@export_group("What to draw")
## The wire volume around the target (its own CollisionShape3D where it has one, else an axis-aligned box).
@export var show_wire: bool = true
## The floating fact stack above the target's head.
@export var show_labels: bool = true
## A line from an NPC to its NavigationAgent3D destination, with a ring at the far end — "where is it heading".
@export var show_nav_target: bool = true
## A small sphere at the exact point the aim ray struck, so you can tell a body hit from a near miss.
@export var show_hit_marker: bool = true

@export_group("Style")
@export_range(1, 200) var label_font_size: int = 26
## Metres above the target's head (or the top of its wire volume) to float the label stack.
@export_range(0.0, 3.0) var label_height: float = 0.5
## Draw lines + labels ignoring depth, so the readout stays visible through geometry (the usual debug want).
@export var draw_through_walls: bool = true: set = set_draw_through_walls
## NEUTRAL / unclassified NPC colour. HOSTILE / FRIENDLY / companion come from CBPalette so the readout matches
## the NPC rim outline and the hover name, and honours the colorblind-safe toggle.
@export var neutral_color: Color = Color(0.95, 0.85, 0.2, 0.9)
## Anything that is not an NPC — a crate, a door, a wall.
@export var prop_color: Color = Color(0.55, 0.8, 1.0, 0.9)
## The nav-destination line + ring.
@export var nav_color: Color = Color(0.4, 1.0, 0.6, 0.8)
@export_range(0.05, 3.0) var nav_ring_radius: float = 0.35
## Lift the nav line off the floor so it does not z-fight the ground when depth testing is on.
@export_range(0.0, 1.0) var nav_line_lift: float = 0.1
@export_range(0.01, 1.0) var hit_marker_radius: float = 0.08
## Wire volume used when the target has no usable CollisionShape3D (a bare MeshInstance3D, or a ConvexPolygon /
## Concave shape, which WireShapes.shape_lines returns empty for). Full extents, sitting ON the target's origin.
@export var fallback_box_size: Vector3 = Vector3(1.0, 2.0, 1.0)

@export_group("Aim ray")
@export_range(1.0, 1000.0) var max_range: float = 200.0
## Physics layers the aim ray collides with. Bodies only — areas (the talk layer, trigger volumes) are skipped
## so you inspect the actor, not the invisible box around it.
@export_flags_3d_physics var collide_mask: int = 0xFFFFFFFF
## Mask out the layer a CARRIED prop is moved to while held. Without this, a player holding a crate inspects the
## crate forever: the ray ignores the physics EXCEPTION the carrier gets, so the floating prop reads as a wall.
@export var ignore_held_prop: bool = true

## The lazily-spawned line + label renderer. Present only while `enabled`; freeing it clears everything it drew.
var _renderer: AiDebugDraw = null
## Last target resolved from the aim ray, CACHED from the physics tick (see the raycast contract above).
## `_target` is the ACTOR the hit belongs to; `_collider` is the body actually struck (they differ when the ray
## lands on a child body). Either can be freed OR silently parked out of the tree between ticks — run them through
## _usable() before EVERY transform read (`is`/property reads crash on a freed instance, queue_free() is deferred a
## frame, and an off-tree global_position is an engine error), and is_instance_valid() before a name-only read.
var _target: Node = null
var _collider: Node = null
## Vector3.INF = "the last tick hit nothing" (and before the first tick). Written together with `_target` on a hit
## and reset together in _clear_target(), so the drawing path (gated on _usable(_target)) never sees the sentinel;
## hit_point() hands it out verbatim so a command can tell "no point" from a genuine hit at the origin.
var _hit_point: Vector3 = Vector3.INF
var _distance: float = 0.0
## False until the first physics tick has actually run a query, so describe_target() can say "arming" instead of
## lying with "nothing under the crosshair" on the very first `who` after the console creates this node.
var _has_ticked: bool = false
## Latched when the debug-build gate refuses: the node stays permanently inert, whatever anyone calls.
var _gated_off: bool = false


# This script is intentionally NOT @tool, so none of its code runs in the editor — that is why (unlike
# NavDebugOverlay) there is no Engine.is_editor_hint() dance anywhere in this file.
func _ready() -> void:
	# DEBUG-BUILD GATE: an exported release must carry no cheat surface at all. Go inert rather than free()
	# ourselves, so a scene that authored this node still loads with the node in place.
	if not OS.is_debug_build() and not force_in_release:
		_gated_off = true
		set_enabled(false)
		set_process_input(false)
		return
	# DialogueManager owns the only gameplay pause in this project, and a paused tree stops _process, _input AND
	# _physics_process on an INHERIT node — i.e. exactly when you most want to inspect the NPC you are stuck
	# talking to. Every screen autoload runs ALWAYS for the same reason.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# See the WORLD-SPACE CONTRACT in the class docstring: our child AiDebugDraw draws in world coordinates, so
	# this node must sit at the world origin with an identity basis and stay there even if its parent moves.
	top_level = true
	transform = Transform3D.IDENTITY
	# Armed unconditionally rather than on `toggle_key != KEY_NONE`: the export can be re-pointed live from the
	# remote inspector, and gating the callback here would leave a key bound after _ready permanently dead. _input()
	# short-circuits on KEY_NONE itself, so the unbind still works and the per-event cost is one comparison.
	set_process_input(true)
	_apply()


# --- public API (DebugConsole / DebugMenu call these; keep the names) -------------------------------------

## Master switch. Also the property setter for `enabled`, so a designer ticking the box in the inspector and the
## console's `inspect on` land in the same place. Guarded on is_inside_tree() because a scene-authored export
## value is assigned BEFORE _ready — _ready calls _apply() itself to catch up.
func set_enabled(on: bool) -> void:
	enabled = on and not _gated_off
	if is_inside_tree():
		_apply()


func is_enabled() -> bool:
	return enabled


## The same facts the floating label shows, as text, for the console's `who`. Reads the CACHED target resolved on
## the last physics tick — it never raycasts, because an off-physics-frame space query silently returns empty
## (the spacestate-needs-a-physics-frame trap), which would make `who` report "nothing" while you stare at a
## raider. Empty return = genuinely nothing under the crosshair; the caller prints its own line for that.
func describe_target() -> PackedStringArray:
	if _gated_off:
		return PackedStringArray()
	if not _has_ticked:
		# TWO different reasons the cache is cold, and only ONE of them is cured by asking again. The aim ray runs
		# in _physics_process, which _apply() arms only while `enabled` or `always_track`; with both off, "run it
		# again" would send a dev round a loop that can never terminate. Say which wall they hit.
		var cold := "look-at readout arms on the next physics frame (the aim ray is only valid inside one) — run it again"
		if not is_physics_processing():
			cold = "look-at tracking is OFF (the overlay is disabled and always_track is unticked) — enable it first"
		return PackedStringArray([cold])
	if not _usable(_target):
		return PackedStringArray()
	return _facts_for(_target)


## The NODE under the crosshair as resolved on the LAST physics tick, or null. This is the seam the console's
## per-NPC commands (`brain`, `npc <verb>` — debug_actions_world.gd) act through: `who` gives them TEXT, this
## gives them the actor. Same cache, same _usable() gate as describe_target(), so "what am I aiming at" can never
## disagree between the readout and the command — and a freed / pooled-out-of-tree / mid-level-swap target reads
## as null rather than a crashing `is` or an off-tree transform error. NEVER a fresh raycast: a space-state query
## outside a physics frame silently returns empty (the trap tpaim documents in debug_actions_player.gd), and
## commands run from keystroke/button callbacks. Null before the first tick and whenever tracking is off.
func target() -> Node:
	if _gated_off or not _usable(_target):
		return null
	return _target


## The crosshair's world-space impact point from the SAME tick target() answers for, or Vector3.INF when that tick
## hit nothing (and before the first tick). Points-taking verbs (`npc walkto` / `npc investigate`) read this so
## "send it HERE" means the spot under the crosshair, not the target's origin. It is deliberately not tied to the
## target's validity: a hit stays a hit even if the struck actor was freed a frame later — the point is still
## where the ray landed. Same physics-tick cache, never a fresh cast (see target()).
func hit_point() -> Vector3:
	if _gated_off:
		return Vector3.INF
	return _hit_point


func set_draw_through_walls(v: bool) -> void:
	draw_through_walls = v
	if _renderer != null:
		_renderer.draw_through_walls = v


func set_always_track(v: bool) -> void:
	always_track = v
	if is_inside_tree():
		_apply()


# --- lifecycle -------------------------------------------------------------------------------------------

## Spawn the renderer when enabled, free it (clearing every line and label) when not, and arm the physics tick
## whenever we are drawing OR tracking for `who`.
func _apply() -> void:
	var want_render := enabled and not _gated_off
	if want_render and _renderer == null:
		_renderer = AiDebugDraw.new()
		_renderer.name = "AiDebugDraw"
		_renderer.draw_through_walls = draw_through_walls
		_renderer.label_font_size = label_font_size
		add_child(_renderer)
	elif not want_render and _renderer != null:
		_renderer.queue_free()
		_renderer = null
	set_physics_process((enabled or always_track) and not _gated_off)


## Raw dev-key toggle, swallowed locally the way DebugOverlay does (debug_overlay.gd:66-69) rather than joining
## InputManager's modal registry — dev tooling stays out of the player-facing modal contract.
func _input(event: InputEvent) -> void:
	if _gated_off or toggle_key == KEY_NONE:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != toggle_key:
		return
	set_enabled(not enabled)
	get_viewport().set_input_as_handled()


## The whole tick: re-resolve what the crosshair is on (physics-frame-only work), then redraw. begin() ->
## add_*() -> end() must run EVERY frame or last frame's labels stay on screen (ai_debug_draw.gd:9-12), so end()
## is called even on a frame that draws nothing.
func _physics_process(_delta: float) -> void:
	_refresh_target()
	if _renderer == null:
		return
	_renderer.label_font_size = label_font_size
	_renderer.begin()
	_draw_target()
	_renderer.end()


# --- targeting -------------------------------------------------------------------------------------------

## Cast from the player's aim and cache the actor it lands on. Runs ONLY from _physics_process.
func _refresh_target() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# A paused tree deactivates the physics server, so the query below would come back EMPTY with no error and
	# blank the readout for the whole conversation. Keep the last resolved target instead — the world is frozen,
	# so it is still correct.
	if tree.paused:
		return
	# human_player excludes recruited companions, which share the Player group.
	var player: Node3D = GroupsScript.human_player(tree)
	if player == null or not is_instance_valid(player):
		_clear_target()
		_has_ticked = true
		return
	if not player.has_method(&"get_aim_origin") or not player.has_method(&"get_aim_basis"):
		_clear_target()
		_has_ticked = true
		return
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	var origin: Vector3 = player.call(&"get_aim_origin")
	# The BASIS, not get_aim_direction(): that one applies AimSway drift, so the pick would not follow the
	# crosshair. -Z is forward in Godot.
	var aim: Basis = player.call(&"get_aim_basis")
	var mask := collide_mask
	if ignore_held_prop:
		# The raw layer bitmask a held prop is moved to, read defensively (0 = clear no bit) because it comes
		# through a GameSettings resource that momentarily re-resolves on a reimport.
		mask &= ~TalkHelpers.held_prop_collision_layer()
	var query := PhysicsRayQueryParameters3D.create(origin, origin - aim.z * max_range, mask)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excluded: Array[RID] = []
	var self_body := player as CollisionObject3D
	if self_body != null:
		excluded.append(self_body.get_rid())
	query.exclude = excluded
	var hit := space.intersect_ray(query)
	_has_ticked = true
	if hit.is_empty():
		_clear_target()
		return
	var collider: Object = hit.get("collider")
	if collider == null or not is_instance_valid(collider):
		_clear_target()
		return
	var hit_node := collider as Node
	if hit_node == null:
		_clear_target()
		return
	# "position" is always present on a hit; the fallback only exists so a malformed result degrades quietly.
	var fallback_point := origin
	var hit_body := hit_node as Node3D
	if hit_body != null:
		fallback_point = hit_body.global_position
	var point: Vector3 = hit.get("position", fallback_point)
	_collider = hit_node
	_target = _resolve_owner(hit_node)
	_hit_point = point
	_distance = origin.distance_to(point)


func _clear_target() -> void:
	_target = null
	_collider = null
	_hit_point = Vector3.INF  # keep the sentinel honest: a miss must not leave last hit's point for hit_point()
	_distance = 0.0


## Is a CACHED node handle safe to read a TRANSFORM off? is_instance_valid() alone is NOT enough here:
## Node3D.get_global_transform() hard-fails with an engine error on an off-tree node (`!is_inside_tree()`,
## node_3d.cpp) and degrades to identity, and this overlay reads global_position on every drawn frame and in every
## `who`. Two live paths park a still-VALID target OUT of the tree, and both are reachable while you are aiming at
## it: GameRoot.load_level remove_child()s the whole level subtree a frame before queue_free()ing it
## (game_root.gd:123-126), and NpcPool.reclaim parks a dead body out of tree WITHOUT freeing it (npc_pool.gd:146).
## Either would otherwise spam one engine error per physics frame — and GUT's error tracker fails any test that
## crosses one ([[gut-engine-errors-fail-offtree-transform-tests]]). is_instance_valid() MUST come first: `is` and
## property reads CRASH on a freed instance, and queue_free() is deferred by a frame.
## ⭐ The parameter is UNTYPED on purpose (the F-C46 idiom, options_menu.gd `_on_music_folder_picked`, and
## NpcTargeting._is_live): a `node: Node` signature makes the VM type-check the argument BEFORE the body runs, and a
## previously-freed handle FAILS that check — "Invalid type in function '_usable' ... (previously freed)" — so the
## is_instance_valid() guard inside would never get to answer. `_target` is exactly such a handle the tick after the
## aimed NPC's queue_free lands (target()/describe_target() run from console callbacks BETWEEN physics ticks, and a
## paused tree keeps the cached target without re-resolving it), so a typed param here would spam that error and
## fail every test that frees a target it was pointed at.
static func _usable(node) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree()


## Walk UP from the struck body to the actor that owns it: the first ancestor in the NPC or Player group, else
## the first one that duck-types as a Character (take_damage + is_alive), else the collider itself — a crate is
## its own owner and deserves a readout. Group membership is preferred over a class test: it is what the NPC
## itself registers (npc.gd:536) and it keeps this file decoupled from the NPC class.
static func _resolve_owner(hit_node: Node) -> Node:
	var node := hit_node
	var steps := 0
	while node != null and steps < OWNER_WALK_LIMIT:
		steps += 1
		if not is_instance_valid(node):
			return hit_node
		if node.is_in_group(GroupsScript.NPC) or node.is_in_group(GroupsScript.PLAYER):
			return node
		if node.has_method(&"take_damage") and node.has_method(&"is_alive"):
			return node
		node = node.get_parent()
	return hit_node


# --- drawing ---------------------------------------------------------------------------------------------

## One frame of overlay for the cached target, gated on _usable() first: the target can be killed and queue_free()d
## — or reclaimed into NpcPool, or ridden out of the tree by a level swap — between the tick that resolved it and
## this one.
func _draw_target() -> void:
	if not _usable(_target):
		return
	var body := _target as Node3D
	if body == null:
		return
	var col := _color_for(_target)
	# Built even when show_wire is off: the label anchor is derived from the volume's top so it clears the head
	# of a crate as well as an NPC.
	var wire := _wire_lines(body)
	if show_wire and not wire.is_empty():
		_renderer.add_lines(wire, col)
	if show_hit_marker:
		_renderer.add_lines(WireShapes.sphere(hit_marker_radius, Transform3D(Basis(), _hit_point), HIT_MARKER_SEGMENTS), col)
	if show_nav_target and _target.is_in_group(GroupsScript.NPC):
		_draw_nav_target(body)
	if show_labels:
		# ONE multi-line label, not a stack of Label3Ds: AiDebugDraw's labels are fixed_size (constant SCREEN
		# size at any distance) while their positions are world-space, so separately-placed lines would visibly
		# converge into each other as you back away. A single label's line spacing is screen-space and stays legible.
		var text := "\n".join(_facts_for(_target))
		_renderer.add_label(_label_anchor(body, wire), text, col)


## Where the NPC is actually heading. Reads `_nav.target_position` and measures the distance ourselves rather
## than calling is_navigation_finished() / get_next_path_position(), both of which force a nav-map query — and a
## map that has not synced yet (iteration_id 0, e.g. the first frames after a level load or a re-bake) pushes an
## engine error when queried.
func _draw_nav_target(body: Node3D) -> void:
	var nav: Object = _target.get(&"_nav")
	if nav == null or not is_instance_valid(nav):
		return
	var agent := nav as NavigationAgent3D
	if agent == null:
		return
	var dest := agent.target_position
	if not dest.is_finite():
		return
	var from := body.global_position + Vector3.UP * nav_line_lift
	_renderer.add_lines(PackedVector3Array([from, dest]), nav_color)
	_renderer.add_lines(WireShapes.ring(nav_ring_radius, Transform3D(Basis(), dest)), nav_color)


## The target's own physics volume where it has one (the honest shape — same source the editor gizmos read),
## else a deliberately AXIS-ALIGNED fallback box sitting on the origin, so an un-shaped prop still reads.
func _wire_lines(body: Node3D) -> PackedVector3Array:
	var shape_node := _first_collision_shape(body)
	if shape_node != null and shape_node.shape != null:
		var lines := WireShapes.shape_lines(shape_node.shape, body.global_transform * shape_node.transform)
		if not lines.is_empty():
			return lines
	var centre := body.global_position + Vector3.UP * (fallback_box_size.y * 0.5)
	return WireShapes.box(fallback_box_size, Transform3D(Basis(), centre))


## First DIRECT child CollisionShape3D — mirrors NavDebugOverlay._first_collision_shape so a volume reads the
## same in this overlay, that one, and the editor gizmo.
static func _first_collision_shape(node: Node) -> CollisionShape3D:
	for c in node.get_children():
		if c is CollisionShape3D:
			return c as CollisionShape3D
	return null


## Head height for an NPC (its public head anchor), else the top of the wire volume — plus `label_height`.
func _label_anchor(body: Node3D, wire: PackedVector3Array) -> Vector3:
	if body.has_method(&"head_world_position"):
		var head: Variant = body.call(&"head_world_position")
		if head is Vector3:
			var head_pos: Vector3 = head
			return head_pos + Vector3.UP * label_height
	var anchor := body.global_position
	for p in wire:
		anchor.y = maxf(anchor.y, p.y)
	return anchor + Vector3.UP * label_height


## Disposition colour for an NPC (a recruited companion — an NPC also in the Player group — wins as an ally),
## flat prop colour for everything else. CBPalette keeps this in lockstep with the rim outline and hover name.
func _color_for(node: Node) -> Color:
	if not node.is_in_group(GroupsScript.NPC):
		return prop_color
	var kind := -1
	if node.has_method(&"resolved_disposition"):
		kind = int(node.call(&"resolved_disposition"))
	return CBPalette.disposition_color(node.is_in_group(GroupsScript.PLAYER), kind, neutral_color)


# --- facts -----------------------------------------------------------------------------------------------

func _facts_for(node: Node) -> PackedStringArray:
	if node.is_in_group(GroupsScript.NPC):
		return _npc_facts(node)
	return _other_facts(node)


## Everything an NPC will tell you. Every field is read duck-typed through get()/call() rather than a typed NPC
## reference: this overlay is also aimed at companions, story NPCs and half-built actors, and a missing member
## must degrade to a dash instead of erroring. Several of these are PRIVATE fields (_perception, _executor,
## _target, _nav, _stranded_cycles) — there is no public accessor for them, and NavDebugOverlay reads the same
## three the same way (nav_debug_overlay.gd:220,236,246).
func _npc_facts(npc: Node) -> PackedStringArray:
	var out := PackedStringArray()

	var header := _text_of(npc, &"display_name", "")
	if header.strip_edges() == "":
		header = String(npc.name)
	if npc.has_method(&"is_alive") and not bool(npc.call(&"is_alive")):
		header += "   [dead]"
	out.append(header)

	out.append("hp %.0f/%.0f   %.1fm away" % [_num_of(npc, &"hp", 0.0), _num_of(npc, &"max_hp", 0.0), _distance])

	var kind := -1
	if npc.has_method(&"resolved_disposition"):
		kind = int(npc.call(&"resolved_disposition"))
	out.append("%s   faction %s" % [disposition_text(kind, _flag_of(npc, &"_provoked")), _faction_text(npc)])

	# Perception is the real "is it engaged with you" answer — see the _target line below for why.
	var state := -1
	var perception: Object = npc.get(&"_perception")
	if perception != null and is_instance_valid(perception):
		state = int(_num_of(perception, &"state", -1.0))
		var tier := -1
		if perception.has_method(&"suspicion"):
			tier = int(perception.call(&"suspicion"))
		out.append(perception_text(state, _num_of(perception, &"detection", 0.0), tier))
	else:
		out.append("sees -   (no Perception built)")

	out.append("goap " + _goap_text(npc))

	# NpcTargeting acquires by pure PROXIMITY with no LOS gate, and NPC.tscn ships sight_range 500 — so every
	# hostile holds the player as _target from level load (npc.gd:2582-2589). Say so when perception disagrees,
	# or this line reads as "the whole cast is hunting you".
	var target_name := "-"
	var held: Object = npc.get(&"_target")
	if held != null and is_instance_valid(held) and held is Node:
		target_name = String((held as Node).name)
		if state == Perception.State.UNAWARE:
			target_name += "  (proximity pick only — unaware)"
	out.append("target " + target_name)

	out.append(_nav_text(npc))

	var stranded := int(_num_of(npc, &"_stranded_cycles", 0.0))
	if stranded > 0:
		out.append("! stranded %d  (give-ups in the same spot; 3+ means a bad-bake nav island)" % stranded)
	return out


## A non-NPC target: a crate, a door, a terminal, a wall. Reported rather than silently skipped so "nothing is
## drawn" always means "you are pointing at nothing".
func _other_facts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(String(node.name))

	var kind := node.get_class()
	var script_ref: Object = node.get_script()
	if script_ref != null and script_ref is Script:
		var path := String((script_ref as Script).resource_path)
		if path != "":
			kind += "   " + path.get_file()
	out.append(kind)

	var groups := PackedStringArray()
	for g in node.get_groups():
		var name_text := String(g)
		# Godot's own internal groups are underscore-prefixed and are noise here.
		if not name_text.begins_with("_"):
			groups.append(name_text)
	if not groups.is_empty():
		out.append("groups " + ", ".join(groups))

	# A Character (a body that can be damaged) still has vitals worth showing even outside the npc group.
	if node.has_method(&"is_alive"):
		out.append("hp %.0f/%.0f" % [_num_of(node, &"hp", 0.0), _num_of(node, &"max_hp", 0.0)])

	var body := node as Node3D
	if body != null:
		out.append("%.1fm away   @ %s" % [_distance, _vec_text(body.global_position)])
	# The struck body is only worth naming when it is NOT the actor we resolved (a hitbox, a child collider).
	if _collider != null and is_instance_valid(_collider) and _collider != node:
		out.append("hit via " + String(_collider.name))
	return out


## "goal / action", via the shipped formatter so this overlay and NavDebugOverlay's floating labels read
## identically. BOTH the goal and the action can legitimately be null — no feasible goal, or an exhausted plan.
func _goap_text(npc: Node) -> String:
	var executor: Object = npc.get(&"_executor")
	var has_brain := executor != null and is_instance_valid(executor)
	var goal: StringName = &""
	var action: StringName = &""
	if has_brain:
		var current_goal: Object = executor.get(&"current_goal")
		if current_goal != null and is_instance_valid(current_goal):
			var goal_name: Variant = current_goal.get(&"name")
			if goal_name != null:
				goal = StringName(goal_name)
		if executor.has_method(&"current_action"):
			var current_action: Object = executor.call(&"current_action")
			if current_action != null and is_instance_valid(current_action):
				var action_name: Variant = current_action.get(&"name")
				if action_name != null:
					action = StringName(action_name)
	return NavDebugOverlay.goap_label_text(has_brain, goal, action)


## Nav destination + how the Locomotor is coping with it. `target_position` is a plain property read (no nav-map
## query — see _draw_nav_target), and the locomotion predicates are the honest answer to "why is it not moving".
func _nav_text(npc: Node) -> String:
	var nav: Object = npc.get(&"_nav")
	var body := npc as Node3D
	var line := "nav -"
	if nav != null and is_instance_valid(nav):
		var agent := nav as NavigationAgent3D
		if agent != null and agent.target_position.is_finite():
			var remaining := 0.0
			if body != null:
				remaining = body.global_position.distance_to(agent.target_position)
			line = "nav -> %s  (%.1fm)" % [_vec_text(agent.target_position), remaining]
	var loco: Object = npc.get(&"_locomotor")
	if loco != null and is_instance_valid(loco):
		var flags := PackedStringArray()
		for probe: StringName in [&"is_moving", &"is_struggling", &"is_holding"]:
			if loco.has_method(probe) and bool(loco.call(probe)):
				flags.append(String(probe).trim_prefix("is_"))
		if not flags.is_empty():
			line += "  " + " ".join(flags)
	return line


## Faction by its INTERNAL Faction.id where the resource resolved, falling back to the authored faction_id
## dropdown string (they can differ — Factions.ids() returns FILENAMES while Reputation keys on Faction.id).
func _faction_text(npc: Node) -> String:
	var faction: Object = npc.get(&"faction")
	if faction != null and is_instance_valid(faction):
		var id: Variant = faction.get(&"id")
		if id != null and String(id) != "":
			return String(id)
	var authored := _text_of(npc, &"faction_id", "")
	return authored if authored != "" else "-"


# --- pure helpers (no tree, no autoloads — unit-testable off-tree) ----------------------------------------

## "sees ALERTED  det 100%  susp alerted". Detection is a 0..1 meter; it is PINNED at 1.0 while ALERTED.
static func perception_text(state: int, detection: float, tier: int) -> String:
	var pct := int(round(clampf(detection, 0.0, 1.0) * 100.0))
	return "sees %s  det %d%%  susp %s" % [state_name(state), pct, suspicion_name(tier)]


static func state_name(state: int) -> String:
	match state:
		Perception.State.UNAWARE:
			return "UNAWARE"
		Perception.State.DETECTING:
			return "DETECTING"
		Perception.State.ALERTED:
			return "ALERTED"
		Perception.State.INVESTIGATING:
			return "INVESTIGATING"
	return "?"


static func suspicion_name(tier: int) -> String:
	match tier:
		Perception.SuspicionTier.CALM:
			return "calm"
		Perception.SuspicionTier.WARY:
			return "wary"
		Perception.SuspicionTier.SUSPICIOUS:
			return "suspicious"
		Perception.SuspicionTier.ALERTED:
			return "alerted"
	return "?"


## The attitude an NPC holds toward the player. `provoked` is called out separately because it OVERRIDES both the
## individual disposition and the faction standing — a "friendly" NPC you shot reads HOSTILE, and knowing which
## of the two is talking is the whole point of the line. if/elif rather than match so the enum comes through the
## preloaded script constant without relying on match-pattern constant folding.
static func disposition_text(kind: int, provoked: bool) -> String:
	var word := "?"
	if kind == DispositionScript.Kind.HOSTILE:
		word = "hostile"
	elif kind == DispositionScript.Kind.NEUTRAL:
		word = "neutral"
	elif kind == DispositionScript.Kind.FRIENDLY:
		word = "friendly"
	return word + ("  (provoked)" if provoked else "")


static func _vec_text(v: Vector3) -> String:
	return "%.1f %.1f %.1f" % [v.x, v.y, v.z]


## Duck-typed reads that degrade instead of erroring: Object.get() returns null for a member that does not exist
## on this particular actor, and float(null) / bool(null) would throw. The project's host-property convention.
static func _num_of(node: Object, prop: StringName, fallback: float) -> float:
	var v: Variant = node.get(prop)
	if v is float or v is int:
		return float(v)
	return fallback


static func _text_of(node: Object, prop: StringName, fallback: String) -> String:
	var v: Variant = node.get(prop)
	if v is String or v is StringName:
		return String(v)
	return fallback


static func _flag_of(node: Object, prop: StringName) -> bool:
	var v: Variant = node.get(prop)
	if v is bool:
		return bool(v)
	return false
