# Slice Test Level Guide

This guide shows how to build the `SliceTestLevel` mission slice as a human
designer in the Godot editor. It uses only the project's normal authoring
surfaces: a level scene, a `LevelData` resource, an `Item`, a `Quest`, a
`DialogueResource`, and drop-in components.

The finished loop is:

1. The player accepts `Recover the Package` from a quest board.
2. The player crosses a guarded yard.
3. The player picks up the `Sealed Package`.
4. The player returns to a relay terminal.
5. The terminal completes the quest and the HUD shows the quest-complete toast.

## Files

The built slice uses these authored files:

| Purpose | Path |
| --- | --- |
| Level scene | `res://scenes/levels/SliceTestLevel.tscn` |
| Level data | `res://resources/levels/SliceTestLevel.tres` |
| Quest item | `res://resources/items/slice_package.tres` |
| Quest | `res://resources/quests/recover_the_package.tres` |
| Terminal dialogue | `res://resources/dialogue/slice_relay_terminal.tres` |

> **Beyond the core loop.** The shipped `SliceTestLevel.tscn` also carries extra sandbox props this step-by-step does not build: a crouch `TutorialPrompt`, a CSG `BuildingShell` + `BlockoutFloor` interior with a locked `Door` (opens with a `lockpick`), a `DogCrate`, a merchant NPC (`Talkable` + `Merchant` + `Restocker` + `StockEntry`), and a `radio` `Throwable`. They pack more components into one test scene; ignore them if you only want the recover-the-package loop.

## 1. Create the Level

1. Duplicate `res://scenes/levels/LevelTemplate.tscn`.
2. Save it as `res://scenes/levels/SliceTestLevel.tscn`.
3. Keep the root node named `Level` and keep the `LevelRoot` script on it.
4. Keep the standard child buckets:
   - `NavigationRegion3D`
   - `WorldEnvironment`
   - `DirectionalLight3D`
   - `Characters`
   - `Lights`
   - `Geometry`
   - `Objects`
   - `Graffitti`
   - `PlayerSpawn`

The buckets are not magic except for their groups and scripts, but they keep the
scene readable. Put walkable/static world geometry under `Geometry`, NPCs under
`Characters`, and interactables under `Objects`.

## 2. Create the LevelData

1. Duplicate `res://resources/levels/LevelTemplate.tres`.
2. Save it as `res://resources/levels/SliceTestLevel.tres`.
3. Set:
   - `scene = res://scenes/levels/SliceTestLevel.tscn`
   - `display_name = Slice Test Level`

Run levels through `res://scenes/game.tscn`. To start directly in this level,
select the `GameRoot` node in `game.tscn` and set its `level` export to
`res://resources/levels/SliceTestLevel.tres`.

## 3. Block Out the Playspace

Build a compact "in, grab, out" arena:

1. Move `PlayerSpawn` near the south end of the level.
   - In the current slice it is at approximately `(0, 1.5, 14)`.
2. Add a long approach lane from spawn toward the yard.
3. Add a wider guard yard near the north side.
4. Add an objective pad in the yard center.
   - In the current slice the pad is around `(0, 0.13, -12)`.
5. Add perimeter walls so the testbed is bounded.
6. Add four cover blocks:
   - two near the approach lane
   - two inside the yard
7. Add a cool light near spawn and a warm light over the objective pad.
8. Add two throwable cubes near spawn for distraction/physics testing.

Use simple `MeshInstance3D` box meshes and matching `StaticBody3D` +
`CollisionShape3D` children for any geometry that should block the player or
NPCs.

## 4. Bake or Provide the Navmesh

The slice needs a clean, one-island navmesh so the raider NPCs can move.

Editor workflow:

1. Make sure walkable floor geometry is under a node in the `navmesh` group.
   The template's `Geometry` bucket already has this group.
2. Select `NavigationRegion3D`.
3. Confirm its `NavigationMesh` settings:
   - `geometry_source_geometry_mode = Group With Children`
   - `geometry_source_group_name = navmesh`
   - `Parsed Geometry Type = Static Colliders` (NOT the default "Both" — else decorative meshes with no collider bake walkable and NPCs stick on them)
   - `agent_height = 2.2`
   - `agent_radius = 0.6`
   - `agent_max_climb = 0.4`
   - `agent_max_slope = 30.0`
