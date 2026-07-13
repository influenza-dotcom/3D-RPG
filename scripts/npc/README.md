# NPC host-facade contract

`scripts/npc/` is the non-player actor. `npc.gd` (`class_name NPC`, ~2.8k lines) is the root coordinator; behaviour
is split into **drop-in components** it builds in `NPC._build_components()`. Each component holds a `host` reference and
reads/writes members ON that host. This file is the **contract**: which host members each component depends on, so a
rename/delete of an `npc.gd` member is done with eyes open (see the hazard below). Read it before renaming an NPC
private, and before extracting a new component off the root.

For the decision brain (planner/executor/actions), see [`goap/README.md`](goap/README.md). This file is about the
component ↔ host coupling only.

## The typed-vs-Node split (why some renames are silent)

A component's `host` is typed one of two ways, and that choice decides whether a bad rename fails LOUD or SILENT:

- **`var host: NPC`** (6 components) — a rename of a host member is a **compile error** in the component. Safe-ish.
- **`var host: Node`** (8 components) — deliberately `Node`-typed to break the `Component ↔ NPC` class cycle (a
  component that `NPC` builds, typed as `NPC`, would re-form the cycle). Every `host.X` is a **dynamic** call, so a
  renamed/removed host member is **NOT** caught at compile time — it fails at runtime (or silently no-ops). These are
  the dangerous ones.

> **Rename hazard (read this).** `UNUSED_PRIVATE_CLASS_VARIABLE` is per-class: the linter cannot see that a "dead"
> `npc.gd` private is read dynamically by a `Node`-typed component. Deleting an apparently-unused private has shipped a
> crash before. **Grep the whole `scripts/npc/` tree (and `goap/`) for a host member before removing or renaming it.**
> See the memory note *unused-private-var-warning-unsafe-for-host-members*.

## Public write seams (prefer these over poking a private)

Where a component WRITES host state, route it through a public setter so the write is greppable + rename-safe:

- `NPC._set_target(node)` — bind the combat target (also feeds Perception). Used by `NpcTargeting`.
- `NPC.set_last_attacker(node)` — set/clear the sticky "who last hit us" lock. Used by `NpcTargeting` (M2). `npc.gd`'s
  own damage/death paths set the private `_last_attacker` directly (same class, no facade needed).

Add a narrow setter like these when a `Node`-typed component gains a new high-churn write, rather than growing the
count of raw `host._private =` pokes.

**Movement delegation (Phase B).** `_move_toward` and `apply_velocity` — host members several components depend on
below — are now thin shells over a DRIVEN `Locomotor` child (`_locomotor`, built in `_ready` right after `_build_nav`).
Locomotor owns the path-stepping, combat nav-hop, off-mesh recovery, and the anti-stuck / wall-slide give-up machine
(`drive_move_to` + `update_stuck`); `npc.gd` stays the sole `move_and_slide` writer and injects its `_nav` via
`external_nav` so `host._nav` (CompanionFollow) still resolves to the single agent. The facade methods are UNCHANGED —
components still call `host._move_toward(...)`; only the body moved. See [`../components/README.md`](../components/README.md).

## Retarget-throttle read seam (NpcTargeting)

`npc.gd`'s `_physics_process` drives target acquisition through NpcTargeting via three thin host facades, so the
group-scan cost stays controlled:

- `NPC._target_invalid()` → `NpcTargeting._target_invalid()` — the O(1) "is our current target still good?" check.
- `NPC._should_immediately_retarget()` → `NpcTargeting._should_immediately_retarget()` — the throttle's per-frame
  pre-check. True **only** when we currently HOLD a target instance that just went invalid (died, out of range,
  non-hostile); a target-**less** NPC returns false so the idle cast re-scans on the `retarget_interval` timer
  instead of paying the full O(n) `_acquire_target` group scan every physics frame. This is the C8 fix — before it,
  `_target_invalid()` reported true for a null target, so every idle/target-less NPC ran the group scan each frame.
- `NPC._acquire_target()` → `NpcTargeting._acquire_target()` — the full nearest-hostile group scan (runs on the
  throttle timer, or same-frame when `_should_immediately_retarget()` fires).

## Component → host members

Builtin `Node`/`CharacterBody3D`/`Character` members (`global_position`, `velocity`, `hp`, `get_tree`, …) are omitted;
these are the `npc.gd`-owned members (the renameable ones a rename would break).

### `NPC`-typed (compile-checked)

