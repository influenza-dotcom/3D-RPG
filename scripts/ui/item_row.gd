class_name ItemRow

## The ONE place an item stack becomes row text for the inventory-style screens (InventoryScreen /
## LootScreen / ShopScreen) — so the player's backpack, a corpse, a crate, and a shop all speak the same
## LABELED language instead of each screen inventing its own bare numbers ("3.4" -> "wt 3.4",
## "[9mm x12]" -> "ammo 9mm: 12"). Stateless static, in the TalkHelpers/CBPalette mold.

## "Health Pack  x3  ·  wt 1.5" — name, count (when stacked), labeled stack weight; plus, for a weapon with
## a caliber, the holder's spare-ammo readout ("ammo 9mm: 24"). `holder` is the inventory whose reserve the
## ammo count reads (the bag the row belongs to); null skips the ammo readout.
static func stack_text(item: Item, count: int, holder: CharacterInventory = null) -> String:
	var text := item.label()
	if count > 1:
		text += "  x%d" % count
	text += "  ·  wt %.1f" % (item.weight * count)
	if item.is_weapon() and item.weapon != null and item.weapon.caliber != &"" and holder != null:
		text += "  ·  ammo %s: %d" % [item.weapon.caliber, holder.ammo_count(item.weapon.caliber)]
	return text
