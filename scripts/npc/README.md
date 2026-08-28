# NPC host-facade contract

`scripts/npc/` is the non-player actor. `npc.gd` (`class_name NPC`, the large host script) is the root coordinator; behaviour
is split into **drop-in components** it builds in `NPC._build_components()` — except `WeaponStance` and `NpcLaser`,
built later in `_ready` under the combatant-only `weapon_data != null` branch (a civilian NPC has neither). Each
component holds a `host` reference and reads/writes members ON that host. This file is the **contract**: which host
members each component depends on, so a rename/delete of an `npc.gd` member is done with eyes open (see the hazard
below). Read it before renaming an NPC private, and before extracting a new component off the root.

For the decision brain (planner/executor/actions), see [`goap/README.md`](goap/README.md). This file is about the
component ↔ host coupling only.

## The typed-vs-Node split (why some renames are silent)

A component's `host` is typed one of two ways, and that choice decides whether a bad rename fails LOUD or SILENT:

- **`var host: NPC`** (6 components) — a rename of a host member is a **compile error** in the component. Safe-ish.
- **`var host: Node`** (9 components) — deliberately `Node`-typed to break the `Component ↔ NPC` class cycle (a
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
- `NPC.stand_down()` — break off the CURRENT engagement: target + attacker lock cleared, Perception back to
  `UNAWARE`, laser hidden, so the GOAP Idle floor takes the wheel next tick. Used by `NpcHomeReturn`. It deliberately
  does **not** clear `_provoked` / `_npc_grudges` / faction standing — standing down is not forgiveness.

Add a narrow setter like these when a `Node`-typed component gains a new high-churn write, rather than growing the
count of raw `host._private =` pokes.

**Movement delegation (Phase B).** `_move_toward` and `apply_velocity` — host members several components depend on
below — are now thin shells over a DRIVEN `Locomotor` child (`_locomotor`, built in `_ready` right after `_build_nav`).
Locomotor owns the path-stepping, combat nav-hop, off-mesh recovery, and the anti-stuck / wall-slide give-up machine
(`drive_move_to` + `update_stuck`); `npc.gd` stays the sole `move_and_slide` writer and injects its `_nav` via
`external_nav` so `host._nav` (CompanionFollow) still resolves to the single agent. The facade methods are UNCHANGED —
components still call `host._move_toward(...)`; only the body moved. See [`../components/README.md`](../components/README.md).

## Retarget-throttle read seam (NpcTargeting)

`npc.gd`'s `_physics_process` drives target acquisition through NpcTargeting via two thin host facades, so the
group-scan cost stays controlled:

- `NPC._should_immediately_retarget()` → `NpcTargeting._should_immediately_retarget()` — the throttle's per-frame
  pre-check. It wraps NpcTargeting's **internal** `_target_invalid()` (the O(1) "is our current target still
  good?" check — no host facade; the NPC never calls it directly). True **only** when we currently HOLD a target
  instance that just went invalid (died, out of range, non-hostile); a target-**less** NPC returns false so the
  idle cast re-scans on the `retarget_interval` timer instead of paying the full O(n) `_acquire_target` group scan
  every physics frame. This is the C8 fix — before it, `_target_invalid()` reported true for a null target, so
  every idle/target-less NPC ran the group scan each frame.
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
| `talk_approach.gd` (TalkApproach) | `_move_toward`, `_face_point`, `_face_travel`, `_desired_velocity`, `is_hostile`, `is_in_combat`, `is_sitting` (string-literal `call()` — dynamic, NO compile signal even from this NPC-typed host), `talk_approach_distance`, `talk_approach_timeout` |
| `npc_outline.gd` (NpcOutline) | `_apply_overlay_to_meshes`, `_flash_material`, `has_outline`, `is_following`, `resolved_disposition`, `is_alerted_on_player`, `outline_target_fade_s`, `_find_body_swap`, `body_part_at`, `_build_flash_tween`, `flash_red` (per-part hit-flash, H2b) |
| `npc_laser.gd` (NpcLaser) | `_outline_color_for_disposition` |
| `npc_audio_cues.gd` (NpcAudioCues) | `threat_response` |

### `Node`-typed (dynamic — NO compile signal on a host rename)

| Component | Host members it depends on |
|---|---|
| `npc_targeting.gd` (NpcTargeting) | `_set_target`, `set_last_attacker`, `_last_attacker` (read), `_target`, `_protectee`, `_treats_as_enemy`, `sight_range` |
| `npc_locomotion.gd` (NpcLocomotion) | `_move_toward`, `_face_point`, `_face_travel`, `_face_yaw`, `_flee_threat_point`, `_follow`, `_pick_wander_point`, `_snap_to_navmesh`, `_spawn_position`, `_spawn_yaw`, `flee_distance`, `is_following`, `is_sitting` (string-literal `call()`), `wanders`, `wander_dwell_min`, `wander_dwell_max` |
| `npc_voice.gd` (NpcVoice) | `_pick_bark`, `_emit_bark` (the facade its triggers deliberately round-trip through — its BODY is `NpcVoice.emit`), `_bark_pool`, `_bark_duration_ms`, `_bark_until_msec` (write — the no-overlap latch stays host-owned), `_popup_text`, `note_speaking`, `_clear_bark_bubble`, `_find_talkable`, `_is_ally_of`, `_real_player`, `_target`, `_dead`, `is_fleeing`, `is_hostile`, `is_hostile_to`, `is_in_combat`, `resolved_disposition`, and the `*_LINES` bark arrays |
| `npc_scavenge.gd` (NpcScavenge) | `_move_toward`, `_face_travel`, `inventory`, `is_fleeing` |
| `npc_combat.gd` (NpcCombat) | `_aim_point`, `_engage_range`, `_move_toward`, `_face_point`, `_target`, `_target_body`, `_weapon`, `_shot_interval`, `_aim_laser_at`, `_current_weapon_uses_ranged_attack_telegraphs`, `_on_aim`, `_report_aim`, `_emit_gunfire_noise`, `_try_reload_bark`, `_hide_laser`, `_find_body_swap`, `_scavenge`, `_audio_cues`, `_aim_sfx_delay`, `_fire_timer`, `_charging`, `_warned`, `_shot_miss`, `_desired_velocity`, `engage_range_fraction`, `miss_chance`, `move_speed`, `dodge_chance`, `dodge_interval`, `dodge_duration`, `dodge_speed_fraction` |
| `npc_bark_ui.gd` (NpcBarkUi) | (none — the host calls INTO it; it holds no host reads) |
| `npc_mortality.gd` (NpcMortality) | `ragdoll_scene`, `inventory`, `money`, `display_name`, `_body_discovery_on`, `_real_player`, `global_position` (death world-spawns; `_on_died` calls its `drop_loot` / `award_kill_xp` / `spawn_corpse_marker` via the `_drop_loot` / `_award_kill_xp` / `_spawn_corpse_marker` facades) |
| `npc_home_return.gd` (NpcHomeReturn) | `stand_down`, `is_following`, `_spawn_position`, `_spawn_yaw`, `_snap_to_navmesh`, `_height_above_floor`, `_dead`, `hp`, `_cutscene_control`, `_guarding`, `_talk`, `_perception`, `_target`, `_nav`, `_locomotor`, `_locomotion`, `wanders`, `wander_radius`, `global_position`, `rotation`, `velocity` (the "go home" leash — player death / off-screen reset; the host calls INTO it via the `send_home` facade) |
| `npc_senses.gd` (NpcSenses) | `_perception`, `_body_discovery_on`, `_dead`, `hp`, `is_fleeing`, `global_position`, `get_world_3d` (distraction/body scans — pure queries; the stateful reaction bodies that consume them are NpcDistraction's (no-target `react_unaware` / `react_music` AND has-target-while-UNAWARE `react_distraction` / `scan_distractions` — a hostile holds the player by proximity before noticing them), reaching `loudest_noise` / `nearest_audible_radio` / `nearest_visible_corpse` through the npc.gd `_loudest_noise` / `_nearest_audible_radio` / `_nearest_visible_corpse` facades) |
| `npc_distraction.gd` (NpcDistraction) | `_perception`, `_noise_initiates_on`, `_body_discovery_on`, `_loudest_noise`, `_nearest_audible_radio`, `_nearest_visible_corpse`, `_try_search_bark`, `_try_lost_interest_bark`, `_try_check_body_bark`, `react_music`, `_face_point`, `_on_directed_route`, `_desired_velocity` (write), `_attending_radio` (write), `_was_distracted` (write), `_scripted_investigating` (write), `_alerted_allies` (write), `is_fleeing`, `is_following`, `_dead`, `hp` (the stateful no-target/UNAWARE reaction bodies — `_react_unaware` / `_react_music` / `_react_distraction` / `_scan_distractions` moved here behind npc.gd's 1-line facades, which must keep their `_physics_process` positions; the scan throttles + music-comment latch are component-owned, reset by its own `reset_for_reuse`. Built by SCRIPT PATH into the Node-typed `_distraction` — the @tool new-classname idiom) |

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

## Sight rays go through `SightRay`, never straight to `intersect_ray`

Every "can this NPC SEE / HEAR past that?" ray in this folder is cast by **`SightRay.cast(world, query)`**
(`sight_ray.gd`) instead of `world.direct_space_state.intersect_ray(query)`. It is the same query the caller
already built — mask, exclude, from/to unchanged — with one extra rule: a hit on **see-through geometry** does not
stop the ray, it resumes just past it. So what comes back is always the first genuinely OPAQUE thing in the way,
and a chain-link fence, a wire grille or a shop window stops hiding you from a guard standing behind it.

Current callers: `Perception.can_see`, `Perception.can_see_node`, `Perception._wall_between` (hearing occlusion),
`NpcSenses._corpse_occluded`, `NpcHomeReturn._occluded` (the "can the player see this NPC blink?" gate), and
`NPC._aim_laser_at` — the AIM ray, which feeds `NpcCombat.act_attack`'s clear-shot test and the laser beam's
endpoint. **Add new perception rays here too.**

**Gunfire passes through the same geometry**, which is why the aim ray is on that list: an NPC that can see you
through a fence can also shoot you through it, so it should stand and fire instead of running around looking for
a gap. The other two fire paths reach the same rule by their own routes — `DamageTrace.run_pellet` (hitscan)
calls `SightRay.is_see_through_hit` inside its pierce walk, and `Projectile._ready` adds a physics collision
exception with every body in `Groups.SEE_THROUGH`.

Deliberately NOT routed through it: the player's look-at interaction ray (no looting through the wire), the
grapple hook, `SilentTakedown`'s reach ray, and anything that asks about the FLOOR. A fence is still a solid you
cannot walk through, props still bounce off it, and the navmesh still carves around it.

Geometry is marked by the two drop-ins in `scripts/components/`: **`SeeThrough`** (tags a whole prop's bodies)
and **`SeeThroughBrushes`** (splits a func_godot map's transparent-textured brushes into their own `StaticBody3D`
and tags that — a whole TrenchBroom map compiles into ONE body, and a flying round can only be excepted per
body). See `docs/AUTHORING_GUIDE.md`.
