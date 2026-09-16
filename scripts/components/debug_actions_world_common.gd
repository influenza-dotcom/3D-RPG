extends RefCounted

## The SHARED half of the world debug actions: every helper, const and cached static that more than one of the
## world action modules needs — ctx accessors, tree lookups, the content scans `sources()` completion reads, the
## formatting helpers, and the state keys `release_scene_scoped_state` erases. Split out of debug_actions_world.gd
## on 2026-09-11 so the per-NPC, Story and View command families could move into their own files WITHOUT a preload
## cycle: this file preloads NOTHING from the action modules, they all preload it (by PATH — no class_name, so the
## split never depends on the editor having rescanned the global class cache).
##
## Everything here is `static`; the underscore names are private to the FAMILY (the four world action files), not to
## this file — GDScript does not enforce it, and the names are kept so the per-command code reads as it always did.

const GroupsScript := preload("res://scripts/world/groups.gd")


# =============================================================================================================
# constants and cached statics (from the main file's header)
# =============================================================================================================

## ⭐DebugInspector is referenced by PATH and loaded LAZILY, never preloaded — matching the DebugNoclip handling in
## debug_actions_player.gd:40-45. A `preload()` of a path not on disk YET is a HARD PARSE FAILURE, so preloading a
## sibling script that lands in the same change would take this module — and the console and menu that preload US —
## down with it until every file exists. A runtime load degrades to one honest line instead. Swap it back to a
## preload only if debug_inspector.gd is ever guaranteed to ship ahead of this file.
const INSPECTOR_SCRIPT_PATH := "res://scripts/components/debug_inspector.gd"

const QUEST_DIR := "res://resources/quests/"

## `killall` damage. Routed through take_damage (NOT die()) so the kill is fully credited: XP, notify_kill for a
## quest, the faction kill_penalty, the bounty, the lootable corpse.
const KILL_DAMAGE := 99999.0

## `ledger` prints at most this many entries per bucket before a "... N more" tail — a long-played level's
## world_objects bucket holds one row per door/pickup/prop ever touched, and the console scrollback is finite.
const LEDGER_MAX_LINES := 40

## `resurrect` names at most this many forgotten snapshot keys inline (the rest are counted).
const RESURRECT_MAX_NAMED := 8

## Whether `freezeai` currently has the cast under cutscene control (there is no engine-side flag to read back).
const STATE_FREEZE_AI := &"world/freeze_ai"

## The NPC the last `npc`/`brain` command acted on (a Node handle, validity-checked on every read). The
## crosshair NPC ALWAYS wins; this is only the fallback that lets `npc walkto` / `npc investigate` take a POINT
## from the crosshair — you cannot aim at the NPC and at the spot it should walk to in the same frame.
const STATE_NPC_STICKY := &"world/npc_sticky"

## `hud off`'s snapshot: a PackedStringArray of UI-relative NodePaths (String) of every direct HUD child the sweep
## hid, held while the HUD is down. Node PATHS, not handles: toasts and floats are freed under the hide, and a path
## that no longer resolves is simply skipped on restore. Erased by `hud on` and by release_scene_scoped_state.
const STATE_HUD_HIDDEN := &"world/hud_hidden"

## `screenshot` output. user:// only — the project rule for anything a debug command writes.
const SCREENSHOT_DIR := "user://screenshots"

## The 2D debug drop-ins a `screenshot clean` frame hides, matched by SCRIPT PATH on any CanvasLayer in the tree
## (never `is <class>` — the stale-cache cascade, and a designer may parent one under an autoload). The two
## Groups.DEBUG_SURFACE members are listed too, belt and braces, for a build where the group is empty.
const CLEAN_HIDDEN_SCRIPT_PATHS: Array[String] = [
	"res://scripts/components/debug_console.gd",
	"res://scripts/components/debug_menu.gd",
	"res://scripts/components/debug_overlay.gd",
	"res://scripts/components/ai_event_log.gd",
	"res://scripts/components/debug_event_ticker.gd",
]

## The Perception fields NPC._build_perception copies ONCE at build time and never re-syncs (npc.gd:1977-1984 —
## the survey's #1 AI trap: writing npc.sight_range at runtime does not move the sight cone). `npc rebrain`
## re-stamps every one of them from the NPC's live exports; `npc sight <r>` writes the two sight_range knobs.
const PERCEPTION_COPIED_ONCE: Array[StringName] = [
	&"sight_range", &"fov_degrees", &"crouch_sight_mult", &"time_to_detect", &"forget_time", &"pursuit_grace_time",
	&"eye_height", &"hearing",
]

