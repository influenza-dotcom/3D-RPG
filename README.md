# 3D RPG (Godot 4.6)

First-person shooter prototype built in Godot 4.6 with a small set of weapons, hitscan + projectile combat, and a custom feel layer (camera bob, screen shake, FOV kicks, decals, etc).

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
│   ├── player/              Player.tscn, Character.tscn
│   ├── enemies/             enemy.tscn
│   ├── projectiles/         Projectile.tscn, rock_projectile.tscn, bullet_casing.tscn
│   ├── effects/             explosion_area.tscn, blood.tscn, dust*.tscn
│   └── decals/              bullet_hole_decal, blood_hole_decal, scorch_mark_decal
├── scripts/                 game logic (.gd)
│   ├── autoload/            game_tuning.gd (global feel knobs)
│   ├── player/              player, character, head, crouch, player_debug
│   ├── combat/              weapon, attack, ammo, reload, inventory, swap_weapons, scope_in
│   ├── projectiles/         projectile, projectile_spawner, rock_projectile, bullet_casing, projectile_manager
│   ├── effects/             explosion(_area, _mesh), muzzle_flash, gun_mesh, bullet_hole_decal, flash
│   ├── camera/              camera_3d, camera_effects, ScreenShake
│   ├── input/               mouse_input
│   └── ui/                  ui
├── resources/
│   ├── weapons/             pistol.tres, shotgun.tres, rock_weapon.tres
│   ├── materials/           bloodmat, bulletmat
│   └── shaders/             enemy.gdshader
└── assets/
	├── audio/               *.mp3, *.wav
	└── textures/            *.png
```

## Architecture

### Player composition

The `Player` (CharacterBody3D) is a container. Character-level concerns sit directly under it; combat/weapon concerns are grouped under a single `Weapon` (WeaponSystem) sub-node:

```
Player
├── Crouch                  capsule resize + ceiling check
├── MouseInput              rotation + attack input forwarding
├── Head                    pitch
│   ├── Camera3D            + ScreenShake, CameraEffects, GunMesh, lights
│   └── Muzzle              + MuzzleFlash visual
├── Weapon  (WeaponSystem)  facade over the combat system
│   ├── Inventory           currently equipped Weapon resource
│   ├── Ammo                per-weapon ammo counts (Dictionary)
│   ├── Attack              hitscan, spread, fire/reload/swap gating
│   ├── Reload              R-key input → reload signal
│   ├── SwapWeapons         1/2/3 input → equip_this signal
│   ├── ScopeIn             RMB → FOV lerp + scope spread
│   └── ProjectileSpawner   spawns the visual projectile after a hitscan
└── UI                      hp + ammo labels
```

The `Weapon` node holds typed `@export` references to its children (`character`, `inventory`, `ammo`, `attack`, `scope_in`) so any outside system has a single seam to talk to combat through.

Inter-node communication is **all signals**, wired in `Player.tscn`. `attack.gd` is the gating hub — it owns the fire / reload / swap cooldown timers and emits `reload_started`, `swap_started`, `swap_finished` for the gun-mesh animator to consume.

### Feel knobs: `GameTuning` autoload

Hard-coded gameplay values live in [`scripts/autoload/game_tuning.gd`](scripts/autoload/game_tuning.gd) as `const`s. To rebalance, edit one file:

```gdscript
const PLAYER_MAX_SPEED: float = 5.0
const CROUCH_HEIGHT_RATIO: float = 0.6
const CAMERA_SCOPED_FOV: float = 40.0
...
```

Per-instance, per-weapon, or per-scene values stay as `@export` on the relevant node or resource.

### Weapons as resources

Each weapon is a `Resource` (`scripts/combat/weapon.gd`) — `pistol.tres`, `shotgun.tres`, `rock_weapon.tres`. Swapping just changes `Inventory.equipped_weapon`; the actual mesh doesn't change yet. Per-weapon ammo is persisted across swaps by `ammo.gd`.

### Frame-rate independence

Movement, blast decay, decal fade, crouch, and all camera effects (bob, FOV, tilt, land dip) use either `lerp(a, b, 1 - pow(1 - rate, delta * 60))` or `1 - exp(-rate * delta)` so feel doesn't change between 60 / 144 / 240 Hz.

### Strong typing

Every system has a `class_name` so `@export` references are checked at scene-load: `Character`, `Ammo`, `Inventory`, `Attack`, `Crouch`, `Weapon`, `ScopeIn`, `CameraEffects`, `ScreenShake`, `Projectile`, `Explosion`, `ExplosionMesh`. The static analyzer will complain immediately if you wire the wrong node into the wrong slot.

## Roadmap

- Extract `Weapon` into its own `Weapon.tscn` sub-scene so multiple characters (NPCs, enemies) can drop it in.
- Per-weapon gun meshes that swap with `swap_finished`.
- Enemy AI (currently `enemy.gd` only takes damage and dies).
- Save / load.
