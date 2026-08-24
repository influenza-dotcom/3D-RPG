class_name Groups
extends RefCounted

## Canonical SceneTree group names — one source of truth, so add_to_group / get_nodes_in_group / is_in_group never
## drift on a typo or a case mismatch. (A literal mismatch is silent: a query against a never-populated name just
## returns nothing — see the lowercase-"player" bug this registry fixed.) New group code should reference these.
##
## PLAYER is the combat / identity group: the human Player (Player.tscn `groups=["Player"]`) AND recruited
## companions (they add_to_group(PLAYER) so enemies target them too). To get the HUMAN player specifically — not a
## companion — call human_player() below (the ONE home for that rule). There is intentionally NO lowercase "player".

const PLAYER := &"Player"                      ## human player + recruited companions (combat/identity target group)
## The const is intentionally named NPC (the npc group) even though it matches the global NPC class — this file
## holds only group-name consts and never uses the NPC type, so the shadow is benign. Silence the parse warning.
@warning_ignore("shadowed_global_identifier")
const NPC := &"npc"
const CONTAINERS := &"containers"
const MINIMAP := &"minimap"                    ## WorldMarker dots on the minimap
## STATION GLYPHS on the minimap — a Merchant / Atm / Healer / Bonfire / LevelUp / ChipInstaller / ChessMatch /
## PerkStation / RespecStation / LevelDoor that has a StationMarker. A SEPARATE channel from MINIMAP on purpose,
## twice over: these are STATIC landmarks, so they must not pin Minimap's idle gate open (a station never moves,
## so a repaint for its sake would be a repaint for nothing), and a station riding a dialogue NPC must still get
## its disposition-tinted NPC dot — joining MINIMAP would suppress it (see Minimap._paint_markers' de-dupe).
## Joined via the StationMarker drop-in, which adds ITSELF (it carries the kind + the pin choice).
const MINIMAP_STATION := &"minimap_station"
## Props whose colliders the HUD floorplan must NOT turn into walls — a chain-link fence, a market awning, a
## parked car. FloorplanSource.gather skips the whole subtree. Joined via the MinimapHide drop-in, which adds
## its PARENT rather than itself (the WorldMarker idiom).
const MINIMAP_HIDE := &"minimap_hide"
const COMPASS := &"compass"                    ## WorldMarker chevrons on the screen-edge compass
const LIGHTS := &"lights"                       ## scene lights sampled by PlayerLightLevel (stealth)
const PICKUP_BEACON := &"pickup_beacon"         ## pickup item lights (PickupBeacon) excluded from PlayerLightLevel
const STEALTH_LIGHT_EXEMPT := &"stealth_light_exempt" ## decorative lights PlayerLightLevel skips (NOT the player's HP glow — that one counts and is crouch-doused by CrouchLightDouse instead)
## Lights the player CARRIES on their person — the flashlight, a lit lantern prop. PlayerLightLevel reads this
## group into `player.carried_light`, the "I am a walking beacon" penalty enemy Perception applies ON TOP of the
## light meter (wider sight range + a faster-filling detection meter). Membership is what makes a lamp a liability
## at RANGE: the exposure meter saturates at 1.0, so being lit can only ever cancel the darkness discount, never
## push you past baseline. A carried light also still feeds that meter like any other lamp.
const CARRIED_LIGHT := &"carried_light"
const GAME_ROOT := &"game_root"                 ## the GameRoot (level-load seam) — LevelDoor finds it here
const PLAYER_SPAWN := &"player_spawn"
const NAVMESH := &"navmesh"                     ## geometry + the NavigationRegion3D that feed the navmesh bake
const WORLD_ENVIRONMENT := &"world_environment" ## the WorldEnvironment StarSky repaints
const MUSIC := &"music"
const DAY_NIGHT := &"day_night"                 ## the level's DayNightSky driver — sampled (duck-typed current_day_factor) by ViewModelCamera's night fill
const SKY_TITLE := &"sky_title"
const AMBIENT_DUST := &"ambient_dust"
const GIB := &"gib"
## World gore the PLAYER'S OWN death spawned — its meat chunks / body parts, the floor splat, the corpse, and the
## secondary splatter those gibs bleed when they pop. Stamped by GoreSpawner off Character.death_gore_group() and
## swept by the in-place checkpoint revive (Player._respawn_at_checkpoint), so you are never brought back standing
## over your own remains. NPC gore is deliberately never tagged: it is world dressing and stays where it fell.
const PLAYER_GORE := &"player_gore"
const PAINT_DECAL := &"paint_decal"
const CORPSE := &"corpse"                       ## discoverable death markers (Corpse) scanned by NPC._nearest_visible_corpse (Corpse.GROUP aliases this)
const NOISE := &"noise"                         ## shared stealth sound channel — NoiseSource/NoisePulser emit, NpcSenses scans (NoiseSource.GROUP aliases this)
const VIP := &"vip"                             ## bodyguard-protectee role — a GuardDuty NPC defends the first node in this group (protectee_group default)
## Debug UIs that FREE THE CURSOR and SUSPEND THE PLAYER while open (DebugConsole, DebugMenu). Membership is how
## each finds the others so that opening one closes the rest first: two suspensions restored in the wrong order
## either unfreeze the player under a still-open panel (clicks fire the weapon) or leave them frozen with nothing
## on screen. Dev-build only in practice — the surfaces gate on OS.is_debug_build() before joining.
const DEBUG_SURFACE := &"debug_surface"


## The HUMAN player node — the single `Player` member of the PLAYER group (recruited companions join PLAYER for
## targeting but are NPCs, not Player, so they're excluded). Returns null if there's no human in `tree` yet, or a
## null / absent tree — callers PASS their get_tree() (a static util can't call get_tree() itself; passing the tree
## also lets an off-tree caller pass null and get null back without a guard). This is the ONE home for the
## "which member is the human" rule (M6), so the identity-by-string-scan trap — the dead lowercase "player" group
## that silently killed kill-XP — stays contained here. `is Player` (not `not is NPC`) both dodges this file's NPC
## const shadow and positively identifies the human, matching DialogueManager's existing idiom. For ANY player-group
## member (human OR companion), scan PLAYER directly instead.
static func human_player(tree: SceneTree) -> Node3D:
	if tree == null:
		return null
	for p in tree.get_nodes_in_group(PLAYER):
		if p is Player:
			return p as Player
	return null