static var _quest_index: Dictionary = {}   ## Quest.id (String) -> .tres path

static var _quest_scanned: bool = false

## RenderingServer.set_debug_generate_wireframes(true) is a one-shot process-wide arm; WIREFRAME renders NOTHING
## until it has been called. Nothing else in the project calls it, so we own the latch.
@warning_ignore("unused_private_class_variable")  # armed by the View family (Common._wireframes_armed); per-class lint can't see it
static var _wireframes_armed: bool = false


# =============================================================================================================
# AI — the per-NPC verbs (brain / npc <verb> / notarget)
# =============================================================================================================

## Which NPC a `brain` / `npc <verb>` acts on, and where "the point" is. Returned as a small Dictionary so the two
## commands share ONE resolution and can never disagree:
##   &"npc"    Node or null   — the acted-on NPC (crosshair NPC first, else the sticky one from the last command)
##   &"aimed"  Node or null   — whatever the inspector resolved this tick (may be a wall, the player, or the NPC)
##   &"sticky" bool           — the NPC came from STATE_NPC_STICKY, not the crosshair
##   &"error"  String         — non-empty = nothing to act on; the caller returns it verbatim
##
## Reads the inspector's PHYSICS-TICK CACHE through its target() accessor — never a fresh raycast: a
## direct_space_state query outside a physics frame silently returns EMPTY (the spacestate-needs-a-physics-frame
## trap `tpaim` documents in debug_actions_player.gd), and run() is called from an input callback. Both accessors
## are ADDITIVE and land beside this change, so they are probed with has_method and their absence is one honest
## line rather than a crash.
static func _resolve_aimed_npc(ctx: Dictionary) -> Dictionary:
	var out := {&"npc": null, &"aimed": null, &"sticky": false, &"error": ""}
	var insp := _inspector(ctx)
	if insp == null:
		out[&"error"] = "no DebugInspector available (%s missing, or the name is taken under the current scene)" % INSPECTOR_SCRIPT_PATH
		return out
	if not insp.has_method(&"target"):
		out[&"error"] = "DebugInspector has no target() accessor — the look-at inspector predates the per-NPC commands (add target()/hit_point() to debug_inspector.gd)"
		return out
	# The two "cold cache" walls describe_target() reports, mirrored — but tracking-OFF is checked FIRST and
	# regardless of _has_ticked: an inspector that ticked once and was then switched off (`inspect off` on an authored
	# node with always_track unticked) still HOLDS its last resolved target, and `who` will happily describe that
	# stale node — acceptable for a readout, not for `npc kill`, which would act on whatever you aimed at minutes
	# ago. A node that IS tracking but has not run a physics tick yet (this command just created it) is the other
	# wall: ask again next frame.
	if _bool_of(insp.get(&"_gated_off")):
		out[&"error"] = "the DebugInspector is inert (release-build gate, force_in_release unticked) — target()/hit_point() always read null/INF here"
		return out
	if not insp.is_physics_processing():
		out[&"error"] = "look-at tracking is OFF (the inspector is disabled and always_track is unticked) — `inspect on` first"
		return out
	var ticked: Variant = insp.get(&"_has_ticked")
	if ticked is bool and not bool(ticked):
		out[&"error"] = "the look-at inspector arms on the next physics frame (the aim ray is only valid inside one) — run it again"
		return out
	var raw: Variant = insp.call(&"target")
	var aimed: Node = null
	if raw != null and is_instance_valid(raw):
		aimed = raw as Node
	out[&"aimed"] = aimed
	var state := _state(ctx)
	if aimed != null and aimed.is_inside_tree() and aimed.is_in_group(GroupsScript.NPC):
		out[&"npc"] = aimed
		state[STATE_NPC_STICKY] = aimed
		return out
	# Not aiming at an NPC: fall back to the last one an `npc`/`brain` command touched, if it still stands.
	var held: Variant = state.get(STATE_NPC_STICKY)
	if held != null and is_instance_valid(held):
		var prev := held as Node
		if prev != null and prev.is_inside_tree() and prev.is_in_group(GroupsScript.NPC):
			out[&"npc"] = prev
			out[&"sticky"] = true
			return out
	state.erase(STATE_NPC_STICKY)
	if aimed != null and aimed.is_in_group(GroupsScript.PLAYER) and not aimed.is_in_group(GroupsScript.NPC):
		out[&"error"] = "that is you — aim at an NPC (a recruited companion counts; it is in both groups)"
	elif aimed != null:
		out[&"error"] = "\"%s\" is not an NPC (not in the \"%s\" group) and no earlier `npc` target is standing — aim at one first" % [String(aimed.name), String(GroupsScript.NPC)]
	else:
		out[&"error"] = "nothing under the crosshair and no earlier `npc` target is standing — aim at an NPC first"
	return out

