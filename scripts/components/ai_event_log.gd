class_name AiEventLog
extends CanvasLayer

## Drop-in AI TRANSITION LOG (debug builds only): a timestamped ring buffer of every NPC state FLIP — perception
## state, target acquire/lose, GOAP goal/action change, provoke, flee, cutscene freeze, stranded count, alive, plus
## spawn/free — and the two AI edges that DO have signals (Perception.just_spotted / just_alerted) and Character.died.
## It answers "in what ORDER did this happen", the question the live labels (F4 inspector, NavDebugOverlay GOAP
## labels) cannot: those show NOW, this shows the timeline. Dump it from the console with `ailog [count] [filter]`
## (debug_actions_world.gd reads the STATIC lines() below — no node handle needed) or watch the optional last-N-lines
## panel (bottom-left) while playing.
##
## WHY POLL-DIFF, NOT SIGNALS. GoapExecutor is a RefCounted with no signals; target binding (npc.gd _set_target),
## provoke(), stand_down() and break_and_flee() emit nothing; only Perception's two edges + Character.died exist.
## So the tick polls `get_tree().get_nodes_in_group(Groups.NPC)` every `poll_every_ticks` physics ticks, keyed by
## instance_id, and diffs a per-NPC SNAPSHOT (a plain Dictionary of channel -> String) against the last one. The
## comparison is the pure static diff_snapshot() so the tick is a thin loop and the logic is unit-tested.
## ⭐ It deliberately does NOT hook the SceneTree's global node-added signal for spawn detection:
## tests/test_global_node_added_listeners.gd pins EXACTLY two such listeners (star_sky + menu_style). A new
## instance_id in the group IS the spawn; an id that vanished is the free/pool.
##
## ⭐ THE RING IS STATIC. A death reload / quickload (`reload_current_scene`) frees this drop-in with the scene, and
## that is precisely the moment you want the history — so `_ring` (and its cap) live in `static var`s and survive
## the node. lines()/clear()/record() are statics for the same reason: the console can read the log with no live
## instance at all. The cap is applied from the `max_lines` export (setter + _ready) onto the static.
##
## ⭐ CACHED-HANDLE RULES (nav_debug_overlay / debug_inspector idiom). Every NPC handle is read duck-typed through
## get()/call()/has_method(); is_instance_valid() runs FIRST on every cached handle (queue_free is deferred a frame,
## and `is` / property reads CRASH on a freed instance); nothing here reads a transform, so the is_inside_tree gate
## only decides the "pooled" vs "freed" wording (NpcPool.reclaim parks a still-valid body OUT of the tree without
## freeing it). Every parameter that receives a possibly-freed handle is UNTYPED on purpose (the F-C46 trap: a typed
## `node: Node` param makes the VM reject a previously-freed handle BEFORE the body's is_instance_valid can run).
##
## SIGNAL EDGES. On first sight of an NPC the log connects Perception.just_spotted / just_alerted (NO args) and
## Character.died (NO args) with `.bind(signal_name, npc)` — .bind APPENDS, so the callback receives exactly the
## two bound values. Connections die with the emitter (a freed NPC takes them along); a POOLED body keeps its
## Perception, so re-adoption checks the live connection list before connecting again (never a duplicate-connection
## error on pool reuse).
##
## THE PANEL never eats clicks and never pumps the layer: every Control is MOUSE_FILTER_IGNORE (read-only overlay
## convention, cf. debug_overlay.gd), and the Label sits inside a clip_contents Control whose height is pinned to
## `panel_lines` x the RENDERED line height (the make_hint_footer idiom, menu_style.gd) — a bare Label reports its
## wrapped height as its minimum and would grow the panel off-screen as lines arrive. Two details keep the NEWEST
## line on screen (the whole point of a tail): the Label's `line_spacing` is pinned (Label draws N lines as
## sum(line_h) + (N-1) x line_spacing, and get_line_height() does NOT fold the spacing — with the default theme's
## 3 px, 8 lines overshoot an 8-line box by 21 px and Label then DROPS the trailing lines it cannot fit, i.e. the
## newest ones), and the Label is anchored to the clip's BOTTOM edge growing UPWARD, so even a mis-measured metric
## pushes OLD lines off the top rather than new ones off the bottom. Layer 140: the 129..199 band is free (128 =
## F3 + Options, 149/150 = debug menu/console, 200 = MenuStyle's tooltip).
##
## DEV-ONLY TEXT: everything painted here is developer copy — this file is in ScanText.SKIP_FILES, so raw literals
## are legal HERE and nowhere else. It reads gameplay; it never writes it.

