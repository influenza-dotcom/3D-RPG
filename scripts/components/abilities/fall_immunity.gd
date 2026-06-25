class_name FallImmunity
extends Ability

## Passive UPGRADE: while a FallImmunity ability is present + enabled on the Player, a hard landing costs no HP.
## No behaviour hooks — its mere PRESENCE grants the immunity: the Player's _apply_fall_damage override reads
## has_mechanic(&"fall_immunity") and skips the fall-damage math. Granted by an UpgradePickup (drag FallImmunity.tscn
## into its `grants` slot, or pick "fall_immunity" in unlock_id) and serialized by id like every other ability,
## so the autosave re-adds it on load. The mechanic id is the snake_case of the scene filename (FallImmunity.tscn),
## the convention AbilityRegistry + the drift test pin.

func ability_id() -> StringName:
	return &"fall_immunity"