## "Name (identity_key)  hp x/y" for a command header. identity_key() is the stable NpcData.id-or-display-name.
static func _npc_label(npc: Node) -> String:
	var label := String(npc.name)
	if npc.has_method(&"identity_key"):
		var key := String(npc.call(&"identity_key"))
		if key != "" and key != label:
			label += " (%s)" % key
	if npc.has_method(&"is_alive"):
		label += "  hp %.0f/%.0f" % [_float_of(npc.get(&"hp")), _float_of(npc.get(&"max_hp"))]
	return label

## "{a=true, b=false}" for a facts / preconditions / effects Dictionary, keys sorted so two dumps line up.
static func _facts_text(d: Dictionary) -> String:
	if d.is_empty():
		return "{}"
	var keys := PackedStringArray()
	for k in d.keys():
		keys.append(String(k))
	keys.sort()
	var bits := PackedStringArray()
	for k in keys:
		# String and StringName are the SAME Dictionary key in Godot 4, so the String we sorted by finds the
		# StringName-keyed fact.
		var v: Variant = d.get(k)
		bits.append("%s=%s" % [k, ("%.2f" % float(v)) if v is float else str(v)])
	return "{" + ", ".join(bits) + "}"

## bool of a Variant that may be null (Object.get() on a missing property) — never `bool(null)`.
static func _bool_of(value: Variant) -> bool:
	return value is bool and bool(value)


# =============================================================================================================
# ctx helpers
# =============================================================================================================

## ⭐EVERY ctx object goes through is_instance_valid() BEFORE the `as` cast. ctx is built by the host and can be
## re-used across commands, so a handle in it can outlive its node: `reload` / `load` free the whole scene, `warp`
## frees the level subtree, `killall` queue_free()s bodies. A cast (like `is`) evaluates the object's type and
## errors on a FREED instance — the project rule is validity FIRST, always. A stale handle degrades to null here,
## which every call site already guards.
static func _tree(ctx: Dictionary) -> SceneTree:
	var raw: Variant = ctx.get(&"tree")
	if not is_instance_valid(raw):
		return null
	return raw as SceneTree

## The human player, or null. ALWAYS null-guarded at every call site: the console can be open on the main menu,
## before the player spawns, or over a corpse.
static func _player(ctx: Dictionary) -> Node:
	var raw: Variant = ctx.get(&"player")
	if not is_instance_valid(raw):
		return null
	return raw as Node

static func _player3d(ctx: Dictionary) -> Node3D:
	var raw: Variant = ctx.get(&"player")
	if not is_instance_valid(raw):
		return null
	return raw as Node3D

## The host-owned Dictionary that PERSISTS across commands. Returns a throwaway when the host forgot to supply
## one, so a toggle degrades to "stateless" instead of crashing.
static func _state(ctx: Dictionary) -> Dictionary:
	var raw: Variant = ctx.get(&"state")
	if raw is Dictionary:
		var s: Dictionary = raw
		return s
	return {}

static func _one(line: String) -> PackedStringArray:
	return PackedStringArray([line])


# =============================================================================================================
# tree lookups
# =============================================================================================================

static func _game_root(tree: SceneTree) -> Node:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GroupsScript.GAME_ROOT)

## The live level subtree ("Level"). GameRoot works in TWO layouts — script on the scene root, or a drop-in child
## with Player/Level as siblings (which is what scenes/game.tscn uses, so the level lands at Game/Level, NOT
## GameRoot/Level). Groups.level_node is the ONE walk (the console, ticker and round-trip harness share it).
static func _level_node(tree: SceneTree) -> Node:
	return GroupsScript.level_node(tree)

## Ps1Warp.cover() silently skips a level root that is not a LevelRoot, so `warp` checks for the script by path
## rather than by type (no compile-time dependency, and it works for a root whose script simply is not set).
static func _has_level_root_script(level: Node) -> bool:
	var scr := level.get_script() as Script
	return scr != null and String(scr.resource_path).get_file() == "level_root.gd"

