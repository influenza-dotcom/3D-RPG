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
`Radio`, and more — **20 scripts extend `LookAtInteractable`** (see the full tree below). Plus standalone
drop-ins: `Lock`, `SpawnOnDestroy`, `CanDestroy`, `Throwable`, `Pettable`, `NoisePulser`, `Locomotor`, `NavBlocker`, `NavLink`,
`AmbientSound`, `AudioZone`, `IndoorAmbienceDucker`, and more — that list is a sampler, not the roster; the full
designer-facing catalogue (every drop-in with its knobs) is `docs/AUTHORING_GUIDE.md` §11, *The drop-in component
catalogue*.

## The `LookAtInteractable` hierarchy

`LookAtInteractable` (`look_at_interactable.gd`, `extends Area3D`) is the shared base for every world
object you **look at and press E** on. It is the interaction PLUMBING — the talk-layer hitbox the player's
interaction ray (`PickupRay`) detects, plus the white look-at outline drawn over the host on hover — so each
subclass writes only its OWN verb and leaves the ray untouched.

**The duck-typed talk-handler surface** (four methods; `PickupRay` calls these by name, never by type, so a
new subclass needs zero ray changes). A subclass overrides the first three; `host_npc()` stays the base's
`null` on world objects — it exists only so the FNV hover can tell "no NPC here" without an `NPC` ↔
`LookAtInteractable` type loop:

| method | what it does | base default |
| --- | --- | --- |
| `look_name() -> String` | the hover readout ("Take Medkit", "Trade", "Read Note") | `"Interact"` |
| `start_talk(player) -> void` | the action when E is pressed (open a screen, pick up, swing) | no-op |
| `can_be_talked_to() -> bool` | whether it's offerable right now (e.g. only while non-empty) | `true` |
| `host_npc() -> Node` | the NPC behind it, if any (world objects return `null`) | `null` |

**Shared `@export`s** every subclass inherits: `highlight_target` (the `Node3D` to outline; null → parent),
`highlight_color`, `highlight_width`, and `auto_fit_collider` (opt-in: fit the hitbox to the host meshes at
runtime instead of hand-sizing a `CollisionShape3D`; default `false`).

### The subclass tree

```
LookAtInteractable            look_at_interactable.gd   (extends Area3D)
│  talk-layer hitbox + look-at outline; duck-typed surface
│  (look_name / start_talk / can_be_talked_to / host_npc)
│
├─ CanPickUp                  can_pick_up.gd        — E: add an Item (± loot_table) to the backpack
│   └─ DogPickup              dog_pickup.gd         — a CanPickUp whose Item is priced/sized/coated from the live dog
├─ MoneyPickUp                money_pickup.gd       — E: collect zorkmids, update the HUD, self-free
├─ UpgradePickup              upgrade_pickup.gd     — E: permanently grant a player ability
├─ ItemContainer              container.gd          — E: open the loot screen (persistent crate/chest/locker)
├─ LootableCorpse             lootable_corpse.gd    — E: open the loot screen on a dead body (spawned by the death system)
├─ Merchant                   merchant.gd           — E / dialogue "Trade": open the shop screen
├─ Healer                     healer.gd             — E / dialogue: pay to heal to full + clear limb damage
├─ Bonfire                    bonfire.gd            — E / dialogue: rest — full heal + set the respawn checkpoint
├─ LevelUp                    level_up.gd           — E / dialogue: spend zorkmids to raise a stat / skill points on perks
├─ PerkStation                perk_station.gd       — E: learn a Perk (permanent bonus / ability grant)
├─ RespecStation              respec_station.gd     — E: pay to reverse every perk and refund the points, re-pick from scratch
├─ ChipInstaller              chip_installer.gd     — E / dialogue "Install": pay to install an ability microchip
├─ ChessMatch                 chess_match.gd        — E / dialogue "Play Chess": blindfold-chess minigame vs a ChessAi
├─ Atm                        atm.gd                — E / dialogue "Bank": deposit / withdraw on the signed ledger account (GameState.account)
├─ Door                       door.gd               — E: swing a door open/closed (lockable: built-in key/lockpick gate, or a child Lock)
├─ LevelDoor                  level_door.gd         — E: travel to another level (GameRoot.load_level → matching PlayerSpawn)
├─ Radio                      radio.gd              — E: play / cycle a folder of music tracks (takes precedence over the score)
├─ Readable                   readable.gd           — E: read a note / sign / datapad through the dialogue UI
├─ Switch                     switch_lever.gd       — E: set a flag / call a method on target / toast (the manual TriggerVolume)
└─ QuestStarter               quest_starter.gd      — E: accept a Quest (a quest board / giver)
```

