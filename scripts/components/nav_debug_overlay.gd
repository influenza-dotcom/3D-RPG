@tool
class_name NavDebugOverlay
extends Node

## Drop this Node into a level (or bind an Input action) to VISUALIZE navigation AND AI behaviour while you play, so
## a designer can diagnose why an NPC is stuck, blind, or picking the wrong plan WITHOUT reading logs. Debug-build
## friendly and INERT by default (every layer ships OFF) — a safe no-op in a release build.
##
## Two families of layers, all gated by the master `enabled` (toggle it with `toggle_action`, or flip the checkboxes
## live via the remote inspector while the game runs):
##   NAVIGATION (Godot built-ins) — the green walkable navmesh polys + every NavigationAgent3D's path line. Pairs
##     with File -> Run scripts/tools/audit_navmesh.gd (the audit says WHICH polys are bad; this shows the NPCs
##     hitting them at runtime).
##   AI DIAGNOSTICS (drawn by this overlay, since the editor gizmos don't run in a running game) — per live NPC:
##     its Perception sight cone, a faction-coloured ground ring, and a floating GOAP goal/action label; plus the
##     extents of every trigger/hazard/audio/shadow volume (the runtime twin of the CYBER SUNDAY editor gizmos).
##
## The AI layers are drawn through a spawned-on-demand AiDebugDraw child (ImmediateMesh lines + billboard labels) so
## this script stays a thin "what to draw" coordinator; the wire geometry lives in the pure, tested WireShapes.

@export var enabled: bool = false: set = set_enabled     ## master on/off; flip in the inspector or call toggle()
@export var toggle_action: StringName = &""              ## optional Input action to master-toggle live; blank = none

@export_group("Navigation")
## The built-in navmesh debug draw (green walkable polygons). On by default so enabling the overlay behaves as it
## historically did; turn it off to see ONLY the AI layers below without the navmesh clutter.
@export var show_navmesh: bool = true: set = set_show_navmesh
## Also draw every NavigationAgent3D's current path line (the route an NPC is following right now).
@export var agent_paths: bool = true: set = set_agent_paths

@export_group("AI Diagnostics")
## Per live NPC, draw its Perception view-cone (fov_degrees x sight_range) as a flat wire fan at eye height. The
## cone is horizontal-only because Perception's FOV is (crouch height never hides you on its own).
@export var show_sight_cones: bool = false: set = set_show_sight_cones
## Per live NPC, a ground ring coloured by its disposition TOWARD THE PLAYER: hostile / friendly / neutral / a
## recruited companion (see the style colours below). Read "which team is this?" at a glance.
@export var show_faction_colors: bool = false: set = set_show_faction_colors
## Per live NPC, a floating label above its head with the current GOAP "goal / action" (e.g. "combat / fire_armed",
## or "idle / -"). This is the plan the brain is executing right now.
@export var show_goap_labels: bool = false: set = set_show_goap_labels
## Draw the extents of every TriggerVolume / HazardZone / AudioZone / ShadowVolume as a wireframe — the runtime
## equivalent of their editor gizmos, so a designer can see the invisible volumes while actually playing.
@export var show_trigger_zones: bool = false: set = set_show_trigger_zones

@export_group("AI Diagnostics — Style")
## Tint each sight cone by the NPC's Perception.State (calm green / detecting orange / alerted red / investigating
## yellow) instead of the flat `sight_cone_color`, so alertness reads off the cone itself.
@export var color_cone_by_alertness: bool = true
## Flat cone colour used when color_cone_by_alertness is off (matches the editor gizmo's "sight" yellow).
@export var sight_cone_color: Color = Color(1.0, 0.95, 0.3, 0.7)
## NEUTRAL faction ring colour (yellow by default). Hostile / friendly / companion colours come from CBPalette so
## they match the NPC outline + name cues (and honour the colorblind-safe toggle).
@export var faction_neutral_color: Color = Color(0.95, 0.85, 0.2, 0.85)
@export_range(0.1, 5.0) var faction_ring_radius: float = 0.6
## Trigger / audio / shadow volume wireframe colour (cyan — matches the gizmo "zone" material).
@export var zone_color: Color = Color(0.2, 0.9, 1.0, 0.7)
## HazardZone wireframe colour (orange-red — matches the gizmo "danger" material), so a damaging volume stands out.
@export var hazard_zone_color: Color = Color(1.0, 0.35, 0.1, 0.7)
## Draw the AI lines + labels ignoring depth, so you see cones/rings/labels THROUGH walls (the usual debug want).
@export var draw_through_walls: bool = true: set = set_draw_through_walls
@export_range(0.0, 3.0) var label_height: float = 0.45   ## metres above the head to float GOAP labels
@export_range(1, 200) var label_font_size: int = 32