## Groups / Perception are plain class scripts, NOT autoloads — preloaded by PATH so this file never depends on the
## editor's global-class cache being warm (the new-classname-not-registered cascade). Group NAMES must come from the
## Groups consts: tests/test_groups.gd fails any raw group literal under res://scripts.
const GroupsScript := preload("res://scripts/world/groups.gd")
const PerceptionScript := preload("res://scripts/npc/perception.gd")

## The CanvasLayer slot. See the class doc for the band; not a designer knob (two overlays on one layer tie-break
## by tree order, which is exactly the double-booking the band exists to avoid).
const LAYER := 140
## Ring cap default — shared by the export and the static so a never-authored scene and a bare static read agree.
const DEFAULT_MAX_LINES := 400
## Drawing details, not tuning: the text drop shadow (1 px, whole pixels — the 792x444 canvas is nearest-upscaled
## ~2.4x, so a fractional metric rasterizes into a ragged comb), the pre-measurement line-height estimate used
## only when the font is not resolvable yet (the same fallback make_hint_footer uses), the text inset from the
## backing's edges, and the PINNED inter-line spacing (an explicit theme override so the line pitch is exactly
## get_line_height() + this — see the class doc on why the default theme's 3 px would hide the newest lines).
const SHADOW_OFFSET_PX := 1
const LINE_HEIGHT_FALLBACK_PAD := 4
const PANEL_TEXT_PAD_PX := 4
const PANEL_LINE_SPACING_PX := 0

## Channel words — the `<channel>` token in every line, the snapshot keys, and the filter words a dev types
## (`ailog 50 target`). Kept as consts so the tick, the mute mask and the tests cannot drift on a spelling.
const CH_PERCEPTION := "perception"
const CH_TARGET := "target"
const CH_GOAL := "goal"
const CH_ACTION := "action"
const CH_PROVOKED := "provoked"
const CH_FLEE := "flee"
const CH_CUTSCENE := "cutscene"
const CH_STRANDED := "stranded"
const CH_ALIVE := "alive"
const CH_SPAWN := "spawn"
const CH_SIGNAL := "signal"

## Channel -> mute-mask bit. Mirrors the `channels` @export_flags below (same words, same bits). An unknown channel
## word maps to 0 and is treated as ALWAYS ON by _channel_on(), so a new channel can never be silently muted.
const CHANNEL_BITS := {
	CH_PERCEPTION: 1, CH_TARGET: 2, CH_GOAL: 4, CH_ACTION: 8, CH_PROVOKED: 16, CH_FLEE: 32,
	CH_CUTSCENE: 64, CH_STRANDED: 128, CH_ALIVE: 256, CH_SPAWN: 512, CH_SIGNAL: 1024,
}
## Every bit above — the default mask (nothing muted). Spelled as the OR so a new channel is added in ONE place.
const ALL_CHANNELS := 1 | 2 | 4 | 8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024
## The snapshot's channel order — also the order diff lines land in when several fields flip on one tick.
const SNAPSHOT_CHANNELS: Array[String] = [
	CH_PERCEPTION, CH_TARGET, CH_GOAL, CH_ACTION, CH_PROVOKED, CH_FLEE, CH_CUTSCENE, CH_STRANDED, CH_ALIVE,
]

