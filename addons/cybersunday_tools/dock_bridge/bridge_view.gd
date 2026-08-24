@tool
extends VBoxContainer

## CYBER SUNDAY "Bridge" tab -- the editor-side half of the external tool bridge.
##
## WHAT IT IS FOR: an external process (the MCP server at tools/mcp/cyber_mcp.py, driving an AI agent) can already
## read the project headlessly, but it cannot see the OPEN EDITOR: which scene is being edited, what is selected,
## and -- the big one -- it cannot tell the editor that a file it just wrote on disk has changed. Until the editor
## happens to rescan, its stale in-memory copy silently wins on the next Ctrl+S. This tab opens a tiny localhost
## command server that serves exactly three READ-ONLY tools (godot_fs_sync / godot_editor_state / godot_reveal).
##
## SECURITY POSTURE, and why this tab exists at all instead of the plugin just always listening:
##  - The server is OFF BY DEFAULT. Nothing opens a port unless the user presses Start on this tab.
##  - bridge_server.gd binds 127.0.0.1 EXPLICITLY (the TCPServer default is "*", i.e. every interface -- that would
##    be a network-reachable command channel into a game editor). This tab states the bind address on screen so the
##    posture is verifiable at a glance, not just in a comment.
##  - Every request must carry the random token from the handshake file (res://.godot/cyber_bridge.json), which is
##    written on Start and DELETED on Stop.
## The banner is deliberately loud: a user glancing at this tab must instantly know whether a port is open.
##
## HEIGHT CONTRACT (load-bearing -- read dock_content/content_dock.gd's header for the same rule): the bottom-panel
## TabContainer sizes itself to its TALLEST tab, so a tab that grows freely makes the whole editor unusable on a
## short display. This plugin has shipped that bug twice. Therefore: head (button bar + banner + status) stays a
## few fixed rows OUTSIDE the scroll, and everything that can grow -- the exposure summary and the rolling request
## log -- lives in ONE ScrollContainer with a small height floor and horizontal scrolling disabled.

const BridgeServer := preload("res://addons/cybersunday_tools/dock_bridge/bridge_server.gd")

## Rolling log depth. This is a dev-tool UI budget, not a gameplay number, so a plain const is correct
## (see CLAUDE.md: ports/timeouts/UI caps in a dev tool are not designer-tunable values).
const LOG_CAP := 50
## Height floor for the scrolled body. Small on purpose -- see the HEIGHT CONTRACT note above.
const BODY_MIN_HEIGHT := 110.0
## How much of the token to show. Enough to match against the handshake file / an MCP error message, short enough
## that a screenshot or a screen-share of this panel does not hand out the whole credential.
const TOKEN_PREVIEW_CHARS := 8
## Character budget for a start() failure painted into the status row. bridge_server.gd's bind error is a whole
## paragraph on purpose (it names the likely cause and the fix), and the status row lives OUTSIDE the scroll --
## so an un-budgeted message here inflates the tab's MINIMUM height, which is exactly what the HEIGHT CONTRACT
## above forbids. The untruncated text always survives in the request log and in the row's tooltip.
const STATUS_ERROR_CHARS := 110
## Ceiling on the status row's painted lines. Caps Label.minsize.height at two rows no matter how the panel is
## sized, so the head can never be the thing that makes this tab the tallest one in the bottom panel.
const STATUS_MAX_LINES := 2

const COLOR_ON_BG := Color(0.10, 0.33, 0.16)    ## listening: unmistakable green slab
const COLOR_OFF_BG := Color(0.19, 0.19, 0.21)   ## off: flat neutral, reads as "nothing running"
const COLOR_ERR_BG := Color(0.42, 0.13, 0.13)   ## start refused (busy port, bad bind): loud red, and still OFF
const COLOR_OK_BB := "#8fe388"
const COLOR_FAIL_BB := "#ff6b6b"

## The server object. A RefCounted, NOT a Node -- this tab owns its lifetime and drives poll() from _process.
## Typed by the preloaded script (not by `RefCounted`) ON PURPOSE: it makes start/stop/poll/port/token and the
## request_served signal statically checked here, so any drift from the bridge_server.gd contract is a compile
## error at integration time instead of a silent no-op on a port that is open.
var _server: BridgeServer = null

var _start_btn: Button = null
var _stop_btn: Button = null
var _port_spin: SpinBox = null
var _banner: Label = null
var _banner_box: StyleBoxFlat = null
var _status: Label = null
var _info: RichTextLabel = null
var _log: RichTextLabel = null

## Newest-first rows of already-formatted bbcode, capped at LOG_CAP.
var _log_rows: Array[String] = []
## Last start() failure, kept so the banner can stay red+OFF until the next attempt instead of silently reverting.
var _last_error := ""


