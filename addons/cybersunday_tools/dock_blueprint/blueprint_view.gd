@tool
extends VBoxContainer

## CYBER SUNDAY -> Blueprints (Create group): one-click multi-resource "content packs". The Content tab makes ONE
## unwired .tres at a time; a blueprint scaffolds a SET of cross-wired resources. Today: the ENEMY PACK -- a Faction +
## a WeaponData+Item pair + a LootTable + an NpcData that references all three. Type a name, see exactly which files it
## will create (live, in designer words -- the full res:// path rides each row's hover hint, never the prose) and
## Scaffold. It REFUSES to overwrite any existing file: the Scaffold button greys the moment the name is empty or ANY
## planned path already exists (its tooltip names the first one), so the refusal is visible BEFORE the click. The
## post-click guards stay as the fallback. Pure logic in blueprint_ops.gd.
##
## Layout contract (every tab in the panel): the name row is OUTSIDE the ScrollContainer, the ONE status Label (+ the
## Place It handoff button beside it) sits under it, and everything that grows -- the live "Will create" preview and
## the result text -- lives INSIDE the scroll with fit_content on, so a longer name or a longer report grows the
## SCROLL, never the panel. The scroll carries a small height floor because a TabContainer's minimum is the CURRENT
## tab's minimum, and the editor's bottom splitter keeps the height it grew to: one tall tab would ratchet the whole
## bottom panel taller for every tab after it.
##
## Handoff (core/host.gd): after a successful scaffold, Place It hands the new NpcData to the panel's open_in_editor,
## which switches to the Place tab with that archetype preselected (scene_placer.select_path); a host that cannot
## route it opens the Inspector itself, and with no host at all (off-tree) this tab falls back to
## EditorInterface.edit_resource. The result text also carries a "Tune the weapon" link (meta_clicked) that opens the
## pack's WeaponData in the Inspector. Off-tree (GUT / the headless probe construct this bare) _init touches no editor
## API: the filesystem_changed hook sits behind Engine.is_editor_hint() and every other editor call lives in a handler.

const Scaffold := preload("res://addons/cybersunday_tools/dock_content/content_scaffold.gd")
const Ops := preload("res://addons/cybersunday_tools/dock_blueprint/blueprint_ops.gd")
const Host := preload("res://addons/cybersunday_tools/core/host.gd")

## Canonical folders, mirroring content_dock.gd (the single-resource generators write to these same dirs).
const DIRS := {
	"faction": "res://resources/factions/",
	"weapon": "res://resources/weapons/",
	"item": "res://resources/items/",
	"loot": "res://resources/loot/",
	"npc": "res://resources/characters/",
}

## Designer words for the plan's resource types. blueprint_ops.plan emits the class names (tests pin that order and
## spelling), so the translation to what a designer reads lives here, at the one place the rows are painted.
const LABELS := {
	"Faction": "Faction",
	"WeaponData": "Weapon stats",
	"Item": "Weapon item (inventory)",
	"LootTable": "Loot table",
	"NpcData": "Enemy archetype",
}

## Status / tooltip sentences, shared between a button's disabled tooltip and the post-click fallback so the two can
## never drift apart.
const MSG_IDLE := "Type a name, then Scaffold Enemy Pack -- it creates five wired files and never overwrites."
const MSG_NO_NAME := "Type a name first."
const MSG_NO_PACK := "Scaffold a pack first."
const NAME_TIP := "The enemy's name. It becomes the file name of every file in the pack (Ghoul -> ghoul.tres)."
const SCAFFOLD_TIP := "Creates a new enemy from this name: its faction, weapon stats, weapon item, loot table and enemy archetype, all wired together. Writes five new files -- never overwrites an existing one."
const PLACE_TIP := "Opens %s in the Place tab, ready to drop into the open level. Read-only."
const OUT_IDLE := "[i]An Enemy Pack is one new enemy, ready to fight: its faction, its weapon (stats + an inventory item), its loot table and the enemy archetype that ties them together.[/i]"

## Status tints -- a theme override on the Label, never bbcode. Warn for a refusal / failure, ok for a finished write.
const TINT_WARN := Color(1.0, 0.82, 0.3)
const TINT_OK := Color(0.6, 1.0, 0.6)

var _edit: LineEdit = null
var _scaffold_btn: Button = null
var _preview: RichTextLabel = null
var _out: RichTextLabel = null
var _status: Label = null
var _place_btn: Button = null

