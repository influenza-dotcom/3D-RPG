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
`LootableCorpse`. Plus standalone drop-ins: `Lock`, `SpawnOnDestroy`, `CanDestroy`, `Throwable`, `Pettable`.

**Dual item** — a `CanPickUp` parented under a `Throwable` makes one prop both stashable (E → backpack)
and throwable (Z → carry/throw). `ray_cast.gd` resolves E-vs-Z by ancestry, so the `CanPickUp` MUST be a
descendant of the `Throwable`. This is what `WorldItem.build()` constructs for dropped loot, and what
`scenes/throwable/stashable_crate.tscn` ships as a ready-to-place example. See `docs/AUTHORING_GUIDE.md` §4.

`Pettable` is the friendly twin of the silent-takedown verb: drop it on any object and the player can HOLD the
Takedown key (Q) while aimed at it to "pet" it (a ♥ floats up). The per-object config lives here as `@export`s;
the polling/hold/dispatch lives player-side in `PetInteraction` (`scripts/player/pet_interaction.gd`, built by
`Player._ready` next to `SilentTakedown`) — the same split as the takedown verb.

Some drop-ins are **auto-built unless you drop a configured one in** (the `LocomotionFx` idiom — the NPC
scans its children, a designer-placed instance wins, otherwise it self-adds a default seeded from today's
tuning so existing scenes are unchanged): `SelfHealer` (spend a carried medkit when hurt) and
`PanicOnDamage` (break + flee when hurt mid-fight). Drop a configured instance to retune per-NPC, or set
`enabled = false` so that NPC never does it.

**New drop-in components go here.** Internal helpers composed in code with `.new()` under the
Player/NPC (HurtFeedback, NpcVoice, AimSway, …) are NOT editor-attached and stay with their owning
subsystem — this folder is only for things a designer drags onto a node.

> The drop-in component family was moved here from `scripts/world/` + `scripts/combat/`. Because some
> scenes referenced these scripts **by path** (e.g. `merchant.tscn`, `container.tscn` had no UID
> fallback), the move rewrote every referencing `.tscn`/`.tres`/`.gd` in the same change. Do any future
> relocation the same way — editor closed, all path refs updated together, never piecemeal.
