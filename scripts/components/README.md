# Components

Drop-in editor components — **attach to a scene node, configure in the Inspector, no scripting.**

A component here is a `Node` / `Area3D` subclass with:
- its own `class_name`,
- `@export` config (the Inspector knobs a designer touches),
- behaviour that reads its host/parent or wires through signals,
- null-guards so a bare instance never crashes.

The established idiom is the **`LookAtInteractable` family** — the base supplies the talk-layer
hitbox + look-at outline, and each subclass writes only its own behaviour (`start_talk` /
`can_be_talked_to` / `look_name`): `CanPickUp`, `MoneyPickUp`, `ItemContainer`, `Merchant`,
`LootableCorpse`, the service stations (`Healer`, `Bonfire`, `LevelUp`, `PerkStation`, `RespecStation`), `Door`,
`Radio`, and more — 17 scripts extend `LookAtInteractable` (this list is illustrative; the full roster is the
component catalogue in `docs/AUTHORING_GUIDE.md`). Plus standalone drop-ins: `Lock`, `SpawnOnDestroy`,
`CanDestroy`, `Throwable`, `Pettable`, `NoisePulser`, `Locomotor`.

**Dual item** — a `CanPickUp` parented under a `Throwable` makes one prop both stashable (E → backpack)
and throwable (Z → carry/throw). `ray_cast.gd` resolves E-vs-Z by ancestry, so the `CanPickUp` MUST be a
descendant of the `Throwable`. This is what `WorldItem.build()` constructs for dropped loot, and what
`scenes/throwable/stashable_crate.tscn` ships as a ready-to-place example. See `docs/AUTHORING_GUIDE.md` §9 (Items, loot, money and pickups).

`Pettable` is the friendly twin of the silent-takedown verb: drop it on any object and the player can HOLD the
Takedown key (Q) while aimed at it to "pet" it (a ♥ floats up). The per-object config lives here as `@export`s;
the polling/hold/dispatch lives player-side in `PetInteraction` (`scripts/player/pet_interaction.gd`, built by
`Player._ready` next to `SilentTakedown`) — the same split as the takedown verb.

Some drop-ins are **auto-built unless you drop a configured one in** (the `LocomotionFx` idiom — the NPC
scans its children, a designer-placed instance wins, otherwise it self-adds a default seeded from today's
tuning so existing scenes are unchanged): `SelfHealer` (spend a carried medkit when hurt),
`PanicOnDamage` (break + flee when hurt mid-fight), and `CrippleCallout` (when a limb is crippled, toast the
player who did it — "Crippled Kyle's arm", colour set by `toast_color` — and cry out "My arm!", unless the
hit was lethal). Drop a configured instance to retune per-NPC, or set `enabled = false` so that NPC never does it.

