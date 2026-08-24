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

1. **Open a level.** Open `res://scenes/levels/TestLevel.tscn` (or `TestLevel_2.tscn`) from the FileSystem dock. This is a playground scene with ground, navigation, and a player spawn already wired -- a safe place to drop things. (The game itself boots at `res://scenes/computerroom.tscn` — the computer-room intro that hosts the start menu — set as the main scene.)
2. **Drop in an NPC.** Drag `res://scenes/characters/NPC.tscn` into the scene tree as a child of the level, then move it somewhere on the ground in the viewport. That single scene is *every* non-player actor in the game -- civilian to combatant -- driven entirely by the fields you set next.
3. **Give it a faction (its attitude).** Select the NPC and find the **Hostility** group in the Inspector. Set the **`faction_id`** dropdown to `townsfolk` -- now it resolves to the Townsfolk faction (`FRIENDLY` toward the player; it won't attack unless provoked). Pick `raiders` instead and it's `HOSTILE` on sight. (Leave `faction_id` empty and the standalone **`disposition`** field takes over -- `HOSTILE` / `NEUTRAL` / `FRIENDLY`.) While you're here, type a **`display_name`** under the Identity & Outline group -- it shows as the speaker label in dialogue. For a civilian, leave **`weapon_data`** (under Weapon) empty: no faction is needed to talk, only to fight.
4. **Give it something to say.** First make the conversation: in the FileSystem dock, right-click -> **Create New -> Resource -> `DialogueResource`**, save it as e.g. `res://resources/dialogue/greeter.tres`. Open it and add entries to its **`lines`** array -- each is a `DialogueLine` with a **`text`** field (leave `choices` empty for a line that just plays). Then drop `res://scenes/dialogue/talkable.tscn` as a child of your NPC, select that `Talkable`, and assign your `greeter.tres` to its **`dialogue`** field. (Leave its `display_name` blank and it borrows the NPC's.)
5. **Press Play.** Run the scene (F6 for the current scene). Walk up, **look at** the NPC (the Talkable is a look-at target, not a proximity trigger -- you have to aim at it) and press **E** to talk. A neutral townsperson will turn, face you, and read its lines; a raider will open fire instead.

That's the entire loop: a scene, a dropped component, a few Inspector fields, an authored Resource. Every feature in this guide is a variation on it.

**Gotchas**
- **A field or `faction_id` option looks missing?** Reload the project (Rule 2). New exports and `class_name` types don't show until Godot rescans.
- **NPC won't talk?** Talk is **look-at**, not walk-into-range -- aim the crosshair at the body and press F. Also check the `Talkable.dialogue` field is actually assigned, and that the NPC isn't `HOSTILE`/in combat (a fighting NPC refuses to talk -- it only fights).
- **Edited a `.tres` but nothing changed in-game?** Make sure you saved the Resource (Ctrl+S in its Inspector) and that it's the same file the node points at -- it's easy to edit one copy and reference another.
- **A profiled NPC's inline fields are overwritten by default.** If an NPC has an `NpcData` assigned to its `profile`, that archetype stamps ~50 fields at spawn and your inline overrides are ignored -- edit the archetype `.tres`, clear `profile` to tune inline, or tick `profile_fills_blanks_only` to keep your per-instance tweaks (additive merge).

## Contents

1. Orientation: how authoring works here
2. Building a level scene
3. Story flags (world-state)
4. Triggers, encounters & cutscenes
5. Placing and configuring NPCs
6. Customising an NPC look (body/head/limbs) — and the player character customizer
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
17. Quest markers and the compass
18. The day/night clock and NPC routines
19. Stealth and detection
20. Tuning NPC behaviour (GOAP profiles)
21. NPC barks (combat & reaction lines)
22. The player: HP, stats, and starting money
23. Limb and locational damage
24. Saving, checkpoints and what persists
25. Destructible & throwable props (ThrowableData)
26. Menus are scenes (authored .tscn screens)
27. Reskinning the menus (MenuSkin)
28. Troubleshooting (symptom → fix)
29. Glossary

_Plus six short utility chapters (unnumbered): **Editor dev-tools (the CYBER SUNDAY Tools plugin)** (right after Orientation), **Validating your content** (right after Quests), **Keeping the System Map in sync (architecture annotations)** (right after that), **In-game debug tools (console, cheat menu, noclip, inspector, logs)** and **Diagnosing AI & navigation — the debug overlay** (right before Troubleshooting), and **Quick reference** (at the very end)._

---

## Orientation: how authoring works here

Welcome. In CYBER SUNDAY you build the game the way you'd mod one: almost everything is done **inside the Godot editor** by placing nodes, ticking boxes in the **Inspector**, and editing `.tres` Resource files. You should rarely (ideally never) need to open a script. The whole project is built around a single rule, spelled out in `rpg/CLAUDE.md`: *every feature must be reachable without touching code.* When you want behaviour, you drop in a pre-made node; when you want to change a number, you edit an `@export` field or a tuning Resource; when you want new "stuff," you author a Resource. That's it.

### The three authoring surfaces

Everything you'll ever do falls into one of three buckets. Learn to recognize which one your task is, and you'll always know where to go.

**1. Behaviour → a drop-in component (a node you attach in-scene).**
A component is a node with its own `class_name` and a set of `@export` knobs. You drag it into your scene, point it at the thing it should affect, and configure it in the Inspector — no branching logic, no scripting. These live in `rpg/scripts/components/` (and their abilities in `rpg/scripts/components/abilities/`). Examples you'll use constantly: `LookAtInteractable` and its family (the ones that extend it — `CanPickUp`, `MoneyPickUp`, `ItemContainer`, `Merchant`, `LootableCorpse`, `Healer`, `Bonfire`, `Radio`, `UpgradePickup`), plus standalone drop-ins like `Lock`, `CanDestroy`, `SpawnOnDestroy`, and `Throwable`. The abilities (all extending `Ability`) — `Slide`, `WallClimb`, `Grapple`, `AirDash`, `FallImmunity`, `SilentTakedownAbility`, and `ChessVisualizer` — drop under the Player. Some ship as ready-made one-node scenes in `rpg/scenes/components/` (e.g. `container.tscn`, `merchant.tscn`, `radio.tscn`, `atm.tscn` — the drop-in ledger terminal — plus the ones in `scenes/components/abilities/`) so you can drag the whole thing in at once.

**2. Tunables → an `@export` field, or a tuning Resource on the GameSettings registry.**
There are two flavours of "numbers you tune":
- **Per-instance** tuning is an `@export` right on the component you placed — e.g. a `MoneyPickUp`'s `amount`, or a weapon's `pellet_count`. You change it only for that one node, in the Inspector.
- **Global** tuning lives in `rpg/resources/tuning/*.tres` — one Resource per system (`PlayerMovementSettings.tres`, `CameraSettings.tres`, `WeaponGeneralSettings.tres`, `EconomySettings.tres`, `ScreenShakeSettings.tres`, and so on). These are all registered on the **`GameSettings`** autoload, and code reads them as `GameSettings.<group>.<field>` (for example `GameSettings.camera.default_fov`). Edit the `.tres` and the change applies everywhere that system is used. (You'll also find player-facing options like volume, FOV, and sensitivity exposed in the in-game settings menu — but for design-time tuning, the `.tres` files are your home base.)

The golden rule: if a designer might ever want to tune it, it is **never** a hardcoded constant — it's an `@export` or a tuning Resource.

**3. Content → authored Resources (`.tres`).**
Content is the catalogue of "what exists": weapons, items, characters, throwables. Each is a Resource you create and fill in via the Inspector. They live under `rpg/resources/` by kind:
- `resources/weapons/` — `WeaponData` (e.g. `pistol.tres`, `shotgun.tres`, `melee.tres`)
- `resources/items/` — inventory `Item`s (`healthpack.tres`, `ammo_pistol.tres`, …)
- `resources/characters/` — `NpcData` archetypes + stat resources (`raider.tres`, `sniper.tres`, `Townsperson.tres`, `DefaultCharacterRes.tres`, `character_stats.tres`)
- `resources/interactables/` — `ThrowableData` (`wooden_crate.tres`, `gore_gib_data.tres` (shared by the meat chunks AND the body-part gibs))
- plus `resources/dialogue/` and `resources/factions/`

A `StockEntry`, `Loadout`, or `NpcData` is the same idea: data you author, then hand to a component via one of its `@export` slots (for example `Merchant.stock_counts` takes an `Array[StockEntry]`, `swap_weapons.gd` takes a `Loadout`, and `npc.gd` takes an `NpcData`).

### How it all fits in a scene

A level is a scene (`.tscn`) under `rpg/scenes/`. You'll see existing levels like `rpg/scenes/levels/TestLevel.tscn` and `rpg/scenes/levels/TestLevel_2.tscn`, plus building blocks in `scenes/components/`, `scenes/props/`, `scenes/characters/`, and `scenes/weapons/`. The flow is always the same: **drop a component node** (surface 1), **set its `@export` fields** (surface 2), and where it asks for content, **assign a `.tres`** (surface 3). Behaviour is composed from nodes, never hidden in a monolithic script — so you can add, remove, or rearrange features just by editing the scene tree. Most drop-in components also ship a ready-to-drag template under `scenes/components/` (e.g. `talkable.tscn`, `can_destroy.tscn`, `noise_source.tscn`): instance the `.tscn` to get the node pre-built with its collider/visual and `@export` wiring instead of assembling it by hand.

### A quick worked example: a coin the player can grab

1. Open a level scene, e.g. `rpg/scenes/levels/TestLevel.tscn`.
2. Add a child node and set its type to **`MoneyPickUp`** (a drop-in component — surface 1). With no model assigned it builds a default gold coin and auto-fits its own pickup hitbox (it sets `auto_fit_collider`), so a bare node already works.
3. In the Inspector, set **`amount`** to the value you want (this is the per-instance `@export` — surface 2). Optionally set `pickup_label`, or assign a `world_model` PackedScene to swap the coin for a custom mesh.
4. Play the level, aim at it, and press the interact key (**E**, the `PickUp` action) — it credits the player's wallet via `add_money`, updates the HUD money readout/floating gain indicator, plays its pickup sound, and removes itself.

No code was written: a node, an `@export`, done. If you instead wanted to change how the economy behaves broadly, you'd edit `resources/tuning/EconomySettings.tres` (surface 2, global). If you wanted a new kind of item to exist, you'd author a new `.tres` (surface 3).

### Opening and playing a level

The game's main scene is `res://scenes/computerroom.tscn` (set in `rpg/project.godot` under `run/main_scene`), so pressing **F5 (Run Project)** shows the startup internet warning first, with the computer-room timer/audio held silent behind it. After that gate clears, click to power the monitor on and the start menu (`res://scenes/start_menu.tscn`, instanced over the room by `scripts/ui/computerroom.gd`) fades in. While iterating on a specific level it's faster to open that level's `.tscn` in the editor and press **F6 (Run Current Scene)** — that launches the level you're looking at directly, skipping the menu.

### The #1 gotcha: the editor must reload before new fields/scripts appear

This will trip you up once, so internalize it now: **after you add or change `@export` fields, or add/modify a script or `class_name`, the editor needs to reimport/reload before the change shows up.** A brand-new component type may not appear in the "add node" list, a new `@export` may be missing from the Inspector, or a scene may momentarily look empty ("node count is 0") right after an edit. **This is not a bug.** As `rpg/CLAUDE.md` notes, right after edits the editor reimports and can briefly yield empty PackedScenes or "File not found" — give it a moment, or trigger a reload (re-focus the editor, or use *Project → Reload Current Project*), and the new fields and types appear. If something looks broken seconds after an edit, wait and retry before assuming you did anything wrong — it clears on its own.

**Gotchas**
- New component type not in the add-node list, or a missing `@export`? The editor hasn't rescanned yet — reload/reimport, don't re-author.
- Per-instance vs global tuning are different surfaces: an `@export` on the node changes only that one placement; a `resources/tuning/*.tres` change is global. Pick deliberately.
- Don't hand-edit a "number" in a script — if it's tunable it already lives on an `@export` or a tuning Resource. Find it there instead.
- Components are designed to work bare (sensible defaults, null-guards), so an unconfigured drop-in won't crash — but assign its content `.tres` and point its `@export` targets to get the behaviour you actually want.
- The interact verb is the `PickUp` input action (bound to **E**), not an action literally named "Interact" — keep that in mind if you go looking in the Input Map.
- **Q is a CONTEXTUAL key, and LEAN is what it falls back to.** `LeanLeft` shares Q with `Takedown` (which already doubled as the pet verb). `LeanRight` has E to itself — **Interact (`PickUp`) lives on F** — so the right peek is unconditional. On each PRESS the `Lean` component asks the Player whether any verb driver has a live target on an action bound to that same key (`Player.pending_verb_actions()` + `InputManager.actions_share_binding()`); if one does the verb takes the press, otherwise the lean CLAIMS the key for the whole hold and the verb drivers stand down (`Player.lean_owns_action()`). So: **aim at an unaware NPC and Q takes them down; aim at nothing and Q peeks left.** Two consequences for you as an author — (1) anything that makes an NPC takedown-able or pettable also silently takes Q away from the lean while you look at it, which is intended; (2) a player who rebinds Lean Left/Right onto their own keys in Options → Controls stops sharing, and those keys then lean unconditionally — which is exactly what moving Interact onto F did to the E side. Nothing hardcodes "E" or "Q".

Key paths to remember (all under the repo's `rpg/` folder): drop-in components → `rpg/scripts/components/`; global tuning → `rpg/resources/tuning/`; content Resources → `rpg/resources/<kind>/`; levels and building blocks → `rpg/scenes/`.

---

## Editor dev-tools (the CYBER SUNDAY Tools plugin)

The repo ships a project-specific editor plugin, **`addons/cybersunday_tools`**, that adds authoring tools
`@tool` scripts can't — viewport gizmos, a tabbed tool panel, inspector add-ins, and a toolbar. This is the
plugin this guide describes; third-party addons such as FuncGodot and GUT may also be enabled in the project.
Enable it once at **Project Settings → Plugins → "CYBER SUNDAY Tools" → ✔**.

If you are changing the plugin itself, use `docs/CYBER_SUNDAY_PLUGIN_QA.md` as
the acceptance checklist before calling the slice done.

> After you edit any plugin script, toggle it **off then on** in that same panel so the editor reloads the new code.

**Open the panel:** every tool below (except the gizmos, the inspector add-ins, and the toolbar) lives in **one**
collapsible bottom panel. Click the **CYBER SUNDAY** button in the editor's bottom bar (next to **Output** /
**Debugger**) to expand it; click it again to collapse. The panel is a single tab strip — switch tools by clicking a
tab title across the top. (It's a bottom panel on purpose: right-side docks force the editor taller and Godot
restores their saved sizes on relaunch, which squished the 3D viewport on short/HiDPI displays.)

The 24 tabs group into four jobs, plus the **Bridge** (see the end of this section).

**Create & edit content** — author `.tres` without ever touching the raw inspector:
- **Content** — one-click generators for EVERY content type: New Quest / NPC archetype / Weapon+Item pair / Item /
  Faction / Dialogue / LootTable / Perk / StatusEffect / Encounter / Schedule / Cutscene / BarkSet / Loadout /
  Grapple / Map / Throwable. Type a name → it writes a seeded `.tres` (`id` = filename),
  creates the folder if missing, refuses to overwrite, and opens it in the Inspector. The starting point for new content.
  (*New Throwable* writes a `ThrowableData` into `res://resources/interactables/` at the resource's own defaults with
  only `display_name` filled — `mesh` stays null on purpose, so you reskin it in the Inspector; see §25.)
- **Blueprints** — multi-resource "content packs" that the single-resource Content generators don't cover. Type a
  name → it previews the exact files it will create (live), then *Scaffold Enemy Pack* writes a CROSS-WIRED set in
  one click: a Faction + a Weapon+Item pair + a LootTable + an NpcData that references all three (faction_id /
  weapon_data / loot pre-linked). Refuses to overwrite any of the five; opens the NpcData. The faction ships
  HOSTILE (`default_disposition` — the field that drives player aggro; `relations` is NPC-vs-NPC only), so the enemy
  fights out of the box. Authoring a new enemy type in one action, not four.
- **Icons** — bake clean, consistent inventory icons for EVERY item (the in-tile live render frames small /
  inconsistently, and letter-glyph tiles read as placeholders). *Bake all item icons* renders each item to
  `res://resources/icons/<item.id>.png`, sized to its GRID FOOTPRINT (grid_w × grid_h cells): an item with a
  model uses it — a weapon's `WeaponData.view_model`, a `world_model`, or a `world_prop` scene (its scripts are
  stripped for the render, so full props like the dog crate bake safely) — and an item with NO model renders a
  procedural primitive stand-in (`icon_models.gd`: caliber-keyed cartridges for ammo, a medkit for healers,
  keyword-matched trinkets like scope / dog-tags / syringe / battery for the passives, a tinted pouch for anything
  unrecognised). Authoring a `world_model` (or `Item.icon`) on the `.tres` retires the stand-in on the next bake.
  The bake is TWO-PASS: a loose AABB framing, then a re-frame from the pixels that actually rendered, then an
  autocrop back to the footprint aspect — so icons fill their tiles with no dead space even when a GLB carries
  polluted bounds. The inventory grid (`grid_tile.gd`) picks each tile's art in this order: an authored
  `Item.icon` → this baked PNG (by id) → the live 3D mesh → a category glyph (now only the pre-bake fallback).
  Writes PNGs only (never touches your item `.tres`); re-run any time. Needs a renderer — use the tab, or from a
  shell: `godot --path <project> -s scripts/tools/bake_item_icons.gd` (windowed, NOT `--headless`).
- **Dialogue Edit** — pick a `DialogueResource` and edit the conversation: each line (its text + the **Reveals
  speaker's name** checkbox — see *Strangers until introduced*) + its choices (target line, a
  `target_on_fail` branch, the full requirement gates — stat / flag / faction+reputation / perk / item / quest-state —
  and the set-flag / complete-quest / advance-quest consequences), add / remove / reorder, then **Save**.
  A **Consequences** group carries the rest of what a choice can *do*: **Start quest** (a real dropdown over
  `resources/quests/`, labelled by `Quest.id` — that is the key the runtime matches, not the filename),
  **give item + count**, **give money**, **reward reputation + faction**, and **aggro speaker**. So a conversation
  can hand out a quest, pay for one, and turn a speaker hostile without leaving the tab.
  Every id field keeps its **LineEdit** and gains a narrow `▾` **stamp picker** beside it (stat / faction / perk /
  item ids). A stamp writes the id into the box and steps back to the prompt row — so ids for content you have not
  authored *yet* stay typable, which a closed dropdown would forbid. A choice's row in the list shows a short tag
  (e.g. `[Q+]`) when it does something, so consequences are visible without opening each one.
  Picking a quest also warns when `QuestTracker.start_quest` would silently no-op — a blank `Quest.id`, or an unmet
  `prereq_quest_id`. Those are the states where the quest simply never starts in game and nothing says so.
- **Quest Edit** — title / description / reward money+XP / **item `rewards[]`** (a parallel list with an item
  picker + count) / `prereq_quest_id` + `next_quest` chaining / the **Auto-complete** and **Expire on flag** flow
  flags + the objective list (typed KILL/TALK/PICKUP/… dropdown, target, count, a per-objective **description**, an
  **Optional** checkbox — an optional objective gets an "(optional)" tag on its row, matching the Journal — and the
  optional **world marker**: a checkbox plus XYZ position), add / remove / reorder, then **Save**.
  The objective `target_id` keeps its text box and gains a `▾` **stamp picker** whose contents follow the
  objective's *type* (a PICKUP offers item ids, a FLAG offers flag names), because ids are case-sensitive and
  `clear_the_block.tres` already ships a `target_id = "Raider"` that no longer matches `raider.tres`'s `"raider"`.
  Two fields stay inspector-only ON PURPOSE, and neither is an oversight: **`Quest.id`** and
  **`QuestObjective.id`** are PRIMARY KEYS — a save keys its quest sections by `String(quest.id)` and seeds
  progress as `progress[String(obj.id)]`, and dialogue's start/complete/advance ids match them BY VALUE. Re-keying
  one in a passing tidy-up silently orphans every reference and strands live player progress.
  (`Quest.reward_reputation` is a faction→delta Dictionary and needs a key/value editor this panel doesn't offer.)
  **Turn-in note:** `auto_complete` defaults **true**, so a quest completes itself the moment its objectives are
  done. Untick it to author a hand-in step. **Marker note:** a marker only renders in a level carrying a
  `QuestMarkerSync` node — today that is `LevelTemplate.tscn` alone, so a marker on an older level is silently
  invisible.
- **Loot Edit** — a `LootTable`'s entries (item picker + chance + min/max count) with a live expected-drops readout,
  then **Save**.
- **Text** — bulk-edit ALL of the game's player-facing prose in one searchable, category-grouped panel instead of
  hopping between two dozen `.tres` in the Inspector: item names + descriptions, **stat** titles + blurbs, status-effect
  and perk text, quest titles/descriptions, and faction / NPC / level names. Type into any field, filter with the search
  box, then **Save Changed** writes back only the resources you touched (each backed up to `<file>.tres.bak` first, like
  the other editors). What shows up is driven by one registry — `addons/cybersunday_tools/dock_text/text_sources.gd`
  (`SOURCES`); add a row there to expose a new content type's text (also the seam a future localization export would walk).
  The `.tres` stay the single source of truth — this is just a faster surface over the same fields. Text nested in
  ARRAYS (quest objectives, dialogue lines, bark lists) stays in the **Quest Edit** / **Dialogue Edit** tabs.
  Note: **stat** wording now lives in `resources/stats/<id>.tres` (`StatText`), read by `StatInfo` — it used to be a
  hardcoded table, so it couldn't be edited without touching code.
- **Browse** — find + open ANY content `.tres`, grouped by type (Quests / NPCs / Weapons / Items / Factions /
  Dialogue / LootTables / Perks / StatusEffects / Encounters / Schedules / Cutscenes / Barks / Loadouts / Abilities /
  Maps / Tuning), with a search filter; double-click opens it + reveals it in
  the FileSystem.

**Build the scene:**
- **Palette** — searchable, category-grouped browser of every drop-in component (the `core/catalog.gd`
  source-of-truth — one row per component). Select a node, pick a component, *Add to selected node* drops it under the selection. Undo-able.
- **Items** — pick any authored `Item` and drop a ready **dual world item** (a `Throwable` you carry/throw with Z
  **and** a `CanPickUp` child you loot with E) ~3 m in front of the editor camera, selected. *Refresh list* re-scans
  `resources/items/`.
- **Place** — instantiate a configured **NPC** (an NpcData archetype picker assigns its `profile`) and the
  **PlayerSpawn / LevelDoor / Door / Container** prefabs into the scene: parented under your selection, positioned at the
  camera, owner-set so they save, undoable. It also carries the **Blockout (CSG)** block — *Place Building Shell +
  door* / *Floor* / *Wall* / *Ramp*, a *Grid snap (X/Z)* dropdown and *Snap Selected to Grid* — for carving a level's
  walkable shell; see **"Blockout the shell with CSG"** in §2.
- **Level** — one-click **Audit Navmesh**, **Bake + Audit** (synchronous, so the audit sees the fresh bake),
  **Validate Level** (the `LevelRoot` config-warning checks), **Validate Content**, and **New Level** (clones
  `LevelTemplate.tscn` + writes a matching `LevelData` .tres).

**Tune & wire:**
- **Tuning** — lists every global tuning `.tres` in `resources/tuning/` (the `GameSettings` groups, e.g.
  `EconomySettings`, `CameraSettings`); click a row to open it in the Inspector. Read/open only.
- **Factions** — an N×N grid of *Enemy / Neutral / Ally* dropdowns editing inter-faction relations (row = *from*,
  column = *toward*; the diagonal is locked to Ally). *Reload Factions* rebuilds the grid.

**Diagnose:**
- **Audit** — *Re-scan* lists findings errors-first from a scene walk (every node's config warnings, unbaked
  `NavigationRegion3D`, duplicate `PlayerSpawn` `entry_id`) **plus** a `res://` sweep of `.gd` group literals — every
  raw group-call string is flagged so group names stay centralized in `scripts/world/groups.gd`: lowercase `"player"`
  is the known DEAD group (ERROR), a **registered** name used as a raw string (e.g. `add_to_group(&"npc")`) is a WARN
  naming the exact `Groups.<CONST>` to use, and an **unregistered** name is a WARN (a typo, or a group to add to the
  registry). Literals quoted inside `#` comments are ignored. The sweep also covers broken `ext_resource` refs,
  dead/zero-chance `LootTable` entries, out-of-range `DialogueResource` targets **plus** wiring checks (dangling
  story-flags: read-with-no-writer / write-with-no-reader; unresolved quest-id + objective-id refs; unresolved
  faction-ids + `relations`/`reward_reputation` dict-keys). It also lists the **hardcoded player-facing text** debt:
  a raw string literal at a paint site (`label.text = "…"`, `notify_toast("…")`, `MenuStyle.make_title("…")`, …) is a
  WARN naming the line — player copy belongs in `PlayerText` (`scripts/ui/player_text.gd`). **That list should be
  empty:** the debt was paid to zero on 2026-07-27, `tests/test_player_text.gd` now fails on *any* offender, and
  `scripts/tools/text_debt.gd` (or `validate.cmd`) reports the same count headlessly. A row appearing here means
  someone painted a new literal — move it into `PlayerText` rather than re-opening the test's baseline.
  Double-click a row to jump to it; an *Auto* toggle (off by
  default) re-scans, debounced, on changes.
  Findings with ONE unambiguous mechanical fix are tagged `[fixable]`; a **Fix (N)** button batch-applies them —
  the dead `"player"` literal → `Groups.PLAYER`, any registered group literal → its `Groups.<CONST>`, and a `LootTable`
  `max_count < min_count` clamp — after previewing every change in a confirm dialog. Judgment-call findings (unregistered
  group names, broken paths, out-of-range targets) are flagged only. The writes are to disk; save open scripts first and revert via version control if needed.
  **Add your own checks without touching the plugin:** drop a `@tool extends CyberAuditRule` script into
  `res://audit_rules/` and override `run_audit(root) -> Array`, returning findings in the same
  `{severity, source, message, node?}` shape (use the `CyberAuditRule.finding(...)` helper). The panel runs every
  rule with each Re-scan; an absent folder is a no-op. Keep `run_audit` defensive — it runs at edit time.
- **Graphs** — a READ-ONLY visualizer of branching dialogue + quest chains (the **Dialogue Edit** / **Quest Edit**
  tabs are the editable counterparts). Pick a mode + resource, **Build**; dangling / out-of-range targets tint red.
- **Saves** — a READ-ONLY inspector for GameState's `ConfigFile` saves (the autosave, quicksave, and three manual
  slots). Pick a slot to dump its sections + keys into a tree — for answering "what actually persisted?" without
  opening the raw `.cfg`. It reads the EDITOR's `user://`, so it sees saves written by a game launched from the
  editor (▶ Play / ▶ Spawn), not a standalone export's.
- **Refs** — a READ-ONLY back-reference (owners) viewer: **what points AT this resource?** Type a `res://` path
  (or pick a file in the FileSystem dock and hit *Use selected*), *Find refs*, and it lists every project file that
  references it — by `res://` path OR by `uid://` — with the referring line(s) shown beneath each file. This is your
  **delete / rename impact preview**: review the whole list before you remove a `.tres`/`.tscn`/`.gd`. Unlike Godot's
  native *View Owners* it also catches `.gd` scripts that `load()`/`preload()` the path or hold its uid. Double-click
  to open + reveal. The match is text/substring-based so it can slightly over-report (verify), and the scan is a
  one-shot project walk (button-triggered, like Audit Re-scan).
- **Encounter** — a READ-ONLY preview of an `EncounterSpawner`: select the spawner node in the scene, *Preview
  selected*, and it lists each wave (which NPC × how many, scatter radius, stagger, archetype/faction/weapon
  overrides, auto-aggro) + the authored total and placement mode (scatter vs markers). Counts are **authored**;
  runtime multiplies each by difficulty `enemy_count_mult`, so the footer labels the total an estimate. Preview
  only — it spawns nothing and never touches the scene.
- **Stats** — a READ-ONLY content dashboard: *Refresh* counts how much of each content type you have
  (items/weapons/NPCs/factions/quests/dialogue/loot/perks/status/…) and lists **unreferenced straggler candidates**
  — resources nothing references (a WeaponData no Item uses, a LootTable no NpcData uses), double-click to open. The
  straggler check is scoped to REFERENCE-used folders and EXCLUDES the folder-scanned ones (items/factions load by
  directory scan, so "unreferenced" there is noise); treat a flag as a delete *candidate* to verify, not a verdict.
  (`quests/` is now in that scope — it was missing, which is why `clear_the_block.tres`, referenced by nothing at
  all, never surfaced here.)
- **Reach** — a READ-ONLY answer to the question no other tab asks: **what can a PLAYER actually get to from the
  boot scene?** *Rescan* walks the real chain — `project.godot`'s main scene → the menus → `game.tscn` → its
  `LevelData` → that level — and reports which quests have a start site, which of those start sites are themselves
  reachable, and which levels are wired in at all. It exists because every other check stays GREEN on a quest
  nothing starts: Stats asks "is it referenced?", the Audit asks "do its ids resolve?", and both pass a quest that
  is perfectly authored and unreachable.
  **Read an all-green Reach report with suspicion.** A lot of content here loads by folder scan (`ItemDb` scans
  `resources/items/`, factions are scanned), so the tab excludes those roots — and if that exclusion ever
  over-fires it produces an empty, reassuring, wrong report. The status line prints what it *scanned* as well as
  what it *found* precisely so "0 orphans" can be told apart from "scanned nothing".
- **Scene Diff** — a READ-ONLY structural compare of two `.tscn` files. Pick scene A (before) + B (after) and *Diff*:
  it lists nodes ADDED in B, REMOVED from B, and CHANGED (type or properties), with the per-property deltas under
  each changed node. For "what did this edit actually touch?" without diffing raw text. Compare only — no merge
  (apply changes by hand); it parses the scene text, never instantiating it.
- **Architecture** — a READ-ONLY viewer of the living System Map: *Rescan* scans `scripts/`, `managers/`, and
  `resources/` for `## @system / @seam / @risk / @test` annotation blocks, groups them by system, and reports whether
  the committed `docs/SYSTEM_MAP.md` is in sync / **STALE** / not generated yet. The tab never writes — regeneration
  is the headless CLI it prints (`scripts/tools/gen_arch_doc.gd`), which shares the same `ArchScan` builder + a
  drift-guard test.

Outside the panel:

- **Viewport gizmos** (automatic) — draw the normally-invisible spatial data of components right in the 3D viewport
  so you place by eye: `TriggerVolume` / `AudioZone` / `ShadowVolume` (cyan, from the node's first child
  `CollisionShape3D`) and `HazardZone` (orange) extents, `NavBlocker` carve box / avoid cylinder, `PatrolPath` route
  (green, closed if `loop`), `PlayerSpawn` arrival arrow, `EncounterSpawner` scatter rings (at the real `spawn_radius`),
  `ExplosiveBarrel` blast sphere, `InvestigatePoint` / `NoiseSource` rings, `WorldMarker` cross, `AmbientSound` / `Radio`
  audible-range spheres, a `Door` swing arc, and an NPC's sight cone + alert ring. It also draws **wiring link lines**
  so you see what connects to what: `TriggerVolume` → its `target` / `activate_node_path`, `AlarmPanel` → its spawner,
  an NPC's `GuardDuty` → its protectee, and the NPC → its patrol path. No setup, no `@tool` on the target — select a
  node and look.
- **Inspector add-ins** — selecting one of these resources adds a card atop the Inspector: **LootTable** (drop summary
  + a **Roll 1000×** Monte-Carlo), **WeaponData** (a DPS / time-to-kill balance readout + amber traps; the key balance
  fields are editable inline), **NpcData** (resolved-archetype card + the `faction_id`/`faction` both-set conflict flag;
  key fields editable inline), **GoapProfile** (the resolved priority/cost table + amber warnings for stale override rows — `goal_priorities` / `hp_scales` / `temperament_scales` matching no known goal — + a "goals[] is an enforced allow-list" banner),
  and **Perk** (bad stat-bonus keys + dangling prereqs). The WeaponData/NpcData inline edits write back undoably (Ctrl+Z).
- **Play-from-spawn toolbar** — **▶ Play** runs the main scene (`res://scenes/computerroom.tscn`); **▶ Spawn** runs it starting the player at the
  **selected** `PlayerSpawn` (select one first), for fast iteration on a specific area.

**Gotchas**
- **Several tools WRITE `.tres` TO DISK** (not a deferred apply): the **Content** generators + the **Blueprints** packs + **New Level**, the
  Dialogue / Quest / Loot **Save** buttons and the **Text** tab's *Save Changed* (each edited `.tres` backed up to
  `<file>.tres.bak` first), the inline WeaponData/NpcData inspector edits, the **Factions** grid
  (every cell edit), and the **Audit** *Fix* button (rewrites a dead/raw group literal in a `.gd` to its `Groups`
  const, re-saves a clamped `LootTable`). The inspector edits are undoable; the Factions grid quantizes a hand-tuned relation float to the
  nearest Enemy/Neutral/Ally bucket on save, and generators refuse to overwrite an existing path; the Audit *Fix*
  previews + confirms first. The purely **read-only** tabs are **Browse, Tuning, Graphs, Saves, Refs, Encounter, Stats, Scene Diff, Architecture** —
  and Audit's *Re-scan* / *Auto* (only its *Fix* writes) — they navigate / point at problems but change nothing.
- **Double-click an Audit finding to jump to it** — a scene-node finding selects and opens the node; a `res://` file
  finding opens the resource in the Inspector and reveals it in the FileSystem.
- **Gizmos are edit-time visualizers** — they draw nothing at runtime and read serialized data. All are
  visualization-ONLY except one EDITABLE handle: an `ExplosiveBarrel` shows a draggable dot on its blast sphere —
  drag it to resize `blast_radius` (undoable with Ctrl+Z, exactly like an Inspector edit). A zone draws
  nothing if it has no direct-child `CollisionShape3D` (extent is authored on the child shape, not an export); only
  Box/Sphere/Cylinder/Capsule shapes render; an NPC sight cone needs both `sight_range` and `fov_degrees` > 0.
- **Palette / Items / New Level need an open scene** — with no scene open they show "Open a scene first." Adds and
  placements are undoable, but you must **save the scene** yourself to persist them.

### Driving the tools from an AI assistant (the `cyber` CLI + the Bridge tab)

Everything above is built for a human clicking in the editor. Two extra surfaces let an AI assistant *read* the
same data. Both are read-only — no AI-facing path writes a resource or edits a scene.

**`scripts/tools/cyber.gd` — a headless CLI over the plugin's pure modules.** No editor needed. Seven verbs:

| Verb | Answers |
|---|---|
| `catalog` | which drop-in components exist (stops an AI inventing one) |
| `audit` | every finding the Audit tab shows, as JSON |
| `refs` | what points AT this resource — by `res://` path **and** `uid://`, which grep misses |
| `graph` | dialogue / quest graphs + dangling-target problems |
| `balance` | weapon DPS/TTK + loot expected-drops |
| `list` | content inventory by type |
| `describe` | one resource's authored fields |

```
& "C:\Users\dalla\bin\godot.cmd" --headless --path "C:\Users\dalla\3D RPG\rpg" -s scripts/tools/cyber.gd -- --verb=audit
```

A headless boot costs ~7.6s, so prefer `--batch=<abs .json>` (an array of `{"verb":…,"args":{…}}`) — five verbs in
one boot is ~15s instead of ~38s. `--out=<abs>` sends the JSON to a file instead of stdout. Output is framed
between `<<<CYBER-JSON` / `CYBER-JSON>>>` because Godot's banner and the UI autoloads also print to stdout.

**The Bridge tab — an opt-in localhost server for the three things that are impossible headless.** It is **OFF
until you press Start**, binds `127.0.0.1` only, and is gated by a random token in `.godot/cyber_bridge.json`
(gitignored). Press Stop, or disable the plugin, and the port closes.

- `godot_fs_sync` — tells the open editor a file changed on disk. **This is the one that matters.** Without it, a
  `.tres` written by any external process is invisible to your editor until it happens to rescan, and the editor's
  stale in-memory copy silently wins on your next Ctrl+S. That hazard exists whether or not you use the Bridge.
- `godot_editor_state` — the open scene, your selection, the inspected resource. Turns "find the file, paste the
  path" into "fix the thing I'm looking at".
- `godot_reveal` — opens a resource in the Inspector / selects a node, so the AI can hand you the thing it means.

`tools/mcp/cyber_mcp.py` exposes all ten as MCP tools (zero dependencies — Python stdlib only). It is registered
in `.mcp.json` at the Claude Code project root. Check it with
`python tools/mcp/cyber_mcp.py --selftest`.

Placement, baking and every other mutation are deliberately **not** exposed. The AI can read your project and
point at things; it changes files through ordinary reviewed edits, not through a socket.

---

## Building a level scene

A level in CYBER SUNDAY is just a `Node3D` scene full of instanced props, lights, characters, and exactly one `WorldEnvironment`. The shipped example is `res://scenes/levels/TestLevel.tscn` (root node **`Level`**, a plain `Node3D`). It is *instanced*, not run directly: `res://scenes/game.tscn` (root **`Game`**) is the real entry point — it adds the `Level` instance, a `Player`, the `SkyTitle` ("CYBERSUNDAY") banner, and the ambience/music players (which live under the `Player`). So the rule of thumb is: **build your world in a level scene, then drop that scene into a Game-style wrapper that supplies the Player.**

> **⚡ Fastest path — don't build the skeleton by hand.** Two ways to start a new level, both pre-wired with the full correct layout (every group, the navmesh bake settings, a sky StarSky can repaint, a floor, a default `PlayerSpawn`):
> - **Duplicate** `res://scenes/levels/LevelTemplate.tscn` (FileSystem → right-click → Duplicate, or open it and *Scene → Save Scene As…*), rename the root, and start filling in `Geometry`. Duplicate `res://resources/levels/LevelTemplate.tres` too and point its `scene` at your new file.
> - **Generate both at once:** open `res://scripts/tools/new_level.gd`, set `NEW_LEVEL_NAME`, and **File → Run** — it writes `scenes/levels/<Name>.tscn` + a matching `resources/levels/<Name>.tres` and prints the next steps.
>
> The template's root carries the `@tool` **`LevelRoot`** script, whose inspector **config-warnings** tell you exactly what's still missing (no sky/region/spawn, a `WorldEnvironment` outside its group, a duplicate `entry_id`, or "not baked yet"). When `LevelRoot` is quiet, the level is structurally complete. Then: build geometry under `Geometry`, select the `NavigationRegion3D` and click **Bake NavigationMesh**, and point a `LevelDoor` (drop `res://scenes/components/level_door.tscn`) or `GameRoot.level` at your `LevelData .tres`. The manual steps below explain what each piece is.

### The level root layout

Open `TestLevel.tscn` and you'll see the root's direct children are organised into a handful of grouping `Node`s. This is the layout to mirror in a new level:

| Child of `Level` | Type | What lives here |
|---|---|---|
| `NavigationRegion3D` | `NavigationRegion3D` (group `navmesh`) | the baked navmesh NPCs walk on |
| `AmbientDust` | instance of `scenes/effects/ambient_dust.tscn` | floating dust motes (its `motes` field is set to `1600`) |
| `WorldEnvironment` | `WorldEnvironment` (group `world_environment`) | the sky / fog / ambient (one per level) |
| `DirectionalLight3D` | `DirectionalLight3D` | the moonlight key light |
| `Characters` | plain `Node` | every NPC instance (`NPC.tscn`, `medicine_person.tscn`, …) |
| `Lights` | plain `Node` | the `OmniLight3D` / `SpotLight3D` street lights (several carry a child `AudioStreamPlayer3D` buzz) |
| `Geometry` | `Node3D` (group `navmesh`) | static world: buildings, roads (the `Asphalt` `MeshInstance3D`), cars, trees, rocks, containers — anything the navmesh bakes from. CSG shell geometry belongs in a `Blockout` child (a `Node3D`, also in `navmesh`) — `LevelTemplate.tscn` ships one (and `new_level.gd` clones the template, so a generated level has it too); SELECT that node before using the Place-tab CSG buttons, which parent each piece under your current selection, or under the scene root if nothing is selected. TestLevel has none yet — see *Blockout the shell with CSG* below |
| `Objects` | plain `Node` | dynamic/throwable props — `cube.tscn`, `trash.tscn`, and the `Radio` Area3D (parented under one of the cubes) |
| `Graffitti` | plain `Node` | decal `Sprite3D`s |
| `PlayerSpawn` | instance of `scenes/world/PlayerSpawn.tscn` (a `Marker3D`, group `player_spawn`) | where `GameRoot` drops the player on entry. At least one with a blank `entry_id` (the default arrival); add named ones (`entry_id = &"north"`, …) to receive `LevelDoor`s. Its facing arrow is drawn by the CYBER SUNDAY editor gizmo plugin (`addons/cybersunday_tools/gizmos/cybersunday_gizmo_plugin.gd`), not by the prefab — the prefab is a bare `Marker3D`, so the arrow shows only while the plugin is enabled and never exists at runtime. |

The bucket nodes are pure organisation (no scripts). In a NEW level the **root** carries the `@tool` **`LevelRoot`** script (`LevelTemplate.tscn` ships it, and `new_level.gd` clones the template), whose inspector config-warnings flag anything missing — the legacy `TestLevel.tscn` root has NO script, so opening it shows no validator; attach `scripts/world/level_root.gd` if you want one there. Use the buckets so the tree stays legible; nothing breaks if you add another category. (Some props get instanced straight onto the root — that works, it's just messier; prefer the buckets.) The `LevelTemplate.tscn` ships this whole layout ready to go.

**Where new content gets parented:**
- A new **NPC** → instance `res://scenes/characters/NPC.tscn` (an armed combatant), `res://scenes/characters/civilian.tscn` (a non-combat townsperson — townsfolk faction, flees threats, pre-wired with a `Talkable`), or `res://scenes/characters/medicine_person.tscn` under `Characters`, then set its `@export` fields in the inspector (`display_name`, `faction`, `profile`, `weapon_data`, `wanders`, `sight_range`, …). Drop a `talkable.tscn` instance under the NPC to make it conversational (set its `dialogue` and `voice`).
- A new **static prop / building** → under `Geometry`, so the navmesh carves around it (see "Navigation" below).
- A new **pickup / throwable / interactable** → under `Objects` (e.g. another `cube.tscn`).
- A new **light** → under `Lights`.

### Cutout brush materials (fences, foliage): never set Cull Mode = Disabled

A brush material in `tb_materials/textures/` that uses **Transparency = Alpha Scissor** (fences, grates, tree
canopies — the see-through ones) must keep **Cull Mode = Back**, the Godot default. Setting it to **Disabled**
(double-sided) is the single most expensive mistake available in this folder, and it does not look like a
material bug when it bites — it looks like *the level is flickering*.

Why: a TrenchBroom brush is a **closed solid**, so its far side is already hidden by its near side; double-sided
rendering buys you nothing on a box. What it *does* do is start rasterizing the box's interior caps — the bottom
cap sitting on the floor slab, the top cap tucked under a cap rail, the end caps butted into the next panel.
Brush authoring snaps those flush **exactly**, so each one becomes a coplanar pair with zero gap. Normally one
member of such a pair is back-facing and silently culled; with Cull Mode = Disabled both rasterize at identical
depth and z-fight. Alpha Scissor renders in the **opaque** pass (depth-written), so this is a true depth fight,
not a sorting issue — you cannot fix it with `render_priority`.

It then *animates*, which is what turns a static z-fight into visible flicker: `ps1_applier.gd` deliberately
skips non-opaque materials, so the cutout face is the **only** geometry in the level that is NOT vertex-snapped,
while its coplanar opaque partner IS. `ps1.gdshader`'s snap moves clip-space XY every frame, which changes the
interpolated depth at a given pixel, so the winner of the fight re-randomizes each frame the camera moves. The
snap runs at full strength from **1.5 m to 20 m**, so the worst offenders are the ones nearest the player.

This was the root cause of the long-running "texture flickering" bug: `fence1_a.tres` shipped with
`cull_mode = 2`, and `alive.map`'s 13 fence brushes (all closed 6-face boxes, 0.5 m thin) produced **41 coplanar
z-fight pairs totalling ~162 m²** — including a flat floor-grate panel whose 42.75 m² underside sat exactly on
the concrete slab beneath it. Deleting one line fixed it, with **no** map rebuild (the baked surface references
the material by path).

Two related traps in the same area, both measured and both dead ends — don't spend time on them:
- **Alpha-to-coverage is inert here.** `alpha_antialiasing_mode` needs MSAA, and `project.godot` ships
  `msaa_3d=0`. Turning it on changes nothing rendered.
- **`alpha_scissor_threshold` is not a flicker knob.** `fence1_a`'s alpha is near-binary (only ~0.4% of texels
  sit near the cut) and its coverage is nearly LOD-invariant, so moving the threshold only fattens or thins the
  wires. It is a look dial, not a fix.

If you genuinely need a double-sided cutout (a true zero-thickness card, e.g. a crossed-quad billboard), that's
fine — the rule above is about **closed solids**, where the back faces are pure cost. `tree.tres` is still
`cull_mode = 2` on purpose: its brushes are thick solids whose double-sidedness supplies the "far foliage seen
through the near side's holes" volume, so flipping it is a real look change, not a free win. Evaluate it on its
own if tree flicker ever comes up.

### The WorldEnvironment (sky, fog, ambient)

The `WorldEnvironment` node holds one `Environment` resource and is tagged with the group **`world_environment`**. That group name is load-bearing: the **`StarSky`** autoload (`res://scripts/effects/star_sky.gd`, registered in `project.godot`) listens for any node entering the tree that is a `WorldEnvironment` *or* in that group, and repaints its sky at runtime. So whatever sky you author in the inspector is a *seed* — StarSky takes it over when the game runs. Two things happen, non-destructively (your saved `.tscn` is never modified):

1. **Horizon sky.** StarSky reads your `Environment.sky`. If its material is a `PanoramaSkyMaterial`, it grabs that material's `panorama` texture and rebinds it onto the `horizon_sky.gdshader` (`res://resources/shaders/horizon_sky.gdshader`), which lays the image *flat along the horizon as a band* (cylindrical) instead of the pinched equirectangular sphere mapping. In `TestLevel` the authored panorama is `res://assets/textures/hdi.png`. A level with **no** panorama just renders the shader's gradient + amber haze (the shader's `use_panorama` uniform is left `false`).
2. **Pinned mood.** The authored env lights its ambient from the (bright) sky, which washes everything white. StarSky overrides that: it forces `ambient_light_source` to a fixed **colour** (`GameSettings.effects.sky_ambient_fill`, default `Color(0.05, 0.07, 0.13)`), disables sky reflections (`reflected_light_source` → disabled), and lifts `background_energy_multiplier` off a pathological `0`. Note `TestLevel`'s env ships at `background_energy_multiplier = 0.0` precisely because StarSky will lift it — that's intentional, not a mistake.

**What *you* still author on the Environment** (StarSky leaves these alone): the volumetric fog and tonemap. In `TestLevel`'s env those are `tonemap_mode = 4` (AgX), fog on (`fog_mode = 1`) with `fog_density = 1.0` / `fog_sun_scatter = 1.0`, and `volumetric_fog_enabled = true` (`anisotropy 0.1`, `sky_affect 0.33`). Tune fog/tonemap here per level for the look you want.

**Tunables you control without code:**
- **The sky look** lives on the shader uniforms — select the live `ShaderMaterial` at runtime, or set sane defaults by editing the `.gdshader`. The designer-facing uniforms are: `pano_yaw` (rotate the image), `pano_tiles` (how many times it wraps — raise if a non-panoramic photo looks stretched), `band_bottom` / `band_top` / `edge_fade` (where the image band sits on the horizon and how it blends), the four colours `zenith_color` / `horizon_color` / `ground_color` / `haze_color`, and `gradient_power`, `haze_height`, `haze_strength`, `sun_glow`, `sun_azimuth`. (`flash` / `flash_color` are driven by StarSky's kill flash — don't hand-set them.)
- **The pinned ambient tint and the whole on-kill sky flash** live on the `GameSettings.effects` registry (the `EffectsSettings` resource, `res://resources/tuning/EffectsSettings.tres`), under the **Sky FX** group: `sky_ambient_fill`, plus five knobs for the kill pop — `sky_flash_color` (ships **red**, `Color(1.0, 0.1, 0.08)` — a hotter, brighter red than the hurt wash's darker `Color(0.85, 0, 0)`, which is the only hue separation between the two red cues; the rest of the separation is shape), `sky_flash_peak` (`1.0` = the sky goes *solid* that colour; lower tints instead), and the three beats `sky_flash_up_time` (`0.06`) / `sky_flash_hold_time` (`0.3`) / `sky_flash_down_time` (`0.64`), which sum to the ~**1 second** the player actually sees. These are global, not per-level.
  - **The hold is the part that makes it read as a colour.** `StarSky.flash_kill` builds `up → hold → down` (the same three-beat shape as `Character._build_flash_tween`'s per-part hit flash). Drop `sky_flash_hold_time` to `0` and the tween degrades cleanly to two beats — but a second-long up+down ramp reads as the sky *brightening*, not as the sky turning red, which is why it ships held.
  - **Retune all three times together, not one.** They are the length of one beat; raising only `down` slows the fade without lengthening the colour, and raising only `hold` pushes the total past a second.
  - **Watch the blood, if you tune this.** `sky_flash_peak = 1.0` means the sky goes *solid* `sky_flash_color` for the whole beat, and the on-kill `BloodSplatter` blobs are dark red — so wherever sky is in frame during the flash, the blobs are dark-red-on-bright-red: a ~46% luminance gap and **zero** hue gap (under the old purple the blue channel differed by `0.98` and they popped). If the blood reads as washed out on an outdoor kill, drop `sky_flash_peak` to ~`0.7` so the sky *tints* instead of going solid and the authored dark sky keeps the blobs' backdrop dark — that is a one-knob change and does not touch the colour.
  - **`sky_flash_color` is written on every kill**, not once at paint time, so you can tune it live in the **Remote** inspector mid-fight. The shader's own `flash_color` default is still white and is only the fallback for a sky that StarSky did not paint.
  - **The sky has a SECOND flash channel: RED when you TAKE DAMAGE** (`StarSky.flash_hurt`, fired from `Player.take_damage` — the one funnel every damage vector already goes through, so enemy fire, explosions, hazards, status DoT and falls all wash the sky with no per-source wiring). Its knobs sit beside the kill ones in **Sky FX**: `sky_hurt_color` (matching the screen-space `hurt_flash_color` red), `sky_hurt_peak` (`0.55`) and `sky_hurt_up_time` / `sky_hurt_hold_time` / `sky_hurt_down_time` (`0.04` / `0.06` / `0.35` — about `0.45 s`).
    - **It is deliberately shorter and PARTIAL where the kill flash is long and solid.** You take damage an order of magnitude more often than you kill; a solid red sky held for a second would sit red through an entire firefight and smear into the kill flash. **Since the kill flash is red too, this asymmetry is now what tells the two cues apart** — a kill goes *solid* and *holds*, a hit is a partial wash half as long, on top of the brighter red. A GUT test pins `hurt beat < kill beat` so a retune can't silently invert that.
    - **The two channels are separate shader uniforms** (`flash`/`flash_color` and `hurt_flash`/`hurt_flash_color`), not one shared pair, and `StarSky` keys a tween per channel. That is what lets a bullet you take mid-kill wash the sky **without cutting the kill beat short** — with one channel, each trigger would kill the other's tween and repaint its colour. In the shader the hurt mix is applied LAST, so when both are up the damage read wins: being shot outranks having scored. **Caveat now that BOTH cues are red:** at `sky_flash_peak = 1.0` the kill flash *replaces* the sky, so a hit landing mid-kill only pulls `(1.0, 0.1, 0.08)` toward `(0.85, 0, 0)` at `0.55` — a ~20% brightness dip with **no hue change**, where the old purple flash swung hue hard. The hurt wash is still not swallowed, but it no longer reads as a *different colour*. Drop `sky_flash_peak` below `1.0` (giving the hurt mix a non-red base to pull from) or move one of the two colours off red if you want that separation back.
  - **A kill is a SKY-ONLY cue — the screen-space punch ships OFF.** `PlayerHud.flash_kill` still exists and still pulses a full-screen `ColorRect` from `GameSettings.player_feedback` (`kill_flash_color` — kept matched to the sky's red, `kill_flash_time` `0.35`), but **`kill_flash_peak_alpha` ships at `0`** and `flash_kill` early-outs there, so nothing tweens. The reason is draw order: `_kill_flash` is added as the LAST child of `ui`, so it drew *over* the **BloodSplatter** overlay `Player.on_nearby_death` sprays on a close kill — and a `0.45`-alpha full-screen wash fading over `0.35 s` buried the blood, which is the kill feedback that actually reads at melee range, i.e. exactly the case where the sky is not in frame.
    - **The known cost of shipping it at `0`.** That screen punch was the *only* half of the kill cue that works with no sky in frame, and `blood_splatter_range` is just `3.5 m` — so an **indoor kill past ~3.5 m** (a DoT tick finishing someone, a fall you caused, a shot down a corridor) now confirms with the camera kick (`kill_shake_amount`) and nothing else. The hitmarker is not a substitute: it fires identically for a hit and for a kill. This is a deliberate trade for seeing the blood, not an oversight.
    - **If you re-arm it, retint it first.** Raising `kill_flash_peak_alpha` off `0` while `kill_flash_color` is red walks straight back into the original complaint: the blood blobs are themselves dark red (`blood_splatter_tint_*` = `0.6 / 0.04 / 0.02`), so a red wash hides them *by hue* as well as by alpha. Reordering the rect under `BloodSplatter` in `ui` — which would have fixed the old white punch outright — buys almost nothing against a red one. Retint to white (or anything off the blood's hue) *and* drop the alpha.
    The damage pair is untouched and still flashes both halves (`hurt_flash_color` red). All of them honour the Accessibility "Screen Flashes" toggle.

### Navigation

NPCs path on the `NavigationRegion3D` child. Its `navigation_mesh` is a baked `NavigationMesh` whose bake settings are authored in the inspector — and the key field is `geometry_source_geometry_mode = 1` ("Group Explicit") with `geometry_source_group_name = &"navmesh"`. **That is why `Geometry` is in the `navmesh` group:** only nodes in that group feed the bake. The region itself is also in `navmesh`. Other tuned bake fields you can see: `cell_height = 0.01`, `agent_height = 2.2`, `agent_radius = 0.6`, `region_min_size = 0.1`, `edge_max_error = 0.1`, `filter_low_hanging_obstacles = true`, and `navigation_layers = 4294967295` (all layers, set on the `NavigationRegion3D` node).

**Bake from COLLISION, not visual meshes — `geometry_parsed_geometry_type = 1` ("Static Colliders").** The engine default is `2` ("Both"), which ALSO parses every `MeshInstance3D` in the `navmesh` group — so a decorative mesh with **no collider** (or whose collider differs from the visible mesh) gets baked walkable, and NPCs path onto/around it and grind ("stuck on meshes, not just collision"). This project authors walkability deliberately as collision — floor `StaticBody` colliders, CSG `use_collision`, `NavBlocker` CARVE — so set **Parsed Geometry Type → Static Colliders** on the `NavigationMesh` and the navmesh matches exactly what the NPC's body collides with. The templates (`LevelTemplate.tscn`, `new_level.gd`) already set this; the `LevelRoot` inspector validator and `audit_navmesh.gd` both flag any region still on Both/Mesh Instances. (This does NOT help a SOLID prop that has a collider — that still bakes a walkable top; see `NavBlocker(CARVE)` below.)

To author navigation in a new level: put your walkable floor + obstacle meshes under a node in the `navmesh` group, select the `NavigationRegion3D`, and click **Bake NavigationMesh** in the toolbar. The region's `visible = false` just hides the debug overlay — it stays functional. **If NPCs won't move, the usual cause is the mesh wasn't baked or the geometry isn't in the `navmesh` group.**

**Keeping NPCs OFF props and AROUND obstacles — `NavBlocker` (`nav_blocker.gd`, `@tool`, `extends NavigationObstacle3D`).** A solid prop in the `navmesh` group bakes a *walkable top* (NPCs climb onto a car/dumpster and get stuck), and a movable prop (a thrown crate) isn't in the bake at all, so paths run straight through it. Drop a **`NavBlocker`** under the prop (next to its `CollisionShape3D`; it auto-sizes from that, or set `size_override`) and pick a `mode`:
- **`CARVE`** (default, for SOLID immovable props) — cuts the prop's footprint out of the bake: no walkable roof, and paths route around its base. **Re-bake the `NavigationRegion3D` after adding/moving one** — it only changes the bake. (Already on `old_car` / `dumpster` / `shipping_container`.)
- **`AVOID`** (for MOVABLE props) — a runtime RVO obstacle that NPCs steer around live (no re-bake); it reports its body's velocity so a *thrown* crate is dodged mid-flight. (Already on the throwable `cube`.) NPCs ship with `NavigationAgent3D` avoidance ON, so this just works.

Also keep the bake's **`agent_max_slope`** sane (`30°` is the recommended baseline): too high and a prop's sloped surfaces (a car hood/windshield) become a ramp NPCs walk up onto the roof. And keep **`agent_max_climb`** at ~`0.4` (the template's value) — if the field is missing it falls back to the engine default `0.9`, which lets the bake step onto curbs/props/roofs. The `LevelRoot` validator flags a bad bake (islands / elevated polys / `agent_max_climb > 0.5`) right in the inspector.

**Making NPCs traverse ledges & drops — `NavLink` (`nav_link.gd`, `@tool`, `extends NavigationLink3D`).** A consequence of that `agent_max_climb ≈ 0.4` is that the bake leaves any surface more than ~0.4 m above/below its neighbour as a *separate, disconnected navmesh island* (`audit_navmesh.gd` reports these). So A* can't route an NPC across a ledge — **up or down** — and an off-duty NPC never steps off a drop or climbs a lip (the combat "nav-hop" only fires in threatening pursuit). Bridge the gap with a **`NavLink`**: add it as a child of the level near the ledge and drag its two endpoint handles (NavigationLink3D's built-in gizmo) onto the lower and upper walkable surfaces — a metre or so in from each rim so `auto_project` can snap them onto the baked mesh. Pick `direction`:
- **`TWO_WAY`** — climb up **and** drop down (a low ledge / crate / short step-up).
- **`ONE_WAY_DOWN`** — drop only: NPCs leave but can't scale it (a cliff / balcony). Auto-orients so the higher end is the start.

...and pick `traversal` — *how the body physically crosses the climb*:
- **`LAUNCH`** (default) — the `Locomotor` injects a **ballistic hop** onto the higher island. For a bare **ledge / crate / single tall step** with no walkable geometry between the two surfaces.
- **`WALK`** — **no launch**: the NPC steers along the link and its **step-up** climbs the real stair treads underneath, so the flight reads as *walking up*, not a leap. Use this for a **staircase**. Lay the two endpoints on the lower and upper landings (along the stair footprint) so the straight link runs up over the steps.

**Stairs specifically.** This project's brush stairs have **0.5 m risers** — taller than the bake's `agent_max_climb` (0.4), so every flight bakes as a stack of *disconnected islands* and A* can't route up it. Two things make NPCs use stairs: (1) NPCs now have the same **auto step-up** the player does (`Locomotor.enable_step_up`, on for every NPC — it lets the `CharacterBody3D` physically climb risers, which `move_and_slide` can't do alone), and (2) a **`WALK` `NavLink` across each flight** to give A* the routing edge. With both, NPCs walk up stairs in every state; combat pursuers already climb even *without* the link (the straight-line pursuit charge + step-up carries them up when chasing you). A `WALK` link skips the "taller than a jump" warning (it's walked, not jumped) but warns if you draw it near-vertical (no stairs under it for step-up to climb).

**No re-bake** — unlike `NavBlocker(CARVE)`, a link is a *runtime* routing edge, not a bake input: drop it, save, done. The upward *launch* (LAUNCH mode) that carries the body onto a higher island comes from the `Locomotor`'s link-ascent driver (decoupled from the combat hop, so idle/civilian NPCs climb too); descent is just gravity. Raise `traverse_cost` if NPCs jump a ledge that has a nearby ramp you'd rather they use. It config-warns on coincident handles, a redundant sub-0.4 m span, or a `TWO_WAY` `LAUNCH` link too tall for an NPC to jump (use `ONE_WAY_DOWN`, a `WALK` link over stairs, or a ramp).

**Auto-generating links instead of hand-placing them — File → Run `scripts/tools/generate_nav_links.gd`.** Rather than dropping a `NavLink` at every ledge yourself, run this after baking: it scans the region for disconnected islands within a jump/drop budget and creates a `NavLink` for each real gap (reusing the audit's island detection — the brain is `NavLinkPlanner`, unit-tested). It **auto-classifies each gap**: a bare ledge/crate → `LAUNCH`, a cliff → `ONE_WAY_DOWN`, and — via a physics raycast probe between the two island rims — a **staircase/ramp** (continuous ground rising in ≤`step_up_height` steps) → a `WALK` link spanning the whole flight. So stairs are handled automatically now, not hand-flipped. It also **rescues sinks**: a *small* island you can only drop **into** — every link touching it is a one-way-down arriving there, with no walk/two-way/drop-out — would strand any NPC that pursues or falls in (A* has no route back up), so its cheapest incoming drop is promoted to a climbable `TWO_WAY` and the NPC climbs back out however it got in (the link-ascent launch scales to any height). Only *pure* sinks smaller than the main floor qualify, so a legitimate one-way cliff down to the ground is left alone. It's **preview-first** — `APPLY = false` (default) just prints what it *would* create to the Output panel; set `APPLY = true`, re-run, then **Ctrl+S**. Inserted links live under a `GeneratedNavLinks` container and regeneration is idempotent (it replaces only that container, so hand-placed links elsewhere are untouched) — re-run it after every re-bake. Caveats: **bake first** (bad islands → bad links; audit them), and eyeball the result in the viewport (a mis-probed link is rare but possible). Tune reach via the `BUDGET` consts at the top of the script (`max_gap_h` / `max_climb` / `max_drop` / `link_spacing` for jumps; `stair_run_max` / `stair_climb_max` / `step_walk_max` for stairs).

**Diagnosing bad navigation (NPCs stuck on roofs / shuffling in place).** Those symptoms are almost always a bad *bake*, not the AI. Three tools to find and confirm it:
- **Audit the bake — File → Run `scripts/tools/audit_navmesh.gd`.** Prints a per-level health report to the Output panel: how many **disconnected islands** the navmesh has (an NPC on one can't path to another), and any **elevated polygons** baked on top of cars/props (the "stuck on a roof" cause), with their heights + locations. Fix the flagged props with a `NavBlocker(CARVE)` or a lower `agent_max_climb`, then re-bake. (Analysis is `NavMeshAudit.analyze()`, unit-tested.)
- **Watch it live — `NavDebugOverlay`.** Add a `NavDebugOverlay` node to a level (or bind its `toggle_action`) and enable it: it turns on the navmesh debug draw + every NPC's path line while you play, so you can see whether a stuck NPC is off the mesh, on a stray poly, or has no path. Inert by default — the master `enabled` ships OFF, so nothing draws until you tick it (underneath it the two Navigation layers are ON, which is why enabling the node alone gives you the navmesh + path lines; the four AI-diagnostic layers ship off). There is no build gate, though: don't ship a level with `enabled` ticked. (The editor's **Debug → Visible Navigation** menu toggle shows the mesh too, without code.)
- **Prove the AI is fine — `res://scenes/levels/NavSandbox.tscn`.** A flat, pre-baked, zero-clutter level (with crates as obstacles): set `GameRoot.level` to `resources/levels/NavSandbox.tres` and play. If NPCs roam and route around the crates smoothly there, the problem is your level's bake, and a clean bake is the real fix. (**Gotcha:** with a save on disk that assignment is ignored — `GameRoot.resolve_boot_level` boots the SAVED level instead — so start a **New Game** to actually land in the sandbox.)

### Blockout the shell with CSG (carve floors, walls & enter-able buildings fast)

Hand-aligning a `MeshInstance3D` + `CollisionShape3D` for every floor and wall is the slow, error-prone part of level-building — gaps and floating boxes are exactly what fragments the navmesh into islands. Carve the walkable **shell** as native **CSG** instead. Godot parses `CSGShape3D` geometry into the same `navmesh`-group bake (verified across every parser mode), so a CSG blockout drops straight into the existing Bake → `audit_navmesh.gd` loop — no extra pipeline, no external tool.

**One-click pieces — CYBER SUNDAY bottom panel → `Place` tab → "Blockout (CSG)".** Each button builds a self-contained piece already in the `navmesh` group with `use_collision` on, drops it in front of the editor camera, owns it so it saves, and selects it (one undo). **Re-Bake the `NavigationRegion3D` after placing** — these change the bake, not the runtime.
- **Place Building Shell + door** — 4 walls (no floor: it sits on the open ground so the interior floor *is* the exterior ground = one continuous island) with a doorway in the +Z wall, floored to a safe width (see the rule below).
- **Floor / Wall / Ramp** (three small buttons sharing one row beneath the Building Shell button; the full description is in each tooltip) — bare CSG primitives for raised floors, partitions, and walkable ramps (ramp tilt is auto-clamped under `agent_max_slope` so it stays walkable).
- **Grid snap (X/Z)** — pick `0.5`/`1`/`2 m` and every placement (props too) snaps to that grid; **Snap Selected to Grid** rounds already-placed nodes onto it. Snapping is what keeps floor pieces tiling flush — gaps between floor pieces are the root cause of island fragmentation.

Pieces land under whatever you have selected — select the **`Geometry/Blockout`** node (an empty `Node3D` organizer the template now ships, in the `navmesh` group) to keep them tidy — or under the scene root; either way they carry the `navmesh` group so the bake finds them. Hand-authoring works too: add `CSGBox3D` children under a `CSGCombiner3D` (in the `navmesh` group, `use_collision = true`).

**⚠ The doorway rule — the #1 seamless-interior gotcha.** With the level's `agent_radius = 0.6` the bake erodes every opening by ~0.6 m per side. A doorway under **~2.4 m clear** erodes shut and the interior bakes as a SEPARATE navmesh island — NPCs and companions can't walk in or out, even though the gap looks walkable to the *player* (the player isn't navmesh-bound). Measured on this project's settings: 1.8 m door → **2 islands**; 2.4 m → **1 connected island**. Keep openings ≥ 2.4 m (the Building Shell button enforces this); if `audit_navmesh.gd` reports 2 islands after adding a building, widen the door and re-bake.

**Finishing a blockout.** CSG is heavier at runtime than baked meshes and has limited UV/material control, so treat it as the *shell*: carve playable space fast, then dress it with hero props (`scenes/props/*`) and skin the surfaces. For a perf-sensitive final, select the root CSG node and use the viewport toolbar's **Bake Mesh Instance** to convert the settled shell to a `MeshInstance3D`, then re-Bake the navmesh.

### Worked example: a new "alley" level

1. **Start from the template.** Duplicate `res://scenes/levels/LevelTemplate.tscn` → `Alley.tscn` (or File → Run `scripts/tools/new_level.gd` with `NEW_LEVEL_NAME = "Alley"`, which also makes the `LevelData` for you). It already ships every bucket, the `navmesh`/`world_environment` groups + bake settings, a seed sky, a floor, and a default `PlayerSpawn` — no hand-wiring.
2. **Build the world** under `Geometry`. Carve the walkable shell — floors, walls, enter-able buildings — fast with the **CSG blockout** buttons (`Place` tab → *Blockout (CSG)*) into `Geometry/Blockout`; instance set-dressing props (`scenes/props/store.tscn`, an asphalt `MeshInstance3D`, …) on top. For solid props NPCs shouldn't climb, drop a `NavBlocker` (above). The root's `LevelRoot` config-warnings flag anything missing. (See *Blockout the shell with CSG* for the doorway rule.)
3. **Bake & audit:** select the `NavigationRegion3D` → **Bake NavigationMesh** (clears the validator's "isn't baked" reminder). Then **File → Run `scripts/tools/audit_navmesh.gd`** and confirm **~1 island / ~0 elevated polys** (the `NavSandbox` baseline) *before* you test — if not, add a `NavBlocker(CARVE)` or lower `agent_max_climb`, then re-bake. Treat this as a GO/NO-GO gate, not troubleshooting. **One-click shortcut:** select the level root and tick **`bake_and_audit`** in the inspector — it bakes the region *and* prints the island/elevated/climb verdict to the Output panel in one step.
4. **Populate:** under `Characters`, instance `scenes/characters/NPC.tscn` (set `display_name` / `faction` / `wanders`, add a `talkable.tscn` for dialogue); drop physics props under `Objects`.
5. **Re-skin the sky** (optional): on the `WorldEnvironment`, swap the `PanoramaSkyMaterial.panorama` image and tune fog/tonemap — StarSky handles the rest at runtime.
6. **Make it loadable via the seam:** duplicate `res://resources/levels/LevelTemplate.tres` → `Alley.tres` and point its `scene` at `Alley.tscn` (the generator already did this). Then either point a **`LevelDoor`**'s `target_level` at `Alley.tres` (drop `scenes/components/level_door.tscn` into another level, give the destination a `PlayerSpawn` whose `entry_id` matches the door), or set `GameRoot.level` to `Alley.tres` to make it the starting level. No `game.tscn` copy needed — the Player + wrapper are supplied by the existing Game/GameRoot. (**Gotcha:** a LOADED game's SAVED level outranks `GameRoot.level`. `GameState._ready` pulls the autosave into memory at boot (`load_from_disk`, which sets `loaded = true`), and `GameRoot.resolve_boot_level` then boots that saved level. So with a save on disk, Continue — or pressing Play straight on `game.tscn` — starts you in the level you saved in, not `Alley`. Start a **New Game** (`reset_for_new_game` clears `loaded` and `current_level_path`) to actually boot the exported level.)

### Gotchas

- **StarSky overrides a SKY-SOURCED ambient.** While `ambient_light_source` is Background/Sky, StarSky flips it to a fixed colour (`sky_ambient_fill`) at runtime and your `ambient_light_color` tweak is overwritten. To pin your own ambient, set `ambient_light_source = Color` yourself — a deliberately-authored fixed ambient is left alone. Background energy is only lifted when it is `0` (the pathological case); a real authored value survives. The sky *look* is still best changed via the shader uniforms and `EffectsSettings`.
- **The level scene has no Player.** Running `TestLevel.tscn` alone gives you a world with nothing to control. Always play through `game.tscn` (or your own Game wrapper) — that's where the `Player` instance and its spawn `transform` live.
- **Geometry must be in the `navmesh` group, then re-baked.** New static props added under `Geometry` are not walkable until you bake again; props placed *outside* a `navmesh`-group node are ignored by the bake entirely.
- **One `WorldEnvironment` per level.** StarSky drives its kill-flash on the *last* painted environment, so a second live env in the same scene would leave the first one's sky un-flashed.
- **Only the PLAYER's kills pop the sky, and EVERY kill does. One name, one caller: `Player.on_scored_kill()`, fired from the lethal branch of `Character.take_damage`.** That method *is* the kill cue: StarSky's sky pour + `PlayerHud.flash_kill`'s screen punch + the **camera kick** (`GameSettings.screen_shake.kill_shake_amount`, `0.4`). It rides the **same `killer` the bounty does** — the one `Character._resolve_killer()` picks — on the principle that "who does this death pay?" and "whose sky pops?" are the same question. Nothing else may call it; a second caller would double-fire it.
  - **That is why every kill flashes, including the ones with no hit to confirm.** Shooting, melee, a projectile, explosive splash, a thrown prop or thrown weapon, a grapple-swung prop, the pinball body-ram and a **silent takedown** all reach it because they all deal damage through `take_damage` credited to you. A **status-effect / DoT tick** and a **fall you caused** reach it too, even though their killing blow carries no attacker at all, because `_resolve_killer` falls back to `Character._credit_attacker` inside `kill_credit_window_ms`.
  - **The kick is the half you feel, and it does NOT fall off with distance.** `on_scored_kill` adds `kill_shake_amount` trauma to `ScreenShake` at any range. That is deliberate and is the one place the kill cue diverges from `Player.on_nearby_death`, which shakes for a death you merely *stood next to* (anyone's kill, including your own death) and fades to nothing by `death_shake_range` `8` m — so without this, a sniped kill, a thrown knife across a room, a DoT tick or a fall you caused would land with no camera answer at all. Point-blank both fire; `shake()` clamps to `ScreenShake.MAX_TRAUMA`, so they saturate rather than spike and the in-your-face kill stays the most violent. It honours **Options → Accessibility → Screen Shake** (that slider scales `intensity_multiplier`, so `0` removes the kick along with every other shake) — the shake counterpart to the "Screen Flashes" toggle the two flashes honour.
  - **Three guarantees come free from that seam, so no damage path needs a corpse check of its own.** It fires **once per victim** (`take_damage`'s `_dead` latch is the authoritative "this hit was the kill" edge, so a shotgun's remaining pellets or a second grenade on a body cannot re-pop it); **never on a suicide** (`_resolve_killer` nulls out `killer == self`, so your own blast can't congratulate you); and **never for an NPC's kill**, because `Character.on_scored_kill()` is a **no-op** and only `Player` overrides it — NPC-vs-NPC infighting still collects its bounty one line up without touching your sky.
  - **A kill with nobody credited flashes nothing**, by design: a hazard zone, ambient DoT or a plain unprovoked fall resolves to a null killer. There is no player to congratulate.
  - **Adding a new damage source needs no wiring at all** — route it through `Character.take_damage` with the attacker credited (which you already must, for the bounty, XP and kill-quests) and the flash comes with it. `tests/test_character.gd` pins all of the above off-tree via a `_KillSpy` subclass that neuters `_begin_death()`.
- **Doors, trigger volumes and spawners now ship as drop-in components.** Drop `res://scenes/components/door.tscn` (a `Door` that swings open on Interact, lockable by item or flag), `res://scenes/components/trigger_volume.tscn` (a `TriggerVolume` that fires configurable actions -- set a flag, start dialogue, play audio, call a method, spawn a wave -- when a body enters/exits its zone), and an `EncounterSpawner` node (spawns NPCs from `SpawnDefinition`s, typically fired by a trigger). All three are configured entirely in the inspector -- no code. See **Triggers, encounters & cutscenes** below for the full treatment.
- **The level seam is the path now (`GameRoot` + `LevelData`).** A `LevelData` `.tres` bundles a level's `scene` + `display_name` + `music` + `ambience` + an optional `map_data` (authored minimap underlay, §16); the `GameRoot` in `game.tscn` loads it as the `Level` child and places the player at a `PlayerSpawn` (the `WeaponData` / `NpcData` pattern). To change the starting level, set `GameRoot.level`; to travel between levels in-game, use a `LevelDoor`. Authored `LevelData` live in `resources/levels/` (see `TestLevel.tres`) — no per-level `game.tscn` copy.
- A panorama that isn't a true 360° photo will look stretched when wrapped — raise the shader's `pano_tiles` (and nudge `band_top` / `band_bottom`) to fix it.

Relevant files: `res://scenes/levels/TestLevel.tscn`, `res://scenes/game.tscn`, `res://scripts/effects/star_sky.gd`, `res://resources/shaders/horizon_sky.gdshader`, `res://resources/tuning/EffectsSettings.gd` / `.tres`.

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

This is the payoff and the reason flags are the spine: **setting a flag to a truthy value auto-advances any active quest's `FLAG` objective whose `target_id` matches.** `set_flag` calls `_advance_flag_objectives` internally, which bumps every matching objective by one. That makes flags the **universal "something happened → a quest step ticks" hook** — you never wire the trigger to the quest by hand. Drop a `TriggerVolume` that sets `&"reached_the_roof"`, author a quest objective `type = FLAG, target_id = &"reached_the_roof"`, and walking into the volume advances the quest. (Setting a flag to a *falsy* value — `false` or `0` — does **not** advance anything.) `set_flag` also queues a world-state autosave on **every** write (truthy or not), and a truthy one can **close** a quest window as well as advance one — see the Gotchas below.

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
- **A flag name is a shared namespace — it can FAIL a quest as well as advance one.** A truthy `set_flag` calls `_expire_quests_on_flag` alongside `_advance_flag_objectives`: every **ACTIVE** quest whose `expire_on_flag` matches that name is auto-**failed**, and a failed quest can never be re-started. Before reusing a flag name, check that no quest keys on it as its `expire_on_flag` (see "Failing and expiring a quest" under §14).
- **There's nothing to drop for the flag itself.** Flags aren't a component or a resource — they're pure runtime world-state on `GameState`. You author the *producers* (`TriggerVolume`, Cutscene actions) and *consumers* (quest objectives, gating scripts); the flag is just the shared name connecting them. Keep names stable — a typo'd `target_id` silently never advances.
- **New Game clears all flags.** Don't rely on a flag persisting across a fresh run; it's run-scoped profile state, not project content.
- **Chained quests back-fill an already-set flag.** Starting a quest whose `FLAG` objective keys on a flag that is *already* set satisfies that objective immediately — a chained quest that follows a flag an earlier quest (or trigger) already flipped doesn't stall waiting for a set that will never fire again. Only a truthy flag back-fills; a falsy/unset one doesn't. So you can safely gate a follow-up quest on a milestone flag the player has already passed.

Relevant files: `res://managers/GameState.gd` (the flags API + the FLAG→quest hook), `res://scripts/components/trigger_volume.gd` (`set_flag` / `set_flag_value` / `trigger_once`), `res://scripts/quests/quest_objective.gd` (`type = FLAG`, `target_id`).

---

## Triggers, encounters & cutscenes

This is the "make things happen" layer — the glue that turns a static level into an authored experience. Three drop-in pieces compose every scripted beat in CYBER SUNDAY: a **`TriggerVolume`** detects when the player walks somewhere, an **`EncounterSpawner`** drops enemies on cue, and a **`Cutscene`** scripts a cinematic. None of it is code; you drop the nodes in, fill `@export` fields, and point them at each other in the inspector. The sanctioned pattern throughout is *a trigger fires a target* — the volume's generic `action`/`target` knobs call a named method on a spawner, a wave manager, a cutscene player, a door, anything.

### TriggerVolume — when a body enters a zone, do things

The **`TriggerVolume`** (`class_name TriggerVolume`, `@tool` `extends Area3D`, `res://scripts/components/trigger_volume.gd`) is the keystone "when X, do Y" primitive. A body in `trigger_group` enters the zone and it fires a configurable set of **independent** actions. Drop the prefab **`res://scenes/components/trigger_volume.tscn`** (a cylinder, `CylinderShape3D` radius `2.0` / height `3.0`) into your level and **resize its `CollisionShape3D`** to cover the area you want to watch.

**Gating (who fires it):**
- **`trigger_group`** (StringName) — only bodies in this group fire it (`&"Player"`). On `_ready()` the volume forces its `collision_mask` to **all layers** and filters by group instead — so it catches the player whatever physics layer it sits on, and **physics layer numbers never matter**. Just set the group.
- **`trigger_once`** (bool) — fire ONCE then stop monitoring, for one-shot story beats and ambushes (`false` = fires every entry).
- **`fire_on_exit`** (bool) — also fire when a body LEAVES the zone, not just on enter (`false` = enter only).

**Actions (each independent, each INERT when left unset):** a bare trigger with no actions filled in does nothing but emit its **`fired(activator)`** signal — which you can wire to anything in the editor. Fill in any combination of:
- **`set_flag`** (StringName) + **`set_flag_value`** (bool, `true`) — write a global story flag via `GameState.set_flag` (empty = none). The common "mark that this happened" case.
- **`start_dialogue`** (DialogueResource) — start a conversation via `DialogueManager.start`, with the activator as the speaker.
- **`activate_node_path`** (NodePath) — the **"arm a sleeping node"** pattern: re-enables `process` + `physics_process` + visibility on a node you left switched OFF in the editor (e.g. a dormant `EncounterSpawner` or another trigger).
- **`play_audio`** (AudioStream) + **`audio_bus`** (StringName, `&"sfx"`) — play a positional sound at the volume, routed to the named bus so its volume slider applies.
- **`action`** (StringName) + **`target`** (NodePath) — **the generic escape hatch.** Calls the method named in `action` on the `target` node (e.g. `action = &"trigger_spawn"`, `target =` an EncounterSpawner). This is how a trigger drives the spawner/wave/cutscene systems below. Ignored when `action` is blank.

- **`toast_text`** (String) + **`toast_color`** (Color, white) — pop an on-screen toast through the player's HUD when fired (e.g. "Area secured"). Empty = none. The designer-fireable notice, no scripting.

**Quest actions (the `Quest` group — wire a trigger straight to the quest log, no escape hatch needed):**
- **`start_quest`** (Quest) — begin tracking this quest (`GameState.start_quest`) when fired. Empty = none. The "walk in, the quest starts" beat (and it's safe to re-enter — `start_quest` no-ops on an already-active/completed quest).
- **`complete_quest_id`** (StringName) — turn a quest in by id (`GameState.complete_quest`) when fired — the explicit completion path for a quest authored with `auto_complete = false`. Empty = none.
- **`advance_quest_id`** (StringName) + **`advance_objective_id`** (StringName) — bump objective `advance_objective_id` of quest `advance_quest_id` by one when fired (`GameState.advance_objective`). **BOTH are required** — the `@tool` script config-warns if you set one without the other. This is the clean way to tick a `USE_ITEM`/`FLAG`-less step on entry.
- **`quest_area_id`** (StringName) — notify any active **`ENTER_AREA`** objective whose `target_id` matches this name (`GameState.notify_enter`) when fired. Empty = none. **This is the sanctioned hook for `ENTER_AREA` objectives** — drop a volume at the area, set `quest_area_id` to the objective's `target_id`, done.

> **Prefer the typed quest fields over the generic `action`/`target`.** A `TriggerVolume` now talks to the quest system directly through the `Quest` group above; you no longer reach for `action = &"advance_objective"`. The `action`/`target` escape hatch is for *non-quest* targets (a spawner, a Door, a `WaveManager`, a `CutscenePlayer`).

`fire(activator)` is public, so a test — or a `Switch`, which dispatches by the method's arity and hands the activator through — can drive it directly. But a `TriggerVolume`'s own `action`/`target` hop and a cutscene's CALL_METHOD step both call the named method with **NO arguments**, so those two can only target zero-arg methods (`trigger_spawn`, `start`, `open`, `play`) — never `fire`. Neither one config-warns about it, because both check only that the method exists. The `@tool` script config-warns in the editor if there's no `CollisionShape3D` child (the volume can't detect anything without one).
#### TutorialPrompt — a one-time "how to" tooltip volume

A **`TutorialPrompt`** (`class_name TutorialPrompt`, `@tool` `extends TriggerVolume`, `res://scripts/components/tutorial_prompt.gd`) is a drop-in volume that teaches a verb the first time the player walks into it -- and never again. Because it **subclasses `TriggerVolume`**, every base action above (set_flag, audio, dialogue, the quest hooks) still fires alongside the prompt if you also fill them in; the prompt is just an extra thing it does on entry. It's **INERT until you set `prompt_text`**.

Drop it where the player first needs the verb, **resize its `CollisionShape3D`**, and set:

- **`prompt_text`** (String, multiline, default `""`) — the tutorial line shown on entry. Write **`{action}` tokens** and each is replaced with the player's CURRENT binding for that input action: `"Press {PickUp} to open doors"` -> `"Press E to open doors"`, and it updates live if they rebind. The token takes the **action NAME**, not its Options label -- the interact action is `PickUp` (labelled "Interact" in Options -> Controls, bound to `E` by default); an unknown action renders as `"(none)"`. The substitution is bare, so author your own brackets if you want them: `"Press [{PickUp}] to open doors"`. Empty = teaches nothing (inert).
- **`prompt_color`** (Color, default `Color(0.85, 0.95, 1.0)`) — the colour of the prompt toast.
- **`seen_flag`** (StringName, default `&""`) — a **persistent "already shown" flag** (stored on `GameState`, so it survives save/reload and new sessions). Once shown, this is set and the prompt **never repeats** -- on re-entry, reload, or a fresh session. **Give each prompt a UNIQUE flag.** Blank = NON-persistent (shows on every entry -- a deliberately repeating reminder).

The `@tool` script config-warns if `prompt_text` is empty (it teaches nothing) or if `seen_flag` is blank (it will repeat on every entry -- the reminder you usually don't want).

> **Worked example -- teach the interact key once.** Drop a `TutorialPrompt` across the corridor leading to the first door. Set `prompt_text` = `"Press {PickUp} to open doors"`, leave `prompt_color`, and set `seen_flag` = `&"tut_seen_interact"`. Walk in: the toast shows `"Press E to open doors"` once and is remembered forever -- reloading or replaying never repeats it. If the player rebinds Interact to F, a fresh prompt (different `seen_flag`) would read `"Press F..."` automatically.


### Encounter spawning — EncounterSpawner / SpawnDefinition / WaveManager

Instead of hand-placing every enemy alive from frame one, you author *what spawns* as data and fire it on cue.

#### EncounterSpawner

The **`EncounterSpawner`** (`class_name EncounterSpawner`, `@tool` `extends Node3D`, `res://scripts/components/encounter_spawner.gd`) holds your spawn list:
- **`spawn_definitions`** (`Array[SpawnDefinition]`) — one row per enemy group to spawn (see below).
- **`spawn_points`** (`Array[NodePath]`) — OPTIONAL exact spawn markers (`Marker3D` node paths). Spawns are placed at these points **in order, cycling**, instead of the random scatter. Empty (the default) = scatter within each definition's `spawn_radius`. Use markers for hand-placed cover positions; leave empty for a quick area drop.
- **`attach_scenes`** (`Array[PackedScene]`) — OPTIONAL components instanced under **every** spawned NPC — e.g. a `GuardDuty`, a `PatrolBehavior`, a `CutsceneActor`. So a whole wave arrives **pre-configured with behaviour**, no per-NPC editing after the fact. (They're added in-tree, so their `_ready` resolves the world.)

**Signals & queries (for "clear the room" gates and a live counter):**
- **`spawned(npc)`** — emitted for each NPC the spawner produces.
- **`cleared`** — emitted when every NPC this spawner ever produced is dead **or despawned** (a tracked spawn leaves on its `died` *or* `tree_exited`, whichever fires first). Fires **only after at least one spawn existed** — never on an empty spawner. Wire it to an exit `Door`'s `open`/unlock for a "clear the room to proceed" gate.
- **`alive_count_changed(count)`** — emitted after each spawn and each death; drive a "3 enemies left" HUD counter off it.
- **`alive_count()`** — the current live-spawn count (`0` once cleared).

It adds spawned NPCs as **SIBLINGS** — into `get_parent()`, the level around it — so **parent the spawner under your level's `Characters` node**, not under a stray root, or the enemies land in the wrong place in the tree. `trigger_spawn()` fires *every* definition (the common case); `trigger_spawn_wave(i)` fires just one by index; each spawn emits **`spawned(npc)`**. No spawner prefab ships — add the node yourself — but `res://resources/encounters/raider_squad.tres` is a shipped example `SpawnDefinition` (`NPC.tscn` ×3, `spawn_radius` `3.0`, `spawn_delay` `0.4`) you can assign straight into `spawn_definitions` or duplicate as a starting point.

#### SpawnDefinition

A **`SpawnDefinition`** (`class_name SpawnDefinition`, `@tool` `extends Resource`, `res://scripts/combat/spawn_definition.gd`) is one entry: which enemy, how many, and the per-spawn overrides.
- **`npc_scene`** (PackedScene) — the enemy scene to instance (e.g. `res://scenes/characters/NPC.tscn`).
- **`count`** (int, range `1..99`, `1`) — how many of it to spawn **at Normal difficulty**. At runtime the spawner scales it by `GameSettings.difficulty.enemy_count_mult` (Easy `0.7`, Hard `1.35`, rounded, never below 1 — see **"Difficulty: the live multipliers"**), so an authored `3` spawns 2 on Easy and 4 on Hard.
- **`spawn_radius`** (float, `2.0`) — scatter radius (m) the spawns land in, around the spawner.
- **`profile`** (NpcData) — OPTIONAL archetype stamped on each spawn. The **primary** override; a profile's faction WINS.
- **`faction_override`** (Faction) — OPTIONAL faction, applied only when no `profile` dictates one.
- **`weapon_override`** (WeaponData) — OPTIONAL weapon, applied only when no `profile` dictates one.
- **`auto_aggro`** (bool, `true`) — make each spawn immediately hostile to + targeting the `&"Player"` group on arrival (skips the perceive-first delay). Spawning this way does **NOT** cost the player faction reputation — it's rep-neutral, so an N-member wave never multiplies the faction-rep hit by the squad size. If you want a one-time faction-rep hit when the encounter trips, wire an **`AlarmPanel`** (it applies the penalty exactly once). Kills still apply `kill_penalty` per body.
- **`spawn_delay`** (float, `0.0`) — seconds between each NPC *within this one definition* (`0` = all at once).

**Override precedence:** `profile` > `faction_override` / `weapon_override`. They're stamped onto the NPC (via `npc.set(...)`) BEFORE `add_child`, so the NPC's `_ready()` picks them up.

#### WaveManager

For "clear the room over several waves," add a **`WaveManager`** (`class_name WaveManager`, `extends Node`, `res://scripts/components/wave_manager.gd`). It sequences a spawner's definitions as timed waves: fire definition 0, wait, fire definition 1, ….
- **`spawner_path`** (NodePath) — the `EncounterSpawner` to sequence (config-warns if empty).
- **`wave_interval`** (float, `5.0`) — seconds between waves.
- **`auto_start`** (bool, `false`) — begin on `_ready`; otherwise a trigger/cutscene calls `start()`.

`start()` fires **each `SpawnDefinition` as one timed wave**, `wave_interval` apart, emitting **`wave_started(index)`** per wave then **`all_waves_done`** at the end.
- **`wait_for_clear()`** — `await` until every NPC the spawner produced **across all waves** is dead (it tracks the spawner's `alive_count` + `cleared`). Crucially, a clear during an inter-wave lull does **not** resolve it — the loop keeps waiting while a run is in progress, so it only fires once the *last* wave is also down. Resolves immediately if nothing's alive and no run is going. Best awaited after / alongside `start()` — e.g. a quest step or an exit Door that unlocks once the whole arena is clear. (Distinct from the spawner's own `cleared` signal, which fires whenever the *currently-spawned* set empties — between waves that can be momentarily true.)

> **Two distinct timers.** `spawn_delay` staggers NPCs *inside a single definition*; `wave_interval` spaces *whole definitions apart* when a `WaveManager` drives them. A definition with `count = 5, spawn_delay = 0.3` drips five enemies in over a second-and-a-half; five definitions under a `WaveManager` with `wave_interval = 5.0` are five separate waves twenty-five seconds apart.

**Firing a spawner.** The sanctioned way is a `TriggerVolume` with `action = &"trigger_spawn"`, `target =` the spawner. For a `WaveManager`, point a trigger at it with `action = &"start"` instead.

#### NpcPool — reuse a fleet instead of instantiating per spawn (optional)

By default an `EncounterSpawner` **instances** each NPC on spawn and **frees** it on death. For a *repeating* fight — a horde arena, a respawning checkpoint, a wave gauntlet you re-trigger — that per-spawn `instantiate()` (which runs the full `NPC._ready`: weapon model, mesh swap, ~20 components) causes a visible hitch, and the churn of allocating/freeing bodies fragments memory. An **`NpcPool`** (`class_name NpcPool`, `@tool` `extends Node`, `res://scripts/components/npc_pool.gd`) fixes both: it builds a **fixed fleet up front** (paying that cost once, at level load, hidden), then hands bodies out on spawn and **parks** them on death for reuse. Reused bodies are **reset**, not rebuilt, so there's no per-spawn hitch and the body count stays flat.

**Wiring it (all inspector, no code):**
1. Drop an **`NpcPool`** node under your level.
2. On the `EncounterSpawner`, set **`pool`** (NodePath) to that pool. That's it — the spawner warms the pool with its own `spawn_definitions` at load and draws from it thereafter.
3. Leave `pool` **empty** on any spawner that shouldn't pool — it keeps the classic instance/free behaviour, unchanged.

**How bodies are matched.** The pool buckets bodies by **loadout** = `npc_scene` + `profile` + `faction_override` + `weapon_override`. Two definitions with the *same* four share a bucket, so a reused body already wears the right archetype/weapon/appearance — reuse never re-stamps a profile or re-swaps a mesh. If a wave asks for more bodies than were warmed (e.g. a difficulty multiplier pushed the count up), the pool instances a fresh one on the spot and adopts it, so a spawn **never fails** — the pool just grows to meet demand.

**Standalone prewarm (optional).** A pool not driven by a spawner can warm itself: fill its **`prewarm`** (`Array[SpawnDefinition]`) and it builds each entry's `count` bodies at load. The common case (a spawner points at it) needs this left empty.

**Limitations — when NOT to pool (documented, by design):**
- A pooled NPC **skips the "freeze-then-explode" death beat** (that freeze disables processing irreversibly). Its death still spawns a lootable corpse + gibs + loot exactly as normal — including the **body-part burst**, which duplicates the body's parts rather than taking them, so a recycled body comes back whole; it just doesn't hold the brief freeze pose. Fine for trash mobs — the whole point of a pool.
- **`attach_scenes` + `pool` warns.** A pooled body gets its `attach_scenes` components **once** (at warm time) and keeps them across lives; their per-life state is **not** reset on reuse, and their `_ready` resolves the world at the *pool's* location, not the spawn point (fine for group/NodePath-resolved behaviour like GuardDuty; wrong for anything that reads its spawn position). Only pool spawners whose attach components are stateless. The `@tool` spawner config-warns if you set both.
- **Don't share one pool across spawners with *different* `attach_scenes`.** The pool buckets by loadout only, so a recycled body from spawner A (with A's GuardDuty) could be handed to spawner B (which declared none) — B's "plain" enemy would arrive running A's behaviour. Give each distinct-attach spawner its own `NpcPool`, or keep their `attach_scenes` identical.
- A **`RandomInventory` / `RandomCoat`** roll is **not** re-rolled on reuse (the body re-seeds its *authored* loadout deterministically). Pool homogeneous loadouts, not randomised ones.
- Pooling is for **dynamic encounter enemies** — pooled bodies are excluded from the exact-save tier (same as any runtime spawn today), so don't pool a hand-placed authored NPC you expect a quicksave to restore.

### Cutscenes — Cutscene / CutsceneAction / CutscenePlayer

A cutscene is an ordered list of steps a player runs while control is locked — wait, set a flag, call a method, play a line of dialogue, ease a cinematic camera, fade the screen.

#### Cutscene

A **`Cutscene`** (`class_name Cutscene`, `@tool` `extends Resource`, `res://scripts/combat/cutscene.gd`) is the script itself — author it as a `.tres`.
- **`actions`** (`Array[CutsceneAction]`) — the ordered steps. Player control + the gameplay camera are always restored when the last action finishes (or on Escape).

#### CutsceneAction

A **`CutsceneAction`** (`class_name CutsceneAction`, `@tool` `extends Resource`, `res://scripts/combat/cutscene_action.gd`) is one step. Its **`type`** selects which grouped fields apply:
- **`type`** (enum `Type { WAIT, SET_FLAG, CALL_METHOD, DIALOGUE, CAMERA_MOVE, FADE }`, default `WAIT`).

> The `type` enum has grown to `Type { WAIT, SET_FLAG, CALL_METHOD, DIALOGUE, CAMERA_MOVE, FADE, TOAST, CAPTION, WALK_TO, FACE, PLAY_ANIM }`. The five new beats — an on-screen toast, a centred caption, and three **actor** verbs (walk / face / pose) — are documented below; the camera fields are now much richer.

- *Toast group:* **`toast_text`** (String) + **`toast_color`** (Color, white) — flash a HUD toast (`UI.toast`) and continue immediately. Empty = nothing shown. (Distinct from CAPTION: a toast is the corner notice; a caption is the centred title card.)
- *Caption group:* **`caption_text`** (String) + **`caption_color`** (Color, white, outlined black so it reads over anything) — show a centred cinematic caption ("Three days later…") for `duration` seconds, then clear it. **Leave `duration` at `0` to HOLD the caption until the cutscene ends** (`_finish` clears it). Empty `caption_text` = nothing shown.
- *Actor group* (the WALK_TO / FACE / PLAY_ANIM steps — see **CutsceneActor** below):
  - **`actor_path`** (NodePath) — the `CutsceneActor` (or an NPC addressed directly) this step drives. **Resolving it suppresses that NPC's AI brain** so it won't fight the scripted blocking; control is auto-released when the cutscene ends (even on skip).
  - **`actor_target`** (NodePath) — WALK_TO / FACE destination as a live NODE (its position is read each call, so the actor walks to / faces a moving marker). Overrides `actor_point` when set.
  - **`actor_point`** (Vector3) — WALK_TO / FACE destination as a raw world position (used when `actor_target` is empty).
  - **`anim_name`** (StringName) — animation to play for a PLAY_ANIM step, on the actor's assigned `AnimationPlayer` if it has one. **Actors are procedural by default, so PLAY_ANIM is usually a no-op** — wiring a real rig is a separate art task.
  - WALK_TO honours `duration`: the step holds for `duration` seconds so the *next* step waits out the walk (`0` = fire-and-continue). FACE and PLAY_ANIM are issued instantly.
- **`duration`** (float, `1.0`) — seconds this step takes; used by **WAIT / CAMERA_MOVE / FADE**.
- *Set Flag group:* **`flag_name`** (StringName) + **`flag_value`** (bool, `true`) → `GameState.set_flag`.
- *Call Method group:* **`event_node_path`** (NodePath) + **`event_method`** (StringName) — call a method on a node. **This is the cross-system glue** — call `trigger_spawn` on a spawner, `open` on a Door, `start` on a `WaveManager`, `play` on another `CutscenePlayer`. The step passes **NO arguments**, so the target method must take none — `TriggerVolume.fire(activator)` can't be driven this way, and the config warning won't catch it (it only checks that the method exists).
- *Dialogue group:* **`dialogue`** (DialogueResource) — play a conversation; the cutscene WAITS for it to finish.
- *Camera Move group:* the cinematic camera eases (or snaps) to a new framing over `duration`.
  - **`camera_position`** (Vector3) — the world position to ease to — OR, when `camera_follow` is set, the **OFFSET** from the followed node (so the camera trails a moving subject at this relative position).
  - **`camera_rotation`** (Vector3, in **DEGREES** — converted to radians at runtime) — the world rotation to ease to. Ignored when `camera_look_at` is set.
  - **`camera_look_at`** (NodePath) — OPTIONAL node to keep framed: the camera looks at it **every frame** of the move (a moving subject stays centred), overriding `camera_rotation`. Empty = ease to `camera_rotation`.
  - **`camera_follow`** (NodePath) — OPTIONAL node to follow: the camera's target becomes `that node's position + camera_position` (the offset), tracked live, so it trails a moving subject. Empty = ease to the absolute `camera_position`.
  - **`camera_fov`** (float, `0.0`) — target field of view (degrees) eased to over the move — a dolly zoom. **`0` = leave the FOV unchanged.**
  - **`camera_snap`** (bool, `false`) — snap-cut instantly to the framing (a hard cut) instead of easing.
  - **`camera_ease`** (`Tween.EaseType`, `EASE_IN_OUT`) + **`camera_trans`** (`Tween.TransitionType`, `TRANS_SINE`) — the easing curve / transition for the move (ignored when `camera_snap` is on).
- *Fade group:* **`fade_color`** (Color, `Color(0,0,0,1)`) — the screen eases TO this colour over `duration`. **Alpha drives it:** `a = 1` fades to opaque (out), `a = 0` fades back in.

#### CutscenePlayer

A **`CutscenePlayer`** (`class_name CutscenePlayer`, `extends Node`, `res://scripts/components/cutscene_player.gd`) runs a cutscene at runtime.
- **`cutscene`** (Cutscene) — the cutscene `play()` runs.

Fire it with the **no-arg `play()`** (so a `TriggerVolume` with `action = &"play"`, `target =` this player drives it) or `play_cutscene(c)` for an ad-hoc one. While ANY cutscene plays, **player control is LOCKED** — playback sets the static `CutscenePlayer.is_active()` flag, which `InputManager.gameplay_suppressed()` reads (the single sanctioned place to register a control-suppressing overlay). **Escape (`ui_cancel`) skips** the rest. It emits **`cutscene_started`** / **`cutscene_finished`**. CAMERA_MOVE lazily builds its own `Camera3D` (and hands `current` back to the gameplay camera at the end); FADE lazily builds a full-screen `ColorRect` on its own `CanvasLayer` above the HUD. No `CutscenePlayer` prefab ships — add the node yourself — but `res://resources/cutscenes/sample_cutscene.tres` is a shipped example `Cutscene` (a 2.5 s CAPTION → a 0.5 s WAIT → a TOAST reading "Objective updated") to assign or duplicate. Its CAPTION step has an EMPTY `caption_text`, though, so fill that in before you expect to see anything on screen.

The player builds its overlays on demand and stacks them correctly: CAPTION gets its own `CanvasLayer` at **layer 101 — above** FADE's layer-100 rect, so a caption reads over a faded-black screen. **Player control + the gameplay camera are restored unconditionally** at the end (and on Escape-skip): there is no "auto end" toggle — `_finish` always reclaims the camera, clears a held caption, fades the rect back to transparent, and releases every staged actor. (If you remember a `Cutscene.auto_end` field, it's gone — control restore is no longer optional.)

> **Why a step "hangs" the cutscene.** DIALOGUE waits for `DialogueManager.dialogue_finished`; CAMERA_MOVE and FADE wait out their tween (`duration`); a CAPTION with `duration > 0` waits, then clears; WALK_TO waits `duration` seconds; and a WAIT waits `duration` seconds (default `1.0` — a WAIT is only a no-op at `duration = 0`). SET_FLAG/CALL_METHOD/TOAST/FACE/PLAY_ANIM are instant and fall straight through to the next step. Sequence accordingly — e.g. put a WALK_TO with a non-zero `duration` before the line you want spoken *after* the actor arrives.

#### CutsceneActor (`res://scripts/components/cutscene_actor.gd`)

The **`CutsceneActor`** (`class_name CutsceneActor`, `@tool` `extends Node`) is the bridge that lets a `Cutscene` *block* an NPC — walk it to a mark, turn it to face someone, play a pose — **with the NPC's AI brain suppressed** so it doesn't wander off or open fire mid-scene. Drop it **under the NPC** you want to stage (or point `npc_path` at one), then address it from a WALK_TO / FACE / PLAY_ANIM `CutsceneAction`'s `actor_path`.

- **`npc_path`** (NodePath) — the NPC this actor drives. **Empty = this node's parent** (the common case: child it under the NPC and leave this blank).
- **`animation_player_path`** (NodePath) — OPTIONAL `AnimationPlayer` for PLAY_ANIM. Actors are procedural (`BodyModelSwap`), so this is usually empty and PLAY_ANIM does nothing; a real rig is a separate art task.

Its API (called by the `CutscenePlayer`, but public so a CALL_METHOD step or a test can drive it): **`begin()`** (take cutscene control — suppress the brain; idempotent), **`walk_to(point)`**, **`face(point)`**, **`play_anim(anim)`**, and **`end()`** (release control — the AI resumes). The `@tool` script config-warns if it has no NPC or the NPC can't be cutscene-controlled.

> **You don't even need a `CutsceneActor`.** A WALK_TO / FACE / PLAY_ANIM step can point `actor_path` *straight at the NPC* — the player calls `begin`/`walk_to`/`face`/`play_anim`/`end` if present, else falls back to the NPC's own `set_cutscene_control` + `walk_to` + `face`. The `CutsceneActor` exists for the tidy "drop a behaviour node under the NPC" idiom and so you can keep an `AnimationPlayer` reference local to it.

> **The brain is ALWAYS handed back.** Every actor a cutscene took control of is released in `CutscenePlayer._finish` — including on Escape-skip — so an NPC can never be left frozen. Don't worry about "un-suppressing" by hand.

### Worked example — ambush on entry

> Goal: the player walks into a room, three raiders spawn around them and attack, and a story flag records it — once.

1. Under your level's **`Characters`** node, add an **`EncounterSpawner`**.
2. Expand its `spawn_definitions`, set size **1**, and open element `[0]` (a `SpawnDefinition`):
   - `npc_scene` = your enemy scene (e.g. `res://scenes/characters/NPC.tscn`)
   - `count` = `3`
   - `spawn_radius` = `4.0`
   - `profile` = `res://resources/characters/raider.tres`, the shipped raider archetype (its faction wins — no need to set `faction_override`)
   - `auto_aggro` = `true`
3. Drop **`trigger_volume.tscn`** into the room and size its `CollisionShape3D` to cover the doorway/floor. Set:
   - `trigger_group` = `&"Player"`
   - `trigger_once` = `true`
   - `action` = `&"trigger_spawn"`, `target` = the EncounterSpawner
   - `set_flag` = `&"ambush_sprung"`
4. Run, walk in once → 3 raiders spawn within 4 m and provoke (3 is the **Normal** count — 2 on Easy, 4 on Hard), the `ambush_sprung` flag flips, and the volume stops monitoring (it never fires again).

For an **intro cutscene**, author a `Cutscene` `.tres` whose `actions` are, in order: a **FADE** to `fade_color` alpha `1` with `duration` ~`0.01` (the fade overlay is built TRANSPARENT, so you must snap it to black first — a lone alpha-`0` FADE at the head of a cutscene tweens transparent to transparent and does nothing but burn its `duration`), a **CAMERA_MOVE** to your establishing shot, a **FADE** to alpha `0` to fade up into it, a **DIALOGUE** line, a **CALL_METHOD** (`event_method = &"trigger_spawn"` on the spawner) to drop the enemies on the beat, a **FADE** back, and a **SET_FLAG** `&"intro_seen"`. Add a `CutscenePlayer`, set its `cutscene`, and point a `trigger_once` `TriggerVolume` at it with `action = &"play"`.

### Gotchas

- **Parent the EncounterSpawner under `Characters`.** It adds spawns as siblings (into `get_parent()`), so a spawner sitting on a stray root puts your enemies in the wrong branch of the tree.
- **Physics layers don't gate a TriggerVolume — the group does.** The volume forces `collision_mask` to all layers and filters by `trigger_group`. If the trigger never fires, check the body's *group membership*, not its collision layer.
- **`trigger_once` is one-and-done.** Once spent it stops monitoring entirely — it won't fire on exit again either. Use a non-once volume for repeatable beats.
- **Profile beats the overrides.** `faction_override` / `weapon_override` only apply when no `profile` dictates one. If you assigned a `profile`, its faction/weapon win — clearing the overrides won't change anything.
- **Two spawn timers, two scopes.** `spawn_delay` is *within* a definition; `wave_interval` is *between* definitions under a `WaveManager`. Don't reach for one expecting the other's behaviour.
- **Cutscenes lock control globally.** While one plays, `InputManager.gameplay_suppressed()` is true via the static `is_active()` flag — that's intentional. Escape is the only way out mid-scene. Don't add a second control-suppression path; register overlays through that one flag.
- **The player takes NO damage while a cutscene plays (or during dialogue).** `InputManager.world_frozen()` (true whenever a cutscene is active OR a conversation is up) gates `Player.take_damage`, and freezes `HazardZone` and `StatusEffectManager` bookkeeping so durations don't burn — so a scripted hazard beat (a blast, a fire, a DoT tick) won't actually hurt the player until the cutscene ends. Sequence any "damage the player on this beat" effect to fire *after* the scene, not during it.
- **CAMERA_MOVE rotation is in degrees.** Author `camera_rotation` as degrees in the inspector; it's converted to radians at runtime. **`camera_look_at` overrides it** — set a look-at node and the camera frames that subject every frame, ignoring `camera_rotation`. **`camera_follow` re-purposes `camera_position` as an OFFSET** from the followed node, not an absolute point. `camera_fov = 0` leaves the FOV alone; `camera_snap` hard-cuts instead of easing. FADE is alpha-driven — `a = 1` goes to opaque, `a = 0` clears.
- **Only `trigger_volume.tscn` ships as a prefab.** `EncounterSpawner`, `WaveManager`, `NpcPool` and `CutscenePlayer` are bare nodes you add yourself. Example RESOURCES do ship, though: `res://resources/encounters/raider_squad.tres` (a `SpawnDefinition` already wired to the `raider.tres` archetype — 3 SMG raiders) and `res://resources/cutscenes/sample_cutscene.tres` (a `Cutscene`).

Relevant files: `res://scripts/components/trigger_volume.gd`, `encounter_spawner.gd`, `wave_manager.gd`, `cutscene_player.gd`; `res://scripts/combat/spawn_definition.gd`, `cutscene.gd`, `cutscene_action.gd`; prefab `res://scenes/components/trigger_volume.tscn`.

---

## Placing and configuring NPCs

Every non-player actor in CYBER SUNDAY -- from a townsperson who just wanders to a sniper who locks on and fires -- is the **same** `NPC` node (`rpg/scripts/npc/npc.gd`, `extends Character`). There are no enemy/civilian subclasses; behaviour is driven entirely by the inspector fields you set. This section walks you through dropping one in and configuring it.

### Step 1 — Instance the NPC scene

The ready-to-use prefab is `res://scenes/characters/NPC.tscn`. It inherits from the base `enemy.tscn`, which already wires up the `BodyModelSwap` body component (it IS the visible body — the swapped torso/head/arms/legs; there is no longer a separate default `Man.glb` body node), the collision capsule, and the `damaged`/`died` signal connections. (The on-death drop is set on `NPC.tscn` itself via `ragdoll_scene`, not on the base — it ships pointed at the `LootBag` (`scenes/props/loot_bag.tscn`), so a killed enemy leaves a lootable bag on the floor; swap it for the rigged `skeleton.tscn` there if you'd rather it drop a ragdoll corpse.) You almost never start from `enemy.tscn` directly -- `NPC.tscn` is the configured starting point.

1. In the scene you're building (e.g. `Level.tscn`), open the **Scene** menu or drag from the FileSystem dock: instance `res://scenes/characters/NPC.tscn` as a child of your level.
2. Move/rotate it into place with the gizmo. The NPC remembers its spawn position and facing at `_ready` -- wandering strays from there, and after losing you it searches around that spot.
3. Select the instance and configure it in the **Inspector**. Everything below is an `@export` on the root node; you never open a script.

> If you need to tweak the body/head meshes or per-limb tints for this one instance, you don't have to enable "Editable Children" -- the root exposes a **Body & Head → Custom Models → `look`** slot. Assign an `NpcLook` resource there (its fields are `body_model`, `body_texture`, `body_color`, `head_model`, `arm_color`, `leg_color`, etc.) and that NPC re-skins live in the editor. See "Customising an NPC look" below.

### Step 2 — The key inspector fields

#### Civilian vs combatant: `weapon_data` (group **Weapon**)

This single field decides what kind of actor you have:

- **`weapon_data` = null → CIVILIAN.** No gun, no laser, no fire path is built. The NPC still senses, wanders, flees, faces toward whoever shot it, and can talk. The stock `NPC.tscn` actually ships a `melee.tres` here; clear it to null for a true unarmed townsperson.
- **`weapon_data` = a `WeaponData` .tres → COMBATANT.** The NPC wields the *same* `Weapon` component the player does, aimed by the AI. It locks the nearest hostile (the player or a faction-opposed NPC), turns, aims, paints its laser, and fires once it has actually detected the target -- no 360-degree omniscience.

#### Attitude: `faction_id`, `disposition`, `disposition_overrides_faction` (group **Hostility**)

This is the FNV-style hostility model. Three fields work together:

- **`faction_id`** -- a dropdown (`PROPERTY_HINT_ENUM_SUGGESTION`) with `townsfolk`, `raiders`, `neutral_wildlife`. Pick one and it resolves to the matching Faction `.tres` (from `res://resources/factions/`) at `_ready`. A factioned NPC's attitude toward the player tracks the player's **reputation** with that faction, and it fights NPCs of opposed factions.
- **`faction`** -- a raw `Faction` slot, used only if you leave `faction_id` empty (for a custom/inline faction). Empty id **and** null faction = **UNALIGNED**.
- **`disposition`** (`Disposition.Kind`: `HOSTILE` / `NEUTRAL` / `FRIENDLY`) -- the standalone attitude, used **only when the NPC is unaligned** (no faction). It defaults to `HOSTILE`, so an armed NPC with no faction behaves like a classic enemy.
- **`disposition_overrides_faction`** -- set this true and the NPC's individual `disposition` wins toward the player even though it has a faction (the faction still drives reputation and NPC-vs-NPC relations). Use it for, say, one raider who's personally friendly to you.

The combat outline rim re-tints from this automatically: HOSTILE = red, FRIENDLY = green, NEUTRAL = the `outline_color` export (black by default; NPCs are excluded from the world's InkOutline ink pass, so the rim never doubles with it). A recruited companion wears blue. (The hostile/friendly rim colours come from `CBPalette`, so with the colorblind-safe cues toggle on they shift to orange/cyan. The companion blue is a fixed `NPC.OUTLINE_FOLLOWING` const and does not shift -- `CBPalette`'s periwinkle ally colour applies to the hover/dialogue NAME readout, not the rim.) (`friendly_aggro_threshold`, also in this group, is how much accidental player damage a FRIENDLY ally forgives before it turns on you.)

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
- **`pursuit_grace_time`** (s) -- how long it keeps **chasing your live position** after losing sight (you dropped off a ledge, ducked behind cover) before it downgrades to searching your last-known spot. This is the "follow me off a ledge" window: without it, an enemy that lost line of sight the instant you dropped would freeze at the top and never commit over the edge. `0` = the old instant give-up. (The Locomotor's `max_pursuit_drop` caps how *deep* a drop it will then leap off.)
- **`turn_speed`** -- how fast it rotates to face what it's tracking (this one lives in the **Perception** group, not Movement). Higher = snaps onto aim quicker.

> **The stock `NPC.tscn` ships these COMBAT-tuned, not at the class defaults.** The prefab overrides `sight_range` -> **500**, `time_to_detect` -> **0.1**, `forget_time` -> **1.0**, `turn_speed` -> **20** (and `fire_range` -> 0.5): an instantly-alert, far-seeing fighter. The gentler class defaults (`sight_range` 25, `time_to_detect` 1.0, `forget_time` 4.0, `turn_speed` 8; `fov_degrees` 110 is the one the prefab leaves alone) only describe a bare actor. So a freshly-placed `NPC.tscn` reacts *much* faster than the field descriptions alone suggest -- dial these down for a sleepier guard.

Also here: `crouch_sight_mult` (how much crouching shortens its sight), `eye_height` (where its rays start), `hearing` (notice gunfire/fast movement outside the cone), and `search_sweep_rate` (how fast it scans in a circle when looking around at a spot). Two further groups shape *how fast* the meter fills (all behaviour-preserving by default) — but read them as **code-level defaults, not inspector knobs**: they live on the **`Perception` child node** (`scripts/npc/perception.gd`), which no scene authors — `npc.gd`'s `_build_perception()` constructs it at spawn and mirrors only the sight/hearing fields above onto it — so there is no node to reach via Editable Children and `NpcData` has no field for any of them: the **Sight Falloff** group — `range_falloff` / `peripheral_falloff` (Curves: a far or cone-edge target fills the meter slower; unset = no falloff), `light_falloff` (Curve: a target in shadow fills slower; unset = fall back to the global `GameSettings.light_stealth` curve — the implemented-but-unreachable per-archetype override of the light/shadow pillar), and `min_visibility` (`0.15`, the floor so a real sighting still reaches ALERTED eventually) — and the **Suspicion** group (`suspicion_wary_threshold` `0.15` / `suspicion_suspicious_threshold` `0.6`, the meter levels that drive the graded WARY/SUSPICIOUS feedback tiers — deliberately global, so every enemy reads WARY/SUSPICIOUS at the same meter level). The shipped way to tune how much darkness slows detection is the **global** `GameSettings.light_stealth` curve (`LightStealthSettings.tres`, §12/§19). The per-NPC **stealth-sense opt-ins** — `hearing_initiates_opt_in` and `body_discovery_opt_in` (both default off) — are `@export`s on the **NPC ROOT** (npc.gd's `Perception` `@export_group`), so you set them straight in the NPC-root inspector — unlike the Sight Falloff / Suspicion fields above, which aren't inspector-reachable at all. They wake just THIS NPC's ears/body-discovery, OR'd with the global `NpcAiSettings` flags (§19). The richer "hunt a widening area" search -- breadcrumbs around the last-known spot + a frantic→resigned falloff, and the [CAUTION] HUD readout while it hunts -- is a **global** tuning group: `GameSettings.search` (`SearchSettings.tres`). It already overrides `max_search_radius` -> **`10.0`**, so a lost-target hunt sweeps a real 10 m breadcrumb ring out of the box; only `sample_points` is still inert at `1` -- raise it (and optionally widen `max_search_radius`) to broaden the sweep. The per-archetype hunt mutter ("Where are you?") is gated by **`NpcData.search_barks`** (default on, alongside `damage_barks` / `death_barks`). (Full reference for the Sight Falloff / Suspicion code defaults and the `hearing_initiates_opt_in` / `body_discovery_opt_in` stealth opt-ins: see **"Stealth and detection."**)

#### Loadout: `item_stacks` (group **Inventory**)

These are the items the NPC actually **carries** -- pickpocketable and dropped on its corpse -- seeded on top of the weapon and ammo from `weapon_data`:

- **`item_stacks`** -- an `Array[ItemStack]`, the count-based contents list: "30 ammo, 2 stims, 1 keycard" as item+count rows. Weapons are duplicated to unique instances; if an `item_stacks` weapon is stronger than `weapon_data`, the NPC actually draws that one.

These are deterministic carried inventory. (The random drop table is a separate concept and exists on BOTH -- the NPC root's **Loot → `loot`** slot for a one-off, and `NpcData.loot` on an archetype; a profile's `loot` wins whenever a profile is assigned, even if it's empty.)
#### Group AI: alerting allies (group **Group AI (allies)**)

By default each NPC fights as a solo island — it never tells its squad you're there, and a firefight two rooms away is silent. This group wakes up coordinated group reactions. **Every field here is OFF / inert by default**, so existing encounters are unchanged until you opt a guard in.

- **`alert_radius`** (m) — **ALERT PROPAGATION (GA-1).** When this NPC gets first-hand contact (it goes ALERTED on a live target), it tells same-faction (or allied-faction) allies within this radius to converge and investigate the threat — so a squad reacts together. Latched once per engagement, and an *alerted* ally does NOT re-broadcast (it only investigates), so there's no alert storm. Default `0.0` = **OFF** (no propagation). Set e.g. `15` on a guard to make its patrol a reactive squad.
- **`gunfire_noise_radius`** (m) — audible reach of this NPC's GUNFIRE on the shared noise channel, so a guard elsewhere can HEAR the firefight and come look. Default `18.0`; `0` = its gunfire is silent. **INERT until a listener opts in** — a hearer only reacts to it when `hearing_initiates` is on (the global `GameSettings.npc_ai` flag, default off, OR a per-NPC `hearing_initiates_opt_in`; see the Perception group).
- **`death_noise_radius`** (m) — audible reach of this NPC's DEATH (a cry / thud) on the noise channel. Default `12.0`; `0` = silent. Same listener gate as gunfire.
- **`combat_noise_interval`** (s) — minimum seconds between gunfire-noise pulses, so a full-auto burst emits a steady pulse instead of one noise per bullet. Default `0.4`. (The death cry is one-shot and ignores this.)
- **`combat_noise_decay`** / **`combat_noise_lifetime`** — how fast each gunfire/death noise burst fades (m/s) and how long it lives (s). Defaults `0.0` / `0.35` — keep it brief, it's a momentary cue, never a lingering source.

> **Coordinated search comes free with `alert_radius` (GA-4).** When a squad is alerted via `alert_radius`, each ally is handed a **different sector** of the search origin instead of all piling onto the same breadcrumb, so they fan out and sweep different ground. There's no separate knob — it rides on GA-1 propagation automatically. How *thorough* each NPC's hunt is (single-point stare vs. a widening area sweep) is the global `GameSettings.search` group (`SearchSettings.tres`, see the Perception section), whose shipped `.tres` already overrides `max_search_radius = 10.0` (a live 10 m sweep); only `sample_points` is still inert at `1`.


### Worked example — a fleeing townsperson

You want a civilian who roams the market and runs when shot at:

1. Instance `NPC.tscn`, position it in the market.
2. **Weapon → `weapon_data`**: clear it to **null** (civilian).
3. **Hostility → `faction_id`**: `townsfolk`. (Now their attitude tracks your town reputation.)
4. **Behavior → `threat_response`**: `FLEE`; tick **`wanders`** on; set `wander_radius` to taste.
5. **Identity & Outline → `display_name`**: e.g. "Market Vendor" so dialogue and the kill feed name them.
6. **Inventory → `item_stacks`**: add a row (the `kickstart_stims` Item, count 2) so the body is worth pickpocketing.

Drop them in, hit play -- they pace the stall, greet you, and bolt if you draw on them, never shooting back.

### Step 3 — Archetypes: the `NpcData` profile (group **Profile**)

Configuring ~40 fields per NPC by hand gets tedious when you're placing a dozen raiders. The **`profile`** export (top of the inspector, group **Profile**) takes an `NpcData` resource (`rpg/scripts/npc/npc_data.gd`) -- a reusable **archetype** that stamps roughly 40 tuning fields onto the NPC at once.

**How it works:** assign a profile and `NPC._apply_profile()` (the first line of `_ready`) copies the archetype's values onto the matching exports -- `display_name`, `max_hp`, `stats`, the whole Hostility block, `weapon_data` + weapon tuning, all of Perception, all of Movement, `threat_response`, `temperament`, wander settings, talk settings, and so on. So a "raider" / "townsperson" / "sniper" becomes **one resource assignment** instead of dozens of inline overrides. `NpcData` also carries a few extras the inline NPC doesn't: the optional Identity **`id`** (a stable `StringName` identity key for quest KILL/TALK matching and the known-names ledger — blank falls back to `display_name`; deliberately never stamped onto the NPC, it's read from the archetype via `identity_key()`; see *Stranger names* and *Quests*), a `bark_set` (per-archetype voice lines, with the `damage_barks` / `death_barks` / `search_barks` gates) and the death opt-outs `sours_faction_on_death` / `pause_on_kill` / `freeze_on_death`.

**Profile vs inline:**

- **Assign a `profile`** → the NPC is driven *entirely* by that archetype. Any value you also set inline is overwritten at `_ready`, so don't mix. To vary one stat, author a variant `.tres`.
- **Leave `profile` null** → `_apply_profile()` is a no-op and your inline inspector values stand. Every existing scene does this, so they're unaffected.

**The additive merge (`profile_fills_blanks_only`):** by default a profile is all-or-nothing (it overwrites every field). Tick **`profile_fills_blanks_only`** on the NPC and it becomes ADDITIVE: the profile fills only the fields you left at their default, and any field you tweaked inline WINS -- so "use the raider archetype, but give THIS one more HP" works (assign the profile, tick the flag, bump HP). Cleanest from a blank base (`enemy.tscn` / `civilian.tscn`); `NPC.tscn` pre-sets combat fields (weapon, sight, fire range, ...) inline, so those would count as tweaks and win over the profile.

**When to use which:**

- **Use a profile** when you're placing several of the same kind of NPC, or want a named archetype you can retune in one place and have every instance pick up the change. Author them once in `res://resources/characters/` (right-click → New Resource → `NpcData`), like you author `WeaponData` or `Faction` .tres. Four ship today: **`raider.tres`** (SMG squad grunt — raiders faction, `raider_barks.tres` wired, wanders its camp; the one `raider_squad.tres` spawns), **`sniper.tres`** (long-range glass cannon — `sniper_wep.tres`, 150 m sight in an 85° cone, slow `turn_speed`, `starts_unloaded` so the first shot telegraphs, `search_barks` off = a silent stalker), **`Townsperson.tres`** (unarmed fleeing civilian) and **`DefaultCharacterRes.tres`** (generic armed hostile). Start from the closest of those instead of a blank resource.
- **Tune inline** for a true one-off -- a single named boss or a unique scripted character that doesn't share its numbers with anyone.

To make a profile: in the FileSystem dock, create a new `NpcData` resource, fill in its grouped fields (Identity, Vitals & outline, Hostility, Weapon, Inventory, Perception, Laser, Movement, Behavior, Barks, AI (GOAP), Loot, Death — the last carries the per-archetype `sours_faction_on_death` / `pause_on_kill` / `freeze_on_death` knobs), save it, then drag it onto an NPC instance's `profile` slot.

### Gotchas

- **`weapon_data` is the civilian/combatant switch -- and the stock `NPC.tscn` is NOT a civilian.** It ships with `melee.tres` assigned. For an unarmed townsperson you must explicitly clear `weapon_data` to null.
- **`disposition` only matters when the NPC is unaligned.** If you set a `faction_id`, the standalone `disposition` is ignored toward the player unless you also tick `disposition_overrides_faction`. A common mistake is setting both a faction and a FRIENDLY disposition and wondering why the NPC still tracks faction reputation.
- **Profile clobbers inline by default.** With a profile assigned, anything you type into the inline fields is stamped over at runtime -- UNLESS you tick `profile_fills_blanks_only` (then your inline tweaks win; see "The additive merge" above). If an instance "ignores" your inspector edits, check whether it has a `profile` and whether that flag is off. **The inspector now NAMES the fields it's about to eat** in the node's configuration warning (e.g. *"...OVERWRITES these inline edits: disposition, sitting"*), so you don't have to diff the archetype by hand -- the classic version of this bug is ticking `sitting` and setting `disposition = NEUTRAL` on an instance and getting a standing hostile in game, with no error anywhere.
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

**How it wires up (automatically).** You don't touch `npc.gd`. The NPC's `NpcLocomotion._idle` looks for a `PatrolBehavior` child on its host and, while the NPC is idle (no target, not in combat, not following a leader), hands movement to patrol instead of wander. A fight interrupts the patrol; the NPC resumes the beat afterward. Patrol drives the host through the **same navmesh pathing** as wander, so the route steers around walls — you place corner markers, you don't author the path between them. The `_idle` priority order is: **companion-follow > `sitting` (holds the post) > daily routine (`ScheduleBehavior`) > patrol > wander > return-to-post.** Each `PatrolBehavior` keeps its own waypoint index and ping-pong direction, which is why several NPCs can point at one shared `PatrolPath` and each walk it independently.

**Worked example — a guard pacing a courtyard**

1. Add a **`Node3D`** to the level and attach `patrol_path.gd` (now a `PatrolPath`).
2. Add **3 `Marker3D` children** under it, one at each corner of the beat. Set the `PatrolPath`'s `loop = true` and `wait_time = 2.0`.
3. Select your guard NPC, add a **child `Node`**, and attach `patrol_behavior.gd`. Set its `patrol_path` to the `PatrolPath` from step 1.
4. Play. The guard walks the 3 markers in order, pausing 2 s at each, and resumes the loop if a fight pulls it away.
5. Variations: set the `PatrolPath`'s `loop = false` to make it ping-pong the line instead of cycling; point a **second** guard's `PatrolBehavior` at the *same* `PatrolPath` to share the route (each keeps its own place on it).

**Gotchas**
- **`PatrolBehavior` only runs while the NPC is idle.** It's not a leash — combat, chasing a target, and following a leader all take over, and patrol resumes when the NPC goes idle again. (Companion-follow also outranks it, so a follower won't patrol.)
- **`sitting` outranks patrol.** Ticking `sitting` on the NPC root makes `_idle` return before it ever reaches `ScheduleBehavior` / `PatrolBehavior` / wander, so a seated guard will never walk its beat — pick one. (A real engagement, companion-follow and cutscene control all stand it back up, at which point the normal order resumes; so does being away from its post, which is how a seated NPC walks itself home.)
- **`PatrolPath` waypoints are child nodes, not an array.** To change the route, add/remove/reorder the Marker3D children — there's no waypoint `@export` to fill. Zero children → the route is empty and it config-warns.
- **Markers must be reachable on the navmesh.** Patrol uses the NPC's own pathing; if the navmesh won't route to a waypoint the NPC treats it as "arrived," pauses, and advances — so keep markers on walkable ground and re-bake after moving geometry.

### Going home: the leash (`NpcHomeReturn`)

Levels leak their cast. A guard chases you two districts away and just stays there; you die and the default `CHECKPOINT_RESPAWN` revives you in an **untouched world**, so everything that hunted you is still parked wherever it killed you. **`NpcHomeReturn`** (`res://scripts/npc/npc_home_return.gd`, `class_name NpcHomeReturn`, `@tool` plain `Node`) is the leash that puts them back. Every NPC **auto-builds one** — you don't add anything to get the behaviour — and it fires on two triggers:

1. **The player died.** That trigger owns **both halves of the encounter reset**: every survivor goes back to its post *and* is **healed to full HP** (`heal_on_player_death`, on by default — limb damage is cleared too). Without the heal, `CHECKPOINT_RESPAWN` hands you a second attempt against enemies still carrying every wound from the first, so a fight you lose gets easier each time you die at it, and that damage never heals for the rest of the session. **The dead are not revived** — an NPC you killed stays killed, where it fell. The heal reaches the *whole* cast, including the NPCs that are exempt from being *moved* (a companion, a bodyguard, a cutscene body): none of those is a reason to leave someone wounded. The cue is `GameState.player_died`, and its **timing is the contract**: it fires on the death cinematic's **fully black frame** — with the whole `death_card_delay` settle beat (and then some) still to run before the *"You were killed by X with Y"* card fades in — not at the moment of death. Fire it any earlier and you can plainly watch the cast teleport away through the closing vignette, which reads worse than them not moving at all. So the encounter resets behind the black and you're back on your feet in a world that's been put away. It composes with the separate **`deaggro_on_player_death`** rule (see *Factions, disposition and reputation*): that one settles a **provoked grudge**, this one settles **positions** — the town calms down *and* goes home.
2. **It's been off-screen for a while.** After `off_screen_delay` seconds outside the player's view, an NPC that has drifted more than `home_slack` from its post goes back.

**An NPC with aggro on you is never teleported by trigger 2.** Locked on, hunting a lost trail, or just holding you as a proximity target it hasn't consciously noticed yet — breaking line of sight is a combat move, not a despawn button, and an enemy that evaporates mid-encounter reads as the game deleting the fight. This is a **hard rule in the component**, not a knob: even with the hard-leash settings below, the most a leashed-but-aggro'd NPC does is stand down and *walk* back. Only the player-death reset (trigger 1, on a black screen) is allowed past it. A blink also needs `min_blink_distance` (8 m) of separation — out of the view cone isn't the same as unnoticeable when you're one turn away from looking right at it.

**How it gets home is the dog / companion trick, in reverse.** A companion that falls behind off-screen blinks up to your heel (`CompanionFollow` — see *NPC services and progression → Companions*), and a claimed dog does the same via `PropFollow`; this **blinks the NPC back to its spawn spot** instead. The rule is the same and non-negotiable: **never move a body the player can see.** The cone test is the same wide dot-product guard those two use, and with `occlusion_check` on, an NPC standing inside a building you happen to be facing counts as out of view (one raycast, only when the cone says "in view"). When a blink is refused — or `blink_home` is off — the NPC still **stands down**, and the existing idle **return-to-post / wander re-centre** walks it home on foot, which is the right read while you're watching.

**What it does NOT reset: hostility.** Going home drops the current *engagement* (target, attacker lock, perception back to `UNAWARE`, laser off — `NPC.stand_down()`), but the provoke flag, faction standing and NPC-vs-NPC grudges are untouched. A guard you shot is still angry the next time it lays eyes on you; it has simply gone back to its post. Quests and flags are never involved.

**What it does NOT reset: the dead.** An NPC you killed stays killed and stays where it fell — the player-death reset restores the *survivors* of a fight, it never undoes one.

**Who is exempt** (never leashed — the *heal* still reaches them): a recruited **companion** (its home is you — `CompanionFollow` owns its own blink), a **bodyguard** on `GuardDuty` (it belongs beside its VIP), an NPC under **cutscene** control, one **walking up for a conversation**, and the dead.

**The global dials** live on `GameSettings.npc_ai` (`res://resources/tuning/NpcAiSettings.tres`, group **Home return (leash)**) and seed every auto-built instance: `home_return` (master, ships **on**), `home_return_on_player_death`, `home_return_heal_on_player_death` (ships **on** — full-HP the survivors on that same beat), `home_return_death_delay` (`0` s — *extra* wait after the fully-black beat; the screen is already covered, so raise it only to land the reset later still), `home_return_off_screen`, `home_return_off_screen_delay` (`15` s), `home_return_requires_calm`, `home_return_slack` (`3` m), `home_return_blink`, `home_return_min_blink_distance` (`8` m). Turning `home_return` off restores the pre-leash behaviour everywhere.

**Per-NPC override:** drop a **configured `NpcHomeReturn` under the NPC in the scene** and the auto-build leaves it alone (it only binds the host). Its knobs: `enabled`; **Home** — `home_marker` (a `Node3D`/`Marker3D` whose transform *is* home; empty = the spawn spot + facing), `home_slack`, `snap_home_to_navmesh` (leave off — the authored spot is already valid, and snapping drags a sentry off its crate); **Player death** — `return_on_player_death`, `heal_on_player_death` (independent of it: an NPC can be healed without being moved, or moved without being healed), `death_return_delay` (extra wait past the fully-black beat; `0` by default), `death_return_ignores_view` (on, and safe — the screen is black, so "in the view cone" no longer means "on screen"; off holds the same guard as the off-screen trigger); **Off screen** — `return_when_off_screen`, `off_screen_delay`, `off_screen_requires_calm` (on = the leash waits for the NPC to give up the chase first, so the clock doesn't even run mid-firefight; **off = a hard leash** — break line of sight long enough and the NPC disengages and heads back, though it still *walks*, never teleports, while it has aggro); **How it returns** — `blink_home`, `min_blink_distance`, `view_dot`, `occlusion_check`, `scan_interval`.

You can also force it from code or a cutscene: **`NPC.send_home(force)`** returns `true` when the NPC actually went (pass `force = true` to skip the on-screen guard).

**Worked example — a shopkeeper who is always behind his counter.** Select the vendor, add a child **`Node`**, attach `npc_home_return.gd`. Set `off_screen_delay = 2.0` and `home_slack = 1.0`. Now the moment you stop looking at him he is back at his till, however far a brawl dragged him. Add a `Marker3D` behind the counter and point `home_marker` at it if his authored spawn isn't exactly where he should stand.

**Gotchas**
- **The blink is refused while you can see the NPC *or* its post.** If a level's NPCs never seem to teleport home, you are probably looking at the area — that's the guard working. They still walk back; watch for the walk, not the pop.
- **A seated NPC walks home like anyone else.** The seat only applies *at* the post (`GameSettings.npc_ai.seat_return_radius`), so a shopkeeper dragged off his stool reads as standing, the idle walk-back drives him back, and he sits again on arrival — `blink_home = false` is fine for seated casts. The blink is still what rescues one stranded **off the navmesh**.
- **`off_screen_requires_calm` is what keeps fights fair.** Turning it off makes any long enough break in line of sight disengage the encounter — a real design choice (Souls-style leashing), not a bug fix. Playtest it before shipping it. It cannot, however, make an aggro'd NPC *teleport*; that refusal lives in the component and no setting reaches it.
- **Home is the *spawn* transform, and it gets re-stamped.** `NpcPool` reuse and a `WorldSnapshot` save-reload both re-anchor an NPC's spawn point to where it was just placed, so a pooled/restored body leashes to its **new** post, not the previous life's. Use `home_marker` when you need a fixed spot regardless.
- **It is not a substitute for a navmesh fix.** The leash hides "NPC stranded on a bad bake" instead of curing it — if bodies keep needing rescue, re-bake and re-run `scripts/tools/generate_nav_links.gd` (see *Navigation*).

Files referenced: `res://scripts/npc/npc.gd`, `res://scripts/npc/npc_data.gd`, `res://scripts/npc/npc_home_return.gd`, `res://scenes/characters/NPC.tscn`, `res://scenes/characters/enemy.tscn`.

### Crowd cost: AI level of detail (`AiLod`)

NPC count is the frame budget's cliff, and it is **CPU**, not GPU. Measured on the shipped map (2026-08-13, GTX 1660 / i5-9400F, 40 spawned NPCs): the frame ran **66.7 ms (15 fps)**; disabling *only* `npc.gd`'s own `_physics_process` — every component child still ticking — took it to **12.5 ms (80 fps)**. So **~81% of a crowd's cost is the NPC brain's tick cadence.** Three intuitive culprits were measured and **refuted**, and should not be re-blamed: RVO avoidance (`avoidance_enabled = false` changed nothing), `sight_range = 500` as a *direct* cost (dropping it to 15 changed nothing), and pathing (`wanders = false` changed nothing). The NavigationServer measured 0.1–0.4 ms.

**`AiLod`** (`res://scripts/components/ai_lod.gd`) is the single cadence gate on that tick. Every NPC auto-builds one from `GameSettings.npc_ai`'s *AI level of detail* group; drop a configured `AiLod` under an NPC to override it there.

- **Bands** — inside `near_distance` (20 m): every tick. Out to `far_distance` (45 m): every `mid_interval` (0.1 s). Beyond: every `far_interval` (0.25 s).
- **Movement is never throttled.** Gravity and `move_and_slide` run every tick at every band, so a throttled NPC walks perfectly smoothly — it only *decides* less often. The gate deliberately sits **above** `_desired_velocity = Vector3.ZERO` so a skipped tick preserves the last decided steering instead of freezing the NPC.
- **No slow motion.** The delta handed to the brain on a think tick is the *real* time banked since the last one, so `_fire_timer` / `_retarget_timer` / perception / GOAP all advance in true seconds.
- **Staggered.** Each NPC waits its own slice of the first window (derived from `instance_id`), re-seeded on every band *entry* — otherwise a cohort crossing a boundary together would think on the same tick and turn a steady cost into a periodic frame spike.
- **Exemptions (always full rate):** perception past `UNAWARE`, scripted-investigating, companions, and **any level with no human player** — that last one keeps `tests_soak` measuring exactly what it did before this existed.

> ⭐ **`NPC.tscn` ships `sight_range = 500.0`** — the whole map. Targets are acquired by pure proximity with no perception gate, so *every* hostile NPC in a level holds the player as `_target` from load. That is why the LOD gates on **perception state**, not on holding a target: exempting target-holders would switch the feature off for the entire cast. It also caps the win — an NPC that can genuinely *see* you from 80 m is exempt by design, and correctly so. If you want the full benefit of LOD in a big populated level, bring `sight_range` down to something the level's sightlines actually justify.

---

## Customising an NPC look (body/head/limbs)

Every enemy in Cyber Sunday starts from the same `enemy.tscn` rig — whose visible body IS its `BodyModelSwap` child (the old skinned `Man.glb` body node was removed as a vestigial hidden placeholder) — but you almost never edit that rig directly. Instead, a drop-in `BodyModelSwap` child *replaces* the visible body, head, arms and legs with your own `.glb`/`.blend` models, and it does so **live in the editor** (it's a `@tool` script). Better still, you can override the look **per instance straight from the NPC root**, so re-skinning one guard in a level is a matter of clicking it and filling a few inspector fields — no "Editable Children", no duplicate scenes. Beyond the look, the same component also drives the NPC's runtime CHARACTER motion: legs that steer toward the direction it's actually moving (independent of the torso, which stays on its aim), an armed NPC that only raises its weapon once a foe is close, and a talking presentation (head-bob + a flapping mouth) plus speaker-only idle breathing. Those are runtime-only knobs on the same node (see "Runtime motion" and "Talking and breathing" below).

### The two places a look is defined

There are two layers, and it helps to know which one you're touching:

1. **The shared default look** lives on the `BodyModelSwap` node inside `res://scenes/characters/enemy.tscn` (script: `rpg/scripts/components/body_model_swap.gd`). This is what *every* enemy wears unless overridden. In the shipped scene it's set to:
   - `body_model` = `res://scenes/bodyparts/torso.tscn`, `body_model_scale` = `0.205`, `body_model_rotation` = `(0, -90, 0)`, `body_texture` = `stupidbody_Material Base Color.png`
   - `head_model` = `res://assets/models/headblue.glb`, `head_scale` = `0.205`, `head_position` = `(0, 0.615, 0.04)`, `head_rotation` = `(0, 90, 0)`, `head_texture` = `headblue_Material Base Color.png`
   - `arm_model` = `arm.blend` (scale `0.35`, position `(-0.27, 0.155, -0.05)`, rotation `(90, 0, 0)`) and `leg_model` = `assets/models/leg.blend` (scale `0.44`, position `(0.095, -0.265, -0.02)`, rotation `(0, -90, 0)`)
   - (The arm/leg *tints* in the shipped scene come from the `BodyModelSwap` child itself — its `arm_color` = a blue, `leg_color` = a maroon. The NPC root carries no arm/leg tint by default; assign an `NpcLook` to `look` with a non-white `arm_color`/`leg_color` to override them per instance.)

   Note the field names differ slightly between the two layers: on the `BodyModelSwap` child the head transform fields are `head_scale` / `head_position` / `head_rotation`, while in the `NpcLook` (below) the equivalents are `head_model_scale` / `head_model_position` / `head_model_rotation`.

2. **Per-instance overrides** are an **`NpcLook` resource** you assign to the NPC root's single **Body & Head ▸ Custom Models ▸ `look`** slot (`rpg/scripts/npc/npc.gd`; the resource class is `rpg/scripts/npc/npc_look.gd`). The NPC root no longer carries the appearance fields inline — it has just the one `look` field. Drop an `NpcLook` there (a reusable `.tres` you author in `resources/`, or an inline sub-resource) and the `@tool` `BodyModelSwap` child *reads that look* and prefers it over its own shared default — so an assigned look wins and previews instantly. Author a "raider look" / "townsperson look" once and reuse it across NPCs; clear the `look` to fall back to the shared default.

Assign an `NpcLook` to `look` and IT carries these override fields (their names mirror the shared-default fields on the `BodyModelSwap` child). Leave any at its default — null model / WHITE colour / `1.0` scale — to leave that part alone:

| Field | Type | What it overrides |
|---|---|---|
| `apply_body_part` | pick (dropdown) | **Momentary shortcut** — pick a body by name and its model + seat are stamped into the four `body_model_*` fields below. Snaps back to empty; nothing is stored. See "Pick a part by name" |
| `apply_head_part` | pick (dropdown) | **Momentary shortcut** — same for the head, filling `head_model` + `head_model_scale` / `_position` / `_rotation` / `head_texture` |
| `body_model` | PackedScene or Mesh | Swap this NPC's body mesh |
| `body_model_scale` | float | Body uniform scale |
| `body_model_position` | Vector3 | Body local offset (nudge Y so feet meet the ground) |
| `body_model_rotation` | Vector3 (deg) | Body yaw/pitch/roll |
| `body_texture` | Texture2D | Re-skin the body (albedo) *without* swapping the mesh |
| `body_color` | Color | Tint the body (WHITE = leave it) |
| `head_model` | PackedScene or Mesh | Swap this NPC's head |
| `head_model_scale` | float | Head uniform scale |
| `head_model_position` | Vector3 | Head local offset (raise Y to sit it on the neck) |
| `head_model_rotation` | Vector3 (deg) | Head rest facing |
| `head_texture` | Texture2D | Re-skin the head (albedo) |
| `head_color` | Color | Tint the head (WHITE = leave it) |
| `arm_color` | Color | Tint both arms (WHITE = keep the default) |
| `leg_color` | Color | Tint both legs (WHITE = keep the default) |

Note there is **no `arm_model` / `leg_model` (nor arm/leg scale, position, rotation, or texture) in the `NpcLook`** — a look can only *tint* the limbs (`arm_color` / `leg_color`). The arm and leg *models* and their placement live solely on the `BodyModelSwap` child.

### Pick a part by name (the fastest path)

You do **not** have to drag a `.glb` out of the file explorer to change an NPC's head. Both layers carry momentary **pick** rows, each sitting directly above the model slot it fills:

| Surface | Pick rows | Reads from |
|---|---|---|
| `BodyModelSwap` child | `apply_body_part`, `apply_head_part`, `apply_arm_part`, `apply_leg_part` | `res://resources/parts/{bodies,heads,arms,legs}/` |
| `NpcLook` resource | `apply_body_part`, `apply_head_part` | `res://resources/parts/{bodies,heads}/` |

Choosing an id **stamps** that part's `model` *and* its fitted `scale` / `position` / `rotation` / `texture` into the ordinary fields below it, then the row snaps back to empty. That seat is the point: every head model has its own native size, origin and facing, so the four shipped heads sit at scale `0.205` / `0.4183` / `0.1199` / `0.2436` with *opposing* yaws. Dragging a model in gets you step one of four; picking gets you all four.

Things to know:

- **The pick is not remembered.** It writes into the normal fields and forgets the id — the `.tscn`/`.tres` keeps the plain model reference it always had, nothing new resolves at runtime, and deleting `res://resources/parts/` never changes how an already-authored NPC renders. Everything stays hand-editable afterwards; nudge the stamped numbers freely.
- **The dropdown shows the *id* (= the filename), not the `display_name`.** It is an editable suggestion box, so you can type — an id that doesn't resolve simply does nothing rather than blanking a working part.
- **The folder is the scope.** `resources/parts/heads/` cannot offer you `ak47.glb`. Drop a new part `.tres` into a slot folder and it appears in that slot's dropdown with **no editor restart**.
- **There is NO UNDO for a pick.** Ctrl+Z cannot restore the five fields a stamp wrote (the only undoable property is the momentary row, whose value is always `""`), and the scene may read as *unmodified* afterwards while the stamp is still applied — so don't rely on closing without saving to discard one. Before overwriting anything, the stamp **prints the previous model + seat to the Output panel** in copy-pasteable form; that print is the recovery path.
- **A look beats the child.** If the NPC's `look` sets a part's model, a pick made on the `BodyModelSwap` child for that same part will not show — the look wins (see the precedence note below). The stamp pushes a warning naming the look when it detects this; pick on the **look** instead.

Adding your own part:

1. Duplicate any `.tres` in `res://resources/parts/heads/` (or the slot you want) and rename the copy — **the filename is the id**.
2. Open it and set `id` to match the filename, plus a `display_name`.
3. Drag your model into its `model` field — **once, ever**. Everyone who picks it from now on gets it without touching the file explorer.
4. Tune the seat on any NPC (`head_scale` / `head_position` / `head_rotation` in the viewport), then copy those three numbers back into the part file so the next pick lands fitted.

Moving or renaming the model `.glb` afterwards is safe — Godot rewrites the part file's `ext_resource` for you.

A few rules the component bakes in, worth internalising:

- **Texture/colour resolve independently of the model.** You can re-skin the *default* body just by setting `body_texture`/`body_color` and leaving `body_model` empty — no mesh swap needed.
- **WHITE is the "leave it alone" sentinel** for every `*_color`. The override only kicks in when you pick a non-white colour; white restores the model's own baked material. Same idea for an empty texture.
- **A swapped model brings its own material.** If you set `body_model` but no `body_texture`/`body_color`, the new mesh shows the material it was authored with. (And if the host overrides the *model* but leaves its texture null / colour WHITE, the swapped model keeps its own material rather than inheriting the child's default skin.)
- **Arms and legs are tint-only from the root.** Their *models* and placement always come from the `BodyModelSwap` child (they're gait-animated — they swing as the NPC walks, and by default the LEGS also swivel to face the direction the NPC is actually moving, independent of the torso which stays trained on its aim — a run-and-gun strafe), but `arm_color`/`leg_color` on the root recolour them per instance.

### Runtime motion (on the BodyModelSwap child)

These knobs are all `@export`s on the **`BodyModelSwap` child** (not the NPC root), and they only play **in-game** — the editor shows the static rest pose.

- **`legs_follow_movement`** (bool, default **true**) — the legs/hips swivel to face the direction the NPC is actually MOVING, independently of the torso (which keeps facing its aim/look). So a strafing or backpedalling enemy points its hips along its path while its chest stays trained on you. Off = legs stay square with the torso.
- **`leg_turn_rate`** (float, default `9.0`) — how snappily the legs swivel toward the movement direction; lower = a lazier, sliding turn.
- **`legs_square_when_idle`** (bool, default **true**) — when the character STOPS, swivel the legs back square with the torso (the NPC idle combat stance — feet under the hips, facing its aim). Off = the legs HOLD their last movement facing, so the feet stay pointed where they were going instead of snapping back to the torso/camera. The Player's first-person legs set this **off** (stopping after a strafe shouldn't rotate the feet to camera-forward). Only matters with `legs_follow_movement` on.
- **`arms_hold_when_drawn`** (bool, default **true**) — an armed NPC holds its weapon in a two-handed forward stance the **whole time the gun is drawn**, so a hostile with its gun permanently out has both hands ON it instead of letting the arms hang at its sides while the gun floats at the hand anchor (the disconnected look). Stealth-safe: the hold pose is symmetric and points the gun along the **torso**, whose facing is perception-gated, so hands-on-the-gun never means "aiming at a player it hasn't seen" — the honest "I noticed you" tells stay the torso swivel + head-look. Turn it **off** to restore the wary stealth telegraph (`arm_raise_range` below).
- **`arm_raise_range`** (float, default `10.0`, metres) — **only used when `arms_hold_when_drawn` is off.** An armed NPC then only raises its weapon into the forward hold pose when the foe is within this distance **and** it has actually sensed the foe (`has_sensed_foe()`); farther out, or before it's noticed you, the gun stays **drawn** but the arms hang / swing with the stride, so the arms coming up is itself the "I noticed you" tell. Purely cosmetic — it never changes when the NPC actually fires. `0` = raised the moment the gun is out; with no target the arms stay down.

### Seated NPCs

Tick **`sitting`** on the **NPC root** and the `BodyModelSwap` child holds a seated pose while the NPC is off duty **at its post**. The pose knobs live on the **`BodyModelSwap` child**:

- **`seated_snap_to_ground`** (bool, default **true**) — the seated visual **drops until it rests flush on whatever surface is straight below the NPC** (the floor for a ground-sitter, the seat for an NPC parked on a chair/crate). You just place the NPC and tick `sitting`; the seat height sorts itself out per spot. At runtime that surface comes from a downward raycast, re-run only when the NPC actually moves, so parked sitters cost next to nothing; where there's no stepped physics to ray — **the editor viewport**, or a probe that misses — it falls back to the NPC's own **capsule bottom**, which is the same plane for any settled character. **The seat needs a real layer-1 collider the NPC's capsule can stand on** — on a decorative collider-less chair the capsule (and so the seat plane) falls through to the floor, and the NPC sits through the seat. Turn this **off** to author the drop yourself: `seated_visual_offset.y` then stands, editor and runtime alike.
- **`seated_max_snap_depth`** (float, default `1.2` m) — how far below the NPC's origin the runtime probe reaches; it doubles as a sanity gate, so an NPC whose origin pokes past a ledge rim **rejects** the cliff-bottom hit instead of rendering its seated body into the drop.
- **`seated_hip_clearance`** (float, default `0.06` m) — how high the hip joint (`leg_position`) rests above the seat plane; roughly half the leg's thickness. Trim it until the butt/legs visibly touch rather than float or sink — **judge it in the viewport**, which now resolves the same plane.
- **`seated_hand_clearance`** (float, default `0.05` m) — the hands never come closer to the seat plane than this: the seated arm pitch **auto-raises** past `seated_arm_pitch` (never below it) using the arm model's measured reach. In practice the seat plane pins the shoulder a fixed height above itself, so a sitter's arms always settle at the same clamped angle (**~55° hands-on-lap on the shipped rig**, floor and chair alike) — `seated_arm_pitch` only changes the pose when authored *steeper* than that.
- **`seated_visual_offset`** (Vector3, default `(0, -0.28, 0.04)`) — X/Z always apply as authored; the Y is the **last-resort** drop, used only when no seat plane resolves at all (snap off, or a host with no capsule).
- **`seated_body_pitch`** (`8.0`°, forward torso lean), **`seated_arm_pitch`** (`-25.0`°, the *preferred* **idle** arm hang — see the clamp above), **`seated_leg_pitch`** (`-90.0`°, legs straight out in front; positive would fold them backward through the seat).
- **`seated_hide_shadow`** (bool, default **true**) — hides the host's blob-shadow `Decal` ("Shadow" child) while seated (it's sized/placed for the standing silhouette). A floor-sitter may look better keeping it — untick per rig to taste.

**A seated NPC keeps its hands on a drawn gun.** `seated_arm_pitch` is the *idle* pose; with a weapon out the seated arms take `arm_hold_pitch` under exactly the same gates as standing (`arms_hold_when_drawn`, else `arm_raise_range` + actually having sensed the foe), and the held view-model's hand anchor drops with the body, so the gun stays in the hands instead of hovering at standing chest height. A seated NPC you're **talking to** always puts it down in its lap for the conversation.

**When a seated NPC stands up.** It holds the seat through the first "what was that?" beat (perception `DETECTING` — it swivels to look, gun up on its lap) and gets up for a real engagement: locked on (`ALERTED`), hunting a lost trail (`INVESTIGATING`), companion-follow, or cutscene control. That's what makes a **hostile** authored with `sitting` actually get found sitting: a hostile holds the player as a proximity target and starts detecting from anywhere inside `sight_range` (25 m by default), so standing at the first flicker meant it was always already on its feet. Dialogue keeps it seated and it speaks in place.

**After a fight it walks back before sitting.** The seat is a *post* behaviour: while the NPC is further than `GameSettings.npc_ai.seat_return_radius` (default `1.25` m) from its spawn spot it stays standing, which is what lets the idle return-to-post walk run — then the seat re-applies on arrival. Without that a raider would sit down wherever the firefight ended. Keep the radius above the `Locomotor`'s `arrival_distance` (that walk stops within it); `npc.gd` floors it against the live value anyway.

### Talking and breathing

Also `@export`s on the **`BodyModelSwap` child**, runtime-only. The head-bob and mouth both need a **head node** — a swapped `head_model` (without one, they're silent no-ops; see Gotchas).

- **`talk_head_bob`** (bool, default **true**) — the head bobs up/down while THIS NPC is delivering a dialogue line **or a bark** (it animates for the utterance's duration, then settles — not the whole time a line sits on screen). In a conversation it also stops the **instant** the NPC is no longer speaking — when the response menu opens, or the conversation ends — so the head doesn't keep bobbing while you read the choices or as the NPC walks off (DialogueManager cuts the envelope via `note_speaking_stop`). `talk_bob_height` (`0.03` m), `talk_bob_rate` (`9.0`, bob cadence), `talk_bob_ease` (`8.0`, how fast it eases in/out).
- **`show_mouth`** (bool, default **true**) — a billboarded black "Tomodachi"-style mouth that flaps between a thin line and a full circle while the NPC speaks a line or a bark, and hides between utterances. `mouth_size` (`0.06` m radius), `mouth_flap_rate` (`22.0`, chatter speed), and **`mouth_position`** (Vector3, default `(0, -0.03, 0.14)`, HEAD-LOCAL, +Z is the face front) — **tune this so it sits on the model's mouth**; if you don't see it, it may be buried inside the head, so push Z further forward.
- **Breathing** (the existing `breathe` / `breathe_amount` / `breathe_rate` chest idle) now applies, *during a conversation*, ONLY to the NPC you're talking to — every other NPC holds still, so the scene reads as frozen around your conversation partner.
- **Arms lower in dialogue (automatic, no field).** The NPC you're talking to always drops its arms to the by-side rest pose for the whole conversation, even if it had them raised (weapon-hold, fists-out) the instant you started talking — so no one keeps a gun trained on you mid-parley. It eases the arms back up on its own once the conversation ends if it's still armed (its weapon drawn — or, with `arms_hold_when_drawn` off, once you're within `arm_raise_range` and it has sensed you). A **seated** speaker is the exception: it holds the seated arm pose (the floor-cleared pitch) instead of the standing hang, so a ground-sitter's arms don't stab through the floor for the conversation.

### Worked example: a red-shirted variant of the default guard

Say you want one specific enemy in your level to wear a red torso and a pale head, but otherwise stay the default guy.

1. In your level scene, select the placed **Enemy** instance (the root `CharacterBody3D`). You do **not** need "Editable Children".
2. In the inspector open **Body & Head ▸ Custom Models** and find the **`look`** field. Click its **`[empty]`** button and choose **New NpcLook** to make an inline look resource (or assign an `NpcLook` `.tres` you authored), then expand it to reach its fields.
3. Inside the look, leave `body_model` and `head_model` empty — you're keeping the default meshes. (There's no arm/leg model field; the limbs always come from the child.)
4. Set the look's `body_color` to a red. The torso re-tints in the viewport immediately (the `@tool` child rebuilds on the change).
5. Set its `head_color` to a pale skin tone. Done.

Want a genuinely different *body* instead of a tint? In the look, set `body_model` to your `.glb`/`.tscn`, then dial `body_model_scale` (start around `0.2` — the default body sits at `0.205`, and most imported models come in giant at scale `1.0`), nudge `body_model_position.y` so the feet land on the ground, and yaw `body_model_rotation` until it faces the NPC's forward. Everything previews as you type. The same node performs the swap at runtime, so **what you see in the editor is what ships** — and at runtime the head-look and sniper glint automatically retarget onto your swapped head (the component calls `register_swapped_head()` on the NPC), and the combat outline re-rims the swapped parts.

If you instead want to change the default for *all* enemies, open `res://scenes/characters/enemy.tscn`, select the `BodyModelSwap` node, and edit its fields there.

### Gotchas

- **An `NpcLook` may safely override only `head_model`.** The torso then falls through to the `BodyModelSwap` child's own `body_model` (`torso.tscn`) — that's exactly what the shipped `kyle_look.tres` does (head + limb colours, no body). What must keep a `body_model` is the `BodyModelSwap` **child** itself: there's no fallback body mesh any more (the old hidden `Man.glb` node was removed, so `default_body` resolves to null and the hide is a harmless no-op), so clearing the child's `body_model` in `enemy.tscn` leaves a head over nothing. The node flags exactly that case with an editor configuration warning ("Head model set with no body model"), and it resolves against the **effective** models — a body supplied via the NPC's `look` counts, so the warning only fires when neither layer supplies one.
- **The animated swing/hold poses are runtime-only.** In the editor you see the *static rest pose* (so you can place limbs); the walk swing, the leg-follows-movement swivel, the proximity-gated weapon raise, the weapon-hold, the air-flail, the breathing chest idle, AND the talking head-bob + flapping mouth all only play in-game. Place limbs (and `mouth_position`) against the rest pose, then playtest to see the motion. (The **seated** pose is the one posture the editor *does* preview, and it previews at the real seat height — the drop resolves off the NPC's capsule bottom when there's no runtime probe. See "Seated NPCs".)
- **No mouth or head-bob? You need a head node.** `talk_head_bob` and `show_mouth` ride on the head — the component's own swapped `head_model`. Without one resolved they're silent no-ops. If the mouth never shows on a talking NPC, confirm a head is present and that `mouth_position` (head-local, +Z forward) actually sits on the face rather than buried inside the head mesh.
- **Preview not refreshing?** After a `.glb` reimport or a script reload the live preview can lag. Tick `refresh_preview` on the `BodyModelSwap` node (it snaps back off and forces a rebuild). This field is on the child, not the NPC root.
- **The override is detected by a non-default field in the assigned `look`**, so an empty/`null` `body_model` (or a WHITE colour, or a null texture) means "fall through to the `BodyModelSwap` default" — it does not mean "blank it out." To drop ALL per-instance overrides, clear the NPC's `look`; to change the default for *everyone*, edit the `BodyModelSwap` child in `enemy.tscn`. This precedence is why a **pick** (`apply_*_part`) made on the child looks like a no-op on an NPC whose look already sets that part's model — a pick is a one-time write into ordinary fields, not a new override layer, so it cannot outrank the look. Pick on the look instead.

Relevant files: `rpg/scripts/components/body_model_swap.gd`, `rpg/scripts/npc/npc.gd` (the **Body & Head ▸ Custom Models** subgroup — the single `look` export — and `register_swapped_head`), `rpg/scripts/components/part_library.gd` (the `apply_*_part` pick dropdowns; authoring-time only), the part files under `rpg/resources/parts/`, and the `BodyModelSwap` node in `rpg/scenes/characters/enemy.tscn`.

### The player character customizer (the head/body picker)

The player builds their character on **New Game**: the character-creation screen has a **Stats** tab (the zero-sum stat build), a **Look** tab with a **live rotating 3D preview** plus pickers for the **head**, the **body**, and **arm / leg colours** (skin colour is fixed — see Colours below), and a **Shirt** tab where the player **paints their own torso texture** (a blank tee they decorate — see *Draw-your-own shirt* below); **Begin** then leads to the **implant-purchase step** (fit starting chips on credit — the bill can push the starting wallet negative; see *Saving → Starting implants (bought on credit)*). The same portrait shows again on the in-game **Stats** screen (head-and-shoulders framing) so the player can see their character later. (Cyber Sunday is first-person, so the character is currently only *seen* in these menu portraits — but the chosen look is saved on the player as the natural hook for any future third-person body.)

**Everything the picker offers is data-driven from one catalog resource**, so you add a head or a body with **no code**:

- The catalog class is **`CharacterAppearanceCatalog`** (`rpg/scripts/player/character_appearance_catalog.gd`); each pickable part is a **`CharacterPartOption`** (`rpg/scripts/player/character_part_option.gd`).
- The **shipped catalog is `res://resources/characters/PlayerAppearanceCatalog.tres`** — edit it in the Inspector to add/tune heads, bodies, the limb palette. (A code fallback, `CharacterAppearanceCatalog.default()`, is used only if that `.tres` is ever missing, so the customizer never hard-breaks.) `get_catalog()` prefers the `.tres`.
- **Its `heads` / `bodies` entries are `ext_resource` references into `res://resources/parts/`** — the *same* files the NPC `apply_*_part` pick dropdowns offer, so the player creator and NPC authoring share one source of truth (`tests/test_part_library.gd` pins it; re-inlining a `[sub_resource]` here fails that test). Two consequences worth knowing: (a) dropping a part `.tres` into `resources/parts/heads/` reaches the **NPC picker immediately but NOT the player creator** — that reads this catalog's `heads` array, so add it there too if players should be able to choose it; (b) retuning a shared part file (e.g. `head.tres`) changes it for the player creator as well — author a **new** part file instead when you only want one NPC to differ (`resources/parts/heads/kyle.tres` is the shipped example: the same `femalehead.blend` at a different seat).
- A **`CharacterPartOption`** carries: `id` (a stable save key — never reuse/renumber it), `display_name` (shown in the cycler), `model` (a `.glb`/`.blend` PackedScene or a Mesh), `scale` / `position` / `rotation` (how it seats on the rig — the same numbers you'd tune on a `BodyModelSwap`), an optional `texture`, and `whole_body`.
- **Heads** compose onto a torso body. Each head needs its OWN `scale` / `position` / `rotation` — a different model won't fit the `headblue` seat (`scale` `0.205`, `position` `(0, 0.615, 0.04)`, `rotation` `(0, 90, 0)`). **Tune a head exactly like an NPC:** open **`res://scenes/player/character_customizer_setup.tscn`** (a `BodyModelSwap` on the shipped torso), set its `head_model` to the head, dial `head_scale` / `head_position` / `head_rotation` live in the 3D viewport, then copy those three values into that head's `CharacterPartOption` in the `.tres`. The four shipped heads (`headblue` / `head` / `spiky` / `chrysalis`) each carry their own fitted seat in the `.tres` (different scale/position/rotation per head — they do NOT share one); use this workflow when adding a new head or refining a fit.
- **Bodies**: only the **standard torso** (`whole_body = false` = `torso.tscn`) ships — it composes with the chosen head + the catalog's shared arm/leg models, and the body cycler's arrows disable while there's a single body. **`whole_body = true`** is still supported (a complete-character model that renders **alone** — own head/arms/legs — disabling the head picker): add a `CharacterPartOption` with `whole_body` ticked to grow the body list. (The old `man` = `Man.glb` whole-body option was removed.)
- **Colours**: `arm` / `leg` tint the limbs — the two swatch rows the Look tab offers — and (in first person) the player's own view-model legs + carry-arms pick up the chosen `leg` / `arm` colour too. **`skin` is FIXED**: the character creator no longer offers a skin-colour picker (it had no visible effect on the shipped head/body materials), so every character uses the catalog's `default_skin_color` tint over the head + body — edit that one field to reskin the shipped look for everyone. `WHITE` = "no tint / natural" (show the model/texture as authored, same sentinel as `NpcLook`) and is deliberately kept OUT of `limb_palette` (arms/legs have no baked texture to reveal). Edit `limb_palette` (a `PackedColorArray` on the catalog) to change the offered arm/leg swatches.

**Draw-your-own shirt.** The **Shirt** tab (`rpg/scripts/ui/shirt_canvas.gd`, a preloaded `ShirtCanvas` paint widget) lets the player paint a small pixel grid that becomes the torso's texture — a blank white tee they decorate. The tee has **two independently-drawn sides** — a **Front / Back** toggle above the canvas switches which one you edit and spins the 3D preview round to face it (`ShirtCanvas.set_side`, `SIDE_FRONT`/`SIDE_BACK`; the preview snaps via `CharacterPreview.set_turntable_yaw`). Player tools: **Paint** (drag-paint), **Fill** (a bucket — floods the clicked same-colour region), **Erase** (paints the blank colour; **right-drag always erases** whatever the tool), **Pick** (an eyedropper — click/drag the canvas to sample that pixel's colour into the brush; `ShirtCanvas.TOOL_EYEDROP` + the `color_picked` signal, read-only, stays selected so you can scrub), a **Size** radio (1–4, the square brush footprint in cells — applies to Paint + Erase; `SHIRT_BRUSH_SIZES` in `character_creation.gd`, `ShirtCanvas.set_brush_size`), a **Mirror** toggle (paints both horizontal halves for symmetric designs), and **Undo** (button or **Ctrl+Z** — steps whole strokes/fills back **per side**, including un-**Reset**). Colours come from the preset chips **or** the **Custom** swatch, which opens a free HSV colour-wheel overlay (the same trimmed wheel the spray can uses — built as a centered `CanvasLayer` overlay, NOT a `ColorPickerButton`, because `embed_subwindows = false` in exclusive fullscreen would open a native popup as its own never-shown OS window). The drawing REPLACES the body option's own `texture` via `configure_swap`, which forces `body_color` to `WHITE` so the art reads true (the head still takes the skin tint) **and flips `BodyModelSwap.body_texture_planar` ON**: a drawn shirt is **planar-projected** flat onto the torso (`rpg/resources/shaders/shirt_planar.gdshader`, parameterised per-mesh by `_planar_shirt_material`) instead of sampling the torso's own baked-atlas UVs, which would scatter the drawing into unreadable scraps. The drawing is a **combined front-over-back stack** (`ShirtCanvas.png_bytes` / the live texture are `edit_res × 2·edit_res`): chest-facing fragments sample the **top half** (front drawing), back-facing fragments the **bottom half** (back drawing), each mirror-corrected to read un-flipped; side/top/bottom faces show plain FABRIC (the nearer side's corner colour, sampled live — a red-front / blue-back tee gets red and blue sides) instead of smeared print-edge pixels (tune via the shader's `print_threshold`). A **legacy square save** decodes onto BOTH halves (an old symmetric shirt is unchanged); `CharacterAppearanceCatalog.shirt_texture` normalises any stored shirt to the 1:2 layout. (Authored/baked body textures keep the mesh UVs — they're painted FOR that atlas.) It's applied only once the player actually paints EITHER side (so an untouched tab / **Reset** / a full undo of both sides leaves the base shirt). Because the game is first-person the torso is only *seen* in the creation + Stats portraits — same as the head/body. Designer knobs: the brush palette is **`shirt_palette`** (a `PackedColorArray` on the catalog — edit it in the **authored `.tres`**, which the runtime prefers over the code default; a test pins it non-empty. Pure black/white are welcome here, unlike `limb_palette`); the canvas + upscale resolutions are `@export`s on `ShirtCanvas` (`edit_res` 32, `apply_res` 128). The drawn shirt is persisted as a tiny **PNG stored as bytes** in `GameState.appearance["shirt"]` (decoded back by `CharacterAppearanceCatalog.shirt_texture`, which accepts either the live `Texture2D` during creation or the saved bytes).

Under the hood the preview and any rig are driven by **`CharacterAppearanceCatalog.configure_swap(swap, appearance)`**, which sets a `BodyModelSwap`'s **own** exports directly (it never assigns the player a `look`, which would leak a head/body into the first-person legs rig). The chosen look is stored as a small save-friendly dict in **`GameState.appearance`** (part ids + Colours + the drawn-shirt PNG bytes; empty = never customised → the catalog default) and mirrored onto **`Player.appearance`**; it round-trips through the profile save and `capture()` leaves it alone (it's authored once at creation, like the name).

Relevant files: `rpg/resources/characters/PlayerAppearanceCatalog.tres` (the shipped, inspector-editable catalog), `rpg/resources/parts/` (the shared part files it references — also the NPC pick dropdowns' source), `rpg/scripts/components/part_library.gd`, `rpg/scenes/player/character_customizer_setup.tscn` (the live head-tuning aid), `rpg/scripts/player/character_appearance_catalog.gd`, `rpg/scripts/player/character_part_option.gd`, `rpg/scripts/ui/character_preview.gd` (the reusable 3D portrait), `rpg/scripts/ui/shirt_canvas.gd` (the shirt paint widget), `rpg/scripts/ui/character_creation.gd` (the Look + Shirt tabs), `rpg/scripts/ui/stats_screen.gd` (the Stats portrait), and `GameState.appearance` / `Player.appearance`.

---

## Factions, disposition and reputation

In CYBER SUNDAY, every NPC's attitude toward the player — and toward other NPCs — flows from a **Faction**: a small authored Resource (`.tres`) that says who an NPC belongs to, how that group feels about the player by default, and which other factions it loves or hates. You never write code for this. You pick a faction from a dropdown, and you can mint brand-new factions by dropping a `.tres` into one folder.

### The pieces

| Piece | What it is | Where it lives |
|---|---|---|
| `Faction` | The Resource you author (id, name, default disposition, relations) | `res://scripts/faction/faction.gd`, instances in `res://resources/factions/` |
| `Disposition.Kind` | The three-state attitude enum: `HOSTILE`, `NEUTRAL`, `FRIENDLY` | `res://scripts/npc/disposition.gd` |
| `Factions` registry | Resolves the `faction_id` dropdown string to a `Faction.tres` by filename (no `class_name` — it's preloaded as a const) | `res://scripts/faction/factions.gd` |
| `Reputation` (autoload) | Tracks the player's standing per faction and maps it to a disposition | `res://managers/Reputation.gd` |

### The Faction `.tres` fields

Open any of the three shipped factions (`res://resources/factions/raiders.tres`, `townsfolk.tres`, `neutral_wildlife.tres`) and you'll see four inspector fields, grouped under **Identity** and **Disposition & Relations**:

- **`id`** (`StringName`) — the stable lookup key. **This must equal the filename** (minus `.tres`): `raiders.tres` has `id = &"raiders"`. The `Reputation` autoload stores the player's standing keyed by this `id`, so two factions sharing an id would silently share one reputation pool. The registry pushes a loud editor warning if the internal `id` ever drifts from the filename.
- **`display_name`** (`String`) — the human-readable name for dialogue and UI ("Raiders", "Townsfolk", "Wildlife").
- **`default_disposition`** (`Disposition.Kind`) — how this faction feels about the player **at zero reputation**, before any rep shift. In the inspector this is a dropdown; in the raw `.tres` it's the enum's integer index: `0 = HOSTILE`, `1 = NEUTRAL`, `2 = FRIENDLY`. So raiders ship `default_disposition = 0` (hostile on sight), townsfolk `= 2` (friendly), wildlife `= 1` (neutral).
- **`relations`** (`Dictionary`) — maps **another faction's `id`** → a relation score (`float`). **`< 0` = enemies, `> 0` = allies, absent/`0` = neutral.** Raiders carry `{ &"townsfolk": -1.0 }` and townsfolk carry `{ &"raiders": -1.0 }`, so the two groups shoot each other on sight. This only governs **NPC-vs-NPC** aggro — it has nothing to do with how either faction feels about the player.

### Picking a faction: the `faction_id` dropdown

On an NPC node (`res://scripts/npc/npc.gd`) — and on an `NpcData` archetype (`res://scripts/npc/npc_data.gd`) — you don't drag a `.tres` into a slot. You pick from a dropdown:

- **`faction_id`** (`String`, a `PROPERTY_HINT_ENUM_SUGGESTION` dropdown) — the options are generated at edit time by `Factions.ids_csv()` in `_validate_property`, a scan of `res://resources/factions/` sorted alphabetically (currently `neutral_wildlife, raiders, townsfolk`), so a new faction `.tres` saved into that folder appears automatically. At `_ready`, the NPC calls `Factions.by_id(faction_id)`, which loads `res://resources/factions/<id>.tres` (or `.res`) and stamps it onto the live `faction` slot. A non-empty `faction_id` **wins over** the `faction` resource slot.
- **`faction`** (`Faction`) — the underlying resource slot. Leave `faction_id` empty and you can drop a custom/inline `Faction.tres` here directly. Empty `faction_id` **and** null `faction` = **UNALIGNED**: the NPC ignores reputation entirely and uses its own standalone `disposition` field instead.

> The suggestion list is just a typing convenience — the dropdown is editable, so you can type any id you want. What actually makes resolution work is the file existing at `res://resources/factions/<id>.tres` with a matching internal `id`. If you type a `faction_id` that resolves to nothing, the NPC logs a warning and falls back to UNALIGNED.

### How disposition is resolved (player-facing attitude)

A factioned NPC's attitude toward the player isn't fixed — `Reputation.disposition_for(faction)` recomputes it live from the faction's baseline plus the player's standing:

- Rep `<= hostile_threshold` → **HOSTILE**, no matter the baseline.
- Rep `>= friendly_threshold` → **FRIENDLY**.
- In between → falls back to the faction's `default_disposition`.

So earning enough standing can thaw a hostile faction, and wronging a friendly one sours it. Those thresholds (plus the `rep_min`/`rep_max` clamp) are themselves designer tunables on `GameSettings.reputation` (`res://resources/tuning/ReputationSettings.gd` / `.tres`) — you balance how fast the world turns on the player without code. When the player attacks a factioned NPC, that NPC's `provoke` drops the whole faction's player-rep by `provoke_penalty` (FNV-style), so the group sours together; the `reputation_changed` and `alignment_changed` signals let the HUD toast the shift. **Holstering (weapon down) forgives a provoke:** `forgive_provoke` clears the transient provoked flag AND restores the *exact* rep the provoke removed (each provoked member reverses only its own clamp-aware delta), so a whole faction that only bristled at a drawn weapon stands back down. A pardon that **lands** pops a **"+friend"** icon over that NPC's chest — the exact mirror of the aggro icon a provoke (and a *refused* second holster, below) flashes — so both outcomes of putting the gun away are readable at a glance instead of only failure being telegraphed. That cue uses the NPC's `popup_positive` art when one is authored and falls back to the shipped `+friend` texture otherwise, so it never silently vanishes (leaving `popup_positive` empty only mutes the separate *rescue* popup). A faction that is genuinely hostile-by-rep — soured by **kills**, not just a provoke — stays hostile, because `kill_penalty` is never reversed by holstering. **This pardon is ONE-SHOT per NPC per life** (`GameSettings.npc_ai.holster_forgiveness_once`, ships on): once an NPC has stood down, RE-ATTACKING it (which re-provokes it) makes the hostility permanent — a second holster is refused and flashes its aggro icon instead of pacifying it. Without this, the player could spam the hold-R holster toggle to keep de-aggroing a mob they kept shooting and farm free kills; turn the toggle off in `NpcAiSettings.tres` to restore the old infinitely-forgivable behaviour. The latch is per-life, so a scene reload or pool reuse clears it. **The one-shot binds FLEEING NPCs too — deliberately, with no exemption.** (A `fleeing_always_forgivable` mercy carve-out shipped briefly and was removed after playtest: `break_and_flee` is one-way within a life, so any coward-temperament fighter shot until it panicked became a *permanent* fleer — permanently exempt and infinitely pardonable, the very farm the latch closes — and even pure `FLEE` civilians became a consequence-free assault loop. A refused runner isn't stranded: its sprint decays once perception drops it to UNAWARE; it just re-flees on sight, the same permanence a latched fighter lives with.) **Dying settles a provoked grudge too** (`GameSettings.npc_ai.deaggro_on_player_death`, ships on): when a hostile NPC *kills the player*, every NPC that is hostile ONLY because it was provoked stands back down and gets its provoke rep restored — the same pardon holstering grants, except the one-shot latch is **not** spent (dying isn't you talking anyone down, so it must not cost the pardon you may still need). The score is square: they shot back and won. It lands **on the respawn**, not at the moment of death (the rule is judged at death, while your killer is still alive to be judged, then applied when you come back) — so the world calms down where you can see it and the standing-restored toast reaches a HUD that is back on screen, exactly like the death wallet toast. Without it, a `CHECKPOINT_RESPAWN` revives you into an untouched world where a town whose pardon is already spent stays hostile *forever* and every retry re-provokes it. Two limits: a hostile NPC has to have actually killed you (a fall, a hazard, your own grenade or a friendly's stray round settles nothing — nobody won that fight; note that's the same split the death *wallet* uses, so a death that settles no grudge is also the death that spills your purse on the ground instead of handing it to anyone), and only **provokes** are settled, so a faction soured by kills — and raiders, who were never provoked — go on hunting you. Turn it off to make holstering the only way back down. ⭐**The weapon that `die()` holsters for the death cinematic is NOT a stand-down** and grants no pardon (`Player.should_holster_deescalate` gates on the death latches, exactly as it does for the forced carry holster): if it counted, every death — including a fall or your own grenade — would pacify the whole level *and* burn each NPC's one-shot forgiveness, which is precisely what the killer-aware settlement above is shaped to avoid.

There's also a per-NPC override: tick **`disposition_overrides_faction`** (`bool`) and the NPC keeps its faction (for reputation, NPC-vs-NPC relations, and grouping) but reads its **own** `disposition` toward the player instead of the faction's.
> **Reputation also drives the economy.** The same per-faction standing that thaws or sours an NPC's attitude is read by a `Merchant`'s **`faction_id`**: a `reputation_discount_curve` bends prices in the player's favour (or against them) by standing, and a `StockEntry`'s `required_reputation` withholds a line until the player's standing with that faction earns it. Both are designer-set on the merchant and inert by default — see "Merchant (the "Trade" option)" under "NPC services and progression."

### How NPC-vs-NPC hostility is resolved

When two NPCs meet, `is_hostile_to` consults `HostilityHelpers.npc_vs_npc_hostile(a.faction, b.faction)`: **both** must be factioned, and faction A's `relation_to(B.id)` must be **`< 0`**. Unaligned NPCs never faction-fight. The mirror, `npc_vs_npc_allied`, treats a shared faction (same `.tres` or same `id`) or a relation **`> 0`** as allies (this drives the "Murderer!" death-witness bark when the player kills an ally).

### Worked example: adding a "Corp Security" faction allied with townsfolk

1. **Author the resource.** In the FileSystem dock, right-click `res://resources/factions/` → **Create New → Resource → Faction**. Save it as **`corp_security.tres`** (the filename is load-bearing).
2. **Fill the fields** in the inspector:
   - `id` = `corp_security` (must match the filename exactly).
   - `display_name` = `Corp Security`.
   - `default_disposition` = `NEUTRAL` (they tolerate the player until provoked).
   - `relations` — add two entries: key `raiders` → value `-1.0` (enemies, they'll shoot raiders), and key `townsfolk` → value `1.0` (allies). For the alliance to be symmetric, also add `corp_security` → `1.0` to `townsfolk.tres`'s `relations`.
3. **Nothing to "make it pickable."** The `faction_id` dropdown auto-populates from `res://resources/factions/` (both `npc.gd` and `npc_data.gd` build the hint via `Factions.ids_csv()` in `_validate_property`). The moment you save `corp_security.tres` into that folder it appears in the dropdown on every NPC and `NpcData` — no code edit at all. (Reload the project if it doesn't show immediately.)
4. **Assign it.** Select an NPC in your scene, pick **`corp_security`** from the `faction_id` dropdown, and play. They'll ignore the player (neutral baseline), gun for raiders, and stand with townsfolk.

### Gotchas

- **`id` must equal the filename.** A copy-pasted `.tres` whose internal `id` still says `raiders` while the file is named `corp_security.tres` will silently merge into the raiders' reputation pool — the registry warns about this in the editor, so watch the Output panel.
- **`relations` are one-directional.** Setting raiders→townsfolk `-1.0` does *not* automatically make townsfolk hate raiders; author the reciprocal entry on the other faction (as the shipped pair does).
- **`relations` only affects NPC-vs-NPC.** It never changes how a faction feels about the player — that's `default_disposition` + reputation.
- **`relations` keys are `StringName`s of the target's `id`**, not display names — use `corp_security`, not `Corp Security`.
- **Empty `faction_id` + null `faction` = UNALIGNED**, which uses the NPC's standalone `disposition` and ignores reputation entirely. If a factioned NPC seems to ignore rep, check whether `disposition_overrides_faction` is ticked.
- The `faction_id` dropdown is editable free-text; a typo that doesn't match a file resolves to nothing and the NPC falls back to UNALIGNED (with a warning), rather than erroring.

Relevant files: `res://scripts/faction/faction.gd`, `res://scripts/faction/factions.gd`, `res://scripts/npc/disposition.gd`, `res://scripts/npc/hostility_helpers.gd`, `res://managers/Reputation.gd`, `res://resources/factions/{raiders,townsfolk,neutral_wildlife}.tres`, and the `faction_id` exports in `res://scripts/npc/npc.gd` / `npc_data.gd`.

---

## Authoring dialogue

A conversation in CYBER SUNDAY is pure content: a tree of authored `.tres` Resources, hung off a drop-in component on whatever you want to talk to. No script ever needs editing. This section walks the resource stack from the top down, then wires a finished conversation onto an NPC.

### The resource stack

Three nested Resource types, mirroring how the editor lets you nest sub-resources inside an array field. From outside in:

| Resource (`class_name`) | Script | Key fields |
|---|---|---|
| `DialogueResource` | `res://scripts/dialogue/dialogue_resource.gd` | `lines: Array[DialogueLine]` |
| `DialogueLine` | `res://scripts/dialogue/dialogue_line.gd` | `text`, `reveals_name`, `choices: Array[DialogueChoice]` |
| `DialogueChoice` | `res://scripts/dialogue/dialogue_choice.gd` | `text`, `target`, `target_on_fail`, `required_stat`/`required_value`, `required_flag`/`required_flag_value`, and the **Consequences** group (`set_flag`, `start_quest_on_choice`, `complete_quest_id`, `advance_quest_id`/`advance_objective_id`, `give_item_id`/`give_item_count`, `give_money`) |

**`DialogueResource`** is the whole conversation — just an ordered `lines` array. `DialogueManager` plays it top to bottom. The order is also the addressing: choices jump by **index into this array**, so line 0 is the first line, line 1 the second, and so on.

**`DialogueLine`** is one spoken beat. Fill `text` (it's `@export_multiline`, so you get a real text box in the inspector). There is **no speaker field on the line** — the speaker's name comes from the talking character (see wiring, below), so you author the same `DialogueResource` for any speaker. Leave `choices` empty and the line plays linearly: the player clicks/presses to hear the next line. Add choices and the line becomes a **branch point**.

Tick **`reveals_name`** on the one line where the character introduces themselves ("The name's Marcus.") — see **"Strangers until introduced"** below.

**`DialogueChoice`** is one selectable button on a branch line. Fill `text` (the button label). The important field is `target`, an int that says where picking it goes:

- **`-2` = CONTINUE (the default).** Carries on to the *next* line. A freshly-added choice you forget to point anywhere just continues the conversation rather than dead-ending it. (In the script this constant is `DialogueLine.CONTINUE`.)
- **`-1` = END.** Finishes the conversation. (Script constant: `DialogueLine.END`.)
- **`0` or higher = BRANCH.** Jumps to that line index in `DialogueResource.lines` and re-enters the listen-first flow there.

In the inspector `target` is a plain integer field — type `-1` to end, `-2` to continue, or the destination line's index to branch. (An out-of-range index ends the conversation cleanly rather than crashing, but double-check your indices.)

### Skill checks (`required_stat` / `required_value`)

A choice can be gated behind a player stat. Set `required_stat` to a `CharacterStats` stat name as a StringName (e.g. `&"streetwise"`) and `required_value` to the threshold. If the player meets the requirement, the button shows the gate baked into its label: `[Streetwise 6] Talk them down`. (The stat's shown name is the authored `StatText` title from `resources/stats/<id>.tres` — retitle it there and the gate label, stats screen, and tooltips all follow; it is never derived from the id.) If the player's stat is below `required_value`, the option is hidden entirely.


The check is evaluated against the real human player's **effective** stat — `stats_or_default().get_stat(...)` **plus** `status_stat_modifier(...)`, i.e. live bonuses from held passive items and timed status effects — so a `+1 streetwise` trinket both *reveals* and *passes* a `required_value = 6` gate for a sheet-5 character (the hide rule reads the same effective value). Companions (NPCs in the same `Player` group) are skipped, and when no player is found the check reads `CharacterStats.BASELINE` (0) so it behaves neutrally rather than crashing. Leave `required_stat` blank (the default `&""`) and the choice has no gate. This is what makes character builds matter in conversation. (Valid stat names: `strength`, `endurance`, `gunplay`, `agility`, `streetwise`, `larceny` — an unknown name just reads BASELINE.)

### Flag gates and the fail branch (`required_flag`, `target_on_fail`)

A choice can also gate on **world state**, not just a stat. Set **`required_flag`** (a `GameState` flag name) and **`required_flag_value`** (a String, default `"true"`): the choice stays visible, but picking it only passes when `str(GameState.get_flag(required_flag)) == required_flag_value`. Leave `required_flag` blank for no flag gate. (Because the value is stringified, a bool flag set via `set_flag` matches the default `"true"`.)

Non-stat gates use the **try-and-fail** model: the choice stays selectable, and **`target_on_fail`** says where a failed attempt leads — distinct from `target`, which is where a pass leads. Same integer space as `target`:
- **`-1` = END (the default for `target_on_fail`)** — a blocked attempt ends the conversation.
- **`0` or higher = BRANCH** — jump to a "that didn't work" line.
- **`-2` = CONTINUE** — carry on regardless.

`target_on_fail` is ignored by a choice with no gate. (Note the asymmetry: `target`'s default is `-2` CONTINUE; `target_on_fail`'s default is `-1` END.)
### More gates: reputation, perk, item, quest-state (`required_faction_id` / `required_perk_id` / `required_item_id` / `required_quest_id`)

Beyond a stat (`required_stat`) and a flag (`required_flag`), a `DialogueChoice` carries four more **OPTIONAL** gates — the WR-1/WR-3 set. Every one is **INERT by default** (empty/zero); fill any combination and they **stack** (the choice passes only when *all* set gates pass). These non-stat gates stay visible and use the same `target_on_fail` routing as flag gates. Stat gates are the exception: unmet stat-gated options are hidden.

- **`required_faction_id`** (String, a faction dropdown) + **`required_reputation`** (float, default `0.0`) — reputation gate (WR-1): passes only while the player's standing with that faction is **>=** `required_reputation`. The dropdown self-populates from `resources/factions/` (§7). Empty `required_faction_id` = no rep gate.
- **`required_perk_id`** (StringName, default `&""`) — perk gate (WR-3): passes only while the player has **LEARNED** that perk (matched by `Perk.id`, §13's PerkStation). Empty = no perk gate.
- **`required_item_id`** (StringName, an item-id dropdown) + **`required_item_count`** (int, default `1`) — item gate (WR-3): passes only while the player **CARRIES** at least that many of the item. This is a **CHECK, not a cost** — the item is *not* consumed (think flashing a keycard, not handing it over). Empty `required_item_id` = no item gate.
- **`required_quest_id`** (StringName) + **`required_quest_state`** (enum `QuestGate { ANY, ACTIVE, COMPLETED, FAILED }`, default `ANY`) — quest-state gate (WR-3): passes only when that quest is in the named state right now. `ANY` = the player merely **KNOWS** the quest (active OR completed OR failed); `ACTIVE` / `COMPLETED` / `FAILED` = exactly that state. Empty `required_quest_id` = no quest gate. (See "Failing and expiring a quest" under §14 for how a quest reaches `FAILED`.)

All four are evaluated at runtime and are **fail-closed**: an *unset* gate is skipped, but a gate that is set and can't resolve — no human player in the tree, or a `required_faction_id` that matches no file in `resources/factions/` — **fails**, so the choice routes to `target_on_fail`. (Only the stat gate reads neutrally: it falls back to `CharacterStats.BASELINE`.) A typo in a gate id therefore *locks* the option rather than disabling it; an unresolvable faction id at least pushes a `Factions: no faction resource for id '<id>' ...` warning to the Output panel at runtime. They share the **same pass/fail routing** as flag gates: a gated choice stays selectable, `target` is the pass branch, **`target_on_fail`** (default `-1` END) is where a blocked attempt goes.

**Worked example — "only if they trust you, and you're carrying the data."** On one choice: `text = "Hand over the intel"`, `required_faction_id = "resistance"`, `required_reputation = 25`, `required_item_id = &"intel_chip"`, `required_item_count = 1`, `required_quest_id = &"the_handoff"`, `required_quest_state = ACTIVE`. The button stays visible, but selecting it only passes once the player is liked by the resistance, *is* carrying the chip, and has the handoff quest open. The chip is checked, not spent, so the choice itself can be the thing that turns it in via Consequences.


### Consequences (what picking a choice DOES)

A `DialogueChoice` isn't only navigation — its **Consequences** group fires side effects when the selected choice passes its gates, so a conversation can hand out quests, items, money, and flags with no script. Each is INERT when left blank/zero; fill any combination:
- **`set_flag`** (StringName) + **`set_flag_value`** (bool, default `true`) — write a global story flag via `GameState.set_flag` (which also auto-advances any matching `FLAG` quest objective, §3). Empty = none.
- **`start_quest_on_choice`** (Quest) — begin a quest via `GameState.start_quest` (safe to re-pick: starting an already-active/completed quest is a no-op). Null = none.
- **`complete_quest_id`** (StringName) — the **turn-in** path: finish a quest by id via `GameState.complete_quest` (use with the quest's `auto_complete = false`, §14). Empty = none.
- **`advance_quest_id`** + **`advance_objective_id`** (both StringName) — advance one objective by one via `GameState.advance_objective`. **BOTH** are required; this is how a dialogue choice ticks a `TALK`-adjacent or manual objective.
- **`give_item_id`** (StringName, a dropdown of item ids on disk) + **`give_item_count`** (int, default `1`) — give the player that item. Empty = none.
- **`give_money`** (float, default `0.0`) — credit the wallet; **NEGATIVE for a fee/cost** (e.g. `-50` to charge for info). `0` = none.

**Worked example — a paid streetwise check that starts a quest.** On one choice: `text = "Talk them down"`, `required_stat = &"streetwise"`, `required_value = 6` (the option is hidden below 6; at 6+ it shows `[Streetwise 6] Talk them down`), `target = 3` (the "they back off" line), and under Consequences `start_quest_on_choice =` your follow-up Quest, `give_money = -25` (a bribe). One choice: a stat-gated option that only appears for the right build and then takes the player's money and opens a quest — no code.

**Gotchas**
- **`target` is the PASS branch; `target_on_fail` is the FAIL branch.** They only diverge for visible non-stat gates (flag / reputation / perk / item / quest-state). An unmet stat gate is hidden, so it has no failed click path.
- **Different defaults.** `target` defaults to `-2` (CONTINUE) so a fresh choice doesn't dead-end; `target_on_fail` defaults to `-1` (END). Set them deliberately.
- **Consequences fire only on pass.** The `set_flag` / `give_*` / quest side effects run when a selected choice passes its gates. If a visible non-stat gate fails, the choice routes to `target_on_fail` without applying consequences.
- **`advance_quest_id` needs `advance_objective_id` too.** Setting only one does nothing — both name the target.
- **`give_money` negative = a charge.** It's the same field for rewards and costs; a positive value pays the player, a negative one bills them. There is no affordability guard and no debt clamp here, so a large negative value can push the wallet below zero.
The **Consequences** group also carries two WR-3 *write* effects beyond the give/quest/flag ones above — a conversation can move standing and turn the speaker hostile, no script. Both are **INERT by default**:

- **`reward_reputation_faction_id`** (String, a faction dropdown) + **`reward_reputation`** (float, default `0.0`) — when the choice passes, add `reward_reputation` to the player's standing with that faction (via the Factions registry → `Reputation.add_reputation`). **NEGATIVE to sour them** (a rude line costs you standing). The dropdown self-populates from `resources/factions/` (§7). Both must be set (empty id or `0.0` = no change).
- **`aggro_speaker`** (bool, default **`false`**) — when the choice passes, the NPC you're talking to is **provoked** and attacks the player once the conversation ends (a threat / insult line that draws steel). Off by default; flip it on for a "you just made an enemy" reply. (No-op if the speaker can't be provoked — e.g. an inanimate Talkable host.) It **also costs reputation** when the speaker is factioned: `provoke()` is called with `apply_rep` left at its default, so the player's standing with the speaker's *whole faction* drops by `GameSettings.reputation.provoke_penalty` (`30.0` shipped — more than double the `12.0` `kill_penalty` a member's *death* costs), so an `aggro_speaker` line sours the group, not just the individual. (An UNALIGNED speaker just turns hostile, no rep cost.) Holstering can forgive that provoke and refund the exact delta — see §7.

Like every other consequence, these fire **only on pass**. If you want a rep hit after a failed visible non-stat gate, route `target_on_fail` to a line whose choice carries the write.


### VoiceData — how lines are read aloud

Lines are spoken by the in-game offline Flite text-to-speech (the `SpeechTts` autoload). `VoiceData` (`res://scripts/dialogue/voice_data.gd`) is a small `.tres` you author once per character and assign to the talk component's `voice` slot:

- **`flite_voice`** — an `@export_enum` dropdown of the bundled voices: `cmu_us_aew`, `cmu_us_ahw`, `cmu_us_awb`, `cmu_us_eey`, `cmu_us_fem`, `cmu_us_slp`, `cmu_us_slt`. `slt` and `fem` read female; the rest read male. Leave blank to fall back to a male/female default (`cmu_us_aew` / `cmu_us_slt`, picked by the `female` fallback toggle).
- **`rate`** (0.1–4.0, default 1.0) — speaking speed. Flite scales the sample rate, so faster also reads a touch higher.
- **`pitch`** (0.1–2.0, default 1.0) — a pitch nudge *folded into* playback speed (Flite has no independent pitch knob; effective speed is `rate × pitch`, clamped). Prefer `rate` for predictable control; treat `pitch` as a sweetener.
- **`female`** — fallback toggle, only consulted when `flite_voice` is blank.

Voice is optional — leave the component's `voice` unset and the line still shows on screen, just read with the default voice. The shipped `res://resources/dialogue/old_man_voice.tres` is a one-field example: `flite_voice = "cmu_us_slt"`.

### One NPC, many conversations (`DialogueSelector`)

A single `dialogue` slot gives an NPC the *same* lines forever. To make an NPC "remember what you did" — greet you differently before vs. after a quest, or once a flag flips — author a **`DialogueSelector`** and assign it to the talk component's **`dialogue_selector`** slot instead of (or alongside) `dialogue`. Both `Talkable` and `DialogueNPC` carry the `dialogue_selector` field, and when one is set it **wins**: the component calls `dialogue_selector.pick()` to choose the conversation each time you talk.

**`DialogueSelector`** (`res://scripts/dialogue/dialogue_selector.gd`, `@tool` Resource) has two fields:
- **`rows`** (`Array[DialogueSelectorRow]`) — checked **top to bottom**; the first row whose gates all pass (and that has a `dialogue`) is used.
- **`default_dialogue`** (DialogueResource) — the baseline greeting used when **no** row matches. May be null.

Each **`DialogueSelectorRow`** (`res://scripts/dialogue/dialogue_selector_row.gd`, `@tool` Resource) is one candidate conversation plus its optional gates. `matches()` is true when **every set gate passes** — an unset gate is ignored, so a row with no gates always matches (put that one last as a catch-all, or use `default_dialogue`):
- **`dialogue`** (DialogueResource) — the conversation this row plays when it wins.
- **`required_flag`** (StringName) + **`required_flag_value`** (String, default `"true"`) — flag gate: matches when `str(GameState.get_flag(required_flag)) == required_flag_value`. Empty `required_flag` = no flag gate. (A bool flag set via `set_flag` stringifies to `"true"`.)
- **`required_quest_id`** (StringName) + **`required_quest_state`** (enum `QuestState { ANY, ACTIVE, COMPLETED, NOT_STARTED }`, default `ACTIVE`) — quest gate: the named quest must be in that state right now. Empty `required_quest_id` = no quest gate.
> **WR-6 — the selector also reacts to a FAILED quest.** `required_quest_state`'s enum is actually `QuestState { ANY, ACTIVE, COMPLETED, NOT_STARTED, FAILED }`. Pick **`FAILED`** for a row that an NPC should use *after the player blew the quest* — "you let the hostage die" instead of the thank-you. (Note `NOT_STARTED` excludes a failed quest too: once a quest has been started-and-failed it's no longer "not started".) So a single fixer can greet you with the offer (default), a nudge while `ACTIVE`, a thank-you while `COMPLETED`, and a cold shoulder while `FAILED` — four rows, no script.


**Worked example — a fixer who reacts to a quest.** Author one `DialogueSelector`, assign it to the fixer's `Talkable.dialogue_selector`, and fill `rows`:
- `[0]`: `required_quest_id = &"clear_outpost"`, `required_quest_state = COMPLETED`, `dialogue =` a "thanks for clearing it" conversation.
- `[1]`: `required_quest_id = &"clear_outpost"`, `required_quest_state = ACTIVE`, `dialogue =` a "how's it going out there?" conversation.
- `default_dialogue =` the first-meeting pitch that *offers* the quest.

Now the same fixer greets you with the offer before, a nudge during, and a thank-you after — no scripting, just rows checked top-down.

**Gotchas**
- **Selector beats `dialogue`.** If a `dialogue_selector` is assigned, the plain `dialogue` field is ignored (the component always asks the selector). Use `default_dialogue` for the baseline instead.
- **First match wins — order matters.** Put the most specific rows first; a gate-less row matches everything, so anything below it is dead. Prefer `default_dialogue` over a trailing catch-all row.
- **A selector with all rows gated and `default_dialogue` null can pick nothing.** `pick()` then returns null — but the host still *looks* talkable: the outline and the "[F] Talk to …" readout still show (the component only checks that a selector is **assigned**, not that it picks anything), the interact is accepted, and an NPC host even acknowledges and walks into frame before the conversation silently fails to open. Always give it a `default_dialogue` (or a final un-gated row).

### The listen-first reveal flow

Worth understanding so your branch lines read the way you expect. When a line opens, the player **hears it first** with only a continue prompt — the response menu is *not* shown yet. The menu appears once the line's spoken time elapses, or on the *next* click/press. On a linear line the conversation **auto-continues** to the next line after the line's spoken time (auto-advance, on by default), and a click skips ahead immediately (so clicking "skips through" a monologue). The choices menu is also auto-revealed on the **final** line, even if it has no authored choices, so the player always gets a clean way out.

When the menu does appear, the manager appends synthesized options *after* your authored choices automatically — based on components attached to the speaker: **Follow me / Wait here** (companion recruit), **Trade** (a Merchant child), **Heal** (Healer child), **Rest** (Bonfire child), **Level Up** (LevelUp child), **Install** (a ChipInstaller child), **Play Chess** (a ChessMatch child), **Exchange Gear** (a following ally with a backpack), and always a final **Goodbye.** to leave. You don't author those — attaching the relevant component to the NPC makes them appear.

### Auto-advance (lines play themselves)

By default a conversation **auto-continues**, New Vegas style: when a line finishes being spoken it advances to the next on its own, no click required (a click still skips ahead, and the response menu still waits for input). The pacing lives in `GameSettings.dialogue` (the `DialogueSettings` Resource at `res://resources/tuning/DialogueSettings.tres`), under the **Auto-advance** group:

- **`auto_advance`** (bool, default **on**) — the master switch. Off = the player clicks/presses to advance every line.
- **`auto_advance_seconds_per_char`** (`0.07`) — estimated spoken time per character for text-only fallback timing and the talking head-bob / mouth-flap.
- **`auto_advance_min_seconds`** (`1.6`) / **`auto_advance_max_seconds`** (`9.0`) — floor and cap on the estimated text-only spoken time and talking animation, so a one-word line still holds briefly and a wall of text doesn't stall when no TTS audio is playing.

When TTS audio is on, auto-advance waits for the generated Flite audio to finish instead of the clamped estimate, so longer spoken lines are not cut off early. When TTS is off, a line's spoken time is `length × per_char`, clamped to `[min, max]`.

### Face light (readable faces during dialogue)

The NPC you're talking to is automatically lit by a soft key light on its face, so its expression stays readable even in a dark scene. It's **automatic — no wiring, no per-NPC node**: `DialogueManager` owns one `DialogueFaceLight` (`res://scripts/dialogue/dialogue_face_light.gd`, a code-built child alongside the dialogue box and music ducker), retargeted to whoever the current speaker is. The light **fades in** as the box opens and **fades out** when the conversation ends. Its pose is **static** — placed once, on the first frame the speaker's head resolves, then held fixed in world space so it stays a steady key light the NPC's head-look can turn under (it deliberately does **not** ride the head frame-to-frame). An inanimate speaker with no head (a note / terminal) gets no light — it only keys onto an NPC's face (resolved via `head_world_position` / `head_visual`).

Tuning lives in `GameSettings.dialogue` (the `DialogueSettings` Resource), under the **Face Light** group:

- **`face_light_enabled`** (bool, default **on**) — master switch. Off = no dialogue face light at all.
- **`face_light_energy`** (`3.0`) — peak brightness at full fade-in. **`face_light_color`** (`(1.0, 0.96, 0.88)`, a warm off-white key).
- **`face_light_spot_angle`** (`32.0°`) — cone width of the pool on the face. **`face_light_range`** (`4.0` m) — max throw, kept local to the NPC so it doesn't light the whole room.
- **`face_light_distance`** (`1.2` m in front of the face, toward you) / **`face_light_height`** (`0.35` m above) — where the light sits before aiming back at the head. **`face_light_fade_speed`** (`6.0`) — how snappily it fades in/out.

### Wiring a conversation onto an NPC

Behaviour is a drop-in component. Two interchangeable ways to make a thing talkable; both behave identically to the player's look-at interaction ray:

- **`Talkable`** (`res://scripts/components/talkable.gd`, scene `res://scenes/dialogue/talkable.tscn`) — an `Area3D` you instance *as a child* of an existing node (a villager, an enemy you can parley with, a car). Use this to add talk to something without overriding its root script. This is the path used on real combat NPCs.
- **`DialogueNPC`** (`res://scripts/components/dialogue_npc.gd`) — a script on the node itself, with a child `Area3D` assigned to its `range_area`. Use it for a self-contained inanimate speaker (terminal, sign).

Both expose the same dialogue fields: **`dialogue`** (the `DialogueResource` — leave it unset and the host can't be talked to), **`voice`** (the `VoiceData`, optional), and **`display_name`**. Leave `display_name` blank on a `Talkable` and it uses the host NPC's `display_name`, so a talkable NPC is named once on the NPC itself; set it to name an inanimate host. `turn_to_face` makes a character rotate toward the player on talk (default **on** for `Talkable`, **off** for `DialogueNPC` — flip it on for a character).

The component does the rest: it sits on the talk physics layer so the interaction ray finds it when aimed at, highlights the host with a white outline while you look (tunable via `highlight_color` / `highlight_width`), and on interact calls `DialogueManager.start(dialogue, host, voice, name)`. `DialogueManager` must be registered as an autoload named exactly **`DialogueManager`** (Project Settings → Autoload) — it usually already is.

### Worked example: a talkable car

The shipped `res://resources/dialogue/old_man.tres` is a two-line shell — its line/choice **text fields ship unauthored** (empty, per the AI-text scrub), so any wording below is illustrative only; the *structure* is what the example demonstrates:

- **Line 0** — a single linear line, no choices (plays straight through to the next line).
- **Line 1** — a line with **two choices**, both left at the default `target = -2` (CONTINUE), so picking either one rolls past the end of the line list and the conversation finishes.

To wire it onto a car in your level:

1. Select the car node in the scene. Instance `talkable.tscn` (the `Talkable` component) as a child.
2. Size its `CollisionShape3D` to roughly cover the car's body — that's what the player aims at.
3. In the inspector, set the component's **Dialogue → dialogue** to `res://resources/dialogue/old_man.tres`.
4. Set **voice** to `res://resources/dialogue/old_man_voice.tres` (or your own `VoiceData`).
5. Since a car is inanimate, set **display_name** to `"Old Man"` (or whatever the speaker is) and turn **Interaction → turn_to_face** off so the car doesn't pivot.

Aim at the car, press interact (F / PickUp), and the box opens with line 0 read aloud, then line 1 with your two reply buttons.

To go further: add a third line for a real branch — point line 1's second choice at `target = 2`, and author line 2 as the follow-up. To add a skill gate, give a choice `required_stat = &"streetwise"` and `required_value = 6`; it'll show `[Streetwise 6] ...` and lock until the player's streetwise clears 6.

### Strangers until introduced

Every NPC is shown to the player as **"Stranger"** until they say their name in conversation. That single placeholder replaces the real `display_name` **everywhere the player reads it** — the dialogue speaker label, the look-at hover ("Talk to Stranger" / "Pick Pocket Stranger"), the corpse loot prompt ("Loot Stranger"), the death card ("Killed by Stranger"), the takedown prompt, and the cripple toast. It does **not** touch identity: a `kill <name>` / `talk to <name>` quest objective matches the NPC's stable identity key (`NpcData.id`, falling back to the authored `display_name`), so masking never breaks a quest.

You open the gate per line: tick **`reveals_name`** on the `DialogueLine` where the character introduces themselves (e.g. a line whose `text` is *"The name's Marcus."*). When that line plays, the NPC's real name is learned — from that moment the speaker label on that same line, and every surface after, shows **Marcus**. It **sticks across a save** (persisted in `GameState.known_names`) and is **wiped on New Game** (a fresh run re-meets everyone as a Stranger).

- **A hostile stranger's name is *hidden entirely* on hover.** Aiming at a HOSTILE NPC you haven't been introduced to shows **nothing** under the crosshair (not even "Stranger") — an anonymous threat. If you're crouched and can pickpocket them, the verb alone still shows ("Pick Pocket", no name). The moment their name is revealed, a hostile NPC reads out its real name again. A NON-hostile stranger still reads "Talk to Stranger" so you know you can approach them.
- **Identity is the key, and it's authorable.** The reveal is keyed by the NPC's stable identity — `NpcData.id`, falling back to the authored `display_name` when no id is set. Two id-less NPCs sharing one `display_name` are therefore "the same person" once introduced (the pre-identity behaviour); give them distinct `NpcData.id`s to keep their quest/ledger identities separate. (Note: the on-screen masking still keys by the shown string, so two same-named NPCs both *display* as known once one introduces themselves — quests and the ledger stay distinct.) Generic mob names (`Raider`) never get a `reveals_name` line, so they simply stay "Stranger" forever — which reads correctly (you never learned who they were).
- **`NpcData.id` also future-proofs quests.** A KILL/TALK objective's `target_id` should be the `NpcData.id` where one exists — it keeps matching if you later edit or localise the `display_name`, and a claimed pet renamed by the player still counts toward its authored objective. Objectives authored against a display name keep working (it matches as the fallback).
- **Only real characters are masked.** An inanimate `DialogueNPC` speaker (terminal, sign) and a nameless NPC are never "Stranger" — a `reveals_name` tick on a terminal's line is a harmless no-op.
- **Turn it off while authoring.** Flip `GameState.stranger_names_enabled` to `false` (a dev switch, not a player setting — it resets to `true` each launch) to see every real name outright.
- The label seam is **`GameState.public_name(real_name)`**, and the placeholder word lives in **`PlayerText.STRANGER`** (edit it there to relabel, e.g. `"???"`).

### Gotchas

- **Targets are line *indices*, not line objects.** If you reorder or delete lines in `DialogueResource.lines`, every `target >= 0` that pointed past the change now points somewhere else. Re-check branch targets after reordering.
- **`-2` continues, `-1` ends.** It's easy to leave a choice at the default `-2` (CONTINUE) when you meant to end the conversation — that choice will roll into the next line instead of closing the box.
- **No per-line speaker.** Don't look for a speaker/name field on `DialogueLine`; the name comes from the talk component's `display_name` (or the host NPC's). Set it on the component, once.
- **Listen-first means an extra beat on branch lines.** Players hear the line, *then* the choices appear (once its spoken time elapses, or on the next input). That's intended, not a bug — author your branch text as something the NPC says before offering the options.
- **Lines auto-advance by default.** With `GameSettings.dialogue.auto_advance` on (the default), a linear line continues on its own after its spoken time (New Vegas style) — you no longer click every line. A click still skips ahead and the menu still waits. Turn `auto_advance` off in `DialogueSettings.tres` to require a click per line.
- **Empty `dialogue` = silent.** A `Talkable` / `DialogueNPC` with no `DialogueResource` assigned simply does nothing on interact (and a `Talkable` host won't even register as talkable). Assign the resource.
- **`voice` is optional but `flite_voice` matters.** With no `VoiceData`, lines read in a default voice; pick `flite_voice` per character so two NPCs don't sound identical. (Note: `cmu_us_slt` — the one the shipped `old_man_voice.tres` uses — reads *female*; pick a male voice like `cmu_us_aew` if that's the character.)
- **A hostile or in-combat NPC won't talk.** `Talkable.can_be_talked_to()` refuses a hostile or fighting NPC — the talk highlight and prompt won't even show. That's by design; don't expect to parley mid-firefight.

Relevant files: `rpg/scripts/dialogue/dialogue_resource.gd`, `dialogue_line.gd`, `dialogue_choice.gd`, `dialogue_manager.gd`, `voice_data.gd`, `dialogue_view.gd`; components `rpg/scripts/components/talkable.gd` and `dialogue_npc.gd`; example content `rpg/resources/dialogue/old_man.tres` and `old_man_voice.tres`; scene `rpg/scenes/dialogue/talkable.tscn`.

---

## Items, loot, money and pickups

Everything a player can hold, take, or steal in CYBER SUNDAY funnels through one little data type — the **Item** Resource — and a handful of drop-in components that hand Items (and zorkmids) to the player. None of it needs code. You author Item `.tres` files in the inspector, then drop pickup/container/corpse nodes into your level and fill their `@export` lists. This section walks the whole chain.

### 1. The Item Resource (`res://scripts/items/item.gd`)

An `Item` (`class_name Item`) is the atom of everything carryable. Create one with **right-click in the FileSystem → New Resource → Item**, save it under `res://resources/items/` (that's where the shipped ones live — `healthpack.tres`, `pistol_item.tres`, `ammo_pistol.tres`, …), and fill these fields:

**Identity & Display**
- `id` (StringName) — the stable lookup key, unique per `.tres` (e.g. `&"healthpack"`). Used by `ItemDb` and save/load.
- `display_name` (String) — what shows in the inventory, loot screen, and "[F] Take …" prompts.
- `description` (multiline) — tooltip / detail text.
- `icon` (Texture2D) — optional AUTHORED override; when set, grid tiles draw it (winning over a baked `resources/icons/<id>.png` and the live mesh). Usually left null: a grid tile picks its art as authored `icon` → baked icon PNG (CYBER SUNDAY → Icons, which covers EVERY item — an authored model when present, else a procedural stand-in) → the item's live 3D MESH (a weapon's `WeaponData.view_model`, else this item's `world_model`) → a small category glyph (only seen for an item added since the last bake). A stack placed rotated on the grid draws its icon/mesh turned 90° to match its footprint. The item's name shows on hover in the footer detail line.

**Classification & Stats**
- `category` (enum: `WEAPON / CONSUMABLE / AMMO / MISC`) — gates which fields below matter and which helper (`is_weapon` / `is_ammo` / `is_consumable`) applies. A non-gear item that has a `world_prop` or `world_model` is **`is_holdable`** — it can be placed on the hotbar and pulled into your hands (see **World Model** below), with one exception: the `zorkmids` wallet coin tile (it wears a `world_model` but is money, not a prop — see the *Hotbar-holdable props* callout below).
- `max_stack` (int) — how many fit in one stack. `1` = unstackable (always set this for weapons); `>1` lets ammo/consumables pile up (the Health Pack uses `5`).
- `weapon` (WeaponData) — set **only** on `WEAPON`-category items; point it at a weapon `.tres` like `res://resources/weapons/pistol.tres`. This is what makes the item equippable.
- `caliber` (StringName) — for `AMMO` items, the caliber these rounds feed (e.g. `&"pistol"`), matched against a weapon's own `caliber` on reload. (Shipped calibers are `pistol`, `smg`, `shells`, `rifle`, `grenades`.)
- `weight` (float) — abstract carry weight of one of this item; summed into the carrier's load (over capacity = encumbered/slowed).
- `value` (float) — base trade value in **zorkmids** (the in-game currency). Fractional — zorkmids run in hundredths, so `0.5` is half a zorkmid. `0` = worthless / unsellable.
- `heal_amount` (float) — for `CONSUMABLE` items, HP restored when used from the inventory.
- `held_passive_effect` (StatusEffect) — optional **Dota-style passive buff granted while this item is merely CARRIED** (no equip). Point it at a `StatusEffect` `.tres`; only its `stat_modifiers` + `speed_multiplier` are read (author `duration = 0`). On any category. See **§1c** below.
- `passive_unique` (bool) — for a `held_passive_effect`: `true` = carrying multiple copies still grants the buff **once** (Dota "unique" items); default `false` = it **stacks** with the count held.

**World Model**
- `world_model` (Resource — a model scene `.glb`/`.gltf`/`.blend`, or a raw `Mesh` `.obj`) — optional unique 3D model for when this item sits **in the world** (dropped/looted/spawned). A pickup with `build_model_from_item` on will instantiate this and auto-fit its hitbox. Null = the pickup keeps whatever body it was authored with. **Doubles as the inventory-grid thumbnail** for non-weapon items (a weapon falls back to its `WeaponData.view_model`); set it on an ammo/consumable to give that item a 3D icon instead of the default glyph.

> **Hotbar-holdable props.** Any non-gear item that has a `world_prop` (an authored prop scene like the **Dog** or the **Dog Crate**) *or* a `world_model` is **`is_holdable`**: the player can **hand-assign** it to a hotbar slot (open the backpack, hover the item, press a slot key — holdables never auto-fill, so a pocket of dogs can't crowd out your guns) and then press that slot to **pull the prop out into their hands** — carried hands-free exactly like an aimed **Z**-grab. Pressing the slot again **stashes it back** into the bag; **dropping/throwing** it (F/Z/left-click) instead leaves it in the world as a normal re-collectible pickup and vacates the slot. While held from the hotbar the prop is temporarily **indestructible** (it floats at arm's length blocking fire — a 1-HP prop like the Dog Crate would otherwise be shot out of your hands and the bag item lost); its authored destructibility is restored the instant you drop or throw it. Nothing to wire — it falls out of the item having a world representation. **One exclusion: the `zorkmids` wallet coin tile is NOT holdable**, even though `MoneyPurse` gives it the money-bag `world_model` — it's money, not a carryable prop, so `Item.is_holdable()` guards its id and it can never be hotbar-assigned or pulled into your hands (that would mint a physics money-bag out of the wallet).

**Inventory grid** (the Tetris-style spatial backpack)
- `grid_width` / `grid_height` (int, clamped ≥1) — the item's **footprint** in backpack cells (Resident Evil / Deus Ex style). `1×1` is a single cell; bigger, distinct shapes make weapons read differently and force packing/rotation. The shipped weapons are authored: pistol `2×1`, SMG `3×1`, shotgun `4×2`, sniper `5×1`, melee `1×3`, spray paint `1×2`; ammo and consumables stay `1×1`, and misc usually does too — but the bulky props are bigger: the **Dog** and the **Dog Crate** are `2×2` and the Sealed Package is `2×1` (and the player's own zorkmids tile grows with the wallet — see the money-purse gotcha below). Each STACK occupies one footprint (not each unit), and the player can **rotate** a held item with **R** while dragging it. The grid's overall size is a global tunable — `GameSettings.inventory.grid_cols/grid_rows` (see §12). The player AND every NPC share that grid — an NPC is capped to the player's size and drops a matching bag — while a fresh corpse-copy / persistent container / merchant stock stays unbounded until the loot screen grids it. A stack that can't be placed (bag full, or a footprint too big for even an empty grid) is kept **unplaced** — it's no longer invisible: `GridInventoryView` renders every unplaced stack as a one-cell tile in a **click-only overflow strip** below the grid (left-click = take/equip, right-click = drop; no drag in or out), so it can still be taken. Sizing the grid to fit an NPC's authored loadout keeps loot tidy, but an over-authored bag no longer soft-locks a corpse with unlootable overflow.

> One Item class covers everything — there is deliberately no `WeaponItem` subclass. A weapon is just an Item with `category = WEAPON` and a `weapon` reference, because Godot's typed-array `.tres` serialization doesn't reliably round-trip script subclasses inside an `Array[Item]`.

### 1b. Status effects on a consumable (buffs / poison / stims)

A potion that haunts you for 8 seconds, a stim that hastens your stride, a poison dart that ticks your HP down — all of it is one tiny data type, the **`StatusEffect`** Resource (`res://scripts/combat/status_effect.gd`, `class_name StatusEffect`), riding on a consumable Item. You author the effect `.tres` in the inspector, drag it into an Item's `consumable_effect`, and the player applies it by using the item from the backpack. No code.

#### Authoring a StatusEffect .tres

Create one with the **Content** generator or with **right-click in the FileSystem → New Resource → StatusEffect**. Save status-effect resources under `res://resources/status/`; shipped examples include `poison.tres` and `adrenaline.tres`. The fields:

- **`id`** (StringName, default `&""`) — the dedup key. A **non-empty** id makes re-applying the *same* effect **refresh its duration** instead of stacking a second copy (use the same stim twice and the timer just resets to full). An **empty** id always stacks, so two copies run independently. Set an id for anything a player might re-use mid-effect; leave it empty only when you genuinely want them to pile up.
- **`display_name`** (String) — human label for the effect.
- **`description`** (`@export_multiline`) — detail text.
- **`icon`** (Texture2D) — optional effect icon.
- **`duration`** (float, default `5.0`) — seconds the effect lasts. **`0` = permanent** until something explicitly removes it (`remove_effect` / `clear_effects`).
- **`tick_interval`** (float, default `1.0`) — seconds between periodic ticks. **`0` = no periodic effect at all** (a pure buff/debuff with no DoT).
- **`damage_per_tick`** (float, default `0.0`) — HP applied to the host each tick. **Positive = damage** (poison/burn). Needs `tick_interval > 0` to ever fire; `0` means no DoT.
- **`stat_modifiers`** (Dictionary, default `{}`) — per-stat additive tweaks, e.g. `{ "agility": 2 }`. **Consumed for the live stats** — agility (move/jump), gunplay (gun damage / aim sway), streetwise (shop prices + reputation), larceny (detection + pickpocketing), and strength's **melee-damage** component — folded live via `Character.status_stat_modifier`. `strength`'s carry-capacity/max-HP are the exception (see Gotchas): they're stamped once at spawn, so a *timed* modifier can't move them (only the melee part responds). Buffs never touch `get_stat`, so they don't open dialogue skill-checks or stat-gates.
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

1. **New Resource → StatusEffect**, save as `res://resources/status/poison.tres`. Set:
   - `id` = `&"poison"` (non-empty → re-use refreshes the timer)
   - `duration` = `8.0`
   - `tick_interval` = `1.0`
   - `damage_per_tick` = `4.0`
   - `speed_multiplier` = `0.8`
2. On the consumable Item `.tres`: `category` = `CONSUMABLE`, `heal_amount` = `0`, and drag `poison.tres` into `consumable_effect`.
3. Done. Using it deals 4 HP/tick for 8 seconds at 0.8× move speed. Using it again before it expires **refreshes** the full 8 seconds (because `id` is non-empty) rather than stacking a second poison.

**A haste potion** is the same recipe with no DoT: `id` = `&"haste"`, `duration` = `10.0`, `tick_interval` = `0.0`, `damage_per_tick` = `0.0`, `speed_multiplier` = `1.5`. Pair it with `heal_amount` on the Item if you want a heal-and-run stim.

#### Gotchas

- **`stat_modifiers` on a TIMED (consumable) effect works for the live MULTIPLIER stats; strength's carry/max-HP are stamped, not live.** A buff on `agility`, `gunplay`, `streetwise`, or `larceny` folds live into move/jump, gun-damage/sway, shop prices + reputation, detection, and the pickpocket flow (via `Character.status_stat_modifier`). A `{ "strength": 2 }` buff on a *consumable* still moves strength's **melee damage** (that's read live at the swing), but does **nothing** to carry capacity or max HP — those are stamped once at spawn, not read live, so a temporary modifier can't move them. Author permanent carry/HP gains as perks/level-ups, or as a **`held_passive_effect`** (§1c) — the held-item path *does* re-stamp strength onto carry/max-HP while the item is carried.
- **Empty `id` stacks; non-empty `id` refreshes.** If a re-used effect is doubling up when you wanted a timer reset (or vice-versa), check the `id` field — that single field decides it.
- **No DoT without an interval.** `damage_per_tick` is ignored unless `tick_interval > 0`. A "poison" with `tick_interval = 0` does nothing.
- **You don't place the manager for consumables.** The `"StatusEffects"` node appears on the player automatically on first consumable use. Only drop a `StatusEffectManager` by hand for always-on / NPC effects you drive from a script.
- **`duration = 0` is permanent**, not instant — it lasts until `remove_effect` / `clear_effects`. Use it only for effects you intend to clear yourself.

Relevant files: `res://scripts/combat/status_effect.gd`, `res://scripts/components/status_effect_manager.gd`, `item.gd` (`consumable_effect`), and the character speed hook in `Character.status_move_multiplier()`.

### 1c. Passive item buffs — "carry it, get the buff" (Dota / ARTS idiom)

In Dota 2 and other ARTS games, an item in your inventory grants its bonus **passively — no equip step**. This game does the same: give any Item a **`held_passive_effect`** and its buff is on the instant the item enters your backpack and off the instant it leaves. No node to place, no code — it's reconciled automatically by the **`PassiveItemBuffs`** component every `Character` (player *and* NPC) carries.

#### How to author one

1. **Author a `StatusEffect` `.tres`** exactly as in §1b, but for a passive: set **`duration = 0`** (it's ignored anyway — held effects have no timer) and fill **`stat_modifiers`** and/or **`speed_multiplier`** with the buff. Give it a `display_name` for readability. Save under `res://resources/status/`.
2. On the Item `.tres`, drag that effect into **`held_passive_effect`** (it sits just below `consumable_effect`). This works on **any** category — a `MISC` trinket, a `WEAPON` that buffs while merely owned, etc.
3. Optionally tick **`passive_unique`** if holding several copies should still count as one.

That's the whole feature. The moment the item is in the backpack the carrier gets the buff; drop, sell, or deposit it and the buff is gone.

**You don't write a `description` — the tooltip derives one.** Item `description`s ship blank (the Steam AI-text scrub), so the inventory / loot / shop hover tooltip *computes* the effect line from the data instead: a `held_passive_effect` reads as `While carried: +3 Streetwise · …` (a held `strength` shows as its real `Max HP` + `Carry` gain, since that's what it re-stamps — never a misleading "+N Strength"), a `consumable_effect` as `When used: …`, and an `installs_ability` chip as `Installs Wall Climb`. It's all in `ItemInfo._effect_lines` (`res://scripts/ui/item_info.gd`), pulling stat titles from `StatInfo.title` and the ability name from `AbilityRegistry.display_name_for` (the ability scene root's authored `display_name`) — so a new trinket communicates itself with **zero** authored prose. Just wire the effect and the numbers speak; pinned by `res://tests/test_item_info.gd`.

#### What each stat does (and the one asymmetry)

- **The "live" stats fold in for free, and STACK by count.** `agility` (move/jump), `gunplay` (gun damage / aim sway), `streetwise` (shop prices + reputation), `larceny` (detection + pickpocketing), plus `speed_multiplier`, are read live at their existing seams — carrying **two** non-unique `{ "agility": 1 }` trinkets gives `+2` agility. (`speed_multiplier` compounds: two `1.5×` items = `2.25×`.)
- **`strength`'s carry / max-HP DO re-stamp here** (unlike a consumable effect). A held `strength` re-stamps both **carry capacity** (`+2` each) and **max HP** (`+1.5` each) — the same conversion a level-up uses, applied as a running delta so dropping the item takes back exactly what it gave. A held `{ "strength": 2 }` really does raise your max HP by 3 **and your carry capacity by 4** while carried (and heals you up to it; dropping it while wounded lowers max HP and clamps current HP, never below 1) — but it does **not** touch melee damage (`PassiveItemBuffs.stat_modifier()` returns `0` for strength, so a held strength buff is a carry/HP item only). (A *timed* strength buff is the mirror image — it only reaches the melee component; the stamped carry/HP need the held path. Author a melee buff as a consumable `consumable_effect` instead.)
- **`get_stat()` still isn't touched.** A held buff never opens a dialogue skill-check or a stat-gate — those read your permanent build only. Buffs are gameplay power, not identity.

#### Save / load & stacking notes

- **Nothing extra is saved.** The buff is a pure function of what's in the bag, and your inventory is already saved — on load the buffs rebuild themselves as the bag restores. (Max HP isn't stored as a number; it re-derives from your stat sheet at spawn, then the held delta is re-added, so a `+HP` trinket never double-counts.)
- **Held buffs and consumable buffs stack.** If you drink a `+agility` stim while carrying a `+agility` trinket, both apply.

#### Worked example — the Ironheart Locket (shipped)

> Goal: a trinket that, *while carried*, grants **+3 max HP**, **+4 carry capacity** and **+5% move speed**, and stacks if you hold more than one.

Already shipped so you can drop it in a loot table or a starting loadout immediately:

1. `res://resources/status/held_ironheart.tres` — a `StatusEffect` with `duration = 0`, `stat_modifiers = { "agility": 1, "strength": 2 }`, `speed_multiplier = 1.0`.
2. `res://resources/items/ironheart_locket.tres` — a `MISC` Item (`id = &"ironheart_locket"`, `max_stack = 5`) with `held_passive_effect` → the effect above and `passive_unique = false`.

Pick it up and your max HP rises by 3, your carry capacity by 4, and you move 5% faster; carry a second and it doubles; drop them and you're back to baseline. To make it a **unique** (one-copy) buff instead, tick `passive_unique` on the Item.

Relevant files: `res://scripts/components/passive_item_buffs.gd` (`class_name PassiveItemBuffs`), `item.gd` (`held_passive_effect` / `passive_unique`), the fold hooks `Character.status_stat_modifier()` / `status_move_multiplier()`, and the strength factors `CharacterStats.CARRY_PER_STRENGTH` / `HP_PER_STRENGTH` (not `MELEE_DAMAGE_PER_STRENGTH` — that const feeds `melee_damage_mult()`, which the held path never reaches).

#### The shipped trinket set

Ten passive-buff trinkets ship in `res://resources/items/` (each with a matching `duration = 0` effect in `res://resources/status/held_*.tres`). Drop them in loot tables, container stock, merchant stock, or NPC bags:

| Item | Buff (per copy) | Stacks? |
|---|---|---|
| `ironheart_locket` | +3 max HP, +4 carry, +5% move | stacks |
| `trigger_bone` | +2 gunplay (damage / steadier aim) | stacks |
| `mule_rig` | +6 carry capacity, +4.5 max HP | stacks |
| `kickstart_stims` | +2 agility, +10% move | stacks |
| `rep_tags` | +2 streetwise (bigger rep, cheaper trades) | stacks |
| `chrome_grin` | +3 streetwise (cheaper trades, bigger rep) | **unique** |
| `deadeye_optic` | +4 gunplay | **unique** |
| `second_wind_cell` | +7.5 max HP, +10 carry | **unique** |
| `featherframe_weave` | +3 agility, **−4 carry**, **−3 max HP** (risk/reward) | stacks |
| `juggernaut_plate` | +9 max HP, +12 carry, **−2 agility** (risk/reward) | **unique** |

Add more the same way (§1c), or one-click a `StatusEffect` + Item in the CYBER SUNDAY **Content** tab and wire `held_passive_effect` in the inspector.

### 1e. Randomly giving NPCs trinkets — `RandomInventory` (`res://scripts/components/random_inventory.gd`)

To sprinkle these across your NPCs, drop a **`RandomInventory`** node under an NPC (anywhere in its subtree). On spawn it drops a **random** handful of items into that NPC's backpack — which means (via §1c) the NPC actually *wears* the buffs, and drops the trinkets as loot when you kill it. **Add it, leave the defaults, done:** an empty `pool` falls back to every passive-buff trinket in the game.

Exports:
- `pool` (`Array[Item]`) — the items it can grant. **Leave empty** to draw from every Item with a `held_passive_effect` (all the trinkets above). Fill it to restrict the roll to a hand-picked set (only a faction's gear, only weapons, etc.).
- `use_all_passive_items_if_empty` (bool, default on) — the empty-pool fallback above. Turn off for a placed-but-inert roller.
- `min_items` / `max_items` (int, default 1 / 2) — how many it rolls per spawn.
- `allow_duplicates` (bool, default off) — off = distinct items (count capped at the pool size); on = the same item can come up twice, **stacking its buff**.
- `chance` (0..1, default 1.0) — the fraction of NPCs that get *anything*, so not every enemy is dripping in chrome. `0.3` = about a third.
- `rng_seed` (int, default 0) — `0` rolls fresh every spawn; a non-zero value gives that placement the **same** roll every time.

Notes: it only makes sense on **NPCs** (the player's bag is the bounded Tetris grid). NPC bags aren't saved, so a `0`-seed roller re-rolls on every level load — set `rng_seed` if you want a specific NPC to always carry the same thing. The roll is deferred one frame so it lands after the NPC's own loadout is seeded (it adds on top, never replaces).

### 2. ItemStack — "N of this item" (`res://scripts/items/item_stack.gd`)

When you want to author *contents* — what's inside a crate, what a pickup grants — you don't repeat an Item N times. You use an **`ItemStack`** (`class_name ItemStack`), which is just two fields:

- `item` (Item) — the item this row holds (null = the row is ignored).
- `count` (`@export_range 0..9999`) — how many. `0` skips the row.

So "5 healthpacks, 30 pistol ammo, 2 shotguns" is **three rows**, each an Item + a count. The rule for how counts expand is shared everywhere (containers, pickups, NPC bags) so it can't drift:
- **Weapons** (`is_weapon()`) are seeded as **one unique instance per count** — 2 shotguns become two distinct objects (no shared-instance bugs).
- **Stackables** (ammo, junk, consumables) stack to the count as the shared template.

`ItemStack` appears as an `item_stacks: Array[ItemStack]` export on the components below. In the inspector you just set the array size, then for each element drag in an Item `.tres` and type a count.

### 3. Putting loot + money into a crate — `ItemContainer` (`res://scripts/components/container.gd`)

A crate, chest, locker, or fridge is the **`ItemContainer`** component (`class_name ItemContainer`, extends `LookAtInteractable`). It's a *persistent* two-way stash: the player aims at it, presses **F (Interact)**, and the loot-transfer screen opens on the container's own inventory — they can take things out **or** deposit their own gear and come back later (unlike a corpse, a container is never freed).

**Setup**
1. Add an `ItemContainer` node under your crate's visual (or assign `highlight_target`).
2. Size its `CollisionShape3D` to cover the body the player aims at.
3. Fill in the contents exports:
   - `item_stacks` (`Array[ItemStack]`) — **the way to fill a crate.** Count-based rows (item + count).
   - `money` (float) — zorkmids stashed inside. At spawn it's seeded as a real **zorkmids coin tile** in the contents (the same coin tile a corpse drops), looted by clicking it like any other item. `0` = no cash. Fractional allowed.
   - `loot_table` (LootTable) — **optional** random loot rolled in *on top* of the fixed contents at spawn (see the **LootTable** entry below). Null = just the fixed contents.
   - `container_name` (String) — shown on the hover ("Loot \<name>") and the transfer screen title. Blank = just "Container".
   - `save_id` (StringName, optional) — stable id for the **exact-save (quicksave/slot) tier**. Leave blank for most crates (a level|node-path fallback identifies them); set it on a *story* container whose looted/stashed state must survive you renaming/re-parenting the node in a later scene edit. Mirrors `NPC.save_id` / `Corpse.save_id`.

At spawn the container builds a child `CharacterInventory` and seeds it from `item_stacks`, then rolls the optional `loot_table` on top. It joins the `&"containers"` group, so a nearby under-armed NPC can even raid it for a better gun (`NpcScavenge`).

> If you drop a `Lock` node as a child of the container, the first E press attempts the lock (pick/key) before opening — a failed attempt toasts what the lock needs and the hover reads "Unlock \<name>" instead of "Loot \<name>".

**What persists.** A **manual quicksave/slot save** snapshots every authored container exactly — contents (incl. the coin tile and per-instance weapon state), the grid layout the player arranged, and a `Lock` child's picked-open state — so on quickload a looted crate stays looted, a stash survives, and the loot table does NOT re-roll (a child `Restocker` also can't insta-refill on the first reopen; its cycle resumes one full interval later). The lean **autosave/Continue** deliberately persists none of this: containers re-seed fresh from their authored exports on Continue (the profile-vs-snapshot tier split in `docs/CURRENT_ARCHITECTURE.md`).

**Worked example — a supply crate behind the gas station**

> Goal: a crate holding 5 health packs, 30 pistol rounds, a spare pistol, and 120 zorkmids.

1. Drop an `ItemContainer` under your crate mesh; size the collider to the box.
2. Set `container_name` = `Supply Crate`.
3. Set `money` = `120`.
4. Expand `item_stacks`, set size **3**:
   - `[0]` item = `res://resources/items/healthpack.tres`, count = `5`
   - `[1]` item = `res://resources/items/ammo_pistol.tres`, count = `30`
   - `[2]` item = `res://resources/items/pistol_item.tres`, count = `1`
5. Done. The pistol seeds as its own unique instance; ammo and packs stack. Aim, press F, and the player sees the health packs, ammo, and pistol tiles plus a **120-zorkmid coin tile** — click it to pocket the cash, same as any other item.

### 4. Scattering pickups around the level "New Vegas style"

For loose loot lying on the ground — a stimpak on a shelf, ammo in a gutter, a weapon on a dead-end rooftop — use the lighter **`CanPickUp`** component (`res://scripts/components/can_pick_up.gd`, `class_name CanPickUp`, extends `LookAtInteractable`). Aim, press F, the item goes straight into the player's backpack and the world object frees itself. No transfer screen — it's a grab, not a container.

**Payload exports**
- `item` (Item) — the single item granted on pickup.
- `amount` (int) — how many of `item` (weapons add as that many unique instances).
- `item_stacks` (`Array[ItemStack]`) — **a count-based mini-pile** granted on top of `item` ("2 stims + 10 ammo" in one pickup). Leave empty for a plain single-item pickup.
- `loot_table` (LootTable) — optional random loot on top; can be set **without** an `item` for a pure random-loot bag.
- `auto_equip_weapon` (bool, **on** by default) — when `item` is a weapon, picking it up **draws it immediately, but only while the player is unarmed** (bare fists — `equipped_item` null). An already-armed player keeps what they're holding, so grabbing a pipe off the floor can't swap the rifle away mid-fight; note that's about *owning* a weapon, not having it out — a merely holstered gun still counts as armed. It goes through the normal equip bridge (`CharacterInventory.equip_item` → the swap animation, which also un-holsters), and it equips the **unique instance that was just granted**, so carrying two of the same gun still marks the right one. Only `item` auto-equips — never an `item_stacks` pile or a `loot_table` roll. Turn it OFF for a weapon the player should own but not wield even when unarmed (a quest piece, a gift). Players can also switch it off globally in **Options → Game → "Auto-Equip Weapons When Unarmed"** (`Settings.auto_equip_pickups`); both the export and the setting must be on.

**Hover Label**
- `pickup_label` (String) — blank → "Take \<item name>".

**World Visual**
- `build_model_from_item` (bool) — when on, builds the world visual at spawn (from `item.world_model`, or a built-in glowing placeholder box if the item has none, so it's never invisible) and auto-fits the hitbox. Mainly for code-spawned/dropped loot; for hand-placed pickups you usually just parent the component under an existing model instead.

To litter a level New-Vegas style, the workflow is: author each loose item once as an Item `.tres`, then place `CanPickUp` nodes wherever you want them, drag the Item into `item`, and (optionally) give visual variety via each Item's `world_model` with `build_model_from_item` on. A single pistol on a crate is one `CanPickUp` with `item = pistol_item.tres`; a "junk pile" is one `CanPickUp` with three `item_stacks` rows. It's pickable as long as it has *anything* to give (a fixed item, a pile, or a table).

#### Making a physics prop (Throwable) ALSO stashable — the "dual item"

A `Throwable` (`res://scripts/components/Throwable.gd`) is a `RigidBody3D` physics prop you carry/throw with the **Throw key (Z)** — a crate, bottle, trashcan, etc. To *also* let the player tuck one into the backpack, drop a **`CanPickUp` as a child of the `Throwable`**. The player then gets two verbs on the same object:

- **F (Interact)** → stash it into the backpack (the `CanPickUp`'s payload)
- **Z (Throw)** → grab it to carry/throw, exactly as before

This is the same object `WorldItem.build()` constructs in code for dropped loot, so the E-vs-Z priority is already handled in `ray_cast.gd` — no scripting.

**The one invariant:** the `CanPickUp` must be a **descendant of the `Throwable`** (drop it directly under the prop). That ancestry is what tells the interaction ray to run E (stash) instead of grabbing the body that's physically closer to the camera. A `CanPickUp` floating as a *sibling* of the prop will be grabbed-through instead of stashed.

**Setup**
1. Open your `Throwable` prop scene (e.g. `res://scenes/throwable/cube.tscn`).
2. Add a `CanPickUp` node as a **child** of the prop root.
3. Give the `CanPickUp` its own `CollisionShape3D` sized to the body you aim at (its talk-layer hitbox — slightly larger than the prop is easiest to target). Or set the `CanPickUp`'s `auto_fit_collider = true` to size it to the prop's meshes at runtime.
4. Set `highlight_target` to the prop root (so E frees the whole prop and the prop — not the bare hitbox — outlines on hover). Left blank it falls back to the parent, which is the same node here.
5. Author an Item `.tres` for the prop and drag it into `item` (the backpack holds Items, so anything stashable needs one). A bare crate just needs a simple `MISC` item with no `world_prop`. (Note `res://resources/items/crate_item.tres` is **not** a plain example — it's the fully-wired **Dog Crate** (`id = dog_crate`, `world_prop` already set to `dogcrate.tscn`), so dropping it spawns the destructible dog-crate prop, not a bare box.)

**Ready-made example.** `res://scenes/throwable/stashable_crate.tscn` is exactly this: a `cube.tscn` crate with a `CanPickUp` child granting `crate_item.tres` (the **Dog Crate** item — its `world_prop` is `dogcrate.tscn`, so a dropped-back crate rebuilds the destructible dog-crate prop, not a bare box). Drag it into a level and you can throw the crate with **Z** or pocket it with **E**. (Your bare `cube.tscn` crates are unchanged — stashing is opt-in per prop.)

**Drop fidelity & unique behaviour — `Item.world_prop`.** By default, dropping a stashed item back out of the backpack (`Player.drop_item`, via `WorldItem.build()`) rebuilds a *generic* throwable — a small gray box for non-weapon items, not the original prop. To make the item drop as a **specific prop scene that keeps its own behaviour** — a dog crate that's destructible and spawns a dog on break, a barrel with a loot table — set the Item's **`world_prop`** field to that prop scene's path. `WorldItem.build()` then spawns *that exact scene* on every drop/place instead of the placeholder. A prop is one physical object, so dropping a **stack** of more than one still spawns a single prop — but its `CanPickUp` is stamped with the full stack count, so pressing **E** re-stashes every unit; no items are silently lost. (Right-clicking one grid tile drops only *that* stack, so an unstackable prop like the dog crate drops one at a time regardless.)

**Taking the wielded weapon in hand (`H` / `DropHeld`).** **H** is a **two-stage hand verb**, and on your own weapon a **toggle**. Carrying a physics prop (world-grabbed or hotbar-pulled)? H sets it down without a throw. Hands free but a weapon **wielded**? H takes the knife/gun out of the holster and **into your hands as a carried prop** (`Player.hold_equipped_weapon` → `Player._pull_and_hold`, the same path the hotbar's hold-from-backpack action uses) — you fall back to bare fists, and the item leaves the bag but keeps its hotbar slot **reserved**. From there: **H again PUTS IT BACK** — the item returns to the bag *and* is re-wielded, so two presses leave you exactly where you started (`Player.return_held_weapon_to_hands` → `stash_held_item`, whose re-draw runs *after* the carry release because carrying keeps the weapon `draw_locked`); **left-click** or a **Z**-hold throws it; an **E**/**Z** tap still sets it on the ground. Pressing that weapon's **hotbar slot key** while it's in your hands does the same put-back. A weapon that can't build a `Throwable` falls back to the old floor drop (`drop_item`). Saving while a weapon is in your hands folds it back into the backpack snapshot (`GameState` reads `Player.held_inventory_item()`), so a reload lands it in the bag rather than losing it.

Every **weapon** that falls through to the default throwable shell (`build()` cases 2/3/4 — i.e. a weapon with no `world_prop`, which is every weapon today) is **indestructible** (`Throwable.destructible = false`) so a stray shot or hard impact can't break a dropped gun/knife, and it inherits its `WeaponData`'s **Thrown** group: `thrown_uses_weapon_damage` (a thrown hit lands as a real *weapon* hit — weapon damage, headshots, **the sneak-attack multiplier against a target that hasn't noticed you**, limb damage — instead of a speed-based bludgeon), `thrown_pins_body_part` (a lethal hit staples the struck limb to the wall behind, blade through it — see *The PIN kill* under Effects tuning), `thrown_impact_damage_mult` (a final "hits harder thrown" multiplier), `thrown_impulse_mult` (launch speed — the knife is *hurled*, a gun is tossed), `thrown_sound` (a signature throw whip), `thrown_faces_travel` + `thrown_face_rotation_degrees` (nose toward the travel direction — the knife leads with its point; guns leave it off and tumble), `thrown_trail` + `thrown_trail_color` (drag a white tracer behind it in flight — **on by default for every weapon**; see *The thrown-weapon tracer* under Effects tuning), `held_faces_aim` (in your hands, the business end points down your look direction — held ready to throw), `dropped_item_light_always_lit` (keep the red weapon glow at every range), plus `dropped_model_offset` / `dropped_collision_size`, which seat and shape the dropped object. (Non-weapon drops are unchanged.)

`world_prop` is a **scene PATH** (an `@export_file` with a file picker — browse to the `.tscn`, or drag it in), **not** a `PackedScene` slot. That's deliberate: the clean pattern points `world_prop` at the **same prop scene** whose `CanPickUp` grants this item, so the loop is seamless — place the prop → stash with **E** (you get the item) → drop the item → it's the real prop again (destructible, throwable, re-stashable). But that makes the prop reference the item *and* the item reference the prop. A direct `PackedScene` reference both ways is a **load-time cycle** — Godot throws *"Recursion detected, unable to assign resource to property."* Storing a path sidesteps it: a path isn't a load-time dependency, so `WorldItem.build()` just `load()`s it at drop time (by when the item is already loaded). No cycle.

**Worked example — the dog crate (`res://scenes/props/dogcrate.tscn`):** a `Throwable` (destructible, `max_hp 1`) with a `SpawnOnDestroy` set to spawn `dog.tscn` on break, plus a `CanPickUp` granting `crate_item.tres`. `crate_item.tres` **already ships with `world_prop` = `res://scenes/props/dogcrate.tscn`**, so the dropped crate is the full destructible-spawns-a-dog prop, not a box. (Authoring a *fresh* prop item you'd set `world_prop` yourself, via the file picker.) (`world_prop` is the whole authored object; the older `world_model` is only a visual mesh for a generic pickup.)

**Re-drop fidelity — per-instance state survives stash → drop.** A `world_prop` drop rebuilds the scene FRESH, which would otherwise re-roll every random component (a picked-up brown dog dropping as a re-rolled grey stray, forgetting it was befriended). To avoid that, the pickup STASHES a prop's live per-instance state onto its `Item` (as metadata) and the drop RESTORES it onto the rebuilt scene via a matching `preset_*` field the component applies on `_ready`. Wired for the **dog** today (`DogPickup` captures; `WorldItem.build` restores): its **size** (`RandomSize.SIZE_META` → `preset_scale_mult`), its **coat colour** (`RandomCoat.COAT_META` → `preset_tint` — the exact tint on the mesh, whether from a random roll or a spray-paint recolour), and its **befriended state** (`Claimable.CLAIMED_META`/`CLAIMED_NAME_META` → `preset_claimed`/`preset_claim_name` — so a dropped dog keeps its name, follows you again, and stays loyal). This is a WITHIN-SESSION round-trip only — it is NOT a save/load persistence (a hand-placed or reloaded dog still rolls fresh; see the `RandomCoat`/`SprayPaintable` "not persisted" notes below). To extend the pattern to another random prop, give its roller a `preset_*` export honoured over the roll and add capture/restore metas the same way. **The dog's inventory icon** is the baked `res://resources/icons/dog.png` (from the CYBER SUNDAY Icons bake of `world_prop` → `dog.tscn`); a `world_prop`-only item has no live mesh to render in the grid, so it relies on the baked icon — re-run the Icons bake if you change the dog's model, and commit the PNG **with** its `.import` sidecar. The icon is baked at the **neutral white base** (the Icons baker strips every script before rendering, so `RandomCoat` never rolls into the PNG), and the inventory tile then **modulates it by the dog's captured coat tint** (`RandomCoat.COAT_META` → `GridTile.icon_modulate_for`) — so a picked-up brown, black, or spray-painted dog's tile shows its **real colour** instead of always white, matching the 3D dog exactly (the tile multiply mirrors how `RandomCoat` recolours the mesh by multiplying its base albedo). Keep the PNG baked at the white base — if a coat ever baked into it, the draw-time tint would double-apply.

### 5. Looting corpses — `LootableCorpse` (`res://scripts/components/lootable_corpse.gd`)

You normally **don't place this by hand** — `LootableCorpse` (`class_name LootableCorpse`, extends `LookAtInteractable`) is spawned automatically when an NPC dies. It copies the dead NPC's backpack (so freeing the NPC can't drain the loot) and its **wallet** (designer-set money plus any kill bounties it earned in life), which `setup` **seeds as a real zorkmids coin tile in the loot bag** — cash loots exactly like any other item, no separate "Take N zm" button to miss. Then it attaches as a child of the on-death drop — the `LootBag`, the rigged skeleton `Ragdoll`, or (for an NPC with no `ragdoll_scene`) a free-standing corpse. The player aims at the drop, presses E, and the same loot-transfer screen opens — every item tile *including the coin tile*. The drop lingers until the whole bag (coins included) is emptied, then fades; a fully drained one stops highlighting and reads as just the bare name.

The one tunable you might touch is `trigger_radius` (float, default `1.2`) — the radius of the loot hitbox (it follows the crumpling body on a skeleton ragdoll; on a resting `LootBag` it simply rides the bag). Where the corpse's contents come from is authored upstream on the NPC: its starting gear/loadout and its `NpcData.loot` LootTable, which is rolled into the backpack on death and lands in the corpse. So to make an enemy drop good loot, you stock that enemy — not the corpse component.

### 6. LootTable — random drops (`res://scripts/items/loot_table.gd`)

A **`LootTable`** (`class_name LootTable`) is the random-loot Resource you plug into `loot_table` on a container or `CanPickUp`, or into an `NpcData.loot`. It holds an `entries: Array[LootEntry]`, and each `LootEntry` (`res://scripts/items/loot_entry.gd`) rolls **independently**:

- `item` (Item) — what drops.
- `chance` (`@export_range 0..1`) — probability this row drops at all. `0.0` never drops; `1.0` always drops.
- `min_count` / `max_count` (int) — the count range rolled when it hits.

Because rows are independent, one table can mix a guaranteed "1–3 ammo" (`chance 1.0`) with a rare "10% keycard" (`chance 0.1`). Weapons rolled from a table become unique instances, same as everywhere else.

### 7. UpgradePickup — granting player unlocks (`res://scripts/components/upgrade_pickup.gd`)

For a **permanent player ability** (grappling hook, wall-climb, air dash…) rather than an inventory item, use **`UpgradePickup`** (`class_name UpgradePickup`, extends `LookAtInteractable`). Aim + Interact and it adds the ability node to the player immediately, toasts, autosaves the run (a new mechanic is a milestone), and frees itself.

> **Instant grant vs. the microchip two-step.** `UpgradePickup` grants the ability *on the spot*. The game's normal upgrade progression instead uses **microchips**: the player picks up a chip Item (which does nothing on its own) and pays a **`ChipInstaller`** mechanic to install it — see "NPC services and progression → ChipInstaller". A fresh game starts with **no** abilities (`Player.tscn` `starting_unlocks` is empty) beyond any implants **bought on credit** at New Game (the implant-purchase step — see *Saving → Starting implants (bought on credit)*; the bill starts the run with a **negative wallet**, and an empty cart is allowed), so chips are the main path; reach for `UpgradePickup` only when you want a pickup that comes online immediately.

**Exports**
- `grants` (PackedScene) — **the preferred way.** Drag an ability scene from `res://scenes/components/abilities/` here (the shipped set: `Grapple.tscn`, `WallClimb.tscn`, `AirDash.tscn`, `Slide.tscn`, `FallImmunity.tscn`, `SilentTakedown.tscn`, `ChessVisualizer.tscn` — the Board Visualizer chip for the blindfold-chess minigame). Its node — with its own authored config — is added under the player on pickup. Takes precedence over `unlock_id`. A scene whose root isn't an `Ability` is discarded and grants nothing (fails safe).
- `unlock_id` (String) — **fallback**, used only when `grants` is empty. It's an `ENUM_SUGGESTION` dropdown offering `grapple, wall_climb, air_dash, slide, fall_immunity, silent_takedown, chess_visualizer` (you can pick from the list or leave it blank); the chosen id is passed to `player.unlock_mechanic()`. Prefer `grants`. The dropdown **self-populates** from the `.tscn` files in `scenes/components/abilities/` via `AbilityRegistry` (each scene's PascalCase filename snake-cased), so it can't drift out of sync with the shipped abilities.
- `display_name` (String) — shown in the pickup toast and the "Take \<name>" hover (e.g. "Grappling Hook").
- `world_model` (Resource — a model scene or raw Mesh) — optional custom visual; with none assigned it builds a small glowing blue emblem so a bare pickup is still visible and auto-fits its hitbox.
- `toast_color` (Color) — tint of the "\<name> acquired!" toast.

**Worked example — a grappling-hook upgrade on a rooftop**

1. Drop an `UpgradePickup` node where you want it.
2. Set `grants` = `res://scenes/components/abilities/Grapple.tscn`.
3. Set `display_name` = `Grappling Hook`.
4. (Optional) set `world_model` or leave it for the default emblem.
5. Done — walking up and pressing F grants the grapple ability node to the player on the spot, toasts "Grappling Hook acquired!", and autosaves.

**Tuning an ability.** Each ability *scene* carries its own `@export` config -- open `Grapple.tscn` for its `config` (a `GrappleHookResource` rope `.tres`; null falls back to the Player's own `grapple_resource`), `WallClimb.tscn` for `climb_hop_up` / `climb_hop_forward` / `wall_climb_speed`, and so on; every ability also inherits an `enabled` flag **and a `display_name`** — the mechanic's player-facing name ("Wall Climb"), edited on the scene root in the Inspector. UI resolves it *by id* through `AbilityRegistry.display_name_for()` (the one canonical accessor — e.g. the upgrade-chip tooltip's "Installs …" line); a blank `display_name` degrades to the capitalized id, never a blank. It is display-only: behaviour, saves, and grants still key on `ability_id()`. Tune the scene (or the `UpgradePickup`'s instanced copy of it) like any other node.

**Adding a NEW ability scene.** Writing the ability itself is code (a script extending `Ability`, overriding `ability_id()` and the movement hooks). Follow the **naming convention** across all three files: the script `res://scripts/components/abilities/<id>.gd`, its scene `res://scenes/components/abilities/<PascalCase>.tscn`, and its `ability_id()` must all agree in snake_case (`wall_climb.gd` ↔ `WallClimb.tscn` ↔ `&"wall_climb"`). `AbilityRegistry` scans the scenes folder to self-populate the `unlock_id` dropdown **and** derives the script path from the id (`AbilityRegistry.script_path_for`), so a runtime grant (chip install / save load) rebuilds the node with no hand-maintained id→script table — there is no `Player.ABILITY_SCRIPTS` to update. A drift test (`test_ability_scripts_covers_registry_ids`) enforces that every scanned scene id is buildable, so a mismatched or missing script fails the test rather than silently granting nothing. The grant/revoke/persistence itself is handled by the Player-owned `AbilityManager` (`scripts/components/abilities/ability_manager.gd`) — you don't touch it to add an ability.

### 8. Loose money — `MoneyPickUp` (`res://scripts/components/money_pickup.gd`)

For a pure stash of cash on the ground (not inside a container or corpse), drop a **`MoneyPickUp`** (`class_name MoneyPickUp`). Set `amount` (float, fractional allowed) — on F it credits the player's wallet, fires the HUD readout + floating "+N" indicator, plays a **"cha-ching!"** jingle (`AudioManager.play_2d_sfx`), and frees itself. With no authored body it builds a simple gold coin (or `world_model` if you assign one); `pickup_label` overrides the default "Take N zorkmids" hover. The collect sound is the `pickup_sound` export (defaults to the coin `Chaching.mp3`) at `pickup_volume_db` — clear `pickup_sound` for a silent pickup, or drop in your own reward sting. This fires for **every** money pickup, including the `Reclaim` child on a dropped money bag (below), so scooping a bag back up cha-chings too.

**Player money-bag drop (`MoneyBag`, `res://scripts/components/money_bag.gd`).** Two things spawn one: the player right-clicking their zorkmids tile in the backpack (`Player.drop_money`), and **dying with nobody to blame** (`Player._spill_death_purse` — a fall, a hazard, your own grenade spills your purse where you fell; see the *Death group* callout under Global tuning). Both go through the same builder, so a purse you dumped and a purse you dropped dead are the same reclaimable object. Either way you get a physics **money bag** instead of a bare coin: a `Throwable` sack (grab with the carry key, hurl it as a weapon) with a `MoneyPickUp` child so aiming + Interact scoops the whole purse back into the wallet and frees the bag — the same "dual item" a dropped weapon or a corpse's `LootBag` uses. A fat purse is a better bludgeon: the bag's **size, mass, and throw damage all scale with the amount** it holds (via the new `Throwable.impact_damage_mult`). It's built in code (no scene to author); the curves are designer-tuned on **`EconomySettings`** (group **Money bag**: `money_bag_min_size` / `_max_size` / `_size_per_sqrt_zm`, `_base_mass` / `_mass_per_zm` / `_max_mass`, `_damage_per_zm` / `_max_damage_mult`). The bag is `destructible = false` (a stray shot can't burst it and lose the cash).

**Staying collected across a reload (`save_id` / `persist_collected`).** Both `MoneyPickUp` (§8) and `UpgradePickup` (§7) now record a "gone" bit in the save's per-object ledger when collected — exactly like `CanPickUp` / `CanDestroy` — so a hand-placed pickup **doesn't respawn** on Continue (a `MoneyPickUp` would otherwise be infinite money) or **re-grant** its upgrade. For a pickup whose collected-state must survive layout edits, author a stable **`save_id`** (Save group); blank falls back to a fragile level+path+position key, which silently re-keys if you move/rename the node — fine for a pickup that never moves, but set an id on anything important. **`persist_collected`** defaults true; set it **false only for code-spawned pickups** — a dropped money bag's `Reclaim` child sets it so a dynamic spawn (no stable identity) never clutters or mis-keys the ledger. You touch neither export for a plain hand-placed pickup.

### 9. Pickup item lights — the colour-coded glow on pickups (`res://scripts/components/pickup_beacon.gd`)

Every world pickup can carry a small **item light**: a local `OmniLight3D` on the object itself that fades out as you get close. There are no vertical shafts, mesh beacons, or distance-fade pillars. You author **nothing** for the default case — each pickup component spawns its own light at runtime:

- **`CanPickUp`** (hand-placed, dropped, or loot-dropped) — colour is derived from the item's **kind** (weapon / ammo / consumable / passive-buff / chip); a pure loot-table cache with no fixed `item` glows as a loot-sack. It exposes TWO knobs (Item Light group): **`item_light`** (default on) — untick it for a bespoke pickup that shouldn't glow (a big authored prop, a hidden stash); and **`item_light_always_lit`** (default off) — see *Always-lit lights* below. Old scenes that set `loot_beacon` still migrate into the `item_light` setting.
- **`MoneyPickUp`** → a gold glow. **`UpgradePickup`** → a cyan glow (echoing the acquire toast).
- **`LootableCorpse`** (the enemy-dropped **sack** / lootable body) → a glow that **scales with how much it still holds** and **hides once looted empty**. It rides the settling ragdoll or sits on the dropped bag automatically.

**Colour = KIND.** The classifier (`PickupBeacon.kind_for_item`) checks most-specific-first: microchip (`installs_ability`) → weapon → ammo → consumable → **passive** (`held_passive_effect`, the Chrome Grin idiom — a MISC-category item that grants a carry buff) → misc.

**Always-lit lights — a glow that survives being picked up and thrown.** The default distance fade is built for loot *on the ground*: it is **fully off inside `near_distance` (3 m)** so a pickup you're standing over doesn't glare. That is exactly wrong for something you **carry and throw** — at arm's length the light is dark, which is why a knife in your hands used to have no glow at all. Set **`CanPickUp.item_light_always_lit`** (→ `PickupBeacon.always_lit`) and the light burns at full brightness at *every* range, beating both the near fade **and** the optional `max_distance` cull (the other thing it must stay visible for is the knife you just threw across the yard). The light also drops the small ground lift and sits **on** the object, since that offset is in the body's local space and would otherwise swing around and trail a nosing blade in flight. Because it's viewed from ~1 m rather than the 9 m the ground energy is tuned for, it's scaled by **`always_lit_energy_scale`** / **`always_lit_range_scale`** (below). You rarely set this by hand: a **weapon** turns it on from `WeaponData.dropped_item_light_always_lit` (the knife does), and it applies uniformly on the floor, in your hands, and in flight. It is still an item light, so the player's **Item Lights** option governs it like every other.

**Tuning is one place: `GameSettings.pickup_beacons`** (`resources/tuning/PickupBeaconSettings.tres`). The palette is eight `Color`s (`weapon_color`, `ammo_color`, `consumable_color`, `passive_color`, `chip_color`, `money_color`, `loot_bag_color`, `misc_color`); the look is `light_energy` / `light_range`; the fade is `near_distance` (fully off) → `full_distance` (fully on), with optional `max_distance` cull; the always-lit trims are `always_lit_energy_scale` / `always_lit_range_scale` (both `1.0` = identical to a ground pickup; they multiply **only** always-lit lights); the sack scaling is `bag_min_scale` / `bag_max_scale` / `bag_count_for_max` (distinct stacks that hit max brightness).

**Player toggle.** Options → **Accessibility → Item Lights** (`Settings.loot_beacons_enabled`) hides/shows every pickup light instantly (polled live). **Stealth-safe:** each light joins `Groups.PICKUP_BEACON`, which `PlayerLightLevel` skips, so item lights never make the player easier for enemies to detect.

### Gotchas

- **Always set `max_stack = 1` on weapon Items.** Weapons must be unique instances; a stackable weapon breaks the "each weapon is its own object" assumption the whole loot pipeline relies on.
- **A `WEAPON`-category Item with no `weapon` assigned isn't a weapon** — `is_weapon()` checks both. It'll behave as plain junk (stacks, won't equip).
- **`category` in the saved `.tres` is the enum *index*** — `0=WEAPON, 1=CONSUMABLE, 2=AMMO, 3=MISC`. Edit it through the inspector dropdown, not the raw text, to avoid mislabeling (e.g. `healthpack.tres` shows `category = 1` for CONSUMABLE).
- **Author cash via the `money` field; it's seeded as a real `zorkmids` coin tile — don't hand-place one.** For containers and corpses the authored `money` float is turned into a genuine `zorkmids` coin Item tile in the loot at spawn (`ItemContainer._seed_money_coins` / `LootableCorpse.setup`), so cash loots by clicking the tile like any other item — **no "Take N zm" button to miss**. Author the amount in the `money` field and let the component build the tile; don't put a raw `zorkmids` entry in `item_stacks` or a `LootTable`. **Even a *live* NPC's wallet is a coin tile now** — `LootScreen._freeze_live_wallet` mints its `Character.money` float into a real 1×1 `zorkmids` tile in its pockets when you open them, and `_refloat_live_wallet` folds any un-taken (or planted) coins back into that float on close, so the NPC still carries a plain float between robberies (looting the same NPC's **corpse** later shows the coin tile as normal). There is no "Take N zm" button anywhere in the game. The **player's own backpack** mirrors the wallet the same way, but *live*: the player's `money` is *mirrored* into a real `zorkmids` coin Item (`resources/items/zorkmids.tres`, id `&"zorkmids"`) by the **`MoneyPurse`** component (`scripts/inventory/money_purse.gd`), so your money shows up as a genuine draggable tile in the grid (rendering the `bag.glb` mesh) you can right-click to **drop** as a physics **money bag** (`MoneyBag`) — a grabbable, throwable purse that gets bigger and hits harder the more zorkmids it holds (aim + Interact pockets it back; see §8). The player tile's **grid footprint also grows with the amount** (a fat purse hogs more cells — a square whose side scales on a √ curve, tuned by `EconomySettings` `money_bag_grid_*`); it only ever grows into FREE cells, never evicting other items, and stays smaller if the next size won't fit. (Corpse / container coin tiles stay a fixed 1×1, so they always place on the loot grid.) It's auto-managed: `money` (the fractional float on `Character`) stays the single source of truth the whole economy reads, one coin-unit = one `Zorkmids.QUANTUM` (0.01 zm) so the integer stack stays fractional, and the **player's** coin stack is **excluded from the save** (money persists as the `[player]` wallet float and the purse rebuilds the stack on load; corpses aren't saved at all, so their coin tiles re-seed from `money` on the next spawn; a **container's** coin tile is real loot and DOES survive a manual quicksave/slot load, re-seeding only on the profile/Continue tier). You don't author or place the player tile — dropping `zorkmids.tres` in `resources/items/` registered it; the player gets the tile automatically.
- **The PLAYER and every NPC backpack is spatially bounded** (`grid_cols × grid_rows` cells, footprints from each Item). A pickup or loot-take can be **refused when the grid is full** — the world pickup stays put and a "No room" toast fires; a shop won't charge for something that won't fit. So a player can't carry infinite loot, and an NPC carries no more than the player — size the grid (`GameSettings.inventory`) and item footprints with that in mind, and keep NPC loadouts within the grid (overflow is kept but **unplaced** — now shown in a **click-only overflow strip** below the grid so it can still be taken, no longer invisible loot). A fresh corpse-copy / persistent container / merchant stock is UNBOUNDED until the loot screen grids it.
- **The loot / pickpocket / container screen is two GRIDS** (source on top, your bag below), not two lists. Click an item to take/deposit it, drag within a grid to rearrange, or **drag a tile across into the other grid** to transfer it into the exact slot you aim at. Authoring is unchanged — you still just fill `item_stacks` / `money`.
- **The SHOP is two grids too** (stock on top, your bag below). Click a tile to buy/sell one, or drag it across to trade it into a chosen slot. Because a grid cell has no room for a price column, the hovered item's **price** (and whether you can afford it) is shown in the detail line under the grids — that's the deliberate trade for a shelf that renders real item meshes like every other transfer surface. The **Sort** button now physically *repacks* both grids into the chosen order rather than reordering rows. A merchant's shelf gets the roomier `container_grid_cols/rows` on first open, so an over-authored `stock_counts` list can leave its tail in the click-only overflow strip below the grid rather than on it.
- **You can ATTEMPT to lift anything — value sets the ODDS, not permission.** Every loose item in an off-guard NPC's pockets is clickable at any `larceny`, including the expensive stuff (a **microchip**, a fat gemstone). Value up to your skill-scaled allowance (`base_value_allowance` + `value_allowance_per_point` × larceny) lifts at the plain catch chance; every zorkmid **above** that adds `over_value_risk` to the caught roll. The hover tooltip shows the resulting odds live, so a 250-zm chip reads an honest **0%** for a novice, **28%** around larceny 12, and **64%** for a master — you always know what you're gambling before you click, and investing in larceny both widens the free band *and* flattens the overage penalty. (This replaced a hard "too valuable to lift" refusal: a wall reads as a bug — *why can't I even try?* — where terrible odds read as a skill problem you can go fix. Loose **cash** and valueless junk never carry value-risk; robbing a rich mark is no harder per coin than a poor one.)
- **Pickpocketing the weapon a live NPC is actively holding takes skill.** Its wielded gun (`inventory.equipped_item`) shows as a **padlock** on the pickpocket grid and refuses the take (a "Can't lift the weapon they're holding" toast) until your `larceny` reaches `GameSettings.pickpocket.equipped_pickpocket_threshold` (ships at **8**) — below that you can't pluck a drawn gun out of someone's hands; at or above it a master thief can, and the lift still rolls the normal caught check. Everything else in their pockets is fair game: lift their **ammo** to disarm them mid-sneak, or take the weapon off their **corpse**. This lock is pickpocket-only — corpse loot, a companion **gear exchange**, and containers still hand over the equipped weapon normally.
- **PLANTING a weapon on an NPC only arms a COMBATANT, and only in combat.** You can deposit items into a live NPC's pockets (reverse-pickpocket) or a following ally's bag (gear exchange). A weapon lands in their backpack, but an NPC equips it from there *only* when it's fighting (its combat AI draws the strongest backpack gun on the next alerted tick) — so a peaceful enemy you hand a gun stays empty-handed until it engages, then draws it. A **civilian** (an NPC authored with no `weapon_data`, hence no weapon "hub") can **never** wield a planted gun; depositing one fires a **"They can't use a weapon"** toast so you know it's cosmetic. Want an enemy to actually use a gun? Give it `weapon_data` (or a weapon in `item_stacks`) at authoring time.
- **`UpgradePickup`: assign `grants`, not `unlock_id`.** The scene carries its ability's authored config; `unlock_id` is just a string fallback for pickups authored before the scene system and grants a bare mechanic. Don't fill in both — `grants` wins and the id is ignored.
- **You don't author corpses.** `LootableCorpse` is spawned on death; to change what a body drops, edit the NPC's loadout and its `NpcData.loot` LootTable, not the corpse component.
- **`loot_table` rolls on top of fixed contents**, it doesn't replace them. A crate with both `item_stacks` and a `loot_table` gives the guaranteed items *plus* whatever the table rolls.

Relevant files: `res://scripts/items/item.gd`, `item_stack.gd`, `loot_table.gd`, `loot_entry.gd`; `res://scripts/components/container.gd`, `lootable_corpse.gd`, `can_pick_up.gd`, `upgrade_pickup.gd`, `money_pickup.gd`; example content under `res://resources/items/` and ability scenes under `res://scenes/components/abilities/`.

---

## Weapons and ammo

Every gun, blade, and pair of fists in CYBER SUNDAY is one `WeaponData` resource (`rpg/scripts/combat/weapon_data.gd`). It is pure data — the entire firing pipeline reads its `@export` fields — so a new weapon is a new `.tres` you author in the inspector, never a code change. The shipped weapons live in `res://resources/weapons/`: `pistol.tres`, `smg.tres`, `shotgun.tres`, `sniper_wep.tres`, `melee.tres` (a knife), `fists.tres`, `rock_weapon.tres`, and `spray_paint.tres`. Open any of them to see a worked-out example of the knobs below.

### Authoring a WeaponData .tres

In the editor: **FileSystem → right-click `resources/weapons/` → New Resource → search "WeaponData"**. Save it (e.g. `ar15.tres`), then fill in the Inspector. The fields are grouped exactly as they appear in the panel:

- **General** — `effective_range` (metres; the hitscan ray stops here, and a ranged NPC uses it as its standoff distance; `0` = unranged — note that an NPC wielding a gun with a `projectile_scene` *and* a positive `effective_range` also **fires while still closing**, up to `GameSettings.npc_ai.fire_grace_range` metres beyond this standoff, because its projectiles genuinely fly past the hitscan cap — so a short `effective_range` sets where it *wants* to stand, not a hard silence radius; an *unranged* lob like the rock gets no such band, since its fallback engage distance already exceeds its ballistic reach), and `move_speed_multiplier`, the speed scale applied to the wielder *while this weapon is drawn* (`1.0` = no penalty; the SMG uses `0.93`, fists use `1.25` to make you faster bare-handed).
- **Damage** — `is_melee` (the explicit "this is a melee weapon" flag — it decides which stat scales the hit; see *Melee vs. ranged* below), `damage` (HP per hit, *per pellet* on a shotgun; the player has only 4 HP, so `1.0` is a quarter-bar), `headshot_multiplier`, `sneak_attack_multiplier` (hitting an un-alerted enemy), `backstab_multiplier` (inert at `1.0` until you raise it) / `backstab_arc_degrees` (the rear arc that counts as a backstab, `90.0` = the back quarter), and `overkill_penetration` (excess damage punches through to whoever's behind).
- **Thrown** — how a **dropped copy of this weapon** behaves as a physics prop (the `H` verb takes the wielded weapon into your hands; left-click or a `Z`-hold throws it). A weapon drop carries no `ThrowableData`, so these *are* its authoring surface. **Most** are stamped onto the drop's `Throwable` (or, for the item light, its `CanPickUp`) by `WorldItem._make_throwable`; the other two shape the drop itself in `WorldItem.build()` — and those two are read **only in its case 3** (the weapon's `view_model` is the drop's visual, i.e. no `world_model`), with `dropped_model_offset` additionally gated on **`npc_hold_override`** being ON. Leave that override off and the offset is a silent no-op. `thrown_uses_weapon_damage` → `Throwable.thrown_weapon` (the WeaponData itself). **This is the knob that decides what a thrown hit even IS.** OFF (default) the prop deals the generic speed-based bludgeon every crate deals — `round((impact m/s − 6) × 0.4)` — which is right for a gun you toss aside. ON, the hit resolves as a real **weapon** hit through the same `ShotResolver` the swing and the bullet use: the weapon's `damage`, its `headshot_multiplier` on a hit in the target's head zone, and its melee/ranged stat scaling, with the located contact point forwarded so **limb and zone damage apply exactly as from a swing**. Sneak and backstab multipliers are deliberately *not* rolled in — at the impact site the prop knows neither the victim's alert state nor the approach arc, and stacking the knife's `4.0` sneak would put a throw far past the swing it's meant to match. The knife has this ON, so a thrown knife deals **2.0 body / 6.0 head**, identical to swinging it. Why it matters beyond flavour: the blunt formula scales with **impact speed**, so tuning a weapon to fly faster silently made it hit harder — the knife's `2.5×` launch speed took it from ~10 to ~50 damage on the old path. Weapon damage is speed-independent, so the two knobs stop fighting; `thrown_impact_damage_mult` → `Throwable.impact_damage_mult`, a final multiplier applied on **both** paths so the field keeps one meaning ("how hard this prop hits when thrown"). `1.0` (the knife, and every gun) = no change — a weapon-damage thrower lands exactly its swing damage. Raise it for a weapon that should hit *harder* thrown than swung; `thrown_impulse_mult` → `Throwable.throw_impulse_mult`, the **launch-speed multiplier** on `PhysicsDamageSettings.pickup_throw_impulse` (`1.0` = a gun tossed at the same speed as a crate; the knife's `2.5` turns the base `12` m/s into `30` m/s so it reads as a *thrown blade*). It scales **only a real throw** — the `H` tap-drop and the death/quickload release stay gentle — and a value above `1.0` also switches the drop to **continuous collision detection**, because a slender body covering more than its own collider length per physics tick can otherwise tunnel through a thin wall; `thrown_sound` → `Throwable.throw_sound`, played **instead of** the release sound on a real throw (null = a throw is as quiet as a drop, right for a gun you toss aside; the knife uses `Throw.mp3`). Distinct from `audio`, the *swing* sound of the wielded weapon; `thrown_faces_travel` → `Throwable.face_travel_when_thrown` (nose toward the travel direction like a throwing knife; leave off for guns so they tumble); `thrown_face_rotation_degrees` → `Throwable.face_carrier_rotation_degrees`, the **mesh-front correction** for that facing (**note the differing field names**) — the aim points the drop's local **−Z** along travel, so the knife needs `Y = 180` because its blade points mesh **−X** and `npc_hold_rotation`'s `(0,90,0)` maps that onto the drop's **+Z**, the tail of the aim; `thrown_trail` → a **`ThrowTrail` child** added to the drop — the only field in this group that adds a *node* rather than setting one, because the streak is a drop-in component (`scripts/components/throw_trail.gd`) a hand-placed prop can get by dragging it into the scene. **ON by default, for every weapon** (it shipped knife-only): a thrown copy drags a **white tracer** behind it through its whole arc, so you can read the throw you actually made and see where the weapon went — as useful for a hurled pistol as for a blade. `thrown_trail_color` sets its colour (white by default, alpha included), and its *shape* — width, tail length, the speed it stops at — is global tuning under **Effects → Thrown weapon trail**, so every streak in the game matches. Only a **real throw** streaks: the arm rides the same `is_throw` decision as the facing and the throw sound, so the `H` tap-drop and the death/quickload release draw nothing. Landing doesn't cut the streak, it stops feeding it — the tail then fades out over its lifetime. A **tumbling** drop is fine: the `ThrowTrail` is stamped at the drop's *origin* with no offset, so a gun spinning end over end still lays a smooth line (an offset node on a tumbling body would scribble a corkscrew — that is why only a hand-placed trail on a *nosing* prop should be dragged onto the blade tip). Turn it **off** only for a weapon whose flight should not be readable, e.g. a decoy meant to be lost track of; `held_faces_aim` → `Throwable.face_carrier_while_held` **and** `Throwable.face_carrier_reversed`, which decide whether that **same correction also poses the drop while it is CARRIED**. One weapon flag sets both, because a weapon has exactly one sensible carry pose: the dog's Portal-style face-carrier machinery **reversed**, so the business end points **away, down your look direction** — a knife held blade-forward, ready to throw — rather than nosed back at your own face. OFF (guns) keeps the rotation thrown-only, exactly as before this field existed. Because the carried pose already matches where the throw will send it, releasing doesn't visibly snap the model around. **Don't** try to flip the held facing by adding another 180 to `thrown_face_rotation_degrees`: that same value is what makes the blade lead in *flight*, so it would spin the knife in the air too — that's precisely why the reversal is a direction flip (`face_carrier_reversed`) and not a rotation offset; `dropped_item_light_always_lit` → `CanPickUp.item_light_always_lit` → `PickupBeacon.always_lit`, which keeps the drop's **red weapon glow burning at every range** instead of fading out as you close on it. Ground loot *should* fade (it would glare when you stand over it), but that same fade is fully off inside 3 m — so a weapon in your hands, or one that just left them, had no glow at all. Turn it on for a weapon you actually carry and throw (§9); `dropped_model_offset`, an extra local offset added to `npc_hold_position` **only for the dropped copy** (the NPC hand mount and the FP rig ignore it) — author it as the **negated centre of the model's posed bounds**, because the thrown facing spins the prop about its body origin, so a model that isn't centred there pivots on an arm and wobbles instead of nosing. Usually a **small trim**: measure the posed bounds rather than assuming a large correction (the knife's is ~2 cm — its GLB nodes bake a `+44.33` translation that `knife.tscn`'s `-0.4285` child origin already cancels). Finally `dropped_collision_size` replaces the shared default `0.7 × 0.3 × 0.3` collider, which suits a gun lying flat but sits **broadside to every throw** once a weapon noses (the facing pins local **+Z** along travel); the knife authors a slender `0.08 × 0.10 × 0.46` box matching its blade. Zero keeps the default.
- **Firing** — `pellet_count` (>1 makes a shotgun spread) and `pellet_spread`, `auto_fire` (hold vs. click-per-shot), `attack_windup` (wind-up delay for weight), and `attack_speed` — the per-shot cooldown in seconds, where **lower = faster** (`0.1` is 10 shots/sec; the pistol is `0.44`).
- **Per-shot stamina — DERIVED, not authored.** Firing costs stamina, and the price comes out of the weapon's own stats: **`WeaponData.stamina_effort()`** = `damage × √pellet_count` plus, for an exploding round, a flat blast payload scaled by radius. It is normalised so a plain `1.0`-damage single-projectile round scores exactly `1.0`, which makes `GameSettings.player_movement` → **Stamina** → `stamina_shot_cost` (`1.8`) read as *"what one baseline shot costs"*. Shipped efforts: SMG `0.88`, pistol `1.00`, sniper `1.25`, shotgun `4.00`, grenade launcher `8.00` — so **the launcher costs 8× a pistol shot and 2× a shell without anyone hand-pricing it**, and a new weapon gets a sane price the moment you author its damage. Pellets count as `√n` because one trigger pull is one recoil impulse and the pellets diverge over `pellet_spread`.
  - **`projectile_explodes`** (default OFF) — tick it when this weapon's round really does blast, so the payload is charged for. It is a *pricing fact only*: whether a round explodes is decided inside its `projectile_scene` (`rock_projectile.tscn` wires its `Explosion` node to the full blast path, `Projectile.tscn` to a cosmetic spark that hardcodes force `0`). It has to exist because **nothing else on WeaponData can tell an explosive apart** — `explosion_radius` defaults to `4.0` on every weapon and `max_explosion_force` to `20.0`, so the *pistol* nominally out-blasts the launcher's authored `10.0`. **`rock_weapon.tres` is the grenade launcher** (its `view_model` is `grenade_launcher.tscn`, its caliber `grenades`) — the filename is legacy, and it is the one weapon that ticks this.
  - **`stamina_cost_mult`** (default `1.0`) is a **trim on the derived price, not the price**. Use it only for something the per-shot formula structurally cannot see, and say why on the `.tres`. Exactly one weapon needs it: `smg.tres` authors `0.75`. Effort is per-*shot*, but what a player feels on a held trigger is per-*second*, and at 8 shots/sec the SMG multiplies its cost harder than anything else on the roster — at `1.0` it would drain `12.7/sec` (74% of the `17.1/sec` clamp) while firing the **weakest round in the game**, which reads as a punishment for picking the light weapon. The trim buys back that cadence asymmetry. Reach for a damage or cadence change first; a trim far from `1.0` means the formula and your intent have diverged. `0` makes the weapon's fire free (that is what `spray_paint.tres` authors). **Melee ignores both** — a swing is priced by `stamina_melee_attack_cost`, and unlike a shot it is REFUSED on an empty pool (firing never is, so an exhausted player always has *something*).
  - **The ceiling is structural.** Cost is clamped to `stamina_shot_drain_ceiling × stamina_sprint_drain × attack_speed`, so no weapon you can author ever drains more than `0.95 × 18.0 = 17.1/sec` on a held trigger — "shooting never costs more per second than running" is a theorem, not a habit. But a weapon that *hits* the clamp gets silently **cheaper** as it grows more powerful, so `tests/test_combat_data.gd` fails if any shipped weapon is railed against it.
  - **A shot holds off recovery for `stamina_regen_delay_after_shot` (`1.5 s`), NOT the `0.35 s` movement delay** — and that knob, not the cost, is what decides whether shooting can deplete you at all. Every spend re-floors its hold; if a weapon's cadence is *slower* than the hold, it regenerates between its own shots and pays for itself however much a round costs. That was a real bug: at the movement delay the pistol earned `24.0 × (0.44 − 0.35) = 2.16` standing still against a `1.80` cost, so emptying the pool with it was **impossible**, and the shotgun refunded `19.2` at the same idle rate against a `7.2` cost. At `1.5 s` the hold outlasts every cadence on the roster (the slowest is the shotgun's `1.4 s`), so sustained fire is pure drain and the magazine sizes are the real budget — continuous fire empties a full pool in ~6 s with the launcher, ~11 s with the SMG, ~19-30 s with the shotgun, pistol and sniper. ⭐ **`attack_speed` is only the cooldown — the real gap is the RELOAD whenever a shot empties the magazine**, and `Attack._shot_regen_hold()` takes the larger of the two so the rule holds for any weapon you author. That distinction is not academic: `sniper_wep.tres` cycles every `0.668 s` on paper, but `max_ammo 1` + `auto_reload` means every shot is really followed by `auto_reload_delay + reload_time = 3.5 s`. Under a flat hold it handed back `24.0 × 2.0 = 48` against a `2.25` shot — the pool *climbed* while you fired — so its shots now hold `3.5 s`. `tests/test_combat_data.gd` checks both the mid-clip and the clip-emptying shot of every weapon, and asserts each nets a real drain standing still. Note the movement delay is deliberately left short, because raising it is felt hardest by bunnyhopping, where a chain of jumps re-arms it on every launch.
- **Ammo & Reload** — `max_ammo` (clip size), `is_infinite_ammo` (set `true` for melee/fists — the clip never depletes), `caliber`, `auto_reload`, `reload_time`. (Caliber is covered below.)
- **Projectile** — assign a `projectile_scene` (a Bullet scene, e.g. `res://scenes/projectiles/Projectile.tscn`) for a travelling round; leave it unset for pure hitscan. Then tune `projectile_speed`, `projectile_life_time`, `bullet_gravity_scale` (`0` = flat laser, `1` = grenade arc), `launch_angle`, and `has_tracer`.
  - **GOTCHA — a projectile scene MUST scan physics layer 1, or it flies through the level.** The map's brush geometry (func_godot `worldspawn` / `func_geo` / `func_detail`, see `addons/func_godot/fgd/*.tres`) is authored **`collision_layer = 1`, `collision_mask = 0`** — one `StaticBody3D` for the whole world that **scans nothing** and relies entirely on whatever hits it to scan layer 1. Characters (`Player.tscn`, `enemy.tscn`) are `collision_layer = 2`. So a projectile root needs **`collision_layer = 0`, `collision_mask = 3`** — the setting on `Projectile.tscn` and `sphere_projectile.tscn`. Mask out layer 1 and the round silently passes through every wall, floor and ceiling, then dies on its `life_time` timeout — a path that deliberately does **not** emit `queued_for_deletion`, so `explosion.gd`'s bridge never fires and no blast, decal or impact sound ever happens. It still detonates on people (layer 2), which makes the symptom read as "it only explodes on NPCs". `rock_projectile.tscn` shipped `collision_mask = 2` and had exactly that bug; `tests/test_rocket_world_impact.gd` now flies a real round into a worldspawn-shaped slab and pins it.
- **Explosion / Knockback** — `max_explosion_force` + `explosion_radius` + `explosion_damage` for blast rounds (`explosion_damage` = `-1` uses the global `PhysicsDamageSettings.explosion_damage`; author a value for a hard-hitting rocket vs a shove-only grenade — force/radius are already per-weapon); `self_knockback` (recoil shove on the shooter — go *negative* for a melee lunge, like the knife's `-2.5`), `enemy_knockback`, `enemy_lift`.
- **View Model & cosmetics** — `view_model` is the first-person weapon scene the gun rig instantiates on equip (the SMG points at `ak_472.tscn`, the pistol at `silenced.tscn`); unset = the rig's built-in placeholder shows. **Never clear it to mean "no weapon"** — that placeholder is a silenced pistol, so an unset field hands the player a gun. Then `view_model_is_first_person_only` (below), `has_muzzle_flash`, `has_laser_sight`, `spawns_casing`, `casing_size_scale`, `muzzle_smoke_scale` (how big a barrel-smoke trail this gun leaves: 1.0 = the authored wisp, >1 = a big-bore belch, 0 = never smokes; only read when `has_muzzle_flash` is on), and the **Audio** streams (`audio`, `whiz_sound`, `impact_sound`, `impact_enemy_sound`, `reload_sound`).
- **`view_model_punch`** (default OFF) — this weapon's swing is a **punch**, not a shot. Three effects: in `GunMesh.fire()`, the whole view model kicks **forward** (`GameSettings.effects` → **View-Model Kick** → `punch_kick_*`) instead of recoiling back into you, and the mounted view-model root is asked to play its own `strike()` if it has one; and in `Attack`, the full-screen white **hitscan hit-flash is suppressed** (visibility only — the 85 ms combat beat still runs) so every swing doesn't strobe the screen. **`fists.tres` is the only weapon that sets it.** Guns must leave it off — a forward-kicking rifle reads as a shove. See *Authoring the punch* below.
- **`view_model_is_first_person_only`** (default OFF) — set it ON when this weapon has **no `view_model` at all** because the player's own body draws it. **`fists.tres` is the one weapon that uses it**: unarmed mounts nothing, and the bare fists are the Player's first-person arms rig (the same hands as carrying a prop), which lives under the *camera* rather than the gun rig. The flag suppresses the swapper's "you forgot a model" warning — having none is the point — and makes **`held_view_model()`** return null so an NPC hand, a ground drop and an inventory tile show nothing. Non-player consumers read `held_view_model()`, never `view_model`. Leave it OFF for every real weapon. `tests/test_fists_view_model.gd` pins both directions.
- **Feedback / ADS / Scoped-Attack Launch / Spray Paint** — `screen_shake_amount`, `hit_flash_opacity` (strength of the full-screen white hitscan hit-flash for this weapon: `1.0` = full white, and the knife authors `0.5` so its fast repeat swings pop softly instead of strobing — cosmetic only, the 85 ms combat beat still runs), `hitstop_duration` (and `hitstop_recovery`); `no_ads` (true for fists), `scoped_fov_override` (an **absolute** angle, unlike the global `scope_magnification` — a scope is a fixed optic, so a sniper's zoom belongs to the weapon and must not drift with the player's FOV setting; clamped to 1–179°, so anything under 1° is the same ~75× scope), `hip_sway_mult`; `launch_on_scoped_attack` (the knife's ADS-dash, with `launch_force` / `launch_upward`); and `is_spray_paint` + `paint_colors` for the graffiti gun (mousewheel while aiming cycles `paint_colors`, right-click opens an HSV picker; its blob tags surfaces with a coloured decal — but a prop carrying a **`SprayPaintable`** component recolours its whole coat instead, e.g. spray the dog any colour, see the component catalogue below).

**Authoring the punch (unarmed).** Unarmed has **no view model at all**. The bare fists are the Player's OWN first-person arms rig — the same hands you see when carrying a prop (`FirstPersonBody._build_first_person_arms`, on the Player's **FirstPersonBody** child in the same scene), which lives under the *camera*, not under the gun rig. That is deliberate, and it is what keeps the fists on the character's arm colour, centred on the camera instead of offset to the gun's side, and out of the gun's 45-degree holster park. Do **not** re-introduce a second arms rig as a `view_model` — all three of those break again.

| What | Where |
| --- | --- |
| Which weapons punch | `WeaponData.view_model_punch` (only `fists.tres`) |
| Whether the fists show, and how they swing | the `fp_arm_*` exports on the Player's **FirstPersonBody** child (`scenes/player/Player.tscn`) |
| The whole-rig kick for a weapon that DOES mount a model | `GameSettings.effects` → **View-Model Kick** |

**Two-fisted input.** Left click throws the **left** fist, right click the **right**. The second button is `MouseInput.alt_attack_action` (default `Zoom`, i.e. right click), and it is free precisely when it matters: a punching weapon sets `no_ads`, so `ScopeIn` already refuses to scope with it out. `Attack._on_mouse_input_attack` takes it only when the weapon sets `view_model_punch`, so **right click stays ADS for every gun**. It routes through the identical fire gates as left click (dialogue, carry-lock, holster, cooldown), so a punch off either button costs the same `attack_speed` and deals the same damage. `Attack.last_attack_alt` banks which button got through, and the Player reads it to pick the hand — `fp_arm_punch_alternate` is therefore OFF by default, since the mouse decides.

The punch knobs sit beside the existing carry-hand ones: `fp_arm_unarmed` (show fists at all), `fp_arm_unarmed_nudge` / `fp_arm_unarmed_tilt_deg` / `fp_arm_unarmed_scale_mult` / `fp_arm_unarmed_spread` and the `fp_arm_unarmed_bob_*` / `fp_arm_unarmed_breath_*` motion knobs (the guard framing & motion — see below), `fp_arm_punch_pitch`, `fp_arm_punch_duration`, `fp_arm_punch_thrust`, `fp_arm_punch_alternate`, `fp_arm_punch_offhand`, `fp_arm_punch_curve`. They are stamped onto the rig when it is built, so **tune them on the `FirstPersonBody` node in `Player.tscn`, never on `body_model_swap.gd`** — those script defaults are what every *NPC* punch uses, and editing them changes every NPC in the game.

**`fp_arm_unarmed_nudge`** frames the fists as a **raised guard**. The rig's rest offset (`fp_arm_offset`) is tuned for the *carry* hold — hands low and forward, reaching toward a floating prop — which parks bare fists at the bottom of the frame. **The guard's geometry is counter-intuitive — it was tuned by rendering it, not by formula.** The arm model is a straight, rigid limb: leave it near-flat and "raise it into frame" and you get fully extended arms whose fist tips converge at a far point near screen centre — it reads as *reaching into the distance*, no matter how near the rig sits. What reads as *fists up close* is **foreshortening**: the shoulders **drop** below the carry rest (`fp_arm_unarmed_nudge`, default `(0, -0.13, 0.12)` — note the **negative Y**) while **`fp_arm_unarmed_tilt_deg`** (default `45`, the load-bearing knob) swings the arms steeply up, so the fists rise knuckles-first into the lower third, big and near, flanking the crosshair with your aim always visible in the gap. Shallow tilts (~10°) regress to the reaching look. **`fp_arm_unarmed_scale_mult`** (default `1.15`) is a final size boost on top, and **`fp_arm_unarmed_spread`** (default `0.28`, vs the carry hold's `fp_arm_spread` `0.2`) widens the pair so the two fists read distinct. The nudge stays *relative* to the carry rest on purpose. The draw/stow slide and the carry→fists handoff each ease to the right rest/tilt/scale/spread automatically. **Re-tuning any of this? Drag it live in the Inspector.** The guard pose tracks its exports every frame while the fists are up, so: play the scene, switch the editor's Scene panel to the **Remote** tab, select the running Player's **FirstPersonBody** child, and drag `fp_arm_unarmed_nudge` / `fp_arm_unarmed_tilt_deg` / `fp_arm_unarmed_scale_mult` / `fp_arm_unarmed_spread` — the fists follow as you drag (the range hints give the numeric knobs real sliders; the per-frame export tracking moved with the code, so live-tunability survived the extraction). Remote edits don't persist: note the values you like and set them on the FirstPersonBody node in `Player.tscn`. For out-of-game side-by-side stills there is also `scripts/tools/preview_fists_frame.gd` (CLI, windowed — add candidate rows to its `CONFIGS`, eyeball the PNGs; its baseline row renders the authored pose read straight off `Player.tscn` / the script defaults at run time, so it never drifts from the shipped guard).

**First-person body (legs + torso + arms).** Looking down shows your own body: the `FirstPersonLegs` rig (built in `FirstPersonBody._build_first_person_legs`, rendered with real world depth — not on the gun layer) carries the walking legs, **your torso** and **your arms**. The torso is resolved from your character-creation appearance through the same catalog slice the customizer uses — chosen body model, **your drawn shirt** (planar-projected, untinted, exactly like the portrait), else the skin tint — but **head-less**: never a head (it sits exactly where the camera is), and a `whole_body` appearance skips the torso entirely (a one-piece model can't drop its head). The torso wears the catalog rotation **+180° yaw** (body options are authored facing an NPC's `+Z`; the player faces `-Z`). It is **hidden until you look down at it** and eases in across `fp_body_reveal_start_deg` (default `50°` below the horizon) to fully visible at `fp_body_reveal_full_deg` (default `70°`), where it rests at `fp_torso_transparency` (default `0` = solid; raise it for a permanent ghost). See the reveal bullet below for why that gate is on the LOOK and on nothing else. All see-through draws as a **dithered screen-door** (`BodyModelSwap.body_transparency`, alpha-hash: depth-writes stay on, nothing re-sorts, and the stipple suits the PS1 look — the Mario-Odyssey treatment), drawn shirts included (the planar shirt shader carries its own `see_through` dither uniform; death gibs strip the see-through so your flung torso lands solid). The chest also carries the rig's gentle breathing pulse, and the legs ride the same reveal gate (`BodyModelSwap.leg_transparency`). **Crouching fades it fully out** (and back in on stand), riding the eased `crouch_t` — crouched, your chest would fill the whole lowered view — and the torso also sinks with the head's live drop during the transition. Knobs on the Player's **FirstPersonBody** child: `first_person_torso` (on/off), `fp_torso_offset` (FP-specific nudge added to the catalog body's authored position — LIVE-tunable in the Remote inspector; tune it **standing** so the shoulder line sits below the camera) and `fp_torso_transparency`. Framing was set with the render-probe workflow (see the fists section); the shipped default was probe-verified at straight-down, half-down and level pitch.

**Your own arms, on your own body.** `first_person_body_arms` (default **ON**) hangs the mirrored arm pair off that same rig, so looking down shows arms attached to your chest — body awareness, and **a completely different rig from the view-model hands** above: those live under the *camera* on the gun's render layer and are the carry hold / the bare fists, while these sit at real world depth and are just your arms. **The mount is inherited, not authored:** `arm_model` / `arm_scale` / `arm_position` / `arm_rotation` are read straight off the appearance catalog — the exact rows `CharacterAppearanceCatalog.configure_swap` stamps onto every NPC — which is what makes them *the same arms everyone else has* by construction instead of by a copied number that rots. So **tune the mount in `resources/characters/PlayerAppearanceCatalog.tres`** (it moves the whole cast, which is correct) and use **`fp_body_arm_offset`** (the `fp_torso_offset` idiom, zero by default, Remote-inspector live) for anything first-person-specific. The arm **colour** still comes from your customizer choice, like the legs'. A `whole_body` look mounts nothing — that model already has arms.

**Only one pair of arms is ever on screen.** `fp_body_arms_hide_when_drawn` (default **ON**) dissolves the body arms whenever the view-model rig owns your hands, on the same dithered screen-door as the torso (`fp_body_arms_hide_fade` paces it, defaulted to read alongside the weapon's own ~0.35 s holster swing rather than racing it). Two distinct reasons, and the second is not covered by the first: a **drawn weapon** (`not attack.holstered` — the gun or the raised fists *are* what your arms are doing, and that mesh lives on the gun rig where this component can't see it), and a **carried prop** (the view-model hands are visibly holding it — and carrying *force-holsters* the weapon, so a holster-only gate would leave your real arms hanging at your sides while your other hands carry a crate). The gate reads the view-model rig's live `visible`, not a latch, which is what gives the sequencing: the view-model hands finish sinking out of frame *before* your real arms fade back in.

Three things the rig is deliberately configured *against*, all worth knowing before you touch `_configure_fp_body_arms`:

- **All three mode pitches are zeroed.** `BodyModelSwap` swings arms to `arm_hold_pitch` when its host reports a drawn weapon, to `arm_fists_pitch` when it reports fists out, and to **`arm_air_pitch` (default `-160°`, both arms straight overhead — the NPC roller-coaster flail) whenever the host is airborne**. The Player answers `is_on_floor()`, so leaving that default live throws **your own arms over your face on every jump**. The two weapon pitches are inert only because the Player happens not to implement `is_holding_gun` / `is_fists_out` — they are zeroed anyway, so adding either later can't swing your body arms forward through the view model you are already holding. What survives is exactly what should: the antisymmetric walk-swing (**`fp_body_arm_swing_deg`**, default `35°` = NPC parity), at a cadence the legs rig already matches to your real speed.
- **⭐⭐The cast does not fit under this camera, so the rig is SCALED, not re-stacked (`fp_body_scale`, default `0.60`).** An NPC's body measures **1.226 m** from soles to the top of its chest; the player's eye sits **1.0 m** above the floor (`Player.tscn` authors `Head` at y ≈ `0.014`, i.e. on the player origin, and the capsule bottom is exactly `-1.0`). **1.226 does not fit in 1.0 at any mount height** — push the feet down onto the floor and the chest closes over the lens, drop the chest clear of the lens and the feet go through the floor. This is the trap the two earlier passes both fell into by moving a *single* offset: the 2026-08-14 floor fix raised `fp_leg_offset` by `0.55` to get the feet out of the ground and paid it back through `fp_torso_offset` (`-0.65`) and `fp_body_arm_offset` (`-0.55`) so the chest and shoulders "wouldn't move" — which preserved the two parts that were fine and displaced the one part that was the whole point, leaving the **hips mounted 0.19 m above the top of the chest**. That is what "my legs are drawn on top of my body" (2026-08-15) was: not a draw-order or transparency fault at all, but a body assembled in the wrong order, with the z-buffer faithfully drawing what it was given. **A uniform scale cannot reorder anything**, so the catalog's own part-to-part layout survives by construction rather than by three numbers agreeing with each other. `fp_torso_offset`, `fp_body_arm_offset` and `fp_body_arm_scale_mult` are therefore all back to **neutral** (`0`, `0`, `1.0`) — reach for them only for a genuinely FP-specific framing need, never to fix a fit. **`fp_leg_offset` is DERIVED from the scale**, not tuned: `-1.0 + 0.984 × fp_body_scale + clearance` (`-0.39` at `0.60`, ~2 cm clear) — retune one and you owe the other. `tests/test_fp_body_arms.gd` pins all three questions separately: no limb below the floor, the **hip below the chest's top**, and the mount tracking the scale.
- **The arms take the torso's sink AND its fade.** They hang off the chest, so `_update_fp_torso` writes them the same crouch drop and the same `see` value it writes the torso — otherwise the crouch hide (and the deep look-down dissolve) deletes your chest and leaves **two arms floating under the camera**, which looks worse than either extreme. That needed a new **`BodyModelSwap.arm_transparency`**: an exact sibling of `body_transparency` (same alpha-hash screen-door, same per-instance duplicates, same zero-cost early-out), default `0`, so no NPC rig changes. (The crouch sink is measured in *player* metres but written as a *rig-local* offset, so it is divided back out by `fp_body_scale` — miss that and the chest follows the camera down by only 60% of the drop and creeps up into the lowered view.)
- **⭐⭐A basis write to this rig owes `fp_body_scale` — that is how the scale went missing for a day.** `Basis` holds rotation *and* scale in the same three columns, so `transform.basis = Basis()` does not mean "no rotation", it means "no rotation, **and scale 1**". `update_leg_wall_pose()` is called unconditionally from `Player._physics_process` and takes its resting branch on every grounded frame, so a scale-less write there reset the whole body to full NPC size 60 times a second: feet 0.37 m through the floor and the chest **45.6° below the horizon — inside a 120° FOV frustum while standing still and looking straight ahead**, which is what "I can see my body without looking down" was. Every basis write now routes through `_fp_legs_basis()`. **Nothing in this project could catch it**: the frame probe and every geometry test build their *own* rig and set the scale themselves, so all of them measured a rig that call had never touched — `tests/test_fp_body_arms.gd::test_the_wall_pose_never_wipes_the_body_scale` drives the real call instead.
- **⭐⭐VISIBILITY IS ONE RULE: the body is hidden until you LOOK DOWN at it** (`fp_body_reveal_start_deg` `50°` → `fp_body_reveal_full_deg` `70°`, easing in across the band, applied to torso, arms *and* legs so they can never disagree). It reads the head pitch and nothing else. **The rule used to be the other way up** — solid by default, dissolving only once you buried your look — and that is correct only if the body is off-screen whenever you are *not* looking at it. It is not: your eyes are 1.0 m off the floor, the chest tops out 0.245 m below them, and at a wide FOV it sits barely outside the frustum edge at level pitch. Then four things drop the **lens** toward a body that has not moved — the **landing dip** (up to 1.0 m; an ordinary jump lands ~0.30 m), the **stair step-smoothing** (up to 0.7 m, firing on any auto-step over 1.5 cm so running across brush seams accumulates it), the **crouch** (0.61 m) and the **walk-bob** (0.075 m at a full run, hard-capped). Two rounds went into chasing those with position sinks and metre-sized dissolve bands, and the player still saw their own chest while running, crouching and climbing stairs; the band could not even be sized safely, because the drop at which the chest enters frame is `-top - front × tan(fov/2)` and so **shrinks with the player's FOV setting** (0.189 m at the default 75, 0.094 m at the 120 maximum, against a bob floor of 0.075). **A gate on the LOOK cannot be defeated by anything that moves the camera** — no threshold to size, no FOV to track, no fifth offset to forget. This is also why the **legs** got `BodyModelSwap.leg_transparency`: they had no fade channel at all, so whatever the torso did, a pair of thighs stayed on screen.
- **⭐Your body wears the actor RIM, and that is what keeps the world's ink OFF it** (`first_person_body_outline`, default **ON**; `fp_body_outline_color` black, `fp_body_outline_width` `2.0` = NPC parity). Your legs/torso/arms are an actor at real world depth, so `InkOutline`'s screen-space edge detect finds their silhouette exactly like a wall's — until 2026-08-15 they were the one actor in the game outside that contract, wearing the **world's** line while every NPC beside them wore a hull rim. The switch is not "outline on/off": it sets `BodyModelSwap.actor_outline`, which stamps the inverted hull **and** registers the meshes with `InkOutline.ACTOR_INK_MASK_LAYER` in one operation, because a hull with no mask draws *both* lines and a mask with no hull draws *none*. It lives on the rig (not on a walk in `FirstPersonBody`) because `BodyModelSwap` re-instances its parts on any appearance swap and **resets their render layers** — a stamp applied from outside is silently lost the next time you change clothes. The rim's alpha is driven from `body_transparency` / `arm_transparency` per part, so a dissolving chest takes its outline with it instead of leaving a solid black silhouette of you hanging in the air.

For stills, `scripts/tools/preview_fp_body_frame.gd` (CLI, windowed — the sibling of the fists probe) renders the body at a **sweep of look-down pitches**, which is the framing question that matters here: these parts sit at real depth *around* the camera, so most of them are only in frame once you look down, and a pose that reads fine head-on can be invisible or clipping at 70°. Rows carry a pitch plus optional pose overrides; all-null rows render the shipped body. Its numbers are read as text off `Player.tscn`, the catalog and `user://settings.cfg` at run time, so nothing is mirrored.

**Read its numeric half first.** Alongside each render it prints a **per-limb extents report** — the vertical span and forward reach of the torso, each arm and each leg, against the floor plane it locates from the player's own capsule — and draws that floor in the render so a limb through the ground is visible rather than left to the eye. "The limbs clip into the floor" is a measurement, not an opinion, and eyeballing one pitch cannot tell you *by how much*. Extents are taken at the REST pose (`animate_arms`/`animate_legs` off), which is the worst case for depth: both the walk swing and the arm stride rotate a limb about its mount, which raises the far end.

**⭐It prints a STACK line too, and that half exists because clearance alone endorsed a broken rig for a day.** Clearance is a *one-sided* measurement — it only ever looks down — so a part mounted too **high** passes it silently, and so does the part mounted too **low** underneath it. That is precisely how the legs came to sit on top of the chest with every number in the report reading `OK`. The STACK line compares the leg's top (the hip it pivots on) against the torso's span and says so in words. **Caveat:** the torso renders in a flat stand-in skin tone in that harness — `torso.tscn`'s material wants autoloads that a `-s` tool run doesn't have — so use it to judge *placement, reach and stacking*, and judge colour and shading in-game. The probe also builds the rig with its real **actor rim**, which is deliberate: `--headless` never compiles a shader, so a broken `outline.gdshader` passes every test in this project and ships dead (it has, twice). If the rim is missing from the PNG, the shader is broken.

**`fp_arm_unarmed_bob_pos` / `fp_arm_unarmed_bob_roll_deg`** (defaults `0.007` m / `0.6°` — a touch more travel than `GunPose.walk_bob_pos`'s `0.004`, since bare hands swing more than a braced gun) give the fists the same **footstep walk-bob** every mounted weapon gets. The rig is a child of the camera, so it inherits the head-bob and would read glued to the screen without its own counter-motion — the exact reason `GunPose` exists for guns. The bob keeps the gun's climbing-counts-as-walking rule and the **View Bobbing** accessibility toggle, and it fades out while carrying a prop (the carry hold stays planted on the held object). **Where it goes beyond `GunPose`: the fists answer to how fast AND which way you are moving.** Both channels hang off one *speed ratio* — your horizontal speed as a fraction of the run tier (`PlayerMovementSettings` → `max_speed`), so a walk sits at `walk_speed_mult` of it, a crouch-creep lower, and a bhop-boosted sprint runs past `1`. **`fp_arm_unarmed_bob_speed_gain`** (default `0.7`) scales the **cadence**: the phase rate is `bob_speed` × the ratio, blended by the gain, so a walk pumps at ~`0.99 s`/cycle against a run's `0.79` and a bhop sprint's `0.55`. `GunPose`'s rate is flat, and amplitude alone only ever changed the *size* of the pump — a walk and a sprint traced the same figure-eight at the same footstep rate, which reads as one gait at two volumes. `0` restores that flat rate exactly, and the rate is clamped in proportion to the gain so no boost stack can strobe the arms. **`fp_arm_unarmed_lean_mult`** (default `(0.6, 0.4)`) adds the **direction** read: the pair leans *against* the body's velocity — strafe right and the fists drift left, run forward and they trail back toward the lens, backpedal and they press away from it. That is inertia, the same read `HudSway.velocity_target` gives the corner HUD. It is a **multiple of `fp_arm_unarmed_bob_pos`**, not absolute metres (the `fp_arm_unarmed_nudge` idiom — see the depth-coupling note below), it is measured in the *body's* yaw frame so looking at your feet does not cancel the forward term, and it tops out at the run tier: a boost buys cadence, never more reach. At the authored guard that is ~`0.076 m` of sideways drift at a full strafe (~30 px). `0` is direction-blind. It is written onto the rig's `FirstPersonArmsBobMount` parent, never the rig itself, so it can never fight the draw/stow tweens. The hands wear the **weapon look**: the same `GunVisuals` dress pass every view model gets (warm rim light + black inverted-hull outline, shadows off) is stamped onto the arms rig at build — carry hold and guard alike — as a code-built `FistVisuals` child; tune its rim/outline live on the Remote tree. **`fp_arm_unarmed_stride_deg`** (default `7°`) makes the walk **asymmetric**: the fists ALTERNATE — left rises as right falls, one full alternation per two footfalls — on top of the whole-rig bob, scaling with speed and parking at zero for the carry hold (hands planted on the prop) and mid-punch (the strike stays authoritative). **`fp_arm_unarmed_breath_pos` / `_deg` / `_speed`** (defaults `0.006` m / `1°` / `1.6`) are the **idle half**: standing still, the fists rise and settle with the breath and wander slightly sideways (a quarter-strength drift at an offset frequency, so it never reads metronomic), crossfading with the walk-bob as you start/stop moving. Like the gun's breathing, it runs even with View Bobbing off — micro-motion, not travel. **`fp_arm_unarmed_bob_fade`** (default `8`) paces both blends: draw/stow/carry fade-in-out AND the walk↔idle crossfade — higher = snappier.

**Two invariants keep the walk-bob from jittering, and both are pinned in `tests/test_fists_view_model.gd`.** (1) The bob **PHASE** (`_fp_bob_time`) only ever *advances*, and is wrapped to `TAU * 2` — the period of the half-rate bob/roll/stride terms. It must **never** be eased toward zero: a phase grows without bound while you walk (~240 rad after 30 s), so lerping it moves it *tens of radians* in one frame — whole bob cycles. Settling to centre is the amplitude's job, not the phase's. (2) The **AMPLITUDE** (`_fp_bob_amp`) is eased, never taken straight from the grounded-and-moving gate, because `is_on_floor()` blips false for single frames while you are genuinely walking (brush seams, the 0.5 m stair risers, any bump) and horizontal speed dips under `footstep_min_horizontal_speed` between strides. Together those two were the 2026-08-08 "the fists vibrate when walking" bug: each blip snapped the arm-pump by a full `fp_arm_unarmed_stride_deg` **and** teleported the phase, measured at a **6.3° one-frame stride step = 0.32 m of fist travel**; the fix brings the worst single-frame step to `0.42°` = `0.021 m`, i.e. the ordinary walk cadence. The whole-rig bob hid it — it is lerped onto the mount, so it only ever moved 15% of a step — while the stride was written raw; **the stride is now smoothed on the same constant as the mount**, and should stay that way: it drives a lever, so degrees there are decimetres of fist on screen.

**`fp_arm_punch_curve`** (`resources/tuning/punch_strike_curve.tres`) is the shape. **x is ELAPSED fraction** (0 = the swing's start, 1 = settled), **y is amplitude**, so one curve re-times itself when you change the duration. y may go **below 0 for anticipation** (the fist pulls back first) and **above 1 for overshoot**. Null gives the legacy NPC envelope — full amplitude on frame one, then ease out, i.e. a follow-through with no wind-up.

**The curve must actually reach ~1, and the throw must dominate the wind-up.** Amplitude is a *multiplier* on `fp_arm_punch_thrust` and `fp_arm_punch_pitch`, so a curve that peaks at a fraction of 1 makes the punch look like nothing — and the natural reaction is to crank those knobs, which scales the **negative** lobes by the same factor. That is exactly how the 2026-08-08 "the fists vibrate when punching" bug happened: the curve had drifted to a peak of `+0.064` with two dips to `-0.22`/`-0.16`, `fp_arm_punch_thrust.z` had been pushed to `-5` m to compensate, and the result was a **1.42 m** back-forward-back sweep that yanked the fists clean out of frame twice per swing. Fixed by re-authoring the curve to the documented shape (`-0.12` anticipation → `1.0` snap → settle to `0`) and rescaling the thrust/pitch by the old peak so the punch's *maximum extension is unchanged*. `tests/test_body_model_swap_strike.gd` now pins peak > `0.8` and `|dip| < peak/2`. If a punch reads wrong, look at the curve **before** the thrust.

Two rules worth keeping. **`fp_arm_punch_duration` must stay under the weapon's `attack_speed`** (fists: 1.2 s), or spamming attack restarts the swing before it completes. And **keep the reach of `fp_arm_punch_thrust` proportionate to the guard's rig depth** (`fp_arm_offset.z + fp_arm_unarmed_nudge.z`) — the thrust extends *away* from the lens, but the swing also pitches the arm, and an over-deep lunge can swing arm geometry through the near clip plane.

**Every motion knob on this rig is depth-coupled, so re-pose and re-tune together.** `fp_arm_unarmed_nudge` / `_tilt_deg` / `_scale_mult` decide how far from the lens the fists sit and how long the arm reads; the *travel* knobs (`fp_arm_unarmed_bob_pos`, `_stride_deg`, `fp_arm_punch_thrust`) are plain metres and degrees that get amplified by that geometry. The currently authored guard puts the shoulder ~1.95 m **behind** the lens with a ~2.9 m arm and the fists ~1.0 m in front — at 90° FOV that is roughly **396 px per metre**, so `0.1 m` of bob is ~40 px of screen sway and a 7° stride swings the fist ~0.35 m. After any guard retune, re-check the travel knobs by eye or with the frame probe rather than trusting numbers that were tuned at a different depth.

**NPC hand-hold (`WeaponData` "NPC Hand-Hold" group).** An NPC hangs the weapon's `view_model` off its hand anchor and, by default, only corrects yaw with the per-NPC `weapon_mesh_rotation` (guns are authored at an identity root, so their `+X` barrel maps cleanly onto the NPC's `+Z` forward). A view-model whose **root bakes a first-person-only pose** breaks that: the knife's `knife.tscn` root carries FP scale `1.585`, a Z-tilt, and a forward offset tuned for the *player's* gun camera, so an NPC inherited that scale + offset and the knife floated off-hand, oversized. Set **`npc_hold_override = true`** and the NPC mount discards the baked FP root transform and places the model fresh from **`npc_hold_position`** / **`npc_hold_rotation`** (Euler °) / **`npc_hold_scale`** — so one scene reads right in first person (its baked root) *and* in an NPC's hand (these). The knife uses `(0, 90, 0)` — `+90°` Y, the *reverse* of a gun's `-90°`, because its blade points `-X` (a gun's barrel points `+X`), so this faces the blade toward the NPC's `+Z` forward. Leave the override **off** for identity-root guns; they already hold correctly. (Nudge `npc_hold_position`/`_scale` in the Inspector to taste — zero position sits the model exactly where a gun would.) Separately, **`npc_held_display_scale`** (default `1.75`) is a *readability boost* multiplied onto a **gun's** held-out mesh (override weapons are exempt — their authored `npc_hold_scale` IS the final held size): view-models are first-person-tuned, and at NPC viewing distance that world size reads squint-small — the player couldn't tell what an enemy was holding. It is display-only (the FP view-model, ground drops, inventory icons, and the inspect preview never read it); tune per weapon in the Inspector — a long rifle wants less boost than a pocket pistol (at `1.75` the sniper's muzzle sits ~1.6 m from the hand, which can poke through thin cover — try ~`1.2` there), and `1.0` = no boost.
### Recoil & bloom (per-weapon kick and spread-under-fire)

The **Recoil & Bloom** group on `WeaponData` gives a weapon a felt kick and lets sustained fire walk the aim wider. **Every field defaults to `0`, which is fully inert** — an unconfigured weapon behaves exactly as before, so this is a knob you opt a weapon *into*. Only the **PLAYER** reacts to these (they drive the player's AimSway); NPCs never read them, so raising them never changes enemy accuracy.

Recoil is a transient *kick* that recovers; bloom is accumulated *spread* that recovers:

- **`recoil_kick_deg`** (float) — degrees the aim kicks UP per shot (the muzzle climbs), recovered over time. Default `0.0` (no recoil).
- **`recoil_horizontal_deg`** (float) — max degrees of RANDOM horizontal kick per shot (the gun also wanders sideways). Default `0.0` = purely vertical climb.
- **`recoil_recovery`** (float) — how fast the kick returns to centre, per second; higher = snappier. Default `8.0` (only bites once recoil is set).
- **`bloom_per_shot_deg`** (float) — extra spread added to the aim wander per shot; sustained fire blooms wider. Default `0.0` (no bloom).
- **`bloom_max_deg`** (float) — cap on accumulated bloom (degrees); sustained fire can't widen past this. Default `0.0` (no bloom).
- **`bloom_recovery`** (float) — how fast bloom tightens back to zero when not firing, per second; higher = recovers faster. Default `6.0`.

**Worked example — a punchy full-auto rifle.** On your `ar15.tres`, set `recoil_kick_deg = 0.6`, `recoil_horizontal_deg = 0.25`, `recoil_recovery = 7.0`, then `bloom_per_shot_deg = 0.4`, `bloom_max_deg = 4.0`, `bloom_recovery = 8.0`. Now the first shots are crisp, the muzzle climbs and drifts as you hold the trigger, and the cone opens up — forcing burst-fire — then tightens back when you let go. Set `hip_sway_mult` high (ADS / Scope group) on top if you want the bloom to bite far harder from the hip than down the scope.

### On-hit status effect (poison / burn / slow guns)

The **On-Hit Effect** group lets a weapon apply a `StatusEffect` to any character it hits — a poison dart gun, a flamethrower that burns, an SMG that slows. It's **inert by default**: `on_hit_effect` is `null`, so an unconfigured weapon applies nothing.

- **`on_hit_effect`** (StatusEffect) — the effect resource applied to a character this weapon hits (poison / burn / slow / …). Drop a `StatusEffect` `.tres` here. Default `null` = no on-hit effect.
- **`on_hit_chance`** (float, `@export_range 0..1`) — chance the effect lands on a connecting shot. Default `1.0` = always (when an effect is set); `0` = never.

To author one: create the `StatusEffect` resource first (see the status-effects content folder), then drop it into `on_hit_effect` and dial `on_hit_chance`. On a hit the game lazily attaches a status manager to the victim and applies the effect, so it works on the player, on NPCs, and with no pre-placed manager.

> Gotcha: the effect is rolled **once per shot**, so a shotgun's pellets don't stack the effect — a connecting blast refreshes the effect's duration rather than applying it nine times. Keep `on_hit_chance` < 1.0 if you want it to land only sometimes.


### Gotchas

- **Caliber strings must match exactly.** A weapon with a `caliber` that has no matching AMMO `Item` in `resources/items/` can be fired only until the loaded clip empties — it can never be reloaded. For a free-reloading weapon (melee, fists, spray paint), the caliber must be *empty*, not a made-up string. (The rock launcher is **not** one of them — `rock_weapon.tres` sets `caliber = &"grenades"` and spends a spare clip per reload.)
- **Don't confuse "infinite ammo" with the clip count.** `is_infinite_ammo = true` still wants a sane `max_ammo` (the HUD shows it), but the count is cosmetic — `consume_ammo()` short-circuits on the flag.
- **`weapon_slots` is typed `Array[Resource]`, not `Array[WeaponData]`**, on purpose (Godot 4's typed-array `.tscn` serialization is unreliable for `script_class` types). Drop your WeaponData `.tres` in anyway — it's validated as `WeaponData` at use time. The same trap is why `Loadout.weapons` and `item_stacks` are authored as typed arrays only via the editor.
- **A profiled NPC is all-or-nothing by default.** If you assign an `NpcData` profile, it drives the NPC entirely (including `weapon_data`); inline exports are overwritten -- unless you tick `profile_fills_blanks_only` (additive merge: your inline tweaks win). To vary one stat, author a profile variant `.tres` or use that flag.
- After saving a brand-new `WeaponData` or ammo `Item`, give the editor a moment to reimport before referencing it elsewhere — a freshly written `.tres` can briefly read as empty in headless runs.

Key files: `rpg/scripts/combat/weapon_data.gd`, `rpg/scripts/combat/ammo.gd`, `rpg/scripts/combat/loadout.gd`, `rpg/scripts/combat/swap_weapons.gd`, `rpg/scripts/combat/inventory.gd`, `rpg/scripts/items/item.gd`, `rpg/scripts/items/item_db.gd`, `rpg/scripts/npc/npc_data.gd`, `rpg/scripts/npc/npc.gd`; content in `rpg/resources/weapons/` and `rpg/resources/items/`.

---

## The drop-in component catalogue

This is the heart of building CYBER SUNDAY without code. A **drop-in component** is a script with a `class_name` (a `Node`, `Area3D`, `StaticBody3D`, etc.) that carries a whole behaviour plus its `@export` knobs. You never edit the script — you **attach it in the scene under the thing it should affect, then fill in its `@export` fields in the inspector.** The component's `_ready()` finds its host (usually `get_parent()`, or a `highlight_target` you point at), wires itself up, and runs. Stack as many as you like: a crate can carry `CanDestroy` + `SpawnOnDestroy`; a campfire can carry `Bonfire` + `LevelUp`.

### The idiom in 4 steps

1. In the scene tree, **add a child node** of the right base type (the catalogue below tells you which) under the object you want to give the behaviour to.
2. **Attach the component script** (or drop its prefab `.tscn`) — the node now shows the component's `@export` fields in the inspector.
3. For look-at interactables, **size the `CollisionShape3D`** to cover the body the player aims at (or set `auto_fit_collider = true` to let it fit the host's meshes at runtime). Several pickups *build their own* visual + hitbox when you leave the body unauthored.
4. **Fill the `@export` fields** — an `Item`, a `PackedScene`, a name string, costs. Done. No code.

### The "look-at interactable" family

The most common base is **`LookAtInteractable`** (`extends Area3D`, `rpg/scripts/components/look_at_interactable.gd`). It is the shared talk-layer hitbox + white look-at outline that the player's interaction ray (`PickupRay`) detects. You rarely attach it raw — you attach one of its subclasses below. Its own knobs are inherited by all of them: `highlight_target` (the `Node3D` to outline; null → parent), `highlight_color`, `highlight_width`, and `auto_fit_collider` (opt-in runtime hitbox-fitting, default `false`). Every subclass overrides `start_talk()` / `can_be_talked_to()` / `look_name()` to add only its own verb, so the ray needs zero changes per component.

⭐**Turning the hover outline OFF, and why `highlight_target` matters.** The hover outline is written into each mesh's single `material_overlay` slot — the same slot that holds an NPC's combat rim and a prop's black hull — so the base is careful about which meshes it may claim. Setting `highlight_color`'s **alpha to 0** or `highlight_width` to **0** means *no highlight*: the component builds no material and never touches the slot (rather than swapping a transparent one in, which would blank whatever outline was showing). And the mesh collect **skips actor and prop subtrees**, so a component whose `highlight_target` is blank — host falls back to the parent — can't strip other things' outlines even when that parent is the level root. Set `highlight_target` (or child the component under the prop) anyway: the skip limits the damage, it doesn't make "the whole level" a sensible highlight host.

### The catalogue

**World interaction — look at it, press F (Interact):**

- **`CanPickUp`** (`can_pick_up.gd`) — add a configured `Item` to the player's backpack. Drop under the visible object (or assign `highlight_target`). Knobs: `item`, `amount`, `item_stacks` (count-based pile, e.g. "2 stims + 10 ammo"), `loot_table` (random bag on top), `pickup_label`, `build_model_from_item` (spawn its visual from `item.world_model`, or a placeholder box if it has none), `save_id` (a stable key so a consumed pickup stays *gone* across a save/reload via `GameState.world_objects` — see *Saving, checkpoints and what persists*; blank falls back to a level/path/position key).
- **`MoneyPickUp`** (`money_pickup.gd`) — a stash of zorkmids; collects `amount` (a `float` — fractional fines are allowed), updates the HUD money readout/floating delta, plays a "cha-ching!" jingle, frees itself. Drop a bare node and it builds a gold coin + hitbox for you; or set `world_model` / `highlight_target`. Knobs: `amount`, `pickup_label`, `world_model`, `pickup_sound` (defaults to `Chaching.mp3`; clear for silent), `pickup_volume_db`, `save_id` (a stable key so a collected pickup stays *gone* across a save/reload, like `CanPickUp` — blank falls back to a level/path/position key), `persist_collected` (set **false** on a code-spawned pickup so it never enters the ledger).
- **`UpgradePickup`** (`upgrade_pickup.gd`) — permanently grants a player ability. Drag an ability scene from `scenes/components/abilities/*.tscn` into `grants`; set `display_name`, `toast_color`, optional `world_model`. (`unlock_id` is a string fallback whose dropdown — `grapple,wall_climb,air_dash,slide,fall_immunity,silent_takedown,chess_visualizer` — self-populates from that abilities folder via `AbilityRegistry`, so it never drifts.) Builds a glowing emblem when you leave the body unauthored. Also `save_id` / `persist_collected` (like `MoneyPickUp`) so a granted upgrade never re-grants on Continue.
- **`ItemContainer`** (`container.gd`) — a persistent lootable crate/chest/locker (two-way transfer, never freed). Drop under the prop, size its `CollisionShape3D`. Knobs: `item_stacks` (count-based contents), `money`, `loot_table`, `container_name`, `save_id` (optional stable id for the exact-save tier — set it on a story crate that must survive scene-layout edits). (Child a `Lock` to keep it shut until picked/keyed.)
- **`LootableCorpse`** (`lootable_corpse.gd`) — a dead body's loot hitbox; opens the loot screen. Normally spawned by the gore/death system (not hand-placed), but it's the same family. Knob: `trigger_radius`.
- **`Merchant`** (`merchant.gd`) — a shop. Two modes: `standalone` (default; aim+interact opens the shop) or data-only on a dialogue NPC (`standalone = false`, the NPC's dialogue offers "Trade"). Knobs: `stock_counts` (`StockEntry` rows — each is an `item` + a `count`), `shop_name`, `money` till, `buy_mult` / `sell_mult`.
- **`Restocker`** (`restocker.gd`, plain `Node`) — drop UNDER a `Merchant` / `ItemContainer` (or point `target_path` at one) to top fixed authored stock/item rows back up over time (`mode = TIMER`) or on the player's next visit (`ON_VISIT`). Refills only the SHORTFALL — never doubles stock, never removes what you sold/deposited. Container money is not re-seeded, and loot tables are not re-rolled. Knobs: `mode`, `interval` (0 = `EconomySettings.restock_interval`), `target_path`. See "Vendor / container restocking."
- **`Healer`** (`healer.gd`) — pay to restore HP-to-full + clear limb damage. Same dual `standalone` pattern. Knobs: `heal_name`, `cost_per_hp`, `min_cost`, `standalone`.
- **`Bonfire`** (`bonfire.gd`) — rest/checkpoint: full heal + set respawn point. Dual `standalone`. Knobs: `bonfire_name`, `standalone`.
- **`LevelUp`** (`level_up.gd`) — spend zorkmids to raise a `CharacterStat` (cost rises with total level) AND/OR spend XP-earned skill points on perks (`available_perks` non-empty turns the picker on). Dual `standalone`. Knobs: `station_name`, `base_cost`, `cost_per_level`, `accepts_credit` (default **off**) + `requires_settled_account` (default **on**) — together, the Ledger's money does not buy levels here, `available_perks`, `perk_points_per_level`. (Dark-Souls bonfire = put a `Bonfire` *and* a `LevelUp` on the same node.)
- **`ChipInstaller`** (`chip_installer.gd`, `@tool`) — the upgrade mechanic: pay to have a microchip `Item`'s `installs_ability` fitted as a permanent player mechanic (and buy chips it stocks, bought + fitted in one payment). Same dual `standalone` pattern. Knobs: `stock_counts`, `installer_name`, `install_mult`, `buy_mult`, `min_fee`, `standalone`. See "NPC services and progression."
- **`ChessMatch`** (`chess_match.gd`, `@tool`) — a blindfold-chess opponent: drop it on a chess table (`standalone`) or under a dialogue NPC for a "Play Chess" option. Knobs: `opponent_name`, `ai_depth` (1–4, default `2`), `ai_blunder_chance`, `player_plays_white`, `wager`, `standalone`. See "NPC services and progression."
- **`Atm`** (`atm.gd`, `@tool`) — the **ledger terminal**. Same dual `standalone` pattern as the other stations: a kiosk you aim + E at, or `standalone = false` under a dialogue NPC for a teller whose conversation offers **"Bank"**. Deposit cash (against a debt the same button *is* the repayment — one signed account), withdraw savings, read the five-line statement (cash / on deposit / owed / credit line / credit score + band), and flip the DEBIT/CREDIT rail every till in the game reads. Deposits and withdrawals are FREE both ways; the counterweight is the service charge on *purchases* funded from the account (`GameSettings.economy.bank_noncash_fee_fraction`). Prefab `res://scenes/components/atm.tscn` (an `Atm` root + a 1 × 2 × 1 `BoxShape3D` to resize). Knobs: `station_name`, `standalone`, `allows_deposit` / `allows_withdraw`. A standalone terminal builds its own diegetic panel speaker — the shared `StationSpeaker` drop-in, see *Cheap diegetic speakers* — so there is nothing to author for sound: it chirps as the screen wakes and **applauds you for paying down your debt**. See "NPC services and progression."
- **`PerkStation`** (`perk_station.gd`) — aim + E at a shrine to learn a `Perk` (permanent stat bonuses / ability grant). Knobs: `perk`, `consume_on_use`. (A `LevelUp` with a non-empty `available_perks` is the *other* path — spend an XP-earned skill point on the picker. See "Perks (the PerkStation shrine)".)
- **`RespecStation`** (`respec_station.gd`, `@tool`, `extends LookAtInteractable`) — the respec twin of `PerkStation`: aim + **E**, pay `respec_cost`, and EVERY unlocked perk is reversed (stat bonuses undone, granted abilities revoked) and its skill point refunded, so you re-pick from scratch at a `LevelUp`. Not consumed (respec as often as you can pay). Knobs: `station_name`, `respec_cost`. See "The RespecStation component."
- **`QuestStarter`** (`quest_starter.gd`, `@tool`, `extends LookAtInteractable`) — a quest board / giver: aim + **E** to start a `Quest` (the inspector twin of `PerkStation`). Knobs: `quest` (the `Quest` to start), `prompt_label` (blank → "Accept: <title>"), `consume_on_use` (default `true` — the board frees itself once accepted). Only offerable while the quest isn't already active or completed; calls `GameState.start_quest`. See "Quests and the Journal."
- **`Radio`** (`radio.gd`) — an in-world radio that **takes precedence over the dynamic score** (plays through a fight while `MusicDirector` holds the bed silent; `duck_for_combat` flips it back) and plays through dialogue too, only dipping with the music bus (`duck_for_dialogue` restores the old duck-out); plays out of a spatial `AudioStreamPlayer3D` from one of three sources, highest precedence first: a single pinned **`track`** (a specific song for THIS radio — looped, and it ignores `music_folder`, `shuffle`, *and* the player's own-music Options override), then a *folder* of tracks (`music_folder`, default the shipped music folder; optional per-radio `shuffle`), then a single `fallback_audio` track when the folder is empty. While a stream is actually playing it bounces the prop and launches Minecraft-style music-note particles that float up and disappear. Drop under a radio prop. Knobs: `radio_name`, `track`, `music_folder`, `shuffle`, `fallback_audio`, `audible_radius`, `show_music_note`, `vibration_enabled` (plus note-particle, bounce, fade/duck, and click-SFX tuning).
- **`Talkable`** (`talkable.gd`) — make ANYTHING speakable (villager, terminal, vending machine) without overriding the host's root script. Instance `talkable.tscn` under the host, assign a `DialogueResource` to `dialogue` (and optional `voice`), size the shape. Use **`DialogueNPC`** (`dialogue_npc.gd`) instead when you want the whole node to *be* the talkable (script on the root, with a child Area3D assigned to `range_area`).
- **`Readable`** (`readable.gd`, `@tool`, `extends LookAtInteractable`) — a note, sign, datapad, or terminal: aim + E to read `text` through the dialogue UI, paginated on blank lines and labeled with `title`. First read can set a story flag, advance a quest objective, and/or grant XP. Knobs: `title`, `text`, `verb`, `set_flag_on_read`, `advance_quest_id`, `advance_objective_id`, `xp_on_read`.
- **`Switch`** (`switch_lever.gd`, `@tool`, `extends LookAtInteractable`) — the manual counterpart to `TriggerVolume`: aim + E to set a flag, call a method on `target`, show a toast, and/or play a clunk. Child a `BuildGate` under it for stat/perk/ability/faction requirements. Knobs: `verb`, `one_shot`, `locked_toast`, `set_flag`, `set_flag_value`, `action`, `target`, `toast_text`, `toast_color`, `play_audio`, `audio_bus`.

**Petting — look at it, HOLD the Takedown key (Q):**

- **`Pettable`** (`pettable.gd`, `extends Area3D`, `rpg/scripts/components/pettable.gd`) — drop onto any object (a cat, a dog, a shrine) and the player can **HOLD the Takedown key (default Q — the same verb as the silent takedown)** while aimed at it to *pet* it: a ♥ floats up above the object and a crowd-applause "clap" cheer plays (the same reward as an all-headshots NPC kill). The friendly twin of the takedown — Q is contextual THREE ways now: an off-guard NPC under the crosshair gets a takedown, a Pettable object gets a pet, and **nothing eligible under the crosshair gets a LEAN LEFT** (`scripts/player/lean.gd`; the lean claims the key on the press and both hold-verbs stand down for that hold, so a peek can never quietly pet or take down whatever it swings past). **One-click add (no hand-built area):** select the object in the scene tree, open the **CYBER SUNDAY** bottom panel → **Palette**, search *Pet*, and click **Add to selected node** — it lands a configured `Pettable` child and auto-fits its own hitbox at runtime, so you never size a collider by hand. Self-sufficient: on its own physics layer (NOT the talk layer, so it never shows an "[F]" prompt) and, if you don't author a `CollisionShape3D`, it auto-builds one fitted to the parent's meshes (`auto_fit_collider`, default `on`; objects with their own body collider work either way). A solid wall between you and the object blocks the pet, and you can't pet an object you're currently carrying (a held prop sits right under the crosshair). Knobs — **Pet**: `enabled`, `hold_time` (`0.6` s), `max_range` (`2.5` m), `cooldown` (re-pet delay, `2.0` s — paces both the heart and the applause so two claps never overlap; lower it for rapid petting, `0` for none), `prompt_verb` (the hover verb shown before the name — its default ships as an unauthored placeholder, so author it), `display_name` (blank → the host object's OWN authored name: a `Throwable`'s `display_name`/`data.display_name`, an NPC's/Talkable's `display_name`, else the host node name — so a pettable crate reads "Pet Dog", not "Pet Throwable"). **Heart**: `heart_glyph` (`♥`), `heart_color`, `heart_height`, `heart_rise`, `heart_hold`, `heart_fade`, `heart_font_size`. **Feel**: `applause_on_pet` (on — the crowd-clap cheer, the same one an all-headshots kill plays via `AudioManager.play_applause`), `show_toast` (off), `pet_sound` (optional purr/chirp). **Hitbox**: `auto_fit_collider`, `fallback_radius`. React to a pet by connecting the **`petted(by)`** signal in the editor (a purr SFX, a quest flag, a companion-affinity bump). No keybind to add — it reuses the existing Takedown action; to split it onto its own key, give `PetInteraction` its own `InputManager` action + `ActionCatalog` row.

**Befriending & following — look at it, TAP the Befriend key (B) to adopt, HOLD to release:**

- **`Claimable`** (`claimable.gd`, `extends Area3D`, `rpg/scripts/components/claimable.gd`) — drop onto any object (a stray dog, a drone, a robot) and the player can **TAP the Befriend key (default B, the `Claim` action internally)** while aimed at it to *adopt* it: a real-time text box pops up to **name** it (mouse freed, the world keeps running — you stay vulnerable while you type), and on confirm the object is renamed, gains a **blue "this is mine" outline**, *and* starts **following** you. **HOLD the same key** while aimed at a befriended object to **release** it (a deliberate hold). The release prompt is **hidden by default** (`show_release_prompt` off) — the gesture still works, it's just not advertised — so the only on-screen line you normally see is "[B] Befriend Dog" (stacked above "[Q] Pet Dog" on the dog, until it's adopted). The one-time, ownership twin of petting. On its OWN physics layer (not the talk/pet layers, so no stray prompt), wall-occluded (can't befriend through a wall), and you can't befriend something you're carrying. Like `Pettable` it auto-fits its own hitbox at runtime (`auto_fit_collider`, default `on`). What befriending does: (1) pushes the chosen name onto the host's `display_name` so the readout now reads the dog's name; (2) **pins a persistent blue outline** on the prop (the SAME blue a recruited companion NPC wears — `NPC.OUTLINE_FOLLOWING` — so a befriended dog and a recruited guard read alike; only on hosts with the outline system, e.g. a `Throwable`); (3) **switches on a `PropFollow`** so it follows you — it ENABLES a `PropFollow` you pre-placed on the prop (honouring your tuning) or, if there's none, adds a default one; (4) makes a thrown `Throwable` **LOYAL** — it no longer damages your FRIENDLY/NEUTRAL NPCs and hits HOSTILE NPCs *harder* (the dog won't bite your allies but mauls enemies); (5) fires the **`claimed(by, chosen_name)`** signal. Releasing it reverses (1)–(4) — strips the name you gave it (reverts the `display_name` to whatever it was before, so an unbefriended dog is just "Dog" again), drops the outline, disables (but keeps) the follow, and restores normal thrown damage — and fires **`unclaimed(by)`**. Knobs — **Claim**: `enabled`, `max_range` (`3.0` m), `prompt_verb` (the hover verb shown before the name — its default ships as an unauthored placeholder, so author it), `display_name` (blank → the host's resolved name). **Naming**: `ask_for_name` (on → opens the name box; off → instant adopt using `default_name`), `default_name`. **Claimed look**: `show_claimed_outline` (on), `claimed_outline_color` (default the companion blue). **Unclaim**: `allow_unclaim` (on → HOLD to release; off → befriending is permanent and an adopted object shows no prompt), `unclaim_hold_time` (`0.6` s), `show_release_prompt` (**off** → the release gesture is hidden). **Preset (drop-restore)**: `preset_claimed` (off; on → auto-befriends itself on spawn) + `preset_claim_name` — not hand-authored, they're how a dropped-but-previously-befriended dog re-adopts itself so it stays yours (see *Re-drop fidelity* above). **Befriended combat**: `loyal_when_befriended` (on → spares allies + extra vs enemies when thrown), `befriended_spares_allies` (on → no damage to friendly/neutral NPCs), `befriended_damage_multiplier` (`2.0` → double damage to hostiles). **Feel**: `show_toast` (off), `toast_color`, `claim_sound`. **Hitbox**: `auto_fit_collider`, `fallback_radius`. The keybind ships on **B** (it moved off T when the Fallout-style Wait screen took that key) (the `Claim` action — the internal name; it shows as "Befriend Pet" in Options → Controls and is rebindable).
- **`PropFollow`** (`prop_follow.gd`, `extends Node`, `rpg/scripts/components/prop_follow.gd`) — drop onto any physics prop (a `Throwable`/`RigidBody3D`) to make it keep up with the player using the **same hidden teleport recruited NPC companions use**: when the prop falls well behind AND is **off-screen**, it silently blinks to a reachable spot just behind you (down-rayed onto the floor), so a dropped dog you walked away from reappears at your heel instead of being left behind. It does NOT walk the prop between blinks (a RigidBody has no navmesh pathing) — it sits where it lands and blinks up again when you get far enough ahead. **Ships DISABLED** (`enabled` off) so an unclaimed prop never follows; `Claimable` flips it on at claim time. Pre-place it (disabled) only if you want to tune its blink feel in the Inspector — otherwise `Claimable` adds a default one for you. Knobs: `enabled`, `teleport_distance` (`9` m — how far behind before a blink), `teleport_behind` (`3` m), `teleport_side_spread` (`2` m), `teleport_cooldown` (`1.5` s — paces blinks, no strobing), `view_dot` (`0.35`, the on-screen guard — never pops in view), `ground_probe` (`3` m down-ray to rest on the floor).

**Appearance — random cosmetic variety:**

- **`RandomCoat`** (`random_coat.gd`, `extends Node`, `rpg/scripts/components/random_coat.gd`) — drop onto any prop that has a `MeshInstance3D` (a dog, a cat, a rat, even a barrel) to give each spawned instance a **random coat**: on ready it rolls ONE albedo tint and/or ONE albedo texture from your authored pools and applies it to the mesh, so a litter of otherwise-identical dogs comes out in varied colours instead of all-white. Purely cosmetic, rolls once. It **duplicates** the mesh's material per instance before recolouring — a scene's material is a *shared* resource, so tinting it in place would recolour every dog at once *and* mutate the on-disk resource — and applies on a **deferred** call so it lands AFTER a `Throwable` has pushed its `data.material` onto `material_override`. It recolours only `material_override` (the albedo); the look-at outline / hit-flash live on `material_overlay`, so they're untouched. Editor-safe (no coat is ever baked into the saved scene) and **not persisted** (a hand-placed prop re-rolls its coat each load — fine for a cosmetic, non-saved dynamic prop). Knobs: `coat_tints` (an `Array[Color]` — each entry MULTIPLIES the base albedo, so the texture's pattern/shading survives and just recolours; include a plain white `Color(1,1,1)` so some props keep their natural colour; empty → tint untouched), `coat_value_mults` (an `Array[float]`, **optional** — a per-coat TRADE-VALUE multiplier index-aligned to `coat_tints`, so a rarer coat sells for more: coat_tints[i] is worth coat_value_mults[i] × the dog's base value. Leave empty to price every coat the same — fully backwards-compatible — and match its length to `coat_tints` when you do author it, else unmatched coats fall back to ×1.0 and the node raises a config warning. Only `DogPickup` reads it; harmless on a prop with no size-priced pickup), `coat_albedos` (an `Array[Texture2D]` — each entry REPLACES the albedo texture outright, for spotted / patterned coats you author as extra PNGs; empty → base texture kept), `mesh_path` (optional explicit target; blank → the host's `mesh_instance`, e.g. a `Throwable`'s visual root, else the first `MeshInstance3D` under the host), `enabled` (on), `preset_tint` (a FIXED tint that overrides the roll — the alpha-0 default means "roll normally"; not hand-authored, it's how a re-dropped prop is restored to its stashed colour, see *Re-drop fidelity* above). **On the shipped dog** (`scenes/characters/dog.tscn`) it carries seven natural coat tints — white, cream, light brown, chocolate, grey, black, red-setter — so a pack of dogs reads as visibly different animals, **priced** ×1.0 / ×1.25 / ×1.5 / ×2.0 / ×1.75 / ×3.0 / ×2.5 respectively (the darker/richer coats fetch more zorkmids). The coat's price rides the re-drop round-trip: the restored `preset_tint` maps back to the same pool entry, so a re-dropped rare dog keeps both its colour and its higher value.
- **`RandomSize`** (`random_size.gd`, `extends Node`, `rpg/scripts/components/random_size.gd`) — the size twin of `RandomCoat`: drop it under any prop and on ready it rolls ONE scale multiplier and multiplies the host `Node3D`'s **authored** scale by it, so a litter of dogs comes out in visibly different sizes. Two optional knock-ons, both duck-typed (absent on a prop that doesn't expose them): it scales the host's `impact_damage_mult` by the size (a bigger thrown prop hits harder) and its `sound_pitch_mult` *inversely* (smaller = higher-pitched yelp). Rolls once, editor-safe, and **not persisted** (a hand-placed prop re-rolls each load). Knobs: `min_scale_mult` (`0.75`), `max_scale_mult` (`1.35`), `affects_impact_damage` (on) + `damage_power` (the exponent the size is raised to), `affects_sound_pitch` (on) + `pitch_power`, `enabled` (on), `preset_scale_mult` (`0.0` = roll normally — a FIXED multiplier that overrides the roll; not hand-authored, it's how a re-dropped prop is restored to its stashed size, see *Re-drop fidelity* above). **On the shipped dog** (`scenes/characters/dog.tscn`) it rides between `RandomCoat` and `SprayPaintable` with defaults. **On the gore gib** (`scenes/effects/gore_gib.tscn`) it rides with a wider authored range (`min_scale_mult 0.6` / `max_scale_mult 1.5`), so every meat chunk a death flings comes out its own size — pinned by `tests/test_gore_gib_prefab.gd`. (The body-part gib chassis deliberately carries none: a flung head stays the character's true head size.)
- **`SprayPaintable`** (`spray_paintable.gd`, `extends Node`, `rpg/scripts/components/spray_paintable.gd`) — the **spray-can twin of `RandomCoat`**: drop it under any prop with a `MeshInstance3D` and the paint gun (any `is_spray_paint` weapon — the shipped `spray_paint.tres`) **recolours the whole prop to the sprayed colour** when a paint blob lands on it, instead of gluing a splatter decal on. The blob (`PaintProjectile`) discovers the component on the body it hit (`SprayPaintable.find_on`) and calls `paint()`; it reuses the exact same duplicate-the-shared-material / `material_override`-only recolour contract as `RandomCoat` (shared in `MeshCoat`), so the look-at outline / hit-flash are untouched. `RandomCoat` sets the INITIAL coat once at spawn, `SprayPaintable` OVERWRITES it on every spray — last writer wins, so they compose (spray a random-coated dog and it takes your colour). Cosmetic and **not persisted** (reverts to its natural / rolled coat on reload). Knobs: `enabled` (on), `mesh_path` (optional explicit target; blank → the same auto-resolve as RandomCoat: the host's `mesh_instance` else the first `MeshInstance3D` under the host), `blend` (`@export_range` 0–1 — `1.0` snaps the coat fully to the sprayed colour in a single hit, lower eases toward it over repeated sprays so paint "builds up" the longer you hold the trigger on the prop), `suppress_decal` (on by default → recolour and leave NO splatter decal on the prop; off → also drop the usual splat on top of the recolour), plus a `painted(color)` **signal** you can wire in the editor to chain a reaction (a yelp bark, a shake, a particle) when the prop gets painted. **On the shipped dog** (`scenes/characters/dog.tscn`) it rides next to `RandomCoat` with defaults, so the player can spray the dog any colour with the paint can. Drop it onto a cat, a car door, a barrel, a sign — anything with a `StandardMaterial3D` mesh — to make it spray-recolourable too.

**Openable & triggered geometry:**

- **`Door`** (`door.gd`, `@tool`, `extends LookAtInteractable`) — aim + **F (Interact)** to swing a door open/closed; a child `StaticBody3D` under the pivot blocks the doorway until it opens, so an open door simply isn't in the way. Prefab `res://scenes/components/door.tscn`. Swing knobs: `pivot` (**REQUIRED** — the `Node3D` it rotates, holding the mesh + the blocker; null → open/close are no-ops), `open_angle` (`90.0`; negative swings the other way), `open_duration` (`0.5` s), `start_open`. Lock knobs (a key and pickability are INDEPENDENT): `locked`, `key_item_id` (an optional inventory `Item.id` that opens it outright; empty = no key), `consume_key` (eat the key on unlock, off = reusable), `pickable` (**off by default** — turn ON to allow lockpicking), `lockpick_item_id` (which pick, default `&"lockpick"`), `consumes_pick` (snap the pick on success, on by default), `unlock_flag` (while this `GameState` flag is true the door counts as unlocked), `save_id` (a stable key so the door's open/locked state persists across a save/reload via `GameState.world_objects` — see *Saving, checkpoints and what persists*; blank falls back to a level/path/position key). API: `open()` / `close()` / `toggle()` / `is_open()`; signals `opened` / `closed` — so a `TriggerVolume`, switch, or cutscene can drive it. **Re-bake the navmesh** if the door body sits in walkable space.
- **`LevelDoor`** (`level_door.gd`, `@tool`, `extends LookAtInteractable`) — a PORTAL to another level: aim + **F (Interact)** to travel (calls `GameRoot.load_level`) and arrive at the matching `PlayerSpawn`. The level-flow twin of `QuestStarter` / `PerkStation`. Knobs: `target_level` (the destination `LevelData`; null → no-op + a config-warning), `entry_id` (the `PlayerSpawn.entry_id` to arrive at in that level; blank → its default spawn), `prompt_label` (hover label; blank → "Enter \<level display_name>"). **REQUIRES a `GameRoot` in the scene** (group `game_root`) — `game.tscn` has one, so this works in the shipped game; in a bare level scene with no GameRoot the door is inert: the setup fault lands in the error log (`push_error`), the player just sees a `[PH]` "It won't open." toast. Prefab: `scenes/components/level_door.tscn`.
- **`PlayerSpawn`** (`player_spawn.gd`, `extends Marker3D`) — an arrival point in a level: `GameRoot` drops the player on the spawn whose `entry_id` matches the `LevelDoor` that sent them (or the blank-`entry_id` one for the default entrance), and seeds it as the respawn point. Prefab: `scenes/world/PlayerSpawn.tscn` (carries an editor-only arrow gizmo, freed at runtime). Knob: `entry_id`. Every level needs at least one; the `LevelRoot` validator warns if there are none or if two share an `entry_id`.
- **`TriggerVolume`** (`trigger_volume.gd`, `extends Area3D`) — fire configurable actions when a body in `trigger_group` enters (or exits) a zone. Prefab `res://scenes/components/trigger_volume.tscn`. See **"Triggers, encounters & cutscenes"** for the full field list.
- **`TutorialPrompt`** (`tutorial_prompt.gd`, `@tool`, `extends TriggerVolume`) — a one-time tooltip volume: walk in and it teaches a verb ONCE (remembered across saves via a persistent flag), with live `{action}` tokens that show the player's CURRENT binding (`"Press {PickUp} to open doors"` → `"Press E…"` — the token is the action NAME, and the substitution is bare, so add your own brackets if you want them). Subclasses `TriggerVolume`, so its base actions still fire too. Knobs: `prompt_text` (with `{action}` tokens; empty = inert), `prompt_color`, `seen_flag`. See **"TutorialPrompt — a one-time 'how to' tooltip volume."**

**Navigation helpers:**

- **`NavBlocker`** (`nav_blocker.gd`, `@tool`, `extends NavigationObstacle3D`) — child a solid prop so NPC paths avoid it. `mode = CARVE` cuts a static footprint out of the baked navmesh (re-bake after moving); `mode = AVOID` creates a runtime RVO obstacle for movable props. It auto-sizes from the parent's first `CollisionShape3D`, or use `size_override` for odd shapes.
- **`NavLink`** (`nav_link.gd`, `@tool`, `extends NavigationLink3D`) — child of the level at a ledge/drop to bridge two disconnected navmesh islands so NPCs traverse it (the bake disconnects anything taller than `agent_max_climb`). `direction = TWO_WAY` (climb + drop) or `ONE_WAY_DOWN` (drop only). `auto_project` snaps endpoints onto the mesh; `traverse_cost` biases A* toward ramps. **No re-bake.** The upward launch comes from the `Locomotor` link-ascent driver (idle NPCs climb, not just combatants).
- **`NavDebugOverlay`** (`nav_debug_overlay.gd`, `@tool`, plain `Node`) — drop into a level to toggle Godot's navmesh debug draw plus every `NavigationAgent3D` path line while you play. Debug-build only and inert unless enabled. Knobs: `enabled`, `toggle_action`, `agent_paths`.
- **`DebugOverlay`** (`debug_overlay.gd`, `extends CanvasLayer` — **not** the same node as `NavDebugOverlay` above) — a runtime perf + game-state HUD with rolling line graphs. **Pre-placed in `scenes/game.tscn`** (as of 2026-08-18): press **F3** while playing to show/hide it. READ-ONLY — it only samples Engine / Performance / group counts / player state, sits on layer `128` above the HUD, and ignores mouse input, so it can never eat a click or touch gameplay. Knobs: `toggle_key` (`KEY_F3` — a raw dev key, deliberately *not* a rebindable `InputManager` action), `start_visible` (off), `sample_interval` (`0.25` s per sample), `history` (`120` points per graph, range 8–600), `capture_errors` (on — installs a runtime error/warning sink, **debug builds only**), `write_error_log_on_exit` (on — dumps what it captured to `user://session_errors.log` on quit, the post-mortem trail for a playtest), `show_player_state` (on — a live HP/stamina/wallet/bank/position/clock/level/disk-writes block under the perf readout), `show_stealth` (on — light / carried-light / noise / stealth level / awareness census), `show_input_state` (on — cursor mode, pause, suppression, open modals, focus owner).

**In-game debug tools (all in `scenes/game.tscn`, all debug-build-gated — see the "In-game debug tools" chapter):**

- **`DebugConsole`** (`debug_console.gd`, `extends CanvasLayer`, layer `150`) — the backtick developer console: ~55 typed commands with Tab completion, history and grouped `help`. Suspends the player + frees the cursor while open. Drop at the **scene root** (never inside the Level subtree — level warps free that). Knobs: `toggle_key` (backtick), `force_in_release`, `scrollback_lines`, `history_lines`, panel/typography/colour exports.
- **`DebugMenu`** (`debug_menu.gd`, `extends CanvasLayer`, layer `149`) — the **F1** clickable cheat menu: every console command as a button/cycler page, generated from the same registry; destructive rows take a second confirming click. Same drop rule and suspension contract as the console; the two close each other so only one holds the cursor. Knobs: `toggle_key`, `force_in_release`, `panel_size` (a PREFERRED size — the panel clamps it to the live canvas minus `panel_offset`, so it stays fully on screen at any aspect), `output_height`, `editor_width`/`arrow_button_width`, `field_color`, `console_path`. Help lines and output lines WRAP (they are the readable payload); only fixed chrome — the title, a cycler's current value — clips with an ellipsis.
  - **Search bar** (the `find` field under the title): filters the pane across **every** page at once, live as you type, via `DebugCommands.search()` — it matches the command name, its page, its help line, its argument names and its verb words, so `fall` finds `god` and `crosshair` finds `npc`. Multiple words AND together (more words narrow). Results are ranked name-match-first and each one is tagged with the page it normally lives on; the title bar carries the hit count. **Enter** hands the caret to the first result (its first text argument if it has one) — it never runs a command. **Escape** clears a live filter, and closes the panel when there is none. Clicking a category, or the `x` beside the field, leaves the search. Knobs: `search_caption`, `search_clear_glyph`, `search_title_prefix`, `no_match_text`, `focus_search_on_open` (ON = the caret lands in the field, so F1-then-type just works; OFF restores the first category button as the landing spot, which is friendlier on a keyboard because a LineEdit being typed into swallows Up/Down as caret moves).
- **`DebugNoclip`** (`debug_noclip.gd`, plain `Node`) — **F2** noclip flight: freezes the player's own physics and flies the real body along the camera basis, so the ink outline and view-model stay correct; landing re-arms the ground snap and zeroes the banked fall-death timer. The console's `noclip` command mounts one at the scene root automatically if none exists. Knobs: `toggle_key`, `fly_speed`, `boost_multiplier`, `vertical_speed`, `snap_to_ground_on_exit`, the action-name exports, `force_in_release`.
- **`DebugInspector`** (`debug_inspector.gd`, `extends Node3D`) — the **F4** look-at inspector: aim at an NPC for live hp / disposition / GOAP / perception / nav labels drawn in the world (via `AiDebugDraw`), or at any prop for its identity; the console's `who` command reads the same facts as text. Keep it at the **world origin** (its drawing surface is world-space). Knobs: `toggle_key`, `always_track`, `show_wire`, `show_labels`, `show_nav_target`, `max_range`, `draw_through_walls`, colour/size exports.
- **`AiEventLog`** (`ai_event_log.gd`, `extends CanvasLayer`, layer `140`) — the AI transition log: polls every NPC each physics tick and records perception-state / target / GOAP goal+action / provoke / flee / freeze / stranded / spawn+free flips into a session ring buffer (a `static var`, so it survives death reloads); `ailog [n] [filter]` dumps it, `ailog on` shows a last-N panel. Knobs: `max_lines`, `poll_every_ticks`, `channels` (mute mask), `log_initial_cast`, `show_panel`, `panel_lines`, `force_in_release`.
- **`DebugEventTicker`** (`debug_event_ticker.gd`, `extends CanvasLayer`, layer `141`) — the game-event ticker: a fading top-right column of one line per quest / reputation / clock phase / rent / dialogue / money+xp / effect / death / level / save event, backed by a session ring `events [n] [filter]` dumps; `events on|off` toggles the column. Read-only, never eats clicks. Knobs: `start_visible`, `max_lines`, `visible_lines`, `line_seconds`, `corner`, the `log_*` channel bools, `force_in_release`.

**Locking:** **`Lock`** (`lock.gd`, plain `Node`) — drop under any interactable (a container, or a `Door`) and the host checks it before opening. A lock separates a **key** from **pickability**, so it can be pickable-only (the default), key-only, BOTH (a carried key takes precedence over a lockpick — never wasting a pick), or sealed. Knobs: `locked`, `key_item_id` (an optional key/keycard id that opens it outright; empty = no key), `consume_key` (off = reusable), `pickable` (**on by default** — the classic lockpick lock; turn off for key-only/sealed), `lockpick_item_id` (default `&"lockpick"`), `consumes_pick` (off for a reusable skeleton key), `unlock_flag`. Emits `unlocked(by)`. (`Door` has the same fields built in for an inline door lock; the shared rule lives in `lock_rules.gd`.)

- **`BuildGate`** (`build_gate.gd`, `@tool`, plain `Node`) — the *build-aware* twin of `Lock`: drop one under any interactable (a `Door`, an `ItemContainer`, a `TriggerVolume`) and the host consults it before opening/firing, gating on who the player has BECOME. Gates on a player **stat** (`required_stat` ≥ `required_value`), a learned **perk** (`required_perk`), a granted **ability** (`required_ability`), and/or **faction standing** (`required_faction_id` ≥ `required_reputation`) — every SET requirement must pass (AND). Knobs: `required_stat` (a `CharacterStats` stat, dropdown-populated; empty = no stat gate), `required_value`, `required_perk` (a `Perk` id), `required_ability` (a mechanic id), and `required_faction_id` (a faction id, dropdown-populated from the Factions registry) + `required_reputation` (minimum standing; passes only when `Reputation.get_reputation(faction) ≥ required_reputation`). Empty (nothing set) always passes; a failed open toasts `deny_reason()` ("Requires Strength 5", or "Requires standing with &lt;faction&gt;") — the toast names the requirement by its **authored display name** (the stat's `StatText` title, the perk's `display_name`, the faction's `display_name`; a capitalized id only when nothing is authored), so retitling a resource retitles the toast. Discovered via `BuildGate.of(host)`, exactly like `Lock`.

**Destruction & drops:**

- **`CanDestroy`** (`can_destroy.gd`, `extends StaticBody3D`) — a body that breaks when shot (works for every weapon; both hitscan and projectiles call `take_damage`). Use it as the root of a breakable, give it a `CollisionShape3D` + `MeshInstance3D`. Knobs: `max_hp`, `destroy_effect`, `destroy_sound`, `save_id` (a stable key so a destroyed prop stays broken across a save/reload via `GameState.world_objects` — see *Saving, checkpoints and what persists*; blank falls back to a level/path/position key). Emits `destroyed`.
- **`SpawnOnDestroy`** (`spawn_on_destroy.gd`, plain `Node`) — drop UNDER a `CanDestroy` or `Throwable` and it spawns loot into the level when the host breaks. Knobs: `spawn_scene`, `count`, `scatter`, optional `loot_table`. For random loot just assign a **`loot_table`** and leave `spawn_scene` EMPTY — the shipped `CanPickUp` is used automatically and the rolled item (with its world model, or a placeholder if it has none) is stamped onto each drop. Set `spawn_scene` only for a FIXED, pre-configured drop. Pair with `CanDestroy` for "shoot the crate for loot."
- **`Throwable`** (`Throwable.gd`, `@tool`, `extends RigidBody3D`) — a pick-up-and-throw physics object (a crate). Emits `destroyed` on break (the same signal as `CanDestroy`), so `SpawnOnDestroy` works on it too.
- **`ThrowTrail`** (`throw_trail.gd`, `@tool`, `extends Node3D`) — child it to a `Throwable` and a **real throw** drags a white tracer behind the prop through its arc. Nothing to wire (it finds its own host body); its shape knobs default to `0` = inherit **Effects → Thrown weapon trail**. Every weapon drop gets one automatically — `WeaponData.thrown_trail` defaults **on**. See *The thrown-weapon tracer* under Effects tuning.

**NPC / character presentation (drop under the Enemy root):**

- **`BodyModelSwap`** (`body_model_swap.gd`, `@tool`) — swap an NPC's body/head (and even arms/legs) for your own `.glb` files with a **live editor preview**, AND drive its runtime character motion. Knobs include `body_model`, `head_model`, and `*_scale` / `*_position` / `*_rotation` for each part, optional `*_texture` / `*_color` re-skins, arm/leg gait-animation tuning, and a momentary `refresh_preview`. Runtime motion (see "Customising an NPC look"): `legs_follow_movement` + `leg_turn_rate` (legs steer to the movement direction independent of the torso), `arms_hold_when_drawn` (default **true** — an armed NPC holds its weapon in both hands the whole time the gun is drawn, the natural "armed enemy" look; stealth-safe because the pose points the gun along the perception-gated torso, not at the player) with `arm_raise_range` as the opt-out (turn `arms_hold_when_drawn` off and the arms stay LOW until the foe is within that many metres **and** it has actually sensed you — `has_sensed_foe()` — so the arms coming up is the "I noticed you" telegraph), the talking head-bob (`talk_head_bob` + `talk_bob_*`) and a billboarded flapping mouth (`show_mouth` + `mouth_*`, active while it speaks a line or bark), and the chest `breathe` idle (during a conversation only the NPC you're talking to breathes). Note: the head scale/pos/rot knobs are named `head_scale` / `head_position` / `head_rotation` (the body's are `body_model_scale` / `body_model_position` / `body_model_rotation`).
- **`NpcHeadLookMount`** (`npc_head_look_mount.gd`) — FNV-style independent head tracking (the head turns to its foe/player/noise). Drop one under the Enemy root. Knobs: `enabled`, `look_range`, `max_yaw_deg`, `max_pitch_deg`, `neck_pivot`, `turn_speed`, `look_at_player`, `host_path`. Gated by `GameSettings.npc_ai.head_look`, which **ships ON**, so it's live by default. **If the head clips into the torso/shoulders when it turns:** the head rotates about the swapped head node's own origin, and each head `.glb` plants that origin somewhere different — so a wide turn can arc the skull into the body. Two knobs fix it: keep `max_yaw_deg` / `max_pitch_deg` near a real neck's independent range (defaults **55 / 25**; cranking them toward 90 owl-swings the jaw into the collar), and set `neck_pivot` to hinge the turn at the base of the neck instead of the head origin (an offset in metres below/behind the head — a down-look then pushes the face *forward* off the chest instead of into it). `neck_pivot` defaults `(0,0,0)` (rotation about the head origin, unchanged) and is a per-rig playtest knob — head-look is runtime-only, so there's no editor preview; the shipped `enemy.tscn` seeds `(0,-0.08,0)`. A head model whose origin sits *behind* the face (e.g. the female look) wants a positive Z to pull the pivot up under the head. **Truthful tracking (stealth contract):** the head only points where the NPC's `Perception` currently vouches for — it tracks a foe's live position only while ALERTED (actually seeing it), eases to the last-known spot while investigating/lost, and only glances at a nearby player it can genuinely see (range + view cone + clear line of sight via `can_see_node`). It will **not** crane toward a target it can't see — through a wall, behind its back, or in the dark — so a head-turn never telegraphs awareness the NPC doesn't have. (The priority order lives in the pure, unit-tested `NpcHeadLookMount.resolve_look_point`; the brain feeds it perception-resolved facts in `NPC.head_look_point`.)
- **`LocomotionFx`** (`locomotion_fx.gd`) — footstep SFX + landing thud + dust for any `CharacterBody3D`. NPCs auto-build one, so you only attach it to override. Knobs: `footstep_sounds`, `land_sound`, `stride_length`, `move_threshold`, `footstep_volume_db`, `land_volume_db`, `min_land_speed`, `hard_land_speed`.
- **`FallScream`** (`fall_scream.gd`) — plays a yell after falling for a moment, re-arms on landing. Drop under any `CharacterBody3D`. Knobs: `scream` (clear it → inert), `min_fall_time`, `min_fall_speed`, `volume_db`.
- **`SelfHealer`** (`self_healer.gd`, `@tool`, plain `Node`) — drop under an NPC to override when it spends carried healing consumables mid-fight. NPCs auto-add a default one, so place a configured instance only to tune or disable that NPC. Knobs: `enabled`, `heal_at_hp_frac`, `cooldown_ms`.
- **`PanicOnDamage`** (`panic_on_damage.gd`, `@tool`, plain `Node`) — drop under an NPC to tune whether it breaks and flees after taking damage. NPCs auto-add one seeded from temperament; a placed instance overrides per-NPC. Knobs: `enabled`, `panic_scale`.
- **`ProvokeOnAttack`** (`provoke_on_attack.gd`, `@tool`, plain `Node`) — drop under an NPC to control whether player attacks can turn a non-hostile actor hostile. Use `enabled = false` for a scripted shopkeeper or quest-giver who absorbs hits without aggroing. Knob: `enabled`.

**NPC routes:**

- **`PatrolPath`** (`patrol_path.gd`, `@tool`, `extends Node3D`) — a level-placed route; its `Marker3D` / `Node3D` **children** are the ordered waypoints (config-warns with zero). Knobs: `loop` (`true` = cycle the route, `false` = ping-pong), `wait_time` (`1.0` s paused per waypoint). No prefab. See **"Patrol routes."**
- **`PatrolBehavior`** (`patrol_behavior.gd`, `@tool`, plain `Node`) — drop **UNDER an NPC** and point `patrol_path` at a `PatrolPath`; the NPC walks the beat while idle (combat interrupts, then it resumes). Knobs: `enabled`, `patrol_path` (`NodePath`; empty = inactive). No prefab. See **"Patrol routes."**
- **`ScheduleBehavior`** (`schedule_behavior.gd`, `@tool`, plain `Node`) — drop **UNDER an NPC** to make it follow a daily ROUTINE instead of idling: it reads the `WorldClock` phase and walks the NPC to the marker for that phase ("market by day, home by night"). Point `schedule` at a `Schedule` resource and drop a `Marker3D` into each phase's `location_group`. Runs in idle ABOVE patrol/wander, BELOW companion-follow — a fight interrupts it, then it resumes. Knobs: `enabled`, `schedule` (empty → normal idle), `arrive_distance` (m, default `1.5`). Mirrors `PatrolBehavior`. No prefab. See **"The day/night clock and NPC routines."**
- **`NpcHomeReturn`** (`npc_home_return.gd`, `@tool`, plain `Node`) — the "go home" LEASH: sends an NPC back to the spot it was authored at when the **player dies** (`GameState.player_died`) or after it has been **off-screen** for `off_screen_delay`. Every NPC **auto-adds one seeded from `GameSettings.npc_ai`** (group *Home return (leash)*), so place a configured instance only to tune or disable that NPC. It returns via the same hidden blink companions/dogs use to catch up — never while the player can see the NPC or its post — and falls back to the normal idle walk-back otherwise. Drops the current engagement (`NPC.stand_down()`) but **not** hostility. Knobs: `enabled`, `home_marker`, `home_slack`, `snap_home_to_navmesh`, `return_on_player_death`, `death_return_delay`, `death_return_ignores_view`, `return_when_off_screen`, `off_screen_delay`, `off_screen_requires_calm`, `blink_home`, `view_dot`, `occlusion_check`, `scan_interval`. See **"Going home: the leash."**
- **`AiLod`** (`ai_lod.gd`, plain `Node`, `scripts/components/`) — AI LEVEL OF DETAIL: how often a **distant, unaware** NPC re-runs its brain. Every NPC **auto-adds one seeded from `GameSettings.npc_ai`** (group *AI level of detail*), so place a configured instance only to tune or exempt that NPC (`enabled = false` = always full rate). Bands: inside `near_distance` (20 m) every tick; out to `far_distance` (45 m) every `mid_interval` (0.1 s); beyond it every `far_interval` (0.25 s). **Movement is never throttled** — gravity and `move_and_slide` run every tick at every band, so a throttled NPC still walks smoothly; it only *decides* less often, and the delta it thinks with is the real time banked since its last think, so nothing runs in slow motion. **Exempt entirely** (always full rate): perception past `UNAWARE`, scripted-investigating, companions, and any level with no human player (which keeps `tests_soak` measuring what it always did). Knobs: `enabled`, `near_distance`, `far_distance`, `mid_interval`, `far_interval`. Measured: 40 NPCs spread across the map went 66.7 ms → ~43 ms/frame. See **"Crowd cost: AI level of detail."**
- **`GuardDuty`** (`guard_duty.gd`, `@tool`, plain `Node`) — drop **UNDER an NPC** to put it on BODYGUARD duty: it defends `protectee` (engages anyone hostile to them) the way a recruited companion defends the player, but for ANY character. Calls the parent NPC's `guard()` on `_ready`. Knobs: `protectee_path` (the VIP), `protectee_group` (default `&"vip"` — when `protectee_path` is empty it guards the first node in this group, so a spawned squad can arrive guarding a VIP via `EncounterSpawner.attach_scenes`).
- **`CutsceneActor`** (`cutscene_actor.gd`, `@tool`, plain `Node`) — drop **UNDER an NPC** (or point `npc_path` at one) to let a `Cutscene` STAGE it: `WALK_TO` a marker, `FACE` a target, `PLAY_ANIM` — with the NPC's AI brain SUPPRESSED so it won't fight the scripted blocking. Control is auto-released when the cutscene ends, so the NPC can never be left frozen. Knobs: `npc_path` (empty = parent), `animation_player_path` (optional; procedural `BodyModelSwap` actors leave it empty and `PLAY_ANIM` is a no-op). API: `begin()` / `walk_to(point)` / `face(point)` / `play_anim(name)` / `end()`. See **"Triggers, encounters & cutscenes."**
- **`InvestigatePoint`** (`investigate_point.gd`, `@tool`, `extends Marker3D`) — a "go look here" beacon: call `trigger()` (from a `TriggerVolume` `action = &"trigger"`, or a cutscene `CALL_METHOD`) to send an NPC to investigate THIS marker's position (its no-target GOAP Investigate). Knobs: `npc_path` (a specific NPC; empty = every NPC in the `&"npc"` group within `radius`), `radius` (default `20.0`), `alerted` (true = the alerting "!" sting, false = a quiet "come look"). Works regardless of the global stealth-sense flags — it's a scripted command, not ambient sensing.

**Player abilities** (all `extends Ability`, `rpg/scripts/components/abilities/`) — drop under a Player; the node's **presence** grants the mechanic, stack as many as you want. **`Grapple`** (the grappling hook, owns its rope config `.tres` via `config: GrappleHookResource`), **`WallClimb`** (owns its climb tuning, e.g. `climb_hop_up` / `climb_hop_forward`), **`Slide`**, **`AirDash`**, **`FallImmunity`** (passive -- its presence makes hard landings cost no HP; no behaviour hooks), **`SilentTakedownAbility`** (`silent_takedown.gd` / `SilentTakedown.tscn` -- grants `&"silent_takedown"`, the chip-gated stealth-kill verb; normally installed via the Takedown Chip at a `ChipInstaller`, see "Stealth and detection"), and **`ChessVisualizer`** (the Board Visualizer chip for the blindfold-chess minigame -- its presence lets the hidden board render). Each inherits `enabled` from `Ability` (off → temporarily revoked without removing the node). These are usually *granted* via an `UpgradePickup`, but you can pre-attach them to start the player with the mechanic.

**Ambience & titles:**

- **`SkyTitle`** (`sky_title.gd`) — a depth-tested "drawn in the sky" title card that the skyline occludes; fades in on a music cue. Drop ONE under the Game root. Knobs: `text` (default `"CYBER SUNDAY"`), `cue_seconds`, `fade_in_time`, `hold_seconds`, `fade_out_time`, `sky_distance`, plus size/colour knobs (`pixel_size`, `font_size`, `text_color`, `vertical_stretch`) and a `test_show_immediately` preview toggle.
- **`AmbientDust`** (`ambient_dust.gd`, `extends GPUParticles3D`) — level-wide floating motes that re-centre on the camera. Drop ONE anywhere. Knobs: `motes`, `mote_lifetime`, `volume_extents`, `mote_size` (plus `mote_color`, `drift`, `turbulence`).
- **`AmbientSound`** (`ambient_sound.gd`, `@tool`, `extends Node3D`) — a looping ambient bed (wind, machine hum, crowd murmur, a flickering-light buzz). Drop it where the sound lives, assign a `stream`, done: it auto-creates a child `AudioStreamPlayer3D` on the **`ambient`** bus (so the Ambient volume slider governs it, NOT Master) and loops forever. Knobs: `stream` (empty = silent + warning), `volume_db`, `bus` (default `&"ambient"`), `loop` (off = one-shot establishing cue), `autoplay` (off = call `play()` from a trigger/cutscene), `max_distance` (0 = engine default), `unit_size` (falloff, default `10.0`). API: `play()` / `stop()` / `is_playing()`. See **"Looping ambience & audio zones"** in the Atmosphere chapter.
- **`AudioZone`** (`audio_zone.gd`, `@tool`, `extends Area3D`) — while the player is inside this volume a child sound cross-fades IN; on exit it fades back OUT (a bar's music, a reactor-room tone, a PA loop). Drop the area over a region, give it a `CollisionShape3D` child AND an `AudioStreamPlayer` / `AudioStreamPlayer3D` child on a non-Master bus. Knobs: `trigger_group` (default `&"Player"`), `active_volume_db`, `inactive_volume_db` (a near-silent floor, default `-40`), `fade_speed` (dB/s, default `24`), `autoplay`. Runs on `PROCESS_MODE_ALWAYS` (fades through a pause) and ref-counts bodies so overlapping zones don't double-toggle. API: `is_active()`.
- **`MusicDirector`** (`music_director.gd`) — dynamic music: the parent track plays constantly but stays silent in exploration, fading IN for combat and **sustaining, ducked, through the CAUTION phase** while an enemy is still hunting you. A playing in-world `Radio` the player can hear takes precedence (`yield_to_radio`), holding the dynamic bed silent so the radio carries the moment — for both combat and dialogue. Drop as a **child of the music `AudioStreamPlayer` / `AudioStreamPlayer3D`** (an `AudioStreamPlayer2D` parent is also accepted); it captures the parent's `volume_db` as the audible level.
- **`WanderMusic`** (`wander_music.gd`, `extends AudioStreamPlayer`) - the quiet **exploration** bed, and the exact complement of `MusicDirector`: it plays while nobody is fighting, hunting, talking, standing at a terminal or within earshot of a diegetic `Radio`, and fades out the instant any of those takes the moment. Already authored in `scenes/game.tscn` under `Player`; you only author the playlist in `resources/tuning/WanderMusicSettings.tres`. Everything is tuned there rather than on the node, because there is exactly one of it. See section 1e.
- **`DetectionStinger`** (`detection_stinger.gd`, `@tool`, plain `Node`) — drop under an `AudioStreamPlayer` / `AudioStreamPlayer2D` / `AudioStreamPlayer3D` whose stream is the one-shot "you've been seen" cue. It polls for an NPC first locking onto the player, plays on the rising edge, then re-arms after combat ends. Knob: `cooldown`. **Authored nowhere yet, by design** — the drop-in is ready; place it under an `AudioStreamPlayer` with an authored sting clip (`game.tscn`, beside `MusicDirector`, is the natural home).
- **`RewardStinger`** (`reward_stinger.gd`, `@tool`, plain `Node`) — the positive mirror of `DetectionStinger`: drop it as a **child of an `AudioStreamPlayer` / `AudioStreamPlayer2D` / `AudioStreamPlayer3D`** whose stream is the reward sting (leave that player non-autoplay, non-loop — the stinger calls `play()` itself) and it fires when a quest completes and/or the player levels up. Signal-driven, not polled. Both this node **and** the parent audio player are forced `PROCESS_MODE_ALWAYS`, so the sting still plays while the world is paused (a turn-in mid-dialogue, the level-up screen) — a `play()` on a paused INHERIT player is silently dropped. Knobs: `cooldown` (`0.5` s — coalesces a simultaneous quest-complete + level-up into ONE cue), `on_quest_complete` (on), `on_level_up` (on). Parenting isn't optional: an unwired parent config-warns in the editor and the node does nothing. **Authored nowhere yet, by design** — the drop-in is ready; place it under an `AudioStreamPlayer` with an authored sting clip (`game.tscn`, beside `MusicDirector`, is the natural home).
- **`NoiseSource`** (`noise_source.gd`) — a point of sound NPCs can hear and investigate (the stealth distraction channel). Knobs: `radius`, `decay`, `lifetime` (persistent when both `decay` and `lifetime` are 0; a self-freeing one-shot otherwise). Runtime-only (not an Inspector knob): `emitter` — WHO made the sound; `NoiseEmitter` stamps the Player on its live source and `NoisePulser` stamps its host, an authored/decoy source is nobody — it decides whether an investigating NPC's "!" reads as "noticed YOU" (2D sting) or a bare point (positional). Inert unless `GameSettings.npc_ai.hearing_initiates` is on.

- **`ShadowVolume`** (`shadow_volume.gd`, `@tool`, `extends Area3D`) — paint this Area3D over a dark region and the player inside reads as UNLIT to enemy `Perception`: it writes a low `light_exposure` while inside and restores `1.0` on exit. The cheap, designer-painted alternative to live light probing (no `Player.tscn` edit — just paint shadows). Needs a `CollisionShape3D` child. Knobs: `trigger_group` (default `&"Player"`), `shadow_exposure` (`@export_range` 0–1; 0 = pitch dark → slowest detection, 1 = fully lit). Needs an enemy `Perception` light curve to bite — `GameSettings.light_stealth` ships one. Don't overlap two on the same spot (the one a body exits LAST wins).

**HUD markers (compass / minimap points of interest):**

- **`WorldMarker`** (`world_marker.gd`, plain `Node3D`) — a point-of-interest beacon: drop it in the world and it shows as a chevron on the `Compass` (screen edge) and a dot on the `Minimap`. Joins the `"compass"` and `"minimap"` groups on `_ready` so both HUD channels pick it up with no wiring. Knobs: `on_compass`, `on_minimap`, `color` (the Compass chevron tint). Place by hand for fixed landmarks (a vendor, an exit, a stash). The minimap half works out of the box (the HUD ships one, §16); the `Compass` half still needs a `Compass` Control on the HUD.
- **`QuestMarkerSync`** (`quest_marker_sync.gd`, plain `Node`) — drop ONE into a level: it spawns a `WorldMarker` for each ACTIVE quest objective that has `show_marker`, and removes them as objectives complete / quests finish or fail — so the Compass + Minimap point at your current objectives with NO per-quest wiring. Driven by `GameState`'s quest signals. Knob: `marker_color`. **`LevelTemplate.tscn` already ships one**, so a level started from the template needs nothing; add one by hand only to a level built another way. Pairs with the per-objective `show_marker` / `marker_position` exports (§14).
- **`MinimapHide`** (`minimap_hide.gd`, plain `Node`) — child it under a prop (fence, awning, parked car, pipe run) to keep that prop's colliders out of the HUD minimap's wall cut; collision is untouched. **Marks its PARENT, not itself**, so it must be a child of the prop. Knob: `enabled`, read once at level load (see §16).
- **`Compass`** (`compass.gd`, `extends Control`) — a screen-edge compass HUD: for every `WorldMarker` (anything in the `"compass"` group) it draws a dot at its on-screen position when visible, else a chevron pinned to the screen edge pointing toward it. Add it to the HUD (`res://scenes/player/ui.tscn`) as a full-rect Control. Knobs: `edge_margin` (px the edge ring is inset, default `28`), `marker_size` (px radius, default `6`), `max_distance` (hide farther markers; 0 = no limit).

**Death & gore drop-ins:** **`BodyPartGibs`** (`body_part_gibs.gd`, plain `Node`) — per-actor control over the **body-part death burst**: the character coming apart into its OWN head, torso, arms and legs (the LEGO/Roblox read) instead of only spraying generic meat chunks. **You do not need to place this node** — the burst is already ON for every actor that has a `BodyModelSwap`, governed globally by `GameSettings.effects` → **Body-part gibs**. Drop it under a Character (a DIRECT child of the root — that's where it's looked for) purely to override that for one actor: untick **`enabled`** to leave a boss/quest NPC in one piece, or tick it to gib one actor while the global switch is off. Also picks **which** parts fly (`burst_head` / `burst_torso` / `burst_arms` / `burst_legs` — arms and legs are one pair each), how much loose gore goes with them (`meat_gib_count`, `-1` = inherit the global, `0` = parts only), how hard they're flung (`launch_speed_scale`), and an optional replacement chassis (`part_gib_scene`). The flying parts need no art: their visual is lifted live off that actor's `BodyModelSwap`, skin and tint included.

**Mostly auto-wired (rarely hand-placed, but they are `class_name` components):** **`LootBag`** (`loot_bag.gd`, `extends Throwable`) — the default on-death drop assigned to the enemy's `ragdoll_scene` (`scenes/props/loot_bag.tscn`): a physics bag that falls and rests on the floor on its own, carries the dead actor's loot, and — being a Throwable with a `LootableCorpse` child (a "dual item") — can be looted (aim + Interact) or picked up / thrown. By default (`spawn_only_with_loot`) it doesn't spawn at all when the dead actor has nothing to loot — no items and no cash — so an empty-handed kill leaves no bag; turn that off to always drop one. Keep `destructible = false` so a stray shot can't burst it and lose the loot; **`Ragdoll`** (`ragdoll.gd`) — the alternative drop for that same `ragdoll_scene` slot, a physics-skeleton corpse that needs a one-time editor setup (Create Physical Skeleton on a rigged `.glb`, then assign the scene); **`Explosion`** (`explosion_area.gd`, `extends Area3D`) + **`ExplosionMesh`** (`explosion_mesh.gd`) — radial blast prefab; **`ShellDrop`**, **`MuzzleFlash`**, **`SparkAttack`**, **`MuzzleSmoke`** (the little white cartoon puff off the barrel — same muzzle marker and same `Attack.flash_muzzle` signal as the spark, but a CONTINUOUS emitter gated by a hot-barrel countdown rather than a one-shot burst. It simulates in LOCAL space (`local_coords`), i.e. WELDED to the muzzle: world space looks right standing still and loses the whole cluster behind the camera the moment you advance, and `inherit_velocity_ratio` does not rescue it. It is ~40 small camera-facing quads wearing a disc-with-a-soft-rim `GradientTexture2D` at a per-puff alpha of 0.42, so the puffs read INDIVIDUALLY as a cartoon cluster rather than fusing into a realistic haze; count and alpha must be tuned together, since hundreds of faint puffs give haze and a few hundred at middling alpha give a solid-white ball. Its whole envelope rides the emitter's `amount_ratio`: a short `muzzle_smoke_delay` (~0.05 s) so it reads as its own event rather than part of the muzzle flash, then SWELL IN over `muzzle_smoke_attack`, hold for `muzzle_smoke_hold`, PETER OUT over `muzzle_smoke_taper`. ⭐Both soft ends matter — a long delay plus emission snapping to full flow pops a whole cluster of puffs into existence in one frame, which is jarring in a different way than blooming on the flash, so the delay stays short and the onset stays soft. The quad is deliberately NON-square with a random per-particle `angle`, so the puffs are randomly-rotated ellipses rather than a clump of identical spheres. Judge it with `scripts/tools/muzzle_smoke_qa_shots.gd` — a windowed run that equips a gun, fires, walks, and photographs the barrel; no headless test can see this effect at all); and the gun-rig effects in `scripts/effects/` (**`GunMesh`**, **`GunVisuals`**, **`GunPose`**, **`MuzzleRig`**, **`WeaponModelSwapper`**, **`BloodSplatter`**, **`BloodDropEmitter`**, **`ParticleTimeBind`**) — these are internal to weapon/character prefabs; you tune their `@export`s but don't drop them onto level geometry.

**Encounters & cutscene drivers (plain nodes, no prefab — fired by a `TriggerVolume`):**

- **`EncounterSpawner`** (`encounter_spawner.gd`, `@tool`, `extends Node3D`) — spawns enemies on cue from `SpawnDefinition` rows; adds them as **siblings** (parent it under `Characters`). Knobs: `spawn_definitions`, `spawn_points` (exact `Marker3D` placement, cycling, vs. random scatter), `attach_scenes` (a behaviour node — `GuardDuty`/`PatrolBehavior`/`CutsceneActor` — added under every spawn). API: `trigger_spawn()` / `trigger_spawn_wave(i)` / `alive_count()`; signals `spawned` / `cleared` / `alive_count_changed`. Fire it with `action = &"trigger_spawn"`. See **"Triggers, encounters & cutscenes."**
- **`WaveManager`** (`wave_manager.gd`, `@tool`, plain `Node`) — sequences an `EncounterSpawner`'s definitions as timed waves. Knobs: `spawner_path`, `wave_interval`, `auto_start`. API: `start()` / `is_running()` / `wait_for_clear()`; signals `wave_started` / `all_waves_done`. Drive it with `action = &"start"`. No prefab.
- **`CutscenePlayer`** (`cutscene_player.gd`, `@tool`, plain `Node`) — runs a `Cutscene` (camera moves, fades, captions, dialogue, actor blocking) with player control LOCKED, restoring it (and the gameplay camera) at the end or on Escape. Knob: `cutscene`. API: `play()` (no-arg, for a trigger) / `play_cutscene(c)`; signals `cutscene_started` / `cutscene_finished`. Drive it with `action = &"play"`. No prefab.
- **`PlayerLightLevel`** (`player_light_level.gd`, `extends Node3D`) — the live alternative to `ShadowVolume`: drop it as a **child of the player** and it auto-discovers every `Light3D` in the running scene (no group tagging) and samples them each tick, writing the player's `light_exposure` (dark → slower enemy detection). Zero-config — `host` auto-wires to the parent. Knobs: `host`, `ambient` (`0.2` base light), `sample_interval` (`0.1` s), `require_los` (`true`, lamps blocked by geometry don't count), `auto_collect` (`true`; turn it **off** to read only the curated `&"lights"` group instead), `recollect_interval` (`2.0` s between rescans, `auto_collect` only), `directional_contributes` (`true` — a `DirectionalLight3D` sun/moon adds its energy globally; turn it **off** for a SUN-LIT level, or the sun pins the meter to fully-lit everywhere and darkness can never help), plus the **Carried light** pair `carried_light_radius` (`3.0` m) / `carried_light_full_energy` (`1.0`) that drive the second field it writes, `carried_light` — the flashlight beacon penalty, scanned from the `&"carried_light"` group. Absent → player stays fully lit and carries nothing (purely additive). See **"Stealth and detection."**
**Spectacle & hazards (shoot it, stand in it, trip it):**

- **`ExplosiveBarrel`** (`explosive_barrel.gd`, `@tool`, `extends CanDestroy`) — a destructible that **DETONATES when destroyed**: shoot it (or catch it in another blast) and it spawns a damaging explosion at its spot, then breaks like any `CanDestroy`. Use it as the root of a barrel/fuel-tank prop with a `CollisionShape3D` + `MeshInstance3D`, exactly like `CanDestroy`. It inherits the `CanDestroy` knobs (`max_hp`, `destroy_effect`, `destroy_sound`) and adds a **Blast** group: `blast_force` (`20.0`, peak radial push at ground zero, falling to 0 at the rim — also sizes the explosion's feel), `blast_radius` (`4.0` m, the reach + push/damage falloff), `blast_upward_bias` (`@export_range` 0–1, default `0.1`; `0` = a flat outward shove, `1` = a pure vertical pop). **CHAINING is free** — the blast's Area3D damages every overlapping body, so a nearby `ExplosiveBarrel` is destroyed and detonates in turn (a frame later, never a synchronous recursion; a destroyed barrel can't re-trigger). The player who shot the first barrel is **credited through the whole chain** (the attacker rides each blast as the instigator), so a barrel kill counts as yours and provokes the right faction. The flash/SFX come from the shared explosion prefab plus your `destroy_effect` / `destroy_sound`.
- **`HazardZone`** (`hazard_zone.gd`, `@tool`, `extends Area3D`) — a damage-over-time volume: while a body stands in it, it takes periodic damage (fire, acid, radiation, a gas cloud) and optionally a status effect. Drop the area over a region, give it a `CollisionShape3D` child, and set the ticks. Knobs: `damage_group` (default `&""` = ANY body with `take_damage` — fire burns everything; set a group to scope it), `damage_per_tick` (`1.0` HP per tick — **`0` = a status-only zone**, no HP loss), `tick_interval` (`0.5` s; the first tick lands one interval after entering), `on_tick_effect` (an optional `StatusEffect` applied to a `Character` each tick — burning / poison / slow; refreshes by id so it lingers a beat after you leave; null = damage only). **AMBIENT by design:** the damage is attributed to NO ONE, so standing in fire never provokes a faction or credits a kill — it's pure environmental danger. The zone auto-detects bodies on every physics layer, so you never match mask numbers. (Knocking an enemy *into* one with a blast is free — it just takes the ticks.)
- **`AlarmPanel`** (`alarm_panel.gd`, `@tool`, `extends Node3D`) — a tripwire alarm: trip it and it (1) fires a reinforcement wave from a wired `EncounterSpawner`, (2) turns a whole faction hostile to the player, and (3) optionally sounds a klaxon. **ONE-SHOT** — a second trip is a no-op, so the wave can't be farmed. Knobs: `spawner_path` (a `NodePath` to an `EncounterSpawner` whose definitions are the reinforcements; empty = aggro only, no wave), `alarm_faction_id` (a faction dropdown auto-populated from `res://resources/factions/`, like the NPC/`NpcData` one — the faction that turns hostile on trip; empty = no faction aggro), `alarm_sound` (an `AudioStream` klaxon at the panel; null = silent). Trip it however you like: wire a `TriggerVolume` (`action = &"trip"`, `target` = the panel), have a guard call `trip()`, or hook it to an interactable. API: `trip()` / `has_tripped()`. **The reputation penalty is applied EXACTLY ONCE** when it trips (not once per NPC), so sounding the alarm on a big squad doesn't multiply the standing hit — every member flips hostile but the provoke is a single rep drop.
- **`RentCollector`** (`rent_collector.gd`, plain `Node`) — a recurring money sink tied to `WorldClock`: it serves a one-shot `notice_message` stating the terms on the first dawn, lets `grace_days` dawns pass free, then every `period_days` dawns charges `rent_amount` zorkmids without ever pushing the wallet below zero, emitting `notice_served`, `rent_paid` or `payment_missed` so you can wire eviction, reputation, or warning beats. Inert while `rent_amount` is 0. Knobs: `rent_amount`, `period_days`, `grace_days`, `notice_message`, `paid_message`, `missed_message`. **Arming it without a notice is an authoring bug** — see its section for why.
- **`DayNightSky`** (`scripts/effects/day_night_sky.gd`, plain `Node`) — the VISUAL half of `WorldClock`. ⭐The authored look is the RESTING STATE: a bare node leaves the day byte-identical to the authored scene (sun direction/colour/energy, sky, ambient all untouched at noon) and adds only the NIGHT — energy and ambient ease down after dusk, the sun goes off below the horizon. The arcing sun (`drive_sun_rotation`), colour ramp (`sun_color_gradient`), and day-brightened sky (`drive_sky`) are opt-in knobs. Drop one anywhere in a level (the main level authors one); it auto-finds the sun and env. See **"The day/night clock and NPC routines"** for the full knob list, and `MyLight.night_only` for streetlamps that douse by day.


### Worked example: a shoot-to-break crate that drops a pistol

1. Add a **`CanDestroy`** node (it's a `StaticBody3D`); give it a `CollisionShape3D` + `MeshInstance3D` (your crate mesh). Set `max_hp = 3`, assign `destroy_effect` (a debris VFX scene) and `destroy_sound`.
2. As a **child** of that `CanDestroy`, add a **`SpawnOnDestroy`** node. Set `spawn_scene` to a `CanPickUp` prefab and `count = 1` — or, for randomised drops, assign a `loot_table` `.tres` instead (it rolls and stamps each item onto a copy of the pickup, and sets `build_model_from_item` on each so the rolled item shows its own world model).
3. Optionally also child a **`Lock`**? No — that's for openables, not breakables. If you want cash to scatter, add a separate **`SpawnOnDestroy`** with `spawn_scene` set to a configured `MoneyPickUp` prefab. Do not put `MoneyPickUp` in a `LootTable`; loot-table rows are `Item` resources, and the table path stamps them onto `CanPickUp`.
4. Run. Shoot the crate 3 times → it plays the VFX/sound, frees itself, and the pickup drops into the level (`current_scene`, so it outlives the crate) where the player can aim at it and press F.

### Gotchas

- **Some components have a global gate, not just a local toggle.** `NpcHeadLookMount` (`GameSettings.npc_ai.head_look`) and `NoiseSource` (`GameSettings.npc_ai.hearing_initiates`) are gated by a registry flag in `NpcAiSettings.tres`. The **shipped `NpcAiSettings.tres` turns the whole stealth/reaction layer ON** (`body_discovery`, `hearing_initiates`, `hearing_occlusion`, `music_reactions`, `head_look` all `true`), so a head-look mount, a `Radio`'s NPC reactions, and a `NoiseSource` lure are all live by default. The script defaults in `NpcAiSettings.gd` are `false`, so clear the override or flip a flag off in the `.tres` to disable a layer for a quieter playtest.
- **Parent matters.** `SpawnOnDestroy` and `MusicDirector` connect to / read their **parent**, so they must be a *child of the right host* (a `CanDestroy` / `Throwable`, or the music player). `Lock` must be a child of the interactable it guards (it's discovered via `Lock.of(host)`, which scans the host's children).
- **Size the hitbox.** Look-at interactables only respond where their `CollisionShape3D` covers — if E does nothing, the shape is too small or missing. Set `auto_fit_collider = true` to fit it to the host's meshes (at runtime for any interactable; the `@tool` dual-mode stations — `Merchant`/`Healer`/`Bonfire`/`LevelUp`/`Radio`/`ItemContainer`/`PerkStation` — also preview-resize an *existing* collider live in the editor and persist it on save, so author a `CollisionShape3D` first for the editor preview to size).
- **The two "build their own body" pickups vs. CanPickUp.** `MoneyPickUp` and `UpgradePickup` build their default coin/emblem only when `highlight_target` is left **null/unassigned**; assign a `highlight_target` (or a `world_model`) and they use your authored model instead. `CanPickUp` is different: it builds its visual when you tick **`build_model_from_item = true`** — from the `item`'s `world_model` if it has one, else a built-in glowing placeholder box so the pickup is **never invisible** (matching the MoneyPickUp/UpgradePickup fallbacks). It doesn't key off `highlight_target` at all. Leave `build_model_from_item` off and author the body yourself (under the node, or via `highlight_target`).
- **Dual-mode stations** (`Merchant`, `Healer`, `Bonfire`, `LevelUp`, `ChipInstaller`, `ChessMatch`): set `standalone = false` when the station lives on a dialogue NPC, or the interaction ray will grab the station instead of letting the NPC's `Talkable` drive the conversation.

Relevant files (all under `res://scripts/`): mostly `components/*.gd`, `components/abilities/*.gd`, `effects/*.gd` (base class `components/look_at_interactable.gd`), plus a few that live in their own folders — `world/player_spawn.gd` (`PlayerSpawn`), `ui/compass.gd` (`Compass`), and `player/player_light_level.gd` (`PlayerLightLevel`).

---

## Global tuning (GameSettings) and the settings menu

Most of CYBER SUNDAY's "feel" numbers — how fast you run, how wide the FOV is, how hard explosions shake the screen, how gory a death is, how NPCs investigate noise — do **not** live in scripts. They live in a set of authored Resource files under `res://resources/tuning/`, and a single autoload exposes them to the whole game. This is the **global tuning** layer: numbers that apply everywhere, edited entirely in the inspector.

This is distinct from per-instance tuning (an `@export` you set on one node in one scene) and from content (`.tres` like `Item`, `NpcData`, `Loadout`). Use a tuning group when a number is **the same across the whole game** and you want one place to dial it.

### The registry: `GameSettings`

`rpg/managers/GameSettings.gd` is an autoload (a Node that's always loaded). It does one job: it `preload()`s every tuning `.tres` and hangs it off a named property. Every system in the game reads its numbers as `GameSettings.<group>.<field>` — for example the player reads `GameSettings.player_movement.max_speed`, the camera reads `GameSettings.camera.default_fov`. You never touch that code; you just edit the `.tres` the property points at.

The groups, the property name, the file, and what each governs:

| `GameSettings.` property | Resource file (`res://resources/tuning/…`) | Governs |
| --- | --- | --- |
| `player_movement` | `PlayerMovementSettings.tres` | Run speed (`max_speed`), backward / strafe / **slow-walk** (`walk_speed_mult`) multipliers, jump velocity, coyote-time & jump-buffer windows, ground/air accel smoothing, footstep cadence + speed-scaled footstep volume (`footstep_slow_volume_db`), landing-impact divisor + the long-fall kill (`max_continuous_fall_time`), the **Stairs** step-assist group (`step_up_height` `0.6` / `step_down_snap` `0.65` / `step_min_horizontal_speed` — brush stairs act as walkable terrain without a ramp collider; pairs with the camera's **Stair Smoothing** group), and the whole **Stamina** economy (`max_stamina`, the four `stamina_regen_*` rates + `stamina_regen_delay_after_spend` and the longer `stamina_regen_delay_after_shot` (a shot holds off recovery past the weapon's own firing interval, which is what lets shooting deplete you at all), `stamina_sprint_drain` / `stamina_sprint_lockout`, and the per-verb costs `stamina_jump_cost`, `stamina_grapple_fire_cost` / `stamina_grapple_attached_drain`, `stamina_wall_climb_drain`, `stamina_air_dash_cost`, `stamina_slide_start_cost`, `stamina_melee_attack_cost`, plus `stamina_shot_cost` + `stamina_shot_drain_ceiling` — the per-RANGED-shot price, charged per unit of `WeaponData.stamina_effort()` so a grenade launcher costs 8× a pistol shot automatically, then clamped so no weapon can out-drain sprinting; it is the one cost that never REFUSES its verb, so an empty pool just makes shooting free) — the pool behind every special-movement verb **and every trigger pull**; endurance raises the cap via `Player.stamina_max()` (§22) and the on-screen readout is styled in `hud` — the crosshair **Stamina ring** group by default, the corner **Stamina bar** group when the player opts back into it (Options → Accessibility → "Crosshair Stamina Ring" OFF) |
| `player_crouch` | `PlayerCrouchSettings.tres` | Crouched height ratio, crouch-walk speed penalty, lerp in/out rate, stand-up ceiling clearance, quieter crouched footstep dB |
| `player_lean` | `PlayerLeanSettings.tres` | The Deus Ex / Cruelty Squad **corner-peek** (`Lean`, `scripts/player/lean.gd`): how far the head rig slides sideways (`max_offset`), the camera roll into the lean (`max_roll_deg` — which honours the SAME Options → Accessibility "Camera Tilt" toggle as the strafe roll, so turning it off leaves the peek and levels the horizon), the ease rate (`lerp_speed`), the sideways **Wall Probe** group (`probe_radius` / `probe_margin` / `probe_collision_mask`, default layer 1 = world geometry only, so a passing NPC never snaps your lean back), and the **Gates** group — `allow_airborne` (off) plus `ground_grace` (`0.35` s). ⭐That grace is not cosmetic: every weapon applies `WeaponData.self_knockback` to the SHOOTER on fire, so a shot aimed even slightly downward shoves you up and un-grounds you for a few frames; without the window — and with the airborne gate treated as a HARD refusal — a single trigger pull killed the lean until you released the key. The airborne gate is SOFT: it eases the lean out and straight back, and never drops your hold on the key. **The lean moves the HEAD RIG only — never the collision capsule** — so you expose your view, not your hitbox; the aim origin does lean with you, so you can shoot from the peek |
| `player_aim` | `PlayerAimSettings.tres` | Deus Ex-style aim-wander amplitude by stance (moving loose / standing tighter / crouching tightest), plus the hold-still "settle" that tightens it over time |
| `bunnyhop` | `BunnyhopSettings.tres` | Bhop boost-per-hop (`boost_per_hop`), chain max speed (`max_speed`), the re-hop grace window (`land_window` — the only window; the legacy crouch-gated input window is gone), and the speed-based look-sensitivity falloff (`sens_reduction_threshold` / `sens_min_multiplier`) |
| `camera` | `CameraSettings.tres` | `mouse_sensitivity` (radians per **screen** pixel — `MouseInput` reads `InputEventMouseMotion.screen_relative`, never `relative`, which the project's `viewport` stretch mode pre-scales by canvas/window width, so one value feels the same fullscreen, windowed, 1080p or 4K; the default `0.000825` is the old canvas-px `0.002` × 792/1920, and `Settings.SENS_MIN`/`SENS_MAX` + the catalog slider row share the unit — retune all three together), pitch limits, `default_fov` / `scope_magnification` (ADS zoom **strength**, as a magnification over the player's *current* rest FOV — the scoped angle is SOLVED from `default_fov`, so aiming feels the same at 75 FOV as at 120; the absolute `scoped_fov` is the legacy fallback, consulted only when `scope_magnification` is `0`. Tune the magnification, not the angle: an absolute ADS FOV silently strengthens the zoom every time a player widens their FOV slider — at 110 rest a 40° scope is a 3.9× jump instead of the intended 2.1×), dynamic FOV kicks (fall/rise/forward/**sprint**/dash — `sprint_fov_mult`, default `7.0`, is a flat all-or-nothing widen off the Player's stamina-gated `is_sprinting()` that STACKS on the push-scaled `forward_fov_mult`; every cosmetic kick is dropped by Options → Accessibility → **FOV Effects**, and the composed FOV is clamped to 1–179° so an over-tuned mult can't error the view), head-bob, landing dip, a **Stair Smoothing** group (`step_smooth_speed` / `step_smooth_max` — the body snaps up a riser instantly because collision needs the exact position, so this eases the CAMERA over that snap and brush stairs glide instead of jolting the view up per step), strafe tilt, a **Dialogue Camera** group (`dialogue_focus_duration`, `dialogue_frame_height`, `dialogue_min_fov` — how a conversation swings onto and frames the speaker), plus a **Scope (ADS)** group — scoped depth-of-field (`dof_scoped_far_distance`), volumetric-fog thinning (`scoped_fog_density_factor`) and the music duck (`scope_music_duck_db`/`scope_music_duck_time`) for the sniper-scope look/feel |
| `screen_shake` | `ScreenShakeSettings.tres` | Trauma `decay_rate`, master `intensity_multiplier`, death-shake range/amount, the on-kill kick `kill_shake_amount`, explosion shake caps |
| `weapon_general` | `WeaponGeneralSettings.tres` | Weapon-wide (not per-gun): `swap_time`, muzzle-flash duration, ADS spread divisor / speed penalty / range multiplier / **run lockout** (`allow_sprint_while_scoped`, off = you can't sprint while scoped), bullet-time slow-mo, hitstop scaling, tracers |
| `effects` | `EffectsSettings.tres` | Visual FX: decal fade/placement, dust puffs, the on-screen blood overlay, gore gibs & world blood drops (including `clear_player_gore_on_respawn` — whether a checkpoint revive destroys the player's OWN remains), the **Body-part gibs** group (`body_part_gibs_enabled` and the `body_part_gib_*` feel knobs — the burst that flings a dying character's own head/torso/arms/legs), the enemy **Death freeze** beat (`death_freeze_duration` — how long an enemy holds its pose before bursting into gore), the **Thrown weapon trail** group (`throw_trail_enabled` and the `throw_trail_*` shape knobs — the white tracer a thrown weapon drags in flight), explosion visuals, sky/hit flashes, the **Muzzle & Impact FX** group (`muzzle_flash_radius`, `hit_spark_backoff`, `hit_spark_speed_to_scale`, `overkill_burst_radius`), plus the first-person **Gun Holster (view model)** put-away/draw animation (`gun_holster_animation_time` / `gun_holster_position_offset` / `gun_holster_rotation_offset`), and the **World ghost** group (`world_ghost_strength` / `world_ghost_tau` / `world_ghost_dead_zone` / `world_ghost_chroma_px` / `world_ghost_chroma_gain` — the HUD’s phosphor persistence extended very faintly to the picture, `scripts/effects/world_ghost.gd`: a never-cleared offscreen buffer keeps a running average of the finished frame and a full-rect shader adds the DIFFERENCE between that average and the live frame back over it, so the effect exists only where something moved — at rest the average has converged and the composite re-emits the picture unchanged. `world_ghost_dead_zone` is the housekeeping knob that makes that exact rather than approximate; `world_ghost_chroma_px` splits the trail’s red and blue either side of green along the direction of motion, which is what keeps it in the same family as the HUD’s coloured ghost without painting the world. Keep the strength LOW — it ships at 0.12 against the HUD ghost’s 0.32, and a full-screen trail over an already-posterised frame turns to smear fast. The player scales it via Options → Accessibility → "World Ghosting") |
| `audio` | `AudioSettings.tres` | **The per-play pitch variation for WORLD sounds (`global_pitch_spread`)**, landing thump, **player footstep pitch spread + master volume trim**, falling/fast-move wind swell, bullet/muzzle whiz pitch, impact & enemy-hit-by-HP pitch, NPC-fired impact volume (`npc_impact_volume_db`), ammo-driven fire pitch |
| `physics_damage` | `PhysicsDamageSettings.tres` | Explosion damage, blast decay, ram/body-check, character-vs-rigidbody push, pickup/throw impact behaviour |
| `economy` | `EconomySettings.tres` | Every bounty, trick-shot reward, and seed value (zorkmids are fractional), plus the **Long-range kills** group (`long_range_*` — the marksman bounty for a distant kill, see callout below), `restock_interval` (group **Restock**, for fixed vendor stock / container item rows only; it does not re-seed container money or re-roll loot tables), the **Death** group (`death_purse_*` — what happens to your zorkmids when you die; see the callout below) and the **Starting credit** group (`credit_*` — New Game's implant-purchase bank, *the Underwriting Sheet*: the creation build is rated `credit_score_min`..`credit_score_max` off the authored **`credit_underwriting`** actuarial table (one `StatUnderwriting` row per stat) across four lines — CAPACITY, VIABILITY, TRADE minus EXPOSURE — weighted by `credit_weight_*` over a `credit_baseline_fraction` floor, and the score earns a spending limit up to `credit_limit_max` (shipped **2100 zm**) shaped by `credit_limit_curve` in `credit_limit_step` round-number quotes; `credit_band_*` name the verdict tiers and `credit_reason_*` set the per-line minimums the filed reason cites. Set `credit_score_min` equal to `credit_score_max` to switch the credit check off — every build then rates the full cap. See the callout under *Starting implants* below) |
| `player_feedback` | `PlayerFeedbackSettings.tres` | The hurt/death/spawn arc: hit slow-mo + muffle, red hurt flash, damage thud, death cinematic, the **death sting** (`death_sting*` + `death_cinematic_buses` / `death_world_residue` — the world duck the sting rides over, see §the death sting), respawn/spawn fade, dash-recharge & kill flashes, plus the **toast colours** — `sneak_toast_color` (green, the "Sneak Attack!" pop), `cripple_toast_color` (red, the limb-cripple notice), `death_wallet_toast_color` (amber, the death wallet-settlement line shown on the respawn — "your killer took it" / "it's on the ground where you fell") and `sneak_toast_cooldown_ms` (1200 ms, so a multi-pellet sneak shot shows one line, not one per pellet), plus the **Out-of-combat recovery** tail — `combat_calm_grace` (6.0 s of quiet before you count as out of combat; keep it above GunPose's 5.0 `idle_combat_grace` so the gun visibly drops FIRST), `health_regen_frac_per_sec` (0.012 = ~83 s empty-to-full, authored as a fraction of max HP so the pace doesn't drift as `max_hp` grows; 0 = feature off), `health_regen_cap_frac` (**the economy dial** — 1.0 regenerates you to full, ~0.5 leaves the last chunk for a Bonfire / Healer / health pack), `health_regen_commit_frac` (signal hygiene, not feel: how much HP banks before a `damaged` emit) and `heartbeat_calm_duck_db` (4.0 dB quieter low-HP heartbeat once things calm down — volume only, the beat RATE is untouched). The regen rate scales with ENDURANCE (`CharacterStats.hp_regen_mult`, +10%/point) |
| `npc_ai` | `NpcAiSettings.tres` | Species-wide NPC brain dials: retarget interval, engage/point-blank ranges, self-care, companion follow, the **Home return (leash)** group (`home_return` + `home_return_on_player_death` / `home_return_death_delay` / `home_return_off_screen` / `home_return_off_screen_delay` / `home_return_requires_calm` / `home_return_slack` / `home_return_blink` — NPCs go back to their authored post when the player dies or after they've been off-screen; seeds every auto-built `NpcHomeReturn`, ships ON), scavenging, holster **de-escalation** (`holster_forgiveness_once` — a provoked NPC is holster-forgiven at most once per life, ships ON, and binds fleers too — the brief `fleeing_always_forgivable` exemption was removed as an exploit; `deaggro_on_player_death` — an NPC that KILLS the player drops a grudge it holds only because it was provoked, applied on the respawn and without spending the one-shot latch, ships ON), the stealth/reaction toggles (`body_discovery`, `hearing_initiates`, `hearing_occlusion`, `music_reactions`, `head_look` — all ship ON in the `.tres`; the `music_turn_body` sub-toggle for the face-the-radio body yaw ships ON via the script default), and the **AI level of detail** group (`lod_enabled` / `lod_near_distance` / `lod_far_distance` / `lod_mid_interval` / `lod_far_interval` — how often a distant, unaware NPC re-runs its brain; seeds every auto-built `AiLod`, ships ON — see **"Crowd cost: AI level of detail."**) |
| `npc_bark` | `NpcBarkSettings.tres` | NPC voice CADENCE (not the lines — those are `BarkSet` content, §21): how far a bark carries (`bark_distance`), how often each NPC barks / greets (`bark_cooldown_ms` / `greet_cooldown_ms`), the `search_bark_delay` grace (seconds of sustained searching before the "still around here somewhere…" hunt mutter first fires, so a one-second loss of sight doesn't blurt it instantly), the death-witness radius, the low-HP `hurt_bark_hp_frac` cry threshold, and the detection-sting throttles (`alert_cooldown_ms`, `aim_cooldown_ms`, `aim_sfx_delay`) |
| `npc_audio` | `NpcAudioSettings.tres` | The NPC combat-audio MIX: per-cue volumes (dB) + random pitch ranges for the MGS "!" **detection sting** (`alert_volume_db` — played **2D, no distance falloff**, when it's the PLAYER the NPC just noticed, so you hear it perfectly wherever the spotter is; `alert_volume_db_vs_npc` — played positionally at the spotter when it noticed another NPC), the aim/charge sting, the incoming-shot beep, and the miss ricochet |
| `reputation` | `ReputationSettings.tres` | Faction-standing penalties and the HOSTILE / FRIENDLY thresholds (NEUTRAL is the band between them) |
| `distraction` | `DistractionSettings.tres` | Default noise of a thrown decoy (the "lob a rock to lure a guard" verb; inert unless `npc_ai.hearing_initiates` is on) |
| `search` | `SearchSettings.tres` | How an NPC HUNTS a lost target / noise: the uncertainty ring (`max_search_radius`, `uncertainty_grow_rate`, `min_search_radius`, `sample_points`, `crumb_timeout`), per-stimulus seeds (`noise_radius_scale`, `corpse_radius_frac`, `seed_radius`), and the frantic→resigned `intensity_curve` + dwell (`crumb_dwell_min/max`). The shipped `.tres` overrides `max_search_radius = 10.0`, so a lost-target search already sweeps a 10 m ring out of the box; only `sample_points` is still inert at `1` (a single sample point). Raise `sample_points` (and optionally widen `max_search_radius`) to broaden the breadcrumb sweep |
| `takedown` | `SilentTakedownSettings.tres` | The silent-takedown verb (hold the Takedown key behind an off-guard NPC): `enabled` (master switch), `hold_time` (`3.0` s held to commit — the BASE wind-up at baseline larceny; see the larceny scaling below), `min_hold_time` (`0.3` s floor the larceny-scaled hold can't drop below), `max_range` (`1.5` m melee reach), `behind_arc_degrees` (`120°` rear arc — matches `DamageApplier.is_behind`), the `require_behind` (`true`) / `require_crouch` (`true`) gates, plus the **Audio** group — `takedown_sfx` (the wind-up clip, shipped as the *Hydraulic Press* sound: plays while you hold over an eligible target and is cut the instant you release OR the kill commits; loops to fill a hold longer than the clip) and `takedown_sfx_volume_db`. The actual wind-up a player feels is `hold_time × CharacterStats.takedown_time_mult()` (LARCENY shortens it 5%/point, floored at `min_hold_time`), so a stealthier operator kills quicker. The shipped `SilentTakedownSettings.tres` sets `hold_time = 3.0`, `max_range = 1.5`, `require_crouch = true`, and assigns `takedown_sfx`, overriding the gentler script defaults |
| `dialogue` | `DialogueSettings.tres` | Conversation flow + presentation feel: pre-talk pacing (`npc_turn_to_face_duration`, `talk_prompt_buffer_duration`), intro delay + speaker face-turn (`dialogue_intro_delay`, `dialogue_speaker_face_duration`), the **Auto-advance** group (`auto_advance` true, `auto_advance_seconds_per_char` 0.07, `auto_advance_min_seconds` 1.6, `auto_advance_max_seconds` 9.0 — lines auto-continue after their spoken time, New Vegas style), the cinematic letterbox bars, the music duck while a conversation is up, and the dialogue box layout (panel margins, font sizes, label offsets) |
| `inventory` | `InventorySettings.tres` | The Tetris-style spatial backpack's dimensions: the CHARACTER grid every actor shares — the player AND every NPC (`grid_cols` 6, `grid_rows` 5), so an NPC carries no more than you and the bag it drops matches your grid — plus the roomier grid a persistent **container** (crate/chest) gets when you open it (`container_grid_cols` 10, `container_grid_rows` 8). Bigger = more carry slots; shrink for a tighter Tarkov-style squeeze — but keep the character grid big enough for an NPC's authored loadout to stay tidy (overflow is kept **unplaced** and shown in a click-only overflow strip below the grid, still takeable — no longer unlootable). Per-item *footprints* live on the `Item` (`grid_width`/`grid_height`, §9), not here |
| `light_stealth` | `LightStealthSettings.tres` | The GAME-WIDE light-stealth curve: how the player's light exposure (0 = pitch dark, 1 = fully lit) scales an enemy's detection-fill rate. `dark_visibility` (default `0.25`) is the multiplier at pitch dark when no curve is authored (so a target in shadow fills the meter at a quarter rate); assign a `light_falloff` `Curve` to hand-shape it. Inert until a writer (a `ShadowVolume` / `PlayerLightLevel`) actually lowers exposure below 1.0; an NPC's own `Perception.light_falloff` overrides this per-archetype (§19). ⭐Also holds the **carried-light (flashlight) penalty**, which is LIVE by default because exposure alone saturates and could never charge for a torch: `carried_light_sight_mult` (`1.6`, enemies spot you ~60% further out while your lamp is lit) and `carried_light_detect_mult` (`2.0`, their meter fills twice as fast); both read `1.0` for a target carrying nothing (§19) |
| `pickpocket` | `PickpocketSettings.tres` | The loot-screen PICKPOCKET flow (crouch-interact an off-guard NPC, §22): the catch roll (`base_catch_chance` `0.35` at larceny 0, lowered by `catch_chance_per_point` `0.03`), the free-lift value band (`base_value_allowance` `10.0` + `value_allowance_per_point` `5.0`) and the **value-RISK** slope above it (`over_value_risk` `0.004` catch per zorkmid of overage — value no longer *refuses* a lift, it just makes it riskier, so a microchip is an attemptable gamble whose odds scale with larceny), `equipped_pickpocket_threshold` (`8` — the larceny needed to lift the weapon in an NPC's hands, the one remaining hard refusal), and `caught_witness_radius` (`12.0` m — how far a blown lift rallies nearby enemies to turn and look; `0` = only the victim reacts) |
| `xp` | `XpSettings.tres` | Leveling: `base_xp` (`100`) + `per_level_growth` (`50`) shape the cumulative XP-per-level ramp, `points_per_level` (`1`) is the perk/skill points granted per level crossed, and `xp_per_kill` (`25`) is the flat bounty an NPC kill awards (`0` = kills give no XP). See §22 |
| `hud` | `HudSettings.tres` | The HUD's look + feel on one page — colours, sizes, fonts, timings for the segmented HP bar (`hp_seg_size`/`hp_seg_gap`/`hp_bar_inset` + the `hp_seg_empty`/`hp_seg_fill`/`hp_seg_low` colours, plus the FIXED width budget: `hp_bar_max_width` `232` is the total width the whole bar may occupy at ANY max HP — segments first shrink, then, once they'd dip under `hp_seg_min_width` `4`, consolidate so one drawn cell represents more than 1 HP; the bar never grows past the budget), the stamina readout's TWO modes — the crosshair **Stamina ring** group (`stamina_ring_radius` `14`/`stamina_ring_thickness` `2`, the signed `stamina_ring_start_deg` `180`/`stamina_ring_sweep_deg` `-180` gauge geometry, and the full-pool fade `stamina_ring_idle_alpha`/`stamina_ring_fade_speed` — the SHIPPED default, drawn by `scripts/ui/stamina_ring.gd`; keep radius+thickness/2 under ~25 px or it collides with the aim-warning arcs sharing that centre) and the slim corner **Stamina bar** tucked beneath the HP segments (`stamina_bar_size`/`stamina_bar_gap` — the accessibility fallback via Options → Accessibility → "Crosshair Stamina Ring" OFF); both modes share the `stamina_empty`/`stamina_fill`/`stamina_low` colours and blend between them CONTINUOUSLY with the fill level (`StaminaRing.ring_color` — there is no `stamina_low_frac` snap threshold any more), the readout for the pool tuned in `player_movement`'s Stamina group — the **HUD weight** group (`hud_sway_gain`/`hud_sway_max`/`hud_sway_stiffness`/`hud_sway_damping` + the impact-kick pair `hud_land_kick`/`hud_kick_max` + the body-lean `hud_vel_gain` + the lens-breath pair `hud_fov_scale_gain`/`hud_fov_scale_max` — the corner HUD cluster trails camera turns on a damped spring, `scripts/ui/hud_sway.gd`, leans against strafe velocity, floats on falls / presses on launches, and takes discrete kicks: landings dip the panel via `Ui.hud_land`, while every *rotational* camera event — weapon-fire screen shake, explosions, the ram bounce — rattles it automatically off the camera-basis measurement, no wiring per source; the look + lean targets share the ONE `hud_sway_max` budget. Dynamic-FOV kicks (fall/rise, run, sprint, dash punch) *breathe* the panel's scale toward/away from screen centre on a second spring (ADS scope + dialogue zoom are gated out — they own `fov`); the aim-point annotations never sway, walk-bob/stair-glide are deliberately not coupled, and the player scales the whole effect 0–100% via Options → Accessibility → "HUD Sway"), the **HUD ghosting** group (`hud_ghost_strength`/`hud_ghost_tau` for the persistence half and `hud_ghost_drag_gain`/`hud_ghost_drag_max`/`hud_ghost_drag_response` for the latency half, plus the `hud_ghost_residue_floor` housekeeping cut — CRT phosphor persistence behind the whole HUD, `scripts/ui/hud_ghost.gd`: the HUD is re-rendered into a never-cleared offscreen buffer that fades a little each frame and is drawn BEHIND the live readouts, so anything that moves or changes drags a soft tail and anything that sits still is pixel-identical to a build without the feature. `hud_ghost_drag_max` is THE subtlety knob — the reticle is welded to screen centre, so persistence alone would never show on it, and the couple of pixels the ghost image lags while you turn is the only reason the crosshair participates; set it to 0 for persistence with no double vision at all. The player scales the whole effect 0–100% via Options → Accessibility → "HUD Ghosting", and 0 stops the offscreen pass rendering entirely, so OFF is genuinely free), the **HUD curve** group (`hud_curve_amount` is the bend, `hud_curve_axis_ratio` its shape, plus the `hud_curve_edge_fade` / `hud_curve_chroma` trimmings — the corner instrument panel is rendered into a SubViewport and composited back through a cylindrical warp (`resources/shaders/hud_curve.gdshader`, driven by `ui.gd._apply_hud_curve`), so the panel wraps TOWARD you at its edges — the inside of a curved monitor, not the outside of a CRT bulge. ONLY the `_weighted` carrier goes through it: the reticle, the stamina ring, the directional damage/aim arcs and every other screen-projected annotation stay flat, because they annotate the aim point or a world bearing and a warped one would lie — which is the SAME moved-vs-pinned rule the HUD-weight group already draws, reused rather than re-listed. The bend is FITTED — divided by its own value at the extreme, which pins the corners to the screen corners and bows the edges inward from them — so no readout can ever be pushed off the canvas and `hud_curve_amount` is safe to crank. `hud_curve_axis_ratio` `0` (shipped) is a monitor curved about a VERTICAL axis: horizontal lines bow and every vertical stays dead straight. `1` bends both axes and reads as an eye or a fishbowl instead. The player scales the whole effect 0–100% via Options → Accessibility → "HUD Curve", and 0 TEARS THE VIEWPORT DOWN and hands the carrier back to the layer, so OFF is the pre-curve tree rather than an identity pass), the money readout (`money_font_size`/`money_delta_font_size`, `money_color` plus `money_debt_color` — the red the readout turns while the wallet is NEGATIVE (implants are bought on credit, so a run can start in debt), the `+N`/`-N` gain/loss colours + `money_delta_rise`/`money_delta_time` float), the reputation/notification toasts (`rep_toast_hold`/`rep_toast_fade`/`rep_toast_font_size` + the neutral colour `rep_neutral_color`; the gain/loss toast colours are deliberately **not** knobs here — they come from `CBPalette` (`scripts/ui/cb_palette.gd`), which swaps to a colorblind-safe pair when Options → Accessibility → "Colorblind-Safe Cues" is on), the centred message `hud_font_size`, the reticle (`crosshair_size` plus `hide_crosshair_when_holstered`, ON out of the box — the dot goes away whenever the weapon is stowed, which includes the moment you spawn, since `Player.start_holstered` opens the game holstered; the look-at name readout and every interaction prompt are untouched, so bare-handed play still reads normally, and turning it OFF restores the old permanent reticle), the bottom-left ammo readout (`ammo_font_size` + the low-clip warning `ammo_low_frac`/`ammo_low_color` — it warns at a quarter clip out of the box), the quest surfaces (`quest_toast_color`, the new-quest announcement tint — the complete/failed colours are deliberately NOT knobs, they route through `CBPalette` like the rep toasts — plus the top-right objective tracker's `quest_tracker_color` and its `quest_tracker_width` px column budget, English-measured; long lines wrap downward), the amber save-load caveat toast `load_warning_color`, the centre-screen prompt sizes (`prompt_font_size` — shared by the look-at name and the takedown/pet/claim cues — and the smaller `stealth_font_size` for the persistent `[ HIDDEN ]` badge), the centre-screen meter colours (`meter_bg_color`/`meter_fill_color` for the hold-to-act bars, plus the detection bar's `detection_safe_color` → `detection_hot_color` heat lerp as enemies notice you), the **Enemy health bar** group (the top-centre readout that pops whenever you damage something — `enemy_hp_top` `4`/`enemy_hp_size` `144×8` place it in the ONLY free band above the centre-top prompt stack, `enemy_hp_hold_time` `3.0`/`enemy_hp_fade_time` `0.6` are its self-expiry, `enemy_hp_chip_color`/`enemy_hp_chip_delay`/`enemy_hp_chip_speed` shape the bright "chip" shard that marks the damage a hit just did, `enemy_hp_outline_width`/`enemy_hp_outline_color` are its contrast rim, and `enemy_hp_neutral_color` is the fill for a target with no allegiance — the hostile/friendly/companion fills are deliberately **not** knobs, they come from `CBPalette` like the rep toasts; the track reuses `meter_bg_color`), and the whole **Hotbar** group (nine `hotbar_*` knobs read by `hotbar.gd`: slot size / inset / separation, the key/name/count font sizes, and the empty/filled/equipped slot tints). These are AUTHOR-TIME numbers (a designer tuning group), **not** a player Options row |
| `pickup_beacons` | `PickupBeaconSettings.tres` | The colour-coded pickup ITEM LIGHTS (§9): the per-kind glow palette (weapon / ammo / consumable / passive-buff / chip / money / loot-bag / misc colours), the light itself (`light_energy` `2.2`, `light_range` `3.0` — stealth-exempt, purely cosmetic), the distance fade (fully off at/within `near_distance` `3.0` m, full at/beyond `full_distance` `9.0` m; `max_distance` `0` = never hard-cull), and the loot-sack contents scaling (`bag_min_scale` `0.7` → `bag_max_scale` `1.7` at `bag_count_for_max` `8` stacks — only sack lights scale) |
| `difficulty` | `DifficultySettings.tres` | The Easy/Normal/Hard multiplier set — the live `damage_taken_mult` / `damage_dealt_mult` / `enemy_count_mult` / `loot_mult` / `money_mult` / `xp_gain_mult` (group **Current**, machine-written by `Settings.set_difficulty` → `apply_level()`, so don't hand-edit them; all `1.0` on Normal, i.e. inert) plus the **Easy preset** / **Hard preset** groups (`easy_*` / `hard_*`) a designer actually tunes. Unlike the other rows this one is ALSO a player **Options → Game** row — see **"Difficulty: the live multipliers"** below |
| `station_music` | `StationMusicSettings.tres` | The music a self-serve machine plays out of its own panel speaker while its screen is awake (§1d) — the `tracks` playlist, the `enabled` master switch, `volume_db` / `silent_db`, the `fade_in` / `fade_out` envelope, the `hold_seconds` station-to-station grace window, and the tinny `bus`. WHICH screens play it is NOT here: that is one `station_music` flag per row of the modal registry in `managers/InputManager.gd`. An empty `tracks` makes the whole layer inert |
| `wander_music` | `WanderMusicSettings.tres` | The quiet exploration bed that plays while you are just walking around (1e) - the `tracks` playlist, the `enabled` master switch, `volume_db` / `silent_db`, the `fade_in` / `fade_out` envelope, the `resume_delay` calm window, the `rest_seconds_min`/`max` silence between tracks, `continuous`, and the `bus`. WHAT silences it is NOT here: that is one shared scan (`scripts/audio/soundscape.gd`) plus the flags the other music layers already publish. An empty `tracks` makes the whole layer inert |

> **EconomySettings gained a Restock knob.** `economy.restock_interval` (default `60.0` s) is the fallback period a `Restocker` (the vendor/container refill drop-in, §13) uses when its own per-instance `interval` is left at `0` — i.e. how fast shops and containers replenish fixed authored stock/item rows game-wide. It does not re-seed container money or re-roll loot tables. Override it on the `Restocker` node for a faster/slower single vendor; edit it here to move the global default.

> **EconomySettings gained a Long-range kills group.** An EXTRA zorkmid bounty for a distant kill — the marksman reward. When a character is downed, the killer→victim distance at the moment of death is measured (exact for a hitscan; a close approximation for a projectile, whose shooter has barely moved during flight); a kill at or beyond `long_range_min_distance` (default `30` m — beyond a default NPC's `fire_range`, so you outranged their gun) pays `long_range_bounty` (default `2` zm) **plus** `long_range_bounty_per_m` (default `0.1` zm) for every metre past the threshold, all capped at `long_range_bounty_max` (default `8` zm). Like the collateral / confetti trick-shots it pays **any** killer into its wallet (an NPC sniper banks it too, ready to loot) and toasts only the **player** ("Long-range kill!  42 m  +N zm"). Distance is the only gate, so a melee / point-blank kill (under the threshold) pays nothing and no weapon-type check is needed. **To turn it off**, zero both `long_range_bounty` and `long_range_bounty_per_m` (or raise the threshold out of reach). The payout math is the pure static `EconomySettings.long_range_bonus_for(...)` (unit-tested in `tests/test_managers_tuning.gd`), wired in `character.gd` `_award_long_range_bonus`.

> **EconomySettings' Death group — dying MOVES your zorkmids, it never destroys them.** `death_purse_loss_fraction` (default **`1.0`** — the whole purse) is the share of your wallet that leaves your pocket when you die, and it always lands somewhere you can go and take it back from:
> - **Something killed you** → *they pocket the lot.* It sits in that killer's live wallet, so when you hunt them down it drops in their loot bag as a zorkmids coin tile (`LootableCorpse` seeds it from `money` at their death) — or you can pickpocket it off them. The revive toast names them so you know who to chase.
> - **Nothing killed you** (a fall, a hazard, your own grenade — anything `_resolve_killer` won't credit) → *it spills on the ground* as a physics **money bag** (the same `MoneyBag` a backpack dump makes) at the spot you died, glowing on its loot beacon. Walk back and Interact. Toggle this off with **`death_purse_drops_when_unclaimed`** and an unattributed death simply takes nothing.
>
> Because a fall can kill you in mid-air over nothing, the drop point is a **ladder**: the floor at your feet → a deep probe straight down (**`death_purse_drop_ground_probe`**, default `200` m) → **the last ground you stood on** (for a fall, the ledge you walked off — where a player actually goes to look) → the checkpoint you're about to respawn at (**`death_purse_drop_to_respawn_in_void`**, ON). If every rung misses, the money simply **stays in your wallet** — a bag dropped into a bottomless void would fall forever and be lost, which is worse than not taking it.
>
> **⚠ Go and get it in the SAME SESSION.** This is the one limit to know before you raise the fraction. Neither destination survives a save/load: NPC wallets aren't in any save tier, and a dropped money bag is a dynamic spawn that no tier records either (`docs/CURRENT_ARCHITECTURE.md`, *Save Model* — "loot drops + money bags" are still roadmap). But the *debit* is autosaved the instant it happens (it routes through `add_money`, a save milestone). So dying with 500 zm and then quitting, quickloading, or taking a `LevelDoor` **before** you loot the killer or walk back to the bag destroys the lot — at `1.0` that's your whole purse, where the old 50 % rule left you half. Until money bags and NPC wallets are persisted, either treat recovery as a same-session errand or dial `death_purse_loss_fraction` down.
>
> Two smaller limits. **Your killer has to still be alive when they kill you** — which is normally true, but the 5-second kill-credit window means a *corpse* can be credited (kill a raider, fall off a ledge two seconds later, and that raider is still your "killer"); the settlement checks `is_alive()` and falls through to the ground spill in that case, because a corpse's loot bag was already minted at its own death and money paid in afterwards would be unreachable. After that they must actually **die (or be pickpocketed)** for you to get it back. And **the same kill-credit window can surprise you the other way**: fall off a ledge moments after a raider merely grazed you and that *living* raider is credited, so the money goes in **their** pocket rather than on the ground. Set `death_purse_loss_fraction` to `0` to switch the whole feature off. A `RELOAD_*` `death_mode` takes **nothing at all** — the world is about to be rebuilt, so there'd be no killer left holding it and no bag left lying there, and the save restores your wallet anyway.

### Editing a tuning value in the inspector

1. In the **FileSystem** dock, open `res://resources/tuning/` and double-click the group you want, e.g. `EffectsSettings.tres`.
2. The **Inspector** shows the fields, organised under the `@export_group` headers you see in the table (Decals, Dust, Gore gibs, …). Every field has a tooltip describing exactly what it does and which direction is "more".
3. Change the value and **save** (`Ctrl+S`). Because `GameSettings` preloads that same file, the new number is live the next time you run — no code, no recompile.

**Worked example — make the whole game gorier.** Open `EffectsSettings.tres`. Under **Gore gibs**, raise `gib_count` from `6` to `12` and bump `gib_max_active` from `36` to `64` so the extra chunks aren't reclaimed immediately. Under **Body-part gibs**, raise `body_part_gib_meat_count` from `3` to `8` (that is the chunk count used on a death where the character's own limbs also fly). Under **Blood drops (world)**, raise `blood_drop_count` from `24` to `40`. Save. Done — every bloody-mess death in every scene now bursts bigger, and you never opened a script.

**Worked example — a cleaner, toy-like break-up.** Still in `EffectsSettings.tres`, under **Body-part gibs** set `body_part_gib_meat_count` to `0`. Now a kill throws only the character's actual head, torso, arms and legs, with no loose meat at all — the LEGO/Roblox read. Turning `body_part_gibs_enabled` OFF instead goes the other way, back to meat chunks only (and then `gib_count`, not `body_part_gib_meat_count`, is what governs how many).

### The PIN kill: a thrown blade staples a limb to the wall

Kill someone with a **thrown knife** and the body part it struck is carried into the surface behind them and left stapled there, blade through it, while the rest of the body crumples where it stood. Walk over to pull your knife out and the limb drops off the wall.

It is not a separate effect bolted on — it **re-routes one of the six limbs the death burst already throws**, so it needs body-part gibs on (it inherits the `BodyPartGibs` drop-in's per-actor opt-out for free) and it needs something solid behind the victim. With no wall in range the kill silently plays as an ordinary burst; that is the intended degrade, not a bug.

> **The trigger has to be REACHABLE, and that is a damage question, not an effects one.** The pin only fires on a thrown hit that actually *kills*, so the weapon's thrown damage decides how often anyone sees it. As shipped, the knife's 2.0 base × 3.0 headshot × the 4.0 sneak multiplier against a 14 HP `DefaultCharacterRes` raider means an **unaware headshot throw kills outright** (24), a **finishing throw at a wounded enemy kills at any damage**, and nothing else does — an unaware *body* hit is 8–12, still under 14. If you want the pin to fire more often, the knob is `thrown_impact_damage_mult` on `melee.tres` (`2.0` makes any ambush body throw lethal at 16); if you re-tune enemy HP, re-check that arithmetic or the pin quietly stops happening.

> ⚠️ **The wall probe runs at STRIKE time, in `Throwable._probe_pin_surface`, and it has to.** `PhysicsDirectSpaceState3D` is only valid to query *during a physics frame*, and the death burst is not one — an NPC's `gore()` fires from the death-freeze `SceneTreeTimer`, whose timeout lands on the idle frame, where a raycast returns an empty result no matter what is standing there. The probe therefore happens inside the knife's `body_entered` (a real physics callback) and its answer rides along in the pin marker. This is not a micro-optimisation and moving it "next to the rest of the pin logic" in `GoreSpawner` silently disables the whole feature — that exact bug shipped once, with every seam correct and the probe finding a wall precisely never. `tests/test_pin_kill_integration.gd` guards it by driving the burst from an idle frame.

**Turning it on for another weapon.** One field, on the `WeaponData` `.tres` under **Thrown**: tick `thrown_pins_body_part`. It also requires `thrown_uses_weapon_damage` on the same resource — the pin reads that path's located contact point to know which limb was hit, and the blunt speed-based prop path carries no location at all. `melee.tres` (the knife) is the only weapon that ships with either.

**Tuning it.** `EffectsSettings.tres` → **Pinned body parts**:

| Field | What it does |
|---|---|
| `pinned_parts_enabled` | Master switch. Off = every kill bursts as it did before. |
| `pinned_part_head` / `_torso` / `_arms` / `_legs` | Which limbs are worth stapling. **Head and torso ship ON, arms and legs OFF** — at this game's internal resolution an arm on a wall is a few pixels wide and, with the PS1 vertex snap, reads as a mesh poking through the geometry rather than a trophy. Turn them on if you want every hit to pin. |
| `pinned_part_probe_distance` | How far past the victim to look for a wall. Bigger = fires in more rooms, but the limb flies further to reach one. |
| `pinned_part_probe_mask` | Which physics layers count as a surface. |
| `pinned_part_max_surface_angle` | How far off straight-on a surface may face and still take the staple. This is what rejects a **floor caught by a downward throw** — a limb lying flat on the ground already looks like an ordinary gib that failed to bounce. |
| `pinned_part_flight_speed` | How fast the limb travels to the wall. The flight is the whole point (the player should *see* it carried there), so this is really "how long that reads for". |
| `pinned_part_bury` | How deep the limb sinks in, as a fraction of **its own** thickness — so a head and a forearm bite in by the same proportion. |
| `pinned_part_blade_embed` | How far the blade's tip ends up inside the surface. |
| `pinned_part_lifetime` / `pinned_part_drop_linger` | How long it stays up, then how long it tumbles on the floor before fading. Expiry is also what hands the player's knife back if they never fetch it. |
| `pinned_part_burst_speed_scale` / `pinned_part_meat_count` | **How much the rest of the death is quieted.** At the normal launch speed the wall gets its limb inside a cloud of five more and nobody sees which one behaved differently, so a pin kill flings the other parts at a fraction of the speed and (shipped) sprays no loose chunks at all. Set the scale to `1.0` to turn the quieting off. |

**Worked example — make it fire on every hit.** Under **Pinned body parts**, tick `pinned_part_arms` and `pinned_part_legs`. Now any lethal knife throw pins whatever it hit. Pair it with a longer `pinned_part_lifetime` and a room with walls.

> **Gotchas.** The pinned limb is deliberately **inert** — collision off, so it cannot be shot off the wall, grabbed, or walked into, and it can never block an NPC's line of sight or confuse the editor-baked navmesh. The **knife stays solid**, which is what lets you aim at it and pull it out. And the limb is stapled to a *specific collider*: when that geometry goes (a level change frees the level, but gore lives under the tree root and would otherwise survive it), the trophy goes with it.

### The thrown-weapon tracer: a white streak through the arc

Throw **any weapon** and it drags a **white streak** behind it for the whole flight — a tapering, fading ribbon that shows the arc you actually threw and, when it lands out of sight, where it went. It is the thrown counterpart of the bullet tracer, and like that one it exists to make a fast thing *readable*. (It shipped on the knife alone, on the theory that a tracer on a tossed gun would read as a bug. It doesn't — it reads as a throw — so it is now on the whole roster.)

**Every weapon already has it — the field is an opt-OUT.** One field on the `WeaponData` `.tres` under **Thrown**: `thrown_trail`, which defaults **on**, so a brand-new weapon streaks with no authoring at all. Set `thrown_trail_color` for a signature throw (white by default). Un-tick `thrown_trail` only for a weapon whose flight shouldn't be readable — a decoy you want the player to lose, or a stealth throw that shouldn't paint a line back to where it came from. `tests/test_weapon_data_completeness.gd` pins the whole roster ON, so an accidental un-tick fails the suite rather than quietly shipping one bare weapon.

**Putting one on a hand-placed prop.** The effect is a drop-in: child a **`ThrowTrail`** (`scripts/components/throw_trail.gd`) to any `Throwable` — a spear on a rack, a thrown bottle. Position the child node where the streak should come from (drag it onto the blade's tip; it rides the prop's own basis, so on a prop that noses toward its travel it follows the point). Its four SHAPE knobs (`width`, `lifetime`, `min_speed`, `max_points`) default to `0` = **inherit the global tuning** below, so a dropped-in trail matches every other one until you override one. (`color` is not a shape knob — it defaults to white and has no global counterpart.) `require_thrown` off is the one mode for a prop nothing throws — a hazard launched by a machine — which then streaks purely on speed.

**Only a real throw streaks.** The arm rides the same `is_throw` decision as the thrown facing and the throw sound (`PickupRay._release`, plus the grapple fling), so a knife you tap-drop at your feet, or one released by death/quickload, draws nothing. Landing doesn't cut the streak — the prop simply stops feeding it below `throw_trail_min_speed` and the tail fades out; once it has settled the arm itself is released, so a knife lying where it fell won't streak again if something later blasts or yanks it.

Tuning lives on `GameSettings.effects` (`resources/tuning/EffectsSettings.tres` → **Thrown weapon trail**):

| Field | What it does |
| --- | --- |
| `throw_trail_enabled` | Master switch for every streak in the game. Off = thrown props fly bare. |
| `throw_trail_width` | Ribbon width at the head, where it leaves the prop; it tapers to a point at the tail. Sized for a knife. |
| `throw_trail_lifetime` | How long a point of streak lingers — the tail's length in **time**, not metres, so a harder throw automatically draws a longer streak. |
| `throw_trail_min_speed` | The speed below which the prop stops laying new streak. This is what ends the effect on landing, and what stops a bounced knife rolling across the floor from scribbling. **Keep it under `PhysicsDamageSettings.pickup_throw_impulse` (12 m/s, the speed an ordinary throw leaves the hand at)** — at or above it the effect silently reverts to knife-only, since the knife's `2.5×` launch is the only thing still clearing the bar. Pinned by `tests/test_managers_tuning.gd`. |
| `throw_trail_reference_dist` | Distance at which the ribbon is drawn at exactly its authored width; past it the streak is widened in proportion so a long throw doesn't thin into a flickering sub-pixel line. Never makes it thinner (the `tracer_reference_dist` rule for bullet tracers). |
| `throw_trail_max_points` | Cap on live samples — the effect's whole cost, since the ribbon is rebuilt every physics frame. |

> **Gotchas.** The streak's material must stay **transparent**: writing no depth is the only reason the Borderlands ink pass can't see it, and an opaque one would get a black ink line drawn around every streak. The ribbon is also deliberately parented to the **tree root**, not to the prop — every `MeshInstance3D` under a `Throwable` is swept by its outline chain (black hull + ink mask bit) and by the carried-transparency fade, and a ribbon childed to the prop gets dressed like part of it. Neither is a knob; both are load-bearing, and both are commented at the top of `throw_trail.gd`.

### Restyling the effects themselves (edit the effect `.tscn`)

`EffectsSettings` (above) tunes the *numbers* -- how many gibs, how long blood lingers. To change what those effects **look like**, edit the effect's own **scene**. Each visual effect IS its own `.tscn`, and every spawn site preloads that scene by UID, so **editing the scene restyles the effect everywhere** -- no gameplay code, no slot to repoint.

> `EffectFactory` (`rpg/managers/EffectFactory.gd`) is **not** a central registry -- it owns only the blood-impact particle spawn seam (`spawn_blood_particle`) plus a generic `spawn_at(scene, pos)` helper. The other effects are spawned by their own systems, which pass per-instance config (an explosion's force/radius/instigator, reimport-recovery reloads) that a shared slot couldn't carry. An earlier version exported a slot per effect, but repointing one did nothing (the call sites don't read it), so those misleading slots were removed. **Edit the scene, not a slot.**

To restyle an effect, open its scene in the **FileSystem** dock (double-click it, or search its UID) and edit it -- every spawn of that effect loads the same scene, so the change propagates everywhere:

| Effect | Scene to edit | UID |
|---|---|---|
| Blood impact spray | `blood.tscn` | `uid://c7v6vgs74fhn4` |
| Blood splat decal | `blood_splat_decal.tscn` | `uid://dg5ui5is8sakg` |
| Big death gore burst | `bloody_mess.tscn` | `uid://yeq88l33gvle` |
| Blood drip | `blood_drop.tscn` | `uid://b3dropfx7anp` |
| Bullet-hole decal | `bullet_hole_decal.tscn` | `uid://dh1ydtvwvgiqg` |
| Dust puff / heavy cloud | `dust.tscn` / `dust_large.tscn` | `uid://um6f8g8g6l7v` / `uid://ckxkt0g5gq8bb` |
| Explosion blast | `explosion_area.tscn` | `uid://co1ehjy0gbhu3` |
| Gore gib (generic meat chunk) | `gore_gib.tscn` | `uid://bgore1gib0scn` |
| Body-part gib (a flung head/torso/arm/leg) | `body_part_gib.tscn` | — (reference by path) |

The generic `gore_gib` chunk and the `bloody_mess` burst are the obvious first swaps when real gore art
lands. The **body-part gib** needs no art at all: its visual is the dying character's OWN part, lifted live
off that actor's `BodyModelSwap`, so it always matches whatever head/torso/arms/legs the NPC is wearing. Its
`.tscn` is only the physics chassis (mass, damping, impact sound, the empty `Model` mount point the part is
parented under) — edit it to change how limbs FLY and LAND, never how they look.

The meat chunk also **sizes itself per spawn**: a `RandomSize` child on `gore_gib.tscn` (the dog's size
roller — see *Appearance — random cosmetic variety*) multiplies the whole chunk's root scale by a random
`0.6×`–`1.5×` on ready, so a burst reads as torn pieces of meat rather than six identical props (bigger
chunks also hit a touch harder via the roller's `impact_damage_mult` knock-on). Retune the range on that
node's Inspector — it's a SCENE knob, deliberately not an `EffectsSettings` row, because it travels with the
chunk's art. The body-part gib has no roller: limbs fly at the character's true size.

### The rule: player-facing tunables and keybinds must ALSO reach the settings menu

Here's the catch that trips people up. A tuning `.tres` value is a **designer** knob — great for things the player never touches (gib count, NPC retarget interval, faction thresholds). But the moment a value is something a **player** should control — volume, sensitivity, FOV, an accessibility/comfort toggle, screen-shake strength — the project rule from `rpg/CLAUDE.md` ("Keep the settings menu in sync with features") says it must **also** be wired through two more files, or the in-game options screen silently won't have it:

- **`rpg/managers/Settings.gd`** — the player-facing OPTIONS + persistence autoload. This is *not* the same as `GameSettings`. `Settings` owns only what the Options menu can change: it stores the player's choice, saves it to `user://settings.cfg`, loads + applies it on boot, and (where relevant) pushes it onto the right `GameSettings` field. For instance `Settings.set_fov()` clamps to `FOV_MIN..FOV_MAX` (60–120) and writes `GameSettings.camera.default_fov`; `set_mouse_sensitivity()` clamps to `SENS_MIN..SENS_MAX` and writes `GameSettings.camera.mouse_sensitivity` (radians per **screen** pixel — the `screen_relative` unit; it persists under the cfg key `mouse_sensitivity_screen`, and a settings.cfg from before the switch, which carries the OLD `mouse_sensitivity` key in canvas-px units, is rescaled ONCE by `Settings.LEGACY_MOUSE_SENS_SCALE` = 792/1920 in `read_mouse_sensitivity` so a returning player's 1080p feel is unchanged — never write the old key back); `set_screen_shake_scale()` scales `GameSettings.screen_shake.intensity_multiplier` (off a baseline captured at boot). The pattern for a new tunable: add a stored `var`, a `set_…()` that applies + calls `save_settings()`, and a line in both `load_settings()` and `save_settings()` for the `.cfg`. ⭐ **And the other half of that pattern, which is easy to miss: whatever CONSUMES the pushed `GameSettings` field must read it LIVE at the point of use — never cache it in a field initializer.** A `set_…()` writes `GameSettings` and nothing else; it does not go looking for live nodes. So a consumer holding a snapshot silently keeps the OLD value until the level reloads, and if a *second* system reads the same field live you get two writers easing one property toward two different targets. That is exactly what happened to the FOV slider: `CameraEffects.base_fov` was `var base_fov: float = GameSettings.camera.default_fov`, evaluated once per camera, while `ScopeIn` eased the same `fov` toward `default_fov` directly — asking for 95° from a stale 120° settled the view at **104°**, the fixed point of the two lerps. `base_fov` is a getter now (fixed 2026-08-20, pinned by `tests/test_camera_input_ui.gd::test_camera_base_fov_follows_a_mid_run_fov_change`), matching `mouse_sensitivity` and `intensity_multiplier`, which were always read at the point of use.
- **`rpg/scripts/ui/options_menu.gd`** -- the `OptionsMenu` overlay (autoload, opened with Escape; serves both the start menu and in-game). It is fully DATA-DRIVEN: every row is a `SettingSpec` in `resources/settings/SettingsCatalog.tres`, and `_rebuild_tabs()` iterates `CATALOG.specs` and lets `_emit_row()` build each control by dispatching on `SettingSpec.Widget` (Section / Toggle / Slider / Dropdown / Keybind / Custom). Tabs appear in the order their first spec is seen; `SettingSpec.tab` is the tab's stable KEY (it groups the rows and names the page node -- tests pin it), and the optional **`SettingSpec.tab_label`** is the DISPLAY title the `TabContainer` paints (the first non-empty `tab_label` among a tab's specs wins, catalog order; blank falls back to `String(tab)`, so an unlabeled catalog looks exactly as before). Edits stage into `_pending` and only commit on **Apply** (key rebinds are the exception -- they bind live). You do NOT hand-build rows here: to add an option you add a typed `var` + a `set_*` setter to `Settings.gd`, then add ONE `SettingSpec` row to the catalog (no `options_menu.gd` edits).

**Keybinds** are also data-driven. To add a rebindable action: add its keyboard/mouse default to `project.godot`'s `[input]` map (the editor's Input Map panel) and its controller default in `managers/InputManager.gd`, **then** add ONE `ActionSpec` row (`action` / `label` / `section` / `section_key` / `rebindable`) to `resources/input/ActionCatalog.tres`. (`section` is the DISPLAY header, `section_key` its stable id — author it the same on every row of the section, e.g. `&"sec_movement"`; blank falls back to deriving it from the title, but authoring it means retitling a section can never change the generated `SettingSpec.key`.) The Controls-tab section headers + rebind rows are GENERATED by `ActionCatalog.keybind_specs()`, which `OptionsMenu` appends to `CATALOG.specs` in `_rebuild_tabs()` -- so do NOT hand-author a `Keybind` `SettingSpec` in `SettingsCatalog.tres`. The action *name* is the stable key -- rebinding only swaps the bound event, so everything that polls the action name keeps working. `Settings.rebind_action()` persists the new event under the cfg's `[controls]` section. `InputManager` cross-checks those three name-surfaces at boot (dev builds) via `validate_action_sources()` and prints a warning per drifted name, so a forgotten surface shows up the first time you run -- not just under GUT. To show a key in a prompt or UI, call `InputManager.get_action_binding(action)` (the single binding-query seam; `display_key()` is a kept alias) rather than reading the `InputMap` events yourself.

> **A shipped verb that's easy to miss: night vision.** The `NightVision` action (default **N**, rebindable in Options → Controls; it's an `ActionCatalog` row in the **Combat** section, next to `Grapple` and `Takedown`) toggles the post-process night-vision look, eased in/out at `Player.night_vision_fade_rate` (`@export`, default `9.0`). There is **nothing to wire per level**: it drives the `night_vision` uniform on the ShaderMaterial of the player's own `UI/ColorRect` post-process overlay (`resources/shaders/post_process.gdshader`), so it travels with the player into any level.

So the mental model is: **`GameSettings` = the designer's master tuning sheet; `Settings` = the slice of it (plus video/audio/keybinds) the player is allowed to override, persisted to disk; `OptionsMenu` = the screen that drives `Settings`.** A pure balance number stops at `GameSettings`. A player-facing one travels through all three.
### Difficulty: the live multipliers (`DifficultySettings`)

Difficulty in CYBER SUNDAY is the cleanest case of the three-file pattern above. It's *both* a designer tuning group (the Easy/Hard preset numbers you balance) **and** a player Options row (the Easy/Normal/Hard choice). The whole system is **inert at the default** — Normal is every multiplier at `1.0`, i.e. today's balance unchanged — so it does nothing until a player picks a non-Normal level.

`DifficultySettings.gd` (read as **`GameSettings.difficulty`**, authored as `resources/tuning/DifficultySettings.tres` — a row in the registry, §12) holds two things: a set of **live multipliers** the combat / spawn / reward seams read every frame, and the **Easy / Hard presets** that get copied into those live fields when the player chooses a difficulty. There's an `enum Level { EASY, NORMAL, HARD }` (so `EASY` = 0, `NORMAL` = 1, `HARD` = 2).

**The live multipliers** (group **Current**, written only by `apply_level()` — don't hand-edit these, they're overwritten on every difficulty change and on boot). All default `1.0` (= no change):

- **`damage_taken_mult`** (float) — scales damage the **player takes**. `>1` = harder. Default `1.0`.
- **`damage_dealt_mult`** (float) — scales damage the **player deals** to enemies. `>1` = easier. Default `1.0`.
- **`enemy_count_mult`** (float) — scales how many enemies an `EncounterSpawner` (§ encounters) spawns per wave. `>1` = denser. Default `1.0`.
- **`loot_mult`** (float) — scales loot drop quantity. `>1` = more. Default `1.0`.
- **`money_mult`** (float) — scales money (zorkmid) kill rewards. `>1` = richer. Default `1.0`.
- **`xp_gain_mult`** (float) — scales XP gained (§22). `>1` = faster leveling. Default `1.0`.

**The presets** are what you actually tune as a designer — two `@export_group`s of the same six fields, copied into the live set when the player picks that level:

- **Easy preset** — `easy_damage_taken_mult` `0.5`, `easy_damage_dealt_mult` `1.5`, `easy_enemy_count_mult` `0.7`, `easy_loot_mult` `1.25`, `easy_money_mult` `1.25`, `easy_xp_gain_mult` `1.0`. (Take half damage, deal 50% more, thinner waves, richer loot/money, normal XP.)
- **Hard preset** — `hard_damage_taken_mult` `1.75`, `hard_damage_dealt_mult` `0.85`, `hard_enemy_count_mult` `1.35`, `hard_loot_mult` `1.0`, `hard_money_mult` `1.0`, `hard_xp_gain_mult` `1.25`. (Take more damage, deal a bit less, denser waves, normal loot/money, faster XP as a reward for the harder run.)

Normal has no preset group — it's the neutral baseline, so picking Normal resets every live multiplier to `1.0`.

**Where each multiplier actually applies (the seams).** You don't wire these; they're already read at the right places, and only the listed cases scale — everything else is untouched:

- `damage_taken_mult` — on the **player only** (gated in `take_damage`), so an NPC taking damage is never scaled.
- `damage_dealt_mult` — on the **player's own shots** (hitscan + projectiles), so only the player benefits from "deal more".
- `enemy_count_mult` — in `EncounterSpawner`'s spawn count, **rounded and floored at 1** (Easy thins a wave but never empties an encounter a designer placed).
- `loot_mult` — on a loot-table roll's count, **floored at 1** (a roll that hit still yields ≥ 1).
- `money_mult` — on the **kill bounty** paid to the player.
- `xp_gain_mult` — at the `add_xp` inflow, so XP **grants** scale while a save-load that restores XP directly does not.

Because the live fields are read every frame, a mid-run difficulty change takes effect immediately — no reload.

**The player-facing side (`Settings.difficulty_level`).** `Settings.gd` stores the choice as **`difficulty_level: int`** (default `DifficultySettings.Level.NORMAL`) and exposes **`set_difficulty(level)`** (clamps 0–2). Like every other setter it applies immediately — `apply_difficulty()` calls `GameSettings.difficulty.apply_level(difficulty_level)`, copying the chosen preset into the live mults — and persists to `user://settings.cfg` (under `[gameplay] difficulty_level`). It's also re-applied on boot (via `apply_all`), so a returning player's saved difficulty is live from the first frame.

**Worked example — make Hard brutal.** Open `DifficultySettings.tres`. Under **Hard preset**, raise `hard_damage_taken_mult` from `1.75` to `2.5` and `hard_enemy_count_mult` from `1.35` to `1.6`. Save. The next time a player on Hard takes a hit or trips an encounter, they eat 2.5× damage against 60% denser waves — and you never touched a script. Leave the **Current** group alone; it's machine-written.

> **The Options row (already shipped).** Difficulty is a live **Options → Game** choice row — no manual catalog edit needed. `resources/settings/SettingsCatalog.tres` already carries the `difficulty` `SettingSpec` (key `&"difficulty"`, getter `difficulty_level`, setter `set_difficulty`, custom handler `_emit_difficulty`), and `scripts/ui/options_menu.gd` defines `_emit_difficulty()` (it builds the `Easy / Normal / Hard` in-canvas `< value >` cycler, indices 0/1/2 matching the `Level` enum). A player changes difficulty in-menu and it applies + persists immediately, exactly like every other catalog row (see "The rule" above) — you don't touch code or hand-edit `settings.cfg`.

#### Difficulty gotchas

- **Don't edit the Current group.** `damage_taken_mult` … `xp_gain_mult` are the *output* of `apply_level()` and are overwritten on every difficulty change (and on boot). Tune the **Easy preset** / **Hard preset** groups instead; Normal is hardcoded to reset everything to `1.0`.
- **Normal = inert.** With the shipped defaults and a Normal selection, every seam multiplies by `1.0`, so the difficulty system is byte-identical to no system at all. It only diverges once a player picks Easy or Hard.
- **`enemy_count_mult` and `loot_mult` floor at 1.** An Easy multiplier below `1.0` thins waves and drops but never zeroes out an authored encounter or a roll that already hit — so you can't accidentally design an empty fight.
- **Damage mults are player-only.** `damage_taken_mult` scales only the *player's* incoming damage and `damage_dealt_mult` only the *player's* outgoing shots; NPC-vs-NPC damage is never touched by difficulty.


### The player's menu screens

Five full-screen player menus open from rebindable keys (Deus Ex / Pip-Boy style -- they share a tab group, so the player can flip between them):

| Screen | Default key | Shows |
|---|---|---|
| **Inventory** (the Tetris grid, §9) | **Tab** | the backpack grid + equipped weapon |
| **Stats** (§22) | **C** | the player's `CharacterStats` sheet |
| **Implants** (§13's chips) | **I** (action `Implants`) | installed microchip abilities (click a row to switch one off/on), plus carried chips a `ChipInstaller` mechanic could fit |
| **Reputation** (§7) | **V** (action `Factions`) | standing with each faction |
| **Journal** (§14) | **J** (action `Journal`) | active / completed / failed quests and their objectives |

They're autoloads that auto-populate from live state, so there's nothing to author per level -- this is just *where* the content you set (stats, reputation, items) is shown to the player. The keys are rebindable like any other (they're `ActionCatalog` rows in the **Interface** section, alongside `RotateItem` = **R** for rotating an item in the grid).

### Gotchas

- **Don't confuse `GameSettings` with `Settings`.** They're two different autoloads. `GameSettings` holds the live `.tres` numbers; `Settings` holds the saved player overrides and *writes into* a few `GameSettings` fields on apply. Editing `CameraSettings.tres`'s `default_fov` changes the authored default; `Settings` will overwrite it on boot with the player's saved FOV (it seeds *from* the design default only when there's no `settings.cfg` yet). So if a value seems to ignore your `.tres` edit at runtime, check whether the Options menu owns it.
- **A player-facing value added only to a `.tres` will never appear in the Options menu.** The menu is built from `Settings`, not from `GameSettings`. Skipping the `Settings.gd` + `options_menu.gd` wiring is the single most common way a new comfort/audio/sensitivity option ends up uncontrollable in-game.
- **`intensity_multiplier = 0` (ScreenShake) and `bob_amount = 0` (Camera) fully disable** those effects — handy, but note the same outcomes are reachable by players via the Accessibility tab's Screen Shake slider and View Bobbing toggle. Prefer leaving the `.tres` at the authored baseline and letting the player opt out, since `Settings` captures that baseline at boot to anchor its percentage sliders.
- **What's already in Options → Accessibility** — check here before adding a new comfort knob, the row may already exist: Screen Shake, Screen Flashes, Vertex Warp (PS1), Hit Stop, Colorblind Filter, Colorblind-Safe Cues, View Bobbing, Camera Tilt, FOV Effects, HUD Sway (0–100% scale on the diegetic HUD-weight motion), HUD Ghosting (0–100% scale on the CRT phosphor persistence behind the HUD — moving readouts drag a decaying tail and the ghost image lags a couple of pixels behind the live HUD while you turn, which is what puts a tail on the screen-locked reticle; 0 stops the offscreen accumulation pass entirely), World Ghosting (0–100% scale on the same persistence applied — very faintly — to the PICTURE behind the HUD: a running average of the finished frame is added back over it, so where the view moved you see a short memory of where it was. Its OWN dial rather than a share of the HUD one because it is a full-screen temporal effect, the closest thing in the game to motion blur, and the first thing a motion-sensitive player turns off while still wanting the HUD to ghost. The weapon is masked out per pixel and menus switch it off entirely; 0 stops the pass rendering and the frame is bit-identical), HUD Curve (0–100% scale on the curved-glass bend — the corner instrument panel is composited through a cylindrical warp so it wraps toward you at its edges like the inside of a curved monitor; the corners stay pinned so nothing leaves the screen, the reticle and the combat arcs stay flat, and 0 tears the SubViewport down so OFF is the pre-curve HUD), Show Detection Meter, Enemy Health Bar (OFF hides the top-centre readout that pops when you damage something), Item Lights, Crosshair Stamina Ring (OFF restores the classic bottom-left stamina bar), Minimap (OFF hides the top-right floorplan and returns the objective tracker to the corner), Rotate Minimap (ON = heading-up, OFF = north-up), NPCs On Minimap (OFF hides the allegiance-shaped NPC glyphs, leaving terrain, station and objective markers), Stations On Minimap (OFF hides the shop/bank/clinic/trainer/tech/rest/exit glyphs), Minimap Zoom (0.5x–3.0x, also cycled by the MinimapZoom key — default M), HUD Clock (OFF hides the time-of-day readout under the map and lifts the objective tracker into the space it used), 24-Hour Clock (ON = "14:35", OFF = "2:35 PM"), Show Weapon, Left-Handed Weapon, Lens Curve (0–100% scale on the WORLD lens — the whole rendered frame drawn through a barrel/fisheye warp: the centre magnified, the periphery squeezed, straight lines off the centre bowing outward. The corners are PINNED, so it can never show a black edge at any strength, and 0 makes the shader early-out to a plain screen fetch, so OFF is pixel-identical to a build without the feature. The amplitude is `GameSettings.camera.lens_barrel_amount`; this row is the player's scale over it), Text-to-Speech, Low-HP Heartbeat. (All 29 are `SettingSpec` rows in `SettingsCatalog.tres` with `tab = &"Accessibility"`.)
- **What's already in Options → Video** — Window Mode, Resolution, VSync, Max FPS, Render Scale, Field of View, Contrast, **Ink Outline** (0–100% on the Borderlands-style black outline over the whole frame; 0% hides the pass entirely), **Color Depth** (which colours the frame is allowed to use at all — see below), **Muzzle Smoke** (0-100% on the little white puff that curls off a hot barrel a beat after each shot; the per-weapon `WeaponData.muzzle_smoke_scale` multiplies into it, and 0% stops the emitter arming at all, so off is free), and **Dithering** (0–100% on the ordered **Bayer** matrix the frame is quantised through — 100% is the authored pattern, 0% quantises by plain round-to-nearest and you get hard colour banding, most visible as onion rings around the moon). All four live here rather than under Accessibility on purpose: they are *looks*, not comfort settings — nothing about them moves, so they have none of the motion-sickness rationale that puts Vertex Warp (PS1), View Bobbing, HUD Sway and HUD Ghosting on the other tab. HUD Ghosting is the edge case that shows where the line is: it is unmistakably a *look* (phosphor persistence), but it is a look made of MOTION — a tail only exists because something moved — so it sits with the comfort rows rather than with Dithering. HUD Curve lands on the same side for the neighbouring reason: the bend itself is static, but it displaces every corner readout away from where the eye expects it and then rides the HUD-weight spring, and a warped panel is exactly the class of thing a motion-sensitive player wants to dial back rather than switch off. **Lens Curve is the clearest case of all, and it is the one to reason from.** A barrel warp is perfectly static — nothing about it animates — so by the "does it move?" test it belongs on Video beside Dithering. It is on Accessibility anyway, because it bends the WORLD rather than a HUD panel: every camera turn now sweeps the periphery at a different rate than the centre, and peripheral distortion at a wide field of view is a well-known nausea contributor. The rule the line actually encodes is not "does the effect move" but "does the effect change how MOTION reads" — which is also why Vertex Warp (PS1) sits there and Ink Outline does not.
    - **The dither's matrix SIZE is not a player setting** — it is `bayer_order` on the post-process ShaderMaterial (`scenes/player/ui.tscn` → `ColorRect`), authored beside `color_steps` because it is a palette decision, not a preference: `0` off, `1` = 2×2, `2` = 4×4, `3` = 8×8 (shipped). A bigger matrix carries more threshold levels (N×N) and so reconstructs a gradient more finely at the same colour depth. A/B it live in-game with the debug console's `dither <strength> [grid]` (grid typed as the width — 2/4/8), or shoot the whole sweep to PNG with `scripts/tools/dither_qa_shots.gd`. ⭐ A grid set from the console **outlives death, respawn and level changes** — the material is a sub-resource of the cached PackedScene — so re-run `dither <strength> 8` to hand the authored look back.
    - **Color Depth is the quantiser the dither feeds, and its default changes nothing.** `post_process.gdshader` has always snapped the finished frame onto a colour grid; what this row adds is a *player* choice of grid, and a **per-channel** one. The list is named for the hardware depths it reproduces: Default, 24-bit (Off), 16-bit (RGB565), 15-bit (PS1) (RGB555), 12-bit, 9-bit, 8-bit (RGB332), 6-bit, 3-bit. The unequal rows are the point of it being per-channel — 16-bit spends its odd bit on **green** because the eye resolves green detail finest, and 8-bit starves **blue** for the same reason; a single `color_steps` can express neither. **Default (index 0) is the shipped look**: it is a sentinel, not a depth, and hands the material back its own authored `color_steps` (16 on the player's overlay in `scenes/player/ui.tscn`, 32 on the CRT wall in `scenes/computerroom.tscn`), so a player who never opens the menu sees exactly the frame the game shipped with — and an un-driven material (that CRT wall, or the shader on a bare quad in the editor) keeps quantising the way it was authored. **The table lives in ONE place**: `Settings.COLOR_QUANTIZE_LEVELS` (index → per-channel step count), with `Settings.color_quantize_levels()` / `color_quantize_color_count()` beside it. `player.gd` pushes the looked-up `Vector3` onto the live material as the shader's `quantize_levels` uniform every frame (the `contrast` / `colorblind_mode` idiom, so the row bites with no level reload) — the shader never learns what a menu index is, and the numbers the GPU gets are the numbers the suite asserts. To add or retune a depth, edit that table and add a caption to `PlayerText.OPTIONS_CQ_*`: **array order is behaviour** (the cycler maps its index straight into the table), and `tests/test_color_quantization.gd` fails if the caption count and the table size disagree. Depth and dither only make sense as a pair — this row decides which colours exist, that one decides how the ones in between are faked, and from 6-bit down the dither is the only reason the image still reads. A/B it live with the console's `quantize [0-8]` (F1 → View), which is **in-memory only** and never writes `settings.cfg`; unlike `dither`'s grid it does not outlive a respawn, because it is a Settings field the driver re-reads rather than a value parked on the material. **Verify a change with a real windowed run**: `godot --path . res://scripts/tools/color_depth_qa_shots.tscn -- --shots-dir="C:/some/dir"` shoots every depth and *counts the distinct colours* in each captured frame against that depth's arithmetic cap (it zeroes the film grain first — grain is added after the quantiser and would swamp the count, and it hides the HUD, which draws above the ColorRect and is never quantised). Headless never compiles a `.gdshader`, so the suite can only pin the source text and the table; that harness is the part that can see the pixels.
    - ⭐ **Never re-split the posterize and the dither into two steps.** The shader quantises exactly once, with the Bayer value as that quantisation's threshold. Posterizing first and adding a threshold afterwards is a mathematical no-op (`floor(k + d) == k` for an integral `k` and `d < 1`) — which is exactly what this shader did for a long time, so the 4×4 matrix in it never changed a single pixel. `tests/test_smoke.gd` pins the single-quantisation shape, because headless never compiles shaders and no assertion can look at a dither pattern.
- **Windowed mode is screen-fitted, and `no_focus` must stay OFF.** The Resolution row offers only the `Settings.RESOLUTIONS` presets whose *decorated* window (caption + borders, measured off the live window) fits the current monitor's usable area (`Settings.available_resolutions()`), and `Settings.apply_video` re-fits a saved `windowed_size` that no longer fits (largest fitting preset by area, else clamped — `windowed_size` is *mutated* to the effective size, and Options rebuilds its rows after Apply so the row shows what the player actually got) and centres the frame in the usable rect with the title bar on-screen — a short frame-counted guard undoes the OS/driver's occasional post-fullscreen "restore" jump, and re-centring only happens when the mode or size actually changes (VSync / FPS / Render Scale never yank a dragged window). Do **not** tick Project Settings → Display → Window → **No Focus**: on Windows a `no_focus` main window loses `WS_VISIBLE` and refuses click-activation the moment it goes windowed, so the game *vanishes*; fullscreen masks it, which is how it shipped unnoticed for months. `tests/test_windowed_mode.gd` pins the flag off + the pure fit/centre rules; `apply_video` also clears the flag at runtime (and dev builds warn once) so a re-ticked checkbox cannot ship a vanishing game. Presets are all ~16:9 on purpose — the fit swaps between them, so the canvas keeps its shape.
- **Keep Project Settings → Input Devices → Joypads → "Ignore Joypad On Unfocused Application" ON, and add no focus checks to input readers.** (`input_devices/joypads/ignore_joypad_on_unfocused_application=true` in `project.godot`; `tests/test_focus_input_lock.gd` pins it.) It is what stops a pad from steering and firing the character while the player is alt-tabbed away — SDL keeps reporting the stick through an alt-tab, and only that engine flag makes `Input` drop joypad events and release held joy state on focus loss; keyboard and clicks already stop at the focused window. That checkbox is the designer-facing switch — there is no script-side gate to find or add, and `gameplay_suppressed()` is unchanged. The one thing it can't cover, the click that *re-focuses* the window firing the drawn weapon, is handled by `MouseInput`'s refocus fire latch (one per fire button; the activating click has to be let go before that button fires again; `PickupRay`'s left-click throw honours it too). Mechanism, notification choice and known residuals (mouse wheel, pad trigger held across the edge) are in `docs/CURRENT_ARCHITECTURE.md` §"OS focus and input"; the manual check is: draw a gun, alt-tab away, click the game window — no shot.
- **A new full-screen flash MUST check `Settings.screen_flash_enabled`.** That's the photosensitivity toggle, and it is **not** applied centrally — every fire site reads it live: the dash / hurt / kill flashes in `scripts/player/player_hud.gd`, `StarSky.flash_kill` (the whole-sky pop), and the player's own full-screen `white_flash` in two more places — `scripts/combat/attack.gd` (on a hitscan shot, reached through `Character.get_hit_flash()`) and `scripts/player/ram_reactor.gd` (a body-check ram). An ungated flash silently ignores the player's setting. Gate only the *visual*: the `attack.gd` site deliberately keeps its 85 ms await and abort window outside the check, because gating the whole block once let an accessibility setting change combat outcomes (a flash-off shot skipped the await and could deal 0 vs full damage in the same race).
- **The `npc_ai` stealth/comfort toggles have safe script defaults of `false`** and the shipped `NpcAiSettings.tres` turns ALL of them ON — `body_discovery`, `hearing_initiates`, `hearing_occlusion`, `music_reactions`, and `head_look` are every one `true` in the resource. So the full stealth/reaction layer is live out of the box; flip a flag off in the `.tres` to disable that pillar for a quieter level, and re-playtest after any change (some, like `head_look`, can need a per-rig axis tweak).
- **All of the radio's feel lives on the `Radio` component's own `@export`s** (duck/settle timings, fade times, click SFX, audible radius, the launched music-note particles, and the prop bounce/impulse) — there's no global radio tuning group; per-instance `@export`s cover everything.

Relevant files: `rpg/managers/GameSettings.gd`, `rpg/managers/Settings.gd`, `rpg/scripts/ui/options_menu.gd`, and the group definitions in `rpg/resources/tuning/*.gd` with their authored values in the matching `rpg/resources/tuning/*.tres`.

---

## NPC services and progression (shops, healing, companions)

Any NPC in CYBER SUNDAY can offer a *service* the same way it offers anything else: you drop a **component** under it in the scene tree and fill in a few `@export` fields. There's no scripting. The dialogue system scans the NPC you're talking to for these components and automatically adds the matching button to the conversation menu — "Trade", "Heal", "Rest", "Level Up", "Install", "Play Chess", "Bank", plus "Follow me"/"Wait here" for recruitment. This section covers the service components and how to wire each one.

### The big idea: `standalone` vs. data-only

The service components (`Merchant`, `Healer`, `Bonfire`, `LevelUp`, `ChipInstaller`, `ChessMatch`, and the `Atm` ledger terminal) all extend `LookAtInteractable` and share one decisive flag: **`standalone`** (a `@export bool`, default `true`).

- **`standalone = true`** — the component is a *self-serve prop*. It sits on the talk layer, so aiming at it and pressing Interact opens the service directly. Use this for a vending machine, a healing fountain, a lit campfire, a level-up shrine. No NPC or dialogue needed.
- **`standalone = false`** — the component becomes **data-only**: the aim ray ignores it entirely (its `collision_layer` is set to `0`). You attach it *under a dialogue NPC* (one that already has a `Talkable` driving its conversation). The NPC's dialogue then grows the matching option — "Trade", "Heal", etc. — that opens this component's service. This is how one NPC both *talks* and *trades*.

So the universal recipe for a service NPC is: an NPC with a `Talkable` (for conversation) **plus** a service component as a sibling child with `standalone = false`. A NEW kind of service is one component implementing the two dialogue-station contract methods — the dialogue grows the option automatically, no dialogue code.

The dialogue manager discovers each service through the **dialogue-station contract** (`rpg/scripts/dialogue/dialogue_manager.gd`): it scans the speaker's **direct children** for components exposing the method pair `dialogue_station_option()` (the option's label / order / suspend info) + `open_dialogue_station(player)` (the press), so the component must be a **direct child** of the NPC node — one nested two levels deep is invisible. It doesn't care about the class name — only that method pair — but using the real components below is the supported path. The menu order is fixed by each component's `DIALOGUE_ORDER` const (Trade, Heal, Rest, Level Up, Install, Play Chess, Bank), not by the order you author the children — see `rpg/scripts/components/README.md` for the contract details.

---

### Merchant (the "Trade" option) — `rpg/scripts/components/merchant.gd`

Drop a **`Merchant`** node under the shopkeeper. The dialogue adds "Trade" via the Merchant's dialogue-station contract (it's the first option — `DIALOGUE_ORDER` 10); picking it *suspends* the conversation and opens `ShopScreen` on this merchant's stock — closing the shop drops you back into the conversation rather than ending it.

Fields, grouped as they appear in the inspector:

**Stock**
- **`stock_counts: Array[StockEntry]`** — how you author what's for sale. Each `StockEntry` (`rpg/scripts/components/stock_entry.gd`) is one row with an **`item: Item`** and a **`count`** (`@export_range(1, 999)`, default `1`). Weapons are stocked as one *unique* instance per count, so "2 shotguns" really is two distinct objects.

**Display**
- **`shop_name: String`** — shown on the look-at hover ("Trade: <name>") and the shop title. Blank falls back to "Merchant".

**Pricing**
- **`money: float`** (default `1000.0`) — the merchant's till. Selling *to* it draws from this; it can't buy what it can't afford.
- **`buy_mult: float`** (default `1.0`) — the player buys at `item.value × buy_mult`. `>1.0` marks up.
- **`sell_mult: float`** (default `0.5`) — the player sells at `item.value × sell_mult`. `<1.0` is the merchant's cut. (The player's streetwise stat further nudges both prices at runtime via `buy_price_mult()` / `sell_price_mult()` — buy 4% cheaper / sell 4% dearer per point. The buy multiplier can reach 0, but a valued item still costs at least one coin quantum; selling has no cap but never pays below 0.)
- **`accepts_ledger: bool`** (default `true`) — **turn it OFF for a cash-only vendor.** On, the merchant takes the player's armed payment rail like every other till: cash first, then banked savings, then (under CREDIT) the credit line, with the account-funded portion carrying the service charge. Off, the merchant takes **nothing but coins in hand** — savings and the credit line are invisible to it, no service charge applies, and the sale can neither draw down savings nor deepen a debt. Use it for a back-alley fence, a vending machine, or a black-market dealer who isn't on the ledger; it's the knob that makes *carrying cash* matter in a game where banking is otherwise strictly better. ShopScreen dims rows on the **merchant's** predicate (`can_afford`), not the player's, so a cash-only vendor's rows correctly read as unaffordable even when the player is rich on paper. Turning it off also **hides the DEBIT/CREDIT selector** on that shop, since neither rail applies. (For a till that should still take *banked savings* but must not lend, the narrower knob is `LevelUp.accepts_credit` — see the LevelUp section; it refuses credit alone rather than the whole ledger.)

> **The DEBIT/CREDIT selector is a drop-in — `PaymentRailButton` (`rpg/scripts/ui/payment_rail_button.gd`).** The armed rail (`GameState.payment_method`) decides what a purchase may draw on: cash → banked savings → (under CREDIT only) the credit line. It ships on all five paid screens — shop, heal, level-up, chip-install and respec — plus the ATM. **Two of those hide it at runtime rather than lying:** a cash-only `Merchant` (`accepts_ledger` off) and a `LevelUp` that does not lend (`accepts_credit` off, the shipped default) both call `set_available(false)`; the level-up card then prints its terms where the selector sat, because the armed rail is global persisted state and a player who armed CREDIT at an ATM deserves to be told why the control vanished. **To add it to a new paid screen:** author a `Button` named `RailButton` into that screen's `.tscn` with `payment_rail_button.gd` as its script and `unique_name_in_owner` on, then in `_bind_ui()` do `_rail_btn = %RailButton as PaymentRailButton`, `MenuStyle.cap_button(_rail_btn)`, and **connect `rail_changed` to that screen's repaint**. That last step is not optional: flipping the rail changes which rows are affordable (CREDIT lets the same draw continue past zero where DEBIT declines), so a screen that ignores the signal will sit there showing greyed-out rows the till would now happily serve. **Every one of those paid cards paints the ALL-IN quoted total** — the base price plus the service charge (`GameSettings.economy.bank_noncash_fee_fraction`) on whatever portion pocket cash can't cover — via `Character.charge_total` (ShopScreen routes it through `Merchant.quoted_total`, which drops the fee for a cash-only vendor), so the number on the label is exactly what `charge()` takes. Note the fee formula never reads the armed rail: the account-funded portion carries the charge under DEBIT and CREDIT alike, so a flip changes *affordability* but moves the printed number only insofar as the funding split changes — the repaint re-derives the total from the live split either way, which is what keeps the card honest when cash is spent or banked under it. Call `set_available(false)` when the vendor can't honour a rail choice (the cash-only case above). The flip persists like any run state — a rail armed at a shop is still armed at the next terminal.

**Behavior**
- **`standalone: bool`** — leave `true` for a vending machine; set `false` under a dialogue NPC.

**Access** — an optional story-flag gate (keep a vendor closed until the player has earned it):
- **`required_flag: StringName`** (default empty = always open) — when set, the standalone Interact path refuses to open (toasting "Not open for business") unless `str(GameState.get_flag(required_flag))` equals `required_flag_value`.
- **`required_flag_value: String`** (default `"true"`) — the flag value required to trade. For "the fence opens once you've met the boss."
**Faction pricing (WR-2) — a favoured faction trades you a better deal.** Two more fields under **Pricing** bend every price by the player's *standing with the merchant's own faction*. Both ship inert, so leaving them alone is exactly today's flat markup/markdown.

- **`faction_id: String`** (default `""`) — the merchant's faction, picked from the same auto-populated dropdown as an NPC's `faction_id` (it scans `res://resources/factions/` via `Factions.ids_csv()`, so a new faction `.tres` appears here automatically). Empty = no faction pricing (and also disables the rep stock gate below). This is the faction whose standing the discount reads.
- **`reputation_discount_curve: Curve`** (default `null`) — the heart of WR-2. **`null` = inert** (flat prices, today's behaviour). When set, the player's standing with `faction_id` is normalised to `0..1` across the rep clamp (`GameSettings.reputation`'s `rep_min`..`rep_max`) and fed into this `Curve`; the sampled Y is a **favour fraction**. The player then **buys at `(1 - favor)×` and sells at `(1 + favor)×`** — a favoured faction sells to you cheaper *and* pays you more. `0` = neutral (no change), `0.2` = ~20% friendlier, a **negative** Y = a hostile *markup* (you pay more, get paid less). Author it as a Curve over X in `0..1`. The favour is layered on top of `buy_mult` / `sell_mult` and the player's streetwise, and the result is still snapped to the coin grid (buys round up, sells round down), so prices never round away the merchant's margin.

> A merchant with no `faction_id` (or a `reputation_discount_curve` left `null`) can't read standing, so the favour is `0` and prices are flat — the curve only bites once both are set.

**Reputation-gated stock (WR-5) — "the fence only sells the good stuff once the gang trusts you."** Each `StockEntry` row carries one optional gate field:

- **`required_reputation: float`** (on `StockEntry`, default `0.0`) — `0` (default) = always stocked. When positive, that line is only put on the shelf (**at first seed AND on every `Restocker` refill**) while the player's standing with the merchant's `faction_id` is **at least** this value, on the `GameSettings.reputation` scale (`0` = neutral). Standing is re-checked at restock time, so a line **appears** once you've earned the merchant's trust and **drops back out** of the visible stock if your standing later falls below the bar. A merchant with an empty `faction_id` (or an id that doesn't resolve) can't measure standing, so the gate is ignored and the line always stocks — pair WR-5 with a `faction_id` for it to matter.

#### Worked example: a fence who likes the gang

1. On the `Merchant`, set **`faction_id`** = the gang's faction (e.g. `raiders`).
2. Create a `Curve` in **`reputation_discount_curve`**: leave it flat at `0.0` up to mid-standing, then ramp to `0.2` at the right edge (`X = 1.0`). Now a trusted player buys ~20% cheaper and sells ~20% dearer; a hostile one (drag the left edge below zero) pays a markup.
3. Add a high-value `StockEntry` (the "good stuff") and set its **`required_reputation`** to a standing only an allied player reaches. It stays off the shelf until the player earns it, and reappears on each refill thereafter.

See "Factions, disposition and reputation" for how the player's standing with a faction is earned, clamped, and tuned (`rep_min` / `rep_max` and the thresholds on `GameSettings.reputation`).

### Atm (the "Bank" option) — `rpg/scripts/components/atm.gd`

Drop an **`Atm`** on a wall terminal, a lobby kiosk, or a cash machine bolted to a shopfront and the player has somewhere to **bank**. It is the world-side surface of the ledger every till in the game already spends from: aim + **F (Interact)** and a card opens with **Deposit** / **Withdraw**, the DEBIT/CREDIT `PaymentRailButton`, and a five-line statement — cash on hand, on deposit, owed, credit line, credit score + band. The machine chirps out of its own tinny panel speaker as the screen wakes — and claps out of the same one when you pay down what you owe.

> **⭐NO STATION SCREEN FREEZES THE GAME.** Shop, heal, level-up, respec, chip-install, chess and the ATM all used to pause the tree, on the theory that a transaction is a cutscene. It never read that way, because all of them *except* the ATM are reached through a **conversation** — and dialogue had already paused the world before the sub-menu opened, so their own pause was invisible. The `Atm` is the one you walk up to and press F on with nothing in front of it, and there the freeze read as the whole city stopping dead at a cash machine. So they are all real-time now (the `LootScreen` posture) and **dialogue's pause is the only one left in the game**. Consequences you author around: the world keeps running, NPCs keep moving, the clock keeps ticking, **and you can be shot while you bank / shop / play chess** — don't place a station where a player is expected to survive a firefight standing still, and think twice about a chess table (a match runs minutes, not one button press). Still true regardless: your movement and weapons are suppressed while a station screen is up, the Pip-Boy tabs refuse to open over it, and the ATM statement repaints itself if the world moves a number under you (a dawn interest posting).

**Placing one.** The prefab is **`res://scenes/components/atm.tscn`**: an `Atm` (an `Area3D`) with a 1 × 2 × 1 `BoxShape3D`. Drop it in, resize the shape to your terminal art, set `station_name`, done. Or child the bare component under an existing prop the way you would a `Merchant` — assign `highlight_target` (the `Node3D` to outline) or tick `auto_fit_collider` and it sizes its own hitbox from the host's meshes. A terminal is *always* interactable even with both services switched off, because a statement you can read is still a service.

**⭐The one idea the whole terminal rests on: the account is a SINGLE SIGNED number.** `GameState.account` positive is **savings**; negative is **what you owe**. There is no second ledger and no third verb, so **depositing against a negative balance IS paying the debt down** — the same button, the same code, only the caption changes ("Deposit" → "Pay down") and the toast says so. Three consequences worth knowing as a designer:

- **Banked money is death-safe; cash is not.** Death only touches the wallet, so the terminal is where a player makes a run's earnings survive them — that is the reason to walk to one.
- **You can never hold a death-safe hoard while owing.** Every deposit is eaten by the debt until you are solvent, so "buy on credit, bank the profit, then die" is unrepresentable rather than patched.
- **You can never draw the credit line as cash.** Withdrawal is clamped to the *positive* balance, so the line funds purchases only — there is no cash-advance loop to balance.

**Fields** (as they appear in the inspector):

- **`station_name: String`** — the look-at hover ("Bank at \<name>") and the screen title ("LEDGER — \<name>"); blank falls back to "Ledger Terminal" / "LEDGER TERMINAL". (All four strings ship as `[PH]` placeholder copy in `PlayerText`, so name any terminal the player will actually read.)
- **`standalone: bool`** (default `true`) — `true` = a self-serve kiosk on the talk layer: aim + Interact opens the terminal directly. `false` = data-only, exactly like the other stations: its `collision_layer` goes to `0` and the aim ray ignores it, so it can ride a dialogue NPC without stealing the interaction from their `Talkable` — their conversation grows a "Bank" option instead (below).
> **⭐There is no per-terminal fee, by design.** Every terminal quotes the **global** purchase service charge
> (`GameSettings.economy.bank_noncash_fee_fraction` — "Spending it costs 3% — the cash in your pocket never does"),
> because a fee that changed with whichever terminal you last stood at would be unquotable at the point of sale:
> the shop card has no terminal in scope when it prices a purchase. A `fee_multiplier` knob briefly existed here and
> was **deleted** — it only ever scaled the number the ATM *screen printed*, never the charge, so a terminal authored
> at `0.0` advertised a free kiosk and the till billed the global rate anyway. Tune the rate on `EconomySettings`.

**Services** — the group that makes a machine a *kind* of machine:

- **`allows_deposit: bool`** (default `true`) — off = a **withdrawal-only cash machine**. `deposit()` refuses outright and the Deposit button stays disabled.
- **`allows_withdraw: bool`** (default `true`) — off = a **deposit-only night safe** (drop your takings and walk away). Both off = a statement-only screen, which is a legitimate prop.

**Speaker** — the terminal's diegetic wake-up chirp is no longer the `Atm`'s own code or its own knobs: it is the shared **`StationSpeaker`** drop-in every station uses, documented once (with the bus that gives it its cheap-plastic honk) under **"Cheap diegetic speakers"** in the Atmosphere chapter. A standalone terminal builds one at load, so a bare prefab already chirps; drag a `StationSpeaker` under it only to retune (`open_sound`, `volume_db`, `applause_sound`, `applause_volume_db`, `bus`, `max_distance`, `unit_size`) or to mute it.

**It claps when you pay down your debt.** Deposit against a negative balance and the terminal plays a little canned round of applause out of that same forty-cent panel speaker — tinny, positional, and pleased with you. It fires on exactly the portion of a deposit that **retires debt**, which is the same branch that scores credit standing: overpay a 100 debt with 400 and you get the clap for the 100; deposit into an already-positive account and the machine says nothing, because banking savings is not an achievement. A refused deposit (nothing in your pocket, an amount under `bank_min_transaction`, a deposit-blocked terminal) is never applauded either — the cue hangs on what actually moved, not on the press. The screen's normal commit click still fires alongside it, on purpose. Clip and level are the `StationSpeaker`'s `applause_sound` / `applause_volume_db`; clear the clip for a terminal that takes your money without the fanfare.

**What a transaction actually does.** Deposit is clamped to the cash the player physically carries (a broke player deposits nothing rather than digging the debt deeper); withdrawal is clamped to the positive balance (never into credit). Amounts snap to the coin quantum and anything under `GameSettings.economy.bank_min_transaction` (group **Banking**, ships at `0` = any amount) is refused. Every successful transaction toasts and **autosaves** — banking is a milestone, like resting at a `Bonfire`. **Both directions are free, deliberately:** charge both ends and "withdraw, then pay cash" converges with "pay by debit" and the whole decision collapses. The counterweight is the service charge on the portion of a *purchase* not covered by pocket cash — `bank_noncash_fee_fraction` (3%) — which is what keeps money you already carry the cheapest way to buy.

**Repaying builds the credit record.** Only the portion of a deposit that actually **retires debt** earns credit standing (`credit_standing_per_zm_repaid`, 0.02 per zorkmid), and clearing the balance outright pays a one-off `credit_standing_debt_cleared` bonus (10) on top. Paying into an already-positive account earns **nothing** — that is saving, not creditworthiness, and rewarding it would let a rich player buy a spotless record without ever borrowing. Standing is the fifth underwriting line behind the score and band on the statement (weight `credit_weight_standing`, and the only line a player *earns* rather than builds), so a run of repayments visibly moves the rating — and the live credit limit with it. Sitting in arrears runs the other way: `LedgerAccrual` (authored on `Player.tscn`, not a level component) posts one period at every `WorldClock` dawn — debt compounds at `bank_debt_interest_rate` (2%/day), savings earn `bank_savings_interest_rate` (0.5%/day), and each day in the red costs `credit_standing_arrears_per_day` standing even when the interest itself rounds away to nothing. The terminal's hint line advertises whichever rate applies — solvent: "Banked money is safe if you die and grows 0.5% at every dawn…"; in the red: "What you owe grows 2% at every dawn — deposits pay it down first…" — so the player learns both directions move without having to catch a dawn toast. A rate set to `0` drops its clause rather than advertising "0%" (a zeroed *debt* rate falls back to the solvent wording wholesale). All of it is tuned in the **Banking** and **Starting credit** groups on `GameSettings.economy`.

**The rail button on the card.** Flipping DEBIT/CREDIT here writes `GameState.payment_method`, which is **run state, not an option** — it rides the save and every till reads it, so a rail armed at a terminal is still armed at the next shop, healer, mechanic or level-up station. See the `PaymentRailButton` note in the `Merchant` section for what each rail may draw on.

**Dialogue-hosted mode (the "Bank" option).** Set `standalone = false` and child the `Atm` under a dialogue NPC and their conversation grows a **"Bank"** button, exactly like Trade or Install: picking it *suspends* the conversation, opens the terminal, and closing the terminal drops you back at the same response menu rather than ending the chat. That is the whole wiring — a teller NPC is a `Talkable` with a `DialogueResource` plus an `Atm` child, no code and no authored choice. **One button covers everything**, because the terminal's own screen owns deposit / withdraw / pay-down; there is no separate "Deposit" and "Withdraw" option to author. `DialogueManager` finds it on the speaker's **direct** children via the dialogue-station contract (`dialogue_station_option` / `open_dialogue_station`; the "Bank" option is `DIALOGUE_ORDER` 70, the last station), so — like every other service — a component nested two levels deep is invisible to it. **One difference from the kiosk:** a teller-hosted terminal opens *under the conversation's pause*, so banking through dialogue is the frozen-world experience the other stations give you (the card itself runs `PROCESS_MODE_ALWAYS`, which is why its buttons still work there). The real-time posture in the callout above is the standalone path — the machine you walk up to alone.

> **⭐The `@tool` configuration warning.** Leave `standalone` **on** under a dialogue NPC and the node flags itself in the scene tree: *"`standalone` is on but this Atm is a child of a dialogue NPC — its talk-layer hitbox steals the interaction ray from the NPC's Talkable."* That is the real failure it is protecting you from: the terminal's hitbox sits in front of the NPC and the player banks instead of talking — the conversation you wrote never opens. Fix it the way the warning says (`standalone = false`, and bank through the dialogue), or move the terminal off the NPC entirely if you want a kiosk beside the teller.

**Contract notes for anyone editing this.** `deposit()` / `withdraw()` are the only *banking* writers of `GameState.account` — purchases also draw it down through `Player.charge` (the credit rail deliberately crosses below zero) and the New Game implant bill stamps it in `StartMenu._stamp_new_game_profile`, so audit all four plus `LedgerAccrual` (the interest posting) before touching the clamps. They self-guard and run off-tree, and `AtmScreen` is a pure view that decides nothing — which is why the whole terminal is unit-tested without a scene (`rpg/tests/test_atm.gd`). The screen sounds the machine through the shared static seam `StationSpeaker.chirp(atm)` — type-agnostic and null-safe, so no station screen duck-types a method name and none can drift out of sync with the others. The repayment applause is the sibling seam `StationSpeaker.applaud(atm)`, fired from **`deposit()` itself** rather than from the screen: the component is the only place that knows how much of a deposit retired debt, and putting it there means a scripted or dialogue-driven repayment is celebrated too. Both are equally forgiving of a missing speaker, which matters more for the clap — it fires *after* the money and the credit standing have already moved, so a crash there would strand a half-finished transaction.

### Healer (the "Heal" option) — `rpg/scripts/components/healer.gd`

Drop a **`Healer`** under the medic. The dialogue adds "Heal" via the Healer's dialogue-station contract (`DIALOGUE_ORDER` 20); it suspends the conversation and opens `HealScreen`. A heal restores HP to **full** and clears **all** limb damage in one purchase.

- **`heal_name: String`** — hover + screen title; blank → "Healer".
- **`cost_per_hp: float`** (default `1.0`) — zorkmids charged per point of *missing* HP. Cost is linear in how hurt you are.
- **`min_cost: int`** (default `5`) — floor charged whenever there's any damage (covers a limb-only heal where HP is full).
- **`standalone: bool`** — `true` for a med-station; `false` under a dialogue NPC.

If the player is at full HP with no limb damage, `heal_cost` returns 0 and the service is free/refused — so a healer never charges for nothing.

### ChipInstaller (the "Install" option) — `rpg/scripts/components/chip_installer.gd`

The **upgrade mechanic**: the two-step home for player abilities. Every player upgrade (wall-climb, grapple, slide, air-dash, fall-immunity, board-visualizer, **silent-takedown**) ships as a **microchip Item** the player finds or buys but *can't use just by carrying* — they bring it to a `ChipInstaller` and pay zorkmids to have it fitted, which permanently grants the encapsulated ability (via `player.unlock_mechanic`). A fresh game starts with **no** abilities (`Player.tscn` `starting_unlocks` is empty) except any implants **bought on credit** at New Game's implant-purchase step (billed against the starting wallet, which may go **negative**; an empty cart is allowed) — every other ability you earn as a chip. This is the deliberate alternative to the instant-grant `UpgradePickup` (§7 in Items); use chips for normal progression, `UpgradePickup` only for a special "instantly online" grant.

Drop a **`ChipInstaller`** node under the mechanic. Like `Merchant`/`Healer` it works standalone (aim + Interact opens the install screen) or under a dialogue NPC (`standalone = false` → the dialogue adds an **"Install"** option via the installer's dialogue-station contract, `DIALOGUE_ORDER` 50). It opens `ChipInstallScreen`, a two-section overlay: **Install your chips** (chips already in the backpack, priced at the labour fee) and **For sale — buy & install** (chips the mechanic stocks that you don't carry, bought and fitted in one payment).

**Stock**
- **`stock_counts: Array[StockEntry]`** — the chips this mechanic sells (same `StockEntry` rows as `Merchant`). Only entries whose `item.is_upgrade_chip()` are stocked; a stray non-chip line is ignored. Leave empty for an install-only mechanic (the player must find every chip in the world).

**Display**
- **`installer_name: String`** — hover ("Upgrades: <name>") + screen title; blank → "Mechanic".

**Pricing** (all derived from the chip Item's `value`, so tune the price on the chip `.tres`, the rates here):
- **`install_mult: float`** (default `0.5`) — fee to install a chip the player **already carries** = `value × install_mult`, floored at `min_fee`. Just labour, so cheaper than the chip.
- **`buy_mult: float`** (default `1.25`) — sale markup for a **stocked** chip. The buy-&-install total is `value × buy_mult` **plus** the install fee, so buying here always costs more than fitting a chip you found — finding chips is rewarded.
- **`min_fee: int`** (default `10`) — floor on the install fee, so a cheap chip still costs something to fit.

**Behavior**
- **`standalone: bool`** — `true` for a workbench/kiosk you aim at; `false` under a dialogue NPC.

Installing consumes the chip (it goes into the machine — a bought chip never enters the bag), charges the player through the wallet seam (`add_money`), grants the ability, and **autosaves** (a new mechanic is a milestone). The grant persists in `GameState.unlocks` like any unlock, so it survives a reload; the consumed chip stays gone. The player reviews what's fitted at any time on the **Implants** tab (**I** — see "The player's menu screens"): installed abilities on top, carried-but-unfitted chips below with a "find a mechanic" hint. **Clicking an installed row switches that implant off** (click again to switch it back on) — a reversible, free preference, not an uninstall: the ability stops working everywhere (`has_mechanic` reads false, so every gate — air dash, fall immunity, takedown, gated doors — turns off, a live slide ends and a live grapple rope severs) but the implant stays **owned**. It keeps its row, the mechanic still refuses to re-sell you the chip, and the off state persists (`GameState.disabled_unlocks`). Installing is still the only paid step, and it still happens at a `ChipInstaller`.

**Two predicates, and which one your code wants.** `Player.has_mechanic(id)` = **active** (installed AND switched on) — that is what every gameplay gate should ask, and the default for anything new. `Player.mechanic_installed(id)` = **installed** (owned, switched on or off) — for economy/UI questions like "do they already have this, so don't sell it again". Getting these backwards is how a switched-off implant becomes re-sellable, so the `ChipInstaller` guards deliberately use `mechanic_installed`.

**A new Ability with live state should override `on_deactivated()`** (`scripts/components/abilities/ability.gd`) to end whatever it has in flight — the hook fires when the player switches the implant off, so a later switch-on can't resume stale state. `Slide` ends the slide, `Grapple` severs the rope; a pure gate (air dash, fall immunity) needs nothing.

**Authoring a chip Item.** A chip is an ordinary `Item` `.tres` (see "Items, loot, money and pickups") with two things set: **`installs_ability`** (group **Upgrade Chip**) — an `ENUM_SUGGESTION` dropdown of the ability ids on disk (the *same* `AbilityRegistry` list `UpgradePickup.unlock_id` uses) — and **`world_model` = `res://assets/models/microchip/microchip.glb`** so it looks like a microchip in the world and inventory. The shipped set is `resources/items/chip_*.tres` (one per ability, `value` tuned per upgrade). After adding a chip, bake its icon (CYBER SUNDAY → Icons, or `scripts/tools/bake_item_icons.gd`).

**Placing the mechanic.** `res://scenes/characters/chip_mechanic.tscn` is a ready, neutral NPC (a dialogue-driven `ChipInstaller` stocked with a couple of chips) — drop it in a level and it works. `TestLevel_2` has one placed, plus a couple of chip world-drops (`CanPickUp` with `build_model_from_item`) and a `MoneyPickUp`, so the whole find → pay → install loop is playable there.

### ChessMatch (the "Play Chess" option) — `rpg/scripts/components/chess_match.gd`

Drop a **`ChessMatch`** under an NPC (or a chess table prop) — it's in the CYBER SUNDAY **Add-Component palette** under *World Objects* (the Board Visualizer ability is under *Player*) — to let the player sit down for a game of **blindfold chess**. The dialogue adds "Play Chess" via the match's dialogue-station contract (`DIALOGUE_ORDER` 60); picking it *suspends* the conversation and opens `ChessScreen` (which reads the match's config getters, `ai_search_depth` / `display_opponent_name` / …) — closing the board drops you back into the conversation rather than ending it. Same dual `standalone` pattern as the other stations (`true` = a table you aim at; `false` = a dialogue NPC's option). Moves are **typed as text** (coordinate like `e2e4` or SAN like `Nf3`); there is **no rendered board** until the player installs the **Board Visualizer chip** (below) — that's the whole point.

- **`opponent_name: String`** — hover ("Play Chess: <name>"), the match title, and the move-log speaker. Blank → "Opponent".
- **`ai_depth: int`** (1–4, default `2`) — the opponent's search plies. `1` = a pushover that only sees immediate captures; `2` = a solid club player; `3+` = sharp but slower to move (each ply multiplies think time, so keep it modest for snappy turns).
- **`ai_blunder_chance: float`** (0–1, default `0.15`) — chance per turn the opponent throws the search away and plays a *random* legal move. Higher = easier + more characterful (a drunk at `0.4` hangs pieces; a master at `0.0` never slips). This is the main "make it beatable" knob.
- **`player_plays_white: bool`** (default `true`) — `true` = you are White and open the game; `false` = the opponent is White and moves first, so you reply blindfold to an opening move (the harder, hustler-favoured start).
- **`wager: int`** (default `0`) — zorkmids staked. `0` = a friendly game (always playable). `> 0` = win **+**, lose **−**, draw even; the match refuses to start unless the player can cover the stake.
- **`standalone: bool`** — `true` for a table you aim at; `false` under a dialogue NPC (so the ray doesn't steal the conversation).

**The Board Visualizer chip.** `resources/items/chip_chess_visualizer.tres` is an ordinary upgrade chip (`installs_ability = &"chess_visualizer"`) — stock it on any `ChipInstaller`, or scatter it as a `CanPickUp` world-drop, and it installs exactly like Wall-Climb or Grapple. Once installed, `ChessScreen` renders the 8×8 board (in the player's orientation, last move highlighted) instead of the blindfold placeholder. It persists in `GameState.unlocks` like every ability, so it's a permanent upgrade — the chip is the difference between blindfold and sighted play. See `scripts/chess/README.md` for the engine/AI internals and known limitations (e.g. threefold-repetition draws are not implemented; an in-progress game is session-only).

### Bonfire (the "Rest" option) — `rpg/scripts/components/bonfire.gd`

Drop a **`Bonfire`** under a campfire prop or NPC. The dialogue adds "Rest" via the bonfire's dialogue-station contract (`DIALOGUE_ORDER` 30 — and the one **act-and-close** station: no sub-screen, so picking it rests and then *ends* the conversation instead of suspending it). Resting is instant: it **full-heals** (HP + limbs), sets **this** node as your respawn point via `GameState.set_respawn(global_position, global_rotation.y)`, and autosaves via `GameState.autosave`. On death you return *here* — the world is not reset.

- **`bonfire_name: String`** — hover + toast ("Rested at <name>"). Note the *hover* label when blank reads "Rest at bonfire" (not "Bonfire"), and the toast when blank reads "Rested at the bonfire".
- **`standalone: bool`** — `true` for a lit campfire you aim at; `false` to expose it through a dialogue NPC's "Rest".

### LevelUp (the "Level Up" option) — `rpg/scripts/components/level_up.gd`

### XP, levels, and skill points — `rpg/resources/tuning/XpSettings.gd`

CYBER SUNDAY has **two parallel progressions**, and it's worth keeping them straight:

- **Stats** (`strength` … `agility`) are bought one point at a time for zorkmids at a **`LevelUp`** station (below). "Total level" there is just the *sum of your six stats* (= points purchased).
- **XP / character level** is the new automatic track. You earn XP from kills and quests, cross thresholds, and each crossing grants **skill points** — the currency the perk *picker* (also below) and a `LevelUp`'s perk section spend. This track needs **no station to advance** — XP accrues during normal play.

The whole XP curve is two knobs on one global tuning group, **`XpSettings`**, read as **`GameSettings.xp`** and authored as `resources/tuning/XpSettings.tres` (it's a row in the GameSettings registry, §12). There's no `Curve` resource — it's a gentle quadratic from:

- **`base_xp: float`** (default `100.0`) — XP for the *first* level (the linear term). Higher = slower early leveling.
- **`per_level_growth: float`** (default `50.0`) — added growth per level (the quadratic term). The cumulative XP to *reach* level n is `base_xp×n + per_level_growth×n×(n-1)/2`.
- **`points_per_level: int`** (default `1`) — skill (perk) points granted per level **crossed**. `1` = one pick per level.
- **`xp_per_kill: float`** (default `25.0`) — flat XP bounty per NPC kill. **`0` = kills give no XP** (a pure quest-XP game).

**Where XP comes from.** Two seams feed `Player.add_xp(amount)`:

1. **Kills** — any player-caused NPC death awards `GameSettings.xp.xp_per_kill` (the NPC routes it to the live player on death; `_award_kill_xp`, `npc.gd`). No per-NPC field — it's the one global bounty.
2. **Quests** — a `Quest`'s **`reward_xp: float`** (`@export`, default `0.0`; `quest.gd`) is paid out alongside `reward_money` / `reward_reputation` on turn-in (`GameState.gd`). `0` = no XP for that quest.

**What a level-up does.** `add_xp` recomputes the character `level` from the curve; for **each level crossed** it grants `points_per_level` skill points to the player's `PerkManager` (raising both its spendable `skill_points` and its cumulative `points_earned`), toasts "Level N! +K skill points" (a real singular template — "… +1 skill point" — when K is 1, not an "(s)"), and autosaves. XP and the derived level both persist in the save (the level is cached so a save survives a later `XpSettings` retune). The player emits `xp_changed(xp, level)` and `leveled_up(new_level, points_gained)` for any HUD/listener.

> **Skill points are spent on perks, not stats.** A level-up grants *perk* skill points (used by the perk picker / `RespecStation`); raising a *stat* still costs zorkmids at a `LevelUp`. They're deliberately separate economies.

#### Gotchas

- **Skill points live on the `PerkManager`, not the Player.** `Player.add_xp` forwards them; the picker and `RespecStation` read `pm.skill_points`. You never place the `PerkManager` (it auto-creates under the player on first XP or first perk — see "Perks").
- **`xp_per_kill = 0` disables kill XP entirely** — handy for a quest-only build. Likewise a quest with `reward_xp = 0` gives no XP. Neither is a bug.
- **A respec refunds points up to `points_earned`, not beyond.** Cumulative earned points are tracked so free/repeatable station grants can't be farmed into infinite skill points (see `RespecStation`).

Relevant files: `rpg/resources/tuning/XpSettings.gd`, `rpg/scripts/player/player.gd` (`xp` / `level` / `add_xp`), `rpg/scripts/npc/npc_mortality.gd` (`award_kill_xp`, via the `NPC._award_kill_xp` facade), `rpg/scripts/quests/quest.gd` (`reward_xp`), `rpg/managers/GameState.gd` (quest turn-in).

Drop a **`LevelUp`** under a trainer or shrine. The dialogue adds "Level Up" via the station's dialogue-station contract (`DIALOGUE_ORDER` 40); it suspends the conversation and opens `LevelUpScreen`, where the player spends zorkmids to raise any one of `strength`, `endurance`, `gunplay`, `agility`, `streetwise`, or `larceny` by 1.

- **`station_name: String`** — hover + screen title; blank → "Level Up".
- **`base_cost: int`** (default `1`) — cost at total level 0.
- **`cost_per_level: float`** (default `1.5`) — added per point already invested, so cost climbs Dark-Souls style with your total level (the sum of all six stats). Formula: `maxf(0, base_cost + (total_level × cost_per_level))`.
  - **The floor matters below baseline.** Character creation permits a *net-negative* build (every stat can sit at −5), so total level can be **negative** and the raw curve would price under zero — which doesn't discount a raise, it *inverts* it (a negative charge pays the player). The cost bottoms out at **free** instead: training a sub-baseline character costs nothing, and a free raise still **works** (it's the floored price, not a refusal) — including for a wallet in debt, mirroring `RespecStation`'s zero-cost convention. Raise `base_cost` if you'd rather weak characters still pay something.
- **`accepts_credit: bool`** (default **`false`**) — **this trainer does not lend.** A raise is funded from pocket cash and banked savings only; the till will not push the account past zero onto the credit line, whichever rail the player armed elsewhere. The screen hides its DEBIT/CREDIT selector and prints the terms in its place.
  - **Why it is off by default, and why you should think hard before turning it on.** The credit *limit* is re-rated live off the permanent stat sheet (`Player.credit_limit()`), and this is the only till in the game that **sells entries on that sheet** — so a stat point bought on borrowed money raises the very line that paid for it. On the shipped knobs the first point costs 1 zm and lifts the line from 200 to 300 zm; each of the first fifteen purchases opens more credit than it consumes; and the ladder runs out at total level **51 with 2022 zm owed — the same for every starting build**, because character creation is zero-sum so all of them meet the identical cost curve. That is roughly 1,964 kills’ worth of bounty handed over in one sitting, and it erases the build the player just made. `Atm.withdraw` already states the invariant it violates — "the credit line funds PURCHASES, never cash" — and a stat point is worse than cash, because it converts back into credit. (It is *not* a die-and-keep-it loop: the debt is death-safe too, so dying settles nothing.) Turn it on for a deliberate loan-shark trainer, knowing that is what you are authoring.
  - Distinct from `Merchant.accepts_ledger`, which is **cash-only** (it refuses savings too). This knob refuses *credit alone*; it rides the payment seam’s `allow_credit` parameter, so the station gate, the row dim and the quoted total all obey one answer.
- **`requires_settled_account: bool`** (default **`true`**) — **no paid raise while you are in the red.** This is the other half of the same rule, and it is the half that actually holds. A credit line is **fungible into cash** at any ledger vendor: buy an item on the CREDIT rail, sell it straight back (`Merchant.sell` pays out in *cash*, and `sell_price` is clamped to only `min_vendor_spread` under `buy_price`), and you are holding almost the whole line as coins — which a cash-taking till would accept. The shipped Medicine Person carries a `Merchant` **and** a `LevelUp` on the same NPC, so that round trip is one conversation. Requiring a settled account closes it arithmetically instead of chasing the laundry: you cannot hold laundered cash without being in the red, and clearing the red costs more than the round trip returned. A **free** raise still serves a debtor — this gates the fee, never the service. Turning it off re-opens the laundering path even with `accepts_credit` off; the two knobs are one rule. Both pinned by `tests/test_level_up_credit.gd`.
- **`standalone: bool`** — `true` for a self-serve shrine; `false` under a dialogue NPC.

**Flat, Dark-Souls cost — the same for every stat.** Cost depends **only** on total level, not on which stat you buy or how high it already is: raising a maxed stat costs exactly what raising a fresh one does. There's no per-stat "specialization tax" — the old `cost_per_stat_point` export is **gone**. One curve, identical across all six stats.

Strength raises max HP (`max_hp_bonus()`) and carry capacity (`carry_bonus()`) automatically — both applied as a *delta* so the bonus isn't double-counted; the other stats (and strength's melee-damage component) are read live at their own seams. Raising a stat also heals you by the gained max HP and autosaves the run.


> **Dark-Souls bonfire pattern:** put a **`Bonfire`** *and* a **`LevelUp`** on the same node. Resting heals + sets respawn, and the same spot lets you spend levels.

---

### Perks (the PerkStation shrine)

A **perk** is a permanent player upgrade you author once as a `.tres` and hand out at a shrine — a bundle of permanent stat bonuses and/or a granted ability, optionally gated behind prerequisite perks (a simple tree). Like a `LevelUp`, a perk's stat bonuses run through the same private-sheet + strength delta handling, so a perk's `strength` raises both max HP and carry capacity exactly the way leveling does. Like an `UpgradePickup`, a perk can also grant an ability scene under the player. None of it needs code — you fill a `Perk` resource and drop one `PerkStation` node.

> **Two paths now.** A perk is unlocked either at a `PerkStation` (a free station grant) **or** by spending an XP-earned *skill point* on a `LevelUp` screen's perk picker. `LevelUp`'s `available_perks` export is now **wired** — a non-empty list grows a "Perks" section on the Level Up screen. See "The level-up perk PICKER" below and "XP, levels, and skill points" above.

#### 1. The Perk Resource (`rpg/scripts/player/perk.gd`)

A `Perk` (`class_name Perk`, an `@tool` Resource) is the data atom. Create one with **right-click in the FileSystem → New Resource → Perk** and fill it in:

- **`id`** (StringName) — the stable lookup key, unique per `.tres` (e.g. `&"tough_skin"`). The `PerkManager` records and prerequisite-checks perks by this id; an empty id can never unlock.
- **`display_name`** (String) — shown in the "Learn: …" hover and the "Learned: …" toast. Blank falls back to the `id`.
- **`description`** (multiline) — detail text.
- **`icon`** (Texture2D) — optional display icon.
- **`stat_bonuses`** (Dictionary) — permanent stat deltas applied on unlock, e.g. `{ "strength": 2, "agility": 1 }`. **Keys MUST be `CharacterStats` attribute names** — `strength`, `endurance`, `gunplay`, `agility`, `streetwise`, `larceny` — and any unknown key is **ignored AND warned** (`Perk.validate()` runs on unlock and `push_warning`s the bad key), so a typo grants nothing but no longer fails silently — watch the editor/console output. `strength` bumps both max HP and carry capacity automatically (same delta math as `LevelUp`); the other five (and strength's melee-damage component) are read live at their own seams.
- **`grants_ability`** (PackedScene) — *optional* ability scene instanced under the player on unlock, exactly like an `UpgradePickup`'s `grants` (drag in a scene from `scenes/components/abilities/`). Leave null for a pure stat perk.
- **`requires_perks`** (`Array[StringName]`) — prerequisite perk ids that must already be unlocked before this one can be. Empty = always available. This is how you build a tree (see below).
- **`combat_bonuses`** (Dictionary) — **RULE-CHANGING combat effects (PD-2)**, the perk's effect on the *damage math* rather than the stat sheet. Keys are **fractions**: `{ "damage": 0.1 }` = +10% weapon damage, `{ "crit": 0.25 }` = +25% headshot/crit damage. These are summed **LIVE** across every unlocked perk and read at the damage seam — so unlike `stat_bonuses` they're never stamped onto a sheet, and a respec reverses them automatically just by clearing the unlock. Empty = no combat effect (a pure stat / ability perk is unchanged). Stack two `damage` perks and their fractions add. (The keys `pierce` / `reload` are reserved for their own future seams — only `damage` and `crit` bite today.)


#### 2. The PerkStation component (`rpg/scripts/components/perk_station.gd`)

A `PerkStation` (`class_name PerkStation`, an `@tool` node that **extends `LookAtInteractable`**) is the drop-in shrine. The player aims at it, presses **F (Interact)**, and the perk is applied. It inherits the whole look-at family — `highlight_target`, `highlight_color`/`highlight_width`, and `auto_fit_collider` — and adds two knobs:

- **`perk`** (Perk) — the perk this station grants. Unassigned → the station can't be interacted with (and the inspector shows a configuration warning).
- **`consume_on_use`** (bool, default `true`) — free the station after a successful grant (a one-time shrine). Set `false` to leave it standing.

There's **no shipped `.tscn`** for the station — author it the way you author an `UpgradePickup`: drop a plain `Area3D` under the shrine prop, attach `perk_station.gd`, size its `CollisionShape3D` (or tick `auto_fit_collider`), and assign `perk`.

**How the grant works.** On the first interaction the station finds the player's `PerkManager` child (a `Node` named `"Perks"`) or **auto-creates one** — you never place it. The manager owns a **private duplicated `CharacterStats`** sheet (it never mutates a shared `.tres`) and re-applies the same `strength → max_hp` and `strength → carry` deltas as `LevelUp`, then instances `grants_ability` (if any) under the player. The unlock is gated by `can_unlock`: the perk must be valid, **not already owned**, and **all of its `requires_perks` already unlocked**. A successful grant toasts "Learned: \<name>" (and frees the station if `consume_on_use`); a blocked or repeat attempt toasts "Already learned" and leaves the station in place.

**Worked example — a "Tough Skin" shrine**

> Goal: aim at a shrine, press F, gain +2 strength (and the matching max-HP bump — plus extra carry capacity and melee damage) once.

1. Create `tough_skin.tres` (**New Resource → Perk**). Set `id = &"tough_skin"`, `display_name = "Tough Skin"`, and expand `stat_bonuses` to one row: key `strength`, value `2`.
2. In your level, drop an `Area3D` under the shrine `MeshInstance3D`, attach `perk_station.gd`. Leave `consume_on_use = true` and tick `auto_fit_collider` (or size the `CollisionShape3D` to the shrine).
3. Assign `perk = res://.../tough_skin.tres`.
4. Run. The hover reads **"Learn: Tough Skin"**; pressing F toasts **"Learned: Tough Skin"**, adds +2 strength — bumping max HP, carry capacity, and melee damage — and the station frees itself.

**For a perk tree**, author a second `Perk` — say `iron_hide.tres` — with `requires_perks = [&"tough_skin"]`. Its station will refuse to grant (toasting "Already learned"/no-op) until the player has learned Tough Skin first, then unlocks normally.

#### 3. The level-up perk PICKER (`LevelUp.available_perks` — now wired)

There are now **two ways** a player learns a perk: aim at a `PerkStation` (above), or **pick one on a `LevelUp` screen** for a *skill point* earned by gaining XP. The picker is live — `LevelUp`'s perk-export group is no longer authored-ahead data.

A `LevelUp` (standalone *or* on a dialogue NPC) carries:

- **`available_perks: Array[Perk]`** (`@export_group("Perks")`) — the perks this station offers. **Non-empty turns the picker on**: the Level Up screen grows a "Perks — N points" section ("… — 1 point" singular) below the stat rows, one selectable row per perk. Empty = no perk section.
- **`perk_points_per_level: int`** (default `1`) — authored alongside; documents picks-per-level for the design (the actual point grant runs through `XpSettings.points_per_level` on the PerkManager).

**How a pick works.** Clicking an available perk calls `LevelUp.unlock_perk(player, perk)`, which spends **one skill point** off the `PerkManager` and unlocks the perk through the *same* `PerkManager.unlock_perk` path a `PerkStation` uses — applying its `stat_bonuses` (with the strength→max-HP / strength→carry deltas) and granting any `grants_ability`. The pick is gated by **a spare skill point AND `can_unlock`** (perk valid, not already owned, all `requires_perks` met). A row is disabled + dimmed when it's already owned (labelled "(owned)"), its prereqs aren't met, or you have zero points; its `description` shows as a hover tip. Picking autosaves; the station is **not** consumed (keep leveling). No zorkmids are charged — perks cost skill points, stats cost money.

So a single `LevelUp` shrine can do both: raise stats for cash *and* spend XP-earned skill points on the perks you authored into `available_perks`. A `PerkStation` remains the *station-only* alternative (no skill point needed — it just grants).

Relevant files: `rpg/scripts/components/level_up.gd` (`available_perks` / `unlock_perk`), `rpg/scripts/ui/level_up_screen.gd` (the picker UI), `rpg/scripts/components/perk_manager.gd` (`skill_points` / `can_unlock` / `unlock_perk`).

#### 4. The RespecStation component (`rpg/scripts/components/respec_station.gd`)

A **`RespecStation`** (`class_name RespecStation`, an `@tool` node that **extends `LookAtInteractable`**) is the respec twin of `PerkStation`: aim at it, press **F (Interact)**, pay a fee, and **every** unlocked perk is reversed — its stat bonuses undone (max-HP / carry deltas telescope back to baseline), its granted ability revoked, and the skill point refunded — leaving the player free to re-pick from scratch at a `LevelUp`. It inherits the look-at family (`highlight_target`, `highlight_color`/`highlight_width`, `auto_fit_collider`) and adds two knobs:

- **`station_name: String`** — hover label; blank → "Respec".
- **`respec_cost: float`** (default `100.0`) — zorkmids charged per respec. **`0` = free.**

**How the respec works.** On interaction the station finds (or auto-creates) the player's `PerkManager` and calls `respec()`: it walks the unlocked perks in **reverse unlock order** (so a prereq-child is undone before its prereq, keeping each intermediate sheet valid), reverses every perk's stat-bonus and derived deltas, revokes each granted ability, clears the ledger, and **refunds `skill_points` back up to `points_earned`** (the cumulative count of points *earned via XP* — so free station grants never inflate the refund). It autosaves the reversed build. The station is **never consumed** — respec as often as you can pay. It refuses (with a toast) when there are no perks to respec, or when you can't afford `respec_cost`.

There's **no shipped `.tscn`** — author it like a `PerkStation` (bare `Area3D` + `respec_station.gd`, size/fit the collider). Interacting opens a **`RespecScreen` confirm modal** (the cost + the perks that will be refunded, with Confirm / Cancel) — real-time like every station screen, so the world keeps running while you decide; confirming toasts "Respec: N perks refunded" ("… 1 perk refunded" singular).

**Worked example — a respec shrine for 250 zm**

> Goal: aim at a shrine, press F, pay 250, get all perks (and their skill points) back.

1. Drop an `Area3D` under the shrine `MeshInstance3D`, attach `respec_station.gd`.
2. Set `station_name = "Memory Wipe"`, `respec_cost = 250`, tick `auto_fit_collider` (or size the `CollisionShape3D`).
3. Run. The hover reads **"Respec: Memory Wipe"**; pressing F opens the confirm modal — clicking **Confirm** charges 250, reverses every perk, refunds the skill points (up to what XP earned), and toasts the count. Re-pick at any `LevelUp` with a perk section.

**Gotchas**

- **`respec_cost = 0` makes it free** — fine for testing, but pair it with a real cost in the shipped level or players will respec every encounter.
- **Refund is capped at XP-earned points.** If a perk was granted free at a `PerkStation` (not paid for with a skill point), respeccing it does **not** hand back a spendable point — `points_earned` only rises on XP level-ups. This is intentional anti-farming.
- **Confirms before it wipes.** Interacting opens the `RespecScreen` modal (mirrors `LevelUpScreen` / `HealScreen`) — nothing is charged or reversed until you click **Confirm**; **Cancel**, the Interact key, or Esc backs out. Confirm is disabled (with the reason in the button) when you have no perks or can't afford the cost.
- **You don't place the `PerkManager`.** Like the other perk components, the station auto-creates it.

Relevant files: `rpg/scripts/components/respec_station.gd` (`do_respec` / `perk_manager`), `rpg/scripts/ui/respec_screen.gd` (the confirm modal — a `RespecScreen` autoload), `rpg/scripts/components/perk_manager.gd` (`respec` / `unlocked_perks` / `skill_points` / `points_earned`).

**Gotchas**

- **`stat_bonuses` keys must be exact `CharacterStats` names.** `strength` / `endurance` / `gunplay` / `agility` / `streetwise` / `larceny` only — any other key (a typo, a made-up stat) is dropped and grants nothing, but `Perk.validate()` now `push_warning`s it on unlock, so check the console if a perk does less than you intended.
- **Two ways to learn a perk.** A `PerkStation` grants one for free (aim + E); a `LevelUp` with a non-empty `available_perks` lets the player *spend an XP-earned skill point* on it via the on-screen picker. Both route through the same `PerkManager.unlock_perk`, so prereqs / one-grant-per-id apply either way.
- **One grant per perk id.** Re-interacting (or a second station with the same `perk`) is a no-op — the manager tracks owned ids and `can_unlock` returns false. Set `consume_on_use = false` only if you *want* the shrine to stay (it still won't double-grant).
- **You don't place the `PerkManager`.** It auto-creates under the player on first use. Don't pre-add a node named "Perks" by hand.
- **No `.tscn` ships.** Build the station like an `UpgradePickup` — bare node + script — and remember to size/fit its hitbox, or E will do nothing.

Relevant files: `rpg/scripts/player/perk.gd`, `rpg/scripts/components/perk_station.gd`, `rpg/scripts/components/perk_manager.gd`, `rpg/scripts/components/level_up.gd`.

---

### Companions: the "Follow me" / "Wait here" option

Recruitment is different — it isn't a separate component you drop on, it's a **contract already built into the `NPC` script** (`rpg/scripts/npc/npc.gd`). The dialogue's `CompanionRecruiter` (`rpg/scripts/dialogue/companion_recruiter.gd`) checks the speaker for `can_recruit` / `is_following` and shows the right label:

- A recruitable NPC offers **"Follow me"** → calls `start_following(player)`; the NPC acknowledges with a spoken "Alright." and joins the `&"Player"` group so enemies treat it as an ally, wears the blue companion rim, and tails you.
- A companion already at your side offers **"Wait here"** → calls `stop_following()`; the button flips back to "Follow me".

What makes an NPC recruitable is **`can_recruit()`**, which is true only when:
1. its **resolved disposition toward the player is `FRIENDLY`** (`resolved_disposition() == Disposition.Kind.FRIENDLY`), and
2. it isn't already following someone (`not is_following()`).

So to author a recruitable companion, the lever is the NPC's **`disposition`** `@export` (`Disposition.Kind`, defaults to `HOSTILE`). Set it to **`FRIENDLY`** in the inspector (or via the NPC's profile / `disposition_overrides_faction` if faction would otherwise win out). A merely *neutral* or hostile NPC will *not* show the recruit button — that's by design. No extra node is required for basic recruitment.

The follow *behaviour* (escorting at a standoff, and the off-screen "blink up behind you" teleport) lives in the **`CompanionFollow`** child (`rpg/scripts/npc/companion_follow.gd`) that `NPC` builds for itself at runtime; you don't place it. Its dials (`follow_standoff`, `follow_teleport_distance`, `follow_teleport_cooldown`) are global tunables on **`GameSettings.npc_ai`** (a `NpcAiSettings` resource), not per-instance exports.

**Bonus — "Exchange Gear":** once an NPC is *following you* and carries a `CharacterInventory` (its `inventory` reads as one), the dialogue also offers "Exchange Gear" (a two-way transfer screen, `LootScreen.exchange`, capped by the companion's carry capacity). This is automatic for any following companion with a backpack — nothing extra to author.

---

### Worked example: a guard who chats, trades, and can join you

1. In your level scene, add the NPC (a node using the `NPC` script with a `Talkable` child for conversation and a `DialogueResource` assigned).
2. In the inspector, set the NPC's **`disposition` = `FRIENDLY`** (this both makes them non-hostile and unlocks "Follow me").
3. Add a **`Merchant`** node as a *direct child* of the NPC. Set **`standalone` = false**. Set `shop_name = "Surplus"`, `money = 500`, `buy_mult = 1.2`, `sell_mult = 0.4`.
4. Fill `stock_counts`: add three `StockEntry` resources — `{ item: healthpack.tres, count: 3 }`, `{ item: ammo_pistol.tres, count: 20 }`, `{ item: shotgun_item.tres, count: 2 }` (all under `res://resources/items/`; note that `res://resources/weapons/shotgun.tres` is the `WeaponData`, NOT the `Item` — `StockEntry.item` only accepts an `Item`).
5. (Optional) Add a **`Bonfire`** child with `standalone = false`, `bonfire_name = "Guard Post"`, so the same guard lets you rest and set a respawn.

Now: aim at the guard, press Interact, listen to their line, click to reveal the menu — and you'll see your authored choices plus **Trade**, **Rest**, **Follow me**, and **Goodbye**. Trade runs its service and returns you to the conversation; **Rest is instant and ENDS the conversation** — it full-heals (HP + limbs), sets this bonfire as your respawn point, autosaves, toasts, and closes the dialogue box. "Follow me" recruits them.

### Vendor / container restocking (`Restocker`)

A shop you clean out or a crate you loot stays empty forever unless you say otherwise. Drop a **`Restocker`** (`rpg/scripts/components/restocker.gd`, `@tool`, plain `Node`) as a **child of the `Merchant` / `ItemContainer`** (or, in `TIMER` mode only, point `target_path` at one) and it refills the host back up to its fixed authored stock/item rows. **`ON_VISIT` requires it to be a direct child of the host** — the host calls `Restocker.notify_visit(self)`, which scans only its own children, so a `target_path`-only `Restocker` in `ON_VISIT` mode never fires and the editor gives no configuration warning.

- `mode` — `TIMER` refills on a clock every `interval` seconds; `ON_VISIT` refills when the player next opens the host (the first visit always restocks; later re-opens are rate-limited to no more often than `interval`, so rapid re-opening doesn't spam stock). **One exception to "the first visit always restocks":** if a manual quicksave/slot load just restored an `ItemContainer`'s exact contents, its child `Restocker`s are marked spent, so the first reopen after loading does *not* top the restored bag back up (otherwise every quickload would be a free instant restock). The cycle resumes normally one `interval` later. If you loaded a save and wondered why your emptied crate stayed empty, that's this.
- `interval` — seconds between restocks. **`0` = use `GameSettings.economy.restock_interval`** (the global default, 60 s) so you can tune every vendor's pace from one place.
- `target_path` — the host to refill. Empty = this node's parent.

The host's `refill()` only adds the **shortfall** versus its authored stock/item rows — it never doubles a partially-bought shelf and never removes what the player sold into the till or deposited in the crate. So a `Merchant` whose `stock_counts` lists 5 stims, sold down to 2, climbs back to 5 (not 7), and the gun the player dumped on the vendor stays for sale. An `ItemContainer` refills from `item_stacks` only; authored `money` is not re-seeded and the optional `loot_table` is not re-rolled. An `ON_VISIT` `Restocker`'s refill is triggered by the host in `start_talk` before opening, so the player always sees the topped-up goods. (The same global default lives on `EconomySettings.restock_interval`, group **Restock**.)

### Gotchas

- **Direct child only.** The dialogue manager does a *shallow* scan of the speaker's immediate children. A service component nested two levels deep won't be detected.
- **`standalone = false` for dialogue-driven services.** If you leave it `true` on an NPC, the component sits on the talk layer and the aim ray can fight the NPC's own `Talkable` for the interaction. Off means data-only — its `collision_layer` goes to `0`, the ray ignores it, and the dialogue option is the only door.
- **Recruitment hinges on disposition.** No "Follow me" button means the NPC's `resolved_disposition()` isn't `FRIENDLY` — check the `disposition` export (and faction/`disposition_overrides_faction` if a faction is overriding it). Neutral is not enough.
- **The follow component is not hand-placed.** Don't add `CompanionFollow` yourself; the `NPC` builds it. Its standoff/teleport numbers are global tunables on `GameSettings.npc_ai`, not per-NPC exports.
- **Heal/Level Up cost can be free/refused.** A healer charges nothing at full health; a level-up is blocked if the player can't afford the (rising) cost — but a level-up priced at **zero** (a sub-baseline build, where the cost curve floors) is served free rather than refused, debt included. All intentional, not bugs.
- **Merchant till limits buybacks.** A merchant with low `money` literally cannot buy expensive items from the player — raise `money` if you want a deep-pocketed fence.
- **The "Bank" option is one button, not two.** A teller's `Atm` child grows a single "Bank" choice; deposit, withdraw and paying a debt down all live on the terminal's own screen, so there is nothing extra to author (and nothing to hide when the player is in the red).

Relevant files: `rpg/scripts/dialogue/dialogue_manager.gd`, `rpg/scripts/dialogue/companion_recruiter.gd`, `rpg/scripts/components/merchant.gd`, `rpg/scripts/components/stock_entry.gd`, `rpg/scripts/components/healer.gd`, `rpg/scripts/components/bonfire.gd`, `rpg/scripts/components/level_up.gd`, `rpg/scripts/components/atm.gd` + `rpg/scripts/ui/atm_screen.gd` + `rpg/scripts/components/ledger_accrual.gd` (the ledger terminal, its view, and the interest posting), `rpg/scripts/npc/npc.gd` (the companion contract: `can_recruit` / `start_following` / `stop_following` / `is_following`), `rpg/scripts/npc/companion_follow.gd`.

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
- **`reward_xp`** (float, default `0.0`) — XP added to the player on completion (it routes to `Player.add_xp`, which levels you up and may pop the perk picker — see §13). `0` = no XP reward.
- **`reward_reputation`** (Dictionary — faction id → delta) — **wired and granted on completion.** Author it as `{ "townsfolk": 15, "raiders": -10 }`: each key is a faction id (the `faction_id` dropdown values, §7), each value the standing delta. On completion `GameState` resolves every id via the Factions registry and calls `Reputation.add_reputation`, so finishing the quest can raise your standing with one faction and tank it with another. (Reputation is granted even with no player in the world — money + items + XP need a live player. Off-tree / in a bare test with no `SceneTree`, nothing at all is granted, not even reputation.)

**Flow**
- **`auto_complete`** (bool, default `true`) — finish + pay out the instant every non-optional objective is met. Turn it **off** to require an explicit turn-in (a `GameState.complete_quest(id)` call, e.g. from a "hand in the quest" dialogue option).
- **`expire_on_flag`** (StringName, default `&""`) — **WR-6 optional expiry.** While the quest is **ACTIVE**, setting this `GameState` story flag auto-**FAILS** it — the "you missed the window" trigger (fire the flag when the hostage dies, the bomb detonates, the deadline timer ends). Empty = the quest **never expires** (the default). A failed quest grants nothing, can't be re-started, and opens the `FAILED` dialogue gates (§8). See "Failing and expiring a quest" below.
- **`prereq_quest_id`** (StringName, default `&""`) — a quest that must be **COMPLETED** before `start_quest` will begin this one (a `start_quest` on a quest whose prereq isn't done is a silent no-op). Empty = no prerequisite. Use it to gate a follow-up behind an earlier quest.
- **`next_quest`** (Quest, default `null`) — a quest **auto-started** the instant this one completes, so you can chain a storyline (finish part 1 → part 2 begins). Left `null` = nothing chains. (A **failed** quest does NOT start its `next_quest`.)

### 2. The QuestObjective Resource (`res://scripts/quests/quest_objective.gd`)

Each **`QuestObjective`** (`class_name QuestObjective`, also an `@tool` `Resource`) is one step. Author it inline in the quest's `objectives` array:

- **`id`** (StringName) — stable id, unique **within this quest**. This is the key `advance_objective` and the progress queries use.
- **`description`** (multiline) — the line shown in the Journal (e.g. "Kill the boss"). Blank falls back to the raw `id`.
- **`type`** (enum `Type { KILL, TALK, PICKUP, ENTER_AREA, USE_ITEM, FLAG }`, default `FLAG`) — what completes it. This decides which auto-hook (if any) fires it.
- **`target_id`** (StringName) — **what to match**, and its meaning depends on `type`:
  - `KILL` / `TALK` → the NPC's **identity key** — its **`NpcData.id`** where one is authored (preferred: the objective then survives a `display_name` edit/localisation, and a claimed pet renamed by the player still counts), else its **`display_name`**. A display-name target keeps matching as the fallback either way, so pre-identity quests need no edits.
  - `PICKUP` / `USE_ITEM` → the **`Item.id`**
  - `ENTER_AREA` → the **area / group name**
  - `FLAG` → the **`GameState` flag name**
  - **Dropdown:** for `PICKUP` / `USE_ITEM` the field self-populates as a **dropdown of the item ids on disk** (a suggestion — still typable), so pick from it instead of retyping. The other four types have no on-disk registry, so they stay free text and the exact-match rule below is the only guard.
- **`required_count`** (int, default `1`, range `1..9999`) — how many times it must fire (e.g. "kill 5 raiders"). Progress clamps to this.
- **`optional`** (bool, default `false`) — a bonus goal. An optional objective does **not** block the quest from completing — only the required ones gate `auto_complete`.

**Marker** (drives the compass / minimap beacon -- see §17, "Quest markers and the compass")
- **`show_marker`** (bool, default `false`) -- on = a `QuestMarkerSync` in the level spawns a compass chevron + minimap dot at `marker_position` while this objective is active, removing it when the objective is done. Off = no marker.
- **`marker_position`** (Vector3, default `Vector3.ZERO`) -- the world position the marker sits at (the objective's destination: a turn-in NPC, an area, a pickup spot). Copy it from the destination node's `Transform`.

> **Matching is string-exact.** `target_id` is compared verbatim against the NPC's identity key (`NpcData.id` / authored `display_name`) or the `Item.id`. A typo'd target (`&"Raider Boss "` with a trailing space, `&"raider boss"` lower-cased) silently never advances — the objective just sits at `[ ]` forever with no error. This is the #1 quest footgun; copy the value from the actual NpcData/NPC/Item resource, don't retype it.

### 3. The GameState API

You drive quests through three calls on the **`GameState`** autoload (`res://managers/GameState.gd`):

- **`GameState.start_quest(quest)`** — begin tracking. No-op if `quest` is null, id-less, already active, already completed, already failed, or its `prereq_quest_id` isn't completed yet (so calling it twice from a repeatable dialogue is safe). Seeds every objective to 0, emits `quest_started`.
- **`GameState.advance_objective(quest_id, objective_id, amount := 1)`** — bump one objective toward its `required_count` (clamped). When the quest `auto_completes` and every non-optional objective is met, it completes itself. No-op for an unknown quest/objective.
- **`GameState.complete_quest(quest_id)`** — finish a quest explicitly (the turn-in path for `auto_complete = false`). Moves it to the completed list, grants the rewards, emits `quest_completed`.

Signals (the Journal listens to these; you can too): **`quest_started(quest)`**, **`objective_advanced(quest, objective)`**, **`quest_completed(quest)`**.
### 3b. Failing and expiring a quest (WR-6)

A quest can also **FAIL** — a dead end, the opposite of completion: no rewards, no chaining, no re-start. There are two ways to fail one, and as a designer **you author neither in code**:

- **Explicitly, from a choice or trigger.** A `DialogueChoice`'s **`complete_quest_id`** finishes a quest; to *fail* one, set a flag instead (next bullet) — failing is flag-driven so the same `set_flag` you already use everywhere is the fire. (`GameState.fail_quest(id)` exists for scripts, but you rarely call it directly.)
- **By expiry (the usual path).** Set the quest's **`expire_on_flag`** (§1, Flow) to a story flag, then have **any** flag-setter raise that flag while the quest is active — a `TriggerVolume`'s `set_flag`, a `DialogueChoice`'s `set_flag`, or `GameState.set_flag` from a cutscene/timer. The instant the flag flips, every active quest whose `expire_on_flag` matches is auto-failed. **No new "fail trigger" component exists or is needed** — a flag write you already know how to author *is* the fail.

What failing does: the quest moves to the **failed** list, emits the **`quest_failed(quest)`** signal (the Journal listens; wire it to a toast / strike-through too), grants **nothing**, and does **not** start its `next_quest`. A failed quest is closed for good — `start_quest` refuses it forever after, so the player can't retry. State queries: **`GameState.is_quest_failed(id)`** and **`GameState.failed_quests()`** (the failed `Quest` resources, for the Journal's failed list), mirroring the completed pair.

Failing also **changes how NPCs talk to you**: the `FAILED` value on a dialogue choice's `required_quest_state` and on a `DialogueSelector` row's `required_quest_state` (both §8) light up only after the quest has failed — so a fixer can give you the cold shoulder, or a gloating villain can open a new branch, the moment you blow it.

**Worked example — a hostage you can fail to save.** On the quest: `id = &"save_hostage"`, `expire_on_flag = &"hostage_dead"`. In the level, put the death on a `TriggerVolume` (or the executioner NPC's death) whose `set_flag = &"hostage_dead"`. While `save_hostage` is active, the moment that flag fires the quest auto-fails — the Journal strikes it through, its objective markers drop off the compass/minimap (§17), no reward, and any dialogue row gated `required_quest_state = FAILED` becomes the one the giver now uses.


Completion **automatically** pays out `reward_money` (via the player's wallet) and seeds `rewards` (items) into the player's inventory. (Off-tree / in a bare test with no player in the world, the grant is a safe no-op.)

### 4. The auto-hooks (what fires objectives for free)

Five objective types advance **by themselves** when the matching gameplay event happens — you never call `advance_objective` for these:

- **`KILL`** — fires on a player-attributed NPC death, matched by the dead NPC's identity key (`NpcData.id` / authored `display_name`), with its live display string as the fallback.
- **`PICKUP`** — fires when a `CanPickUp` grant succeeds, matched by `Item.id`.
- **`TALK`** — fires when `DialogueManager.start` runs with a named speaker, matched by that speaker's identity key (an NPC's `identity_key()`; an inanimate `DialogueNPC` uses its resolved name), with the resolved speaker name as the fallback.
- **`FLAG`** — fires from **`GameState.set_flag(name)`**: setting a flag auto-advances any active objective with `type = FLAG` and a matching `target_id`. (This is how you wire a quest to the flag/trigger system — set a flag, the objective ticks.)
- **`USE_ITEM`** — fires when a **consumable is used** (`Player.use_consumable` → `GameState.notify_use(Item.id)`), matched by `Item.id`. (Only *consumables* auto-fire this; a non-consumable "use" would need a manual advance.)

The remaining one has **no auto-hook**:

- **`ENTER_AREA`** advances when something calls **`GameState.notify_enter(area_name)`** — the sanctioned producer is a **`TriggerVolume`'s `quest_area_id`** export (set it to the objective's `target_id` and drop the volume at the area). (For any objective you'd rather drive manually, a `TriggerVolume`'s `advance_quest_id` + `advance_objective_id` exports call `GameState.advance_objective(...)` directly.)

### 5. The Journal (`res://scripts/ui/quest_journal.gd`)

The Journal is a `CanvasLayer` autoload bound to the **J** key (`InputManager.action_journal`) — read-only, with **no class_name** and nothing to place in a level. Its layout is an **authored scene** (`res://scenes/ui/quest_journal.tscn` — the autoload IS that scene; the script binds the chrome by %unique name and the skin owns the look, like the other menu screens). It is the **4th Pip-Boy tab** after Inventory / Stats / Reputation, and like the other player menus it frees the cursor but **does not pause the world**.

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
   - `target_id` = `&"Raider Boss"` — this **must equal** the boss NPC's identity key, character-for-character: its `NpcData.id` if one is authored (preferred), else its `display_name` (which also always matches, as the fallback)
   - `required_count` = `1`
3. **Add the optional loot objective** in `[1]`:
   - `id` = `&"loot_intel"`, `description` = `Recover the intel`
   - `type` = `PICKUP`
   - `target_id` = `&"intel_doc"` — the **`Item.id`** of the intel document
   - `optional` = `true`
4. **Start it.** From a dialogue option (or any script), call `GameState.start_quest(load("res://resources/quests/clear_outpost.tres"))` — or, for an inspector-native quest board the player walks up to and accepts, drop a **`QuestStarter`** component (§11) with its `quest` set.
5. **Play it.** Kill the `Raider Boss` → the `KILL` hook fires, `kill_boss` is the only required objective, so the quest **auto-completes and pays out** (200 zm + 5 rounds of 5.56) on the spot. The optional intel pickup ticks whenever the player grabs the `intel_doc` (before or after), but never gates completion. Press **J** to watch `[ ] Kill the boss` flip to `[x]` and the quest drop into the completed list.

### Gotchas

- **`target_id` must EXACTLY match the NPC's identity key (`NpcData.id` / authored `display_name`) or the `Item.id`.** Matching is string-exact and silent on failure — a wrong case, trailing space, or renamed source value just never advances. Copy from the source resource. (Prefer targeting the `NpcData.id`: a display-name target breaks if you later rename the NPC, which is exactly what the id exists to survive.)
- **`ENTER_AREA` has no automatic gameplay hook.** Drive it with a **`TriggerVolume`'s `quest_area_id`** export (it calls `GameState.notify_enter`, matched against the objective's `target_id`) — authoring the objective alone does nothing. (`USE_ITEM`, by contrast, *does* auto-advance: **using a consumable** fires `GameState.notify_use(Item.id)`. Only a non-consumable "use" would need a manual `GameState.advance_objective(...)`.)
- **`reward_reputation` is granted by resource-path id.** Each key must be a real faction id (a `faction_id` dropdown value, §7) — an id that doesn't resolve in the Factions registry is silently skipped (no standing change). Copy the id from the faction, don't retype it.
- **Quest progress IS save-persisted, by resource path.** Active, completed **and failed** quests round-trip through the autosave (the `[quests_active]` / `[quests_completed]` / `[quests_failed]` cfg sections, keyed by each `Quest`'s `.tres` path — with objective progress stored on the active ones only, since a closed quest has none). A failed quest therefore stays failed across a save/load, so `start_quest` keeps refusing it and it can never be re-offered. The catch: a quest authored as a `.tres` on disk persists; a quest with no `resource_path` (built in memory, never saved) is skipped on save (with a console warning naming it) and a **renamed or deleted** `.tres` is dropped on load with a warning, not a crash. So keep your quest `.tres` paths stable once a save exists.
- **Turn-in needs `auto_complete = false`.** Leave it on and the quest finishes the instant the last required objective ticks. For a "report back to the giver" beat, turn it off and call `GameState.complete_quest(id)` from the turn-in dialogue option.
- **There is no giver field.** Nothing on the Quest names who offers it — starting a quest is always an explicit `start_quest` call (a QuestStarter, TriggerVolume, or dialogue choice).

Relevant files: `res://scripts/quests/quest.gd`, `quest_objective.gd`; the live API + auto-hooks in `res://managers/GameState.gd`; the read-only log in `res://scripts/ui/quest_journal.gd`; author quests under `res://resources/quests/`.

---

## Validating your content (the content validator)

String-exact ids are the recurring footgun across this guide — a faction id that doesn't match its filename, a duplicate item id, a perk `stat_bonuses` key that's a typo, a quest objective pointing at a name that no longer exists. There's a one-button sanity check for the silent ones: the **content validator**.

**How to run it.** In the editor, open `res://scripts/tools/validate_content.gd` and choose **File → Run** (it's an `EditorScript`, not a scene — there's nothing to drop in a level). It scans your authored resources and prints a report to the **Output** panel: `[ContentValidator] PASS — no content problems found.`, or a numbered list of problems to fix.

**What it checks** (all from `res://scripts/tools/content_validator.gd`, which the tests reuse, so the report is the same one CI sees):

- **Item ids** — flags a **blank** `Item.id` ("it can't be save/load tracked") and any **duplicate** id across the item database (ids must be unique). Also flags an **AMMO**-category item with an empty `caliber` ("no weapon can draw from it", §10).
- **Faction id == filename** — every faction `.tres` under `res://resources/factions/` must have an internal `id` equal to its filename (Reputation, and the `faction_id` dropdown, key on the internal id; a mismatch means standing silently won't apply). This is the §7 "name the file the same as the id" rule, enforced.
- **Perk `stat_bonuses` keys** — recursively scans `res://resources/` for `Perk` resources and flags any whose `stat_bonuses` has a key that isn't a real `CharacterStats` attribute (`strength`/`endurance`/`gunplay`/`agility`/`streetwise`/`larceny`) — i.e. a typo that would silently grant nothing (§13).
- **GoapProfile override names** — flags a `GoapProfile` whose goal/action override rows reference goal or action names the GOAP library doesn't define (§20).

The validator only reads — it never mutates a resource — so running it is always safe. Make it a habit before a playtest or a commit: it catches the exact "authored it, but it silently never fires" class of bug this guide keeps warning about.

Relevant files: `res://scripts/tools/validate_content.gd` (the **File → Run** entry point), `res://scripts/tools/content_validator.gd` (the reusable `ContentValidator.run()` check).

---

## Keeping the System Map in sync (architecture annotations)

Same spirit as the content validator, but for the *architecture* docs. `docs/SYSTEM_MAP.md` is a GENERATED index of the game's systems — each system's one-line **seam** (the contract other systems rely on), its silent-regression **risks**, and the **contract test** that locks it down. You never write that file by hand; you annotate the code seam and regenerate.

**How to annotate a system.** Put a `##` doc-comment block above the owning `class_name` (or, for an autoload like `GameState`, at the top of its script) with these markers:

```gdscript
## @system NPC Brain
## @seam GOAP is the sole NPC decision layer; action bodies delegate back to combat/idle/locomotion methods.
## @risk Scene wiring (weapon.tscn, nav, head anchor) can regress silently without a prefab contract test.
## @test res://tests/test_goap_executor.gd
class_name NPC
```

- `@system` is the group/title (required — a block without it is ignored, so ordinary doc comments stay invisible to the map). Several files may share one `@system` name; they group together.
- `@seam` is the one contract line. `@risk` and `@test` may repeat (0..n each). A seam with no `@test` renders as "playtest-only" — a visible nudge to lock it down.

**How to regenerate** (headless, no editor needed):

```cmd
godot --headless --path . -s scripts/tools/gen_arch_doc.gd
```

**How it stays honest.** `tests/test_arch_doc_sync.gd` re-renders the map from the current annotations and fails if `docs/SYSTEM_MAP.md` is stale; the same gate runs headless as `gen_arch_doc.gd -- --check`. The CYBER SUNDAY **Architecture** tab shows the live index (grouped by system) and whether the committed file is in sync.

Relevant files: `res://scripts/tools/gen_arch_doc.gd` (generator + `--check`), `res://scripts/tools/arch_scan.gd` (the pure scanner/renderer), `res://tests/test_arch_doc_sync.gd` (drift guard), `res://docs/SYSTEM_MAP.md` (the output).

---

## Atmosphere: radio, music and movement FX

This is the audio-and-vibe layer of CYBER SUNDAY: the dynamic combat score, the looping bed under conversations, the in-world diegetic radio, the footstep/dust/landing FX that make any actor feel grounded, a falling scream, and the giant timed title that drops out of the sky. Everything here is a drop-in node plus inspector fields — no code. Buses matter: the score and the radio's track ride the **`music`** bus; footsteps, landings, screams and the radio click ride the **`sfx`** bus; a machine's own crappy speaker (the ATM panel) rides the **`speaker`** bus, which is a tinny filter chain sending *into* `sfx` (§2a); and the shop music a machine plays out of that same panel rides **`station_music`**, which is the *same* filter chain sending *into* `music` (§1d — the chain is what makes it sound tinny, the send is what decides which volume slider owns it). The Settings volume sliders and the dialogue ducker act on those buses, so as long as you route things to the right bus they cooperate automatically.

### 0. World sounds vary slightly in pitch (`global_pitch_spread`)

Before any of the components below: **every sound the game world makes plays at a slightly different pitch each time**, so a clip retriggered two or three times a second never machine-guns the byte-identical sample at you. It is one knob, and **nothing you author has to opt in**.

**The knob:** `res://resources/tuning/AudioSettings.tres` -> **Pitch Variation** -> `global_pitch_spread`, default **`0.15`**. Live-editable from the Inspector while the game runs. `0.0` switches the effect off entirely.

* **Size it against this project's other spreads, not against intuition.** `0.15` is deliberately the same number as `interactable_impact_pitch_spread`, i.e. what the codebase already uses for a physical impact. For scale: footsteps `0.08`, paint splat `0.10`, throwable impact `0.15`, generic impact and muzzle whiz `~0.17`, NPC aim/beep `~0.22`, landing `0.25`, blood drop `~0.35`.
* **Too small is the failure mode, not too large.** The first cut of this shipped at `0.04` and was flatly inaudible — six consecutive enemy hits spanned about 1.2 semitones *in total*, with neighbouring pairs far below that, which on a short percussive clip you simply cannot hear. At `0.15` the same six span ~2.9 semitones.
* It **multiplies** whatever pitch a sound was already going to play at, it does not replace it. So the gun still sags as the magazine empties, a wounded enemy's hit still deepens with its HP, a big dog still yaps low, and footsteps/impacts/whizzes keep their own authored spreads — they simply stop being identical on a retrigger.

**⭐The line is DIEGETIC: it varies what the WORLD makes, and nothing else.**

| Varies | Stays exactly the same every time |
| --- | --- |
| Footsteps, landings, gunfire, reloads, shell tinks | **Menu and UI cues** — hover, click, open, back, tab, commit, the refusal buzz |
| Bullet and melee impacts, explosions, the bullet whiz | **Stings and HUD cues** — the MGS "!" alert, the aim/charge sting, the incoming-shot beep, the hitmarker ding |
| Gore splashes, cripple cracks, a dog's bite | **Reward jingles** — the cha-ching bounty, the pickup chime, the applause cheer, a station terminal's chirp |
| **Every voice** — the NPC hurt cry (fires on *every* damage tick), death screams, falling yells, a dog's yap / purr, a claim bark | **Music, ambience and every loop** — the score, `AmbientSound`, the radio's track, the computer-room hum and fan, the falling/slide wind, a held prop's pant, the heartbeat |
| Doors, switches, levers, destructibles, thrown props, the flashlight and radio switches | |

**Voices vary AROUND their own base pitch, never instead of it.** The variation *multiplies*, so a creature that has an authored voice keeps it: a `Throwable`'s **Sound Pitch Mult** is its rolled **body size** (small dogs yap high, big dogs low — `RandomSize` writes it, and `SpawnOnDestroy` passes it on so a dog crate barks at the size of the dog inside), and that stays the **centre** of the roll. A big dog still yaps low; it just never fires the identical sample twice.

> ⭐**The enemy-hit impact is where this matters most, and it is the least obvious.** That sound's base pitch is the HP lerp (`enemy_hit_pitch_low_hp`..`enemy_hit_pitch_full_hp`), which is *deterministic* for a given remaining HP — so shooting a high-HP target with a weak weapon barely moves it, and before this every hit landed on the byte-identical pitch. The variation is the only thing separating them.

Why the right column is excluded differs by row, and it is worth knowing: a **UI blip** that wobbles reads as a *bug*, not as life — a button should sound like the same button every press. A **melodic jingle** varied just sounds out of tune. The **hitmarker's** pitch *is* the information (it deepens as the target nears death), so a jitter would blur the signal. And a **loop** restarts itself when it finishes, so a per-play roll would re-tune the bed every lap.

If a loop of yours starts drifting in pitch, something is playing it as a one-shot.

**If you write code** (you usually won't):

* A **world** one-shot via `AudioManager.play_sfx` / `play_2d_sfx` varies automatically — nothing to do.
* A **persistent `AudioStreamPlayer` in a scene that you retrigger** must be played with **`AudioManager.play_varied(player)`** instead of `player.play()`. Pass a base pitch as the second argument if the site's pitch means something (`AudioManager.play_varied(fire_player, ammo_pitch)`).
* A **non-diegetic** one-shot — a sting, a HUD cue, a jingle — **or any character voice** passes `vary = false`: `AudioManager.play_2d_sfx(clip, db, pitch, &"sfx", false)`, or for the 3D helper `AudioManager.play_sfx(pos, clip, db, pitch, &"sfx", AudioManager.DEFAULT_MAX_DB, false)`. Do **not** infer this from 2D-vs-3D; the bullet whiz and the ram thud play 2D and *are* world sounds, while a positional death cry is 3D and is *not*.
* A **loop, or a menu cue**, just calls `player.play()` (menu cues go through `MenuStyle`, which never touches `AudioManager` at all).

### 1. Dynamic combat music (`MusicDirector`)

`MusicDirector` (`rpg/scripts/components/music_director.gd`) is the heart of the score. The trick: your music track **plays constantly** but sits silent during exploration, then fades **in** for combat and back out once the coast is genuinely clear. (Exploration is no longer *silence*, though - the wandering bed in **section 1e** is this score's exact complement and fills exactly the moments this one leaves empty.) It runs a **three-tier ladder** — **FULL** in a live firefight, **CAUTION** (the same bed, ducked by `caution_duck_db`) while an enemy is merely *hunting* you, and **SILENT** when nobody is aware of anything — so losing line of sight drops the intensity instead of cutting the music dead. Because the stream never stops, a fade-in joins the music mid-track instead of restarting it. (This score does **not** swell for dialogue unless you opt in with `swell_for_dialogue` — conversations get their own separate track instead, the `DialogueMusicBed` in §1c.)

**Setup**
1. Add an `AudioStreamPlayer` (or `AudioStreamPlayer3D`) to your level — this is your "Music" node. Set its **Bus** to `music`, assign your looping score to **Stream**, and turn on **Autoplay** (and make the stream loop) so the position always advances.
2. Set that player's **Volume dB** to the level you want combat music to reach — `MusicDirector` reads the authored volume as its **audible target**.
3. Add a `MusicDirector` node as a **child** of that player. That's it.

**Fields** (`@export`): `fade_in_time` (1.2 s, silence→audible, fast because combat hits fast), `fade_out_time` (3.0 s, the fight breathing out), `combat_linger` (2.5 s the music holds after the last enemy disengages, so it doesn't flap during a brief lull — it doubles as the CAUTION tier's hold at the tail of a search), `caution_duck_db` (**-6.0** — how far *under* the authored level the score sits while an enemy is hunting rather than shooting; a negative offset like the dialogue ducker's `music_duck_amount_db`, clamped into `[silent_db, authored]` so a sign slip can't make a search louder than a firefight. Set it to `-60` — anything reaching the floor — to opt back out and have searching play in silence), `silent_db` (-60.0, the inaudible floor), `yield_to_radio` (true — a playing in-world `Radio` the player can hear takes precedence, holding the dynamic bed silent so the radio's own music carries the moment; applies to combat and, when it's on, the dialogue swell), and `swell_for_dialogue` (**false** — off by default, because conversations have their own bed (§1c); turn it on to swell the *combat* score under a conversation as well, and the same `yield_to_radio` precedence then applies to it. With a `dialogue_music` track authored, leaving this off is almost always right — on, the two scores play **together**).

**What triggers it:** the **FULL** tier is any NPC in the `npc` group reporting `is_in_combat()` (ALERTED *with a live target* — an active fight). The **CAUTION** tier is any NPC reporting `is_hunting()` while nobody is in combat — an enemy that lost you and is sweeping your last-known spot, chasing a heard noise, or standing over a body (Perception `INVESTIGATING`, what the stealth HUD prints as `[CAUTION]`). One group scan reads both, and FULL always outranks CAUTION, so a mixed crowd of one shooter and one searcher scores as a fight. Both predicates are **target-agnostic**, matching the combat scan's long-standing behaviour: an NPC hunting *another* NPC still scores, which is why the music can play while the HUD reads `[HIDDEN]` (the score follows the fight in the world; the HUD follows the fight aimed at you). `combat_linger` holds FULL right through the `ALERTED ⇄ INVESTIGATING` flicker of a broken line of sight, so a firefight never audibly dips to the search level and back. A conversation (`DialogueManager.is_active()`) is **only** a trigger when `swell_for_dialogue` is on — off by default, since dialogue has its own bed (§1c). **Radio precedence:** when the player stands within a playing `Radio`'s `audible_radius`, the dynamic bed is suppressed (the radio carries the moment) — for combat and, when it's enabled, the dialogue swell, so an opted-in conversation near a radio plays over the radio rather than swelling a second score on top of it. The combat scan runs on a fixed 0.3 s interval (a `POLL_INTERVAL` const, not a tunable). Gotcha worth knowing: if the music node's authored Volume dB is at or below `silent_db`, the fade is a no-op — `MusicDirector` will push a warning and drop the floor 20 dB to keep it working, but the clean fix is to raise the node's volume.
#### 1b. The "you've been seen" sting (`DetectionStinger`)

Where `MusicDirector` rides the continuous **bed** up and down its FULL / CAUTION / SILENT ladder, a **`DetectionStinger`** (`rpg/scripts/components/detection_stinger.gd`, `@tool` `extends Node`) is the sharp one-shot cue ON the detection edge -- it plays its parent audio player's stream the instant an NPC first **locks onto the player**. It pairs with `MusicDirector`: the bed swells under you while the sting punctuates the moment you're spotted. It's **inert until an NPC actually goes ALERTED on the player.**

**Setup:** drop a `DetectionStinger` as a **CHILD** of an `AudioStreamPlayer` / `AudioStreamPlayer3D` / `AudioStreamPlayer2D` whose stream is your detection sting. Leave that player **non-autoplay and non-loop** -- the stinger calls `play()` itself on the edge. (It runs on `PROCESS_MODE_ALWAYS`, like `MusicDirector`, so it still fires the very moment combat begins, even through a pause.) **No shipping scene authors one yet, by design** — the drop-in is ready the moment you place it under a player with an authored clip (`game.tscn`, beside `MusicDirector`, is the natural home).

**Field** (`@export`): `cooldown` (5.0 s) -- the minimum seconds between stings, so a flickering line of sight (LOS lost then regained) won't replay the cue. It latches, so one sustained engagement stings exactly **once** and re-arms only after every NPC has disengaged. The poll runs on a fixed 0.3 s interval (a `POLL_INTERVAL` const, not a tunable).

> **It triggers on detection of the PLAYER specifically**, not just "any combat" -- an NPC fighting *another* NPC is in combat but hasn't spotted you, and won't trip the sting. The `@tool` script config-warns if the parent isn't an audio player (drop it under one, or it does nothing).

#### 1c. Dialogue music (`DialogueMusicBed`)

A looping track that plays **under every conversation** — it fades in as the dialogue box opens and fades back out (then stops) when the conversation ends. Unlike the two components above there is **nothing to drop into a scene**: `DialogueMusicBed` (`rpg/scripts/dialogue/dialogue_music_bed.gd`) is built in code as a child of the `DialogueManager` autoload, alongside the `DialogueView` and the `MusicDucker`. You only author the track.

**Setup:** open `res://resources/tuning/DialogueSettings.tres` and drop an audio file onto **Dialogue Music**. That's the whole setup. Clear the field and conversations play dry again (the pre-bed behaviour).

**Fields** (on `GameSettings.dialogue`, the `Dialogue Music` group): `dialogue_music` (the track; empty = no bed), `dialogue_music_volume_db` (0.0), `dialogue_music_fade_in` (0.6 s), `dialogue_music_fade_out` (0.8 s, after which the bed stops), `dialogue_music_talk_duck_db` (-4 dB — see the talk duck below; 0 = off), `dialogue_music_talk_duck_fade` (0.25 s), `dialogue_music_menu_duck_db` (-60 dB — the station-terminal handover, see §1d; 0 = off), `dialogue_music_menu_duck_fade` (0.8 s), `dialogue_music_bus` (`music`).

**It loops no matter how the file was imported.** A bed that stops dead partway through a long conversation is never what you meant, so the component forces the loop flag on **its own copy** of the stream — a `.wav` imported with Loop Mode *Disabled* still loops seamlessly, and the authored resource is left untouched for anything else holding it. Setting the import correctly (a `.wav`'s **Loop Mode → Forward**, an `.mp3`/`.ogg`'s **Loop** tick) simply skips that copy.

**How it stacks with the rest of the audio layer** — worth understanding before you tune the volume:

- **The `MusicDucker` also ducks this bed.** The ducker drops the whole `music` bus by `music_duck_amount_db` (-12 dB) for the conversation, and the bed rides that bus, so it plays 12 dB under its authored level. That's a *constant* offset (the bed only ever plays during a conversation), so just tune `dialogue_music_volume_db` by ear — but note that changing the duck amount shifts this bed too.
- **The bed also has its own slight talk duck.** While a line is actually being *spoken*, the bed dips a further `dialogue_music_talk_duck_db` (-4 dB) under the voice, swelling back while the player reads the response menu (or once the line's spoken estimate elapses, with auto-advance off). It tracks the exact envelope that drives the talking head-bob, so consecutive lines hold one continuous dip rather than pumping per line. `dialogue_music_talk_duck_fade` (0.25 s) shapes the dip/swell; set the duck to 0 to turn it off.
- **The `MusicDirector` score is silent during dialogue by default**, so normally this loop is the only music you hear while talking. That suppression is *enforced*, not incidental: a conversation pauses the tree, so an NPC left mid-search can never finish searching, and an unsuppressed CAUTION tier would hold the combat bed under every line. If you turn `swell_for_dialogue` on, the combat score and this bed play **together** — pick one.
- **A diegetic `Radio` does not suppress it.** `yield_to_radio` governs the `MusicDirector` bed, not this one; a conversation next to a playing radio will have both.
- **A station terminal's own radio DOES suppress it**, and this is the one exception to "a suspended conversation keeps the bed playing". Opening Trade / Heal / Level Up / Install / Chess / Bank from a conversation opens a *station* screen, and stations play their own tinny shop music (§1d). Rather than stack two beds the conversation's steps aside by `dialogue_music_menu_duck_db` (-60 dB = a full handover) over `dialogue_music_menu_duck_fade` (0.8 s), then swells back when the sub-menu closes — it is a **duck, not a stop**, so the loop keeps its position. Set the duck to about -8 to layer the two instead, or 0 to hear both at their authored levels. This is also what makes a person-vendor sound identical to a bare kiosk.
- Being on the `music` bus also means the Options **Music** volume slider governs it, which is why `dialogue_music_bus` should stay `music` unless you have a specific reason.

**Lifecycle:** on at `start()`, off at `_finish()` — the same two points as the ducker. A conversation merely *suspended* behind a sub-menu (Trade / Heal / Level Up / Install) **keeps the bed playing** (though it steps aside for that sub-menu's own music — see the handover bullet above), since the conversation still exists and cutting the music there would stutter the scene. The bed restarts from the top each conversation, so a short loop always opens on its downbeat. It runs `PROCESS_MODE_ALWAYS`, so it keeps playing through the tree-pause that dialogue puts the world under.

#### 1d. Station music — the machine's own radio (`StationMusic`)

While you are standing at a **self-serve terminal with its screen open** — a shop counter, the ATM, the clinic kiosk, the trainer, the respec booth, the chip bench, the chess table — that machine plays a looping shop theme **out of the same forty-cent panel speaker that just chirped at you** when the screen woke up. Like §1c there is **nothing to drop into a scene**: `StationMusic` (`rpg/managers/StationMusic.gd`) is an autoload. You only author the playlist.

**Setup:** open `res://resources/tuning/StationMusicSettings.tres` and drop audio files into **Tracks**. That is the whole setup. Empty the array and the entire layer goes inert — no bed, and every other audio layer behaves exactly as it did before the feature existed.

**Fields** (on `GameSettings.station_music`): `tracks` (the playlist; empty = off), `enabled` (master switch for A/B-ing without emptying the array), `volume_db` (-6.0), `silent_db` (-60.0, the fade floor), `fade_in` (0.6 s), `fade_out` (1.2 s), `hold_seconds` (3.0), `bus` (`station_music`).

**Which screens play it is NOT a field here** — it is one `station_music = true` flag per row of the modal registry in `rpg/managers/InputManager.gd`, sitting beside `blocks_tabs`. That registry is the single place every "which screens count?" question in the game is answered, and every row carries the flag explicitly (with a one-line reason on the `false` ones) so an exclusion is auditable rather than implied. The `true` set is deliberately **exactly the screens that answer with a `StationSpeaker` chirp** (§2a): the music comes out of a clone of that speaker's cone, so the thing playing music must be the thing that just beeped. Loot, Wait, the Pip-Boy tabs, Options and Save/Load are all `false` — a corpse, a rooftop, your own device, and the volume sliders themselves.

**How it behaves:**

- **One track, picked at random, never the same one twice in a row.** With a four-track playlist a naive roll repeats a quarter of the time and you hear the repeat, not the randomness. The "what played last" memory is deliberately never reset, so it holds across separate visits, level changes and deaths.
- **It loops no matter how the file was imported**, by the same forced-loop rule as §1c (`LoopableStream`, now shared by both beds). This is not theoretical — every `.mp3` imports with **Loop off** by default, so without it the shop would fall silent about a minute in.
- **Closing one terminal and opening another is one continuous track.** `hold_seconds` (3.0) keeps the bed at full level after the last screen closes before the fade-out even starts, so shop → the ATM next door never stutters. Re-opening inside that window (or during the fade-out) **resumes the same track at the same position**; re-opening after it picks a fresh one from the top.
- **It never writes an audio bus** — only its own node volume — so it stacks cleanly with the dialogue ducker, the ADS duck and the death cinematic, all of which own bus levels.

**How it stacks with the rest of the audio layer:**

- **The `MusicDirector` combat score stands down for it** (`yield_to_station_music`, on by default) exactly as it does for a diegetic `Radio`: the machine in front of you is already playing music. Turn it off and a mid-firefight shop visit keeps the combat score playing underneath.
- **A conversation's bed steps aside for it** (§1c's handover bullet), so a shop hosted by a talking merchant sounds the same as a bare kiosk.
- **The `MusicDucker`, the ADS duck and the death-cinematic world duck all reach it for free**, because `station_music` sends into `music` — that inheritance is most of the reason for the routing choice.
- **The Options → Audio → Music slider governs it.** ⭐This is the one place the station bed deliberately *diverges* from the ATM chirp it is modelled on. The chirp's `speaker` bus sends into `sfx`; this bus carries a parameter-for-parameter clone of that filter chain but sends into `music`, because a minute-long loop is music by every definition that menu uses. A player who pulls Music to 0 to run their own playlist must not still hear shop themes, and one who pulls Effects to 0 to quiet gunfire must not lose them. Point `bus` at `speaker` if you want them to share a fate, or at `sfx` for a clean, expensive-sounding machine. A bus name that does not exist degrades to `music` with a warning — never to Master, which would escape every slider *and* the death duck. `tests/test_audio_bus_hygiene.gd` asserts the two chains stay identical stage for stage, because a hand-copied filter chain is exactly the thing that drifts silently.

**Checking it by hand:** no automated test can hear a filter, a fade or a bus send. Open a terminal, drop the debug console and run **`stationmusic`** — it prints the gate (which screens are open), the tier flag the other music layers stand down for, the live dB against its target, and the resolved bus.

> ⚠ **The four shipped tracks are knowing placeholders** (Spelunky OST) and are logged in `ATTRIBUTION.md` §A as REPLACE. They live in `assets/audio/music/station/` rather than `assets/audio/music/` on purpose: `Radio._scan_audio_folder` is non-recursive, so the subfolder keeps in-world radios from shuffling shop themes. Replacing them is a pure resource edit — clearing `tracks` makes the layer inert, so the purge can neither break the build nor need a code change.


#### 1e. The wandering bed - exploration music (`WanderMusic`)

While you are just **walking around** - nobody hunting you, no radio on, no terminal screen up, nobody talking - a quiet non-diegetic track plays underneath. This is the **exact complement of section 1's combat score**: `MusicDirector`'s track is silent in precisely the moments this one is audible, and swells in precisely the moments this one stands down. Between them the score is never absent and never doubled.

**Setup:** open `res://resources/tuning/WanderMusicSettings.tres` and drop audio files into **Tracks**. That is the whole setup. Empty the array (or untick **Enabled**) and the entire layer goes inert - nothing plays, and every other audio layer behaves exactly as it did before the feature existed.

The node itself is already authored: `WanderMusic` (`rpg/scripts/components/wander_music.gd`) is an `AudioStreamPlayer` in `scenes/game.tscn` under **Player**, beside the combat score's `Music` node. It is deliberately **not** an autoload - an autoload would need an "am I even in the game world?" gate to keep itself out of the main menu, and a scene node simply does not exist there.

**What silences it** - four things, and every one of them is somebody else already owning the moment:

| Owner | What it means | Reported by `wandermusic` as |
| --- | --- | --- |
| Combat | any NPC is `is_in_combat()` - a live firefight | `combat` |
| Caution | any NPC is `is_hunting()` - sweeping your last-known spot | `caution` |
| Dialogue | a conversation is engaged (`DialogueManager.is_engaged()`) | `dialogue` |
| Station | a terminal screen is up and playing its own tinny radio (1d) | `station` |
| Radio | you are inside a playing in-world `Radio`'s `audible_radius` (section 2) | `radio` |

The first two come from the **same one scan** `MusicDirector` polls (`rpg/scripts/audio/soundscape.gd`), and the rest are flags those layers already publish. Nothing here re-derives an answer another layer already computed - that is what makes the two beds true complements rather than two systems that agree by luck.

**Pacing knobs** (all on `WanderMusicSettings.tres`):

- **`volume_db`** (-14) - the audible level. Well under the combat score's authored 0 dB, because the brief is *quietly*.
- **`fade_in`** (4.0 s) / **`fade_out`** (0.8 s) - deliberately lopsided. It seeps in unnoticed, but it has to be **gone before the combat score arrives**, so `fade_out` must stay under `MusicDirector.fade_in_time`. `tests/test_wander_music.gd` pins that relationship, because it is the one number a retune breaks silently.
- **`resume_delay`** (6.0 s) - seconds of **unbroken** calm before the bed returns. Sized to cover `MusicDirector`'s whole tail (`combat_linger` 2.5 s + `fade_out_time` 3.0 s), so it can never creep in underneath a fight that is still breathing out. Any interruption resets this clock to zero - it is not a pause.
- **`rest_seconds_min` / `rest_seconds_max`** (45-120 s) - the **silence between tracks**. A wandering bed that never stops is the fastest way to make a good piece of music hateful; real exploration scores play, then leave you alone with the room tone. Set both to 0 for back-to-back playback. The rest counts down in **real** seconds whether or not the bed is currently allowed to play, so a long firefight spends the silence for you rather than banking it.
- **`continuous`** (off) - ignore the rest window and loop the picked track seamlessly instead. The loop flag is **forced at play time** in both directions (`LoopableStream`), so this behaviour is decided by the knob and never by whether anyone ticked **Loop** in the Import dock.

**How it interacts with the rest of the mix**

- **It yields to everything and is yielded to by nothing.** It is the bottom layer. There is no knob to make a firefight play *under* it.
- **It goes on the plain `music` bus** - no filter, no 3D position. This is *score*, not a sound coming out of an object in the world (contrast the station bed's tinny `station_music` and the radio's band-limited `radio`). Sending into `music` is also what puts it under the **Options -> Audio -> Music** slider and inherits the dialogue duck, the ADS duck and the death-cinematic world duck for free.
- **It never writes a bus**, only its own `volume_db`, so it stacks cleanly with every bus writer (`DeathMix` owns `music` outright during the death cinematic).

**Checking it by hand:** no automated test can hear a fade. Drop the debug console and run **`wandermusic`** - it prints **who owns the moment** (the single most useful line: it is why the bed is quiet), the calm clock against `resume_delay`, the rest remaining, the live dB against its target, and the resolved bus.

> **This layer currently ships with an EMPTY playlist, so nothing plays.** The wiring is complete and tested - the node is authored, the tuning group is registered, the suppression logic is live - but `tracks` is empty, which by design makes the whole layer inert: no bed, and every other audio layer behaves exactly as it did before the feature existed. Turning it on is a one-field resource edit: drop a track into `assets/audio/music/wander/` and add it to **Tracks**.
>
> Put the file in `assets/audio/music/wander/`, **not** `assets/audio/music/`: `Radio._scan_audio_folder` is non-recursive, so a track left flat in `music/` gets shuffled into every in-world radio and every thrown radio-grenade. `tests/test_wander_music.gd` pins that rule.


### 2. The in-world radio (`Radio`)

`Radio` (`rpg/scripts/components/radio.gd`) is a `LookAtInteractable` — the player aims at it and presses Interact to toggle it on/off. While on, it **takes precedence over the combat score**: by default it plays straight through a firefight while `MusicDirector` holds the combat bed silent for anyone within earshot (the radio you can hear owns the soundscape). During **dialogue it keeps playing** and only dips with the rest of the music bus (the cinematic `MusicDucker` quieting — the `radio` bus sends into `music`, so a conversation lowers it a few dB but never hides it). (Flip `duck_for_dialogue` on to restore the old behaviour — the radio ducks fully out for the conversation and breathes back in afterward. Flip `duck_for_combat` on likewise for combat — the radio ducks and the combat bed plays over it.) It plays from one of three sources, **highest precedence first: a single pinned `track`** (a specific song for *this* radio — it loops that one track and ignores everything else, including the player's own-music override), a **folder of tracks** (`music_folder`), or a single shipped **`fallback_audio`**. The folder cycles out of a spatial `AudioStreamPlayer3D` — truly in-engine, positional, diegetic music, classic-radio style: it auto-advances when a track ends and loops the folder (with an optional per-radio shuffle).

**Setup**
1. Drop a `Radio` node under (or onto) your radio prop. Because it extends `LookAtInteractable`, set **`highlight_target`** to the mesh you want the hover-outline on (defaults to the parent), and size the node's `CollisionShape3D` to the body the player aims at — or turn on **`auto_fit_collider`** to auto-fit the hitbox at runtime.
2. Set **`radio_name`** (blank → "radio" in the hover label).
3. **Pick a source.** For ONE specific song on this radio, assign **`track`** (drag any imported `AudioStream`) — the radio plays exactly that song on loop and ignores `music_folder`, `shuffle`, **and** the player's own-music override. Use it for a story beat or a location theme. Otherwise leave `track` null and use the folder/fallback below.
4. Point **`music_folder`** at a folder of `.mp3`/`.ogg`/`.wav` tracks (defaults to the shipped `res://assets/audio/music`). The radio scans it on turn-on and plays through it. Set **`shuffle`** for a per-radio-deterministic random order. Leave **`audio_player`** unset to auto-create a child player on the `radio` bus (the tinny filter — see below). *(Ignored when `track` is set.)*
5. Optionally assign **`fallback_audio`** — a single shipped track used only when `track` is null and `music_folder` has no audio files (so a radio is never accidentally silent).
6. Optionally set **`click_on`** / **`click_off`** (a physical clunk on toggle) and **`click_volume_db`**; these auto-route to the `sfx` bus through a separate `click_player`, so the combat duck never touches them.
7. Leave **`show_music_note`** and **`vibration_enabled`** on for the default "it's playing" feedback: the prop bounces and launches short-lived note particles. The bounce knobs live in the **Bounce** export group. Set **`vibration_target`** only when you want to bounce a specific mesh child; otherwise the radio uses `highlight_target`, then the parent prop, then itself.

**The "tinny radio" sound (the `radio` bus):** the radio's player routes to a dedicated **`radio`** audio bus (in `default_bus_layout.tres`) carrying a band-limited "real radio" effect chain — a **high-pass** (600 Hz, kills the bass/body for the thin tinny character), a **light overdrive** (cheap-speaker grit), and a **low-pass** (5 kHz, rolls off the airy top) — plus a few dB of makeup gain to offset what the filters strip. That bus **sends into `music`**, so the radio still rides the Music volume slider *and* the dialogue/combat duck, but the filter touches **only the radio** — the `MusicDirector` score stays full-range. Tune or disable it in the editor's **Audio** panel (the bottom bus tabs): adjust each effect, or untick the `radio` bus effects for clean playback. (If you author your own `audio_player`, set its **bus** to `radio` to get the effect, or `music` for clean.)

**Note particles & bounce:** while `is_playing_music()` is true (the radio is switched on and its `AudioStreamPlayer3D` is actually playing a stream), the radio launches billboarded `Label3D` notes in bright note-block colors. Each note detaches into world space, rises, fades, and frees itself. Tune them with `show_music_note`, `note_glyph`, `note_color`, `note_rainbow`, `note_height`, `note_rise`, `note_spread`, `note_emit_interval`, `note_lifetime`, `note_font_size`, `note_pixel_size`, and `note_fade_time`. The **Bounce** export group uses `vibration_target` when set; otherwise it bounces `highlight_target`, the parent prop, or the `Radio` node. A `RigidBody3D` target gets a tiny `vibration_impulse` plus `vibration_side_impulse` once per `vibration_rate` cycle. Non-physics targets use `vibration_visual_bounce` for height and `vibration_visual_side` for side wobble; that visual offset is removed when the music stops.

**The player's own music (Options → Audio → Music Folder):** the player can point a directory picker at *their own* folder of tracks; that override (`Settings.music_folder`) wins over **every** radio's `music_folder` until they clear it ("Default"). It does **not** override a radio with a pinned **`track`** — a designer-chosen song stays put. A `res://` folder is loaded through the import pipeline; an outside folder (their Music directory, a `user://` path) is decoded from raw file bytes at runtime (mp3/ogg/wav). Undecodable files are skipped.

**Dialogue-duck field:** `duck_for_dialogue` (false by default — the radio plays *through* a conversation and only dips with the music bus via `MusicDucker`, so it never abruptly vanishes; set true to restore the old behaviour, where the radio ducks fully out to `silent_db` while a dialogue/menu is up and eases back in when it closes). It reuses the same `fade_pause_time` / `fade_resume_time` / `silent_db` as the combat duck.

**Combat-duck fields:** `duck_for_combat` (false by default — the radio takes precedence over the combat score and plays *through* a fight; set true to make it duck for combat instead, the way it used to, with the combat bed playing over it). The rest only matter when `duck_for_combat` is on: `combat_strict` (false = duck through the whole hunt, *including* the INVESTIGATING search phase — matching the `MusicDirector`, whose CAUTION tier keeps the bed alive across exactly that phase; true = only during an active ALERTED firefight, i.e. only the `MusicDirector`'s FULL tier), `poll_interval` (0.3 s), `settle_cooldown` (3.0 s ducked after the last enemy disengages), `fade_pause_time` (0.4 s out), `fade_resume_time` (1.2 s back in), `silent_db` (-60.0), `fallback_volume_db` (0.0). The duck/settle brain is the pure `RadioPlaybackState`; the track ordering is the pure `MusicPlaylist`.

**NPC reactions:** set **`audible_radius`** (12 m) — how far a nearby NPC can "hear" a playing radio and react (turn its head toward it, comment by quality). This only fires when `GameSettings.npc_ai.music_reactions` is on; otherwise a playing radio is inert to NPCs. The comment tier comes from `MusicQuality` (`rpg/scripts/components/music_quality.gd`), a deterministic 0..1 score folded from the radio's `quality_text()` — the pinned **`track`**'s filename when one is set, else the **current folder track's filename** when a folder is playing (so an NPC scores the actual song), else the `radio_name`. The same string always scores the same, so one NPC consistently loves a track another finds awful. The three tier cuts are `music_tier_meh` / `music_tier_good` / `music_tier_great` on `GameSettings.npc_ai`.

### 2a. Cheap diegetic speakers — the `speaker` bus and the `StationSpeaker` drop-in

The radio's `radio` bus makes a sound *broadcast*; the **`speaker`** bus makes it come out of a **bad little speaker bolted to a machine**. Same idea, harsher settings, and a different destination: a **high-pass** (900 Hz, resonant — strips the bass and body so there is nothing but honk left), a **lo-fi distortion** (bit-crush grit, the sound of a cone that cost forty cents), and a **low-pass** (4.2 kHz, no air at all), plus +4 dB of makeup gain for what the filters strip. It **sends into `sfx`** (not `music`, which is where the radio bus goes) — so a machine chirp rides the **SFX** volume slider and ducks with the rest of the world under the death cinematic.

**Who uses it: every self-serve station**, through one drop-in — **`StationSpeaker`** (`rpg/scripts/components/station_speaker.gd`, `extends Node3D`). Opening a kiosk's screen chirps out of the machine itself, so the sound is genuinely **positional**: it pans and falls off from the panel you are standing at, rather than blipping in your ear like a menu sound.

**You usually author nothing.** `Merchant`, `Healer`, `LevelUp`, `RespecStation`, `ChipInstaller`, `ChessMatch` and `Atm` each build a default `StationSpeaker` on themselves at load **when `standalone` is on** — a bare kiosk dropped into a level already answers when you use it. A station running `standalone = false` (data-only, riding a talking NPC) gets **no** speaker, because a person who beeps is a bug.

**Two cues, two voices.** A speaker has a wake-up **chirp** (every station) and a reward **clap** (today: the `Atm`, when you pay down what you owe). They get separate `AudioStreamPlayer3D` children — `Player` and `Applause` — so neither cuts the other: closing and re-opening the terminal mid-celebration doesn't chop the applause off. Within one cue, restarting *is* the behaviour — a second repayment re-claps rather than stacking a second crowd on the first.

**Author one to tune or silence a machine.** Drag a `StationSpeaker` under the station: the station finds it **by type** (not by name or an exported path) and never adds a second. Knobs:

- **`open_sound`** (AudioStream) — the chirp, defaulting to the shipped `res://assets/audio/sfx/deposit.wav`. **Clear it for a deliberately silent machine**, or drop in your own clip.
- **`volume_db`** (0.0) — level, measured after the bus filters have taken their bite.
- **`applause_sound`** (AudioStream) — the reward clap, defaulting to the shipped `res://assets/audio/sfx/Applause.mp3`. **Clear it for a terminal that takes your repayment without the fanfare.** Independent of `open_sound`: a machine can clap and not chirp, or the reverse.
- **`applause_volume_db`** (0.0) — level trim for the clap alone, so you can seat the celebration under (or over) the chirp without re-levelling either clip. Its own knob because the two clips come from different places and rarely match out of the box.
- **`bus`** (`&"speaker"`) — **this field is the tinny sound.** Point it at `sfx` for a clean, full-range, expensive-sounding machine. A bus name that doesn't exist falls back to `sfx` with a warning rather than landing on Master, where no volume slider would reach it. Both voices route through it.
- **`max_distance`** (10 m) / **`unit_size`** (4.0) — how far the cues carry and how fast they fall off. A panel speaker is not a PA; keep both small so it stays *the machine's* sound. Shared by both voices — one machine, one cone.

> **One open cue, never two.** A station screen asks `StationSpeaker.chirp(station)` at the moment it commits to opening, and that call **returns whether it spoke** — the screen feeds the answer straight into `ModalMenu.grab_mouse(not chirped)`. So a machine with a voice replaces the generic menu-open sting, and a person (or a machine you muted) still gets it. Muting `open_sound` therefore gives you the normal UI cue back, not silence. And because the chirp fires past every refuse guard, a station that *couldn't* open never beeps.

> **The clap is the deliberate exception to that rule.** `StationSpeaker.applaud(station)` **does not** suppress the caller's UI cue, and that is not an oversight. The "never two" rule exists because the chirp and the menu sting answered the *same instant of the same event on the same layer*, so one had to yield. The applause doesn't compete: the crisp commit click confirms **the press registered** (immediate, 2D, the sound every till in the game makes), while the clap is a several-second diegetic flourish for a milestone only *some* presses reach. Swallow the click and a repayment would feel mushier than an ordinary deposit — exactly backwards. Its one caller today is `Atm.deposit`, on the portion of a deposit that actually **retires debt** — the same branch that scores credit standing, so the sound and your credit file can never disagree, and merely banking savings stays unremarkable.

**Reusing it on your own props** (a vending machine, a station PA, a door intercom, a drive-thru): author or build an `AudioStreamPlayer3D` on the prop and set its **bus** to `speaker`. An `AmbientSound` works too — set its `bus` to `speaker` for a looping tannoy. Tune or bypass the chain in the editor's **Audio** panel (bottom bus tabs) like any other bus.

> **⭐If the sound plays while a menu holds the game paused, set the player's `process_mode` to `Always`.** A pausable `AudioStreamPlayer3D` silences itself the instant `get_tree().paused` flips — measured: the chirp dies about 15 ms in, with no error and nothing in the log. `StationSpeaker` sets this for you (the station screens are real-time now, but a *dialogue-hosted* station opens under the conversation's pause, and the death cinematic pauses too); an authored player of your own does not, and the symptom is a sound that "doesn't play" only inside menus.

### 2b. Looping ambience & audio zones (`AmbientSound`, `AudioZone`, `IndoorAmbienceDucker`)

Three drop-ins cover the rest of a level's soundscape. `AmbientSound` builds its own player on the **`ambient`** bus by default, so it obeys the Ambient volume slider instead of Master (the footgun a bare `AudioStreamPlayer3D.new()` falls into). `AudioZone` has **no bus of its own** — it only fades a child player YOU author, so you set that child's bus (its `@tool` config warning flags a Master-bus child). `IndoorAmbienceDucker` doesn't make a sound — it *modulates* one when you step under a roof.

**`AmbientSound`** (`rpg/scripts/components/ambient_sound.gd`, `@tool`, `extends Node3D`) — a single looping bed. Drop it where the sound lives, assign a `stream`, and on load it spawns a child `AudioStreamPlayer3D` and plays. It's positional (fades with distance), so a generator hum stays near the generator.

- `stream` — the looping `AudioStream`. Empty = silent (and a configuration warning).
- `volume_db` — level applied to the player.
- `bus` — the routing bus, default `&"ambient"`. A bus not in the project's layout warns (it would fall back to Master and ignore the slider).
- `loop` — re-play on finish (the designer-friendly default, regardless of the stream's own loop flag). Off = a one-shot establishing cue.
- `autoplay` — start on `_ready`. Off = call `play()` from a `TriggerVolume` action or a cutscene.
- `max_distance` (0 = engine default) and `unit_size` (falloff, default `10.0`) shape how far it carries.
- API: `play()` / `stop()` / `is_playing()`.

**`AudioZone`** (`rpg/scripts/components/audio_zone.gd`, `@tool`, `extends Area3D`) — cross-fades a sound by player presence. Paint the area over a region (a bar, a boss arena, a reactor room), then give it **two children**: a `CollisionShape3D` (the trigger volume) and an `AudioStreamPlayer` / `AudioStreamPlayer3D` set to a non-Master bus (the sound it fades). When the player enters, the child rises to `active_volume_db`; when they leave, it sinks to `inactive_volume_db`.

- `trigger_group` — the group a body must be in to count, default `&"Player"` (it monitors every physics layer and filters by group, like `TriggerVolume`, so you never match mask numbers).
- `active_volume_db` / `inactive_volume_db` — the in-zone and out-of-zone levels (set the floor low, e.g. `-40`, for "effectively silent outside").
- `fade_speed` — cross-fade speed in dB/s.
- `autoplay` — start the child looping (already running, just silent) on `_ready`, so the first entry has no attack.
- It runs on `PROCESS_MODE_ALWAYS` (the fade keeps going through a pause — a menu opened mid-zone) and ref-counts qualifying bodies (overlapping zones / a recruited companion won't double-toggle). API: `is_active()`.

**`IndoorAmbienceDucker`** (`rpg/scripts/components/indoor_ambience_ducker.gd`, `@tool`, `extends Node3D`) — makes a city/outdoor bed **quieter and muffled under a roof**. Drop it under the **Player**, next to the `Ambience` `AudioStreamPlayer3D` (this is already wired in `scenes/game.tscn`). Each tick it casts a small fan of rays straight UP; when at least `coverage_threshold` of them hit geometry within `ceiling_scan_height`, it applies two treatments and reverses both under open sky:
  1. **Volume** — cross-fades the target bed from `outdoor_db` down to `indoor_db`. It moves only the target player's own `volume_db` (never a bus), so the Ambient volume slider still governs the overall level (the two compose in dB, the same split `AudioZone` uses).
  2. **Muffle** — sweeps a low-pass filter's `cutoff_hz` from `outdoor_cutoff_hz` (transparent) down to `indoor_cutoff_hz` (default `2500` Hz — a clearly-audible "stepped indoors" roll-off). A low-pass is a per-**bus** effect, so the bed lives on its own **`ambient_bed`** bus (added in `default_bus_layout.tres`, carrying an `AudioEffectLowPassFilter`, sending into `ambient` so the slider still applies) — the same shape as the `radio` bus's low-pass. Turn it off with `enable_muffle` for a pure volume duck.

- `host` — the player (gets `is_indoors` written each sample). Blank → auto-wired to the parent.
- `target` — the `AudioStreamPlayer` / `AudioStreamPlayer3D` to duck. Blank → auto-find the first sibling on `bus`.
- `outdoor_db` / `indoor_db` — the open-sky and under-a-roof levels (default `0` / `-12`; keep indoor below outdoor or a warning fires).
- `fade_speed` — volume cross-fade speed in dB/s (so an awning eases the volume instead of snapping it).
- `enable_muffle` (default on) / `muffle_bus` (default `&"ambient_bed"`) — the low-pass treatment and the bus it sweeps.
- `outdoor_cutoff_hz` / `indoor_cutoff_hz` — the low-pass cutoff outdoors (default `20500` = transparent) vs indoors (default `2500` = a clearly-audible "stepped indoors" muffle; the `radio` bus sits at `5000` for reference). Raise toward `6000` for lighter, drop toward `1200` for a heavy "sealed room" muffle — much above `~8000` is nearly inaudible on broadband ambience. `muffle_smoothing` — how fast the cutoff eases (per-second exponential rate).
- `ceiling_scan_height` — how far up (m) to look for a roof; `probe_radius` — the horizontal spread of the ray fan; `coverage_threshold` (0..1] — fraction of the fan that must hit to count as indoors (the fan + vote stop a doorway gap / skylight directly overhead from flickering you "outdoors").
- `sample_interval` — seconds between scans; `eye_height` — ray origin height above the host's origin.
- It also **WRITES `host.is_indoors`** (a bool declared next to `light_exposure` in `player.gd`) each sample — the shared "is there a roof over me" flag a future reverb send / rain cutoff / interior-music swap can read instead of re-casting. API: `is_roof_overhead()`.

**A light fixture's electrical buzz** is the fourth ambience surface, and it lives on `MyLight` (`scenes/levels/Light.tscn`) rather than on a component you drop: tick `_electric_buzz` and the fixture hums. The **Buzz mix** group tunes how far that hum carries, and `MyLight` pushes all four values into its child emitter every frame — so, exactly like the fixture's colour and ranges, the child `AudioStreamPlayer3D`'s own authored settings are overwritten and mean nothing. (They have to live on the fixture: a level instance can't reach a child of an instanced scene without "editable children".)

- `buzz_volume_db` (default `-6`) — level once you're inside `buzz_falloff_distance`. The `ambient` bus adds another +6 dB on top.
- `buzz_falloff_distance` (default `4`) — the distance at which the hum sits at exactly `buzz_volume_db`; closer is louder, further falls off. Ceiling fixtures hang 3-5 m over the player's ear, so standing under one already puts you at full level.
- ⭐`buzz_radius` (default `12`) — the radius past which the fixture drops out of the mix. **Godot reads 0 as _unlimited_, not silent** — a `@tool` config warning fires if you clear it on a humming fixture. Keep it under the spacing between your buzzing fixtures; to silence one, clear `_electric_buzz`.
- `buzz_air_cutoff_hz` (default `20500` = OFF) — the engine's air-absorption shelf, which dulls a 3D sound's high end by up to -24 dB as it recedes. Drop it toward `5000` only if you *want* a fixture to sound weathered near the edge of its radius.

> **⭐Why those defaults exist — the "why does the buzzing light sound like it's outside" bug.** The emitter shipped with `max_distance = 0` (unlimited) and the engine-default 5000 Hz shelf. With inverse-distance falloff off a ~4 m unit size, a fixture **20 m away still plays only ~14 dB down** — plainly audible — and heavily rolled off up top. The main level's four buzzing fixtures sit ~19-23 m apart, so they summed into a permanent, dull, unlocalised hum a few dB under whichever one you were standing beside. And it felt like a *roof-duck* bug because the duck is what exposed it: `IndoorAmbienceDucker` drops the city bed 12 dB and rolls its top end off indoors, which **unmasked the wash the bed had been covering**. The duck never touched the buzz (see the routing note under Gotchas). Pinned by `tests/test_my_light_buzz.gd`.

**Gotchas.** `AmbientSound` makes its own player; `AudioZone` fades a player you author as its child (the first `AudioStreamPlayer`/`3D` it finds); `IndoorAmbienceDucker` fades a bed that already exists (its `target`, or an auto-found sibling) — it does NOT create one. Mixing these up is the usual "nothing fades" cause. Keep every bed on a non-Master bus or the volume slider does nothing — **and note this is no longer only a slider problem: the death cinematic ducks the world buses rather than Master (see the death sting, §Death), so anything left on Master also keeps blaring at full volume under the death card.** `tests/test_audio_bus_hygiene.gd` fails the suite on any authored `AudioStreamPlayer` with no `bus` line. The full bus set is `ambient`, `sfx`, `music`, `voice`, `radio` (-> `music`), `ambient_bed` (-> `ambient`), `speaker` (-> `sfx`, the tinny StationSpeaker kiosk chain — §2a), `station_music` (-> `music`, that same chain re-cloned for the shop bed a terminal plays — §1d) and `sting` (-> Master, reserved for the death sting: it is exempt from the cinematic duck by ROUTING, which is the whole point of it). The muffle needs the bed on a bus that carries a low-pass (`ambient_bed`); if you re-route the bed, either keep a low-pass on its bus or set `enable_muffle = false` (a config warning flags the mismatch).

⭐**What the roof duck can and cannot reach.** Its volume fade moves one node (`target`), and its muffle is a per-**bus** low-pass on `ambient_bed` — so `ambient_bed` **is** the duck's entire blast radius. Because audio flows child bus → parent bus and `ambient_bed` sends *into* `ambient`, everything authored on `ambient` itself (a light fixture's buzz, a machine hum, the player's fall-wind) is **upstream of that filter and cannot be dulled by walking under a roof**. That is deliberate: a sound you're standing next to indoors should get *clearer* inside, not muffled. Two consequences worth keeping straight — (1) if a local sound seems to go dull indoors, the duck is almost certainly not the cause; suspect the emitter's own distance falloff (see the fixture-buzz box above, which is exactly that mistake). (2) Anything you *do* route to `ambient_bed` opts in to the treatment, so put outdoor beds there and nothing else. Both directions are pinned by `tests/test_audio_bus_hygiene.gd`.

### 3. Movement FX (`LocomotionFx` + `FallScream`)

`LocomotionFx` (`rpg/scripts/components/locomotion_fx.gd`) gives any `CharacterBody3D` footstep SFX while it walks, plus a louder **landing thud + ground-dust puff** on touchdown. **Every NPC auto-builds one** in `npc.gd`'s `_build_components()` unless you've already dropped a configured `LocomotionFx` under it (so you only add one by hand when you want to override the defaults).

> **⭐The PLAYER does not use `LocomotionFx`** — do not add one, it would double every step. The player's footsteps are node-driven instead (the `WalkingSFX` `AudioStreamPlayer3D` on `Player.tscn`, replayed by `Landing.tick_footsteps`), because the player's cadence is crouch- and climb-aware in ways a fire-and-forget one-shot can't model. Its knobs live in three places: **`Landing.footstep_sounds`** (the clip set, one picked at random per step, never the same clip twice running; clear it to pin one authored clip on the node), **`GameSettings.audio.footstep_pitch_spread`** / **`footstep_volume_db`** (§12 — the wobble and the master trim), and **`GameSettings.player_movement.footstep_*`** / **`player_crouch.quiet_footstep_db`** (cadence and the two dB cuts).

**Setup:** drop a `LocomotionFx` node under the actor. All host reads are duck-typed (`is_on_floor` / `velocity` / `spawn_dust`), so it works on anything that moves. It polls in `_physics_process`.

**Fields:** `footstep_sounds` (an `Array[AudioStream]`, picked at random per step — defaults to the shipped Footstep1/2/3 set; empty → silent), `land_sound` (touchdown — defaults to the shipped Footstep1, and if you clear it the node reuses the first footstep sound), `stride_length` (1.7 m per step — bigger = fewer steps; cadence = stride ÷ speed, clamped to a 0.18–1.2 s range, so faster movement = quicker steps), `move_threshold` (0.4 m/s below which no footsteps), `footstep_volume_db` (-8.0), `land_volume_db` (-1.0), and the landing window `min_land_speed` (2.0 — below this a touchdown is treated as a stair-step/hop and makes no thud) → `hard_land_speed` (9.0 — a full-strength landing: loudest, lowest-pitched, biggest dust). Everything routes to the `sfx` bus via `AudioManager.play_sfx` at the host's position, and the dust puff reuses the host's `spawn_dust(intensity)` (the player/NPC's DustSpawner, exposed on `Character`).

`FallScream` (`rpg/scripts/components/fall_scream.gd`) plays a one-shot yell once an actor has been **falling** long enough, then re-arms on landing — good for a comedic plummet off a rooftop.

**Setup:** drop a `FallScream` node under any `CharacterBody3D`. **Fields:** `scream` (the yell — the default is a placeholder hurt grunt (`Augh.mp3`), swap it for a real falling yell; clearing it makes the node inert), `min_fall_time` (1.1 s of continuous falling before it fires), `min_fall_speed` (1.5 m/s minimum descent to count as a real plummet, filtering a slope-slide), `volume_db` (0.0), and `enabled` (`true` — a master switch; uncheck to make the node inert without removing it). It's positional on the `sfx` bus, and duck-typed like `LocomotionFx`.

### 4. The sky title card (`SkyTitle`)

`SkyTitle` (`rpg/scripts/components/sky_title.gd`) draws a huge title ("CYBER SUNDAY") parked **far away in the sky** (a real depth-tested Label3D, oriented to the camera each frame), so the city skyline depth-occludes it while it stays big and readable and tracks where the player looks. It fades in at a cue time after the game-start spawn, so the title drop lands a beat into the entrance.

**Setup:** drop **one** `SkyTitle` node under your Game root. It self-arms on spawn (via its own `arm()`) and is also pinged by the player as the spawn fade-in begins (the first arm wins, so it counts from the game start), so the cue runs no matter how the game was launched. The cue + fade run on **wall-clock time**, so they stay on schedule through pause and slow-mo.

**Fields:** `text` ("CYBER SUNDAY" — all-caps reads best), `cue_seconds` (168.0 — seconds after the spawn before the reveal; **tune by ear**), `fade_in_time` (2.5), `hold_seconds` (30.0), `fade_out_time` (2.5), `sky_distance` (350 m, auto-clamped just inside the camera's far plane so it never gets clipped), `pixel_size` (0.25) + `font_size` (256) + `text_color` (white) for size/colour, and `vertical_stretch` (1.5 — taller, more imposing letters). `overlay_enabled` (true) also draws an on-top duplicate with the ADS reticle's colour-invert so the title pops crisply over the HUD while the sky copy gets cut by the skyline; tune it with `overlay_size_scale`. While authoring, flip **`test_show_immediately`** to **on** to reveal and size the title instantly without waiting out the ~2:48 cue — then turn it **off** for the real timed drop.

### 5. The boot intro quote (`BootQuotes`)

After the loading screen and before the world fades in, the start menu plays a short intro: a black screen, a **random quote** fading slowly in then out. The quotes are authored content — no code. They live in a **`BootQuotes`** resource (`res://resources/ui/boot_quotes.tres`, `class_name BootQuotes`) holding a `quotes: Array[BootQuote]`; each `BootQuote` (`res://resources/ui/boot_quote.gd`) is two fields: `text` (the line) and `attribution` (the source/byline, optional). `start_menu.gd` loads the `.tres` at runtime and picks one at random per boot, so add a row and it's in the rotation. (A `FALLBACK_QUOTE` const covers a missing/empty resource, so the intro never blanks.)

**To add a quote:** open `boot_quotes.tres`, grow the `quotes` array, and fill a new `BootQuote`'s `text` + `attribution`. Save — it's live next boot.

### 5a. The startup internet warning (`INTERNET_WARNING_CARDS`)

Separate from the New Game boot quote: every normal project launch begins with a short warning — the "This game is connected to the internet." / "Everything you do will be remembered." cards — on the **same black fade card** the boot quote uses (one line at a time, `QUOTE_FADE_IN` → `QUOTE_HOLD` → `QUOTE_FADE_OUT`). It appears before the computer-room intro, before the one-time Terms of Service, and before the menu. It is **skippable** (any key / click) **only once the player has accepted the Terms on a previous boot** — on a genuine first launch (`Settings.tos_accepted` false) the cards play out in full so a first-time player actually reads them (`_internet_warning_skippable`, latched when the cards start; the `debug_always_show_tos` replay stays skippable so devs aren't stuck). The press is swallowed either way. Both the room intro and the menu briefly shield fresh input so the skip input cannot click through into the monitor boot or New Game / Continue. The debug straight-to-game boot continues only after this startup gate clears.

The text is an `INTERNET_WARNING_CARDS` const in `start_menu.gd` (fixed narrative, like `FALLBACK_QUOTE`) — the flow is `_begin_menu_boot_flow → _maybe_start_internet_warning → _play_internet_warning → _reveal_menu_after_internet_warning`. **To change the lines:** edit that const (each string is one card; blank the array to disable the warning). The computer-room host instances the menu immediately, keeps its timer/audio stopped, and waits for the menu's `startup_gate_finished` signal before beginning the room boot.

### 5b. The first-launch Terms of Service (`TermsOfService`)

The one-time gate after the startup warning (§5a): on the **very first launch of an install**, before the menu is usable, the player must consent to a **fake, comedic Terms of Service** — an impenetrable wall of legal jargon that (falsely) insists the game is *always online* and that *every action is remembered forever*. It grants no real rights and collects no real data; it is flavour, part of the "you are being watched" opener. `start_menu.gd` shows it (`_open_terms`) whenever `Settings.tos_accepted` is false, hides the menu behind it, and only on consent records the flag (`Settings.accept_tos()`) before releasing the startup gate — so the TOS appears **exactly once per install** (the flag lives in `user://settings.cfg`, which survives New Game, unlike the wiped-on-new-game profile save). To re-see the gate on **every** launch while iterating, there's **Options → Game → "Debug: Always Show Terms on Launch"** (`Settings.debug_always_show_tos`) — the boot gate ORs it in without touching `tos_accepted`, so no need to wipe `settings.cfg`. It defaults OFF, including in editor/debug builds; turn it on manually only while re-testing the gate. A value saved via that Options row still wins.

The whole document is authored content in a **`TermsOfService`** resource (`res://resources/ui/terms_of_service.gd`, `class_name TermsOfService`) — every player-facing string is an `@export`: `title`, `subtitle` (blank by default → no subheader), the long `body` (multiline), `accept_label` / `decline_label` / `reconsider_label` (the "Back" button on the decline nag) / `quit_label`, the `scroll_hint_*` footnotes, and `require_scroll` (force the player to scroll to the end before "I Agree" unlocks — the classic wall-of-text dark pattern; on by default). The **shipping document is the script's baked defaults**, so the gate works with **no `.tres` at all** — the screen calls `TermsOfService.load_default()`, which prefers `res://resources/ui/terms_of_service.tres` when a designer authors one and falls back to the defaults otherwise (the same "resource missing → fallback" safety as `BootQuotes`).

**To reword the agreement:** right-click `resources/ui/` → **New Resource** → `TermsOfService`, save it as `res://resources/ui/terms_of_service.tres`, and edit its fields in the inspector — the screen picks it up automatically next boot. (Author the `.tres` in the editor; don't hand-write its `uid`.) **Behaviour to know:** "Decline" never lets the player through — it raises a bare nag with just two choices, **Back** (`reconsider_label`, returns to the agreement) and **Quit to Desktop**. Consent precedes play; the player is gated, never trapped. The screen is `rpg/scripts/ui/terms_of_service_screen.gd` (a transient menu overlay, a sibling of `character_creation.gd`).

> **`Settings.tos_accepted` is a deliberate NON-Option.** It's a persisted `Settings` field with **no `SettingSpec` catalog row** on purpose — it's a one-time consent flag, not a tunable, and surfacing it in Options would let a player "un-accept" and break the fiction. This is the same catalog-less-persisted-field shape as `keybinds` / `music_folder`. Do **not** "fix" it by adding an Options row — it is the documented exception to "The rule: player-facing tunables and keybinds must ALSO reach the settings menu" (under *Global tuning (GameSettings) and the settings menu*).

### A worked example: a back-alley radio

You want a grimy radio on a crate in an alley that cycles a folder of shipped lo-fi tracks, and the player's gang reacts to it.

1. Drop your tracks into a folder, e.g. `res://assets/audio/music/alley/` (or reuse the default `res://assets/audio/music`).
2. Under your alley scene, select the radio prop's mesh. Add a child `Radio` node.
3. Set **`radio_name`** = `"Alley Radio"`, **`highlight_target`** = the radio mesh, and either size its `CollisionShape3D` or tick **`auto_fit_collider`**.
4. Point **`music_folder`** at your folder (tick **`shuffle`** if you want a random order); optionally assign **`fallback_audio`** = a single track for the empty-folder case, and **`click_on`** = a switch clunk (`click_off` can be left blank to reuse it).
5. Leave `audio_player` and `click_player` unset (auto-created on the `radio` and `sfx` buses — the radio track comes out tinny, the click clean).
6. To make the gang react, set **`audible_radius`** = `8` and make sure `GameSettings.npc_ai.music_reactions` is on.

Now: aim at the crate, press Interact. The folder plays out of the crate, advancing track-to-track and looping; the prop bounces while colorful notes pop out, drift upward, fade, and disappear. A firefight no longer interrupts it — the radio plays straight through while the dynamic combat score stays silent (the diegetic radio you can hear wins). Nearby idle NPCs — **friendly and hostile alike** (a raider chilling by its own radio reacts too) — turn to **face** the radio (body yaw + head-look) and comment based on the **current track's** `MusicQuality` tier. (And if the player set their own Music Folder in Options, this radio plays *their* tracks instead.)

**Want one specific song instead?** Skip the folder entirely: assign that song to the radio's **`track`** field. It plays exactly that track on loop, ignoring `music_folder`, `shuffle`, and even the player's own-music override — perfect for a story radio that must always play *the* song. (NPCs still react, scoring it by the song's filename.)

### Gotchas

- **Bus routing is load-bearing.** The `MusicDirector` score and the `WanderMusic` exploration bed both go on plain `music` (they are complements - the same layer of the mix, never audible at once); the radio track goes on the dedicated `radio` bus (the tinny filter, which *sends into* `music` so it still rides the slider + ducks); footsteps, landings, screams and the radio click go on `sfx`. Put music on `sfx` and the dialogue/combat ducks won't touch it; put the click on `music`/`radio` and the combat duck will silence it mid-press; route the radio track to `music` instead of `radio` and you lose the tinny effect.
- **`MusicDirector` must be a child of the audio player**, and that player's authored Volume dB must sit above `silent_db` or the fade is a no-op (it warns and self-corrects by dropping the floor 20 dB, but raise the volume).
- **A radio with no pinned `track`, no folder of tracks, and no `fallback_audio` is silent** — it surfaces a configuration warning in the editor. Pin a `track`, point `music_folder` at audio files, or assign a royalty-free `fallback_audio`.
- **A `res://` `music_folder` scan sees the source files when you run from the editor** (the normal workflow). The player's own folder (an OS path / `user://`) is always real files, decoded from bytes at runtime.
- **NPCs are silent to radios unless `GameSettings.npc_ai.music_reactions` is enabled** — the radio still plays, NPCs just don't react.
- **Only drop one `SkyTitle`.** Remember to turn `test_show_immediately` back **off** before shipping, or the title appears the instant you spawn instead of on the beat.
- **Don't hand-add `LocomotionFx` to NPCs** unless you mean to override the auto-built one — NPCs build their own; a second one would double up footsteps.

Key files: `rpg/scripts/components/music_director.gd`, `rpg/scripts/components/radio.gd`, `rpg/scripts/components/radio_playback_state.gd`, `rpg/scripts/components/music_playlist.gd`, `rpg/scripts/components/music_quality.gd`, `rpg/scripts/components/locomotion_fx.gd`, `rpg/scripts/components/fall_scream.gd`, `rpg/scripts/components/sky_title.gd`.

---

## Map and minimap

**The HUD ships a minimap. You do not author one per level.** It sits in the top-right corner and it draws a
**procedural vector floorplan of the floor you are standing on** — derived at runtime from the level's own
geometry. There is no texture to render, no `MapData` to create, and nothing to place. Open any level and it
works.

**The WIDGET itself, though, is an authored scene** — `scenes/ui/hud_minimap.tscn`, which `ui.gd` instances into
the HUD. Its box, its draw order and its two art slots are editor work, not code: see **The minimap is a scene**
below, and the drop-in marker art in §27.

That is a change: this section used to tell you to render the level top-down, author a `MapData`, and drop a
`Minimap` `Control` into `ui.tscn` yourself. None of that is required now. If you *want* an authored image
under the procedural plan, that path is optional and per-level: author a `MapData` and assign it to your
level's `LevelData.map_data` — see **The authored underlay** at the end of this section.

### What it draws, and where each part comes from

Two layers, both derived from the level and both cached per floor:

1. **The walkable fill** — a dim wash over the floor, fanned from the level's **baked `NavigationMesh`**. This
   is why a freshly baked level has a usable map immediately. An UNBAKED level has no fill (see §14 — bake it).
2. **The wall strokes** — a **horizontal section cut** of the level's STATIC colliders, taken at chest height.
   A real floorplan is a section cut: walls become lines and doorways become the gaps between them. A level
   with no static colliders has no strokes. The cut is drawn as **one merged silhouette**, not as one outline
   per collider: see below.

**Overlapping brushes draw as ONE shape.** A level is *built* out of overlapping boxes, but a floorplan drawn
that way reads as a wireframe of your brushwork rather than as rooms — every box inking all four of its sides,
including the ones buried inside the box next to it. So the cut is unioned before it is drawn: any side that
runs inside a neighbouring solid is dropped, and a room built from four wall brushes prints as a room instead
of four rectangles crossing at the corners. Two brushes that merely **share a face** count as one too
(`minimap_merge_weld`, 5 cm — nonzero on purpose: an edge lying exactly on its neighbour's boundary otherwise
survives and gets inked twice). Nothing about your geometry changes; only the drawing does. `minimap_merge_solids`
turns it off if a level actually wants the seams. Two details worth knowing:

- A **trimesh collider or CSG bake** is cut into loose segments rather than closed rings, so it gets *trimmed
  by* the boxes around it but never trims them. A CSG blockout's bake is already one merged solid, so this
  costs you nothing in practice.
- A brush rejected by `minimap_max_solid_span` / `minimap_min_solid_span` (below) never merges either — a void
  seal encloses the whole level, and letting it into the union would blank the map.

On top of that: a caret for you, and dots for points of interest and NPCs.

**It draws ONE FLOOR — the band you are standing in.** This is the honest limitation to design around. A
mezzanine, a catwalk, or the top of a staircase is simply not on the map while you are below it, and a flight
of stairs reads as a gap between two floors. Markers on another storey fade rather than lying about being in
the room with you.

### Which knobs live where

The split is the usual one, and it matters when you go looking for a value:

**The rule, so you only have to remember one thing: if it changes how the map LOOKS it is on the skin
(`hud_skin.tres`); if it changes what the map DOES it is the scene or `HudSettings.tres`.** Colours and their
widths/sizes were split across two resources until 2026-08-19 — "make the walls orange" and "make the walls
thicker" were two different files — and they are now one group.

| You want to change | It lives on |
|---|---|
| Every colour AND every width/size the map inks — walls, floor fill, backing, rim, the four marker sizes, glyph stroke, alert-ring gap + step, off-floor tick + fade, north tick, rim-pin margin | `MenuStyle.hud` -> `resources/ui/hud_skin.tres`, group **Minimap** (§27) |
| The wall GLOW — a second, wider wall pass for a neon/inked restyle (alpha 0 = off, the shipped state) | `hud_skin.tres` -> `minimap_wall_glow_color` / `_width` |
| How much WORLD the box shows, where the section cut is taken, floor-band height + hysteresis, clutter-reject spans, wall merge + weld, zoom-key steps | `GameSettings.hud` -> `resources/tuning/HudSettings.tres`, group **Minimap**. These change which geometry gets GATHERED, not how it is inked |
| Whether a whole channel draws at all (walls / floor fill / NPC dots / station glyphs), and the deck cache + bake delay | The scene: `Minimap`'s own inspector in `scenes/ui/hud_minimap.tscn` |
| Drop-in ART for the player caret, POI beacons and the seven station badges | `MenuStyle.hud` -> `hud_skin.tres`, group **Minimap art** (§27). Ten optional `Texture2D` slots; null = the code-drawn glyph |
| A backdrop BEHIND the plan, or a bezel/frame/glass IN FRONT of it | The scene: drop art into `%MapUnder` / `%MapOver` in `scenes/ui/hud_minimap.tscn` (below) |
| Where the box sits and how big it is | The scene's root offsets — **and** mirror them into `minimap_inset` / `minimap_size` on `HudSettings.tres` (a test pins that the two agree) |
| Marker COLOURS — the neutral body ring, the hostile alert ring, the station family, the exit exception, the north tick | `MenuStyle.hud` -> `hud_skin.tres`, group **Minimap**. NOT the hostile/friendly/companion tints — those come from `CBPalette` so they swap with Colorblind-Safe Cues |
| Which GLYPH a station kind wears | `StationMarker.glyph_shape` / `glyph_angle` (`scripts/components/station_marker.gd`) — one shape per `Kind`, mapped beside the enum |
| On/off, heading-up vs north-up, zoom, NPC dots, station glyphs | The PLAYER's, in Options -> Accessibility. `Settings.minimap_*`, polled live |
| Which key cycles the zoom | `MinimapZoom` (default **M**) — rebindable in Options -> Controls -> Interface |
| Whether a particular prop counts as a wall | A `MinimapHide` child on that prop (below) |
| Whether a particular station is marked, and how | A `StationMarker` child on that station (below) |
| The CLOCK under the map -- box, gaps, font size | `GameSettings.hud` -> `HudSettings.tres`, group **Clock** (§18) |
| The clock's digit tint | `MenuStyle.hud.clock_color` -> `hud_skin.tres`, group **Clock** (§27) |
| Clock on/off, 12-hour vs 24-hour face | The PLAYER's, in Options -> Accessibility. `Settings.clock_*`, polled live |

`minimap_size` and `minimap_inset` must stay WHOLE PIXELS: the 792x444 canvas is nearest-upscaled ~2.4x, and a
fractional size rasterizes into a ragged edge. A test pins this (and the same rule for `clock_size`).

**The top-right corner is a THREE-ROW STACK: the map, the clock, then the objective tracker.** Each row's top is
DERIVED from the row above it, so nudging any of these knobs slides the whole stack instead of colliding with it --
and each row can be switched off independently by the player (map off lifts the clock into the corner; clock off
drops the tracker back to exactly where it sat before the clock existed). `tests/test_minimap_hud_layout.gd` pins
every combination, so you get an error rather than objective text silently drawing over the map.

**The top-right corner is shared with the objective tracker**, and the minimap owns the reflow: `ui.gd` measures
the AUTHORED box back out of the instanced scene (`UI.minimap_box`) and derives the tracker's top from
`box top + box height + minimap_tracker_gap`, so moving or resizing the box **in the editor** moves the clock and
the tracker with it. Turning the map off in Options returns the tracker to `minimap_tracker_bare_top` (8 px —
exactly where it sat before the minimap existed). Do not hand-place the tracker against the map.

The `minimap_size` / `minimap_inset` knobs are still real: they are the **fallback** box (used when there is no
widget — a bare `UI` in a test, a failed instantiate) and the numbers every layout invariant is pinned against.
So when you move the box in the scene, mirror it into `HudSettings.tres`; `tests/test_minimap_scene.gd` fails
loudly if the two stop describing the same rectangle.

### The minimap is a scene

`scenes/ui/hud_minimap.tscn` is the widget. Open it and you get a box you can drag, plus **two empty art slots
whose tree order is the render order**:

| Node | Renders | Put here |
|---|---|---|
| **`%MapUnder`** | wholly BEHIND the procedural plan | a backdrop: paper, parchment, a CRT wash, a grid |
| *(the root's own drawing)* | backing, floor fill, wall strokes, markers, caret, rim | — code-drawn, tinted from `hud_skin.tres` |
| **`%MapOver`** | wholly IN FRONT of everything | a bezel, a frame, glass, scanlines, a vignette, corner brackets |

Both ship empty, so an untouched game draws exactly what it always drew — art lands **one node at a time**.

- **A backdrop in `%MapUnder` needs the backing out of the way.** The code-drawn backing rect paints over it.
  Zero the **alpha** of `minimap_backing_color` in `hud_skin.tres` and your art shows through (alpha-as-null, the
  same sentinel `StationMarker.color` uses).
- **A `NinePatchRect` in `%MapOver` is now the right way to frame the box** — it stretches its edges and keeps its
  corners sharp. The older `HudSkin.minimap_frame_texture` slot scales one flat PNG over the whole box; it stays
  for the looks that really want that.
- **`%EditorPreview`** is a grey fill that exists only so you can see the box in the 2D editor and align art
  against it. `_ready` hides it at runtime. Leave it alone.

Four limits, all deliberate:

1. **Art cannot go BETWEEN the plan and the markers.** The plan, the dots and the rim are one `_draw` pass.
2. **Everything is clipped to the box.** `clip_contents` is forced in code — a marker pinned to the rim must not
   escape onto the quest tracker below, and the rim-pin margin maths is written against the clip being on.
3. **`mouse_filter` is forced to IGNORE on every art node you add.** An authored `TextureRect` / `NinePatchRect` /
   `ColorRect` defaults to STOP, which would make the top-right corner of the screen eat clicks.
4. **No text in the scene.** Strings belong to `PlayerText` (l10n + the text-debt ratchet), same as every menu.

Art children need **no repaint wiring**: each is its own `CanvasItem`, so nothing you add can affect the map's
idle gate (the widget deliberately does not repaint while you stand still — see `Minimap._needs_repaint`).

### Restyling the plan itself (no art required)

The walls, the floor fill and the markers are all drawn, so they restyle from `hud_skin.tres` alone — you do
not need to deliver a single PNG to change how the map reads. Everything below is one resource, live-editable
against a running game through Godot's **Remote** inspector:

| To do this | Set |
|---|---|
| Recolour the walls | `minimap_wall_color` |
| Make the walls thicker | `minimap_wall_width` (0 = hairline, the shipped crispest look) |
| **Neon walls** | `minimap_wall_glow_color` to the wall hue at ~0.5 alpha, `minimap_wall_glow_width` ~5 |
| **Inked-on-paper walls** | glow colour a dark translucent brown, `minimap_walkable_color` a warm cream |
| Bigger/smaller arrow | `minimap_caret_px` |
| Bigger/smaller markers | `minimap_poi_glyph_px`, `minimap_npc_glyph_px`, `minimap_station_glyph_px` |
| Heavier outlines on the hollow glyphs | `minimap_glyph_stroke_px` |
| Lose the rim (because your frame art replaces it) | `minimap_outline_width = 0` |

The glow is a **second pass of the same wall geometry**, drawn wider and underneath — one extra draw call
over a buffer that is already built, no shader and no second viewport. It ships with **alpha 0 = off**, so
the shipped plan is untouched until someone reaches for it.

**The reference pack.** `scripts/tools/minimap_qa_shots.gd` boots the real game and captures the corner at the
true runtime canvas — shot 01 is the whole screen, 02 is the box alone at 4x nearest, and 03/04 inject stand-in
art into both slots so you can see the sandwich working. Run it windowed (the GPU must render), then upscale the
PNGs with **NEAREST** for a hand-off — the canvas is deliberately low-res and a smooth upscale lies about the
pixel look:

```bash
godot --path . res://scripts/tools/minimap_qa_shots.tscn -- --shots-dir="C:/some/dir"
```

### Markers on it

- **Points of interest** — anything in the `&"minimap"` group (`Groups.MINIMAP`), which is what a **`WorldMarker`**
  joins. These are drawn in the marker's own `color`, and when one is off the edge of the box it PINS to the rim
  pointing at itself, because an objective you cannot see yet is exactly what you want pointed at. Active quest
  objectives get theirs automatically from a **`QuestMarkerSync`**, which `LevelTemplate.tscn` now ships — see §17.
- **NPCs** — every living NPC, as a **shape** in an allegiance **colour**. Unlike a POI marker an NPC dot is
  **never pinned to the rim**: pinning bodies would report every NPC on the level against the box edge, which is
  a radar rather than a floorplan. A dot means "actually near you". Dead NPCs are filtered (bodies are pooled,
  so a corpse would otherwise blip forever). The player switches these off with Options -> Accessibility ->
  **NPCs On Minimap**; the designer switch is `Minimap.dot_npcs`.
- **Stations** — a shop, bank, clinic, trainer, tech booth, resting spot or level exit, as a **stroked** glyph.
  These come free with the component; see **Stations on the map** below.

### The glyph alphabet — why shape and not just colour

A marker is 4-5 px on a 108 px box. **Hue alone cannot carry a distinction at that size**, and this project also
ships Options -> Accessibility -> **Colorblind-Safe Cues**, which deliberately swaps the hostile/friendly hues —
so any fact encoded only as a colour is a fact the player may not be able to read. Every marker therefore carries
its meaning in its SHAPE first and its colour second. The vocabulary is `MapGlyph.Shape`
(`scripts/ui/map_glyph.gd`, pure statics, pinned by `tests/test_map_glyph.gd`):

| Marker | Shape | Fill | Colour comes from |
|---|---|---|---|
| Hostile body | triangle (caret) | filled | `CBPalette.hostile()` |
| Recruited companion | diamond | filled | `CBPalette.ally()` |
| Friendly body | circle | filled | `CBPalette.friendly()` |
| Neutral body / anything that answers nothing | circle | **hollow ring** | `MenuStyle.hud.minimap_neutral_color` |
| Shop (`Merchant`) | diamond | stroked | `minimap_station_color` |
| Bank (`Atm`) | hexagon | stroked | `minimap_station_color` |
| Clinic (`Healer`) | cross | stroked | `minimap_station_color` |
| Trainer (`LevelUp` / `PerkStation` / `RespecStation`) | triangle, **inverted** | stroked | `minimap_station_color` |
| Tech booth (`ChipInstaller`) | square | stroked | `minimap_station_color` |
| Rest / play (`Bonfire` / `ChessMatch`) | circle | stroked | `minimap_station_color` |
| Level exit (`LevelDoor`) | chevron (arrowhead) | stroked | `minimap_exit_color` |

**Two rules keep the two families apart, and both matter.** Bodies are FILLED and small; stations are STROKED and
larger. That is why a hollow triangle is a campfire and a solid one is a man with a gun. Trainer is additionally
turned upside down, because triangle is the one shape the two alphabets share and "hostile" is the reading you
cannot afford to get wrong. **Do not fill station glyphs**, and do not un-invert the trainer.

### The hostile alert ring

A hostile that has noticed **you** grows an amber halo outside its caret — one radius step per
`Perception.SuspicionTier` (WARY, SUSPICIOUS, ALERTED). It reads `NPC.suspicion_of(player)`, which is
**target-gated**, so a guard trading fire with a stray dog does not ring; and it is gated on **hostile**, so a
shopkeeper glancing at you or a companion tracking you never wears the threat halo. The ring GROWS rather than
recolouring, so the threat level survives the colourblind palette swap. Tune it with `minimap_alert_ring_gap_px`
and `minimap_alert_ring_step_px`; recolour it with `MenuStyle.hud.minimap_alert_color`.

This reveals nothing the player cannot already learn from the detection meter and the `[ HIDDEN ]` badge — what
it adds is WHICH body noticed, which is the difference between "run" and "deal with that one guard". **Never add
a sight cone**: `Perception.can_see()` raycasts, and the HUD draws off the physics frame where
`direct_space_state` returns empty *silently*, so a cone would pass every test and report nothing in play.

### Off-floor markers, and finding north

- **Up/down ticks.** A marker on another storey already faded; it now also draws a small tick above or below
  itself, so "two floors up" no longer looks the same as "far away". Length is `minimap_floor_tick_px` (0 disables
  the ticks and leaves the fade to speak alone).
- **The north spoke.** In heading-up mode the plan turns under a fixed caret, so there is otherwise no fixed
  bearing anywhere on the HUD — you can spin on the spot and every landmark moves. A short spoke on the rim points
  at world north. Skipped entirely in north-up mode, where north is always the top of the box. Length is
  `minimap_north_tick_px`, colour `MenuStyle.hud.minimap_north_color`.
- **Zoom without opening Options.** `MinimapZoom` (default **M**) cycles `minimap_zoom_steps` and wraps, writing
  through the same `Settings.set_minimap_zoom` the Options slider uses — so the key and the slider are one value
  and a keyed zoom persists. Keep every authored step inside `Settings.MINIMAP_ZOOM_MIN/MAX` (0.5–3.0) or two
  steps clamp onto the same value and the key appears to do nothing (a test pins this).

### Stations on the map (`StationMarker`)

**You do not place this.** Each of the ten station components calls `StationMarker.ensure(self, <kind>)` from its
own `_ready`, so dropping a bare `Merchant` / `Atm` / `Healer` / `Bonfire` / `LevelUp` / `ChipInstaller` /
`ChessMatch` / `PerkStation` / `RespecStation` / `LevelDoor` into a level puts it on the minimap with no tick to
remember and no child node to add. This is the same bargain `StationSpeaker.ensure` makes for the station voice.

Child a **`StationMarker`** (`scripts/components/station_marker.gd`, a `Node3D`) under a station ONLY to override
something — an authored one always wins:

- **`enabled = false`** — keep this one station off the map entirely (the `MinimapHide` role, per station).
- **`kind`** — a different glyph (a `Merchant` that is really a fence, a `Bonfire` that is really a shrine).
- **`color`** — a per-instance tint. It ships **transparent**, which is the sentinel for "use the skin"; any
  alpha above 0 wins, so a story-critical vendor can be picked out of the family.
- **its POSITION** — it is a `Node3D`, so moving it moves the pin without moving the station's hitbox. Useful when
  the interactable sits on a counter but the pin should read at the shop's doorway.
- **`pin_offscreen`** — whether the glyph pins to the box rim when it is off the drawn area.

**Pinning defaults from the station's own `standalone` flag**, which already answers "am I a fixed kiosk or am I
riding a person": a wall terminal points at itself from the rim, while a vendor on a walking NPC stays clipped to
the box, because a rim blip that tracks a body around the edge is the radar this widget refuses to be. A station
with no `standalone` field at all (`PerkStation`, `RespecStation`, `LevelDoor` are always on the talk layer) is a
fixed fixture by construction, so it pins.

**A station riding a dialogue NPC gets BOTH marks** — the shop glyph *and* the body's allegiance dot. That is why
stations have their own group (`Groups.MINIMAP_STATION`) rather than joining `Groups.MINIMAP`: the POI channel is
what the NPC loop skips, so joining it would have traded "who is hostile" for "who is a shop" on exactly the
7-of-8 placed stations that ride NPCs.

**Adding an eleventh station type:** add a `Kind`, map it in `StationMarker.glyph_shape` (and `glyph_angle` if it
needs turning), and add the `StationMarker.ensure(self, Kind.X)` line to the component's `_ready`. A roster test
(`tests/test_station_marker.gd`) greps for that line, so a station that forgets it fails loudly instead of being
silently missing from the map.

### Keeping a prop out of the walls (`MinimapHide`)

A chain-link fence, a market awning, a parked car and a pipe run all have colliders, and all of them cut into
clutter that hides the room behind them. Child a **`MinimapHide`** (`scripts/components/minimap_hide.gd`, a
plain `Node`) under the prop and its whole subtree drops out of the wall cut. Collision is untouched — the prop
still blocks bullets, footsteps and navigation.

- **It marks its PARENT, not itself**, which is why you child it under the prop rather than dropping it beside
  one. (That is also why it is a `Node` and not a `Node3D`.)
- **`enabled` is read once, at level load**, during the single gather that makes the map free per frame.
  Toggling it at runtime does nothing until something calls `Minimap.rebake()`.

Two blunter dials for the same problem, both in the Minimap tuning group: `minimap_min_solid_span` rejects
detail smaller than it on both axes (trim, sign backers, pipe collars), and `minimap_max_solid_span` rejects a
brush bigger than it on both axes — that one exists for the Quake "void seal", a worldspawn box enclosing the
whole map, which would otherwise draw a frame around every room.

### The authored underlay (`MapData`) — optional, per level

`MapData` (`class_name MapData`, `@tool` `Resource`, `res://scripts/ui/map_data.gd`) is an authored top-down
image plus the world rect it covers. Assigned, its image is drawn UNDER the procedural plan, positioned
through the SAME view matrix via its `world_bounds` — so the picture and the dots cannot drift apart.

**The authoring surface is `LevelData.map_data`** — three inspector steps, no widget to place, no wiring:

1. **Make the `MapData`:** Content dock → **New Map** (scaffolds a `.tres` into `res://resources/maps/`;
   **Browse** lists them under Maps), or create the resource by hand.
2. **Fill it in:** set `map_texture` (your top-down render) and `world_bounds` (the fields below).
3. **Assign it** to your level's `LevelData` (`resources/levels/*.tres`) in its `map_data` slot.

The HUD minimap picks it up on level load by itself: the widget re-resolves the active level's map inside
`rebake()`, riding the same region-staleness hook that drops its deck cache, and a level with no `map_data`
**clears** the previous level's image rather than keep drawing it in the wrong world space
(`tests/test_minimap.gd` pins the stamp, the clear, and the precedence). The `Minimap.map_data` export still
exists as a **per-widget override** — set on an instance it wins over every level's map; the shipped
code-built HUD widget leaves it null.

- **`map_texture`** (`Texture2D`) — a top-down image of the level.
- **`world_bounds`** (`Rect2`, default `Rect2(-50, -50, 100, 100)`) — the world area that image covers. It is a
  top-down projection, so `x` / `width` are the world **X** span and `y` / `height` are the world **Z** span;
  **world Y is ignored.** Get this wrong and the image slides off the plan under it.
- **`player_marker`** / **`npc_marker`** (`Texture2D`) — optional icons replacing the drawn caret and dots.

A texture-less `MapData` is VALID and means "no underlay" — assigned or not, the procedural plan still draws.
A sample ships at `res://resources/maps/sample_map.tres`.

**Gotcha**
- **The map only knows about a level's geometry, not its intent.** If a room reads badly, reach for the dials in
  the table above rather than assuming it is broken: `minimap_cut_height` (is the cut passing through a mezzanine
  floor or under a counter?), `minimap_min_solid_span` (speckle), and `MinimapHide` on the individual offender.
- **An unbaked level draws no floor fill.** That is the navmesh bake talking, not the minimap — see §14.

---

## Quest markers and the compass

On top of the minimap, CYBER SUNDAY has a **point-of-interest beacon** system that feeds two HUD channels at once: a screen-edge **compass** (chevrons pointing at off-screen objectives) and the **minimap** (dots). You place a beacon by dropping one node -- it joins both channels with zero wiring -- and active quest objectives spawn their own beacons automatically. This is the system that finally puts NPCs/objectives on the minimap (the older "nothing joins the minimap group yet" caveat is gone).

### WorldMarker -- the drop-in beacon (`res://scripts/components/world_marker.gd`)

A **`WorldMarker`** (`class_name WorldMarker`, `extends Node3D`) is a point-of-interest you drop in the world. On `_ready` it adds itself to the `&"compass"` and/or `&"minimap"` groups, so both HUD channels pick it up with no further wiring. Place them by hand for **fixed landmarks** -- a vendor, an exit, a stash -- or let `QuestMarkerSync` (below) spawn them for live objectives.
- **`on_compass`** (bool, `true`) -- show as a chevron on the screen-edge compass (joins the `&"compass"` group).
- **`on_minimap`** (bool, `true`) -- show as a dot on the minimap (joins the `&"minimap"` group).
- **`color`** (Color, default `Color(1.0, 0.85, 0.3)` -- amber) -- the marker tint. The **compass chevron always uses it**; on the minimap it colours the **fallback dot** when `MapData.npc_marker` is unset (the default), but is ignored once a shared `npc_marker` texture is assigned (every NPC dot then uses that one texture).

> Not `@tool` on purpose: a plain `Node3D` never runs `_ready` in the editor, so it joins its groups only at runtime -- you won't see it on the HUD until you play.

### Compass -- the screen-edge HUD (`res://scripts/ui/compass.gd`)

A **`Compass`** (`class_name Compass`, `extends Control`) draws every `WorldMarker` in the `&"compass"` group: a dot where the marker is when it's on-screen, or a **chevron pinned to the screen edge pointing toward it** when it's off-screen or behind you. Add it to the HUD (`res://scenes/player/ui.tscn`) as a **full-rect Control** (it needs to span the screen to project to the edges) and it needs the active `Camera3D` to project world->screen. It only redraws while visible, so a hidden compass costs nothing.
- **`edge_margin`** (float, `28.0`) -- inset (px) of the edge-chevron ring from the screen border.
- **`marker_size`** (float, `6.0`) -- radius (px) of a drawn marker dot / chevron.
- **`max_distance`** (float, `0.0`) -- hide markers farther than this (m) from the camera. `0` = no limit (show all).

### QuestMarkerSync -- auto-markers for active objectives (`res://scripts/components/quest_marker_sync.gd`)

A **`QuestMarkerSync`** (`class_name QuestMarkerSync`, plain `Node`) -- drop **one into a level** and it spawns a `WorldMarker` for every ACTIVE quest objective that asked for one (`show_marker`, see below), and removes them as objectives complete or quests finish or fail. It's driven by `GameState`'s quest signals (`quest_started` / `objective_advanced` / `quest_completed` / `quest_failed`) and rebuilds the whole marker set on any quest change -- so the compass and minimap always point at your current objectives with **no per-quest wiring**.
- **`marker_color`** (Color, default `Color(0.4, 0.9, 1.0)` -- cyan) -- the tint for every objective marker it spawns.

### Putting a marker on a quest objective

The objective itself opts in, via the **Marker** group on `QuestObjective` (`res://scripts/quests/quest_objective.gd`, see also §14):
- **`show_marker`** (bool, `false`) -- on = a `QuestMarkerSync` shows a compass chevron + minimap dot at `marker_position` while this objective is active, and removes it when the objective is done. Off = no marker.
- **`marker_position`** (Vector3, `Vector3.ZERO`) -- the world position the marker sits at: the objective's destination (a turn-in NPC, an area, a pickup spot).

So the full objective-marker recipe is: tick `show_marker` and set `marker_position` on the objective, and drop one `QuestMarkerSync` in the level. Nothing else.

### Worked example -- guide the player to a turn-in NPC

> Goal: while a quest's "report back" step is active, a chevron points the player to the questgiver; it vanishes when they hand in.

1. In the quest's `QuestObjective` for the turn-in step, open the **Marker** group: tick `show_marker`, and set `marker_position` to the questgiver's world position (copy it from the NPC's `Transform`).
2. Drop a **`QuestMarkerSync`** anywhere in the level (it's a plain `Node`; tint its `marker_color` if you like).
3. The **minimap** needs nothing — the HUD ships one (§16). For the screen-edge chevron as well, add a **`Compass`** (full-rect Control) to the HUD; unlike the minimap it is still not shipped by default.
4. Play. While that objective is active, a cyan chevron rides the screen edge toward the NPC (and a dot shows on the minimap); finishing the objective removes both automatically.

For a **permanent landmark** (a vendor that's always marked), skip the objective and just drop a `WorldMarker` at the spot -- set its `color`, leave `on_compass`/`on_minimap` on.

### Gotchas

- **The compass must be a full-rect Control.** Its edge-chevron math projects to the viewport rectangle, so a small/anchored Compass will pin chevrons to its own little box, not the screen edge. Anchor it full-rect on the HUD.
- **`WorldMarker` only joins its groups at runtime.** It's not `@tool`, so you won't see it on the HUD in the editor -- press Play to verify placement.
- **`color` tints the compass chevron always; on the minimap it colours the fallback dot only when `MapData.npc_marker` is unset (the default).** Assign a shared `npc_marker` texture and every NPC dot draws with that texture instead, ignoring per-marker `color`.
- **`QuestMarkerSync` rebuilds on every quest change.** That's intentional and cheap (few active objectives). Don't expect a marker to linger after its objective completes -- the rebuild drops it. Same for a quest that **fails** (an `expire_on_flag` expiry or an explicit fail, §14): it leaves the active set, so its beacons go with it.
- **An objective marker needs all three pieces.** `show_marker` + a sane `marker_position` on the objective, AND a `QuestMarkerSync` in the level. Miss the sync node and the objectives are tracked but never beaconed.

Relevant files: `res://scripts/components/world_marker.gd`, `res://scripts/ui/compass.gd`, `res://scripts/components/quest_marker_sync.gd`, `res://scripts/quests/quest_objective.gd` (the `show_marker` / `marker_position` Marker group).

---

## The day/night clock and NPC routines

CYBER SUNDAY runs a single global **day/night clock** that any system can read, and NPCs can follow a **daily routine** off it -- "market by day, home by night." Both halves are designer-reachable: the clock is an always-on autoload you tune with plain numbers, and a routine is a drop-in component pointed at an authored `.tres`. There is nothing to wire by hand -- the clock advances itself and the routine reads it.

### The clock: `WorldClock` (`res://managers/WorldClock.gd`)

**`WorldClock`** is an autoload (a `Node` that's always loaded, no `class_name`). It owns one number -- the time of day -- and advances it every frame. It **pauses with the tree**, so a paused game freezes the clock too. Its three knobs are plain `var`s (not consts), so a designer or a small script can retune the cycle at runtime:

- **`time_of_day`** (float, `0..1`, default `0.5`) -- the current time. `0` = midnight, `0.5` = noon. It starts at noon so a fresh game opens in daylight, and wraps (`fposmod`) so it never leaves `0..1`.
- **`day_length_seconds`** (float, `600.0`) -- how many REAL seconds one full in-game day takes. Lower = faster cycle. **Set it to `0` to FREEZE the clock** (it stops advancing entirely -- handy for a level you want pinned to one time).
- **`day_start`** (float, `0.25`) and **`night_start`** (float, `0.75`) -- the `time_of_day` fractions where DAY (dawn) and NIGHT (dusk) begin. DAY is the half-open band `[day_start, night_start)`; everything else is NIGHT. Widen or shift the band to make days longer/shorter or dawn earlier.

**Reading the clock** (you rarely call these -- the routine component does it for you):
- **`WorldClock.phase()`** -- the live `Phase` (`enum Phase { NIGHT, DAY }`, so `0` = Night, `1` = Day), cached and updated each frame.
- **`WorldClock.phase_of(t)`** -- pure: the `Phase` for any `time_of_day` fraction (DAY in `[day_start, night_start)`, else NIGHT). Used for "what phase WOULD it be at time t."
- **`WorldClock.time_of_day`** -- read the raw `0..1` fraction directly (exactly what `DayNightSky` eases its sun off -- see below).
- **`phase_changed(new_phase: int)`** -- a signal that fires the instant the live time crosses a day/night boundary. Connect it to swap lights, open/close a shop, or flip a flag at dusk.

### Waiting: the Wait screen (`res://scenes/ui/wait_screen.tscn`)

**The player can also MOVE the clock.** Pressing **T** (the Fallout 3/NV key — `Claim`/Befriend moved to **B** to free it) opens `WaitScreen`, an autoload modal where the player picks a number of in-game hours and confirms. You author nothing; it ships wired.

⭐**It routes through `WorldClock.advance_hours`, never `set_time_of_day`.** That is the whole difference between the two ways of moving the clock (see the `WorldClock` section above): `advance_by`/`advance_hours` WALK the span and emit `phase_changed` once per boundary crossed, so a three-day wait fires three dawns — rent falls due three times, interest posts three times, NPC schedules step. `set_time_of_day` is the SILENT seek for a save restore, and using it for a wait would let the player skip every dawn forever. If you write a cutscene that covers a night, use `advance_by` for the same reason.

**Tuning: `GameSettings.wait` → `resources/tuning/WaitSettings.tres`.**
- **Span** — `max_hours` (`24`), `min_hours` (`1`), `default_hours` (`1`): the selector's range and where it opens.
- **Recovery** — `hp_per_hour` (`2.0`), `hp_cap_fraction` (`1.0`), `heals_limbs` (`off`). ⭐Waiting is **not** a rest: a `Bonfire` is the full heal AND the respawn checkpoint, and a wait that matched it would make fires pointless. Set `hp_per_hour = 0` for the strict New Vegas rule (waiting never heals).
- **Refusal** — `hostile_awareness_blocks` (`on`), `airborne_blocks` (`on`).

**When waiting is refused** (it toasts the reason rather than opening a card with a dead button — the screen frees the mouse, and freeing it mid-firefight would be worse than the missing panel):
- something is hunting you — `StealthStatus.Level.CAUTION` or worse, the SAME aggregate the stealth HUD reads (a merely-filling detection meter does *not* block, or waiting would be impossible anywhere patrolled);
- you are airborne;
- ⭐**the level's clock is FROZEN** (`day_length_seconds = 0`). Time genuinely does not pass on such a level, so waiting there is refused outright — which is what keeps the frozen-clock promise below (no dawns, no rent) true even with a Wait key in the player's hands.

**The player can SEE the clock.** The HUD ships a time-of-day readout (`scripts/ui/hud_clock.gd`) directly under the minimap -- you author nothing, it is code-built by `ui.gd` like the map is. It renders `WorldClock.time_of_day` as digits ("14:35", or "2:35 PM" if the player prefers a 12-hour face) so the hour is a readout rather than something to infer from the lighting -- which is a poor instrument, since `DayNightSky`'s moon keeps midnight legible and interiors are lit around the clock. Its knobs follow the usual split: box/gaps/font size are author-time tuning on `GameSettings.hud` group **Clock**, the digit tint is `MenuStyle.hud.clock_color` (§27), and **On/off + 12-hour vs 24-hour belong to the PLAYER** in Options -> Accessibility (`Settings.clock_enabled` / `Settings.clock_24_hour`, polled live -- a change bites the same frame). **Setting `day_length_seconds = 0` freezes the displayed time too**, which is the right look for a level pinned to one hour but reads as a broken clock if you did not intend it.

### The look of the clock: `DayNightSky` (`res://scripts/effects/day_night_sky.gd`)

**`DayNightSky`** (`class_name DayNightSky`, plain `Node`) is the clock's VISUAL half -- without one, a level's lighting is frozen at whatever you authored no matter what time it is. Drop the bare node anywhere in a level (**the main level authors one** beside its `DirectionalLight3D`).

⭐⭐**The authored look is the resting state.** A bare DayNightSky changes NOTHING about how your day looks: the sun keeps its authored direction, colour and energy (the main level's low violet key light), the sky material is untouched, and the ambient holds its authored value -- **at noon the level renders identically to the scene with the component deleted** (measured, not assumed: same mean screen luminance, same sun/fog/ambient values). What the bare node adds is only the NIGHT: the key light eases down from the sun's authored energy to the **moon's** fraction of it, and the level runs on that plus its fixtures until dawn. Your manicured aesthetic is the anchor the cycle returns to every morning.

⭐**The moon is what makes night work.** The first version simply switched the sun off below the horizon and dimmed the ambient to a third — and midnight came out unreadably black. The fix is a **moon**: the *same* `DirectionalLight3D`, kept alive at `moon_energy_scale` (`0.2`) of its authored energy in `moon_color` (a cool blue-white), still on your authored key angle. That matters because **ambient is the wrong dial for night** — it is flat, so cutting it removes brightness without adding any shape and the street becomes one dark mass; a dim *directional* keeps edges, falloff and a sense of where light comes from. Hence `ambient_night_scale` now ships at `1.0` (night keeps the full authored ambient) and the moon carries the difference. The sun→moon handover is a `max()` crossfade, never a lerp — a lerp passes through a value dimmer than both and puts a visible dip in every dusk. Knobs: `moon_energy_scale`, `moon_color`, `moon_fog_scale` (`0.25` — a moon pushing the sun's full volumetric-fog energy greys the night haze into soup and swallows the neon). **`moon_energy_scale = 0` restores the old pitch-black night** — and with it the fully-hidden stealth night, since the key light then really is off.

**The cinematic extras are OPT-IN**, each its own knob, all defaulting off or to "authored":

- **`drive_sun_rotation`** (off) -- arc the sun: horizon at dawn (`0.25`) up to `max_sun_pitch_deg` at noon, back down at dusk (`0.75`), with a yaw sweep so shadows move. Turning it on also engages `high_sun_fog_scale` (see the callout below).
- **`sun_color_gradient`** (null = authored colour at every hour) -- author a `Gradient` to colour-ramp the day; the knob's doc comment carries a classic night-blue -> dawn-amber -> warm-noon recipe.
- **`drive_sky`** (off = the authored moody horizon sky holds 24/7) -- day-brighten the StarSky horizon shader via its existing `zenith_color` / `horizon_color` / `sun_glow` / `sun_azimuth` uniforms (parameter writes only; StarSky keeps the material, the panorama and the kill `flash`). Skipped silently if the live sky isn't the horizon shader.

**Knobs** (grouped in the Inspector): Sun -- `sun` (null = auto-find), `drive_sun_rotation` (off), `peak_sun_energy` (**`0` = authored**), `sun_energy_curve`, `sun_color_gradient` (null = authored), `max_sun_pitch_deg` (`58`), `sun_yaw_deg` (`35`), `sun_sweep_deg` (`120`), `high_sun_fog_scale` (`0.12`); Moon -- `moon_energy_scale` (`0.2`), `moon_color`, `moon_fog_scale` (`0.25`); Ambient -- `drive_ambient`, `world_environment` (null = group lookup), `ambient_day_scale` (`1.0`), `ambient_night_scale` (`1.0`); Sky -- `drive_sky` (off), `sky_day_zenith` / `sky_day_horizon`, `sky_night_zenith` / `sky_night_horizon` (defaults mirror the shader's authored night), `sky_sun_glow` (`0.5`).

> ⭐**Two probe-verified traps the ARC knobs encode** (relevant only with `drive_sun_rotation` on). `max_sun_pitch_deg` is deliberately NOT 90: at a true overhead noon, vertical facades catch grazing-incidence ~nothing and a canyon city goes DARK at midday. And `high_sun_fog_scale` scales the sun's `light_volumetric_fog_energy` down as it climbs -- the authored `2.519` is tuned for a GRAZING sun the buildings shadow; at full energy an overhead sun reaches into every street canyon and saturates the volumetric fog to a white sheet. A held authored direction keeps the authored fog energy verbatim. Retune either only with `scripts/tools/day_night_shots.gd` open (below).

> **Night is a stealth buff for free:** `PlayerLightLevel` adds a `DirectionalLight3D`'s raw energy globally, so dropping the key light from the sun's authored energy to the moon's fraction of it drops the player's light exposure by the same ratio — darkness-stealth engages at night with zero wiring. (It is the moon's *energy* that does this, not the light switching off; with a moon the sun node stays visible all night.) Give a `MyLight` fixture **`night_only`** to douse it (light + buzz + stealth contribution) during the day -- off by default, so every authored fixture keeps burning 24/7 until you opt it in. The first-person gun's ambient fill also follows the cycle (`ViewModelCamera.night_fill_scale`), so the view model darkens with the world at night.

**Judging it by eye:** run `& "C:\Users\dalla\bin\godot.cmd" --path . -s scripts/tools/day_night_shots.gd` from `rpg/` -- a ~20 s WINDOWED run (headless never compiles shaders) that boots the main level, freezes the clock at midnight / morning / noon / dusk, and writes a PNG per stop (default `user://day_night_shots`, or pass `-- --shots-dir=<dir>`). To watch the cycle in-game fast, drop `WorldClock.day_length_seconds` to `30`.

### RentCollector -- a recurring money sink on the clock (`res://scripts/components/rent_collector.gd`)

A **`RentCollector`** (`class_name RentCollector`, plain `Node`) is a landlord on a timer: it rides the `WorldClock` dawn tick and, every `period_days` in-game days, charges the player rent. It's the canonical **recurring money sink**. Drop it anywhere that makes sense as a book-keeper -- under a landlord NPC, under a rented safehouse, or on the level root. Every knob is an `@export` on the node; no code, no wiring (it connects to `WorldClock.phase_changed` itself on `_ready`).

**It is OFF by default.** With `rent_amount` at its default `0.0` the collector is inert -- dropping one in changes nothing until you set a rent (and a disarmed collector is *completely* silent: it doesn't even serve its notice). The player can also **never go into debt**: if they can't cover the charge it takes whatever they have (down to zero) and reports the shortfall, so you can wire the consequence yourself.

> ⚠ **Arm a collector and you MUST author `notice_message` + `grace_days`.** A recurring charge the player was never told about doesn't read as a debt clock, it reads as a bug -- *"what rent?"*. This is not hypothetical: on the shipping clock (`day_length_seconds = 600`, the game opening at noon) the first dawn lands **7m30s into a fresh run**, and `EconomySettings.player_starting_money` is `0`, so an un-graced collector's first and only player-facing word about rent is a red *you failed to pay* toast against a wallet that was empty by construction. The notice/grace pair exists to make the first word a statement of terms instead. `tests/test_shipping_level_rent.gd` pins this for the shipping level.

**Rent**
- **`rent_amount`** (float, `0.0`) -- zorkmids charged each cycle. **`0` (default) = OFF** -- no rent is ever collected. Fractional is fine (it's the Zorkmids scale).
- **`period_days`** (int, `1`) -- in-game days between charges, one `WorldClock` dawn (the NIGHT->DAY crossing) counted as one day. Floored at `1`, so an armed collector charges at least daily.
- **`grace_days`** (int, `0`) -- dawns of grace before the meter starts. The notice is served on the **first** dawn; this many dawns (that one included) then pass free, and only after them does the `period_days` counter begin. **`1` is what an armed collector wants** -- told at the first dawn, billed at the second, so the player has a full in-game day to earn it. `0` (the default, kept so existing authored collectors are unchanged) serves the notice and the first bill on the same dawn.

**Feedback** -- all three lines substitute the same way: named tokens by replacement, and money arrives as the **whole `Zorkmids.money_text` phrase** (`"20 zm"`), so author `"{amount}"`, never `"{amount} zm"`.
- **`notice_message`** (String, `""`) -- the one-shot toast served at the first dawn, **before any money moves**: the answer to *"what rent?"*. Tokens `"{amount}"` (the charge) and `"{days}"` (the period, floored the same way the counter floors it). Blank = the terms are never announced, which is exactly what makes a later charge read as a bug.
- **`paid_message`** (String, `""`) -- optional toast shown when rent is collected; `"{amount}"` is the amount taken (e.g. `"Rent paid: {amount}"`; a legacy `"%s"` still works). Blank = silent.
- **`missed_message`** (String, `""`) -- optional toast shown when the player can't cover the rent. Tokens `"{shortfall}"` (what went unpaid), `"{amount}"` (the rent that was **owed**, not the part collected) and `"{paid}"` (what was actually taken). Blank = silent.

**Signals** (wire a consequence to these):
- **`notice_served(amount: float)`** -- the terms were announced, before any money moved. Fires even when `notice_message` is blank, so a landlord bark or a quest flag can carry the beat instead of a toast.
- **`rent_paid(amount: float)`** -- the full rent was collected this cycle.
- **`payment_missed(shortfall: float)`** -- the player couldn't cover it; `shortfall` is what went unpaid. Connect this to an eviction `TriggerVolume`, a reputation hit, a flag flip, or a threatening toast.

You can also call **`collect()`** directly (e.g. from a dialogue "pay up" option or a cutscene `CALL_METHOD`) to charge the rent on demand; it's a no-op when disarmed or no player is found, and obeys the same never-go-negative rule. Pass a specific wallet node to `collect(player_node)`, or omit it to charge the player found via the `&"Player"` group.

#### Worked example -- a weekly rent on a safehouse

1. Add a **`RentCollector`** node under the safehouse (or its landlord NPC).
2. Set `rent_amount = 50`, `period_days = 7`, `grace_days = 1`.
3. Author all three lines: `notice_message = "The landlord wants {amount} every {days} days. First one is due next week."`, `paid_message = "Rent paid: {amount}"`, `missed_message = "You're behind on rent by {shortfall}."`
4. Connect `payment_missed` to a `TriggerVolume`'s eviction action (or set a `GameState` flag) so missing rent has teeth.
5. Play with a faster clock to verify: drop `WorldClock.day_length_seconds` (e.g. to `30`) so the notice, the grace dawn and seven more dawns pass quickly and you can watch all three toasts fire in order.

#### Gotchas

- **It counts DAWNS, not real time.** Rent comes due on the `period_days`-th NIGHT->DAY crossing. A **frozen clock** (`WorldClock.day_length_seconds = 0`) never advances, so the phase never changes and **rent never comes due** -- the same freeze that pins a level to one time also pauses every `RentCollector`. The clock (and so the rent timer) also pauses with the game.
- **Arming rent without a notice is an authoring bug, not a hard mode.** See the warning above: work out when your first dawn actually lands and what the player's wallet holds at that moment before you decide `grace_days`.
- **Waiting delivers several dawns in ONE frame.** `WorldClock.advance_by()` (the player Waiting, a cutscene covering a night) walks every boundary the span crosses, so a long wait runs notice -> grace -> charge -> charge in a single call, exactly as if the days had been lived. That's deliberate -- a seek would be free rent forever -- but it does mean a multi-day wait can stack several rent toasts at once.
- **`rent_amount = 0` is the OFF switch**, not a bug -- a collector with zero rent silently does nothing, notice included.
- **No debt, ever.** A broke player is charged `min(rent, wallet)` and the rest is reported via `payment_missed` -- the wallet is never pushed negative. If you want a debt mechanic, accumulate the shortfall yourself off that signal.
- **Substitution is token-replace on all three lines**, so a literal `%` anywhere in a line is safe -- it never touches GDScript's `%` format operator. `{amount}` renders the whole `"20 zm"` money phrase, so don't append a unit yourself.

### The routine: `ScheduleBehavior` + `Schedule` + `ScheduleEntry`

To make an NPC live a daily routine instead of standing around, you drop a **`ScheduleBehavior`** under it and point it at a **`Schedule`** resource. The behaviour reads `WorldClock.phase()` each idle frame and walks the NPC to the marker for the current phase. It slots into the NPC's idle locomotion **above patrol/wander but below companion-follow** -- so a fight interrupts it, and the NPC resumes its routine afterward. It mirrors `PatrolBehavior` exactly (same drop-in pattern, same idle-handoff).

#### ScheduleBehavior (`res://scripts/components/schedule_behavior.gd`)

A **`ScheduleBehavior`** (`class_name ScheduleBehavior`, `@tool`, plain `Node`) -- drop it **UNDER an NPC**.
- **`enabled`** (bool, `true`) -- off = ignore the schedule and fall back to normal idle (patrol / wander / hold).
- **`schedule`** (`Schedule`) -- the daily routine resource. Null = inert (the NPC just idles normally).
- **`arrive_distance`** (float, `1.5`) -- how close (m) counts as "arrived"; within this the NPC holds at the spot instead of nudging it forever.

It's **inert when it has no schedule, or when the current phase has no entry / no marker placed** -- in any of those cases the NPC falls through to its normal idle. The `@tool` script config-warns in the editor if it isn't a child of an NPC, or if `schedule` is unassigned.

#### Schedule (`res://scripts/npc/schedule.gd`)

A **`Schedule`** (`class_name Schedule`, `extends Resource`) -- author it as a `.tres`.
- **`entries`** (`Array[ScheduleEntry]`) -- one row per phase you want to place the NPC for. A phase with no entry leaves the NPC to its normal idle during that phase.

#### ScheduleEntry (`res://scripts/npc/schedule_entry.gd`)

A **`ScheduleEntry`** (`class_name ScheduleEntry`, `@tool` `Resource`) is one line of the routine.
- **`phase`** (dropdown, `"Night"` / `"Day"`, default `Day`) -- which `WorldClock.Phase` this entry applies to (exposed as a dropdown so you never type the raw `0`/`1`).
- **`location_group`** (StringName, `&""`) -- the **group** holding the destination marker for this phase. Drop a `Marker3D` (or any `Node3D`) into that group -- e.g. `&"market"`, `&"home"` -- and the NPC heads to the **first** node found in it.

### Worked example -- a vendor who works the market by day, sleeps at home by night

> Goal: a townsperson stands at the market stall during the day and walks home at dusk, resuming after any interruption.

1. Place two `Marker3D`s in the level: one at the stall, one at the house. Add the stall marker to a group `&"market"`, the house marker to a group `&"home"` (Node dock -> Groups).
2. Author the routine: right-click `res://resources/schedules/` (or anywhere) -> **New Resource -> Schedule**, save as `vendor_routine.tres`. Size `entries` to **2**:
   - `[0]`: `phase` = **Day**, `location_group` = `&"market"`
   - `[1]`: `phase` = **Night**, `location_group` = `&"home"`
3. Under your NPC, add a **`ScheduleBehavior`** node and set `schedule` = `vendor_routine.tres`. Leave `enabled` on.
4. Play. By day the NPC paths to the stall and holds within `arrive_distance`; at dusk (`time_of_day` crosses `night_start`, default `0.75`) the phase flips and it walks home. Shoot near it and it breaks off to react, then resumes the routine. To watch a full cycle fast, drop `WorldClock.day_length_seconds` to e.g. `60`.

### Gotchas

- **The marker must exist IN THE WORLD, in the right group.** `ScheduleBehavior` looks up the live `location_group` and walks to the first `Node3D` in it. No node in that group (or a typo'd group name) = no destination for that phase, and the NPC silently falls back to its normal idle. It does not error.
- **`day_length_seconds = 0` freezes time.** The clock stops advancing entirely -- the phase never changes and `phase_changed` never fires. Use it deliberately to pin a level to one time; don't leave it at `0` by accident expecting a slow day.
- **Phase ints: Night = 0, Day = 1.** If you read `WorldClock.phase()` in a small script, that's the mapping (matching `WorldClock.Phase`). In the `ScheduleEntry` inspector you pick from the **Night/Day dropdown** instead, so you never touch the raw number.
- **A routine outranks patrol/wander but yields to combat and companion-follow.** A scheduled NPC won't also wander; a companion you've recruited follows you instead of running its routine. Don't stack `ScheduleBehavior` with `PatrolBehavior` expecting both -- the schedule wins while it has a valid destination.
- **The clock pauses with the game.** Time doesn't pass while paused (which today means: during a conversation) -- that's intentional, not a stuck clock. Menus and station screens no longer pause, so the clock **does** run while you shop or bank.

Relevant files: `res://managers/WorldClock.gd`, `res://scripts/effects/day_night_sky.gd`, `res://scripts/tools/day_night_shots.gd` (the screenshot probe), `res://scripts/components/schedule_behavior.gd`, `res://scripts/npc/schedule.gd`, `res://scripts/npc/schedule_entry.gd`.

---

## Stealth and detection

CYBER SUNDAY ships a full stealth layer -- a detection meter the player can read, enemies that see worse in the dark and hear worse through walls, noise lures, body discovery, and a bonus for striking the unaware. The script defaults keep the layer inactive (`false` flags and `1.0` multipliers), while the **shipped `NpcAiSettings.tres` turns the systemic flags ON** (`body_discovery`, `hearing_initiates`, `hearing_occlusion` all `true`), so out of the box the stealth consequences are live. To dial stealth *down* you flip those flags off in the resource; to dial it *up* you raise the inactive `SearchSettings` and `backstab_multiplier` knobs below. The pieces are real and already documented in their home chapters (perception in §5, the sneak/backstab multipliers in §10, `NoiseSource` in §11, the tuning resources in §12) -- what this chapter adds is the **map** and the **shipped-defaults + tuning recipe**.

### What the player sees: the detection readout

While the player is **crouched (sneaking)** — or standing but **noticed** by an enemy — a small readout near the top of the screen rises through four tiers as the nearest enemy's awareness climbs:

- **HIDDEN** -- no enemy has any suspicion of you.
- **DETECTED** -- an enemy's detection meter is filling (it senses *something*).
- **CAUTION** -- an enemy had you and lost you, and is now actively searching (its last sighting went cold).
- **DANGER** -- an enemy has fully locked on / gone ALERTED.

It is driven automatically from each enemy's `Perception` awareness (ALERTED -> DANGER, INVESTIGATING -> CAUTION, DETECTING -> DETECTED, otherwise HIDDEN) -- there is **nothing to wire per level**. The player can hide the graded heat **bar** via the **"Show Detection Meter"** row in Options — it does not affect the four-tier text readout (which shows whenever you're crouched **or** an enemy has noticed you — it hides only when you're standing *and* unseen), and the graded bar has no always-on mode (even enabled, the bar only appears while you're crouched and sneaking). The meter fills faster the closer and more centred you are in an enemy's view, and slower at the edge of its cone or in shadow (see falloff + light below).

**What the player hears: the MGS "!" sting.** The instant an NPC first notices something (Perception UNAWARE -> anything: sight, your footsteps/gunfire, a hit, a caught pickpocket) it plays the "!" (`assets/audio/sfx/Detected.wav`, via `NpcAudioCues`) and pops the "!" over its head. **When what it noticed is YOU** (or a companion in the `&"Player"` group), the sting is played **2D — in your ear, no distance falloff — so you hear it perfectly wherever the spotter is**, a roof sniper 200 m out as loud as a guard at your back. When it noticed something else — another NPC in an NPC-vs-NPC contact, a **thrown decoy**, a scripted `investigate()` point, another NPC's gunfire — the sting stays **positional at that NPC** (faint from afar: atmosphere, not a warning). The split reads what the NPC *actually noticed* (`Perception.noticed`; a `NoiseSource` names its `emitter`), not who it happens to be targeting — so lobbing a decoy near a guard that already has you in range does NOT sound like being seen. Volumes: `npc_audio.alert_volume_db` (2D, on you) / `alert_volume_db_vs_npc` (positional). Throttle: `npc_bark.alert_cooldown_ms` (3 s) — a swarm spotting you at once = one sting, and an ambient contact can never mask your detection cue (it yields to a recent player sting; never the reverse).

### The flashlight — the light you carry, and the trade it forces

Every player has a **flashlight** from the first frame. It is **not** an unlockable: there is no chip to buy, no `Ability` node, and nothing to author — it is the `FlashLight` `SpotLight3D` on the camera rig (`rpg/scenes/player/camera_rig.tscn`, script `rpg/scenes/player/flash_light.gd`), and it toggles with the **`Light` action (L**, or left-stick click on a pad — rebindable in Options → Controls, where the row now reads "Flashlight"). It works holstered, unarmed, mid-reload and while carrying a prop: it is a torch, not a gun attachment. The only thing that switches it off for you is dying.

> ⭐**It makes you visible while it is on, and that is the point — it costs you TWO things.** (1) *You lose the darkness discount.* `PlayerLightLevel` auto-collects every `Light3D` and weights it by energy and distance, and this lamp sits *at* the player, so while lit the light meter saturates and enemies fill their detection meter at full speed. (2) *You become a beacon.* On its own (1) can only ever CANCEL a discount — `light_exposure` clamps at `1.0`, exactly what standing under a streetlamp reads — so a torch would still be free. So the node also joins the **`&"carried_light"`** group, which the sampler turns into `player.carried_light`, and enemy `Perception` reads that as a **wider sight range** (`carried_light_sight_mult`, `1.6` — spotted ~60% further out) plus a **faster-filling detection meter** (`carried_light_detect_mult`, `2.0` — they lock on twice as fast). Both dials live on `GameSettings.light_stealth` (**"Light & shadow"** below). ⭐**Crouching does not hide a lit torch:** the crouch range discount and the beacon penalty *multiply*, so a fully crouched player with the torch on is spotted at `25 × 0.5 × 1.6 = 20 m` instead of `12.5 m`. That is the whole decision the day/night cycle creates: see, or be seen. Switch the beam off and both costs vanish the same instant (the sampler skips *invisible* lights, and `visible` is already false whenever the toggle is off or you are dead). Set **`reveals_you = false`** on the node to opt out of both (it then joins `&"stealth_light_exempt"` instead and skips `&"carried_light"`) if you want a kinder game; to merely *soften* the cost, leave it on and turn the two `carried_light_*` dials down toward `1.0`.

⭐**The beam is the colour of your own body glow, and it tracks your HP.** The player emits a light (`PlayerEmittingLight` on `Player.tscn`) whose colour is driven by health — cyan at full, blending to red as you are hurt (`Player.health_light_color_for`, off the `damaged` signal). The torch **copies that live colour every frame**, so your beam reddens as you bleed out and you can read your own health off the wall in front of you. It copies the node rather than re-deriving the blend, so retinting the body glow retints the torch for free — there is one blend with one home. Switch it off with **`match_player_light = false`** and the beam keeps the colour authored on the node (which is the healthy cyan, so the two never disagree; `tests/test_flashlight.gd` pins that equality across the two scenes). **Purely cosmetic:** `PlayerLightLevel` weighs lights by energy, range and distance and never reads colour, so this cannot move detection.

⭐**It casts real-time shadows, and the reason it does is WHERE it is, not a checkbox.** `shadow_enabled` has always been on — but the beam used to originate at exactly the camera's position, and a light sitting on the eye puts every shadow it casts perfectly *behind* the thing casting it. Each caster hid its own shadow, so the torch read as flat, shadowless fill and the world looked lit-through. The rig's **`LightPosition`** marker is therefore authored **off the lens** — `(-0.22, -0.16, 0)` in camera-local metres, i.e. left of it (mirroring the gun's `+0.187` on the right, so the torch reads as your off hand) and a little below — and that separation is the entire reason props, NPCs and brush geometry now throw shadows down the beam. **Two rules if you move it:** never back to zero (shadows vanish again, silently, with every render setting still correct), and never further out than the player's **0.5 m capsule radius** (an origin outside the body can be pushed through a wall you are leaning on, and the beam would light the room on the far side). `tests/test_flashlight.gd` pins both bounds plus `shadow_enabled`; a `.tscn` holds no comments, so re-authoring this node in the Inspector is exactly how it would get lost. To *see* a change, run the harness — no unit test can look at a shadow:
>
> ```
> godot --path . res://scripts/tools/flashlight_qa_shots.tscn -- --shots-dir="C:/some/dir"
> ```
>
> It boots the real game at night, switches the torch on, and shoots the beam against a probe box, real brush geometry and a real NPC (`rpg/scripts/tools/flashlight_qa_shots.gd`). It must be a **windowed GPU run, never `--headless`**.

⭐**The `FlashLight` node's own transform is inert.** `top_level` plus the per-frame `global_position` write mean the light node's authored position never reaches the screen — the rig carried a `-0.187` X offset there for a long time that had *never* been visible. Move `LightPosition` (or repoint `light_position` at another marker) to relocate the beam; nudging the light node itself in the Inspector does nothing.

**Knobs** on the `FlashLight` node: `follow_rate` (`15.0` — how tightly the beam chases your aim; it is `top_level` and eases toward your look direction, so it *lags* slightly, which is what reads as hand-held rather than welded to your skull), `light_position` (the `Marker3D` the beam originates from — authored to the rig's `LightPosition`, held off the lens; see the shadow rule above), `start_on` (`false` — a fresh game begins with it off), `reveals_you` (`true`, above), `match_player_light` (`true`, above). The beam's *look* is the SpotLight3D's own properties: `light_energy` `3.5`, `spot_range` `22`, `spot_angle` `33°`, shadows **on** (`shadow_blur` `1.5`; visible only because of the origin offset above), and `layers = 5` — that is a bit-VALUE (`1 | 4`), i.e. Inspector **Layer 1** (the world) plus **Layer 3**, the view model (`ViewModelCamera.VIEW_MODEL_LAYER = 4`; tick Layer 4 by mistake and you get value 8, and the torch stops lighting the gun). Layer 3 is what lets your own torch light (and tint) the weapon in your hands. The click is the authored `FlashlightClick` child; delete or mute it for a silent torch.

> **Retired: the laser sight.** The `Light` key used to toggle a red laser-sight dot, gated behind a `LaserSight` chip. That ability, its chip item, and the laser beam mesh are **gone** — the key is the flashlight's now. `WeaponData.has_laser_sight` survives but is **NPC-only**: it gates the red beam an armed *enemy* sweeps at you (`npc.gd`), not anything the player carries. A save that still lists `laser_sight` loads fine — the rebuild finds no such ability and simply grants nothing.

### The three things that let an NPC notice you (recap of §5)

Every NPC's senses are tuned through the NPC's **Perception** inspector group (§5, *Step 2*) -- the sight/hearing fields mirror onto its `Perception` child, while `search_sweep_rate` is read by the search behaviour:

| Field | What it does |
|---|---|
| `sight_range` / `fov_degrees` | how far and how wide the vision cone reaches |
| `crouch_sight_mult` | how much a **crouched** player's effective visibility shrinks (your reward for sneaking). ⭐It is now one of TWO multipliers on the effective sight range: a player carrying a lit flashlight *widens* it by the global `carried_light_sight_mult`, and the two multiply -- so a crouched player with the torch on is spotted well before a crouched player without it |
| `eye_height` | where the line-of-sight ray starts (peeks over low cover) |
| `time_to_detect` / `forget_time` | how long a sighting takes to become a lock, and how long a lost target is hunted |
| `pursuit_grace_time` | how long it keeps chasing your live position after losing sight — commits over a ledge / around a corner before falling back to the last-known search |
| `hearing` | whether this NPC can hear noise at all (the gate for everything below) |
| `search_sweep_rate` | how fast it sweeps its gaze while hunting a lost target |

These are the **per-NPC** dials. The switches that turn the *systemic* behaviours on are global, and they ship off:

#### Waking just ONE NPC's stealth senses

The two stealth-sense behaviours have a **global** flag (in `NpcAiSettings.tres`, below) *and* a **per-NPC opt-in** on the NPC's **Perception** group (§5). The per-NPC flag is OR'd with the global one, so you can turn a single guard's ears/eyes on while the rest of the cast stays deaf:

- **`hearing_initiates_opt_in`** (bool, default `false`) -- this NPC alone hears noise as an awareness initiator (a thrown decoy, a gunshot through a wall pulls it into investigating), even with the global `hearing_initiates` off.
- **`body_discovery_opt_in`** (bool, default `false`) -- this NPC alone leaves a discoverable `Corpse` on death **and** scans for / investigates others' bodies, even with the global `body_discovery` off.

Use them for a single alert sentry in an otherwise-oblivious level, or to playtest one guard before flipping the whole cast on. (`hearing` is still the master gate -- an NPC with `hearing` off ignores noise regardless of either opt-in.)

Two more groups on `Perception` shape *how fast* the meter fills -- but read them as **code-level defaults, not designer knobs**. `npc.gd`'s `_build_perception()` constructs the `Perception` child at spawn and mirrors only `sight_range` / `fov_degrees` / `crouch_sight_mult` / `time_to_detect` / `forget_time` / `pursuit_grace_time` / `eye_height` / `hearing` onto it; nothing below is reachable from the inspector (no scene authors a `Perception` node, and `NpcData` has no field for any of them). They all default to behaviour-preserving values -- an unset curve contributes `1.0`:

| Field (group) | What it does |
|---|---|
| `range_falloff` (Sight Falloff) | Curve: visibility vs distance into sight range (0 = point-blank, 1 = at max range). Unset = no distance falloff. A set curve makes a far target fill the meter slower than a close one. |
| `peripheral_falloff` (Sight Falloff) | Curve: visibility vs angle off the cone centre (0 = dead ahead, 1 = cone edge). Unset = none. Lets the edge of the view cone notice you slower than dead-centre. |
| `light_falloff` (Sight Falloff) | Curve: visibility vs the player's `light_exposure`. Unset = falls back to the global `GameSettings.light_stealth` curve. It is the per-archetype *override* of the light/shadow pillar below -- implemented but unreachable; see **"Per-archetype override: Perception.light_falloff"**. |
| `min_visibility` (Sight Falloff, `0.15`) | Floor on the combined falloff so a genuine in-cone line-of-sight sighting still reaches ALERTED eventually -- just slowly at the far/peripheral/dark fringes. Only bites when a falloff curve is set. |
| `suspicion_wary_threshold` (Suspicion, `0.15`) | Detection-meter level at/above which the graded suspicion tier reads WARY (a faint "did I see something?"). |
| `suspicion_suspicious_threshold` (Suspicion, `0.6`) | Level at/above which it reads SUSPICIOUS (closing on a lock). At `1.0` the state is ALERTED, which always wins. |

**None of those six are authorable today.** Per-archetype falloff would need new mirror fields on the NPC + `NpcData` + `_build_perception()`; the two suspicion thresholds are deliberately global (they're player-feedback-consistency knobs, so every enemy reads WARY/SUSPICIOUS at the same meter level). The shipped way to tune how much darkness slows detection is the **global** `GameSettings.light_stealth` curve (`LightStealthSettings.tres`, below).

### The stealth-layer flags (shipped ON; flip OFF to dial it down)

The systemic flags live in the **Stealth** group of `res://resources/tuning/NpcAiSettings.tres` (the `GameSettings.npc_ai` page, §12). The *script* default is `false`, but the **shipped `.tres` sets all three to `true`**, so these behaviours are live out of the box -- clear the override (or set the flag back to `false`) on the ones you want quiet, then playtest:

| Flag (`npc_ai.*`) | Script default | Shipped `.tres` | What it does when ON |
|---|---|---|---|
| `body_discovery` | `false` | `true` | Every NPC death leaves a discoverable **Corpse** marker; an UNAWARE NPC that *sees* a body (LOS) investigates it and calls out -- so a quiet kill can blow your cover. |
| `hearing_initiates` | `false` | `true` | A noise can pull a **HOSTILE** NPC that hasn't spotted you into investigating it -- a guard that's already hostile to you reacts to a gunshot or a thrown decoy. Neutral and friendly NPCs ignore the shared noise channel entirely (`NPC._noise_initiates_on()` ANDs `is_hostile()`), so a decoy never distracts a townsperson. With it off, noise only matters once you're already a target. |
| `hearing_occlusion` | `false` | `true` | Walls **muffle** sound: a noise behind solid geometry is attenuated by `hearing_wall_attenuation` (0..1) -- a decoy through a doorway carries, one behind a wall doesn't. (`hearing_source_skip` keeps the noise's own body from counting as a wall.) |
| `distraction_scan_interval` | `0.3` | `0.3` | How often a no-target NPC rescans the noise/corpse channels (only matters while `hearing_initiates` or `body_discovery` is on). |

Then two more surfaces, in their own files:

- **The hunt** -- `res://resources/tuning/SearchSettings.tres` (`GameSettings.search`, §12) already overrides `max_search_radius = 10.0`, so a lost-target search sweeps a real 10 m breadcrumb ring out of the box (the uncertainty ring grows over time, intensity ramps from frantic to resigned). Only `sample_points` is still inert at `1` (a single sample point); raise it (and optionally widen `max_search_radius`) to broaden the sweep.
- **The reward** -- on each `WeaponData` (§10, *Damage* group), `sneak_attack_multiplier` (hitting an un-alerted enemy) already ships at `2.0` -- a built-in bonus -- while `backstab_multiplier` (hitting one from behind) ships inert at `1.0`, with `backstab_arc_degrees` at `90.0` (the rear quarter that counts as a backstab). Raise the multiplier to make striking from stealth pay off harder. That bonus rides your **normal attack** when the victim is off-guard / in the arc -- and there's now also a dedicated **silent-takedown verb** (in the stealth tools below) for an instant, quiet kill.

### The player's stealth tools

- **Crouch** (the Crouch keybind; tuned by `GameSettings.player_crouch`, §12) shortens your silhouette, **shrinks your noise radius toward zero** (fully crouched movement is near-silent), quietens your footstep audio, triggers the enemy `crouch_sight_mult` discount, **and douses your own body light** (`CrouchLightDouse` fades `PlayerEmittingLight` out while crouched -- the Thief-style lantern douse; see "Light & shadow" below). This is the core verb.
- **Lean** (the **Lean Left / Lean Right** keybinds, defaults **Q / E**, L1 / R1 on a pad; tuned by `GameSettings.player_lean`, §12) — the Deus Ex / Cruelty Squad corner-peek. HOLD it to slide the camera rig sideways (and roll it into the lean) so you can look and shoot round a corner. **It moves the head rig, NOT the collision capsule**, so your hitbox stays in cover while your view comes out; the aim origin rides the camera, so you really can fire from the peek. A sideways shape-cast against world geometry stops the camera short of the wall, so you can't poke the view through it, and leaning eases out while climbing, sliding, or airborne past `ground_grace` (designer knobs) — easing straight back when you land, so a weapon's recoil hop never costs you the peek. **Both keys are shared with the contextual verbs already on them** — E with Interact, Q with Takedown/Pet — and the lean is the FALLBACK: with a target under the crosshair the press runs the verb, with nothing there it peeks. Rebind either onto its own key in Options → Controls and it leans unconditionally. See the "E and Q are CONTEXTUAL keys" gotcha in §2.
- **Slow-walk is the DEFAULT movement tier** — there is no Walk keybind. Moving without holding the **Run** keybind puts you on the quiet walk tier (`GameSettings.player_movement.walk_speed_mult`, default `0.7`); hold Run to sprint out of it. Noise scales with ground speed, so simply *not sprinting* is the quiet, mobile sneak tier between running and crouching — without pinning you to a crouch. **Aiming down sights forces that walk tier** (Run is ignored while scoped; the ADS `scope_speed_mult` slow then stacks on top) — so ADS is a planted, committed stance and can't be used as a fast quiet-move, and it never drains sprint stamina or fires the sprint FOV widen. Designer opt-out: `GameSettings.weapon_general.allow_sprint_while_scoped`.
- **Silent takedown** (hold the **Takedown** keybind, default **Q**, rebindable in Options → Controls) — **an unlockable ability: the player must install the Takedown Chip** (`resources/items/chip_takedown.tres`) at a `ChipInstaller` first — or buy it on credit at New Game's implant-purchase step; a fresh game that did neither can't take anyone down. Once granted, while **crouched** and looking at an enemy that **hasn't locked onto you** (off-guard) from within its rear arc and in melee range, hold the key for an instant, **quiet kill**. It suppresses the death's witness bark (no "Murderer!" shout) but the body is still discoverable — *silent now, found later* (the delayed cost needs `body_discovery` on; see §5). A centre-screen "Take Down" prompt + a hold-progress bar appear when a target is eligible. Tuned by `GameSettings.takedown` (`SilentTakedownSettings.tres`) — three of these ship **overridden**, so judge them against the shipped value, not the script default: `enabled` (a global on/off, ships **on** — the *per-player* gate is now the chip, not this flag), `hold_time` (script default `0.55`, **ships `3.0`**; scaled down by the attacker's larceny/stealth), `min_hold_time` (`0.3` — the floor that stealth scaling can never undercut), `max_range` (script default `2.2`, **ships `1.5`**), `behind_arc_degrees` (`120`), `require_behind` (`true`), `require_crouch` (script default `false`, **ships `true`** — so a takedown attempted while STANDING silently does nothing, with no on-screen explanation). The kill still grants XP + bounty + kill-quest credit; it uses its **own key**, never overloading Interact (which pickpockets). Under the hood the verb's behaviour is the always-present `SilentTakedown` player component gated on `has_mechanic(&"silent_takedown")`, granted by the `SilentTakedownAbility` node (`scenes/components/abilities/SilentTakedown.tscn`) — the same gate idiom as air-dash.
- **Stay out of an enemy's front cone and out of the light** -- distance/angle falloff and the light/shadow modifier both slow how fast the detection meter fills (defaults are behaviour-preserving; the shipped designer surface is the global light settings -- the per-NPC falloff curves are code-level only, see above).

### Light & shadow: making darkness hide you

The "see worse in the dark" pillar is a tiny pipeline: a **writer** stamps a `light_exposure` (0 = pitch dark, 1 = fully lit) onto the player each frame, and every enemy `Perception` runs that exposure through a **light-falloff curve** that slows (or kills) how fast its detection meter fills. There are two writers (pick one) and one global curve. Unlike most of the stealth layer, **the curve ships ON** -- but the whole thing stays inert until a writer actually drops `light_exposure` below `1.0`, so an unlit scene detects exactly as before.

#### ShadowVolume (rpg/scripts/components/shadow_volume.gd)

**Paint a dark region.** `class_name ShadowVolume`, `@tool` `extends Area3D`. Drop one over an area you want to read as unlit, size its `CollisionShape3D` to cover it, and any qualifying body inside reads as dark to enemy Perception; on exit it's restored to fully lit. The cheap, designer-painted alternative to live light probing -- no Player edit, just paint shadows.

- **`trigger_group`** (StringName, `&"Player"`) -- only bodies in this group get dimmed. It forces its `collision_mask` to all layers and filters by group, so the player's physics layer never matters.
- **`shadow_exposure`** (float `0..1`, default `0.0`) -- the `light_exposure` written to a body inside. `0` = pitch dark (slowest detection); raise it for a half-shadow that only partly helps.

No prefab -- add the `Area3D`, attach the script (or set the node's type), give it a `CollisionShape3D`. API: `is_occupied()` (is a qualifying body inside right now).

#### PlayerLightLevel (rpg/scripts/player/player_light_level.gd)

**Sample real lights instead of painting.** `class_name PlayerLightLevel` `extends Node3D` (not `@tool`). Drop it as a **child of the player** and it estimates how lit the player is each tick by summing nearby lights at the player's position, then writes `light_exposure` -- no hand-painted volumes. By default (`auto_collect = true`) it auto-discovers **every** `Light3D` in the running scene each refresh — except lights in the `&"pickup_beacon"` group (loot-beacon glows are cosmetic and must never make you easier to detect), lights in the `&"stealth_light_exempt"` group (the same opt-out for any decorative lamp of yours -- tag it via the Node dock -> Groups), and *invisible* lights, all of which contribute `0` — so you never hand-tag lights — drop it under the player and any lamp you place (or spawn at runtime) counts automatically. A `DirectionalLight3D` (sun/moon) contributes its energy globally, an `OmniLight3D` / `SpotLight3D` contributes energy times a linear range-falloff. Note the player's **own** body light (`PlayerEmittingLight`, the HP glow) deliberately **does** count -- standing, it lights you up; crouching fades it out (`CrouchLightDouse`, see the gotchas below).

- **`host`** (Node3D) -- the body that gets `light_exposure` written. **Leave it null** and it auto-wires `host = get_parent()`, so dropped as a child of the player it needs zero inspector setup.
- **`ambient`** (float `0..1`, default `0.2`) -- base light everywhere before any lamp adds (a moonlit floor). Raise it for a brighter level where shadows are rarer.
- **`sample_interval`** (float, `0.1` s) -- seconds between samples (lights move slowly; this throttles the scan + LOS rays).
- **`require_los`** (bool, `true`) -- a lamp blocked by geometry between it and the player doesn't count (so a wall casts a real shadow). Turn off to skip the rays (cheaper, but lights bleed through walls).
- **`auto_collect`** (bool, `true`) -- discover every `Light3D` in the scene automatically (the default; no group tagging needed), minus the `&"pickup_beacon"` / `&"stealth_light_exempt"` and hidden ones above. Turn it **off** to read only the curated **`&"lights"`** group instead — the cheapest, most explicit lookup for a huge scene where you want to choose exactly which lights feed stealth (or exclude purely decorative lamps).
- **`recollect_interval`** (float, `2.0` s) -- how often the auto-collected light list is rescanned (`auto_collect` only). Lights rarely change, so this stays slow and is decoupled from `sample_interval`.
- **`directional_contributes`** (bool, `true`) -- whether a `DirectionalLight3D` (sun/moon) lights the host globally. Turn it **off** on a sun-lit level so a bright sun doesn't pin the meter to fully-lit everywhere (use live-sampling for night / interiors; mark dark nooks with a painted `ShadowVolume` on a day level).

⭐**It writes a SECOND field: `carried_light`** (`0..1`) -- how strongly the player is carrying their *own* lamp, scanned from the **`&"carried_light"`** group (the flashlight joins it) rather than from the auto-collected list, so it is found even with `auto_collect` off and costs no LOS ray. Takes the strongest lamp, not a sum -- two torches don't make you twice as findable. An *invisible* lamp contributes nothing, which is how the flashlight's off switch turns the penalty off with no bookkeeping, and a lamp faded toward energy `0` (`CrouchLightDouse`) stops revealing you just as it stops feeding the meter. Enemy `Perception` reads it as the beacon penalty (the `carried_light_*` dials under **"The global curve"** below). Deliberately independent of the exposure sum: a torch lit inside a painted `ShadowVolume` still gives you away, because the shadow is not what you are holding. Its two knobs:

- **`carried_light_radius`** (float, `3.0` m) -- how close a `&"carried_light"` lamp must be to the host to count as *on your person*. Beyond it the lamp is scenery again and only feeds the exposure meter, so you can drop a lit lantern, walk off, and stop being a beacon. Sized for a first-person torch riding at camera height (standing or crouched). `0` disables the whole carried-light penalty.
- **`carried_light_full_energy`** (float, `1.0`) -- the `light_energy` at which a carried lamp reveals you at full strength. A dimmer lamp scales down linearly, so a candle is a smaller liability than a torch.

Absent (or nothing to sample) -> the player stays fully lit (`1.0`), so this is purely additive. The sampling is a rough linear approximation, not a physical light probe -- tune `ambient` / `sample_interval` + playtest.

#### The global curve: GameSettings.light_stealth (LightStealthSettings.tres)

`res://resources/tuning/LightStealthSettings.tres` (read as `GameSettings.light_stealth`, §12) maps the player's `light_exposure` to a **visibility factor** every enemy `Perception` multiplies its detection-fill rate by. With this one curve, painting a `ShadowVolume` (or dropping a `PlayerLightLevel`) slows detection in the dark **game-wide** -- no per-NPC authoring.

- **`light_falloff`** (Curve, null) -- OPTIONAL hand-authored visibility-vs-exposure curve. Null = use the built-in ramp below.
- **`dark_visibility`** (float `0..1`, default `0.25`) -- the built-in ramp's value at pitch dark (exposure `0`) when `light_falloff` is null. `1.0` = light never matters; `0.25` = quarter-rate detection in pitch dark. The ramp runs from this at exposure `0` up to `1.0` at exposure `1`.

**Carried light (the flashlight penalty)** -- the second group on the same resource, and the *only* part of this pillar that is LIVE out of the box rather than inert. ⭐**Why it has to exist separately:** `light_exposure` saturates at `1.0`, and `Perception.visibility_factor` clamps its result at `1.0` too, so the curve above can only ever *slow* detection. Being lit can cancel the darkness discount but can never push you past baseline -- which means a flashlight you carry into a dark street would cost you nothing at all. These two dials are what charge for it. They scale by the player's **`carried_light`** (`0..1`), which `PlayerLightLevel` stamps from the **`&"carried_light"`** group (the flashlight joins it; tag a lit lantern prop's light the same way and it behaves identically).

- **`carried_light_sight_mult`** (float `1..4`, default `1.6`) -- multiplier on an enemy's **sight range** while you carry a fully-lit lamp. `1.6` = spotted ~60% further out. It multiplies with `crouch_sight_mult`, so crouching with the torch on gets you `25 × 0.5 × 1.6 = 20 m` instead of `12.5 m` -- sneaking and a lamp don't mix, by design. `1.0` = a torch costs nothing at range.
- **`carried_light_detect_mult`** (float `1..8`, default `2.0`) -- multiplier on how fast an enemy's **detection meter fills** while you carry a fully-lit lamp. `2.0` = they lock on twice as fast. Applied outside the visibility curve (which clamps at `1.0`). `1.0` = no fill penalty.

Both read exactly `1.0` for a target carrying nothing, so every NPC target and every torch-off player detects exactly as before. Turn the pair to `1.0`/`1.0` and the flashlight is free again -- a deliberate, visible choice (`tests/test_carried_light_stealth.gd` pins that the shipped tuning penalises).

#### Per-archetype override: Perception.light_falloff (implemented, NOT yet authorable)

The override branch is real in code -- `Perception._effective_light_falloff()` returns that NPC's own `light_falloff` when it's set and falls back to `GameSettings.light_stealth` when it's null -- but there is **no inspector path to set it**: `npc.gd`'s `_build_perception()` doesn't mirror a curve and no scene authors a `Perception` node (see **"The three things that let an NPC notice you"** above). So today every NPC uses the global ramp, and a thermal-sighted archetype that darkness never helps against needs a code change. Tune darkness **game-wide** with `LightStealthSettings.dark_visibility` / `light_falloff` instead.

**Gotchas**

- **Use ONE writer, not both.** A `ShadowVolume` and a `PlayerLightLevel` both write the same `light_exposure` field and will fight each other. Pick painted shadows OR live sampling per level -- and note `Player.tscn` already ships a `PlayerLightLevel` child (`host` = the Player), so live sampling is the writer in every level unless you disable it; a painted `ShadowVolume` gets overwritten on the sampler's next tick (`sample_interval`, `0.1` s).
- **The player's own HP glow is a stealth liability -- crouch douses it.** `Player.tscn` ships an always-on `OmniLight3D` child named `PlayerEmittingLight` at the player's own origin (the HP health glow), and the meter counts it like any other lamp -- STANDING, its distance-`0` contribution alone saturates the sample and pins `light_exposure` at `1.0`, so darkness never hides a standing player (walking around with your lamp lit is the point). CROUCHING fades it out: the **`CrouchLightDouse`** drop-in (also shipped on `Player.tscn`; `scripts/player/crouch_light_douse.gd`) tracks crouch depth (`crouch.crouch_t`, the same seam `crouch_sight_mult` reads) and tweens the light's energy toward **`crouched_energy`** (default `0` -- fully doused) over **`fade_time`** (default `0.35` s), fading back in on stand -- and since the meter weights each lamp by its *live* energy, a doused glow contributes ~nothing and `light_exposure` finally drops to what the ENVIRONMENT casts. Crouched beside a street lamp you are still lit; the douse hides only your own glow. Tune both knobs on the `CrouchLightDouse` node. For a *decorative* light that must never feed detection at all, tag it into the **`&"stealth_light_exempt"`** group (Node dock -> Groups), which the meter skips outright in both discovery modes (the `&"pickup_beacon"` rule) -- but never tag `PlayerEmittingLight` itself, or the standing-lit liability half of the mechanic disappears.
- **Don't overlap two `ShadowVolume`s on the same spot.** On exit each restores light to `1.0`, so the volume a body leaves LAST wins -- a body stepping out of an overlap can get re-lit while still in shadow. Paint discrete dark areas.
- **It needs an exposure writer to bite.** The global curve is on by default but reads `1.0` everywhere until a `ShadowVolume`/`PlayerLightLevel` lowers `light_exposure` -- with no writer in the scene, darkness does nothing.
- **`crouch_sight_mult` is a separate stealth axis.** Crouching shrinks an enemy's *sight range* (§5); the light curve scales the *detection fill rate*. They stack -- and crouching ALSO douses your own body light (previous gotcha), so a crouched player in shadow is spotted closer, detected slower, and no longer self-lit. ⭐**But crouching does NOT hide a lit flashlight:** the crouch discount and the `carried_light_sight_mult` penalty multiply (`25 × 0.5 × 1.6 = 20 m`), so the torch eats most of what sneaking bought you. Crouch to douse your *body* glow; the thing in your hand you have to actually switch off.
- **The carried-light penalty is the only LIVE half of this pillar.** Everything else here is inert until you author something (a curve, a `ShadowVolume`, a dark level); the two `carried_light_*` dials ship at `1.6`/`2.0` and bite the moment a player presses **L**. If you want the old free-flashlight behaviour back, set them both to `1.0` -- don't reach for `reveals_you = false`, which also drops the torch out of the exposure meter.
- **`NoiseSource`** (§11 catalogue) -- drop one as an ambient lure (a beeping machine) or to mark a decoy point; NPCs with `hearing` walk to investigate the loudest one. **Inert unless `hearing_initiates` is on.**
- **`NoisePulser`** -- the EVENT / one-shot sibling of `NoiseSource`: drop it under any `Node3D` and call `pulse()` (from a signal, a `TriggerVolume`, or code) to drop a *fading* `NoiseSource` burst on demand -- a breaking window, an alarm, a machine cycling. `radius` / `decay` / `lifetime` / `min_interval` (throttle) are Inspector knobs. NPCs auto-build one so their gunfire + death are audible; the player's *continuous* movement noise stays on the separate `NoiseEmitter`. **Inert unless `hearing_initiates` is on.**
- **Send an NPC to look somewhere ON CUE** -- every NPC exposes a public **`investigate(point: Vector3, alerted := false, sector_phase := NAN, source: Node = null)`** method that walks it to a world point and searches there (the NPC's no-target search behaviour). `alerted = true` shows the "!" reaction sting; `false` is a quiet "come look." `source` names WHO the look is about, if anyone — pass the player for a cutscene "the guard notices you" and the "!" is the 2D player-detection sting; leave it null for a bare point and the sting stays positional at the NPC (see *What the player hears* above). This is a *scripted command*, so it **works regardless of the global stealth-sense flags** -- the ambient `hearing_initiates`/`body_discovery` gates don't apply. Drive it from a cutscene `CALL_METHOD`, from code, or from the `InvestigatePoint` beacon below -- **not** straight from a `TriggerVolume`. A trigger calls its `action` with **zero arguments**, so `action = &"investigate"` errors at the call (`point` has no default) and the NPC never moves; worse, the editor's configuration check only asks `has_method(action)`, which passes, so nothing warns you at author time. Point the trigger at an `InvestigatePoint` instead (`target =` the marker, `action = &"trigger"`) -- that supplies the `Vector3`.
- **`InvestigatePoint`** (§11 catalogue) -- a drop-in "go look here" `Marker3D`. Call its `trigger()` (e.g. from a `TriggerVolume` `action = &"trigger"`, `target =` the marker) to send a specific NPC (`npc_path`) -- or every NPC in the `&"npc"` group within `radius` -- to `investigate()` this marker's position. Set `alerted` for the urgent "!" version. The scripted-command path again -- no global flag needed.

### Worked example: a guard you can sneak past -- and punish

1. Place an NPC (§5) with a combat profile; give its **Perception** a tight `fov_degrees` (say `90`) and a `crouch_sight_mult` around `0.4` so crouching roughly halves how far it can spot you.
2. Confirm `NpcAiSettings.tres` has `hearing_initiates`, `body_discovery`, and (for interior walls) `hearing_occlusion` on -- the shipped `.tres` already does, so this step is usually a no-op; you'd only re-enable one if a level cleared it.
3. In `SearchSettings.tres`, set `max_search_radius` to a few metres and `sample_points` to `4`+ so a guard that hears you actually sweeps the area instead of staring at one spot.
4. On the player's pistol `WeaponData`, raise `sneak_attack_multiplier` from its `2.0` baseline to `4.0` and `backstab_multiplier` from `1.0` to `8.0` with a `backstab_arc_degrees` of `120` -- now an unaware or behind-the-back hit is a one-shot.
5. Drop a `NoiseSource` (radius ~`8`) where you want to pull the guard. Give it a positive `decay` and/or `lifetime` for a **one-shot** burst that fades and then frees itself; leave **both** at `0` for a **persistent** ambient lure whose `radius` you drive externally. (`lifetime = 0` means *never self-frees*, not *one-shot* -- getting that backwards either leaks a node forever or makes your ambient lure vanish mid-level.)
6. Run it: crouch-walk past the cone, lob the lure to pull the guard off his route, then either strike from behind (the backstab bonus) or — once you've installed the **Takedown Chip** — **crouch behind him and hold Takedown (Q) for a silent kill** (the shipped `.tres` sets `require_crouch`, so standing does nothing). Leave the body in his patrol path and watch the next guard discover it.

### Gotchas

- **Shipped ON, inactive script defaults.** The `npc_ai` Stealth flags are `false` in the script, but the shipped `NpcAiSettings.tres` sets `body_discovery` / `hearing_initiates` / `hearing_occlusion` to `true`, so the systemic layer is live out of the box. The `SearchSettings` hunt is partly live too: the shipped `.tres` overrides `max_search_radius = 10.0` (a real 10 m sweep), and only `sample_points` is still inert at `1` (one sample point) — raise it (and optionally widen the radius) for a denser breadcrumb sweep. `backstab_multiplier` ships inactive at `1.0`; `sneak_attack_multiplier` ships at `2.0`. If a noise/body reaction "does nothing," check `hearing` is on (the master gate) before suspecting a flag.
- **`hearing` is the master gate.** An NPC with `hearing` off ignores every noise system (decoys, gunfire alerts, occlusion) no matter what the global flags say.
- **Companions are exempt from distraction.** An NPC following a leader won't wander off to investigate noise -- only free agents do.
- **Body discovery needs line of sight**, not just proximity, and each corpse carries a persistent `discovered` latch -- the first NPC to spot a body claims it (one investigation per corpse, not one per passing NPC). For authored story bodies, set `Corpse.save_id` so that discovery marker survives scene refactors.
- **Crouch hides you in plan, not in elevation** -- by design, crouching never makes you harder to see from above/below, only across the floor.
- **Occlusion costs rays.** `hearing_occlusion` casts a few rays per heard source; it only runs when hearing is active, but keep the ray cost in mind on a dense interior with many simultaneous noise sources. The real tuning knobs are `hearing_wall_attenuation` and `hearing_source_skip` on `NpcAiSettings.gd`.

Key files: `rpg/scripts/npc/perception.gd`, `rpg/scripts/player/noise_emitter.gd`, `rpg/scripts/player/crouch.gd`, `rpg/scripts/player/stealth_status.gd`, `rpg/scripts/components/noise_source.gd`, `rpg/scripts/components/noise_pulser.gd`, `rpg/scripts/npc/npc_senses.gd` (the no-target noise/radio/corpse scans), `rpg/scripts/npc/goap/actions/goap_action_search.gd`; tuning under `res://resources/tuning/` (`NpcAiSettings.tres`, `SearchSettings.tres`, `DistractionSettings.tres`, `PlayerCrouchSettings.tres`).

---

## Tuning NPC behaviour (GOAP profiles)

Every NPC's brain is a **GOAP planner** (Goal-Oriented Action Planning) -- there is no state-machine to edit. Out of the box it already does the sensible thing (chase, shoot, take cover, investigate, flee when hurt), so **most NPCs need nothing here -- leave `goap_profile` null**. When you want an archetype to behave *differently* -- a coward who bolts at the first shot, a berserker who never runs -- you author one small resource and the planner re-weights itself. No code, all dropdowns.

### How the brain decides

Each frame the planner picks the **highest-priority goal it can currently pursue**, then plans the **cheapest sequence of actions** that satisfies it. So behaviour is shaped by two numbers per item: a goal's *priority* and an action's *cost*.

The shipped goals, in default priority order (higher wins):

| Goal | Default priority | What the NPC is trying to do | Serving action(s) |
|---|---|---|---|
| `Survive` | `3.0` | get to safety when threatened/hurt | `Flee` |
| `Engage` | `2.0` | fight the current target | `FireArmed` / `FireUnarmed` |
| `Investigate` | `0.4` | walk to a last-known / noise / corpse point and sweep it (the stealth search, §19) | `Investigate` (the script is `goap_action_search.gd`) |
| `Detect` | `0.3` | close the gap from "senses something" to a confirmed lock | `Detect` |
| `Idle` | `0.1` | no target: hold position / wander the idle floor | `Hold` |

`Survive` *always* outranks `Engage` on priority -- but it's only **pursuable** while the NPC is actually fleeing (its `Flee` action needs `is_fleeing`, i.e. `threat_response == FLEE`), and the planner skips a goal it can't reach a plan for at any priority. So feasibility, not the number, is what decides whether an NPC runs; the levers below re-rank the goals it can already pursue.

### Authoring a `GoapProfile`

1. In the FileSystem dock, **right-click `res://resources/` → New Resource → `GoapProfile`** and save it next to your `NpcData` archetypes (e.g. `coward.tres`).
2. Drop it on the archetype's **`NpcData.goap_profile`** slot (it travels with the profile), or directly on a single NPC instance's **`goap_profile`** export (the **Profile** group — the "AI (GOAP)" label is the `NpcData` resource's). A value on the `NpcData` stamps onto the instance at spawn.

It has **four live levers**, all authored as dropdown rows so the goal/action name is always picked from a real list (no free-text to mistype):

- **`goal_priorities`** -- rows of `{ goal, priority }`. Each **replaces** that goal's default priority for this archetype. *This is the main lever*, but it only re-ranks goals the NPC can **already** pursue: it cannot *make* an NPC flee, because `Survive` is served only by `Flee` and that action's precondition is `is_fleeing` (see the note above). `Survive` also already ships at `3.0`, above `Engage`'s `2.0`, so raising it to e.g. `5.0` changes no ordering. What it *does* do at the `Survive` end: drop it to `0.0` — below the `Idle` `0.1` floor — and an NPC that has broken and run stops running and idles instead.
- **`action_cost_overrides`** -- rows of `{ action, cost }`. Each **replaces** that action's planner cost (clamped `>= 0`). Costs break ties between alternative plans to reach a goal -- raise an action's cost to push the planner toward another route, lower it to prefer that action. The shipped base costs to judge an override against: `Hold` `0.1`, `Detect` `0.1`, `Investigate` `0.2`, `Flee` `0.3`, `FireArmed` `0.5`, `FireUnarmed` `0.6`.
- **`hp_scales`** -- rows of `{ goal, priority }` where the `priority` field **is** the hp_scale: that goal gains `hp_scale × (1 - hp_frac)` on top of its base priority, so it climbs as the NPC is hurt. No row = `0.0` = no effect.
- **`temperament_scales`** -- the same row shape, where `priority` **is** the temperament_scale: the goal gains `temperament_scale × temperament`, weighting it by the NPC's sensed `temperament`. This is the real "a coward weights `Survive` up" lever. No row = `0.0` = no effect, so an unfilled profile leaves every goal at exactly its base priority.

> The fifth field, **`goals`** (an allow-list), is **now enforced**: leave it **empty** to pursue every goal (the default), or list a subset to restrict this archetype to only those goals. **`Idle` is always kept** regardless (it's the always-feasible floor -- dropping it would freeze the brain), so a too-narrow list just means "this NPC never fights", not "this NPC does nothing". Prefer `goal_priorities` for *shaping* behaviour; use `goals` only to genuinely *remove* a goal (e.g. a pure non-combatant that never Engages).

Because each row is picked from a self-populating dropdown, an editor-authored profile can't name a goal/action that doesn't exist. A profile built in *code* with an invalid name **is now caught**: `GoapProfile.validate()` runs both in the content validator and at NPC spawn (`npc.gd`), so an unknown name `push_warning`s at boot (and fails validation) instead of silently no-opping. Coverage is **all** the row lists — `goal_priorities`, `action_cost_overrides`, `hp_scales`, and `temperament_scales` — plus the `goals` allow-list, so a typo in an HP- or temperament-scaling row (which would otherwise fall to the `0.0` fallback and silently apply no scaling) is flagged too.

### Worked example: a coward and a berserker

- **Coward raider:** this one is **not** a `goal_priorities` job -- a priority can't start a flee. Set **`threat_response = Flee`** on the raider's `NpcData` (it runs from the off), or leave it on Fight and give it a high **`PanicOnDamage.panic_scale`** / `temperament` so it breaks mid-fight once hurt (`break_and_flee()` flips `threat_response` for the rest of that life). If you want the profile to help, add a `temperament_scales` row `{ Survive, 1.0 }` so the twitchy end of the cast weights fleeing up once it *is* fleeing.
- **Berserker:** new `GoapProfile`, add `goal_priorities` row `{ Survive, 0.0 }`. If it ever breaks, `Survive` now sits below the `Idle` `0.1` floor, so it stops running -- but note it **idles** rather than fighting on, because `FireArmed` / `FireUnarmed` are gated on `not is_fleeing()`. For a brute that genuinely never breaks, use `PanicOnDamage.enabled = false` and leave `threat_response` on Fight.

Zero code, and every other behaviour (aim, cover, investigate) stays at the tuned defaults.

### Simpler per-instance overrides (heal / panic / provoke)

Four tiny drop-in components cover the most common per-NPC behaviour tweaks **without** a `GoapProfile` -- the planner handles the big picture, these handle the reflexes. Each is **auto-added** with behaviour-preserving defaults (so existing NPCs are unchanged); to override, drop a configured instance under the NPC's Enemy root, or set its `enabled` to `false` to suppress that reaction entirely.

| Component | What it controls | Key knobs |
|---|---|---|
| **`ProvokeOnAttack`** | whether the player attacking this NPC turns it hostile | `enabled` -- set `false` for **a shopkeeper / quest-giver you can shoot at without it ever aggroing** (it absorbs hits and keeps its disposition). A FRIENDLY ally instead forgives until cumulative player damage passes the NPC's `friendly_aggro_threshold`. |
| **`SelfHealer`** | whether the NPC spends a carried medkit mid-fight | `enabled` (off = never heals); `heal_at_hp_frac` (heal at/below this HP fraction -- higher = heals sooner); `cooldown_ms` (min ms between heals). Spends the same health packs its corpse would drop. |
| **`PanicOnDamage`** | whether a hurt NPC breaks and flees | `enabled` (off = holds its ground); `panic_scale` `[0..1]` (flee chance = this × fraction of max HP lost; `0` = fearless). Auto-seeded from the NPC's `temperament`. |
| **`CrippleCallout`** | the callouts when a limb of this NPC is crippled | `enabled` (off = silent cripples); `toast_color` (colour of the "Crippled X's arm" toast shown to the player who did it); `self_bark_template` (the actor's own cry, `{part}` = the part word -- author `"My {part}!"` for the classic callout; a legacy `%s` still works). The template **ships EMPTY, so the cry is silent** until you fill it, per the project-wide unauthored-speech policy; even then a lethal hit stays quiet (a dying NPC doesn't call out). |

So a **shootable shopkeeper** is just `ProvokeOnAttack.enabled = false`; a **brute that never flees or heals** is `PanicOnDamage.enabled = false` + `SelfHealer.enabled = false`; a **twitchy coward** is a high `panic_scale`. Reach for these before a `GoapProfile` -- they're one checkbox each.

### Gotchas

- **The default (null profile) is already good.** Only author a profile when you want a *distinct* archetype; don't bolt one onto every NPC.
- **Priorities are absolute replacements, not deltas.** A `goal_priorities` row sets that goal's priority outright -- judge it relative to the defaults in the table above (`Survive` `3.0`, `Engage` `2.0`, `Investigate` `0.4`, `Detect` `0.3`, `Idle` `0.1`).
- **`goal_priorities` is the strong lever; `action_cost_overrides` is the fine one.** A goal with only one serving action barely cares about cost, so reach for goal priority first.
- **`goals` is an enforced allow-list** (see the note above): empty = pursue all; a subset restricts the NPC to those goals, but `Idle` always stays. Use it to make a genuine non-combatant (list only e.g. `Investigate`, `Idle`) — but a typo'd goal name now `push_warning`s at spawn.

Key files: `rpg/scripts/npc/goap/goap_profile.gd`, `goap_goal_priority.gd`, `goap_action_cost.gd`, `goap_library.gd` (the goal/action name lists the dropdowns read), `goap_executor.gd`, `goap_planner.gd`; the planner is built per-NPC in `rpg/scripts/npc/npc.gd` (`_build_goap_goals` / `_build_goap_actions`). Per-instance reaction components: `rpg/scripts/components/provoke_on_attack.gd`, `self_healer.gd`, `panic_on_damage.gd`, `cripple_callout.gd`.

---

## NPC barks (combat & reaction lines)

NPCs shout short context lines -- **barks** -- as the fight unfolds: a "Contact!" on spotting you, an "I'm hit!" when wounded, a "Murderer!" when they watch you kill an ally (wording illustrative -- see below). **Every bark pool ships UNAUTHORED (the Steam AI-text scrub), so out of the box NPCs are SILENT**: the built-in `*_LINES` consts in `npc.gd` are all empty, and an empty pool never shows a bubble (`_emit_bark` skips a blank line -- no empty speech balloon). The whole-cast fallback voice lives in **`res://resources/barks/default_barks.tres`** -- a real, **designer-editable** `BarkSet` whose categories also ship empty -- so filling that one file voices the *entire cast* without authoring a per-archetype set. To give an *archetype its own voice* -- a raider that snarls, a corp guard that barks procedure -- you author a separate `BarkSet` and hang it on the `NpcData`.

> This is the WHICH-lines layer. §8 (dialogue / `VoiceData`) is the HOW-they're-spoken layer (the text-to-speech voice). They're independent: barks are picked here, then read aloud by the NPC's `VoiceData`. And bark CADENCE -- how often, how far they carry, when the hurt cry fires -- is global tuning, not content: it lives in `GameSettings.npc_bark` (`NpcBarkSettings.tres`, §12), separate from these LINES.

### Authoring a `BarkSet`

1. In the FileSystem dock, **right-click `res://resources/` → New Resource → `BarkSet`**, save it (e.g. `raider_barks.tres`).
2. Fill **only** the categories you want to voice. **Every category defaults to an empty array, which means "fall back to this NPC's built-in pool"** -- so a `BarkSet` overrides just the pools it fills and inherits the rest. Since the built-in pools ship empty (the scrub), an inherited category is *silent* today -- the fallback only speaks once lines exist. Each pool is a list of strings; the NPC picks one at random when the moment fires.
3. Assign it to the archetype's **`NpcData.bark_set`** slot. (A null `bark_set` = the NPC uses every default line.)

The categories, grouped as they appear in the inspector (the Example column is **illustrative only** -- none of these lines ship, per the scrub):

| Group | Category | Fires when... | Example (illustrative) |
|---|---|---|---|
| **Combat** | `spot` | makes combat contact | "Contact!" |
| | `hurt` | wounded, low HP | "I'm hit!" |
| | `reload` | reloading | "Cover me!" |
| | `combat_end` | lost the target | "Where'd they go?" |
| | `lost_interest` | gave up an investigation | "Must've imagined it." |
| | `search` | actively hunting a lost target | "Where are you?" |
| | `flee` | broke and ran under fire | "Forget this!" |
| | `check_body` | spotted a dead body (§19) | "Hey -- a body!" |
| **Social** | `greet` | the player hovers/greets | "Hey there." |
| | `thanks` | the player assisted it | "Hey, thanks!" |
| **Death Reactions** | `death_ally` | a co-aligned peer was killed | "Murderer!" |
| | `death_approve` | a friendly approves an enemy's death | "Good riddance!" |
| | `death_question` | a bystander questions a death | "Was that necessary?" |
| **Player Aggression** | `warn_attack` | the player hit it but DIDN'T aggro it (see `ProvokeOnAttack`, §20) | "Cut that out!" |
| | `aggro` | the player's hit just flipped it hostile | "Alright, that does it!" |
| | `pardon` | the player HOLSTERED and its provoke was pardoned | "Alright... easy, now." |
| | `pardon_fleeing` | ...pardoned while it was still RUNNING | "You're — you're not shooting?" |
| **Music Reactions** | `music_awful` | hears an awful tune on a playing `Radio` (§15) | "Ugh, turn that off." |
| | `music_meh` | hears a mediocre tune | "Eh, it's alright." |
| | `music_good` | hears a good tune | "Oh, nice tune." |
| | `music_great` | hears a great tune | "This is my JAM!" |

The **Music Reactions** tiers fire when an idle NPC — **friendly OR hostile** — hears a playing `Radio` within its `audible_radius` (§15), keyed to the song's quality tier. They're gated by `GameSettings.npc_ai.music_reactions` (shipped ON; the tier thresholds live on that same `npc_ai` page) -- the NPC turns to face the radio and comments where it stands, it does not walk over. The **body turn** is a separate `music_turn_body` toggle (ships ON; flip it off on the `npc_ai` page to keep the reaction head-glance + comment only, no body yaw). Both yield to an active schedule/patrol route — a guard on patrol keeps walking and only head-tracks. Like every other category, an empty tier falls back to the NPC's built-in `MUSIC_*` pool -- which ships empty, so the comment is silent until authored (the turn/glance still happens) -- and a per-archetype `BarkSet` can override each tier (e.g. snarkier raider lines).

> **Intended stealth knock-on (a distraction mechanic).** An NPC's detection cone is its body's forward, so when a **stationed hostile guard** turns to face a radio it also swings its cone off its authored watch spot. This is deliberate: the player can switch a radio on behind a guard to open a "distracted by music" gap and slip past. It is *not* a player-awareness telegraph — the turn keys on the radio, never on the player. To keep guards watching their posts, set `music_turn_body` OFF on the `npc_ai` page (all reactions become head-glance + comment only).

### Muting a whole category (the three gates)

Emptying a pool *falls back* to the defaults -- and since those ship empty, today that happens to be silence. Don't rely on it: the moment `default_barks.tres` is authored, an emptied category speaks again. To *deliberately* mute a reaction -- and keep it muted after lines exist -- use the three boolean gates on `NpcData` (they mute regardless of which lines are in the pool):

- **`damage_barks`** (default `true`) -- the `hurt` cry. Off = a stoic/disciplined archetype that takes hits silently.
- **`death_barks`** (default `true`) -- the death-witness reactions (`death_ally` / `death_approve` / `death_question`). Off = an NPC that ignores killings around it.
- **`search_barks`** (default `true`) -- the `search` call-out. Off = a silent stalker that hunts without giving away its progress.

### Worked example: a snarling raider that searches in silence

1. New `BarkSet` `raider_barks.tres`: fill `spot` with `["Contact!", "Got eyes on!"]`, `aggro` with `["Big mistake.", "You're dead."]`, `flee` with `["Screw this!"]` -- wording illustrative only; the *shipped* `raider_barks.tres` has every category empty (the scrub), the structure is what the example demonstrates. Leave everything else empty -- those fall back to the defaults (currently silent).
2. On the raider's `NpcData`: assign `bark_set = raider_barks.tres`, and set `search_barks = false` so it hunts you quietly. (The shipped `res://resources/characters/raider.tres` already has `bark_set` wired — for that one you'd only flip the gate; the shipped `sniper.tres` ships with `search_barks = false` as its silent-stalker flavour.)
3. Done -- the raider now has its own contact/aggro/flee voice, inherits the rest, and stalks lost targets without a peep.

### Gotchas

- **Empty pool = fall back to defaults -- which ship EMPTY, so today it IS silence.** The mechanism is inheritance, not muting: once `default_barks.tres` carries lines, an emptied category speaks the defaults again. To *deliberately* silence a reaction, flip its `NpcData` gate; don't rely on an empty array.
- **The gates are on `NpcData`, the lines are on the `BarkSet`** -- two different resources. You can mute `hurt` (gate) while still customising `spot` (BarkSet).
- **`warn_attack` vs `aggro` pair with `ProvokeOnAttack` (§20):** a `ProvokeOnAttack.enabled = false` shopkeeper uses `warn_attack` and never reaches `aggro`; a neutral that flips on the first hit jumps straight to `aggro`.
- **`pardon` / `pardon_fleeing` close that arc** — they fire on the holster PARDON (`forgive_provoke`), the mirror of `aggro`. `pardon_fleeing` is the **alternative** read for a pardon that lands while the NPC is still running — a FIRST holster catching an un-betrayed runner (an authored `FLEE` civilian, or a fighter `PanicOnDamage` broke before it ever spent its latch): the same beat plays very differently mid-sprint. It's the one category with a THREE-level fallback — leave it empty and a fleeing pardon falls back to `pardon`, so filling only the standard line still covers both. Unlike the other categories the bark skips the cooldown *read* (like `aggro`, it's a payoff line and always lands) but keeps the earshot gate, since one holster pardons every provoked NPC in the level at once. Neither fires on `NPC.stand_down()` (the plain combat disengage) or the player-death settlement — only the pardon is the player talking someone down.

Key files: `rpg/scripts/npc/bark_set.gd`, `rpg/scripts/npc/npc_voice.gd` (resolves the pools + the gates), `rpg/scripts/npc/npc_data.gd` (the `bark_set` slot + the three gate flags).

---

## The player: HP, stats, and starting money

Most of this guide is about the world, but you'll also want to set the player's **starting build** -- how much punishment they take, their RPG stats, and their opening wallet. All three are plain inspector / resource edits; you make them on the **Player node in `res://scenes/game.tscn`** -- the single shared entry scene whose `GameRoot` loads your `LevelData` as the `Level` child (§2). There is one Player for the whole game and a level swap leaves it alive, so these values apply to **every** level; per-level HP/stat variation isn't authored here.

### Health

The player's health is `max_hp` on the Player (a `Character`), in the **Health & Stats** group. It ships at **`4.0`** -- the player is deliberately fragile, so a weapon's `1.0` damage is a quarter-bar. Raise it on the Player instance to make a tougher run. (`hp` seeds from `max_hp` at spawn and damage can never heal past it.)

**The player glows by HP.** `Player.tscn` ships an `OmniLight3D` child named exactly **`PlayerEmittingLight`** (cyan `Color(0.004, 1, 1)`, `omni_range` ~`2.13`) -- `player.gd` resolves it by that literal name, so a renamed child silently kills the effect. It keeps the scene-authored colour at full HP and blends toward **`player_health_light_damaged_color`** (a Player `@export` in the **Health Light** group, default `Color(1, 0.05, 0.02)`) as HP falls, hitting the damaged colour exactly at `0` HP. Tune the healthy colour / radius on the light node, the hurt colour on the Player export. Note it is a real `Light3D` sitting at the player's own position, so while you STAND it feeds the stealth light meter at full strength (`light_exposure` reads fully lit -- carrying a lit lamp is a deliberate stealth liability), and the `CrouchLightDouse` sibling on `Player.tscn` fades its *energy* out while you crouch so darkness stealth can bite (§19). The douse touches only energy; the HP colour blend here is independent and keeps working on a doused light. ⭐**Leave its `light_volumetric_fog_energy` at `0`** (Inspector: Light3D → Volumetric Fog → Energy) -- that zero is deliberate, not an oversight. Volumetric fog accumulates in a froxel grid that carries ~90% of the previous frame forward in *world* space and has no per-light motion vectors, so a lamp riding the player leaves its glow roughly a light-radius behind you: a second, dimmer cyan ball chasing you around, hard-edged because the froxel blur is off project-wide. Turn it up and the wisp comes back. So the glow reads as light *cast on nearby surfaces*, never as a halo in the air -- if you want the halo, the honest lever is the level Environment's **Volumetric Fog → Temporal Reprojection → Amount** (plus re-enabling `environment/volumetric_fog/use_filter`), because raising this property dims the ghost and the halo by exactly the same factor and leaves the trail just as long. Nothing else notices the zero: the stealth meter weighs energy and radius, the douse writes energy, the HP tint writes colour. ⭐**The flashlight wears this same colour** (`match_player_light`, §19) — it copies this node live, so retinting the healthy colour here retints the torch beam too, and the beam reddens with you as you take damage.

### The enemy health bar (top of the screen)

The mirror of the player's own bottom-left HP bar: a slim meter at the **top centre** that appears the instant you damage anything and fades out a few seconds after your last hit on that target. **There is nothing to wire per NPC or per level** — it is driven from `Character.take_damage`, so it covers every attributed damage path at once: bullets, melee, explosions, thrown props and thrown weapons, the pinball ram, and a silent takedown. (Ambient damage — hazard zones, status damage-over-time, fall damage — has no attacker to credit, so it deliberately never raises the bar.)

- **The fill colour is the target's allegiance**, not its health: red for hostile, green for friendly, blue for a recruited companion, near-white for a neutral (and the whole set swaps to the colorblind-safe palette when Options → Accessibility → "Colorblind-Safe Cues" is on, exactly like the NPC's outline rim and its hover name). Health is read from the bar's *length*, not its hue — so there is deliberately no separate low-HP red ramp to fight the allegiance tint.
- **The bright shard** that lags behind the fill for a beat is the damage your recent hits did — it holds still briefly, then slides down to meet the fill. Tune it with `enemy_hp_chip_delay` / `enemy_hp_chip_speed`.
- **It shows no name.** That is deliberate: an un-introduced hostile is an *anonymous threat* in this game (the hover readout hides their name too, §5), and the free band at the top of the canvas fits a bar but not a name line.
- **The player can turn it off** at Options → Accessibility → **"Enemy Health Bar"**.
- **Tuning** is the **Enemy health bar** group on `HudSettings.tres` (§12) — position, size, hold/fade timings, the chip shard, and the neutral fill.

> **Moving it is a two-widget decision, and you must measure the rim.** The centre-top column below the bar (the `[ HIDDEN ]` stealth badge at y 18, the detection heat bar at 40, then the claim / takedown / pet prompts down to y 123) is an outline-TIGHT ladder with no slack between rows. The bar ships at `enemy_hp_top` `4`, height `8`, rim `1` — and because the contrast rim is drawn *outside* the track, the real painted band is **y 3–13**, clearing the stealth badge's outline ink (which reaches up to y ~15) by 2 px. Use `EnemyHealthBar.ink_rect()` for the true footprint, never `enemy_hp_size` alone. Sideways, the width is limited by the top-right quest tracker — which *sways* on the HUD-weight carrier while this bar is pinned, so the gap has to absorb `hud_sway_max` plus the lens-breath scale; `144` leaves ~3 px even at a hard flick. Both invariants are pinned in `tests/test_enemy_health_bar.gd`. If you make the bar taller or push it down, move the stealth badge too (`_stealth_label.offset_top` in `scripts/player/player_hud.gd`) — don't just let them overlap, because both are on screen through every firefight.

Key files: `rpg/scripts/ui/enemy_health_bar.gd` (the widget), `rpg/scripts/player/player_hud.gd` (builds it), `rpg/scripts/player/character.gd` (the `on_damaged_target` notify that raises it).

### The stat sheet (`CharacterStats`)

Every `Character` -- player **and** NPC -- carries an optional RPG stat sheet in the same group: `stats`, a `CharacterStats` resource. **Baseline is `0` and neutral** (every derived multiplier is exactly 1.0), so a null or all-baseline sheet leaves balance untouched; a build matters only when a stat moves off `0`. To give the player a build: **right-click `res://resources/` → New Resource → `CharacterStats`**, set the six attributes, and assign it to the Player's `stats` slot.

| Attribute | Each point above `0`... | Consumed at |
|---|---|---|
| `strength` | +2.0 carry capacity **and** +1.5 max HP (both stamped at spawn), **and** +5% melee weapon damage (read live at the swing) | inventory weight cap, on top of `max_hp`, melee hits |
| `endurance` | +10 max stamina per point (the shared pool behind special movement **and** every trigger pull), **and** +10% out-of-combat health-regen rate per point (a multiplier read live, floored at 0 — endurance `-10` stops passive healing entirely) | `Player.stamina_max`, `Player._update_health_regen` |
| `gunplay` | +5% ranged weapon damage, +5% headshot punch, aim wander 8% steadier — **RANGED only** | weapon damage / sway (melee vs ranged = the `WeaponData.is_melee` flag) |
| `agility` | +5% move speed and jump | player locomotion |
| `streetwise` | buy 4% cheaper / sell 4% dearer; rep gains 8% bigger, losses 8% smaller; also gates dialogue checks | Merchant prices, §7 reputation, §8 skill checks |
| `larceny` | the thief's stat (merged the old **stealth** + **pickpocket**): enemy detection meter fills 5% slower (harder to spot) **and** silent-takedown wind-up 5% quicker; **plus** a lower chance an NPC catches you lifting an item, a bigger value you can lift at no extra risk, and flatter odds-loss on the *valuable* lifts above that band (a microchip goes from a hopeless 0% to a real gamble as you invest) | §19 Perception detection fill, silent takedown, §9 loot / pickpocket flow |

Negative values are legal and make the build *worse* on that axis. Dialogue skill checks (`DialogueChoice.required_stat`, §8) read these by name; the player sees the sheet on the **Stats** screen.

> **No soft cap — every effect is a straight line.** Each point gives the *same* marginal effect forever: better forever as you climb, worse forever as you go negative. The old interior plateaus are **gone** — the buy multiplier can fall to `0` (merchant prices still floor valued items at one coin quantum), selling no longer caps at 1.5× (it climbs without limit), and aim sway / move speed / detection / damage no longer floor at `0.2` — they floor at `0`, the physical limit where a negative value is meaningless (no damage, frozen in place, undetectable). There is **no diminishing-returns curve** anymore.

#### The strength / gunplay split

**`strength` scales MELEE, `gunplay` scales RANGED.** Which one a weapon uses is decided by the explicit **`WeaponData.is_melee`** flag — `true` = a melee weapon (scaled by strength, and it skips the gunplay headshot bonus), `false` (default) = ranged (scaled by gunplay). It is an authored flag, **not** inferred from `effective_range`: a hitscan melee weapon still needs a positive `effective_range` so its swing raycast actually reaches. A single build can't buff both damage axes with one stat.

- **`strength`** adds **+5% melee damage per point** (`MELEE_DAMAGE_PER_STRENGTH`), read live at the swing — on top of its stamped carry-capacity and max-HP bonuses.
- **`gunplay`** adds **+5% ranged weapon damage** per point (`weapon_damage_mult`) and **+5% headshot punch** on a crit/headshot (`headshot_damage_bonus`, on top of the weapon's own `headshot_multiplier`), plus the 8%-steadier aim wander.

Every multiplier is exactly `1.0` at baseline `0`, so an unsheeted or all-baseline character's damage is unchanged — the scaling only bites once you push the stat off `0`. It applies to any `Character` with the sheet, so a strength-heavy brawler NPC or a `gunplay`-heavy gunner NPC hits harder too. Per-point conversion constants live on `CharacterStats` (`MELEE_DAMAGE_PER_STRENGTH`, `WEAPON_DAMAGE_PER_GUNPLAY`, `HEADSHOT_PER_GUNPLAY`, `SWAY_PER_GUNPLAY`, `PRICE_PER_STREETWISE`, `REP_PER_STREETWISE`, `MOVE_PER_AGILITY`, `JUMP_PER_AGILITY`, `DETECTION_PER_LARCENY`, `TAKEDOWN_TIME_PER_LARCENY`, `HP_REGEN_PER_ENDURANCE`, and the stamped `CARRY_PER_STRENGTH` / `HP_PER_STRENGTH` / `STAMINA_PER_ENDURANCE`).

#### `larceny` (the pickpocket half) and the `PickpocketSettings` resource

The **`larceny`** stat drives the loot screen's pickpocket flow (§9): each point lowers the chance an NPC catches you lifting an item **and** raises how valuable a thing you can steal unnoticed (and, past a threshold, eventually the weapon in their hands). (`larceny` also governs stealth detection + the silent-takedown wind-up — the same stat covers sneaking and stealing since the 2026-07-16 merge.) The pickpocket tunables live on a global resource **`PickpocketSettings`** (`GameSettings.pickpocket`, `res://resources/tuning/PickpocketSettings.tres`, §12) — the resource keeps its `pickpocket` name because it tunes the pickpocket *mechanic*, not the stat:

- **`base_catch_chance`** (`0.35`) — the catch chance at `0` larceny.
- **`catch_chance_per_point`** (`0.03`) — how much each point lowers it (no floor other than `0`).
- **`base_value_allowance`** (`10.0`) — the item value you can lift unnoticed at `0`.
- **`value_allowance_per_point`** (`5.0`) — extra allowance per point.
- **`equipped_pickpocket_threshold`** (`8`) — the larceny level at which lifting the weapon *in an NPC's hands* becomes possible.
- **`caught_witness_radius`** (`12.0`) — when a pickpocket is **blown** (the catch roll fires), every other living **enemy** (a nearby NPC already hostile to the player) within this radius of the victim turns to **look** — it investigates the thief's spot with the "!" sting. The victim itself always reacts (turns hostile + spins to face you); this only controls how far the commotion spreads. `0` = only the victim reacts.

Three feel details ride on this flow:

- **Hovering an item shows the live odds.** While pickpocketing, the tooltip under the grids leads with the per-item chance — e.g. *"72% to lift unnoticed"* — computed from the exact steal-gate + catch roll the take rolls (so the number IS the risk). An item you can't lift at all reads the reason instead (*too valuable* / *the weapon in their hands*).
- **A caught mark is off-limits for good.** Once you're **caught** lifting from an NPC, it never lets you back into its pockets — even after it calms down or is forgiven (`NPC.pickpocket_allowed()` latches false; the *Pick Pocket* look-at prompt also disappears for it). This is runtime-only, so a fresh scene load gives it fresh pockets.
- **The room reacts.** Being caught provokes the victim (hostile + faction-rep drop, as before), and now the victim **spins to face you and engages**, while nearby enemies within `caught_witness_radius` turn to look.


### Starting money

The fresh-game wallet is `player_starting_money` on `EconomySettings.tres` (`GameSettings.economy`, §12); the shipped resource default is **`0.0`**. Raise it for a richer start. Precedence: a **`SwapWeapons` Loadout** that sets starting money overrides this, and a **loaded save** wins over both (these values seed only a *new* game).

### Gotchas

- **HP and stats are per-instance on the Player node**, not a global setting -- set them on the Player in the shared `res://scenes/game.tscn`, not in a tuning `.tres`. But that one Player serves **every** level, so changing them changes them everywhere.
- **Baseline-`0` stats change nothing.** An all-zero (or null) `CharacterStats` is identical to no sheet; only non-zero attributes shift balance. So you can hand the player a sheet and tune one stat without touching the rest.
- **`strength` stacks on `max_hp`.** Final spawn HP is `max_hp` + the strength bonus (`+1.5`/pt) -- account for both if you want an exact number (a deeply negative `strength` is floored so spawn HP never drops below 1). Strength also stamps carry capacity and adds live melee damage.
- **A loaded save overrides these.** `player_starting_money` and a fresh stat build seed a *new* run; a continued save restores the player's saved money and stats instead.

Key files: `rpg/scripts/player/character.gd` (`max_hp` + the `stats` slot), `rpg/scripts/player/character_stats.gd` (the six attributes + their formulas), `rpg/resources/tuning/EconomySettings.gd` (`player_starting_money`).

---

## Limb and locational damage

Every `Character` -- player **and** NPC -- tracks the condition of four body zones (head, torso, arms, legs) and **cripples** a limb when it absorbs enough located damage. It's all tuned per-instance from the **Limb & Locational Damage** `@export` group on the Character.

A **located** hit (one that carries a hit point -- gunfire, a thrown prop -- but *not* fall damage or an explosion) is sorted into a zone by where it lands in the body's local frame: at/above `head_local_y` = head, below `leg_local_y` = legs, the torso band with `|x|` past `arm_local_x` = arms, otherwise torso. Each zone has a condition pool of `limb_condition_frac` × the character's `max_hp`; drain it and that limb cripples (the **torso never cripples**).

| Zone | When crippled | Knob |
|---|---|---|
| Legs | moves slower (a Fallout-style limp) | `crippled_leg_speed_mult` (default `0.5`) |
| Arms | this character's shots spread wider | `crippled_arm_spread` (radians, default `0.06`) |
| Head | a stagger / concussion-feedback pulse | (overridable hook) |
| Torso | -- never cripples -- | -- |

Other knobs (all on the Character, so a tough-limbed brute vs. a fragile civilian is per-instance): `limb_condition_frac` (`0.6` -- how much located damage a limb absorbs before breaking), the zone boundaries `head_local_y` / `leg_local_y` / `arm_local_x`, and `cripple_sound` / `cripple_sound_volume_db` (the crack SFX -- **null by default, so a cripple is silent until you assign a stream**; only the shipped `Player.tscn` has one wired, and `NpcData` carries no equivalent, so assign one per enemy instance if you want enemy limbs to crack too).
### Mitigation: armour, damage reduction, and weakpoints

The same body that gets crippled also has two defensive axes and an offensive one, in the **Mitigation** `@export` group on every `Character`. **All three default to off (`0` / empty), so they change nothing until you set them** — armour and weakpoints are meant as enemy-authoring tools (the player leaves them at default so its head-one-shot immunity stays). They apply on top of HP, per-instance.

- **`armor_flat`** (float) — flat damage soaked off the TOP of every incoming hit (a second defence axis besides HP). Default `0.0` = no armour. Applied *before* `damage_reduction`.
- **`damage_reduction`** (float, `@export_range 0..0.95`) — fraction of the post-armour damage shrugged off (percentage damage reduction). Capped below `1.0` so a character is never fully invulnerable. Default `0.0` = no reduction.
- **`zone_damage_mult`** (Dictionary) — WEAKPOINT multipliers, keyed by `BodyPart` (`TORSO` / `HEAD` / `ARMS` / `LEGS`) → a damage multiplier for a hit in that zone. Empty = `1.0` everywhere (the inert default). A located hit in that zone is scaled by the multiplier; a fall/explosion (no hit point) is always `1.0`.

The order on an incoming hit is: difficulty scale (player only) → `armor_flat` subtracted → `×(1 - damage_reduction)`, floored at `0` (armour can't heal). The same zones from the table above (head/torso/arms/legs, classified in the body's LOCAL frame) drive `zone_damage_mult`.

**Worked example — an armoured brute with a soft core.** On an enemy NPC, set `armor_flat = 0.5` and `damage_reduction = 0.4` so body shots barely chip it, then add a weakpoint: in `zone_damage_mult`, key `Character.BodyPart.TORSO` to `3.0`. Now the brute tanks limb/arm fire but a torso hit punches through at triple — a designer-built "shoot the glowing core" enemy, no code.

> NPC archetypes mirror these. The same three fields live on **`NpcData`** (`armor_flat`, `damage_reduction`, `zone_damage_mult`) so a reusable "armoured raider" profile stamps them onto every spawn instead of your editing each instance (§10). The defaults match — `0.0` / `0.0` / empty = no mitigation.


**Clearing it:** a `Healer` (§13) mends limbs for a price -- that's what its "limb-only heal where HP is already full" covers -- and a `Bonfire` (§13) rest full-heals HP **and** limbs. HP and limb condition are separate pools: `heal()` restores HP, `heal_limbs()` un-cripples.

### Gotchas

- **Only located hits cripple.** Fall damage and explosions hurt HP but never cripple a limb (they carry no hit point to locate).
- **It applies to NPCs too.** The same group is on every NPC; a shot-out leg makes an enemy limp, and the player who crippled it gets a **"Crippled Kyle's leg"** toast. The NPC's own callout is **authored speech and ships SILENT** -- the toast and the cry both live on the `CrippleCallout` drop-in (`rpg/scripts/components/cripple_callout.gd`), which `NPC._build_components` auto-adds unconfigured. Drop a configured `CrippleCallout` under the NPC and set `self_bark_template` (e.g. `"My {part}!"`, where `{part}` becomes head/arm/leg; a legacy `%s` still works) to give it a voice; `toast_color` retints the toast, and `enabled = false` mutes both. A dying actor never cries out, and TORSO gets no callout at all.
- **Zones are local-frame**, so they track a leaning or rotated body -- a headshot stays a headshot mid-dodge.

Key files: `rpg/scripts/player/character.gd` (the Limb & Locational Damage group + `_apply_limb_damage` / `heal_limbs`); cleared by `rpg/scripts/components/healer.gd` and `bonfire.gd`.

---

## Saving, checkpoints and what persists

The game uses a **Dark-Souls-style autosave** to `user://gamestate.cfg`, so quitting and relaunching resumes where you left off; the start menu's **Continue** button appears whenever that file exists. Layered **over** it is an explicit player-driven **quicksave** (F5 / F9 -- see *Quicksave & manual slots* below), so there IS a manual save; the autosave is just the always-on baseline. Three named slots sit alongside it on the `GameState` API, reachable through the **Save / Load screen** (Options → *Save / Load* in-game; *Load Game* at the start menu once any manual save exists -- see *Quicksave & manual slots* below).

**What the autosave carries (the run profile):**

- the player's **money** (zorkmids),
- the character's **name** (chosen at character creation),
- the character's **appearance** -- head / body ids, arm / leg colours, and the painted shirt as PNG bytes (§6),
- the six **stats**,
- **unlocked mechanics** (abilities granted by `UpgradePickup`),
- **faction reputation** (the global standings, §7),
- the **backpack** -- every stack by `Item.id` plus its grid placement, and which stack is the drawn weapon,
- the **respawn point** (the last bonfire, or the initial spawn),
- the **active level identity** (the `LevelData.resource_path`, so Continue loads the level the saved transform belongs to),
- the **day/night clock**,
- active **StatusEffects** by resource path + remaining duration,
- discovered **Corpse** markers (the one-shot "an NPC already reacted to this body" state),
- the **revealed-name ledger** -- which NPCs have introduced themselves, so a `Stranger` stays named across a reload (§8; a New Game re-strangers everyone),
- the **story flags** set during the run (the `[flags]` world-state -- see **Story flags**; a New Game wipes them),
- the player's **XP and character level**,
- **unlocked perks** (the perk ledger) plus **unspent skill points**,
- **active / completed / failed quests** -- by `.tres` resource path, with per-objective progress on active ones,

> All of the above rides the **same autosave** -- quests by resource path (active with per-objective counts, completed, and failed), plus perks / skill points and XP / level. The only caveats: a quest built purely in memory (no saved `.tres`) is skipped, and a renamed or deleted quest `.tres` is dropped on load with a warning.

**When it autosaves:** at each milestone -- a wallet change (kill bounty / trade / pickup), **any backpack change** (both are coalesced to one write at end of frame, so a multi-step transaction saves complete), a level-up, an `UpgradePickup`, a **`PerkStation` purchase**, a **`RespecStation` respec**, a **`ChipInstaller` install**, a `Bonfire` rest, story/quest state changes, and the first NPC reaction to a `Corpse` marker. You can also write explicit quick/manual slots yourself (below).

**Death doesn't reload the world.** You're brought back to life at the respawn point; enemies stay exactly as they were. Only the autosave survives *quitting*. So **placing a `Bonfire` (§13) is how you place a checkpoint** -- a rest sets the respawn point and autosaves.
### What death MEANS (the death card + death mode)

That respawn-in-place behaviour is now a **knob**, not a hardwiring. Death's outcome and its on-screen card both live on the **`PlayerFeedbackSettings`** tuning group (`resources/tuning/PlayerFeedbackSettings.tres`, read as `GameSettings.player_feedback`, §12) -- the same inspector page as the hurt/spawn feel. Edit the `.tres`; no code.

**The death-meaning knob:**

- **`death_mode`** (enum `DeathMode`, default `CHECKPOINT_RESPAWN`) -- what dying does:
  - **`CHECKPOINT_RESPAWN`** -- come back in place at the last checkpoint, the world UNTOUCHED (the Dark-Souls default described above -- enemies stay as they were).
  - **`RELOAD_LAST_SAVE`** -- reload from the last autosave on disk: reverts any unsaved progress and resets the world.
  - **`RELOAD_CHECKPOINT_FRESH`** -- reload the current scene fresh (the world resets) but keep your in-memory profile.
  - **Your own remains follow this choice too.** Only `CHECKPOINT_RESPAWN` has to clean up after you: it revives you in an untouched world, so the gibs, blood splat, blood drops and stains (and a corpse, if the Player carries a `ragdoll_scene`) your death flung would still be lying at the spot you died — and another set would pile on at every retry. So the revive **destroys the gore your own death spawned**, gated on `GameSettings.effects.clear_player_gore_on_respawn` (`EffectsSettings.tres`, *Gore gibs* group, **ships ON**). Untick it to be brought back to life over your own body. **Only the player's gore is ever touched** — the enemies you killed on the way down keep every chunk and stain exactly where it fell — and the wipe happens while the screen is still fully black, so nothing is seen to blink out. Your dropped **death purse is not gore**: it stays put for you to walk back and reclaim. The `RELOAD_*` modes need no knob — the world is rebuilt.
  - **Your zorkmids follow this choice.** Only `CHECKPOINT_RESPAWN` settles the death purse (`economy.death_purse_loss_fraction` -- your killer pockets it, or it spills on the ground; see the *Death group* callout under Global tuning), because only an untouched world still holds a killer to loot or a bag to walk back to. Both `RELOAD_*` modes take **nothing at all** -- the reload restores your wallet anyway, and taking it would just burn it.

**The death card** -- the line that fades in over the black screen, holds, then fades out before the respawn/reload. When an attributed KILLER dealt the lethal blow, the line is built from their name (and weapon) at the moment of death; otherwise (a stray blast, self-inflicted) it falls back to `death_message`; a **FALL** uses its own `death_message_fall` line. All designer-editable and themeable:

- **`death_message_fall`** (String, default `"You hit the ground at [mph] miles per hour."`) -- the card when fall damage lands the killing blow (both a hard landing *and* the max-continuous-fall death). `[mph]` is replaced with the impact speed; a legacy `%d` / `%s` / `%f` is accepted instead, though all render the same whole number — `%f` does not float-format (substitution is token-replace, so a literal `%` elsewhere in the line never errors). Unlike the three lines below it, this one ships **authored**, not a `[PH]` placeholder. Set it to `""` for no card on a fall.
- **`death_message`** (String) -- the card's text for an UNATTRIBUTED death. Its shipped default is an **unauthored `[PH]`-prefixed placeholder** (the AI-text scrub), so author it -- as are the two killed-by lines below. **Set it to `""` to show no card at all for those.**
- **`death_message_killed_by`** (String) -- the line when the killer is known but not their weapon; ships as an unauthored `[PH]` placeholder. When you author it, keep the one `%s` (filled with the killer's name).
- **`death_message_killed_by_weapon`** (String) -- the line when both are known; ships as an unauthored `[PH]` placeholder. When you author it, keep both `%s` (first the killer's name, second their equipped weapon's inventory label).
- **`death_unknown_killer`** (String, default `"someone"`) -- the name used when the killer NPC has no authored `display_name` (so the line stays grammatical).
- **`death_stranger_killer`** (String, default `"a stranger"`) -- the name used when the killer is a real character the player was never introduced to (the "Stranger until introduced" mask). The card is a sentence, so it swaps the proper-noun `Stranger` placeholder for this indefinite, lowercase form: "You were killed by a stranger." Label contexts (hover, corpse, loot titles) keep `Stranger`.
- **`death_message_color`** (Color, default `Color(0.85, 0.1, 0.1)`) -- the card's text colour.
- **`death_message_size`** (int, default `28`) -- the card's font size (the small 396x216 death viewport -- keep it modest).

The surrounding death cinematic is tunable on the same group: **`death_sequence_time`** (`1.6` s -- a black vignette closes over the frame + the world audio ducks away + the camera keels over), **`death_time_scale`** (`0.3`, the slow-mo the world eases into), **`death_camera_roll`** (`1.45` rad, the keel-over), **`death_card_delay`** (`1.0` s -- the beat of PURE BLACK between the vignette fully covering and the card starting to fade in; without it the text arrives on the very frame the fade completes, which still reads as mid-fade -- `0` restores that old timing), **`death_card_fade_time`** (`0.6` s -- how long the card takes to fade in, and later to fade out), **`respawn_delay`** (`1.0` s -- how long the card holds fully visible; a MINIMUM once `death_card_holds_for_sting` is on, which stretches it to cover the death sting -- see below), **`death_card_gap`** (`0.35` s -- the beat on black after the text is gone, before the world fades up), **`spawn_fade_in_time`** (`2.5` s -- the fade-up-from-black + the world audio swelling back on (re)spawn), and **`respawn_hud_delay`** (`1.0` s -- the revive's QUIET WINDOW: how far into the fade-up the HUD comes back and the respawn receipts pop -- the wallet toast, the grudge-settlement reputation toasts, the holster tutorial reminder. At `0` all of that lands on the revive's first frame, a full HUD + toast burst over a still-black screen. The player has control from frame one either way; keep it under `spawn_fade_in_time`).

**Dying puts your weapon away.** `Player.die()` holsters the drawn weapon before the keel-over — the gun *swings* down out of frame (the normal FNV holster animation) instead of hanging dead-centre in view for the whole cinematic, alongside the first-person legs and bare fists, which are hidden in the same beat. It is **not** restored on the revive: every death mode now brings you back **holstered**, drawn again on demand with a fire-click or the hold-R toggle — the same stance `Player.start_holstered` gives a New Game or a Continue (previously only the `RELOAD_*` modes did this, because they re-run `_ready`; `CHECKPOINT_RESPAWN` used to revive you with the gun still out). The reticle follows it away, as it does for any holster. There is no knob: dying with the gun out is not a stance worth preserving. **This holster is not a stand-down** — see the de-escalation rules under Reputation: it grants no pardon and spends nobody's one-shot forgiveness.

#### The death sting (what you HEAR while dying)

The cinematic has its own soundtrack, owned by **`DeathMix`** (`rpg/scripts/player/death_mix.gd`, a code-built child of the Player). The world ducks out from under a clip that keeps playing at full level -- so the sting is alone over the black screen and the death card. **The cinematic is then SCORED to that clip:** the death card's hold is stretched so the sting's final chord attacks on the exact frame the screen begins fading back in.

With the shipped 7.97 s clip, one death runs:

```
0.00s  killed          world starts draining, vignette starts closing, camera keels over
0.20s  STING STARTS    from SILENCE, a slight offset off the killing-blow frame
0.70s  sting at level   swelled in over death_sting_fade_in (0.5s)
1.60s  full black      world silent under the sting; GameState.player_died fires; the black SETTLES
2.60s  card fades in   after death_card_delay (1.0s) of pure black
3.20s  card up         "You were killed by ..." holds  (hold = 2.37s, DERIVED - see below)
5.57s  card fades out
6.17s  black, no text
6.52s  respawn         FINAL CHORD ATTACKS as the screen starts fading back in; control is back NOW
7.52s  HUD returns     the quiet window ends (respawn_hud_delay): HUD + the respawn receipts pop
8.17s  sting ends      on its own, 1.65s into the new life. Nothing faded it.
9.02s  screen full     fade-up-from-black complete
```

**The sting is never faded or stopped** -- its own decay is the fade. A forced ramp to silence is perceptually over long before it mathematically finishes, so it amputates the clip's tail and reads as the audio being *cut*; the clip ringing out on its own, under the returning picture, does not.

The `2.37 s` hold is not authored anywhere -- `respawn_delay` is still `1.0`. The card's hold is the only slack in the timeline, so it is what the cinematic solves for:

```
death_sequence_time + death_card_delay + fade_in + HOLD + fade_out + death_card_gap  ==  start_delay + death_sting_sync_point
```

Land that sum on the sync point and the chord hits as `_fade_in_from_black()` starts. It only ever *lengthens* the hold -- a short clip, no clip, or a sync point of `0` plays the original snappy cinematic unchanged. **Retuning any of `death_sequence_time` / `death_card_delay` / `death_card_fade_time` / `death_card_gap` shifts this automatically**, since the hold re-solves; `tests/test_death_mix.gd` fails if the alignment ever drifts.

**Why it is built this way, and the rule that follows from it.** In Godot every bus chain terminates at Master (`ambient` / `sfx` / `music` / `voice` all send there; `radio` -> `music`, `station_music` -> `music`, `ambient_bed` -> `ambient`, `speaker` -> `sfx`). The cinematic therefore ducks the four **world buses** rather than Master, and the sting sits on a bus deliberately left off that list. **The consequence for level authoring: an `AudioStreamPlayer` with no `bus` set in the Inspector lands on Master, which the cinematic does NOT duck -- so it keeps blaring at full volume under the death card while everything else has drained away.** Always set a bus (`tests/test_audio_bus_hygiene.gd` fails the suite if you forget).

Knobs, all on the same `PlayerFeedbackSettings.tres` page:

- **`death_sting`** (AudioStream, default the shipped clip) -- the clip itself. **Clear it and the feature is entirely inert**: the world still ducks, nothing plays, and the cinematic snaps back to its original short timing. That is the one-field rollback. The shipped default is a placeholder track; swap it before any public build.
- **`death_sting_volume_db`** (default `0`) -- trim for the clip.
- **`death_sting_fade_in`** (`0.5` s) -- how long the sting **swells up from silence** once it starts. `0` is full volume on the first sample, which reads as a jolt: the world is ducking *away* underneath it, so a hard entry snatches the mix rather than being handed it. The swell is a linear-**amplitude** ramp, not a dB ramp -- a dB ramp from silence sits inaudible for most of its length and then rushes in. Keep it short enough that the clip's own opening still lands; it shapes the entry, not the track.
- **`death_sting_start_delay`** (`0.2` s) -- a *slight* offset so the sting does **not** land on the same frame as the killing blow (which reads as part of the gunshot rather than a reaction to it). It still opens under the keel-over, with the world draining away beneath it. `0` fires it on the blow; push it past `death_sequence_time` and it starts on a black screen instead.
- **`death_card_holds_for_sting`** (default **on**) -- scores the cinematic to the clip: holds the death card up so the respawn lands on `death_sting_sync_point`. `respawn_delay` becomes a **minimum**, and the extra hold is **re-solved every death** from the clip and the surrounding beat lengths, so retuning any other cinematic timing shifts it automatically. Turn it off to run the short cinematic on `respawn_delay` alone.
- **`death_sting_bus`** (default `&"sting"`) -- **must not** appear in `death_cinematic_buses`, or the cinematic ducks its own soundtrack. `DeathMix` pushes a warning at boot and `tests/test_death_mix.gd` fails if you break it. The `sting` bus sends straight to Master and carries no effects, unlike `sfx` (-6.6 dB into a distortion) and `radio` (a lo-fi chain).
- **`death_sting_slider_bus`** (default `&"music"`) -- `sting` has no Options slider of its own, so `DeathMix` folds this bus's slider into the sting player's own level (at 0% the sting is skipped entirely). Set it to `""` to make the sting a full-mix event only the Master slider can quiet.
- **`death_sting_sync_point`** (`6.32` s) -- the moment **inside the clip** that should land exactly as the screen begins fading back in. For the shipped sting that is its final synth chord: the last real attack, after which the track is pure decay to silence at ~7.95 s. This is what `death_card_holds_for_sting` solves the card's hold against. **The one number here that does not re-derive itself** -- nothing can detect a chord for you, so re-measure it if you swap `death_sting`, or set it to `0` to stop aligning to anything. It is clamped to the clip's length, so an over-long value can't strand you on a black screen listening to nothing.
- **`death_sting_release`** (`0` = **off**, the default) -- an *optional* forced fade-out at the respawn. Leave it at `0` and the clip rings out naturally, which is what stops the audio sounding cut. Set a value only for a clip that genuinely outstays its welcome, and keep it at least as long as the tail still to play (clip length minus `death_sting_sync_point`, ~1.65 s here) or it will chop the very decay it was meant to smooth. The `RELOAD_*` death modes always cut the sting dead regardless (a fresh scene, nothing to ring into).
- **`death_cinematic_buses`** (default `[ambient, sfx, music, voice]`) -- what counts as "the world". Those four cover 100% of authored audio, because ducking a parent bus takes its children with it. Setting this to `[Master]` restores the old global fade exactly, silencing the sting along with everything else.
- **`death_world_residue`** (`0.0`) -- how much of the world survives underneath the sting. `0` is the pre-existing total drain to silence; try `0.05`-`0.10` if the dead vacuum reads as a bug rather than a beat.

> **`CHECKPOINT_RESPAWN` is the default for a reason.** The other two modes throw away progress made since the relevant save/checkpoint -- use them for a more punishing game, but pair `RELOAD_LAST_SAVE` with frequent `Bonfire`s (each rest autosaves) or death will rewind a lot.


**Fresh game vs. loaded save.** A loaded save **restores** the profile above and ignores your authored starting values. A **New Game** re-seeds them from the world: the `player_starting_money` knob (§22), the starting `Loadout` (§10), and the **character-creation** screen's chosen name + stat build + implants bought on credit (below) — which **always** replaces the player's authored `CharacterStats` sheet (§22): creation stamps all six stats, zeros included, so any run started through the menu ignores the sheet you assigned on the Player node (an all-zero build is baseline-neutral, so it's a *non-zero* authored sheet you actually lose). Only a dev boot straight into `game.tscn`, with no creation screen and an empty `GameState.stat_values`, keeps the authored sheet. In short -- *authored starting values seed a new run; character creation and, on Continue, the autosave override them.*

**Character creation (New Game).** Clicking **New Game** opens a creation screen (`scripts/ui/character_creation.gd`) BEFORE the world loads. The player types a **name** and allocates the six `CharacterStats` as a **zero-sum tradeoff**: every stat starts at `0`, and raising one is paid for by lowering another (the net never goes positive; you MAY underspend into a deliberately weak build; each stat is clamped to **−5…+10**). A **negative** stat is a genuine weakness — `CharacterStats` already inverts every derived effect below baseline (less carry / HP / damage, more aim sway, slower, bigger reputation losses), safely floored so a deep negative can't break the character. On **Begin**, the flow moves to the **implant-purchase step** (below) — the profile isn't touched yet. **Back** returns to the menu, no profile change. The name is shown on the in-game **Stats** screen. This is player-facing (no per-instance authoring); tune wording/effect floors on `CharacterStats` (§22) if you want a different feel.

**Starting implants (bought on credit) (New Game, step two).** Creation's **Begin** raises a second screen (`scripts/ui/implant_choice.gd` + `scenes/ui/implant_choice.tscn`, the same StartMenu-owned overlay idiom) where the player checks microchip abilities **ON CREDIT** — but **the Ledger rates the build first** (see *The Underwriting Sheet* below). The verdict + filed-reason lines announce the rating, the tally tracks the credit left, and any unchecked chip row whose price no longer fits **greys out** — the cart can never bill past the limit (+ `player_starting_money`), while a checked row always stays live to un-check. Each checked chip is billed at its authored `Item.value` (that field IS the creation price knob), a pinned tally shows the running bill + the projected starting balance, and the wallet is **allowed to go negative**: a loaded build starts the run in debt (every paid service — merchant, healer, installer, level-up, wagered chess — simply refuses until the wallet climbs back past its cost; the HUD's signed readout is the debt display — it and every menu wallet label tint red while negative (`HudSettings.money_debt_color` / `MenuStyle.wallet_color`) — and the backpack shows no coin tile while below zero). An **empty cart** is the default and keeps the debt-free zero-ability start; every other ability still goes through the paid `ChipInstaller` economy. The roster is **disk-driven**: one row per distinct installable ability from the `ItemDb` scan of `res://resources/items/` (chips filtered by `Item.is_upgrade_chip()` + `AbilityRegistry.can_build()`, deduped by ability id) — drop a new chip `.tres` in that folder and it appears here with no code. **Back** returns to the creation screen with the typed name/stats/painted shirt intact (the overlay is kept alive underneath). Only on THIS screen's **Begin** are the chosen name (`GameState.player_name`), stat build (`GameState.stat_values`) and implants (`GameState.unlocks`) stamped onto the freshly-reset profile, and the bill debited straight from `GameState.money` — the ONE home of the (negative-capable) balance, which the spawning Player reads via its `profile_active` wallet branch on **every** boot of a created run that isn't a disk load (the fresh boot, a menu-and-back Continue, a no-save death reload), so the goods and the bill can never separate; all ride the autosave from there.

**The Underwriting Sheet — how a build earns its credit limit.** The bank is not grading taste; it is pricing a loan against someone it expects to die. `EconomySettings.credit_rating_for(stat_values, eco, stat_floor, stat_ceiling)` is a pure static (the `long_range_bonus_for` mold — off-tree testable, no nodes) returning `{score, band, reason, capacity, viability, trade, exposure}`. It reads the build on four lines, each normalised to 0..1:

| line | what it asks | how it's computed |
|---|---|---|
| **CAPACITY** | can this body generate zorkmids? | `income_weight × points ABOVE zero` |
| **VIABILITY** | will it live long enough to repay? | `survival_weight × points ABOVE zero` |
| **TRADE** | is there a marketable specialty, or a hobbyist? | `peak invested stat ÷ credit_depth_points` |
| **EXPOSURE** | what has been pledged, and what's it worth? | `dump_severity × depth^credit_dump_exponent`, capped at `dump_saturation` |

`score = score_min + span × clamp(credit_baseline_fraction + w_cap·CAP + w_via·VIA + w_trade·TRADE − w_exp·EXPOSURE)`.

⭐**The property that makes it work: positives feed ONLY the three additive lines and negatives ONLY the subtractive one, so raising any stat can never lower a score and lowering any can never raise it — for *any* table you author.** That is the fix for the model this replaced: because the creation budget is **zero-sum** (every invested point is funded by a dumped one), a per-dump penalty was algebraically a flat tax on *having a character* — the all-zero non-build rated the ceiling and took the full cap, while a committed build was fined. Investing now always pays, and the maximum sits at the budget corner where it belongs.

**The content is the table, not the code.** `credit_underwriting` on `EconomySettings.tres` holds one **`StatUnderwriting`** row per stat (`scripts/player/stat_underwriting.gd`): `stat` (dropdown), `income_weight`, `survival_weight`, `dump_severity`, `dump_saturation`. Re-price the whole bank by dragging 24 numbers — no code. Shipped table and what each number is arguing:

| stat | income | survival | severity | saturation | reasoning |
|---|---:|---:|---:|---:|---|
| `strength` | 0.55 | **1.00** | **2.00** | **2** | base `max_hp` is 4.0, so +1.5/pt is the biggest per-point effect in the game; dumping it crosses a categorical line (1 HP dies to one round). Saturates at 2 — `max_hp` is already floored there, so −3…−5 take nothing further. |
| `endurance` | 0.30 | 0.45 | 0.15 | 5 | TWO effects, both rate-of-RECOVERY rather than rate-of-output. (a) Stamina pool size: sustained throughput — sprint drain, and the per-shot `stamina_shot_cost` — is identical at every value, so it buys *burst length*, for firefights as well as for movement. (b) Since 2026-08-18, +10%/pt on the out-of-combat health-regen rate (`hp_regen_mult`, consumed at `Player._update_health_regen`). Weighted a little above strict honesty because its sinks are the movement chips this screen sells. ⭐`dump_severity` 0.15 was priced when stamina was the ONLY effect and has NOT been re-derived since regen landed — a −5 build now heals at half rate and −10 stops regenerating at all, which is a longer pledge than 0.15 reads. Re-check it before treating this row as calibrated. |
| `gunplay` | **1.00** | 0.55 | 0.40 | 5 | the income engine: bounties key on headshots and gunplay scales headshots hardest. Sway is skill-substitutable (crouch/ADS/settle), so dumps are cheap. |
| `agility` | 0.45 | 0.75 | 0.65 | 5 | jump height goes as v², so a dump is a real traversal lockout — the second-costliest pledge. |
| `streetwise` | **1.00** | 0.20 | 0.60 | 5 | 4%/pt both ways on every trade. The run starts in debt, so this is literally the debt-servicing stat. |
| `larceny` | 0.85 | 0.60 | 0.35 | **3** | feeds the detection multipliers; pickpocket allowance floors at −2 but detection/takedown keep degrading, hence 3. |

⭐**`dump_saturation` couples every row.** The EXPOSURE normaliser is `Σ(dump_severity × dump_saturation^exponent)` over the whole table, so editing ONE stat's saturation rescales EVERY build's exposure — it effectively retunes `credit_weight_exposure`. A test pins that total for exactly this reason. Also note saturation makes dumping past the cap **free**, which is honest (the derived effect has already floored) but is a real optimiser edge.

**What the player sees.** Three stacked lines above the roster: the standing explainer, the **verdict** (band + score + limit) and the single **filed reason** — the adverse-action-notice parody, naming whichever line falls furthest under its `credit_reason_*` floor. The bank never says "bad build"; it says the *loan* is bad, for reasons the player can read off their own stat sheet. Bands and reasons cross the boundary as `StringName` **keys** (`EconomySettings.BAND_*` / `REASON_*`), and `PlayerText.implant_choice_verdict` / `implant_choice_reason` select a whole authored template per key — re-wording a band can never change behaviour.

Shipped ratings, for calibration: all-zero **432 → 200 zm** (one cheap chip: nobody is locked out), a fully committed two-stat specialist **842 → 2050 zm**, all-six-dumped **300 → 0 zm** (declined). The advertised 850/2100 is deliberately just out of reach — a bank that hands out its own maximum isn't satire. Raise `credit_baseline_fraction` if you'd rather it be attainable. Five of the six single-stat "fantasies" land within 30 points of each other, so playing the character you *want* costs at most one cheap chip — this is a loan officer, not a gear score.

### Gotchas

- **An item with no `Item.id` can't be saved** -- it's skipped with a warning. Register every persistent item under `res://resources/items/` so it round-trips.
- **This is not an exact world snapshot, but a named-object ledger now rides on top.** A `Door`'s open/locked state and a consumed `CanPickUp` / `MoneyPickUp` / `UpgradePickup` / destroyed `CanDestroy` prop's "gone" state persist per level (`GameState.world_objects`), so a collected money/upgrade pickup no longer respawns on Continue. Set a `save_id` on hand-placed doors/props/pickups you want to survive **layout edits** — otherwise a level/path/position fallback is used (fine for objects that never move, fragile if you refactor the scene). A code-spawned pickup opts OUT of the ledger — `MoneyPickUp`/`UpgradePickup` via `persist_collected = false`, a loot-dropped `CanPickUp` via `build_model_from_item`. Looted/refilled containers and spawner-produced (encounter / pooled) entities still reset. **Dead AUTHORED NPCs no longer do:** within a session a killed hand-placed NPC stays dead through a `LevelDoor` A→B→A return, and a quicksave/quickload restores the whole cross-level kill set (`npc.gd` → `GameState.record_npc_death` → `GameState.suppress_dead_authored`, which `GameRoot.load_level` runs on **every** level load — no save involved). Deaths only reach DISK in a manual quicksave/slot save (folded into its `[world_snapshot]`), so a **Continue** from the lean autosave still brings everyone back. Hand-placed story NPCs take a **`save_id`** (an `@export` on the NPC root) like doors and pickups so their dead state survives a layout edit; blank falls back to a level|node-path key — deliberately position-free, because an NPC moves. `Corpse.discovered` is the older lightweight exception with the same `save_id` guidance.
- **The autosave is a single in-place slot** -- overwritten at each milestone. But an explicit **quicksave** (F5 / F9) layers on top (see *Quicksave & manual slots* below), so you DO have a manual bookmark. Three named slots (`save_to_slot` / `load_from_slot`, `SLOT_COUNT` = `3`) round-trip on the `GameState` API and are **player-reachable through the Save / Load screen** (`scripts/ui/save_load_screen.gd`, the `SaveLoadScreen` autoload): in-game via the *Save / Load* button on the Options menu's bottom row, at the start menu via *Load Game* (shown once any manual save exists). The read-only CYBER SUNDAY *Saves* dock shows the same files.
- **New Game doesn't delete the file immediately** -- the existing save survives until the first autosave of the new run overwrites it, so starting a new game and quitting before any progress doesn't lose your prior run.

Key files: `rpg/managers/GameState.gd` (the whole model -- `save_to_disk` / `load_from_disk` / `capture` / `autosave` / `reset_for_new_game` / `set_respawn` / `set_current_level`) and `rpg/scripts/world/game_root.gd` (resolves the saved `LevelData` on boot).
### Quicksave & manual slots (alongside the autosave)

The Dark-Souls autosave above is still the canonical, quit-and-resume profile. Layered **over** it are explicit, player-driven snapshots -- **one quicksave plus three named slots** -- written to *separate* files so they never clobber the autosave (`user://quicksave.cfg`, `user://save_slot_1.cfg` .. `user://save_slot_3.cfg`). Quitting still resumes the autosave; a quick/slot save is a deliberate bookmark you load on demand.

There's nothing to drop in your scene -- it's all on the `GameState` autoload, driven by the F5/F9 keys or the shipped **Save / Load screen** (below):

- **`quicksave(player)`** / **`quickload()`** -- write / restore the single quicksave. Bound to **F5 / F9** at runtime.
- **`save_to_slot(player, slot)`** / **`load_from_slot(slot)`** -- the same for manual slot `1..3` (`SLOT_COUNT` = `3`).
- **`has_quicksave()`** / **`has_slot(slot)`** -- whether each file exists; the Save / Load screen gates its *Load* buttons (and paints its *Empty* captions) on these.

**The Save / Load screen** (`scripts/ui/save_load_screen.gd`, autoload `SaveLoadScreen`) is the player-facing face of this layer: one row per file -- the quicksave (**load-only**: F5 owns writing it) then slots 1..3 -- each showing the saved level's `LevelData.display_name` plus the file's modified time (an empty slot says so). In-game (Options menu → *Save / Load*; Options closes first, the screens never stack) every slot row offers **Save** -- with an overwrite confirm on an occupied slot -- and **Load**; from the start menu (*Load Game*, shown once any manual save exists) it is load-only and boots the chosen file exactly the way Continue boots the autosave. Escape or the Interact key closes it, and like the Options menu it does **not** pause the world. Keep the two-tier language straight: every row here is the **exact-snapshot tier** -- the lean autosave/Continue profile is a separate product and deliberately never appears in this menu.

What a quick/slot save captures is **the full run profile** (the same money / stats / unlocks / backpack / reputation / flags / quests / perks as the autosave), the **active `LevelData` path**, and the respawn point at the player's *current* position and facing -- so a load returns you to the level and spot where you saved, not to the editor's default level or the last bonfire. A load is applied the same way Continue is: it sets `loaded = true` and **reloads the scene**, rebuilding a fresh Player that re-applies the saved build (and resetting `Engine.time_scale` first, so a quickload fired during the death slow-mo doesn't carry the dilation across the reload). The live player is never mutated in place.

**A quick/slot save is also the EXACT-snapshot tier.** On top of the profile it writes a `[world_snapshot]` cfg section (`rpg/scripts/world/world_snapshot.gd`, with its own `SNAPSHOT_VERSION` decoupled from the profile's save version) capturing the live world -- where every authored NPC in the level you saved in was standing (position / yaw / hp), plus every visited level's authored-NPC death ledger, plus **every authored `ItemContainer`'s exact contents** in the level you saved in (stacks incl. the coin tile and per-instance weapon state, the grid layout you arranged, and a child `Lock`'s picked-open state) -- which `GameRoot.load_level` re-applies once, after the level subtree enters the tree, via `GameState.consume_world_snapshot()`. Restoring a container REPLACES the bag its `_ready` just seeded, so a looted crate stays looted and its `loot_table` does **not** re-roll; a child `Restocker` is marked spent, so the first reopen after a quickload can't insta-refill it. The lean autosave/Continue profile **never** carries one (`autosave()` nulls it first), and that is the real difference between the two save products. A snapshot written by a version outside the supported range is skipped with a warning and the profile still loads on its own (the range is `SNAPSHOT_MIN_COMPAT`..`SNAPSHOT_VERSION`; the shape has only grown additively, so an older quicksave keeps its world state). Still out of scope: corpses (a dead authored NPC just vanishes on quickload -- no body, no loot), loot drops, dynamically-spawned (spawner) NPCs, **and containers in any level other than the one you saved in** -- those re-seed from their authored exports. See "The exact-snapshot tier roadmap" in `docs/CURRENT_ARCHITECTURE.md`.

F5 / F9 are also present in the data-driven controls catalog (`resources/input/ActionCatalog.tres`), so they can show up with the other rebindable actions in Options.

#### Gotchas

- **Off-tree saves do nothing.** Like `autosave`, `quicksave` / `save_to_slot` no-op (and return `false`) when the player isn't in the tree -- so a unit-test run never overwrites your real save files.
- **A failed disk write reports failure, not success.** `save_to_disk` returns the `ConfigFile.save()` `Error`; `quicksave` / `save_to_slot` (via `_capture_and_write`) return `false` if the write didn't persist (disk full / permission), so the F5 path toasts *"Quicksave failed"* instead of a false *"Quicksaved"*, and any failed write `push_warning`s to the error log/overlay.
- **A quick/slot save moves your checkpoint.** Because it stamps the respawn point at where you're standing, loading it -- or dying afterward -- brings you back *there*, not to the last `Bonfire`.
- **Slot numbers are clamped to `1..3`.** A bad slot index can't escape `user://`; it just lands on the nearest valid slot.


---

## Destructible & throwable props (ThrowableData)

A crate you can shoot apart, a barrel, a gore gib -- any destructible / grabbable physics prop is a **`Throwable`** component (§11 catalogue) driven by a **`ThrowableData`** resource. `ThrowableData` is to a Throwable what `WeaponData` is to a weapon: one Throwable scene reskins into many object types purely by swapping the `.tres`. Author one with **CYBER SUNDAY → `Content` tab → *New Throwable*** (type an id, it writes the `.tres` into `res://resources/interactables/` and opens it), or by hand with **right-click `res://resources/interactables/` → New Resource → `ThrowableData`** (the shipped examples are `wooden_crate.tres` and `gore_gib_data.tres` (shared by the meat chunks AND the body-part gibs)) — then assign it to the Throwable's data slot.

The fields, by inspector group:

| Group | Fields |
|---|---|
| **Identity** | `display_name` (optional noun for hover prompts: `Dog` shows as `[Z] Pick Up Dog`; blank keeps the generic `[Z] Pick Up`) |
| **Stats** | `destructible` (can it be damaged/destroyed at all -- **ON by default**; turn OFF for indestructible props like the dog, so a stray shot/impact can't break them -- `take_damage` then no-ops entirely; settable on the **data** to cover every instance OR on a placed Throwable per-instance, and EITHER one being off wins. **Weapon drops set this OFF automatically** -- `WorldItem.build()` stamps `destructible = false` on any dropped weapon, so you never hand-author it for a tossed gun/knife); `max_hp` (hits before it breaks, default `5`); `mass` (kg -- heavier throws/falls with more momentum); `physics_material` (bounce/friction; null = the scene's default) |
| **Appearance** | `mesh` and `material` overrides (null = keep what the Throwable scene ships with) |
| **Audio** | `pickup_sound` (one-shot when the player grabs/carries it), `held_loop_sound` (looped while carried, e.g. dog panting), `release_sound` (one-shot when the player drops/throws/lets go), `throw_sound` (played **instead of** `release_sound` on a real throw -- null = a throw just uses the release sound), `impact_sound` (hard knock), `destroy_sound` (on break) -- null = silent |
| **Destruction FX** | `destroy_particle_scene` (null = the default dust puff), `destroy_screen_shake` (camera kick, default `0.35`), `spawns_destroy_decal` (scorch on the floor -- gibs set this `false`) |
| **Behaviour** | `fade_while_held` (ON = prop becomes see-through while carried; OFF = stays opaque, useful for Dog), `face_carrier_while_held` (Portal-style carried pose: yaw the prop so its front faces back toward the player/camera), `face_carrier_rotation_degrees` (extra local correction if the imported mesh's front is not Godot `-Z`), `breathe` / `breathe_amount` / `breathe_rate` (visual-only living-prop pulse, same sine idea as NPC torsos); `damages_player` (does a high-speed impact hurt the player -- gibs set `false` so your own kill's chunks can't chip you); `is_gib` (marks a gore chunk -- shooting one out of the air pops confetti instead of gore) |
| **Stealth** | `noise_on_land` (**ON by default**; turn OFF for a silent throwable) -- a **thrown** copy drops a one-shot `NoiseSource` where it lands (the "lob a rock to distract a guard" verb, §19); `noise_radius` / `noise_decay` override the global `distraction` defaults per-prop (negative = inherit), and `noise_lifetime` likewise but inherits on `0`-or-negative too (a decoy is always one-shot, never persistent) |

### Gotchas

- **Names can live on the data or the placed prop.** Set `ThrowableData.display_name` for a reusable prop type; set a placed `Throwable.display_name` to override just that instance.
- **Pickup sounds follow the same rule.** Set `ThrowableData.pickup_sound` for every prop of that type, or set a placed `Throwable.pickup_sound` when one instance needs a custom grab sound.
- **Held loops are for continuous carry audio.** Set `ThrowableData.held_loop_sound` for every prop of that type, or set a placed `Throwable.held_loop_sound` for one special prop. Any assigned stream loops until the prop is dropped/thrown/freed. By default it plays only while *carried* — but see `loop_when_noticed` below to also play it when the player is near/looking.
- **Release sounds fire when the player lets go.** Set `ThrowableData.release_sound` for every prop of that type, or set a placed `Throwable.release_sound` for one instance. It plays on drop, throw, and forced release.
- **A real THROW can have its own sound.** Set `ThrowableData.throw_sound` (or a placed `Throwable.throw_sound`) and a genuine throw — the `Z`/`E` long-hold release or the **left-click quick-throw while carrying** — plays *that* instead of the release sound, so a hurled knife whips while setting it down stays quiet. It degrades safely: with no `throw_sound` authored a throw uses `release_sound`, exactly as before. A tap-drop and a **forced** release (death/quickload) are never throws, so they always use `release_sound`. A **WEAPON drop** authors it as `WeaponData.thrown_sound` instead (it has no `ThrowableData`); the knife uses `Throw.mp3`.
- **A prop can be thrown HARDER than the global default.** `Throwable.throw_impulse_mult` (Tuning group, `1.0` = normal) multiplies `PhysicsDamageSettings.pickup_throw_impulse` for **this prop only**, so a knife can leave the hand at `30` m/s while a crate still lobs at `12`. It scales a real throw only — the tap-drop impulse and the forced release are returned untouched, and the throw-vs-drop test deliberately reads the **raw** impulse *before* the multiply, so a fast-throw prop's gentle set-down can never be scaled up past the throw threshold and start nosing/whipping/aggroing like a throw (pinned by `tests/test_throw_release_policy.gd`). A weapon drop authors it as `WeaponData.thrown_impulse_mult`, which also enables `continuous_cd` on the drop above `1.0` — a fast slender body that crosses more than its own collider length per physics tick can tunnel through thin geometry otherwise. **Watch the damage coupling:** the default prop-impact formula is speed-derived, so raising launch speed raises damage too. If you want a fast throw whose damage you control independently, pair it with `thrown_uses_weapon_damage` (below) — that's exactly why the knife has both.
- **A thrown WEAPON can hit like the weapon, not like a rock.** `Throwable.thrown_weapon` (a `WeaponData`) switches a hit on a Character off the speed-based bludgeon and onto the real weapon-damage path: `ShotResolver.scaled_damage` with the weapon's `damage` + `headshot_multiplier` + melee/ranged stat scaling, and the contact point forwarded to `take_damage` so limb/zone damage lands. Author it on a placed `Throwable` for a bespoke prop (a spear, a cleaver), or — for a **weapon drop**, which has no `ThrowableData` — set `WeaponData.thrown_uses_weapon_damage` and `WorldItem` stamps the resource for you. Null (every crate, gib and gun) keeps the blunt formula unchanged. The contact point is approximated by the prop's ORIGIN, since Godot's `body_entered` carries no manifold — fine for a slender weapon whose collider is centred on its model, and well inside the granularity `Character.is_headshot` tests at.
- **A prop can sound different when it hits a CHARACTER.** Set `ThrowableData.character_impact_sound` (or a placed `Throwable.character_impact_sound`) and a hit on an NPC or the player plays *that* — e.g. the Dog's bite — **instead** of the generic impact thud; walls and other props still thud. Leave it null and a character hit just uses the normal `impact_sound`. Same speed-scaling and cooldown as the generic thud, so it never double-plays.
- **Carry visibility can live on data or the placed prop.** `ThrowableData.fade_while_held = false` keeps every prop of that type opaque while carried. A placed `Throwable.held_visibility_mode` can force `Fade` or `Opaque` for just one instance, or stay `Inherit`.
- **Portal-style facing is opt-in.** Turn on `face_carrier_while_held` for props like Dog that should present themselves to the player while carried. If the model faces sideways/backward, adjust `face_carrier_rotation_degrees` (often `Y = 180`) until its face/nose points at the player. **The pose can be REVERSED.** `face_carrier_reversed` (instance or `ThrowableData`) points the prop's front **away** from the carrier, down their look direction, instead of back at them: the dog is *presented* to you, a knife is *held ready to throw*. It flips the aim **direction**, not the mesh correction — deliberately, because `face_carrier_rotation_degrees` is shared with the thrown facing, so flipping it there would also spin the prop mid-flight. A **WEAPON drop** has no `ThrowableData`, so it opts in through `WeaponData.held_faces_aim`, which sets both flags at once — the knife uses it, keeping the same `Y = 180` its thrown facing needs while the blade in your hands points forward down your aim.
- **Thrown props can nose toward their travel direction.** Turn on `face_travel_when_thrown` (per-instance, or `ThrowableData.face_travel_when_thrown` for every prop of that type) so a *thrown* prop — a knife, spear, bottle — leads with its front and tips over as it arcs. It's THROW-only: a tap-drop, a forced release (death/quickload), and a re-grab never trigger it. It uses the same `face_carrier_rotation_degrees` for the mesh-front correction, and releases back to natural tumbling once the prop slows below `face_travel_min_speed` — `ThrowableData.face_travel_min_speed` defaults `2.0` m/s; the placed `Throwable.face_travel_min_speed` defaults `0`, which *means* "inherit the resource", so set a positive value on the instance to override it. The whole **Throw Pose** group lives on the `ThrowableData` resource too, so a prop type is configured once and reused. Applies to the pickup throw (Z/E long-hold), the **left-click quick-throw while carrying**, and a grapple yank-fling — but never the tap-drop. A **WEAPON drop** is the third authoring surface: it has no `ThrowableData`, so it inherits this pose from its `WeaponData`'s **Thrown** group instead (`thrown_faces_travel` / `thrown_face_rotation_degrees`, stamped by `WorldItem`) — the knife's `Y = 180` is the worked example of a mesh-front correction. Note the **facing-release** speed (`face_travel_min_speed`, the speed at which the prop stops nosing and starts tumbling) is **not** per-weapon authorable: a weapon drop has no resource and `WorldItem` doesn't stamp the instance field, so it always uses the `2.0` m/s default. The *launch* speed is a separate knob and **is** per-weapon (`thrown_impulse_mult` — see the throw-harder gotcha above).
- **A thrown prop can drag a tracer.** Child a **`ThrowTrail`** to it and a real throw leaves a white streak behind the prop for the length of its flight. (A *weapon* drop needs nothing: `WeaponData.thrown_trail` is on by default, so every thrown weapon already streaks — this is for hand-placed props.) Same THROW-only rule as the nosing above — a tap-drop and a forced release draw nothing — but it is **independent** of the nosing: a prop can streak without nosing, or nose without streaking. On a prop that does *not* nose, leave the trail node at the body origin; an offset one orbits the centre of mass as the prop tumbles and scribbles a corkscrew. Shape is global (**Effects → Thrown weapon trail**), colour is per-prop (`ThrowTrail.color`, or `WeaponData.thrown_trail_color`). Unlike the facing, the streak is not released by `face_travel_min_speed` — it has its own `throw_trail_min_speed`, and the tail *fades* out rather than stopping dead.
- **Living throwables can breathe.** Turn on `breathe` for props like Dog. It pulses the visual `mesh_instance` scale only; the RigidBody and collision shape stay fixed, so breathing is presentation, not physics.
- **Living throwables can pant when you notice them.** Turn on `loop_when_noticed` (the **Idle Loop** group) so the `held_loop_sound` (the pant) ALSO plays when the player is NEAR the prop (`loop_near_radius`, default `3.5` m) or LOOKING at it (`loop_look_range` `12` m within a `loop_look_dot` `0.96` view cone) — not only while carried. One loop player drives both, so it hands off seamlessly: drop the dog while watching it and the pant continues. The Dog has this on; it needs a `held_loop_sound` to have anything to play.
- **It's the `WeaponData` of props.** The same Throwable scene becomes a crate or a barrel by swapping the `.tres`, so build the scene once and vary the data.
- **The thrown-decoy noise needs the global flag.** `noise_on_land` does nothing until `GameSettings.npc_ai.hearing_initiates` is on (§19) -- it's the stealth distraction channel.
- **Gibs are throwables too** (`is_gib = true`): they skip the destroy decal, don't hurt the player, and pop confetti when shot mid-air. That covers **both** kinds — the generic meat chunk (`gore_gib.tscn`) and the **body-part gib** (`body_part_gib.tscn`, a real head/torso/arm/leg torn off the dying character), which share `gore_gib_data.tres` (shared by the meat chunks AND the body-part gibs). So a severed head can be shot out of the air for the trick shot, or picked up and thrown ("Pick Up Head").
- **A body-part gib's `ThrowableData` must set NO `mesh` and NO `material`.** Its visual is mounted at spawn from the dying character's own `BodyModelSwap` part; `Throwable._ready` pushes `data.mesh`/`data.material` over everything under the mount point, which would replace the limb or wipe the character's skin off it. `body_part_gib.gd` config-warns in the editor if you assign a data resource that sets either.
- **`mesh_instance` is what the gib despawn FADE tweens — wire it or the fade is a silent no-op.** After `GameSettings.effects.gib_lifetime` a gib fades out over `gib_fade_time` and frees itself, and `Throwable._fade_out_for_despawn` does that by tweening `mesh_instance.transparency`. With the export unwired it returns immediately, so the chunk **pops** out of existence and the `gib_fade_time` knob does nothing. (This is exactly what `gore_gib.tscn` shipped with for a long while; it now wires both refs, pinned by `tests/test_gore_gib_prefab.gd`.) A chassis whose visual is a **subtree** under the mount point must also override `_fade_out_for_despawn` — `GeometryInstance3D.transparency` is per-instance and does **not** propagate to children, which is why `body_part_gib.gd` tweens every mesh in its mounted limb instead.
- **`auto_fit_collider` (Prop Setup, default ON) — turn it OFF for a deliberately off-centre collider.** On ready/save `Throwable` resizes `collision_shape`'s shape to the visual bounds, so a prop reskinned by swapping its `.tres` is never mis-sized. But the auto-fit rewrites the shape's **size only** — it never touches the `CollisionShape3D`'s own transform, and a `BoxShape3D` is centred on that transform's origin. So a collider intentionally offset or rotated away from the visual centre gets **grown to the full mesh bounds while keeping that offset**, poking out one side of the prop and missing the other. That is the shipped meat chunk (`gore_gib.tscn`): its box is hand-tuned to `0.384 × 0.320 × 1.0`, tilted ~14.5° and raised `+0.237` m, against a `model.obj` whose bounds are ~`1.0 × 1.0 × 1.08` — auto-fitting it would put a quarter-metre of collider above the chunk and none underneath. It ships **off**. The cost of switching it off is that a `ThrowableData` mesh swap no longer resizes the collider, so re-author the box by hand. Same field name and meaning as the `auto_fit_collider` on `LookAtInteractable` / `Pettable` / `Claimable`.

Key files: `rpg/scripts/combat/throwable_data.gd`, `rpg/scripts/components/Throwable.gd`; example data under `rpg/resources/interactables/`.

---

## Menus are scenes (authored `.tscn` screens)

Every converted menu screen is an **authored scene** you edit in the Godot editor, not a code-built tree. The screen's autoload in `project.godot` points at the **scene** (`*res://scenes/ui/<screen>.tscn` — the root carries the script), and the split is strict:

- **The scene owns STRUCTURE**: containers, anchors (full-rect roots, the `0.12` / options-`0.07` panel bands), size flags and stretch ratios, autowrap/clip flags, focus modes, scroll modes, literal separations. Rearranging a screen, adding decoration, inserting artist frames — all editor work, no code.
- **The script owns BEHAVIOUR + LOOK**: it binds the chrome by **`%` unique name** in `_bind_ui()` (rename a bound node and the screen breaks at boot — each screen's `tests/test_<screen>_scene.gd` pins the `BOUND` roster), wires signals, and applies every skin-derived value at runtime through the `MenuStyle` adopt-helpers (`apply`, `style_dim`, `style_dialog_card`, `style_title`, `style_hint`, `style_button_row` — the `make_*` factories' twins). So `menu_skin.tres` keeps reskinning scene screens exactly like it always did.
- **Dynamic content stays code-built**: shop/loot grids (`GridInventoryView`), options rows (generated from `SettingsCatalog`/`ActionCatalog` into the authored empty `%Tabs`), per-stat/faction/quest rows, and the player-menu tab strip (`PlayerMenus.build_tab_strip` into each screen's authored empty `%TabSlot`). The scene authors the **containers** those populate.
- **No text in scenes.** Every `.tscn` ships empty `text` properties; scripts set all strings from `PlayerText` (l10n + the text-debt ratchet own strings). The per-screen scene test enforces this.

**Adding a new screen:** copy the exemplar trio — `scenes/ui/heal_screen.tscn` + `scripts/ui/heal_screen.gd` (see its `AUTHORED SCENE` header + `_bind_ui`) + `tests/test_heal_screen_scene.gd` — and register the autoload as the scene. For a full-panel screen with an anchor band and scroll sections, `level_up_screen` / `loot_screen` are the closer templates; for the player-menu tab family, `stats_screen` (or `quest_journal` / `implants_screen` for the plain scrolling-list flavour).

**Gotchas:** don't author skin-derived values (colours, fonts, `content_separation`, width pins) into a scene — they'd go stale the moment the skin changes; the adopt-helpers apply them at runtime. Don't hand-write `uid://` strings in a `.tscn`; the editor assigns one on import. Buttons authored in a scene get their **hover + generic click** sounds from `MenuStyle.apply()`'s existing-button sweep — nothing to wire for those two. But a button whose meaning is *not* "generic confirm" — a Back/Close, a tab, a purchase — needs `MenuStyle.set_button_sound(btn, kind)` (`&"back"` / `&"tab"` / `&"commit"`, or `&""` to mute), or it will sound TWICE: once from the auto-wired click and once from whatever its handler plays. See §"Reskinning the menus" → **Sounds**.

## Reskinning the menus (`MenuSkin`)

The entire menu look -- the start menu and every in-game modal (inventory, shop, loot, level-up) -- comes from **one** resource: `res://resources/ui/menu_skin.tres` (`class_name MenuSkin`). The **`MenuStyle`** autoload reads it and builds the live `Theme` every menu uses, so editing that one `.tres` in the inspector restyles the **whole UI** -- no menu code. (VFX have no equivalent single skin -- `EffectFactory` is **not** a VFX registry; each effect is restyled by editing its own `.tscn`, see §12 **"Restyling the effects themselves"**.)

Open `menu_skin.tres` and edit, by group:

| Group | What it controls |
|---|---|
| **Background (full-screen menus)** | `background_texture` (drop a PNG for a custom start-menu backdrop), `background_scene` (an animated/shader background -- wins over the texture), `background_color` (the flat fallback) |
| **Backdrop (in-game modals)** | `backdrop_dim` -- the dim drawn over the world behind a modal (higher alpha = darker) |
| **Panel** | the menu-card chrome: `panel_color`, `panel_border_color` / `panel_border_width`, `panel_corner_radius`, `panel_content_margin`, or hand your own `panel_style` `StyleBox` to fully replace it. The shipped skin does exactly that: the artist's torn-border olive panel (`assets/textures/ui/menu_panel.png` — a 600x375 bake of the 800x500 rectangle master in `src_masters/`, composited into a 616x391 canvas with a baked drop shadow) as a `StyleBoxTexture` with texture margins 36/36/36/40 (torn border + 8px shadow pad) and **expand margins 8** — THE SHADOW RULE: a baked shadow always rides in expand margins, which draw OUTSIDE the layout rect, so no metric anywhere shifts with the shadow (the button boxes follow it with a 5px pad). THE HOUSE LIGHT IS STRAIGHT OVERHEAD: every baked shadow falls straight DOWN, never diagonally — one vertical light is what makes panel, buttons, tooltip and dialogue box read as one lit object. `scripts/tools/bake_ui_shadows.gd` owns that (`godot --headless --path <abs> -s scripts/tools/bake_ui_shadows.gd`): it re-aims the shadow already in each PNG — sampling its colour and strength so the artist's weight survives — and sizes it to reach exactly the pad, so canvas sizes and every `.tres` number stay put. Keep the pad UNIFORM on all four edges even though the top one is now empty; the expand margins are what the tests pin, and a directional pad would move the drawn rect. Re-run it after any new art lands rather than compositing a shadow by hand. It wears on every `Panel`/`PanelContainer` under a menu root — full-panel screens AND the centered dialog cards. With `panel_style` set, the `panel_*` colour/margin knobs above are dormant for THEME wearers (the box carries its own content margins: 36/36/36/40) — but they still feed `MenuStyle.make_plain_panel_style()`, the generated flat panel worn by COMPACT confirm cards (quit-confirm / TOS-nag / overwrite-confirm adopt it via `MenuStyle.style_compact_card`, which also styles the card's `PanelContainer` parent) and — only while `dialogue_panel` (below) is empty — the dialogue choice list's solid backing: at ~106px popup scale the screen-card art is nearly all border, so utility popups keep the plain look by design. A new confirm-sized popup uses `style_compact_card`, not `style_dialog_card` |
| **Palette** | `text_color`, `text_dim_color`, `accent_color` (the single accent -- selection bar / focus / active tab / slider fill / hover), `gold_color` (zorkmids), `danger_color`, `disabled_text_color`. `text_color`/`text_dim_color` are **PANEL ink** — they colour text sitting on the menu card, and the shipped skin runs them DARK (the artist's plum on the olive panel). A surface that draws over the WORLD or the item art pins its own light ink instead of consuming them: dialogue lines (`DialogueSettings.dialogue_text_color`), the start menu's quote/attribution, the grid tiles' count badge (`tile_count_color`), and the whole HUD (its own `HudSkin` / `HudSettings` knobs) |
| **Typography** | `body_font` / `title_font` (null = Godot default), `title_size` / `header_size` / `body_size` / `hint_size`, `title_tracking`, and `uppercase_titles` (the tracked-uppercase look) |
| **Text drop shadow** | the TYPE half of the same straight-overhead light the art PNGs are baked with (see the Panel row's SHADOW RULE): `text_shadow_color` (⚠ **alpha 0 = no text shadow** — the same alpha-as-null sentinel the button ink knobs use, so an art-less skin stays flat), `text_shadow_offset` (a `Vector2i`; keep **X at 0** — straight down is the whole point, and a sideways lean would disagree with every panel and button on screen), and `text_shadow_blur` (Godot's `shadow_outline_size`; 0 = a crisp offset copy, which is what the pixel look wants). ⚠ **What this can and cannot reach:** Godot 4.7 gives font-shadow theme items to `Label`, `RichTextLabel` and `TooltipLabel` and to **nothing else** — `Button`, `TabBar`/`TabContainer` and `LineEdit` never read one. So every title, hint, options row, list column and stat/price/wallet readout wears the shadow, but **button captions, the two tab strips and the four text fields do not**, and can't without re-drawing their glyphs by hand. That is a deliberate stop, not an oversight: the shipped skin paints captions DARK on the LIGHT parchment button art, where a dark drop shadow is nearly invisible anyway, while panel Labels are plum on mid-dark olive, where it reads. ⚠ Setting `font_shadow_color` on the `Button` theme type **succeeds and does nothing** (`Theme.has_color()` will even confirm it is there) — don't be fooled into "fixing" it that way. The in-viewport cursor tooltip is a fourth surface that DOES get the shadow but takes it by hand (`MenuStyle._style_tip`): it hangs off the MenuStyle autoload's own `CanvasLayer`, so no theme reaches it. Pinned by `tests/test_menu_skin_art.gd` |
| **Layout** | the shared spacing/width numbers every panel screen reads instead of a per-file magic number: `content_separation` (root VBox gap), `button_row_separation`, `dialog_button_min_width`, `tab_min_width`, and `dialog_width` -- the FIXED width of a centered transaction/prompt card (heal / respec / name-entry) |
| **Layout budgets (English-measured px)** | the fixed pixel widths of TEXT-bearing columns/buttons, measured against the ENGLISH strings that land in them (German runs +30-40% longer): `slider_readout_width` + `rebind_button_width` + `setting_label_col_width`(`_dense`) (options rails), `sort_button_width` + `price_col_width` (shop / chip-install), `level_up_cols_width` + `stat_name_col_width` (level-up rows), `disposition_col_width` + `rep_value_col_width` (reputation — the disposition word and the right-aligned signed `+100`/`-100` standing columns), `cycler_value_width` (character creation), `start_button_min_width` (start menu — the Continue/New Game/Settings/Quit button floor; a min width with air, not a clip budget). A future locale retunes them via a per-locale remapped `menu_skin.tres`; do **not** "fix" a clipped string by growing one globally -- the fixed widths are what stop runtime text from resizing/shifting controls (see each knob's fit math in `menu_skin.gd`) |
| **Widget art — buttons / toggles / sliders / text fields / meters / tabs / scrollbars / misc** | **the UI artist's drop-in surface.** Eight groups of OPTIONAL per-widget, per-state art slots that replace the generated flat look wholesale: `button_normal`/`hover`/`pressed`/`focus`/`disabled` (`StyleBox` each), the four `toggle_*_icon` textures (CheckButton/CheckBox switch art), `slider_track`/`slider_fill` (+ `slider_grabber` thumb texture), `line_edit_normal`/`focus`, `meter_background`/`meter_fill` (deliver fill art in white/grey — tinted meters recolour a copy per row), `tab_selected`/`unselected`/`hovered` (worn by BOTH tab systems — the Options `TabContainer` and the player-menu strip), `scrollbar_track`/`grabber`, `separator_style`, `tooltip_panel` (the cursor tip and native tooltips), and `dialogue_panel` (the bottom conversation box — see its own note at the end of this row). Every slot is null by default and falls back to the generated look, so art can land **one widget at a time**. To turn a PNG into a slot value: in the slot pick **New StyleBoxTexture**, drop the PNG into its `texture`, and set its **Texture Margins** so the corners don't stretch (9-patch) — and set the SAME **Content Margins** on every state's box, or the button resizes as it is hovered (the menus-don't-shift discipline). Exception — `button_focus`: Godot draws the focus box as an **overlay on top of** the current state box (including disabled), so it must stay a transparent-centred ring/outline, never an opaque body (the shipped skin authors a 1px accent-ring `StyleBoxFlat` there). Opaque button art usually also needs the **caption ink knobs** in the same group: `button_font_color`/`_hover`/`_pressed`/`_focus`/`_disabled` (alpha 0 = unset → the palette-derived colour, so art-less skins repaint identically; the pressed knob also inks `hover_pressed`). The shipped skin carries the first delivery — the parchment `button_frame_*.png` set (`assets/textures/ui/`: game-ready 40px bodies baked from the artist's 100px masters in `assets/textures/ui/src_masters/` — a `.gdignore`d folder so Godot never imports the masters — composited into 50px canvases whose 5px pad holds a baked drop shadow — straight down, riding in the boxes' expand margins; see the Panel row's SHADOW RULE and re-aim with `scripts/tools/bake_ui_shadows.gd`) in `button_normal`/`hover`/`pressed`, the accent focus RING in `button_focus`, and dark inks for all five states; `disabled` art stays null — `MenuStyle` derives a dimmed copy of the rest body for it (the toggle-icon reuse rule), so enable/disable greys the body instead of popping it. KNOWN STAND-IN: the artist's "Selected" file arrived byte-identical to "Normal", so `button_frame_selected.png` is currently that copy and the pressed box darkens it via `modulate_color(0.88, 0.86, 0.82)` — when real Selected art lands, replace the PNG and clear the modulate. One more consumer rule: an empty-text LIST-ROW button (rows carrying their own child Labels) must route through `MenuStyle.style_list_row()` beside `size_row_button()` — rows keep the transparent/accent-bar ROW language and must never wear the button-body art (their labels' light inks would drown in it). **`dialogue_panel`** is the odd one out and gets its own slot for a reason: the conversation box is short and very wide (~632x160 on the 792x444 canvas) and floats over the 3D world, so the full torn-border screen card in `panel_style` would drown it — the same logic as the compact confirm cards. The shipped skin fills it with the artist's OTHER panel — the transparent one, whose rectangle revision became `panel_style` — baked at 0.4 of the 800px master (`src_masters/dialogue_panel_800.png` → `assets/textures/ui/dialogue_panel.png`, a 320x200 body in a 336x216 canvas carrying the same 8px shadow pad). ⚠ **THE NOTCH RULE**: that art's bottom-left corner is genuinely **cut away** (transparent), and a 9-patch draws only the four CORNER cells at native size — so `texture_margin_left` (78) and `texture_margin_bottom` (54) must **contain the whole cut**, or it smears across every stretched column, and `content_margin_bottom` (44) must clear it, or the last choice button paints over the hole. Re-bake at a different scale and **rescale all four margins with it**. Leave the slot null and the box returns to its background-LESS look — outlined text straight over the world, with only the response menu backed by `make_plain_panel_style()`; both looks are supported, so this slot is a real fork rather than a migration. Pinned by `tests/test_menu_skin_art.gd` |
| **Grid tiles** | the tetris-grid stack tiles (`grid_tile.gd` / `grid_inventory_view.gd` -- the inventory/loot/shop cells): `equipped_border_color` (the equipped item's tile border -- defaults to the accent gold, so diverging from the ammo/money category gold is a deliberate choice), `tile_consumable_color` (border tint of a consumable stack's tile, the non-weapon "use it" category), `tile_hover_ring_color` (the thin ring the overlay draws around the hovered stack), `drag_source_dim_alpha` (the alpha the source tile dims to while its stack is being dragged), `tile_count_color` (ink of a tile's stack-count / money badge). That badge ink is a GRID knob on purpose, **not** `text_color`: it paints over the item art inside a dark tinted cell rather than on the menu card, so it stays light while the panel palette runs dark (the shipped plum) — the same rule dialogue text and the start-menu quote follow, and it matches the white the HUD hotbar's slot text wears. Pinned by `tests/test_menu_skin_art.gd` |
| **Sounds** | **the menu's whole audio vocabulary — one `AudioStream` slot per SEMANTIC event, every one optional (null = that event is silent), so audio lands one cue at a time exactly like the widget art.** `hover_sound` (mouse over any button — the highest-frequency cue, keep it short and quiet), `click_sound` (the DEFAULT confirm), `open_sound` (a menu came up COLD — never a tab swap), `back_sound` (back / close / cancel), `tab_sound` (a SIDEWAYS swap: tab strip, tab bar, shop sort, payment-rail flip), `step_left_sound` / `step_right_sound` (a value stepped down/left or up/right — cycler arrows, +/- buttons, slider ticks), `commit_sound` (a HEAVY commit: money spent, level taken, save written, run stamped), `denied_sound` (the game REFUSED the action: can't afford it, out of stock, bag full, nothing to withdraw, an illegal move, a failed save). The shipped clips live in `res://assets/audio/sfx/ui/`. **`denied_sound` is the ONE slot you can leave empty and still hear** — unassigned, it DERIVES from `back_sound` played at `denied_pitch_scale` (0.75), which is why refusals are audible out of the box with no ninth clip; assign a real stream to override, and tune `denied_pitch_scale` either way. Do not repurpose `back_sound` for refusals yourself: back means "this closed / I honoured your cancel", and a refused Confirm that plays the ordinary close sound reads as "done". **Volume** sub-group: `ui_sound_volume_db` is the MASTER trim and each `*_volume_db` is ADDED to it (the clips are not normalised against each other and land on the `sfx` bus, which carries its own trim plus a distortion insert — so levelling is a designer job here, never an import-time normalize; `step_volume_db` covers the L/R pair with ONE knob so the two directions can't drift apart; `denied_volume_db` is the only trim shipping non-zero at `-2.0`, since its default voice is a clip levelled for a different job). **Retrigger limits** sub-group: `hover_min_interval` (drop hover ticks closer than this — sweeping a 12-row list otherwise machine-guns), `step_min_interval` (tames keyboard auto-repeat on the cyclers), `slider_tick_count` (a full slider sweep is quantised to this many ticks whatever the slider's own step is, so a 360-step Max FPS slider and a 0..1 slider feel identical) |

To restyle: edit the fields and save -- every screen updates next run. For a whole alternate theme, author a second `MenuSkin` `.tres` and point `MenuStyle` at it (`MenuStyle.set_skin`).

**Working with a UI artist who doesn't use Godot:** ask for widget art as PNGs — a button in its five states (rest / hover / pressed / focused / disabled), a slider track + fill + thumb, toggle ON/OFF, a tab, a panel, a tooltip card — each drawn so the middle can stretch (tell them where the safe 9-patch margins are). *You* then do the one Godot step per asset: wrap the PNG in a `StyleBoxTexture` in the matching Widget-art slot and set its Texture Margins. No scripting, and each asset lands independently — the rest of the UI keeps the generated look until its art arrives. Remember the theme colours the **text** (`Palette` group) and the art boxes sit *behind* it, so agree on a palette with the artist too — for buttons specifically, the per-state **ink knobs** next to the art slots override the palette-derived caption colours when the delivered body needs its own (e.g. dark ink on the shipped parchment frames). Mind the SCALE: the canvas is 792x444 and a text button stands ~22-24 px, so a large master (the artist's frames arrive at 100 px) must be baked down to a game-ready size (the shipped set is 40 px, ~5 px of bevel per edge) before its 9-patch margins can physically fit — keep the master in `assets/textures/ui/src_masters/` (`.gdignore`d) and re-bake from it. Bakes may composite a drop shadow into a padded canvas — the pad's width then goes into the box's **expand margins** (draw-only), never its content margins, so shadows cost zero layout. Don't hand-composite that shadow: drop a row for the new texture into `scripts/tools/bake_ui_shadows.gd` and run it, so the piece inherits the one house light (straight down) instead of whichever way the artist's layer effect happened to lean.

**`uppercase_titles` / `title_tracking` are the *latin* look, and that's a recorded constraint, not an accident.** The UI renders at 792x444 with 11-15 px type; CJK is illegible at that scale under tracked uppercase, so a future CJK locale means a per-locale `MenuSkin` (bigger sizes, `uppercase_titles = false`, `title_tracking = 0`) plus a legibility pass -- don't retune `title_tracking` globally without knowing this. Code-side, `MenuStyle.title_text()` is the ONLY casing site and it consults `uppercase_titles`, so flipping the flag really does de-case every title at once.

**Menus don't shift with text.** Every screen is built so no runtime string (a merchant/station name, a cost, a stat value, a money total) can change an element's width, position, or alignment. Four disciplines enforce this, and any new menu code must follow them:
- **Full-panel screens** (inventory / shop / loot / stats / level-up / journal / reputation / options) pin their `PanelContainer` to a fixed screen *fraction* via a per-screen `PANEL_MARGIN` const (`anchor_left = PANEL_MARGIN … anchor_bottom = 1.0 - PANEL_MARGIN`, offsets `0`) -- `0.12` on all of them except options, which uses `0.07` for a wider panel -- so the panel is content-independent. Value columns use fixed `custom_minimum_size.x` (right-aligned), and unbounded labels are capped with `MenuStyle.cap_label()` (`clip_text` + `…` -- clip_text is what actually drops a Label's min width so the cap holds; ellipsis alone does not in a content-sized parent). `custom_minimum_size` is a FLOOR, not a cap -- a value column, slider readout, or fixed-width button (options rebind column) still needs `cap_label()` / `cap_button()` on top or a wide string grows it past the floor and shifts the row.
- **Floating dialogs** (heal / respec / name-entry) use `MenuStyle.make_dialog(root, extra_sep)`, which returns a content VBox pinned to `skin.dialog_width` inside a centered card. Titles/buttons run through `cap_label()` / `cap_button()`, status lines `autowrap`, and button rows use `SIZE_EXPAND_FILL` -- so the card is *exactly* `dialog_width` regardless of its text.
- **Heights must hold too.** The `make_dialog` pin is width-only: the card's height shrink-wraps and its `CenterContainer` re-centers on any height change, so a status label whose LINE COUNT varies hops the whole card. Keep every dynamic child's line count constant while it's on screen -- pad the composed string to its worst-case line count (`heal_screen.gd _refresh`) or reserve `custom_minimum_size.y`. Same rule inside anchored panels whose only vertical expander sits *below* the changing label (the chess panel's hint is single-line by contract for this reason).
- **Empty-text row buttons must be height-pinned.** A multi-column list row built as an empty-text `Button` carrying full-rect child Labels (the implant-choice / chip-install `_make_row` idiom) collapses to its stylebox v-margins alone — an empty text buffer contributes ZERO height to `Button.get_minimum_size()` — so the hover/pressed/focus accent bar (the menu "cursor"), the selection fill, and the click hitbox all land half a line above the visible text. Route every such button through **`MenuStyle.size_row_button()`**, which pins `custom_minimum_size.y` to the exact one-line caption box from the theme's Button metrics; `tests/test_menu_row_button.gd` pins the helper's math and its adopters. The level-up rows show the OTHER sanctioned shape (a wrapper `Control` with an explicit `custom_minimum_size.y` and the `Button` full-rect-anchored inside it) — either is fine; a bare empty-text `Button` as a direct list child is not.
- **Hide with alpha, not `visible`.** A Godot container REMOVES a hidden child from layout, so `visible = false` on a hint/status row makes its siblings slide into the gap (the character-creation name hint jumped the whole tab block on the first keystroke until it switched). Toggle `self_modulate.a` (0/1) to hide in place, or blank the text -- reserve the slot, never collapse it.
- **A card that can't fit its content GROWS -- it never clips or scrolls.** When a Control's combined *minimum* size beats the rect its anchors give it, Godot resizes it past those anchors (`grow_horizontal/grow_vertical = BOTH` swells it around its centre), so the panel gets bigger and re-centres, often off-screen. Two consequences every tabbed screen has to respect: **(1)** a `TabContainer`'s minimum is the CURRENT page's minimum unless `use_hidden_tabs_for_min_size` is on, so pages of different sizes resize the card as you click between them -- `MenuStyle.apply()` now pins that flag ON for every `TabContainer` under a menu root (and the scenes author it too, so the editor preview matches), which makes the minimum the MAX over all pages: one size, whichever tab is up. **(2)** That max still has to FIT. Budget it: *panel band* (`anchor fraction x 792x432`, the shortest the canvas ever gets) *- the panel stylebox's content margins* (the shipped parchment frame spends **72 x 76 px** of every card on its border) *- the screen's pinned chrome* (title / name row / button row / separations) *- ~24 px of tab bar* = what a page may claim. Character creation's Shirt tab wanted 202 px against ~156 px and pushed the card 45 px off the top of the screen; Options' Accessibility two-up columns wanted 642 px against 609 px and made the card 33 px wider than on every other tab. Fix the PAGE (fold a row into another, narrow a column floor, lower a canvas floor -- floors on `EXPAND_FILL` children cost nothing at the drawn size), never the anchor band. `tests/test_menu_layout_stability.gd` measures every tabbed screen at 792x432 and fails if a card changes size between tabs or outgrows its band; `scripts/tools/menu_size_probe.gd` (headless, prints per-node minimums) is the diagnostic when it does.

Key files: `rpg/scripts/ui/menu_skin.gd`, `rpg/scripts/ui/menu_style.gd` (the autoload that builds the Theme); the authored skin is `rpg/resources/ui/menu_skin.tres`.

### Reskinning the in-game HUD (`HudSkin`)

`MenuSkin`'s twin for everything painted **during gameplay** is `res://resources/ui/hud_skin.tres` (`class_name HudSkin`, `rpg/scripts/ui/hud_skin.gd`), exposed as **`MenuStyle.hud`** (swap a whole alternate skin at runtime with `MenuStyle.set_hud_skin`, the `set_skin` twin). Edit it in the inspector, grouped **per component**:

| Group | What it controls |
|---|---|
| **Crosshair** | `crosshair_texture` — OPTIONAL artist reticle art shown instead of the code-drawn dot while unscoped (the scoped inverting disc is functional and never replaced) |
| **HUD ghost** | `ghost_gradient` — the colour ramp of the phosphor trail behind the HUD (`scripts/ui/hud_ghost.gd`), sampled by each trail pixel's **age**: offset `1.0` is the freshest part of the tail, `0.0` the oldest. So a gradient authored cyan → violet → magenta makes a trail SHIFT HUE as it decays instead of being a dimmer copy of whatever colour the element was. Keep the freshest stop **saturated** — it is the brightest part of any trail, and a near-white one makes the whole effect read as translucent UI however colourful the cold end is. Null = the shipped ramp (`HudGhost.default_gradient`). How far the ramp replaces the source colour, and how visible the ramp's cold end is, are the `hud_ghost_tint` / `hud_ghost_tail_lift` amounts on `GameSettings.hud` |
| **Hitmarker** | the hit-confirm X around the crosshair: timing, tick geometry, body/headshot colours + scale, and an optional `hitmarker_texture` drop-in |
| **Damage direction arcs** | the red "hit from here" arcs: duration, radius, wedge width, thickness, colour |
| **Aim warning arcs** | the "being aimed at" radials + the shot-ping: radii/damage scaling, colour, alpha ramp, blink beat |
| **Sniper glints** | the distant-aimer lens flare: core radius, streak length, colour, charge ramps |
| **Compass / Minimap** | the compass's fallback marker tint + an optional `compass_marker_texture`; and the minimap's WHOLE painted look — every colour *and* every width/size it inks (wall stroke + optional glow, rim, the four marker sizes, glyph stroke, alert-ring gap/step, off-floor tick + fade, north tick, rim-pin margin). Sizes moved here from `HudSettings` on 2026-08-19 so a colour and its width are never in two files |
| **Minimap art** | ten optional `Texture2D` slots — the player caret, the POI beacon, and the seven station badges. Null = the code-drawn glyph. The contact sheet is below |
| **Label chrome** | the black-outline dialect on the HUD's code-built labels (toasts, money, quest tracker, look-name, ammo corner readouts) |
| **Hotbar chrome** | slot panel modulate, key-caption/count tints, item-name outline width |

The same rules as `MenuSkin` apply: every optional texture slot defaults **null = the shipped code-drawn look**, and every default **equals the value the code used to hardcode**, so an untouched `hud_skin.tres` is pixel-identical to the shipped game (`tests/test_hud_skin.gd` pins this). What is deliberately **not** here: gameplay-tuning numbers (bar geometry, sway, timings, fonts) stay on `GameSettings.hud` (`resources/tuning/HudSettings.tres`); allegiance/gain-loss colours stay on `CBPalette` (colorblind accessibility, not art); accessibility gates stay in Settings; and a scene-authored HUD component's own `@export`s (compass/minimap geometry) still win per-instance.

**Editing the skin against a running game.** The minimap now listens to `Resource.changed` on the live skin and repaints on it, so you can open Godot's **Remote** inspector while the game runs, click `hud_skin.tres`, and nudge a colour or drop in a texture to see it land immediately. (It also repaints on a whole-skin `MenuStyle.set_hud_skin` swap. Both matter because the map deliberately does **not** repaint while the player stands still.)

#### Minimap marker art — the contact sheet

Ten slots in the **Minimap art** group. Every one is optional, and each replaces the marker's **silhouette only** — where it sits, how big it is and what colour it wears stay owned by the knobs, so a PNG can never set its own footprint on a 108 px box or break the colour contract. **Deliver art white/grey and let the tint colour it**, exactly as `MenuSkin`'s meter fills ask.

| Slot | Replaces | Sized by | Tinted by | Rotates? |
|---|---|---|---|---|
| `minimap_player_texture` | the caret triangle at the box centre | `Minimap.arrow_size` (a square of 2x it) | `minimap_player_color` | **Yes** — the only one. Author it pointing **screen-up** |
| `minimap_poi_texture` | the flat POI dot (`WorldMarker` / quest beacon) | `Minimap.marker_radius` | the marker's own `color`, else `minimap_npc_color` | No |
| `minimap_station_texture` | *the family fallback* — any station kind with no slot of its own | `minimap_station_glyph_px` | the `StationMarker`'s own `color`, else `minimap_station_color` | No |
| `minimap_station_shop_texture` | the stroked diamond (`Merchant`) | ↑ | ↑ | No |
| `minimap_station_bank_texture` | the stroked hexagon (`Atm`) | ↑ | ↑ | No |
| `minimap_station_heal_texture` | the stroked cross (`Healer`) | ↑ | ↑ | No |
| `minimap_station_train_texture` | the stroked inverted triangle (`LevelUp` / `PerkStation` / `RespecStation`) | ↑ | ↑ | No |
| `minimap_station_tech_texture` | the stroked square (`ChipInstaller`) | ↑ | ↑ | No |
| `minimap_station_leisure_texture` | the stroked circle (`Bonfire` / `ChessMatch`) | ↑ | ↑ | No |
| `minimap_station_exit_texture` | the stroked chevron (`LevelDoor`) | ↑ | `minimap_exit_color` — picked out of the family on purpose | No |

Three rules worth knowing before you draw:

- **The seven station slots are an ALPHABET.** A player reads *which kind of place* off the shape at ~5 px. Filling only `minimap_station_texture` and leaving the seven empty collapses them all to one badge — that is a legitimate art direction, and it is the honest way to say it. Filling all seven with the same image is the same thing said dishonestly.
- **An art slot bypasses the trainer's upside-down flip.** That inversion exists only so a stroked triangle can never be mistaken for the filled hostile caret; draw a trainer badge that is already unmistakable and the flip stops mattering.
- **A per-level `MapData` still wins.** `MapData.player_marker` / `npc_marker` override the caret and POI slots for the one level that authors them, so a set-piece can differ from the global look.

**There is deliberately no slot for the body glyphs** (hostile caret, ally diamond, friendly dot, neutral ring), **the alert ring, the floor tick or the north tick.** Those are 2–4 px marks whose meaning *is* their shape — the accessibility channel this project chose over hue precisely because hue fails at that size and swaps under **Colorblind-Safe Cues**. Art there buys a smudge and costs the alphabet. **Backdrops and frames are not here either**: they are whole-box layers and belong in the scene's `%MapUnder` / `%MapOver` slots (§"The minimap is a scene").

---

## In-game debug tools (console, cheat menu, noclip, inspector, logs)

`scenes/game.tscn` ships seven debug drop-ins as siblings of `GameRoot`/`Player` (so they survive every level
swap). **All of them gate on `OS.is_debug_build()`** — an exported release build never even constructs their UI —
and each has a `force_in_release` export to override that for a playtest build. Every toggle is a **raw dev key**
(`toggle_key` export), deliberately not a rebindable `InputManager` action.

| Key | Tool | What it does |
|-----|------|--------------|
| **`** (backtick) | `DebugConsole` | Typed commands with Tab completion and history — **86 commands**. `help` lists them by category; `help <cmd>` shows usage; `keys` lists the dev keys live. Runs `user://autoexec.cfg` at boot; `exec <file>` replays a command file; `bind F6 "god; noclip on"` binds a dev key. Mirrors its transcript to `print()` (Output dock / `user://logs/godot.log`). |
| **F1** | `DebugMenu` | The same commands as clickable pages — buttons, `< value >` cyclers and inline fields, plus a `find` bar that filters all of them at once (matches help text too; Escape clears it). Destructive rows need a second confirming click. |
| **F2** | `DebugNoclip` | Fly the real player body with no collision/gravity (camera basis + `forward/backward/left/right`, `jump` up, `Crouch` down, `Run` boost). The real camera stays, so the ink outline and view-model render correctly. |
| **F3** | `DebugOverlay` | Perf HUD + rolling graphs + a live game-state block (HP/stamina/wallet/bank/position/clock/level/disk-writes), a STEALTH block (light / carried-light / noise / awareness census), and an INPUT/MODAL line (cursor mode, pause, suppression, open modals). Shouts **SANDBOX SAVES ON** while the save sandbox is armed. |
| **F4** | `DebugInspector` | Aim at an NPC: hp / disposition / GOAP goal+action / perception / nav state drawn in the world beside it. Feeds `who`, `brain` and every `npc <verb>`. |
| — | `AiEventLog` | Records every NPC state flip (perception / target / goal / action / provoke / flee / freeze / stranded / spawn+free) into a session ring; `ailog [n] [filter]` dumps it, `ailog on` shows a last-N panel. |
| — | `DebugEventTicker` | A fading top-right column of game events (quest / reputation / clock phase / rent / dialogue / money+xp / effects / death / level / save); `events [n] [filter]` dumps the ring, `events on|off` toggles the column. |

**The command families** (every one is `help <name>`-documented in-game):

- *Player*: `god heal hurt [part] cripple kill revive noclip speed stamina tp tpaim mark [name] back goto marks pos stat stats me ability`
- *Economy*: `money bank credit xp sp level perk perks respec give weapon ammo items effect effects cleareffects rep reps`
- *World*: `time advance clock timescale warp levels reload save load sandbox roundtrip`
- *AI*: `spawn npcs killall peace aggro freezeai notarget who brain npc <verb> ailog soak resurrect`
- *Story*: `flag flags quest (start|complete|fail|show|advance) quests notify ledger wipeobjects names`
- *View*: `inspect navdebug perf wireframe overdraw unshaded screenshot [clean] hud quantize dither dof sway lens`
- *Meta*: `help clear keys exec bind errors events saves`

Things worth knowing before you lean on them:

- **The console and the menu suspend the player while open** (mouse-look, movement *and* the trigger — a click on
  a panel must not fire the gun) and free the cursor; closing restores exactly what was found. Opening one closes
  the other, so only one ever holds the player.
- **`sandbox on` is the way to cheat safely.** It redirects the five save files (autosave, quicksave, slots) into
  `user://sandbox/` for the session; `sandbox off` reloads the real profile, `sandbox commit` copies the sandbox
  over it. Without it, money / XP / item / flag / quest commands all ride the game's own autosave paths and write
  your **real** save. The sandbox is session-only — a crash or relaunch boots the real profile.
- **`time` SEEKS, `advance` WALKS.** `time 18:00` jumps the clock silently — no rent, no interest, no dawn events.
  `advance 24` fires every boundary it crosses, exactly as if you had waited. They are different on purpose.
- **`notarget` vs `freezeai`.** `notarget` makes you invisible to every NPC while the AI keeps running (the way to
  stand beside a raider and watch its idle brain); `freezeai` suspends perception, GOAP and locomotion outright.
- **`brain`** prints, for the NPC under the crosshair, every GOAP goal's priority / satisfied? / plan cost, the goal
  the planner *would* pick now, and the plan the executor is *actually* stepping — they can legitimately differ.
- **`lens <barrel> [chroma]` is the FISHEYE dial.** `post_process.gdshader` bends the screen fetch radially, so the
  centre of the frame is magnified and the periphery squeezed and straight lines off the centre bow outward.
  - ⭐ **The number is centre magnification minus one**: `0.12` (the shipped default) = the middle reads ~12%
    bigger. The bend is normalised by the corner and divided by its own value there, which **pins the corners** —
    so it can never show a black edge at any strength, and `SCREEN_TEXTURE` (a `repeat_disable` sampler) is never
    fetched past its edge. Displacement is therefore zero at the centre AND zero at the corner, peaking a third of
    the way out; do not expect a whole-frame difference when you measure it.
  - ⭐ **No Camera3D property can do this.** FOV is a *uniform* scale on the projected image (`h / (2 d tan(fov/2))`
    — for any two points the tan term cancels), so no field-of-view number bends a straight line; it only changes
    how much you can see. The bend has to happen after projection, which is why it lives in the post-process and
    not on the camera.
  - ⭐ **The command writes the SOURCE, not the material.** `player.gd` re-pushes `lens_barrel` every frame from
    `GameSettings.camera.lens_barrel_amount x Settings.lens_curve`, so a direct `set_shader_parameter` would be
    stomped on the next frame — the same coupling `dither`'s strength half documents. `lens` therefore writes the
    tuning resource, which means an override lasts the whole **process** (surviving death, respawn and level
    changes, like `dof`) but never touches disk. Commit a value in `resources/tuning/CameraSettings.tres`.
  - **The player's slider can veto it**: Options → Accessibility → "Lens Curve" multiplies the amount, so at 0 the
    frame is flat whatever you type. The command's report always prints amount, scale and the product.
  - **The HUD does not bend with it.** The post-process ColorRect and the HUD share one CanvasLayer, but the HUD
    draws *above* this shader. The crosshair sits at the centre, which is the one point a radial warp never moves —
    but a *world-projected* annotation (the enemy health bar, a world marker) is drawn flat over a bent picture, so
    it drifts from its subject toward the periphery. Match the feel with the HUD's own "HUD Curve" row if you want
    the panel to bow too.
- **`dof` and `sway` are the LENS dials** — the two knobs for "close things closer, far things farther", live, so a
  value gets picked in-game instead of guessed. Both are in-memory only and never write `settings.cfg`.
  - **`dof near <m> [transition]` is the whole effect; `dof amount` almost isn't.** Measured on the shipped level
    with the windowed probe below, `near 1.0` changes ~16% of the frame and `amount 0.10 → 0.18` changes ~1.5%.
    `amount` only strengthens blur that already *exists*, and the far field it would act on is already ~78%
    swallowed by volumetric fog at the 30 m onset (the command prints that fog figure for the live level, so you
    can see when a far-side change has nothing left to do). Turn `near` on first.
  - ⭐ **The near blur was authored and never switched on.** `scenes/player/camera_rig.tscn` writes
    `dof_blur_near_distance = 0.5` and never wrote `dof_blur_near_enabled` at all — the same dead-knob shape as
    `auto_exposure_max_sensitivity = 400.0` on the next line with `auto_exposure_enabled` absent. And Godot's near
    ramp runs *toward the lens* (sharp AT the distance, full at `distance - transition`), so the authored 0.5
    against the default 1.0 transition would have put full blur behind the camera anyway. `dof near` auto-sizes
    the transition and warns when a ramp cannot land.
  - **What makes it a depth cue rather than a soft frame: the view model is immune by construction.** The weapon
    and the carry-hands render through `ViewModelCamera`'s own `Camera3D`, built with NO `CameraAttributes` on
    purpose — so the world's near field softens while what is in your hands stays sharp.
  - ⭐ **`dof far` also writes `CameraEffects._dof_default_far_distance`**, because `set_scope_dof()` restores that
    snapshot on every unscope and would otherwise silently undo your value the first time you aimed. The far
    *enabled* flag cannot be held down at all (unscope forces it true), so `dof off` and `dof far 0` last only
    until the next aim — push the blur out with `dof far 400` instead.
  - ⭐ **The two have OPPOSITE lifetimes, and it surprises people.** A `dof` override survives death, respawn and
    level changes (`CameraAttributesPractical` is a shared sub-resource of the cached `camera_rig.tscn`, the same
    trap as `dither`'s grid) and clears only on a process restart or `dof reset`. A `sway` override survives none
    of them — `GunMesh` builds a fresh `GunPose` with `.new()` each time, on the script defaults.
  - ⭐ **Mouse sway sits OUTSIDE every accessibility gate.** `Settings.view_bob_enabled` reaches only GunPose's
    walk-bob; the mouse-sway decay and its four offset terms run unconditionally, and `fov_effects_enabled` never
    reaches GunPose. Survivable at the shipped 14 mm. **Add the gate in `gun_pose.gd` before committing a raised
    value** — `sway preset 1` is 38 mm, and rotation-linked view-model motion provokes more than bob does.
  - **Verify with a real windowed run**, never headless: `godot --path . res://scripts/tools/__lens_probe.tscn --
    --shots-dir="C:/some/dir"`. It drives both commands through the same entry point the console uses, sweeps the
    near distance, and gates on a *measurement* (blur lowers the frame's mean gradient). ⭐ Every comparison is an
    adjacent pair, never against a stored baseline: the day/night cycle moves the sun between shots and the HUD
    re-shows itself past any hide, so an absolute baseline reported `dof reset` as broken when it was not.
- **`spawn` marks NPCs as dynamic** so they never pollute the save's death ledger, and caps the count per call.
  `resurrect` and `wipeobjects` re-load the level in place; `roundtrip` and `load` reload the scene.
- **Reloads unwind every shared-tuning override** (`speed`, `god`'s fall-death timer, `timescale`) — the console
  releases them in `_exit_tree`, so a death reload never leaves the session at 3× speed.
- **Adding a command** is one row in `scripts/components/debug_commands.gd` (the pure registry both surfaces
  build from) plus a `match` case in `debug_actions_player.gd` or `debug_actions_world.gd`. A GUT test pins the
  pairing, so a row without a case fails the suite instead of shipping a dead command.

---

## Diagnosing AI & navigation — the debug overlay (`NavDebugOverlay`)

When an NPC misbehaves — stares the wrong way, never spots you, walks off a cliff, picks a weird plan, or trips a
trigger you can't see — you don't have to read logs. Drop **`NavDebugOverlay`** into the level (it's a drop-in in the
CYBER SUNDAY component list: add a plain `Node`, attach `res://scripts/components/nav_debug_overlay.gd`, or grab it
from the Place/component browser) and switch on the layers you need. It's **debug-friendly and ships fully inert** —
the master `enabled` defaults **off**, so leaving one in a scene costs nothing until you turn it on, and it never
touches gameplay (read-only). Flipping `enabled` on lights up the two Navigation layers immediately (`show_navmesh`
and `agent_paths` both default **on**); the four AI Diagnostics layers default off and are opted into one at a time.

**Turning it on.** `enabled` is the master switch. Flip it in the inspector, bind `toggle_action` to an Input action
for an in-game hotkey, or call `toggle()`. While playing you can flip any individual layer live via the **remote
inspector** (Scene tree → the overlay node → tick a checkbox) — that's the zero-setup path. If you'd rather have
in-game hotkeys per layer, bind the optional actions under **AI Toggle Actions** (add them to the Input Map first).
This is *dev tooling*, so its toggles live on the node / dev keys, **not** in the player-facing Options menu.

**The layers** (all gated by `enabled`):

| Group | Toggle | Shows |
|---|---|---|
| Navigation | `show_navmesh` | Godot's green walkable navmesh polygons (on by default). |
| Navigation | `agent_paths` | Each NPC's current `NavigationAgent3D` path line (on by default). |
| AI Diagnostics | `show_sight_cones` | Every live NPC's Perception view-cone (`fov_degrees` × `sight_range`) as a flat fan at eye height, pointing where it's actually looking. |
| AI Diagnostics | `show_faction_colors` | A ground ring under each NPC coloured by its attitude toward the player. |
| AI Diagnostics | `show_goap_labels` | A floating "goal / action" label above each NPC's head (the plan its GOAP brain is running right now, e.g. `combat / fire_armed`, or `idle / -`). |
| AI Diagnostics | `show_trigger_zones` | The extents of every `TriggerVolume` / `HazardZone` / `AudioZone` / `ShadowVolume` as a wireframe — the runtime twin of their editor gizmos. |

**Colour legend.**
- *Sight cones* (with `color_cone_by_alertness` on, the default) tint by awareness: **green** = unaware, **orange** =
  detecting (meter filling), **red** = alerted (locked on), **yellow** = investigating a last-known spot. Turn that
  off for a flat `sight_cone_color`.
- *Faction rings* reuse the same palette as the NPC outlines/name cues (and honour the colorblind-safe Options
  toggle): **red** hostile, **green** friendly, **blue** a recruited companion, and `faction_neutral_color`
  (**yellow** by default) for neutral.
- *Zones* are **cyan**, except `HazardZone` which is **orange-red** so a damaging volume stands out.

By default the lines and labels draw **through walls** (`draw_through_walls`) so you can see a cone or zone behind
geometry; turn it off to depth-test them. Pairs with **File → Run `scripts/tools/audit_navmesh.gd`** (§2): the audit
tells you *which* polys are bad, this overlay shows you the NPCs hitting them live.

---

## Troubleshooting (symptom → fix)

A symptom-indexed entry point into the per-chapter gotchas. Find the row that matches what you're seeing; the fix and the chapter with the full detail are on the right.

| Symptom | Likely cause → fix | See |
|---|---|---|
| A new field / script / dropdown doesn't appear in the inspector | The editor hasn't re-scanned -- it must reload before new `@export`s / `class_name`s show. Refocus the editor or reopen the scene. | §1 |
| My inspector edit is ignored at runtime | Three usual culprits: an `NpcData` **profile** stamps over inline NPC fields; the value is owned by **`Settings`/Options**, not `GameSettings` (it overwrites on boot); or **StarSky** re-pins the `WorldEnvironment`. | §5, §12, §2 |
| NPC won't walk / find a path | Its geometry isn't in the `navmesh` group, or the nav mesh wasn't re-baked after props changed. | §2 |
| The level has nothing to control | A level scene has no `Player` -- play through `game.tscn` (or your own Game wrapper). | §2 |
| A new audio / comfort / sensitivity option isn't in the Options menu | A `.tres` value alone never reaches Options -- it needs a `Settings.gd` `var`+setter **and** a `SettingSpec` catalog row. | §12 |
| A stealth feature does nothing | The shipped `NpcAiSettings.tres` turns every `npc_ai` stealth flag ON (the script defaults alone are off) -- so check the per-NPC `hearing` master gate first, then whether a level/test cleared the `.tres` override. | §19 |
| Two NPCs won't fight / an NPC ignores my faction | NPC-vs-NPC needs **both** factioned with a relation `< 0`; the `faction_id` filename is load-bearing. | §7 |
| Dialogue has no Trade / Heal / Rest / Follow option | The speaker needs the matching child component (`Merchant` / `Healer` / `Bonfire` / companion flag). | §13 |
| The radio is silent | It needs a pinned `track`, a `music_folder`, **or** a `fallback_audio`, and its player must sit on the `radio` bus (which sends into `music`). | §15 |
| An item didn't survive a save | An item with no `Item.id` can't persist -- register it under `res://resources/items/`. | §24 |
| Pressing E does nothing on a prop | Its interaction hitbox is too small, or it isn't a `LookAtInteractable`. | §11 |
| I turned a sound's `volume_db` down in the Inspector and it made no difference | ⭐The project authors most `AudioStreamPlayer3D` nodes at **`volume_db` 80** (`WalkingSFX`, weapon.tscn, enemy.tscn, the impact nodes). A 3D player outputs `min(volume_db + distance attenuation, max_db)`, and attenuation is POSITIVE inside `unit_size` — so at 80 dB the sum is pinned to `max_db` (default 3.0) at every playable range and `volume_db` is a **dead knob**. Move `max_db`, or use the seam that carries both: `AudioManager.play_sfx(..., max_db)`, `Landing.step_db`, `GameSettings.audio.footstep_volume_db` / `npc_impact_volume_db`. | §15 |
| A world sound I added replays byte-identically every time | Node-driven SFX only vary if the site plays them through **`AudioManager.play_varied(player)`** instead of `player.play()`. One-shots spawned via `AudioManager.play_sfx` / `play_2d_sfx` already vary with no opt-in. Check `GameSettings.audio.global_pitch_spread` isn't 0. | §15 |
| A menu blip / alert sting / reward jingle wobbles in pitch | It is being played as a WORLD sound. Non-diegetic one-shots must pass `vary = false` to `play_sfx` / `play_2d_sfx`; menu cues must go through `MenuStyle`, never `AudioManager`. | §15 |
| My dog's yap sounds wildly different each time | `global_pitch_spread` is too high. It multiplies around the creature's **Sound Pitch Mult** (its rolled body size), so at `0.15` the size still reads clearly; at `0.4` it would not. | §15 |
| A wounded NPC sounds like a stuck sample under automatic fire | The hurt cry (`scripts/npc/damage.gd`) fires once per damage tick, so it must go through `AudioManager.play_varied`. A bare `play()` there retriggers one identical yell many times a second. | §15 |
| Every sound in the game sounds detuned | `GameSettings.audio.global_pitch_spread` is too high. `0.15` matches this project's own impact spread; well past `0.35` (blood-drop territory) clips read as out of tune. `0.0` turns the whole effect off. | §15 |
| I can't hear ANY variation | Almost certainly the spread is too small — `0.04` is inaudible on short percussive clips. Compare against the hand-rolled spreads (footsteps `0.08`, impacts `~0.17`, landing `0.25`) and raise it. Also confirm you restarted the game: the editor caches compiled scripts, so an already-running instance keeps the old value. | §15 |
| My looping ambience / music re-tunes itself every lap | Something is playing a **bed** through `AudioManager.play_varied` (or `play_sfx`). Loops re-trigger on `finished`, so each lap re-rolls the pitch — beds must call `player.play()` directly. | §15 |
| The player's footsteps sound like one sample machine-gunned | `Landing.footstep_sounds` is empty or down to a single clip, or `GameSettings.audio.footstep_pitch_spread` is 0. The player has no `LocomotionFx` (see §15) so it does not inherit that component's variety -- it gets its own clip set + pitch wobble, and both have to be populated. | §15 |
| Footsteps doubled on an NPC | TWO `LocomotionFx` under one NPC. An NPC auto-builds one ONLY if none is already there, so a single hand-dropped (configured) `LocomotionFx` suppresses the auto-build and is the supported way to tune footsteps -- delete the duplicate, not the configured one. | §15 |
| NPCs never go back to their posts after a chase / after I die | The leash is `NpcHomeReturn` (auto-built, ships on). Check `GameSettings.npc_ai.home_return*`; note the blink is **refused while you can see the NPC or its post**, and by default the off-screen clock only runs while the NPC is calm (`home_return_requires_calm`). | §5 |
| Enemies keep the damage I did to them across my deaths (the boss gets easier every attempt) | The full heal is `home_return_heal_on_player_death` (auto-built, ships **on**) — check it, and the master `home_return` / per-NPC `enabled` above it, since the heal rides the same component. It only tops up **survivors**: an NPC you killed stays dead. | §5 |
| An NPC disengages and heads home mid-fight when I break line of sight | `home_return_requires_calm` (or the per-NPC `off_screen_requires_calm`) is off -- that's the hard-leash mode. Turn it back on, or raise `off_screen_delay`. (It can only *walk* back in that state; an aggro'd NPC never teleports.) | §5 |
| The detection readout never changes | The text readout shows while **crouched** OR when an enemy has noticed you (the optional heat **bar** shows only while crouched); if nothing changes at all, stealth detection tuning may be at defaults. | §19 |
| I can't tell what an NPC sees / is planning, or where a trigger zone is | Drop in **`NavDebugOverlay`** and switch on sight cones / faction colours / GOAP labels / trigger zones — the runtime AI debug overlay. | Diagnosing AI |

---

## Glossary

The project's coined terms, defined once.

| Term | Meaning |
|---|---|
| **Zorkmids** | The in-game currency (fractional -- `0.5` is half a zorkmid). |
| **Bark** | A short, context-triggered spoken line ("Contact!", "I'm hit!") -- distinct from scripted dialogue. (§21) |
| **Drop-in component** | A `class_name` Node/Area3D with `@export` config you attach in a scene to add behaviour without code (the `LookAtInteractable` / `Ability` idiom). (§11) |
| **The three authoring surfaces** | Behaviour = a drop-in component; numbers = an `@export` or a `GameSettings` tuning `.tres`; content = an authored Resource. (§1) |
| **Profile / archetype** | An `NpcData` resource that stamps ~50 tuning fields onto an NPC at spawn, so one assignment makes a raider / townsperson. (§5) |
| **GOAP** | Goal-Oriented Action Planning -- the NPC brain. Each tick it pursues the highest-priority **goal** it can and plans the cheapest **actions** to reach it. (§20) |
| **Disposition** | How an NPC feels toward the player -- HOSTILE / NEUTRAL / FRIENDLY -- resolved from faction + reputation. (§7) |
| **`faction_id`** | The faction a `.tres` filename keys; it drives NPC-vs-NPC and NPC-vs-player attitude. The filename is load-bearing. (§7) |
| **Look-at interactable** | The `LookAtInteractable` family -- a prop you aim at and press Interact (F) to use. (§11) |
| **Standalone vs data-only** | A service component (Merchant / Healer / …) that works on its own (`standalone`) vs. one that only supplies a dialogue option. (§13) |
| **Caliber** | A weapon's ammo type; ammo reserves connect to it. (§10) |
| **Footprint** | An item's grid size (`grid_width` × `grid_height`) in the Tetris backpack. (§9) |
| **Inert-by-default** | A shipped feature whose defaults keep the system inactive until you opt in -- e.g. `SearchSettings.sample_points` at `1` and `WeaponData.backstab_multiplier` at `1.0`. (The stealth layer itself now ships ON in `NpcAiSettings.tres`.) (§19) |
| **Located / cripple damage** | A hit sorted into a body zone (head / torso / arms / legs); draining a zone's pool cripples that limb. (§23) |
| **Awareness states** | An enemy's `Perception` states. It ESCALATES UNAWARE → DETECTING (meter filling) → ALERTED (locked on), and DROPS to INVESTIGATING to search your last-known spot when it loses you (a heard noise also enters INVESTIGATING straight from UNAWARE; re-sighting there returns to DETECTING, never straight to ALERTED). Surfaced to the player as the detection readout. (§19) |
| **`GameSettings` vs `Settings`** | `GameSettings` = the designer's master tuning sheet; `Settings` = the player-overridable slice persisted to disk. (§12) |

---


### When two fields define the same thing (precedence)

Some systems let you author the same thing in more than one place. The inspector now **config-warns** on the common conflicts (Node hosts); a few resource-only cases can't warn, so they're listed here too. Who wins:

| Concept | Sources | Who wins |
| --- | --- | --- |
| Container / NPC items | `item_stacks` + `loot_table` (on top) | both SEED into contents; `loot_table` adds random extras |
| NPC faction | `faction_id` (dropdown) + `faction` (resource) | `faction_id` WINS, replaces the slot |
| NPC attitude | `faction` + `disposition` + `disposition_overrides_faction` | faction + reputation, UNLESS the override bool is on (then `disposition`); a provoke always -> HOSTILE |
| NPC archetype | `profile` (NpcData) + the NPC's inline fields | `profile` OVERWRITES inline, unless `profile_fills_blanks_only` is on |
| NPC death loot | inline `loot` + `profile.loot` | `profile` wins whenever a profile is set (even if its loot is empty) |
| NPC appearance | `look` (NpcLook) / BodyModelSwap's own fields | `look` overrides BodyModelSwap's own fields, per part (model/scale/pos/rot/tex/colour) |
| Spawned NPC | SpawnDefinition `profile` + `faction_override` / `weapon_override` | `profile` wins (overrides apply only with NO profile) |
| Which level loads | saved `GameState.current_level_path` + GameRoot `level` (LevelData) + any child named `Level` | loaded saves prefer the saved LevelData path; fresh games use `GameRoot.level`; loading a LevelData FREES & replaces a child named exactly `Level`; OTHER world geometry loads on top |
| Level music / ambience | LevelData `music`/`ambience` + the Player/Music node's autoplay stream | the LevelData wins (re-plays its stream) |
| Player loadout | SwapWeapons `weapon_slots` + a `Loadout` | the Loadout's weapons replace `weapon_slots` IF non-empty; its money/clips ALWAYS override |
| Player start pose | the Player node's transform + a `PlayerSpawn` + a saved respawn | saved respawn > PlayerSpawn > authored transform |

Rule of thumb: a **resource / profile / data slot** usually wins over an inline field, and a **dropdown id** wins over a dragged-in resource. When in doubt, fill ONE source — the inspector flags the rest.
## Quick reference

A map of WHERE each kind of content lives. All paths are `res://` (the project root is `rpg/`). For each, you author a `.tres` in the inspector (right-click the folder → **New Resource** → pick the listed type) or drop the named component node into your scene. The fastest way to seed any of these correctly is the plugin's **Content** tab (§ Editor dev-tools) — one button per type writes a seeded `.tres` into the right folder and opens it; **Browse** finds an existing one.

**The folder CONVENTION.** Content resources keep their `class_name` script under `res://scripts/<subsystem>/` (e.g. `scripts/combat/weapon_data.gd`) and their authored `.tres` under `res://resources/<domain>/` (e.g. `resources/weapons/`) — one folder per kind. **Global tuning is the exception**: each tuning group co-locates its `*.gd` class beside its `*.tres` instance in `res://resources/tuning/` (e.g. `EconomySettings.gd` + `EconomySettings.tres`), and all are registered on the `GameSettings` autoload (§12). Stick to the canonical folder for a type so the dropdowns, the plugin's Browse/Content tabs, and any folder-scanning validators find it.

### Where each content type lives

| Content type | Folder | Resource / `class_name` | Backing script | Notes |
|---|---|---|---|---|
| **Factions** | `res://resources/factions/` | `Faction` | `res://scripts/faction/faction.gd` | One `.tres` per faction. Resolved by `Factions` (`res://scripts/faction/factions.gd`) on the **filename** — see gotchas. |
| **Dialogue** | `res://resources/dialogue/` | `DialogueResource` (with sub-resources `DialogueLine`, `DialogueChoice`) | `res://scripts/dialogue/dialogue_resource.gd`, `dialogue_line.gd`, `dialogue_choice.gd` | Voice lines pair with a `VoiceData` `.tres` (e.g. `old_man_voice.tres`, `res://scripts/dialogue/...`). Attach to a `DialogueNPC` / `Talkable` node in-scene. |
| **Items** | `res://resources/items/` | `Item` | `res://scripts/items/item.gd` | Ammo, consumables, weapon-items. A weapon-item (`pistol_item.tres`) holds a sub-`ext_resource` pointing at the matching `WeaponData`. Registered at runtime by the `ItemDb` autoload (`res://scripts/items/item_db.gd`). |
| **Weapons** | `res://resources/weapons/` | `WeaponData` | `res://scripts/combat/weapon_data.gd` | The stats/feel/audio of a gun. Threw-/throwable weapons use `ThrowableData` (`res://scripts/...`). |
| **Loot tables** | `res://resources/loot/` | `LootTable` (+ sub `LootEntry`) | `res://scripts/items/loot_table.gd` | Weighted item-drop list (each entry: item, chance, min/max). Assign to `NpcData.loot`, a container, or `SpawnOnDestroy.loot_table`. Inspector add-in has a **Roll 1000×** test (§ Editor dev-tools). |
| **NPC barks** | `res://resources/barks/` | `BarkSet` | `res://scripts/npc/bark_set.gd` | Per-archetype spoken lines (combat / social / death / aggression / music). Assign to `NpcData.bark_set`; empty categories fall back to the built-in pools / `default_barks.tres` — ALL of which ship EMPTY (the AI-text scrub), so unauthored barks are silent. LINES only — cadence is `GameSettings.npc_bark` (§12, §21). |
| **NPC archetypes** | `res://resources/characters/` | `NpcData` | `res://scripts/npc/npc_data.gd` | e.g. `raider.tres`, `sniper.tres`, `Townsperson.tres`, `DefaultCharacterRes.tres`. References a `Faction`, a `CharacterStats` (`res://scripts/.../character_stats.gd`), a `WeaponData`, and starting `Item`s. Drives an `NPC` / `Enemy` node. |
| **Character stats** | `res://resources/characters/` | `CharacterStats` | `res://scripts/...` (`class_name CharacterStats`) | Shared stat block referenced by `NpcData.stats`. |
| **Global tuning** | `res://resources/tuning/` | One `*Settings` resource per group (`EconomySettings`, `NpcAiSettings`, `CameraSettings`, `BunnyhopSettings`, `AudioSettings`, `DistractionSettings`, …) | co-located `*.gd` beside each `.tres` (e.g. `EconomySettings.gd`) | Registered on the **`GameSettings`** autoload (`res://managers/GameSettings.gd`). Code reads `GameSettings.<group>.<field>` (e.g. `GameSettings.economy.…`, `GameSettings.npc_ai.…`). |
| **Sky / shaders** | `res://resources/shaders/` | `.gdshader` files (`horizon_sky.gdshader`, `starry_sky.gdshader`, `film_grain.gdshader`, `outline.gdshader`, `ink_outline.gdshader`, `ps1.gdshader`, `post_process.gdshader`, …) | n/a (shader code) | The moody sky is applied non-destructively by the **`StarSky`** autoload (`res://scripts/effects/star_sky.gd`), which preloads `horizon_sky.gdshader`. The PS1 vertex/texture warp (`ps1.gdshader`) is applied non-destructively and AUTOMATICALLY to every level by the **`Ps1Warp`** autoload (`res://scripts/effects/ps1_warp.gd`): `GameRoot.load_level` calls `Ps1Warp.cover(level_root)` on every load and it parents ONE `res://scripts/effects/ps1_applier.gd` Node under the `LevelRoot`, so you never add it to a level by hand. Only a NON-level scene that still wants the warp (e.g. `scenes/computerroom.tscn`) gets that script attached to a plain `Node` directly — it has no `class_name`, so attach it by path. Its strength is scaled LIVE by the **Options → Accessibility → "Vertex Warp (PS1)"** slider (0% = normal render, 100% = full authored warp). The shader's affine *texture*-warp half (`affine_amount`) ships **OFF** (default 0 on `ps1_applier.gd`) — on brush-scale triangles the swim smears textures into an ugly stretch — so the automatic look is vertex wobble with perspective-correct textures; opt in per instance on a hand-placed applier if you want the texture melt too. Three hard-won tuning rules: **don't lower `vertex_snap` below its 396 default casually** — the func_godot brush mesh is unwelded, every seam can tear open by one snap cell, and a coarse grid (the old 80) holes buildings through to the sky (396 = one cell per texel of the real 792-wide screen buffer = tears read as pixel crawl); the shader deliberately **skips snapping in the shadow pass** (`IN_SHADOW_PASS`) because a snapped shadow map strobes every lit surface; and the snap **fades in under ~1.5 m and out over 20–40 m** (`snap_near_fade_*` / `snap_far_fade_*` on the applier) because distant buildings sit on coplanar flush brush faces that z-fight — per-frame jitter re-randomizes the winner and whole walls flash (the real cure is separating the overlapping brushes in TrenchBroom; the fade just stops the warp from animating the fight) — while the near fade holds point-blank walls and the floor underfoot still. Related: `stabilize_floor_surfaces` now ships **OFF** — freezing floor surfaces while their adjoining walls warp tore a flickering seam along every stair-step and wall-base contact line; opt it back in per level only if the ground feels swimmy. <br><br>**The Borderlands black ink outline (`ink_outline.gdshader` + `res://scripts/effects/ink_outline.gd`) is the OTHER outline — don't confuse it with `outline.gdshader`.** `outline.gdshader` is the inverted hull, and it stays what it is: a *gameplay* rim, per-mesh and colour-coded (white = hovered `Throwable`, blue = yours, black = an enemy `NPC`), always built through `TalkHelpers.make_outline_material()`. `ink_outline.gdshader` is the *art style*: one screen-space depth + normal edge detect that inks the **world**. Nothing is authored on an object to receive it — it is a `MeshInstance3D` with the `InkOutline` script childed to the **camera** (already wired into `scenes/player/camera_rig.tscn` as `ScreenShake/Camera3D/InkOutline`), and it inks whatever that camera renders **except the actors**: NPCs, props and the view model keep their hull rims and are excluded per-pixel via the `ACTOR_INK_MASK_LAYER` render-layer stamp the overlay walks apply automatically (an un-excluded actor's own opaque body is a depth edge, so the ink draws a line straddling its silhouette that lands half on the hull rim and half on the world — a doubled outline; the hull IS their outline, the ink never touches them). A hand-built actor-like object gets the same treatment by OR-ing `InkOutline.ACTOR_INK_MASK_LAYER` onto its meshes' `layers` — but **on an ACTOR, OR the bit only if the thing already wears a hull rim**: the two are one contract, and stamping the mask onto a body with no rim leaves it with no outline at all rather than fixing a double. That is the lesson of the player's own first-person body, which had *neither* until 2026-08-15 (`Character`'s walk is scoped to `mesh`, and the Player's `mesh` is the `GunMesh`, so the `FirstPersonLegs` rig was never reached by any walk) and so wore the *world's* ink line while every NPC beside it wore a rim. A **`BodyModelSwap`** rig gets both halves from one switch — tick **`actor_outline`** (with `actor_outline_color` / `actor_outline_width`) and it stamps rim + mask on every part and re-stamps them on every rebuild; leave it OFF on NPCs, whose rim belongs to `NpcOutline`'s disposition colouring. **A VFX mesh is the deliberate exception to the rim-plus-stamp rule — read the layer as "the ink does not own this pixel", not as "this is an actor".** `ExplosionMesh` (the flash on every explosion, bullet-impact spark, paint pop and muzzle flash) stamps the bit in its own `_ready`, unconditionally and with no rim required: it is an OPAQUE emissive sphere, so until 2026-08-16 it wrote depth like a wall and the ink ringed every blast in black, and a blast is meant to read as *light* — it owes the world no silhouette. Nothing else could have covered it, either: an `Explosion` is spawned under the scene root, outside every overlay walk. Its **`has_outline`** export is then its only line: leave it **off** for a blast (no outline at all, which is the right answer for light and never the right answer for a body) or tick it for the muzzle flash's thicker inverted-hull rim. **Masked actors only suppress ink where they can actually be SEEN** — the mask carries a depth channel (`actor_mask_resolve.gdshader`) and the ink pass compares it against what the main camera draws, so somebody standing behind a wall no longer bites a person-shaped hole out of the lines in front of them (that read as sensing people through walls, and it hit props and gibs as much as NPCs). Three knobs, all under **Actor occlusion** and all live: `occlusion_aware_mask` (the A/B — off restores the old always-suppress behaviour), `mask_occlusion_bias` (how much nearer the world has to be, as a fraction of the distance, before an actor counts as hidden — lower catches thinner cover, higher is safer near walls), and `mask_rim_search_px` (**keep it >= the widest `outline_width` you author, x4** — the hull rim writes no depth, so the ink pass has to search outward for the body's; fall short and a hidden actor punches an O-shaped ring instead of nothing at all. A GUT test pins it). A/B a real frame with `scripts/tools/__ink_occlusion_shots.gd`, which also shoots a reference frame with the hidden actor off the mask entirely — the occlusion-on shot should match it pixel for pixel. A/B the seam merge and the junction dial with `scripts/tools/__ink_seam_shots.gd` (a synthetic row of every join a box level is made of — flush, overlap, gap, 2 cm step, slab-on-slab, pilaster, chamfer, ramp — shot at each setting; `--cam=B` for the tight view that shows the step sliver). To tune, press play and edit the node in the **Remote** inspector — every knob is live: `width_px` (thickness, in pixels of the 1584-wide 3D buffer, so 2.0 ≈ one visible pixel and the shipped 3.0 ≈ one and a half — 2.0 reads as a tasteful technical edge, which is not what Borderlands ink is), `crease_strength` (0 = bare silhouettes; higher adds the interior lines at wall corners, floor/wall junctions and prop facets), `crease_threshold` (raise it if curved/low-poly surfaces start growing grime lines), `crease_min_feature_px` (**the seam merge**, ships `4`, `0` = off — level geometry built from several boxes should ink as ONE solid, not as its parts, and it mostly already did: a flush or interpenetrating join has no depth step and no normal change (measured on a synthetic scene and on the shipped map's flush floor/roof brush joins). What broke it is a piece a couple of *centimetres* out of line — a sub-pixel sliver of perpendicular face along the join, invisible in the art but a full corner to the crease term, so one surface came out split by a faint dotted line that crawls with the camera; on the shipped map that is the 6 cm plank trims over the yard doors seen edge-on (470 px of dashed line, all gone at the default) and a 4 mm decal-plate brush on the tower. The crease is now re-measured on two wider crosses whose taps sit **this many pixels of the 3D buffer** either side (two crosses, the weaker wins, as a *ratio* of the narrow result so shallow creases like a ramp meeting the floor are not dimmed) and can only be *reduced* by it — so a face narrower than this on screen cannot hold a tap and its creases merge into the surface around it, while every corner wide enough to be a corner keeps its line. Screen-space on purpose — a 4 cm kerb underfoot spans many pixels and keeps its lines, the same kerb at 40 m loses them, and that is right at both ends; the documented collateral is that a reveal, trim or stair tread that projects narrower than this loses its *interior* lines at that distance (silhouettes stay) and gets them back as you approach. RAISE to merge sloppier joins at the cost of fine detail at distance; set `0` to get every line back. ⭐ Values between 0 and `width_px` are floored to `width_px` in the shader (closer in than that the wide taps sit inside the narrow cross's own footprint and only thin real lines), so the only true off is exactly `0`. This is the one crease term that only ever *removes* ink, which is why it ships at the smallest reach that clears the artefact rather than the largest that looks tidy), `concave_crease_strength` (**the piece-junction dial**, ships `1.0` = unchanged look — a crease is *convex* where the surfaces fold away from you (a building's outside corner, a step's nosing, the top of a wall) and *concave* where they fold toward you (the floor/wall junction, the inside corner of an L, the line where a slab sits on a wall, a tread against its riser); normals alone cannot tell them apart, so the shader reads which way they fold from the depth taps it already has. On a level built from boxes every "junction between two pieces" is a concave crease, so this is how much the pieces read as ONE solid: `1.0` draws every junction, `0.0` draws only convex edges and silhouettes — a slab on a wall or a step against a riser shows no line where they meet — and `0.4`–`0.6` keeps junctions present but lighter than edges. Note the floor/wall line and the inside corner of an L are the same kind of crease and go with it), `depth_threshold` + `grazing_tolerance` (raise the tolerance if the floor ahead of you carpets itself in false lines), `contact_merge_m` (**the contact merge**, ships `1.0` m, `0` = off — the other half of "ink the solid, not its pieces", and the half no crease knob can reach. A flight of stairs is a stack of slabs and every step drew its own line, so the flight read as separately outlined pieces; measured on the porch steps, the risers are not even visible from eye height (the surface normal is `(0,1,0)` on both sides), so each step is a *pure depth discontinuity* between two treads and `crease_strength = 0` left every line intact. The rule is the one you gave — don't ink it *where the two are actually touching*: at an edge pixel the two taps that found the edge land on two surfaces, and the 3D distance between those points is how far apart the pieces are along the view ray. A step gives its riser height (~0.95 m for this level's 0.5 m module, however grazing the view, because the far tread begins at the foot of the riser); a box on the floor gives its own height; a facade against one 10 m behind gives 10 m; the sky gives the far plane and can never merge. Closer than this = one solid, and the shoulder runs to 2× so a piece near the threshold fades instead of popping. Measured: the whole street view loses **117 px** at `1.0` while the porch flight's step lines go. RAISE to merge bigger steps (`2.0` merges a full flight including the porch lip); LOWER or `0` to get every silhouette back. ⭐ It is in world metres, so unlike every other term here it does **not** relax with distance, and it deletes real silhouettes by design — a crate parked against a wall, a low ledge, or a shallow alcove will lose the line that said they were separate), `min_depth_reference` (raise it to calm the *gun* down — at 20 cm from the lens it otherwise draws every panel gap), `fade_start` / `fade_end` (a distance backstop for FOGLESS scenes), and `fog_match` (default 1.0 — the important distance control in practice: each frame the pass reads the live `WorldEnvironment`'s fog density and attenuates the ink by the same Beer-Lambert `exp(-density × distance)` the fog itself applies to geometry, so lines dissolve exactly where the world does instead of floating crisp over fog-swallowed buildings; raise above 1 for a deliberate "only ink what's near" look, 0 to ignore fog). Players scale the whole thing with **Options → Video → "Ink Outline"** (0% hides the quad AND stops the mask pass rendering, so off is genuinely free); actor hull rims are independent of the slider — they are not part of this pass. **If the pass ever costs you frames, `mask_resolution` (Advanced, ships `1.0`) is the knob** — the actor exclusion is a *second scene render* over every rimmed actor and prop in view, and it is the only expensive part of the effect. Most of its cost is already gone for free (it no longer inherits the project's 3D supersample, and every AA / shadow-atlas / mesh-detail default is stripped off it, since only its coverage is ever read). Resolution is the part that is **not** free: lower it and the world's ink stops visibly short of every actor. Some gap is correct and unavoidable — the ink has to stop half a line-width out, or it draws a second outline straddling the one the hull already owns — but past that it reads as a bare **halo** that does not shrink with distance, so a far-off NPC sits in a void bigger than itself and you can pick people out by it. Measured against a reference frame with the mask off: **`1.0` → 1 px, `0.5` → 2 px, `0.25` → 2 px but ink starts leaking back onto actors.** So `0.5` is the trade to make if you need frames; `0.25` is a last resort. (Diagnosing: set the Ink Outline slider to 0% — if the frame rate jumps, this pass is your cost; if it doesn't, look elsewhere.) It needs Forward+ and the depth prepass left enabled — with the prepass off the crease lines quietly vanish and only silhouettes remain. Add one to any *other* camera the same way; there is no autoload and nothing per level. |
| **In-world title drop** | scene node | `SkyTitle` | `res://scripts/components/sky_title.gd` | Drop into a level; armed at game-start by the player. The game name is revealed in-world, not on the menu. |
| **Custom NPC body/head** | scene node | `BodyModelSwap` (`@tool`) | `res://scripts/components/body_model_swap.gd` | Drop under the NPC root; set `body_model` (+ optional `head_model`) `.glb` for a live editor preview. |
| **GOAP brain** | `res://resources/goap/` | `GoapProfile` (`resources/goap/goapprofile.tres`) | `res://scripts/npc/goap/goap_profile.gd` | Holds `GoapActionCost` / `GoapGoalPriority` lists. Optional per-archetype tuning over the planner (null = defaults). |
| **Materials / UI skin** | `res://resources/materials/`, `res://resources/ui/` | standard `Material`s; `MenuSkin` (`menu_skin.tres`); `HudSkin` (`hud_skin.tres`) | `res://scripts/...` (`class_name MenuSkin` / `HudSkin`) | Blood, bullet, shell, outline mats; menu styling; the in-game HUD's paint (combat indicators, compass/minimap tints, label/hotbar chrome — §27). |
| **Audio clips** | `res://assets/audio/` | raw `.wav` / `.mp3` (no wrapper resource) | n/a | Three folders, and the split is the whole convention: **`music/`** (radio + dialogue beds; **`music/station/`** holds the station-terminal shop bed — a SUBfolder because `Radio._scan_audio_folder` is non-recursive, which is what keeps in-world radios from shuffling shop themes), **`sfx/`** (everything diegetic — weapons, impacts, voices, ambience), and **`sfx/ui/`** (menu chrome ONLY — the `menu_*.wav` cue set the `MenuSkin` **Sounds** group points at). Drop a new clip in the right folder and reference it from the resource that consumes it (`WeaponData`, `MenuSkin`, an `AudioStreamPlayer` in a scene) — never `preload()` an audio path at a call site. Gameplay one-shots route through `AudioManager.play_sfx` / `play_2d_sfx` so the SFX volume slider applies; menu cues route through `MenuStyle`'s own always-processing players (a paused menu silently drops an inherit-mode player). `.gitattributes` sends `*.wav` through LFS but **not** `*.mp3`. |
| **Interactables** | `res://resources/interactables/` | data `.tres` (e.g. `wooden_crate.tres`, `gore_gib_data.tres` (shared by the meat chunks AND the body-part gibs)) | per-component scripts | Pair with drop-in components like `CanDestroy`, `CanPickUp`, `SpawnOnDestroy`, `LookAtInteractable`. |
| **Quests** | `res://resources/quests/` | `Quest` (+ sub `QuestObjective`) | `res://scripts/quests/quest.gd`, `quest_objective.gd` | Tracked on the **`GameState`** autoload; KILL/TALK/PICKUP/FLAG objectives auto-advance. Press **J** for the Journal. |
| **Status effects** | `res://resources/status/` | `StatusEffect` | `res://scripts/combat/status_effect.gd` | Drag into `Item.consumable_effect`; a `StatusEffectManager` is auto-created on the player. `damage_per_tick` (DoT), `speed_multiplier`, and `stat_modifiers` (agility/gunplay/streetwise/larceny + strength's melee live stats) are all live. |
| **Perks** | `res://resources/perks/` | `Perk` | `res://scripts/player/perk.gd` | Granted at a `PerkStation`; `PerkManager` applies the stat deltas. |
| **Cutscenes** | `res://resources/cutscenes/` | `Cutscene` (+ sub `CutsceneAction`) | `res://scripts/combat/cutscene.gd`, `cutscene_action.gd` | Run by a `CutscenePlayer`; locks player control while playing. |
| **Encounters / spawns** | `res://resources/encounters/` | `SpawnDefinition` | `res://scripts/combat/spawn_definition.gd` | One row per enemy group (scene, count, radius, optional profile/faction/weapon override). Build the `spawn_definitions` array on an `EncounterSpawner`; fired by a `TriggerVolume` `action`. |
| **Schedules** | `res://resources/schedules/` | `Schedule` (+ sub `ScheduleEntry`) | `res://scripts/npc/schedule.gd` | Maps a `WorldClock` phase → a `location_group` so an NPC walks a daily routine (market by day, home by night, §18). Assign to a `ScheduleBehavior` under the NPC. |
| **Loadouts** | `res://resources/loadouts/` | `Loadout` | `res://scripts/combat/loadout.gd` | Starting weapons / clips / money for a scenario or difficulty kit. Assign to `SwapWeapons.loadout` (null = the hardcoded default slots). |
| **Abilities (grapple)** | `res://resources/abilities/` | `GrappleHookResource` | `res://scripts/player/grapple_hook_resource.gd` | Hook/rope visuals, SFX, range/speed and screen-shake for the grapple. Assign to `Player.grapple_resource` (null = built-in defaults). |
| **Map data** | `res://resources/maps/` | `MapData` | `res://scripts/ui/map_data.gd` | Optional authored minimap underlay, per level: assign the `.tres` (the Content dock's **New Map** scaffold) to a `LevelData.map_data` and the HUD minimap draws its `map_texture` UNDER the procedural floorplan, re-resolving on every level swap. Null = the floorplan is the whole map. The `Minimap.map_data` export is a per-widget override. See §16. |

### Top gotchas

- **Reload the editor after adding new `@export` fields or a new `class_name`.** A newly added export won't show in the inspector — and a brand-new `class_name` the editor hasn't scanned yet can cascade into *"Could not find type X"* errors — until the editor reimports. Right after edits the editor may briefly yield empty PackedScenes or *"File not found"*; retry after a few seconds, it clears.
- **`.gd.uid` sidecars are tracked.** Commit each new script's `.gd.uid` alongside the `.gd`. If it's missing, `godot --headless --import` regenerates it. Do not orphan them.
- **Keep exactly one `BodyModelSwap` (one `body_model`) per NPC.** It IS the NPC's visible body — the base `enemy.tscn` no longer carries a default `Man.glb` body node (removed as a vestigial hidden placeholder), and the NPC root's `mesh` export points at the `BodyModelSwap` so the damage-flash + combat outline walk the swapped parts. If you delete or empty it, the flash/outline chain silently no-ops. The runtime head-look + sniper-glint retarget to the swapped head.
- **A faction file's id must equal its filename.** `Factions` resolves a faction by loading `res://resources/factions/<id>.tres`, and `Reputation` keys on the file's **internal `id`**. If the `.tres`'s internal `id` doesn't match its filename you get a loud `push_warning` and two factions can silently merge into one rep pool. So `raiders.tres` must have `id = &"raiders"`.
- **Player-facing tunables must be wired into the Options menu *and* `Settings`.** A new tunable (volume, sensitivity, FOV, accessibility, screen-shake, ...) isn't done when the gameplay code reads it -- add a typed `var` + a `set_*` setter to the **`Settings`** autoload (`res://managers/Settings.gd`) and ONE `SettingSpec` row to `res://resources/settings/SettingsCatalog.tres` (the Options menu is data-driven -- no `options_menu.gd` edits). New keybinds additionally go in `InputManager.gd` + `project.godot [input]` + ONE `ActionSpec` row in `resources/input/ActionCatalog.tres` (NOT a `Keybind` `SettingSpec`).
- **Player-facing strings go through `PlayerText` or an authored resource -- never a raw literal at a paint site.** New UI copy is a const/func in `res://scripts/ui/player_text.gd` or an authored field (a template `@export`, a `SettingSpec`/`ActionSpec` label, a `DialogueResource` line); assigning a bare literal to `label.text` / a toast / a `MenuStyle` text factory fails `tests/test_player_text.gd` (a shrink-only baseline -- the count can only go DOWN) and shows as a WARN in the CYBER SUNDAY Audit tab. Designer template exports substitute **named tokens** -- `{amount}` (`RentCollector.paid_message`), `{part}` (`CrippleCallout.self_bark_template`), `[mph]` (`death_message_fall`) -- by replacement, never GDScript's `%` operator, so a literal `%` in authored text is always safe (a legacy `%s` / `%d` in an old template still substitutes). A `[PH] ` prefix marks unauthored placeholder copy awaiting a writing pass. New `PlayerText` entries follow the **whole-template rule** (`TextFormat`, `res://scripts/ui/text_format.gd`): author ONE whole template per variant and substitute `{named}` tokens via `TextFormat.subst` -- SELECT between whole templates for a bool/enum difference, give a counted line a real singular AND plural template picked by `TextFormat.plural` (no hand-rolled `(s)`), format numbers with `TextFormat.num` and money with `Zorkmids.money_text` (`"{amount} zm"`) -- never build a line by appending prose fragments or suffixes (fragments can't be translated).
