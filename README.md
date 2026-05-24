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

The `Player` (CharacterBody3D) is a container — each gameplay system is a child node with its own script:

| Node | Script | Responsibility |
| --- | --- | --- |
| `Player` | `player.gd` | movement, gravity, footsteps, lands |
| `Head` | `head.gd` | mouse pitch |
| `Crouch` | `crouch.gd` | camera dip + capsule resize + ceiling check |
| `Inventory` | `inventory.gd` | currently equipped weapon resource |
| `Ammo` | `ammo.gd` | per-weapon ammo counts (persisted via Dictionary) |
| `Attack` | `attack.gd` | hitscan, spread, swap/reload gating, signal emitter |
| `Reload` | `reload.gd` | reload input → `reload` signal |
| `SwapWeapons` | `swap_weapons.gd` | 1/2/3 input → `equip_this` signal |
| `ScopeIn` | `scope_in.gd` | RMB hold → FOV lerp + scope spread signal |
| `MouseInput` | `mouse_input.gd` | captures mouse, forwards rotation + attack |
| `ProjectileSpawner` | `projectile_spawner.gd` | spawns the visual projectile after a hitscan |
| `UI` | `ui.gd` | hp + ammo labels |

Inter-node communication is **all signals**, wired through `Player.tscn`. `attack.gd` is the gating hub — it owns the fire / reload / swap cooldown timers and emits `reload_started`, `swap_started`, `swap_finished` for the gun-mesh animator to consume.

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

Movement, blast decay, decal fade, and crouch all use `lerp(a, b, 1 - pow(1 - rate, delta * 60))` so feel doesn't change between 60 / 144 / 240 Hz.

## Roadmap

- Consolidate `Inventory`, `Ammo`, `Attack`, `Reload`, `SwapWeapons`, `ScopeIn`, `ProjectileSpawner` under a single `Weapon` interface node between the character and the weapon system.
- Per-weapon gun meshes that swap with `swap_finished`.
- Enemy AI (currently `enemy.gd` only takes damage and dies).
- Save / load.