The seven **dual-mode** subclasses (`Merchant`, `Healer`, `Bonfire`, `LevelUp`, `ChipInstaller`, `ChessMatch`, `Atm`)
run standalone by default (aim + E) OR, with `standalone = false`, sit as a data-only child of a `DialogueNPC`
whose conversation offers the action ("Trade" / "Install" / "Play Chess") — the NPC's `Talkable` owns the ray
in that mode. `_on_dialogue_host()` on the base powers their config warning against stealing the ray.

Each dual-mode station also implements the two-method **dialogue-station contract** that grows the option:
`dialogue_station_option() -> Dictionary` (`label`: a `PlayerText` const, `order`: the script's `DIALOGUE_ORDER`
const, `reason`: `_suspend_for_menu`'s reason string, `closed`: the sub-menu's resume `Signal`) and
`open_dialogue_station(player)` (the press). `DialogueManager` scans the speaker's **direct** children by
`has_method` of **both** names (a half-implemented pair paints no button) and sorts by the explicit `order` key —
`10..70` is today's Trade → Bank sequence, so authored child order never matters. `Bonfire` omits
`reason`/`closed` = an **act-and-close** station (rest, then the conversation ends — no suspension). Adding a
station = author the component (pick a free order slot; the consts are spaced by 10) plus one roster row in
`tests/test_dialogue_speaker_contracts.gd`, which pins the labels, orders, reasons, and the roster itself —
no `DialogueManager` edit.

Per-component **knobs / `@export` fields** are the designer-facing source of truth in
`docs/AUTHORING_GUIDE.md` → *The "look-at interactable" family* — this tree does not repeat them.

### Not in this tree (related, but a different base)

- **`Corpse`** (`scripts/npc/corpse.gd`, `extends Node3D`) — the AI "a body is here" DISCOVERY marker (has a
  `save_id`, in the `&"corpse"` group). It is **not** the lootable body; the loot interactable is
  `LootableCorpse`. One death can spawn both. Don't confuse the two.
- **`Talkable`** / **`DialogueNPC`** (`talkable.gd` / `dialogue_npc.gd`) — the conversation surface. They
  DUCK-TYPE the same four talk-handler methods so `PickupRay` treats them identically, but they extend
  `Area3D` / their own root, not `LookAtInteractable`.
- **`Pettable`** / **`Claimable`** (`pettable.gd` / `claimable.gd`, `extends Area3D`) — HOLD-Q pet and TAP-T
  befriend verbs on their OWN physics layers, deliberately off the talk layer so they never show an "[E]"
  prompt.
