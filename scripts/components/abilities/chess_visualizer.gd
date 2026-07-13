class_name ChessVisualizer
extends Ability

## Passive UPGRADE granted by the Board Visualizer microchip (resources/items/chip_chess_visualizer.tres). It has
## NO behaviour hooks — its mere PRESENCE + enabled flag is the grant: ChessScreen reads has_mechanic(&"chess_visualizer")
## and, when set, RENDERS the chess board instead of forcing blindfold play. Without the chip a match shows only the
## move log and you track the position in your head; installing it flips blindfold -> sighted. That's the whole
## design hook — the chip IS the difference.
##
## Installed exactly like every other ability chip: the player finds/buys the chip Item and pays a ChipInstaller
## to fit it (installs_ability = &"chess_visualizer" -> Player.unlock_mechanic), and it serializes by id in the
## save's unlock set like the movement upgrades. The mechanic id is the snake_case of the scene filename
## (ChessVisualizer.tscn), the convention AbilityRegistry + the drift test (test_upgrades.gd) pin.

func ability_id() -> StringName:
	return &"chess_visualizer"
