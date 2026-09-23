extends GutTest

## The AI per-NPC command family (scripts/components/debug_actions_world_npc.gd: `brain`, `npc <verb>`), split out
## of debug_actions_world.gd on 2026-09-11. Pins (1) the static surface the dispatcher routes into and the
## registry<->family verb parity for `npc` BY SOURCE SCAN (the same approach test_debug_commands.gd takes for the
## match arms — run() cannot be driven live, it writes real NPC / autoload state), (2) the pure readout helpers
## (plan text / cost / why-no-plan over real GoapAction+GoapGoal objects, the enum-word formatters, the script
## chain const probe) with concrete inputs, and (3) that every command degrades to ONE honest line with no
## inspector, never a crash or a push_error.

const NPC_PATH := "res://scripts/components/debug_actions_world_npc.gd"
const WORLD_PATH := "res://scripts/components/debug_actions_world.gd"
const Commands := preload("res://scripts/components/debug_commands.gd")
const Npc := preload("res://scripts/components/debug_actions_world_npc.gd")
const Common := preload("res://scripts/components/debug_actions_world_common.gd")
const PerceptionScript := preload("res://scripts/npc/perception.gd")
const DispositionScript := preload("res://scripts/npc/disposition.gd")

## A duck-typed body: all _alive() may rely on is an is_alive() method.
class AliveDouble extends Node:
	var alive := true
	func is_alive() -> bool:
		return alive


func _static_names(script: GDScript) -> Dictionary:
	var out := {}
	for m in script.get_script_method_list():
		out[String(m["name"])] = true
	return out


## The `"word": ...` arms inside ONE static func's body in `src` (from its `static func <name>(` line to the next
## `static func` / end of file).
func _arms_in(src: String, func_name: String) -> Dictionary:
	var start := src.find("static func %s(" % func_name)
	assert_gt(start, -1, "%s is defined" % func_name)
	if start < 0:
		return {}
	var end := src.find("\nstatic func ", start + 1)
	var body := src.substr(start, (end - start) if end > 0 else -1)
	var rx := RegEx.new()
	rx.compile("\\n\\t\\t\"([a-z_]+)\":")
	var out := {}
	for m in rx.search_all(body):
		out[m.get_string(1)] = true
	return out


# --- dispatch surface -------------------------------------------------------------------------------------------

func test_dispatcher_routes_into_statics_that_exist() -> void:
	var names := _static_names(Npc)
	var world_src := FileAccess.get_file_as_string(WORLD_PATH)
	var rx := RegEx.new()
	rx.compile("NpcActions\\.(_cmd_[a-z_]+)\\(")
	var routed := {}
	for m in rx.search_all(world_src):
		var fn := m.get_string(1)
		routed[fn] = true
		assert_true(names.has(fn), "debug_actions_world.gd routes to NpcActions.%s() which does not exist" % fn)
	assert_true(routed.has("_cmd_brain"), "`brain` is routed to this family")
	assert_true(routed.has("_cmd_npc"), "`npc` is routed to this family")
	# vice-versa: every _cmd_* this family defines is reached from the dispatcher, else it is a DEAD handler.
	for fn in names.keys():
		if String(fn).begins_with("_cmd_"):
			assert_true(routed.has(fn), "%s is defined in the npc family but the dispatcher never routes to it (dead handler)" % String(fn))


## validate() is the ONLY gate in front of these handlers: _cmd_npc reads args[0] unguarded and to_float()s the value
## slot, _cmd_brain reads no args at all. So the registry rows must refuse exactly the argv shapes the handlers cannot
## take, and accept the ones they are documented to (a value on a non-sight verb is ignored, not an arity error).
func test_brain_and_npc_rows_admit_exactly_the_argv_their_handlers_read() -> void:
	var brain := Commands.find("brain")
	var npc := Commands.find("npc")
	assert_false(brain.is_empty(), "`brain` is a registry row")
	assert_false(npc.is_empty(), "`npc` is a registry row")
	assert_eq(Commands.validate(brain, PackedStringArray()), "", "a bare `brain` runs (it reads the crosshair, not argv)")
	assert_ne(Commands.validate(npc, PackedStringArray()), "",
		"a bare `npc` must be refused: _cmd_npc indexes args[0] with no guard, so letting it through would error in the console")
	assert_eq(Commands.validate(npc, PackedStringArray(["kill"])), "", "`npc kill` runs")
	assert_eq(Commands.validate(npc, PackedStringArray(["kill", "3"])), "", "`npc kill 3` is accepted (the value is ignored on every verb but sight)")
	assert_eq(Commands.validate(npc, PackedStringArray(["sight", "40"])), "", "`npc sight 40` runs")
	assert_ne(Commands.validate(npc, PackedStringArray(["sight", "far"])), "", "a non-number value is refused before _cmd_npc to_float()s it into 0")
	assert_ne(Commands.validate(npc, PackedStringArray(["explode"])), "", "a verb _cmd_npc has no arm for is refused up front")
	assert_ne(Commands.validate(npc, PackedStringArray(["kill", "3", "extra"])), "", "a third token is an arity error")
	# validate() lowercases the verb it checks, so the handler must too or `npc KILL` would pass the gate and then
	# fall into the "unknown verb" drift line.
	assert_eq(Commands.validate(npc, PackedStringArray(["KILL"])), "", "the gate accepts an upper-case verb")
	var shouted := Npc._cmd_npc({}, PackedStringArray(["KILL"]))
	assert_true(shouted.size() == 1 and shouted[0].begins_with("npc kill:"),
		"and the handler reads it as the same verb (lower-cased), never as a drifted unknown one: %s" % str(shouted))
	# Both rows share a menu page with `who`, the family's read-only sibling that targets the same crosshair NPC.
	var page := String(Commands.find("who")["category"])
	var on_page := {}
	for row in Commands.in_category(page):
		on_page[String(row["name"])] = true
	assert_true(on_page.has("brain") and on_page.has("npc"), "brain and npc sit on the same F1 page as `who` (%s)" % page)


