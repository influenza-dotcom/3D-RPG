@tool
extends RefCounted

## PURE content scaffolders for the CYBER SUNDAY "Content" dock — one static builder per generator
## (Quest / NpcData archetype / Weapon+Item pair / Faction / DialogueResource / Item / LootTable / Perk /
## StatusEffect / SpawnDefinition / Schedule / Cutscene / BarkSet / Loadout / GrappleHookResource / MapData /
## ThrowableData).
## Every function returns a
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


## A starter NON-weapon Item — CONSUMABLE by default (the most useful seed: a health pack that heals), or MISC
## (junk) when `consumable` is false. Never WEAPON (use build_weapon_and_item for that — a weapon item needs a
## cross-linked WeaponData). The id == the slugified name so the filename matches the lookup key (the ItemDb
## rule). A consumable seeds a small heal_amount + a stack so it's immediately usable; junk stacks too but is
## inert. NO caliber / weapon / consumable_effect — those slots stay null/empty for the designer to add.
static func build_item(name: String, consumable: bool) -> Item:
	var base := _slugify(name)
	if base.is_empty():
		base = "item"
	var it := Item.new()
	it.id = StringName(base)
	it.display_name = _titleize(name)
	if consumable:
		it.category = Item.Category.CONSUMABLE
		it.description = "TODO: describe this consumable."
		it.heal_amount = 25.0
		it.max_stack = 5
		it.weight = 0.5
		it.value = 10.0
	else:
		it.category = Item.Category.MISC
		it.description = "TODO: describe this item."
		it.max_stack = 10
		it.weight = 1.0
		it.value = 5.0
	it.grid_width = 1
	it.grid_height = 1
	return it


## A starter LootTable: VALID but EMPTY (no entries) so the designer adds drop rows in the inspector. The table
## is immediately rollable — roll() over an empty entries list returns nothing, never errors — so an NpcData.loot
## slot can reference it before any rows are authored. `entries` is an explicitly-typed empty array so the .tres
## serializes the Array[LootEntry] element type (a bare [] would deserialize as an untyped array).
static func build_loot_table() -> LootTable:
	var lt := LootTable.new()
	var entries: Array[LootEntry] = []
	lt.entries = entries
	return lt


## A starter Perk whose id EQUALS the supplied id (so filename == registry key, the rule PerkManager persistence
## depends on). Empty-but-valid stat_bonuses / combat_bonuses / requires_perks for the designer to fill — an empty
## stat_bonuses passes validate() (no unknown keys), so the perk is unlockable as-is (it just does nothing yet).
## requires_perks is an explicitly-typed empty Array[StringName] so the .tres keeps its element type.
static func build_perk(id: StringName) -> Perk:
	var p := Perk.new()
	p.id = id
	p.display_name = _titleize(String(id))
	p.description = "TODO: describe what \"%s\" does." % _titleize(String(id))
	p.stat_bonuses = {}
	p.combat_bonuses = {}
	var reqs: Array[StringName] = []
	p.requires_perks = reqs
	return p


## A starter StatusEffect whose id EQUALS the supplied id (re-applying an effect with a live id REFRESHES rather
## than stacks, so a stable id == filename keeps that behaviour predictable). Seeds a neutral, immediately-valid
## buff/debuff: a short duration, NO periodic damage and a 1.0 speed multiplier (no change) so attaching it does
## nothing surprising until the designer dials in damage_per_tick / speed_multiplier / stat_modifiers.
static func build_status_effect(id: StringName) -> StatusEffect:
	var se := StatusEffect.new()
	se.id = id
	se.display_name = _titleize(String(id))
	se.description = "TODO: describe this status effect."
	se.duration = 5.0
	se.tick_interval = 1.0
	se.damage_per_tick = 0.0   # inert by default — set positive for poison/burn
	se.speed_multiplier = 1.0  # no move-speed change until the designer tweaks it
	se.stat_modifiers = {}
	return se


## A starter EncounterSpawner entry (SpawnDefinition): spawns `count` of `npc_scene`, scattered within
## spawn_radius, auto-aggro on. The dock passes the project's default enemy scene (NPC.tscn); a null is tolerated
## (an inert definition until the designer assigns npc_scene). profile / faction_override / weapon_override stay
## null for the designer to stamp an archetype on the wave — pure (the dock loads the scene, this never touches disk).
static func build_spawn_definition(npc_scene: PackedScene) -> SpawnDefinition:
	var sd := SpawnDefinition.new()
	sd.npc_scene = npc_scene
	sd.count = 3
	sd.spawn_radius = 4.0
	sd.auto_aggro = true
	sd.spawn_delay = 0.0
	return sd


