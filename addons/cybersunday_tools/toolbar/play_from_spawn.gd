@tool
extends HBoxContainer

## Play-from-spawn toolbar: launch the game from the editor. "Play" runs the project's main scene. "Play From
## Spawn" writes the SELECTED PlayerSpawn's entry_id to GameRoot.DEV_START_FILE (GameRoot consumes it once on
## start) and runs the main scene -- so you start the player at that spawn instead of the level's default arrival,
## for fast iteration on a specific area.
##
## WHY the second button is DISABLED until a PlayerSpawn is selected: it used to look live at all times and, with
## nothing selected, its only feedback was a push_warning into the Output dock -- which a designer does not watch.
## The click looked like it had launched the game and then nothing happened. Now the button greys itself from the
## editor's selection signal and says what is missing in its tooltip, and every refusal that can still happen goes
## to the editor TOASTER (the transient banner over the viewport), where it is actually seen.
##
## The tooltip NAMES the main scene by READING it back from ProjectSettings rather than hardcoding a filename.
## It used to say "game.tscn" while `application/run/main_scene` had long since become `scenes/computerroom.tscn`
## -- the button was always correct (play_main_scene follows the setting) but the label told the designer the wrong
## thing. Deriving it means the label can never drift from what the button actually launches.
##
## EDITOR-ONLY SEAMS: every EditorInterface call sits behind `Engine.is_editor_hint()` so the whole control can be
## built and driven off-tree by GUT (tests/test_devtools_toolbar.gd constructs it bare and calls the handler).

const SPAWN_TIP := "Play, starting the player at the selected PlayerSpawn instead of the level's usual arrival."
const SPAWN_TIP_DISABLED := "Select a PlayerSpawn in the scene to enable -- then this plays from that spawn."

var _spawn_btn: Button = null


## The project's configured main scene, as a bare filename for the tooltip ("computerroom.tscn"), or a plain
## fallback phrase when the setting is unset/blank.
static func _main_scene_label() -> String:
	var path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	return path.get_file() if not path.is_empty() else "the project's main scene"


func _init() -> void:
	name = "PlayFromSpawn"
	var play := Button.new()
	play.text = "▶ Play"
	play.tooltip_text = "Play the main scene (%s). Same as F5." % _main_scene_label()
	play.pressed.connect(func() -> void: EditorInterface.play_main_scene())
	add_child(play)

	_spawn_btn = Button.new()
	_spawn_btn.text = "▶ Play From Spawn"
	_spawn_btn.tooltip_text = SPAWN_TIP_DISABLED
	_spawn_btn.disabled = true
	_spawn_btn.pressed.connect(_play_from_spawn)
	add_child(_spawn_btn)


## The editor's selection drives the button's enabled state, so the designer never clicks a control that cannot
## work. Connected on tree entry (the toolbar lives in the editor's own tree) and released on exit -- the editor
## reloads plugins on every script change, and an unreleased connection leaks one per reload.
func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	var sel := EditorInterface.get_selection()
	if sel != null and not sel.selection_changed.is_connected(_refresh_enabled):
		sel.selection_changed.connect(_refresh_enabled)
	_refresh_enabled()


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		return
	var sel := EditorInterface.get_selection()
	if sel != null and sel.selection_changed.is_connected(_refresh_enabled):
		sel.selection_changed.disconnect(_refresh_enabled)


func _refresh_enabled() -> void:
	if _spawn_btn == null:
		return
	var has_spawn := _selected_spawn() != null
	_spawn_btn.disabled = not has_spawn
	_spawn_btn.tooltip_text = SPAWN_TIP if has_spawn else SPAWN_TIP_DISABLED


## Write the selected spawn's entry_id where GameRoot will consume it once, then play. Every refusal returns
## WITHOUT launching, so the designer never watches the game boot at the wrong place and wonders why.
func _play_from_spawn() -> void:
	var spawn := _selected_spawn()
	if spawn == null:
		_notify("Select a PlayerSpawn in the scene first, then press Play From Spawn.")
		return
	var f := FileAccess.open(GameRoot.DEV_START_FILE, FileAccess.WRITE)
	if f == null:
		# Launching anyway would silently start at the level's default arrival -- the exact "it ignored me" bug.
		_notify("Couldn't write the play-from-spawn note: %s. Nothing was launched." % error_string(FileAccess.get_open_error()))
		return
	var entry := String(spawn.entry_id)
	f.store_string(entry)
	f = null
	if entry.strip_edges().is_empty():
		# A blank entry_id IS the level's default arrival (player_spawn.gd), so this run is identical to plain Play.
		# Say so rather than letting it read as a broken button.
		_notify("That PlayerSpawn has a blank entry id -- it is the level's default arrival, so this is the same as Play.")
	if Engine.is_editor_hint():
		EditorInterface.play_main_scene()


## Refusals and notes go to the editor's toaster (a banner over the viewport) because the Output dock is muted or
## scrolled away on a working editor. push_warning stays as the headless / no-toaster fallback.
func _notify(msg: String) -> void:
	if Engine.is_editor_hint():
		var toaster := EditorInterface.get_editor_toaster()
		if toaster != null:
			toaster.push_toast(msg, EditorToaster.SEVERITY_WARNING)
			return
	push_warning("Play From Spawn: %s" % msg)


## The first selected PlayerSpawn, or null. Returns null outside the editor so the whole control (and this handler)
## can be exercised off-tree by GUT without an EditorInterface singleton. Validity is tested BEFORE the type check:
## the editor's selection can still hold a node that was freed under it (a scene closed / a node deleted between the
## selection_changed signal and this read), and `is` on a freed instance HARD-CRASHES the editor -- validity FIRST.
func _selected_spawn() -> PlayerSpawn:
	if not Engine.is_editor_hint():
		return null
	var sel := EditorInterface.get_selection()
	if sel == null:
		return null
	for n in sel.get_selected_nodes():
		if is_instance_valid(n) and n is PlayerSpawn:
			return n as PlayerSpawn
	return null
