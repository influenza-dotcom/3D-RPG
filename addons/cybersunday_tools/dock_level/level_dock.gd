@tool
extends VBoxContainer

## Level tab (Build group of the CYBER SUNDAY panel): New Level / Check Navmesh / Bake + Check Navmesh / Validate
## Level / Validate Content, with the report in a scrolling panel under a one-line status. It REUSES the existing
## tooling rather than duplicating it -- NavMeshAudit.analyze, the LevelRoot validator (the node's own configuration
## warnings, reached through SceneWalk.config_warnings), ContentValidator.run fed by the shared ItemScan folder
## scan, and a port of scripts/tools/new_level.gd's template clone. Every check targets
## EditorInterface.get_edited_scene_root(); the region / LevelRoot are found by an explicit walk (SceneWalk), never
## get_tree() group queries (which at edit time span the whole open editor scene).
##
## Reads vs writes: the four check buttons are read-only reporters. Bake + Check Navmesh mutates the OPEN scene's
## NavigationMesh (the designer keeps it with Ctrl+S or discards it) but writes no file itself; the bake runs on a
## thread and the report lands when the region's bake_finished fires. New Level is the one disk writer -- two
## brand-new files, never an overwrite -- and then hands off: opens the scene, selects Geometry/Blockout so the Place
## tab's blockout pieces land there, and reveals the new level file in the FileSystem dock.
##
## Layout contract (shared with every tab in the panel): three one-line action rows and ONE two-line status Label
## sit outside a ScrollContainer; the report lives inside it behind a small height floor, so the tab's minimum height
## stays small. That matters because a TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom
## splitter keeps the height it grew to -- one tall tab stretches the shared panel for everyone.
##
## Host seams (cyber_panel.gd): on_scene_changed(root) is forwarded from EditorPlugin.scene_changed (and once at
## enable) so the three scene-bound buttons grey with "Open a scene first" BEFORE a click, not after. The lazy
## first-reveal latch re-asks the editor for the edited scene the first time the tab is actually shown, covering a
## tab built after that enable-time call. Off-tree (GUT / the headless probe construct this bare) every editor call
## stays inside a button handler or behind Engine.is_editor_hint(), so _init never touches EditorInterface.

const SceneWalk := preload("res://addons/cybersunday_tools/core/scene_walk.gd")
## The shared name-normalisation seam every other generator routes designer-typed names through (id == filename).
const Scaffold := preload("res://addons/cybersunday_tools/dock_content/content_scaffold.gd")
## The ONE shared item folder scan. ItemDb (the runtime registry) is a non-@tool autoload, so inside the editor it is
## an EMPTY Node -- without this scan ContentValidator's item rules ran over nothing and reported a clean project.
const ItemScan := preload("res://addons/cybersunday_tools/core/item_scan.gd")
## Faction ids on disk (a folder scan), so the content verdict can say how many factions it actually checked.
const Factions := preload("res://scripts/faction/factions.gd")

const TEMPLATE_SCENE := "res://scenes/levels/LevelTemplate.tscn"
const LEVEL_SCENE_DIR := "res://scenes/levels"
const LEVEL_DATA_DIR := "res://resources/levels"

## Report-panel verdict colours (bbcode, RichTextLabel only -- the status Label uses a theme override instead).
const OK_COLOR := "lime"
const WARN_COLOR := "#ffd24d"
## Status Label font override for a refusal (mirrors dialogue_graph.gd's PROBLEM_COLOR); removed on the next OK write.
const PROBLEM_COLOR := Color(1.0, 0.42, 0.42)

## Report ScrollContainer floor: small enough that the tab never forces the shared bottom panel taller than a short
## display; the report scrolls inside it.
const REPORT_MIN_HEIGHT := 90
## Seconds after which a bake that never reported back releases the two navmesh buttons (see _on_bake_watchdog).
const BAKE_WATCHDOG_SEC := 120.0

