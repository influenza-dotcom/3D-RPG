@tool
extends VBoxContainer

## CONTENT GENERATORS dock: one-click .tres scaffolders for the five core content types — New Quest, New NPC
## archetype, New Weapon+Item pair, New Faction, New Dialogue. Each row is a name LineEdit + a Button (the NPC
## row also carries a preset OptionButton); pressing the button validates the name, calls the matching PURE
## builder in content_scaffold.gd, ResourceSaver.saves the result into the right res:// folder REFUSING to
## overwrite (the level_dock _make_level idiom), rescans the FileSystem, and opens the new resource in the
## inspector. All the seeding logic lives in content_scaffold.gd (pure + GUT-tested); this file is editor glue.

const Scaffold := preload("res://addons/cybersunday_tools/dock_content/content_scaffold.gd")

const QUESTS_DIR := "res://resources/quests/"
const NPC_DIR := "res://resources/characters/"
const WEAPONS_DIR := "res://resources/weapons/"
const ITEMS_DIR := "res://resources/items/"
const FACTIONS_DIR := "res://resources/factions/"
const DIALOGUE_DIR := "res://resources/dialogue/"

const NPC_PRESETS := ["raider", "townsperson", "sniper", "shopkeeper"]
## The default weapon the NPC archetype is equipped with (a real weapon on disk).
const DEFAULT_NPC_WEAPON := "res://resources/weapons/pistol.tres"

var _out: RichTextLabel = null
var _quest_edit: LineEdit = null
var _npc_edit: LineEdit = null
var _npc_preset: OptionButton = null
var _weapon_edit: LineEdit = null
var _faction_edit: LineEdit = null
var _dialogue_edit: LineEdit = null


func _init() -> void:
	name = "Content"
	add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Content Generators"
	add_child(title)

	_quest_edit = _add_row("New Quest", "quest_id", _on_new_quest)
	_npc_edit = _add_npc_row()
	_weapon_edit = _add_row("New Weapon+Item", "weapon_name", _on_new_weapon)
	_faction_edit = _add_row("New Faction", "faction_id", _on_new_faction)
	_dialogue_edit = _add_row("New Dialogue", "dialogue_id", _on_new_dialogue)

	add_child(HSeparator.new())
	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.scroll_active = true
	_out.selection_enabled = true
	_out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_out.custom_minimum_size = Vector2(0, 90)  # small floor so the dock can shrink on a short display
	_out.text = "[i]Type a name, then click a generator to scaffold a .tres.[/i]"
	add_child(_out)


## A name LineEdit + a generator Button on one row. Returns the LineEdit so the handler can read it.
func _add_row(button_text: String, placeholder: String, handler: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var b := Button.new()
	b.text = button_text
	b.pressed.connect(handler)
	row.add_child(b)
	add_child(row)
	return edit


## The NPC row: name LineEdit + a preset OptionButton + the generator Button.
func _add_npc_row() -> LineEdit:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.placeholder_text = "npc_id"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	_npc_preset = OptionButton.new()
	for p in NPC_PRESETS:
		_npc_preset.add_item(p)
	row.add_child(_npc_preset)
	var b := Button.new()
	b.text = "New NPC"
	b.pressed.connect(_on_new_npc)
	row.add_child(b)
	add_child(row)
	return edit


# --- handlers --------------------------------------------------------------------------------------------------

func _on_new_quest() -> void:
	var id := _validated(_quest_edit)
	if id.is_empty():
		return
	_save_and_open(QUESTS_DIR, id, Scaffold.build_quest(StringName(id), 1))

func _on_new_npc() -> void:
	var id := _validated(_npc_edit)
	if id.is_empty():
		return
	var preset := String(NPC_PRESETS[0])
	if _npc_preset != null and _npc_preset.selected >= 0:
		preset = String(NPC_PRESETS[_npc_preset.selected])
	var weapon := load(DEFAULT_NPC_WEAPON) as WeaponData  # null is fine — an unarmed archetype
	_save_and_open(NPC_DIR, id, Scaffold.build_npc(preset, weapon))

func _on_new_weapon() -> void:
	var nm := _validated(_weapon_edit)
	if nm.is_empty():
		return
	var pair := Scaffold.build_weapon_and_item(nm)
	var weapon: WeaponData = pair["weapon"]
	var item: Item = pair["item"]
	var base := String(item.id)
	# Both files share the base name; refuse if EITHER exists, then save the weapon first so the item resolves it.
	var weapon_path := WEAPONS_DIR + base + ".tres"
	var item_path := ITEMS_DIR + base + "_item.tres"
	if FileAccess.file_exists(weapon_path) or FileAccess.file_exists(item_path):
		_warn("'%s' already exists (weapon or item) — pick another name." % base)
		return
	_ensure_dir(WEAPONS_DIR)
	_ensure_dir(ITEMS_DIR)
	if ResourceSaver.save(weapon, weapon_path) != OK:
		_warn("Failed to save %s" % weapon_path)
		return
	item.weapon = load(weapon_path)  # re-link to the SAVED weapon so the item .tres references it by path
	if ResourceSaver.save(item, item_path) != OK:
		_warn("Failed to save %s" % item_path)
		return
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.edit_resource(load(item_path))
	_set_out("[color=lime]Created[/color] %s + %s\nThe item carries the weapon; author its ammo Item with caliber [b]%s[/b] so it can reload." % [weapon_path, item_path, String(weapon.caliber)])

func _on_new_faction() -> void:
	var id := _validated(_faction_edit)
	if id.is_empty():
		return
	_save_and_open(FACTIONS_DIR, id, Scaffold.build_faction(StringName(id)))

func _on_new_dialogue() -> void:
	var id := _validated(_dialogue_edit)
	if id.is_empty():
		return
	_save_and_open(DIALOGUE_DIR, id, Scaffold.build_dialogue(StringName(id)))


# --- save / validate -------------------------------------------------------------------------------------------

## Strip + return the LineEdit's text, or "" (after warning) if it's empty. The single name gate.
func _validated(edit: LineEdit) -> String:
	if edit == null:
		return ""
	var nm := edit.text.strip_edges()
	if nm.is_empty():
		_warn("Type a name first.")
	return nm


## Save `res` to <dir>/<name>.tres, REFUSING to overwrite (the level_dock dupe-guard), then rescan + open it.
func _save_and_open(dir: String, name_: String, res: Resource) -> void:
	var path := dir + name_ + ".tres"
	if FileAccess.file_exists(path):
		_warn("'%s' already exists at %s — pick another name." % [name_, path])
		return
	_ensure_dir(dir)
	if ResourceSaver.save(res, path) != OK:
		_warn("Failed to save %s" % path)
		return
	EditorInterface.get_resource_filesystem().scan()  # so the new file shows up in the FileSystem dock immediately
	EditorInterface.edit_resource(load(path))          # open it in the inspector, ready to tweak
	_set_out("[color=lime]Created[/color] %s — opened in the inspector. Fill in the TODO fields." % path)


## Create the target folder if it doesn't exist yet (resources/quests/ isn't on disk in a fresh project, and
## ResourceSaver.save won't auto-create a missing dir). res:// paths are valid for DirAccess here.
func _ensure_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


# --- output ----------------------------------------------------------------------------------------------------

func _set_out(bb: String) -> void:
	if _out != null:
		_out.text = bb

func _warn(msg: String) -> void:
	_set_out("[color=#ffd24d]" + msg + "[/color]")
