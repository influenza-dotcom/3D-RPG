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
`LootableCorpse`. Plus standalone drop-ins: `Lock`, `SpawnOnDestroy`, `CanDestroy`, `Throwable`.

**New drop-in components go here.** Internal helpers composed in code with `.new()` under the
Player/NPC (HurtFeedback, NpcVoice, AimSway, …) are NOT editor-attached and stay with their owning
subsystem — this folder is only for things a designer drags onto a node.

> Migration note: existing components still live under `scripts/world/` etc. and several scenes
> reference them **by path** (`res://scripts/world/merchant.gd`), so relocating a `.gd` here means
> updating every referencing `.tscn`/`.tres` in the same change — done as a coordinated move with the
> Godot editor closed, never piecemeal.