4. Click `Bake NavigationMesh`.
5. Select the level root and check `LevelRoot` inspector warnings.

For this greybox, a single flat baked island is enough. If NPCs pace in place or
stand on props, re-bake and run the navmesh audit tool described in the main
authoring guide.

## 5. Author the Package Item

> **AI-text scrub — shipped text is deliberately blank or `[PH] `-marked.** The
> `description`/`text` values in §5–§7 are authoring suggestions only: the shipped
> `slice_package.tres`, `recover_the_package.tres`, and `slice_relay_terminal.tres`
> author NO descriptions and NO dialogue text (per the project-wide AI-text scrub —
> never refill them), so the terminal's lines and turn-in button render BLANK until
> a designer types them in (`dialogue_view.gd` sets labels straight from `text`, no
> empty-string fallback). The strings that DO ship (`title`, `giver_npc`,
> `display_name`, `prompt_label`, `pickup_label`) carry the `[PH] ` placeholder
> prefix, never stripped at display time — the board reads
> `[PH] Accept Job: Recover the Package`, and `PlayerText.quest_complete` adds its
> own `[PH] `, so the toast reads `[PH] Quest complete: [PH] Recover the Package`
> (double-prefixed). This guide quotes values without the prefix.

Create a new `Item` resource:

1. In the FileSystem, right-click `res://resources/items/`.
2. Choose `New Resource`.
3. Pick `Item`.
4. Save it as `res://resources/items/slice_package.tres`.
5. Set:
   - `id = slice_package`
   - `display_name = Sealed Package`
   - `description = A taped courier package with no sender name. The relay terminal is waiting for it.`
   - `category = MISC`
   - `max_stack = 1`
   - `weight = 1.0`
   - `value = 75.0`
   - `grid_width = 2`

The `id` is the important part. The pickup objective and relay terminal gate
both match on `slice_package`.

## 6. Author the Quest

Create a new `Quest` resource:

1. In the FileSystem, right-click `res://resources/quests/`.
2. Choose `New Resource`.
3. Pick `Quest`.
4. Save it as `res://resources/quests/recover_the_package.tres`.
5. Set:
   - `id = recover_package`
   - `title = Recover the Package`
   - `description = A package is sitting in the raider yard. Slip in, grab it, and bring it back to the relay terminal.`
   - `auto_complete = false`
   - `giver_npc = Slice Job Board`
   - `reward_money = 120.0`
   - `reward_xp = 35.0`
   - `reward_reputation = { "townsfolk": 8 }`

Add one objective in the `objectives` array:

1. Set the array size to `1`.
2. Create a new `QuestObjective` in element `0`.
3. Set:
   - `id = recover_package`
   - `description = Recover the sealed package from the lit pad in the guard yard.`
   - `type = PICKUP`
   - `target_id = slice_package`
   - `required_count = 1`
   - `optional = false`
   - `show_marker = true`
   - `marker_position = Vector3(0, 0.5, -12)`

Why `auto_complete = false`: picking up the package completes the objective, but
the quest itself should stay active until the player returns to the relay
terminal.

Marker note: `show_marker` only authors the objective's marker data. To actually
spawn compass/minimap markers in a level, add one `QuestMarkerSync` node anywhere
in the scene.

## 7. Author the Relay Terminal Dialogue

Create a new `DialogueResource`:

1. In the FileSystem, right-click `res://resources/dialogue/`.
2. Choose `New Resource`.
3. Pick `DialogueResource`.
4. Save it as `res://resources/dialogue/slice_relay_terminal.tres`.
5. Add two `DialogueLine` entries.

Line `0`:

- `text = Relay uplink online. Active jobs can be closed here.`
- Add one `DialogueChoice` entry (the shipped `slice_relay_terminal.tres` has
  exactly one choice; add a second `text = Leave.`, `target = -1` choice if you
  want an explicit back-out).

Choice `0`:

- `text = Transmit recovered package.`
- `target = 1`
- `required_item_id = slice_package`
- `required_quest_id = recover_package`
- `required_quest_state = ACTIVE`
- `complete_quest_id = recover_package`

