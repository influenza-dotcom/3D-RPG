@tool
extends VBoxContainer

## CYBER SUNDAY → Blueprints: one-click multi-resource "content packs". The Content tab makes ONE unwired .tres at
## a time; a blueprint scaffolds a SET of cross-wired resources. Today: the ENEMY PACK — a Faction + a Weapon+Item
## pair + a LootTable + an NpcData that references all three. Type a name, see exactly which files it will create
## (live), and Scaffold. It REFUSES to overwrite any existing file. Pure logic in blueprint_ops.gd.

const Scaffold := preload("res://addons/cybersunday_tools/dock_content/content_scaffold.gd")
const Ops := preload("res://addons/cybersunday_tools/dock_blueprint/blueprint_ops.gd")

## Canonical folders, mirroring content_dock.gd (the single-resource generators write to these same dirs).
const DIRS := {
	"faction": "res://resources/factions/",
	"weapon": "res://resources/weapons/",
	"item": "res://resources/items/",
	"loot": "res://resources/loot/",
	"npc": "res://resources/characters/",
}

var _edit: LineEdit = null
var _preview: RichTextLabel = null
var _out: RichTextLabel = null


func _init() -> void:
	name = "Blueprints"
	add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Content-pack blueprints"
	add_child(title)

	var row := HBoxContainer.new()
	_edit = LineEdit.new()
	_edit.placeholder_text = "enemy_id (e.g. ghoul)"
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_changed.connect(func(_t): _refresh_preview())
	row.add_child(_edit)
	var b := Button.new()
	b.text = "Scaffold Enemy Pack"
	b.tooltip_text = "Create a wired Faction + Weapon+Item + LootTable + NpcData from this name."
	b.pressed.connect(_on_scaffold)
	row.add_child(b)
	add_child(row)

	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = true
	_preview.fit_content = true
	_preview.custom_minimum_size = Vector2(0, 70)
	add_child(_preview)

	add_child(HSeparator.new())
	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.selection_enabled = true
	_out.custom_minimum_size = Vector2(0, 60)
	add_child(_out)

	_out.text = "[i]An Enemy Pack = Faction + Weapon+Item + LootTable + NpcData, cross-wired. Authoring a new enemy in one click.[/i]"
	_refresh_preview()


## Live list of the files the current name would create (QA: show every resource a template creates BEFORE it runs).
func _refresh_preview() -> void:
	var base := Scaffold._slugify(_edit.text.strip_edges())
	if base.is_empty():
		_preview.text = "[color=#888]Type a name to preview the files this pack will create.[/color]"
		return
	var lines := PackedStringArray(["[b]Will create:[/b]"])
	for entry in Ops.plan(base, DIRS):
		var exists: bool = FileAccess.file_exists(String(entry["path"]))
		var mark := "  [color=#ff6666](exists!)[/color]" if exists else ""
		lines.append("• %s — %s%s" % [str(entry["type"]), str(entry["path"]), mark])
	_preview.text = "\n".join(lines)


## Create the pack: sub-resources first (so the NpcData references them by path), then the Faction + NpcData. Refuses
## if ANY target path already exists. Fails soft — a save error stops with a message, never a half-built throw.
func _on_scaffold() -> void:
	var base := Scaffold._slugify(_edit.text.strip_edges())
	if base.is_empty():
		_warn("Type a name first.")
		return
	for entry in Ops.plan(base, DIRS):
		if FileAccess.file_exists(String(entry["path"])):
			_warn("'%s' already exists — pick another name (nothing was created)." % str(entry["path"]))
			return
	for d in DIRS.values():
		_ensure_dir(String(d))

	var weapon_path: String = DIRS["weapon"] + base + ".tres"
	var item_path: String = DIRS["item"] + base + "_item.tres"
	var loot_path: String = DIRS["loot"] + base + ".tres"
	var faction_path: String = DIRS["faction"] + base + ".tres"
	var npc_path: String = DIRS["npc"] + base + ".tres"

	var pair := Scaffold.build_weapon_and_item(base)
	if not _save(pair["weapon"], weapon_path):
		return
	var item: Item = pair["item"]
	item.weapon = load(weapon_path)  # re-link to the SAVED weapon so the item .tres references it by path
	if not _save(item, item_path):
		return
	if not _save(Scaffold.build_loot_table(), loot_path):
		return
	var pack := Ops.build_pack(base, load(weapon_path), load(loot_path))
	if not _save(pack["faction"], faction_path):
		return
	if not _save(pack["npc"], npc_path):
		return

	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.edit_resource(load(npc_path))  # open the NpcData — the hub of the pack
	_set_out("[color=lime]Created the %s pack[/color] (5 files):\n• %s\n• %s\n• %s\n• %s\n• %s\n\n[b]Next:[/b] the new faction is NEUTRAL — set its relations in %s (e.g. enemy of the player's faction) so the enemy actually fights." % [
		Scaffold._titleize(base), faction_path, weapon_path, item_path, loot_path, npc_path, faction_path])


func _save(res: Resource, path: String) -> bool:
	if ResourceSaver.save(res, path) != OK:
		_warn("Failed to save %s" % path)
		return false
	return true


func _ensure_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


func _set_out(bb: String) -> void:
	if _out != null:
		_out.text = bb


func _warn(msg: String) -> void:
	_set_out("[color=#ffd24d]" + msg + "[/color]")
