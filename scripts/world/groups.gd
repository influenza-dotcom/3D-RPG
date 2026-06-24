class_name Groups
extends RefCounted

## Canonical SceneTree group names — one source of truth, so add_to_group / get_nodes_in_group / is_in_group never
## drift on a typo or a case mismatch. (A literal mismatch is silent: a query against a never-populated name just
## returns nothing — see the lowercase-"player" bug this registry fixed.) New group code should reference these.
##
## PLAYER is the combat / identity group: the human Player (Player.tscn `groups=["Player"]`) AND recruited
## companions (they add_to_group(PLAYER) so enemies target them too). To get the HUMAN player specifically — not a
## companion — filter for the non-NPC member (see NPC._real_player). There is intentionally NO lowercase "player".

const PLAYER := &"Player"                      ## human player + recruited companions (combat/identity target group)
## The const is intentionally named NPC (the npc group) even though it matches the global NPC class — this file
## holds only group-name consts and never uses the NPC type, so the shadow is benign. Silence the parse warning.
@warning_ignore("shadowed_global_identifier")
const NPC := &"npc"
const CONTAINERS := &"containers"
const MINIMAP := &"minimap"                    ## WorldMarker dots on the minimap
const COMPASS := &"compass"                    ## WorldMarker chevrons on the screen-edge compass
const LIGHTS := &"lights"                       ## scene lights sampled by PlayerLightLevel (stealth)
const GAME_ROOT := &"game_root"                 ## the GameRoot (level-load seam) — LevelDoor finds it here
const PLAYER_SPAWN := &"player_spawn"
const NAVMESH := &"navmesh"                     ## geometry + the NavigationRegion3D that feed the navmesh bake
const WORLD_ENVIRONMENT := &"world_environment" ## the WorldEnvironment StarSky repaints
const MUSIC := &"music"
const SKY_TITLE := &"sky_title"
const AMBIENT_DUST := &"ambient_dust"
const GIB := &"gib"
const PAINT_DECAL := &"paint_decal"
const CORPSE := &"corpse"                       ## discoverable death markers (Corpse) scanned by NPC._nearest_visible_corpse
