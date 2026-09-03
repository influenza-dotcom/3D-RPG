class_name DebugEventTicker
extends CanvasLayer

## Drop-in GAME-EVENT TICKER (debug builds only): a read-only column that appends ONE timestamped line per
## cross-system game event — quest started/advanced/completed/failed, reputation delta + alignment flip, day/night
## phase, rent notice/paid/missed, dialogue open/close/suspend/resume, money / xp / level-up / mechanic, status
## effect added/removed, player death + the world-reset cue, level swap / reload, every save write — into a STATIC
## ring buffer, and paints the newest few for `line_seconds` each before they fade out. The console's `events
## [count] [filter]` dumps the ring; `events on|off` toggles the column and `events clear` empties the ring
## (debug_actions_world.gd _ring_command, via set_column_visible / is_column_visible / lines / clear below — the
## registry row's slot 1 is Kind.TEXT so a control word validates there; a number is read as the count).
##
## WHY A TICKER: these are exactly the cross-system PRODUCTS no single surface shows in ORDER — the rent ambush
## (notice -> charge landing while the wallet is empty), the provoke trap (faction rep dropping once PER MEMBER in
## one frame), SEEK-vs-WALK (`time` fires NO phase_changed while `advance` fires several in one frame), "money
## moved but no save followed". Every line here is a signal that already exists; this node only listens. What has
## NO signal is deliberately NOT here: set_flag / record_object_state / an EncounterSpawner wave (those are the
## `flags` / `ledger` console reads, not timeline entries) — do not fake them from a poll.
##
## THE RING IS STATIC ON PURPOSE. A death reload / F9 quickload / `reload` calls reload_current_scene, which FREES
## this drop-in with the scene — the moment you most want the last ten seconds of history. `static var` history
## survives the free; the next instance's _ready re-applies `max_lines` as the cap. It is session-only, never saved.
##
## DISCOVERY IS POLLED, NEVER node_added: tests/test_global_node_added_listeners.gd pins exactly two node_added
## listeners project-wide. Every level-scoped source (the human Player, its lazily-created StatusEffectManager, the
## level's RentCollector) is re-resolved on a slow poll (`poll_interval`) and reconnected with is_connected guards;
## the autoload sources (QuestTracker / Reputation / WorldClock / GameState / DialogueManager) are connected once in
## _ready and die with this node. Cached handles are validity-checked FIRST on every read (pooled bodies leave the
## tree without freeing; queue_free is deferred; `is` crashes on a freed instance).
##
## LAYOUT: the column lives in the free 129..199 layer band (128 = F3 + Options, 149/150 = menu/console, 200 =
## MenuStyle's cursor tip which must stay on top). Default corner is TOP-RIGHT under the minimap / clock / quest
## tracker stack (ui.gd builds those at x 484..784, y 8..~180 on the 792x444 canvas — the tracker word-wraps DOWN,
## so `margin.y` is the knob if a long objective ever collides). The rows are `visible_lines` FIXED-HEIGHT Labels
## placed by hand inside a clip_contents Control sized to N x the RENDERED line height, so a growing log can never
## pump the layer off-screen (a bare Label reports its wrapped height as its minimum — the make_hint_footer trap).
## Every Control is MOUSE_FILTER_IGNORE: a read-only overlay must never eat clicks. No MenuStyle, no theme reaches a
## CanvasLayer under a non-Control, so every look is an explicit override. WHOLE-PIXEL metrics only (the ~2.4x
## nearest upscale combs any fraction).
##
## This file paints raw developer strings and is listed in ScanText.SKIP_FILES for exactly that reason — nothing it
## paints can ever be player copy. Keep it that way: never route a line through PlayerText or notify_toast.

## Existing classes preloaded BY PATH (never by class_name) so a stale global-class cache can't take this file down
## with it — the debug_overlay.gd:11 / debug_actions_world.gd:42-50 idiom. Group NAMES must come from the Groups
## consts (tests/test_groups.gd fails any raw group literal under res://scripts).
const GroupsScript := preload("res://scripts/world/groups.gd")
const DispositionScript := preload("res://scripts/npc/disposition.gd")
## For clock_text (0..1 fraction -> HH:MM) on the phase line — reuse over a second copy of the same three lines.
const DebugOverlayScript := preload("res://scripts/components/debug_overlay.gd")

## The script basename the level's rent node must carry. Matched by SCRIPT PATH (never `is RentCollector`, no
## compile-time class dependency) because RentCollector is in no group and has no registry — the shipping instance
## is a plain child somewhere under the level subtree, and a designer may have renamed the node.
const RENT_SCRIPT_FILE := "rent_collector.gd"

