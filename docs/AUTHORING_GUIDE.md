# CYBER SUNDAY -- Level Designer's Authoring Guide

Welcome. This guide is for the person who builds CYBER SUNDAY **inside the Godot editor** -- placing nodes in a scene, filling in `@export` fields in the Inspector, and authoring `.tres` Resources. You will not write a line of GDScript. Everything in the game -- a raider who shoots on sight, a townsperson who flees when shot, a vending machine you can "talk" to -- is reachable by dropping a component into a scene and editing its fields. If you ever feel like you *need* to open a script to get something done, that is a bug in the design, not in you; flag it.

## The philosophy: designer-first

The whole project is built around one rule: **the editor is the modding surface.** Every feature lands in one of three forms, and you author all three the same way -- in the Inspector.

- **Behaviour = a drop-in component.** A behaviour is a `class_name` Node or Area3D you attach *in the scene* and configure with `@export` fields. You want an NPC to be talkable? You don't edit the NPC's brain -- you drop a `Talkable` (`res://scenes/dialogue/talkable.tscn`) under it and fill in its `dialogue` field. Behaviour is something you *attach*, never a branch buried in a big script.
- **Tunables = an `@export` or a tuning Resource.** Every number a designer might want to change -- a sight range, a fire rate, a wander radius -- is an `@export` on the component (per-instance) or lives in a `resources/tuning/*.tres` group on the `GameSettings` registry (global). Numbers are never hardcoded constants.
- **Content = authored `.tres` Resources.** Factions, weapons, dialogue, NPC archetypes, loot tables -- these are data files you create and edit in the Inspector (`Faction`, `WeaponData`, `DialogueResource`, `NpcData`, `LootTable`). Make one once, reuse it everywhere.

