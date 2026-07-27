extends GutTest

## ItemInfo.tooltip() — the DERIVED "what does this item do" text. Item `description`s ship EMPTY (Steam AI-text
## scrub), so a trinket / chip / stim must communicate its effect from its STRUCTURED data (held_passive_effect /
## installs_ability / consumable_effect), never authored prose. This suite pins that derivation so a shipped trinket
## like the Chrome Grin can never silently go back to a blank, mute tooltip.
##
## The held-STRENGTH rule is the sharp edge: PassiveItemBuffs re-stamps a held strength modifier into Max HP + Carry
## (and, unlike the strength STAT, NOT melee), so the tooltip must read those concrete resources — not "+N Strength".
## The per-point consts asserted here are CharacterStats.HP_PER_STRENGTH (1.5) / CARRY_PER_STRENGTH (2.0); if those
## move, these numbers move with them (both sites read the same const, so they can't drift apart).
##
## Conventions per test_items.gd: extends GutTest, real .tres via preload for shipped items, synthetic Item.new() /
## StatusEffect.new() (RefCounted -> released with `= null`) for the paths no shipped item exercises yet.

const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")  # the canonical ability-name accessor _ability_name routes through

const CHROME_GRIN := preload("res://resources/items/chrome_grin.tres")   # unique, streetwise +3, max_stack 1
const IRONHEART := preload("res://resources/items/ironheart_locket.tres")  # agility +1, strength +2, stacks, max_stack 5
const MULE_RIG := preload("res://resources/items/mule_rig.tres")          # strength +3 only (Max HP + Carry, no melee)
const FEATHERFRAME := preload("res://resources/items/featherframe_weave.tres")  # agility +3, strength -2 (negative path)
const CHIP_WALL_CLIMB := preload("res://resources/items/chip_wall_climb.tres")
const PISTOL_ITEM := preload("res://resources/items/pistol_item.tres")
const MELEE_ITEM := preload("res://resources/items/melee_item.tres")     # is_melee, infinite ammo (must NOT read "∞")
const SNIPER_ITEM := preload("res://resources/items/sniper_item.tres")   # move_speed 0.85 (heavy)
const SHOTGUN_ITEM := preload("res://resources/items/shotgun_item.tres") # move_speed 0.82 (heavy)
const SPRAY_ITEM := preload("res://resources/items/spray_paint_item.tres") # max_ammo 0 -> must NOT read "Clip 0"
const CRATE_ITEM := preload("res://resources/items/crate_item.tres")     # world_prop -> is_holdable()


# ---------------------------------------------------------------------------
# Held passive buffs — the Chrome Grin case (the reported gap).
# ---------------------------------------------------------------------------

func test_chrome_grin_tooltip_states_its_buff() -> void:
	var t := ItemInfo.tooltip(CHROME_GRIN)
	assert_true(t.contains("While carried:"),
		"A held-buff trinket must announce it is a WHILE-CARRIED effect (blank description alone tells the player nothing). Got:\n%s" % t)
	assert_true(t.contains("+3 Streetwise"),
		"The Chrome Grin's held_passive_effect is streetwise +3 — the tooltip must derive '+3 Streetwise'. Got:\n%s" % t)

func test_chrome_grin_tooltip_has_no_unrelated_stats() -> void:
	var t := ItemInfo.tooltip(CHROME_GRIN)
	assert_false(t.contains("Strength") or t.contains("Max HP") or t.contains("Carry"),
		"The Chrome Grin only modifies streetwise — no strength/HP/carry noise should appear. Got:\n%s" % t)