func _init() -> void:
	name = "Bridge"
	add_theme_constant_override("separation", 4)

	_server = BridgeServer.new()
	_server.request_served.connect(_on_request_served)

	# --- head: the controls (outside the scroll, so they can never be scrolled away) ---
	var bar := HBoxContainer.new()
	_start_btn = Button.new()
	_start_btn.text = "Start"
	_start_btn.tooltip_text = "Open the localhost command server and write the handshake file. Nothing listens until you press this."
	_start_btn.pressed.connect(_on_start_pressed)
	bar.add_child(_start_btn)

	_stop_btn = Button.new()
	_stop_btn.text = "Stop"
	_stop_btn.tooltip_text = "Close the listener and DELETE the handshake file."
	_stop_btn.pressed.connect(_on_stop_pressed)
	bar.add_child(_stop_btn)

	var port_label := Label.new()
	port_label.text = "Port"
	port_label.modulate = Color(1, 1, 1, 0.7)
	bar.add_child(port_label)

	# A busy port makes start() FAIL LOUDLY on purpose (a silent port+1 fallback would leave the external proxy
	# talking to a dead listener forever), so the user needs a way to pick another one -- that is this SpinBox.
	# Locked while listening: changing it mid-run would only misdescribe the socket that is actually open.
	_port_spin = SpinBox.new()
	_port_spin.min_value = 1024
	_port_spin.max_value = 65535
	_port_spin.step = 1
	# min/max BEFORE value: Range clamps on assignment, so setting the default first would snap it to 0.
	_port_spin.value = BridgeServer.DEFAULT_PORT
	_port_spin.custom_minimum_size = Vector2(96, 0)
	_port_spin.tooltip_text = "Only change this if %d is already taken. The MCP server reads the real port from the handshake file, so it follows automatically." % BridgeServer.DEFAULT_PORT
	bar.add_child(_port_spin)

	var clear_btn := Button.new()
	clear_btn.text = "Clear log"
	clear_btn.pressed.connect(_on_clear_pressed)
	bar.add_child(clear_btn)
	add_child(bar)

	# --- the state banner: the one thing a glance has to answer ---
	var banner_panel := PanelContainer.new()
	_banner_box = StyleBoxFlat.new()
	_banner_box.bg_color = COLOR_OFF_BG
	_banner_box.corner_radius_top_left = 3
	_banner_box.corner_radius_top_right = 3
	_banner_box.corner_radius_bottom_left = 3
	_banner_box.corner_radius_bottom_right = 3
	_banner_box.content_margin_left = 8
	_banner_box.content_margin_right = 8
	_banner_box.content_margin_top = 5
	_banner_box.content_margin_bottom = 5
	banner_panel.add_theme_stylebox_override("panel", _banner_box)
	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 16)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_panel.add_child(_banner)
	add_child(banner_panel)

	# The detail row: handshake path + token fingerprint while listening, the reason while refused, an invitation
	# while idle. It sits OUTSIDE the scroll (a user must not have to scroll to find out a port is open), which
	# means it is head geometry and is therefore HARD-CAPPED at STATUS_MAX_LINES rows -- see the HEIGHT CONTRACT
	# header note. Anything longer is clipped here and stays reachable via tooltip_text and the request log.
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = STATUS_MAX_LINES
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_status)

	# --- body: everything that can GROW lives here, height-bounded (see the HEIGHT CONTRACT header note) ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, BODY_MIN_HEIGHT)
	add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)

	# selection_enabled so the user can copy the handshake path straight out of the panel; bbcode off for the
	# same reason content_dock's result dialog turns it off -- res:// paths must render literally.
	_info = RichTextLabel.new()
	_info.bbcode_enabled = false
	_info.fit_content = true
	_info.selection_enabled = true
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_info)

	body.add_child(HSeparator.new())

	var log_head := Label.new()
	log_head.text = "Served requests (newest first, last %d)" % LOG_CAP
	log_head.modulate = Color(1, 1, 1, 0.6)
	body.add_child(log_head)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true          # grows INSIDE the scroll instead of needing its own height floor
	_log.selection_enabled = true
	_log.scroll_active = false       # the outer ScrollContainer owns scrolling; a nested scroller fights it
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_log)

	set_process(false)  # only poll while a listener is actually open -- re-asserted in _ready(), see below
	_render_log()
	_refresh_state()


# --- lifetime ------------------------------------------------------------------------------------------------

