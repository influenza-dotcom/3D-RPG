extends GutTest

## The two dev-only seams the AI debug commands act through (2026-08-18, loop iteration 2):
##  * NPC.DEBUG_NOTARGET_META — the ghost gate at the top of NPC._treats_as_enemy (the ONE predicate targeting
##    acquires/keeps by and the per-frame Perception.is_hostile writer), read by DebugActionsWorld `notarget`.
##  * DebugInspector.target() / hit_point() — the physics-tick cache the per-NPC verbs (`brain`, `npc <verb>`)
##    resolve their actor and point through, never a fresh raycast.
## An NPC's _ready is never run here (CLAUDE.md) — the gate is pinned by SOURCE SCAN because _treats_as_enemy's
## fall-through calls is_hostile_to → _protectee, which read components only _ready builds. The inspector IS
## constructed off-tree (no _ready), which is exactly the "before the first tick" state its accessors promise; its
## cache is then poked directly (white-box, the members are the contract) to drive the three lifecycles a physics
## tick cannot be made to produce here: a target parked OUT of the tree (NpcPool.reclaim), a target FREED (an NPC's
## queue_free landing), and a miss (_clear_target).

const InspectorScript := preload("res://scripts/components/debug_inspector.gd")

const NPC_PATH := "res://scripts/npc/npc.gd"
const WORLD_ACTIONS_PATH := "res://scripts/components/debug_actions_world.gd"


func test_inspector_accessors_are_null_and_inf_before_the_first_tick() -> void:
	var insp = InspectorScript.new()
	assert_null(insp.target(), "no physics tick has run -> no target")
	assert_eq(insp.hit_point(), Vector3.INF, "no physics tick has run -> the INF sentinel, never a stale point")
	insp.free()


func test_inspector_target_refuses_off_tree_and_freed_bodies_and_hit_point_outlives_them() -> void:
	# The cache is written by _refresh_target inside a physics tick (a real raycast); here it is written by hand,
	# because what is under test is the READ side: what target()/hit_point() hand out for each state the cached
	# handle can be in between ticks. Any engine error along the way (a typed-param "previously freed" rejection, an
	# off-tree transform read) fails this test through GUT's error tracker — that IS part of the assertion.
	var insp = InspectorScript.new()
	var body := Node3D.new()
	add_child(body)  # in the tree = a live hit
	var point := Vector3(1.5, 0.0, -3.25)
	insp._target = body
	insp._hit_point = point
	assert_eq(insp.target(), body, "a live in-tree target resolves")
	assert_eq(insp.hit_point(), point, "the impact point of that hit")

	remove_child(body)  # NpcPool.reclaim parks a body OUT of the tree without freeing it (still is_instance_valid)
	assert_null(insp.target(), "an out-of-tree (pooled) body must read null — a global_position on it is an engine error")
	assert_eq(insp.hit_point(), point, "parking the target does not un-hit the point")

	body.free()  # the aimed NPC's queue_free landing: the cached handle now dangles
	assert_null(insp.target(), "a freed target reads null, with no engine error (see _usable's untyped param)")
	assert_eq(insp.hit_point(), point, "hit_point() survives the target being freed — the ray still landed there")

	insp._clear_target()  # what a MISS does on the next tick
	assert_null(insp.target(), "a miss clears the target")
	assert_eq(insp.hit_point(), Vector3.INF, "a miss resets the INF sentinel — never last hit's point")
	insp.free()