`CrippleCallout` is a good example of a **fully portable Type-1 drop-in**: the NPC drives it through one
duck-typed `react(host, part, attacker)` call (from the `_on_limb_crippled` shell that stays on the root because
it's a dispatch-by-name `Character` virtual), and the component references no `NPC` type at all — only
`Character.BodyPart` (the base limb enum, fully qualified since it extends `Node`). The NPC wires it by SCRIPT
PATH rather than the `CrippleCallout` class_name, so its `@tool` root never needs the new type in the class cache
to parse — the pattern to copy when auto-adding any new drop-in from `npc.gd`.

`NoisePulser` is the **event / one-shot half** of the stealth *noise* channel: drop it under any `Node3D`
and call `pulse()` (from a signal, a `TriggerVolume`, a script) to drop a fading `NoiseSource` burst that
listening NPCs walk to investigate — a breaking window, a tripped alarm, a beeping machine. Configure
`radius` / `decay` / `lifetime` / `min_interval` in the Inspector. It's host-agnostic (reads `get_parent()`),
so it works on anything; an NPC also auto-builds one to make its gunfire + death audible. (The player's
*continuous* movement noise is the separate `NoiseEmitter` internal helper.) Inert until
`NpcAiSettings.hearing_initiates` is on — a config warning says so on a placed instance.

`Locomotor` is **drop-in pathfinding + movement for any `CharacterBody3D`**: attach it under the body, call
`move_to(pos)` (from a script, a `TriggerVolume`, a patrol component), and it routes there on the baked navmesh —
RVO-avoiding other agents, applying gravity, and turning to face travel. In the default autonomous mode it drives
the body itself (`gravity` + `move_and_slide`), so a bare mob *just moves*; `drive_body = false` instead exposes a
`desired_velocity` for a host that runs its own move loop. Tuning (`move_speed` / `move_accel` / `air_accel` /
`turn_speed`) is duck-typed — a host property wins, else the `@export` fallback — so it needs no specific script.
It fires `reached_target` / `path_blocked` signals to chain behaviour. (It is the extraction target for `npc.gd`'s
in-line nav brain; the NPC will migrate onto it — see [`../npc/README.md`](../npc/README.md). The combat nav-hop +
anti-stuck refinements still live on `npc.gd` for now.)

`RandomCoat` is a **cosmetic "random albedo per instance"** drop-in: attach it under any prop with a
`MeshInstance3D` and fill its `coat_tints` (an `Array[Color]` that multiplies the base albedo) and/or
`coat_albedos` (an `Array[Texture2D]` that replaces it), and each spawned instance rolls one at ready — a
pack of dogs comes out in different coats instead of all-white. It **duplicates** the mesh's material per
instance (a scene's material is shared, so tinting in place would recolour every instance and mutate the
on-disk resource) and applies on a **deferred** call so it lands after a `Throwable` has pushed its
`data.material` onto `material_override`; it touches only `material_override` (albedo), leaving the outline /
hit-flash `material_overlay` alone. Editor-safe and not persisted (cosmetic, re-rolls each load). The shipped
`scenes/dog.tscn` carries seven natural coat tints. The pick is a pure `static pick_index()` (unit-tested in
`tests/test_random_coat.gd`); the in-tree recolour is playtest-verified.

`SprayPaintable` is the **spray-can twin of `RandomCoat`**: drop it under any prop with a `MeshInstance3D` and the
paint gun (`is_spray_paint` weapon) recolours the whole prop to the sprayed colour when its blob lands, instead of
gluing a splatter decal on. The blob (`PaintProjectile`) discovers the component on the body it hit
(`SprayPaintable.find_on`) and calls `paint(color)`. `RandomCoat` sets the coat once at spawn; `SprayPaintable`
overwrites it on every spray — last writer wins, so they compose (spray a random-coated dog and it takes the sprayed
colour). Knobs: `enabled`, `mesh_path` (blank → same auto-resolve as RandomCoat), `blend` (`@export_range` 0–1: 1 =
snap to the sprayed colour in one pass, lower = eases toward it over repeated sprays), `suppress_decal` (default on →
recolour and drop NO decal; off → also leave the splat on top), and a `painted(color)` signal to chain a reaction.
Cosmetic and not persisted (reverts on reload, like RandomCoat's roll). Shipped on `scenes/dog.tscn`. The pure
`blend_color()` / `find_on()` are unit-tested (`tests/test_spray_paintable.gd`); the recolour is playtest-verified.

Both coat drop-ins share the runtime recolour contract via **`MeshCoat`** (`mesh_coat.gd`, a pure `static` helper, not
a component): `resolve_meshes()` (mesh_path → host `mesh_instance` → first descendant mesh) and `writable_material()`
(a per-instance DUPLICATE of the shared material — never the on-disk resource — touching `material_override` only).
Any future "recolour a prop's albedo at runtime" work should go through it (unit-tested in `tests/test_mesh_coat.gd`).

`RandomInventory` is a **spawn-time loot roller for NPCs**: drop it under any `Character` and on spawn it drops a
random selection of Items into that character's backpack. It pairs with the held-item buff system — leave its `pool`
empty and it draws from **every passive-buff trinket in `ItemDb`** (any Item with a `held_passive_effect`), so a
seeded NPC walks around actually wearing the buffs and drops the trinkets as loot when killed. Knobs: `pool`
(restrict to a hand-picked set), `min_items`/`max_items` (count rolled per spawn), `allow_duplicates` (repeat an item
to stack its buff), `chance` (fraction of NPCs that get anything), `rng_seed` (0 = fresh roll each spawn, non-zero =
reproducible). **Timing:** the roll is `call_deferred` because a `Character` builds its `inventory` during ITS `_ready`,
which runs *after* a child's — so the deferred pass runs once the bag exists and the NPC has seeded its own loadout,
adding on top. NPC bags aren't saved, so each spawn re-rolls (use `rng_seed` to pin it). Only for NPCs — the player's
bag is the bounded grid. Pure `grant_into()` is unit-tested (`tests/test_random_inventory.gd`); the in-tree spawn is
playtest-verified. (`PassiveItemBuffs` itself is NOT a drop-in — it's auto-built on every `Character` like the
internal helpers below.)

**New drop-in components go here.** Internal helpers composed in code with `.new()` under the
Player/NPC (HurtFeedback, NpcVoice, AimSway, PassiveItemBuffs, …) are NOT editor-attached and stay with their owning
subsystem — this folder is only for things a designer drags onto a node.

> The drop-in component family was moved here from `scripts/world/` + `scripts/combat/`. Because some
> scenes referenced these scripts **by path** (e.g. `merchant.tscn`, `container.tscn` had no UID
> fallback), the move rewrote every referencing `.tscn`/`.tres`/`.gd` in the same change. Do any future
> relocation the same way — editor closed, all path refs updated together, never piecemeal.
