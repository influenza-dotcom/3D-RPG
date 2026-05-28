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
├── managers/                  autoload singletons
│   ├── AudioManager.gd        play_sfx / play_2d_sfx with auto-free
│   ├── EffectFactory.gd       PackedScene slots + spawn helpers
│   ├── InputManager.gd        action-name vars + wrappers
│   └── GameSettings.gd        loads + exposes the nine tuning resources
├── scripts/                   game logic (.gd)
│   ├── autoload/              game_tuning.gd (legacy — no longer autoloaded; pending Phase 8 deletion)
│   ├── player/                player, character, head, crouch, coyote_time, jump_buffer, bullet_time, bunnyhop, player_debug
│   ├── combat/                weapon_data, weapon_system, attack, ammo, reload, inventory, swap_weapons, scope_in
│   ├── projectiles/           projectile, projectile_spawner, rock_projectile, bullet_casing
│   ├── effects/               explosion, explosion_area, explosion_mesh, muzzle_flash, muzzle_whiz, gun_mesh,
│   │                          bullet_hole_decal, blood_drop, blood_splatter
│   ├── camera/                camera_effects, screen_shake
│   ├── input/                 mouse_input
│   └── ui/                    ui
├── resources/
│   ├── tuning/                nine *Settings.gd + matching *Settings.tres (data-driven gameplay tuning)
│   ├── weapons/               pistol.tres, shotgun.tres, smg.tres, rock_weapon.tres, melee.tres
│   ├── interactables/         wooden_crate.tres (and future InteractableData)
│   ├── materials/             bloodmat, bulletmat
│   └── shaders/               outline, rim_light, flash_overlay, laser, film_grain, pixel
├── tests/                     GUT smoke suite (test_smoke.gd) + Phase 6 manager/settings tests
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

### Data-driven tuning (`GameSettings` autoload)

Hard-coded gameplay values used to live as `const`s in `game_tuning.gd`. They're now split into nine **`Resource` (`.tres`)** files in `resources/tuning/`, all loaded once at startup by the `GameSettings` autoload. To rebalance the game, open a `.tres` in the inspector and tweak — no code edit, no recompile.

| Resource | What it controls |
| --- | --- |
| `PlayerMovementSettings.tres` | Walk/jump speed, coyote time, jump buffer, smoothing, footstep cadence, landing impact divisor |
| `PlayerCrouchSettings.tres` | Crouch height, lerp speed, slow-mult, ceiling clearance, footstep quieting |
| `BunnyhopSettings.tres` | Boost per hop, max bhop speed, input/land windows, high-speed sensitivity reduction |
| `CameraSettings.tres` | FOV (default + scoped), bob, tilt, pitch limits, landing recovery, scope-zoom speed, mouse sensitivity |
| `ScreenShakeSettings.tres` | Decay rate, intensity multiplier, death-shake range/amount, explosion shake mult and max trauma |
| `WeaponGeneralSettings.tres` | Swap time, muzzle-flash duration, scope spread divisor, bullet-time scale/duration/lerp |
| `EffectsSettings.tres` | Decal fade/probe, dust intensities, blood splatter overlay tint/scale, explosion flash speeds |
| `AudioSettings.tres` | Landing SFX thresholds + pitch, falling-air ramp, bullet-whiz volume, muzzle-whiz pitch range |
| `PhysicsDamageSettings.tres` | Explosion damage, blast decay, enemy friction, pickup/throw/hold mechanics, interactable HP and impact rules |

Access pattern from code: `GameSettings.<category>.<field>`. Example: `GameSettings.player_movement.max_speed`.

One runtime `var` lives directly on `GameSettings`, not in a resource:

```gdscript
var allow_timescale_changes: bool = true
```

`BulletTime` and `FreezeFrame` both honor it. Flip it to `false` to make every system that touches `Engine.time_scale` a no-op (forward-thinking toggle for multiplayer, where global time-scale is generally a bad idea).

Per-instance, per-weapon, and per-scene values still stay as `@export` on the relevant node or resource. Example: `Character.blast_damp_divisor` is `@export`'d so the player retains horizontal momentum after a blast (1.12) while the enemy resets it (1.0).

### Manager autoloads

Four singletons live in `managers/`:

- **`GameSettings`** — central tuning registry (see above)
- **`AudioManager`** — `play_sfx(pos, stream, volume, pitch)` and `play_2d_sfx(...)` spawn ephemeral players that auto-free on `finished`. Use this instead of per-scene `AudioStreamPlayer3D` nodes
- **`EffectFactory`** — `@export`'d `PackedScene` slots for every visual effect (blood, dust, decals, gibs, explosions). Swap effects globally by changing the inspector reference instead of editing every call site
- **`InputManager`** — wraps Input action names as `StringName` vars (`action_forward`, `action_jump`, etc.) with `is_action_pressed/just_pressed/just_released/get_vector` wrappers. Rebind in one place

Autoload order (`project.godot → [autoload]`): `AudioManager → EffectFactory → InputManager → GameSettings → FreezeFrame`. `GameSettings` deliberately comes last because no other manager reads from it on startup. `GameSettings` loads its resources via `preload()` field initializers, so its fields are populated the moment the autoload instance is constructed — before any scene's `@implicit_new`.

