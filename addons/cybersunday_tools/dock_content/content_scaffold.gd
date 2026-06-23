@tool
extends RefCounted

## PURE content scaffolders for the CYBER SUNDAY "Content" dock — one static builder per generator
## (Quest / NpcData archetype / Weapon+Item pair / Faction / DialogueResource). Every function returns a
## freshly-built, sensibly-seeded Resource (or a Dictionary of them) and does NOTHING ELSE: no EditorInterface,
## no ResourceSaver, no scene-tree, no file I/O. The dock (content_dock.gd) owns all the editor glue (validate
## name -> call a builder here -> ResourceSaver.save -> rescan -> open). Keeping these pure is what lets the GUT
## suite exercise them headless (an EditorInterface call would crash a headless test).
##
## The seeds match the project's designer-first idiom: each .tres comes out VALID and editable, with the
## drift-prone ids pre-filled (a Quest's id == its filename, a Faction's id == its filename) so the designer
## only tweaks values, never re-derives the wiring. NO `uid://` is ever hand-written — the dock's ResourceSaver
## .save mints the uid at runtime.

const RAIDER_FACTION := "raiders"          ## valid id on disk (resources/factions/raiders.tres)
const TOWN_FACTION := "townsfolk"          ## valid id on disk (resources/factions/townsfolk.tres)


## A starter Quest: seeded id/title/description + a small money reward and N objectives. Always at least one
## objective (a FLAG objective is the simplest — no on-disk target registry needed). `objective_count` is
## clamped to >= 1. Each objective gets a stable, unique id ("obj_1".."obj_N") so advance_objective can address it.
static func build_quest(id: StringName, objective_count: int) -> Quest:
	var q := Quest.new()
	q.id = id
	q.title = _titleize(String(id))
	q.description = "TODO: describe the quest \"%s\"." % _titleize(String(id))
	q.reward_money = 100.0
	q.reward_xp = 50.0
	var n := maxi(1, objective_count)
	var objs: Array[QuestObjective] = []
	for i in n:
		var o := QuestObjective.new()
		o.id = StringName("obj_%d" % (i + 1))
		o.type = QuestObjective.Type.FLAG  # default-friendly: a story flag, no NPC/item target to wire up yet
		o.target_id = StringName("flag_%s_%d" % [String(id), i + 1])
		o.description = "TODO: objective %d." % (i + 1)
		o.required_count = 1
		objs.append(o)
	q.objectives = objs
	return q


## A starter NpcData archetype for one of four presets (raider / townsperson / sniper / shopkeeper). Sets the
## faction_id (a valid id on disk) and the key Perception / threat fields per preset, and equips `weapon`.
## CRITICAL (NpcData's EITHER/OR rule): we set faction_id XOR faction — only faction_id is touched, the
## `faction` resource slot is left null. Setting both would be ambiguous (the dropdown id wins, but a stray
## resource invites confusion), so we never do.
static func build_npc(preset: String, weapon: WeaponData) -> NpcData:
	var d := NpcData.new()
	d.weapon_data = weapon
	# faction_id ONLY — never also set d.faction (the either/or rule). d.faction stays null by default.
	match preset:
		"raider":
			d.display_name = "Raider"
			d.faction_id = RAIDER_FACTION
			d.threat_response = 0  # Fight
			d.max_hp = 12.0
			d.sight_range = 28.0
			d.fov_degrees = 120.0
			d.move_speed = 4.5
			d.temperament = 0.2
		"townsperson":
			d.display_name = "Townsperson"
			d.faction_id = TOWN_FACTION
			d.threat_response = 1  # Flee — civilians run, never fire
			d.max_hp = 8.0
			d.sight_range = 22.0
			d.fov_degrees = 110.0
			d.move_speed = 3.5
			d.wanders = true
			d.temperament = 1.0
		"sniper":
			d.display_name = "Sniper"
			d.faction_id = RAIDER_FACTION
			d.threat_response = 0  # Fight
			d.max_hp = 10.0
			d.sight_range = 45.0   # eagle-eyed: long sight + tight cone
			d.fov_degrees = 70.0
			d.time_to_detect = 0.6
			d.move_speed = 3.5
			d.engage_range_fraction = 0.95  # holds at distance
			d.temperament = 0.1
		"shopkeeper":
			d.display_name = "Shopkeeper"
			d.faction_id = TOWN_FACTION
			d.threat_response = 1  # Flee
			d.max_hp = 10.0
			d.sight_range = 18.0
			d.fov_degrees = 110.0
			d.move_speed = 3.0
			d.wanders = false
			d.temperament = 1.0
		_:
			d.display_name = preset.capitalize() if not preset.is_empty() else "NPC"
			d.faction_id = TOWN_FACTION
			d.threat_response = 1
	return d


