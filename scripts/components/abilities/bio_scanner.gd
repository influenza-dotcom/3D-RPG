extends Ability

## The ENTRY-TIER BODY SCANNER, granted by the Bio-Scanner microchip (resources/items/chip_bio_scanner.tres).
## Like ChessVisualizer it has no behaviour hooks — its presence + enabled flag IS the grant, and what it
## unlocks is a channel on a UI widget: scripts/ui/minimap.gd asks the Player for body_scan_range() and dots
## Groups.NPC bodies out to that many metres, fading them off across the last GameSettings.hud.minimap_scan_fade_m.
##
## ⭐WITHOUT A SCANNER THE BODY CHANNEL IS BLANK — on the HUD corner box AND on the Map tab. That is the whole
## point of the chip. The Map tab draws 120 m of world, zooms out to 240 and pans 400, so an ungated body
## channel was a free through-wall census of the level: every patrol in the building, read from a locked room,
## at any range. The other three marker channels are untouched, because none of them is a live read on other
## people — a quest beacon is a place you were told about, a station glyph is a shop, a waypoint is a pin you
## placed, and the noise ring is sound YOU made. A fresh game ships with no abilities at all (see
## Player.starting_unlocks), so knowing where people are is earned exactly like the silent takedown is.
##
## Installed like every other ability chip: find or buy the chip and pay a ChipInstaller to fit it
## (installs_ability = &"bio_scanner" -> Player.unlock_mechanic), and it serialises by id in the save's unlock
## set. The mechanic id is the snake_case of the scene filename (BioScanner.tscn) — the convention
## AbilityRegistry and the drift test (test_upgrades.gd) pin. DeepScanner is the same mechanic at a longer
## reach; AbilityManager.scan_range takes the WIDEST ENABLED one, so owning both is simply the deep one.

## ⭐THE RANGE IS THIS SCRIPT'S DEFAULT, NOT AN AUTHORED VALUE ON BioScanner.tscn, and that is load-bearing
## rather than tidiness. A RUNTIME grant — a paid chip install, a save load, an UpgradePickup — never touches
## the scene: AbilityManager._build does `load(AbilityRegistry.script_path_for(id)).new()`, a bare script
## instance with default exports. Every other ability is a pure presence flag so nothing has ever been lost
## there, but a scanner authored at 22 m on the .tscn alone would install at the script default instead — a
## chip you paid for that grants a 0 m scanner and a map that stays blank, with nothing anywhere reporting an
## error. tests/test_minimap_scan.gd pins the built node and the scene instance against each other.
## The export stays, so a designer hand-placing this node can still retune ONE Player.
@export var scan_range: float = 22.0


func ability_id() -> StringName:
	return &"bio_scanner"


## THE DUCK-TYPED CONTRACT AbilityManager.scan_range() reads, by method rather than by class: the manager holds
## plain `Ability`s and must not know this file exists, so a future implant that happens to grant map presence
## (a drone, a spliced camera net) joins in simply by answering this. Clamped at zero so a mis-authored negative
## reads as "no scanner" rather than inverting the rim fade's maths.
func scan_range_m() -> float:
	return maxf(0.0, scan_range)