## Disabled-state tooltips (rule: a button that cannot apply says what is missing) and the idle status.
const MSG_NO_SCENE := "Open a scene first"
const MSG_NO_NAME := "Type a level name first"
const MSG_BAKING := "Baking navmesh... wait for the report"
const MSG_IDLE := "Open a level scene, then Check Navmesh or Validate Level -- or type a name and press New Level."
## Button tooltips: what it does, then whether it writes.
const TIP_NEW_LEVEL := "New Level: copies the level template into a new scene and writes its level file, then opens it. Writes two new files, never overwrites."
const TIP_CHECK := "Check Navmesh: counts islands and elevated polys on the baked NavigationRegion3D. Read-only."
const TIP_BAKE := "Bake + Check Navmesh: bakes, then checks. The bake lives in the scene until you save."
const TIP_VALIDATE_LEVEL := "Validate Level: runs the checks the level's root node shows in the Inspector (sky, navmesh, player spawn), all at once. Read-only."
const TIP_VALIDATE_CONTENT := "Validate Content: checks item ids, ammo calibers, faction files, perks and AI profiles across the project. Read-only."

var _name_edit: LineEdit = null
var _new_level_btn: Button = null
var _check_btn: Button = null
var _bake_btn: Button = null
var _validate_level_btn: Button = null
var _validate_content_btn: Button = null
var _status: Label = null
var _out: RichTextLabel = null

## Mirrors the host's on_scene_changed(root): drives the disabled state of the three scene-bound buttons. The
## handlers re-read the live edited-scene root themselves (the editor is the source of truth); this only gates buttons.
var _scene_open := false
## True from a Bake + Check Navmesh press until the region's bake_finished fires; both navmesh buttons stay grey.
var _baking := false
## The region whose bake is pending. A scene closed mid-bake frees its region, and a freed region never emits
## bake_finished -- _update_button_state releases the latch when this stops being a live instance.
var _bake_region: NavigationRegion3D = null
## Bumped on every Bake press. The watchdog timer carries this number instead of the region, so a timer left over
## from an earlier bake identifies itself as stale without holding a Node reference for two minutes.
var _bake_token := 0

## Lazy first-reveal latch -- the tab asks the editor for the edited scene the first time it is actually shown, not
## at panel construction (cyber_panel._init builds every tab eagerly, and _init must stay free of editor calls so the
## bare off-tree construction under GUT keeps working). Mirrors palette_dock / item_placer_dock.
var _revealed := false


func _init() -> void:
	name = "Level"
	add_theme_constant_override("separation", 4)

	# Row 1: level name + New Level. The button is the ONLY writer in this tab, so it stays a deliberate click (no
	# Enter-to-submit on the name field).
	var row1 := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Level name (e.g. Raider Camp)"
	_name_edit.tooltip_text = "The new level's name. Spaces and capitals are fine -- the two files it writes get a tidied-up version of it."
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Greys New Level until there is something to name the level. Note the SETTER never emits this signal, so any
	# code path that assigns _name_edit.text must call _update_button_state() itself.
	_name_edit.text_changed.connect(func(_t: String) -> void: _update_button_state())
	row1.add_child(_name_edit)
	_new_level_btn = _make_button("New Level", TIP_NEW_LEVEL, _on_new_level)
	row1.add_child(_new_level_btn)
	add_child(row1)

	# Row 2: the navmesh pair. Row 3: the two validators. Every button shares the row's width.
	var row2 := HBoxContainer.new()
	_check_btn = _make_button("Check Navmesh", TIP_CHECK, _on_check)
	_check_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_check_btn)
	_bake_btn = _make_button("Bake + Check Navmesh", TIP_BAKE, _on_bake_check)
	_bake_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_bake_btn)
	add_child(row2)

	var row3 := HBoxContainer.new()
	_validate_level_btn = _make_button("Validate Level", TIP_VALIDATE_LEVEL, _on_validate_level)
	_validate_level_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_validate_level_btn)
	_validate_content_btn = _make_button("Validate Content", TIP_VALIDATE_CONTENT, _on_validate_content)
	_validate_content_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_validate_content_btn)
	add_child(row3)

	# What the tab just DID or REFUSED: one two-line clamped row whose tooltip mirrors the full text on every write,
	# so a long refusal can never push the report off a short bottom panel.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	_set_status(MSG_IDLE)

	# The report. The RichTextLabel grows to its text (fit_content) and the ScrollContainer around it scrolls;
	# horizontal scrolling is DISABLED so a long warning wraps instead of widening the whole bottom panel.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, REPORT_MIN_HEIGHT)
	add_child(scroll)
	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.fit_content = true
	_out.scroll_active = false
	_out.selection_enabled = true
	_out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_out)
	_set_out("[i]Reports land here.[/i]")

	_update_button_state()  # scene-bound buttons start grey; the first reveal / the host's on_scene_changed lifts them

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # no-op off-tree (not visible); in the editor the real reveal fires the signal


