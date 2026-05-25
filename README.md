# 3D RPG (Godot 4.6)

First-person shooter prototype built in Godot 4.6 with a small set of weapons, hitscan + projectile combat, and a custom feel layer (camera bob, screen shake, FOV kicks, decals, coyote-time, jump-buffer, bullet-time, etc).

## Running

1. Open `project.godot` in **Godot 4.6** or later.
2. The main scene (`scenes/game.tscn`) is set as the project's run scene — press **F5** or hit Play.
3. On first launch Godot will re-import audio and texture assets; this takes a few seconds.

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
| Reset scene | `End` |

All bindings live in `project.godot` under `[input]` and can be rebound through Godot's *Project → Project Settings → Input Map*.

## Project layout

```
rpg/
├── project.godot
├── icon.svg
├── scenes/                  scene files (.tscn)
│   ├── game.tscn            entry scene
│   ├── Level.tscn           sample level
│   ├── player/              Player.tscn, Character.tscn, bloody_mess, freeze_frame, shell_drop
│   ├── enemies/             enemy.tscn, death
│   ├── projectiles/         Projectile.tscn, rock_projectile.tscn, sphere_projectile.tscn, bullet_casing.tscn
│   ├── effects/             explosion_area.tscn, blood.tscn, blood_drop.tscn, bloody_mess.tscn, dust*.tscn, screen_shake_area
│   └── decals/              bullet_hole_decal, blood_hole_decal, blood_splat_decal, scorch_mark_decal
├── scripts/                 game logic (.gd)
│   ├── autoload/            game_tuning.gd (global feel knobs)
│   ├── player/              player, character, head, crouch, coyote_time, jump_buffer, bullet_time, player_debug
│   ├── combat/              weapon_data, weapon_system, attack, ammo, reload, inventory, swap_weapons, scope_in
│   ├── projectiles/         projectile, projectile_spawner, rock_projectile, bullet_casing
│   ├── effects/             explosion, explosion_area, explosion_mesh, muzzle_flash, gun_mesh, bullet_hole_decal, blood_drop
│   ├── camera/              camera_effects, screen_shake
│   ├── input/               mouse_input
│   └── ui/                  ui
├── resources/
│   ├── weapons/             pistol.tres, shotgun.tres, smg.tres, rock_weapon.tres
│   ├── materials/           bloodmat, bulletmat
│   └── shaders/             enemy.gdshader
└── assets/
	├── audio/               *.mp3, *.wav
	└── textures/            *.png
```

## Architecture

### Player composition

The `Player` (CharacterBody3D, extends `Character`) is a container. Character-level concerns sit directly under it; combat/weapon concerns are grouped under a single `Weapon` (`WeaponSystem`) sub-node:

```
Player
├── Crouch                  capsule resize + ceiling check
├── CoyoteTime              brief post-edge jump window
├── JumpBuffer              brief pre-landing jump queue
├── BulletTime              slo-mo when scoped in mid-air
├── MouseInput              rotation + attack input forwarding
├── Head                    pitch
│   └── ScreenShake         shake offset (own pivot — composes cleanly with tilt)
│       └── Camera3D        + CameraEffects, GunMesh, lights
│           └── Muzzle      + MuzzleFlash visual
├── Weapon  (WeaponSystem)  facade over the combat system
│   ├── Inventory           currently equipped Weapon resource
│   ├── Ammo                per-weapon ammo counts (Dictionary)
│   ├── Attack              hitscan, spread, fire/reload/swap gating
│   ├── Reload              R-key input → reload signal
│   ├── SwapWeapons         1/2/3 input → equip_this signal
│   ├── ScopeIn             RMB → FOV lerp + scope spread + scoped_in signal
│   └── ProjectileSpawner   spawns the visual projectile after a hitscan
└── UI                      hp + ammo labels
```

`Player` and `Weapon` both wire their typed `@export` references in `_enter_tree()` so any outside system has a single seam to talk to combat through.