func test_held_strength_reads_as_hp_and_carry_not_strength() -> void:
	# Mule Rig is strength +3. Held strength re-stamps to Max HP (+3 * 1.5 = +4.5) and Carry (+3 * 2.0 = +6) and does
	# NOT touch melee, so showing "+3 Strength" would be a lie (it would imply a melee boost the carrier never gets).
	var t := ItemInfo.tooltip(MULE_RIG)
	assert_true(t.contains("+4.5 Max HP"),
		"Held strength +3 must read as +4.5 Max HP (3 * HP_PER_STRENGTH). Got:\n%s" % t)
	assert_true(t.contains("+6 Carry"),
		"Held strength +3 must read as +6 Carry (3 * CARRY_PER_STRENGTH). Got:\n%s" % t)
	assert_false(t.contains("Strength"),
		"A HELD strength buff must NOT be labeled 'Strength' — it grants no melee, unlike the strength stat. Got:\n%s" % t)

func test_ironheart_mixes_expanded_strength_and_raw_stat() -> void:
	# agility +1 (a live stat, raw) alongside strength +2 (-> +3 Max HP, +4 Carry).
	var t := ItemInfo.tooltip(IRONHEART)
	assert_true(t.contains("+1 Agility"), "A non-strength stat stays raw '+1 Agility'. Got:\n%s" % t)
	assert_true(t.contains("+3 Max HP"), "strength +2 -> +3 Max HP. Got:\n%s" % t)
	assert_true(t.contains("+4 Carry"), "strength +2 -> +4 Carry. Got:\n%s" % t)

func test_negative_held_modifiers_are_sign_correct() -> void:
	# Featherframe Weave is a shipped risk/reward trinket: agility +3 but strength -2 (-> -3 Max HP, -4 Carry). This is
	# the ONLY path that exercises the negative _signed/_num branch, so pin it — a regression to a stray "+-" or "-0"
	# would otherwise ship on a real item. (Sign-correctness is a first-class contract here, see stat_info.gd.)
	var t := ItemInfo.tooltip(FEATHERFRAME)
	assert_true(t.contains("-3 Max HP"), "strength -2 -> -3 Max HP (a clean minus). Got:\n%s" % t)
	assert_true(t.contains("-4 Carry"), "strength -2 -> -4 Carry. Got:\n%s" % t)
	assert_true(t.contains("+3 Agility"), "agility +3 stays a positive raw stat. Got:\n%s" % t)
	assert_false(t.contains("+-"), "A negative must never render as a '+-' double sign. Got:\n%s" % t)

func test_stacking_note_only_when_multiple_can_be_held() -> void:
	# Ironheart stacks and max_stack is 5 -> "per copy"; Chrome Grin is unique AND max_stack 1 -> no note at all.
	assert_true(ItemInfo.tooltip(IRONHEART).contains("per copy"),
		"A stacking trinket you can hold several of must say the buff is 'per copy'.")
	assert_false(ItemInfo.tooltip(CHROME_GRIN).contains("per copy") or ItemInfo.tooltip(CHROME_GRIN).contains("counts once"),
		"A max_stack 1 trinket can only ever be held once, so no stacking note should clutter its tooltip.")

func test_unique_stackable_says_counts_once() -> void:
	# No shipped item is BOTH unique and max_stack > 1, so synthesize that edge to pin the 'counts once' branch.
	var fx := StatusEffect.new()
	fx.stat_modifiers = {"gunplay": 2}
	var it := Item.new()
	it.id = &"test_optic"  # a real id: PassiveItemBuffs only grants a held buff for an id'd item, so the tooltip must too
	it.display_name = "Test Optic"
	it.max_stack = 3
	it.passive_unique = true
	it.held_passive_effect = fx
	var t := ItemInfo.tooltip(it)
	assert_true(t.contains("counts once"),
		"A unique buff you can still stack copies of must say the bonus 'counts once'. Got:\n%s" % t)
	assert_true(t.contains("+2 Gunplay"), "The buff itself must still show. Got:\n%s" % t)
	it = null
	fx = null

func test_speed_multiplier_reads_as_signed_percent() -> void:
	var fx := StatusEffect.new()
	fx.speed_multiplier = 1.1
	var it := Item.new()
	it.id = &"test_speed"  # id'd so the tooltip's held-buff line matches what PassiveItemBuffs would actually grant
	it.held_passive_effect = fx
	var t := ItemInfo.tooltip(it)
	assert_true(t.contains("+10% Move Speed"),
		"speed_multiplier 1.1 must read as '+10%% Move Speed'. Got:\n%s" % t)
	it = null
	fx = null


