@tool
extends VBoxContainer

## The NEW tab (Control name "Content" — pinned by cyber_panel's handoff registry; the painted title "New" is set by
## cyber_panel with set_tab_title). One-click scaffolders for every content type: New Quest, New NPC Archetype, New
## Weapon+Item pair, New Item (consumable/junk), New Faction, New Dialogue, New Loot Table, New Perk, New Status
## Effect, plus the world/NPC content: New Encounter (SpawnDefinition), New Schedule, New Cutscene, New Bark Set, New
## Loadout, New Grapple (GrappleHookResource), New Map (MapData), New Throwable (ThrowableData). Each row is a name
## LineEdit + a Button (the NPC and Item rows also carry a kind OptionButton); pressing the button validates the
## name, calls the matching PURE builder in content_scaffold.gd, ResourceSaver.saves the result into the right res://
## folder REFUSING to overwrite (the level_dock _make_level idiom), rescans the FileSystem, opens the new resource in
## the Inspector, clears the name box and arms the Edit button. Edit hands the file to the tab that edits it
## (Quest -> Quests, DialogueResource -> Dialogue, LootTable -> Loot, NpcData -> Place) through core/host.gd; a type
## with no editor tab (Item, WeaponData, Faction, ...) opens in the Inspector instead. All the seeding logic lives in
## content_scaffold.gd (pure + GUT-tested); this file is editor glue.
##
## HEIGHT CONTRACT: the generator rows live INSIDE a ScrollContainer with a small height floor; only the status row
## (the one status Label + Edit) sits outside it. The bottom panel's inner TabContainer takes its minimum from the
## CURRENT tab, and the editor's bottom splitter keeps whatever height it grew to — so a tab whose minimum is tall
## (seventeen bare rows) would push the whole panel up the screen and it would stay there. Scrolling the rows keeps
## this tab's minimum at the scroll's 90 px floor plus the two-line status row.
##
## OFF-TREE: GUT and the headless probe construct this tab bare (.new(), no parent, no tree), so _init builds widgets
## only — every EditorInterface call lives in a button handler, which is in-tree by definition.

const Scaffold := preload("res://addons/cybersunday_tools/dock_content/content_scaffold.gd")
const Host := preload("res://addons/cybersunday_tools/core/host.gd")

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

## Builder keys for the NPC preset dropdown (content_scaffold.build_npc matches on these); the designer reads them
## titleized ("Raider"), the handler maps the picked index back to the key.
const NPC_PRESETS := ["raider", "townsperson", "sniper", "shopkeeper"]
## The default weapon the NPC archetype is equipped with (a real weapon on disk).
const DEFAULT_NPC_WEAPON := "res://resources/weapons/pistol.tres"
## The default enemy scene a New Encounter (SpawnDefinition) spawns — the designer can swap npc_scene afterward.
const DEFAULT_SPAWN_NPC := "res://scenes/characters/NPC.tscn"
## Item kinds the New Item row can scaffold (a WEAPON item is the separate New Weapon+Item generator).
const ITEM_KINDS := ["consumable", "junk"]

## The idle status — one imperative next step.
const IDLE_TEXT := "Type a name, then press a generator -- it writes one new file and opens it."
## Amber for refusals ("Couldn't ..."), applied as a font_color theme override on the status Label — never bbcode,
## so a file name in the text renders literally.
const REFUSED_COLOR := Color(1.0, 0.82, 0.3)
## Floor width for the two kind dropdowns (see _guard_picker) — wide enough for "Townsperson" at the editor font.
const KIND_PICKER_MIN_WIDTH := 120.0

