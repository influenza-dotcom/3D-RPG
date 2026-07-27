@tool
extends VBoxContainer

## CONTENT GENERATORS dock: one-click .tres scaffolders for every content type — New Quest, New NPC archetype,
## New Weapon+Item pair, New Item (consumable/junk), New Faction, New Dialogue, New LootTable, New Perk, New
## StatusEffect, plus the world/NPC content: New Encounter (SpawnDefinition), New Schedule, New Cutscene, New
## BarkSet, New Loadout, New Grapple (GrappleHookResource), New Map (MapData), New Throwable (ThrowableData). Each row is a name LineEdit + a
## Button (the NPC and Item rows also carry a kind OptionButton); pressing the button validates the name, calls the
## matching PURE builder in content_scaffold.gd, ResourceSaver.saves the result into the right res:// folder REFUSING
## to overwrite (the level_dock _make_level idiom), rescans the FileSystem, and opens the new resource in the
## inspector. All the seeding logic lives in content_scaffold.gd (pure + GUT-tested); this file is editor glue.
## The rows live in a ScrollContainer so the full generator list never overflows a short bottom panel.

const Scaffold := preload("res://addons/cybersunday_tools/dock_content/content_scaffold.gd")

const QUESTS_DIR := "res://resources/quests/"
const NPC_DIR := "res://resources/characters/"
const WEAPONS_DIR := "res://resources/weapons/"
const ITEMS_DIR := "res://resources/items/"
const FACTIONS_DIR := "res://resources/factions/"
const DIALOGUE_DIR := "res://resources/dialogue/"
const LOOT_DIR := "res://resources/loot/"
const PERKS_DIR := "res://resources/perks/"
const STATUS_DIR := "res://resources/status/"
const ENCOUNTERS_DIR := "res://resources/encounters/"
const SCHEDULES_DIR := "res://resources/schedules/"
const CUTSCENES_DIR := "res://resources/cutscenes/"
const BARKS_DIR := "res://resources/barks/"
const LOADOUTS_DIR := "res://resources/loadouts/"
const ABILITIES_DIR := "res://resources/abilities/"  # GrappleHookResource lives here (resources/abilities/)
const MAPS_DIR := "res://resources/maps/"            # MapData lives here; UI skins/boot quotes stay in resources/ui/
const THROWABLES_DIR := "res://resources/interactables/"  # ThrowableData lives here (wooden_crate.tres, gore_gib_data.tres)

const NPC_PRESETS := ["raider", "townsperson", "sniper", "shopkeeper"]
## The default weapon the NPC archetype is equipped with (a real weapon on disk).
const DEFAULT_NPC_WEAPON := "res://resources/weapons/pistol.tres"
## The default enemy scene a New Encounter (SpawnDefinition) spawns — the designer can swap npc_scene afterward.
const DEFAULT_SPAWN_NPC := "res://scenes/characters/NPC.tscn"
## Item kinds the New Item row can scaffold (a WEAPON item is the separate New Weapon+Item generator).
const ITEM_KINDS := ["consumable", "junk"]

var _out: RichTextLabel = null
var _rows: VBoxContainer = null   ## the generator rows live here (inside a ScrollContainer) so the list can't overflow
var _quest_edit: LineEdit = null
var _npc_edit: LineEdit = null
var _npc_preset: OptionButton = null
var _weapon_edit: LineEdit = null
var _faction_edit: LineEdit = null
var _dialogue_edit: LineEdit = null
var _item_edit: LineEdit = null
var _item_kind: OptionButton = null
var _loot_edit: LineEdit = null
var _perk_edit: LineEdit = null
var _status_edit: LineEdit = null
var _encounter_edit: LineEdit = null
var _schedule_edit: LineEdit = null
var _cutscene_edit: LineEdit = null
var _bark_edit: LineEdit = null
var _loadout_edit: LineEdit = null
var _grapple_edit: LineEdit = null
var _map_edit: LineEdit = null
var _throwable_edit: LineEdit = null


func _init() -> void:
	name = "Content"
	add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Content Generators"
	add_child(title)

	# The generator rows live in a ScrollContainer (with an inner VBox _rows) so the full list — which grew past
	# what fits on a short display — never forces the bottom panel taller than the screen. The output label sits
	# BELOW the scroll, always visible.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 90)
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)

	_section("Core content")
	_quest_edit = _add_row("New Quest", "quest_id", _on_new_quest)
	_npc_edit = _add_npc_row()
	_weapon_edit = _add_row("New Weapon+Item", "weapon_name", _on_new_weapon)
	_item_edit = _add_item_row()
	_faction_edit = _add_row("New Faction", "faction_id", _on_new_faction)
	_dialogue_edit = _add_row("New Dialogue", "dialogue_id", _on_new_dialogue)
	_loot_edit = _add_row("New LootTable", "loot_id", _on_new_loot)
	_perk_edit = _add_row("New Perk", "perk_id", _on_new_perk)
	_status_edit = _add_row("New StatusEffect", "status_id", _on_new_status)

	_section("World & NPC content")
	_encounter_edit = _add_row("New Encounter", "encounter_id", _on_new_encounter)
	_schedule_edit = _add_row("New Schedule", "schedule_id", _on_new_schedule)
	_cutscene_edit = _add_row("New Cutscene", "cutscene_id", _on_new_cutscene)
	_bark_edit = _add_row("New BarkSet", "bark_id", _on_new_bark)
	_loadout_edit = _add_row("New Loadout", "loadout_id", _on_new_loadout)
	_grapple_edit = _add_row("New Grapple", "grapple_id", _on_new_grapple)
	_map_edit = _add_row("New Map", "map_id", _on_new_map)
	_throwable_edit = _add_row("New Throwable", "throwable_id", _on_new_throwable)

	add_child(HSeparator.new())
	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.scroll_active = true
	_out.selection_enabled = true
	_out.custom_minimum_size = Vector2(0, 90)  # small floor; the scroll above takes the vertical slack
	_out.text = "[i]Type a name, then click a generator to scaffold a .tres.[/i]"
	add_child(_out)