## A matched Weapon + Item pair. Returns { "weapon": WeaponData, "item": Item } where item.category == WEAPON,
## item.weapon points AT the returned weapon (the cross-link the equip pipeline reads), and the item's caliber
## mirrors the weapon's so an ammo item authored later lines up. The ids derive from `name` so the pair stays
## addressable. `name` is sanitised to a snake_case base.
static func build_weapon_and_item(name: String) -> Dictionary:
	var base := _slugify(name)
	if base.is_empty():
		base = "weapon"
	var caliber := StringName(base)  # a fresh caliber named after the weapon — author its ammo Item next
	var w := WeaponData.new()
	w.damage = 1.0
	w.attack_speed = 0.3
	w.effective_range = 25.0
	w.max_ammo = 12
	w.caliber = caliber
	var it := Item.new()
	it.id = StringName(base)
	it.display_name = _titleize(name)
	it.category = Item.Category.WEAPON
	it.weapon = w               # the cross-link: a WEAPON item carries its WeaponData
	it.caliber = caliber        # mirror the weapon's caliber so matching ammo resolves
	it.max_stack = 1
	it.weight = 1.5
	it.value = 50.0
	it.grid_width = 2
	it.grid_height = 1
	return {"weapon": w, "item": it}


## A starter Faction whose id EQUALS the supplied id (so a designer's filename == registry key, the rule
## Reputation depends on). Neutral baseline disposition + an empty relations map for the designer to fill.
static func build_faction(id: StringName) -> Faction:
	var f := Faction.new()
	f.id = id
	f.display_name = _titleize(String(id))
	f.default_disposition = Disposition.Kind.NEUTRAL
	f.relations = {}
	return f


## A starter conversation: a DialogueResource seeded with a greeting line and a goodbye line (2 lines), each a
## linear line (no choices) so it plays back top-to-bottom immediately and the designer just edits the text.
static func build_dialogue(id: StringName) -> DialogueResource:
	var dr := DialogueResource.new()
	var greeting := DialogueLine.new()
	greeting.text = "Hello there. (TODO: write %s's greeting.)" % _titleize(String(id))
	var goodbye := DialogueLine.new()
	goodbye.text = "Safe travels. (TODO: write the goodbye.)"
	var lines: Array[DialogueLine] = [greeting, goodbye]
	dr.lines = lines
	return dr


# --- helpers (pure) --------------------------------------------------------------------------------------------

## "raider_camp" / "Raider Camp" -> "Raider Camp" (a display-friendly Title Case from any id/name spelling).
static func _titleize(s: String) -> String:
	var cleaned := s.strip_edges().replace("_", " ").replace("-", " ")
	if cleaned.is_empty():
		return s.strip_edges()
	return cleaned.capitalize()

## "Plasma Rifle!" -> "plasma_rifle" (a file-safe snake_case base for ids/calibers; strips non-alphanumerics).
static func _slugify(s: String) -> String:
	var out := ""
	var prev_us := false
	for ch in s.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
			prev_us = false
		elif not prev_us and not out.is_empty():
			out += "_"
			prev_us = true
	return out.trim_suffix("_")