## Re-assert "not processing" AFTER the tab is added to the dock. Godot turns processing back ON by itself at
## NOTIFICATION_READY for any script that overrides _process (node.cpp: `if (GDVIRTUAL_IS_OVERRIDDEN(_process))
## set_process(true)`), so the set_process(false) in _init alone would leave this tab ticking every editor frame
## with no server to poll. The real gate is the server's own state, so read it rather than hardcoding false.
func _ready() -> void:
	set_process(_server != null and _server.is_listening())


## Every editor frame while listening: hand the server a slice to accept + serve connections. poll() is required
## to return promptly (it drops half-written peers on a deadline) so this cannot stall the editor.
func _process(_delta: float) -> void:
	if _server == null or not _server.is_listening():
		# The listener went away without going through _on_stop_pressed (a failed start, or a stop from elsewhere).
		# Stop burning frames and resync the UI once.
		set_process(false)
		_refresh_state()
		return
	_server.poll()


## MANDATORY pairing. The user toggles this plugin off/on in Project Settings after every plugin script edit --
## dozens of times a day -- and Godot also reloads the plugin on its own when a plugin script changes. An
## unpaired listener strands the port (and leaves a handshake file pointing at a dead socket), so the very next
## Start fails with "address already in use" for no reason the user can see.
func _exit_tree() -> void:
	set_process(false)
	if _server != null:
		_server.stop()


## Belt-and-braces for the reload path where the panel is freed without a normal tree exit. stop() is documented
## idempotent, so a double call is a no-op.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _server != null and is_instance_valid(_server):
		_server.stop()


# --- buttons -------------------------------------------------------------------------------------------------

func _on_start_pressed() -> void:
	if _server == null or _server.is_listening():
		return
	# Annotated, NOT wrapped in String(): a cast would silently stringify whatever start() returned, which is exactly
	# the drift the script-typed _server exists to catch (see its declaration). int() around the SpinBox IS needed --
	# Range.value is a float.
	var err: String = _server.start(int(_port_spin.value))
	if err != "":
		# FAIL LOUDLY and stay off -- no silent port+1 retry (see the SpinBox comment).
		_last_error = err
		_append_log("bridge", false, "start refused: " + err)
		_refresh_state()
		return
	_last_error = ""
	set_process(true)
	_append_log("bridge", true, "listening on %s:%d" % [BridgeServer.BIND_ADDRESS, _server.port()])
	_refresh_state()


func _on_stop_pressed() -> void:
	if _server == null:
		return
	var was := _server.is_listening()
	_server.stop()
	set_process(false)
	_last_error = ""
	if was:
		_append_log("bridge", true, "stopped, handshake file deleted")
	_refresh_state()


func _on_clear_pressed() -> void:
	_log_rows.clear()
	_render_log()


# --- server feedback -----------------------------------------------------------------------------------------

## One row per served request, so the user can watch exactly what the external process asked for. This is the
## audit trail for an open port -- it is why the log exists at all, not a debug convenience.
func _on_request_served(tool_name: String, ok: bool, detail: String) -> void:
	_append_log(tool_name, ok, detail)


func _append_log(tool_name: String, ok: bool, detail: String) -> void:
	# Newest FIRST: this log lives inside a ScrollContainer that does not auto-follow its content, so appending at
	# the bottom would push new rows out of sight on a short panel.
	_log_rows.push_front(format_log_row(Time.get_time_string_from_system(), tool_name, ok, detail))
	while _log_rows.size() > LOG_CAP:
		_log_rows.pop_back()
	_render_log()


## Pure row formatter (static so it is trivially checkable without a socket or an editor).
## BOTH peer-supplied fields are bbcode-escaped, not just `detail`. This log is the AUDIT TRAIL for an open port,
## so a client must not be able to smuggle markup into it -- an unescaped "[color=...]OK" in a rejected request's
## name would let a hostile local process paint itself a clean row. `tool_name` is gated to the known TOOLS list
## today, but the escape is what keeps that true if a future rejection path ever echoes the requested name back.
static func format_log_row(time_text: String, tool_name: String, ok: bool, detail: String) -> String:
	var tag := ("[color=%s]OK  [/color]" % COLOR_OK_BB) if ok else ("[color=%s]FAIL[/color]" % COLOR_FAIL_BB)
	var body := "%s  %s  %s" % [time_text, bb_escape(tool_name), bb_escape(detail)]
	return tag + "  " + body


## Escape bbcode's opening bracket so literal text (paths, JSON fragments) renders as typed.
static func bb_escape(s: String) -> String:
	return s.replace("[", "[lb]")


## Trim a message to a character budget. Used only on head-row text, where an arbitrary-length string would grow
## the tab's minimum height (HEIGHT CONTRACT, header). Pure + static so it stays checkable without an editor.
static func clamp_line(s: String, budget: int) -> String:
	if budget <= 0 or s.length() <= budget:
		return s
	return s.substr(0, budget) + "…"


