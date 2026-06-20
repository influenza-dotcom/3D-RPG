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
3. **Give it a faction (its attitude).** Select the NPC and find the **Hostility** group in the Inspector. Set the **`faction_id`** dropdown to `townsfolk` -- now it resolves to the Townsfolk faction (`FRIENDLY` toward the player; it won't attack unless provoked). Pick `raiders` instead and it's `HOSTILE` on sight. (Leave `faction_id` empty and the standalone **`disposition`** field takes over -- `HOSTILE` / `NEUTRAL` / `FRIENDLY`.) While you're here, type a **`display_name`** under the Identity & Outline group -- it shows as the speaker label in dialogue. For a civilian, leave **`weapon_data`** (under Weapon) empty: no faction is needed to talk, only to fight.
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
3. Story flags (world-state)
4. Triggers, encounters & cutscenes
5. Placing and configuring NPCs
6. Customising an NPC look (body/head/limbs)
7. Factions, disposition and reputation
8. Authoring dialogue
9. Items, loot, money and pickups
10. Weapons and ammo
11. The drop-in component catalogue
12. Global tuning (GameSettings) and the settings menu
13. NPC services and progression (shops, healing, companions)
14. Quests and the Journal
15. Atmosphere: radio, music and movement FX
16. Map and minimap
17. Stealth and detection
18. Tuning NPC behaviour (GOAP profiles)
19. NPC barks (combat & reaction lines)
20. The player: HP, stats, and starting money
21. Limb and locational damage
22. Saving, checkpoints and what persists
23. Destructible & throwable props (ThrowableData)
24. Reskinning the menus (MenuSkin)
25. Troubleshooting (symptom â†’ fix)
26. Glossary

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
- **Doors, trigger volumes and spawners now ship as drop-in components.** Drop `res://scenes/components/door.tscn` (a `Door` that swings open on Interact, lockable by item or flag), `res://scenes/components/trigger_volume.tscn` (a `TriggerVolume` that fires configurable actions -- set a flag, start dialogue, play audio, call a method, spawn a wave -- when a body enters/exits its zone), and an `EncounterSpawner` node (spawns NPCs from `SpawnDefinition`s, typically fired by a trigger). All three are configured entirely in the inspector -- no code. See **Triggers, encounters & cutscenes** below for the full treatment.
- **A data-driven level seam exists (`GameRoot` + `LevelData`), but isn't wired into the shipped scene yet.** Rather than duplicating `game.tscn` per level (the manual path above), a `LevelData` `.tres` can bundle a level's `scene` + `display_name` + `music` + `ambience`, and a `GameRoot` node swaps levels from it (the `WeaponData` / `NpcData` pattern). The shipped `game.tscn` still hardcodes its `Level` child, so this is an **opt-in** upgrade -- attach a `GameRoot` to adopt it.
- A panorama that isn't a true 360Â° photo will look stretched when wrapped â€” raise the shader's `pano_tiles` (and nudge `band_top` / `band_bottom`) to fix it.

Relevant files: `C:\Users\dalla\3D RPG\rpg\scenes\TestLevel.tscn`, `C:\Users\dalla\3D RPG\rpg\scenes\game.tscn`, `C:\Users\dalla\3D RPG\rpg\scripts\effects\star_sky.gd`, `C:\Users\dalla\3D RPG\rpg\resources\shaders\horizon_sky.gdshader`, `C:\Users\dalla\3D RPG\rpg\resources\tuning\EffectsSettings.gd` / `.tres`.

---

## Story flags (world-state)

Story flags are the **spine of your scripting**: a single runtime world-state store that `TriggerVolume`, Quests, Doors and Cutscenes all read from and write to. A flag is just a named fact about your run — *"the player met the fixer," "the warehouse alarm is live," "the bridge is lowered"* — that any other system can check later. There is **no inspector field, no `.tres`, and no node to drop** for the flags themselves: they live entirely on the `GameState` autoload (`res://managers/GameState.gd`, a plain `Node` with no `class_name`), and you set and read them *declaratively* from components — you rarely touch the API directly.

### What a flag is

A flag is a `String` key mapped to a `Variant` value (a `bool`, `int`, or `String`). The whole store is one dictionary on `GameState`, persisted in the autosave's `[flags]` section, so flags **survive quitting and relaunching** exactly like money and stats. **New Game wipes every flag** (`reset_for_new_game()` clears them) — a fresh run forgets everything that happened.

Keys are `String`-coerced internally, so it does not matter whether you author a flag name as a `StringName` (`&"met_the_fixer"`) or a plain `String` — the set, get, and has calls all normalise to the same key, dodging the GDScript `String`-vs-`StringName` dictionary trap.

### The API (you rarely call it directly)

When you *do* read a flag from a small script, these are the three calls on the `GameState` autoload:

- **`GameState.set_flag(flag: StringName, value := true)`** — write a flag. `value` defaults to `true`, the common "mark that this happened" case. Pass a number or string for richer state (e.g. `set_flag(&"alarm_stage", 2)`).
- **`GameState.get_flag(flag: StringName, fallback := false)`** — the flag's value, or `fallback` when it was never set. An unset bool flag therefore reads as `false` with no special-casing.
- **`GameState.has_flag(flag: StringName)`** — was this flag ever set (to *any* value, including `false`/`0`)? Use this for pure "did it happen at all" gates; use `get_flag` when the *value* matters.

### How designers actually set and read flags

You almost never write `set_flag` in code. Instead:

**To SET a flag** — declaratively, from either of two places:
- A **`TriggerVolume`** (see *Triggers, encounters & cutscenes*): fill its **`set_flag`** field with the flag name and it calls `GameState.set_flag` when fired. **`set_flag_value`** (default `true`) is the value written. Pair with **`trigger_once`** for a one-shot gate.
- A **Cutscene `SET_FLAG` action** — the same write, sequenced inside a scripted beat.

**To READ a flag** — two ways:
- A **Quest `FLAG` objective** (see *Quests and the Journal*): author a `QuestObjective` with `type = FLAG` and `target_id =` the flag name.
- An `if GameState.has_flag(...)` / `get_flag(...)` check in a small gating script (a gated dialogue choice, a merchant who only stocks something post-event, a door that won't open yet).

### The key behaviour — flags auto-advance quests

This is the payoff and the reason flags are the spine: **setting a flag to a truthy value auto-advances any active quest's `FLAG` objective whose `target_id` matches.** `set_flag` calls `_advance_flag_objectives` internally, which bumps every matching objective by one. That makes flags the **universal "something happened → a quest step ticks" hook** — you never wire the trigger to the quest by hand. Drop a `TriggerVolume` that sets `&"reached_the_roof"`, author a quest objective `type = FLAG, target_id = &"reached_the_roof"`, and walking into the volume advances the quest. (Setting a flag to a *falsy* value — `false` or `0` — does **not** advance anything.)

### Worked example: a one-time story gate

> Goal: the first time the player reaches the alley mouth, mark that they "met the fixer." Use it later to unlock a dialogue branch *and* tick a quest step — and have it stick across saves.

1. Drop a **`TriggerVolume`** at the alley mouth (size its `CollisionShape3D` to span the entrance).
2. Set **`set_flag`** = `&"met_the_fixer"`. Leave **`set_flag_value`** = `true`.
3. Set **`trigger_once`** = `true` so it fires once and never re-arms.
4. Read it back wherever you need it, in a small gating script: `if GameState.has_flag(&"met_the_fixer"):` then offer the "Ask about the job" dialogue option.
5. *Or* author a Quest objective `type = FLAG, target_id = &"met_the_fixer"` — step 2's `set_flag` advances it automatically, no extra wiring.

Walk through the alley once: the flag is set, the gated branch opens, the quest step ticks. Quit and relaunch — the flag is still set (it rode the autosave's `[flags]` section). Start a New Game — it's gone, and the gate is closed again.

### Gotchas

- **`has_flag` vs `get_flag`.** `has_flag` is true the moment a flag exists, even if its value is `false`/`0`. If you `set_flag(&"x", false)`, then `has_flag(&"x")` is `true` but `get_flag(&"x")` is `false`. For "did it happen," prefer `has_flag`; for "what's the state," read `get_flag`.
- **Only TRUTHY sets advance quests.** A `FLAG` objective fires on `set_flag(name)` / `set_flag(name, true)` (or any non-zero/non-empty value). Setting a flag to `false` or `0` writes the value but ticks nothing.
- **There's nothing to drop for the flag itself.** Flags aren't a component or a resource — they're pure runtime world-state on `GameState`. You author the *producers* (`TriggerVolume`, Cutscene actions) and *consumers* (quest objectives, gating scripts); the flag is just the shared name connecting them. Keep names stable — a typo'd `target_id` silently never advances.
- **New Game clears all flags.** Don't rely on a flag persisting across a fresh run; it's run-scoped profile state, not project content.

Relevant files: `res://managers/GameState.gd` (the flags API + the FLAG→quest hook), `res://scripts/components/trigger_volume.gd` (`set_flag` / `set_flag_value` / `trigger_once`), `res://scripts/quests/quest_objective.gd` (`type = FLAG`, `target_id`).

---

## Triggers, encounters & cutscenes

This is the "make things happen" layer — the glue that turns a static level into an authored experience. Three drop-in pieces compose every scripted beat in CYBER SUNDAY: a **`TriggerVolume`** detects when the player walks somewhere, an **`EncounterSpawner`** drops enemies on cue, and a **`Cutscene`** scripts a cinematic. None of it is code; you drop the nodes in, fill `@export` fields, and point them at each other in the inspector. The sanctioned pattern throughout is *a trigger fires a target* — the volume's generic `action`/`target` knobs call a named method on a spawner, a wave manager, a cutscene player, a door, anything.

### TriggerVolume — when a body enters a zone, do things

The **`TriggerVolume`** (`class_name TriggerVolume`, `@tool` `extends Area3D`, `res://scripts/components/trigger_volume.gd`) is the keystone "when X, do Y" primitive. A body in `trigger_group` enters the zone and it fires a configurable set of **independent** actions. Drop the prefab **`res://scenes/components/trigger_volume.tscn`** (a cylinder, `CylinderShape3D` radius `2.0` / height `3.0`) into your level and **resize its `CollisionShape3D`** to cover the area you want to watch.

**Gating (who fires it):**
- **`trigger_group`** (StringName) — only bodies in this group fire it (`&"player"`). On `_ready()` the volume forces its `collision_mask` to **all layers** and filters by group instead — so it catches the player whatever physics layer it sits on, and **physics layer numbers never matter**. Just set the group.
- **`trigger_once`** (bool) — fire ONCE then stop monitoring, for one-shot story beats and ambushes (`false` = fires every entry).
- **`fire_on_exit`** (bool) — also fire when a body LEAVES the zone, not just on enter (`false` = enter only).

**Actions (each independent, each INERT when left unset):** a bare trigger with no actions filled in does nothing but emit its **`fired(activator)`** signal — which you can wire to anything in the editor. Fill in any combination of:
- **`set_flag`** (StringName) + **`set_flag_value`** (bool, `true`) — write a global story flag via `GameState.set_flag` (empty = none). The common "mark that this happened" case.
- **`start_dialogue`** (DialogueResource) — start a conversation via `DialogueManager.start`, with the activator as the speaker.
- **`activate_node_path`** (NodePath) — the **"arm a sleeping node"** pattern: re-enables `process` + `physics_process` + visibility on a node you left switched OFF in the editor (e.g. a dormant `EncounterSpawner` or another trigger).
- **`play_audio`** (AudioStream) + **`audio_bus`** (StringName, `&"sfx"`) — play a positional sound at the volume, routed to the named bus so its volume slider applies.
- **`action`** (StringName) + **`target`** (NodePath) — **the generic escape hatch.** Calls the method named in `action` on the `target` node (e.g. `action = &"trigger_spawn"`, `target =` an EncounterSpawner). This is how a trigger drives the spawner/wave/cutscene systems below. Ignored when `action` is blank.

`fire(activator)` is public, so a trigger can be fired manually by another trigger, a cutscene's CALL_METHOD step, or a test. The `@tool` script config-warns in the editor if there's no `CollisionShape3D` child (the volume can't detect anything without one).

### Encounter spawning — EncounterSpawner / SpawnDefinition / WaveManager

Instead of hand-placing every enemy alive from frame one, you author *what spawns* as data and fire it on cue.

#### EncounterSpawner

The **`EncounterSpawner`** (`class_name EncounterSpawner`, `@tool` `extends Node3D`, `res://scripts/components/encounter_spawner.gd`) holds your spawn list:
- **`spawn_definitions`** (`Array[SpawnDefinition]`) — one row per enemy group to spawn (see below).

It adds spawned NPCs as **SIBLINGS** — into `get_parent()`, the level around it — so **parent the spawner under your level's `Characters` node**, not under a stray root, or the enemies land in the wrong place in the tree. `trigger_spawn()` fires *every* definition (the common case); `trigger_spawn_wave(i)` fires just one by index; each spawn emits **`spawned(npc)`**. There's no shipped prefab or `.tres` — add the node and author its `SpawnDefinition`s fresh.

#### SpawnDefinition

A **`SpawnDefinition`** (`class_name SpawnDefinition`, `@tool` `extends Resource`, `res://scripts/combat/spawn_definition.gd`) is one entry: which enemy, how many, and the per-spawn overrides.
- **`npc_scene`** (PackedScene) — the enemy scene to instance (e.g. `res://scenes/enemies/NPC.tscn`).
- **`count`** (int, range `1..99`, `1`) — how many of it to spawn.
- **`spawn_radius`** (float, `2.0`) — scatter radius (m) the spawns land in, around the spawner.
- **`profile`** (NpcData) — OPTIONAL archetype stamped on each spawn. The **primary** override; a profile's faction WINS.
- **`faction_override`** (Faction) — OPTIONAL faction, applied only when no `profile` dictates one.
- **`weapon_override`** (WeaponData) — OPTIONAL weapon, applied only when no `profile` dictates one.
- **`auto_aggro`** (bool, `true`) — make each spawn immediately hostile to + targeting the `&"player"` group on arrival (skips the perceive-first delay).
- **`spawn_delay`** (float, `0.0`) — seconds between each NPC *within this one definition* (`0` = all at once).

**Override precedence:** `profile` > `faction_override` / `weapon_override`. They're stamped onto the NPC (via `npc.set(...)`) BEFORE `add_child`, so the NPC's `_ready()` picks them up.

#### WaveManager

For "clear the room over several waves," add a **`WaveManager`** (`class_name WaveManager`, `extends Node`, `res://scripts/components/wave_manager.gd`). It sequences a spawner's definitions as timed waves: fire definition 0, wait, fire definition 1, ….
- **`spawner_path`** (NodePath) — the `EncounterSpawner` to sequence (config-warns if empty).
- **`wave_interval`** (float, `5.0`) — seconds between waves.
- **`auto_start`** (bool, `false`) — begin on `_ready`; otherwise a trigger/cutscene calls `start()`.

`start()` fires **each `SpawnDefinition` as one timed wave**, `wave_interval` apart, emitting **`wave_started(index)`** per wave then **`all_waves_done`** at the end.

> **Two distinct timers.** `spawn_delay` staggers NPCs *inside a single definition*; `wave_interval` spaces *whole definitions apart* when a `WaveManager` drives them. A definition with `count = 5, spawn_delay = 0.3` drips five enemies in over a second-and-a-half; five definitions under a `WaveManager` with `wave_interval = 5.0` are five separate waves twenty-five seconds apart.

**Firing a spawner.** The sanctioned way is a `TriggerVolume` with `action = &"trigger_spawn"`, `target =` the spawner. For a `WaveManager`, point a trigger at it with `action = &"start"` instead.

### Cutscenes — Cutscene / CutsceneAction / CutscenePlayer

A cutscene is an ordered list of steps a player runs while control is locked — wait, set a flag, call a method, play a line of dialogue, ease a cinematic camera, fade the screen.

#### Cutscene

A **`Cutscene`** (`class_name Cutscene`, `@tool` `extends Resource`, `res://scripts/combat/cutscene.gd`) is the script itself — author it as a `.tres`.
- **`actions`** (`Array[CutsceneAction]`) — the ordered steps. Player control + the gameplay camera are always restored when the last action finishes (or on Escape).

#### CutsceneAction

A **`CutsceneAction`** (`class_name CutsceneAction`, `@tool` `extends Resource`, `res://scripts/combat/cutscene_action.gd`) is one step. Its **`type`** selects which grouped fields apply:
- **`type`** (enum `Type { WAIT, SET_FLAG, CALL_METHOD, DIALOGUE, CAMERA_MOVE, FADE }`, default `WAIT`).
- **`duration`** (float, `1.0`) — seconds this step takes; used by **WAIT / CAMERA_MOVE / FADE**.
- *Set Flag group:* **`flag_name`** (StringName) + **`flag_value`** (bool, `true`) → `GameState.set_flag`.
- *Call Method group:* **`event_node_path`** (NodePath) + **`event_method`** (StringName) — call a method on a node. **This is the cross-system glue** — call `trigger_spawn` on a spawner, `open` on a Door, `fire` on another trigger.
- *Dialogue group:* **`dialogue`** (DialogueResource) — play a conversation; the cutscene WAITS for it to finish.
- *Camera Move group:* **`camera_position`** (Vector3) + **`camera_rotation`** (Vector3, in **DEGREES** — converted to radians at runtime) — the cinematic camera eases there over `duration`.
- *Fade group:* **`fade_color`** (Color, `Color(0,0,0,1)`) — the screen eases TO this colour over `duration`. **Alpha drives it:** `a = 1` fades to opaque (out), `a = 0` fades back in.

#### CutscenePlayer

A **`CutscenePlayer`** (`class_name CutscenePlayer`, `extends Node`, `res://scripts/components/cutscene_player.gd`) runs a cutscene at runtime.
- **`cutscene`** (Cutscene) — the cutscene `play()` runs.

Fire it with the **no-arg `play()`** (so a `TriggerVolume` with `action = &"play"`, `target =` this player drives it) or `play_cutscene(c)` for an ad-hoc one. While ANY cutscene plays, **player control is LOCKED** — playback sets the static `CutscenePlayer.is_active()` flag, which `InputManager.gameplay_suppressed()` reads (the single sanctioned place to register a control-suppressing overlay). **Escape (`ui_cancel`) skips** the rest. It emits **`cutscene_started`** / **`cutscene_finished`**. CAMERA_MOVE lazily builds its own `Camera3D` (and hands `current` back to the gameplay camera at the end); FADE lazily builds a full-screen `ColorRect` on its own `CanvasLayer` above the HUD. No shipped prefab or `.tres` — add the node and author a `Cutscene` fresh.

### Worked example — ambush on entry

> Goal: the player walks into a room, three raiders spawn around them and attack, and a story flag records it — once.

1. Under your level's **`Characters`** node, add an **`EncounterSpawner`**.
2. Expand its `spawn_definitions`, set size **1**, and open element `[0]` (a `SpawnDefinition`):
   - `npc_scene` = your enemy scene (e.g. `res://scenes/enemies/NPC.tscn`)
   - `count` = `3`
   - `spawn_radius` = `4.0`
   - `profile` = a raider `NpcData` (its faction wins — no need to set `faction_override`)
   - `auto_aggro` = `true`
3. Drop **`trigger_volume.tscn`** into the room and size its `CollisionShape3D` to cover the doorway/floor. Set:
   - `trigger_group` = `&"player"`
   - `trigger_once` = `true`
   - `action` = `&"trigger_spawn"`, `target` = the EncounterSpawner
   - `set_flag` = `&"ambush_sprung"`
4. Run, walk in once → 3 raiders spawn within 4 m and provoke, the `ambush_sprung` flag flips, and the volume stops monitoring (it never fires again).

For an **intro cutscene**, author a `Cutscene` `.tres` whose `actions` are, in order: a **FADE** (`fade_color` alpha `0` to fade up from black), a **CAMERA_MOVE** to your establishing shot, a **DIALOGUE** line, a **CALL_METHOD** (`event_method = &"trigger_spawn"` on the spawner) to drop the enemies on the beat, a **FADE** back, and a **SET_FLAG** `&"intro_seen"`. Add a `CutscenePlayer`, set its `cutscene`, and point a `trigger_once` `TriggerVolume` at it with `action = &"play"`.

### Gotchas

- **Parent the EncounterSpawner under `Characters`.** It adds spawns as siblings (into `get_parent()`), so a spawner sitting on a stray root puts your enemies in the wrong branch of the tree.
- **Physics layers don't gate a TriggerVolume — the group does.** The volume forces `collision_mask` to all layers and filters by `trigger_group`. If the trigger never fires, check the body's *group membership*, not its collision layer.
- **`trigger_once` is one-and-done.** Once spent it stops monitoring entirely — it won't fire on exit again either. Use a non-once volume for repeatable beats.
- **Profile beats the overrides.** `faction_override` / `weapon_override` only apply when no `profile` dictates one. If you assigned a `profile`, its faction/weapon win — clearing the overrides won't change anything.
- **Two spawn timers, two scopes.** `spawn_delay` is *within* a definition; `wave_interval` is *between* definitions under a `WaveManager`. Don't reach for one expecting the other's behaviour.
- **Cutscenes lock control globally.** While one plays, `InputManager.gameplay_suppressed()` is true via the static `is_active()` flag — that's intentional. Escape is the only way out mid-scene. Don't add a second control-suppression path; register overlays through that one flag.
- **CAMERA_MOVE rotation is in degrees.** Author `camera_rotation` as degrees in the inspector; it's converted to radians at runtime. FADE is alpha-driven — `a = 1` goes to opaque, `a = 0` clears.
- **Nothing here ships a prefab except the TriggerVolume.** `EncounterSpawner`, `WaveManager`, `CutscenePlayer` and all their resources are authored fresh; only `trigger_volume.tscn` exists as a drop-in.

Relevant files: `res://scripts/components/trigger_volume.gd`, `encounter_spawner.gd`, `wave_manager.gd`, `cutscene_player.gd`; `res://scripts/combat/spawn_definition.gd`, `cutscene.gd`, `cutscene_action.gd`; prefab `res://scenes/components/trigger_volume.tscn`.

---

## Placing and configuring NPCs

Every non-player actor in CYBER SUNDAY -- from a townsperson who just wanders to a sniper who locks on and fires -- is the **same** `NPC` node (`rpg/scripts/npc/npc.gd`, `extends Character`). There are no enemy/civilian subclasses; behaviour is driven entirely by the inspector fields you set. This section walks you through dropping one in and configuring it.

### Step 1 â€” Instance the NPC scene

The ready-to-use prefab is `res://scenes/enemies/NPC.tscn`. It inherits from the base `enemy.tscn`, which already wires up the body mesh (`Man.glb`), the swappable head, the collision capsule, the `BodyModelSwap` re-skin component, and the `damaged`/`died` signal connections. (Ragdoll is set on `NPC.tscn` itself via `ragdoll_scene`, not on the base.) You almost never start from `enemy.tscn` directly -- `NPC.tscn` is the configured starting point.

1. In the scene you're building (e.g. `Level.tscn`), open the **Scene** menu or drag from the FileSystem dock: instance `res://scenes/enemies/NPC.tscn` as a child of your level.
2. Move/rotate it into place with the gizmo. The NPC remembers its spawn position and facing at `_ready` -- wandering strays from there, and after losing you it searches around that spot.
3. Select the instance and configure it in the **Inspector**. Everything below is an `@export` on the root node; you never open a script.

> If you need to tweak the body/head meshes or per-limb tints for this one instance, you don't have to enable "Editable Children" -- the root exposes a **Body & Head â†’ Custom Models â†’ `look`** slot. Assign an `NpcLook` resource there (its fields are `body_model`, `body_texture`, `body_color`, `head_model`, `arm_color`, `leg_color`, etc.) and that NPC re-skins live in the editor. See "Customising an NPC look" below.

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

> **The stock `NPC.tscn` ships these COMBAT-tuned, not at the class defaults.** The prefab overrides `sight_range` -> **500**, `time_to_detect` -> **0.1**, `forget_time` -> **1.0**, `turn_speed` -> **20** (and `fire_range` -> 0.5): an instantly-alert, far-seeing fighter. The gentler class defaults (`sight_range` 25, `time_to_detect` 1.0, `forget_time` 4.0, `turn_speed` 8; `fov_degrees` 110 is the one the prefab leaves alone) only describe a bare actor. So a freshly-placed `NPC.tscn` reacts *much* faster than the field descriptions alone suggest -- dial these down for a sleepier guard.

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
- **The `faction_id` dropdown self-populates from `res://resources/factions/`.** It's generated at edit time -- both `npc.gd` and `npc_data.gd` set the hint via `Factions.ids_csv()` (a `DirAccess` folder scan, sorted alphabetically) in `_validate_property` -- so the moment you save a new faction `.tres` into that folder it appears in the dropdown on every NPC and `NpcData`, with no list to maintain and no code edit. (Reload the project if a just-added faction doesn't show yet.)
- **`turn_speed` lives under Perception, not Movement** -- worth knowing when you're hunting for it.
- **`goap_profile` is the optional per-archetype AI tuning.** A `GoapProfile` `.tres` that retunes the planner's goal priorities / action costs for an archetype; the GOAP planner is the shipping NPC brain, so leave `goap_profile` null to use its defaults.

### Patrol routes

Want a guard who walks a beat instead of standing around or random-wandering? It's two drop-in nodes and zero code — one node defines the **route**, the other tells one NPC to **walk it**.

**The route — `PatrolPath`** (`res://scripts/components/patrol_path.gd`, `class_name PatrolPath`, `@tool` `Node3D`). Place it anywhere in the level. Its **child** `Node3D` / `Marker3D` nodes ARE the waypoints, walked in child order (it's not an `@export` list — add/reorder Marker3D children to edit the route, and it config-warns if there are none). Knobs:

- **`loop`** — `true` cycles the route (…→last→first→…); `false` ping-pongs (…→last→…→first→…). Default `true`.
- **`wait_time`** — seconds the NPC pauses at each waypoint before moving on (`1.0`).

It's pure waypoint data — one `PatrolPath` can be shared by any number of NPCs.

**The behaviour — `PatrolBehavior`** (`res://scripts/components/patrol_behavior.gd`, `class_name PatrolBehavior`, `@tool` plain `Node`). It **must be a child of the NPC** it drives. Knobs:

- **`enabled`** — off = this NPC ignores the route and falls back to normal wander/hold idle (`true`).
- **`patrol_path`** — the `NodePath` to the `PatrolPath` this NPC walks; empty = inactive (config-warns).

**How it wires up (automatically).** You don't touch `npc.gd`. The NPC's `NpcLocomotion._idle` looks for a `PatrolBehavior` child on its host and, while the NPC is idle (no target, not in combat, not following a leader), hands movement to patrol instead of wander. A fight interrupts the patrol; the NPC resumes the beat afterward. Patrol drives the host through the **same navmesh pathing** as wander, so the route steers around walls — you place corner markers, you don't author the path between them. The `_idle` priority order is: **companion-follow > patrol > wander > return-to-post.** Each `PatrolBehavior` keeps its own waypoint index and ping-pong direction, which is why several NPCs can point at one shared `PatrolPath` and each walk it independently.

**Worked example — a guard pacing a courtyard**

1. Add a **`Node3D`** to the level and attach `patrol_path.gd` (now a `PatrolPath`).
2. Add **3 `Marker3D` children** under it, one at each corner of the beat. Set the `PatrolPath`'s `loop = true` and `wait_time = 2.0`.
3. Select your guard NPC, add a **child `Node`**, and attach `patrol_behavior.gd`. Set its `patrol_path` to the `PatrolPath` from step 1.
4. Play. The guard walks the 3 markers in order, pausing 2 s at each, and resumes the loop if a fight pulls it away.
5. Variations: set the `PatrolPath`'s `loop = false` to make it ping-pong the line instead of cycling; point a **second** guard's `PatrolBehavior` at the *same* `PatrolPath` to share the route (each keeps its own place on it).

**Gotchas**
- **`PatrolBehavior` only runs while the NPC is idle.** It's not a leash — combat, chasing a target, and following a leader all take over, and patrol resumes when the NPC goes idle again. (Companion-follow also outranks it, so a follower won't patrol.)
- **`PatrolPath` waypoints are child nodes, not an array.** To change the route, add/remove/reorder the Marker3D children — there's no waypoint `@export` to fill. Zero children → the route is empty and it config-warns.
- **Markers must be reachable on the navmesh.** Patrol uses the NPC's own pathing; if the navmesh won't route to a waypoint the NPC treats it as "arrived," pauses, and advances — so keep markers on walkable ground and re-bake after moving geometry.

Files referenced: `C:\Users\dalla\3D RPG\rpg\scripts\npc\npc.gd`, `C:\Users\dalla\3D RPG\rpg\scripts\npc\npc_data.gd`, `C:\Users\dalla\3D RPG\rpg\scenes\enemies\NPC.tscn`, `C:\Users\dalla\3D RPG\rpg\scenes\enemies\enemy.tscn`.

---

## Customising an NPC look (body/head/limbs)

Every enemy in Cyber Sunday starts from the same `enemy.tscn` rig â€” a single skinned `Man.glb` body whose head is a bone â€” but you almost never edit that rig directly. Instead, a drop-in `BodyModelSwap` child *replaces* the visible body, head, arms and legs with your own `.glb`/`.blend` models, and it does so **live in the editor** (it's a `@tool` script). Better still, you can override the look **per instance straight from the NPC root**, so re-skinning one guard in a level is a matter of clicking it and filling a few inspector fields â€” no "Editable Children", no duplicate scenes. Beyond the look, the same component also drives the NPC's runtime CHARACTER motion: legs that steer toward the direction it's actually moving (independent of the torso, which stays on its aim), an armed NPC that only raises its weapon once a foe is close, and a talking presentation (head-bob + a flapping mouth) plus speaker-only idle breathing. Those are runtime-only knobs on the same node (see "Runtime motion" and "Talking and breathing" below).

### The two places a look is defined

There are two layers, and it helps to know which one you're touching:

1. **The shared default look** lives on the `BodyModelSwap` node inside `res://scenes/enemies/enemy.tscn` (script: `rpg/scripts/components/body_model_swap.gd`). This is what *every* enemy wears unless overridden. In the shipped scene it's set to:
   - `body_model` = `res://scenes/torso.tscn`, `body_model_scale` = `0.205`, `body_model_rotation` = `(0, -90, 0)`, `body_texture` = `stupidbody_Material Base Color.png`
   - `head_model` = `res://assets/models/headblue.glb`, `head_scale` = `0.205`, `head_position` = `(0, 0.615, 0.04)`, `head_rotation` = `(0, 90, 0)`, `head_texture` = `headblue_Material Base Color.png`
   - `arm_model` = `arm.blend` (scale `0.35`, position `(-0.27, 0.155, -0.05)`, rotation `(90, 0, 0)`) and `leg_model` = `leg.blend` (scale `0.44`, position `(0.095, -0.265, -0.02)`, rotation `(0, -90, 0)`)
   - (The arm/leg *tints* in the shipped scene come from the `BodyModelSwap` child itself â€” its `arm_color` = a blue, `leg_color` = a maroon. The NPC root carries no arm/leg tint by default; assign an `NpcLook` to `look` with a non-white `arm_color`/`leg_color` to override them per instance.)

   Note the field names differ slightly between the two layers: on the `BodyModelSwap` child the head transform fields are `head_scale` / `head_position` / `head_rotation`, while in the `NpcLook` (below) the equivalents are `head_model_scale` / `head_model_position` / `head_model_rotation`.

2. **Per-instance overrides** are an **`NpcLook` resource** you assign to the NPC root's single **Body & Head â–¸ Custom Models â–¸ `look`** slot (`rpg/scripts/npc/npc.gd`; the resource class is `rpg/scripts/npc/npc_look.gd`). The NPC root no longer carries the appearance fields inline â€” it has just the one `look` field. Drop an `NpcLook` there (a reusable `.tres` you author in `resources/`, or an inline sub-resource) and the `@tool` `BodyModelSwap` child *reads that look* and prefers it over its own shared default â€” so an assigned look wins and previews instantly. Author a "raider look" / "townsperson look" once and reuse it across NPCs; clear the `look` to fall back to the shared default.

Assign an `NpcLook` to `look` and IT carries these override fields (their names mirror the shared-default fields on the `BodyModelSwap` child). Leave any at its default â€” null model / WHITE colour / `1.0` scale â€” to leave that part alone:

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

Note there is **no `arm_model` / `leg_model` (nor arm/leg scale, position, rotation, or texture) in the `NpcLook`** â€” a look can only *tint* the limbs (`arm_color` / `leg_color`). The arm and leg *models* and their placement live solely on the `BodyModelSwap` child.

A few rules the component bakes in, worth internalising:

- **Texture/colour resolve independently of the model.** You can re-skin the *default* body just by setting `body_texture`/`body_color` and leaving `body_model` empty â€” no mesh swap needed.
- **WHITE is the "leave it alone" sentinel** for every `*_color`. The override only kicks in when you pick a non-white colour; white restores the model's own baked material. Same idea for an empty texture.
- **A swapped model brings its own material.** If you set `body_model` but no `body_texture`/`body_color`, the new mesh shows the material it was authored with. (And if the host overrides the *model* but leaves its texture null / colour WHITE, the swapped model keeps its own material rather than inheriting the child's default skin.)
- **Arms and legs are tint-only from the root.** Their *models* and placement always come from the `BodyModelSwap` child (they're gait-animated â€” they swing as the NPC walks, and by default the LEGS also swivel to face the direction the NPC is actually moving, independent of the torso which stays trained on its aim â€” a run-and-gun strafe), but `arm_color`/`leg_color` on the root recolour them per instance.

### Runtime motion (on the BodyModelSwap child)

These knobs are all `@export`s on the **`BodyModelSwap` child** (not the NPC root), and they only play **in-game** â€” the editor shows the static rest pose.

- **`legs_follow_movement`** (bool, default **true**) â€” the legs/hips swivel to face the direction the NPC is actually MOVING, independently of the torso (which keeps facing its aim/look). So a strafing or backpedalling enemy points its hips along its path while its chest stays trained on you. Off = legs stay square with the torso (the old behaviour).
- **`leg_turn_rate`** (float, default `9.0`) â€” how snappily the legs swivel toward the movement direction; lower = a lazier, sliding turn.
- **`arm_raise_range`** (float, default `10.0`, metres) â€” an armed NPC only raises its weapon into the forward hold pose when the foe is within this distance; farther out the gun stays **drawn** but the arms hang / swing with the stride, so an enemy only "takes aim" up close instead of the instant it draws across the map. Purely cosmetic â€” it never changes when the NPC actually fires. `0` = always raised the moment the gun is out (the old behaviour); with no target the arms stay down.

### Talking and breathing

Also `@export`s on the **`BodyModelSwap` child**, runtime-only. The head-bob and mouth both need a **head node** â€” a swapped `head_model`, or a legacy `head_scene` (with neither, they're silent no-ops; see Gotchas).

- **`talk_head_bob`** (bool, default **true**) â€” the head bobs up/down while THIS NPC is delivering a dialogue line **or a bark** (it animates for the utterance's duration, then settles â€” not the whole time a line sits on screen). `talk_bob_height` (`0.03` m), `talk_bob_rate` (`9.0`, bob cadence), `talk_bob_ease` (`8.0`, how fast it eases in/out).
- **`show_mouth`** (bool, default **true**) â€” a billboarded black "Tomodachi"-style mouth that flaps between a thin line and a full circle while the NPC speaks a line or a bark, and hides between utterances. `mouth_size` (`0.06` m radius), `mouth_flap_rate` (`22.0`, chatter speed), and **`mouth_position`** (Vector3, default `(0, -0.03, 0.14)`, HEAD-LOCAL, +Z is the face front) â€” **tune this so it sits on the model's mouth**; if you don't see it, it may be buried inside the head, so push Z further forward.
- **Breathing** (the existing `breathe` / `breathe_amount` / `breathe_rate` chest idle) now applies, *during a conversation*, ONLY to the NPC you're talking to â€” every other NPC holds still, so the scene reads as frozen around your conversation partner.

### Worked example: a red-shirted variant of the default guard

Say you want one specific enemy in your level to wear a red torso and a pale head, but otherwise stay the default guy.

1. In your level scene, select the placed **Enemy** instance (the root `CharacterBody3D`). You do **not** need "Editable Children".
2. In the inspector open **Body & Head â–¸ Custom Models** and find the **`look`** field. Click its **`[empty]`** button and choose **New NpcLook** to make an inline look resource (or assign an `NpcLook` `.tres` you authored), then expand it to reach its fields.
3. Inside the look, leave `body_model` and `head_model` empty â€” you're keeping the default meshes. (There's no arm/leg model field; the limbs always come from the child.)
4. Set the look's `body_color` to a red. The torso re-tints in the viewport immediately (the `@tool` child rebuilds on the change).
5. Set its `head_color` to a pale skin tone. Done.

Want a genuinely different *body* instead of a tint? In the look, set `body_model` to your `.glb`/`.tscn`, then dial `body_model_scale` (start around `0.2` â€” the default body sits at `0.205`, and most imported models come in giant at scale `1.0`), nudge `body_model_position.y` so the feet land on the ground, and yaw `body_model_rotation` until it faces the NPC's forward. Everything previews as you type. The same node performs the swap at runtime, so **what you see in the editor is what ships** â€” and at runtime the head-look and sniper glint automatically retarget onto your swapped head (the component calls `register_swapped_head()` on the NPC), and the combat outline re-rims the swapped parts.

If you instead want to change the default for *all* enemies, open `res://scenes/enemies/enemy.tscn`, select the `BodyModelSwap` node, and edit its fields there.

### Gotchas

- **Keep a `body_model` â€” head-only swaps aren't supported on this rig.** `Man.glb` is **one** skinned mesh (`BaseHuman`) and its head is a *bone*, not a separate node, so the component can't hide "just the head." The moment any body *or* head model is swapped in, it hides the **entire** `Man.glb` mesh. Every shipped NPC swaps in a `body_model` (`torso.tscn`), so the body fills that hidden rig back in. If you set only `head_model` and leave `body_model` empty, you'll hide the whole default body with nothing to replace it â€” a head floating over no torso. Always pair a head swap with a body swap.
- **The animated swing/hold poses are runtime-only.** In the editor you see the *static rest pose* (so you can place limbs); the walk swing, the leg-follows-movement swivel, the proximity-gated weapon raise, the weapon-hold, the air-flail, the breathing chest idle, AND the talking head-bob + flapping mouth all only play in-game. Place limbs (and `mouth_position`) against the rest pose, then playtest to see the motion.
- **No mouth or head-bob? You need a head node.** `talk_head_bob` and `show_mouth` ride on the head â€” the component's own swapped `head_model`, or a legacy `head_scene`. With neither resolved they're silent no-ops. If the mouth never shows on a talking NPC, confirm a head is present and that `mouth_position` (head-local, +Z forward) actually sits on the face rather than buried inside the head mesh.
- **Preview looking stale?** After a `.glb` reimport or a script reload the live preview can lag. Tick `refresh_preview` on the `BodyModelSwap` node (it snaps back off and forces a rebuild). This field is on the child, not the NPC root.
- **The override is detected by a non-default field in the assigned `look`**, so an empty/`null` `body_model` (or a WHITE colour, or a null texture) means "fall through to the `BodyModelSwap` default" â€” it does not mean "blank it out." To drop ALL per-instance overrides, clear the NPC's `look`; to change the default for *everyone*, edit the `BodyModelSwap` child in `enemy.tscn`.

Relevant files: `rpg/scripts/components/body_model_swap.gd`, `rpg/scripts/npc/npc.gd` (the **Body & Head â–¸ Custom Models** subgroup â€” the single `look` export â€” and `register_swapped_head`), and the `BodyModelSwap` node in `rpg/scenes/enemies/enemy.tscn`.

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

- **`faction_id`** (`String`, a `PROPERTY_HINT_ENUM_SUGGESTION` dropdown) â€” the options are generated at edit time by `Factions.ids_csv()` in `_validate_property`, a scan of `res://resources/factions/` sorted alphabetically (currently `neutral_wildlife, raiders, townsfolk`), so a new faction `.tres` saved into that folder appears automatically. At `_ready`, the NPC calls `Factions.by_id(faction_id)`, which loads `res://resources/factions/<id>.tres` (or `.res`) and stamps it onto the live `faction` slot. A non-empty `faction_id` **wins over** the `faction` resource slot.
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
3. **Nothing to "make it pickable."** The `faction_id` dropdown auto-populates from `res://resources/factions/` (both `npc.gd` and `npc_data.gd` build the hint via `Factions.ids_csv()` in `_validate_property`). The moment you save `corp_security.tres` into that folder it appears in the dropdown on every NPC and `NpcData` â€” no code edit at all. (Reload the project if it doesn't show immediately.)
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

Worth understanding so your branch lines read the way you expect. When a line opens, the player **hears it first** with only a continue prompt â€” the response menu is *not* shown yet. The menu appears once the line's spoken time elapses, or on the *next* click/press. On a linear line the conversation **auto-continues** to the next line after the line's spoken time (auto-advance, on by default), and a click skips ahead immediately (so clicking "skips through" a monologue). The choices menu is also auto-revealed on the **final** line, even if it has no authored choices, so the player always gets a clean way out.

When the menu does appear, the manager appends synthesized options *after* your authored choices automatically â€” based on components attached to the speaker: **Follow me / Wait here** (companion recruit), **Trade** (a Merchant child), **Heal** (Healer child), **Rest** (Bonfire child), **Level Up** (LevelUp child), **Exchange Gear** (a following ally with a backpack), and always a final **Goodbye.** to leave. You don't author those â€” attaching the relevant component to the NPC makes them appear.

### Auto-advance (lines play themselves)

By default a conversation **auto-continues**, New Vegas style: when a line finishes being spoken it advances to the next on its own, no click required (a click still skips ahead, and the response menu still waits for input). The pacing lives in `GameSettings.dialogue` (the `DialogueSettings` Resource at `res://resources/tuning/DialogueSettings.tres`), under the **Auto-advance** group:

- **`auto_advance`** (bool, default **on**) â€” the master switch. Off = the player clicks/presses to advance every line (the old behaviour).
- **`auto_advance_seconds_per_char`** (`0.07`) â€” estimated spoken time per character. This same number drives how long the talking head-bob / mouth-flap runs, so the animation and the advance stay in sync (~0.07 â‰ˆ 14 chars/sec, tuned to the TTS pace).
- **`auto_advance_min_seconds`** (`1.6`) / **`auto_advance_max_seconds`** (`9.0`) â€” floor and cap on a line's spoken time, so a one-word line still holds briefly and a wall of text doesn't stall.

A line's spoken time is `length Ã— per_char`, clamped to `[min, max]`. The same estimate is used whether or not TTS audio is on, so auto-advance works either way.

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
- **Listen-first means an extra beat on branch lines.** Players hear the line, *then* the choices appear (once its spoken time elapses, or on the next input). That's intended, not a bug â€” author your branch text as something the NPC says before offering the options.
- **Lines auto-advance by default.** With `GameSettings.dialogue.auto_advance` on (the default), a linear line continues on its own after its spoken time (New Vegas style) â€” you no longer click every line. A click still skips ahead and the menu still waits. Turn `auto_advance` off in `DialogueSettings.tres` to require a click per line.
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
- `icon` (Texture2D) â€” legacy/optional; the **grid** backpack does NOT use it. A grid tile renders the item's 3D MESH (a weapon's `WeaponData.view_model`, else this item's `world_model`); items with no mesh (ammo, consumables) draw a small category glyph instead. The item's name shows on hover in the footer detail line.

**Classification & Stats**
- `category` (enum: `WEAPON / CONSUMABLE / AMMO / MISC`) â€” gates which fields below matter and which helper (`is_weapon` / `is_ammo` / `is_consumable`) applies.
- `max_stack` (int) â€” how many fit in one stack. `1` = unstackable (always set this for weapons); `>1` lets ammo/consumables pile up (the Health Pack uses `5`).
- `weapon` (WeaponData) â€” set **only** on `WEAPON`-category items; point it at a weapon `.tres` like `res://resources/weapons/pistol.tres`. This is what makes the item equippable.
- `caliber` (StringName) â€” for `AMMO` items, the caliber these rounds feed (e.g. `&"pistol"`), matched against a weapon's own `caliber` on reload. (Shipped calibers are `pistol`, `smg`, `shells`, `rifle`, `grenades`.)
- `weight` (float) â€” abstract carry weight of one of this item; summed into the carrier's load (over capacity = encumbered/slowed).
- `value` (float) â€” base trade value in **zorkmids** (the in-game currency). Fractional â€” zorkmids run in hundredths, so `0.5` is half a zorkmid. `0` = worthless / unsellable.
- `heal_amount` (float) â€” for `CONSUMABLE` items, HP restored when used from the inventory.

**World Model**
- `world_model` (PackedScene) â€” optional unique 3D model for when this item sits **in the world** (dropped/looted/spawned). A pickup with `build_model_from_item` on will instantiate this and auto-fit its hitbox. Null = the pickup keeps whatever body it was authored with. **Doubles as the inventory-grid thumbnail** for non-weapon items (a weapon falls back to its `WeaponData.view_model`); set it on an ammo/consumable to give that item a 3D icon instead of the default glyph.

**Inventory grid** (the Tetris-style spatial backpack)
- `grid_width` / `grid_height` (int, clamped â‰¥1) â€” the item's **footprint** in backpack cells (Resident Evil / Deus Ex style). `1Ã—1` is a single cell; bigger, distinct shapes make weapons read differently and force packing/rotation. The shipped weapons are authored: pistol `2Ã—1`, SMG `3Ã—1`, shotgun `4Ã—2`, sniper `5Ã—1`, melee `1Ã—3`, spray paint `1Ã—2`; ammo, consumables, and misc stay `1Ã—1`. Each STACK occupies one footprint (not each unit), and the player can **rotate** a held item with **R** while dragging it. The grid's overall size is a global tunable â€” `GameSettings.inventory.grid_cols/grid_rows` (see Â§12). NPC / corpse / container bags are unbounded; only the player's bag enforces the spatial cap, so an over-stuffed loadout never silently loses NPC loot.

> One Item class covers everything â€” there is deliberately no `WeaponItem` subclass. A weapon is just an Item with `category = WEAPON` and a `weapon` reference, because Godot's typed-array `.tres` serialization doesn't reliably round-trip script subclasses inside an `Array[Item]`.

### 1b. Status effects on a consumable (buffs / poison / stims)

A potion that haunts you for 8 seconds, a stim that hastens your stride, a poison dart that ticks your HP down — all of it is one tiny data type, the **`StatusEffect`** Resource (`res://scripts/combat/status_effect.gd`, `class_name StatusEffect`), riding on a consumable Item. You author the effect `.tres` in the inspector, drag it into an Item's `consumable_effect`, and the player applies it by using the item from the backpack. No code.

#### Authoring a StatusEffect .tres

Create one with **right-click in the FileSystem → New Resource → StatusEffect**. There's no shipped example yet, so save your first one under `res://resources/effects/` (create the folder). The fields:

- **`id`** (StringName, default `&""`) — the dedup key. A **non-empty** id makes re-applying the *same* effect **refresh its duration** instead of stacking a second copy (use the same stim twice and the timer just resets to full). An **empty** id always stacks, so two copies run independently. Set an id for anything a player might re-use mid-effect; leave it empty only when you genuinely want them to pile up.
- **`display_name`** (String) — human label for the effect.
- **`description`** (`@export_multiline`) — detail text.
- **`icon`** (Texture2D) — optional effect icon.
- **`duration`** (float, default `5.0`) — seconds the effect lasts. **`0` = permanent** until something explicitly removes it (`remove_effect` / `clear_effects`).
- **`tick_interval`** (float, default `1.0`) — seconds between periodic ticks. **`0` = no periodic effect at all** (a pure buff/debuff with no DoT).
- **`damage_per_tick`** (float, default `0.0`) — HP applied to the host each tick. **Positive = damage** (poison/burn). Needs `tick_interval > 0` to ever fire; `0` means no DoT.
- **`stat_modifiers`** (Dictionary, default `{}`) — per-stat additive tweaks, e.g. `{ "strength": 2 }`. **Tracked and queryable today but NOT yet read by `CharacterStats`** — see Gotchas. Don't ship an effect that relies on this for its payoff yet.
- **`speed_multiplier`** (float, default `1.0`) — move-speed factor while active. `0.5` = slowed, `1.5` = hastened, `1.0` = no change. This one works live for both player and NPCs.
- **`visual_effect`** (PackedScene, optional) — a particle/overlay scene instanced as a child of the host while the effect is active and freed automatically when it ends. Use it for a poison cloud or a haste shimmer.

#### Wiring it onto a consumable (the easy path)

The whole point is that you never place a manager node. Author the effect, then on a consumable Item `.tres`:

1. Set the Item's **`category` = `CONSUMABLE`**.
2. Drag your `StatusEffect` `.tres` into **`Item.consumable_effect`** (it sits beside `heal_amount` in the inspector).

That's it. Using the item from the backpack runs `Player.use_consumable`, which **lazily creates a `StatusEffectManager` child named `"StatusEffects"` on the player on first use** — you never pre-place one. Move speed is then read automatically: `Character.status_move_multiplier()` re-scans the character's children every frame (for *both* the player and NPCs), so `speed_multiplier` just takes effect with zero extra wiring. An effect can heal *and* buff in one item — `heal_amount` still applies its instant HP on use, on top of whatever the `StatusEffect` does over time.

For an **always-on or NPC effect** (a hazard aura, a buff a script grants on a trigger), drop a **`StatusEffectManager`** node (`res://scripts/components/status_effect_manager.gd`, `class_name StatusEffectManager`, a plain `Node` — no `@export`s) directly under any character; its host is `get_parent()`. Call `apply_effect(my_effect)` on it from a script (e.g. an area trigger), and use `remove_effect(id)` / `has_effect(id)` / `clear_effects()` to manage it. It emits `effect_added` / `effect_removed` if you want to drive a HUD off it. (Periodic damage only lands if the host has a `take_damage` method — every `Character` does.)

#### Worked example — a poison dart

> Goal: a consumable that poisons the user for 4 HP/second over 8 seconds and slows them while it ticks, refreshing if re-used.

1. **New Resource → StatusEffect**, save as `res://resources/effects/poison.tres`. Set:
   - `id` = `&"poison"` (non-empty → re-use refreshes the timer)
   - `duration` = `8.0`
   - `tick_interval` = `1.0`
   - `damage_per_tick` = `4.0`
   - `speed_multiplier` = `0.8`
2. On the consumable Item `.tres`: `category` = `CONSUMABLE`, `heal_amount` = `0`, and drag `poison.tres` into `consumable_effect`.
3. Done. Using it deals 4 HP/tick for 8 seconds at 0.8× move speed. Using it again before it expires **refreshes** the full 8 seconds (because `id` is non-empty) rather than stacking a second poison.

**A haste potion** is the same recipe with no DoT: `id` = `&"haste"`, `duration` = `10.0`, `tick_interval` = `0.0`, `damage_per_tick` = `0.0`, `speed_multiplier` = `1.5`. Pair it with `heal_amount` on the Item if you want a heal-and-run stim.

#### Gotchas

- **`stat_modifiers` does nothing to your stat sheet yet.** It's recorded and readable (`StatusEffectManager.stat_modifier(stat)`), but `CharacterStats` doesn't consume it — that hookup is a follow-up. **Only `damage_per_tick` and `speed_multiplier` have live effects today.** Don't author a "+2 strength" buff and expect it to do anything in-game.
- **Empty `id` stacks; non-empty `id` refreshes.** If a re-used effect is doubling up when you wanted a timer reset (or vice-versa), check the `id` field — that single field decides it.
- **No DoT without an interval.** `damage_per_tick` is ignored unless `tick_interval > 0`. A "poison" with `tick_interval = 0` does nothing.
- **You don't place the manager for consumables.** The `"StatusEffects"` node appears on the player automatically on first consumable use. Only drop a `StatusEffectManager` by hand for always-on / NPC effects you drive from a script.
- **`duration = 0` is permanent**, not instant — it lasts until `remove_effect` / `clear_effects`. Use it only for effects you intend to clear yourself.

Relevant files: `res://scripts/combat/status_effect.gd`, `res://scripts/components/status_effect_manager.gd`, `item.gd` (`consumable_effect`), and the character speed hook in `Character.status_move_multiplier()`.

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
   - `loot_table` (LootTable) â€” **optional** random loot rolled in *on top* of the fixed contents at spawn (see the **LootTable** entry below). Null = just the fixed contents.
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

**Tuning an ability.** Each ability *scene* carries its own `@export` config -- open `Grapple.tscn` for its `config` (a `GrappleHookResource` rope `.tres`; null falls back to the Player's own `grapple_resource`), `WallClimb.tscn` for `climb_hop_up` / `climb_hop_forward` / `wall_climb_speed`, and so on; every ability also inherits an `enabled` flag. Tune the scene (or the `UpgradePickup`'s instanced copy of it) like any other node.

**Adding a NEW ability scene.** Writing the ability itself is code (a script extending `Ability`, overriding `ability_id()` and the movement hooks). Save its scene under `res://scenes/components/abilities/` and follow the **naming convention**: the scene's **PascalCase** filename must equal its `ability_id()` in **snake_case** (`Grapple.tscn` â†” `grapple`, `WallClimb.tscn` â†” `wall_climb`). `AbilityRegistry` scans that folder and snake-cases the filenames to self-populate the `unlock_id` dropdown, and a drift test enforces the match -- so a mismatched name fails the test rather than silently vanishing from the dropdown.

### 8. Loose money â€” `MoneyPickUp` (`res://scripts/components/money_pickup.gd`)

For a pure stash of cash on the ground (not inside a container or corpse), drop a **`MoneyPickUp`** (`class_name MoneyPickUp`). Set `amount` (float, fractional allowed) â€” on E it credits the player's wallet, fires the HUD readout + floating "+N" indicator, and frees itself. With no authored body it builds a simple gold coin (or `world_model` if you assign one); `pickup_label` overrides the default "Take N zorkmids" hover.

### Gotchas

- **Always set `max_stack = 1` on weapon Items.** Weapons must be unique instances; a stackable weapon breaks the "each weapon is its own object" assumption the whole loot pipeline relies on.
- **A `WEAPON`-category Item with no `weapon` assigned isn't a weapon** â€” `is_weapon()` checks both. It'll behave as plain junk (stacks, won't equip).
- **`category` in the saved `.tres` is the enum *index*** â€” `0=WEAPON, 1=CONSUMABLE, 2=AMMO, 3=MISC`. Edit it through the inspector dropdown, not the raw text, to avoid mislabeling (e.g. `healthpack.tres` shows `category = 1` for CONSUMABLE).
- **`money` lives on the container/corpse, not in `item_stacks`.** Cash isn't an Item â€” there's a dedicated `money` float and a "Take N zm" row. Don't try to make a "zorkmid" Item. (The inventory shows the wallet as a coin *tile*, but that's display only â€” the economy still reads a float.)
- **The PLAYER backpack is spatially bounded now** (`grid_cols Ã— grid_rows` cells, footprints from each Item). A pickup or loot-take can be **refused when the grid is full** â€” the world pickup stays put and a "No room" toast fires; a shop won't charge for something that won't fit. So a player can't carry infinite loot â€” size the grid (`GameSettings.inventory`) and item footprints with that in mind. NPC / corpse / container bags are UNBOUNDED, so stocking a heavy NPC loadout never drops loot.
- **The loot / pickpocket / container screen is two GRIDS now** (source on top, your bag below), not two lists. You click an item to take/deposit it and can drag to rearrange your own grid; item footprints apply there too. Authoring is unchanged â€” you still just fill `item_stacks` / `money`.
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
- **Damage** â€” `damage` (HP per hit, *per pellet* on a shotgun; the player has only 4 HP, so `1.0` is a quarter-bar), `headshot_multiplier`, `sneak_attack_multiplier` (hitting an un-alerted enemy), `backstab_multiplier` (inert at `1.0` until you raise it) / `backstab_arc_degrees` (the rear arc that counts as a backstab, `90.0` = the back quarter), and `overkill_penetration` (excess damage punches through to whoever's behind).
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

> Important: the calibers that actually ship are `&"pistol"`, `&"smg"`, `&"shells"`, `&"rifle"`, and `&"grenades"` â€” for the pistol, SMG, shotgun, sniper, and rock-launcher respectively (see the matching `ammo_*.tres` in `resources/items/`). The `9mm` you'll see in some code comments is just an illustrative example, not a real caliber in the project. Match the weapon's `caliber` to an existing ammo item's `caliber` exactly, or the gun can never be reloaded.

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
- **`PerkStation`** (`perk_station.gd`) â€” aim + E at a shrine to learn a `Perk` (permanent stat bonuses / ability grant). Knobs: `perk`, `consume_on_use`. (Note: the level-up perk picker isn't built yet â€” the station is the only path today. See "Perks (the PerkStation shrine)".)
- **`Radio`** (`radio.gd`) â€” an in-world radio that ducks during combat/dialogue; cycles a *folder* of tracks (`music_folder`, default the shipped music folder; optional per-radio `shuffle`) out of a spatial `AudioStreamPlayer3D`, falling back to a single `fallback_audio` track only when the folder is empty. Drop under a radio prop. Knobs: `radio_name`, `music_folder`, `shuffle`, `fallback_audio`, `audible_radius` (plus fade/duck and click-SFX tuning).
- **`Talkable`** (`talkable.gd`) â€” make ANYTHING speakable (villager, terminal, vending machine) without overriding the host's root script. Instance `talkable.tscn` under the host, assign a `DialogueResource` to `dialogue` (and optional `voice`), size the shape. Use **`DialogueNPC`** (`dialogue_npc.gd`) instead when you want the whole node to *be* the talkable (script on the root, with a child Area3D assigned to `range_area`).

**Openable & triggered geometry:**

- **`Door`** (`door.gd`, `@tool`, `extends LookAtInteractable`) â€” aim + **E (Interact)** to swing a door open/closed; a child `StaticBody3D` under the pivot blocks the doorway until it opens, so an open door simply isn't in the way. Prefab `res://scenes/components/door.tscn`. Swing knobs: `pivot` (**REQUIRED** â€” the `Node3D` it rotates, holding the mesh + the blocker; null â†’ open/close are no-ops), `open_angle` (`90.0`; negative swings the other way), `open_duration` (`0.5` s), `start_open`. Lock knobs: `locked`, `requires_item_id` (an inventory `Item.id` key; empty = no key), `consume_key` (eat the key on unlock, off = reusable), `unlock_flag` (while this `GameState` flag is true the door counts as unlocked). API: `open()` / `close()` / `toggle()` / `is_open()`; signals `opened` / `closed` â€” so a `TriggerVolume`, switch, or cutscene can drive it. **Re-bake the navmesh** if the door body sits in walkable space.
- **`TriggerVolume`** (`trigger_volume.gd`, `extends Area3D`) â€” fire configurable actions when a body in `trigger_group` enters (or exits) a zone. Prefab `res://scenes/components/trigger_volume.tscn`. See **"Triggers, encounters & cutscenes"** for the full field list.

**Locking:** **`Lock`** (`lock.gd`, plain `Node`) â€” drop under any interactable (a container, or a `Door`) and the host checks it before opening. Knobs: `locked`, `requires_item_id` (default `&"lockpick"`; set a key/keycard id for a keyed variant), `consumes_item` (off for a reusable key). Emits `unlocked(by)`.

**Destruction & drops:**

- **`CanDestroy`** (`can_destroy.gd`, `extends StaticBody3D`) â€” a body that breaks when shot (works for every weapon; both hitscan and projectiles call `take_damage`). Use it as the root of a breakable, give it a `CollisionShape3D` + `MeshInstance3D`. Knobs: `max_hp`, `destroy_effect`, `destroy_sound`. Emits `destroyed`.
- **`SpawnOnDestroy`** (`spawn_on_destroy.gd`, plain `Node`) â€” drop UNDER a `CanDestroy` or `Throwable` and it spawns loot into the level when the host breaks. Knobs: `spawn_scene` (e.g. a `CanPickUp` prefab), `count`, `scatter`, optional `loot_table` (rolls and stamps each rolled item onto a copy). Pair the two for "shoot the crate for loot."
- **`Throwable`** (`Throwable.gd`, `@tool`, `extends RigidBody3D`) â€” a pick-up-and-throw physics object (a crate). Emits `destroy` on break, so `SpawnOnDestroy` works on it too.

**NPC / character presentation (drop under the Enemy root):**

- **`BodyModelSwap`** (`body_model_swap.gd`, `@tool`) â€” swap an NPC's body/head (and even arms/legs) for your own `.glb` files with a **live editor preview**, AND drive its runtime character motion. Knobs include `body_model`, `head_model`, and `*_scale` / `*_position` / `*_rotation` for each part, optional `*_texture` / `*_color` re-skins, arm/leg gait-animation tuning, and a momentary `refresh_preview`. Runtime motion (see "Customising an NPC look"): `legs_follow_movement` + `leg_turn_rate` (legs steer to the movement direction independent of the torso), `arm_raise_range` (an armed NPC only raises its weapon when the foe is within this many metres; farther = gun drawn but arms down), the talking head-bob (`talk_head_bob` + `talk_bob_*`) and a billboarded flapping mouth (`show_mouth` + `mouth_*`, active while it speaks a line or bark), and the chest `breathe` idle (during a conversation only the NPC you're talking to breathes). Note: the head scale/pos/rot knobs are named `head_scale` / `head_position` / `head_rotation` (the body's are `body_model_scale` / `body_model_position` / `body_model_rotation`). If you use `head_model`, clear the NPC's own `head_scene`.
- **`NpcHeadLookMount`** (`npc_head_look_mount.gd`) â€” FNV-style independent head tracking (the head turns to its foe/player/noise). Drop one under the Enemy root. Knobs: `enabled`, `look_range`, `max_yaw_deg`, `max_pitch_deg`, `turn_speed`, `look_at_player`, `host_path`. Gated by `GameSettings.npc_ai.head_look`, which **ships ON**, so it's live by default.
- **`LocomotionFx`** (`locomotion_fx.gd`) â€” footstep SFX + landing thud + dust for any `CharacterBody3D`. NPCs auto-build one, so you only attach it to override. Knobs: `footstep_sounds`, `land_sound`, `stride_length`, `move_threshold`, `footstep_volume_db`, `land_volume_db`, `min_land_speed`, `hard_land_speed`.
- **`FallScream`** (`fall_scream.gd`) â€” plays a yell after falling for a moment, re-arms on landing. Drop under any `CharacterBody3D`. Knobs: `scream` (clear it â†’ inert), `min_fall_time`, `min_fall_speed`, `volume_db`.

**NPC routes:**

- **`PatrolPath`** (`patrol_path.gd`, `@tool`, `extends Node3D`) â€” a level-placed route; its `Marker3D` / `Node3D` **children** are the ordered waypoints (config-warns with zero). Knobs: `loop` (`true` = cycle the route, `false` = ping-pong), `wait_time` (`1.0` s paused per waypoint). No prefab. See **"Patrol routes."**
- **`PatrolBehavior`** (`patrol_behavior.gd`, `@tool`, plain `Node`) â€” drop **UNDER an NPC** and point `patrol_path` at a `PatrolPath`; the NPC walks the beat while idle (combat interrupts, then it resumes). Knobs: `enabled`, `patrol_path` (`NodePath`; empty = inactive). No prefab. See **"Patrol routes."**

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

- **Some components have a global gate, not just a local toggle.** `NpcHeadLookMount` (`GameSettings.npc_ai.head_look`) and `NoiseSource` (`GameSettings.npc_ai.hearing_initiates`) are gated by a registry flag in `NpcAiSettings.tres`. As shipped, **`head_look` and `music_reactions` are ON**, so a head-look mount and a `Radio`'s NPC reactions are live by default; **`hearing_initiates` is still OFF**, so a `NoiseSource` stays inert until you flip that flag for a playtest.
- **Parent matters.** `SpawnOnDestroy` and `MusicDirector` connect to / read their **parent**, so they must be a *child of the right host* (a `CanDestroy` / `Throwable`, or the music player). `Lock` must be a child of the interactable it guards (it's discovered via `Lock.of(host)`, which scans the host's children).
- **Size the hitbox.** Look-at interactables only respond where their `CollisionShape3D` covers â€” if E does nothing, the shape is too small or missing. Set `auto_fit_collider = true` to fit it to the host's meshes (at runtime for any interactable; the `@tool` dual-mode stations â€” `Merchant`/`Healer`/`Bonfire`/`LevelUp`/`Radio`/`ItemContainer`/`PerkStation` â€” also preview-resize an *existing* collider live in the editor and persist it on save, so author a `CollisionShape3D` first for the editor preview to size).
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
| `npc_audio` | `NpcAudioSettings.tres` | The NPC combat-audio MIX: per-cue volumes (dB) + random pitch ranges for the aim/charge sting, the incoming-shot beep, and the miss ricochet |
| `reputation` | `ReputationSettings.tres` | Faction-standing penalties and the HOSTILE / FRIENDLY thresholds (NEUTRAL is the band between them) |
| `distraction` | `DistractionSettings.tres` | Default noise of a thrown decoy (the "lob a rock to lure a guard" verb; inert unless `npc_ai.hearing_initiates` is on) |
| `search` | `SearchSettings.tres` | How an NPC HUNTS a lost target / noise: the uncertainty ring (`max_search_radius`, `uncertainty_grow_rate`, `min_search_radius`, `sample_points`, `crumb_timeout`), per-stimulus seeds (`noise_radius_scale`, `corpse_radius_frac`, `seed_radius`), and the frantic→resigned `intensity_curve` + dwell (`crumb_dwell_min/max`). INERT at defaults (`max_search_radius` 0 / `sample_points` 1 = today's single-point stare); raise both to turn the breadcrumb hunt on |
| `dialogue` | `DialogueSettings.tres` | Conversation flow + presentation feel: pre-talk pacing (`npc_turn_to_face_duration`, `talk_prompt_buffer_duration`), intro delay + speaker face-turn (`dialogue_intro_delay`, `dialogue_speaker_face_duration`), the **Auto-advance** group (`auto_advance` true, `auto_advance_seconds_per_char` 0.07, `auto_advance_min_seconds` 1.6, `auto_advance_max_seconds` 9.0 â€” lines auto-continue after their spoken time, New Vegas style), the cinematic letterbox bars, the music duck while a conversation is up, and the dialogue box layout (panel margins, font sizes, label offsets) |
| `inventory` | `InventorySettings.tres` | The Tetris-style spatial backpack's dimensions: the PLAYER's grid (`grid_cols` 6, `grid_rows` 5) and the LOOT-source grid a corpse/container gets when you open it (`container_grid_cols` 10, `container_grid_rows` 8). Bigger = more carry slots; shrink for a tighter Tarkov-style squeeze. Per-item *footprints* live on the `Item` (`grid_width`/`grid_height`, Â§9), not here |

### Editing a tuning value in the inspector

1. In the **FileSystem** dock, open `res://resources/tuning/` and double-click the group you want, e.g. `EffectsSettings.tres`.
2. The **Inspector** shows the fields, organised under the `@export_group` headers you see in the table (Decals, Dust, Gore gibs, â€¦). Every field has a tooltip describing exactly what it does and which direction is "more".
3. Change the value and **save** (`Ctrl+S`). Because `GameSettings` preloads that same file, the new number is live the next time you run â€” no code, no recompile.

**Worked example â€” make the whole game gorier.** Open `EffectsSettings.tres`. Under **Gore gibs**, raise `gib_count` from `6` to `12` and bump `gib_max_active` from `24` to `48` so the extra chunks aren't reclaimed immediately. Under **Blood drops (world)**, raise `blood_drop_count` from `24` to `40`. Save. Done â€” every bloody-mess death in every scene now bursts bigger, and you never opened a script.

### Restyling the effects themselves (`EffectFactory`)

`EffectsSettings` (above) tunes the *numbers* -- how many gibs, how long blood lingers. To change what those effects **look like**, swap the scenes on the **`EffectFactory`** autoload (`rpg/managers/EffectFactory.gd`). It holds one `@export PackedScene` per game-wide visual effect, grouped in the inspector; change a slot and *every* spawn of that effect, in every scene, uses the new look -- no gameplay code.

| Group | Slots |
|---|---|
| **Blood** | `blood_decal` (splat on surfaces), `blood_particle` (impact spray), `bloody_mess` (the big death burst), `blood_drop` (drips) |
| **Impact Effects** | `bullet_hole_decal` (marks on non-flesh), `dust` (footstep / small puff), `dust_large` (heavy-impact cloud) |
| **Explosions** | `explosion_area` (the blast -- carries its own damage area) |
| **Gore Gibs** | `gib` (the flung body chunk -- a placeholder cube until real gore meshes exist) |

To restyle: open the **scene a slot points at** (e.g. `bloody_mess.tscn`, or the `gib` placeholder) and edit it -- every spawn picks up the change. Or repoint the slot to a different scene in `EffectFactory.gd`. The `gib` and `bloody_mess` placeholders are the obvious first swaps when real gore art lands.

### The rule: player-facing tunables and keybinds must ALSO reach the settings menu

Here's the catch that trips people up. A tuning `.tres` value is a **designer** knob â€” great for things the player never touches (gib count, NPC retarget interval, faction thresholds). But the moment a value is something a **player** should control â€” volume, sensitivity, FOV, an accessibility/comfort toggle, screen-shake strength â€” the project rule from `rpg/CLAUDE.md` ("Keep the settings menu in sync with features") says it must **also** be wired through two more files, or the in-game options screen silently won't have it:

- **`rpg/managers/Settings.gd`** â€” the player-facing OPTIONS + persistence autoload. This is *not* the same as `GameSettings`. `Settings` owns only what the Options menu can change: it stores the player's choice, saves it to `user://settings.cfg`, loads + applies it on boot, and (where relevant) pushes it onto the right `GameSettings` field. For instance `Settings.set_fov()` clamps to `FOV_MIN..FOV_MAX` (60â€“120) and writes `GameSettings.camera.default_fov`; `set_mouse_sensitivity()` writes `GameSettings.camera.mouse_sensitivity`; `set_screen_shake_scale()` scales `GameSettings.screen_shake.intensity_multiplier` (off a baseline captured at boot). The pattern for a new tunable: add a stored `var`, a `set_â€¦()` that applies + calls `save_settings()`, and a line in both `load_settings()` and `save_settings()` for the `.cfg`.
- **`rpg/scripts/ui/options_menu.gd`** -- the `OptionsMenu` overlay (autoload, opened with Escape; serves both the start menu and in-game). It is fully DATA-DRIVEN: every row is a `SettingSpec` in `resources/settings/SettingsCatalog.tres`, and `_rebuild_tabs()` iterates `CATALOG.specs` and lets `_emit_row()` build each control by dispatching on `SettingSpec.Widget` (Section / Toggle / Slider / Dropdown / Keybind / Custom). Tabs appear in the order their first spec is seen; edits stage into `_pending` and only commit on **Apply** (key rebinds are the exception -- they bind live). You do NOT hand-build rows here: to add an option you add a typed `var` + a `set_*` setter to `Settings.gd`, then add ONE `SettingSpec` row to the catalog (no `options_menu.gd` edits).

**Keybinds** are also data-driven. To add a rebindable action: add its keyboard/mouse default to `project.godot`'s `[input]` map (the editor's Input Map panel) and its controller default in `managers/InputManager.gd`, **then** add ONE `ActionSpec` row (`action` / `label` / `section` / `rebindable`) to `resources/input/ActionCatalog.tres`. The Controls-tab section headers + rebind rows are GENERATED by `ActionCatalog.keybind_specs()`, which `OptionsMenu` appends to `CATALOG.specs` in `_rebuild_tabs()` -- so do NOT hand-author a `Keybind` `SettingSpec` in `SettingsCatalog.tres`. The action *name* is the stable key -- rebinding only swaps the bound event, so everything that polls the action name keeps working. `Settings.rebind_action()` persists the new event under the cfg's `[controls]` section.

So the mental model is: **`GameSettings` = the designer's master tuning sheet; `Settings` = the slice of it (plus video/audio/keybinds) the player is allowed to override, persisted to disk; `OptionsMenu` = the screen that drives `Settings`.** A pure balance number stops at `GameSettings`. A player-facing one travels through all three.

### The player's menu screens

Three full-screen player menus open from rebindable keys (Deus Ex / Pip-Boy style -- they share a tab group, so the player can flip between them):

| Screen | Default key | Shows |
|---|---|---|
| **Inventory** (the Tetris grid, Â§9) | **Tab** | the backpack grid + equipped weapon |
| **Stats** (Â§20) | **C** | the player's `CharacterStats` sheet |
| **Reputation** (Â§7) | **V** (action `Factions`) | standing with each faction |

They're autoloads that auto-populate from live state, so there's nothing to author per level -- this is just *where* the content you set (stats, reputation, items) is shown to the player. The keys are rebindable like any other (they're `ActionCatalog` rows in the **Interface** section, alongside `RotateItem` = **R** for rotating an item in the grid).

### Gotchas

- **Don't confuse `GameSettings` with `Settings`.** They're two different autoloads. `GameSettings` holds the live `.tres` numbers; `Settings` holds the saved player overrides and *writes into* a few `GameSettings` fields on apply. Editing `CameraSettings.tres`'s `default_fov` changes the authored default; `Settings` will overwrite it on boot with the player's saved FOV (it seeds *from* the design default only when there's no `settings.cfg` yet). So if a value seems to ignore your `.tres` edit at runtime, check whether the Options menu owns it.
- **A player-facing value added only to a `.tres` will never appear in the Options menu.** The menu is built from `Settings`, not from `GameSettings`. Skipping the `Settings.gd` + `options_menu.gd` wiring is the single most common way a new comfort/audio/sensitivity option ends up uncontrollable in-game.
- **`intensity_multiplier = 0` (ScreenShake) and `bob_amount = 0` (Camera) fully disable** those effects â€” handy, but note the same outcomes are reachable by players via the Accessibility tab's Screen Shake slider and View Bobbing toggle. Prefer leaving the `.tres` at the authored baseline and letting the player opt out, since `Settings` captures that baseline at boot to anchor its percentage sliders.
- **The `npc_ai` stealth/comfort toggles have safe script defaults of `false`** â€” off means the NPC code path is byte-identical to the old behaviour â€” **but the shipped `NpcAiSettings.tres` turns `head_look` and `music_reactions` ON**; `body_discovery`, `hearing_initiates`, and `hearing_occlusion` remain off. Flip one on, then playtest; some (like `head_look`) can need a per-rig axis tweak.
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

### Perks (the PerkStation shrine)

A **perk** is a permanent player upgrade you author once as a `.tres` and hand out at a shrine — a bundle of permanent stat bonuses and/or a granted ability, optionally gated behind prerequisite perks (a simple tree). Like a `LevelUp`, a perk's stat bonuses run through the same private-sheet + endurance/strength delta handling, so a perk's `endurance` raises max HP and its `strength` raises carry capacity exactly the way leveling does. Like an `UpgradePickup`, a perk can also grant an ability scene under the player. None of it needs code — you fill a `Perk` resource and drop one `PerkStation` node.

> **Today the station is the only path.** `LevelUp` carries an export group (`available_perks` / `perk_points_per_level`) for authoring perks ahead of a level-up perk *picker* — but that picker UI **isn't built yet**, so those fields are data-only. A `PerkStation` is the only way to unlock a perk in the live game right now.

#### 1. The Perk Resource (`rpg/scripts/player/perk.gd`)

A `Perk` (`class_name Perk`, an `@tool` Resource) is the data atom. Create one with **right-click in the FileSystem → New Resource → Perk** and fill it in:

- **`id`** (StringName) — the stable lookup key, unique per `.tres` (e.g. `&"tough_skin"`). The `PerkManager` records and prerequisite-checks perks by this id; an empty id can never unlock.
- **`display_name`** (String) — shown in the "Learn: …" hover and the "Learned: …" toast. Blank falls back to the `id`.
- **`description`** (multiline) — detail text.
- **`icon`** (Texture2D) — optional display icon.
- **`stat_bonuses`** (Dictionary) — permanent stat deltas applied on unlock, e.g. `{ "endurance": 2, "agility": 1 }`. **Keys MUST be `CharacterStats` attribute names** — `strength`, `persuasion`, `gunplay`, `endurance`, `streetwise`, `agility` — and any unknown key is **silently ignored**, so a typo grants nothing. `endurance` bumps max HP and `strength` bumps carry capacity automatically (same delta math as `LevelUp`); the other four are read live at their own seams.
- **`grants_ability`** (PackedScene) — *optional* ability scene instanced under the player on unlock, exactly like an `UpgradePickup`'s `grants` (drag in a scene from `scenes/components/abilities/`). Leave null for a pure stat perk.
- **`requires_perks`** (`Array[StringName]`) — prerequisite perk ids that must already be unlocked before this one can be. Empty = always available. This is how you build a tree (see below).

#### 2. The PerkStation component (`rpg/scripts/components/perk_station.gd`)

A `PerkStation` (`class_name PerkStation`, an `@tool` node that **extends `LookAtInteractable`**) is the drop-in shrine. The player aims at it, presses **E (Interact)**, and the perk is applied. It inherits the whole look-at family — `highlight_target`, `highlight_color`/`highlight_width`, and `auto_fit_collider` — and adds two knobs:

- **`perk`** (Perk) — the perk this station grants. Unassigned → the station can't be interacted with (and the inspector shows a configuration warning).
- **`consume_on_use`** (bool, default `true`) — free the station after a successful grant (a one-time shrine). Set `false` to leave it standing.

There's **no shipped `.tscn`** for the station — author it the way you author an `UpgradePickup`: drop a plain `Area3D` under the shrine prop, attach `perk_station.gd`, size its `CollisionShape3D` (or tick `auto_fit_collider`), and assign `perk`.

**How the grant works.** On the first interaction the station finds the player's `PerkManager` child (a `Node` named `"Perks"`) or **auto-creates one** — you never place it. The manager owns a **private duplicated `CharacterStats`** sheet (it never mutates a shared `.tres`) and re-applies the same `endurance → max_hp` and `strength → carry` deltas as `LevelUp`, then instances `grants_ability` (if any) under the player. The unlock is gated by `can_unlock`: the perk must be valid, **not already owned**, and **all of its `requires_perks` already unlocked**. A successful grant toasts "Learned: \<name>" (and frees the station if `consume_on_use`); a blocked or repeat attempt toasts "Already learned" and leaves the station in place.

**Worked example — a "Tough Skin" shrine**

> Goal: aim at a shrine, press E, gain +2 endurance (and the matching max-HP bump) once.

1. Create `tough_skin.tres` (**New Resource → Perk**). Set `id = &"tough_skin"`, `display_name = "Tough Skin"`, and expand `stat_bonuses` to one row: key `endurance`, value `2`.
2. In your level, drop an `Area3D` under the shrine `MeshInstance3D`, attach `perk_station.gd`. Leave `consume_on_use = true` and tick `auto_fit_collider` (or size the `CollisionShape3D` to the shrine).
3. Assign `perk = res://.../tough_skin.tres`.
4. Run. The hover reads **"Learn: Tough Skin"**; pressing E toasts **"Learned: Tough Skin"**, adds +2 endurance with its max-HP bump, and the station frees itself.

**For a perk tree**, author a second `Perk` — say `iron_hide.tres` — with `requires_perks = [&"tough_skin"]`. Its station will refuse to grant (toasting "Already learned"/no-op) until the player has learned Tough Skin first, then unlocks normally.

**Gotchas**

- **`stat_bonuses` keys must be exact `CharacterStats` names.** `strength` / `persuasion` / `gunplay` / `endurance` / `streetwise` / `agility` only — any other key (a typo, a made-up stat) is silently dropped and grants nothing. There's no error; the perk just does less than you intended.
- **The perk picker doesn't exist yet.** `LevelUp`'s `available_perks` / `perk_points_per_level` exports are authored-ahead data only — placing perks there does nothing in-game today. Use a `PerkStation` to actually hand out a perk.
- **One grant per perk id.** Re-interacting (or a second station with the same `perk`) is a no-op — the manager tracks owned ids and `can_unlock` returns false. Set `consume_on_use = false` only if you *want* the shrine to stay (it still won't double-grant).
- **You don't place the `PerkManager`.** It auto-creates under the player on first use. Don't pre-add a node named "Perks" by hand.
- **No `.tscn` ships.** Build the station like an `UpgradePickup` — bare node + script — and remember to size/fit its hitbox, or E will do nothing.

Relevant files: `rpg/scripts/player/perk.gd`, `rpg/scripts/components/perk_station.gd`, `rpg/scripts/components/perk_manager.gd`, `rpg/scripts/components/level_up.gd`.

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

Relevant files: `rpg/scripts/dialogue/dialogue_manager.gd`, `rpg/scripts/dialogue/companion_recruiter.gd`, `rpg/scripts/components/merchant.gd`, `rpg/scripts/components/stock_entry.gd`, `rpg/scripts/components/healer.gd`, `rpg/scripts/components/bonfire.gd`, `rpg/scripts/components/level_up.gd`, `rpg/scripts/npc/npc.gd` (the companion contract: `can_recruit` / `start_following` / `stop_following` / `is_following`), `rpg/scripts/npc/companion_follow.gd`.

---

## Quests and the Journal

Quests in CYBER SUNDAY are pure authored data plus a handful of auto-firing hooks — there is **zero per-level wiring**. You write a **`Quest`** `.tres` (an ordered list of objectives + the rewards on completion), start it from a dialogue option or a trigger, and the rest happens by itself: the matching gameplay events advance objectives, the quest auto-completes, the player gets paid, and the **Journal** (press **J**) shows the whole thing live. Like `LevelUp` and reputation, it is `GameState`-driven — you call the autoload, you never touch its code.

### 1. The Quest Resource (`res://scripts/quests/quest.gd`)

A **`Quest`** (`class_name Quest`, an `@tool` `Resource`) is the whole quest. Create one with **right-click in the FileSystem → New Resource → Quest**, save it under `res://resources/quests/`, and fill these fields:

**Identity & Display**
- **`id`** (StringName) — the stable lookup key, unique per `.tres` (e.g. `&"clear_outpost"`). `GameState` keys everything off this; an id-less quest is silently refused by `start_quest`.
- **`title`** (String) — the header shown in the Journal.
- **`description`** (multiline) — flavour / detail text.
- **`objectives`** (`Array[QuestObjective]`) — the ordered steps (see §2). Set the array size, then drop a `QuestObjective` into each row.

**Rewards (on completion)**
- **`rewards`** (`Array[ItemStack]`) — items handed to the player when the quest finishes. Count-based rows, same `ItemStack` seeding the loot pipeline uses everywhere (weapons seed as unique instances, stackables stack).
- **`reward_money`** (float, default `0.0`) — zorkmids credited to the wallet on completion. Fractional allowed.
- **`reward_reputation`** (Dictionary — faction id → delta) — **authored but NOT granted yet.** You can fill it, but this slice only pays out money + items; the reputation grant lands when faction-id resolution does. Don't rely on it.

**Flow**
- **`auto_complete`** (bool, default `true`) — finish + pay out the instant every non-optional objective is met. Turn it **off** to require an explicit turn-in (a `GameState.complete_quest(id)` call, e.g. from a "hand in the quest" dialogue option).
- **`giver_npc`** (String) — the quest-giver's display name, **informational only** for the UI. It does not wire anything up.

### 2. The QuestObjective Resource (`res://scripts/quests/quest_objective.gd`)

Each **`QuestObjective`** (`class_name QuestObjective`, also an `@tool` `Resource`) is one step. Author it inline in the quest's `objectives` array:

- **`id`** (StringName) — stable id, unique **within this quest**. This is the key `advance_objective` and the progress queries use.
- **`description`** (multiline) — the line shown in the Journal (e.g. "Kill the boss"). Blank falls back to the raw `id`.
- **`type`** (enum `Type { KILL, TALK, PICKUP, ENTER_AREA, USE_ITEM, FLAG }`, default `FLAG`) — what completes it. This decides which auto-hook (if any) fires it.
- **`target_id`** (StringName) — **what to match**, and its meaning depends on `type`:
  - `KILL` / `TALK` → the NPC's **`display_name`**
  - `PICKUP` / `USE_ITEM` → the **`Item.id`**
  - `ENTER_AREA` → the **area / group name**
  - `FLAG` → the **`GameState` flag name**
- **`required_count`** (int, default `1`, range `1..9999`) — how many times it must fire (e.g. "kill 5 raiders"). Progress clamps to this.
- **`optional`** (bool, default `false`) — a bonus goal. An optional objective does **not** block the quest from completing — only the required ones gate `auto_complete`.

> **Matching is string-exact.** `target_id` is compared verbatim against the live `display_name` / `Item.id`. A typo'd target (`&"Raider Boss "` with a trailing space, `&"raider boss"` lower-cased) silently never advances — the objective just sits at `[ ]` forever with no error. This is the #1 quest footgun; copy the value from the actual NPC/Item resource, don't retype it.

### 3. The GameState API

You drive quests through three calls on the **`GameState`** autoload (`res://managers/GameState.gd`):

- **`GameState.start_quest(quest)`** — begin tracking. No-op if `quest` is null, id-less, already active, or already completed (so calling it twice from a repeatable dialogue is safe). Seeds every objective to 0, emits `quest_started`.
- **`GameState.advance_objective(quest_id, objective_id, amount := 1)`** — bump one objective toward its `required_count` (clamped). When the quest `auto_completes` and every non-optional objective is met, it completes itself. No-op for an unknown quest/objective.
- **`GameState.complete_quest(quest_id)`** — finish a quest explicitly (the turn-in path for `auto_complete = false`). Moves it to the completed list, grants the rewards, emits `quest_completed`.

Signals (the Journal listens to these; you can too): **`quest_started(quest)`**, **`objective_advanced(quest, objective)`**, **`quest_completed(quest)`**.

Completion **automatically** pays out `reward_money` (via the player's wallet) and seeds `rewards` (items) into the player's inventory. (Off-tree / in a bare test with no player in the world, the grant is a safe no-op.)

### 4. The auto-hooks (what fires objectives for free)

Four objective types advance **by themselves** when the matching gameplay event happens — you never call `advance_objective` for these:

- **`KILL`** — fires on a player-attributed NPC death, matched by the dead NPC's `display_name`.
- **`PICKUP`** — fires when a `CanPickUp` grant succeeds, matched by `Item.id`.
- **`TALK`** — fires when `DialogueManager.start` runs with a named speaker, matched by that speaker name.
- **`FLAG`** — fires from **`GameState.set_flag(name)`**: setting a flag auto-advances any active objective with `type = FLAG` and a matching `target_id`. (This is how you wire a quest to the flag/trigger system — set a flag, the objective ticks.)

The remaining two have **no auto-hook**:

- **`ENTER_AREA`** and **`USE_ITEM`** advance **only via a manual `GameState.advance_objective(...)` call** — e.g. a `TriggerVolume` action that fires `advance_objective(&"my_quest", &"reach_roof")` when the player enters the zone, or a use-item callback for `USE_ITEM`.

### 5. The Journal (`res://scripts/ui/quest_journal.gd`)

The Journal is a `CanvasLayer` autoload bound to the **J** key (`InputManager.action_journal`) — read-only, code-built, with **no class_name** and nothing to place in a level. It is the **4th Pip-Boy tab** after Inventory / Stats / Reputation, and like the other player menus it frees the cursor but **does not pause the world**.

Press **J** and it lists every **active** quest (title + a line per objective) and a **completed** list below. Each objective line reads `[ ]` / `[x]`, shows an **`(n/m)` progress count only when `required_count > 1`**, and tags optional goals with **`(optional)`**. It refreshes live off the three quest signals while open — kill the boss with the Journal up and you watch the line flip.

### Worked example: "Clear the Outpost"

> Goal: a quest that pays 200 zm + 5.56 ammo for killing a named boss, with an optional intel-document side find.

1. **Author the quest.** Right-click `res://resources/quests/` → New Resource → **Quest**, save as `clear_outpost.tres`. Set:
   - `id` = `&"clear_outpost"`
   - `title` = `Clear the Outpost`
   - `auto_complete` = `true`
   - `reward_money` = `200.0`
   - `rewards` → size **1**: `[0]` item = your 5.56 ammo `Item` `.tres`, count = `5`
2. **Add the kill objective.** Expand `objectives`, size **2**, drop a `QuestObjective` into `[0]`:
   - `id` = `&"kill_boss"`, `description` = `Kill the boss`
   - `type` = `KILL`
   - `target_id` = `&"Raider Boss"` — this **must equal** the boss NPC's `display_name`, character-for-character
   - `required_count` = `1`
3. **Add the optional loot objective** in `[1]`:
   - `id` = `&"loot_intel"`, `description` = `Recover the intel`
   - `type` = `PICKUP`
   - `target_id` = `&"intel_doc"` — the **`Item.id`** of the intel document
   - `optional` = `true`
4. **Start it.** From a dialogue option (or any script), call `GameState.start_quest(load("res://resources/quests/clear_outpost.tres"))`.
5. **Play it.** Kill the `Raider Boss` → the `KILL` hook fires, `kill_boss` is the only required objective, so the quest **auto-completes and pays out** (200 zm + 5 rounds of 5.56) on the spot. The optional intel pickup ticks whenever the player grabs the `intel_doc` (before or after), but never gates completion. Press **J** to watch `[ ] Kill the boss` flip to `[x]` and the quest drop into the completed list.

### Gotchas

- **`target_id` must EXACTLY match the live `display_name` / `Item.id`.** Matching is string-exact and silent on failure — a wrong case, trailing space, or stale name just never advances. Copy from the source resource.
- **`ENTER_AREA` and `USE_ITEM` have no auto-hook.** They advance only via a manual `GameState.advance_objective(...)` call — usually a `TriggerVolume` action for area entry. Authoring the objective alone does nothing for those two types.
- **`reward_reputation` is not granted yet.** You may author it, but this slice pays out money + items only; the reputation delta is held until faction-id resolution lands.
- **Quest progress is not save-persisted yet.** Active/completed quests live in `GameState` for the session only — a reload starts them fresh. A Quest-id registry (so saves can round-trip quest state) is the planned follow-up; don't build a quest that assumes mid-quest reloads work.
- **Turn-in needs `auto_complete = false`.** Leave it on and the quest finishes the instant the last required objective ticks. For a "report back to the giver" beat, turn it off and call `GameState.complete_quest(id)` from the turn-in dialogue option.
- **`giver_npc` is cosmetic.** It does not make an NPC offer or track the quest — starting a quest is always an explicit `start_quest` call.

Relevant files: `res://scripts/quests/quest.gd`, `quest_objective.gd`; the live API + auto-hooks in `res://managers/GameState.gd`; the read-only log in `res://scripts/ui/quest_journal.gd`; author quests under `res://resources/quests/`.

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

**What triggers it:** any NPC in the `npc` group that reports `is_in_combat()` (ALERTED *with a live target* â€” an active fight only; once a fight breaks line-of-sight and the enemy drops to INVESTIGATING to hunt your last-known spot, the score fades and the search plays in tense silence), OR `DialogueManager.is_active()`. The combat scan runs on a fixed 0.3 s interval (a `POLL_INTERVAL` const, not a tunable). Gotcha worth knowing: if the music node's authored Volume dB is at or below `silent_db`, the fade is a no-op â€” `MusicDirector` will push a warning and drop the floor 20 dB to keep it working, but the clean fix is to raise the node's volume.

### 2. The in-world radio (`Radio`)

`Radio` (`rpg/scripts/components/radio.gd`) is a `LookAtInteractable` â€” the player aims at it and presses Interact to toggle it on/off. While on, it **ducks out during combat and dialogue** and breathes back in afterward (the inverse of `MusicDirector`). It cycles a **folder of tracks** out of a spatial `AudioStreamPlayer3D` â€” truly in-engine, positional, diegetic music, classic-radio style: it auto-advances when a track ends and loops the folder (with an optional per-radio shuffle). An empty/unset folder falls back to a single shipped `fallback_audio` track.

**Setup**
1. Drop a `Radio` node under (or onto) your radio prop. Because it extends `LookAtInteractable`, set **`highlight_target`** to the mesh you want the hover-outline on (defaults to the parent), and size the node's `CollisionShape3D` to the body the player aims at â€” or turn on **`auto_fit_collider`** to auto-fit the hitbox at runtime.
2. Set **`radio_name`** (blank â†’ "radio" in the hover label).
3. Point **`music_folder`** at a folder of `.mp3`/`.ogg`/`.wav` tracks (defaults to the shipped `res://assets/audio/music`). The radio scans it on turn-on and plays through it. Set **`shuffle`** for a per-radio-deterministic random order. Leave **`audio_player`** unset to auto-create a child player on the `music` bus.
4. Optionally assign **`fallback_audio`** â€” a single shipped track used only when `music_folder` has no audio files (so a radio is never accidentally silent).
5. Optionally set **`click_on`** / **`click_off`** (a physical clunk on toggle) and **`click_volume_db`**; these auto-route to the `sfx` bus through a separate `click_player`, so the combat duck never touches them.

**The player's own music (Options â†’ Audio â†’ Music Folder):** the player can point a directory picker at *their own* folder of tracks; that override (`Settings.music_folder`) wins over **every** radio's `music_folder` until they clear it ("Default"). A `res://` folder is loaded through the import pipeline; an outside folder (their Music directory, a `user://` path) is decoded from raw file bytes at runtime (mp3/ogg/wav). Undecodable files are skipped.

**Combat-duck fields:** `combat_strict` (false = duck through the whole hunt, *including* the INVESTIGATING search phase â€” unlike the music; true = only during an active ALERTED firefight, matching the `MusicDirector`), `poll_interval` (0.3 s), `settle_cooldown` (3.0 s ducked after the last enemy disengages), `fade_pause_time` (0.4 s out), `fade_resume_time` (1.2 s back in), `silent_db` (-60.0), `fallback_volume_db` (0.0). The duck/settle brain is the pure `RadioPlaybackState`; the track ordering is the pure `MusicPlaylist`.

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

### 5. The boot intro quote (`BootQuotes`)

After the loading screen and before the world fades in, the start menu plays a short intro: a black screen, a **random quote** fading slowly in then out. The quotes are authored content â€” no code. They live in a **`BootQuotes`** resource (`res://resources/ui/boot_quotes.tres`, `class_name BootQuotes`) holding a `quotes: Array[BootQuote]`; each `BootQuote` (`res://resources/ui/boot_quote.gd`) is two fields: `text` (the line) and `attribution` (the source/byline, optional). `start_menu.gd` loads the `.tres` at runtime and picks one at random per boot, so add a row and it's in the rotation. (A `FALLBACK_QUOTE` const covers a missing/empty resource, so the intro never blanks.)

**To add a quote:** open `boot_quotes.tres`, grow the `quotes` array, and fill a new `BootQuote`'s `text` + `attribution`. Save â€” it's live next boot.

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

## Map and minimap

A minimap is two pieces: a **`MapData`** Resource that says *what the level looks like from above and which world area that picture covers*, and a **`Minimap`** `Control` on the HUD that draws it plus live dots for the player and flagged NPCs. You author the Resource and place the Control yourself — there's no shipped prefab or `.tres` for this yet.

### The MapData Resource (`res://scripts/ui/map_data.gd`)

A `MapData` (`class_name MapData`, `@tool` `Resource`) pairs a top-down image with the world rectangle it spans, so the minimap can project any world position onto the image. Create one with **right-click in the FileSystem → New Resource → MapData** and fill:

- **`map_texture`** (`Texture2D`) — a top-down render of the level. This is the image the minimap draws.
- **`world_bounds`** (`Rect2`, default `Rect2(-50, -50, 100, 100)`) — the **world area the texture covers**. It's a top-down projection, so the rect's `x` / `width` map to the world **X** span and its `y` / `height` map to the world **Z** span (in world units); **world Y is ignored**. Get this right or every dot lands in the wrong place — it's the whole projection.
- **`player_marker`** (`Texture2D`) — optional icon drawn at the player's position. Null → a cyan fallback dot.
- **`npc_marker`** (`Texture2D`) — optional icon drawn at each flagged NPC. Null → a red fallback dot.

### The Minimap Control (`res://scripts/ui/minimap.gd`)

A `Minimap` (`class_name Minimap`, `extends Control`) draws the `MapData` and the markers. Add it to the HUD (`res://scenes/player/ui.tscn`) and assign:

- **`map_data`** (`MapData`) — the level's authored map. Null → it draws nothing.
- **`marker_radius`** (`float`, `4.0`) — radius of the **fallback dot** drawn when a marker `Texture2D` is null.

It reads the player from the **`"player"` group** (cyan fallback dot) and NPC markers from the **`"minimap"` group** (red fallback dot), projecting each through `MapData.world_to_uv`. It only redraws while it's visible, so a hidden minimap costs nothing.

**Worked example — a minimap for the back-alley level**

> Goal: a top-right minimap showing the player and a couple of patrolling guards.

1. Render the level top-down and save the image. Create `res://resources/maps/alley_map.tres` (a `MapData`); set `map_texture` to that render.
2. Measure the level's X/Z extent and set `world_bounds = Rect2(-60, -40, 120, 80)` — i.e. world X from −60 to +60, world Z from −40 to +40.
3. Open `res://scenes/player/ui.tscn`, add a **`Minimap`** `Control` in a corner (anchor it top-right, give it a size), and set `map_data = alley_map.tres`.
4. Play. The player shows as a **cyan dot**. Any `Node3D` you put in the `&"minimap"` group shows as a **red dot** at its projected position.

**Gotcha**
- **Nothing joins the `"minimap"` group automatically yet.** The per-NPC `show_on_minimap` flag is a planned follow-up, so today an NPC only appears on the minimap if you give it a manual `add_to_group(&"minimap")` (e.g. from a small drop-in node or a trigger). The player dot works out of the box because the player is already in the `"player"` group.

---

## Stealth and detection

CYBER SUNDAY ships a full stealth layer -- a detection meter the player can read, enemies that see worse in the dark and hear worse through walls, noise lures, body discovery, and a bonus for striking the unaware. But **almost all of it is OFF by default**, on purpose: the global toggles ship `false` and the bonuses ship at `1.0` so a fresh scene plays exactly like the old non-stealth build. The pieces are real and already documented in their home chapters (perception in Â§5, the sneak/backstab multipliers in Â§10, `NoiseSource` in Â§11, the tuning resources in Â§12) -- what this chapter adds is the **map** and the **"switch it on" recipe**, because a designer reading top-to-bottom would never guess the layer exists.

### What the player sees: the detection readout

While the player is **crouched (sneaking)**, a small readout near the top of the screen rises through four tiers as the nearest enemy's awareness climbs:

- **HIDDEN** -- no enemy has any suspicion of you.
- **DETECTED** -- an enemy's detection meter is filling (it senses *something*).
- **CAUTION** -- an enemy had you and lost you, and is now actively searching (its last sighting went cold).
- **DANGER** -- an enemy has fully locked on / gone ALERTED.

It is driven automatically from each enemy's `Perception` awareness (ALERTED -> DANGER, INVESTIGATING -> CAUTION, DETECTING -> DETECTED, otherwise HIDDEN) -- there is **nothing to wire per level**. The player can hide the graded heat **bar** via the **"Show Detection Meter"** row in Options â€” it does not affect the four-tier text readout (which shows whenever you're crouched), and there is no always-on mode (even enabled, the bar only appears while you're crouched and sneaking). The meter fills faster the closer and more centred you are in an enemy's view, and slower at the edge of its cone or in shadow (see falloff + light below).

### The three things that let an NPC notice you (recap of Â§5)

Every NPC's senses are tuned through the NPC's **Perception** inspector group (Â§5, *Step 2*) -- the sight/hearing fields mirror onto its `Perception` child, while `search_sweep_rate` is read by the search behaviour:

| Field | What it does |
|---|---|
| `sight_range` / `fov_degrees` | how far and how wide the vision cone reaches |
| `crouch_sight_mult` | how much a **crouched** player's effective visibility shrinks (your reward for sneaking) |
| `eye_height` | where the line-of-sight ray starts (peeks over low cover) |
| `time_to_detect` / `forget_time` | how long a sighting takes to become a lock, and how long a lost target is hunted |
| `hearing` | whether this NPC can hear noise at all (the gate for everything below) |
| `search_sweep_rate` | how fast it sweeps its gaze while hunting a lost target |

These are the **per-NPC** dials. The switches that turn the *systemic* behaviours on are global, and they ship off:

### Turning the stealth layer ON (the inert-by-default recipe)

Open `res://resources/tuning/NpcAiSettings.tres` (the `GameSettings.npc_ai` page, Â§12) and flip the **Stealth** group flags you want, then playtest:

| Flag (`npc_ai.*`) | Default | What turning it ON does |
|---|---|---|
| `body_discovery` | `false` | Every NPC death leaves a discoverable **Corpse** marker; an UNAWARE NPC that *sees* a body (LOS) investigates it and calls out -- so a quiet kill can blow your cover. |
| `hearing_initiates` | `false` | A noise can pull an NPC that **hasn't** spotted you into investigating it -- a guard reacts to a gunshot or a thrown decoy even while neutral. Without this, noise only matters once you're already a target. |
| `hearing_occlusion` | `false` | Walls **muffle** sound: a noise behind solid geometry is attenuated by `hearing_wall_attenuation` (0..1) -- a decoy through a doorway carries, one behind a wall doesn't. (`hearing_source_skip` keeps the noise's own body from counting as a wall.) |
| `distraction_scan_interval` | `0.3` | How often a no-target NPC rescans the noise/corpse channels (only matters once `hearing_initiates` or `body_discovery` is on). |

Then two more surfaces, in their own files:

- **The hunt** -- `res://resources/tuning/SearchSettings.tres` (`GameSettings.search`, Â§12) ships inert (`max_search_radius` 0, `sample_points` 1 = a single-point stare). Raise `max_search_radius` and `sample_points` to turn a lost-target search into a real breadcrumb sweep (uncertainty ring grows over time, intensity ramps from frantic to resigned).
- **The reward** -- on each `WeaponData` (Â§10, *Damage* group), `sneak_attack_multiplier` (hitting an un-alerted enemy) already ships at `2.0` -- a built-in bonus -- while `backstab_multiplier` (hitting one from behind) ships inert at `1.0`, with `backstab_arc_degrees` at `90.0` (the rear quarter that counts as a backstab). Raise the multiplier to make striking from stealth pay off harder. There is **no dedicated takedown key** -- the bonus rides the normal attack when the victim is off-guard / in the arc.

### The player's stealth tools

- **Crouch** (the Crouch keybind; tuned by `GameSettings.player_crouch`, Â§12) shortens your silhouette, **shrinks your noise radius toward zero** (fully crouched movement is near-silent), quietens your footstep audio, and triggers the enemy `crouch_sight_mult` discount. This is the core verb.
- **Stay out of an enemy's front cone and out of the light** -- distance/angle falloff and the light/shadow modifier both slow how fast the detection meter fills (defaults are behaviour-preserving; designers tune them via the perception falloff curves / light settings).
- **`NoiseSource`** (Â§11 catalogue) -- drop one as an ambient lure (a beeping machine) or to mark a decoy point; NPCs with `hearing` walk to investigate the loudest one. **Inert unless `hearing_initiates` is on.**

### Worked example: a guard you can sneak past -- and punish

1. Place an NPC (Â§5) with a combat profile; give its **Perception** a tight `fov_degrees` (say `90`) and a `crouch_sight_mult` around `0.4` so crouching roughly halves how far it can spot you.
2. In `NpcAiSettings.tres`, turn on `hearing_initiates` and `body_discovery`. (Add `hearing_occlusion` if the level has interior walls.)
3. In `SearchSettings.tres`, set `max_search_radius` to a few metres and `sample_points` to `4`+ so a guard that hears you actually sweeps the area instead of staring at one spot.
4. On the player's pistol `WeaponData`, raise `sneak_attack_multiplier` from its `2.0` baseline to `4.0` and `backstab_multiplier` from `1.0` to `8.0` with a `backstab_arc_degrees` of `120` -- now an unaware or behind-the-back hit is a one-shot.
5. Drop a `NoiseSource` (radius ~`8`, a short `decay`, `lifetime` `0` for a one-shot when thrown, or persistent for an ambient lure) where you want to pull the guard.
6. Run it: crouch-walk past the cone, lob the lure to pull the guard off his route, strike from behind. Leave the body in his patrol path and watch the next guard discover it.

### Gotchas

- **Inert-by-default is intentional.** Every `npc_ai` Stealth flag and the `SearchSettings` defaults reproduce the old non-stealth behaviour byte-for-byte (the one exception is `sneak_attack_multiplier`, which already ships at `2.0`). If a stealth feature "does nothing," you almost certainly haven't flipped its global flag -- turn it on, **then** playtest.
- **`hearing` is the master gate.** An NPC with `hearing` off ignores every noise system (decoys, gunfire alerts, occlusion) no matter what the global flags say.
- **Companions are exempt from distraction.** An NPC following a leader won't wander off to investigate noise -- only free agents do.
- **Body discovery needs line of sight**, not just proximity, and each corpse carries a permanent `discovered` latch -- the first NPC to spot a body claims it (one investigation per corpse, not one per passing NPC).
- **Crouch hides you in plan, not in elevation** -- by design, crouching never makes you harder to see from above/below, only across the floor.
- **Occlusion costs rays.** `hearing_occlusion` casts a few rays per heard source; it only runs when hearing is active, but keep `max_occlusion`-style scenes in mind on dense interiors.

Key files: `rpg/scenes/enemies/perception.gd`, `rpg/scripts/player/noise_emitter.gd`, `rpg/scripts/player/crouch.gd`, `rpg/scripts/player/stealth_status.gd`, `rpg/scripts/components/noise_source.gd`, `rpg/scripts/npc/goap/actions/goap_action_search.gd`; tuning under `res://resources/tuning/` (`NpcAiSettings.tres`, `SearchSettings.tres`, `DistractionSettings.tres`, `PlayerCrouchSettings.tres`).

---

## Tuning NPC behaviour (GOAP profiles)

Every NPC's brain is a **GOAP planner** (Goal-Oriented Action Planning) -- there is no state-machine to edit. Out of the box it already does the sensible thing (chase, shoot, take cover, investigate, flee when hurt), so **most NPCs need nothing here -- leave `goap_profile` null**. When you want an archetype to behave *differently* -- a coward who bolts at the first shot, a berserker who never runs -- you author one small resource and the planner re-weights itself. No code, all dropdowns.

### How the brain decides

Each frame the planner picks the **highest-priority goal it can currently pursue**, then plans the **cheapest sequence of actions** that satisfies it. So behaviour is shaped by two numbers per item: a goal's *priority* and an action's *cost*.

The shipped goals, in default priority order (higher wins):

| Goal | Default priority | What the NPC is trying to do | Serving action(s) |
|---|---|---|---|
| `Survive` | `3.0` | get to safety when threatened/hurt | `Flee` |
| `Engage` | (between) | fight the current target | `FireArmed` / `FireUnarmed` |
| `Investigate` | (between) | walk to a last-known / noise / corpse point and sweep it (the stealth search, Â§17) | `Investigate` |
| `Detect` | (between) | close the gap from "senses something" to a confirmed lock | `Detect` |
| `Idle` | `0.1` | no target: hold position / wander the idle floor | `Hold` |

`Survive` outranks `Engage` only when the NPC actually needs to flee; that ordering is what the levers below tilt.

### Authoring a `GoapProfile`

1. In the FileSystem dock, **right-click `res://resources/` â†’ New Resource â†’ `GoapProfile`** and save it next to your `NpcData` archetypes (e.g. `coward.tres`).
2. Drop it on the archetype's **`NpcData.goap_profile`** slot (it travels with the profile), or directly on a single NPC instance's **`goap_profile`** export (the **Profile** group â€” the "AI (GOAP)" label is the `NpcData` resource's). A value on the `NpcData` stamps onto the instance at spawn.

It has **two live levers**, both authored as dropdown rows so the goal/action name is always picked from a real list (no free-text to mistype):

- **`goal_priorities`** -- rows of `{ goal, priority }`. Each **replaces** that goal's default priority for this archetype. *This is the main lever.* Raise **`Survive`** above `Engage` (e.g. `5.0`) â†’ a coward that flees the moment it's threatened; drop it to `0.0` â†’ a fearless fighter that never runs.
- **`action_cost_overrides`** -- rows of `{ action, cost }`. Each **replaces** that action's planner cost (clamped `>= 0`). Costs break ties between alternative plans to reach a goal -- raise an action's cost to push the planner toward another route, lower it to prefer that action.

> The third field, **`goals`** (a subset filter), is **authored-but-reserved -- it is deliberately NOT applied yet**, because dropping a combat goal off a target-acquiring NPC would freeze it mid-fight. Leave it empty; use `goal_priorities` to shape behaviour instead.

Because each row is picked from a self-populating dropdown, an editor-authored profile can't name a goal/action that doesn't exist. (There is **no runtime check**, though: a profile built in *code* with a stale name would silently no-op -- `priority_for`/`cost_for` just fall through to the default -- rather than warn. `GoapProfile.validate()` exists for exactly this but is only called from tests, not at boot.)

### Worked example: a coward and a berserker

- **Coward raider:** new `GoapProfile`, add one `goal_priorities` row `{ Survive, 5.0 }`. Drop it on the raider's `NpcData`. It now flees as soon as it's threatened instead of trading shots.
- **Berserker:** new `GoapProfile`, add `goal_priorities` row `{ Survive, 0.0 }`. It never flees -- it fights to the death even at 1 HP.

Two resources, zero code, and every other behaviour (aim, cover, investigate) stays at the tuned defaults.

### Simpler per-instance overrides (heal / panic / provoke)

Three tiny drop-in components cover the most common per-NPC behaviour tweaks **without** a `GoapProfile` -- the planner handles the big picture, these handle the reflexes. Each is **auto-added** with behaviour-preserving defaults (so existing NPCs are unchanged); to override, drop a configured instance under the NPC's Enemy root, or set its `enabled` to `false` to suppress that reaction entirely.

| Component | What it controls | Key knobs |
|---|---|---|
| **`ProvokeOnAttack`** | whether the player attacking this NPC turns it hostile | `enabled` -- set `false` for **a shopkeeper / quest-giver you can shoot at without it ever aggroing** (it absorbs hits and keeps its disposition). A FRIENDLY ally instead forgives until cumulative player damage passes the NPC's `friendly_aggro_threshold`. |
| **`SelfHealer`** | whether the NPC spends a carried medkit mid-fight | `enabled` (off = never heals); `heal_at_hp_frac` (heal at/below this HP fraction -- higher = heals sooner); `cooldown_ms` (min ms between heals). Spends the same health packs its corpse would drop. |
| **`PanicOnDamage`** | whether a hurt NPC breaks and flees | `enabled` (off = holds its ground); `panic_scale` `[0..1]` (flee chance = this Ã— fraction of max HP lost; `0` = fearless). Auto-seeded from the NPC's `temperament`. |

So a **shootable shopkeeper** is just `ProvokeOnAttack.enabled = false`; a **brute that never flees or heals** is `PanicOnDamage.enabled = false` + `SelfHealer.enabled = false`; a **twitchy coward** is a high `panic_scale`. Reach for these before a `GoapProfile` -- they're one checkbox each.

### Gotchas

- **The default (null profile) is already good.** Only author a profile when you want a *distinct* archetype; don't bolt one onto every NPC.
- **Priorities are absolute replacements, not deltas.** A `goal_priorities` row sets that goal's priority outright -- judge it relative to the defaults in the table above (`Survive` `3.0`, `Idle` `0.1`).
- **`goal_priorities` is the strong lever; `action_cost_overrides` is the fine one.** A goal with only one serving action barely cares about cost, so reach for goal priority first.
- **`goals` does nothing yet** (see the note above) -- don't rely on it to make a non-combatant.

Key files: `rpg/scripts/npc/goap/goap_profile.gd`, `goap_goal_priority.gd`, `goap_action_cost.gd`, `goap_library.gd` (the goal/action name lists the dropdowns read), `goap_executor.gd`, `goap_planner.gd`; the planner is built per-NPC in `rpg/scripts/npc/npc.gd` (`_build_goap_goals` / `_build_goap_actions`). Per-instance reaction components: `rpg/scripts/components/provoke_on_attack.gd`, `self_healer.gd`, `panic_on_damage.gd`.

---

## NPC barks (combat & reaction lines)

NPCs shout short context lines -- **barks** -- as the fight unfolds: "Contact!" on spotting you, "I'm hit!" when wounded, "Murderer!" when they watch you kill an ally. Every NPC already ships with a full set of **default** lines, so you author nothing to get chatter. To give an *archetype its own voice* -- a raider that snarls, a corp guard that barks procedure -- you author a `BarkSet` and hang it on the `NpcData`.

> This is the WHICH-lines layer. Â§8 (dialogue / `VoiceData`) is the HOW-they're-spoken layer (the text-to-speech voice). They're independent: barks are picked here, then read aloud by the NPC's `VoiceData`.

### Authoring a `BarkSet`

1. In the FileSystem dock, **right-click `res://resources/` â†’ New Resource â†’ `BarkSet`**, save it (e.g. `raider_barks.tres`).
2. Fill **only** the categories you want to change. **Every category defaults to an empty array, which means "use this NPC's built-in default lines"** -- so a `BarkSet` overrides just the pools it fills and inherits the rest. Each pool is a list of strings; the NPC picks one at random when the moment fires.
3. Assign it to the archetype's **`NpcData.bark_set`** slot. (A null `bark_set` = the NPC uses every default line.)

The categories, grouped as they appear in the inspector:

| Group | Category | Fires when... | Example |
|---|---|---|---|
| **Combat** | `spot` | makes combat contact | "Contact!" |
| | `hurt` | wounded, low HP | "I'm hit!" |
| | `reload` | reloading | "Cover me!" |
| | `combat_end` | lost the target | "Where'd they go?" |
| | `lost_interest` | gave up an investigation | "Must've imagined it." |
| | `search` | actively hunting a lost target | "Where are you?" |
| | `flee` | broke and ran under fire | "Forget this!" |
| | `check_body` | spotted a dead body (Â§17) | "Hey -- a body!" |
| **Social** | `greet` | the player hovers/greets | "Hey there." |
| | `thanks` | the player assisted it | "Hey, thanks!" |
| **Death Reactions** | `death_ally` | a co-aligned peer was killed | "Murderer!" |
| | `death_approve` | a friendly approves an enemy's death | "Good riddance!" |
| | `death_question` | a bystander questions a death | "Was that necessary?" |
| **Player Aggression** | `warn_attack` | the player hit it but DIDN'T aggro it (see `ProvokeOnAttack`, Â§18) | "Cut that out!" |
| | `aggro` | the player's hit just flipped it hostile | "Alright, that does it!" |

### Muting a whole category (the three gates)

Emptying a pool *inherits* defaults -- it does **not** silence the NPC. To actually mute a reaction, use the three boolean gates on `NpcData` (they mute regardless of which lines are in the pool):

- **`damage_barks`** (default `true`) -- the `hurt` cry. Off = a stoic/disciplined archetype that takes hits silently.
- **`death_barks`** (default `true`) -- the death-witness reactions (`death_ally` / `death_approve` / `death_question`). Off = an NPC that ignores killings around it.
- **`search_barks`** (default `true`) -- the `search` call-out. Off = a silent stalker that hunts without giving away its progress.

### Worked example: a snarling raider that searches in silence

1. New `BarkSet` `raider_barks.tres`: fill `spot` with `["Contact!", "Got eyes on!"]`, `aggro` with `["Big mistake.", "You're dead."]`, `flee` with `["Screw this!"]`. Leave everything else empty -- those keep the default lines.
2. On the raider's `NpcData`: assign `bark_set = raider_barks.tres`, and set `search_barks = false` so it hunts you quietly.
3. Done -- the raider now has its own contact/aggro/flee voice, inherits the rest, and stalks lost targets without a peep.

### Gotchas

- **Empty pool = inherit defaults, NOT silence.** To silence a reaction, flip its `NpcData` gate; don't expect an empty array to mute it.
- **The gates are on `NpcData`, the lines are on the `BarkSet`** -- two different resources. You can mute `hurt` (gate) while still customising `spot` (BarkSet).
- **`warn_attack` vs `aggro` pair with `ProvokeOnAttack` (Â§18):** a `ProvokeOnAttack.enabled = false` shopkeeper uses `warn_attack` and never reaches `aggro`; a neutral that flips on the first hit jumps straight to `aggro`.

Key files: `rpg/scripts/npc/bark_set.gd`, `rpg/scripts/npc/npc_voice.gd` (resolves the pools + the gates), `rpg/scripts/npc/npc_data.gd` (the `bark_set` slot + the three gate flags).

---

## The player: HP, stats, and starting money

Most of this guide is about the world, but you'll also want to set the player's **starting build** -- how much punishment they take, their RPG stats, and their opening wallet. All three are plain inspector / resource edits; you make them on the **Player node in your game scene** (the `game.tscn` copy you author your level into -- see Â§2).

### Health

The player's health is `max_hp` on the Player (a `Character`), in the **Health & Stats** group. It ships at **`4.0`** -- the player is deliberately fragile, so a weapon's `1.0` damage is a quarter-bar. Raise it on the Player instance to make a tougher run. (`hp` seeds from `max_hp` at spawn and damage can never heal past it.)

### The stat sheet (`CharacterStats`)

Every `Character` -- player **and** NPC -- carries an optional RPG stat sheet in the same group: `stats`, a `CharacterStats` resource. **Baseline is `0` and neutral** (every derived multiplier is exactly 1.0), so a null or all-baseline sheet leaves balance untouched; a build matters only when a stat moves off `0`. To give the player a build: **right-click `res://resources/` â†’ New Resource â†’ `CharacterStats`**, set the six attributes, and assign it to the Player's `stats` slot.

| Attribute | Each point above `0`... | Consumed at |
|---|---|---|
| `strength` | +2.0 carry capacity | inventory weight cap |
| `endurance` | +1.5 max HP (stamped at spawn) | on top of `max_hp` |
| `persuasion` | buy 4% cheaper / sell 4% dearer (clamped); also gates dialogue checks | Merchant prices, Â§8 skill checks |
| `gunplay` | aim wander 8% steadier | weapon sway |
| `streetwise` | reputation gains 8% bigger, losses 8% smaller | Â§7 reputation |
| `agility` | +5% move speed and jump | player locomotion |

Negative values are legal and make the build *worse* on that axis. Dialogue skill checks (`DialogueChoice.required_stat`, Â§8) read these by name; the player sees the sheet on the **Stats** screen.

### Starting money

The fresh-game wallet is `player_starting_money` on `EconomySettings.tres` (`GameSettings.economy`, Â§12); the shipped resource default is **`0.0`**. Raise it for a richer start. Precedence: a **`SwapWeapons` Loadout** that sets starting money overrides this, and a **loaded save** wins over both (these values seed only a *new* game).

### Gotchas

- **HP and stats are per-instance on the Player node**, not a global setting -- set them in the `game.tscn` wrapper you build your level into, not in a tuning `.tres`.
- **Baseline-`0` stats change nothing.** An all-zero (or null) `CharacterStats` is identical to no sheet; only non-zero attributes shift balance. So you can hand the player a sheet and tune one stat without touching the rest.
- **`endurance` stacks on `max_hp`.** Final spawn HP is `max_hp` + the endurance bonus -- account for both if you want an exact number (a deeply negative `endurance` is floored so spawn HP never drops below 1).
- **A loaded save overrides these.** `player_starting_money` and a fresh stat build seed a *new* run; a continued save restores the player's saved money and stats instead.

Key files: `rpg/scripts/player/character.gd` (`max_hp` + the `stats` slot), `rpg/scripts/player/character_stats.gd` (the six attributes + their formulas), `rpg/resources/tuning/EconomySettings.gd` (`player_starting_money`).

---

## Limb and locational damage

Every `Character` -- player **and** NPC -- tracks the condition of four body zones (head, torso, arms, legs) and **cripples** a limb when it absorbs enough located damage. It's all tuned per-instance from the **Limb & Locational Damage** `@export` group on the Character.

A **located** hit (one that carries a hit point -- gunfire, a thrown prop -- but *not* fall damage or an explosion) is sorted into a zone by where it lands in the body's local frame: at/above `head_local_y` = head, below `leg_local_y` = legs, the torso band with `|x|` past `arm_local_x` = arms, otherwise torso. Each zone has a condition pool of `limb_condition_frac` Ã— the character's `max_hp`; drain it and that limb cripples (the **torso never cripples**).

| Zone | When crippled | Knob |
|---|---|---|
| Legs | moves slower (a Fallout-style limp) | `crippled_leg_speed_mult` (default `0.5`) |
| Arms | this character's shots spread wider | `crippled_arm_spread` (radians, default `0.06`) |
| Head | a stagger / concussion-feedback pulse | (overridable hook) |
| Torso | -- never cripples -- | -- |

Other knobs (all on the Character, so a tough-limbed brute vs. a fragile civilian is per-instance): `limb_condition_frac` (`0.6` -- how much located damage a limb absorbs before breaking), the zone boundaries `head_local_y` / `leg_local_y` / `arm_local_x`, and `cripple_sound` / `cripple_sound_volume_db` (the crack SFX -- a placeholder you can swap).

**Clearing it:** a `Healer` (Â§13) mends limbs for a price -- that's what its "limb-only heal where HP is already full" covers -- and a `Bonfire` (Â§13) rest full-heals HP **and** limbs. HP and limb condition are separate pools: `heal()` restores HP, `heal_limbs()` un-cripples.

### Gotchas

- **Only located hits cripple.** Fall damage and explosions hurt HP but never cripple a limb (they carry no hit point to locate).
- **It applies to NPCs too.** The same group is on every NPC; a shot-out leg makes an enemy limp, and a crippled NPC cries "My leg!" (and toasts you when you did it).
- **Zones are local-frame**, so they track a leaning or rotated body -- a headshot stays a headshot mid-dodge.

Key files: `rpg/scripts/player/character.gd` (the Limb & Locational Damage group + `_apply_limb_damage` / `heal_limbs`); cleared by `rpg/scripts/components/healer.gd` and `bonfire.gd`.

---

## Saving, checkpoints and what persists

The game uses a **Dark-Souls-style single autosave** -- one slot, no manual saves. The run persists to `user://gamestate.cfg`, so quitting and relaunching resumes where you left off; the start menu's **Continue** button appears whenever that file exists.

**What the autosave carries (the run profile):**

- the player's **money** (zorkmids),
- the six **stats**,
- **unlocked mechanics** (abilities granted by `UpgradePickup`),
- **faction reputation** (the global standings, Â§7),
- the **backpack** -- every stack by `Item.id` plus its grid placement, and which stack is the drawn weapon,
- the **respawn point** (the last bonfire, or the initial spawn),
- the **story flags** set during the run (the `[flags]` world-state -- see **Story flags**; a New Game wipes them).

> Note: **quest progress is not yet persisted** -- active/completed quests live in `GameState` for the session only and start fresh on reload (a Quest-id registry is the planned fix; see **Quests and the Journal**).

**When it saves:** at each milestone -- a wallet change (kill bounty / trade / pickup), a level-up, an `UpgradePickup`, and a `Bonfire` rest. You never trigger a save by hand.

**Death doesn't reload the world.** You're brought back to life at the respawn point; enemies stay exactly as they were. Only the autosave survives *quitting*. So **placing a `Bonfire` (Â§13) is how you place a checkpoint** -- a rest sets the respawn point and autosaves.

**Fresh game vs. loaded save.** A loaded save **restores** the profile above and ignores your authored starting values. A **New Game** re-seeds them from the world: the `player_starting_money` knob (Â§20), the player's authored `CharacterStats` build (Â§20), and the starting `Loadout` (Â§10). In short -- *authored starting values seed a new run; the autosave overrides them on Continue.*

### Gotchas

- **An item with no `Item.id` can't be saved** -- it's skipped with a warning. Register every persistent item under `res://resources/items/` so it round-trips.
- **There is only one slot.** No manual saves, no multiple profiles; each milestone overwrites the autosave in place.
- **New Game doesn't delete the file immediately** -- the old save survives until the first autosave of the new run overwrites it, so starting a new game and quitting before any progress doesn't lose your prior run.

Key files: `rpg/managers/GameState.gd` (the whole model -- `save_to_disk` / `load_from_disk` / `capture` / `autosave` / `reset_for_new_game` / `set_respawn`).

---

## Destructible & throwable props (ThrowableData)

A crate you can shoot apart, a barrel, a gore gib -- any destructible / grabbable physics prop is a **`Throwable`** component (Â§11 catalogue) driven by a **`ThrowableData`** resource. `ThrowableData` is to a Throwable what `WeaponData` is to a weapon: one Throwable scene reskins into many object types purely by swapping the `.tres`. Author one with **right-click `res://resources/interactables/` â†’ New Resource â†’ `ThrowableData`** (the shipped examples are `wooden_crate.tres` and `gore_gib_data.tres`) and assign it to the Throwable's data slot.

The fields, by inspector group:

| Group | Fields |
|---|---|
| **Stats** | `max_hp` (hits before it breaks, default `5`); `mass` (kg -- heavier throws/falls with more momentum); `physics_material` (bounce/friction; null = the scene's default) |
| **Appearance** | `mesh` and `material` overrides (null = keep what the Throwable scene ships with) |
| **Audio** | `impact_sound` (hard knock), `destroy_sound` (on break) -- null = silent |
| **Destruction FX** | `destroy_particle_scene` (null = the default dust puff), `destroy_screen_shake` (camera kick, default `0.35`), `spawns_destroy_decal` (scorch on the floor -- gibs set this `false`) |
| **Behaviour** | `damages_player` (does a high-speed impact hurt the player -- gibs set `false` so your own kill's chunks can't chip you); `is_gib` (marks a gore chunk -- shooting one out of the air pops confetti instead of gore) |
| **Stealth** | `noise_on_land` -- when ON, a **thrown** copy drops a one-shot `NoiseSource` where it lands (the "lob a rock to distract a guard" verb, Â§17); `noise_radius` / `noise_decay` override the global `distraction` defaults per-prop (negative = inherit), and `noise_lifetime` likewise but inherits on `0`-or-negative too (a decoy is always one-shot, never persistent) |

### Gotchas

- **It's the `WeaponData` of props.** The same Throwable scene becomes a crate or a barrel by swapping the `.tres`, so build the scene once and vary the data.
- **The thrown-decoy noise needs the global flag.** `noise_on_land` does nothing until `GameSettings.npc_ai.hearing_initiates` is on (Â§17) -- it's the stealth distraction channel.
- **Gibs are throwables too** (`is_gib = true`): they skip the destroy decal, don't hurt the player, and pop confetti when shot mid-air.

Key files: `rpg/scripts/combat/throwable_data.gd`, `rpg/scripts/components/Throwable.gd`; example data under `rpg/resources/interactables/`.

---

## Reskinning the menus (`MenuSkin`)

The entire menu look -- the start menu and every in-game modal (inventory, shop, loot, level-up) -- comes from **one** resource: `res://resources/ui/menu_skin.tres` (`class_name MenuSkin`). The **`MenuStyle`** autoload reads it and builds the live `Theme` every menu uses, so editing that one `.tres` in the inspector restyles the **whole UI** -- no menu code. (It's the menu counterpart of `EffectFactory` for VFX, Â§12.)

Open `menu_skin.tres` and edit, by group:

| Group | What it controls |
|---|---|
| **Background (full-screen menus)** | `background_texture` (drop a PNG for a custom start-menu backdrop), `background_scene` (an animated/shader background -- wins over the texture), `background_color` (the flat fallback) |
| **Backdrop (in-game modals)** | `backdrop_dim` -- the dim drawn over the world behind a modal (higher alpha = darker) |
| **Panel** | the menu-card chrome: `panel_color`, `panel_border_color` / `panel_border_width`, `panel_corner_radius`, `panel_content_margin`, or hand your own `panel_style` `StyleBox` to fully replace it |
| **Palette** | `text_color`, `text_dim_color`, `accent_color` (the single accent -- selection bar / focus / active tab / slider fill), `gold_color` (zorkmids), `danger_color`, `hover_tint`, `disabled_text_color` |
| **Typography** | `body_font` / `title_font` (null = Godot default), `title_size` / `header_size` / `body_size` / `hint_size`, `title_tracking`, and `uppercase_titles` (the tracked-uppercase look) |
| **Sounds** | `hover_sound`, `click_sound`, `ui_sound_volume_db` -- the menu hover/click SFX |

To restyle: edit the fields and save -- every screen updates next run. For a whole alternate theme, author a second `MenuSkin` `.tres` and point `MenuStyle` at it (`MenuStyle.set_skin`).

Key files: `rpg/scripts/ui/menu_skin.gd`, `rpg/scripts/ui/menu_style.gd` (the autoload that builds the Theme); the authored skin is `rpg/resources/ui/menu_skin.tres`.

---

## Troubleshooting (symptom â†’ fix)

A symptom-indexed entry point into the per-chapter gotchas. Find the row that matches what you're seeing; the fix and the chapter with the full detail are on the right.

| Symptom | Likely cause â†’ fix | See |
|---|---|---|
| A new field / script / dropdown doesn't appear in the inspector | The editor hasn't re-scanned -- it must reload before new `@export`s / `class_name`s show. Refocus the editor or reopen the scene. | Â§1 |
| My inspector edit is ignored at runtime | Three usual culprits: an `NpcData` **profile** stamps over inline NPC fields; the value is owned by **`Settings`/Options**, not `GameSettings` (it overwrites on boot); or **StarSky** re-pins the `WorldEnvironment`. | Â§5, Â§12, Â§2 |
| NPC won't walk / find a path | Its geometry isn't in the `navmesh` group, or the nav mesh wasn't re-baked after props changed. | Â§2 |
| The level has nothing to control | A level scene has no `Player` -- play through `game.tscn` (or your own Game wrapper). | Â§2 |
| A new audio / comfort / sensitivity option isn't in the Options menu | A `.tres` value alone never reaches Options -- it needs a `Settings.gd` `var`+setter **and** a `SettingSpec` catalog row. | Â§12 |
| A stealth feature does nothing | It's inert by default -- flip the matching `npc_ai` global flag, then playtest. | Â§17 |
| Two NPCs won't fight / an NPC ignores my faction | NPC-vs-NPC needs **both** factioned with a relation `< 0`; the `faction_id` filename is load-bearing. | Â§7 |
| Dialogue has no Trade / Heal / Rest / Follow option | The speaker needs the matching child component (`Merchant` / `Healer` / `Bonfire` / companion flag). | Â§13 |
| The radio is silent | It needs a `music_folder` **or** a `fallback_audio`, and music must sit on the `music` bus. | Â§15 |
| An item didn't survive a save | An item with no `Item.id` can't persist -- register it under `res://resources/items/`. | Â§22 |
| Pressing E does nothing on a prop | Its interaction hitbox is too small, or it isn't a `LookAtInteractable`. | Â§11 |
| Footsteps doubled on an NPC | A hand-added second `LocomotionFx` -- NPCs build their own; don't add one. | Â§15 |
| The detection readout never changes | The player must be **crouched** for the readout to show, and stealth detection tuning may be at defaults. | Â§17 |

---

## Glossary

The project's coined terms, defined once.

| Term | Meaning |
|---|---|
| **Zorkmids** | The in-game currency (fractional -- `0.5` is half a zorkmid). |
| **Bark** | A short, context-triggered spoken line ("Contact!", "I'm hit!") -- distinct from scripted dialogue. (Â§19) |
| **Drop-in component** | A `class_name` Node/Area3D with `@export` config you attach in a scene to add behaviour without code (the `LookAtInteractable` / `Ability` idiom). (Â§11) |
| **The three authoring surfaces** | Behaviour = a drop-in component; numbers = an `@export` or a `GameSettings` tuning `.tres`; content = an authored Resource. (Â§1) |
| **Profile / archetype** | An `NpcData` resource that stamps ~50 tuning fields onto an NPC at spawn, so one assignment makes a raider / townsperson. (Â§5) |
| **GOAP** | Goal-Oriented Action Planning -- the NPC brain. Each tick it pursues the highest-priority **goal** it can and plans the cheapest **actions** to reach it. (Â§18) |
| **Disposition** | How an NPC feels toward the player -- HOSTILE / NEUTRAL / FRIENDLY -- resolved from faction + reputation. (Â§7) |
| **`faction_id`** | The faction a `.tres` filename keys; it drives NPC-vs-NPC and NPC-vs-player attitude. The filename is load-bearing. (Â§7) |
| **Look-at interactable** | The `LookAtInteractable` family -- a prop you aim at and press Interact (E) to use. (Â§11) |
| **Standalone vs data-only** | A service component (Merchant / Healer / â€¦) that works on its own (`standalone`) vs. one that only supplies a dialogue option. (Â§13) |
| **Caliber** | A weapon's ammo type; ammo reserves connect to it. (Â§10) |
| **Footprint** | An item's grid size (`grid_width` Ã— `grid_height`) in the Tetris backpack. (Â§9) |
| **Inert-by-default** | A shipped feature whose global flag / defaults reproduce the old behaviour until you opt in (most of the stealth layer). (Â§17) |
| **Located / cripple damage** | A hit sorted into a body zone (head / torso / arms / legs); draining a zone's pool cripples that limb. (Â§21) |
| **Awareness states** | An enemy's perception ladder -- UNAWARE â†’ DETECTING â†’ INVESTIGATING â†’ ALERTED -- surfaced to the player as the detection readout. (Â§17) |
| **`GameSettings` vs `Settings`** | `GameSettings` = the designer's master tuning sheet; `Settings` = the player-overridable slice persisted to disk. (Â§12) |

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
| **Quests** | `res://resources/quests/` | `Quest` (+ sub `QuestObjective`) | `res://scripts/quests/quest.gd`, `quest_objective.gd` | Tracked on the **`GameState`** autoload; KILL/TALK/PICKUP/FLAG objectives auto-advance. Press **J** for the Journal. |
| **Status effects** | `res://resources/effects/` | `StatusEffect` | `res://scripts/combat/status_effect.gd` | Drag into `Item.consumable_effect`; a `StatusEffectManager` is auto-created on the player. Only `damage_per_tick` / `speed_multiplier` are live so far. |
| **Perks** | `res://resources/perks/` | `Perk` | `res://scripts/player/perk.gd` | Granted at a `PerkStation`; `PerkManager` applies the stat deltas. |
| **Cutscenes** | `res://resources/cutscenes/` | `Cutscene` (+ sub `CutsceneAction`) | `res://scripts/combat/cutscene.gd`, `cutscene_action.gd` | Run by a `CutscenePlayer`; locks player control while playing. |
| **Spawn definitions** | inline on an `EncounterSpawner` | `SpawnDefinition` | `res://scripts/combat/spawn_definition.gd` | One row per enemy group; fired by a `TriggerVolume` `action`. |
| **Map data** | `res://resources/maps/` | `MapData` | `res://scripts/ui/map_data.gd` | Drawn by a `Minimap` `Control` on the HUD. |

### Top gotchas

- **Reload the editor after adding new `@export` fields or a new `class_name`.** A newly added export won't show in the inspector â€” and a brand-new `class_name` the editor hasn't scanned yet can cascade into *"Could not find type X"* errors â€” until the editor reimports. Right after edits the editor may briefly yield empty PackedScenes or *"File not found"*; retry after a few seconds, it clears.
- **`.gd.uid` sidecars are tracked.** Commit each new script's `.gd.uid` alongside the `.gd`. If it's missing, `godot --headless --import` regenerates it. Do not orphan them.
- **Keep exactly one `BodyModelSwap` (one `body_model`) per NPC.** It hides the default `Man.glb` body/head and the runtime head-look + sniper-glint retarget to the swapped head. If you set `head_model`, **clear the NPC's own `head_scene`** â€” the component owns the head then.
- **A faction file's id must equal its filename.** `Factions` resolves a faction by loading `res://resources/factions/<id>.tres`, and `Reputation` keys on the file's **internal `id`**. If the `.tres`'s internal `id` doesn't match its filename you get a loud `push_warning` and two factions can silently merge into one rep pool. So `raiders.tres` must have `id = &"raiders"`.
- **Player-facing tunables must be wired into the Options menu *and* `Settings`.** A new tunable (volume, sensitivity, FOV, accessibility, screen-shake, ...) isn't done when the gameplay code reads it -- add a typed `var` + a `set_*` setter to the **`Settings`** autoload (`res://managers/Settings.gd`) and ONE `SettingSpec` row to `res://resources/settings/SettingsCatalog.tres` (the Options menu is data-driven -- no `options_menu.gd` edits). New keybinds additionally go in `InputManager.gd` + `project.godot [input]` + ONE `ActionSpec` row in `resources/input/ActionCatalog.tres` (NOT a `Keybind` `SettingSpec`).