## Escape hatch for the debug-build gate. Ticking this in an exported build is a deliberate act (a QA build); a
## normal release must carry no debug surface, so the default keeps the node inert.
@export var force_in_release: bool = false
## Ring capacity. Applied onto the STATIC ring (setter + _ready) so a scene-authored value governs the shared buffer.
@export_range(16, 5000) var max_lines: int = DEFAULT_MAX_LINES: set = set_max_lines
## Poll cadence in PHYSICS ticks (1 = every tick). A LOD-throttled NPC only changes state on its own think tick, so
## a per-tick diff misses nothing; raise this only to shave the O(n) duck-typed reads on a huge cast.
@export_range(1, 60) var poll_every_ticks: int = 1
## Mute mask. Untick a channel to stop RECORDING it (the ring is finite — target churn from a proximity-only
## acquire would otherwise evict the lines you came for). Words match CHANNEL_BITS / the `<channel>` token.
@export_flags("perception:1", "target:2", "goal:4", "action:8", "provoked:16", "flee:32", "cutscene:64", "stranded:128", "alive:256", "spawn/free:512", "signal:1024")
var channels: int = ALL_CHANNELS
## Log a `spawn` line for every NPC already present on the FIRST sweep (a level's whole authored cast). Off =
## adopt them silently and log only later spawns/frees — the quiet choice for a big level.
@export var log_initial_cast: bool = true

@export_group("Panel")
## Show the bottom-left last-N-lines column. Setter-backed so a scene-authored value, the console's `ailog on|off`
## and set_panel_visible() all land in the same place; the panel itself is built in _ready.
@export var show_panel: bool = false: set = set_panel_visible
@export_range(1, 40) var panel_lines: int = 8
@export_range(6, 40) var font_size: int = 12
@export_range(80, 1600) var panel_width: int = 440
@export_range(0, 64) var panel_margin: int = 8
@export var panel_color: Color = Color(0.85, 0.95, 1.0, 0.95)
@export var panel_shadow_color: Color = Color(0.0, 0.0, 0.0, 0.85)
@export var panel_backing: Color = Color(0.0, 0.0, 0.0, 0.35)

# --- the shared history (STATIC: survives the node — see the class doc) ----------------------------------------
static var _ring: PackedStringArray = PackedStringArray()
static var _cap: int = DEFAULT_MAX_LINES
## Bumped by every record()/clear() so an instance knows the panel is stale without comparing the (capped) size.
static var _generation: int = 0

# --- per-instance tracking ------------------------------------------------------------------------------------
## instance_id -> {"node": <untyped handle>, "label": String, "arch": String, "snap": Dictionary}. The label and
## archetype are latched at adoption because a freed node has no readable name when it vanishes.
var _tracked: Dictionary = {}
var _tick_counter: int = 0
var _swept_once: bool = false
var _seen_generation: int = -1
## Latched when the debug-build gate refuses: the node stays permanently inert, whatever anyone calls.
var _gated_off: bool = false
var _clip: Control = null
var _label: Label = null


# This script is intentionally NOT @tool, so none of its code runs in the editor.
func _ready() -> void:
	# DEBUG-BUILD GATE: an exported release must carry no debug surface. Go inert rather than free() ourselves, so a
	# scene that authored this node still loads with the node in place.
	if not OS.is_debug_build() and not force_in_release:
		_gated_off = true
		set_physics_process(false)
		return
	layer = LAYER
	# DialogueManager owns the only gameplay pause in this project, and a paused tree stops _physics_process on an
	# INHERIT node — the log must keep ticking (and the panel keep painting) through a stuck conversation.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# An @export's declaration default never runs its setter, so a never-authored max_lines must still reach the
	# static cap here.
	_cap = maxi(1, max_lines)
	_trim_ring()
	_build_panel()
	_refresh_panel()
	set_physics_process(true)


func _exit_tree() -> void:
	# The ring is static and stays; only the per-instance handle map goes. Signal connections die with their
	# emitters (or with us — the engine drops a connection whose target object is destroyed). A re-entry (the node
	# reparented) starts over as a FIRST sweep, so `log_initial_cast` governs the re-adopted cast again.
	_tracked.clear()
	_swept_once = false


# --- public API (DebugConsole / DebugActionsWorld call these; KEEP THE NAMES) ------------------------------------

## The log, newest LAST. `count` 0 = every line; otherwise the last `count` lines. `filter` is a case-insensitive
## substring match applied BEFORE the count, so `lines(20, "target")` is the last 20 target lines, not the target
## lines among the last 20. Static: readable with no live instance (the console after a reload).
static func lines(count: int = 0, filter: String = "") -> PackedStringArray:
	var needle := filter.strip_edges().to_lower()
	var out := PackedStringArray()
	if needle == "":
		out = _ring.duplicate()
	else:
		for line in _ring:
			if line.to_lower().contains(needle):
				out.append(line)
	if count > 0 and out.size() > count:
		out = out.slice(out.size() - count)
	return out