## The CanvasLayer slot. 129..199 is the free band (128 = F3 + Options double-booked; 140 = AiEventLog's panel;
## 149/150 = debug menu/console, which may open OVER this column; 200 = MenuStyle's cursor tip). Not a designer
## knob: two overlays on one layer tie-break by tree order, which is exactly the double-booking the band avoids.
const LAYER := 141
## The static ring's cap before any instance's _ready applies `max_lines` — kept EQUAL to that export's default so
## a bare static read (the console dumping before a ticker was ever mounted) and a never-authored scene agree.
const DEFAULT_MAX_LINES := 300

## Named ScreenCorner, NOT Corner: `Corner` is a GLOBAL engine enum (CORNER_TOP_LEFT ...), and a class enum of the
## same name makes `ScreenCorner.TOP_RIGHT` resolve to the engine's — a parse error on the typed export below.
enum ScreenCorner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

## Escape hatch for the debug-build gate. Ticking it in an exported build is a deliberate act (a QA build); a
## normal release must carry no debug surface, so the default keeps the node fully inert (no UI, no connections).
@export var force_in_release: bool = false
## Column shown from the first frame. Off by default (the on-screen text is opt-in); `events on`
## (set_column_visible) shows it, `events off` hides it again. The ring keeps recording either way.
@export var start_visible: bool = false

@export_group("History")
## Ring capacity, applied to the STATIC ring in _ready (see the header). Older lines fall off the head.
@export_range(10, 5000) var max_lines: int = DEFAULT_MAX_LINES
## Seconds between re-resolving the level-scoped sources (player / status manager / rent / level path). A slow
## poll: rent fires at dawn and a level swap takes a frame, so half a second of latency costs nothing.
@export_range(0.1, 5.0, 0.05) var poll_interval: float = 0.5

@export_group("Column")
## Rows painted on screen. The ring keeps `max_lines`; this is only how many of the newest are shown.
@export_range(1, 24) var visible_lines: int = 6
## A line older than this is hidden from the column (it stays in the ring). 0 = never hide.
@export_range(0.0, 60.0, 0.5) var line_seconds: float = 6.0
## The tail of `line_seconds` over which a row's alpha ramps to 0 (a soft fade instead of a pop). 0 = hard cut.
@export_range(0.0, 10.0, 0.1) var fade_seconds: float = 1.5
@export var corner: ScreenCorner = ScreenCorner.TOP_RIGHT
## Inset from the anchored corner, whole pixels. y 216 clears the top-right minimap (8..116) + clock (119..141) +
## a two-line quest tracker (146..~180) with slack; x 8 lines the column up with that stack's right edge.
@export var margin: Vector2i = Vector2i(8, 216)
## Fixed column width, whole pixels. 300 = HudSettings.quest_tracker_width, so the left edge sits at x 484 too.
@export_range(80, 792) var column_width: int = 300
## Left-aligned by default so the "T+…" stamps form a straight column to read down; right-align for a right
## corner if you prefer the quest tracker's ragged-left look.
@export var text_align_right: bool = false
@export_range(6, 40) var font_size: int = 12
@export var text_color: Color = Color(0.86, 0.90, 0.94, 1.0)
## Black outline for legibility over any scene — the same trick every HUD label uses (no panel behind the rows).
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export_range(0, 8) var outline_size: int = 2

@export_group("Channels")
## Mute a noisy channel here; muted events are NOT recorded (the ring is the log, not a filter). Money and xp
## fire on every pickup / kill and can drown a quest line — turn them off when hunting anything else.
@export var log_quests: bool = true
@export var log_reputation: bool = true
@export var log_clock: bool = true
@export var log_rent: bool = true
@export var log_dialogue: bool = true
@export var log_money: bool = true
@export var log_xp: bool = true
@export var log_level_ups: bool = true
@export var log_mechanics: bool = true
@export var log_effects: bool = true
@export var log_bank: bool = true
@export var log_saves: bool = true
## Player death, the world-reset cue, level swaps / reloads, and the player (re)bind line.
@export var log_lifecycle: bool = true

# --- the STATIC ring (survives a scene reload; see the header) -----------------------------------------------
static var _ring := PackedStringArray()      ## formatted lines, oldest first
static var _stamps := PackedFloat32Array()   ## Time.get_ticks_msec()/1000 per line, parallel to _ring
static var _cap: int = DEFAULT_MAX_LINES      ## applied from `max_lines` in _ready; set_ring_cap for tests