### How to…

**Change a gameplay parameter:** open `resources/tuning/<Category>Settings.tres`, edit a field, save. No code change.

**Add or modify a weapon:** copy an existing `.tres` in `resources/weapons/`, adjust its `WeaponData` fields (damage, attack_speed, knockback, screen_shake_amount, `use_hitscan`, etc.), then drag it into `Weapon/SwapWeapons.weapon_slots` in the scene inspector (or replace an existing slot).

**Replace a sound:** either drop a new audio file in `assets/audio/` and reassign on the relevant node, or change the stream constants on the calling script. Migration to `AudioManager.play_sfx` is in progress — for new code, call the manager rather than wiring up an `AudioStreamPlayer3D` node.

**Replace a visual effect:** open the `EffectFactory` autoload and reassign the `@export` `PackedScene` slot (e.g. `blood_decal`, `gib`, `explosion_area`). The change propagates to every call site that uses the factory's convenience methods (`EffectFactory.spawn_blood_particle(pos)`, etc.).

**Change a keybind:** edit the action name in `InputManager.gd` (e.g. `var action_pickup: StringName = &"PickUp"`) **and** update the matching binding in *Project → Project Settings → Input Map*. The two must stay in sync.

### Weapons as resources

Each weapon is a `Resource` (`scripts/combat/weapon_data.gd`) in `resources/weapons/` — `pistol.tres`, `shotgun.tres`, `smg.tres`, `rock_weapon.tres`, `melee.tres`. The Player's weapon slots are assigned in the editor on `Weapon/SwapWeapons.weapon_slots` (Array[WeaponData]). Per-weapon ammo is persisted across swaps by `ammo.gd`. Each `WeaponData` carries an optional `hand_mesh: Mesh`; on `swap_finished` the `GunMesh` swaps its `mesh` to match. Each weapon also declares its own `screen_shake_amount` so the shotgun kicks harder than the SMG. A `use_hitscan: bool` field is reserved for the future hitscan/projectile split (currently always false; combat uses raycasts everywhere already).

### Strong typing

Every system has a `class_name` so `@export` references are checked at scene-load: `Character`, `Player`, `Ammo`, `Inventory`, `Attack`, `Crouch`, `WeaponSystem`, `WeaponData`, `ScopeIn`, `CameraEffects`, `ScreenShake`, `Projectile`, `ProjectileSpawner`, `Explosion`, `ExplosionMesh`, `GunMesh`, `UI`, `CoyoteTime`, `JumpBuffer`, `BulletTime`, `Bunnyhop`, `MouseInput`, `BloodSplatter`, `ShellDrop`, `Reload`, `SwapWeapons`, `Head`, `PlayerDebug`, `Interactable`. The static analyzer complains immediately if you wire the wrong node into the wrong slot.

## Tests

The project ships with a GUT (Godot Unit Test) smoke suite at `tests/test_smoke.gd` covering scene structure, state machines, falloff math, time-scale ownership, signal wiring, and decal orientation.

Run headless from the project root:

```cmd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

A double-clickable wrapper lives at `tests/run.cmd`.

### Refactor smoke tests (Phase 6)

Four assert/print scripts in `tests/` validate the data-driven refactor. To run one: in Godot, create a new scene with a Node3D root, attach the desired script, then F6.

- **`test_settings_load.gd`** — loads every `.tres` in `resources/tuning/` and asserts its expected fields are present with sane values.
- **`test_weapon_data_completeness.gd`** — iterates every weapon `.tres` in `resources/weapons/` and asserts that all `WeaponData` fields (including the Phase 4 additions) exist with the right types.
- **`test_audio_manager_spawn.gd`** — calls `AudioManager.play_sfx(...)`, waits past the stream's duration, and confirms the temporary `AudioStreamPlayer3D` was freed.
- **`test_autoload_order.gd`** — verifies every manager autoload is reachable and that `GameSettings`'s nine resource slots are all non-null at scene-load time (catches autoload-order regressions).

Each prints `[name] ALL PASS` on success.

## Troubleshooting

- **`Invalid access to property or key 'X' on a base object of type 'Nil'`** at startup — almost always an autoload ordering issue. Make sure `GameSettings` uses `preload()` field initializers (not `load()` in `_ready`), so its resources are populated before any scene constructs its nodes.
- **`Could not find type "PlayerMovementSettings"`** — class names need to be picked up after a project reload. Save the script file and restart the editor.
- **Broken UID** in a `.tres` — replace it with the correct path (`res://...`) or regenerate by deleting the `.import` file and reloading.
- **Resource loading parse error: `load_steps` mismatch** — `load_steps` must equal `1 + number of [ext_resource]` entries in the file.
- **Weapon swap to slot N does nothing** — `Weapon/SwapWeapons.weapon_slots` array is empty or has a `null` at that index. Open `weapon.tscn`, select SwapWeapons, populate the array in the inspector.

## Roadmap

- Extract `Weapon` into its own `Weapon.tscn` sub-scene so multiple characters can drop it in.
- Enemy AI (currently `enemy.gd` only takes damage and dies).
- Pick-up / drop system (the scaffolding under `ray_cast.gd` + `Interactible.gd` is there; not wired up yet).
- Save / load.