## The archetype file of the LAST successful scaffold (Place It's target) and the pack's display name. Empty until a
## pack has been created; cleared again if that file has gone missing when Place It is pressed.
var _npc_path := ""
var _pack_title := ""

## Set when the editor's FileSystem changes while the tab is hidden: the "already exists" marks (and the Scaffold
## button state they drive) are re-checked on the next reveal. A VISIBLE tab re-checks at once -- the check is five
## file stats that repaint the preview only; the typed name is the tab's whole state and it is never touched. Without
## this, deleting a half-made pack in the FileSystem dock would leave Scaffold greyed on a name that is free again.
var _fs_dirty := false


func _init() -> void:
	name = "Blueprints"
	add_theme_constant_override("separation", 4)

	# Head row (outside the scroll): the name + the one write command. No heading -- the tab title already says it.
	var row := HBoxContainer.new()
	_edit = LineEdit.new()
	_edit.placeholder_text = "Enemy name (e.g. Ghoul)"
	_edit.tooltip_text = NAME_TIP
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_changed.connect(func(_t): _refresh_preview())
	row.add_child(_edit)
	_scaffold_btn = Button.new()
	_scaffold_btn.text = "Scaffold Enemy Pack"
	_scaffold_btn.pressed.connect(_on_scaffold)
	row.add_child(_scaffold_btn)
	add_child(row)

	# Everything that grows scrolls: the live plan and the result report, both fit_content so their height follows
	# the text and the scroll (not the tab) absorbs it. Horizontal scroll is off so a long row wraps instead of
	# widening the panel.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 90)
	add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)

	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = true
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_preview)

	body.add_child(HSeparator.new())
	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.fit_content = true
	_out.selection_enabled = true
	_out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_out.meta_clicked.connect(_on_out_meta_clicked)
	body.add_child(_out)

	# Foot row (outside the scroll): the ONE status Label, two lines max with the full text mirrored into its tooltip
	# on every write, and the Place It handoff beside it.
	var foot := HBoxContainer.new()
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	foot.add_child(_status)
	_place_btn = Button.new()
	_place_btn.text = "Place It"
	_place_btn.pressed.connect(_on_place)
	foot.add_child(_place_btn)
	add_child(foot)

	_set_place_state()
	_set_status(MSG_IDLE)
	_set_out(OUT_IDLE)
	_refresh_preview()

	# Editor-only wiring, guarded so the bare off-tree construction (GUT / the headless probe) never touches
	# EditorInterface: the filesystem signal re-checks the "already exists" marks (see _fs_dirty).
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	visibility_changed.connect(_on_visibility_changed)


## EditorFileSystem.filesystem_changed: something under res:// changed. Re-check the plan now if the tab is on screen
## (a read-only repaint -- see _fs_dirty for why that is safe here), else flag it for the next reveal.
func _on_filesystem_changed() -> void:
	if is_visible_in_tree():
		_refresh_preview()
	else:
		_fs_dirty = true


## Re-check the plan on reveal when the filesystem changed while the tab was hidden.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and _fs_dirty:
		_fs_dirty = false
		_refresh_preview()


## Live list of the files the current name would create (QA: show every resource a template creates BEFORE it runs),
## and the Scaffold button's state: greyed with "Type a name first." on an empty name, greyed naming the FIRST
## planned file that already exists, live with its real tooltip otherwise. Runs on every keystroke, after every
## scaffold (all five now exist, so the button greys until the name changes) and on a filesystem change.
func _refresh_preview() -> void:
	var base := Scaffold.slugify(_edit.text.strip_edges())
	if base.is_empty():
		_preview.text = "[color=#888]Type a name to see the five files this pack will create.[/color]"
		_set_scaffold_state(true, MSG_NO_NAME)
		return
	var lines := PackedStringArray(["[b]Will create:[/b]"])
	var first_existing := ""
	for entry_v in Ops.plan(base, DIRS):
		var entry: Dictionary = entry_v
		var path := String(entry["path"])
		var exists := FileAccess.file_exists(path)
		if exists and first_existing.is_empty():
			first_existing = path
		lines.append(_row_bb(String(entry["type"]), path, exists))
	_preview.text = "\n".join(lines)
	if first_existing.is_empty():
		_set_scaffold_state(false, SCAFFOLD_TIP)
	else:
		_set_scaffold_state(true, "%s already exists in %s -- pick another name." % [first_existing.get_file(), _folder_of(first_existing)])


