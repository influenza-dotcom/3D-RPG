# RPG — first-person shooter prototype (Godot 4.6)

A single-player FPS prototype built in **Godot 4.6**, rendered at a deliberately low
internal resolution (396×216, integer-scaled) for a crunchy retro look. The codebase
is small but the **"game feel" layer is deep**: hitscan + projectile combat, a momentum
movement kit (coyote time, jump buffer, bunnyhop, crouch-slide, slide-jump), aim-down-
sights bullet time, a pinball-style ram bounce, gibbing gore, physics props you can
carry and throw, and a screen-space post-process that stacks pixel-downscale + dither +
film grain + a togglable night-vision mode.

Almost every number that affects feel lives in editable `.tres` resources, not code.

> **Documentation:** this README is the overview. For depth see
> [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (how the project is wired) and
> [`docs/SYSTEMS.md`](docs/SYSTEMS.md) (how each gameplay system works).

---

## Running

1. Open `project.godot` in **Godot 4.6** (Forward+ renderer).
2. The run scene is `scenes/game.tscn`. Press **F5**.
3. First launch re-imports audio/textures — give it a few seconds.

The window is small and non-resizable by design (`viewport` stretch, scale 0.5). The
retro pixelation comes from this low internal resolution plus the post-process shader.

---

## Controls

| Action | Default |
| --- | --- |
| Move | `W` `A` `S` `D` |
| Look | Mouse |
| Jump | `Space` |
| Crouch / **Slide** (hold) | `Shift` |
| Attack / fire | Left mouse |
| Aim down sights (ADS) | Right mouse (hold) |
| Reload | `R` |
| Weapon slots 1–5 | `1` `2` `3` `4` `5` |
| Flashlight | `F` |
| Night vision | `N` |
| Pick up / drop / throw | `E` (or `G`) |
| Debug: reload scene | `End` |

Bindings live in `project.godot` under `[input]` and can be rebound via
*Project → Project Settings → Input Map*. Action-name strings are also mirrored in
`managers/InputManager.gd` — if you rename an action, change it in both places.

---

## Feature tour

- **Movement kit** — accel/air-smoothed WASD with frame-rate-independent damping;
  **coyote time** and **jump buffering** for forgiving jumps; a **bunnyhop** chain that
  rewards re-jumping in a tight window after landing with capped speed gains.
- **Crouch-slide** — land at speed while holding crouch to slide; the slide decays via
  friction, any movement key cancels it, and **jumping out of a slide launches you
  forward** proportional to your slide speed.
- **Bullet time** — entering ADS *while airborne* eases global time-scale into slow-mo
  for a "dive and shoot" moment; the first shot ends it.
- **Ram & bounce** — moving fast into an enemy body-checks it (damage scales with speed;
  a kill triggers a bowling-pin strike sound, a survivor a heavy thud). Ramming walls /
  objects / enemies at speed **bounces you back, pinball-style**.
- **Weapons as data** — pistol, shotgun, SMG, rock launcher, and a melee weapon are all
  `WeaponData` resources. Per-weapon toggles cover full/semi-auto fire, muzzle flash,
  laser sight, shell ejection, attack wind-up, and a scoped-attack launch (the melee
  *dash*).
- **Audio juice** — the fire sound deepens as the magazine empties (Cruelty-Squad style),
  enemy-hit pitch deepens as the target nears death, and a kill plays a "cha-ching".
- **Gore** — enemies burst into physics **gibs** (random fragility, some shatter on
  impact) plus a blood-particle burst, falling blood drops, and floor decals; bullets
  leave cheap raycast splatter.
- **Physics props** — crates (and gibs) are `Interactable` rigid bodies you can shoot,
  shove by walking into them, and **carry/throw** (hold `E` to grab, release to drop or
  fling — longer hold = harder throw).
- **Camera & screen FX** — head-bob, landing dip, dynamic FOV kicks, strafe tilt,
  trauma-based screen shake, hit-stop freeze frames, and a combined dither + film-grain +
  night-vision post-process.

See [`docs/SYSTEMS.md`](docs/SYSTEMS.md) for how each of these works and which scripts own them.

---

## Project layout

```
rpg/
├── project.godot                 autoloads, input map, render/window config
├── scenes/
│   ├── game.tscn                 run scene
│   ├── Level.tscn                sample level
│   ├── player/                   Player.tscn + player-side nodes (bloody_mess, ray_cast,
│   │                             flash_light, shell_drop, laser_mesh, freeze_frame, …)
│   ├── enemies/                  enemy.tscn + death/damage SFX adapters
│   ├── projectiles/              Projectile/rock/casing scenes
│   ├── effects/                  explosion_area, dust, blood, gore_gib, spark, screen_shake_area
│   └── decals/                   blood_splat_decal, blood_light
├── managers/                     autoload singletons
│   ├── GameSettings.gd           loads + exposes the 9 tuning resources
│   ├── AudioManager.gd           one-shot SFX spawners that auto-free
│   ├── EffectFactory.gd          PackedScene slots + spawn helpers
│   └── InputManager.gd           action-name registry + Input wrappers
├── scripts/
│   ├── player/                   player, character (base), head, crouch, coyote_time,
│   │                             jump_buffer, bullet_time, bunnyhop, player_debug
│   ├── combat/                   weapon_data, weapon_system, attack, ammo, reload,
│   │                             inventory, swap_weapons, scope_in, interactable_data,
│   │                             Interactable.gd (@tool base for destructible/throwable props)
│   ├── projectiles/              projectile, projectile_spawner, rock_projectile, bullet_casing
│   ├── effects/                  gun_mesh, muzzle_flash, muzzle_whiz, explosion(_mesh/_area),
│   │                             blood_drop, blood_splatter, bullet_hole_decal, particle_time_bind
│   ├── camera/                   camera_effects, screen_shake
│   ├── input/                    mouse_input
│   └── ui/                       ui
├── resources/
│   ├── tuning/                   9 *Settings.gd + matching .tres  (data-driven tuning)
│   ├── weapons/                  pistol/shotgun/smg/rock/melee .tres  (WeaponData)
│   ├── interactables/            crate/gib .tres  (InteractableData)
│   ├── materials/                bloodmat, bulletmat, shell_brass
│   └── shaders/                  post_process, film_grain, outline, rim_light, flash_overlay, laser, pixel
├── tests/                        GUT smoke suite (test_smoke.gd)
├── addons/gut/                   vendored Godot Unit Test framework (third-party)
└── assets/                       audio/, textures/, model .glb files
```

---

## Architecture at a glance

- **Composition over inheritance.** The `Player` (a `CharacterBody3D` extending the shared
  `Character` base) is a container; each concern — crouch, coyote time, bullet time, the
  whole `Weapon` sub-tree — is its own typed node. Refs are wired in `_enter_tree()`, so
  there are no `../`-relative paths in gameplay code.
- **Signals, not polling.** `attack.gd` is the combat hub: it owns the fire/reload/swap
  cooldown timers and emits `flash_muzzle`, `shell_particle`, `reload_started`,
  `swap_started`, `swap_finished`, `spawn_projectile` for downstream visuals/audio.
- **Data-driven tuning.** Feel constants live in nine `Resource` files under
  `resources/tuning/`, loaded once by the `GameSettings` autoload and read as
  `GameSettings.<group>.<field>`. Rebalance by editing a `.tres` — no recompile.
- **Strong typing.** Nearly every script has a `class_name`, so wiring the wrong node into
  an `@export` slot fails at scene-load instead of at runtime.
- **Frame-rate independence.** Every eased value uses `1 - exp(-rate*dt)` or
  `1 - pow(1-rate, dt*60)`, so feel doesn't drift across 60/144/240 Hz.

Full detail — node tree, signal graph, autoload order, the time-scale ownership rules, the
blast-impulse system, and the gun render-layer trick — is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## How to…

**Rebalance the game** — open `resources/tuning/<Group>Settings.tres`, edit a field, save.

**Add / change a weapon** — duplicate a `.tres` in `resources/weapons/`, edit its
`WeaponData` fields (damage, `attack_speed`, `pellet_count`/`pellet_spread`, knockback,
`screen_shake_amount`, and the per-weapon toggles below), then assign it to a slot on
`SwapWeapons.weapon_slots`. Per-weapon toggles: `auto_fire` (false = semi-auto/per-click),
`has_muzzle_flash`, `has_laser_sight`, `spawns_casing`, `attack_windup`, `single_air_dash`,
`launch_on_scoped_attack` (+ `launch_force`/`launch_upward`), `use_hitscan`.

**Add a destructible prop** — duplicate an `InteractableData` `.tres` in
`resources/interactables/` (HP, mass, mesh/material, impact/destroy sounds, destroy
particle, `spawns_destroy_decal`) and point an `Interactable`-scripted RigidBody3D at it.

**Replace a visual effect globally** — reassign the `PackedScene` slot on the
`EffectFactory` autoload (e.g. `blood_decal`, `gib`, `explosion_area`); every call site
that uses the factory's helpers picks it up.

**Add a one-shot sound** — call `AudioManager.play_sfx(pos, stream, db, pitch)` (3D) or
`AudioManager.play_2d_sfx(stream, db, pitch)` (2D) instead of wiring an
`AudioStreamPlayer` node — they spawn an ephemeral player that frees itself.

**Rebind a key** — change it in *Project Settings → Input Map* **and** keep the matching
`StringName` in `InputManager.gd` consistent.

---

## Tests

A GUT (Godot Unit Test) smoke suite lives at `tests/test_smoke.gd`. Each test guards a
load-bearing invariant and its assert message explains *why*, so the file doubles as
documentation of cross-system contracts (enemy blast damp, weapon-data shape, the
nearby-death trauma/freeze behaviour, decal orientation, …).

Run headless from the project root:

```cmd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

The GUT framework under `addons/gut/` is vendored third-party code.

---

## Known rough edges

Tracked in-code as `TODO` comments (documented, not yet fixed):

- `camera_effects.gd` and `scope_in.gd` both write `camera.fov` each frame, so ADS zoom
  and the movement-FOV kicks partially cancel while scoped.
- `Character.apply_velocity_launch_forward()` is unused and asymmetric (dead code).
- `FreezeFrame.timer` is created but never used.
- Melee uses `INT_MIN` as an "infinite ammo" sentinel in `ammo.gd`, relying on signed
  integer overflow wraparound.
- The view-model shows the **gun only** — there are no first-person hands (placeholder
  capsules were prototyped under `GunMesh`, then removed).

## Roadmap

- Enemy AI — `enemy.gd` currently has no locomotion; enemies only react to knockback and
  damage.
- Real first-person arm/hand meshes (the view-model currently has none).
- Save / load.
- Extract the `Weapon` sub-tree into its own scene so non-player actors can reuse it.