func test_notarget_meta_gate_leads_treats_as_enemy() -> void:
	var src := FileAccess.get_file_as_string(NPC_PATH)
	assert_false(src.is_empty(), "npc.gd must be readable")
	assert_true(src.contains("const DEBUG_NOTARGET_META := &\"debug_notarget\""),
		"the ghost meta name is a const on NPC (the reader must not hand-type the string)")
	var fn := src.find("func _treats_as_enemy(node: Node) -> bool:")
	assert_gt(fn, -1, "_treats_as_enemy exists")
	# The window is THIS function only: from its signature to the next top-level `func`, so a match can never come
	# from a neighbour, and a gate that drifted below the function is a real miss, not a find in someone else's body.
	var next_fn := src.find("\nfunc ", fn + 1)
	var body := src.substr(fn, (next_fn - fn) if next_fn > fn else -1)
	var gate := body.find("node.has_meta(DEBUG_NOTARGET_META)")
	var hostile := body.find("if is_hostile_to(node):")
	assert_gt(gate, -1, "the ghost gate is inside _treats_as_enemy")
	assert_gt(hostile, -1, "the normal hostility test is still there")
	assert_lt(gate, hostile, "the ghost gate comes FIRST — a ghost must never be engaged via the protectee branch either")
	# The gate must validity-check before the meta read: has_meta on a null/freed instance crashes.
	var gate_line_start := body.rfind("\n", gate) + 1
	var gate_line_end := body.find("\n", gate)
	var gate_line := body.substr(gate_line_start, (gate_line_end - gate_line_start) if gate_line_end > gate_line_start else -1)
	assert_true(gate_line.contains("is_instance_valid(node)"), "the gate reads the meta only on a valid instance: %s" % gate_line)
	assert_true(gate_line.strip_edges().begins_with("if "), "the gate is a live statement, not a comment mentioning it: %s" % gate_line)
	# "FIRST" means first STATEMENT: nothing but comments/blank lines may sit between the signature and the gate,
	# or a later edit could slip a return path in front of it and this test would still pass on ordering alone.
	var lines_before := body.substr(0, gate_line_start).split("\n")
	for i in range(1, lines_before.size()):  # 0 = the signature line itself
		var stripped := lines_before[i].strip_edges()
		assert_true(stripped.is_empty() or stripped.begins_with("#"),
			"only comments precede the ghost gate inside _treats_as_enemy, found: %s" % lines_before[i])
	# And the gate short-circuits FALSE — the whole point is "never an enemy", not "always one".
	var after_gate := body.substr(gate_line_end if gate_line_end > -1 else gate)
	assert_true(after_gate.strip_edges().begins_with("return false"), "the ghost gate returns false: %s" % after_gate.substr(0, 40))


func test_notarget_reader_uses_the_same_literal_and_actually_writes_it() -> void:
	# The seam is only alive while something WRITES the meta the NPC gate READS, under the SAME literal. Pin both
	# halves from source: the writer declares its own StringName const with the NPC's literal (it deliberately does
	# not import NPC.DEBUG_NOTARGET_META, to stay free of a compile-time NPC dependency) and calls set_meta /
	# remove_meta / has_meta through THAT const — a comment that merely mentions the name must not satisfy this.
	var npc_src := FileAccess.get_file_as_string(NPC_PATH)
	var world := FileAccess.get_file_as_string(WORLD_ACTIONS_PATH)
	assert_false(npc_src.is_empty(), "npc.gd must be readable")
	assert_false(world.is_empty(), "debug_actions_world.gd must be readable")
	var literal := _string_name_const_literal(npc_src, "DEBUG_NOTARGET_META")
	assert_eq(literal, "debug_notarget", "NPC.DEBUG_NOTARGET_META is a &\"...\" const with the ghost literal")
	var re := RegEx.new()
	re.compile("const (\\w+) := &\"%s\"" % literal)
	var m := re.search(world)
	assert_not_null(m, "debug_actions_world.gd declares a StringName const carrying the NPC's literal \"%s\"" % literal)
	if m == null:
		return
	var reader_const := m.get_string(1)
	assert_true(world.contains("set_meta(%s, " % reader_const), "`notarget on` writes the meta through %s" % reader_const)
	assert_true(world.contains("remove_meta(%s)" % reader_const), "`notarget off` clears the meta through %s" % reader_const)
	assert_true(world.contains("has_meta(%s)" % reader_const), "the toggle reads the current state through %s" % reader_const)


## The literal inside `const NAME := &"..."`, or "" when the const is not declared that way.
static func _string_name_const_literal(src: String, const_name: String) -> String:
	var re := RegEx.new()
	re.compile("const %s := &\"([^\"]*)\"" % const_name)
	var m := re.search(src)
	return m.get_string(1) if m != null else ""
