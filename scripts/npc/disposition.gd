class_name Disposition
extends RefCounted

## Shared three-state attitude an NPC holds toward the player, FNV-style. Kept on its own
## tiny script (not on NPC) so the Faction resource, the Reputation autoload, NPC, and the
## tests can all name Disposition.Kind.* without pulling in the NPC scene or each other.
##
## NEVER instantiated — it exists only as a namespace for the enum. The order is load-bearing
## for the reputation->disposition threshold mapping in Reputation: HOSTILE < NEUTRAL < FRIENDLY,
## so a rising reputation walks the enum upward.

enum Kind {
	HOSTILE,   ## attacks the player on sight (today's enemy)
	NEUTRAL,   ## ignores the player until provoked
	FRIENDLY,  ## never aggros from reputation; only a direct attack provokes it
}