## Find-or-create a debug node by name under `parent`. Refuses to shadow an unrelated node that happens to own the
## name. add_child is called directly (not deferred) because a console command must be able to report the resulting
## state in the same line — commands run from input/button callbacks, never from inside a child iteration.
## `script` is typed GDScript, not Script: only GDScript exposes new(), and Script alone would not compile.
## Depth-first search for the first node under `root` carrying exactly `script` (an authored drop-in whose name
## the designer may have changed). Matched by script identity, never `is <class>`, so a not-yet-cached class_name
## cannot cascade — and is_instance_valid first, since a level mid-free can still be a child for a frame.
static func _find_by_script(root: Node, script: GDScript) -> Node:
	if root == null or script == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		if node.get_script() == script:
			return node
		for child in node.get_children():
			stack.push_back(child)
	return null

static func _find_or_create(parent: Node, node_name: StringName, script: GDScript) -> Node:
	if parent == null or script == null:
		return null
	var existing := parent.get_node_or_null(NodePath(String(node_name)))
	if existing != null:
		if existing.get_script() == script:
			return existing
		return null  # the name is taken by something unrelated — refuse rather than shadow or clobber it
	var made := script.new() as Node
	if made == null:
		return null
	made.name = node_name
	parent.add_child(made)
	return made

static var _inspector_script: GDScript = null  ## the loaded DebugInspector GDScript (see INSPECTOR_SCRIPT_PATH)

## The shared DebugInspector, created on demand under the current scene. It is a Node3D that raycasts from the
## player's aim, so it belongs in the 3D world, not on the console's CanvasLayer. `who` and `inspect` both go
## through here so there is exactly one raycast implementation and the two can never disagree.
static func _inspector(ctx: Dictionary) -> Node:
	var tree := _tree(ctx)
	if tree == null or tree.current_scene == null:
		return null
	if _inspector_script == null:
		if not ResourceLoader.exists(INSPECTOR_SCRIPT_PATH):
			return null
		_inspector_script = load(INSPECTOR_SCRIPT_PATH) as GDScript
	if _inspector_script == null:
		return null
	return _find_or_create(tree.current_scene, &"DebugInspector", _inspector_script)


# =============================================================================================================
# content scans (disk, cached in statics — sources() runs on every Tab press)
# =============================================================================================================

## Quests keyed by Quest.id, NOT the filename — recover_the_package.tres declares id "recover_package", and every
## QuestTracker call keys on the id.
static func _quests() -> Dictionary:
	if _quest_scanned:
		return _quest_index
	_quest_scanned = true
	_quest_index = _scan(QUEST_DIR, "quest.gd", "objectives", "id")
	return _quest_index

