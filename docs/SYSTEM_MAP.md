# System Map

<!-- GENERATED FILE - DO NOT EDIT BY HAND.
     Regenerate:  godot --headless --path . -s scripts/tools/gen_arch_doc.gd
     Source of truth: `## @system / @seam / @risk / @test` blocks above class_name / autoload scripts
     under scripts/, managers/ + resources/. tests/test_arch_doc_sync.gd fails if this file is stale.
     Companion to the hand-written ARCHITECTURE_REVIEW.md + docs/CURRENT_ARCHITECTURE.md. -->

This index is generated from `@system` annotations in the code, so it cannot drift from the source.
For the deep narrative see [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md); for current rough edges
see [ARCHITECTURE_REVIEW.md](../ARCHITECTURE_REVIEW.md).

_23 system(s), 46 entries - scanned scripts/, managers/ + resources/._

- [Audio](#audio)
- [Control-Lock And Immunity](#control-lock-and-immunity)
- [Derived Stats](#derived-stats)
- [Economy](#economy)
- [Effect And Audio Seams](#effect-and-audio-seams)
- [HUD Clock](#hud-clock)
- [HUD Rendering](#hud-rendering)
- [Ink Outline](#ink-outline)
- [Interaction](#interaction)
- [Minimap](#minimap)
- [NPC AI](#npc-ai)
- [NPC Brain](#npc-brain)
- [Options Settings](#options-settings)
- [Passive Item Buffs](#passive-item-buffs)
- [Player Abilities](#player-abilities)
- [Player Movement](#player-movement)
- [PS1 Warp](#ps1-warp)
- [Quests](#quests)
- [Rendering](#rendering)
- [Run And Level Flow](#run-and-level-flow)
- [Save Model](#save-model)
- [Save Model — the EXACT-snapshot tier (authored-NPC death/position + cross-level deaths + container contents)](#save-model--the-exact-snapshot-tier-authored-npc-deathposition--cross-level-deaths--container-contents)
- [Wait](#wait)

## Audio

### `autoload StationMusic` - `managers/StationMusic.gd`

POLLS InputManager.any_station_music_open() every frame — deliberately NOT the screens' opened/closed signals, which fire on REFUSE paths too and therefore cannot be refcounted. A poll asks the CURRENT truth, so it self-heals across a refused open, the death sweep, a quickload and a level swap with no repair code, and it touches ZERO screen files. is_bed_wanted() is the public tier flag: MusicDirector stands the combat score down for it (yield_to_station_music) and DialogueMusicBed steps aside for it (note_menu_music), exactly as both already do for a diegetic Radio.

- **Risk:** PROCESS_MODE_ALWAYS is load-bearing: a station screen opened from a CONVERSATION opens under DialogueManager's tree pause, and a pausable AudioStreamPlayer silences itself ~15 ms in with nothing logged (the trap documented on StationSpeaker).
- **Test:** `tests/test_station_music.gd`

### `class StationSpeaker` - `scripts/components/station_speaker.gd`

chirp(station) is THE open cue for every station screen (shop/heal/level-up/respec/install/chess/atm): the screen calls it at its commit point and feeds the RESULT to ModalMenu.grab_mouse(not chirped), so a machine with a voice REPLACES the generic UI sting instead of doubling it and a mute one still gets the sting. Static, type-agnostic and null-safe, so no screen branches or duck-types. applaud(station) is the REWARD cue, same static shape as chirp: the machine claps for you out of its own panel. Its ONE caller today is Atm.deposit on the portion that actually RETIRES DEBT — the same predicate that scores credit standing — so a repayment is celebrated and a plain saving deposit is not. Unlike chirp it does NOT suppress the caller's UI cue: the crisp commit click confirms the press, the applause celebrates the milestone, and they are different layers. ensure(station) is the auto-build seam the station components call in _ready (gated on `standalone`); it never replaces an AUTHORED StationSpeaker child, which is what makes a hand-placed one the tuning AND the mute switch.

- **Risk:** A PAUSABLE AudioStreamPlayer3D silences itself on NOTIFICATION_PAUSED ~15 ms in, with no error and nothing logged — a dialogue-hosted station opens under the conversation's pause, so the built players MUST stay PROCESS_MODE_ALWAYS.
- **Risk:** find_speaker matches by TYPE, not name: a station that exported a NodePath or looked for "Speaker" would go silent the first time a designer renamed the node in their own scene.
- **Test:** `tests/test_station_speaker.gd`

### `class WanderMusic` - `scripts/components/wander_music.gd`

Reads the SHARED soundscape scan (scripts/audio/soundscape.gd) plus the two flags the other layers already publish (StationMusic.is_bed_wanted, DialogueManager.is_engaged), so this bed and MusicDirector's combat score can never disagree about whose moment it is — they are complements computed from one answer.

- **Risk:** PROCESS_MODE_ALWAYS is load-bearing: a conversation PAUSES THE TREE, and a pausable AudioStreamPlayer silences itself ~15 ms in with nothing logged (the trap documented on StationSpeaker). This bed must FADE out of a conversation, not vanish into one.
- **Test:** `tests/test_wander_music.gd`

## Control-Lock And Immunity

### `autoload InputManager` - `managers/InputManager.gd`

world_frozen() (cutscene OR dialogue engaged) is the sole cinematic damage-immunity predicate, distinct from gameplay_suppressed()'s control gate.

- **Risk:** Merging world_frozen() with gameplay_suppressed() silently grants immunity inside real-time menus, or strips it mid-cutscene — no crash, just wrong damage.
- **Risk:** A new control-lock added only to gameplay_suppressed() leaves the frozen player takeable; adding only to world_frozen leaks immunity — both silent.
- **Risk:** Immunity lives at 3 call sites (Player.take_damage, HazardZone._process, StatusEffectManager._process); a rename missing one silently un-gates that damage source.
- **Test:** `tests/test_world_frozen.gd`

### `class CutscenePlayer` - `scripts/components/cutscene_player.gd`

Static is_active() is the cutscene control-lock read by gameplay_suppressed() and world_frozen(); _finish() and _exit_tree() must always clear it (the tree never pauses).

- **Risk:** A mid-cutscene free (RELOAD respawn, level swap) leaving static `_active` set locks input all session with no cutscene visible — a silent, unrecoverable soft-lock.
- **Risk:** Any exit path (finish, skip, teardown) that skips _release_actors() leaves a staged NPC brain-suppressed / frozen forever with no error.
- **Test:** `tests/test_cutscene.gd` `tests/test_cutscene_actor.gd`

### `autoload DialogueManager` - `scripts/dialogue/dialogue_manager.gd`

is_engaged() (_active != null) = a conversation exists at all — the unpaused intro beat + the menu-suspension that is_active() hides — feeding world_frozen() immunity, Player.die() + _on_speaker_died teardown, _suspend_for_menu's box-hide + CONNECT_ONE_SHOT closed->resume one-shot, UI._push_quest_toast's toast queue, and Radio's dialogue duck.

- **Risk:** Dropping is_engaged() from InputManager.world_frozen() loses immunity in the unpaused intro beat — an enemy shoots the frozen player with no error (C66).
- **Risk:** die() gating on is_active() not is_engaged() skips abort() during a sub-menu suspension — the menu's close then re-pauses + re-opens the box over the death cinematic.
- **Risk:** A suspending sub-menu (Shop/Install/Chess/Atm/Heal/LevelUp/Loot-exchange) refuse path that returns WITHOUT emitting `closed` strands the convo _suspended forever — box hidden, tree paused, soft-lock, no crash.
- **Risk:** Station options (Trade/Heal/Rest/Level Up/Install/Play Chess/Bank) are discovered by a has_method scan of the speaker's direct children for the dialogue_station_option + open_dialogue_station pair, and the speaker/player surfaces stay duck-typed (set_in_dialogue/note_speaking/is_following/resolved_disposition + died); a rename on either side silently drops the option/handshake with no compile error — pinned by tests/test_dialogue_speaker_contracts.gd.
- **Test:** `tests/test_dialogue.gd` `tests/test_dialogue_suspend_closed.gd` `tests/test_dialogue_speaker_contracts.gd`

## Derived Stats

### `class CharacterStats` - `scripts/player/character_stats.gd`

restamp_derived is the one strength/endurance re-stamp path LevelUp/PerkManager/PassiveItemBuffs funnel through; STAT_NAMES is the master stat-name const.

- **Risk:** Banking the ideal delta, not restamp_derived's returned post-floor delta, over-restores max_hp/carry on reverse once a value hit its floor — silent, permanent inflation.
- **Risk:** A new derived formula omitting baseline-0 neutrality or its maxf(0.0,..) floor slips the hand-listed baseline test and silently shifts balance for all baseline Characters.
- **Risk:** Dropping restamp_derived's guarded `damaged` emit leaves the HP HUD showing a stale max after a level-up/perk/trinket; no test asserts the emit, so it fails silently.
- **Test:** `tests/test_player_stats.gd`

## Economy

### `class Atm` - `scripts/components/atm.gd`

deposit()/withdraw() are the only BANKING writers of GameState.account — purchases also draw it down through Player.charge (the credit rail deliberately crosses below zero, so these clamps do not bound it) and the New Game implant bill stamps it in StartMenu._stamp_new_game_profile; audit all four plus LedgerAccrual before touching the clamps. Both are self-guarding and callable off-tree, so AtmScreen stays a pure view with no rules of its own.

- **Risk:** A deposit path that does not clamp to maxf(0.0, player.money) lets a debtor mint money.
- **Risk:** A withdraw path that does not clamp to maxf(0.0, GameState.account) opens a cash advance — and with it the draw-the-line / redeposit / earn-savings-interest arbitrage that the single clamp closes today.
- **Test:** `tests/test_atm.gd`

### `class MoneyPurse` - `scripts/inventory/money_purse.gd`

Mirrors `Character.money` into one derived `zorkmids` coin stack (1 unit = QUANTUM) in the player-only bag, self-heals it on any external bag touch, and register_mirror's it as a VIEW.

- **Risk:** If GameState.capture stops skipping `Zorkmids.ITEM_ID`, the coin stack is double-persisted; on load sync() reconciles the reloaded tile to `money` so the wallet does NOT inflate (push-only mirror) — only the single-source invariant breaks.
- **Risk:** If `is_mirrored` wrongly reads TRUE for a real loot source carrying a separate `money` float (corpse/container/pickpocket NPC), taking its coin tile ALSO debits that float -> that cash silently destroyed (F-C37 test guards it).
- **Risk:** If the `_syncing` latch breaks, each external bag touch fires a redundant second sync + extra changed/autosave churn (idempotent set_item_count stops it short of infinite recursion).
- **Test:** `tests/test_money_purse.gd` `tests/test_loot_drop.gd`

### `autoload LootScreen` - `scripts/ui/loot_screen.gd`

`_take` on a zorkmids tile credits real `add_money` (never `transfer_to`) and debits the source's `money` float only if `is_mirrored(item)`.

- **Risk:** Drop the `is_mirrored` guard: taking a live-pickpocket NPC's coin tile also debits its separate pocket float — that cash is destroyed silently.
- **Risk:** `transfer_to`'ing a zorkmids tile (vs `add_money`) lets the player's purse trim it back to the wallet value — the take silently evaporates.
- **Test:** `tests/test_loot_drop.gd`

## Effect And Audio Seams

### `autoload AudioManager` - `managers/AudioManager.gd`

One-shot SFX seam: play_sfx/play_2d_sfx spawn self-freeing players on the sfx bus (default) so volume sliders apply; play_applause is the shared kill+pet cheer; stop_sfx cuts all sfx-bus players, freeing only ONE_SHOT_META ones. Pitch-variation seam: vary_pitch() is THE global per-play detune for DIEGETIC world SFX; play_sfx/play_2d_sfx apply it unless the caller passes vary=false, and play_varied() is the node-driven equivalent for an authored AudioStreamPlayer a world site retriggers.

- **Risk:** A sound spawned bare (not via play_sfx) lands on Master and silently ignores the SFX volume slider AND the death cinematic's world duck (so it blares under the death card) — no error; the bus=&"sfx" default guards the code side, tests/test_audio_bus_hygiene.gd guards the authored-scene side.
- **Risk:** Pitch variation is for DIEGETIC WORLD sound only (footsteps, gunfire, impacts, voices, doors). Menu chrome, HUD/alert stings, reward jingles and music must stay EXACT — a randomised UI blip or a detuned jingle reads as a defect, not as life; the vary=false opt-out on play_sfx/play_2d_sfx is how such a caller says so.
- **Risk:** A new WORLD SFX site that calls player.play() directly instead of AudioManager.play_varied(player) is the ONE way to reintroduce a machine-exact retrigger — it sounds fine in isolation and only reads as fatiguing once it fires three times a second.
- **Risk:** Re-adding a local applause copy in death.gd/pettable.gd instead of calling play_applause drifts the kill vs pet cheer apart, and no test asserts they delegate.
- **Test:** `tests/test_audio_manager_spawn.gd` `tests/test_audio_pitch_variation.gd` `tests/test_autoload_order.gd`

### `autoload EffectFactory` - `managers/EffectFactory.gd`

EffectFactory autoload owns ONE gameplay spawn (spawn_blood_particle) over a null-safe spawn_at that auto-emits+frees particles; it is NOT a VFX registry.

- **Risk:** Re-adding a per-effect slot or spawn_* wrapper is a silent no-op unless it routes through spawn_at AND a call site reads it (the removed slots failed exactly this way).
- **Risk:** The instantiate()-null guard returns null with NO log at all (only the null-scene path warns) — an empty/broken effect scene yields zero VFX silently, no crash, easy to miss.
- **Test:** `tests/test_managers_tuning.gd` `tests/test_autoload_order.gd`

### `class DeathMix` - `scripts/player/death_mix.gd`

Owns everything you HEAR while dying: begin() / set_world_duck(t) / restore_world() / begin_revive() are the four seams Player's death cinematic delegates to, and the sting plays on this very node.

- **Risk:** Listing death_sting_bus INSIDE death_cinematic_buses ducks the sting along with the world — the one wiring mistake that silently un-does the whole feature; _ready() push_warning's it and tests/test_death_mix.gd pins it.
- **Risk:** The duck writes GLOBAL bus volumes, so any teardown that frees the Player without reaching a death branch would leave the world silent into the next life; _exit_tree() is the backstop (and fixes the same pre-existing hole for the Options -> Main Menu / Load-game escapes).
- **Risk:** An authored AudioStreamPlayer with no `bus =` line lands on Master, which the cinematic deliberately no longer ducks — such a sound now plays at FULL volume under the death card; tests/test_audio_bus_hygiene.gd guards the scene side.
- **Test:** `tests/test_death_mix.gd`

## HUD Clock

### `class HudClock` - `scripts/ui/hud_clock.gd`

Code-built by ui.gd into the top-right stack directly UNDER the minimap and ABOVE the quest tracker; layout comes from GameSettings.hud.clock_*, paint from MenuStyle.hud.clock_color, and the player's choices are polled LIVE off Settings.clock_enabled / Settings.clock_24_hour so an Options change bites the same frame with no HUD rebuild (the minimap_enabled idiom). Reads WorldClock.time_of_day — the SAME 0..1 fraction DayNightSky drives the sun from, so the digits and the daylight can never disagree. It is a READER only: nothing here writes the clock. The readout survives save/load for free — GameState.time_of_day snapshots WorldClock and re-applies it on load, so the face shows the hour the save was taken at with no persistence of its own.

- **Risk:** The face pauses with the tree, so it freezes during a dialogue (DialogueManager pauses) — correct, because in-game time genuinely is not advancing, but it does mean a player watching the clock through a long conversation sees no movement.
- **Risk:** A level running WorldClock.day_length_seconds = 0 (a deliberately frozen clock) shows one constant time forever. That is the designer's chosen state, not a fault, and this widget cannot tell the two apart.
- **Test:** `tests/test_hud_clock.gd`

## HUD Rendering

### `class HudGhost` - `scripts/ui/hud_ghost.gd`

The HUD CanvasLayer's canvas is attached to a SECOND (offscreen, never-cleared) viewport, so the

- **Risk:** Any HUD element that SAMPLES THE SCREEN (hint_screen_texture / BackBufferCopy) must be excluded
- **Risk:** The DISPLAY rect lives on the very layer it is showing, so it MUST be excluded from the capture
- **Test:** `tests/test_hud_ghost.gd`

## Ink Outline

### `class InkOutline` - `scripts/effects/ink_outline.gd`

A screen-filling quad childed to a Camera3D; ink_outline.gdshader edge-detects that camera's DEPTH + NORMAL_ROUGHNESS buffers to ink the WORLD, while actors (NPCs / props / view model — everything wearing the inverted-hull rim) are excluded per-pixel via a coverage+depth mask SubViewport fed by the ACTOR_INK_MASK_LAYER render-layer stamp.

- **Risk:** Actor exclusion rests on the ACTOR_INK_MASK_LAYER stamp riding the overlay walks (Character._apply_overlay_to_meshes / NpcOutline.apply_part_overlays / Throwable._setup_overlay_chain / body_part_gib strip / BodyModelSwap._apply_actor_outline / ExplosionMesh._ready) — a new actor path that skips those walks gets inked over its hull rim (the doubled-outline complaint) with no error anywhere, and one that is neither hull-rimmed nor stamped (the player's own first-person body until 2026-08-15, every explosion and hit spark until 2026-08-16) wears the WORLD's line where every NPC beside it wears a rim.
- **Risk:** The mask viewport SHARES the main World3D, so anything visual parented inside it is registered with the MAIN scenario too and the main camera would draw it; the resolve quad only stays invisible because it sits on MASK_INTERNAL_LAYER, a render bit above the 20 a default cull_mask carries. Give it an ordinary layer and it paints its raw depth encoding over the whole screen.
- **Risk:** The mask's depth channel is a NUMBER encoded in an 8-bit sRGB colour target — it survives only because the resolve shader pre-compensates for that transfer and the mask camera's Environment is pinned to the LINEAR tonemapper. A filmic tonemap, an exposure change, glow or colour adjustments on that Environment all corrupt it silently, and the symptom is actors flickering back to a doubled outline.
- **Risk:** The hull rim (outline.gdshader) is a TRANSPARENT material and writes NO depth, so the mask's depth stops at the actor's opaque body and the ink shader has to SEARCH outward (mask_rim_search_px) for it. Author an outline_width whose rim out-reaches that search and the rim degrades to the old always-suppress behaviour — not a break, but the hidden actor's ring-shaped halo comes back on it.
- **Risk:** The quad is culled by its real AABB before the vertex shader can fill the screen, so losing extra_cull_margin makes the whole effect vanish at certain camera angles rather than fail loudly.
- **Risk:** The mask is a SECOND scene render — it costs a full extra pass over every masked actor/prop. It is deliberately stripped to coverage-only (no AA/TAA/shadow atlas, coarse LOD); re-enabling any of that, or letting it inherit the project's 3D supersample again, doubles the frame cost of a level full of props with no visual gain.
- **Risk:** The ink's suppression window must be sized off width_px, NEVER off the mask's resolution — scaling it off the mask texel erases world ink several px out from every actor, a distance-invariant bare halo you can spot people by. Nothing resolution-derived may reach the shader; mask_resolution below 1.0 widens that band and is the one saving here that is not free.
- **Risk:** If the Forward+ depth prepass is ever disabled the normal buffer stops filling and the CREASE lines quietly disappear, leaving silhouettes only — no error, just fewer lines.
- **Risk:** The contact merge (contact_merge_m) deletes a real SILHOUETTE whenever the surface behind it is nearer than the threshold, which is exactly what makes a stack of slabs read as one solid — and also what makes a crate parked against a wall, a low ledge, or a doorway into a shallow alcove lose the line that said they were separate things. It is measured in world metres, so it does NOT relax with distance the way every other term here does. Nothing errors; the frame just reads flatter.
- **Risk:** The seam merge (crease_min_feature_px) is the ONE crease term that only ever REMOVES lines, and it decides by screen-space width alone: raise it and small real features (a reveal, a trim, a stair tread at distance) silently lose their interior lines while their silhouettes stay — nothing errors, the world just reads flatter far away, and a tread that projects narrower than the reach loses its line and gets it back as you approach. It does not touch the depth term, so a genuine gap between two pieces still draws. concave_crease_strength below 1 removes the floor/wall junction and every inside corner along with the slab-on-wall lines it is aimed at — they are the same crease.
- **Test:** `tests/test_ink_outline.gd`

## Interaction

### `class LookAtInteractable` - `scripts/components/look_at_interactable.gd`

Owns the duck-typed talk-handler surface (start_talk/can_be_talked_to/look_name/host_npc/set_look_highlight) + TALK_LAYER hitbox + outline that PickupRay resolves and calls by name, so every interactable subclass plugs into the ray unchanged.

- **Risk:** Rename or re-signature a talk-handler method (start_talk/can_be_talked_to/look_name/set_look_highlight): PickupRay's has_method calls silently no-op, so the subclass stops interacting/highlighting with no error or failing call-site test.
- **Risk:** A subclass overrides _ready without super() or without setting collision_layer=TALK_LAYER (Merchant-style): the talk ray never hits the hitbox (the base _ready() is the only thing joining the talk layer) and the object is silently un-interactable.
- **Test:** `tests/test_look_at_interactable.gd`

### `class PickupRay` - `scripts/components/ray_cast.gd`

_query_talk_handler is THE line-of-sight wall-gate for every look-at interactable (pickup/loot/talk/doors): its talk-ray is gated by _interaction_occluded (a second solid-body ray, target's own bodies excluded). interact_available()/pending_verb_action() answer "would an F press DO something right now?" — the Interact half of the contextual-key rule for BOTH fallbacks that share a key with it (scripts/player/lean.gd on Q, scenes/player/flash_light.gd on F); it must stay in lockstep with the PickUp branch of _unhandled_input.

- **Risk:** Broaden the occlusion mask or drop the target-own-body exclusion (_interaction_occluded's collision_mask + _target_body_exclusions): silent interact-through-walls, or a dropped item self-occludes and is unpickable on open floor.
- **Risk:** Break the closer-prop block (_closer_prop_blocks — the _talk_distance / is_ancestor_of guard, now shared by the PickUp press, _update_talk_target and interact_available): a covered NPC lights up/reads out through a crate, or a dual item's own body blocks its own stash.
- **Risk:** Add an outcome to the PickUp branch without adding it to interact_available(): a fallback claims that press instead and the new interact silently never fires — the lean swallows it on Q, and on F the FLASHLIGHT toggles over it. The reverse is now just as costly: widen interact_available() and F stops reaching the torch for as long as the new condition holds (this is why carrying a prop, which is true the whole time you carry it, needs L as the torch's second key).
- **Risk:** Remove either liveness bail (the `player as Character` is_alive() gates at the TOP of _unhandled_input AND _physics_process): a mid-death-cinematic F/Z/click grabs/interacts/throws — the prop survives the revive or freezes the cinematic — or the corpse camera keeps painting the hover outlines/readout and greeting NPCs it sweeps across.
- **Risk:** Fold the per-prop throw_impulse_mult multiply INTO the throw test (launch_impulse / is_throw_release read the RAW impulse first): a fast-throw prop's gentle tap-DROP then scales past the throw threshold and silently noses, plays the throw sound, and credits the player with an attack.
- **Test:** `tests/test_interaction_occlusion.gd` `tests/test_pickup_ray_liveness.gd` `tests/test_interact_prompts.gd` `tests/test_carry_step_over.gd` `tests/test_throw_release_policy.gd`

## Minimap

### `class StationMarker` - `scripts/components/station_marker.gd`

ensure(station, kind) is the ZERO-AUTHORING seam: every station calls it once from its own _ready, so dropping a bare Merchant / Atm / Healer prefab into a level puts it on the minimap with no tick and no child node to remember — and an AUTHORED StationMarker child always wins, which makes a hand-placed one both the retune (kind, colour, nudged position) AND the hide switch (enabled = false). Verbatim the StationSpeaker.ensure bargain. Joins Groups.MINIMAP_STATION (never Groups.MINIMAP): the station channel is painted with its own glyph alphabet, and a station riding a dialogue NPC must keep its disposition-tinted NPC dot, which joining MINIMAP would suppress via Minimap._paint_markers' de-dupe.

- **Risk:** ensure() is runtime-only (Engine.is_editor_hint bails) — a @tool station must never spawn nodes into a scene the designer is editing, or the marker gets SAVED into the .tscn and then a second one spawns beside it at run time.
- **Risk:** pin_offscreen defaults from the station's own `standalone` flag, so a WALL KIOSK points at itself from the rim while a VENDOR ON A WALKING NPC does not. Hardcoding pin = true would make every shopkeeper a permanent rim blip — the "that is a radar, not a floorplan" line Minimap already refuses to cross.
- **Test:** `tests/test_station_marker.gd`

### `class FloorplanSection` - `scripts/ui/floorplan_section.gd`

view_transform() is THE single projection the HUD minimap draws through: handed to draw_set_transform_matrix(), it maps world (x, z) metres straight onto the Control's pixel space, so the baked floorplan, the optional authored underlay and every marker dot share ONE matrix and can never fork projections. walkable_triangles() turns the level's BAKED NavigationMesh into a flat triangle list for one floor band — the day-one picture, needing no authored texture and no MapData; it reads the same three accessors NavMeshAudit / NavLinkPlanner already rely on (get_vertices / get_polygon_count / get_polygon). silhouette() is the wall layer's boolean UNION: every cut ring is differenced against the other solids' grown outlines with Geometry2D.clip_polyline_with_polygon, so a level built from overlapping boxes prints one merged outline instead of a stack of them. It runs on the LINES, never on the areas, because merge_polygons' outer/hole winding cannot survive being folded over N rings two at a time.

- **Risk:** A section cut renders ONLY the band it cuts — a mezzanine, catwalk or stair tread above the cut plane is invisible by construction, and a flight of stairs reads as a gap between two bands.
- **Risk:** band_floor quantises the player's ORIGIN Y and never raycasts down: get_world_3d().direct_space_state returns EMPTY, silently, outside a physics frame — a previously-shipped bug class in this project.
- **Test:** `tests/test_floorplan_section.gd`

### `class FloorplanSource` - `scripts/ui/floorplan_source.gd`

gather(root, hide_group) is the ONE place level geometry becomes minimap geometry: it walks a level subtree once and converts every STATIC collider into a world-space convex hull or triangle soup, which slice() then cuts at any height. Split out of FloorplanSection precisely so that file can stay pure and provable.

- **Risk:** The static gate is `is StaticBody3D and not is AnimatableBody3D` — a TYPE, never a physics layer. Not because the layers overlap: characters are collision_layer 2 (Player.tscn, enemy.tscn) and level brush geometry is collision_layer 1 / collision_mask 0 (func_godot worldspawn / func_geo / func_detail), so a mask COULD tell a body from a wall. Layer 1 is the ENGINE DEFAULT, though, so it is also where every static thing that never touches the field lands — world brushes, props and door bodies alike (door.tscn's DoorPivot/DoorBody is a bare StaticBody3D). A mask cannot make the one distinction this picture needs, wall vs. movable leaf, and would silently drop any prefab a future author puts on another layer.
- **Risk:** AnimatableBody3D INHERITS StaticBody3D (verified against the engine), so the naive `is StaticBody3D` gate silently includes door leaves and bakes them shut forever. The exclusion is load-bearing, not tidiness.
- **Risk:** CSGShape3D is NOT a CollisionObject3D — in Godot 4.7 that `is` check will not even parse — so a CollisionShape3D walk finds NOTHING on a CSG blockout level. Those need the separate bake_collision_shape() branch, and CLAUDE.md names CSG as the blockout pipeline for new levels.
- **Test:** `tests/test_floorplan_source.gd`

### `class MapGlyph` - `scripts/ui/map_glyph.gd`

The pure SHAPE vocabulary the HUD minimap paints its markers with: shape_points() returns a closed polygon in SCREEN pixels (markers paint after draw_set_transform_matrix(IDENTITY), so a glyph is zoom-invariant by construction), npc_shape()/npc_is_hollow() map a body's live allegiance onto one of those shapes, and StationMarker.glyph_shape()/glyph_angle() map a station's Kind onto the rest. SHAPE is the primary channel and HUE is the secondary one, deliberately: at marker radius ~4 px a salmon neutral and a red hostile are the same dot (and Settings.colorblind_safe_cues exists precisely because hue is contested), so the hostile/friendly/neutral distinction is carried by triangle/circle/ring FIRST and by CBPalette second.

- **Risk:** Fill vs stroke is the family separator (NPCs are FILLED and small, stations are STROKED and larger). Painting a station filled — or an NPC stroked — collapses the two families into one alphabet, because TRIANGLE means "hostile body" in one and "somewhere to rest" in the other.
- **Test:** `tests/test_map_glyph.gd`

### `class Minimap` - `scripts/ui/minimap.gd`

AUTHORED SCENE: scenes/ui/hud_minimap.tscn, instantiated by ui.gd into the _weighted carrier (top-right corner, shared with the quest tracker). The SCENE owns the box — anchors, offsets, z_index, texture filter and the two art slots — and ui.gd MEASURES it back through UI.minimap_box() so the clock and the objective tracker reflow when an artist drags it. Geometry comes from the level's baked NavigationMesh via FloorplanSection, paint from MenuStyle.hud.minimap_*, fallback layout from GameSettings.hud.minimap_*, and the player's choices are polled LIVE off Settings.minimap_enabled / _rotates / _zoom so an Options change bites the same frame with no rebuild. THE ART SANDWICH — the artist's drop-in surface, and the reason this widget is a scene at all. This script's _draw is ONE layer; the scene wraps it in two empty full-rect slots whose TREE ORDER is the render order: %MapUnder (forced show_behind_parent in _ready, so the slot NAME is the contract rather than a checkbox an artist must remember) renders wholly BEHIND the plan — a backdrop supplied there wants the ALPHA of MenuStyle.hud.minimap_backing_color zeroed so it shows through, the alpha-as-null sentinel this project already uses for StationMarker.color — and %MapOver renders wholly IN FRONT of plan, markers, caret and rim, which is where a bezel/frame/glass/vignette belongs (a NinePatchRect there beats minimap_frame_texture's plain stretch). THREE LIMITS: art cannot be inserted BETWEEN the plan and the marker channels (they are one _draw), everything is clipped to the box by clip_contents below, and art children need NO repaint wiring at all — each is its own CanvasItem, so nothing an artist adds can touch _needs_repaint / _painted / the drawn stamps. ⚠ The live READ is only half of that: a Control repaints solely on queue_redraw, so it also takes the drawn-options stamps below to notice the row moved — without them the live read is a lie for any player who is standing still (see the queue_redraw @risk). The level swap is detected from the Groups.NAVMESH region's INSTANCE ID, not a GameRoot signal — a freed region leaves the group by itself, so the deck cache self-heals across a LevelDoor transition and this widget needs no new wiring in game_root.gd. The authored underlay is per-level: LevelData.map_data, PULLED (never pushed) by _resolve_level_underlay inside rebake() — the same region-instance-id hook — via Groups.GAME_ROOT's `level`. The widget's own map_data export is a per-instance override that wins when set, and a level without an authored map CLEARS the previous level's art (the stamp writes null too). THREE marker channels, painted in this order and each with its own rules: Groups.MINIMAP (POI beacons — a plain dot, PINS to the rim), Groups.MINIMAP_STATION (station glyphs — stroked shapes, pin per StationMarker.pin_offscreen), Groups.NPC (bodies — filled shapes by allegiance, NEVER pinned). A node in two channels is drawn by both on purpose: a shop riding a dialogue NPC is both a place to trade and a body with an allegiance. SHAPE is the primary marker channel and HUE the secondary one (MapGlyph): hostile caret / ally diamond / friendly dot / neutral ring, and seven stroked station shapes. At a ~4 px radius hue alone could not carry the distinction, and Settings.colorblind_safe_cues exists because it is contested even at size.

- **Risk:** Renders ONLY the player's own floor band, so a mezzanine or catwalk above the cut is invisible and a staircase reads as a gap between two decks.
- **Risk:** An unbaked level has no walkable fill and a level with no static colliders has no walls; either degrades to a partial map in silence, because both are legitimate states. Minimap.deck_count() is the introspection seam when a level looks blank.
- **Risk:** A hostile's alert ring reads NPC.suspicion_of(player), which is target-gated — it only ever reports awareness OF THE PLAYER, never of another NPC. Widening it to is_in_combat() (target-agnostic) would ring every guard fighting a stray dog and read as "they are onto you".
- **Risk:** A CanvasItem repaints ONLY on queue_redraw(), and the idle gate deliberately withholds that from a standing, still player — so every fact this picture shows owes the gate a way to ask for the ONE repaint that takes it back OFF the canvas when it stops being true. _needs_repaint is that gate, and three of its terms exist purely as those trailing edges (_painted for the marker channels, the drawn-options stamps for the player's Options rows, the drawn-skin stamp for the ARTIST's hud_skin.tres). A new painted channel added without one strands its art on the map forever.
- **Risk:** Never draw a sight CONE here. Perception.can_see() raycasts, and _draw/_process run OFF the physics frame where direct_space_state returns EMPTY silently — a cone would look right in tests and report "sees nothing" in play. The authored sight_range/fov_degrees would draw a cone that is also a wallhack.
- **Test:** `tests/test_minimap.gd`

### `class MinimapArt` - `scripts/ui/minimap_art.gd`

The PRECEDENCE and SIZING rules for every drop-in marker texture the minimap can wear. Statics only, and the skin arrives as a PARAMETER (never MenuStyle.hud), so every rule here is provable off-tree against a bare HudSkin.new() — the FloorplanSection / MapGlyph promise, verbatim. THE BOUNDARY between the two artist surfaces: the SCENE (scenes/ui/hud_minimap.tscn's %MapUnder / %MapOver) owns whole-box LAYERS, and the SKIN owns per-MARKER glyphs. A scene node cannot draw a badge at a position recomputed every frame, which is exactly why these three families — the player caret, the POI beacon, the seven station badges — are skin slots and the backdrop/frame are not.

- **Risk:** Art replaces a marker's SILHOUETTE only. Position, SIZE and TINT stay owned by the knobs (MenuStyle.hud.minimap_*_px, beside the colours) and by the colour the channel already resolved, so a delivered PNG can never encode its own size and fight the canvas's ~2.4x nearest upscale, and can never break the colour contract (a station's per-instance StationMarker.color, the EXIT exception, the off-floor alpha fade).
- **Test:** `tests/test_minimap_art.gd`

## NPC AI

### `class AiLod` - `scripts/components/ai_lod.gd`

AiLod is the ONE cadence gate on npc.gd's decision layer: NPC._physics_process asks think_delta() each tick whether to run its brain, and moves (gravity / move_and_slide) regardless of the answer.

- **Risk:** A force_full regression throttles a FIGHTING NPC — the one case that must never degrade.
- **Risk:** Banding off Groups.PLAYER instead of Groups.human_player silently disables LOD near any companion.
- **Test:** `tests/test_ai_lod.gd`

## NPC Brain

### `class GoapExecutor` - `scripts/npc/goap/goap_executor.gd`

tick() replans only when the current action is null/invalid, else steps act(); FAILED drops the plan; _build_world_state never senses sentinel facts.

- **Risk:** If _build_world_state senses a sentinel fact, its goal self-satisfies -> plan()=[] -> select_goal skips it, so that behaviour silently never runs.
- **Risk:** decide() resets index=0, so if tick() replanned every frame a multi-step plan (reload->shoot) would never advance past step 0 - silent, no error.
- **Risk:** advance() must drop the plan on FAILED, else a still-valid failing action is re-stepped every tick - the NPC sticks, no error.
- **Test:** `tests/test_goap_executor.gd` `tests/test_goap_combat_brain.gd` `tests/test_goap_combat_selection.gd`

### `class NPC` - `scripts/npc/npc.gd`

_build_components builds one GoapExecutor per NPC; _physics_process ticks it as the sole AI decision layer in both physics branches (the no-target branch and the has-target branch).

- **Risk:** An early-return or reorder before _executor.tick in either _physics_process branch (no-target / has-target) silently stops that NPC deciding, no error.
- **Risk:** _perception.sense must precede the has-target _executor.tick in _physics_process; the executor reads _perception.state (GoapExecutor._build_world_state), so reordering picks the wrong arm silently.
- **Risk:** In-tree tick and _act_* delegate bodies have no automated coverage (tick is playtest-only per README) — a broken build/ordering shows only in playtest.
- **Test:** `tests/test_npc_goap_library.gd` `tests/test_npc.gd`

## Options Settings

### `autoload InputManager` - `managers/InputManager.gd`

get_action_binding(action) is the sole binding-query seam (display_key is a kept alias); validate_action_sources() cross-checks the three action-name surfaces (project.godot [input] / action_* vars / ActionCatalog) and _warn_on_action_drift() push-warns per drifted name at boot on dev builds.

- **Risk:** A new action_* var without an ActionCatalog row (or a catalog row on a dead InputMap action) still needs the catalog / _CONTROLLER_ONLY fixed by hand — the boot audit REPORTS the drift, it does not auto-repair it.
- **Test:** `tests/test_input_manager.gd`

### `autoload Settings` - `managers/Settings.gd`

Each option = a typed var + a set_* setter that applies live (DisplayServer/AudioServer/GameSettings) and re-saves settings.cfg; gameplay reads Settings.<field> directly.

- **Risk:** A field left out of apply_all (or a setter skipping apply) persists but never takes effect on boot; nothing round-trips save->load (tests set _loaded=false).
- **Risk:** A bus fade/duck that samples the live AudioServer bus instead of current_bus_db() ratchets volume down on rapid re-trigger — silent audio drift; every duck in the project (death world duck, dialogue, ADS) now derives its restore target from current_bus_db, so re-introducing a live-bus snapshot is the regression to watch for.
- **Risk:** Moving a typed field into a Variant dict silently breaks gameplay's direct Settings.<field> reads and the bare-instance test that reads them.
- **Risk:** project.godot `display/window/size/no_focus=true` makes the game window VANISH the moment apply_video enters WINDOWED (Godot's Windows DisplayServer drops WS_VISIBLE + refuses click-activation for a no_focus main window; fullscreen masks it entirely) — pinned by tests/test_windowed_mode.gd, cleared at runtime by apply_video (dev builds also warn once).
- **Risk:** Windowed placement is measured, not assumed: apply_video fits the DECORATED frame to the screen's usable rect (largest preset that fits, else clamp — windowed_size is MUTATED to the effective size) and centres it; a frame-counted guard undoes the OS's occasional post-fullscreen restore jump. Re-centring happens only when the mode or size actually changes, so VSync/FPS/scale never yank a dragged window.
- **Risk:** mouse_sensitivity is radians per SCREEN pixel (MouseInput reads screen_relative; `relative` is pre-scaled by canvas/window width under the viewport stretch mode, so it made look speed ride the window size). It persists under the cfg key mouse_sensitivity_screen; a pre-switch cfg carries the OLD key mouse_sensitivity in canvas-px units and read_mouse_sensitivity rescales it ONCE by LEGACY_MOUSE_SENS_SCALE (792/1920). Writing the old key again, or reading `relative` again, hands returning players a ~2.4x faster look.
- **Test:** `tests/test_settings.gd` `tests/test_difficulty.gd` `tests/test_windowed_mode.gd`

### `class SettingSpec` - `resources/settings/SettingSpec.gd`

One Options row as DATA (widget + getter/setter names); OptionsMenu emits each value row from SettingsCatalog.tres, resolving each spec's getter/setter on the Settings autoload BY NAME.

- **Risk:** getter/setter resolve on Settings BY NAME (options_menu.gd _spec_current/_spec_setter): a typo or renamed setter breaks that one row only at menu-open; caught by test_settings_catalog if run.
- **Risk:** A generic DROPDOWN loses its options on an editor .tres re-save -> empty in-game menu; window_mode/colorblind/difficulty stay CUSTOM (code-built) to dodge it (a recurred bug).
- **Risk:** Hand-authoring a KEYBIND row in the catalog instead of ActionCatalog.tres double-authors the Controls tab (keybind rows are appended from the ActionCatalog).
- **Test:** `tests/test_settings_catalog.gd` `tests/test_options_menu.gd` `tests/test_difficulty.gd`

### `class ActionCatalog` - `scripts/input/action_catalog.gd`

keybind_specs() turns its ActionSpec rows into the Controls-tab SECTION+KEYBIND SettingSpecs OptionsMenu appends to SettingsCatalog; the action name is the stable rebind key.

- **Risk:** A dropped/renamed ActionSpec silently drops its Controls rebind row (no runtime error) since keybind_specs skips it; caught only at test time by the EXPECTED_REBINDABLE pin.
- **Risk:** Keybinds bind LIVE in _input via Settings.rebind_action, bypassing the _pending/Apply staging other rows use — the key-press IS the confirmation, not an Apply-staged value.
- **Risk:** project.godot [input], InputManager action_* vars, and ActionCatalog.tres must stay in lockstep; drift yields an un-rebindable action or a catalog row on a dead InputMap action — now caught at boot (dev builds) by InputManager.validate_action_sources()'s push_warning, not only at test time.
- **Test:** `tests/test_action_catalog.gd` `tests/test_input_action_catalog.gd` `tests/test_input_manager.gd`

## Passive Item Buffs

### `class PassiveItemBuffs` - `scripts/components/passive_item_buffs.gd`

Exposes a stat_modifier/speed_multiplier/apply_effect surface Character sums/multiplies; held strength re-stamps via CharacterStats.restamp_derived; serializes nothing.

- **Risk:** If max_hp is ever serialized as a stored number, the held +HP/+carry delta double-counts each reload; the carrier silently gains stats, no error.
- **Risk:** If _restamp tracked the ideal delta instead of restamp_derived's real post-floor return, dropping a negative-strength item silently inflates max_hp/carry above base.
- **Risk:** If apply_effect or the method names drift from Character's has_method scanner, every held buff silently stops folding into live stats/speed, no crash.
- **Test:** `tests/test_passive_item_buffs.gd`

## Player Abilities

### `class Ability` - `scripts/components/abilities/ability.gd`

An enabled Ability child grants the mechanic keyed by ability_id(); has_mechanic, unlocked_list (save) and the runtime rebuild all match that id. The grant/revoke/persistence bookkeeping lives in AbilityManager (a Player-owned RefCounted); the Player keeps only the typed hot-path refs + physics beats.

- **Risk:** A subclass that forgets to override ability_id() defaults to &"" (the ability_id() base return): present but grants no queryable mechanic — silent, no crash.
- **Risk:** An id whose ability script is absent from disk (breaks the AbilityRegistry snake_case naming convention) can't be rebuilt on save-load or paid install (AbilityManager._build -> null, silently grants nothing); AbilityRegistry.can_build + the drift test guard it.
- **Test:** `tests/test_upgrades.gd`

### `class ChipInstaller` - `scripts/components/chip_installer.gd`

Paid-install chokepoint: a chip Item (installs_ability) -> permanent mechanic via can_grant guard -> charge -> consume -> unlock_mechanic + autosave.

- **Risk:** Drop the pre-charge can_grant_mechanic guard (in install_carried + buy_and_install): a typo'd installs_ability then silently takes money + eats the chip for nothing.
- **Risk:** Rename install_carried/install_fee: ChipInstallScreen's has_method duck-calls fail silently (the screen's sections go dead); the dialogue's 'Install' OPTION itself now rides the dialogue_station_option/open_dialogue_station station contract, where a rename likewise silently drops the button — both surfaces pinned by tests/test_dialogue_speaker_contracts.gd.
- **Test:** `tests/test_chip_install.gd`

## Player Movement

### `class Lean` - `scripts/player/lean.gd`

THE contextual-key arbiter for the lean keys: owns_action() is what SilentTakedown / PetInteraction ask before charging, and Player.pending_verb_actions() is what this asks before claiming a press.

- **Risk:** Drop the owns_action() gate in a verb driver (SilentTakedown / PetInteraction _can_run) and a lean that sweeps an eligible target into the crosshair silently charges that verb UNDER the peek — no error, just a kill you didn't ask for.
- **Risk:** Move the lean onto the player's CollisionShape3D instead of the head rig: every movement system assumes the capsule is where the body is, and a peeking capsule clips cover / desyncs what NPCs shoot at.
- **Test:** `tests/test_lean.gd`

## PS1 Warp

### `file ps1_applier.gd` - `scripts/effects/ps1_applier.gd`

Runtime ShaderMaterial overrides on opaque BaseMaterial3D surfaces only, skipping Character/Throwable/Camera3D; live-scaled by Settings.ps1_warp_intensity, and 0% restores originals.

- **Risk:** If _warp's Character/Throwable/Camera3D skip regresses, actor outline/hit-flash and the FP view-model warp silently — no test covers the subtree walk.
- **Risk:** If _restore stops clearing overrides or restoring cast_shadow, 0% no longer returns the world to normal — an accessibility regression with no round-trip test.
- **Test:** `tests/test_ps1_applier.gd` `tests/test_effects.gd`

### `autoload Ps1Warp` - `scripts/effects/ps1_warp.gd`

GameRoot drives Ps1Warp.cover() on level load; cover() parents ONE ps1_applier under the LevelRoot (freed with it), not a global SceneTree.node_added listener.

- **Risk:** If the LevelRoot gate breaks or GameRoot stops calling cover(), levels get no applier and the PS1 look silently disappears; test_level_data.gd::test_game_root_load_level_covers_a_levelroot_with_the_ps1_warp asserts the applier attaches on load.
- **Test:** `tests/test_global_node_added_listeners.gd` `tests/test_level_data.gd`

## Quests

### `autoload QuestTracker` - `managers/QuestTracker.gd`

QuestTracker OWNS the live quest tracker (active/completed/failed + objective progress) and the four quest signals; GameState keeps one-line forwarders so authored content and old call sites keep working. save_into/load_from write and restore the [quests_active]/[quests_completed]/[quests_failed] cfg sections; GameState._save_perks_and_quests / _load_perks_and_quests delegate their quest halves here. notify_kill/pickup/talk/enter/use + notify_flag_set are the world's hooks INTO quests — one shared _advance_objectives_matching body behind all of them.

- **Risk:** A quest transition that forgets _gs().autosave_world_state() leaves progress unpersisted until an unrelated money/xp event happens to coincide — the classic "Continue lost my progress" bug.
- **Risk:** _grant_quest_rewards early-returns off-tree, so a bare test grants NOTHING (not even reputation); asserting rewards without a live player silently passes for the wrong reason.
- **Risk:** Restoring a quest whose .tres moved drops it SILENTLY — the _load_warnings array is the only surface that tells the player, and it is consume-once.
- **Test:** `tests/test_quests.gd` `tests/test_quest_tracker.gd`

## Rendering

### `class WorldGhost` - `scripts/effects/world_ghost.gd`

An offscreen never-cleared SubViewport keeps a running average of the FINISHED frame (it samples the

- **Risk:** The display is itself part of the frame that gets averaged — a feedback loop. It is stable only
- **Risk:** The accumulator averages the WHOLE window, including any CanvasLayer above this one. The display
- **Test:** `tests/test_world_ghost.gd`

## Run And Level Flow

### `class GameRoot` - `scripts/world/game_root.gd`

GameRoot is game.tscn's level-load seam: resolve_boot_level picks the boot level (saved-by-path beats export); load_level swaps the single "Level" child and seeds PlayerSpawn + respawn.

- **Risk:** resolve_boot_level diverging from _ready's respawn_level_matches gate boots the WRONG level yet keeps the saved respawn — silent, no crash (both must read saved_level_is_bootable).
- **Risk:** A should_place_at_spawn regression either clobbers a loaded game's restored respawn with the export spawn, or strands the player at stale wrong-level coords (should_place_at_spawn + _place_player_at_entry's re-seed).
- **Risk:** If load_level's detach-rename-queue_free swap regresses (the _LevelFreeing rename before remove_child/queue_free), two "Level" children stack or refs to the freed level dangle mid-frame — silent stale geometry.
- **Test:** `tests/test_level_flow.gd` `tests/test_level_boot_lifecycle.gd` `tests/test_level_data.gd`

### `class LevelData` - `scripts/world/level_data.gd`

resource_path persists as GameState.current_level_path for Continue; a non-null `scene` gates boot-viability, else GameRoot uses the exported level. map_data (the authored minimap underlay) is PULLED by the HUD's Minimap widget, never pushed: Minimap._resolve_level_underlay reads Groups.GAME_ROOT's `level` inside rebake() on every region swap, so the underlay needs no wiring in game_root.gd or ui.gd.

- **Risk:** A LevelData with a blank/unstable resource_path persists no resolvable path, so Continue silently boots the export, losing the saved level (GameRoot.load_level's set_current_level, read back by resolve_boot_level).
- **Risk:** A saved LevelData whose `scene` is null is rejected by resolve_boot_level, which silently boots the export instead of the saved level (GameRoot.saved_level_is_bootable's scene != null check).
- **Test:** `tests/test_level_data.gd` `tests/test_level_flow.gd`

## Save Model

### `autoload GameState` - `managers/GameState.gd`

The additive per-object ledger world_objects[level][key]=state (record_object_state/object_state/has_object_state) persists Door open/locked + consumed-pickup/destroyed-prop 'gone' bits per authored object.

- **Risk:** A changed WorldSaveId key or a stricter load_from_disk Dictionary-shape filter silently drops ledger entries — pickups respawn (free money), doors revert, smashed props un-smash; load still returns true.
- **Risk:** Reading a 'gone' bit with bare truthiness instead of GameState.as_bool falsely despawns a fresh pickup (or crashes via bool(<String>)) on a hand-edited String value.
- **Risk:** A new persistable object type not wired through record_object_state + a save_id export silently never enters the ledger — its state just doesn't persist.
- **Test:** `tests/test_game_save.gd`

### `autoload GameState` - `managers/GameState.gd`

capture() -> save_to_disk atomically write the versioned user://gamestate.cfg; load_from_disk restores it and sets loaded/profile_active, the flags gating Player._ready — a checkpoint, not a world snapshot.

- **Risk:** Breaking _write_atomic's tmp->bak->rename rotation (e.g. dropping the Windows remove-before-rename guard) only loses the sole save on a real crash; the happy path keeps succeeding, so tests never surface it.
- **Risk:** A field wired into only some of capture/save_to_disk/load_from_disk silently defaults on Continue; a STAT_NAMES rename with no SAVE_VERSION migration drops those points (cf. load_from_disk's legacy stat folds).
- **Risk:** Dropping capture()'s Zorkmids.ITEM_ID skip double-counts money on load; applying respawn_position while ignoring respawn_level_matches teleports the player into the wrong level.
- **Risk:** The dev sandbox (enable_sandbox / resolve_save_path) redirects the five canonical save paths at exactly six seams — a new read/write of SAVE_PATH / QUICKSAVE_PATH / slot_path that skips resolve_save_path silently sees or writes the REAL profile while a console `sandbox on` is in force.
- **Test:** `tests/test_game_save.gd` `tests/test_save_slots.gd` `tests/test_debug_sandbox.gd`

### `file world_save_id.gd` - `scripts/world/world_save_id.gd`

WorldSaveId.key_for(node, save_id): an authored save_id is the whole key 'id:<x>' (survives moves), else a level|path|position (_round_cm) fallback — the shared GameState.world_objects key generalizing Corpse.save_key().

- **Risk:** Changing the fallback shape (node_path source or _round_cm precision) silently re-keys every un-authored object, so its saved state stops matching on reload — no error.
- **Risk:** Moving/renaming a hand-placed node between saves silently orphans its fallback-keyed state; give important objects/bodies a save_id or their world-state is lost after any layout edit.
- **Test:** `tests/test_game_save.gd`

## Save Model — the EXACT-snapshot tier (authored-NPC death/position + cross-level deaths + container contents)

### `file world_snapshot.gd` - `scripts/world/world_snapshot.gd`

Rides the MANUAL quicksave/slot layer ONLY: built in GameState._capture_and_write, written as a sibling [world_snapshot] cfg section, applied by GameRoot.load_level (central push) gated on consume_world_snapshot(). The lean Dark-Souls autosave/Continue NEVER carries one — see GameState.autosave (nulls it) + save_to_disk.

- **Risk:** This is a SEPARATE product from the profile save. Never merge it into GameState's profile fields / capture() or the two blur the moment autosave runs (CLAUDE.md "Save semantics must be explicit"). world_objects is untouched.
- **Risk:** NPC identity is POSITION-INDEPENDENT (NPC.snapshot_key), NOT WorldSaveId.key_for — an NPC moves, so a position-keyed match would fail against the reloaded node sitting at its authored .tscn spot.
- **Test:** `tests/test_world_snapshot.gd`

## Wait

### `autoload WaitScreen` - `scripts/ui/wait_screen.gd`

Autoload modal opened by its OWN key (InputManager.action_wait, default T — the Fallout 3/NV key); the QuestJournal idiom where the screen owns its keypress rather than something else opening it. THE ONE CALLER of WorldClock.advance_hours: confirming walks the span and emits every day/night boundary crossed, so rent falls due, bank interest posts and NPC schedules move exactly as if the hours had been lived. Waiting must never route through set_time_of_day (that is the silent seek, and using it here is the free-rent exploit). Refusal is polled off StealthStatus.of_player — the SAME aggregate the stealth HUD reads — so "someone is hunting you" means one thing across the game rather than two.

- **Risk:** Refuses to OPEN when blocked rather than opening a disabled card: the screen frees the mouse, and freeing it mid-firefight would be worse than the missing panel. The reason goes out as a toast so the key never reads as dead.
- **Risk:** Waiting deliberately does NOT heal to full or mend limbs (GameSettings.wait) — a Bonfire rest is the full restore AND the respawn checkpoint, and a wait that matched it would make fires pointless.
- **Test:** `tests/test_wait_screen.gd`