func _make_button(text: String, tip: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(handler)
	return b


## Lazy first-reveal: the first time the tab is actually shown, sync the scene gate from the editor. Guarded by
## Engine.is_editor_hint() because EditorInterface is not a thing in a headless / GUT construction. After this the
## host keeps the gate current through on_scene_changed.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		if Engine.is_editor_hint():
			on_scene_changed(EditorInterface.get_edited_scene_root())


## Host seam (cyber_panel.on_scene_changed, forwarded from EditorPlugin.scene_changed and once at enable): grey
## Check / Bake / Validate Level while no scene is open. New Level and Validate Content never need a scene. `root`
## may be null (every scene closed). is_instance_valid guards a stale root handed over mid-close -- a freed Object
## compares unequal to null in GDScript, so a bare null test is not enough.
func on_scene_changed(root: Node) -> void:
	_scene_open = is_instance_valid(root)
	_update_button_state()


## Disabled state + tooltip of every gated button, from three gates: no scene (the three scene-bound buttons grey,
## "Open a scene first"), a pending bake (the two navmesh buttons grey, "Baking navmesh...") and an empty name box
## (New Level grey, "Type a level name first"). Each handler still repeats its own check and writes the same
## sentence to the status, because a greyed button explains nothing to a designer who never hovers it.
## A release path lives here too: a scene closed mid-bake frees its region and a freed region never emits
## bake_finished, so the latch is dropped the moment the region stops being a live instance instead of leaving the
## buttons grey until the plugin reloads.
func _update_button_state() -> void:
	if _check_btn == null:
		return
	if _baking and not is_instance_valid(_bake_region):
		_baking = false
		_bake_region = null
	_gate_on_scene(_check_btn, TIP_CHECK)
	_gate_on_scene(_bake_btn, TIP_BAKE)
	_gate_on_scene(_validate_level_btn, TIP_VALIDATE_LEVEL)
	if _baking:
		_check_btn.disabled = true
		_check_btn.tooltip_text = MSG_BAKING
		_bake_btn.disabled = true
		_bake_btn.tooltip_text = MSG_BAKING
	# New Level needs no scene, only a name. Validate Content needs neither and is never gated here (it disables
	# itself for the length of its own scan).
	var named := not _name_edit.text.strip_edges().is_empty()
	_new_level_btn.disabled = not named
	_new_level_btn.tooltip_text = TIP_NEW_LEVEL if named else MSG_NO_NAME


func _gate_on_scene(b: Button, tip: String) -> void:
	b.disabled = not _scene_open
	b.tooltip_text = tip if _scene_open else MSG_NO_SCENE


# --- targets ---------------------------------------------------------------------------------------------------

func _edited_root() -> Node:
	return EditorInterface.get_edited_scene_root()

## The first NavigationRegion3D anywhere under `root` (the template has exactly one), or null.
func _region(root: Node) -> NavigationRegion3D:
	for n in SceneWalk.collect_all(root):
		if n is NavigationRegion3D:
			return n as NavigationRegion3D
	return null

## The first node carrying the LevelRoot script (the template puts it on the scene root), or null.
func _level_root(root: Node) -> Node:
	for n in SceneWalk.collect_all(root):
		if n is LevelRoot:
			return n
	return null

## How the status names the open scene: its file name, or the root's node name for a never-saved scene.
func _scene_label(root: Node) -> String:
	var f := root.scene_file_path.get_file()
	return f if not f.is_empty() else String(root.name)


# --- navmesh -----------------------------------------------------------------------------------------------------

func _on_check() -> void:
	var root := _edited_root()
	on_scene_changed(root)  # keep the button state honest with what this click just observed
	if root == null:
		_refuse("Open a level scene first, then Check Navmesh.")
		return
	var region := _region(root)
	if region == null:
		_refuse("Couldn't check the navmesh: %s has no NavigationRegion3D -- levels made from the template have one." % _scene_label(root))
		return
	# Same pre-check as the bake path: NavMeshAudit does answer for a missing mesh, but its wording is a code report
	# ("No NavigationMesh assigned to the region.") beside a row of zeroes. Refusing in words is the kinder answer,
	# and it names the fix.
	if region.navigation_mesh == null:
		_refuse("Couldn't check the navmesh: the NavigationRegion3D has no NavigationMesh -- add one in the Inspector, then Bake + Check Navmesh.")
		return
	_render_audit(NavMeshAudit.analyze(region.navigation_mesh), _scene_label(root), false)


## Threaded bake, then the same report as Check Navmesh once the region says it is done. The two navmesh buttons
## stay grey in between (a second press while baking is refused as well, because the report of a stacked bake would
## be indistinguishable from the first). The bake changes the OPEN scene only -- Ctrl+S keeps it.
func _on_bake_check() -> void:
	if _baking and is_instance_valid(_bake_region):
		_refuse("Couldn't start another bake: the navmesh is still baking -- the report lands here on its own.")
		return
	var root := _edited_root()
	on_scene_changed(root)
	if root == null:
		_refuse("Open a level scene first, then Bake + Check Navmesh.")
		return
	var region := _region(root)
	if region == null:
		_refuse("Couldn't bake the navmesh: %s has no NavigationRegion3D -- levels made from the template have one." % _scene_label(root))
		return
	if region.navigation_mesh == null:
		_refuse("Couldn't bake the navmesh: the NavigationRegion3D has no NavigationMesh -- add one in the Inspector, then Bake + Check Navmesh.")
		return
	if region.is_baking():
		_refuse("Couldn't bake the navmesh: a bake is already running (started from the toolbar?) -- wait for it, then Check Navmesh.")
		return
	_baking = true
	_bake_region = region
	_bake_token += 1
	_update_button_state()
	_set_status("Baking navmesh...")
	# ONE_SHOT: a persistent connection would re-render this tab's report after every toolbar bake of that region
	# for the rest of the editor session. The region and scene label ride along because the edited scene may have
	# changed by the time the bake reports back. The is_connected test covers the ONE case where the one-shot did
	# NOT fire and so did NOT disconnect itself -- a bake the watchdog gave up on: re-connecting an IDENTICAL
	# Callable (same bound region + label) is an engine error, and the surviving connection already does the job.
	var report := _on_bake_finished.bind(region, _scene_label(root))
	if not region.bake_finished.is_connected(report):
		region.bake_finished.connect(report, CONNECT_ONE_SHOT)
	region.bake_navigation_mesh(true)  # on_thread: the editor stays responsive; bake_finished delivers the result
	# Watchdog for the one gap the validity check cannot see: the engine refusing the bake AFTER the latch is set
	# (it then never emits bake_finished, and the region stays alive). Without it the buttons would stay grey for
	# good. It carries the bake TOKEN, never the region: a SceneTreeTimer holds this Callable (and everything bound
	# into it) for two minutes, and a scene closed in that window would leave a freed Node riding in the bind.
	if is_inside_tree():
		get_tree().create_timer(BAKE_WATCHDOG_SEC).timeout.connect(_on_bake_watchdog.bind(_bake_token))


func _on_bake_finished(region: NavigationRegion3D, scene_label: String) -> void:
	if region == _bake_region:
		_baking = false
		_bake_region = null
	_update_button_state()
	if not is_instance_valid(region):
		_refuse("Couldn't check the navmesh after baking: %s was closed before the bake finished." % scene_label)
		return
	_render_audit(NavMeshAudit.analyze(region.navigation_mesh), scene_label, true)


## Release valve, BAKE_WATCHDOG_SEC after the press. `token` identifies the bake it was armed for, so a stale timer
## (the bake already reported, or a newer press replaced it) is a no-op. A bake that is genuinely still running is
## left alone -- bake_finished still lands and clears the latch; no re-arm is needed for that case.
func _on_bake_watchdog(token: int) -> void:
	if not _baking or token != _bake_token:
		return  # that bake already reported back (or a newer one is pending)
	if is_instance_valid(_bake_region) and _bake_region.is_baking():
		return  # still genuinely baking (a huge level) -- bake_finished will land
	_baking = false
	_bake_region = null
	_update_button_state()
	_refuse("Couldn't finish Bake + Check Navmesh: the bake never reported back -- check the Output panel, then try again.")


## The navmesh verdict: one line the designer can act on, then NavMeshAudit's own warnings. `baked` appends the
## reminder that a bake is a scene change the designer still has to save.
func _render_audit(rep: Dictionary, scene_label: String, baked: bool) -> void:
	var settings: Dictionary = rep.get("settings", {})
	var ok: bool = bool(rep.get("ok", false))
	var islands: Array = rep.get("islands", [])
	var elevated: Array = rep.get("elevated", [])
	var warnings: Array = rep.get("warnings", [])
	var counts := "%s, %d elevated, climb %.2f" % [
		_count(islands.size(), "island", "islands"), elevated.size(), float(settings.get("agent_max_climb", 0.0))]
	var lines := PackedStringArray()
	if ok:
		lines.append("[color=%s]Navmesh: OK[/color] -- %s" % [OK_COLOR, counts])
	else:
		lines.append("[color=%s]Navmesh: %d issue(s)[/color]: %s" % [WARN_COLOR, warnings.size(), counts])
		for w in warnings:
			lines.append("  • " + str(w))
	if baked:
		lines.append("(the bake lives in the scene until you save it -- Ctrl+S)")
	_set_out("\n".join(lines))
	var verb := "Baked and checked" if baked else "Checked"
	if ok:
		_set_status("%s the navmesh in %s -- OK." % [verb, scene_label])
	else:
		_set_status("%s the navmesh in %s -- %d issue(s), listed below." % [verb, scene_label, warnings.size()])


# --- validators --------------------------------------------------------------------------------------------------

func _on_validate_level() -> void:
	var root := _edited_root()
	on_scene_changed(root)
	if root == null:
		_refuse("Open a level scene first, then Validate Level.")
		return
	var lr := _level_root(root)
	if lr == null:
		_refuse("Couldn't validate %s: no node in it has the LevelRoot script -- levels made from the template carry it on the root." % _scene_label(root))
		return
	var w := SceneWalk.config_warnings(lr)
	if w.is_empty():
		_set_out("[color=%s]Level: OK[/color] -- %s reports no problems." % [OK_COLOR, lr.name])
		_set_status("Validated %s -- OK." % _scene_label(root))
		return
	var lines := PackedStringArray(["[color=%s]Level: %d issue(s)[/color]" % [WARN_COLOR, w.size()]])
	for s in w:
		lines.append("  • " + str(s))
	_set_out("\n".join(lines))
	_set_status("Validated %s -- %d issue(s), listed below." % [_scene_label(root), w.size()])


## Project-wide content check over the SHARED folder scan (ItemScan), so the item rules actually run inside the
## editor. Files that exist but did not load as an Item are named, not dropped -- a shorter list otherwise reads as
## "my item vanished" mid-reimport. Zero items is called out too: an all-green report over nothing is not a pass.
func _on_validate_content() -> void:
	_set_status("Scanning...")
	_validate_content_btn.disabled = true
	if is_inside_tree():
		await get_tree().process_frame  # let the status paint before the folder walk
	var rep := ItemScan.scan_report()
	var items: Array = rep["items"]
	var skipped: PackedStringArray = rep["skipped"]
	var problems := ContentValidator.run(items)
	var faction_count := Factions.ids().size()
	var checked := "%s, %s checked" % [_count(items.size(), "item", "items"), _count(faction_count, "faction", "factions")]
	var lines := PackedStringArray()
	if problems.is_empty():
		lines.append("[color=%s]Content: OK[/color] -- %s" % [OK_COLOR, checked])
	else:
		lines.append("[color=%s]Content: %d problem(s)[/color] -- %s" % [WARN_COLOR, problems.size(), checked])
		for p in problems:
			lines.append("  • " + str(p))
	if items.is_empty():
		lines.append("[color=%s]No item files were found in resources/items[/color] -- the item checks ran over nothing." % WARN_COLOR)
	if not skipped.is_empty():
		var names := PackedStringArray()
		for p in skipped:
			names.append(String(p).get_file())
		lines.append("[color=%s]%s could not be read and went unchecked:[/color] %s -- reimport in progress? press Validate Content again." % [
			WARN_COLOR, _count(skipped.size(), "item file", "item files"), ", ".join(names)])
	_set_out("\n".join(lines))
	if problems.is_empty():
		_set_status("Validated content -- OK, %s." % checked)
	else:
		_set_status("Validated content -- %d problem(s), listed below." % problems.size())
	_validate_content_btn.disabled = false


# --- new level -----------------------------------------------------------------------------------------------------

## New Level: slugify the typed name, refuse an overwrite, write the two files, then hand off to the editor.
func _on_new_level() -> void:
	var raw := _name_edit.text.strip_edges()
	if raw.is_empty():
		_refuse("Couldn't make a level: type a name for it first.")
		return
	# SLUGIFY like every other generator: the raw text goes straight into a file path, so a "/" would silently write
	# into another folder and a ":"/"?" would fail the save with only a generic message. The typed text is kept as the
	# LevelData display_name, so "Raider Camp" -> raider_camp.tscn / raider_camp.tres shown as "Raider Camp".
	var nm := Scaffold.slugify(raw)
	if nm.is_empty():
		_refuse("Couldn't make '%s': the name has no usable letters or digits -- try one like Raider Camp." % raw)
		return
	var scene_path := "%s/%s.tscn" % [LEVEL_SCENE_DIR, nm]
	var data_path := "%s/%s.tres" % [LEVEL_DATA_DIR, nm]
	if FileAccess.file_exists(scene_path) or FileAccess.file_exists(data_path):
		_refuse("Couldn't make %s: %s or %s already exists -- try another name." % [raw, scene_path.get_file(), data_path.get_file()])
		return
	var problem := _make_level(scene_path, data_path, raw)
	if not problem.is_empty():
		_refuse(problem)
		return
	_set_out("Created %s in scenes/levels and %s in resources/levels.\n%s is selected in the FileSystem dock -- a Level Door in another level points at it to travel here." % [
		scene_path.get_file(), data_path.get_file(), data_path.get_file()])
	_open_new_level(scene_path, data_path, raw)


## Port of new_level.gd: clone LevelTemplate.tscn into `scene_path` (re-packed for a fresh uid) and write a matching
## LevelData at `data_path`. Returns "" on success or the refusal sentence (with the engine's reason in words).
## The caller has already checked that neither path exists.
func _make_level(scene_path: String, data_path: String, display: String) -> String:
	var template := load(TEMPLATE_SCENE) as PackedScene
	if template == null:
		return "Couldn't make %s: the level template %s is missing or broken." % [display, TEMPLATE_SCENE.get_file()]
	# Re-pack a fresh copy so the new scene gets its OWN uid (a raw file copy would clash with the template's uid).
	var inst := template.instantiate()
	var packed := PackedScene.new()
	var err := packed.pack(inst)
	inst.free()
	if err != OK:
		return "Couldn't make %s: packing the template copy failed (%s)." % [display, error_string(err)]
	err = ResourceSaver.save(packed, scene_path)
	if err != OK:
		return "Couldn't save %s: %s." % [scene_path.get_file(), error_string(err)]
	var data := LevelData.new()
	data.scene = load(scene_path)
	data.display_name = display
	err = ResourceSaver.save(data, data_path)
	if err != OK:
		return "Couldn't save %s: %s -- %s was already written; delete it or try another name." % [
			data_path.get_file(), error_string(err), scene_path.get_file()]
	return ""


## The handoff after a successful write: open the new scene, land the designer on Geometry/Blockout (the Place tab
## parents its blockout pieces under the SELECTED node, so selecting it here is what makes "Place tab -> Blockout"
## build in the right place), and reveal the level file in the FileSystem dock -- reveal only, the Inspector keeps
## showing the Blockout node, so the next click is a Place-tab click and not an Inspector detour.
func _open_new_level(scene_path: String, data_path: String, display: String) -> void:
	var fs := EditorInterface.get_resource_filesystem()
	# Register the two new files with the editor's file index NOW: the scan below runs in the background, and the
	# FileSystem dock refuses (with an editor error) to navigate to a path it has not indexed yet.
	fs.update_file(scene_path)
	fs.update_file(data_path)
	fs.scan()
	EditorInterface.open_scene_from_path(scene_path)
	var root := EditorInterface.get_edited_scene_root()
	var blockout: Node = null
	if root != null and root.scene_file_path == scene_path:
		for n in SceneWalk.collect_all(root):
			var parent := n.get_parent()
			if n.name == "Blockout" and parent != null and parent.name == "Geometry":
				blockout = n
				break
	if blockout != null:
		var sel := EditorInterface.get_selection()
		sel.clear()
		sel.add_node(blockout)
		EditorInterface.edit_node(blockout)
	if fs.get_file_type(data_path) != "":
		EditorInterface.get_file_system_dock().navigate_to_path(data_path)
	on_scene_changed(root)  # lift the scene gate now rather than waiting for the editor's scene_changed round-trip
	var where := "" if blockout != null else " (select Geometry/Blockout in the Scene tree first)"
	_set_status("Opened %s. Next: Place tab -> Blockout builds the shell under Geometry/Blockout%s; then Bake + Check Navmesh here; then a Level Door in another level points at this level." % [display, where])


# --- output ----------------------------------------------------------------------------------------------------

static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


func _set_out(bb: String) -> void:
	if _out != null:
		_out.text = bb


## The status row: text + tooltip mirror (the label clamps to two lines; hovering shows the whole message). A
## refusal tints the font; the next non-refusal write clears the tint.
func _set_status(msg: String, problem: bool = false) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg
	if problem:
		_status.add_theme_color_override("font_color", PROBLEM_COLOR)
	else:
		_status.remove_theme_color_override("font_color")


## A command that produced no verdict. The refusal goes to BOTH read-outs on purpose: the report panel is read as
## "what the last button did", so leaving the previous command's green "Navmesh: OK" standing under a refusal would
## let a designer take a verdict from a level (or a check) that never ran. The report also has the room the two-line
## status does not.
func _refuse(msg: String) -> void:
	_set_status(msg, true)
	_set_out("[color=%s]%s[/color]" % [WARN_COLOR, msg])