## Drop the whole history (every instance sees it, since the ring is shared).
static func clear() -> void:
	_ring = PackedStringArray()
	_generation += 1


## THE one writer. Appends a finished line and applies the static cap. Public so a test can seed the ring and so a
## sibling debug surface can drop a marker line into the same timeline; the tick and the signal callbacks go
## through here too.
static func record(line: String) -> void:
	_ring = push_capped(_ring, line, _cap)
	_generation += 1


## Show/hide the last-N panel. Also the property setter for `show_panel`, so a designer ticking the box, the
## console and this call all agree. Guarded on the panel existing: a scene-authored export is assigned BEFORE
## _ready builds it (and an off-tree `.new()` never builds it) — _ready catches up from `show_panel`.
func set_panel_visible(on: bool) -> void:
	show_panel = on
	if _clip != null:
		_clip.visible = on and not _gated_off
		if _clip.visible:
			_refresh_panel()


func is_panel_visible() -> bool:
	return show_panel and not _gated_off


## Setter for `max_lines`: floors at 1 and applies the new cap onto the STATIC ring immediately (a smaller cap
## trims the oldest lines right away, so the export always describes the buffer you are looking at).
func set_max_lines(v: int) -> void:
	max_lines = maxi(1, v)
	_cap = max_lines
	_trim_ring()


# --- the tick ---------------------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	_tick_counter += 1
	if _tick_counter < maxi(1, poll_every_ticks):
		return
	_tick_counter = 0
	_sweep()
	if _clip != null and _clip.visible and _seen_generation != _generation:
		_refresh_panel()


## One poll: adopt new ids, diff known ones, retire vanished ones. Group membership is the discovery mechanism
## (see the class doc for why not the global node-added signal); get_nodes_in_group only returns IN-TREE nodes,
## and a pooled body that left the tree simply stops appearing — which is the "pooled" retirement below.
func _sweep() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var now := _now()
	var log_spawns := _channel_on(CH_SPAWN) and (_swept_once or log_initial_cast)
	var seen := {}
	for n in tree.get_nodes_in_group(GroupsScript.NPC):
		# The group can hold a freed body for a frame (queue_free is deferred). Validity FIRST, then anything else.
		if not is_instance_valid(n):
			continue
		var id: int = n.get_instance_id()
		seen[id] = true
		if not _tracked.has(id):
			_adopt(n, id, now, log_spawns)
			continue
		var rec: Dictionary = _tracked[id]
		# Perception edges not wired yet (no _perception on the first sight — a body built lazily or a non-NPC
		# group member): retry each tick, one get() + validity check, until it lands or the body goes.
		if not bool(rec.get("wired", true)):
			rec["wired"] = _connect_perception_edges(n)
		var cur := _snapshot_of(n)
		var prev: Dictionary = rec["snap"]
		var label := String(rec["label"])
		for d in diff_snapshot(prev, cur):
			var channel := String(d["channel"])
			if _channel_on(channel):
				record(format_line(now, label, channel, String(d["old"]), String(d["new"])))
		rec["snap"] = cur
	# Retire ids that were not in the group this sweep. keys() is a copy, so erasing while walking it is safe.
	for id in _tracked.keys():
		if seen.has(id):
			continue
		var rec: Dictionary = _tracked[id]
		_tracked.erase(id)
		if _channel_on(CH_SPAWN):
			record(format_line(now, String(rec["label"]), CH_SPAWN, String(rec["arch"]), gone_word(rec["node"])))
	_swept_once = true


## First sight of an NPC: latch its label + archetype, take the baseline snapshot, log the spawn, wire the edges.
## `npc` is validity-checked by the caller; untyped per the F-C46 rule all the same. "wired" records whether the
## Perception edges landed (NPC._ready builds _perception synchronously right after joining the group, so this is
## normally true on the first sight); the sweep retries a false one each tick.
func _adopt(npc, id: int, now: float, log_spawn: bool) -> void:
	var label := String(npc.name)
	var arch := archetype_of(npc)
	_connect_once(npc, &"died", npc)
	var wired := _connect_perception_edges(npc)
	_tracked[id] = {"node": npc, "label": label, "arch": arch, "snap": _snapshot_of(npc), "wired": wired}
	if log_spawn:
		record(format_line(now, label, CH_SPAWN, "-", arch))