func test_npc_verbs_match_the_registry_both_ways() -> void:
	# validate() has already restricted the verb slot to the registry list, so an arm the registry lacks is
	# unreachable and a registry word with no arm falls into the "unknown verb" drift line.
	var src := FileAccess.get_file_as_string(NPC_PATH)
	var arms := _arms_in(src, "_cmd_npc")
	var verbs: Array = Commands.find("npc")["verbs"]
	assert_gt(verbs.size(), 10, "the npc row lists its verbs")
	for v in verbs:
		assert_true(arms.has(String(v)), "registry verb 'npc %s' has no match arm in _cmd_npc — the verb is dead" % String(v))
	for a in arms.keys():
		assert_true(verbs.has(String(a)), "_cmd_npc handles '%s' but the registry never offers it (unreachable arm)" % String(a))


# --- degradation with no inspector ------------------------------------------------------------------------------

func test_commands_degrade_to_one_honest_line_with_no_tree() -> void:
	var brain := Npc._cmd_brain({})
	assert_eq(brain.size(), 1, "`brain` off-scene is exactly one line")
	assert_true(brain[0].contains("DebugInspector"), "and it names the missing inspector: %s" % brain[0])
	var npc := Npc._cmd_npc({}, PackedStringArray(["kill"]))
	assert_eq(npc.size(), 1, "`npc kill` off-scene is exactly one line")
	assert_true(npc[0].begins_with("npc kill:"), "prefixed with the verb so the console line reads as the command's: %s" % npc[0])
	var sight := Npc._cmd_npc({}, PackedStringArray(["sight", "40"]))
	assert_true(sight[0].begins_with("npc sight:"), "the value slot never changes the no-target path: %s" % sight[0])


func test_npc_point_resolves_here_to_the_player_and_degrades_without_one() -> void:
	var body := Node3D.new()
	add_child_autofree(body)
	var self_pick := {&"npc": body, &"aimed": body, &"sticky": false, &"error": ""}
	var no_player := Npc._npc_point({}, self_pick)
	assert_false((no_player[&"point"] as Vector3).is_finite(), "crosshair on the NPC itself with no player -> no point")
	assert_true(String(no_player[&"how"]).contains("no player"), "and the reason says so: %s" % String(no_player[&"how"]))
	var player := Node3D.new()
	add_child_autofree(player)
	player.global_position = Vector3(1, 2, 3)
	var here := Npc._npc_point({&"player": player}, self_pick)
	assert_eq(here[&"point"], Vector3(1, 2, 3), "crosshair on the NPC itself -> \"here\" is the PLAYER's position")
	assert_true(String(here[&"how"]).contains("your position"), "and the wording says so: %s" % String(here[&"how"]))
	var other_pick := {&"npc": body, &"aimed": null, &"sticky": true, &"error": ""}
	var no_insp := Npc._npc_point({&"player": player}, other_pick)
	assert_false((no_insp[&"point"] as Vector3).is_finite(), "no inspector -> no point")
	assert_true(String(no_insp[&"how"]).contains("hit_point"), "the reason names the missing accessor: %s" % String(no_insp[&"how"]))


# --- pure GOAP readout helpers ----------------------------------------------------------------------------------

func test_plan_text_and_cost_over_real_actions() -> void:
	var a := GoapAction.new(&"go", 2.0, {}, {&"there": true})
	var b := GoapAction.new(&"shoot", 3.5, {&"there": true}, {&"dead": true})
	var ws := GoapWorldState.new({})
	assert_eq(Npc._plan_text([a, b]), "go -> shoot", "actions are joined by arrows in plan order")
	assert_eq(Npc._plan_text([]), "", "an empty plan is an empty string")
	assert_eq(Npc._plan_text([a, null]), "go -> ?", "a null entry renders as ? rather than erroring")
	assert_almost_eq(Npc._plan_cost([a, b], ws), 5.5, 0.001, "cost sums each action's cost(ws)")
	assert_eq(Npc._plan_cost([], ws), 0.0, "an empty plan costs nothing")
	assert_eq(Npc._name_of(a), "go", "_name_of reads the action's name")
	assert_eq(Npc._name_of(null), "?", "_name_of(null) is ?")
	assert_eq(Npc._name_of(RefCounted.new()), "?", "an object with no name is ?")
	a = null
	b = null
	ws = null


