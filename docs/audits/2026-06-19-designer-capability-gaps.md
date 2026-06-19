# Designer capability-gap audit — 2026-06-19

A 25-agent workflow re-reviewed the (now-accurate) authoring guide against the live code to find what a
level/content **designer still cannot author** without writing GDScript, then adversarially verified each
claimed gap was real. **80 gaps confirmed across 12 domains; 3 claimed gaps rejected as already-covered.**

This is a forward-looking roadmap ("what to build next"), distinct from the [authoring-guide de-stale
audit](2026-06-19-authoring-guide-destale.md) (which fixed what the guide got *wrong*).

## Verdict

Designers can author rich **single scenes** but lack the **connective tissue for a shippable, multi-scene
game**. Three clusters dominate:

1. **Level flow is the biggest missing pillar.** No inspector-reachable level transition, player-spawn
   marker, blank level template, or level select. The `GameRoot`/`LevelData` seam exists in code but is
   physically unwired — `TriggerVolume` can only call no-arg methods while `GameRoot.load_level` needs a
   `LevelData` arg, and `game.tscn`'s root has no `GameRoot` script.
2. **The autoload-reachability wall.** The highest-value APIs (`start_quest`, `complete_quest`, `set_flag`,
   `push_toast`, `load_level`) exist and work, but cannot be reached from a node-relative, no-arg
   `TriggerVolume` / `DialogueChoice` / `CutsceneAction`. Almost every "code-only" blocker is really a
   **missing inspector shim onto a working API.**
3. **String-exact-id footguns with no in-editor validation.** `Item.id` references, `QuestObjective.target_id`,
   `Perk.stat_bonuses` keys, and trigger/cutscene method names silently no-op on a typo — even though the
   dropdown (`_validate_property`) and config-warning idioms already exist in the codebase.

Plus **one outright correctness bug**: perk-granted abilities never register, fire, or save because
`PerkManager` uses a raw `add_child` instead of the Player grant pipeline (rank 1 — cheapest high-value fix).

## Cross-cutting themes

- **Autoload-reachability wall** — working APIs unreachable from inspector surfaces; the fix is shims, not new systems.
- **String-exact-id footguns** — typo'd ids silently fail; the dropdown + config-warning idioms already exist to fix them.
- **Authored-but-dead exports** — `GoapProfile.goals`, `Cutscene.auto_end`, `Quest.reward_reputation`, `LevelUp.available_perks` are inspector fields that do nothing with zero signal.
- **Level/scene flow** — transition + spawn marker + template + level-select are one coupled cluster around the `GameRoot`/`LevelData` seam; they must land together.
- **Prefab + starter-`.tres` gaps** — `PerkStation`, `CutscenePlayer`, ambient sound, player-light-level lack prefabs; `Quest`/`Cutscene`/`MapData`/`StatusEffect` lack example `.tres` to clone, so designers author whole categories cold.
- **Saved-state inconsistency** — flags persist but perks and quests do not, breaking prereq chains and re-granting bonuses on revisit.
- **Restock-once** — vendors and containers seed once; one shared restock helper closes it everywhere.

## Quick wins (high value, S effort — do first)

1. **Fix the perk-grant bug** — route `PerkManager.unlock_perk` through `host.grant_ability` instead of raw `add_child` (rank 1).
2. **`ItemIds` registry + dropdowns** on `Lock`/`Door.requires_item_id` and `QuestObjective.target_id`, plus an `Item` blank-id/caliber config-warning (rank 2).
3. **Validate trigger/cutscene wiring** — extend `TriggerVolume` config-warnings (and add to `Cutscene`) to check `action`/`target` resolve to a real method; `CALL_METHOD` `push_warning` breadcrumb (rank 3).
4. **`AmbientSound` component** + `ambient_sound.tscn` with a null/non-looping-stream warning (rank 16).
5. **`target_on_fail` on `DialogueChoice`** so a failed skill check has a real alternate branch (rank 22).
6. **Designer-fireable toast** — `toast_text` export on `TriggerVolume.fire` + a `CutsceneAction` `TOAST` type wrapping `push_toast` (rank 23).
7. **Ship missing prefabs + starter `.tres`** — `perk_station.tscn`, `cutscene_player.tscn`, one example per never-shipped type (rank 24).
8. **Turn silent-drop / inert exports into warnings or wiring** (rank 25).
9. **`LevelTemplate.tscn`** with the load-bearing `navmesh` / `world_environment` groups pre-wired (rank 26).

