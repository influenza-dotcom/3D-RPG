@tool
extends RefCounted

## PURE logic for the Blueprints tab — multi-resource "content pack" scaffolds that the single-resource Content
## generators don't cover. The single generators each make ONE unwired .tres; a blueprint makes a SET of
## cross-wired resources in one click. Today's blueprint is the ENEMY PACK: a Faction + a Weapon+Item pair + a
## LootTable + an NpcData that references all three — so authoring a new enemy type is one action, not four.
##
## Composes the existing pure builders in content_scaffold.gd; adds the cross-wiring + the file PLAN. The tab
## (blueprint_view.gd) owns the editor glue (ResourceSaver in dependency order, refuse-overwrite, rescan, open),
## exactly like content_dock. plan() + build_pack() are pure so GUT exercises them headless.

const Scaffold := preload("res://addons/cybersunday_tools/dock_content/content_scaffold.gd")


## The files an enemy pack creates, in DEPENDENCY ORDER (sub-resources before the NpcData that references them).
## `dirs` maps {faction, weapon, item, loot, npc} -> res:// folder (passed in so this stays pure + testable). The
## weapon/item naming mirrors content_dock (weapon at <weapon>/<base>.tres, item at <item>/<base>_item.tres). Each
## entry is {type, path} for the preview + the refuse-overwrite check.
static func plan(base: String, dirs: Dictionary) -> Array:
	return [
		{"type": "Faction", "path": String(dirs["faction"]) + base + ".tres"},
		{"type": "WeaponData", "path": String(dirs["weapon"]) + base + ".tres"},
		{"type": "Item", "path": String(dirs["item"]) + base + "_item.tres"},
		{"type": "LootTable", "path": String(dirs["loot"]) + base + ".tres"},
		{"type": "NpcData", "path": String(dirs["npc"]) + base + ".tres"},
	]


## Wire the Faction + NpcData from a base name and the ALREADY-SAVED (path-backed) weapon + loot, so the NpcData
## .tres references them by path. The "raider" preset gives a fighting enemy; we override its faction_id to the NEW
## faction (id == base) and attach the loot table. Returns {faction, npc}. Pure — the caller saves weapon/item/loot
## FIRST, then calls this with the loaded resources, then saves faction + npc.
static func build_pack(base: String, weapon: WeaponData, loot: LootTable) -> Dictionary:
	var faction := Scaffold.build_faction(StringName(base))
	# An ENEMY pack must actually be an enemy: default_disposition HOSTILE makes it attack the player on sight
	# (Reputation.disposition_for reads default_disposition; `relations` is NPC-vs-NPC only). Mirrors raiders.tres.
	faction.default_disposition = Disposition.Kind.HOSTILE
	var npc := Scaffold.build_npc("raider", weapon)  # a fighting archetype, equipped with the pack weapon
	npc.display_name = Scaffold.titleize(base)
	npc.faction_id = base   # use the NEW faction, NOT the raider preset's id (the either/or rule: faction_id only)
	npc.loot = loot
	return {"faction": faction, "npc": npc}