## Create the pack: sub-resources first (so the NpcData references them by path), then the Faction + NpcData. Refuses
## if ANY target path already exists (the button is normally greyed for that already -- this is the fallback). Fails
## soft -- a save error STOPS with a message and never throws, but the files written BEFORE the failure stay on disk
## (there is no rollback: deleting a just-written .tres the editor may already be importing is riskier than leaving
## it). So a partial run REPORTS every path it did create, because the refuse-overwrite guard will block a retry
## under the same name until the designer removes them.
func _on_scaffold() -> void:
	var base := Scaffold.slugify(_edit.text.strip_edges())
	if base.is_empty():
		_set_status(MSG_NO_NAME, TINT_WARN)
		return
	var title := Scaffold.titleize(base)
	for entry_v in Ops.plan(base, DIRS):
		var entry: Dictionary = entry_v
		var path := String(entry["path"])
		if FileAccess.file_exists(path):
			_set_status("Couldn't create the %s pack: %s already exists in %s -- pick another name (nothing was created)." % [title, path.get_file(), _folder_of(path)], TINT_WARN)
			_refresh_preview()
			return
	for d in DIRS.values():
		_ensure_dir(String(d))

	var weapon_path: String = DIRS["weapon"] + base + ".tres"
	var item_path: String = DIRS["item"] + base + "_item.tres"
	var loot_path: String = DIRS["loot"] + base + ".tres"
	var faction_path: String = DIRS["faction"] + base + ".tres"
	var npc_path: String = DIRS["npc"] + base + ".tres"

	# Every path successfully written, so a mid-sequence failure can report exactly what it left behind.
	var made: Array[String] = []

	var pair := Scaffold.build_weapon_and_item(base)
	if not _save(pair["weapon"], weapon_path, "weapon stats", made):
		return
	var item: Item = pair["item"]
	item.weapon = load(weapon_path)  # re-link to the SAVED weapon so the item .tres references it by path
	# Match the item's id to its <base>_item.tres FILENAME (the same correction content_dock._on_new_weapon makes).
	# build_weapon_and_item seeds id == base, which would collide with a plain Item authored as items/<base>.tres --
	# ItemDb keys its registry on Item.id, so two items sharing one id silently shadow each other (last write wins).
	item.id = StringName(base + "_item")
	if not _save(item, item_path, "weapon item", made):
		return
	if not _save(Scaffold.build_loot_table(), loot_path, "loot table", made):
		return
	var pack := Ops.build_pack(base, load(weapon_path), load(loot_path))
	if not _save(pack["faction"], faction_path, "faction", made):
		return
	if not _save(pack["npc"], npc_path, "enemy archetype", made):
		return

	_npc_path = npc_path
	_pack_title = title
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.edit_resource(load(npc_path))  # the NpcData is the hub of the pack -- land the Inspector on it
	_set_place_state()
	_refresh_preview()  # all five now exist: Scaffold greys (naming the first) until the name changes
	var rows := PackedStringArray()
	for entry_v in Ops.plan(base, DIRS):
		var entry: Dictionary = entry_v
		rows.append(_row_bb(String(entry["type"]), String(entry["path"]), false))
	_set_out(("[b]Created the %s pack[/b] -- 5 new files:\n%s\n[hint=%s][url=%s]Tune the weapon: %s[/url][/hint]\n\n"
		+ "[b]Ready to fight:[/b] the faction is hostile, so the enemy attacks the player on sight. Place It drops it "
		+ "into the open level, or add it to an EncounterSpawner. Optional: set the faction's relations for NPC-vs-NPC "
		+ "fights in the Factions tab, and fill the loot table's drops in the Loot tab.") % [
		title, "\n".join(rows), weapon_path, weapon_path, weapon_path.get_file()])
	_set_status("Created the %s pack -- 5 new files; Place It drops the enemy into the open level." % title, TINT_OK)