## Big rocks (high value, L effort — plan deliberately)

- Perk + quest **save persistence** by resource path, fixing the flags-persist-but-progression-doesn't inconsistency (rank 10).
- **`CutsceneActor`** + camera follow/look-at + an `AnimationPlayer` rig + `WALK_TO`/`FACE`/`PLAY_ANIM` action types — the foundation for any directed cinematic (ranks 11–12, build together).
- **NPC schedules / day-night routines** via a `WorldClock` autoload, a `Schedule` resource, and a `ScheduleBehavior` on the `NpcLocomotion` idle seam (rank 28).
- **Level-up perk picker + respec + XP** routed through the fixed grant path (rank 29).
- **HUD authorability** — a `HudSettings` tuning group + optional `HudLayout.tscn` so crosshair/readout/toast numbers are designer-tunable (rank 31). *(Note: the segmented HP bar / ammo / hotbar layout shipped 2026-06-19 still hardcodes its consts — this rock would move them to a tuning group.)*
- **First-party `EditorPlugin` dock** — component palette, new-content launcher, validate button, guide link; the acknowledged last open friction item (rank 32).

## Full ranked list

Format: **rank. title** (domain · value/effort · status) — why it matters · *build.*

1. **Perk-granted abilities never register/fire/persist** (Progression · high/S · new) — raw `add_child` bypasses the grant pipeline. *Route through `host.grant_ability` in `perk_manager.gd`.*
2. **`Item.id` fields lack dropdown/validation** (Tooling · high/S · new) — typo'd ids silently break doors/quests. *`ItemIds` folder-scan registry + `PROPERTY_HINT_ENUM_SUGGESTION` on the 3 fields + `Item` warning.*
3. **Trigger/cutscene method wiring unvalidated** (Encounters · high/S · new) — wrong target/typo gives no feedback. *Resolve target+method in config-warnings + `CALL_METHOD` breadcrumb.*
4. **No LevelDoor/portal to another level** (Level · high/M · new) — blocks shipping >1 level by inspector. *Attach `GameRoot` to `game.tscn`, no-arg `load_assigned_level`, a `LevelDoor` with a `LevelData` export.*
5. **No PlayerSpawn/entry marker** (Level · high/M · new) — nowhere to arrive on load. *`PlayerSpawn` Marker3D with `entry_id`; `GameRoot`/`LevelDoor` teleports + seeds respawn.*
6. **Starting/finishing a quest is code-only** (Quests · high/M · new) — `start_quest`/`complete_quest` unreachable from inspector. *`QuestStarter` drop-in + quest exports on `TriggerVolume` + a `quest` field on `DialogueChoice`.*
7. **Dialogue choices can't write consequences** (Dialogue · high/M · new) — choices are read-only gates. *Optional effect block (set_flag/start_quest/advance/give_item/money) applied in `DialogueManager`.*
8. **An NPC can only say one conversation** (Dialogue · high/M · new) — single `DialogueResource`, can't vary with world state. *`DialogueSelector` (flag/quest-gated rows, first match wins) overriding the slot.*
9. **No encounter-cleared signal; WaveManager can't wait for a clear** (Encounters · high/M · new) — arena/wave progression has nothing to listen to. *Track spawns, connect `died`, emit `cleared` + `alive_count`; `wait_for_clear` on WaveManager.*
10. **Perks + quest progress not saved** (Progression · high/L · known) — flags persist but these don't. *Add perks + quests save sections by resource path, mirroring `inventory_stacks`.*
11. **Cutscenes can't move/pose/animate actors; brain fights poses** (Cutscenes · high/L · new) — only `CALL_METHOD`, no public verbs, GOAP never suppressed. *`CutsceneActor` + brain-suppress gate + `WALK_TO`/`FACE`/`PLAY_ANIM` (+ an AnimationPlayer rig — the bulk).*
12. **Cinematic camera can't look-at/follow; no FOV/cut/easing** (Cutscenes · high/M · new) — moving subjects drift off-frame. *`look_at_path`/`follow_node` + `camera_fov` + snap bool + ease/trans on CutsceneAction.*
13. **No subtitle/caption action** (Cutscenes · high/M · new) — only the heavyweight `DIALOGUE`. *`CAPTION` action on the cutscene's own CanvasLayer, no DialogueManager.*
14. **No designer-runnable content validator** (Tooling · high/M · new) — non-programmers can't self-check before handoff. *`@tool` EditorScript running existing checks (dup ids, faction id=filename, caliber↔ammo, profiles resolve).*
15. **World objects can't be gated by stats/perks/abilities** (Progression · high/M · new) — build-checks live only in dialogue. *`BuildGate` component consulted by `Lock`/`Door`/`TriggerVolume` like `Lock.of(self)`.*
16. **No looping ambient-sound zone** (Audio · high/S · new) — every bed is a raw `AudioStreamPlayer3D` with a Master-bus footgun. *`AmbientSound` Node3D + `ambient_sound.tscn` (Radio/NoiseSource idiom).*
17. **No area-triggered zone music/ambience** (Audio · high/M · new) — MusicDirector is combat/dialogue only. *`AudioZone` Area3D cross-fading a looping player while a player body is inside, ref-counted.*
18. **No per-NPC stealth senses / public investigate verb** (NPC AI · med/M · new) — senses are global off-by-default bools. *Per-NPC opt-in bools OR'd with globals + a public `investigate(point, alerted)`.*
19. **Spawner can't compose components/markers; bodyguard duty code-only** (NPC AI · med/M · new) — disc-scatter only. *`spawn_points`/`attach_scenes` exports + a `GuardDuty` drop-in.*
20. **No vendor restock / container refill** (Items · med/M · known) — seed-once bags. *Shared restock primitive on a Timer/visit/day-tick reusing the split seed methods.*
21. **Quest area/use hooks, turn-in, chaining/prereqs missing** (Quests · high/M · known) — multi-step structure not expressible as data. *`notify_enter`/`notify_use` + area export + complete exports + `prereq`/`next_quest` fields.*
22. **Skill-check/flag-gated choices have no fail branch** (Dialogue · med/S · new) — a failed check is just a disabled button. *`target_on_fail` (default END) kept enabled + bound on gate failure.*
23. **No designer-fireable toast** (UI · med/S · new) — `push_toast` is wired but code-only. *`toast_text` on `TriggerVolume.fire` + `TOAST` cutscene step.*
24. **No PerkStation prefab / starter `.tres` for never-shipped types** (Tooling · med/S · known) — authored cold. *`perk_station.tscn`, `cutscene_player.tscn`, one annotated `.tres` per type.*
25. **Silent-drop / inert exports** (Progression · med/S · known) — `stat_bonuses`/`goals`/`auto_end`/`reward_reputation` do nothing silently. *Config-warnings or wiring; honour/remove `auto_end`; wire `reward_reputation`.*
26. **No blank level template** (Level · med/S · new) — fragile load-bearing group names. *`LevelTemplate.tscn` with groups pre-wired + an optional `@tool` group validator.*
27. **Light/shadow stealth ships effectively off** (Stealth · med/M · new) — no `PlayerLightLevel` on Player.tscn, no `ShadowVolume`. *Ship `player_light_level.tscn` under Player + a `ShadowVolume` Area3D.*
28. **No NPC schedules / day-night routines** (NPC AI · high/L · known) — no in-world clock, NPCs anchored to one spawn. *`WorldClock` autoload + `Schedule` resource + `ScheduleBehavior` on the idle seam.*
29. **No level-up perk picker, respec, or XP** (Progression · high/L · known) — `available_perks` authored-but-dead, money-spend only. *Pick-one-of-N step + `RespecStation` + XP curve with `add_xp` hooks.*
30. **No quest markers/waypoints/compass** (UI · med/L · known) — journal is pure text. *`WorldMarker` screen-edge compass + `QuestObjective` marker export + minimap channel.*
31. **HUD is code-built with no scene/tuning surface** (UI · high/L · new) — hardcoded consts, breaks the const-tuning rule. *`HudSettings` resource + a `GameSettings` preload + optional `HudLayout.tscn`.*
32. **No first-party EditorPlugin/dock** (Tooling · med/L · known) — no in-editor palette/launcher/validate/guide. *Build after the dropdowns + validator land.*

## Per-domain coverage

Level 7 · NPC AI 5 (1 rejected) · Encounters 7 (1) · Quests 9 · Dialogue 5 · Cutscenes 8 · Items 8 · Progression 8 (1) · Stealth 6 · Audio 5 · UI 7 · Tooling 5.