var _out: Label = null            ## the ONE status Label (created / refused / opened); Edit sits beside it
var _edit_btn: Button = null      ## hands _last_saved_path to its editor tab; disabled until a generator succeeds
var _last_saved_path: String = "" ## the file the most recent successful generator wrote — the Edit target
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

	# The generator rows live in a ScrollContainer (with an inner VBox _rows) — see the HEIGHT CONTRACT in the header.
	# The status row (the one status Label + Edit) sits BELOW the scroll, outside it, so it stays visible whatever
	# is scrolled.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 90)
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)

	# Every tooltip is "<what it makes> -> <folder>. Writes N file(s)." — the seeds are described in
	# content_scaffold.gd's builder doc comments; keep the two in step when a seed changes.
	_section("Core content")
	_quest_edit = _add_row("New Quest", "Quest name (e.g. Clear the Block)",
		"New Quest: a quest with one placeholder objective -> resources/quests/. Writes one file.", _on_new_quest)
	_npc_edit = _add_npc_row("New NPC Archetype: an NPC template from the chosen preset (Raider, Townsperson, Sniper or Shopkeeper), armed with the pistol -> resources/characters/. Writes one file.")
	_weapon_edit = _add_row("New Weapon+Item", "Weapon name (e.g. Shotgun)",
		"New Weapon+Item: a weapon balance card plus the inventory item that carries it -> resources/weapons/ and resources/items/. Writes two files.", _on_new_weapon)
	_item_edit = _add_item_row("New Item: a consumable that heals, or an inert junk item, ready to place or loot -> resources/items/. Writes one file.")
	_faction_edit = _add_row("New Faction", "Faction name (e.g. Dockers)",
		"New Faction: a neutral faction with no relations yet (set them in Factions) -> resources/factions/. Writes one file.", _on_new_faction)
	_dialogue_edit = _add_row("New Dialogue", "Conversation name (e.g. Guard Greeting)",
		"New Dialogue: a two-line conversation (greeting, goodbye) with no choices yet -> resources/dialogue/. Writes one file.", _on_new_dialogue)
	_loot_edit = _add_row("New Loot Table", "Loot table name (e.g. Raider Drops)",
		"New Loot Table: an empty loot table, valid to roll, with drop rows to add in Loot -> resources/loot/. Writes one file.", _on_new_loot)
	_perk_edit = _add_row("New Perk", "Perk name (e.g. Steady Hands)",
		"New Perk: an unlockable perk with no bonuses yet -> resources/perks/. Writes one file.", _on_new_perk)
	_status_edit = _add_row("New Status Effect", "Status effect name (e.g. Poisoned)",
		"New Status Effect: a 5-second buff/debuff that changes nothing until you set its damage or speed -> resources/status/. Writes one file.", _on_new_status)

	_section("World & NPC content")
	_encounter_edit = _add_row("New Encounter", "Encounter name (e.g. Alley Ambush)",
		"New Encounter: a spawn wave of three NPCs that attack on sight, for an EncounterSpawner -> resources/encounters/. Writes one file.", _on_new_encounter)
	_schedule_edit = _add_row("New Schedule", "Schedule name (e.g. Market Trader)",
		"New Schedule: a daily routine, market by day and home by night (drop a Marker3D into each group) -> resources/schedules/. Writes one file.", _on_new_schedule)
	_cutscene_edit = _add_row("New Cutscene", "Cutscene name (e.g. Intro)",
		"New Cutscene: a caption then a toast, for a CutscenePlayer to run in order -> resources/cutscenes/. Writes one file.", _on_new_cutscene)
	_bark_edit = _add_row("New Bark Set", "Bark set name (e.g. Raider Barks)",
		"New Bark Set: one placeholder spot line and one hurt line; every other category keeps the NPC's built-in lines -> resources/barks/. Writes one file.", _on_new_bark)
	_loadout_edit = _add_row("New Loadout", "Loadout name (e.g. Starter Kit)",
		"New Loadout: a player starting kit with no weapons yet, 4 spare clips and 100 zorkmids -> resources/loadouts/. Writes one file.", _on_new_loadout)
	_grapple_edit = _add_row("New Grapple", "Grapple name (e.g. Long Rope)",
		"New Grapple: grapple-hook feel settings -> resources/abilities/. Writes one file.", _on_new_grapple)
	_map_edit = _add_row("New Map", "Map name (e.g. Downtown)",
		"New Map: map data for a level, ready for a top-down picture and its bounds -> resources/maps/. Writes one file.", _on_new_map)
	_throwable_edit = _add_row("New Throwable", "Throwable name (e.g. Oil Drum)",
		"New Throwable: a breakable crate's stats (hit points, mass) for a Throwable -> resources/interactables/. Writes one file.", _on_new_throwable)

	add_child(HSeparator.new())
	# The fixed status row: the status Label takes the width, Edit sits beside it. Both stay outside the scroll.
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	add_child(status_row)
	# The ONE status Label, built like every other tab's: two lines on screen with the WHOLE text mirrored into the
	# tooltip on every write (see _status / _refuse), so the longest "Created ..." line can never push the generator
	# rows off a short bottom panel. A plain Label, not a RichTextLabel: it needs no markup (a file name must render
	# literally) and max_lines_visible is what caps the height — a RichTextLabel has no such cap, so it needed a
	# hard pixel floor that ate 48 px even while the status was one short line.
	_out = Label.new()
	_out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_out.max_lines_visible = 2
	_out.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_out.modulate = Color(1, 1, 1, 0.75)
	status_row.add_child(_out)
	_edit_btn = Button.new()
	_edit_btn.text = "Edit"
	_edit_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_edit_btn.pressed.connect(_on_edit_pressed)
	status_row.add_child(_edit_btn)
	_disarm_edit()
	_status(IDLE_TEXT)