Inter-node communication is **all signals**, wired in `Player.tscn`. `attack.gd` is the gating hub — it owns the fire / reload / swap cooldown timers and emits `reload_started`, `swap_started`, `swap_finished` for the gun-mesh animator to consume.

### Feel layer

- **Coyote time + jump buffer.** `coyote_time.gd` and `jump_buffer.gd` are small siblings; `Player._physics_process` only jumps when *both* `coyote_time.can_jump()` and `jump_buffer.wants_jump()` are true, then `consume()`s both. Tuned via `COYOTE_TIME` and `JUMP_BUFFER_TIME` in `GameTuning`.
- **Aim-down-sights slowdown.** While `ScopeIn.is_scoped` is true the player's `target_speed` is multiplied by `GameTuning.SCOPE_SPEED_MULT` so movement feels heavier when aiming.
- **Bullet time.** `BulletTime` (separate node under Player) listens to `scoped_in` and ramps `Engine.time_scale` toward `BULLET_TIME_SCALE` when the player is *scoped AND off the ground*. The instant the player lands or releases the scope, time scale lerps back to 1.0. Lerp uses a real-time `Time.get_ticks_usec()` delta so the recovery doesn't get stuck while time itself is scaled.
- **Screen shake** lives on its own pivot node between `Head` and `Camera3D` (composes cleanly with camera tilt).
- **FOV kicks** for jumping, falling, and forward sprinting in `camera_effects.gd`.

### `GameTuning` autoload

Hard-coded gameplay values live in [`scripts/autoload/game_tuning.gd`](scripts/autoload/game_tuning.gd) as `const`s. To rebalance, edit one file:

```gdscript
const PLAYER_MAX_SPEED: float = 5.0
const CROUCH_HEIGHT_RATIO: float = 0.6
const CAMERA_SCOPED_FOV: float = 40.0
const SCOPE_SPEED_MULT: float = 0.4
const BULLET_TIME_SCALE: float = 0.3
const COYOTE_TIME: float = 0.12
...
```

Per-instance, per-weapon, or per-scene values stay as `@export` on the relevant node or resource. For example, `Character.blast_damp_divisor` is `@export`'d so the player retains horizontal momentum after a blast (1.12) while the enemy resets it (1.0) and so doesn't fly off after a knockback.

### Weapons as resources

Each weapon is a `Resource` (`scripts/combat/weapon_data.gd`) — `pistol.tres`, `shotgun.tres`, `smg.tres`, `rock_weapon.tres`. Per-weapon ammo is persisted across swaps by `ammo.gd`. Each `WeaponData` carries an optional `hand_mesh: Mesh`; on `swap_finished` the `GunMesh` swaps its `mesh` to match.

### Frame-rate independence

Movement, blast decay, decal fade, crouch, scope FOV, enemy friction, and all camera effects (bob, FOV, tilt, land dip) use either `lerp(a, b, 1 - pow(1 - rate, delta * 60))` or `1 - exp(-rate * delta)` so feel doesn't change between 60 / 144 / 240 Hz.

### Strong typing

Every system has a `class_name` so `@export` references are checked at scene-load: `Character`, `Player`, `Ammo`, `Inventory`, `Attack`, `Crouch`, `WeaponSystem`, `WeaponData`, `ScopeIn`, `CameraEffects`, `ScreenShake`, `Projectile`, `ProjectileSpawner`, `Explosion`, `ExplosionMesh`, `GunMesh`, `UI`, `CoyoteTime`, `JumpBuffer`, `BulletTime`. The static analyzer complains immediately if you wire the wrong node into the wrong slot.

## Roadmap

- Extract `Weapon` into its own `Weapon.tscn` sub-scene so multiple characters (NPCs, enemies) can drop it in.
- Enemy AI (currently `enemy.gd` only takes damage and dies).
- Save / load.