@export_group("AI Toggle Actions")
## Optional Input actions to toggle each AI layer LIVE in-game (blank = unbound). Leave blank and just flip the
## checkboxes above via the remote inspector while playing — that's the zero-setup path. Bind these only if you want
## real in-game hotkeys (add them to the Input Map first; this overlay is dev tooling, not a player-facing setting,
## so its toggles intentionally live here / on dev keys, NOT in the Options menu).
@export var sight_cones_action: StringName = &""
@export var faction_colors_action: StringName = &""
@export var goap_labels_action: StringName = &""
@export var trigger_zones_action: StringName = &""

## The lazily-spawned line+label renderer (present only while enabled AND some AI layer is on). See _sync_renderer.
var _renderer: AiDebugDraw = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process_input(_any_action())
	_apply(enabled)  # applies nav flags + spawns/tears down the AI renderer + arms _process


func set_enabled(v: bool) -> void:
	enabled = v
	if is_inside_tree() and not Engine.is_editor_hint():
		_apply(v)


func toggle() -> void:
	set_enabled(not enabled)


func _input(event: InputEvent) -> void:
	if toggle_action != &"" and event.is_action_pressed(toggle_action):
		toggle()
	if sight_cones_action != &"" and event.is_action_pressed(sight_cones_action):
		set_show_sight_cones(not show_sight_cones)
	if faction_colors_action != &"" and event.is_action_pressed(faction_colors_action):
		set_show_faction_colors(not show_faction_colors)
	if goap_labels_action != &"" and event.is_action_pressed(goap_labels_action):
		set_show_goap_labels(not show_goap_labels)
	if trigger_zones_action != &"" and event.is_action_pressed(trigger_zones_action):
		set_show_trigger_zones(not show_trigger_zones)


# --- Navigation (built-in) layers ------------------------------------------------------------------------------