# --- per-instance state ---------------------------------------------------------------------------------------
var _enabled: bool = false            ## false in a release build (or off-tree): every public entry point no-ops
var _column_visible: bool = true
var _root: Control = null
var _rows: Array[Label] = []
var _row_height: int = 0
var _poll_t: float = 0.0
## The cached human Player. UNTYPED on purpose (the F-C46 idiom): a `Node`-typed var/param makes the VM
## type-check a previously-freed handle BEFORE is_instance_valid can run and errors. Read only through _usable().
var _player = null
## Instance ids of the sources currently bound. Ids are what the poll DIFFS (a new id = a rebuilt node = reconnect;
## Godot never reuses an instance id within a session), and — for the status manager and the rent node — the ONLY
## thing kept: their connections die with them, so holding the handle would only add a stale pointer to guard.
var _player_id: int = 0
var _status_id: int = 0
var _rent_id: int = 0
var _level_id: int = 0
var _last_level_path: String = ""
var _last_account: float = 0.0


func _ready() -> void:
	layer = LAYER  # see the const: under the console/menu (149/150), above the F3 HUD (128), beside AiEventLog (140)
	# DialogueManager owns the only gameplay pause, and a paused tree stops _process — but the dialogue lines and
	# the fade clock are exactly what this ticker must keep painting through a conversation.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build() and not force_in_release:
		visible = false
		set_process(false)
		return
	_enabled = true
	set_ring_cap(max_lines)
	_column_visible = start_visible
	_build_ui()
	_connect_autoloads()
	if GameState != null:
		_last_account = float(GameState.account)
	_poll_t = 0.0  # resolve the player / level on the very first frame rather than half a second in


## Build the fixed-size column: a clip_contents Control anchored to `corner`, holding `visible_lines` hand-placed
## single-line Labels. No container anywhere, so nothing can feed a minimum size back up and grow the column.
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "EventColumn"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a read-only overlay must never eat clicks (project convention)
	_root.clip_contents = true
	# A dev timeline must never become a translation msgid lookup (harmless, but every row would miss the catalog).
	_root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_root)
	_rows.clear()
	for i in visible_lines:
		var row := Label.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_font_size_override(&"font_size", font_size)
		row.add_theme_color_override(&"font_color", text_color)
		row.add_theme_color_override(&"font_outline_color", outline_color)
		row.add_theme_constant_override(&"outline_size", outline_size)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if text_align_right else HORIZONTAL_ALIGNMENT_LEFT
		row.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		# Single line, ever: no autowrap, and clip + ellipsis mean a long line can never widen or heighten the row
		# (a Label with clip_text reports a 1 px minimum width, so the fixed column width is the only width).
		row.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_root.add_child(row)
		_rows.append(row)
	# Row height = the RENDERED line height (folds the theme's line spacing), whole pixels, so the clip lands
	# BETWEEN rows. Measured off a real row after its overrides; falls back to the pre-measurement estimate the
	# make_hint_footer idiom uses when the font is not resolvable yet.
	var lh := 0.0
	if not _rows.is_empty():
		lh = _rows[0].get_line_height()
	if lh <= 0.0:
		lh = float(font_size + 4)
	_row_height = int(ceilf(lh))
	for i in _rows.size():
		var row := _rows[i]
		row.position = Vector2(0, i * _row_height)
		row.size = Vector2(column_width, _row_height)
	_layout()
	_root.visible = _column_visible


## Anchor the column to its corner with whole-pixel offsets (the pure corner_offsets/corner_anchor do the math).
func _layout() -> void:
	if _root == null:
		return
	var col_size := Vector2i(column_width, _row_height * maxi(1, _rows.size()))
	var a := corner_anchor(corner)
	var r := corner_offsets(corner, margin, col_size)
	_root.anchor_left = a.x
	_root.anchor_right = a.x
	_root.anchor_top = a.y
	_root.anchor_bottom = a.y
	_root.offset_left = float(r.position.x)
	_root.offset_top = float(r.position.y)
	_root.offset_right = float(r.position.x + r.size.x)
	_root.offset_bottom = float(r.position.y + r.size.y)


func _process(delta: float) -> void:
	if not _enabled:
		return
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = poll_interval
		_poll()
	if _root != null and _root.visible:
		_paint()