## A dim section header inside the rows VBox — groups the generators into "Core content" / "World & NPC content".
func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = Color(1, 1, 1, 0.6)
	_rows.add_child(l)


## A name LineEdit + a generator Button on one row. `tooltip` is the button's (what it makes -> folder; what it
## writes). Returns the LineEdit so the handler can read it.
func _add_row(button_text: String, placeholder: String, tooltip: String, handler: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var b := Button.new()
	b.text = button_text
	b.tooltip_text = tooltip
	b.pressed.connect(handler)
	row.add_child(b)
	_rows.add_child(row)
	return edit


## The NPC row: name LineEdit + a preset OptionButton + the generator Button (tooltip = `tooltip`).
func _add_npc_row(tooltip: String) -> LineEdit:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.placeholder_text = "Archetype name (e.g. Raider)"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	_npc_preset = OptionButton.new()
	for p in NPC_PRESETS:
		_npc_preset.add_item(Scaffold.titleize(String(p)))  # "raider" is the builder key; the designer reads "Raider"
	_guard_picker(_npc_preset)
	row.add_child(_npc_preset)
	var b := Button.new()
	b.text = "New NPC Archetype"
	b.tooltip_text = tooltip
	b.pressed.connect(_on_new_npc)
	row.add_child(b)
	_rows.add_child(row)
	return edit


## The Item row: name LineEdit + a kind OptionButton (Consumable / Junk) + the generator Button (tooltip = `tooltip`).
func _add_item_row(tooltip: String) -> LineEdit:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.placeholder_text = "Item name (e.g. Medkit)"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	_item_kind = OptionButton.new()
	for k in ITEM_KINDS:
		_item_kind.add_item(Scaffold.titleize(String(k)))  # "consumable" is the builder key; the designer reads "Consumable"
	_guard_picker(_item_kind)
	row.add_child(_item_kind)
	var b := Button.new()
	b.text = "New Item"
	b.tooltip_text = tooltip
	b.pressed.connect(_on_new_item)
	row.add_child(b)
	_rows.add_child(row)
	return edit


## The PickerRows.apply width guards, applied by hand because these two kind dropdowns have no "(none)" row (a
## preset is always chosen, so the rows model doesn't fit). fit_to_longest_item defaults TRUE and would grow the
## row — and, through the scroll's disabled horizontal scroll, the whole panel — to the longest label; with
## clip_text the button's own text leaves its minimum, so the floor is what keeps it readable.
func _guard_picker(btn: OptionButton) -> void:
	btn.fit_to_longest_item = false
	btn.clip_text = true
	btn.custom_minimum_size = Vector2(KIND_PICKER_MIN_WIDTH, 0)


# --- handlers --------------------------------------------------------------------------------------------------

func _on_new_quest() -> void:
	var id := _validated(_quest_edit, "Quest")
	if id.is_empty():
		return
	var quest := Scaffold.build_quest(StringName(id), 1)
	var path := _create_file(QUESTS_DIR, id, quest, _quest_edit)
	if path.is_empty():
		return
	# The seeded objective is a FLAG objective (content_scaffold.build_quest), so the quest cannot advance until
	# something sets that story flag. Say so here: the Audit tab reports the unset flag as a dead gate, and a designer
	# who only saw "Created" would read that finding as a bug.
	var flag := ""
	if not quest.objectives.is_empty():
		var first: QuestObjective = quest.objectives[0]
		flag = String(first.target_id)
	_status("Created %s. Its first objective waits on story flag %s -- set it from a conversation choice (Dialogue -> Set flag) or a TriggerVolume; Audit lists it as a dead gate until you do. Press Edit to open it in Quests." % [path.get_file(), flag])

func _on_new_npc() -> void:
	var id := _validated(_npc_edit, "NPC Archetype")
	if id.is_empty():
		return
	var preset := String(NPC_PRESETS[0])
	if _npc_preset != null and _npc_preset.selected >= 0:
		preset = String(NPC_PRESETS[_npc_preset.selected])
	var weapon := load(DEFAULT_NPC_WEAPON) as WeaponData  # null is fine — an unarmed archetype
	_save_and_open(NPC_DIR, id, Scaffold.build_npc(preset, weapon), _npc_edit)

func _on_new_weapon() -> void:
	var nm := _validated(_weapon_edit, "Weapon")
	if nm.is_empty():
		return
	var pair := Scaffold.build_weapon_and_item(nm)
	var weapon: WeaponData = pair["weapon"]
	var item: Item = pair["item"]
	var base := String(item.id)
	# Both files share the base name; refuse if EITHER exists, then save the weapon first so the item resolves it.
	var weapon_path := WEAPONS_DIR + base + ".tres"
	var item_path := ITEMS_DIR + base + "_item.tres"
	if FileAccess.file_exists(weapon_path):
		_refuse_exists(weapon_path)
		return
	if FileAccess.file_exists(item_path):
		_refuse_exists(item_path)
		return
	_ensure_dir(WEAPONS_DIR)
	_ensure_dir(ITEMS_DIR)
	var err := ResourceSaver.save(weapon, weapon_path)
	if err != OK:
		_refuse("Couldn't save %s: %s. Nothing was written." % [weapon_path.get_file(), error_string(err)])
		return
	item.weapon = load(weapon_path)  # re-link to the SAVED weapon so the item .tres references it by path
	# Give the weapon's Item an id matching its <base>_item.tres filename, so it can't collide with a plain Item
	# named `base` (items/<base>.tres). Two Items sharing an id silently shadow each other in ItemDb's registry
	# (last write wins). Set AFTER `base`/paths are derived above and the weapon is linked by path — neither uses id.
	item.id = StringName(base + "_item")
	err = ResourceSaver.save(item, item_path)
	if err != OK:
		# Half a pair is worse than none — a weapon with no item can't be picked up, equipped or placed — so roll the
		# weapon back and leave the disk as it was. Only if THAT fails does the status admit a stray file.
		var undo := DirAccess.remove_absolute(weapon_path)
		# Rescan either way: after a rollback the editor still holds the removed file in its cache, and after a
		# FAILED rollback the stray weapon is invisible in the FileSystem dock until a scan -- which is exactly the
		# dock the refusal below tells the designer to go and delete it from.
		EditorInterface.get_resource_filesystem().scan()
		if undo == OK:
			_refuse("Couldn't save %s: %s. Nothing was written -- %s was removed again." % [item_path.get_file(), error_string(err), weapon_path.get_file()])
		else:
			_refuse("Couldn't save %s: %s. %s was written on its own -- delete it, or pick another name." % [item_path.get_file(), error_string(err), weapon_path.get_file()])
		return
	EditorInterface.get_resource_filesystem().scan()
	# The WeaponData is the balance card (damage, rate, range, ammo) — the numbers a designer tunes first — so THAT is
	# what opens; the item is the wrapper that carries it. Edit re-opens the balance card too (no editor tab for it).
	EditorInterface.edit_resource(load(weapon_path))
	_arm_edit(weapon_path, _weapon_edit)
	_status("Created %s (balance card open in the Inspector) and %s -- the item carries this weapon. Give its ammo Item the caliber %s so it can reload." % [weapon_path.get_file(), item_path.get_file(), String(weapon.caliber)])

func _on_new_faction() -> void:
	var id := _validated(_faction_edit, "Faction")
	if id.is_empty():
		return
	_save_and_open(FACTIONS_DIR, id, Scaffold.build_faction(StringName(id)), _faction_edit)

func _on_new_dialogue() -> void:
	var id := _validated(_dialogue_edit, "Dialogue")
	if id.is_empty():
		return
	_save_and_open(DIALOGUE_DIR, id, Scaffold.build_dialogue(StringName(id)), _dialogue_edit)

func _on_new_item() -> void:
	var nm := _validated(_item_edit, "Item")
	if nm.is_empty():
		return
	var consumable := true  # the default kind (index 0)
	if _item_kind != null and _item_kind.selected >= 0:
		consumable = String(ITEM_KINDS[_item_kind.selected]) == "consumable"
	var item := Scaffold.build_item(nm, consumable)
	_save_and_open(ITEMS_DIR, String(item.id), item, _item_edit)

func _on_new_loot() -> void:
	var id := _validated(_loot_edit, "Loot Table")
	if id.is_empty():
		return
	_save_and_open(LOOT_DIR, id, Scaffold.build_loot_table(), _loot_edit)

func _on_new_perk() -> void:
	var id := _validated(_perk_edit, "Perk")
	if id.is_empty():
		return
	_save_and_open(PERKS_DIR, id, Scaffold.build_perk(StringName(id)), _perk_edit)

func _on_new_status() -> void:
	var id := _validated(_status_edit, "Status Effect")
	if id.is_empty():
		return
	_save_and_open(STATUS_DIR, id, Scaffold.build_status_effect(StringName(id)), _status_edit)

func _on_new_encounter() -> void:
	var id := _validated(_encounter_edit, "Encounter")
	if id.is_empty():
		return
	# The dock loads the default enemy scene and passes it in (the builder stays pure / disk-free). null is fine —
	# the SpawnDefinition is just inert until the designer assigns npc_scene.
	var npc_scene := load(DEFAULT_SPAWN_NPC) as PackedScene
	_save_and_open(ENCOUNTERS_DIR, id, Scaffold.build_spawn_definition(npc_scene), _encounter_edit)

func _on_new_schedule() -> void:
	var id := _validated(_schedule_edit, "Schedule")
	if id.is_empty():
		return
	_save_and_open(SCHEDULES_DIR, id, Scaffold.build_schedule(), _schedule_edit)

func _on_new_cutscene() -> void:
	var id := _validated(_cutscene_edit, "Cutscene")
	if id.is_empty():
		return
	_save_and_open(CUTSCENES_DIR, id, Scaffold.build_cutscene(), _cutscene_edit)

func _on_new_bark() -> void:
	var id := _validated(_bark_edit, "Bark Set")
	if id.is_empty():
		return
	_save_and_open(BARKS_DIR, id, Scaffold.build_bark_set(), _bark_edit)

func _on_new_loadout() -> void:
	var id := _validated(_loadout_edit, "Loadout")
	if id.is_empty():
		return
	_save_and_open(LOADOUTS_DIR, id, Scaffold.build_loadout(), _loadout_edit)

func _on_new_grapple() -> void:
	var id := _validated(_grapple_edit, "Grapple")
	if id.is_empty():
		return
	_save_and_open(ABILITIES_DIR, id, Scaffold.build_grapple_resource(), _grapple_edit)

func _on_new_map() -> void:
	var id := _validated(_map_edit, "Map")
	if id.is_empty():
		return
	_save_and_open(MAPS_DIR, id, Scaffold.build_map_data(), _map_edit)

func _on_new_throwable() -> void:
	var id := _validated(_throwable_edit, "Throwable")
	if id.is_empty():
		return
	_save_and_open(THROWABLES_DIR, id, Scaffold.build_throwable(id), _throwable_edit)


## Edit: hand the file the last generator wrote to the tab that edits it (core/host.gd routes Quest / Dialogue /
## LootTable / NpcData). When the host says no — a type with no editor tab, or a tab that could not find the file
## yet — the host has already opened it in the Inspector, and the status says which happened; with NO host at all
## (off-tree) this tab opens the Inspector itself.
func _on_edit_pressed() -> void:
	if _last_saved_path.is_empty():
		_refuse("Press a generator first -- Edit opens the file it creates.")
		return
	var file := _last_saved_path.get_file()
	if not ResourceLoader.exists(_last_saved_path):
		_refuse("Couldn't open %s: it is no longer on disk -- create it again." % file)
		_disarm_edit()
		return
	var res := load(_last_saved_path) as Resource
	if res == null:
		_refuse("Couldn't open %s -- reimport in progress? try again in a moment." % file)
		return
	var title := _editor_tab_title(res)
	if Host.open_in_editor(self, _last_saved_path):
		_status("Opened %s in %s." % [file, title])
		return
	# A host that returned false has ALREADY opened the Inspector itself (cyber_panel.open_in_editor's fallback), so
	# only the host-less case (off-tree) opens it here -- calling edit_resource twice would re-select the same
	# resource for no reason.
	if Host.find(self) == null:
		EditorInterface.edit_resource(res)
	if title.is_empty():
		_status("Opened %s in the Inspector -- this kind of file has no editor tab." % file)
	else:
		_status("Opened %s in the Inspector -- %s could not find it yet; press Refresh there and try Edit again." % [file, title])


# --- save / validate -------------------------------------------------------------------------------------------

## Validate the LineEdit's text and return a file-safe SLUGIFIED id (snake_case), or "" (after a refusal) when the
## raw text is empty or has no letter or digit to build a name from. The single name gate — every generator gets an
## id==filename slug (matching Item/Weapon), so non-item generators never pass raw display text as both id and filename.
## `thing` is what this row makes ("Loot Table"): seventeen rows share ONE status line, so a refusal that didn't name
## the row would leave the designer hunting for which button just complained.
func _validated(edit: LineEdit, thing: String) -> String:
	if edit == null:
		return ""
	var raw := edit.text.strip_edges()
	if raw.is_empty():
		_refuse("Couldn't create a %s: its name box is empty -- type a name first." % thing)
		return ""
	var slug := Scaffold.slugify(raw)
	if slug.is_empty():
		_refuse("Couldn't create a %s: the name '%s' needs at least one letter or digit." % [thing, raw])
		return ""
	return slug


## Save `res` as <dir>/<name>.tres, REFUSING to overwrite (the level_dock dupe-guard), then rescan the FileSystem,
## open the file in the Inspector, arm Edit and clear `edit` (the row's name box — so a second press cannot refuse
## with "already exists" over the name it just used). Returns the saved path, or "" after reporting why. The CALLER
## writes the success status, so a generator with more to say (New Quest's dead-gate note) can say it.
func _create_file(dir: String, name_: String, res: Resource, edit: LineEdit) -> String:
	var path := dir + name_ + ".tres"
	if FileAccess.file_exists(path):
		_refuse_exists(path)
		return ""
	_ensure_dir(dir)
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_refuse("Couldn't save %s: %s. Nothing was written." % [path.get_file(), error_string(err)])
		return ""
	EditorInterface.get_resource_filesystem().scan()  # so the new file shows up in the FileSystem dock immediately
	EditorInterface.edit_resource(load(path))          # open it in the Inspector, ready to tweak
	_arm_edit(path, edit)
	return path


## The common generator ending: _create_file + the standard "Created" status, with the Edit hint when the type has
## an editor tab. New Quest and New Weapon+Item call _create_file / _arm_edit directly and word their own.
func _save_and_open(dir: String, name_: String, res: Resource, edit: LineEdit) -> void:
	var path := _create_file(dir, name_, res, edit)
	if path.is_empty():
		return
	_status("Created %s -- opened in the Inspector. Fill in the TODO fields.%s" % [path.get_file(), _edit_hint(res)])


## "Couldn't create <file>: a file with that name already exists in <folder> -- pick another name."
func _refuse_exists(path: String) -> void:
	_refuse("Couldn't create %s: a file with that name already exists in %s -- pick another name." % [path.get_file(), path.get_base_dir().trim_prefix("res://")])


## Create the target folder if it doesn't exist yet (resources/quests/ isn't on disk in a fresh project, and
## ResourceSaver.save won't auto-create a missing dir). res:// paths are valid for DirAccess here.
func _ensure_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


# --- the Edit handoff ------------------------------------------------------------------------------------------

## Remember `path` as the Edit target, enable Edit (tooltip names the file) and clear the row's name box.
func _arm_edit(path: String, edit: LineEdit) -> void:
	_last_saved_path = path
	if edit != null:
		edit.text = ""
	if _edit_btn != null:
		_edit_btn.disabled = false
		_edit_btn.tooltip_text = "Open the file you just created in its editor tab (%s). Read-only." % path.get_file()


## No Edit target yet (fresh tab, or the last file vanished from disk): Edit is disabled and its tooltip says why.
func _disarm_edit() -> void:
	_last_saved_path = ""
	if _edit_btn != null:
		_edit_btn.disabled = true
		_edit_btn.tooltip_text = "Open the file you just created in its editor tab. Press a generator first."


## Designer-facing title of the tab that edits `res` — for PROSE only ("Press Edit to open it in Quests"). The real
## routing is cyber_panel.editor_tab_for plus its group table's painted titles; this mirrors those four so the status
## can name the destination without reaching into the panel's layout. "" = no editor tab; Edit opens the Inspector.
func _editor_tab_title(res: Resource) -> String:
	if res is Quest:
		return "Quests"
	if res is DialogueResource:
		return "Dialogue"
	if res is LootTable:
		return "Loot"
	if res is NpcData:
		return "Place"
	return ""


## " Press Edit to open it in <tab>." for a type with an editor tab, else "" (Edit would only re-open the Inspector).
func _edit_hint(res: Resource) -> String:
	var title := _editor_tab_title(res)
	if title.is_empty():
		return ""
	return " Press Edit to open it in %s." % title


# --- output ----------------------------------------------------------------------------------------------------

## Write the status in the normal colour and mirror it into the tooltip, so a line the two-line clamp cuts short can
## still be read in full on hover. Plain text — a file name renders literally.
func _status(text: String) -> void:
	if _out == null:
		return
	_out.remove_theme_color_override("font_color")
	_out.text = text
	_out.tooltip_text = text


## A refusal: the same status Label in amber. Every refusal reads "Couldn't <verb> <Name>: <plain reason>." (or the
## one-line guard "Type a name first.").
func _refuse(text: String) -> void:
	if _out == null:
		return
	_out.add_theme_color_override("font_color", REFUSED_COLOR)
	_out.text = text
	_out.tooltip_text = text