## A dim section header inside the rows VBox — groups the generators into "Core content" / "World & NPC content".
func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.6)
	_rows.add_child(l)


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
	_rows.add_child(row)
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
	_rows.add_child(row)
	return edit


## The Item row: name LineEdit + a kind OptionButton (consumable / junk) + the generator Button.
func _add_item_row() -> LineEdit:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.placeholder_text = "item_id"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	_item_kind = OptionButton.new()
	for k in ITEM_KINDS:
		_item_kind.add_item(k)
	row.add_child(_item_kind)
	var b := Button.new()
	b.text = "New Item"
	b.pressed.connect(_on_new_item)
	row.add_child(b)
	_rows.add_child(row)
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
	# Give the weapon's Item an id matching its <base>_item.tres filename, so it can't collide with a plain Item
	# named `base` (items/<base>.tres). Two Items sharing an id silently shadow each other in ItemDb's registry
	# (last write wins). Set AFTER `base`/paths are derived above and the weapon is linked by path — neither uses id.
	item.id = StringName(base + "_item")
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

func _on_new_item() -> void:
	var nm := _validated(_item_edit)
	if nm.is_empty():
		return
	var consumable := true  # the default kind (index 0)
	if _item_kind != null and _item_kind.selected >= 0:
		consumable = String(ITEM_KINDS[_item_kind.selected]) == "consumable"
	var item := Scaffold.build_item(nm, consumable)
	_save_and_open(ITEMS_DIR, String(item.id), item)

func _on_new_loot() -> void:
	var id := _validated(_loot_edit)
	if id.is_empty():
		return
	_save_and_open(LOOT_DIR, id, Scaffold.build_loot_table())

func _on_new_perk() -> void:
	var id := _validated(_perk_edit)
	if id.is_empty():
		return
	_save_and_open(PERKS_DIR, id, Scaffold.build_perk(StringName(id)))

func _on_new_status() -> void:
	var id := _validated(_status_edit)
	if id.is_empty():
		return
	_save_and_open(STATUS_DIR, id, Scaffold.build_status_effect(StringName(id)))

func _on_new_encounter() -> void:
	var id := _validated(_encounter_edit)
	if id.is_empty():
		return
	# The dock loads the default enemy scene and passes it in (the builder stays pure / disk-free). null is fine —
	# the SpawnDefinition is just inert until the designer assigns npc_scene.
	var npc_scene := load(DEFAULT_SPAWN_NPC) as PackedScene
	_save_and_open(ENCOUNTERS_DIR, id, Scaffold.build_spawn_definition(npc_scene))

func _on_new_schedule() -> void:
	var id := _validated(_schedule_edit)
	if id.is_empty():
		return
	_save_and_open(SCHEDULES_DIR, id, Scaffold.build_schedule())

func _on_new_cutscene() -> void:
	var id := _validated(_cutscene_edit)
	if id.is_empty():
		return
	_save_and_open(CUTSCENES_DIR, id, Scaffold.build_cutscene())

func _on_new_bark() -> void:
	var id := _validated(_bark_edit)
	if id.is_empty():
		return
	_save_and_open(BARKS_DIR, id, Scaffold.build_bark_set())

func _on_new_loadout() -> void:
	var id := _validated(_loadout_edit)
	if id.is_empty():
		return
	_save_and_open(LOADOUTS_DIR, id, Scaffold.build_loadout())

func _on_new_grapple() -> void:
	var id := _validated(_grapple_edit)
	if id.is_empty():
		return
	_save_and_open(ABILITIES_DIR, id, Scaffold.build_grapple_resource())

func _on_new_map() -> void:
	var id := _validated(_map_edit)
	if id.is_empty():
		return
	_save_and_open(MAPS_DIR, id, Scaffold.build_map_data())

func _on_new_throwable() -> void:
	var id := _validated(_throwable_edit)
	if id.is_empty():
		return
	_save_and_open(THROWABLES_DIR, id, Scaffold.build_throwable(id))


# --- save / validate -------------------------------------------------------------------------------------------

## Validate the LineEdit's text and return a file-safe SLUGIFIED id (snake_case), or "" (after warning) if the
## raw text is empty. The single name gate — every generator gets an id==filename slug (matching Item/Weapon),
## so non-item generators no longer pass raw display text as both id and filename.
func _validated(edit: LineEdit) -> String:
	if edit == null:
		return ""
	var raw := edit.text.strip_edges()
	if raw.is_empty():
		_warn("Type a name first.")
		return ""
	return Scaffold._slugify(raw)


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