## Scan one resource folder into { key -> res:// path }.
##
## load() + a type test, never a regex over the .tres TEXT: Godot converts text resources to binary on export, so
## a shipped build's text scan returns garbage (this is the scripts/items/item_ids.gd pattern, including the
## ".remap" suffix a packed build appends). The type test prefers the SCRIPT path — exact, and it still identifies
## a resource whose discriminating field happens to be null — and falls back to a duck-typed probe property.
##
## `key_field` blank = key by file stem; otherwise key by that field's value (Quest.id).
static func _scan(dir_path: String, script_file: String, probe: String, key_field: String) -> Dictionary:
	var out := {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var path := dir_path.path_join(f)
		var res := load(path)
		if res == null:
			continue
		var scr := res.get_script() as Script
		var by_script := scr != null and String(scr.resource_path).get_file() == script_file
		# Object.get() returns null for a property that does not exist, so a probe whose default is never null
		# (an Array, an int enum) discriminates without loading the class.
		if not by_script and res.get(probe) == null:
			continue
		var key := f.get_basename()
		if key_field != "":
			var raw: Variant = res.get(key_field)
			if raw == null:
				continue
			key = String(raw)
			if key == "":
				continue
		out[key] = path
	return out

## Case-insensitive lookup so `warp TestLevel` and `warp testlevel` both land.
static func _lookup(index: Dictionary, wanted: String) -> String:
	if index.has(wanted):
		return String(index[wanted])
	var lower := wanted.to_lower()
	for k in index.keys():
		if String(k).to_lower() == lower:
			return String(index[k])
	return ""

static func _sorted_keys(index: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for k in index.keys():
		out.append(String(k))
	out.sort()
	return out


# =============================================================================================================
# formatting
# =============================================================================================================

static func _quest_state(qid: StringName) -> String:
	if QuestTracker.is_quest_active(qid):
		return "ACTIVE"
	if QuestTracker.is_quest_completed(qid):
		return "DONE"
	if QuestTracker.is_quest_failed(qid):
		return "FAILED"
	return "-"

## The objectives the console lists and addresses for `quest`: the CURRENT stage's while it is ACTIVE
## (QuestTracker.current_objectives -- the same ids advance_objective will match), else what a start would put in play:
## a staged quest's FIRST stage (Quest.objectives_for_stage), a stage-less quest's own `objectives`. Duck-typed, so a
## malformed resource with no stage helpers still degrades to its `objectives` field (or null).
static func _live_objectives(quest: Resource, qid: StringName) -> Variant:
	if qid != &"" and QuestTracker.is_quest_active(qid):
		return QuestTracker.current_objectives(qid)
	if quest != null and quest.has_method(&"objectives_for_stage") and quest.has_method(&"first_stage_id"):
		return quest.call(&"objectives_for_stage", quest.call(&"first_stage_id"))
	return quest.get("objectives") if quest != null else null

## `quest show`: the resource's flow fields plus, for an ACTIVE quest, live per-objective progress (a staged quest: the
## stage it is in, and only that stage's objectives).
static func _quest_report(quest: Resource, qid: StringName, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("%s  \"%s\"   [%s]" % [qid, String(quest.get("title")), _quest_state(qid)])
	out.append("  file %s   auto_complete %s" % [path.get_file(), str(bool(quest.get("auto_complete")))])
	var prereq := StringName(String(quest.get("prereq_quest_id")))
	if prereq != &"":
		out.append("  prereq %s (%s)" % [prereq, _quest_state(prereq)])
	var expire := StringName(String(quest.get("expire_on_flag")))
	if expire != &"":
		out.append("  expires when flag \"%s\" is set" % expire)
	if quest.get("next_quest") != null:
		out.append("  chains into a next_quest on completion")
	out.append("  " + _reward_text(quest))
	var stage_ids_v: Variant = quest.call(&"stage_ids") if quest.has_method(&"stage_ids") else []
	if stage_ids_v is Array and not (stage_ids_v as Array).is_empty():
		var names := PackedStringArray()
		for sid in stage_ids_v:
			names.append(String(sid))
		var at := String(QuestTracker.current_stage_id(qid)) if QuestTracker.is_quest_active(qid) else "(not active)"
		out.append("  stages %s   current: %s" % [" > ".join(names), at])
	var objectives_v: Variant = _live_objectives(quest, qid)
	var active := QuestTracker.is_quest_active(qid)
	if objectives_v is Array:
		var objectives: Array = objectives_v
		for o in objectives:
			var obj := o as Resource
			if obj == null:
				continue
			var oid := StringName(String(obj.get("id")))
			var line := "  - %-18s type %d target \"%s\"" % [oid, int(obj.get("type")), String(obj.get("target_id"))]
			if bool(obj.get("optional")):
				line += " (optional)"
			if active:
				# objective_progress returns 0 for a NON-active quest (a COMPLETED one included), and
				# is_objective_done returns true for EVERY objective of a completed quest — so both are only
				# meaningful while the quest is active.
				line += "   %d/%d%s" % [
					QuestTracker.objective_progress(qid, oid), int(obj.get("required_count")),
					"  DONE" if QuestTracker.is_objective_done(qid, oid) else ""]
			out.append(line)
	if not active:
		out.append("  (per-objective progress only reads true while the quest is ACTIVE)")
	return out

## One line of reward summary, read duck-typed so a malformed/partial resource degrades instead of erroring.
static func _reward_text(quest: Resource) -> String:
	return "rewards: money %.0f, xp %.0f, %d item stack(s), rep on %d faction(s)" % [
		float(quest.get("reward_money")), float(quest.get("reward_xp")),
		_count_of(quest.get("rewards")), _count_of(quest.get("reward_reputation"))]

## size() of an Array or Dictionary held in a Variant; 0 for anything else (including a missing property).
static func _count_of(value: Variant) -> int:
	if value is Array:
		var a: Array = value
		return a.size()
	if value is Dictionary:
		var d: Dictionary = value
		return d.size()
	return 0

## int() of a Variant that may be null or junk. Object.get() answers null for a property that does not exist and
## `int(null)` is an invalid-constructor error, not a graceful 0 — so every duck-typed numeric read of an ADDITIVE
## autoload member (save_count, error_count, a ring-buffer line) comes through here and degrades to `fallback`.
static func _int_of(value: Variant, fallback: int = 0) -> int:
	if value is int or value is float or value is bool:
		return int(value)
	return fallback

## float() of a Variant that may be null or junk — the same guard as _int_of for the per-NPC readouts (hp, ranges,
## a Perception state read as a number).
static func _float_of(value: Variant, fallback: float = 0.0) -> float:
	if value is float or value is int or value is bool:
		return float(value)
	return fallback

static func _vec3_text(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]