## Save one pack file, recording it in `made` on success. On failure the status names the file and the engine's
## reason in words (error_string), and the result text NAMES the files already written -- the refuse-overwrite guard
## will block a retry under this name until the designer deletes them, so "what did it leave behind?" has to be
## answerable from the panel, not from the FileSystem dock. `label` is the row's designer word ("weapon stats").
func _save(res: Resource, path: String, label: String, made: Array[String]) -> bool:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_set_status("Couldn't save %s (%s): %s." % [path.get_file(), label, error_string(err)], TINT_WARN)
		if made.is_empty():
			_set_out("[i]Nothing was created.[/i]")
		else:
			var rows := PackedStringArray()
			for p in made:
				rows.append("• [hint=%s]%s[/hint]" % [p, _short(p)])
			_set_out("[b]Already created[/b] -- delete these in the FileSystem dock before retrying the same name:\n" + "\n".join(rows))
			# The report sends the designer to the FileSystem dock, so the files it names have to BE there: a
			# half-finished pack is written but not yet imported, and an unscanned .tres is invisible in that dock.
			EditorInterface.get_resource_filesystem().scan()
		_refresh_preview()  # whatever did land now exists: grey Scaffold so a retry can't half-overwrite
		return false
	made.append(path)
	return true


## Place It: hand the last pack's NpcData to the Place tab (Host.open_in_editor -> cyber_panel -> scene_placer
## .select_path, which rescans and preselects it). A host that cannot route it has already opened the Inspector
## itself; only with NO host (off-tree) does this tab open the Inspector on its own.
func _on_place() -> void:
	if _npc_path.is_empty():
		_set_status(MSG_NO_PACK, TINT_WARN)
		return
	if not ResourceLoader.exists(_npc_path):
		_set_status("Couldn't open %s: %s is gone from the characters folder -- scaffold it again." % [_pack_title, _npc_path.get_file()], TINT_WARN)
		_npc_path = ""
		_set_place_state()
		return
	if Host.open_in_editor(self, _npc_path):
		_set_status("Opened %s in the Place tab -- Place NPC drops one in front of the camera." % _pack_title)
		return
	if Host.find(self) == null:
		EditorInterface.edit_resource(load(_npc_path))
	_set_status("Opened %s in the Inspector -- the Place tab couldn't take it; pick it from that tab's archetype list after a Refresh." % _pack_title)


## "Tune the weapon" link in the result text: open that WeaponData in the Inspector. `meta` is the res:// path.
func _on_out_meta_clicked(meta: Variant) -> void:
	var path := String(meta)
	if not ResourceLoader.exists(path):
		_set_status("Couldn't open %s: the file is gone -- scaffold the pack again." % path.get_file(), TINT_WARN)
		return
	EditorInterface.edit_resource(load(path))
	_set_status("Opened %s in the Inspector -- tune the weapon's damage, fire rate and range there." % path.get_file())


## One preview / result row: "• <designer label> -- <folder>/<file>" with the full path in the hover hint, plus a
## red "already exists" mark when the file is on disk.
func _row_bb(type: String, path: String, exists: bool) -> String:
	var mark := "  [color=#ff6666]already exists[/color]" if exists else ""
	return "• [b]%s[/b] -- [hint=%s]%s[/hint]%s" % [_label_for(type), path, _short(path), mark]


func _label_for(type: String) -> String:
	return String(LABELS.get(type, type))


## "res://resources/factions/ghoul.tres" -> "factions/ghoul.tres". Four of the five pack files share one file name
## (ghoul.tres), so the folder is the part that tells them apart; the full path stays in the hover hint.
func _short(path: String) -> String:
	return _folder_of(path) + "/" + path.get_file()


func _folder_of(path: String) -> String:
	return path.get_base_dir().get_file()


## The Scaffold button's disabled state + tooltip, derived by _refresh_preview from the name and the plan.
func _set_scaffold_state(disabled: bool, tip: String) -> void:
	if _scaffold_btn == null:
		return
	_scaffold_btn.disabled = disabled
	_scaffold_btn.tooltip_text = tip


## Place It is live only while a scaffolded pack is on record; its tooltip names that pack.
func _set_place_state() -> void:
	if _place_btn == null:
		return
	var ready := not _npc_path.is_empty()
	_place_btn.disabled = not ready
	_place_btn.tooltip_text = PLACE_TIP % _pack_title if ready else MSG_NO_PACK


func _ensure_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


func _set_out(bb: String) -> void:
	if _out != null:
		_out.text = bb


## The one status row: two lines on screen, the whole message in the tooltip. A tint with alpha (TINT_WARN /
## TINT_OK) colours the text through a theme override; the default Color() clears it back to the theme colour.
func _set_status(msg: String, tint: Color = Color()) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg
	if tint.a > 0.0:
		_status.add_theme_color_override("font_color", tint)
	else:
		_status.remove_theme_color_override("font_color")
