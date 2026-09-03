extends GutTest

## The CYBER SUNDAY Blueprints tab: multi-resource "content pack" scaffolds. The PURE logic (plan + build_pack) is
## tested off-tree with .new() resources; the tab is a construct check (its ResourceSaver glue is editor-verified,
## like the Content dock). plan() takes the folders as an arg so it needs no real res:// paths.

const Ops := preload("res://addons/cybersunday_tools/dock_blueprint/blueprint_ops.gd")
const BlueprintView := preload("res://addons/cybersunday_tools/dock_blueprint/blueprint_view.gd")

const DIRS := {
	"faction": "res://f/", "weapon": "res://w/", "item": "res://i/", "loot": "res://l/", "npc": "res://n/",
}


func test_plan_lists_five_files_in_dependency_order() -> void:
	var p := Ops.plan("ghoul", DIRS)
	assert_eq(p.size(), 5, "an enemy pack is five files")
	var types := []
	for e in p:
		types.append(String(e["type"]))
	# NpcData is LAST (it references the others, which must be saved first).
	assert_eq(types, ["Faction", "WeaponData", "Item", "LootTable", "NpcData"], "dependency order: NpcData last")
	assert_eq(String(p[0]["path"]), "res://f/ghoul.tres", "faction path from the passed dir")
	assert_eq(String(p[2]["path"]), "res://i/ghoul_item.tres", "the item path mirrors content_dock's _item suffix")
	assert_eq(String(p[4]["path"]), "res://n/ghoul.tres", "npc path from the passed dir")


func test_build_pack_cross_wires_faction_weapon_and_loot() -> void:
	var weapon := WeaponData.new()
	var loot := LootTable.new()
	var pack := Ops.build_pack("ghoul", weapon, loot)
	var faction: Faction = pack["faction"]
	var npc: NpcData = pack["npc"]
	assert_eq(String(faction.id), "ghoul", "the new faction's id == the base name (filename == registry key)")
	assert_eq(faction.default_disposition, Disposition.Kind.HOSTILE, "an ENEMY pack ships HOSTILE so it attacks the player on sight (default_disposition drives player aggro, not relations)")
	assert_eq(npc.faction_id, "ghoul", "the NPC uses the NEW faction id, not the raider preset's")
	assert_eq(npc.weapon_data, weapon, "the NPC is equipped with the pack weapon")
	assert_eq(npc.loot, loot, "the NPC's loot points at the pack LootTable")
	assert_eq(npc.threat_response, 0, "the raider base makes it a FIGHTING enemy (threat_response Fight)")
	assert_eq(npc.display_name, "Ghoul", "display name is titleized from the base")
	weapon = null
	loot = null


func test_blueprint_view_constructs() -> void:
	var v = BlueprintView.new()
	assert_not_null(v, "the Blueprints tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(v.name, "Blueprints")
	v.free()


## The Scaffold button greys BEFORE the click, not after: an empty name is refused by the button's own disabled state
## and its tooltip says what is missing. Drives _refresh_preview() BY HAND on purpose -- assigning LineEdit.text does
## not emit text_changed, so a test that only set the text would be asserting against a preview nothing had rebuilt.
func test_scaffold_button_greys_on_an_empty_name_and_arms_on_a_free_one() -> void:
	var v = BlueprintView.new()
	v._refresh_preview()
	assert_true(v._scaffold_btn.disabled, "no name typed -> Scaffold is greyed")
	assert_eq(v._scaffold_btn.tooltip_text, BlueprintView.MSG_NO_NAME, "the greyed tooltip names what is missing")
	v._edit.text = "zzz Not A Real Enemy"  # slugifies to a base no shipped file can collide with
	v._refresh_preview()
	assert_false(v._scaffold_btn.disabled, "a name whose five files are all free arms Scaffold")
	assert_eq(v._scaffold_btn.tooltip_text, BlueprintView.SCAFFOLD_TIP, "the armed tooltip is the real what-it-does text")
	assert_true(v._preview.text.contains("Will create"), "the preview lists the pack's files before the click; got: %s" % v._preview.text)
	v.free()