func test_goal_priority_reads_the_goal_or_sorts_last() -> void:
	var g := GoapGoal.new(&"survive", 4.0, {&"safe": true})
	var ws := GoapWorldState.new({})
	assert_almost_eq(Npc._goal_priority(g, ws), 4.0, 0.001, "a goal's base priority reads through priority(ws)")
	assert_eq(Npc._goal_priority(null, ws), -INF, "null sorts last")
	assert_eq(Npc._goal_priority(RefCounted.new(), ws), -INF, "a non-goal sorts last")
	g = null
	ws = null


func test_why_no_plan_names_the_gating_fact_or_the_missing_producer() -> void:
	var goal := GoapGoal.new(&"kill", 1.0, {&"dead": true})
	var shoot := GoapAction.new(&"shoot", 1.0, {&"armed": true, &"seen": true}, {&"dead": true})
	var ws := GoapWorldState.new({&"armed": false})
	var why := Npc._why_no_plan(goal, [shoot], ws)
	assert_true(why.begins_with("shoot needs "), "the producer of the desired fact is named: %s" % why)
	assert_true(why.contains("armed=true (is false)"), "a precondition that reads false is listed with its live value: %s" % why)
	assert_true(why.contains("seen=true (is unset)"), "a precondition with NO fact at all reads 'unset': %s" % why)
	var none := Npc._why_no_plan(goal, [GoapAction.new(&"idle", 1.0, {}, {&"bored": true})], ws)
	assert_eq(none, "no action produces dead=true", "no producer at all is its own line")
	var satisfied := Npc._why_no_plan(goal, [GoapAction.new(&"shoot2", 1.0, {&"armed": true}, {&"dead": true})], GoapWorldState.new({&"armed": true}))
	assert_eq(satisfied, "unreachable within the iteration cap", "every precondition holds -> the only explanation left is the cap")
	goal = null
	shoot = null
	ws = null


# --- enum-word formatters ---------------------------------------------------------------------------------------

func test_perception_state_text_uses_the_enum_words() -> void:
	for key in PerceptionScript.State.keys():
		assert_eq(Npc._perception_state_text(int(PerceptionScript.State[key])), String(key), "State.%s round-trips through find_key" % String(key))
	assert_eq(Npc._perception_state_text(-1), "?", "-1 (no perception) is ?")
	assert_eq(Npc._perception_state_text(999), "?", "an unknown value is ?")


func test_disposition_text_covers_every_kind() -> void:
	for key in DispositionScript.Kind.keys():
		assert_eq(Npc._disposition_text(int(DispositionScript.Kind[key])), String(key), "Kind.%s renders as its word" % String(key))
	assert_eq(Npc._disposition_text(-1), "?", "an unknown kind is ?")


func test_script_chain_has_const_walks_the_base_chain() -> void:
	assert_true(Npc._script_chain_has_const(Npc, "Common"), "a const on the script itself is found")
	assert_false(Npc._script_chain_has_const(Npc, "NO_SUCH_CONST"), "a const nobody declares is not found")
	assert_false(Npc._script_chain_has_const(null, "Common"), "a null script is false, never a crash")
	# dog_pickup.gd extends CanPickUp (can_pick_up.gd), which declares ModelResourceUtil — only visible by walking
	# get_base_script(), since get_script_constant_map() is per-script.
	var sub := load("res://scripts/components/dog_pickup.gd") as GDScript
	assert_not_null(sub, "dog_pickup.gd loads")
	if sub != null:
		assert_false(sub.get_script_constant_map().has("ModelResourceUtil"), "the subclass's OWN map lacks the base const (the reason the walk exists)")
		assert_true(Npc._script_chain_has_const(sub, "ModelResourceUtil"), "a const declared on the BASE script is found through the chain")


func test_alive_gate_is_null_and_duck_safe() -> void:
	assert_false(Npc._alive(null), "null is not alive")
	var plain := Node.new()
	assert_false(Npc._alive(plain), "a node with no is_alive() is not alive (never an error)")
	plain.free()
	# The gate must READ is_alive(), not merely find it: every verb (heal / restock / provoke / ...) refuses a corpse
	# through this one call, and a heal on a corpse is the "revive past the death freeze" bug it exists to stop.
	var body := AliveDouble.new()
	assert_true(Npc._alive(body), "a body whose is_alive() is true is alive")
	body.alive = false
	assert_false(Npc._alive(body), "the same body once is_alive() reads false is dead — the gate reports the answer, not the method")
	body.free()
	# A FREED handle cannot even be passed: the `n: Node` parameter type rejects it at the call boundary, so the
	# in-body is_instance_valid guard is only reachable through the Variant-typed pick dictionary the callers use.