When something feels repetitive (you've overridden 30 fields on five raiders), that's the signal to lift it into a Resource -- author an `NpcData` archetype once and assign it to all five via their `profile` field.

## The golden rules

1. **Edit `@export` fields in the Inspector -- that's where the game lives.** Select a node, look at the Inspector panel, change the value. That is authoring. You do not need the code to change behaviour.
2. **After adding a new script or new `@export` fields, RELOAD the project so they appear.** Godot caches `class_name` types and exported properties. When a new component or a new field has just been added, the Inspector may not show it (or may show a "Could not find type X" error and cascade) until you reload: **Project -> Reload Current Project**. If a dropdown or field looks missing or wrong, reload first before assuming it's broken.
3. **Never hardcode a tunable.** If you find yourself wishing a number were editable, it should be an `@export` or a `GameSettings` tuning entry -- not a value you ask an engineer to change in code. Tune it in the Inspector; if the knob doesn't exist yet, that's a request, not a workaround.
4. **Commit the `.gd.uid` sidecar files.** Every script has a little `.gd.uid` file next to it that pins its stable identity. These are **tracked** -- when you add a new script or component, commit its `.gd.uid` alongside it, or other people's scenes will lose the reference. Don't delete them.

## Your first 10 minutes

A quick end-to-end loop so you can feel how authoring works. You'll open a level, drop in an NPC, give it an attitude and something to say, and watch it run.

1. **Open a level.** Open `res://scenes/TestLevel.tscn` (or `TestLevel_2.tscn`) from the FileSystem dock. This is a playground scene with ground, navigation, and a player spawn already wired -- a safe place to drop things. (The game itself boots at `res://scenes/start_menu.tscn`, set as the main scene.)
2. **Drop in an NPC.** Drag `res://scenes/enemies/NPC.tscn` into the scene tree as a child of the level, then move it somewhere on the ground in the viewport. That single scene is *every* non-player actor in the game -- civilian to combatant -- driven entirely by the fields you set next.
3. **Give it a faction (its attitude).** Select the NPC and find the **Hostility** group in the Inspector. Set the **`faction_id`** dropdown to `townsfolk` -- now it resolves to the Townsfolk faction (`NEUTRAL` toward the player; it won't attack unless provoked). Pick `raiders` instead and it's `HOSTILE` on sight. (Leave `faction_id` empty and the standalone **`disposition`** field takes over -- `HOSTILE` / `NEUTRAL` / `FRIENDLY`.) While you're here, type a **`display_name`** under the Identity & Outline group -- it shows as the speaker label in dialogue. For a civilian, leave **`weapon_data`** (under Weapon) empty: no faction is needed to talk, only to fight.
4. **Give it something to say.** First make the conversation: in the FileSystem dock, right-click -> **Create New -> Resource -> `DialogueResource`**, save it as e.g. `res://resources/dialogue/greeter.tres`. Open it and add entries to its **`lines`** array -- each is a `DialogueLine` with a **`text`** field (leave `choices` empty for a line that just plays). Then drop `res://scenes/dialogue/talkable.tscn` as a child of your NPC, select that `Talkable`, and assign your `greeter.tres` to its **`dialogue`** field. (Leave its `display_name` blank and it borrows the NPC's.)
5. **Press Play.** Run the scene (F6 for the current scene). Walk up, **look at** the NPC (the Talkable is a look-at target, not a proximity trigger -- you have to aim at it) and press **E** to talk. A neutral townsperson will turn, face you, and read its lines; a raider will open fire instead.

That's the entire loop: a scene, a dropped component, a few Inspector fields, an authored Resource. Every feature in this guide is a variation on it.

**Gotchas**
- **A field or `faction_id` option looks missing?** Reload the project (Rule 2). New exports and `class_name` types don't show until Godot rescans.
- **NPC won't talk?** Talk is **look-at**, not walk-into-range -- aim the crosshair at the body and press E. Also check the `Talkable.dialogue` field is actually assigned, and that the NPC isn't `HOSTILE`/in combat (a fighting NPC refuses to talk -- it only fights).
- **Edited a `.tres` but nothing changed in-game?** Make sure you saved the Resource (Ctrl+S in its Inspector) and that it's the same file the node points at -- it's easy to edit one copy and reference another.
- **A profiled NPC's inline fields are overwritten by default.** If an NPC has an `NpcData` assigned to its `profile`, that archetype stamps ~50 fields at spawn and your inline overrides are ignored -- edit the archetype `.tres`, clear `profile` to tune inline, or tick `profile_fills_blanks_only` to keep your per-instance tweaks (additive merge).

## Contents

1. Orientation: how authoring works here
2. Building a level scene
3. Placing and configuring NPCs
4. Customising an NPC look (body/head/limbs)
5. Factions, disposition and reputation
6. Authoring dialogue
7. Items, loot, money and pickups
8. Weapons and ammo
9. The drop-in component catalogue
10. Global tuning (GameSettings) and the settings menu
11. NPC services and progression (shops, healing, companions)
12. Atmosphere: radio, music and movement FX

---

## Orientation: how authoring works here

Welcome. In CYBER SUNDAY you build the game the way you'd mod one: almost everything is done **inside the Godot editor** by placing nodes, ticking boxes in the **Inspector**, and editing `.tres` Resource files. You should rarely (ideally never) need to open a script. The whole project is built around a single rule, spelled out in `rpg/CLAUDE.md`: *every feature must be reachable without touching code.* When you want behaviour, you drop in a pre-made node; when you want to change a number, you edit an `@export` field or a tuning Resource; when you want new "stuff," you author a Resource. That's it.

### The three authoring surfaces

Everything you'll ever do falls into one of three buckets. Learn to recognize which one your task is, and you'll always know where to go.

**1. Behaviour â†’ a drop-in component (a node you attach in-scene).**
A component is a node with its own `class_name` and a set of `@export` knobs. You drag it into your scene, point it at the thing it should affect, and configure it in the Inspector â€” no branching logic, no scripting. These live in `rpg/scripts/components/` (and their abilities in `rpg/scripts/components/abilities/`). Examples you'll use constantly: `LookAtInteractable` and its family (the ones that extend it â€” `CanPickUp`, `MoneyPickUp`, `ItemContainer`, `Merchant`, `LootableCorpse`), plus standalone drop-ins like `Lock`, `CanDestroy`, `SpawnOnDestroy`, `Throwable`, `Healer`, `Bonfire`, `Radio`, and `UpgradePickup`. The abilities (all extending `Ability`) â€” `Slide`, `WallClimb`, `Grapple`, `AirDash`, and `LaserSight` â€” drop under the Player. Some ship as ready-made one-node scenes in `rpg/scenes/components/` (e.g. `container.tscn`, `merchant.tscn`, `radio.tscn`, plus the ones in `scenes/components/abilities/`) so you can drag the whole thing in at once.

**2. Tunables â†’ an `@export` field, or a tuning Resource on the GameSettings registry.**
There are two flavours of "numbers you tune":
- **Per-instance** tuning is an `@export` right on the component you placed â€” e.g. a `MoneyPickUp`'s `amount`, or a weapon's `pellet_count`. You change it only for that one node, in the Inspector.
- **Global** tuning lives in `rpg/resources/tuning/*.tres` â€” one Resource per system (`PlayerMovementSettings.tres`, `CameraSettings.tres`, `WeaponGeneralSettings.tres`, `EconomySettings.tres`, `ScreenShakeSettings.tres`, and so on). These are all registered on the **`GameSettings`** autoload, and code reads them as `GameSettings.<group>.<field>` (for example `GameSettings.camera.default_fov`). Edit the `.tres` and the change applies everywhere that system is used. (You'll also find player-facing options like volume, FOV, and sensitivity exposed in the in-game settings menu â€” but for design-time tuning, the `.tres` files are your home base.)

The golden rule: if a designer might ever want to tune it, it is **never** a hardcoded constant â€” it's an `@export` or a tuning Resource.

**3. Content â†’ authored Resources (`.tres`).**
Content is the catalogue of "what exists": weapons, items, characters, throwables. Each is a Resource you create and fill in via the Inspector. They live under `rpg/resources/` by kind:
- `resources/weapons/` â€” `WeaponData` (e.g. `pistol.tres`, `shotgun.tres`, `melee.tres`)
- `resources/items/` â€” inventory `Item`s (`healthpack.tres`, `ammo_pistol.tres`, â€¦)
- `resources/characters/` â€” character/stat resources (`DefaultCharacterRes.tres`, `character_stats.tres`)
- `resources/interactables/` â€” `ThrowableData` (`wooden_crate.tres`, `gore_gib_data.tres`)
- plus `resources/dialogue/` and `resources/factions/`

A `StockEntry`, `Loadout`, or `NpcData` is the same idea: data you author, then hand to a component via one of its `@export` slots (for example `Merchant.stock_counts` takes an `Array[StockEntry]`, `swap_weapons.gd` takes a `Loadout`, and `npc.gd` takes an `NpcData`).

### How it all fits in a scene

A level is a scene (`.tscn`) under `rpg/scenes/`. You'll see existing levels like `rpg/scenes/TestLevel.tscn` and `rpg/scenes/TestLevel_2.tscn`, plus building blocks in `scenes/components/`, `scenes/props/`, `scenes/enemies/`, and `scenes/weapons/`. The flow is always the same: **drop a component node** (surface 1), **set its `@export` fields** (surface 2), and where it asks for content, **assign a `.tres`** (surface 3). Behaviour is composed from nodes, never hidden in a monolithic script â€” so you can add, remove, or rearrange features just by editing the scene tree. Most drop-in components also ship a ready-to-drag template under `scenes/components/` (e.g. `talkable.tscn`, `can_destroy.tscn`, `noise_source.tscn`): instance the `.tscn` to get the node pre-built with its collider/visual and `@export` wiring instead of assembling it by hand.

### A quick worked example: a coin the player can grab

1. Open a level scene, e.g. `rpg/scenes/TestLevel.tscn`.
2. Add a child node and set its type to **`MoneyPickUp`** (a drop-in component â€” surface 1). With no model assigned it builds a default gold coin and auto-fits its own pickup hitbox (it sets `auto_fit_collider`), so a bare node already works.
3. In the Inspector, set **`amount`** to the value you want (this is the per-instance `@export` â€” surface 2). Optionally set `pickup_label`, or assign a `world_model` PackedScene to swap the coin for a custom mesh.
4. Play the level, aim at it, and press the interact key (**E**, the `PickUp` action) â€” it credits the player's wallet via `add_money`, toasts the gain, and removes itself.

No code was written: a node, an `@export`, done. If you instead wanted to change how the economy behaves broadly, you'd edit `resources/tuning/EconomySettings.tres` (surface 2, global). If you wanted a new kind of item to exist, you'd author a new `.tres` (surface 3).

### Opening and playing a level

The game's main scene is `res://scenes/start_menu.tscn` (set in `rpg/project.godot` under `run/main_scene`), so pressing **F5 (Run Project)** boots the start menu. While iterating on a specific level it's faster to open that level's `.tscn` in the editor and press **F6 (Run Current Scene)** â€” that launches the level you're looking at directly, skipping the menu.

### The #1 gotcha: the editor must reload before new fields/scripts appear

This will trip you up once, so internalize it now: **after you add or change `@export` fields, or add/modify a script or `class_name`, the editor needs to reimport/reload before the change shows up.** A brand-new component type may not appear in the "add node" list, a new `@export` may be missing from the Inspector, or a scene may momentarily look empty ("node count is 0") right after an edit. **This is not a bug.** As `rpg/CLAUDE.md` notes, right after edits the editor reimports and can briefly yield empty PackedScenes or "File not found" â€” give it a moment, or trigger a reload (re-focus the editor, or use *Project â†’ Reload Current Project*), and the new fields and types appear. If something looks broken seconds after an edit, wait and retry before assuming you did anything wrong â€” it clears on its own.

**Gotchas**
- New component type not in the add-node list, or a missing `@export`? The editor hasn't rescanned yet â€” reload/reimport, don't re-author.
- Per-instance vs global tuning are different surfaces: an `@export` on the node changes only that one placement; a `resources/tuning/*.tres` change is global. Pick deliberately.
- Don't hand-edit a "number" in a script â€” if it's tunable it already lives on an `@export` or a tuning Resource. Find it there instead.
- Components are designed to work bare (sensible defaults, null-guards), so an unconfigured drop-in won't crash â€” but assign its content `.tres` and point its `@export` targets to get the behaviour you actually want.
- The interact verb is the `PickUp` input action (bound to **E**), not an action literally named "Interact" â€” keep that in mind if you go looking in the Input Map.

Key paths to remember (all under the repo's `rpg/` folder): drop-in components â†’ `rpg/scripts/components/`; global tuning â†’ `rpg/resources/tuning/`; content Resources â†’ `rpg/resources/<kind>/`; levels and building blocks â†’ `rpg/scenes/`.

---

## Building a level scene

A level in CYBER SUNDAY is just a `Node3D` scene full of instanced props, lights, characters, and exactly one `WorldEnvironment`. The shipped example is `res://scenes/TestLevel.tscn` (root node **`Level`**, a plain `Node3D`). It is *instanced*, not run directly: `res://scenes/game.tscn` (root **`Game`**) is the real entry point â€” it adds the `Level` instance, a `Player`, the `SkyTitle` ("CYBERSUNDAY") banner, and the ambience/music players (which live under the `Player`). So the rule of thumb is: **build your world in a level scene, then drop that scene into a Game-style wrapper that supplies the Player.**

### The level root layout

Open `TestLevel.tscn` and you'll see the root's direct children are organised into a handful of grouping `Node`s. This is the layout to mirror in a new level:

| Child of `Level` | Type | What lives here |
|---|---|---|
| `NavigationRegion3D` | `NavigationRegion3D` (group `navmesh`) | the baked navmesh NPCs walk on |
| `AmbientDust` | instance of `scenes/effects/ambient_dust.tscn` | floating dust motes (its `motes` field is set to `1600`) |
| `WorldEnvironment` | `WorldEnvironment` (group `world_environment`) | the sky / fog / ambient (one per level) |
| `DirectionalLight3D` | `DirectionalLight3D` | the moonlight key light |
| `Characters` | plain `Node` | every NPC instance (`NPC.tscn`, `medicine_person.tscn`, â€¦) |
| `Lights` | plain `Node` | the `OmniLight3D` / `SpotLight3D` street lights (several carry a child `AudioStreamPlayer3D` buzz) |
| `Geometry` | `Node3D` (group `navmesh`) | static world: buildings, roads (the `Asphalt` `MeshInstance3D`), cars, trees, rocks, containers â€” anything the navmesh bakes from |
| `Objects` | plain `Node` | dynamic/throwable props â€” `cube.tscn`, `trash.tscn`, and the `Radio` Area3D (parented under one of the cubes) |
| `Graffitti` | plain `Node` | decal `Sprite3D`s |

These grouping nodes are pure organisation â€” they have no scripts. Use them so the scene tree stays legible; nothing breaks if you add another category. (You'll also notice some props instanced straight onto the root at the bottom of the file â€” that works too, it's just messier. Prefer the buckets above.)

**Where new content gets parented:**
- A new **NPC** â†’ instance `res://scenes/enemies/NPC.tscn` (an armed combatant), `res://scenes/enemies/civilian.tscn` (a non-combat townsperson — townsfolk faction, flees threats, pre-wired with a `Talkable`), or `res://scenes/medicine_person.tscn` under `Characters`, then set its `@export` fields in the inspector (`display_name`, `faction`, `profile`, `weapon_data`, `wanders`, `sight_range`, â€¦). Drop a `talkable.tscn` instance under the NPC to make it conversational (set its `dialogue` and `voice`).
- A new **static prop / building** â†’ under `Geometry`, so the navmesh carves around it (see "Navigation" below).
- A new **pickup / throwable / interactable** â†’ under `Objects` (e.g. another `cube.tscn`).
- A new **light** â†’ under `Lights`.

### The WorldEnvironment (sky, fog, ambient)

The `WorldEnvironment` node holds one `Environment` resource and is tagged with the group **`world_environment`**. That group name is load-bearing: the **`StarSky`** autoload (`res://scripts/effects/star_sky.gd`, registered in `project.godot`) listens for any node entering the tree that is a `WorldEnvironment` *or* in that group, and repaints its sky at runtime. So whatever sky you author in the inspector is a *seed* â€” StarSky takes it over when the game runs. Two things happen, non-destructively (your saved `.tscn` is never modified):

1. **Horizon sky.** StarSky reads your `Environment.sky`. If its material is a `PanoramaSkyMaterial`, it grabs that material's `panorama` texture and rebinds it onto the `horizon_sky.gdshader` (`res://resources/shaders/horizon_sky.gdshader`), which lays the image *flat along the horizon as a band* (cylindrical) instead of the pinched equirectangular sphere mapping. In `TestLevel` the authored panorama is `res://HDI.png`. A level with **no** panorama just renders the shader's gradient + amber haze (the shader's `use_panorama` uniform is left `false`).
2. **Pinned mood.** The authored env lights its ambient from the (bright) sky, which washes everything white. StarSky overrides that: it forces `ambient_light_source` to a fixed **colour** (`GameSettings.effects.sky_ambient_fill`, default `Color(0.05, 0.07, 0.13)`), disables sky reflections (`reflected_light_source` â†’ disabled), and lifts `background_energy_multiplier` off a pathological `0`. Note `TestLevel`'s env ships at `background_energy_multiplier = 0.0` precisely because StarSky will lift it â€” that's intentional, not a mistake.

**What *you* still author on the Environment** (StarSky leaves these alone): the volumetric fog and tonemap. In `TestLevel`'s env those are `tonemap_mode = 4` (AgX), fog on (`fog_mode = 1`) with `fog_density = 1.0` / `fog_sun_scatter = 1.0`, and `volumetric_fog_enabled = true` (`anisotropy 0.1`, `sky_affect 0.33`). Tune fog/tonemap here per level for the look you want.

**Tunables you control without code:**
- **The sky look** lives on the shader uniforms â€” select the live `ShaderMaterial` at runtime, or set sane defaults by editing the `.gdshader`. The designer-facing uniforms are: `pano_yaw` (rotate the image), `pano_tiles` (how many times it wraps â€” raise if a non-panoramic photo looks stretched), `band_bottom` / `band_top` / `edge_fade` (where the image band sits on the horizon and how it blends), the four colours `zenith_color` / `horizon_color` / `ground_color` / `haze_color`, and `gradient_power`, `haze_height`, `haze_strength`, `sun_glow`, `sun_azimuth`. (`flash` / `flash_color` are driven by StarSky's kill flash â€” don't hand-set them.)
- **The pinned ambient tint and the kill-flash timing** live on the `GameSettings.effects` registry (the `EffectsSettings` resource, `res://resources/tuning/EffectsSettings.tres`), under the **Sky FX** group: `sky_ambient_fill`, `sky_flash_up_time` (`0.04`), `sky_flash_down_time` (`0.35`). These are global, not per-level.

### Navigation

NPCs path on the `NavigationRegion3D` child. Its `navigation_mesh` is a baked `NavigationMesh` whose bake settings are authored in the inspector â€” and the key field is `geometry_source_geometry_mode = 1` ("Group Explicit") with `geometry_source_group_name = &"navmesh"`. **That is why `Geometry` is in the `navmesh` group:** only nodes in that group feed the bake. The region itself is also in `navmesh`. Other tuned bake fields you can see: `cell_height = 0.01`, `agent_height = 2.2`, `agent_radius = 0.6`, `region_min_size = 0.1`, `edge_max_error = 0.1`, `filter_low_hanging_obstacles = true`, and `navigation_layers = 4294967295` (all layers, set on the `NavigationRegion3D` node).

To author navigation in a new level: put your walkable floor + obstacle meshes under a node in the `navmesh` group, select the `NavigationRegion3D`, and click **Bake NavigationMesh** in the toolbar. The region's `visible = false` just hides the debug overlay â€” it stays functional. **If NPCs won't move, the usual cause is the mesh wasn't baked or the geometry isn't in the `navmesh` group.**

### Worked example: a new "alley" level

1. **File â†’ New Scene**, root = `Node3D`, rename it `Level`, save as `res://scenes/levels/Alley.tscn`.
2. Add children: a `NavigationRegion3D` (add it to group `navmesh`), a `WorldEnvironment`, a `DirectionalLight3D`, and empty `Node`s named `Characters`, `Geometry` (a `Node3D`, group `navmesh`), `Lights`, `Objects`.
3. On the `WorldEnvironment`: add it to group `world_environment`, give it a new `Environment`, set `background_mode = Sky`, and give the `Sky` a `PanoramaSkyMaterial` with your skybox image in `panorama`. Enable `volumetric_fog` and pick a tonemap. (StarSky handles the rest at runtime.)
4. Under `Geometry`, instance your buildings/roads (`scenes/props/store.tscn`, an `Asphalt` `MeshInstance3D`, etc.). Select the `NavigationRegion3D` â†’ **Bake NavigationMesh**.
5. Under `Characters`, instance `scenes/enemies/NPC.tscn`, set `display_name`, `faction`, `wanders = true`; drop a `talkable.tscn` under it for dialogue.
6. Under `Objects`, drop a couple of `scenes/throwable/cube.tscn` for physics props.
7. To play it, open a copy of `game.tscn`, swap the `Level` instance's scene for `Alley.tscn` (or make `Alley` the instanced level in your own Game wrapper) so it gets a `Player`.

### Gotchas

- **Don't fight StarSky in the inspector.** Tweaking `Environment.ambient_light_color` or background energy directly won't stick at runtime â€” StarSky re-pins them. Change the look via the shader uniforms and `EffectsSettings` instead.
- **The level scene has no Player.** Running `TestLevel.tscn` alone gives you a world with nothing to control. Always play through `game.tscn` (or your own Game wrapper) â€” that's where the `Player` instance and its spawn `transform` live.
- **Geometry must be in the `navmesh` group, then re-baked.** New static props added under `Geometry` are not walkable until you bake again; props placed *outside* a `navmesh`-group node are ignored by the bake entirely.
- **One `WorldEnvironment` per level.** StarSky drives its kill-flash on the *last* painted environment, so a second live env in the same scene would leave the first one's sky un-flashed.
- A panorama that isn't a true 360Â° photo will look stretched when wrapped â€” raise the shader's `pano_tiles` (and nudge `band_top` / `band_bottom`) to fix it.

Relevant files: `C:\Users\dalla\3D RPG\rpg\scenes\TestLevel.tscn`, `C:\Users\dalla\3D RPG\rpg\scenes\game.tscn`, `C:\Users\dalla\3D RPG\rpg\scripts\effects\star_sky.gd`, `C:\Users\dalla\3D RPG\rpg\resources\shaders\horizon_sky.gdshader`, `C:\Users\dalla\3D RPG\rpg\resources\tuning\EffectsSettings.gd` / `.tres`.

---

## Placing and configuring NPCs

Every non-player actor in CYBER SUNDAY -- from a townsperson who just wanders to a sniper who locks on and fires -- is the **same** `NPC` node (`rpg/scripts/npc/npc.gd`, `extends Character`). There are no enemy/civilian subclasses; behaviour is driven entirely by the inspector fields you set. This section walks you through dropping one in and configuring it.

### Step 1 â€” Instance the NPC scene

The ready-to-use prefab is `res://scenes/enemies/NPC.tscn`. It inherits from the base `enemy.tscn`, which already wires up the body mesh (`Man.glb`), the swappable head, the collision capsule, the `BodyModelSwap` re-skin component, and the `damaged`/`died` signal connections. (Ragdoll is set on `NPC.tscn` itself via `ragdoll_scene`, not on the base.) You almost never start from `enemy.tscn` directly -- `NPC.tscn` is the configured starting point.

1. In the scene you're building (e.g. `Level.tscn`), open the **Scene** menu or drag from the FileSystem dock: instance `res://scenes/enemies/NPC.tscn` as a child of your level.
2. Move/rotate it into place with the gizmo. The NPC remembers its spawn position and facing at `_ready` -- wandering strays from there, and after losing you it searches around that spot.
3. Select the instance and configure it in the **Inspector**. Everything below is an `@export` on the root node; you never open a script.

> If you need to tweak the body/head meshes or per-limb tints for this one instance, you don't have to enable "Editable Children" -- the root exposes the **Body & Head â†’ Custom Models** subgroup (`body_model`, `body_texture`, `body_color`, `head_model`, `arm_color`, `leg_color`, etc.). Set them right on the instance and that NPC re-skins live in the editor.

### Step 2 â€” The key inspector fields

#### Civilian vs combatant: `weapon_data` (group **Weapon**)

This single field decides what kind of actor you have:

- **`weapon_data` = null â†’ CIVILIAN.** No gun, no laser, no fire path is built. The NPC still senses, wanders, flees, faces toward whoever shot it, and can talk. The stock `NPC.tscn` actually ships a `melee.tres` here; clear it to null for a true unarmed townsperson.
- **`weapon_data` = a `WeaponData` .tres â†’ COMBATANT.** The NPC wields the *same* `Weapon` component the player does, aimed by the AI. It locks the nearest hostile (the player or a faction-opposed NPC), turns, aims, paints its laser, and fires once it has actually detected the target -- no 360-degree omniscience.

#### Attitude: `faction_id`, `disposition`, `disposition_overrides_faction` (group **Hostility**)

This is the FNV-style hostility model. Three fields work together:

- **`faction_id`** -- a dropdown (`PROPERTY_HINT_ENUM_SUGGESTION`) with `townsfolk`, `raiders`, `neutral_wildlife`. Pick one and it resolves to the matching Faction `.tres` (from `res://resources/factions/`) at `_ready`. A factioned NPC's attitude toward the player tracks the player's **reputation** with that faction, and it fights NPCs of opposed factions.
- **`faction`** -- a raw `Faction` slot, used only if you leave `faction_id` empty (for a custom/inline faction). Empty id **and** null faction = **UNALIGNED**.
- **`disposition`** (`Disposition.Kind`: `HOSTILE` / `NEUTRAL` / `FRIENDLY`) -- the standalone attitude, used **only when the NPC is unaligned** (no faction). It defaults to `HOSTILE`, so an armed NPC with no faction behaves like a classic enemy.
- **`disposition_overrides_faction`** -- set this true and the NPC's individual `disposition` wins toward the player even though it has a faction (the faction still drives reputation and NPC-vs-NPC relations). Use it for, say, one raider who's personally friendly to you.

The combat outline rim re-tints from this automatically: HOSTILE = red, FRIENDLY = green, NEUTRAL = the `outline_color` export (black by default). A recruited companion wears blue. (Those hostile/friendly/ally colours come from `CBPalette`, so with the colorblind-safe cues toggle on they shift to orange/cyan/periwinkle.) (`friendly_aggro_threshold`, also in this group, is how much accidental player damage a FRIENDLY ally forgives before it turns on you.)

#### Reaction: `threat_response` (group **Behavior**)

`threat_response` is a two-value enum:

- **`FIGHT`** (default) -- engage and shoot a noticed hostile (today's enemy).
- **`FLEE`** -- run away from the threat and never fire. Pair `FLEE` + `wanders` + a NEUTRAL/FRIENDLY disposition for a townsperson who only bolts when attacked.

(Related: `temperament` [0..1] is how readily a *fighter* breaks and flees once it's hurt mid-combat -- 0 = fearless, 1 = cowardly.)

#### Senses: the **Perception** group

These tune what the NPC can notice and how quickly:

- **`sight_range`** (m) -- how far it can see.
- **`fov_degrees`** -- full view-cone angle; anything outside this off its facing is invisible to it.
- **`time_to_detect`** (s) -- how long you must stay in the cone before it's fully alerted. This is the player's reaction window.
- **`forget_time`** (s) -- how long it stays wary at your last-known spot before giving up.
- **`turn_speed`** -- how fast it rotates to face what it's tracking (this one lives in the **Perception** group, not Movement). Higher = snaps onto aim quicker.

Also here: `crouch_sight_mult` (how much crouching shortens its sight), `eye_height` (where its rays start), `hearing` (notice gunfire/fast movement outside the cone), and `search_sweep_rate` (how fast it scans in a circle when looking around at a spot). The richer "hunt a widening area" search -- breadcrumbs around the last-known spot + a frantic→resigned falloff, and the [CAUTION] HUD readout while it hunts -- is a **global** tuning group: `GameSettings.search` (`SearchSettings.tres`). It's INERT (the single-point stare) until you raise its `max_search_radius` / `sample_points`. The per-archetype hunt mutter ("Where are you?") is gated by **`NpcData.search_barks`** (default on, alongside `damage_barks` / `death_barks`).

#### Loadout: `starting_items`, `item_stacks` (group **Inventory**)

These are the items the NPC actually **carries** -- pickpocketable and dropped on its corpse -- seeded on top of the weapon and ammo from `weapon_data`:

- **`starting_items`** -- an `Array[Item]`. Add a keycard, stims, junk. Add the same item twice for two of it. Weapons here are duplicated to unique instances; if a `starting_item` weapon is stronger than `weapon_data`, the NPC actually draws that one.
- **`item_stacks`** -- an `Array[ItemStack]`, the easy count-based form: "30 ammo, 2 stims" as item+count rows instead of repeating entries. Seeded alongside `starting_items`.

These are deterministic carried inventory. (The random drop table is a separate concept -- it lives on the `NpcData` profile's `loot` field, below.)

### Worked example â€” a fleeing townsperson

You want a civilian who roams the market and runs when shot at:

1. Instance `NPC.tscn`, position it in the market.
2. **Weapon â†’ `weapon_data`**: clear it to **null** (civilian).
3. **Hostility â†’ `faction_id`**: `townsfolk`. (Now their attitude tracks your town reputation.)
4. **Behavior â†’ `threat_response`**: `FLEE`; tick **`wanders`** on; set `wander_radius` to taste.
5. **Identity & Outline â†’ `display_name`**: e.g. "Market Vendor" so dialogue and the kill feed name them.
6. **Inventory â†’ `item_stacks`**: add a row (a `stims` Item, count 2) so the body is worth pickpocketing.

Drop them in, hit play -- they pace the stall, greet you, and bolt if you draw on them, never shooting back.

### Step 3 â€” Archetypes: the `NpcData` profile (group **Profile**)

Configuring ~40 fields per NPC by hand gets tedious when you're placing a dozen raiders. The **`profile`** export (top of the inspector, group **Profile**) takes an `NpcData` resource (`rpg/scripts/npc/npc_data.gd`) -- a reusable **archetype** that stamps roughly 40 tuning fields onto the NPC at once.

**How it works:** assign a profile and `NPC._apply_profile()` (the first line of `_ready`) copies the archetype's values onto the matching exports -- `display_name`, `max_hp`, `stats`, the whole Hostility block, `weapon_data` + weapon tuning, all of Perception, all of Movement, `threat_response`, `temperament`, wander settings, talk settings, and so on. So a "raider" / "townsperson" / "sniper" becomes **one resource assignment** instead of dozens of inline overrides. `NpcData` also carries a few extras the inline NPC doesn't: a `bark_set` (per-archetype voice lines) and a `loot` `LootTable` (random corpse drops on top of carried items).

**Profile vs inline:**

- **Assign a `profile`** â†’ the NPC is driven *entirely* by that archetype. Any value you also set inline is overwritten at `_ready`, so don't mix. To vary one stat, author a variant `.tres`.
- **Leave `profile` null** â†’ `_apply_profile()` is a no-op and your inline inspector values stand. Every existing scene does this, so they're unaffected.

**The additive merge (`profile_fills_blanks_only`):** by default a profile is all-or-nothing (it overwrites every field). Tick **`profile_fills_blanks_only`** on the NPC and it becomes ADDITIVE: the profile fills only the fields you left at their default, and any field you tweaked inline WINS -- so "use the raider archetype, but give THIS one more HP" works (assign the profile, tick the flag, bump HP). Cleanest from a blank base (`enemy.tscn` / `civilian.tscn`); `NPC.tscn` pre-sets combat fields (weapon, sight, fire range, ...) inline, so those would count as tweaks and win over the profile.

**When to use which:**

- **Use a profile** when you're placing several of the same kind of NPC, or want a named archetype you can retune in one place and have every instance pick up the change. Author them once in `res://resources/characters/` (right-click â†’ New Resource â†’ `NpcData`), like you author `WeaponData` or `Faction` .tres.
- **Tune inline** for a true one-off -- a single named boss or a unique scripted character that doesn't share its numbers with anyone.

To make a profile: in the FileSystem dock, create a new `NpcData` resource, fill in its grouped fields (Identity, Vitals & outline, Hostility, Weapon, Inventory, Perception, Laser, Movement, Behavior, Barks, AI (GOAP), Loot), save it, then drag it onto an NPC instance's `profile` slot.

### Gotchas

- **`weapon_data` is the civilian/combatant switch -- and the stock `NPC.tscn` is NOT a civilian.** It ships with `melee.tres` assigned. For an unarmed townsperson you must explicitly clear `weapon_data` to null.
- **`disposition` only matters when the NPC is unaligned.** If you set a `faction_id`, the standalone `disposition` is ignored toward the player unless you also tick `disposition_overrides_faction`. A common mistake is setting both a faction and a FRIENDLY disposition and wondering why the NPC still tracks faction reputation.
- **Profile clobbers inline by default.** With a profile assigned, anything you type into the inline fields is stamped over at runtime -- UNLESS you tick `profile_fills_blanks_only` (then your inline tweaks win; see "The additive merge" above). If an instance "ignores" your inspector edits, check whether it has a `profile` and whether that flag is off.
- **`faction_id` wins over the `faction` slot.** A non-empty dropdown id overrides whatever raw `Faction` you put in the `faction` slot at `_ready`.
- **Keep the `faction_id` suggestion list in sync with `res://resources/factions/`.** The dropdown is just a hint string (`townsfolk,raiders,neutral_wildlife`); if you add a new faction `.tres`, it won't appear in the dropdown until that list is updated, though the raw `faction` slot still works.
- **`turn_speed` lives under Perception, not Movement** -- worth knowing when you're hunting for it.
- **`goap_profile` is the optional per-archetype AI tuning.** A `GoapProfile` `.tres` that retunes the planner's goal priorities / action costs for an archetype; the GOAP planner is the shipping NPC brain, so leave `goap_profile` null to use its defaults.

Files referenced: `C:\Users\dalla\3D RPG\rpg\scripts\npc\npc.gd`, `C:\Users\dalla\3D RPG\rpg\scripts\npc\npc_data.gd`, `C:\Users\dalla\3D RPG\rpg\scenes\enemies\NPC.tscn`, `C:\Users\dalla\3D RPG\rpg\scenes\enemies\enemy.tscn`.

---

## Customising an NPC look (body/head/limbs)

Every enemy in Cyber Sunday starts from the same `enemy.tscn` rig â€” a single skinned `Man.glb` body whose head is a bone â€” but you almost never edit that rig directly. Instead, a drop-in `BodyModelSwap` child *replaces* the visible body, head, arms and legs with your own `.glb`/`.blend` models, and it does so **live in the editor** (it's a `@tool` script). Better still, you can override the look **per instance straight from the NPC root**, so re-skinning one guard in a level is a matter of clicking it and filling a few inspector fields â€” no "Editable Children", no duplicate scenes.

### The two places a look is defined

There are two layers, and it helps to know which one you're touching:

1. **The shared default look** lives on the `BodyModelSwap` node inside `res://scenes/enemies/enemy.tscn` (script: `rpg/scripts/components/body_model_swap.gd`). This is what *every* enemy wears unless overridden. In the shipped scene it's set to:
   - `body_model` = `res://scenes/torso.tscn`, `body_model_scale` = `0.205`, `body_model_rotation` = `(0, -90, 0)`, `body_texture` = `stupidbody_Material Base Color.png`
   - `head_model` = `res://assets/models/headblue.glb`, `head_scale` = `0.205`, `head_position` = `(0, 0.615, 0.04)`, `head_rotation` = `(0, 90, 0)`, `head_texture` = `headblue_Material Base Color.png`
   - `arm_model` = `arm.blend` (scale `0.35`, position `(-0.27, 0.155, -0.05)`, rotation `(90, 0, 0)`) and `leg_model` = `leg.blend` (scale `0.44`, position `(0.095, -0.265, -0.02)`, rotation `(0, -90, 0)`)
   - (The arm/leg *tints* in the shipped scene actually come from the NPC root â€” see below â€” `arm_color` = a blue, `leg_color` = a maroon. The child's own `arm_color`/`leg_color` stay WHITE.)

   Note the field names differ slightly between the two layers: on the `BodyModelSwap` child the head transform fields are `head_scale` / `head_position` / `head_rotation`, while on the NPC root (below) the equivalents are `head_model_scale` / `head_model_position` / `head_model_rotation`.

2. **Per-instance overrides** live on the **NPC root** (the `Enemy` `CharacterBody3D`, script `rpg/scripts/npc/npc.gd`), in the inspector under **Body & Head â–¸ Custom Models**. The `@tool` `BodyModelSwap` child *reads its parent's* fields and prefers them over its own â€” so anything you set on the root wins, and previews instantly.

The fields on the NPC root under **Custom Models** are:

| Field | Type | What it overrides |
|---|---|---|
| `body_model` | PackedScene | Swap this NPC's body mesh |
| `body_model_scale` | float | Body uniform scale |
| `body_model_position` | Vector3 | Body local offset (nudge Y so feet meet the ground) |
| `body_model_rotation` | Vector3 (deg) | Body yaw/pitch/roll |
| `body_texture` | Texture2D | Re-skin the body (albedo) *without* swapping the mesh |
| `body_color` | Color | Tint the body (WHITE = leave it) |
| `head_model` | PackedScene | Swap this NPC's head |
| `head_model_scale` | float | Head uniform scale |
| `head_model_position` | Vector3 | Head local offset (raise Y to sit it on the neck) |
| `head_model_rotation` | Vector3 (deg) | Head rest facing |
| `head_texture` | Texture2D | Re-skin the head (albedo) |
| `head_color` | Color | Tint the head (WHITE = leave it) |
| `arm_color` | Color | Tint both arms (WHITE = keep the default) |
| `leg_color` | Color | Tint both legs (WHITE = keep the default) |

Note there is **no `arm_model` / `leg_model` (nor arm/leg scale, position, rotation, or texture) on the NPC root** â€” the root can only *tint* the limbs. The arm and leg *models* and their placement live solely on the `BodyModelSwap` child.

A few rules the component bakes in, worth internalising:

- **Texture/colour resolve independently of the model.** You can re-skin the *default* body just by setting `body_texture`/`body_color` and leaving `body_model` empty â€” no mesh swap needed.
- **WHITE is the "leave it alone" sentinel** for every `*_color`. The override only kicks in when you pick a non-white colour; white restores the model's own baked material. Same idea for an empty texture.
- **A swapped model brings its own material.** If you set `body_model` but no `body_texture`/`body_color`, the new mesh shows the material it was authored with. (And if the host overrides the *model* but leaves its texture null / colour WHITE, the swapped model keeps its own material rather than inheriting the child's default skin.)
- **Arms and legs are tint-only from the root.** Their *models* and placement always come from the `BodyModelSwap` child (they're gait-animated â€” they swing as the NPC walks), but `arm_color`/`leg_color` on the root recolour them per instance.

### Worked example: a red-shirted variant of the default guard

Say you want one specific enemy in your level to wear a red torso and a pale head, but otherwise stay the default guy.

1. In your level scene, select the placed **Enemy** instance (the root `CharacterBody3D`). You do **not** need "Editable Children".
2. In the inspector open **Body & Head â–¸ Custom Models**.
3. Leave `body_model` and `head_model` empty â€” you're keeping the default meshes. (There's no arm/leg model field here to touch; the limbs always come from the child.)
4. Set `body_color` to a red. The torso re-tints in the viewport immediately (the `@tool` child rebuilds on the change).
5. Set `head_color` to a pale skin tone. Done.

Want a genuinely different *body* instead of a tint? Set `body_model` to your `.glb`/`.tscn`, then dial `body_model_scale` (start around `0.2` â€” the default body sits at `0.205`, and most imported models come in giant at scale `1.0`), nudge `body_model_position.y` so the feet land on the ground, and yaw `body_model_rotation` until it faces the NPC's forward. Everything previews as you type. The same node performs the swap at runtime, so **what you see in the editor is what ships** â€” and at runtime the head-look and sniper glint automatically retarget onto your swapped head (the component calls `register_swapped_head()` on the NPC), and the combat outline re-rims the swapped parts.

If you instead want to change the default for *all* enemies, open `res://scenes/enemies/enemy.tscn`, select the `BodyModelSwap` node, and edit its fields there.

### Gotchas

- **Keep a `body_model` â€” head-only swaps aren't supported on this rig.** `Man.glb` is **one** skinned mesh (`BaseHuman`) and its head is a *bone*, not a separate node, so the component can't hide "just the head." The moment any body *or* head model is swapped in, it hides the **entire** `Man.glb` mesh. Every shipped NPC swaps in a `body_model` (`torso.tscn`), so the body fills that hidden rig back in. If you set only `head_model` and leave `body_model` empty, you'll hide the whole default body with nothing to replace it â€” a head floating over no torso. Always pair a head swap with a body swap.
- **The animated swing/hold poses are runtime-only.** In the editor you see the *static rest pose* (so you can place limbs); the walk swing, weapon-hold, and air-flail only play in-game. Place limbs against the rest pose.
- **Preview looking stale?** After a `.glb` reimport or a script reload the live preview can lag. Tick `refresh_preview` on the `BodyModelSwap` node (it snaps back off and forces a rebuild). This field is on the child, not the NPC root.
- **The override is detected by the field being set on the root**, so an empty/`null` `body_model` (or a WHITE colour, or a null texture) means "fall through to the `BodyModelSwap` default" â€” it does not mean "blank it out." To truly clear a swap, clear it on the `BodyModelSwap` child in `enemy.tscn`.

Relevant files: `rpg/scripts/components/body_model_swap.gd`, `rpg/scripts/npc/npc.gd` (the **Body & Head â–¸ Custom Models** subgroup, lines 32â€“57; `register_swapped_head` at line 2448), and the `BodyModelSwap` node in `rpg/scenes/enemies/enemy.tscn`.

---

## Factions, disposition and reputation

In CYBER SUNDAY, every NPC's attitude toward the player â€” and toward other NPCs â€” flows from a **Faction**: a small authored Resource (`.tres`) that says who an NPC belongs to, how that group feels about the player by default, and which other factions it loves or hates. You never write code for this. You pick a faction from a dropdown, and you can mint brand-new factions by dropping a `.tres` into one folder.

### The pieces

| Piece | What it is | Where it lives |
|---|---|---|
| `Faction` | The Resource you author (id, name, default disposition, relations) | `res://scripts/faction/faction.gd`, instances in `res://resources/factions/` |
| `Disposition.Kind` | The three-state attitude enum: `HOSTILE`, `NEUTRAL`, `FRIENDLY` | `res://scripts/npc/disposition.gd` |
| `Factions` registry | Resolves the `faction_id` dropdown string to a `Faction.tres` by filename (no `class_name` â€” it's preloaded as a const) | `res://scripts/faction/factions.gd` |
| `Reputation` (autoload) | Tracks the player's standing per faction and maps it to a disposition | `res://managers/Reputation.gd` |

### The Faction `.tres` fields

Open any of the three shipped factions (`res://resources/factions/raiders.tres`, `townsfolk.tres`, `neutral_wildlife.tres`) and you'll see four inspector fields, grouped under **Identity** and **Disposition & Relations**:

- **`id`** (`StringName`) â€” the stable lookup key. **This must equal the filename** (minus `.tres`): `raiders.tres` has `id = &"raiders"`. The `Reputation` autoload stores the player's standing keyed by this `id`, so two factions sharing an id would silently share one reputation pool. The registry pushes a loud editor warning if the internal `id` ever drifts from the filename.
- **`display_name`** (`String`) â€” the human-readable name for dialogue and UI ("Raiders", "Townsfolk", "Wildlife").
- **`default_disposition`** (`Disposition.Kind`) â€” how this faction feels about the player **at zero reputation**, before any rep shift. In the inspector this is a dropdown; in the raw `.tres` it's the enum's integer index: `0 = HOSTILE`, `1 = NEUTRAL`, `2 = FRIENDLY`. So raiders ship `default_disposition = 0` (hostile on sight), townsfolk `= 2` (friendly), wildlife `= 1` (neutral).
- **`relations`** (`Dictionary`) â€” maps **another faction's `id`** â†’ a relation score (`float`). **`< 0` = enemies, `> 0` = allies, absent/`0` = neutral.** Raiders carry `{ &"townsfolk": -1.0 }` and townsfolk carry `{ &"raiders": -1.0 }`, so the two groups shoot each other on sight. This only governs **NPC-vs-NPC** aggro â€” it has nothing to do with how either faction feels about the player.

### Picking a faction: the `faction_id` dropdown

On an NPC node (`res://scripts/npc/npc.gd`) â€” and on an `NpcData` archetype (`res://scripts/npc/npc_data.gd`) â€” you don't drag a `.tres` into a slot. You pick from a dropdown:

- **`faction_id`** (`String`, an `@export_custom` `PROPERTY_HINT_ENUM_SUGGESTION` field) â€” the inspector shows the shipped factions as suggestions: `townsfolk, raiders, neutral_wildlife`. At `_ready`, the NPC calls `Factions.by_id(faction_id)`, which loads `res://resources/factions/<id>.tres` (or `.res`) and stamps it onto the live `faction` slot. A non-empty `faction_id` **wins over** the `faction` resource slot.
- **`faction`** (`Faction`) â€” the underlying resource slot. Leave `faction_id` empty and you can drop a custom/inline `Faction.tres` here directly. Empty `faction_id` **and** null `faction` = **UNALIGNED**: the NPC ignores reputation entirely and uses its own standalone `disposition` field instead.

> The suggestion list is just a typing convenience â€” the dropdown is editable, so you can type any id you want. What actually makes resolution work is the file existing at `res://resources/factions/<id>.tres` with a matching internal `id`. If you type a `faction_id` that resolves to nothing, the NPC logs a warning and falls back to UNALIGNED.

### How disposition is resolved (player-facing attitude)

A factioned NPC's attitude toward the player isn't fixed â€” `Reputation.disposition_for(faction)` recomputes it live from the faction's baseline plus the player's standing:

- Rep `<= hostile_threshold` â†’ **HOSTILE**, no matter the baseline.
- Rep `>= friendly_threshold` â†’ **FRIENDLY**.
- In between â†’ falls back to the faction's `default_disposition`.

So earning enough standing can thaw a hostile faction, and wronging a friendly one sours it. Those thresholds (plus the `rep_min`/`rep_max` clamp) are themselves designer tunables on `GameSettings.reputation` (`res://resources/tuning/ReputationSettings.gd` / `.tres`) â€” you balance how fast the world turns on the player without code. When the player attacks a factioned NPC, that NPC's `provoke` drops the whole faction's player-rep by `provoke_penalty` (FNV-style), so the group sours together; the `reputation_changed` and `alignment_changed` signals let the HUD toast the shift.

There's also a per-NPC override: tick **`disposition_overrides_faction`** (`bool`) and the NPC keeps its faction (for reputation, NPC-vs-NPC relations, and grouping) but reads its **own** `disposition` toward the player instead of the faction's.

### How NPC-vs-NPC hostility is resolved

When two NPCs meet, `is_hostile_to` consults `HostilityHelpers.npc_vs_npc_hostile(a.faction, b.faction)`: **both** must be factioned, and faction A's `relation_to(B.id)` must be **`< 0`**. Unaligned NPCs never faction-fight. The mirror, `npc_vs_npc_allied`, treats a shared faction (same `.tres` or same `id`) or a relation **`> 0`** as allies (this drives the "Murderer!" death-witness bark when the player kills an ally).

### Worked example: adding a "Corp Security" faction allied with townsfolk

1. **Author the resource.** In the FileSystem dock, right-click `res://resources/factions/` â†’ **Create New â†’ Resource â†’ Faction**. Save it as **`corp_security.tres`** (the filename is load-bearing).
2. **Fill the fields** in the inspector:
   - `id` = `corp_security` (must match the filename exactly).
   - `display_name` = `Corp Security`.
   - `default_disposition` = `NEUTRAL` (they tolerate the player until provoked).
   - `relations` â€” add two entries: key `raiders` â†’ value `-1.0` (enemies, they'll shoot raiders), and key `townsfolk` â†’ value `1.0` (allies). For the alliance to be symmetric, also add `corp_security` â†’ `1.0` to `townsfolk.tres`'s `relations`.
3. **Make it pickable.** Open both `res://scripts/npc/npc.gd` and `res://scripts/npc/npc_data.gd` and add `corp_security` to the `PROPERTY_HINT_ENUM_SUGGESTION` list on the `faction_id` export (the line reads `"townsfolk,raiders,neutral_wildlife"` â†’ make it `"townsfolk,raiders,neutral_wildlife,corp_security"`). This is the one tiny text edit â€” it only updates the dropdown suggestions; resolution already works the moment the `.tres` exists.
4. **Assign it.** Select an NPC in your scene, pick **`corp_security`** from the `faction_id` dropdown, and play. They'll ignore the player (neutral baseline), gun for raiders, and stand with townsfolk.

### Gotchas

- **`id` must equal the filename.** A copy-pasted `.tres` whose internal `id` still says `raiders` while the file is named `corp_security.tres` will silently merge into the raiders' reputation pool â€” the registry warns about this in the editor, so watch the Output panel.
- **`relations` are one-directional.** Setting raidersâ†’townsfolk `-1.0` does *not* automatically make townsfolk hate raiders; author the reciprocal entry on the other faction (as the shipped pair does).
- **`relations` only affects NPC-vs-NPC.** It never changes how a faction feels about the player â€” that's `default_disposition` + reputation.
- **`relations` keys are `StringName`s of the target's `id`**, not display names â€” use `corp_security`, not `Corp Security`.
- **Empty `faction_id` + null `faction` = UNALIGNED**, which uses the NPC's standalone `disposition` and ignores reputation entirely. If a factioned NPC seems to ignore rep, check whether `disposition_overrides_faction` is ticked.
- The `faction_id` dropdown is editable free-text; a typo that doesn't match a file resolves to nothing and the NPC falls back to UNALIGNED (with a warning), rather than erroring.

Relevant files: `C:\Users\dalla\3D RPG\rpg\scripts\faction\faction.gd`, `C:\Users\dalla\3D RPG\rpg\scripts\faction\factions.gd`, `C:\Users\dalla\3D RPG\rpg\scripts\npc\disposition.gd`, `C:\Users\dalla\3D RPG\rpg\scripts\npc\hostility_helpers.gd`, `C:\Users\dalla\3D RPG\rpg\managers\Reputation.gd`, `C:\Users\dalla\3D RPG\rpg\resources\factions\{raiders,townsfolk,neutral_wildlife}.tres`, and the `faction_id` exports in `C:\Users\dalla\3D RPG\rpg\scripts\npc\npc.gd` / `npc_data.gd`.

---

Note on changes I made (everything else in the section was confirmed correct against the code):
- **Registry row**: added that `factions.gd` has no `class_name` (it's a preloaded const) â€” the section's table implied it might be globally named; the file deliberately omits `class_name`.
- **`faction_id` description**: corrected "an `@export_custom` enum-suggestion field" to name the actual hint constant `PROPERTY_HINT_ENUM_SUGGESTION` (matches the source), and noted `Factions.by_id` also accepts `.res`, not just `.tres`.
- **Provoke sentence**: made it explicit that the rep drop is the tunable `provoke_penalty` (the field exists on `ReputationSettings`), rather than an unnamed magnitude.

No invented fields, paths, signals, or enums were found, and nothing had to be deleted â€” the worked example and Gotchas all match the code (`PROPERTY_HINT_ENUM_SUGGESTION` strings, the `.tres` values, `disposition_overrides_faction`, `npc_vs_npc_hostile`/`npc_vs_npc_allied`, `DEATH_ALLY_LINES` "Murderer!", the `reputation_changed`/`alignment_changed` signals, and `hostile_threshold`/`friendly_threshold`/`rep_min`/`rep_max` on `GameSettings.reputation`).

---

## Authoring dialogue

A conversation in CYBER SUNDAY is pure content: a tree of authored `.tres` Resources, hung off a drop-in component on whatever you want to talk to. No script ever needs editing. This section walks the resource stack from the top down, then wires a finished conversation onto an NPC.

### The resource stack

Three nested Resource types, mirroring how the editor lets you nest sub-resources inside an array field. From outside in:

| Resource (`class_name`) | Script | Key fields |
|---|---|---|
| `DialogueResource` | `res://scripts/dialogue/dialogue_resource.gd` | `lines: Array[DialogueLine]` |
| `DialogueLine` | `res://scripts/dialogue/dialogue_line.gd` | `text`, `choices: Array[DialogueChoice]` |
| `DialogueChoice` | `res://scripts/dialogue/dialogue_choice.gd` | `text`, `target`, `required_stat`, `required_value` |

**`DialogueResource`** is the whole conversation â€” just an ordered `lines` array. `DialogueManager` plays it top to bottom. The order is also the addressing: choices jump by **index into this array**, so line 0 is the first line, line 1 the second, and so on.

**`DialogueLine`** is one spoken beat. Fill `text` (it's `@export_multiline`, so you get a real text box in the inspector). There is **no speaker field on the line** â€” the speaker's name comes from the talking character (see wiring, below), so you author the same `DialogueResource` for any speaker. Leave `choices` empty and the line plays linearly: the player clicks/presses to hear the next line. Add choices and the line becomes a **branch point**.

**`DialogueChoice`** is one selectable button on a branch line. Fill `text` (the button label). The important field is `target`, an int that says where picking it goes:

- **`-2` = CONTINUE (the default).** Carries on to the *next* line. A freshly-added choice you forget to point anywhere just continues the conversation rather than dead-ending it. (In the script this constant is `DialogueLine.CONTINUE`.)
- **`-1` = END.** Finishes the conversation. (Script constant: `DialogueLine.END`.)
- **`0` or higher = BRANCH.** Jumps to that line index in `DialogueResource.lines` and re-enters the listen-first flow there.

In the inspector `target` is a plain integer field â€” type `-1` to end, `-2` to continue, or the destination line's index to branch. (An out-of-range index ends the conversation cleanly rather than crashing, but double-check your indices.)

### Skill checks (`required_stat` / `required_value`)

A choice can be gated behind a player stat â€” Fallout: New Vegas style. Set `required_stat` to a `CharacterStats` stat name as a StringName (e.g. `&"persuasion"`) and `required_value` to the threshold. The button then:

- shows the gate baked into its label: `[Persuasion 6] Talk them down`, and
- is **visible but disabled** (greyed, unclickable) while the player's stat is below `required_value`.

The check is evaluated against the real human player's `stats_or_default().get_stat(...)` â€” companions (NPCs in the same `Player` group) are skipped, and when no player is found the check reads `CharacterStats.BASELINE` (0) so it behaves neutrally rather than crashing. Leave `required_stat` blank (the default `&""`) and the choice has no gate. This is what makes character builds matter in conversation. (Valid stat names: `strength`, `persuasion`, `gunplay`, `endurance`, `streetwise`, `agility` â€” an unknown name just reads BASELINE.)

### VoiceData â€” how lines are read aloud

Lines are spoken by the in-game offline Flite text-to-speech (the `SpeechTts` autoload). `VoiceData` (`res://scripts/dialogue/voice_data.gd`) is a small `.tres` you author once per character and assign to the talk component's `voice` slot:

- **`flite_voice`** â€” an `@export_enum` dropdown of the bundled voices: `cmu_us_aew`, `cmu_us_ahw`, `cmu_us_awb`, `cmu_us_eey`, `cmu_us_fem`, `cmu_us_slp`, `cmu_us_slt`. `slt` and `fem` read female; the rest read male. Leave blank to fall back to a male/female default (`cmu_us_aew` / `cmu_us_slt`, picked by the legacy `female` toggle).
- **`rate`** (0.1â€“4.0, default 1.0) â€” speaking speed. Flite scales the sample rate, so faster also reads a touch higher.
- **`pitch`** (0.1â€“2.0, default 1.0) â€” a pitch nudge *folded into* playback speed (Flite has no independent pitch knob; effective speed is `rate Ã— pitch`, clamped). Prefer `rate` for predictable control; treat `pitch` as a sweetener.
- **`female`** â€” deprecated legacy toggle, only consulted when `flite_voice` is blank.

Voice is optional â€” leave the component's `voice` unset and the line still shows on screen, just read with the default voice. The shipped `res://resources/dialogue/old_man_voice.tres` is a one-field example: `flite_voice = "cmu_us_slt"`.

### The listen-first reveal flow

Worth understanding so your branch lines read the way you expect. When a line opens, the player **hears it first** with only a continue prompt â€” the response menu is *not* shown yet. The menu appears on the *next* click/press. So on a branch line: click once to hear the line, click again to see the choices. On a linear line, clicking advances to the next line (so clicking "skips through" a monologue). The choices menu is also auto-revealed on the **final** line, even if it has no authored choices, so the player always gets a clean way out.

When the menu does appear, the manager appends synthesized options *after* your authored choices automatically â€” based on components attached to the speaker: **Follow me / Wait here** (companion recruit), **Trade** (a Merchant child), **Heal** (Healer child), **Rest** (Bonfire child), **Level Up** (LevelUp child), **Exchange Gear** (a following ally with a backpack), and always a final **Goodbye.** to leave. You don't author those â€” attaching the relevant component to the NPC makes them appear.

### Wiring a conversation onto an NPC

Behaviour is a drop-in component. Two interchangeable ways to make a thing talkable; both behave identically to the player's look-at interaction ray:

- **`Talkable`** (`res://scripts/components/talkable.gd`, scene `res://scenes/dialogue/talkable.tscn`) â€” an `Area3D` you instance *as a child* of an existing node (a villager, an enemy you can parley with, a car). Use this to add talk to something without overriding its root script. This is the path used on real combat NPCs.
- **`DialogueNPC`** (`res://scripts/components/dialogue_npc.gd`) â€” a script on the node itself, with a child `Area3D` assigned to its `range_area`. Use it for a self-contained inanimate speaker (terminal, sign).

Both expose the same dialogue fields: **`dialogue`** (the `DialogueResource` â€” leave it unset and the host can't be talked to), **`voice`** (the `VoiceData`, optional), and **`display_name`**. Leave `display_name` blank on a `Talkable` and it uses the host NPC's `display_name`, so a talkable NPC is named once on the NPC itself; set it to name an inanimate host. `turn_to_face` makes a character rotate toward the player on talk (default **on** for `Talkable`, **off** for `DialogueNPC` â€” flip it on for a character).

The component does the rest: it sits on the talk physics layer so the interaction ray finds it when aimed at, highlights the host with a white outline while you look (tunable via `highlight_color` / `highlight_width`), and on interact calls `DialogueManager.start(dialogue, host, voice, name)`. `DialogueManager` must be registered as an autoload named exactly **`DialogueManager`** (Project Settings â†’ Autoload) â€” it usually already is.

### Worked example: a talkable car

The shipped `res://resources/dialogue/old_man.tres` is a two-line conversation:

- **Line 0** â€” text `"What a beauty."`, no choices (plays linearly).
- **Line 1** â€” text `"What do you think?"`, with two choices: `"Uh, no."` and `"LOVE IT!"`. Both use the default `target = -2` (CONTINUE), so either one rolls past the end of the line list and the conversation finishes.

To wire it onto a car in your level:

1. Select the car node in the scene. Instance `talkable.tscn` (the `Talkable` component) as a child.
2. Size its `CollisionShape3D` to roughly cover the car's body â€” that's what the player aims at.
3. In the inspector, set the component's **Dialogue â†’ dialogue** to `res://resources/dialogue/old_man.tres`.
4. Set **voice** to `res://resources/dialogue/old_man_voice.tres` (or your own `VoiceData`).
5. Since a car is inanimate, set **display_name** to `"Old Man"` (or whatever the speaker is) and turn **Interaction â†’ turn_to_face** off so the car doesn't pivot.

Aim at the car, press interact (E / PickUp), and the box opens with `"What a beauty."` read aloud, then `"What do you think?"` with your two reply buttons.

To go further: add a third line for a real branch â€” make line 1's `"LOVE IT!"` choice `target = 2`, and author line 2 as the enthusiastic follow-up. To add a skill gate, give a choice `required_stat = &"persuasion"` and `required_value = 6`; it'll show `[Persuasion 6] ...` and lock until the player's persuasion clears 6.

### Gotchas

- **Targets are line *indices*, not line objects.** If you reorder or delete lines in `DialogueResource.lines`, every `target >= 0` that pointed past the change now points somewhere else. Re-check branch targets after reordering.
- **`-2` continues, `-1` ends.** It's easy to leave a choice at the default `-2` (CONTINUE) when you meant to end the conversation â€” that choice will roll into the next line instead of closing the box.
- **No per-line speaker.** Don't look for a speaker/name field on `DialogueLine`; the name comes from the talk component's `display_name` (or the host NPC's). Set it on the component, once.
- **Listen-first means an extra click on branch lines.** Players hear the line, *then* the choices appear on the next input. That's intended, not a bug â€” author your branch text as something the NPC says before offering the options.
- **Empty `dialogue` = silent.** A `Talkable` / `DialogueNPC` with no `DialogueResource` assigned simply does nothing on interact (and a `Talkable` host won't even register as talkable). Assign the resource.
- **`voice` is optional but `flite_voice` matters.** With no `VoiceData`, lines read in a default voice; pick `flite_voice` per character so two NPCs don't sound identical. (Note: `cmu_us_slt` â€” the one the shipped `old_man_voice.tres` uses â€” reads *female*; pick a male voice like `cmu_us_aew` if that's the character.)
- **A hostile or in-combat NPC won't talk.** `Talkable.can_be_talked_to()` refuses a hostile or fighting NPC â€” the talk highlight and prompt won't even show. That's by design; don't expect to parley mid-firefight.

Relevant files: `rpg/scripts/dialogue/dialogue_resource.gd`, `dialogue_line.gd`, `dialogue_choice.gd`, `dialogue_manager.gd`, `voice_data.gd`, `dialogue_view.gd`; components `rpg/scripts/components/talkable.gd` and `dialogue_npc.gd`; example content `rpg/resources/dialogue/old_man.tres` and `old_man_voice.tres`; scene `rpg/scenes/dialogue/talkable.tscn`.

---

**Fact-check summary** (changes I made; the section was overwhelmingly accurate):

- **All class_names, scripts, res:// paths, signals, enums, and `@export` field names verified correct** against the code â€” `DialogueResource.lines`, `DialogueLine.text/choices`, `DialogueChoice.text/target/required_stat/required_value`, `VoiceData.flite_voice/rate/pitch/female`, both components' `dialogue/voice/display_name/turn_to_face/highlight_color/highlight_width/range_area`, the `-2/-1` sentinels (`DialogueLine.CONTINUE`/`END`), the `@export_enum` voice list, and the `start(dialogue, host, voice, name)` call all match.
- **`talkable.tscn` exists** at `res://scenes/dialogue/talkable.tscn`; the `old_man.tres` / `old_man_voice.tres` contents match the worked example exactly.
- **Added precision (not fixes â€” the originals weren't wrong):** named the actual TTS autoload (`SpeechTts`), the `CharacterStats.BASELINE` neutral fallback, the male/female default voice names, the `rate Ã— pitch` clamp, the valid stat-name list, and the script constant names for the sentinels.
- **Added one designer-relevant caveat:** flagged that the shipped `cmu_us_slt` reads *female* despite the example being an "Old Man" â€” a real gotcha a level designer copying that file would hit. This is faithful to the code (the `voice_data.gd` comment states `slt` reads female), not invented.
- **Nothing was deleted** â€” every instruction in the section is supported by the code.

---

## Items, loot, money and pickups

Everything a player can hold, take, or steal in CYBER SUNDAY funnels through one little data type â€” the **Item** Resource â€” and a handful of drop-in components that hand Items (and zorkmids) to the player. None of it needs code. You author Item `.tres` files in the inspector, then drop pickup/container/corpse nodes into your level and fill their `@export` lists. This section walks the whole chain.

### 1. The Item Resource (`res://scripts/items/item.gd`)

An `Item` (`class_name Item`) is the atom of everything carryable. Create one with **right-click in the FileSystem â†’ New Resource â†’ Item**, save it under `res://resources/items/` (that's where the shipped ones live â€” `healthpack.tres`, `pistol_item.tres`, `ammo_pistol.tres`, â€¦), and fill these fields:

**Identity & Display**
- `id` (StringName) â€” the stable lookup key, unique per `.tres` (e.g. `&"healthpack"`). Used by `ItemDb` and save/load.
- `display_name` (String) â€” what shows in the inventory, loot screen, and "[E] Take â€¦" prompts.
- `description` (multiline) â€” tooltip / detail text.
- `icon` (Texture2D) â€” optional inventory icon; the list UI falls back to the name if it's empty.

**Classification & Stats**
- `category` (enum: `WEAPON / CONSUMABLE / AMMO / MISC`) â€” gates which fields below matter and which helper (`is_weapon` / `is_ammo` / `is_consumable`) applies.
- `max_stack` (int) â€” how many fit in one stack. `1` = unstackable (always set this for weapons); `>1` lets ammo/consumables pile up (the Health Pack uses `5`).
- `weapon` (WeaponData) â€” set **only** on `WEAPON`-category items; point it at a weapon `.tres` like `res://resources/weapons/pistol.tres`. This is what makes the item equippable.
- `caliber` (StringName) â€” for `AMMO` items, the caliber these rounds feed (e.g. `&"pistol"`), matched against a weapon's own `caliber` on reload. (Shipped calibers are `pistol`, `smg`, `shells`, `rifle`, `grenades`.)
- `weight` (float) â€” abstract carry weight of one of this item; summed into the carrier's load (over capacity = encumbered/slowed).
- `value` (float) â€” base trade value in **zorkmids** (the in-game currency). Fractional â€” zorkmids run in hundredths, so `0.5` is half a zorkmid. `0` = worthless / unsellable.
- `heal_amount` (float) â€” for `CONSUMABLE` items, HP restored when used from the inventory.

**World Model**
- `world_model` (PackedScene) â€” optional unique 3D model for when this item sits **in the world** (dropped/looted/spawned). A pickup with `build_model_from_item` on will instantiate this and auto-fit its hitbox. Null = the pickup keeps whatever body it was authored with.

> One Item class covers everything â€” there is deliberately no `WeaponItem` subclass. A weapon is just an Item with `category = WEAPON` and a `weapon` reference, because Godot's typed-array `.tres` serialization doesn't reliably round-trip script subclasses inside an `Array[Item]`.

### 2. ItemStack â€” "N of this item" (`res://scripts/items/item_stack.gd`)

When you want to author *contents* â€” what's inside a crate, what a pickup grants â€” you don't repeat an Item N times. You use an **`ItemStack`** (`class_name ItemStack`), which is just two fields:

- `item` (Item) â€” the item this row holds (null = the row is ignored).
- `count` (`@export_range 0..9999`) â€” how many. `0` skips the row.

So "5 healthpacks, 30 pistol ammo, 2 shotguns" is **three rows**, each an Item + a count. The rule for how counts expand is shared everywhere (containers, pickups, NPC bags) so it can't drift:
- **Weapons** (`is_weapon()`) are seeded as **one unique instance per count** â€” 2 shotguns become two distinct objects (no shared-instance bugs).
- **Stackables** (ammo, junk, consumables) stack to the count as the shared template.

`ItemStack` appears as an `item_stacks: Array[ItemStack]` export on the components below. In the inspector you just set the array size, then for each element drag in an Item `.tres` and type a count.

### 3. Putting loot + money into a crate â€” `ItemContainer` (`res://scripts/components/container.gd`)

A crate, chest, locker, or fridge is the **`ItemContainer`** component (`class_name ItemContainer`, extends `LookAtInteractable`). It's a *persistent* two-way stash: the player aims at it, presses **E (Interact)**, and the loot-transfer screen opens on the container's own inventory â€” they can take things out **or** deposit their own gear and come back later (unlike a corpse, a container is never freed).

**Setup**
1. Add an `ItemContainer` node under your crate's visual (or assign `highlight_target`).
2. Size its `CollisionShape3D` to cover the body the player aims at.
3. Fill in the contents exports:
   - `item_stacks` (`Array[ItemStack]`) â€” **the preferred way to fill a crate.** Count-based rows.
   - `starting_items` (`Array[Item]`) â€” *legacy* fixed contents; add the same Item twice for two of it. Prefer `item_stacks`.
   - `money` (float) â€” zorkmids stashed inside, looted via the same "Take N zm" row a corpse offers. `0` = no cash. Fractional allowed.
   - `loot_table` (LootTable) â€” **optional** random loot rolled in *on top* of the fixed contents at spawn (see Â§6). Null = just the fixed contents.
   - `container_name` (String) â€” shown on the hover ("Loot \<name>") and the transfer screen title. Blank = just "Container".

At spawn the container builds a child `CharacterInventory` and seeds it: `item_stacks` first, then `starting_items`, then the optional `loot_table` rolled on top. It joins the `&"containers"` group, so a nearby under-armed NPC can even raid it for a better gun (`NpcScavenge`).

> If you drop a `Lock` node as a child of the container, the first E press attempts the lock (pick/key) before opening â€” a failed attempt toasts what the lock needs and the hover reads "Unlock \<name>" instead of "Loot \<name>".

**Worked example â€” a supply crate behind the gas station**

> Goal: a crate holding 5 health packs, 30 pistol rounds, a spare pistol, and 120 zorkmids.

1. Drop an `ItemContainer` under your crate mesh; size the collider to the box.
2. Set `container_name` = `Supply Crate`.
3. Set `money` = `120`.
4. Expand `item_stacks`, set size **3**:
   - `[0]` item = `res://resources/items/healthpack.tres`, count = `5`
   - `[1]` item = `res://resources/items/ammo_pistol.tres`, count = `30`
   - `[2]` item = `res://resources/items/pistol_item.tres`, count = `1`
5. Done. The pistol seeds as its own unique instance; ammo and packs stack. Aim, press E, and the player sees the four take rows plus "Take 120 zm".

### 4. Scattering pickups around the level "New Vegas style"

For loose loot lying on the ground â€” a stimpak on a shelf, ammo in a gutter, a weapon on a dead-end rooftop â€” use the lighter **`CanPickUp`** component (`res://scripts/components/can_pick_up.gd`, `class_name CanPickUp`, extends `LookAtInteractable`). Aim, press E, the item goes straight into the player's backpack and the world object frees itself. No transfer screen â€” it's a grab, not a container.

**Payload exports**
- `item` (Item) â€” the single item granted on pickup.
- `amount` (int) â€” how many of `item` (weapons add as that many unique instances).
- `item_stacks` (`Array[ItemStack]`) â€” **a count-based mini-pile** granted on top of `item` ("2 stims + 10 ammo" in one pickup). Leave empty for a plain single-item pickup.
- `loot_table` (LootTable) â€” optional random loot on top; can be set **without** an `item` for a pure random-loot bag.

**Hover Label**
- `pickup_label` (String) â€” blank â†’ "Take \<item name>".

**World Visual**
- `build_model_from_item` (bool) â€” when on, builds the world visual from `item.world_model` at spawn and auto-fits the hitbox. Mainly for code-spawned/dropped loot; for hand-placed pickups you usually just parent the component under an existing model instead.

To litter a level New-Vegas style, the workflow is: author each loose item once as an Item `.tres`, then place `CanPickUp` nodes wherever you want them, drag the Item into `item`, and (optionally) give visual variety via each Item's `world_model` with `build_model_from_item` on. A single pistol on a crate is one `CanPickUp` with `item = pistol_item.tres`; a "junk pile" is one `CanPickUp` with three `item_stacks` rows. It's pickable as long as it has *anything* to give (a fixed item, a pile, or a table).

### 5. Looting corpses â€” `LootableCorpse` (`res://scripts/components/lootable_corpse.gd`)

You normally **don't place this by hand** â€” `LootableCorpse` (`class_name LootableCorpse`, extends `LookAtInteractable`) is spawned automatically when an NPC dies. It copies the dead NPC's backpack (so freeing the NPC can't drain the loot) and its **wallet** (designer-set money plus any kill bounties it earned in life), then attaches as a child of the ragdoll. The player aims at the body, presses E, and the same loot-transfer screen opens â€” items plus a "Take N zm" row for the cash. The ragdoll lingers until the body is emptied of both items and money; a fully drained corpse stops highlighting and reads as just the bare name.

The one tunable you might touch is `trigger_radius` (float, default `1.2`) â€” the radius of the loot hitbox that follows the crumpling body. Where the corpse's contents come from is authored upstream on the NPC: its starting gear/loadout and its `NpcData.loot` LootTable, which is rolled into the backpack on death and lands in the corpse. So to make an enemy drop good loot, you stock that enemy â€” not the corpse component.

### 6. LootTable â€” random drops (`res://scripts/items/loot_table.gd`)

A **`LootTable`** (`class_name LootTable`) is the random-loot Resource you plug into `loot_table` on a container or `CanPickUp`, or into an `NpcData.loot`. It holds an `entries: Array[LootEntry]`, and each `LootEntry` (`res://scripts/items/loot_entry.gd`) rolls **independently**:

- `item` (Item) â€” what drops.
- `chance` (`@export_range 0..1`) â€” probability this row drops at all. `0.0` never drops; `1.0` always drops.
- `min_count` / `max_count` (int) â€” the count range rolled when it hits.

Because rows are independent, one table can mix a guaranteed "1â€“3 ammo" (`chance 1.0`) with a rare "10% keycard" (`chance 0.1`). Weapons rolled from a table become unique instances, same as everywhere else.

### 7. UpgradePickup â€” granting player unlocks (`res://scripts/components/upgrade_pickup.gd`)

For a **permanent player ability** (grappling hook, laser sight, wall-climbâ€¦) rather than an inventory item, use **`UpgradePickup`** (`class_name UpgradePickup`, extends `LookAtInteractable`). Aim + Interact and it adds the ability node to the player immediately, toasts, autosaves the run (a new mechanic is a milestone), and frees itself.

**Exports**
- `grants` (PackedScene) â€” **the preferred way.** Drag an ability scene from `res://scenes/components/abilities/` here (the shipped set: `Grapple.tscn`, `LaserSight.tscn`, `WallClimb.tscn`, `AirDash.tscn`, `Slide.tscn`). Its node â€” with its own authored config â€” is added under the player on pickup. Takes precedence over `unlock_id`. A scene whose root isn't an `Ability` is discarded and grants nothing (fails safe).
- `unlock_id` (String) â€” **legacy fallback**, used only when `grants` is empty. It's an `ENUM_SUGGESTION` dropdown offering `grapple, laser_sight, wall_climb, air_dash, slide` (you can pick from the list or leave it blank); the chosen id is passed to `player.unlock_mechanic()`. Prefer `grants`.
- `display_name` (String) â€” shown in the pickup toast and the "Take \<name>" hover (e.g. "Grappling Hook").
- `world_model` (PackedScene) â€” optional custom visual; with none assigned it builds a small glowing blue emblem so a bare pickup is still visible and auto-fits its hitbox.
- `toast_color` (Color) â€” tint of the "\<name> acquired!" toast.

**Worked example â€” a grappling-hook upgrade on a rooftop**

1. Drop an `UpgradePickup` node where you want it.
2. Set `grants` = `res://scenes/components/abilities/Grapple.tscn`.
3. Set `display_name` = `Grappling Hook`.
4. (Optional) set `world_model` or leave it for the default emblem.
5. Done â€” walking up and pressing E grants the grapple ability node to the player on the spot, toasts "Grappling Hook acquired!", and autosaves.

### 8. Loose money â€” `MoneyPickUp` (`res://scripts/components/money_pickup.gd`)

For a pure stash of cash on the ground (not inside a container or corpse), drop a **`MoneyPickUp`** (`class_name MoneyPickUp`). Set `amount` (float, fractional allowed) â€” on E it credits the player's wallet, fires the HUD readout + floating "+N" indicator, and frees itself. With no authored body it builds a simple gold coin (or `world_model` if you assign one); `pickup_label` overrides the default "Take N zorkmids" hover.

### Gotchas

- **Always set `max_stack = 1` on weapon Items.** Weapons must be unique instances; a stackable weapon breaks the "each weapon is its own object" assumption the whole loot pipeline relies on.
- **A `WEAPON`-category Item with no `weapon` assigned isn't a weapon** â€” `is_weapon()` checks both. It'll behave as plain junk (stacks, won't equip).
- **`category` in the saved `.tres` is the enum *index*** â€” `0=WEAPON, 1=CONSUMABLE, 2=AMMO, 3=MISC`. Edit it through the inspector dropdown, not the raw text, to avoid mislabeling (e.g. `healthpack.tres` shows `category = 1` for CONSUMABLE).
- **`money` lives on the container/corpse, not in `item_stacks`.** Cash isn't an Item â€” there's a dedicated `money` float and a "Take N zm" row. Don't try to make a "zorkmid" Item.
- **`item_stacks` is preferred over `starting_items`.** `starting_items` is legacy (no per-row count); reach for it only when you've got an odd one-off, otherwise use the count-based list.
- **`UpgradePickup`: assign `grants`, not `unlock_id`.** The scene carries its ability's authored config; `unlock_id` is just a string fallback for pickups authored before the scene system and grants a bare mechanic. Don't fill in both â€” `grants` wins and the id is ignored.
- **You don't author corpses.** `LootableCorpse` is spawned on death; to change what a body drops, edit the NPC's loadout and its `NpcData.loot` LootTable, not the corpse component.
- **`loot_table` rolls on top of fixed contents**, it doesn't replace them. A crate with both `item_stacks` and a `loot_table` gives the guaranteed items *plus* whatever the table rolls.

Relevant files (all absolute): `C:\Users\dalla\3D RPG\rpg\scripts\items\item.gd`, `item_stack.gd`, `loot_table.gd`, `loot_entry.gd`; `C:\Users\dalla\3D RPG\rpg\scripts\components\container.gd`, `lootable_corpse.gd`, `can_pick_up.gd`, `upgrade_pickup.gd`, `money_pickup.gd`; example content under `C:\Users\dalla\3D RPG\rpg\resources\items\` and ability scenes under `C:\Users\dalla\3D RPG\rpg\scenes\components\abilities\`.

---

## Weapons and ammo

Every gun, blade, and pair of fists in CYBER SUNDAY is one `WeaponData` resource (`rpg/scripts/combat/weapon_data.gd`). It is pure data â€” the entire firing pipeline reads its `@export` fields â€” so a new weapon is a new `.tres` you author in the inspector, never a code change. The shipped weapons live in `res://resources/weapons/`: `pistol.tres`, `smg.tres`, `shotgun.tres`, `sniper_wep.tres`, `melee.tres` (a knife), `fists.tres`, `rock_weapon.tres`, and `spray_paint.tres`. Open any of them to see a worked-out example of the knobs below.

### Authoring a WeaponData .tres

In the editor: **FileSystem â†’ right-click `resources/weapons/` â†’ New Resource â†’ search "WeaponData"**. Save it (e.g. `ar15.tres`), then fill in the Inspector. The fields are grouped exactly as they appear in the panel:

- **General** â€” `effective_range` (metres; the hitscan ray stops here, and a ranged NPC uses it as its standoff distance; `0` = unranged), and `move_speed_multiplier`, the speed scale applied to the wielder *while this weapon is drawn* (`1.0` = no penalty; the SMG uses `0.93`, fists use `1.25` to make you faster bare-handed).
- **Damage** â€” `damage` (HP per hit, *per pellet* on a shotgun; the player has only 4 HP, so `1.0` is a quarter-bar), `headshot_multiplier`, `sneak_attack_multiplier` (hitting an un-alerted enemy), `backstab_multiplier` / `backstab_arc_degrees` (inert at `1.0` until you raise it), and `overkill_penetration` (excess damage punches through to whoever's behind).
- **Firing** â€” `pellet_count` (>1 makes a shotgun spread) and `pellet_spread`, `auto_fire` (hold vs. click-per-shot), `attack_windup` (wind-up delay for weight), and `attack_speed` â€” the per-shot cooldown in seconds, where **lower = faster** (`0.1` is 10 shots/sec; the pistol is `0.44`).
- **Ammo & Reload** â€” `max_ammo` (clip size), `is_infinite_ammo` (set `true` for melee/fists â€” the clip never depletes), `caliber`, `auto_reload`, `reload_time`. (Caliber is covered below.)
- **Projectile** â€” assign a `projectile_scene` (a Bullet scene, e.g. `res://scenes/projectiles/Projectile.tscn`) for a travelling round; leave it unset for pure hitscan. Then tune `projectile_speed`, `projectile_life_time`, `bullet_gravity_scale` (`0` = flat laser, `1` = grenade arc), `launch_angle`, and `has_tracer`.
- **Explosion / Knockback** â€” `max_explosion_force` + `explosion_radius` for blast rounds; `self_knockback` (recoil shove on the shooter â€” go *negative* for a melee lunge, like the knife's `-2.5`), `enemy_knockback`, `enemy_lift`.
- **View Model & cosmetics** â€” `view_model` is the first-person weapon scene the gun rig instantiates on equip (the SMG points at `ak_472.tscn`, the pistol at `silenced.tscn`); `hand_mesh` is an optional stand-in. Then `has_muzzle_flash`, `has_laser_sight`, `spawns_casing`, `casing_size_scale`, and the **Audio** streams (`audio`, `whiz_sound`, `impact_sound`, `impact_enemy_sound`, `reload_sound`).
- **Feedback / ADS / Scoped-Attack Launch / Spray Paint** â€” `screen_shake_amount`, `hitstop_duration` (and `hitstop_recovery`); `no_ads` (true for fists), `scoped_fov_override`, `hip_sway_mult`; `launch_on_scoped_attack` (the knife's ADS-dash, with `launch_force` / `launch_upward`); and `is_spray_paint` + `paint_colors` for the graffiti gun.

### Calibers and ammo: how reserves connect

The link between a gun and its bullets is the `caliber` StringName on `WeaponData`. The rule is simple:

- **`caliber = &""` (empty)** â€” no reserve. The clip refills for free on every reload. This is what melee, fists, the rock, and spray paint use. Combined with `is_infinite_ammo = true`, melee weapons never run dry.
- **`caliber` set (e.g. `&"pistol"`, `&"smg"`)** â€” the weapon draws from the wielder's backpack on reload. **Two weapons that share a caliber string share their reserve ammo.**

Reserve ammo is itself authored content: an **AMMO-category `Item`** (`rpg/scripts/items/item.gd`) in `res://resources/items/`, with `category = AMMO`, a high `max_stack`, and a `caliber` matching the weapon's. For example `ammo_pistol.tres` declares `caliber = &"pistol"`, `max_stack = 999`. The `ItemDb` autoload (`rpg/scripts/items/item_db.gd`) scans that folder at boot and buckets each ammo item by its caliber, so **to add a new caliber you just drop a matching weapon-item and ammo-item `.tres` into `resources/items/` â€” no path list to maintain.** Reloads count reserve ammo in *whole clips*: a magazine reload spends one spare clip (`Ammo._refilled_clip` in `rpg/scripts/combat/ammo.gd`) and discards whatever was left in the old mag.

> Important: the calibers that actually ship are `&"pistol"` and `&"smg"` â€” the `9mm` you'll see in some code comments is just an illustrative example, not a real caliber in the project. Match the weapon's `caliber` to an existing ammo item's `caliber` exactly, or the gun can never be reloaded.

### Arming the player

The player's starting kit lives on the **SwapWeapons** node inside `weapon.tscn` (`rpg/scripts/combat/swap_weapons.gd`). Two ways to author it:

1. **Quick:** drop your `WeaponData` `.tres` files into the `weapon_slots` array (index 0 = first slot). The player seeds its backpack from this list on spawn. Empty by default = start with nothing and scavenge.
2. **Data-driven (recommended for a scenario/difficulty kit):** author a **`Loadout` `.tres`** (`rpg/scripts/combat/loadout.gd`) with a typed `Array[WeaponData] weapons`, a `starting_clips_per_caliber` count, and starting `money`, then assign it to the SwapWeapons `loadout` slot. A non-empty Loadout's `weapons` list **replaces** `weapon_slots` (via `effective_slots()`) and also feeds the player's starting clips and zorkmids â€” one resource instead of editing the array plus player constants. Leave `loadout` null to fall back to `weapon_slots`.

The single equipped weapon is held by the **Inventory** node (`equipped_weapon` export); `equip()` swaps it and broadcasts `weapon_changed`, which every subsystem (Ammo, Attack, ProjectileSpawner, the view-model rig, the laser) listens to.

### Arming an NPC

An NPC (`rpg/scripts/npc/npc.gd`) wields the *same* Weapon component the player does. There are two arming paths:

- **Inline:** set the NPC node's **`weapon_data`** export (`@export var weapon_data: WeaponData`, the "Weapon" group) to any `.tres`. `null` = a **civilian** â€” no gun, laser, or fire path is built, though it still senses, wanders, flees, and faces. A non-null value = a **combatant**.
- **Archetype:** assign an **`NpcData` profile** (`rpg/scripts/npc/npc_data.gd`) â€” assigned to the NPC's **`profile`** export â€” whose own `weapon_data` field is set; `_apply_profile()` stamps it (plus `muzzle_offset`, `weapon_mesh_rotation`, `rate_of_fire_factor`, etc.) onto the NPC. Use a profile to define a reusable "raider"/"sniper" once instead of overriding ~40 fields per instance.

On spawn the NPC seeds its backpack from `weapon_data` (so it drops a real, lootable weapon on death) and stashes starting clips for that caliber automatically (`_equip_initial_weapon`, count from `GameSettings.npc_ai.starting_clips`). It then draws the **strongest** gun in its bag (ranked by `WeaponData.power_score()`) â€” so if you add a better weapon via **`starting_items`** (the `Array[Item]` of deterministic carried gear) or **`item_stacks`**, that one gets equipped instead. Per-NPC firing tweaks: `rate_of_fire_factor`, `miss_chance`, `fire_range` (the engage fallback for an unranged weapon like the rock), and `starts_unloaded` (forces a reload before the first shot).

### Melee vs. ranged

Look at `melee.tres` and `fists.tres` for the melee idiom â€” the difference is entirely in the `.tres` data, not a separate class:

- `is_infinite_ammo = true`, `max_ammo = 1`, empty `caliber` â†’ never reloads, never runs dry.
- No `projectile_scene`, `projectile_speed = 0`, small `effective_range` (the knife is `3.0`, fists `1.5`) â†’ the hit is applied directly, no hitscan/projectile rig needed.
- `has_muzzle_flash`, `has_laser_sight`, `spawns_casing` all `false`; fists set `no_ads = true`.
- Negative `self_knockback` (the knife's `-2.5`) and `launch_on_scoped_attack = true` give the knife its ADS-dash lunge.

A ranged weapon is the inverse: a real `caliber`, a `projectile_scene` (or none for pure hitscan), a meaningful `max_ammo` and `reload_time`, and the muzzle/casing/laser cosmetics turned on.

### Gotchas

- **Caliber strings must match exactly.** A weapon with a `caliber` that has no matching AMMO `Item` in `resources/items/` can be fired only until the loaded clip empties â€” it can never be reloaded. For a free-reloading weapon (melee, rock), the caliber must be *empty*, not a made-up string.
- **Don't confuse "infinite ammo" with the clip count.** `is_infinite_ammo = true` still wants a sane `max_ammo` (the HUD shows it), but the count is cosmetic â€” `consume_ammo()` short-circuits on the flag.
- **`weapon_slots` is typed `Array[Resource]`, not `Array[WeaponData]`**, on purpose (Godot 4's typed-array `.tscn` serialization is unreliable for `script_class` types). Drop your WeaponData `.tres` in anyway â€” it's validated as `WeaponData` at use time. The same trap is why `Loadout.weapons` and `starting_items` are authored as typed arrays only via the editor.
- **A profiled NPC is all-or-nothing by default.** If you assign an `NpcData` profile, it drives the NPC entirely (including `weapon_data`); inline exports are overwritten -- unless you tick `profile_fills_blanks_only` (additive merge: your inline tweaks win). To vary one stat, author a profile variant `.tres` or use that flag.
- After saving a brand-new `WeaponData` or ammo `Item`, give the editor a moment to reimport before referencing it elsewhere â€” a freshly written `.tres` can briefly read as empty in headless runs.

Key files: `rpg/scripts/combat/weapon_data.gd`, `rpg/scripts/combat/ammo.gd`, `rpg/scripts/combat/loadout.gd`, `rpg/scripts/combat/swap_weapons.gd`, `rpg/scripts/combat/inventory.gd`, `rpg/scripts/items/item.gd`, `rpg/scripts/items/item_db.gd`, `rpg/scripts/npc/npc_data.gd`, `rpg/scripts/npc/npc.gd`; content in `rpg/resources/weapons/` and `rpg/resources/items/`.

---

## The drop-in component catalogue

This is the heart of building CYBER SUNDAY without code. A **drop-in component** is a script with a `class_name` (a `Node`, `Area3D`, `StaticBody3D`, etc.) that carries a whole behaviour plus its `@export` knobs. You never edit the script â€” you **attach it in the scene under the thing it should affect, then fill in its `@export` fields in the inspector.** The component's `_ready()` finds its host (usually `get_parent()`, or a `highlight_target` you point at), wires itself up, and runs. Stack as many as you like: a crate can carry `CanDestroy` + `SpawnOnDestroy`; a campfire can carry `Bonfire` + `LevelUp`.

### The idiom in 4 steps

1. In the scene tree, **add a child node** of the right base type (the catalogue below tells you which) under the object you want to give the behaviour to.
2. **Attach the component script** (or drop its prefab `.tscn`) â€” the node now shows the component's `@export` fields in the inspector.
3. For look-at interactables, **size the `CollisionShape3D`** to cover the body the player aims at (or set `auto_fit_collider = true` to let it fit the host's meshes at runtime). Several pickups *build their own* visual + hitbox when you leave the body unauthored.
4. **Fill the `@export` fields** â€” an `Item`, a `PackedScene`, a name string, costs. Done. No code.

### The "look-at interactable" family

The most common base is **`LookAtInteractable`** (`extends Area3D`, `rpg/scripts/components/look_at_interactable.gd`). It is the shared talk-layer hitbox + white look-at outline that the player's interaction ray (`PickupRay`) detects. You rarely attach it raw â€” you attach one of its subclasses below. Its own knobs are inherited by all of them: `highlight_target` (the `Node3D` to outline; null â†’ parent), `highlight_color`, `highlight_width`, and `auto_fit_collider` (opt-in runtime hitbox-fitting, default `false`). Every subclass overrides `start_talk()` / `can_be_talked_to()` / `look_name()` to add only its own verb, so the ray needs zero changes per component.

### The catalogue

**World interaction â€” look at it, press E (Interact):**

- **`CanPickUp`** (`can_pick_up.gd`) â€” add a configured `Item` to the player's backpack. Drop under the visible object (or assign `highlight_target`). Knobs: `item`, `amount`, `item_stacks` (count-based pile, e.g. "2 stims + 10 ammo"), `loot_table` (random bag on top), `pickup_label`, `build_model_from_item` (spawn its visual from `item.world_model`).
- **`MoneyPickUp`** (`money_pickup.gd`) â€” a stash of zorkmids; collects `amount` (a `float` â€” fractional fines are allowed), toasts, frees itself. Drop a bare node and it builds a gold coin + hitbox for you; or set `world_model` / `highlight_target`. Knobs: `amount`, `pickup_label`, `world_model`.
- **`UpgradePickup`** (`upgrade_pickup.gd`) â€” permanently grants a player ability. Drag an ability scene from `scenes/components/abilities/*.tscn` into `grants`; set `display_name`, `toast_color`, optional `world_model`. (`unlock_id` is a legacy string fallback with a dropdown of `grapple,laser_sight,wall_climb,air_dash,slide`.) Builds a glowing emblem when you leave the body unauthored.
- **`ItemContainer`** (`container.gd`) â€” a persistent lootable crate/chest/locker (two-way transfer, never freed). Drop under the prop, size its `CollisionShape3D`. Knobs: `item_stacks` (preferred count-based contents), `starting_items` (legacy), `money`, `loot_table`, `container_name`. (Child a `Lock` to keep it shut until picked/keyed.)
- **`LootableCorpse`** (`lootable_corpse.gd`) â€” a dead body's loot hitbox; opens the loot screen. Normally spawned by the gore/death system (not hand-placed), but it's the same family. Knob: `trigger_radius`.
- **`Merchant`** (`merchant.gd`) â€” a shop. Two modes: `standalone` (default; aim+interact opens the shop) or data-only on a dialogue NPC (`standalone = false`, the NPC's dialogue offers "Trade"). Knobs: `stock_counts` (preferred `StockEntry` rows â€” each is an `item` + a `count`), `starting_stock` (legacy), `shop_name`, `money` till, `buy_mult` / `sell_mult`.
- **`Healer`** (`healer.gd`) â€” pay to restore HP-to-full + clear limb damage. Same dual `standalone` pattern. Knobs: `heal_name`, `cost_per_hp`, `min_cost`, `standalone`.
- **`Bonfire`** (`bonfire.gd`) â€” rest/checkpoint: full heal + set respawn point. Dual `standalone`. Knobs: `bonfire_name`, `standalone`.
- **`LevelUp`** (`level_up.gd`) â€” spend zorkmids to raise a `CharacterStat`; cost rises with total level. Dual `standalone`. Knobs: `station_name`, `base_cost`, `cost_per_level`. (Dark-Souls bonfire = put a `Bonfire` *and* a `LevelUp` on the same node.)
- **`Radio`** (`radio.gd`) â€” an in-world radio that ducks during combat/dialogue; plays a shipped `fallback_audio` track out of a spatial `AudioStreamPlayer3D`. Drop under a radio prop. Knobs: `radio_name`, `fallback_audio` (plus fade/duck and click-SFX tuning).
- **`Talkable`** (`talkable.gd`) â€” make ANYTHING speakable (villager, terminal, vending machine) without overriding the host's root script. Instance `talkable.tscn` under the host, assign a `DialogueResource` to `dialogue` (and optional `voice`), size the shape. Use **`DialogueNPC`** (`dialogue_npc.gd`) instead when you want the whole node to *be* the talkable (script on the root, with a child Area3D assigned to `range_area`).

**Locking:** **`Lock`** (`lock.gd`, plain `Node`) â€” drop under any interactable (a container today, a door later) and the host checks it before opening. Knobs: `locked`, `requires_item_id` (default `&"lockpick"`; set a key/keycard id for a keyed variant), `consumes_item` (off for a reusable key). Emits `unlocked(by)`.

**Destruction & drops:**

- **`CanDestroy`** (`can_destroy.gd`, `extends StaticBody3D`) â€” a body that breaks when shot (works for every weapon; both hitscan and projectiles call `take_damage`). Use it as the root of a breakable, give it a `CollisionShape3D` + `MeshInstance3D`. Knobs: `max_hp`, `destroy_effect`, `destroy_sound`. Emits `destroyed`.
- **`SpawnOnDestroy`** (`spawn_on_destroy.gd`, plain `Node`) â€” drop UNDER a `CanDestroy` or `Throwable` and it spawns loot into the level when the host breaks. Knobs: `spawn_scene` (e.g. a `CanPickUp` prefab), `count`, `scatter`, optional `loot_table` (rolls and stamps each rolled item onto a copy). Pair the two for "shoot the crate for loot."
- **`Throwable`** (`Throwable.gd`, `@tool`, `extends RigidBody3D`) â€” a pick-up-and-throw physics object (a crate). Emits `destroy` on break, so `SpawnOnDestroy` works on it too.

**NPC / character presentation (drop under the Enemy root):**

- **`BodyModelSwap`** (`body_model_swap.gd`, `@tool`) â€” swap an NPC's body/head (and even arms/legs) for your own `.glb` files with a **live editor preview**. Knobs include `body_model`, `head_model`, and `*_scale` / `*_position` / `*_rotation` for each part, optional `*_texture` / `*_color` re-skins, arm/leg gait-animation tuning, plus a momentary `refresh_preview`. Note: the head scale/pos/rot knobs are named `head_scale` / `head_position` / `head_rotation` (the body's are `body_model_scale` / `body_model_position` / `body_model_rotation`). If you use `head_model`, clear the NPC's own `head_scene`.
- **`NpcHeadLookMount`** (`npc_head_look_mount.gd`) â€” FNV-style independent head tracking (the head turns to its foe/player/noise). Drop one under the Enemy root. Knobs: `enabled`, `look_range`, `max_yaw_deg`, `max_pitch_deg`, `turn_speed`, `look_at_player`, `host_path`. **Inert** unless `GameSettings.npc_ai.head_look` is also on.
- **`LocomotionFx`** (`locomotion_fx.gd`) â€” footstep SFX + landing thud + dust for any `CharacterBody3D`. NPCs auto-build one, so you only attach it to override. Knobs: `footstep_sounds`, `land_sound`, `stride_length`, `move_threshold`, `footstep_volume_db`, `land_volume_db`, `min_land_speed`, `hard_land_speed`.
- **`FallScream`** (`fall_scream.gd`) â€” plays a yell after falling for a moment, re-arms on landing. Drop under any `CharacterBody3D`. Knobs: `scream` (clear it â†’ inert), `min_fall_time`, `min_fall_speed`, `volume_db`.

**Player abilities** (all `extends Ability`, `rpg/scripts/components/abilities/`) â€” drop under a Player; the node's **presence** grants the mechanic, stack as many as you want. **`Grapple`** (the grappling hook, owns its rope config `.tres` via `config: GrappleHookResource`), **`WallClimb`** (owns its climb tuning, e.g. `climb_hop_up` / `climb_hop_forward`), **`Slide`**, **`AirDash`**, **`LaserSight`**. Each inherits `enabled` from `Ability` (off â†’ temporarily revoked without removing the node). These are usually *granted* via an `UpgradePickup`, but you can pre-attach them to start the player with the mechanic.

**Ambience & titles:**

- **`SkyTitle`** (`sky_title.gd`) â€” a depth-tested "drawn in the sky" title card that the skyline occludes; fades in on a music cue. Drop ONE under the Game root. Knobs: `text` (default `"CYBER SUNDAY"`), `cue_seconds`, `fade_in_time`, `hold_seconds`, `fade_out_time`, `sky_distance`, plus size/colour knobs (`pixel_size`, `font_size`, `text_color`, `vertical_stretch`) and a `test_show_immediately` preview toggle.
- **`AmbientDust`** (`ambient_dust.gd`, `extends GPUParticles3D`) â€” level-wide floating motes that re-centre on the camera. Drop ONE anywhere. Knobs: `motes`, `mote_lifetime`, `volume_extents`, `mote_size` (plus `mote_color`, `drift`, `turbulence`).
- **`MusicDirector`** (`music_director.gd`) â€” dynamic music: the parent track plays constantly but stays silent in exploration, fading IN during combat/dialogue. Drop as a **child of the music `AudioStreamPlayer` / `AudioStreamPlayer3D`** (an `AudioStreamPlayer2D` parent is also accepted); it captures the parent's `volume_db` as the audible level.
- **`NoiseSource`** (`noise_source.gd`) â€” a point of sound NPCs can hear and investigate (the stealth distraction channel). Knobs: `radius`, `decay`, `lifetime` (persistent when both `decay` and `lifetime` are 0; a self-freeing one-shot otherwise). Inert unless `GameSettings.npc_ai.hearing_initiates` is on.

**Mostly auto-wired (rarely hand-placed, but they are `class_name` components):** **`Ragdoll`** (`ragdoll.gd`) â€” needs a one-time editor setup (Create Physical Skeleton on a rigged `.glb`, then assign the scene to the enemy's `ragdoll_scene`); **`Explosion`** (`explosion_area.gd`, `extends Area3D`) + **`ExplosionMesh`** (`explosion_mesh.gd`) â€” radial blast prefab; **`ShellDrop`**, **`MuzzleFlash`**, **`SparkAttack`**; and the gun-rig effects in `scripts/effects/` (**`GunMesh`**, **`GunVisuals`**, **`GunPose`**, **`MuzzleRig`**, **`WeaponModelSwapper`**, **`BloodSplatter`**, **`BloodDropEmitter`**, **`ParticleTimeBind`**) â€” these are internal to weapon/character prefabs; you tune their `@export`s but don't drop them onto level geometry.

### Worked example: a shoot-to-break crate that drops a pistol

1. Add a **`CanDestroy`** node (it's a `StaticBody3D`); give it a `CollisionShape3D` + `MeshInstance3D` (your crate mesh). Set `max_hp = 3`, assign `destroy_effect` (a debris VFX scene) and `destroy_sound`.
2. As a **child** of that `CanDestroy`, add a **`SpawnOnDestroy`** node. Set `spawn_scene` to a `CanPickUp` prefab and `count = 1` â€” or, for randomised drops, assign a `loot_table` `.tres` instead (it rolls and stamps each item onto a copy of the pickup, and sets `build_model_from_item` on each so the rolled item shows its own world model).
3. Optionally also child a **`Lock`**? No â€” that's for openables, not breakables. Instead, drop a **`MoneyPickUp`** prefab into the loot table too if you want cash to scatter.
4. Run. Shoot the crate 3 times â†’ it plays the VFX/sound, frees itself, and the pickup drops into the level (`current_scene`, so it outlives the crate) where the player can aim at it and press E.

### Gotchas

- **Two components have a global gate, not just a local toggle.** `NpcHeadLookMount` (`GameSettings.npc_ai.head_look`) and `NoiseSource` (`GameSettings.npc_ai.hearing_initiates`) are **inert until the matching global flag is on**, on purpose â€” attaching them changes nothing until you flip the registry flag for a playtest. (A playing `Radio`'s NPC reactions sit behind a third such flag, `GameSettings.npc_ai.music_reactions`.)
- **Parent matters.** `SpawnOnDestroy` and `MusicDirector` connect to / read their **parent**, so they must be a *child of the right host* (a `CanDestroy` / `Throwable`, or the music player). `Lock` must be a child of the interactable it guards (it's discovered via `Lock.of(host)`, which scans the host's children).
- **Size the hitbox.** Look-at interactables only respond where their `CollisionShape3D` covers â€” if E does nothing, the shape is too small or missing. Set `auto_fit_collider = true` to fit it to the host's meshes at runtime (note: the editor still shows the authored shape; only gameplay uses the fitted one).
- **The two "build their own body" pickups vs. CanPickUp.** `MoneyPickUp` and `UpgradePickup` build their default coin/emblem only when `highlight_target` is left **null/unassigned**; assign a `highlight_target` (or a `world_model`) and they use your authored model instead. `CanPickUp` is different: it builds its visual only when you tick **`build_model_from_item = true`** (and the `item` has a `world_model`) â€” it doesn't key off `highlight_target` at all. Leave `build_model_from_item` off and author the body yourself (under the node, or via `highlight_target`).
- **Dual-mode stations** (`Merchant`, `Healer`, `Bonfire`, `LevelUp`): set `standalone = false` when the station lives on a dialogue NPC, or the interaction ray will grab the station instead of letting the NPC's `Talkable` drive the conversation.

Relevant files (all under `C:\Users\dalla\3D RPG\rpg\scripts\`): `components\*.gd`, `components\abilities\*.gd`, `effects\*.gd`; base class `components\look_at_interactable.gd`.

---

## Global tuning (GameSettings) and the settings menu

Most of CYBER SUNDAY's "feel" numbers â€” how fast you run, how wide the FOV is, how hard explosions shake the screen, how gory a death is, how NPCs investigate noise â€” do **not** live in scripts. They live in a set of authored Resource files under `res://resources/tuning/`, and a single autoload exposes them to the whole game. This is the **global tuning** layer: numbers that apply everywhere, edited entirely in the inspector.

This is distinct from per-instance tuning (an `@export` you set on one node in one scene) and from content (`.tres` like `Item`, `NpcData`, `Loadout`). Use a tuning group when a number is **the same across the whole game** and you want one place to dial it.

### The registry: `GameSettings`

`rpg/managers/GameSettings.gd` is an autoload (a Node that's always loaded). It does one job: it `preload()`s every tuning `.tres` and hangs it off a named property. Every system in the game reads its numbers as `GameSettings.<group>.<field>` â€” for example the player reads `GameSettings.player_movement.max_speed`, the camera reads `GameSettings.camera.default_fov`. You never touch that code; you just edit the `.tres` the property points at.

The groups, the property name, the file, and what each governs:

| `GameSettings.` property | Resource file (`res://resources/tuning/â€¦`) | Governs |
| --- | --- | --- |
| `player_movement` | `PlayerMovementSettings.tres` | Run speed (`max_speed`), backward/strafe multipliers, jump velocity, coyote-time & jump-buffer windows, ground/air accel smoothing, footstep cadence, landing-impact divisor |
| `player_crouch` | `PlayerCrouchSettings.tres` | Crouched height ratio, crouch-walk speed penalty, lerp in/out rate, stand-up ceiling clearance, quieter crouched footstep dB |
| `player_aim` | `PlayerAimSettings.tres` | Deus Ex-style aim-wander amplitude by stance (moving loose / standing tighter / crouching tightest), plus the hold-still "settle" that tightens it over time |
| `bunnyhop` | `BunnyhopSettings.tres` | Bhop boost-per-hop, chain max speed, land/input windows, and the speed-based look-sensitivity falloff |
| `camera` | `CameraSettings.tres` | `mouse_sensitivity`, pitch limits, `default_fov` / `scoped_fov`, dynamic FOV kicks (fall/rise/forward/dash), head-bob, landing dip, strafe tilt |
| `screen_shake` | `ScreenShakeSettings.tres` | Trauma `decay_rate`, master `intensity_multiplier`, death-shake range/amount, explosion shake caps |
| `weapon_general` | `WeaponGeneralSettings.tres` | Weapon-wide (not per-gun): `swap_time`, muzzle-flash duration, ADS spread divisor / speed penalty / range multiplier, bullet-time slow-mo, hitstop scaling, tracers |
| `effects` | `EffectsSettings.tres` | Visual FX: decal fade/placement, dust puffs, the on-screen blood overlay, gore gibs & world blood drops, explosion visuals, sky/hit flashes |
| `audio` | `AudioSettings.tres` | Landing thump, falling/fast-move wind swell, bullet/muzzle whiz pitch, impact & enemy-hit-by-HP pitch, ammo-driven fire pitch |
| `physics_damage` | `PhysicsDamageSettings.tres` | Explosion damage, blast decay, ram/body-check, character-vs-rigidbody push, pickup/throw impact behaviour |
| `economy` | `EconomySettings.tres` | Every bounty, trick-shot reward, and seed value (zorkmids are fractional) |
| `player_feedback` | `PlayerFeedbackSettings.tres` | The hurt/death/spawn arc: hit slow-mo + muffle, red hurt flash, damage thud, death cinematic, respawn/spawn fade, dash-recharge & kill flashes |
| `npc_ai` | `NpcAiSettings.tres` | Species-wide NPC brain dials: retarget interval, engage/point-blank ranges, self-care, companion follow, scavenging, and the stealth toggles (`body_discovery`, `hearing_initiates`, `hearing_occlusion`, `music_reactions`, `head_look`) |
| `reputation` | `ReputationSettings.tres` | Faction-standing penalties and the HOSTILE / FRIENDLY thresholds (NEUTRAL is the band between them) |
| `distraction` | `DistractionSettings.tres` | Default noise of a thrown decoy (the "lob a rock to lure a guard" verb; inert unless `npc_ai.hearing_initiates` is on) |
| `search` | `SearchSettings.tres` | How an NPC HUNTS a lost target / noise: the uncertainty ring (`max_search_radius`, `uncertainty_grow_rate`, `min_search_radius`, `sample_points`, `crumb_timeout`), per-stimulus seeds (`noise_radius_scale`, `corpse_radius_frac`, `seed_radius`), and the frantic→resigned `intensity_curve` + dwell (`crumb_dwell_min/max`). INERT at defaults (`max_search_radius` 0 / `sample_points` 1 = today's single-point stare); raise both to turn the breadcrumb hunt on |

### Editing a tuning value in the inspector

1. In the **FileSystem** dock, open `res://resources/tuning/` and double-click the group you want, e.g. `EffectsSettings.tres`.
2. The **Inspector** shows the fields, organised under the `@export_group` headers you see in the table (Decals, Dust, Gore gibs, â€¦). Every field has a tooltip describing exactly what it does and which direction is "more".
3. Change the value and **save** (`Ctrl+S`). Because `GameSettings` preloads that same file, the new number is live the next time you run â€” no code, no recompile.

**Worked example â€” make the whole game gorier.** Open `EffectsSettings.tres`. Under **Gore gibs**, raise `gib_count` from `6` to `12` and bump `gib_max_active` from `24` to `48` so the extra chunks aren't reclaimed immediately. Under **Blood drops (world)**, raise `blood_drop_count` from `24` to `40`. Save. Done â€” every bloody-mess death in every scene now bursts bigger, and you never opened a script.

### The rule: player-facing tunables and keybinds must ALSO reach the settings menu

Here's the catch that trips people up. A tuning `.tres` value is a **designer** knob â€” great for things the player never touches (gib count, NPC retarget interval, faction thresholds). But the moment a value is something a **player** should control â€” volume, sensitivity, FOV, an accessibility/comfort toggle, screen-shake strength â€” the project rule from `rpg/CLAUDE.md` ("Keep the settings menu in sync with features") says it must **also** be wired through two more files, or the in-game options screen silently won't have it:

- **`rpg/managers/Settings.gd`** â€” the player-facing OPTIONS + persistence autoload. This is *not* the same as `GameSettings`. `Settings` owns only what the Options menu can change: it stores the player's choice, saves it to `user://settings.cfg`, loads + applies it on boot, and (where relevant) pushes it onto the right `GameSettings` field. For instance `Settings.set_fov()` clamps to `FOV_MIN..FOV_MAX` (60â€“120) and writes `GameSettings.camera.default_fov`; `set_mouse_sensitivity()` writes `GameSettings.camera.mouse_sensitivity`; `set_screen_shake_scale()` scales `GameSettings.screen_shake.intensity_multiplier` (off a baseline captured at boot). The pattern for a new tunable: add a stored `var`, a `set_â€¦()` that applies + calls `save_settings()`, and a line in both `load_settings()` and `save_settings()` for the `.cfg`.
- **`rpg/scripts/ui/options_menu.gd`** -- the `OptionsMenu` overlay (autoload, opened with Escape; serves both the start menu and in-game). It is fully DATA-DRIVEN: every row is a `SettingSpec` in `resources/settings/SettingsCatalog.tres`, and `_rebuild_tabs()` iterates `CATALOG.specs` and lets `_emit_row()` build each control by dispatching on `SettingSpec.Widget` (Section / Toggle / Slider / Dropdown / Keybind / Custom). Tabs appear in the order their first spec is seen; edits stage into `_pending` and only commit on **Apply** (key rebinds are the exception -- they bind live). You do NOT hand-build rows here: to add an option you add a typed `var` + a `set_*` setter to `Settings.gd`, then add ONE `SettingSpec` row to the catalog (no `options_menu.gd` edits).

**Keybinds** are also data-driven. To add a rebindable action: add its keyboard/mouse default to `project.godot`'s `[input]` map (the editor's Input Map panel) and its controller default in `managers/InputManager.gd`, **then** add ONE `ActionSpec` row (`action` / `label` / `section` / `rebindable`) to `resources/input/ActionCatalog.tres`. The Controls-tab section headers + rebind rows are GENERATED by `ActionCatalog.keybind_specs()`, which `OptionsMenu` appends to `CATALOG.specs` in `_rebuild_tabs()` -- so do NOT hand-author a `Keybind` `SettingSpec` in `SettingsCatalog.tres`. The action *name* is the stable key -- rebinding only swaps the bound event, so everything that polls the action name keeps working. `Settings.rebind_action()` persists the new event under the cfg's `[controls]` section.

So the mental model is: **`GameSettings` = the designer's master tuning sheet; `Settings` = the slice of it (plus video/audio/keybinds) the player is allowed to override, persisted to disk; `OptionsMenu` = the screen that drives `Settings`.** A pure balance number stops at `GameSettings`. A player-facing one travels through all three.

### Gotchas

- **Don't confuse `GameSettings` with `Settings`.** They're two different autoloads. `GameSettings` holds the live `.tres` numbers; `Settings` holds the saved player overrides and *writes into* a few `GameSettings` fields on apply. Editing `CameraSettings.tres`'s `default_fov` changes the authored default; `Settings` will overwrite it on boot with the player's saved FOV (it seeds *from* the design default only when there's no `settings.cfg` yet). So if a value seems to ignore your `.tres` edit at runtime, check whether the Options menu owns it.
- **A player-facing value added only to a `.tres` will never appear in the Options menu.** The menu is built from `Settings`, not from `GameSettings`. Skipping the `Settings.gd` + `options_menu.gd` wiring is the single most common way a new comfort/audio/sensitivity option ends up uncontrollable in-game.
- **`intensity_multiplier = 0` (ScreenShake) and `bob_amount = 0` (Camera) fully disable** those effects â€” handy, but note the same outcomes are reachable by players via the Accessibility tab's Screen Shake slider and View Bobbing toggle. Prefer leaving the `.tres` at the authored baseline and letting the player opt out, since `Settings` captures that baseline at boot to anchor its percentage sliders.
- **The `npc_ai` stealth/comfort toggles (`body_discovery`, `hearing_initiates`, `hearing_occlusion`, `music_reactions`, `head_look`) default to `false` on purpose** â€” off means the NPC code path is byte-identical to the old behaviour. Flip one on, then playtest; some (like `head_look`) can need a per-rig axis tweak.
- **All of the radio's feel lives on the `Radio` component's own `@export`s** (duck/settle timings, fade times, click SFX, audible radius) â€” there's no global radio tuning group; per-instance `@export`s cover everything.

Relevant files: `rpg/managers/GameSettings.gd`, `rpg/managers/Settings.gd`, `rpg/scripts/ui/options_menu.gd`, and the group definitions in `rpg/resources/tuning/*.gd` with their authored values in the matching `rpg/resources/tuning/*.tres`.

---

## NPC services and progression (shops, healing, companions)

Any NPC in CYBER SUNDAY can offer a *service* the same way it offers anything else: you drop a **component** under it in the scene tree and fill in a few `@export` fields. There's no scripting. The dialogue system scans the NPC you're talking to for these components and automatically adds the matching button to the conversation menu â€” "Trade", "Heal", "Rest", "Level Up", plus "Follow me"/"Wait here" for recruitment. This section covers the five service components and how to wire each one.

### The big idea: `standalone` vs. data-only

Four of the five components (`Merchant`, `Healer`, `Bonfire`, `LevelUp`) all extend `LookAtInteractable` and share one decisive flag: **`standalone`** (a `@export bool`, default `true`).

- **`standalone = true`** â€” the component is a *self-serve prop*. It sits on the talk layer, so aiming at it and pressing Interact opens the service directly. Use this for a vending machine, a healing fountain, a lit campfire, a level-up shrine. No NPC or dialogue needed.
- **`standalone = false`** â€” the component becomes **data-only**: the aim ray ignores it entirely (its `collision_layer` is set to `0`). You attach it *under a dialogue NPC* (one that already has a `Talkable` driving its conversation). The NPC's dialogue then grows the matching option â€” "Trade", "Heal", etc. â€” that opens this component's service. This is how one NPC both *talks* and *trades*.

So the universal recipe for a service NPC is: an NPC with a `Talkable` (for conversation) **plus** a service component as a sibling child with `standalone = false`.

The dialogue manager finds each service by duck-typing the speaker's direct children (`rpg/scripts/dialogue/dialogue_manager.gd`), so the component must be a **direct child** of the NPC node. It doesn't care about the class name â€” only the method signature â€” but using the real components below is the supported path.

---

### Merchant (the "Trade" option) â€” `rpg/scripts/components/merchant.gd`

Drop a **`Merchant`** node under the shopkeeper. The dialogue adds "Trade" when the speaker has a child exposing `buy` + `sell`; picking it *suspends* the conversation and opens `ShopScreen` on this merchant's stock â€” closing the shop drops you back into the conversation rather than ending it.

Fields, grouped as they appear in the inspector:

**Stock**
- **`stock_counts: Array[StockEntry]`** â€” the preferred way to author what's for sale. Each `StockEntry` (`rpg/scripts/components/stock_entry.gd`) is one row with an **`item: Item`** and a **`count`** (`@export_range(1, 999)`, default `1`). Weapons are stocked as one *unique* instance per count, so "2 shotguns" really is two distinct objects.
- **`starting_stock: Array[Item]`** â€” legacy flat list; each entry stocks x1. Both lists seed together, so you can mix them.

**Display**
- **`shop_name: String`** â€” shown on the look-at hover ("Trade: <name>") and the shop title. Blank falls back to "Merchant".

**Pricing**
- **`money: float`** (default `1000.0`) â€” the merchant's till. Selling *to* it draws from this; it can't buy what it can't afford.
- **`buy_mult: float`** (default `1.0`) â€” the player buys at `item.value Ã— buy_mult`. `>1.0` marks up.
- **`sell_mult: float`** (default `0.5`) â€” the player sells at `item.value Ã— sell_mult`. `<1.0` is the merchant's cut. (The player's persuasion stat further nudges both prices at runtime via `buy_price_mult()` / `sell_price_mult()`.)

**Behavior**
- **`standalone: bool`** â€” leave `true` for a vending machine; set `false` under a dialogue NPC.

### Healer (the "Heal" option) â€” `rpg/scripts/components/healer.gd`

Drop a **`Healer`** under the medic. The dialogue adds "Heal" when the speaker has a child with `do_heal` + `heal_cost`; it suspends the conversation and opens `HealScreen`. A heal restores HP to **full** and clears **all** limb damage in one purchase.

- **`heal_name: String`** â€” hover + screen title; blank â†’ "Healer".
- **`cost_per_hp: float`** (default `1.0`) â€” zorkmids charged per point of *missing* HP. Cost is linear in how hurt you are.
- **`min_cost: int`** (default `5`) â€” floor charged whenever there's any damage (covers a limb-only heal where HP is full).
- **`standalone: bool`** â€” `true` for a med-station; `false` under a dialogue NPC.

If the player is at full HP with no limb damage, `heal_cost` returns 0 and the service is free/refused â€” so a healer never charges for nothing.

### Bonfire (the "Rest" option) â€” `rpg/scripts/components/bonfire.gd`

Drop a **`Bonfire`** under a campfire prop or NPC. The dialogue adds "Rest" when the speaker has a child with `rest`. Resting is instant (no sub-screen): it **full-heals** (HP + limbs), sets **this** node as your respawn point via `GameState.set_respawn(global_position, global_rotation.y)`, and autosaves via `GameState.autosave`. On death you return *here* â€” the world is not reset.

- **`bonfire_name: String`** â€” hover + toast ("Rested at <name>"). Note the *hover* label when blank reads "Rest at bonfire" (not "Bonfire"), and the toast when blank reads "Rested at the bonfire".
- **`standalone: bool`** â€” `true` for a lit campfire you aim at; `false` to expose it through a dialogue NPC's "Rest".

### LevelUp (the "Level Up" option) â€” `rpg/scripts/components/level_up.gd`

Drop a **`LevelUp`** under a trainer or shrine. The dialogue adds "Level Up" when the speaker has a child with `level_up_stat` + `level_up_cost`; it suspends the conversation and opens `LevelUpScreen`, where the player spends zorkmids to raise any one of `strength`, `persuasion`, `gunplay`, `endurance`, `streetwise`, or `agility` by 1.

- **`station_name: String`** â€” hover + screen title; blank â†’ "Level Up".
- **`base_cost: int`** (default `1`) â€” cost at total level 0.
- **`cost_per_level: float`** (default `1.5`) â€” added per point already invested, so cost climbs Dark-Souls style with your total level (the sum of all six stats). The cost is the same for every stat. Formula: `base_cost + (total_level Ã— cost_per_level)`.
- **`standalone: bool`** â€” `true` for a self-serve shrine; `false` under a dialogue NPC.

Endurance raises max HP (`max_hp_bonus()`) and strength raises carry capacity (`carry_bonus()`) automatically â€” both applied as a *delta* so the bonus isn't double-counted; the other stats are read live at their own seams. Raising a stat also heals you by the gained max HP and autosaves the run.

> **Dark-Souls bonfire pattern:** put a **`Bonfire`** *and* a **`LevelUp`** on the same node. Resting heals + sets respawn, and the same spot lets you spend levels.

---

### Companions: the "Follow me" / "Wait here" option

Recruitment is different â€” it isn't a separate component you drop on, it's a **contract already built into the `NPC` script** (`rpg/scripts/npc/npc.gd`). The dialogue's `CompanionRecruiter` (`rpg/scripts/dialogue/companion_recruiter.gd`) checks the speaker for `can_recruit` / `is_following` and shows the right label:

- A recruitable NPC offers **"Follow me"** â†’ calls `start_following(player)`; the NPC acknowledges with a spoken "Alright." and joins the `&"Player"` group so enemies treat it as an ally, wears the blue companion rim, and tails you.
- A companion already at your side offers **"Wait here"** â†’ calls `stop_following()`; the button flips back to "Follow me".

What makes an NPC recruitable is **`can_recruit()`**, which is true only when:
1. its **resolved disposition toward the player is `FRIENDLY`** (`resolved_disposition() == Disposition.Kind.FRIENDLY`), and
2. it isn't already following someone (`not is_following()`).

So to author a recruitable companion, the lever is the NPC's **`disposition`** `@export` (`Disposition.Kind`, defaults to `HOSTILE`). Set it to **`FRIENDLY`** in the inspector (or via the NPC's profile / `disposition_overrides_faction` if faction would otherwise win out). A merely *neutral* or hostile NPC will *not* show the recruit button â€” that's by design. No extra node is required for basic recruitment.

The follow *behaviour* (escorting at a standoff, and the off-screen "blink up behind you" teleport) lives in the **`CompanionFollow`** child (`rpg/scripts/npc/companion_follow.gd`) that `NPC` builds for itself at runtime; you don't place it. Its dials (`follow_standoff`, `follow_teleport_distance`, `follow_teleport_cooldown`) are global tunables on **`GameSettings.npc_ai`** (a `NpcAiSettings` resource), not per-instance exports.

**Bonus â€” "Exchange Gear":** once an NPC is *following you* and carries a `CharacterInventory` (its `inventory` reads as one), the dialogue also offers "Exchange Gear" (a two-way transfer screen, `LootScreen.exchange`, capped by the companion's carry capacity). This is automatic for any following companion with a backpack â€” nothing extra to author.

---

### Worked example: a guard who chats, trades, and can join you

1. In your level scene, add the NPC (a node using the `NPC` script with a `Talkable` child for conversation and a `DialogueResource` assigned).
2. In the inspector, set the NPC's **`disposition` = `FRIENDLY`** (this both makes them non-hostile and unlocks "Follow me").
3. Add a **`Merchant`** node as a *direct child* of the NPC. Set **`standalone` = false**. Set `shop_name = "Surplus"`, `money = 500`, `buy_mult = 1.2`, `sell_mult = 0.4`.
4. Fill `stock_counts`: add three `StockEntry` resources â€” `{ item: med_pack.tres, count: 3 }`, `{ item: pistol_ammo.tres, count: 20 }`, `{ item: shotgun.tres, count: 2 }`.
5. (Optional) Add a **`Bonfire`** child with `standalone = false`, `bonfire_name = "Guard Post"`, so the same guard lets you rest and set a respawn.

Now: aim at the guard, press Interact, listen to their line, click to reveal the menu â€” and you'll see your authored choices plus **Trade**, **Rest**, **Follow me**, and **Goodbye**. Trade/Rest run their service and return you to the conversation; "Follow me" recruits them.

### Gotchas

- **Direct child only.** The dialogue manager does a *shallow* scan of the speaker's immediate children. A service component nested two levels deep won't be detected.
- **`standalone = false` for dialogue-driven services.** If you leave it `true` on an NPC, the component sits on the talk layer and the aim ray can fight the NPC's own `Talkable` for the interaction. Off means data-only â€” its `collision_layer` goes to `0`, the ray ignores it, and the dialogue option is the only door.
- **Recruitment hinges on disposition.** No "Follow me" button means the NPC's `resolved_disposition()` isn't `FRIENDLY` â€” check the `disposition` export (and faction/`disposition_overrides_faction` if a faction is overriding it). Neutral is not enough.
- **The follow component is not hand-placed.** Don't add `CompanionFollow` yourself; the `NPC` builds it. Its standoff/teleport numbers are global tunables on `GameSettings.npc_ai`, not per-NPC exports.
- **Heal/Level Up cost can be free/refused.** A healer charges nothing at full health; a level-up is blocked if the player can't afford the (rising) cost. Both are intentional, not bugs.
- **Merchant till limits buybacks.** A merchant with low `money` literally cannot buy expensive items from the player â€” raise `money` if you want a deep-pocketed fence.

Relevant files: `rpg/scripts/dialogue/dialogue_manager.gd`, `rpg/scripts/dialogue/companion_recruiter.gd`, `rpg/scripts/components/merchant.gd`, `rpg/scripts/components/stock_entry.gd`, `rpg/scripts/components/healer.gd`, `rpg/scripts/components/bonfire.gd`, `rpg/scripts/components/level_up.gd`, `rpg/scripts/npc/npc.gd` (companion contract, lines ~1013â€“1057), `rpg/scripts/npc/companion_follow.gd`.

---

## Atmosphere: radio, music and movement FX

This is the audio-and-vibe layer of CYBER SUNDAY: the dynamic combat score, the in-world diegetic radio, the footstep/dust/landing FX that make any actor feel grounded, a falling scream, and the giant timed title that drops out of the sky. Everything here is a drop-in node plus inspector fields â€” no code. Buses matter: the score and the radio's track ride the **`music`** bus; footsteps, landings, screams and the radio click ride the **`sfx`** bus. The Settings volume sliders and the dialogue ducker act on those buses, so as long as you route things to the right bus they cooperate automatically.

### 1. Dynamic combat music (`MusicDirector`)

`MusicDirector` (`rpg/scripts/components/music_director.gd`) is the heart of the score. The trick: your music track **plays constantly** but sits silent during exploration, then fades **in** for combat or dialogue and back out afterward. Because the stream never stops, a fade-in joins the music mid-track instead of restarting it.

**Setup**
1. Add an `AudioStreamPlayer` (or `AudioStreamPlayer3D`) to your level â€” this is your "Music" node. Set its **Bus** to `music`, assign your looping score to **Stream**, and turn on **Autoplay** (and make the stream loop) so the position always advances.
2. Set that player's **Volume dB** to the level you want combat music to reach â€” `MusicDirector` reads the authored volume as its **audible target**.
3. Add a `MusicDirector` node as a **child** of that player. That's it.

**Fields** (`@export`): `fade_in_time` (1.2 s, silenceâ†’audible, fast because combat hits fast), `fade_out_time` (3.0 s, the fight breathing out), `combat_linger` (2.5 s the music holds after the last enemy disengages, so it doesn't flap during a brief lull), and `silent_db` (-60.0, the inaudible floor).

**What triggers it:** any NPC in the `npc` group that reports `is_hunting()` (ALERTED or INVESTIGATING â€” so music stays up while an enemy sweeps your last-known position), OR `DialogueManager.is_active()`. The combat scan runs on a fixed 0.3 s interval (a `POLL_INTERVAL` const, not a tunable). Gotcha worth knowing: if the music node's authored Volume dB is at or below `silent_db`, the fade is a no-op â€” `MusicDirector` will push a warning and drop the floor 20 dB to keep it working, but the clean fix is to raise the node's volume.

### 2. The in-world radio (`Radio`)

`Radio` (`rpg/scripts/components/radio.gd`) is a `LookAtInteractable` â€” the player aims at it and presses Interact to toggle it on/off. While on, it **ducks out during combat and dialogue** and breathes back in afterward (the inverse of `MusicDirector`). It cycles a **folder of tracks** out of a spatial `AudioStreamPlayer3D` â€” truly in-engine, positional, diegetic music, classic-radio style: it auto-advances when a track ends and loops the folder (with an optional per-radio shuffle). An empty/unset folder falls back to a single shipped `fallback_audio` track.

**Setup**
1. Drop a `Radio` node under (or onto) your radio prop. Because it extends `LookAtInteractable`, set **`highlight_target`** to the mesh you want the hover-outline on (defaults to the parent), and size the node's `CollisionShape3D` to the body the player aims at â€” or turn on **`auto_fit_collider`** to auto-fit the hitbox at runtime.
2. Set **`radio_name`** (blank â†’ "radio" in the hover label).
3. Point **`music_folder`** at a folder of `.mp3`/`.ogg`/`.wav` tracks (defaults to the shipped `res://assets/audio/music`). The radio scans it on turn-on and plays through it. Set **`shuffle`** for a per-radio-deterministic random order. Leave **`audio_player`** unset to auto-create a child player on the `music` bus.
4. Optionally assign **`fallback_audio`** â€” a single shipped track used only when `music_folder` has no audio files (so a radio is never accidentally silent).
5. Optionally set **`click_on`** / **`click_off`** (a physical clunk on toggle) and **`click_volume_db`**; these auto-route to the `sfx` bus through a separate `click_player`, so the combat duck never touches them.

**The player's own music (Options â†’ Audio â†’ Music Folder):** the player can point a directory picker at *their own* folder of tracks; that override (`Settings.music_folder`) wins over **every** radio's `music_folder` until they clear it ("Default"). A `res://` folder is loaded through the import pipeline; an outside folder (their Music directory, a `user://` path) is decoded from raw file bytes at runtime (mp3/ogg/wav). Undecodable files are skipped.

**Combat-duck fields:** `combat_strict` (false = duck through the whole hunt like the music; true = only during an active firefight), `poll_interval` (0.3 s), `settle_cooldown` (3.0 s ducked after the last enemy disengages), `fade_pause_time` (0.4 s out), `fade_resume_time` (1.2 s back in), `silent_db` (-60.0), `fallback_volume_db` (0.0). The duck/settle brain is the pure `RadioPlaybackState`; the track ordering is the pure `MusicPlaylist`.

**NPC reactions:** set **`audible_radius`** (12 m) â€” how far a nearby NPC can "hear" a playing radio and react (turn its head toward it, comment by quality). This only fires when `GameSettings.npc_ai.music_reactions` is on; otherwise a playing radio is inert to NPCs. The comment tier comes from `MusicQuality` (`rpg/scripts/components/music_quality.gd`), a deterministic 0..1 score folded from the radio's `quality_text()` â€” the **current track's filename** when a folder is playing (so an NPC scores the actual song), else the `radio_name`. The same string always scores the same, so one NPC consistently loves a track another finds awful. The three tier cuts are `music_tier_meh` / `music_tier_good` / `music_tier_great` on `GameSettings.npc_ai`.

### 3. Movement FX (`LocomotionFx` + `FallScream`)

`LocomotionFx` (`rpg/scripts/components/locomotion_fx.gd`) gives any `CharacterBody3D` footstep SFX while it walks, plus a louder **landing thud + ground-dust puff** on touchdown. The player already has this via `Character`; **every NPC auto-builds one** in `npc.gd`'s `_build_components()` unless you've already dropped a configured `LocomotionFx` under it (so you only add one by hand when you want to override the defaults).

**Setup:** drop a `LocomotionFx` node under the actor. All host reads are duck-typed (`is_on_floor` / `velocity` / `spawn_dust`), so it works on anything that moves. It polls in `_physics_process`.

**Fields:** `footstep_sounds` (an `Array[AudioStream]`, picked at random per step â€” defaults to the shipped Footstep1/2/3 set; empty â†’ silent), `land_sound` (touchdown â€” defaults to the shipped Footstep1, and if you clear it the node reuses the first footstep sound), `stride_length` (1.7 m per step â€” bigger = fewer steps; cadence = stride Ã· speed, clamped to a 0.18â€“1.2 s range, so faster movement = quicker steps), `move_threshold` (0.4 m/s below which no footsteps), `footstep_volume_db` (-8.0), `land_volume_db` (-1.0), and the landing window `min_land_speed` (2.0 â€” below this a touchdown is treated as a stair-step/hop and makes no thud) â†’ `hard_land_speed` (9.0 â€” a full-strength landing: loudest, lowest-pitched, biggest dust). Everything routes to the `sfx` bus via `AudioManager.play_sfx` at the host's position, and the dust puff reuses the host's `spawn_dust(intensity)` (the player/NPC's DustSpawner, exposed on `Character`).

`FallScream` (`rpg/scripts/components/fall_scream.gd`) plays a one-shot yell once an actor has been **falling** long enough, then re-arms on landing â€” good for a comedic plummet off a rooftop.

**Setup:** drop a `FallScream` node under any `CharacterBody3D`. **Fields:** `scream` (the yell â€” the default is a placeholder hurt grunt (`Augh.mp3`), swap it for a real falling yell; clearing it makes the node inert), `min_fall_time` (1.1 s of continuous falling before it fires), `min_fall_speed` (1.5 m/s minimum descent to count as a real plummet, filtering a slope-slide), and `volume_db` (0.0). It's positional on the `sfx` bus, and duck-typed like `LocomotionFx`.

### 4. The sky title card (`SkyTitle`)

`SkyTitle` (`rpg/scripts/components/sky_title.gd`) draws a huge title ("CYBER SUNDAY") parked **far away in the sky** (a real depth-tested Label3D, oriented to the camera each frame), so the city skyline depth-occludes it while it stays big and readable and tracks where the player looks. It fades in at a cue time after the game-start spawn, so the title drop lands a beat into the entrance.

**Setup:** drop **one** `SkyTitle` node under your Game root. It self-arms on spawn (via its own `arm()`) and is also pinged by the player as the spawn fade-in begins (the first arm wins, so it counts from the game start), so the cue runs no matter how the game was launched. The cue + fade run on **wall-clock time**, so they stay on schedule through pause and slow-mo.

**Fields:** `text` ("CYBER SUNDAY" â€” all-caps reads best), `cue_seconds` (168.0 â€” seconds after the spawn before the reveal; **tune by ear**), `fade_in_time` (2.5), `hold_seconds` (30.0), `fade_out_time` (2.5), `sky_distance` (350 m, auto-clamped just inside the camera's far plane so it never gets clipped), `pixel_size` (0.25) + `font_size` (256) + `text_color` (white) for size/colour, and `vertical_stretch` (1.5 â€” taller, more imposing letters). `overlay_enabled` (true) also draws an on-top duplicate with the ADS reticle's colour-invert so the title pops crisply over the HUD while the sky copy gets cut by the skyline; tune it with `overlay_size_scale`. While authoring, flip **`test_show_immediately`** to **on** to reveal and size the title instantly without waiting out the ~2:48 cue â€” then turn it **off** for the real timed drop.

### A worked example: a back-alley radio

You want a grimy radio on a crate in an alley that cycles a folder of shipped lo-fi tracks, and the player's gang reacts to it.

1. Drop your tracks into a folder, e.g. `res://assets/audio/music/alley/` (or reuse the default `res://assets/audio/music`).
2. Under your alley scene, select the radio prop's mesh. Add a child `Radio` node.
3. Set **`radio_name`** = `"Alley Radio"`, **`highlight_target`** = the radio mesh, and either size its `CollisionShape3D` or tick **`auto_fit_collider`**.
4. Point **`music_folder`** at your folder (tick **`shuffle`** if you want a random order); optionally assign **`fallback_audio`** = a single track for the empty-folder case, and **`click_on`** = a switch clunk (`click_off` can be left blank to reuse it).
5. Leave `audio_player` and `click_player` unset (auto-created on `music` and `sfx`).
6. To make the gang react, set **`audible_radius`** = `8` and make sure `GameSettings.npc_ai.music_reactions` is on.

Now: aim at the crate, press Interact. The folder plays out of the crate, advancing track-to-track and looping. A firefight ducks it out; the fight ending breathes it back in after the `settle_cooldown`. Nearby gang NPCs turn their heads and comment based on the **current track's** `MusicQuality` tier. (And if the player set their own Music Folder in Options, this radio plays *their* tracks instead.)

### Gotchas

- **Bus routing is load-bearing.** The score and the radio track go on `music`; footsteps, landings, screams and the radio click go on `sfx`. Put music on `sfx` and the dialogue/combat ducks won't touch it; put the click on `music` and the combat duck will silence it mid-press.
- **`MusicDirector` must be a child of the audio player**, and that player's authored Volume dB must sit above `silent_db` or the fade is a no-op (it warns and self-corrects by dropping the floor 20 dB, but raise the volume).
- **A radio with neither a folder of tracks nor a `fallback_audio` is silent** â€” it surfaces a configuration warning in the editor. Point `music_folder` at audio files, or assign a royalty-free `fallback_audio`.
- **A `res://` `music_folder` scan sees the source files when you run from the editor** (the normal workflow). The player's own folder (an OS path / `user://`) is always real files, decoded from bytes at runtime.
- **NPCs are silent to radios unless `GameSettings.npc_ai.music_reactions` is enabled** â€” the radio still plays, NPCs just don't react.
- **Only drop one `SkyTitle`.** Remember to turn `test_show_immediately` back **off** before shipping, or the title appears the instant you spawn instead of on the beat.
- **Don't hand-add `LocomotionFx` to NPCs** unless you mean to override the auto-built one â€” NPCs build their own; a second one would double up footsteps.

Key files: `rpg/scripts/components/music_director.gd`, `rpg/scripts/components/radio.gd`, `rpg/scripts/components/radio_playback_state.gd`, `rpg/scripts/components/music_playlist.gd`, `rpg/scripts/components/music_quality.gd`, `rpg/scripts/components/locomotion_fx.gd`, `rpg/scripts/components/fall_scream.gd`, `rpg/scripts/components/sky_title.gd`.

---

## Quick reference

A map of WHERE each kind of content lives. All paths are `res://` (the project root is `rpg/`). For each, you author a `.tres` in the inspector (right-click the folder â†’ **New Resource** â†’ pick the listed type) or drop the named component node into your scene.

### Where each content type lives

| Content type | Folder | Resource / `class_name` | Backing script | Notes |
|---|---|---|---|---|
| **Factions** | `res://resources/factions/` | `Faction` | `res://scripts/faction/faction.gd` | One `.tres` per faction. Resolved by `Factions` (`res://scripts/faction/factions.gd`) on the **filename** â€” see gotchas. |
| **Dialogue** | `res://resources/dialogue/` | `DialogueResource` (with sub-resources `DialogueLine`, `DialogueChoice`) | `res://scripts/dialogue/dialogue_resource.gd`, `dialogue_line.gd`, `dialogue_choice.gd` | Voice lines pair with a `VoiceData` `.tres` (e.g. `old_man_voice.tres`, `res://scripts/dialogue/...`). Attach to a `DialogueNPC` / `Talkable` node in-scene. |
| **Items** | `res://resources/items/` | `Item` | `res://scripts/items/item.gd` | Ammo, consumables, weapon-items. A weapon-item (`pistol_item.tres`) holds a sub-`ext_resource` pointing at the matching `WeaponData`. Registered at runtime by the `ItemDb` autoload (`res://scripts/items/item_db.gd`). |
| **Weapons** | `res://resources/weapons/` | `WeaponData` | `res://scripts/combat/weapon_data.gd` | The stats/feel/audio of a gun. Threw-/throwable weapons use `ThrowableData` (`res://scripts/...`). |
| **NPC archetypes** | `res://resources/characters/` | `NpcData` | `res://scripts/npc/npc_data.gd` | e.g. `DefaultCharacterRes.tres`. References a `Faction`, a `CharacterStats` (`res://scripts/.../character_stats.gd`), a `WeaponData`, and starting `Item`s. Drives an `NPC` / `Enemy` node. |
| **Character stats** | `res://resources/characters/` | `CharacterStats` | `res://scripts/...` (`class_name CharacterStats`) | Shared stat block referenced by `NpcData.stats`. |
| **Global tuning** | `res://resources/tuning/` | One `*Settings` resource per group (`EconomySettings`, `NpcAiSettings`, `CameraSettings`, `BunnyhopSettings`, `AudioSettings`, `DistractionSettings`, â€¦) | co-located `*.gd` beside each `.tres` (e.g. `EconomySettings.gd`) | Registered on the **`GameSettings`** autoload (`res://managers/GameSettings.gd`). Code reads `GameSettings.<group>.<field>` (e.g. `GameSettings.economy.â€¦`, `GameSettings.npc_ai.â€¦`). |
| **Sky / shaders** | `res://resources/shaders/` | `.gdshader` files (`horizon_sky.gdshader`, `starry_sky.gdshader`, `film_grain.gdshader`, `outline.gdshader`, `ps1.gdshader`, `post_process.gdshader`, â€¦) | n/a (shader code) | The moody sky is applied non-destructively by the **`StarSky`** autoload (`res://scripts/effects/star_sky.gd`), which preloads `horizon_sky.gdshader`. |
| **In-world title drop** | scene node | `SkyTitle` | `res://scripts/components/sky_title.gd` | Drop into a level; armed at game-start by the player. The game name is revealed in-world, not on the menu. |
| **Custom NPC body/head** | scene node | `BodyModelSwap` (`@tool`) | `res://scripts/components/body_model_swap.gd` | Drop under the NPC root; set `body_model` (+ optional `head_model`) `.glb` for a live editor preview. |
| **GOAP brain** | project root | `GoapProfile` (`goapprofile.tres`) | `res://scripts/npc/goap/goap_profile.gd` | Holds `GoapActionCost` / `GoapGoalPriority` lists. Optional per-archetype tuning over the planner (null = defaults). |
| **Materials / UI skin** | `res://resources/materials/`, `res://resources/ui/` | standard `Material`s; `MenuSkin` (`menu_skin.tres`) | `res://scripts/...` (`class_name MenuSkin`) | Blood, bullet, shell, outline mats; menu styling. |
| **Interactables** | `res://resources/interactables/` | data `.tres` (e.g. `wooden_crate.tres`, `gore_gib_data.tres`) | per-component scripts | Pair with drop-in components like `CanDestroy`, `CanPickUp`, `SpawnOnDestroy`, `LookAtInteractable`. |

### Top gotchas

- **Reload the editor after adding new `@export` fields or a new `class_name`.** A newly added export won't show in the inspector â€” and a brand-new `class_name` the editor hasn't scanned yet can cascade into *"Could not find type X"* errors â€” until the editor reimports. Right after edits the editor may briefly yield empty PackedScenes or *"File not found"*; retry after a few seconds, it clears.
- **`.gd.uid` sidecars are tracked.** Commit each new script's `.gd.uid` alongside the `.gd`. If it's missing, `godot --headless --import` regenerates it. Do not orphan them.
- **Keep exactly one `BodyModelSwap` (one `body_model`) per NPC.** It hides the default `Man.glb` body/head and the runtime head-look + sniper-glint retarget to the swapped head. If you set `head_model`, **clear the NPC's own `head_scene`** â€” the component owns the head then.
- **A faction file's id must equal its filename.** `Factions` resolves a faction by loading `res://resources/factions/<id>.tres`, and `Reputation` keys on the file's **internal `id`**. If the `.tres`'s internal `id` doesn't match its filename you get a loud `push_warning` and two factions can silently merge into one rep pool. So `raiders.tres` must have `id = &"raiders"`.
- **Player-facing tunables must be wired into the Options menu *and* `Settings`.** A new tunable (volume, sensitivity, FOV, accessibility, screen-shake, ...) isn't done when the gameplay code reads it -- add a typed `var` + a `set_*` setter to the **`Settings`** autoload (`res://managers/Settings.gd`) and ONE `SettingSpec` row to `res://resources/settings/SettingsCatalog.tres` (the Options menu is data-driven -- no `options_menu.gd` edits). New keybinds additionally go in `InputManager.gd` + `project.godot [input]` + ONE `ActionSpec` row in `resources/input/ActionCatalog.tres` (NOT a `Keybind` `SettingSpec`).