# ---------------------------------------------------------------------------
# Upgrade chips — name the ability they install.
# ---------------------------------------------------------------------------

func test_chip_tooltip_names_the_installed_ability() -> void:
	var t := ItemInfo.tooltip(CHIP_WALL_CLIMB)
	assert_true(t.contains("Installs Wall Climb"),
		"An upgrade chip must name the ability it installs so the player knows what carrying it will buy. Got:\n%s" % t)

func test_chip_ability_name_routes_through_registry() -> void:
	# Phase-2 wiring: _ability_name reads AbilityRegistry.display_name_for (the ONE canonical accessor), so an
	# authored Ability.display_name rename reaches this tooltip with no code change. An id with no ability scene
	# keeps the old capitalized-id degrade — never a blank "Installs " line.
	for id in AbilityRegistry.ids():
		assert_eq(ItemInfo._ability_name(StringName(id)), AbilityRegistry.display_name_for(StringName(id)),
			"_ability_name('%s') must match the canonical accessor — one ability name game-wide" % id)
	assert_eq(ItemInfo._ability_name(&"ghost_ability_xyz"), "Ghost Ability Xyz",
		"an unknown mechanic id degrades to the capitalized id, never a blank")


# ---------------------------------------------------------------------------
# Consumable applied-effect (the timed path).
# ---------------------------------------------------------------------------

func test_consumable_effect_reads_as_when_used() -> void:
	var fx := StatusEffect.new()
	fx.stat_modifiers = {"agility": 2}
	fx.speed_multiplier = 1.25
	fx.duration = 8.0
	var it := Item.new()
	it.category = Item.Category.CONSUMABLE
	it.heal_amount = 10.0
	it.consumable_effect = fx
	var t := ItemInfo.tooltip(it)
	assert_true(t.contains("Heals 10 HP"), "The heal line still shows. Got:\n%s" % t)
	assert_true(t.contains("When used:"), "A consumable's applied effect is a WHEN-USED line. Got:\n%s" % t)
	assert_true(t.contains("+2 Agility") and t.contains("+25% Move Speed") and t.contains("for 8 s"),
		"The timed effect must summarise its stat, speed and duration. Got:\n%s" % t)
	it = null
	fx = null


# ---------------------------------------------------------------------------
# Weapons — the combat block communicates melee / laser / move-speed, not just damage.
# ---------------------------------------------------------------------------

func test_melee_weapon_labeled_melee_and_no_ammo() -> void:
	var t := ItemInfo.tooltip(MELEE_ITEM)
	assert_true(t.contains("Melee"),
		"A melee weapon must be labeled 'Melee' so it's not read as a gun. Got:\n%s" % t)
	assert_false(t.contains("∞") or t.contains("Ammo") or t.contains("Clip"),
		"A melee weapon doesn't fire — no misleading '∞' / 'Clip' ammo readout. Got:\n%s" % t)

func test_heavy_weapon_shows_move_penalty() -> void:
	# sniper_wep 0.85 -> -15%, shotgun 0.82 -> -18%: a real felt penalty while wielded, previously invisible.
	assert_true(ItemInfo.tooltip(SNIPER_ITEM).contains("Move -15%"),
		"move_speed_multiplier 0.85 -> 'Move -15%'.")
	assert_true(ItemInfo.tooltip(SHOTGUN_ITEM).contains("Move -18%"),
		"A heavy weapon that slows you must communicate the movement penalty.")

func test_laser_sight_flag_is_not_surfaced() -> void:
	# has_laser_sight is a cosmetic render flag that defaults TRUE (even the rock has it), so it must NOT appear —
	# it would be meaningless noise on nearly every weapon.
	assert_false(ItemInfo.tooltip(PISTOL_ITEM).contains("Laser sight"),
		"The cosmetic laser-sight flag (default true) must not clutter tooltips.")