- **`PickupBeacon`** (`pickup_beacon.gd`, `extends Node3D`) — the colour-coded pickup item light. The class keeps
  its legacy name, but it now builds only a small `OmniLight3D` on the item: no vertical shaft, no mesh beacon, no
  shaft geometry. The light still distance-fades. It is NOT an interactable (it has no talk handler) — it's a cosmetic companion the pickup
  components spawn for themselves at runtime: `CanPickUp` / dropped items (`attach_for_item`, colour from the
  Item's kind), `MoneyPickUp`/`UpgradePickup` (`attach_kind`), and `LootableCorpse` (`attach_kind(LOOT_BAG)` +
  `set_item_count` so an enemy's dropped sack scales with how much it holds). Its glow light joins
  `Groups.PICKUP_BEACON`, which `PlayerLightLevel` skips so item lights never affect enemy perception. Palette,
  distance fade, light energy/range, and sack scaling live in `GameSettings.pickup_beacons`
  (`resources/tuning/PickupBeaconSettings.tres`); the player hides them all via Options → Accessibility → Item
  Lights (`Settings.loot_beacons_enabled`, polled live).
  **Invariant — the fade is a GROUND-LOOT fade.** `near_distance` (3 m) is where the light reaches ZERO, not full,
  so anything the player *carries* is inside the dark end of the ramp. A pickup that gets picked up and thrown
  (a weapon drop) therefore sets `always_lit` — `brightness_for()` then returns 1.0 unconditionally, beating both
  the near fade and the `max_distance` cull, skipping the player lookup entirely, and dropping the
  `GROUND_LIGHT_LIFT` (that offset is body-local, so on a nosing thrown prop it would swing around and trail the
  blade). Energy/range are trimmed by the palette's `always_lit_*` scales because the viewing distance is ~1 m
  instead of ~9 m. It is set through `CanPickUp.item_light_always_lit`, which `WorldItem` stamps from
  `WeaponData.dropped_item_light_always_lit` — so the knife glows identically on the floor, in hand, and in flight.

- **`WorldMarker`** (`world_marker.gd`, `extends Node3D`) — a point-of-interest beacon: joins the `&"compass"`
  and `&"minimap"` groups on `_ready`, so a chevron rides the screen edge and a dot sits on the HUD floorplan
  with no wiring. Place by hand for fixed landmarks; `QuestMarkerSync` spawns them for live objectives.
- **`MinimapHide`** (`minimap_hide.gd`, `extends Node`) — the "not a wall" tag. `FloorplanSource.gather` skips
  the whole subtree it marks, so a fence / awning / parked car stops being drawn as a wall on the minimap's
  section cut. Collision is untouched: the prop still blocks bullets, footsteps and navigation.
  **Invariant — it joins its PARENT, not itself,** which is why it is a plain `Node` and must be childed under
  the prop. The gather skips subtrees by their ROOT, and the tag node owns no colliders of its own, so a
  version that added itself to the group would look identical in the inspector and silently do nothing.
  Second invariant: the group is read ONCE per level, during the gather that makes the map free per frame —
  toggling `enabled` at runtime does nothing until someone calls `Minimap.rebake()`.

### Adding a new interactable type

1. `class_name Foo` / `extends LookAtInteractable`. Add `@tool` only if you want an in-editor preview or a
   config warning (most leaves do) — then keep the base's editor guard intact (see step 3).
2. Override **`look_name()`** (the hover verb), **`start_talk(player)`** (what E does), and, if conditional,
   **`can_be_talked_to()`**. That is the whole interaction contract — `PickupRay` finds you automatically.
3. If you need extra setup, override `_ready`, do your pre-work, then call **`super()`** (which wires the talk
   layer + builds the outline). If you set your own `collision_layer` first (the `Merchant` pattern), call
   `_build_outline()` instead of `super()`. A `@tool` subclass with NO `_ready` inherits the base's
   `Engine.is_editor_hint()` guard for free; one with its OWN pre-`super()` runtime work must self-guard
   (`if Engine.is_editor_hint(): return`) before that work, like `container` / `can_pick_up`.
4. Put every tunable on an `@export` (per-instance) or a `resources/tuning/*.tres` group — never a hardcoded
   const — and null-guard the host reads so a bare instance never crashes.
5. Document it: add ONE catalogue row to `docs/AUTHORING_GUIDE.md` (*The "look-at interactable" family*) and
   a line to the tree above.
6. If `start_talk` opens a modal screen, register that modal in `InputManager._modal_reg` — an unregistered
   modal is the recurring drift this codebase watches for. Its `blocks_tabs` flag answers ONE question: does
   this screen own the player's hands (so a Pip-Boy tab must refuse to open over it)? A station screen: yes.
   ⭐It is NOT about pausing — **no registered screen pauses the tree**; only `DialogueManager` still does.
   A station screen that froze the world would stop the city at a walk-up kiosk (see `atm_screen.gd`'s header).
7. If it is a self-serve station, give it a voice in one line: `StationSpeaker.ensure(self)` in `_ready`,
   gated on `standalone` (a data-only station rides a talking NPC, and a person who beeps is a bug). The
   screen sounds it with `StationSpeaker.chirp(station)` and suppresses the generic UI sting when it fires.
8. If it is **dual-mode** (a `standalone` flag + a dialogue-NPC option), implement the dialogue-station
   contract pair — `dialogue_station_option()` / `open_dialogue_station(player)` (see the dual-mode paragraph
   above) — with a free `DIALOGUE_ORDER` slot, and add its roster row to
   `tests/test_dialogue_speaker_contracts.gd`. The dialogue grows the option automatically; if the station
   suspends into a NEW screen, that screen still owes the modal-registry row (step 6), a `closed` emit on
   every refuse path (`tests/test_dialogue_suspend_closed.gd`), and its own suspend-contract test row.

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
`PanicOnDamage` (break + flee when hurt mid-fight), `ProvokeOnAttack` (a player attack flips this non-hostile NPC
hostile; `enabled = false` for a shopkeeper the player can shoot without aggro — see `docs/AUTHORING_GUIDE.md` §20),
and `CrippleCallout` (when a limb is crippled, toast the
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
It fires `reached_target` / `path_blocked` signals to chain behaviour. In DRIVEN mode it also carries the full NPC
pursuit brain (lifted from `npc.gd` in the Phase B migration): the combat nav-hop, the anti-stuck / wall-slide give-up
machine (with a net-displacement backstop — `PROGRESS_WINDOW` / `PROGRESS_MIN_TRAVEL` — so a sideways wall-slide can't
masquerade as progress and pace a blocker forever), and off-mesh recovery. The host calls `drive_move_to(target, allow_hop, hop_target)` + `update_stuck(body, delta)`
each physics frame and reads `desired_velocity`; it may inject its own `NavigationAgent3D` via `external_nav` so a system
that reads `host._nav` (CompanionFollow) shares the single agent — see [`../npc/README.md`](../npc/README.md).

**The feet correction (`apply_path_height_offset`) — read this before touching agent setup.** A `NavigationAgent3D`
advances to the next path waypoint on the **3D** distance from its parent's ORIGIN to that waypoint, but baked path
vertices lie on the **floor**. A capsule-centred body's origin floats half its height up (this project's NPC: 1.0034 m
— `enemy.tscn` capsule height 1.95, shape offset y −0.028), so that distance never drops below ~1.0 m against
`path_desired_distance` 0.5 and **the path index is pinned at 0 forever**. `get_next_path_position()` then keeps
returning the point directly *underneath* the body, `to_next` comes out near-vertical, and `_compute_desired` alternates
between its "path won't advance → head straight" emergency fallback and steering back at `path[0]` — a 2-frame
oscillation at full walk speed with **zero net progress**. Measured on the live level's real 2529-poly bake, a 25 m
7-waypoint route: max path index 0 and 25.00 → 25.03 m before; index 6 and 25.00 → 0.99 m after. So the Locomotor
derives `path_height_offset` from the host's own capsule (`collision_bottom_y`) and applies it to **both** agent
branches — the one it builds and the injected `external_nav`. Godot **subtracts** this value from each path vertex, so
it is **negative**. A host with no capsule degrades to 0 (engine default). `path_height_offset_override` wins when set.
Anything that changes the body's capsule or origin at runtime must re-run `apply_path_height_offset` —
`reset_for_reuse` already does, for `NpcPool`.

**Destinations are submitted through a `repath_epsilon` gate.** `drive_move_to` calls `move_to` every physics frame,
and assigning `NavigationAgent3D.target_position` always queues a fresh A* — so an unguarded write ran a whole-map
query per NPC per tick, and (now that paths are actually followed) re-fired `link_reached` every frame while a body sat
on a link, far faster than `JUMP_COOLDOWN` could damp it. `move_to` only submits a destination that moved more than
`repath_epsilon`; `stop()` / `reset_for_reuse` clear `_target_submitted` so a re-issued identical target still re-seeds.

The Locomotor also owns the **NavLink traversal driver** that makes NPCs physically cross an authored `NavLink`
(`nav_link.gd`): it connects the agent's `link_reached` (`_connect_link_signal`, once, guarded), injects a launch when
entering an UP link (`_on_link_reached` -> `jump_velocity_for_climb`), and injects a short horizontal commit when
entering a DOWN link so the `CharacterBody3D` actually steps over the rim. DOWN traversal includes a small forward hop
to break floor contact if the capsule catches the lip. **It is deliberately decoupled from the combat
`allow_hop` gate** — an authored link is an explicit "traverse here", so *idle* NPCs climb/drop too, not just
combatants. Two invariants: (1) traversal state is zeroed in `reset_for_reuse` (`_jump_cd` / `_hopping` /
`_hopped_this_frame` plus the down-link `_link_descent_t` / `_link_descent_dir`), so `NpcPool` reuse is covered; a *new*
Locomotor per-life field still MUST be added to `reset_for_reuse`. (2) Godot 4.6's `link_reached` payload is
`{position(=entry), type, rid, owner}` — there is **no** exit key; the exit is derived by reading the link's endpoints
from its RID (`_link_exit_position`; the climb is derived at the call site as `exit.y - entry.y`).

Following the player **off** a ledge is the DRIVEN commit-and-charge: when the target sits on a disconnected lower
island (you dropped off a ledge) the brain charges straight off the rim — descent is flatten + gravity, no link
needed — gated by **`max_pursuit_drop`**. A down-probe just past the lip (`_drop_ahead_unsafe`) refuses the step-off
when the floor ahead is more than that far below (or bottomless), so an NPC chases you off a balcony but **not** off
a cliff / into a pit (only while grounded at the rim; once airborne the fall finishes). A deliberately-authored
`NavLink` makes such a target *reachable*, so the commit branch never runs there — big intentional drops are the
link's job. Whether the NPC even *tries* to follow you off is a **perception** decision upstream:
`Perception.pursuit_grace_time` keeps it locked on your live position through the brief line-of-sight loss of a drop
(without it, losing sight the instant you go over the edge froze the enemy at the top — see the NPC perception exports).
If `link_reached` does not fire cleanly at the rim, combat pursuit also has a fallback: a nearby lower path point (or a
close lower target) arms the same forward-vault commit so a chaser does not rub around the lip forever while the path is
technically reachable.
While that commit is active, `NPC.apply_velocity` skips RVO and acceleration smoothing so the body receives the shove
directly instead of steering around the rim again.

`RandomCoat` is a **cosmetic "random albedo per instance"** drop-in: attach it under any prop with a
`MeshInstance3D` and fill its `coat_tints` (an `Array[Color]` that multiplies the base albedo) and/or
`coat_albedos` (an `Array[Texture2D]` that replaces it), and each spawned instance rolls one at ready — a
pack of dogs comes out in different coats instead of all-white. It **duplicates** the mesh's material per
instance (a scene's material is shared, so tinting in place would recolour every instance and mutate the
on-disk resource) and applies on a **deferred** call so it lands after a `Throwable` has pushed its
`data.material` onto `material_override`; it touches only `material_override` (albedo), leaving the outline /
hit-flash `material_overlay` alone. Editor-safe and not persisted (cosmetic, re-rolls each load). The shipped
`scenes/characters/dog.tscn` carries seven natural coat tints. The pick is a pure `static pick_index()` (unit-tested in
`tests/test_random_coat.gd`); the in-tree recolour is playtest-verified.

`SprayPaintable` is the **spray-can twin of `RandomCoat`**: drop it under any prop with a `MeshInstance3D` and the
paint gun (`is_spray_paint` weapon) recolours the whole prop to the sprayed colour when its blob lands, instead of
gluing a splatter decal on. The blob (`PaintProjectile`) discovers the component on the body it hit
(`SprayPaintable.find_on`) and calls `paint(color)`. `RandomCoat` sets the coat once at spawn; `SprayPaintable`
overwrites it on every spray — last writer wins, so they compose (spray a random-coated dog and it takes the sprayed
colour). Knobs: `enabled`, `mesh_path` (blank → same auto-resolve as RandomCoat), `blend` (`@export_range` 0–1: 1 =
snap to the sprayed colour in one pass, lower = eases toward it over repeated sprays), `suppress_decal` (default on →
recolour and drop NO decal; off → also leave the splat on top), and a `painted(color)` signal to chain a reaction.
Cosmetic and not persisted (reverts on reload, like RandomCoat's roll). Shipped on `scenes/characters/dog.tscn`. The pure
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

`Ragdoll` is the **rigged-skeleton corpse** drop-in (`ragdoll.gd`, attached to `scenes/props/skeleton.tscn`): on
spawn it starts the physical-bone simulation so the model goes limp, shoves it in the direction of the killing blow,
then fades + frees it (or lingers while a `LootableCorpse` still holds loot). The corpse's fading point-light is
discovered via **`NodeFinder.find_first_of_class(self, OmniLight3D)`**, NOT the old ~15-segment authored Sketchfab
NodePath — that deep path silently resolved to null on any GLB re-import / re-rig (the `_fbx` hash + bone names shift)
and `_process` then crashed on the null deref; `_process` also null-guards `corpse_light` so a scene missing the light
degrades to "no fade dimming" instead of a crash. `tests/test_ragdoll_scene.gd` pins the scene's `OmniLight3D` +
`PhysicalBoneSimulator3D` against exactly that re-import drift (off-tree `instantiate()`, so `Ragdoll._ready` never
runs — no physics await). Physical bones can't be authored from code — the one-time editor setup lives in the
`ragdoll.gd` header.

`IndoorAmbienceDucker` is the **"quieter and muffled under a roof" treatment** for an ambient bed: drop it under the
Player next to the `Ambience` AudioStreamPlayer3D and it casts a small fan of rays STRAIGHT UP each tick — when at
least `coverage_threshold` of them hit geometry within `ceiling_scan_height` (a roof / ceiling / overhang) it applies
two subtle "you're indoors" treatments and reverses both under open sky. (1) VOLUME: cross-fades the bed from
`outdoor_db` down to `indoor_db`, moving only the target player's own `volume_db` (never the `ambient` bus) so the
Ambient slider still governs the level and the two compose in dB — the "fade the node, leave the bus for the slider"
split `AudioZone` uses. (2) MUFFLE (`enable_muffle`, on by default): sweeps a low-pass `cutoff_hz` from
`outdoor_cutoff_hz` (transparent) down to `indoor_cutoff_hz` (default ~2500 Hz — a clearly-audible "stepped indoors" roll-off). A low-pass is per-BUS, so the
bed sits on its own **`ambient_bed`** bus (in `default_bus_layout.tres`, carrying an `AudioEffectLowPassFilter`,
sending into `ambient` so the slider still applies) — the same shape as the `radio` bus's low-pass. (The full bus
set is `ambient`, `sfx`, `music`, `voice`, `radio` → `music`, `ambient_bed` → `ambient`, `speaker` → `sfx` (the
tinny `StationSpeaker` kiosk chain — `docs/AUTHORING_GUIDE.md` §2a), and `sting` → Master,
which is reserved for the death sting: the death cinematic ducks the world buses rather than Master, so `sting`
is exempt by routing. Anything left on Master therefore escapes BOTH the volume sliders and that duck — see
`scripts/player/death_mix.gd`.) The up-ray fan
(not a single ray) plus the vote threshold stop a doorway gap / skylight directly overhead from flickering you
"outdoors". `target` blank → it auto-finds the first sibling on `bus`; `host` auto-wires to the parent. It also
WRITES `host.is_indoors` (a bool on the player, declared next to `light_exposure` in `player.gd`) each sample — the
shared "is there a roof over me" seam a future reverb send / rain cutoff / interior-music swap can read instead of
re-casting. Ray + throttle + held-prop LOS mask are lifted from `PlayerLightLevel`. Pure vote/fade/sweep math, the
low-pass resolver, and the in-tree roof detection are unit-tested (`tests/test_indoor_ambience_ducker.gd`).

`BodyPartGibs` is the **per-actor switch for the body-part death burst** (`body_part_gibs.gd`): a dying character
coming apart into its OWN head / torso / arms / legs — lifted live off its `BodyModelSwap`, skin and tint included —
instead of only spraying the generic meat chunks (`gore_gib.tscn`). The burst itself lives in
`GoreSpawner._spawn_body_part_gibs` (`scripts/player/gore_spawner.gd`) and is **on by default** for any actor with a
`BodyModelSwap`, governed by `GameSettings.effects.body_part_gibs_enabled`; this component exists only to OVERRIDE
that for one actor (both directions), pick which parts fly, and set the meat-chunk mix. Two invariants make it safe:
(1) the parts are **`duplicate()`d, never taken** — a pooled NPC reuses those exact node instances every life and
nothing rebuilds them, so reparenting one would bring the body back permanently limbless; and (2) `GoreSpawner`
reaches this component **duck-typed** on `body_part_gib_config()` and reaches its statics **by script path**, never by
the `BodyPartGibs` class_name — that script sits on `Character`'s parse path, where a not-yet-registered class_name
takes every actor script down with it (the class-cache cascade). The flying limb rides `BodyPartGib`
(`scripts/effects/body_part_gib.gd`, `extends Throwable`), whose `mount_placement` splits the part's world transform
into a clean positive-determinant rotation for the RigidBody and scale-plus-mirror for the mounted child — a scaled
rigid body is ignored by the physics server, and the right arm/leg's det = -1 mirror on one renders the limb black.
Pure seams + the chassis scene contract are pinned by `tests/test_body_part_gibs.gd`.

**Both gib chassis must wire `mesh_instance`, and the meat chunk must keep `auto_fit_collider` OFF.**
`Throwable._fade_out_for_despawn` (the `gib_lifetime` -> `gib_fade_time` despawn) tweens `mesh_instance.transparency`
and returns immediately without one, so an unwired mesh makes the fade a silent no-op and the gib POPS —
`gore_gib.tscn` shipped that way for a long while. Wiring it also arms `_autofit_collision_shape`, and on the meat
chunk that is a REGRESSION, not a retune: the auto-fit resizes the shape but never the `CollisionShape3D`'s
transform, and that gib's box is deliberately tilted ~14.5 deg and raised +0.237 m off the body origin, so fitting it
to `model.obj`'s ~1.0 x 1.0 x 1.08 bounds grows it off-centre (a quarter-metre of collider above the chunk, none
below). Hence the `auto_fit_collider` opt-out — the same field name `LookAtInteractable` / `Pettable` / `Claimable`
already use. `body_part_gib.tscn` keeps the auto-fit ON (its mount point is empty, so the box tracks the real limb)
and instead OVERRIDES `_fade_out_for_despawn`, because `GeometryInstance3D.transparency` does not propagate to
children and its visual is a mounted subtree. Pinned by `tests/test_gore_gib_prefab.gd`.

**New drop-in components go here.** Internal helpers composed in code with `.new()` under the
Player/NPC (HurtFeedback, NpcVoice, NpcDistraction, AimSway, PassiveItemBuffs, …) are NOT editor-attached and stay
with their owning subsystem — this folder is only for things a designer drags onto a node.

> The drop-in component family was moved here from `scripts/world/` + `scripts/combat/`. Because some
> scenes referenced these scripts **by path** (e.g. `merchant.tscn`, `container.tscn` had no UID
> fallback), the move rewrote every referencing `.tscn`/`.tres`/`.gd` in the same change. Do any future
> relocation the same way — editor closed, all path refs updated together, never piecemeal.
