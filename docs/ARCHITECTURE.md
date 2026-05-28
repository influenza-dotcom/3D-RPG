# Architecture

How the project is wired. For *what each gameplay system does*, see
[`SYSTEMS.md`](SYSTEMS.md).

---

## 1. Composition over inheritance

The `Player` is a `CharacterBody3D` that extends the shared **`Character`** base
(`scripts/player/character.gd`). It is mostly a *container*: each concern is its own
typed node, so systems can be added, removed, or reused without touching a monolith.

```
Player  (CharacterBody3D : Character)              [scripts/player/player.gd]
├── CollisionShape3D
├── Crouch              capsule resize + ceiling shape-cast + slide       [crouch.gd]
├── CoyoteTime          post-ledge jump window                           [coyote_time.gd]
├── JumpBuffer          pre-landing jump queue                           [jump_buffer.gd]
├── Bunnyhop            timed re-jump speed chain                        [bunnyhop.gd]
├── BulletTime          airborne-ADS slow-mo state machine               [bullet_time.gd]
├── MouseInput          mouse-look + fire input, speed-scaled sensitivity[mouse_input.gd]
├── bowling             AudioStreamPlayer3D — ram-KILL "strike" sfx
├── JumpSFX / LandSFX / WalkingSFX
├── Head                vertical look (pitch), pitch soft-ramp           [head.gd]
│   └── ScreenShake     shake pivot (rotates the camera)                 [screen_shake.gd]
│       └── Camera3D    first-person camera + FOV/bob/tilt               [camera_effects.gd]
│           ├── GunMesh           view-model pose/anim/rim-light         [gun_mesh.gd]
│           │   └── Sketchfab_Scene (gun model)   (no first-person hands yet)
│           │       └── Muzzle → Spark, ShellDrop, MuzzleFlash, MuzzleWhiz
│           ├── LaserMesh         laser-sight cone, tracks the muzzle    [laser_mesh.gd]
│           ├── FlashLight        toggled spot + laser-sight gate        [flash_light.gd]
│           ├── FallingAirSFX     wind swell while falling
│           ├── white flash       hit-flash sprite
│           └── RayCast (PickupRay) + HoldAnchor   carry/throw props     [ray_cast.gd]
├── Weapon  (WeaponSystem)        facade over the combat system          [weapon_system.gd]
│   ├── Inventory       equipped WeaponData + weapon_changed signal      [inventory.gd]
│   ├── Ammo            per-weapon ammo counts, persisted across swaps   [ammo.gd]
│   ├── Attack          the combat hub (see §3) + Attack/Reload/Swap Timers [attack.gd]
│   ├── Reload          "Reload" input → reload signal                   [reload.gd]
│   ├── SwapWeapons     "Weapon Slot N" input → equip_this signal        [swap_weapons.gd]
│   ├── ScopeIn         ADS FOV + spread + scoped_in signal              [scope_in.gd]
│   └── ProjectileSpawner  spawns the visual/long-range projectile       [projectile_spawner.gd]
├── Shadow              blob-shadow Decal under the player
└── UI  (CanvasLayer)   HP/Ammo labels + overlays                        [ui.gd]
    ├── BloodSplatter   on-hurt screen blood blobs                       [blood_splatter.gd]
    ├── FilmGrain       legacy ColorRect (hidden; merged into ColorRect)
    └── ColorRect       post-process: downscale + dither + grain + night-vision
```

Enemies extend the same `Character` base (`scenes/enemies/enemy.gd`) and so inherit HP,
the damage flash + outline, the blast system, and the gore spawn for free — they only add
friction-based drift and hit-stop.

### Wiring rule

`Player._enter_tree()` and `WeaponSystem._enter_tree()` assign every typed `@export`
reference (and connect a couple of signals). Consequences:

- **No `../`-relative `NodePath`s in gameplay code** — the scene tree can be rearranged
  without breaking script lookups.
- `WeaponSystem` is the single seam an outside system talks to combat through.
- A few effect nodes that need the equipped weapon (MuzzleFlash, MuzzleWhiz, Spark) get
  their `inventory` reference injected here too.

---

## 2. The `Character` base

`scripts/player/character.gd` provides, for both Player and Enemy:

- **HP + death** — `take_damage()` latches `_dead` so a multi-hit frame (e.g. a shotgun's
  9 pellets) can only kill / gib once. `die()` emits `died`.