## Connect the two Perception edges (just_spotted / just_alerted) once per emitter. Returns false while the NPC has
## no live `_perception` to connect to (the caller retries); true once both connects were attempted.
func _connect_perception_edges(npc) -> bool:
	var perception: Variant = npc.get(&"_perception")
	if not is_instance_valid(perception):
		return false
	_connect_once(perception, &"just_spotted", npc)
	_connect_once(perception, &"just_alerted", npc)
	return true


## Connect `_on_npc_signal(sig_name, npc)` to `emitter.sig` unless THIS instance already is. The existing-connection
## check walks the emitter's connection list comparing target object + method — deliberately NOT is_connected() with
## a freshly-bound Callable, because Callable equality across .bind() is not something a pool-reuse path should bet
## on (a false negative here is a duplicate-connection engine error on every reuse). Both params untyped (F-C46).
func _connect_once(emitter, sig: StringName, npc) -> void:
	if not is_instance_valid(emitter) or not emitter.has_signal(sig):
		return
	for c in emitter.get_signal_connection_list(sig):
		var existing: Callable = c.get("callable", Callable())
		if existing.get_object() == self and existing.get_method() == &"_on_npc_signal":
			return
	# .bind APPENDS after the signal's own args; these three signals carry none, so the callback sees exactly
	# (sig_name, npc). A typed-signal edge added later must widen the callback to take its args first.
	emitter.connect(sig, _on_npc_signal.bind(String(sig), npc))


## A signal edge fired on `npc`. Untyped param: the bound handle can be freed by the time a queued emit lands.
func _on_npc_signal(sig_name: String, npc) -> void:
	if not _channel_on(CH_SIGNAL):
		return
	var label := "?"
	if is_instance_valid(npc):
		label = String(npc.name)
	record(format_event(_now(), label, sig_name))


# --- reads (impure, duck-typed; every handle validity-checked before a member read) ------------------------------

## The per-NPC state vector as channel -> String, in SNAPSHOT_CHANNELS order. Every field degrades to "-" (or a
## sane default) when the member is absent on this particular actor — companions, story NPCs and half-built
## bodies all sit in the same group. PRIVATE fields (_perception, _target, _executor, _provoked, _cutscene_control,
## _stranded_cycles) have no public accessor; nav_debug_overlay / debug_inspector read the same ones the same way.
func _snapshot_of(npc) -> Dictionary:
	var snap := {}
	var perception_name := "-"
	var perception: Variant = npc.get(&"_perception")
	if is_instance_valid(perception):
		perception_name = state_name(_int_of(perception.get(&"state"), -1))
	snap[CH_PERCEPTION] = perception_name

	# Having a _target is NOT "engaged" (NpcTargeting acquires by proximity with sight_range 500) — the perception
	# line beside it says whether the target is actually seen. Logged anyway: acquire/lose ORDER is the point.
	var target_name := "-"
	var held: Variant = npc.get(&"_target")
	if is_instance_valid(held) and held is Node:
		target_name = String((held as Node).name)
	snap[CH_TARGET] = target_name

	# GoapExecutor is a RefCounted; both current_goal and current_action() can legitimately be null (no feasible
	# goal / plan exhausted) — copy nav_debug_overlay's null handling, never assume either exists.
	var goal := "-"
	var action := "-"
	var executor: Variant = npc.get(&"_executor")
	if is_instance_valid(executor):
		var current_goal: Variant = executor.get(&"current_goal")
		if is_instance_valid(current_goal):
			goal = _text_of(current_goal.get(&"name"), "-")
		if executor.has_method(&"current_action"):
			var current_action: Variant = executor.call(&"current_action")
			if is_instance_valid(current_action):
				action = _text_of(current_action.get(&"name"), "-")
	snap[CH_GOAL] = goal
	snap[CH_ACTION] = action

	snap[CH_PROVOKED] = yes_no(_flag_of(npc.get(&"_provoked")))
	snap[CH_FLEE] = yes_no(npc.has_method(&"is_fleeing") and bool(npc.call(&"is_fleeing")))
	snap[CH_CUTSCENE] = yes_no(_flag_of(npc.get(&"_cutscene_control")))
	snap[CH_STRANDED] = str(_int_of(npc.get(&"_stranded_cycles"), 0))
	# A body without is_alive() (not a Character) is reported alive rather than flapping between "?" values.
	snap[CH_ALIVE] = yes_no(not npc.has_method(&"is_alive") or bool(npc.call(&"is_alive")))
	return snap