## Repaint the rows from the ring: the newest `visible_lines` lines younger than `line_seconds`, oldest at the top
## for a top corner (rows fill downward) and newest at the bottom for a bottom corner (rows fill upward), each
## row's alpha ramping out over the last `fade_seconds`. Ages are wall-clock so lines keep fading under the
## dialogue pause and under a `timescale` override alike.
func _paint() -> void:
	var now := _now()
	var idx := visible_indices(_stamps, now, line_seconds, visible_lines)
	var k := idx.size()
	var n := _rows.size()
	var top_aligned := corner == ScreenCorner.TOP_LEFT or corner == ScreenCorner.TOP_RIGHT
	var start := 0 if top_aligned else n - k
	for i in n:
		var row := _rows[i]
		var j := i - start
		if j < 0 or j >= k:
			row.text = ""
			continue
		var ri := idx[j]
		if ri < 0 or ri >= _ring.size():
			row.text = ""
			continue
		row.text = _ring[ri]
		row.modulate = Color(1.0, 1.0, 1.0, line_alpha(now - _stamps[ri], line_seconds, fade_seconds))


# =============================================================================================================
# PUBLIC API (the console's `events` command drives these — keep the signatures)
# =============================================================================================================

## The ring, oldest first / newest last, optionally case-insensitively filtered by substring over the whole line
## (so `events 20 quest` and `events 0 rent` both work), then windowed to the last `count` (0 = all).
static func lines(count: int = 0, filter: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	var needle := filter.strip_edges().to_lower()
	for l in _ring:
		if needle.is_empty() or String(l).to_lower().contains(needle):
			out.append(l)
	if count > 0 and out.size() > count:
		out = out.slice(out.size() - count)
	return out


## Wipe the ring (both parallel arrays together — they must never drift apart).
static func clear() -> void:
	_ring = PackedStringArray()
	_stamps = PackedFloat32Array()


## Show / hide the on-screen column. The ring keeps recording while hidden — hiding is a display choice, not a mute.
func set_column_visible(on: bool) -> void:
	_column_visible = on
	if _root != null:
		_root.visible = on


## True only when a column actually exists and is showing: false in a release build and off-tree, so a console
## `events on` in a shipped build reports honestly instead of claiming a column that was never built.
func is_column_visible() -> bool:
	return _enabled and _column_visible and _root != null and _root.visible


## Append one line to the STATIC ring at wall-clock `t` (seconds since launch — see _now()). Public and static so a
## sibling debug drop-in can mirror a line into this timeline without holding an instance; the instance listeners
## below all funnel through it. `channel` is a short lowercase key (`quest`, `rep`, …) the filter can key on.
static func record(t: float, channel: String, text: String) -> void:
	_ring = push_capped(_ring, format_line(t, channel, text), _cap)
	_stamps = push_capped_stamps(_stamps, t, _cap)


## Set the ring capacity (applied on the next push; an over-full ring is trimmed then). Clamped to >= 1.
static func set_ring_cap(cap: int) -> void:
	_cap = maxi(1, cap)


static func ring_cap() -> int:
	return _cap


# =============================================================================================================
# PURE HELPERS (unit-tested: tests/test_debug_event_ticker.gd)
# =============================================================================================================

## One ring line: "T+12.3s  quest: started recover_package". Short and identifier-keyed — the filter and a human
## both scan the `channel:` column. Pure.
static func format_line(t: float, channel: String, text: String) -> String:
	return "T+%.1fs  %s: %s" % [t, channel, text]


## Append `line` and keep only the last `cap` (a rolling window). Returns the new array — callers REASSIGN, which is
## correct under either Packed*Array passing semantics (slice() always yields a fresh array). Pure.
static func push_capped(ring: PackedStringArray, line: String, cap: int) -> PackedStringArray:
	ring.append(line)
	var n := maxi(1, cap)
	if ring.size() > n:
		ring = ring.slice(ring.size() - n)
	return ring


## The stamps twin of push_capped — the two arrays are pushed together with the same cap so they stay parallel. Pure.
static func push_capped_stamps(stamps: PackedFloat32Array, t: float, cap: int) -> PackedFloat32Array:
	stamps.append(t)
	var n := maxi(1, cap)
	if stamps.size() > n:
		stamps = stamps.slice(stamps.size() - n)
	return stamps


## Indices (into `stamps`, OLDEST FIRST) of the newest `count` entries whose age `now - stamp` is at most `max_age`
## (`max_age` <= 0 = no age limit). Scans from the tail; stops once `count` are found. Does not assume the stamps
## are monotonic (a caller-supplied `t` may be out of order), so an old entry never hides a younger one. Pure.
static func visible_indices(stamps: PackedFloat32Array, now: float, max_age: float, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if count <= 0:
		return out
	var i := stamps.size() - 1
	while i >= 0 and out.size() < count:
		if max_age <= 0.0 or now - stamps[i] <= max_age:
			out.append(i)
		i -= 1
	out.reverse()
	return out


## The fade/window logic as pure data: the lines the column would show right now (oldest first). `ring` and
## `stamps` are aligned from the TAIL when their sizes disagree (they only ever grow together, so a mismatch can
## only be a stale head) — the extra head entries are ignored rather than mis-paired. Pure.
static func visible_slice(ring: PackedStringArray, stamps: PackedFloat32Array, now: float, max_age: float, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	var n := mini(ring.size(), stamps.size())
	if n <= 0:
		return out
	var ring_off := ring.size() - n
	var st_off := stamps.size() - n
	var window := stamps if st_off == 0 else stamps.slice(st_off)
	for idx in visible_indices(window, now, max_age, count):
		out.append(ring[ring_off + idx])
	return out


## Row alpha for a line `age` seconds old: 1 while younger than `max_age - fade`, ramping linearly to 0 at
## `max_age`; `max_age` <= 0 never fades; `fade` <= 0 is a hard cut at `max_age`. A `fade` longer than `max_age`
## is clamped to it, so a fresh line is ALWAYS fully opaque (the ramp can start no earlier than birth). Pure.
static func line_alpha(age: float, max_age: float, fade: float) -> float:
	if max_age <= 0.0:
		return 1.0
	if age >= max_age:
		return 0.0
	if fade <= 0.0:
		return 1.0
	var ramp := minf(fade, max_age)
	return clampf((max_age - age) / ramp, 0.0, 1.0)


## The (x, y) anchor a corner pins to: 0 = left/top edge, 1 = right/bottom edge. Pure.
static func corner_anchor(which: int) -> Vector2:
	var right := which == ScreenCorner.TOP_RIGHT or which == ScreenCorner.BOTTOM_RIGHT
	var bottom := which == ScreenCorner.BOTTOM_LEFT or which == ScreenCorner.BOTTOM_RIGHT
	return Vector2(1.0 if right else 0.0, 1.0 if bottom else 0.0)


## Anchor-relative offsets for a `col_size` box inset `margin` from `which` corner: position = (offset_left,
## offset_top), size = col_size (offset_right/bottom = position + size). Whole pixels in, whole pixels out. Pure.
static func corner_offsets(which: int, margin_px: Vector2i, col_size: Vector2i) -> Rect2i:
	var right := which == ScreenCorner.TOP_RIGHT or which == ScreenCorner.BOTTOM_RIGHT
	var bottom := which == ScreenCorner.BOTTOM_LEFT or which == ScreenCorner.BOTTOM_RIGHT
	var left := (-margin_px.x - col_size.x) if right else margin_px.x
	var top := (-margin_px.y - col_size.y) if bottom else margin_px.y
	return Rect2i(Vector2i(left, top), col_size)


## Validity + in-tree gate for a cached handle. UNTYPED param on purpose (the F-C46 idiom, debug_inspector.gd
## _usable): a `node: Node` signature makes the VM type-check the argument BEFORE the body runs, and a previously-
## freed handle FAILS that check with an error — so the is_instance_valid() guard inside would never get to answer.
static func _usable(node) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree()


# =============================================================================================================
# SOURCES — autoloads (connected once; the connections die with this node)
# =============================================================================================================

func _connect_autoloads() -> void:
	# Every autoload is null-guarded so this drop-in also boots in a bare harness without the full set. Listeners
	# take the TYPED ARITY of each signal — a listener that drops an emitted arg errors at emit time.
	if QuestTracker != null:
		_connect_if(QuestTracker, &"quest_started", _on_quest_started)
		_connect_if(QuestTracker, &"objective_advanced", _on_objective_advanced)
		_connect_if(QuestTracker, &"quest_completed", _on_quest_completed)
		_connect_if(QuestTracker, &"quest_failed", _on_quest_failed)
	if Reputation != null:
		_connect_if(Reputation, &"reputation_changed", _on_reputation_changed)
		_connect_if(Reputation, &"alignment_changed", _on_alignment_changed)
	if WorldClock != null:
		_connect_if(WorldClock, &"phase_changed", _on_phase_changed)
	if GameState != null:
		_connect_if(GameState, &"player_died", _on_world_player_died)
		_connect_if(GameState, &"account_changed", _on_account_changed)
		# GameState.saved is documented as a passive observation seam: a listener must NEVER save from it. We only
		# append a line to a static array here.
		_connect_if(GameState, &"saved", _on_saved)
	if DialogueManager != null:
		_connect_if(DialogueManager, &"dialogue_started", _on_dialogue_started)
		_connect_if(DialogueManager, &"dialogue_finished", _on_dialogue_finished)
		_connect_if(DialogueManager, &"dialogue_suspended", _on_dialogue_suspended)
		_connect_if(DialogueManager, &"dialogue_resumed", _on_dialogue_resumed)


## Connect `cb` to `obj.sig` exactly once. Duck-typed on has_signal so an older build of a source (a Player without
## mechanic_toggled, say) degrades to "that channel stays silent" instead of a connect error. `obj` is untyped for
## the same F-C46 reason as _usable — a stale handle must reach is_instance_valid, not a type check.
static func _connect_if(obj, sig: StringName, cb: Callable) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	if not obj.has_signal(sig):
		return
	if obj.is_connected(sig, cb):
		return
	obj.connect(sig, cb)


# --- QuestTracker ---

func _on_quest_started(quest) -> void:
	if log_quests:
		_log("quest", "started %s" % _id_of(quest))


func _on_objective_advanced(quest, objective) -> void:
	if not log_quests:
		return
	var qid := _id_of(quest)
	var oid := _id_of(objective)
	var text := "%s/%s" % [qid, oid]
	# Progress is stamped BEFORE the emit (QuestTracker.advance_objective), so the live count is readable here.
	if QuestTracker != null and QuestTracker.has_method(&"objective_progress") and quest != null and objective != null:
		var have := int(QuestTracker.call(&"objective_progress", quest.get(&"id"), objective.get(&"id")))
		var need_raw = objective.get(&"required_count")
		var need := int(need_raw) if need_raw != null else 0
		text += " %d/%d" % [have, need]
	_log("quest", text)


func _on_quest_completed(quest) -> void:
	if log_quests:
		_log("quest", "COMPLETED %s" % _id_of(quest))


func _on_quest_failed(quest) -> void:
	if log_quests:
		_log("quest", "FAILED %s" % _id_of(quest))


# --- Reputation ---

func _on_reputation_changed(faction, delta: float, new_total: float) -> void:
	if log_reputation:
		_log("rep", "%s %+.1f -> %.1f" % [_id_of(faction), delta, new_total])


func _on_alignment_changed(faction, new_kind: int) -> void:
	if log_reputation:
		_log("rep", "%s now %s" % [_id_of(faction), _kind_text(new_kind)])


# --- WorldClock ---

func _on_phase_changed(new_phase: int) -> void:
	if not log_clock:
		return
	var at := ""
	if WorldClock != null:
		at = " at %s" % DebugOverlayScript.clock_text(float(WorldClock.time_of_day))
	_log("clock", "%s%s" % [_phase_text(new_phase), at])


# --- GameState ---

## The world-reset cue — fires from the death cinematic once the screen is fully covered, i.e. AFTER Player.died
## (logged separately below). Two lines on purpose: the gap between them is the cinematic's length.
func _on_world_player_died() -> void:
	if log_lifecycle:
		_log("game", "player_died (world-reset cue)")


func _on_account_changed(value: float) -> void:
	if log_bank:
		_log("bank", "%.2f -> %.2f (%+.2f)" % [_last_account, value, value - _last_account])
	_last_account = value


func _on_saved(path: String, err: int) -> void:
	if not log_saves:
		return
	var count_text := ""
	if GameState != null:
		var raw = GameState.get(&"save_count")
		if raw is int:
			count_text = " (#%d)" % int(raw)
	if err == OK:
		_log("save", "%s ok%s" % [path.get_file(), count_text])
	else:
		_log("save", "%s FAILED %s (%d)%s" % [path.get_file(), error_string(err), err, count_text])


# --- DialogueManager ---

func _on_dialogue_started(resource) -> void:
	if log_dialogue:
		_log("dialogue", "start %s" % _id_of(resource))


func _on_dialogue_finished() -> void:
	if log_dialogue:
		_log("dialogue", "end")


func _on_dialogue_suspended(reason: String) -> void:
	if log_dialogue:
		_log("dialogue", "suspended (%s)" % reason)


func _on_dialogue_resumed() -> void:
	if log_dialogue:
		_log("dialogue", "resumed")


# =============================================================================================================
# SOURCES — level-scoped (re-resolved on the slow poll; freed on reload / warp)
# =============================================================================================================

func _poll() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	_poll_level(tree)
	_poll_player(tree)
	_poll_status_manager()


## Two independent facts about the level: the LevelData path (a swap) and the live level NODE (a swap OR a
## same-level reload). Both are polled — GameRoot.load_level emits nothing, and reload_current_scene rebuilds the
## node without touching the path. Any node change re-finds + reconnects the RentCollector (the old one went with
## the freed subtree, taking its connections with it).
func _poll_level(tree: SceneTree) -> void:
	var path_changed := false
	if GameState != null:
		var path := String(GameState.current_level_path)
		if path != _last_level_path:
			_last_level_path = path
			path_changed = true
			if log_lifecycle:
				_log("level", "-> %s" % (path.get_file().get_basename() if not path.is_empty() else "(none)"))
	var level := _find_level_node(tree)
	var level_id := level.get_instance_id() if level != null else 0
	if level_id == _level_id:
		return
	var had_level := _level_id != 0
	_level_id = level_id
	# ONE line per swap: a warp already printed its `-> name` above, so the rebuilt line is reserved for the case
	# the path can't show — the same level's node replaced (a same-level warp / an in-place reload).
	if had_level and level_id != 0 and not path_changed and log_lifecycle:
		_log("level", "node rebuilt (%s)" % level.name)
	_rebind_rent(level)


## Find the level's rent node by SCRIPT FILE (see RENT_SCRIPT_FILE) and connect its three signals. The old level's
## rent node — and its connections — went with the freed subtree, so this is a fresh connect, not a re-check.
func _rebind_rent(level: Node) -> void:
	_rent_id = 0
	if level == null:
		return
	var found := _find_by_script_file(level, RENT_SCRIPT_FILE)
	if found == null:
		return
	_rent_id = found.get_instance_id()
	_connect_if(found, &"notice_served", _on_rent_notice)
	_connect_if(found, &"rent_paid", _on_rent_paid)
	_connect_if(found, &"payment_missed", _on_rent_missed)


## The human Player, by group (Groups.human_player excludes recruited companions, which share the PLAYER group).
## A new instance id = a rebuilt player (death reload / quickload / level swap): reconnect its signals; the old
## body's connections died with it.
func _poll_player(tree: SceneTree) -> void:
	var player = GroupsScript.human_player(tree)
	if not _usable(player):
		_player = null
		_player_id = 0
		_status_id = 0
		return
	var pid: int = player.get_instance_id()
	if pid == _player_id:
		return
	_player = player
	_player_id = pid
	_status_id = 0
	_connect_if(player, &"money_changed", _on_money_changed)
	_connect_if(player, &"xp_changed", _on_xp_changed)
	_connect_if(player, &"leveled_up", _on_leveled_up)
	_connect_if(player, &"mechanic_unlocked", _on_mechanic_unlocked)
	_connect_if(player, &"mechanic_toggled", _on_mechanic_toggled)
	_connect_if(player, &"died", _on_player_died)
	if log_lifecycle:
		_log("player", "bound %s" % player.name)


## The player's StatusEffectManager is a LAZILY-CREATED child (Character.status_manager() is null until the first
## apply_status_effect), so it is polled rather than resolved once at bind time. Read through the accessor, never
## by child name — the accessor is the contract.
func _poll_status_manager() -> void:
	if not _usable(_player) or not _player.has_method(&"status_manager"):
		_status_id = 0
		return
	var mgr = _player.call(&"status_manager")
	if mgr == null or not is_instance_valid(mgr):
		_status_id = 0
		return
	var mid: int = mgr.get_instance_id()
	if mid == _status_id:
		return
	_status_id = mid
	_connect_if(mgr, &"effect_added", _on_effect_added)
	_connect_if(mgr, &"effect_removed", _on_effect_removed)


# --- Player ---

func _on_money_changed(total: float, delta: float) -> void:
	if log_money:
		_log("money", "%+.2f -> %.2f" % [delta, total])


func _on_xp_changed(xp: float, level: int) -> void:
	if log_xp:
		_log("xp", "%.1f (lvl %d)" % [xp, level])


func _on_leveled_up(new_level: int, points_gained: int) -> void:
	if log_level_ups:
		_log("levelup", "%d (+%d pt)" % [new_level, points_gained])


func _on_mechanic_unlocked(id: StringName) -> void:
	if log_mechanics:
		_log("mechanic", "unlocked %s" % String(id))


func _on_mechanic_toggled(id: StringName, active: bool) -> void:
	if log_mechanics:
		_log("mechanic", "%s %s" % [String(id), "on" if active else "off"])


## The moment of death (Character.died from Player.die()) — GameState.player_died follows once the cinematic covers.
func _on_player_died() -> void:
	if log_lifecycle:
		_log("player", "died")


# --- StatusEffectManager ---

func _on_effect_added(effect) -> void:
	if not log_effects:
		return
	var dur := ""
	if effect != null and is_instance_valid(effect):
		var raw = effect.get(&"duration")
		if raw != null:
			var d := float(raw)
			# duration 0 = permanent until removed (StatusEffect contract) — say so instead of printing "0.0s".
			dur = " (permanent)" if d <= 0.0 else " (%.1fs)" % d
	_log("effect", "+ %s%s" % [_id_of(effect), dur])


func _on_effect_removed(effect) -> void:
	if log_effects:
		_log("effect", "- %s" % _id_of(effect))


# --- RentCollector ---

func _on_rent_notice(amount: float) -> void:
	if log_rent:
		_log("rent", "notice %.2f" % amount)


func _on_rent_paid(amount: float) -> void:
	if log_rent:
		_log("rent", "paid %.2f" % amount)


func _on_rent_missed(shortfall: float) -> void:
	if log_rent:
		_log("rent", "MISSED, short %.2f" % shortfall)


# =============================================================================================================
# internals
# =============================================================================================================

func _log(channel: String, text: String) -> void:
	record(_now(), channel, text)


## Wall-clock seconds since launch. Monotonic, unaffected by the tree pause and Engine.time_scale — so the stamps
## stay ordered under a dialogue pause / slow-mo, and a reload does not reset the "T+" column mid-session.
static func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## The live level subtree, mirroring debug_actions_world.gd _level_node: GameRoot's own "Level" child, else its
## SIBLING (scenes/game.tscn parents GameRoot beside Player, so the level lands at Game/Level), else the current
## scene's "Level". Never hardcode one layout.
static func _find_level_node(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var gr := tree.get_first_node_in_group(GroupsScript.GAME_ROOT)
	if gr != null and is_instance_valid(gr):
		var own := gr.get_node_or_null(^"Level")
		if own != null:
			return own
		var parent := gr.get_parent()
		if parent != null:
			var sibling := parent.get_node_or_null(^"Level")
			if sibling != null:
				return sibling
	if tree.current_scene != null:
		return tree.current_scene.get_node_or_null(^"Level")
	return null


## Depth-first search for the first node under `root` whose script FILE is `file` (basename match — the
## _find_by_script idiom keyed by path instead of a preloaded GDScript, so no compile-time class dependency and
## no stale-cache cascade). is_instance_valid first: a level mid-free can still be a child for a frame.
static func _find_by_script_file(root: Node, file: String) -> Node:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if not is_instance_valid(node):
			continue
		var scr := node.get_script() as Script
		if scr != null and String(scr.resource_path).get_file() == file:
			return node
		for child in node.get_children():
			stack.push_back(child)
	return null


## A short stable identifier for a Resource-ish arg: its `id` (Quest / QuestObjective / Faction / StatusEffect),
## else its file stem (a DialogueResource has no id), else its display_name, else "?". Duck-typed reads only —
## a null or freed arg degrades to "?" rather than a crash in a signal callback.
static func _id_of(res) -> String:
	if res == null or not is_instance_valid(res):
		return "?"
	var raw = res.get(&"id")
	if raw != null:
		var s := str(raw)
		if not s.is_empty():
			return s
	if res is Resource:
		var path := String((res as Resource).resource_path)
		if not path.is_empty():
			return path.get_file().get_basename()
	var dn = res.get(&"display_name")
	if dn != null and not str(dn).is_empty():
		return str(dn)
	return "?"


## Disposition.Kind int -> its enum NAME, read off the preloaded script's enum so the text can never drift from
## the enum (no hand-kept table). Unknown -> "kind N".
static func _kind_text(kind: int) -> String:
	var key = DispositionScript.Kind.find_key(kind)
	return str(key) if key != null else "kind %d" % kind


## WorldClock.Phase int -> its enum NAME (DAY / NIGHT), same no-table rule as _kind_text.
static func _phase_text(phase: int) -> String:
	if WorldClock != null:
		var key = WorldClock.Phase.find_key(phase)
		if key != null:
			return str(key)
	return "phase %d" % phase