## The single funnel for the navigation debug flags + AI-renderer lifecycle. Each engine call is guarded so it can
## never crash if a debug-only API is absent in this build. `on` is the master `enabled`; the per-layer toggles
## decide what actually draws within that.
func _apply(on: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var nav_on := on and show_navmesh
	if NavigationServer3D.has_method("set_debug_enabled"):
		NavigationServer3D.set_debug_enabled(nav_on)
	if "debug_navigation_hint" in tree:
		tree.debug_navigation_hint = nav_on
	var agents: Array[NavigationAgent3D] = []
	NodeFinder.collect_by_class(tree.root, NavigationAgent3D, agents)
	for agent in agents:
		agent.debug_enabled = on and agent_paths
	_sync_renderer()


func set_show_navmesh(v: bool) -> void:
	show_navmesh = v
	if is_inside_tree() and not Engine.is_editor_hint():
		_apply(enabled)


func set_agent_paths(v: bool) -> void:
	agent_paths = v
	if is_inside_tree() and not Engine.is_editor_hint():
		_apply(enabled)


# --- AI diagnostic layers --------------------------------------------------------------------------------------

func set_show_sight_cones(v: bool) -> void:
	show_sight_cones = v
	_sync_renderer()

func set_show_faction_colors(v: bool) -> void:
	show_faction_colors = v
	_sync_renderer()

func set_show_goap_labels(v: bool) -> void:
	show_goap_labels = v
	_sync_renderer()

func set_show_trigger_zones(v: bool) -> void:
	show_trigger_zones = v
	_sync_renderer()

func set_draw_through_walls(v: bool) -> void:
	draw_through_walls = v
	if _renderer != null:
		_renderer.draw_through_walls = v


## True when at least one AI-diagnostic layer is switched on.
func _any_ai_layer() -> bool:
	return show_sight_cones or show_faction_colors or show_goap_labels or show_trigger_zones


func _any_action() -> bool:
	return (toggle_action != &"" or sight_cones_action != &"" or faction_colors_action != &""
		or goap_labels_action != &"" or trigger_zones_action != &"")


## Spawn the AiDebugDraw child when the overlay is enabled AND some AI layer is on; free it otherwise (which clears
## every line + label). Also arms/disarms _process — no per-frame work unless something is actually being drawn.
func _sync_renderer() -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		return
	var want := enabled and _any_ai_layer()
	if want and _renderer == null:
		_renderer = AiDebugDraw.new()
		_renderer.name = "AiDebugDraw"
		_renderer.draw_through_walls = draw_through_walls
		_renderer.label_font_size = label_font_size
		add_child(_renderer)
	elif not want and _renderer != null:
		_renderer.queue_free()
		_renderer = null
	set_process(want)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _renderer == null:
		return
	_renderer.label_font_size = label_font_size
	_renderer.begin()
	if show_sight_cones or show_faction_colors or show_goap_labels:
		for n in get_tree().get_nodes_in_group(Groups.NPC):
			var npc := n as NPC
			if npc == null or not is_instance_valid(npc) or not npc.is_alive():
				continue
			if show_sight_cones:
				_draw_sight_cone(npc)
			if show_faction_colors:
				_draw_faction_ring(npc)
			if show_goap_labels:
				_draw_goap_label(npc)
	if show_trigger_zones:
		_draw_trigger_zones()
	_renderer.end()


## One NPC's Perception view-cone: a flat wire fan at eye height, along the model's +Z (the direction Perception
## actually measures its FOV off — global_transform.basis.z). No-op if the NPC has no Perception yet (pre-_ready /
## a civilian) or a degenerate range/fov.
func _draw_sight_cone(npc: NPC) -> void:
	var p: Perception = npc._perception
	if p == null:
		return
	var sight := p.sight_range
	var fov := p.fov_degrees
	if sight <= 0.0 or fov <= 0.0:
		return
	var apex := p.global_transform * Transform3D(Basis(), Vector3(0.0, p.eye_height, 0.0))
	var col := cone_color_for_state(p.state) if color_cone_by_alertness else sight_cone_color
	_renderer.add_lines(WireShapes.cone_flat(sight, deg_to_rad(fov) * 0.5, Vector3.BACK, apex), col)


## One NPC's faction ring at its feet, coloured by resolved disposition toward the player (a recruited companion —
## an NPC also in the Player group — wins as an ally). Reuses CBPalette so the ring matches the NPC outline + name
## cues and honours the colorblind-safe toggle.
func _draw_faction_ring(npc: NPC) -> void:
	var kind: int = npc.resolved_disposition()
	var is_ally := npc.is_in_group(Groups.PLAYER)
	var col := CBPalette.disposition_color(is_ally, kind, faction_neutral_color)
	var x := Transform3D(Basis(), npc.global_position)
	_renderer.add_lines(WireShapes.ring(faction_ring_radius, x), col)


## One NPC's current GOAP plan as a floating "goal / action" label above the head. Reads the private _executor
## brain (a plain RefCounted) — either the goal or the action may be null (idle / plan exhausted).
func _draw_goap_label(npc: NPC) -> void:
	var ex: GoapExecutor = npc._executor
	var has_brain := ex != null
	var goal: StringName = &""
	var action: StringName = &""
	if has_brain:
		if ex.current_goal != null:
			goal = ex.current_goal.name
		var a := ex.current_action()
		if a != null:
			action = a.name
	var anchor: Vector3 = npc._head_position() + Vector3.UP * label_height
	_renderer.add_label(anchor, goap_label_text(has_brain, goal, action))


## Every trigger/hazard/audio/shadow volume in the scene, redrawn from its first child CollisionShape3D (exactly
## where the editor gizmo reads the extent). HazardZone is tinted danger-orange; the rest cyan. Re-scanned each
## frame (the volumes are static, but a debug tool favours correctness over caching a stale list).
func _draw_trigger_zones() -> void:
	var zones: Array[Node] = []
	_collect_zones(get_tree().root, zones)
	for z in zones:
		var zone := z as Node3D
		var cs := _first_collision_shape(zone)
		if cs == null or cs.shape == null:
			continue
		var col := hazard_zone_color if zone is HazardZone else zone_color
		_renderer.add_lines(WireShapes.shape_lines(cs.shape, zone.global_transform * cs.transform), col)


## One DFS collecting every trigger/hazard/audio/shadow volume at/under `node` (a single pass, vs four
## collect_by_class sweeps, since this redraws every frame while the layer is on). TutorialPrompt is a TriggerVolume
## subclass, so `is TriggerVolume` already covers it — matching the editor gizmo's membership.
func _collect_zones(node: Node, out: Array[Node]) -> void:
	if node is TriggerVolume or node is HazardZone or node is AudioZone or node is ShadowVolume:
		out.append(node)
	for c in node.get_children():
		_collect_zones(c, out)


## The first DIRECT child CollisionShape3D of a zone (where the zones author their extent), or null. Mirrors the
## editor gizmo's _first_collision_shape so runtime + edit-time read the same shape.
func _first_collision_shape(area: Node) -> CollisionShape3D:
	for c in area.get_children():
		if c is CollisionShape3D:
			return c as CollisionShape3D
	return null


# --- pure helpers (unit-tested; no tree / node access) ---------------------------------------------------------

## Sight-cone colour for a Perception.State: calm green (unaware) -> detecting orange -> alerted red ->
## investigating yellow. Pure so the alertness->colour mapping is testable off-tree.
static func cone_color_for_state(state: int) -> Color:
	match state:
		Perception.State.ALERTED:
			return Color(0.95, 0.2, 0.2, 0.75)        # locked on — red
		Perception.State.DETECTING:
			return Color(1.0, 0.6, 0.1, 0.72)         # filling the meter — orange
		Perception.State.INVESTIGATING:
			return Color(1.0, 0.9, 0.2, 0.68)         # searching last-known — yellow
		_:
			return Color(0.4, 0.9, 0.5, 0.6)          # UNAWARE / calm — green


## Format the GOAP label: "(no brain)" for an NPC without an executor, else "goal / action" with "idle"/"-" for a
## null goal/action. Pure so the string is testable without a live brain.
static func goap_label_text(has_brain: bool, goal: StringName, action: StringName) -> String:
	if not has_brain:
		return "(no brain)"
	var g := String(goal) if goal != &"" else "idle"
	var a := String(action) if action != &"" else "-"
	return "%s / %s" % [g, a]