func _render_log() -> void:
	if _log == null:
		return
	if _log_rows.is_empty():
		_log.text = "[i]No requests yet.[/i]"
		return
	_log.text = "\n".join(_log_rows)


# --- state rendering -----------------------------------------------------------------------------------------

## Repaint the banner / status / button enablement from the ONE source of truth (the server's own is_listening()),
## so the UI can never claim a port is open after the listener dropped underneath it.
func _refresh_state() -> void:
	var listening := _server != null and _server.is_listening()
	if _start_btn != null:
		_start_btn.disabled = listening
	if _stop_btn != null:
		_stop_btn.disabled = not listening
	if _port_spin != null:
		_port_spin.editable = not listening

	# Built into locals first so the three widgets are written through ONE guarded block -- a half-painted banner
	# (green slab, stale port) is the one lie this tab must never tell.
	var banner_text := ""
	var banner_bg := COLOR_OFF_BG
	var status_text := ""
	var status_full := ""
	if listening:
		# The bind address is READ from bridge_server.gd, never retyped. This banner is the user's only proof of
		# the security posture, so it has to be derived from the const that actually reaches TCPServer.listen();
		# a hardcoded "127.0.0.1" here would keep claiming localhost after someone widened the bind.
		banner_text = "● LISTENING  —  %s:%d  (localhost only)" % [BridgeServer.BIND_ADDRESS, _server.port()]
		banner_bg = COLOR_ON_BG
		status_text = "Handshake: %s   ·   token %s…   ·   Stop deletes the handshake file." % [
			BridgeServer.HANDSHAKE_PATH, _server.token().substr(0, TOKEN_PREVIEW_CHARS)]
		status_full = status_text
	elif _last_error != "":
		banner_text = "● OFF  —  start refused, no port is open"
		banner_bg = COLOR_ERR_BG
		status_text = "%s  Pick another port and press Start again — there is deliberately no fallback port." % clamp_line(_last_error, STATUS_ERROR_CHARS)
		status_full = _last_error
	else:
		banner_text = "○ OFF  —  no port is open"
		status_text = "Press Start to let an external tool talk to this editor. Nothing listens until you do."
		status_full = status_text

	# Guarded like the widgets above: _refresh_state() is the one repaint entry point and must degrade rather than
	# throw if it is ever reached before _init finished building the head.
	if _banner != null:
		_banner.text = banner_text
	if _banner_box != null:
		_banner_box.bg_color = banner_bg
	if _status != null:
		_status.text = status_text
		_status.tooltip_text = status_full  # the untruncated message, since the row itself is line-capped
	if _info != null:
		_info.text = _exposure_text(listening)


## The "what exactly is exposed" block. Spelled out rather than summarised: the whole point of a user-visible
## on/off tab is that the user can audit the surface without reading bridge_server.gd.
func _exposure_text(listening: bool) -> String:
	var lines := PackedStringArray()
	# Derived from bridge_server.gd's const, not retyped: this block is an audit surface, and an audit surface that
	# can drift from the code it describes is worse than no audit surface at all.
	lines.append("Bind address:   %s only — never 0.0.0.0, so nothing on your network can reach it." % BridgeServer.BIND_ADDRESS)
	lines.append("Auth:           every request must carry the random token from the handshake file; anything else is refused.")
	lines.append("Handshake file: %s   (port + token + editor PID; written on Start, deleted on Stop)" % BridgeServer.HANDSHAKE_PATH)
	lines.append("Protocol:       one connection = one JSON line in, one JSON line out, then close. No persistent sockets.")
	lines.append("")
	lines.append("Tools served (all read-only — none of them edits a scene or a resource):")
	lines.append("  godot_fs_sync       tell the editor that files changed on disk (EditorFileSystem update_file/scan).")
	lines.append("                      Without this, the editor's stale in-memory copy of an externally written .tres")
	lines.append("                      silently wins on your next Ctrl+S.")
	lines.append("  godot_editor_state  report the edited scene, the selected nodes, and the inspected resource.")
	lines.append("  godot_reveal        open a resource in the Inspector / select a node in the edited scene.")
	lines.append("")
	if listening:
		lines.append("The external MCP server (tools/mcp/cyber_mcp.py) reads the handshake file, so it finds this port by itself.")
	else:
		lines.append("While this is off, the MCP godot_* tools fail with a message telling the caller to open this tab and press Start.")
		lines.append("The seven headless CLI verbs (catalog / audit / refs / graph / balance / list / describe) do NOT need it —")
		lines.append("they shell out to scripts/tools/cyber.gd and never touch the editor.")
	return "\n".join(lines)