Line `1`:

- `text = Package accepted. Payment transferred.`

The important part is the first choice: it is only selectable when the player
has the package and the quest is active, and it calls `GameState.complete_quest`
through the authored `complete_quest_id` field.

Shipped state: `slice_relay_terminal.tres` authors ONLY the gating fields on the
choice — no `text` on either line or the choice (see the scrub note in §5). The
loop still works blank: the choice gates and completes, its button just has no
label.

## 8. Add the Quest Board

In `SliceTestLevel.tscn`, under `Objects`, create a `QuestBoard` node:

1. Add a `Node3D` named `QuestBoard`.
2. Position it near spawn, around `(-4.2, 1.2, 13)`.
3. Add a `MeshInstance3D` child named `BoardMesh`.
   - Use a simple `BoxMesh`, roughly `Vector3(2.6, 1.55, 0.25)`.
   - Give it a readable material.
4. Add an `Area3D` child named `QuestStarter`.
5. Attach `res://scripts/components/quest_starter.gd`.
6. Add a `CollisionShape3D` child under `QuestStarter`.
   - Use a `BoxShape3D`, roughly `Vector3(2.9, 1.8, 0.7)`.
7. Set `QuestStarter` exports:
   - `highlight_target = ../BoardMesh`
   - `quest = res://resources/quests/recover_the_package.tres`
   - `prompt_label = Accept Job: Recover the Package`

At runtime, aiming at this board and pressing Interact starts the quest.

## 9. Add the Relay Terminal

Under `Objects`, create a `RelayTerminal` node:

1. Add a `Node3D` named `RelayTerminal`.
2. Attach `res://scripts/components/dialogue_npc.gd`.
3. Position it near spawn, around `(4.2, 0.8, 13)`.
4. Set:
   - `dialogue = res://resources/dialogue/slice_relay_terminal.tres`
   - `display_name = Relay Terminal`
5. Add a `MeshInstance3D` child named `TerminalMesh`.
   - Use a simple `BoxMesh`, roughly `Vector3(1.4, 1.2, 0.8)`.
6. Add an `Area3D` child named `RangeArea`.
7. Add a `CollisionShape3D` under `RangeArea`.
   - Use a `BoxShape3D`, roughly `Vector3(1.8, 1.6, 1.2)`.
8. Back on `RelayTerminal`, set:
   - `range_area = RangeArea`

`DialogueNPC` makes the whole terminal an inanimate speaker. The `RangeArea`
is the look-at hitbox the player aims at.

## 10. Add the Package Pickup

Under `Objects`, create a `PackagePickup` node:

1. Add a `Node3D` named `PackagePickup`.
2. Position it on the objective pad, around `(0, 0.55, -12)`.
3. Add a `MeshInstance3D` child named `PackageMesh`.
   - Use a simple `BoxMesh`, roughly `Vector3(0.8, 0.35, 0.55)`.
   - Give it a cardboard-like material.
4. Add an `Area3D` child named `CanPickUp`.
5. Attach `res://scripts/components/can_pick_up.gd`.
6. Add a `CollisionShape3D` under `CanPickUp`.
   - Use a `BoxShape3D`, roughly `Vector3(1.15, 1.0, 1.15)`.
7. Set `CanPickUp` exports:
   - `highlight_target = ../PackageMesh`
   - `item = res://resources/items/slice_package.tres`
   - `pickup_label = Take Sealed Package`

When the player picks this up, `CanPickUp` grants the item and calls
`GameState.notify_pickup(slice_package)`, which advances the quest objective.

## 11. Add the Guards

Under `Characters`, instance two copies of `res://scenes/characters/NPC.tscn`.

Guard 1:

- Node name: `YardGuard`
- Position: around `(-7, 0, -8.5)`
- `display_name = Yard Guard`
- `faction = res://resources/factions/raiders.tres`
- `alert_radius = 10.0`
- `gunfire_noise_radius = 16.0`
- `sight_range = 11.0`
- `fov_degrees = 95.0`
- `time_to_detect = 0.9`
- `forget_time = 4.0`
- `wanders = true`
- `wander_radius = 5.0`

Guard 2:

