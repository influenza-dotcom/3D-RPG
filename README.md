# 3D RPG (Godot 4.6)

First-person shooter prototype built in Godot 4.6. Hitscan + projectile combat over a deep "feel" layer — camera bob, screen shake, FOV kicks, decals, velocity-scaled land thuds and dust, bullet whiz, blood splatter, coyote time, jump buffer, fake bunnyhop, scope-in bullet time, and per-weapon screen shake.

## Running

1. Open `project.godot` in **Godot 4.6** or later.
2. The main scene (`scenes/game.tscn`) is the project's run scene — press **F5**.
3. On first launch Godot re-imports audio and texture assets; this takes a few seconds.

## Controls

| Action | Default key |
| --- | --- |
| Move | `W A S D` |
| Look | Mouse |
| Jump | `Space` |
| Crouch (hold) | `C` |
| Attack | `Left mouse` |
| Zoom / scope | `Right mouse` |
| Reload | `R` |
| Weapon slots 1/2/3 | `1` `2` `3` |
| Flashlight | `F` |
| Pick up / drop | `E` |
| Reset scene | `End` |

All bindings live in `project.godot` under `[input]` and rebind through Godot's *Project → Project Settings → Input Map*.

## Project layout

```
rpg/
├── project.godot
├── icon.svg
├── scenes/                    scene files (.tscn)
│   ├── game.tscn              entry scene
│   ├── Level.tscn             sample level
│   ├── player/                Player.tscn, bloody_mess, freeze_frame, shell_drop, flash_light, ray_cast
│   ├── enemies/               enemy.tscn, death, damage
│   ├── projectiles/           Projectile.tscn, rock_projectile, sphere_projectile, bullet_casing
│   ├── effects/               explosion_area, blood, blood_drop, bloody_mess, dust*, screen_shake_area, spark_attack
│   └── decals/                bullet_hole_decal, blood_splat_decal, blood_light
├── scripts/                   game logic (.gd)
│   ├── autoload/              game_tuning.gd (global feel knobs + multiplayer-friendly toggles)
│   ├── player/                player, character, head, crouch, coyote_time, jump_buffer, bullet_time, bunnyhop, player_debug
│   ├── combat/                weapon_data, weapon_system, attack, ammo, reload, inventory, swap_weapons, scope_in
│   ├── projectiles/           projectile, projectile_spawner, rock_projectile, bullet_casing
│   ├── effects/               explosion, explosion_area, explosion_mesh, muzzle_flash, muzzle_whiz, gun_mesh,
│   │                          bullet_hole_decal, blood_drop, blood_splatter
│   ├── camera/                camera_effects, screen_shake
│   ├── input/                 mouse_input
│   └── ui/                    ui
├── resources/
│   ├── weapons/               pistol.tres, shotgun.tres, smg.tres, rock_weapon.tres
│   ├── materials/             bloodmat, bulletmat
│   └── shaders/               enemy.gdshader
├── tests/                     GUT smoke suite (64 tests / 157 asserts)
└── assets/
	├── audio/                 *.mp3, *.wav
	└── textures/              *.png
```

## Architecture

### Player composition

The `Player` (CharacterBody3D, extends `Character`) is a container. Character-level concerns live directly under it; combat/weapon concerns are grouped under a single `Weapon` (`WeaponSystem`) sub-node.

```
Player
├── Crouch                     capsule resize + ceiling shape-cast
├── CoyoteTime                 post-edge jump window
├── JumpBuffer                 pre-landing jump queue
├── BulletTime                 scoped + airborne → slo-mo
├── Bunnyhop                   forward + crouch + jump → chain speed boost (capped)
├── MouseInput                 mouse motion + click forwarding, speed-scaled sensitivity
├── Head                       pitch
│   └── ScreenShake            shake pivot (composes cleanly with tilt + bob)
│       └── Camera3D           + CameraEffects, GunMesh, FlashLight, LightPosition, FallingAirSFX
│           └── Muzzle         + MuzzleFlash + MuzzleWhiz (player-side bullet snap)
├── Weapon  (WeaponSystem)     facade over the combat system
│   ├── Inventory              currently equipped Weapon resource
│   ├── Ammo                   per-weapon ammo counts (Dictionary, persisted across swaps)
│   ├── Attack                 hitscan, spread, fire/reload/swap gating, per-weapon screen kick
│   ├── Reload                 R input → reload signal
│   ├── SwapWeapons            1/2/3 input → equip_this signal
│   ├── ScopeIn                RMB → FOV lerp + scope spread + scoped_in signal
│   └── ProjectileSpawner      spawns the visual projectile after a hitscan
├── WalkingSFX / JumpSFX / LandSFX
└── UI                         hp + ammo labels + BloodSplatter overlay
```

`Player` and `Weapon` wire their typed `@export` references in `_enter_tree()` so any outside system has a single seam to talk to combat through. There are no `../`-relative NodePaths anywhere in gameplay code.

Inter-node communication is **all signals**, wired in `Player.tscn`. `attack.gd` is the gating hub — it owns the fire / reload / swap cooldown timers and emits `reload_started`, `swap_started`, `swap_finished`, `flash_muzzle`, and `shell_particle` for downstream visuals/audio to consume.

### Feel layer