- **Damage flash + outline** — built once in `_setup_overlay_chain()` as a single
  `material_overlay` (the outline material's `next_pass` is the flash material), applied
  to every child `MeshInstance3D`. Hits drive only the flash uniform.
- **The blast system** — see §5.
- **Gore** — `gore()` spawns the death blood burst, floor decal, gibs, and notifies nearby
  players (camera blood + shake + freeze).

`@export var blast_damp_divisor` is the one knob deliberately left per-instance: the player
sets `1.12` (keeps horizontal momentum after a blast — good for rocket jumps) while the
enemy sets `1.0` (knockback bleeds off fast so they don't fly forever).

---

## 3. Signals: `attack.gd` is the hub

Combat is event-driven. `Attack` owns three `Timer`s (fire cooldown, reload, swap) that
gate everything, and broadcasts what happened for visuals/audio to react to:

| Signal | Emitted when | Consumers |
| --- | --- | --- |
| `flash_muzzle` | a shot fires | MuzzleFlash, Spark, MuzzleWhiz, **BulletTime** (ends slow-mo) |
| `shell_particle` | a shot fires *and* `spawns_casing` | ShellDrop |
| `spawn_projectile` | per pellet | ProjectileSpawner |
| `reload_started` | reload begins | GunMesh (dip the gun) |
| `swap_started` / `swap_finished` | weapon swap phases | GunMesh (lower → swap mesh → raise) |
| `play_animation` | a shot fires | GunMesh (recoil) |

Input adapters are deliberately thin: `MouseInput` emits `rotate`/`attack`, `Reload` emits
`reload`, `SwapWeapons` emits `equip_this`, `ScopeIn` emits `scoped_in`. `Inventory` emits
`weapon_changed`, which Ammo / Attack / ProjectileSpawner / GunMesh / FlashLight all derive
their per-weapon state from.

---

## 4. Autoloads

Declared in `project.godot → [autoload]`, in this order:

```
AudioManager → EffectFactory → InputManager → GameSettings → FreezeFrame
```

| Autoload | Role |
| --- | --- |
| **GameSettings** | Central tuning registry — exposes the 9 settings resources (§6) plus `allow_timescale_changes`. |
| **AudioManager** | `play_sfx(pos, stream, db, pitch)` (3D) / `play_2d_sfx(stream, db, pitch)` (2D) spawn an ephemeral player that frees on `finished`. Use instead of per-scene `AudioStreamPlayer` nodes. |
| **EffectFactory** | `@export` `PackedScene` slots for every effect (blood, dust, decals, gibs, explosions) + `spawn_*` helpers. Swap an effect globally by reassigning a slot. |
| **InputManager** | Action-name `StringName`s + thin `Input` wrappers, so action strings live in one place. |
| **FreezeFrame** | Hit-stop — slams `Engine.time_scale` down then eases it back (see §7). |

### Init-order rule (important)

`GameSettings` loads its resources via **`preload()` field initializers**, *not* in
`_ready()`:

```gdscript
var player_movement: PlayerMovementSettings = preload("res://resources/tuning/PlayerMovementSettings.tres")
```

This matters because scripts evaluate `var x = GameSettings.foo.bar` during *construction*
(`@implicit_new`), which runs **before** any autoload `_ready()`. Loading in `_ready()`
would be too late and produce `Invalid access … on a base object of type 'Nil'` at
startup. `GameSettings` is last in the autoload list because nothing else reads from it at
load time.

---

## 5. The blast system (`explosion_velocity`)

The single mechanism behind rocket jumps, the melee dash, slide-jumps, the pinball ram
bounce, explosion knockback, and enemy knockback. Defined on `Character`:

- Systems **add** an impulse to `explosion_velocity` (a decaying velocity layered on top of
  normal movement). They never overwrite controller velocity.
- `apply_blast()` (each physics frame, before the move) re-arms a **grace timer** when the
  impulse is sizable — so a fresh blast survives a frame or two even on the ground (the ram
  bounce needs this) — then eases the impulse toward zero. Once grounded *and* past grace it
  hard-zeroes (you stop sliding after landing).
- `apply_velocity()` adds the impulse for the current frame's `move_and_slide`, pushes any
  rigid bodies hit, then subtracts `explosion_velocity / blast_damp_divisor` so it bleeds
  off over time.

`_push_interactables()` captures the **pre-move** velocity, because `move_and_slide` zeroes
velocity into surfaces — the original speed is what determines how hard a walked-into crate
gets shoved.

---

## 6. Data-driven tuning

Feel constants live in nine `Resource` (`.tres`) files in `resources/tuning/`, each with a
matching `*Settings.gd` script. `GameSettings` loads them once; code reads
`GameSettings.<group>.<field>`.

| Resource | Governs | Read by |
| --- | --- | --- |
| `PlayerMovementSettings` | speeds, jump, coyote/buffer windows, smoothing, footsteps, landing divisor | player.gd, coyote/jump_buffer |
| `PlayerCrouchSettings` | crouch height/speed/lerp, ceiling clearance, quiet footsteps | crouch.gd |
| `BunnyhopSettings` | boost-per-hop, max bhop speed, land window, speed→sensitivity falloff | bunnyhop.gd, mouse_input.gd |
| `CameraSettings` | FOV (default/scoped + kicks), bob, tilt, pitch limits + soft ramp, sensitivity | camera_effects, head, scope_in |
| `ScreenShakeSettings` | trauma decay/intensity, death-shake range/amount, explosion shake | screen_shake, explosion, screen_shake_area |
| `WeaponGeneralSettings` | swap time, muzzle-flash duration, scope spread/speed, bullet-time scale/duration | attack, scope_in, bullet_time |
| `EffectsSettings` | decal fade/probe, dust, blood-overlay tint/scale, explosion flash | effects scripts, bloody_mess, decals |
| `AudioSettings` | landing/falling-air SFX, whiz pitch, impact pitch (incl. enemy-hit-by-HP), fire pitch (by ammo) | player, attack, projectile, muzzle_whiz |
| `PhysicsDamageSettings` | explosion damage, blast decay, enemy friction, ram, pickup/throw, interactable rules | character, player, enemy, ray_cast, Interactable, explosion |

One runtime flag lives directly on `GameSettings`:

```gdscript
var allow_timescale_changes: bool = true
```

Both `BulletTime` and `FreezeFrame` honor it; set `false` to make every `Engine.time_scale`
writer a no-op (headless tests do this; also useful if multiplayer is ever added).

Per-weapon, per-prop, and per-instance values stay as `@export` on `WeaponData`,
`InteractableData`, or the node (e.g. `blast_damp_divisor`).

---

## 7. Time-scale orchestration

Three systems touch the **global** `Engine.time_scale`; they coordinate via ownership and
real-time measurement:

- **BulletTime** eases `time_scale` toward the slow-mo target while active, and only writes
  it while `_managing_time_scale` is true — so it restores to `1.0` only if it was the one
  that lowered it. It measures elapsed time with the **wall clock** (`Time.get_ticks_usec()`)
  rather than the scaled frame `delta`; using `delta` would feed the slow-mo back into its
  own duration. Its node `process_mode` is `ALWAYS`.
- **FreezeFrame** (hit-stop) stomps `time_scale` to a low value, waits on a *real-time*
  `SceneTreeTimer` (`ignore_time_scale = true`), then tweens back to `1.0` (also ignoring
  time-scale). A freeze fired during bullet time overrides it and returns to full speed.
- **ParticleTimeBind** (`particle_time_bind.gd`) multiplies a `GPUParticles3D`'s
  `speed_scale` by `Engine.time_scale` every frame (also `process_mode = ALWAYS`) so
  particle effects visibly slow during slow-mo/freezes instead of finishing at full speed.

---

## 8. Rendering & render layers

- **Low internal resolution.** `project.godot` sets a 396×216 viewport with `viewport`
  stretch and scale 0.5 — the source of the chunky pixel look, on top of the post-process.
- **Post-process.** One full-screen `ColorRect` under the UI runs
  `resources/shaders/post_process.gdshader`: UV-quantize downscale → posterize → 4×4 Bayer
  dither → film grain → optional night-vision tint. Night vision is a uniform driven from
  `player.gd` (toggled by `N`, eased in/out). The older standalone `FilmGrain` ColorRect is
  hidden — its effect was merged in to avoid an opaque pass overwriting it.
- **The gun ignores world decals.** The `GunMesh` lives on render layer 3 (value `4`); the
  player's `Shadow` decal's `cull_mask` (`1048571`) excludes exactly that layer. Because
  imported submeshes default to layer 1, `gun_mesh.gd` walks its descendants and forces
  them all onto the gun layer (and disables their shadows). This stops the blob shadow from
  projecting onto the weapon when crouching brings the gun near the floor.
- World decals (blood, bullet holes, scorch) use `cull_mask = 2`, the world's decal layer.

---

## 9. Frame-rate independence

Every smoothed value uses one of:

- `t = 1.0 - exp(-rate * delta)` — exponential ease toward a target, or
- `t = 1.0 - pow(1.0 - rate, delta * 60.0)` — the same idea expressed against a 60 fps
  reference (used by movement smoothing / blast decay).

This keeps movement, blast decay, decal fade, scope FOV, enemy friction, camera effects,
and the flashlight follow feeling identical at 60 / 144 / 240 Hz. Timing-sensitive
slow-mo logic additionally uses the wall clock (§7).

---

## 10. Strong typing

Nearly every script declares a `class_name`, so `@export` slots are type-checked at
scene-load and mis-wiring fails loudly: `Character`, `Player`, `Enemy`, `WeaponSystem`,
`WeaponData`, `InteractableData`, `Attack`, `Ammo`, `Inventory`, `Reload`, `SwapWeapons`,
`ScopeIn`, `ProjectileSpawner`, `Projectile`, `Explosion`, `ExplosionMesh`, `GunMesh`,
`CameraEffects`, `ScreenShake`, `CoyoteTime`, `JumpBuffer`, `BulletTime`, `Bunnyhop`,
`Crouch`, `Head`, `MouseInput`, `PickupRay`, `BloodSplatter`, `ShellDrop`, `Interactable`,
`UI`, `PlayerDebug`, plus the nine `*Settings` resource classes.