## A starter daily Schedule demonstrating the two-phase pattern: by DAY head to group &"market", by NIGHT to
## &"home" (drop a Marker3D into each group in the level). The phase ints match WorldClock.Phase (Night = 0,
## Day = 1). entries is an explicitly-typed Array[ScheduleEntry] so the .tres keeps its element type.
static func build_schedule() -> Schedule:
	var s := Schedule.new()
	var day := ScheduleEntry.new()
	day.phase = 1                  # Day
	day.location_group = &"market"
	var night := ScheduleEntry.new()
	night.phase = 0                # Night
	night.location_group = &"home"
	var entries: Array[ScheduleEntry] = [day, night]
	s.entries = entries
	return s


## A starter Cutscene: a CAPTION held briefly, then a TOAST — two DIFFERENT action types so the designer sees the
## pattern and edits/extends the list. A CutscenePlayer runs the actions in order. actions is an explicitly-typed
## Array[CutsceneAction] so the .tres keeps its element type.
static func build_cutscene() -> Cutscene:
	var c := Cutscene.new()
	var caption := CutsceneAction.new()
	caption.type = CutsceneAction.Type.CAPTION
	caption.caption_text = "TODO: an opening caption."
	caption.duration = 2.0
	var toast := CutsceneAction.new()
	toast.type = CutsceneAction.Type.TOAST
	toast.toast_text = "TODO: a toast message."
	var actions: Array[CutsceneAction] = [caption, toast]
	c.actions = actions
	return c


## A starter BarkSet: seeds ONE placeholder line in the two most-used categories (spot + hurt) so the designer sees
## the format; every other category stays EMPTY, which means "inherit the NPC's built-in default lines" (a profile
## overrides only the categories it fills). Each array is explicitly Array[String] so the .tres keeps the element type.
static func build_bark_set() -> BarkSet:
	var b := BarkSet.new()
	var spot: Array[String] = ["TODO: a contact line (\"Enemy spotted!\")."]
	var hurt: Array[String] = ["TODO: a low-HP line (\"I'm hit!\")."]
	b.spot = spot
	b.hurt = hurt
	return b


## A starter player Loadout: VALID but with NO weapons (an empty Array[WeaponData] -> it falls back to the
## SwapWeapons.weapon_slots defaults until the designer adds weapons in the inspector) + the default spare clips and
## starting money. Assign it to a SwapWeapons.loadout slot to override the hardcoded kit. The weapons array is
## explicitly typed so the .tres serialises its element type.
static func build_loadout() -> Loadout:
	var l := Loadout.new()
	var weapons: Array[WeaponData] = []
	l.weapons = weapons
	l.starting_clips_per_caliber = 4
	l.money = 100.0
	return l


## A starter GrappleHookResource: every field at its built-in default (the same feel the grapple uses with no
## resource assigned), so it's a VALID tuning starting point — assign it to the Player's grapple_resource and dial
## in the rope / SFX / range / screen-shake in the inspector without touching code.
static func build_grapple_resource() -> GrappleHookResource:
	return GrappleHookResource.new()


## A starter MapData: default world_bounds (a 100×100 area centred on origin) and NO map_texture yet — drop a
## top-down render of the level into map_texture and tighten world_bounds to the level's X/Z extent, then a Minimap
## / MapScreen can project world positions onto it. Valid as-is (projection maps onto the default rect, never errors).
static func build_map_data() -> MapData:
	return MapData.new()


## A starter ThrowableData (the Throwable analogue of WeaponData): a breakable crate at the resource's own defaults
## (max_hp 5, mass 1.0, destructible = true) with ONLY its display_name personalized from `name`. `mesh` stays null
## on purpose — throwable_data.gd documents null as "keep whatever the Throwable scene ships with", so a fresh .tres
## drops onto a Throwable and is reskinned later in the inspector; forcing a model here would need a load() and break
## the pure-builder contract. Pure (no load / ResourceSaver — the dock owns disk I/O).
static func build_throwable(name: String) -> ThrowableData:
	var t := ThrowableData.new()
	t.display_name = _titleize(name)
	return t


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