- **Coyote time + jump buffer.** `Player._physics_process` only jumps when *both* `coyote_time.can_jump()` and `jump_buffer.wants_jump()` are true, then `consume()`s both.
- **Aim-down-sights slowdown.** While `ScopeIn.is_scoped` is true `target_speed` multiplies by `SCOPE_SPEED_MULT`.
- **Bullet time.** `BulletTime` is a state machine (`READY → ACTIVE → EXHAUSTED`) that ramps `Engine.time_scale` toward `BULLET_TIME_SCALE` when scoped *and* airborne, capped at `BULLET_TIME_DURATION` and shot-cancelled by `flash_muzzle`. Recovery lerp uses a real-time `Time.get_ticks_usec()` delta. BulletTime only writes `time_scale` while it claims ownership (`_managing_time_scale`), so `FreezeFrame` hits don't get clobbered.
- **Bunnyhop.** Forward + recently-pressed crouch + jump chains a speed boost (`BHOP_BOOST_PER_HOP` per hop, capped at `BHOP_MAX_SPEED`). Chain breaks the moment any of those preconditions fails. At high speeds `MouseInput` softens mouse sensitivity (`SENS_REDUCTION_THRESHOLD` → `SENS_MIN_MULTIPLIER`).
- **Velocity-scaled landing.** Land impact drives both the SFX volume/pitch (`LAND_SFX_*`) and the puff of dust (`DUST_LAND_*`) — tiny stutter-landings are silent and dustless; full-speed splats hit hard.
- **Falling air.** `FallingAirSFX` ramps its volume in real time as `velocity.y` goes more negative, gated by `FALLING_AIR_MIN_FALL_SPEED`.
- **Bullet whiz (Doppler).** Each `Projectile` carries a `WhizSFX` with `doppler_tracking = PHYSICS_STEP`, and a `MuzzleWhiz` at the player's gun fires a randomly-pitched snap on every shot for shooter-side feedback.
- **Screen shake** lives on its own pivot node between `Head` and `Camera3D`. Trauma sources: per-weapon `screen_shake_amount`, explosion area falloff, and nearby enemy deaths (distance-falloff curve, capped at `DEATH_SHAKE_RANGE`).
- **Blood splatter on camera.** When an enemy dies within `BLOOD_SPLATTER_RANGE`, `Character._notify_nearby_players_of_death()` calls back into the player's UI to spawn blob `TextureRect`s with random rotations and a fade tween.
- **FOV kicks** for jumping, falling, and forward sprinting in `camera_effects.gd`.
- **Frame-rate independence.** Movement smoothing, blast decay, decal fade, scope FOV, enemy friction, flashlight follow, and all camera effects use either `1 - pow(1 - rate, delta * 60)` or `1 - exp(-rate * delta)` so feel doesn't drift between 60 / 144 / 240 Hz.

### `GameTuning` autoload

Hard-coded gameplay values live in [`scripts/autoload/game_tuning.gd`](scripts/autoload/game_tuning.gd) as `const`s — rebalance the whole game by editing one file:

```gdscript
const PLAYER_MAX_SPEED: float = 5.0
const SCOPE_SPEED_MULT: float = 0.4
const BULLET_TIME_SCALE: float = 0.4
const BULLET_TIME_DURATION: float = 1.0
const BHOP_BOOST_PER_HOP: float = 1.2
const BHOP_MAX_SPEED: float = 12.0
const DEATH_SHAKE_RANGE: float = 8.0
const DEATH_SHAKE_AMOUNT: float = 1.6
const BLOOD_SPLATTER_RANGE: float = 3.5
const LAND_SFX_MIN_IMPACT_TO_PLAY: float = 0.08
...
```

One runtime `var` lives alongside the consts:

```gdscript
var allow_timescale_changes: bool = true
```

`BulletTime` and `FreezeFrame` both honor it. Flip it to `false` to make every system that touches `Engine.time_scale` a no-op (forward-thinking toggle for multiplayer, where global time-scale is generally a bad idea).

Per-instance, per-weapon, and per-scene values stay as `@export` on the relevant node or resource. Example: `Character.blast_damp_divisor` is `@export`'d so the player retains horizontal momentum after a blast (1.12) while the enemy resets it (1.0).

### Weapons as resources

Each weapon is a `Resource` (`scripts/combat/weapon_data.gd`) — `pistol.tres`, `shotgun.tres`, `smg.tres`, `rock_weapon.tres`. Per-weapon ammo is persisted across swaps by `ammo.gd`. Each `WeaponData` carries an optional `hand_mesh: Mesh`; on `swap_finished` the `GunMesh` swaps its `mesh` to match. Each weapon also declares its own `screen_shake_amount` so the shotgun kicks harder than the SMG.

### Strong typing

Every system has a `class_name` so `@export` references are checked at scene-load: `Character`, `Player`, `Ammo`, `Inventory`, `Attack`, `Crouch`, `WeaponSystem`, `WeaponData`, `ScopeIn`, `CameraEffects`, `ScreenShake`, `Projectile`, `ProjectileSpawner`, `Explosion`, `ExplosionMesh`, `GunMesh`, `UI`, `CoyoteTime`, `JumpBuffer`, `BulletTime`, `Bunnyhop`, `MouseInput`, `BloodSplatter`, `ShellDrop`, `Reload`, `SwapWeapons`, `Head`, `PlayerDebug`, `Interactable`. The static analyzer complains immediately if you wire the wrong node into the wrong slot.

## Tests

The project ships with a GUT (Godot Unit Test) smoke suite at `tests/test_smoke.gd` — 64 tests / 157 asserts covering scene structure, state machines, falloff math, time-scale ownership, signal wiring, and decal orientation.

Run headless from the project root:

```cmd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

A double-clickable wrapper lives at `tests/run.cmd`.

## Roadmap

- Extract `Weapon` into its own `Weapon.tscn` sub-scene so multiple characters can drop it in.
- Enemy AI (currently `enemy.gd` only takes damage and dies).
- Pick-up / drop system (the scaffolding under `ray_cast.gd` + `Interactible.gd` is there; not wired up yet).
- Save / load.