## The NPC's archetype for the spawn line: the authored NpcData.id (the stable identity, rename-proof), else the
## profile's display_name, else the NPC's own authored display_name, else "-". Static + untyped param so a test can
## hand it a stub.
static func archetype_of(npc) -> String:
	if not is_instance_valid(npc):
		return "-"
	var profile: Variant = npc.get(&"profile")
	if is_instance_valid(profile):
		var id := _text_of(profile.get(&"id"), "")
		if id != "":
			return id
		var profile_name := _text_of(profile.get(&"display_name"), "")
		if profile_name != "":
			return profile_name
	var own := _text_of(npc.get(&"display_name"), "").strip_edges()
	return own if own != "" else "-"


## Why an id left the group: "freed" (the handle is dead), "pooled" (still valid but parked OUT of the tree —
## NpcPool.reclaim never frees), else "left group". Untyped param: the whole point is that it may be freed.
static func gone_word(node) -> String:
	if not is_instance_valid(node):
		return "freed"
	if not node.is_inside_tree():
		return "pooled"
	return "left group"


## Session clock for the T+ stamp: seconds since process launch (wall time, keeps counting under a pause). Chosen
## over a per-node timer because the ring outlives the node — stamps must stay monotonic across a reload.
static func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _channel_on(channel: String) -> bool:
	var bit := int(CHANNEL_BITS.get(channel, 0))
	return bit == 0 or (channels & bit) != 0


# --- panel ------------------------------------------------------------------------------------------------------

func _build_panel() -> void:
	_clip = Control.new()
	_clip.name = "Panel"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a debug overlay must never eat clicks (project convention)
	add_child(_clip)
	var backing := ColorRect.new()
	backing.color = panel_backing
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(backing)
	backing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No wrapping: a long line runs off the right edge and is clipped, instead of adding rows that would push
	# the newest line out of the pinned height.
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Newest line at the bottom; a short history hugs the bottom edge and leaves the slack ABOVE.
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	# A CanvasLayer under a non-Control gets NO theme, so every look is an explicit override.
	_label.add_theme_font_size_override(&"font_size", font_size)
	_label.add_theme_color_override(&"font_color", panel_color)
	_label.add_theme_color_override(&"font_shadow_color", panel_shadow_color)
	_label.add_theme_constant_override(&"shadow_offset_x", SHADOW_OFFSET_PX)
	_label.add_theme_constant_override(&"shadow_offset_y", SHADOW_OFFSET_PX)
	# PIN the inter-line spacing: Label lays N lines out as sum(line_h) + (N-1) x line_spacing, and get_line_height()
	# reports line_h WITHOUT the spacing, so a box sized N x get_line_height() under the default theme's 3 px spacing
	# is (N-1) x 3 px short — and a Label that cannot fit its text drops the TRAILING lines (the newest) rather than
	# clipping the top. With the spacing pinned here the layout below is exact.
	_label.add_theme_constant_override(&"line_spacing", PANEL_LINE_SPACING_PX)
	_clip.add_child(_label)
	_layout_panel()
	_clip.visible = show_panel and not _gated_off


## Pin the clip host to the bottom-left with a height that is a WHOLE-PIXEL multiple of the rendered line height
## (measured off the live Label after its overrides — line pitch is get_line_height() + the pinned spacing), plus the
## text inset top and bottom. The Label is anchored to the clip's BOTTOM edge with grow_vertical = BEGIN: if its
## minimum height ever beats the pinned box (a taller fallback glyph, a metric off by a pixel), the Control grows
## UPWARD past the clip's top edge — old lines vanish, the newest stays glued to the bottom — instead of the default
## END growth pushing the tail below the clip. Anchored, so a window resize keeps it in the corner without a re-layout.
func _layout_panel() -> void:
	var line_h: float = _label.get_line_height()
	if line_h <= 0.0:
		line_h = float(font_size + LINE_HEIGHT_FALLBACK_PAD)  # font not resolvable yet — the pre-measurement estimate
	var line_px := int(ceil(line_h))
	var rows := maxi(1, panel_lines)
	var text_height := rows * line_px + (rows - 1) * PANEL_LINE_SPACING_PX
	var height := text_height + 2 * PANEL_TEXT_PAD_PX
	_clip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_clip.offset_left = float(panel_margin)
	_clip.offset_right = float(panel_margin + panel_width)
	_clip.offset_bottom = -float(panel_margin)
	_clip.offset_top = -float(panel_margin + height)
	_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_left = float(PANEL_TEXT_PAD_PX)
	_label.offset_right = -float(PANEL_TEXT_PAD_PX)
	_label.offset_bottom = -float(PANEL_TEXT_PAD_PX)
	_label.offset_top = -float(PANEL_TEXT_PAD_PX + text_height)