| Component | Host members it depends on |
|---|---|
| `companion_follow.gd` (CompanionFollow) | `_leader`, `_nav`, `_move_toward`, `_face_point`, `_face_travel`, `_height_above_floor`, `_dead` |
| `weapon_stance.gd` (WeaponStance) | `_target`, `_weapon`, `_weapon_mesh`, `_perception`, `_can_fight_with_gun`, `_hide_laser`, `is_predisposed_hostile`, `move_speed`, `threat_response` |
| `talk_approach.gd` (TalkApproach) | `_move_toward`, `_face_point`, `_face_travel`, `_desired_velocity`, `is_hostile`, `is_in_combat`, `talk_approach_distance`, `talk_approach_timeout` |
| `npc_outline.gd` (NpcOutline) | `_apply_overlay_to_meshes`, `_flash_material`, `_outline_color_for_disposition`, `has_outline`, `outline_width`, `resolved_disposition`, `_find_body_swap`, `body_part_at`, `_build_flash_tween`, `flash_red` (per-part hit-flash, H2b) |
| `npc_laser.gd` (NpcLaser) | `_outline_color_for_disposition` |
| `npc_audio_cues.gd` (NpcAudioCues) | `threat_response` |

### `Node`-typed (dynamic — NO compile signal on a host rename)

| Component | Host members it depends on |
|---|---|
| `npc_targeting.gd` (NpcTargeting) | `_set_target`, `set_last_attacker`, `_last_attacker` (read), `_target`, `_protectee`, `_treats_as_enemy`, `sight_range` |
| `npc_locomotion.gd` (NpcLocomotion) | `_move_toward`, `_face_point`, `_face_travel`, `_face_yaw`, `_aim_point`, `_flee_threat_point`, `_follow`, `_pick_wander_point`, `_snap_to_navmesh`, `_spawn_position`, `_spawn_yaw`, `flee_distance`, `is_following`, `wanders`, `wander_dwell_min`, `wander_dwell_max` |
| `npc_voice.gd` (NpcVoice) | `_pick_bark`, `_emit_bark`, `_bark_pool`, `_clear_bark_bubble`, `_find_talkable`, `_is_ally_of`, `_real_player`, `_target`, `_dead`, `is_fleeing`, `is_hostile`, `is_hostile_to`, `is_in_combat`, `resolved_disposition`, and the `*_LINES` bark arrays |
| `npc_scavenge.gd` (NpcScavenge) | `_move_toward`, `_face_travel`, `inventory`, `is_fleeing` |
| `npc_combat.gd` (NpcCombat) | `_aim_point`, `_engage_range`, `_move_toward`, `_face_point`, `_target`, `_target_body`, `_weapon`, `_shot_interval`, `_aim_laser_at`, `_current_weapon_uses_ranged_attack_telegraphs`, `_on_aim`, `_report_aim`, `_emit_gunfire_noise`, `_try_reload_bark`, `_hide_laser`, `_find_body_swap`, `_scavenge`, `_audio_cues`, `_aim_sfx_delay`, `_fire_timer`, `_charging`, `_warned`, `_shot_miss`, `_desired_velocity`, `engage_range_fraction`, `miss_chance`, `move_speed`, `dodge_chance`, `dodge_interval`, `dodge_duration`, `dodge_speed_fraction` |
| `npc_bark_ui.gd` (NpcBarkUi) | (none — the host calls INTO it; it holds no host reads) |
| `npc_mortality.gd` (NpcMortality) | `ragdoll_scene`, `inventory`, `money`, `display_name`, `_body_discovery_on`, `_real_player`, `global_position` (death world-spawns; `_on_died` calls its `drop_loot` / `award_kill_xp` / `spawn_corpse_marker` via the `_drop_loot` / `_award_kill_xp` / `_spawn_corpse_marker` facades) |
| `npc_senses.gd` (NpcSenses) | `_perception`, `_body_discovery_on`, `_dead`, `hp`, `is_fleeing`, `global_position`, `get_world_3d` (distraction/body scans; `_react_unaware` / `_react_music` (no-target) AND `_react_distraction` / `_scan_distractions` (has-target while UNAWARE — a hostile holds the player by proximity before noticing them) call its `loudest_noise` / `nearest_audible_radio` / `nearest_visible_corpse` via the `_loudest_noise` / `_nearest_audible_radio` / `_nearest_visible_corpse` facades) |

Keep this table current when you add a component, add a host dependency, or extract behaviour off the root. A drift
test (`tests/test_npc_facade_contract.gd`) pins the seam methods and asserts each component (including `NpcCombat`)
exposes a `host` field defaulting `null`; the deeper `NpcCombat` firing behaviour is covered by `tests/test_npc_combat.gd`.

## Host-agnostic drop-ins the NPC also builds (NOT in the table)

`NPC._build_components()` also auto-builds **`NoisePulser`** (`scripts/components/noise_pulser.gd`) — the gunfire /
death noise emitter (`_emit_gunfire_noise` / `_on_died` call `pulse()` on it). It is deliberately **absent from the
coupling table above** because it reads NO host members: it's a *generic* drop-in (reads `get_parent()` duck-typed,
the `LocomotionFx` idiom) that works on any `Node3D`, and the NPC merely seeds its Inspector knobs from the
`*_noise_*` exports and calls `pulse(radius, throttled)`. Prefer this shape — a portable component the root drives
through a public method — when extracting new behaviour off the root; it's the direction the whole class is headed.