func test_spray_paint_labeled_and_no_false_combat_stats() -> void:
	# is_spray_paint = true: attack.gd short-circuits before the damage path, so this weapon deals NO damage. Its
	# tooltip must say what it DOES ("Sprays paint") and must NOT frame it as a damage/headshot weapon, nor show a
	# "Clip 0" (max_ammo 0). This is the melee analogue — label the mode, drop the misleading combat readouts.
	var t := ItemInfo.tooltip(SPRAY_ITEM)
	assert_true(t.contains("Sprays paint"), "A paint sprayer must be labeled by its function. Got:\n%s" % t)
	assert_false(t.contains("Damage") or t.contains("Headshot"),
		"A non-damaging paint sprayer must not show Damage / Headshot combat stats. Got:\n%s" % t)
	assert_false(t.contains("Clip 0"), "max_ammo 0 must not render 'Clip 0'. Got:\n%s" % t)

func test_on_hit_effect_clause_is_scoped_with_chance_in_label() -> void:
	# No shipped weapon uses on_hit_effect, so synthesize a poison round to pin the rendering: the chance rides the
	# label and the sub-parts join with commas, so the clause doesn't dissolve into the "  ·  " top-level weapon stats.
	var fx := StatusEffect.new()
	fx.damage_per_tick = 3.0
	fx.tick_interval = 1.0
	fx.duration = 5.0
	var w := WeaponData.new()
	w.damage = 5.0
	w.on_hit_effect = fx
	w.on_hit_chance = 0.5
	var it := Item.new()
	it.category = Item.Category.WEAPON
	it.weapon = w
	var t := ItemInfo.tooltip(it)
	assert_true(t.contains("On hit (50%): "), "The application chance must ride the 'On hit' label. Got:\n%s" % t)
	assert_true(t.contains("3 HP/s damage, for 5 s"),
		"On-hit sub-parts must join with commas so they stay scoped under the clause. Got:\n%s" % t)
	it = null
	w = null
	fx = null


# ---------------------------------------------------------------------------
# Holdable props — the one thing you can DO with them.
# ---------------------------------------------------------------------------

func test_holdable_prop_says_hold_and_throw() -> void:
	var t := ItemInfo.tooltip(CRATE_ITEM)
	assert_true(t.contains("Hold in hand"),
		"A world_prop item can be carried in hand from the hotbar — its tooltip must say so (otherwise it's a bare name). Got:\n%s" % t)


# ---------------------------------------------------------------------------
# Plain items are untouched — no false effect lines.
# ---------------------------------------------------------------------------

func test_plain_weapon_has_no_effect_lines() -> void:
	var t := ItemInfo.tooltip(PISTOL_ITEM)
	assert_false(t.contains("While carried:") or t.contains("When used:") or t.contains("Installs") or t.contains("Hold in hand"),
		"A plain weapon has no held/consumable/chip/holdable effect — its tooltip must gain no effect lines. Got:\n%s" % t)


# ---------------------------------------------------------------------------
# Phase-2 money seam: the value footer renders its money through
# Zorkmids.money_text — the ONE "{amount} zm" template ("zm" never lives here).
# (The _num -> TextFormat.num delegation is pinned in test_text_format.gd.)
# ---------------------------------------------------------------------------

func test_footer_money_uses_the_whole_money_phrase() -> void:
	var t := ItemInfo.tooltip(CHIP_WALL_CLIMB)
	if CHIP_WALL_CLIMB.value > 0.0:
		assert_true(t.contains(Zorkmids.money_text(CHIP_WALL_CLIMB.value)),
			"the value footer must carry the whole money phrase from Zorkmids.money_text. Got:\n%s" % t)
	var worthless := Item.new()
	worthless.display_name = "Scrap"
	assert_false(ItemInfo.tooltip(worthless).contains("zm"),
		"a value-0 item shows no money footer at all")
	worthless = null