func _refresh_panel() -> void:
	if _label == null:
		return
	var shown := lines(panel_lines)
	_label.text = "\n".join(shown)
	_seen_generation = _generation


static func _trim_ring() -> void:
	if _ring.size() > _cap:
		_ring = _ring.slice(_ring.size() - _cap)


# --- pure helpers (unit-tested; no tree, no autoloads) ----------------------------------------------------------

## One transition line: "T+123.4s  <npc name>  <channel>: <old> -> <new>". Two-space gutters so `ailog` output
## columns up in the console's monospace scrollback.
static func format_line(t: float, npc_name: String, channel: String, old_v: String, new_v: String) -> String:
	return "T+%.1fs  %s  %s: %s -> %s" % [t, npc_name, channel, old_v, new_v]


## One signal-edge line: "T+123.4s  <npc name>  signal: just_spotted". Same stamp + gutter as format_line so the
## two interleave cleanly; the arrow is dropped because an edge has no before/after value.
static func format_event(t: float, npc_name: String, event: String) -> String:
	return "T+%.1fs  %s  %s: %s" % [t, npc_name, CH_SIGNAL, event]


## Append `line` and keep only the last `cap` (floored at 1). Returns the array to keep — a trim yields a FRESH
## slice, so callers always reassign the return (the DebugOverlay.push_capped shape); never rely on the append alone.
static func push_capped(ring: PackedStringArray, line: String, cap: int) -> PackedStringArray:
	ring.append(line)
	var n := maxi(1, cap)
	if ring.size() > n:
		ring = ring.slice(ring.size() - n)
	return ring


## The per-NPC comparison as pure data: one {channel, old, new} per key of `cur` whose value differs from `prev`,
## in `cur`'s key order. A key `prev` lacks reports old = "" (a field that became readable). Keys only `prev` has
## are ignored — a field that vanished is not a transition anyone reads. String-compares, so callers snapshot
## Strings.
static func diff_snapshot(prev: Dictionary, cur: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in cur.keys():
		var new_v := String(cur[key])
		var old_v := String(prev[key]) if prev.has(key) else ""
		if old_v != new_v:
			out.append({"channel": String(key), "old": old_v, "new": new_v})
	return out


## Perception.State -> its enum word. if/elif rather than match: the enum comes through the preloaded script const
## (PerceptionScript.State.X is a subscript the analyzer need not fold as a match pattern — a comparison always
## works). "?" for anything else, including the -1 an NPC with no Perception reports.
static func state_name(state: int) -> String:
	if state == PerceptionScript.State.UNAWARE:
		return "UNAWARE"
	if state == PerceptionScript.State.DETECTING:
		return "DETECTING"
	if state == PerceptionScript.State.ALERTED:
		return "ALERTED"
	if state == PerceptionScript.State.INVESTIGATING:
		return "INVESTIGATING"
	return "?"


static func yes_no(v: bool) -> String:
	return "yes" if v else "no"


## Duck-typed value coercions that degrade instead of erroring: Object.get() returns null for a member that does
## not exist on this particular actor, and int(null) / bool(null) / String(null) would misreport or throw.
static func _int_of(v: Variant, fallback: int) -> int:
	if v is int or v is float:
		return int(v)
	return fallback


static func _text_of(v: Variant, fallback: String) -> String:
	if v is String or v is StringName:
		return String(v)
	return fallback


static func _flag_of(v: Variant) -> bool:
	if v is bool:
		return bool(v)
	return false
