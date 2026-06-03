@abstract
class_name NPC
extends Character

## Shared base for all NON-PLAYER actors (Enemy today; future friendly/neutral NPCs
## tomorrow). Sits between Character and Enemy so non-combat NPCs can extend NPC without
## inheriting enemy-only behaviour, while everything keeps inheriting Character's HP /
## damage / gore / blast machinery and `Enemy is Character` stays transitively true.
##
## Intentionally empty in Phase 1 — this is a thin type seam only. Deep component
## decomposition (data-driving the outline onto NPC, extracting a shared outline-highlight
## helper, moving any shared non-combat behaviour down from Enemy) is deferred to Phase 2.
##
## The Player is deliberately NOT an NPC: it stays `extends Character`.
