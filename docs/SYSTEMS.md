# Gameplay systems

How each system behaves and which scripts own it. For how the project is wired
(composition, signals, autoloads), see [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## Movement & input forgiveness

**`player.gd` `_physics_process`** runs the controller. Horizontal movement eases toward a
`target_speed` with separate ground/air smoothing (air is much "floatier"). `target_speed`
is `max_speed`, reduced for backward (`backward_mult`) and strafe-only (`strafe_mult`)
input, by crouch, and by ADS (`scope_speed_mult`). All easing is frame-rate-independent.

Two forgiveness mechanics make jumps feel responsive at both edges of ground contact:

- **Coyote time** (`coyote_time.gd`) — keeps "can jump" true for a short window *after*
  walking off a ledge. `tick(delta)` re-arms the window every grounded frame and counts it
  down once airborne.
- **Jump buffer** (`jump_buffer.gd`) — remembers a jump press for a short window *before*
  landing, so a slightly-early press still fires on touchdown.

A jump only happens when **both** `coyote_time.can_jump()` and `jump_buffer.wants_jump()`
are true; both are then `consume()`d.

**Landing** scales feel by impact: `pre_landing_velocity.y` drives the camera dip, gun dip,
screen shake, land SFX volume/pitch, and dust amount — tiny stutter-landings are nearly
silent and dustless, full-speed splats hit hard. A separate **air-thump** plays a heavy
sound only on a *sudden* mid-air speed loss (a real impact, not a glancing wall slide).

---

## Bunnyhop (`bunnyhop.gd`)

A skill-expression speed chain. Landing opens a tight window (`land_window`); jumping again
*with movement input* inside it increments a `chain`, and `get_target_speed()` returns
`max_speed + chain * boost_per_hop`, capped at the bhop `max_speed`. Standing on the ground
past the window breaks the chain. `bunnyhop.gd` holds no velocity itself — `player.gd` calls
`try_engage()` on each jump and, if it returns true, overrides horizontal velocity with
`get_target_speed()`.

At high speed, `mouse_input.gd` scales look sensitivity **down** (toward `sens_min_multiplier`
at bhop `max_speed`) so fast runs stay controllable.

---

## Crouch & slide (`crouch.gd`, slide in `player.gd`)

**Crouch** (`crouch.gd`) resizes the capsule + lowers the head, blocks crouching if a crate
sits overhead (camera-clip guard), and won't let you stand up under a low ceiling
(shape-cast check).

**Slide** lives in `player.gd`. Conditions and behaviour:

- **Trigger:** on the landing frame, holding crouch, with horizontal speed above
  `slide_min_speed`. The slide is seeded from your landing momentum (capped at
  `slide_max_speed`; `slide_boost` defaults to `1.0` = pure momentum, no acceleration —
  this was tuned down after an early version felt like it *sped you up*).
- **During:** speed bleeds off via `slide_friction`; the camera doesn't bob; footsteps are
  muted.
- **Ends when:** speed decays to `slide_end_speed` (≈ crouch-walk pace, seamless), you
  release crouch, you leave the ground, **or you press any movement key** (movement input
  overrides the slide and hands back normal control).
- **Slide-jump:** jumping out of a slide adds a forward **blast impulse** scaled by your
  *current* slide speed (`_slide_dir * _slide_speed * slide_jump_mult`). Faster slides fling
  you further, and jumping early (while still fast) launches harder.

A dust puff is kicked up on an interval, and a looping wind SFX plays while sliding.

---

## Bullet time (`bullet_time.gd`)

A "dive and peek" moment. Entering ADS **while airborne** eases the global
`Engine.time_scale` into slow-mo. It's a state machine — `READY → ACTIVE → EXHAUSTED` — and
ends on the **first shot** (`flash_muzzle`), on landing, on un-scoping, or when the duration
expires. It will not trigger if you were already scoped on the ground and then launched into
the air. See [`ARCHITECTURE.md` §7](ARCHITECTURE.md) for the time-scale ownership and
wall-clock-timing details.

---

## Ram (body-check) & pinball bounce (`player.gd`)

Both read the **pre-move** velocity (collision response zeroes the post-move velocity into
surfaces), and both run after `move_and_slide`.

- **Ram damage** (`_check_ram_damage`) — moving faster than `ram_min_speed` into an enemy
  deals `round(speed * ram_damage_per_speed)` damage plus knockback. The sound depends on
  the outcome: a **kill** plays the bowling-pin *strike* (`bowling`), a **survivor** a heavy
  positional thud (`ram_thud_sound`). Already-dying enemies are skipped so you don't "kill"
  a corpse.
- **Pinball bounce** (`_check_bounce`) — ramming a wall / object / enemy faster than
  `ram_bounce_min_speed` reflects you off the surface normal via a decaying blast impulse
  (so the rebound carries instead of being killed by the movement lerp). Bounciness is
  `ram_bounce_factor`. The **floor is excluded** (so fast landings don't pop you up), and a
  short cooldown prevents jitter against a single wall while still allowing rapid wall-to-
  wall bouncing.

---

## Combat pipeline (`attack.gd`, `projectile*.gd`)

A shot is **hitscan-first with a visual projectile**:

1. `MouseInput` emits `attack` every frame the fire button is held; `attack.gd` gates on the
   fire/reload/swap timers (and on `auto_fire` — see Melee for per-click weapons).
2. For each pellet (`pellet_count`), a ray is cast from screen center, jittered by
   `pellet_spread` (tightened while ADS by `scope_spread_divisor`), out to `effective_range`.
3. A hit applies damage + knockback, spawns a hit spark, and plays the appropriate impact
   sound. **Interactables play their own contextual sound** (so gibs sound fleshy, crates
   wooden) instead of the weapon's generic clang.
4. `spawn_projectile` is emitted per pellet. Within `effective_range` the raycast already did
   the damage, so the projectile is **visual-only**; beyond it, a real projectile flies and
   resolves its own impact (`projectile.gd`). This is why both `attack.gd` and `projectile.gd`
   contain parallel impact-sound logic.

**Ammo** (`ammo.gd`) is tracked per-weapon and **persisted across swaps** (a dictionary keyed
by `WeaponData`). `consume_ammo()` returns false when empty → `attack.gd` plays the dry-fire
click. **Reload** refills to max. **ADS** (`scope_in.gd`) lerps FOV toward `scoped_fov`,
tightens spread, and slows movement; the per-shot cooldown does *not* break scope (so
rapid-fire stays smooth), but reload/swap do.

---

## Weapons as data (`weapon_data.gd`, `resources/weapons/*.tres`)

Each weapon is a `WeaponData` resource. Beyond the obvious stats (`damage`, `attack_speed`,
`max_ammo`, `effective_range`, `pellet_count`/`pellet_spread`, knockback/lift,
`screen_shake_amount`, per-weapon `audio`/`whiz_sound`/`impact_sound`/`impact_enemy_sound`,
`hand_mesh`), the behavioural **toggles** are:

| Field | Effect |
| --- | --- |
| `auto_fire` | `true` = hold to keep firing; `false` = one attack per click (semi-auto). |
| `has_muzzle_flash` | Show the muzzle flash mesh/light **and** sparks (they're coupled). |
| `has_laser_sight` | Show the laser-sight mesh (when the flashlight is on). |
| `spawns_casing` | Eject a shell casing on fire. |
| `attack_windup` | Seconds between click and the attack actually landing (weight; 0 = instant). |
| `single_air_dash` | Limit the scoped launch to once per airtime (see Melee). |
| `launch_on_scoped_attack` | Attacking while scoped *launches* the player instead of firing. |
| `launch_force` / `launch_upward` | The launch vector for the above. |

Weapons are assigned to `SwapWeapons.weapon_slots` (an `Array[Resource]` populated with
preloaded defaults — typed `Array[WeaponData]` does **not** serialize reliably in `.tscn`,
so the array is `Array[Resource]` and cast in code). On a swap, `gun_mesh.gd` swaps its mesh
to the weapon's `hand_mesh`.

---

## Melee (`melee.tres` + `attack.gd` + `scope_in.gd`)

The melee weapon exercises most of the toggles to feel distinct:

- **Instant-hit** (no projectile travel — `projectile_life_time` = 0), **semi-auto** (`auto_fire = false` — one swing per click),
  with an **`attack_windup`** so the swing has weight (you click, a beat passes, then the
  swing lands). No muzzle flash, sparks, laser, or casing.
- **Dash** — it keeps ADS, but **attacking while scoped launches you** in the look
  direction (`launch_on_scoped_attack`). The dash:
  - immediately **exits ADS** (`scope_in.force_unscope()`), and the fire cooldown then blocks
    an instant re-scope;
  - is limited to **one airborne dash per airtime** (`single_air_dash`) — `attack.gd` also
    blocks re-entering ADS while that lockout is active, so you can't re-scope mid-air just
    to dash again;
  - applies a decaying blast impulse (the dash carries through the air like a rocket jump).
- **Fleshy hits** — because Interactables play their own impact sound, hitting a gib sounds
  meaty rather than producing the melee's metallic world-impact clang.

---

## Audio juice

- **Fire pitch by ammo** (`attack.gd`, Cruelty-Squad style) — `attack_audio.pitch_scale`
  is `lerp(fire_pitch_empty_ammo, fire_pitch_full_ammo, ammo_before / max_ammo)`. A full mag
  fires at full pitch; each shot deepens as the magazine drains. Skipped for infinite-ammo
  weapons (melee).
- **Enemy-hit pitch by HP** (`attack.gd`, `projectile.gd`) — the enemy-impact sound's pitch
  is `lerp(enemy_hit_pitch_low_hp, enemy_hit_pitch_full_hp, hp/max_hp)` *after* damage, so
  hits sound deeper as the target nears death and the killing blow is the deepest.
- **Cha-ching kill reward** (`scenes/enemies/death.gd`) — a 2D cash-register sound on the
  enemy's `died` signal (covers every kill path: shots, melee, ram, explosions).
- **Impact randomization** — generic/whiz impacts get a random pitch within a tuned range so
  repeats don't sound identical.

---

## Gore & gibs (`character.gd`, `bloody_mess.gd`, `gore_gib`)

On death, `Character.gore()` fires:

- a **blood particle burst** + ~100 falling **physics blood drops** (`bloody_mess.particles`)
  that leave decals on impact;
- a **floor blood decal** under the corpse;
- **gibs** (`spawn_gibs`) — `GIB_COUNT` interactable rigid bodies flung outward with random
  velocity/spin and a **random HP 1–2**, so some shatter on first impact and some survive.
  They're given mutual collision exceptions on spawn so they don't instantly self-damage by
  overlapping;
- a **camera-blood overlay + screen shake + freeze frame** on nearby players (distance
  falloff).

When a gib later breaks, its `destroy` signal triggers a smaller secondary burst + floor
decal (`bloody_mess._on_gore_gib_destroy`).

Separately, **per-hit splatter** (`bloody_mess.splatter_at`) places decals via raycast with
*no* physics and *no* SFX — cheap enough to call on every bullet (SMG-friendly), unlike the
heavy death burst.

---

## Interactables & pickup/throw (`Interactable.gd`, `interactable_data.gd`, `ray_cast.gd`)

**Interactables** are `RigidBody3D`s (crates, gibs) driven by an `InteractableData` resource
(HP, mass, mesh/material, impact/destroy sounds, destroy particle, `spawns_destroy_decal`).
They take damage from shots/explosions, get shoved when characters walk into them
(`Character._push_interactables`), play velocity-scaled impact sounds, and on destruction
spawn a particle, an optional scorch decal, screen shake, and a destroy sound.

**Pickup/carry/throw** (`PickupRay` in `ray_cast.gd`) — a camera RayCast detects the aimed
Interactable; hold `E` to grab, release to drop or throw (longer hold = throw impulse, tap =
gentle drop, inheriting player velocity). While held the body is a weightless frozen
kinematic chased toward a hold anchor with **collision-aware motion** (no clipping through
walls). Notable robustness fixes (documented at their call sites):

- **stack-wake** — grabbing a box from a stack wakes nearby bodies so the stack doesn't
  float;
- **grab grace** — eases the body in slowly at first to avoid clipping on pickup;
- **character shove** — a carried crate pushes characters in its path;
- **drop slide-off** — re-enabling player↔crate collision is deferred and re-checked, so a
  crate dropped on your own head nudges away instead of trapping you.

Holding an object also tightens the look pitch limit (`head.gd`) so you can't crane far
enough to clip the carried crate into the camera.

---

## Camera, shake, hit-stop & post-process

- **CameraEffects** (`camera_effects.gd`) — head-bob (speed-scaled), landing dip, dynamic
  FOV (falling widens, rising narrows, forward sprint kicks), and strafe tilt. *Note the
  ADS-FOV coupling caveat in the README.*
- **Pitch soft-ramp** (`head.gd`) — look pitch decelerates into its limit instead of slamming
  a hard clamp.
- **ScreenShake** (`screen_shake.gd`) — trauma-based; the applied magnitude is **trauma²**
  (punchy, fast-settling). The camera is a child of this node. Fed by weapon kick, landings,
  the ram bounce, interactable destruction, and nearby deaths.
- **FreezeFrame** (`freeze_frame.gd`) — hit-stop on enemy damage/death (see
  [`ARCHITECTURE.md` §7](ARCHITECTURE.md)).
- **Post-process** (`post_process.gdshader`) — one full-screen pass: downscale → posterize →
  Bayer dither → film grain → **night vision** (toggled by `N` from `player.gd`, eased in/out
  by driving a shader uniform). The grain sits *over* the retro image; night vision converts
  to an amplified green monochrome to "see in the dark".

---

## View-model (`gun_mesh.gd` + muzzle effects)

The first-person weapon is a `GunMesh` under the camera with layered procedural motion:
walk-bob, strafe roll, vertical pitch lag, mouse-sway, idle breathing, a TF2-style rim
light, and a **readiness tilt** (the muzzle droops while the weapon can't fire). On fire it
recoils; on reload it dips and rises; on swap it lowers → swaps mesh → raises (attacks stay
blocked through the raise).

Hanging off it: `MuzzleFlash` (mesh + light), `Spark` (gated together with the flash by
`has_muzzle_flash`), `MuzzleWhiz` (per-shot snap, prefers the weapon's `whiz_sound`),
`ShellDrop` (gated by `spawns_casing`), and `LaserMesh` (re-aligned to the muzzle each
frame, shown only when the flashlight is on and `has_laser_sight`). There are **no
first-person hands** in the view-model yet — placeholder capsules were prototyped under
`GunMesh`, then removed; the gun renders alone.
The whole gun hierarchy is forced onto a render layer that world decals ignore (see
[`ARCHITECTURE.md` §8](ARCHITECTURE.md)).