- Node name: `YardLookout`
- Position: around `(7, 0, -10)`
- Use the same faction and wander settings, but give it a longer `sight_range = 24.0` (the lookout sees farther than the guard's `11.0`).

This gives the yard enough pressure to demonstrate stealth, distractions, and
combat without needing a custom encounter script.

## 12. Add Decoy Cubes

Under `Objects`, instance two copies of `res://scenes/throwable/cube.tscn`.

Suggested positions:

- `DecoyCubeLeft`: `(-4, 0.5, 9)`
- `DecoyCubeRight`: `(4, 0.5, 8)`

These give the player an immediate toy to throw or carry while testing the
approach.

## 13. Make Quest Completion Toasts Visible

Quest-complete toasts are already emitted by the HUD when `GameState` emits
`quest_completed`. Terminal turn-ins happen from dialogue, and dialogue hides
the notices layer, so the HUD queues quest transition toasts during dialogue and
flushes them when the conversation closes.

The relevant script is `res://scripts/ui/ui.gd`:

- `_on_quest_completed` pushes `PlayerText.quest_complete(quest.title)` (the
  `[PH] Quest complete: {title}` template)
- `_push_quest_toast` queues quest toasts while `DialogueManager.is_active()`
- `_flush_dialogue_toasts` shows the queued messages on `dialogue_finished`

For the slice, this means choosing the terminal's transmit choice shows the
quest-complete toast after the dialogue closes (shipped:
`[PH] Quest complete: [PH] Recover the Package` — template prefix + prefixed
title, see the scrub note in §5).

Current handoff note: this terminal choice checks that the player carries
`slice_package` and completes the quest, but it does not consume/remove the item
from inventory. Add an item-consumption consequence later if the package should
leave the backpack on turn-in.

## 14. Playtest Checklist

Run `res://scenes/game.tscn` with `GameRoot.level` set to
`res://resources/levels/SliceTestLevel.tres`.

Check:

1. The player spawns near the board and terminal.
2. Aiming at the board shows its accept prompt (`QuestStarter.prompt_label`,
   shipped `[PH] `-prefixed).
3. Interacting with the board starts the quest.
4. The quest appears in the journal.
5. The package is visible on the lit objective pad.
6. The two raiders are in the yard and can detect/fight the player.
7. Picking up the package advances the objective.
8. The relay terminal offers its gated transmit choice only while the quest
   is active and the player has the package (shipped, the button renders blank —
   unauthored text — but still gates and completes).
9. Choosing that option completes the quest.
10. After dialogue closes, the HUD shows a quest-complete toast.
11. Money, XP, and townsfolk reputation rewards are granted.

## 15. Common Mistakes

- If the quest does not start, check `QuestStarter.quest` and make sure the
  board's `CollisionShape3D` covers the mesh you aim at.
- If pickup does not advance the objective, check that the `Item.id` and
  `QuestObjective.target_id` both equal `slice_package`.
- If the terminal choice is locked, check that the player actually picked up the
  package and that the choice uses `required_quest_state = ACTIVE`.
- If the terminal completes nothing, check `complete_quest_id = recover_package`
  on the dialogue choice.
- If NPCs do not move, check that the floor is baked into the navmesh and that
  `agent_max_climb` is still around `0.4`.
- If a quest marker does not appear, add one `QuestMarkerSync` node to the level
  and confirm the objective has `show_marker = true`.
- If the player can run the package mission repeatedly in one save, remember
  that `QuestStarter` refuses active/completed quests, and — since world-object
  save v1 — a consumed `CanPickUp` (like the package) records a "gone" bit in
  `GameState.world_objects` (keyed by level + `WorldSaveId`), so the collected
  package stays gone across a save/reload. Set the pickup's `save_id` if it must
  survive scene edits; otherwise it falls back to a level/path/position key. Still
  not persisted by THIS ledger: containers, dead NPCs, and dynamic/loot-dropped
  spawns — it's an additive named-object ledger, not an exact world snapshot. Dead
  authored NPCs and authored-container contents DO survive a manual quicksave/slot
  save, which carries the separate exact-snapshot tier on top (see the roadmap in
  `docs/CURRENT_ARCHITECTURE.md`); Continue alone re-seeds them.
