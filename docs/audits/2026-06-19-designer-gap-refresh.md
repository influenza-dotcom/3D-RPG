# Designer-gap refresh — 2026-06-19 (code-grounded re-check)

A re-verification of the morning's [80-gap designer-capability audit](2026-06-19-designer-capability-gaps.md) against the **current** code, after a full day of implementation. A 5-agent fan-out re-checked each domain, every claim was adversarially re-verified against `file:symbol`, and the highest-stakes findings were hand-confirmed.

This is **not** a fresh from-scratch audit — it answers "where do we actually stand *now*, and what's still lacking for a designer?" The lens is unchanged: a capability only counts if reachable **without writing GDScript** (a drop-in component, a tunable `@export`/`.tres`, or an authored Resource).

## Verdict

The implementation plan was largely executed today — **~20 of the top-ranked gaps landed in code** (all of P0–P3, most of P4, plus two cinematics items the plan had marked late). A designer can now start/advance/complete/chain quests, write dialogue consequences, vary an NPC's conversation by world-state, gate doors by build, fire toasts, drop ambient beds and audio zones, and restock vendors — all from the inspector. That is a real, large jump.

But the refresh surfaced four things the morning audit could not have seen:

1. **The marquee feature shipped broken.** The level-flow cluster (LevelDoor / PlayerSpawn / GameRoot — the audit's "biggest missing pillar") is wired wrong in `game.tscn` and does nothing at runtime. **Fix-first.**
2. **Designers still author every new system cold.** Zero `example_*.tres` and zero prefabs exist for the whole content layer. This is the cheapest, highest-leverage gap on the board.
3. **The guide — the designer's actual surface — is now badly stale.** 12 of the 15 systems shipped today are *entirely undocumented*; 2–3 spots *actively tell designers a working feature doesn't exist yet*. In a designer-first project, an undocumented drop-in is invisible.
4. **The biggest remaining *design* hole is progression.** There is no XP of any kind; character growth is cash-only or find-the-shrine-only, and `LevelUp.available_perks` is a new silent-dead export.

## CRITICAL — fix before anything else

**C1 · Level-flow is shipped-but-dead (ranks 4/5).** `game_root.gd`'s docstring calls it "the root script for game.tscn," but in `scenes/game.tscn` it's attached to a **child** node `GameRoot` (`parent="."`), and `Player` is its **sibling** (`parent="."`), not its child. So GameRoot's runtime paths — `get_node_or_null(^"Player")` (`game_root.gd:53`), `^"Player/Music"` (:76), `^"Player/Ambience"` (:81) — resolve to the non-existent `GameRoot/Player` and return null. Consequences, all silent:
- `_place_player_at_entry` early-returns → a `LevelDoor` swap **never teleports the player** and **never re-seeds `GameState.set_respawn`** (:60).
- `_apply_audio` no-ops → a level's music/ambience override is ignored.
- `TestLevel.tscn` contains **no `PlayerSpawn`** anyway, so even a fixed path has nothing to match.
- Because respawn is never re-seeded, a **death after a portal hop** falls back to `reload_current_scene()` (`player.gd:1574`), silently dumping the player back into the *original* level.

Fix is small: attach `game_root.gd` to the actual scene root (or reparent Player under GameRoot, or change the three paths to `^"../Player"`), and drop a `PlayerSpawn` into the shipped level. Until then, "ship a second level by inspector" — the whole point of the cluster — does not work. **(H value / S effort.)**

## Landed today (now genuinely designer-reachable)

Confirmed working end-to-end against code, so the morning audit's entries for these are closed:

- **Dialogue cluster** — choice **consequences** (`set_flag`/`start_quest`/`advance`/`complete`/`give_item`/`give_money`, `dialogue_choice.gd:44-60`), **`target_on_fail`** fail-branch (:25), **`DialogueSelector`** for one-NPC-many-conversations, flag-gated choices. `give_item_id` is a *validated* dropdown (not a free-text footgun). (ranks 6/7/8/22)
- **Quests** — `QuestStarter` drop-in, TriggerVolume `start/complete/advance` exports, `prereq_quest_id` guard + `next_quest` chaining (`GameState.complete_quest:371-372`), and all six objective types now have an auto-fire hook (ENTER_AREA/USE_ITEM/KILL/PICKUP/TALK/FLAG). (ranks 6/21)
- **Persistence** — perks + quests (with objective progress) now survive a reload, keyed by `resource_path` with a graceful skip-on-miss (`GameState.gd:238-279`). (rank 10)
- **BuildGate** — gate Doors/Locks/Triggers by stat/perk/ability; `required_stat` self-populates a dropdown. (rank 15)
- **Encounters** — `EncounterSpawner.cleared` + `WaveManager.wait_for_clear`; "cleared → `Door.open()`" wires via the editor Signals dock with no script. (rank 9)
- **Audio** — `AmbientSound` (looping bed, auto-routed to the `ambient` bus, slider-obeying) and `AudioZone` (cross-fade on player presence). (ranks 16/17)
- **Restocker** — refills vendors/containers to their authored baseline, top-up-only (never doubles). (rank 20)
- **Cutscenes** — `TOAST` and **`CAPTION`** action verbs and the base `CAMERA_MOVE` ease all shipped (the plan had 13 marked open — it's done). (ranks 13/23, base 12)
- **Validation/safety** — `ItemIds` dropdowns on Lock/Door/QuestObjective/give_item, ItemDb boot warnings, and trigger/cutscene wiring config-warnings + a runtime breadcrumb. (ranks 14/3)
- **Inert-export cleanup** — `Perk.stat_bonuses` key warning, `GoapProfile.goals` warning, `Quest.reward_reputation` now actually grants standing (`GameState.gd:433`), `Cutscene.auto_end` removed. (rank 25)
- **PlayerLightLevel** drop-in shipped (but see G-S1 — it's inert without the global curve). (rank 27.3)

## Still lacking — ranked

### Tier 1 — fix-first, cheap, high-leverage
- **G1 · Zero starter content to clone** (rank 24 + new) — no `example_*.tres` exists for Quest, Cutscene, StatusEffect, Perk, or MapData, and no `perk_station.tscn` / `cutscene_player.tscn` prefab. Designers author whole categories from a blank inspector. *The single cheapest onboarding fix.* **(H/S)**
- **G2 · The guide is stale** (new) — see "Guide is out of date" below. 12 systems undocumented; persistence + reward_reputation + area/use hooks are described as *not done yet*. **(H/M, doc-only)**
- **G3 · No authorable `LevelData` and no level template** (ranks 26 + new) — the only `LevelData` is an inline SubResource trapped in `game.tscn`; there's no `resources/levels/` folder, no example to clone, and no blank `LevelTemplate.tscn` with the load-bearing `navmesh`/`world_environment` groups pre-wired. Pairs with the C1 fix. **(H/S)**

### Tier 2 — the big design holes
- **G4 · No progression loop** (rank 29 + new) — **there is no XP system at all** (zero grep hits): growth is buy-stats-with-cash at a `LevelUp` station or find-a-`PerkStation`-shrine. No level-up perk **picker** (`LevelUp.available_perks` is exported but never read — a *new* silent-dead export), no XP curve / `add_xp`, no respec. A designer cannot build a kill-or-quest-driven character arc. **(H/L)**
- **G5 · No quest navigation** (rank 30) — the journal is pure text; `QuestObjective` has no world-anchor, and nothing emits a waypoint/compass/minimap channel. The only way to point a player at an objective is prose. **(H/M)**
- **G6 · No real barter/bribe in dialogue** (new) — a choice can *give* negative money as a "fee," but `add_money` has **no floor** (`character.gd:39` — the wallet goes negative), there's no `required_money`/`required_item` gate, and `give_item` can only add, never consume. "Pay 500 to pass" / "hand over the keycard" is unauthorable. **(H/M)**
- **G7 · Can't fire a cutscene from dialogue** (new) — `cutscene_player.gd`'s own docstring advertises being driven "from a TriggerVolume or a dialogue," but `DialogueChoice` has no cutscene field. "Talk → cinematic" needs a script. **(H/S)**

### Tier 3 — cinematics & world depth
- **G8 · No CutsceneActor / brain-suppress** (rank 11) — the only way to move/pose an NPC in a cutscene is the generic `CALL_METHOD`, and nothing pauses the GOAP brain, so a posed NPC fights the director. No WALK_TO/FACE/PLAY_ANIM. **(H/L)**
- **G9 · Cinematic camera can't track a subject** (rank 12 extras) — base move shipped, but no look-at/follow (moving subjects drift off-frame), no FOV, no hard-cut/snap (every move tweens), no easing choice. **(H/M)**
- **G10 · Per-level world state isn't persisted** (new) — only the player profile saves. On a real quit→Continue, every looted crate refills, every dead enemy returns, every door re-locks (unless hand-wired to a flag). "This chest stays empty after I loot it" needs code. **(H/L)**

### Tier 4 — validation & tooling
- **G11 · No quest/flag id validation** (new) — `complete_quest_id`/`advance_quest_id`/`advance_objective_id`/`set_flag` on choices + triggers, and `DialogueSelectorRow` gates, are all free-text `StringName` with no registry; a typo silently no-ops. The item-id dropdown pattern exists — it just wasn't applied to quest/flag ids. **(M/M)**
- **G12 · `entry_id` / `quest_area_id` unvalidated** (new) — free-text on LevelDoor/PlayerSpawn/TriggerVolume; a door↔spawn mismatch falls through to "first spawn" with no warning. **(M/S)**
- **G13 · No designer-runnable content validator** (rank 14b) — no `@tool` EditorScript a non-coder can click to check dup ids, faction id==filename, weapon↔ammo, GoapProfile.validate, perk keys before handoff. **(H/M)**
- **G14 · HUD numbers are hardcoded consts** (rank 31) — crosshair size, HP-bar geometry/colors, ammo/money fonts, toast timing live as `const`s in `ui.gd`, violating the project's no-hardcoded-const rule. Needs a `HudSettings` tuning group. **(M/S)**
- **G15 · No first-party editor dock** (rank 32) — no new-content launcher / Validate button / guide link / component palette. (Build last; it only aggregates G1+G13.) **(M/L)**

### Tier 5 — AI, stealth, audio polish, schedules
- **G16 · Per-NPC stealth opt-in + public `investigate()` + `InvestigatePoint` marker** (rank 18) — senses are global; you can't make one guard alert and the civilian beside it oblivious, and there's no marker to send a guard to investigate. **(M/S–M)**
- **G17 · GuardDuty + spawner markers/attach-scenes** (rank 19) — spawns scatter randomly; no precise spawn markers, no way to attach a behavior component to spawned NPCs. **(M/M)**
- **G18 · Light-stealth is inert game-wide** (ranks 27.1/27.2/27.4) — `PlayerLightLevel` shipped, but `Perception._target_light_factor` returns 1.0 unless a `Curve` is hand-assigned on *every* NPC; no `ShadowVolume`, no `LightStealthSettings` tuning + starter curve, no global fallback. The feature silently does nothing. **(M/S–M)**
- **G19 · No WorldClock / schedules** (rank 28) — no time-of-day, no NPC day/night routines; NPCs are anchored to one spawn. (Also blocks day-tick restock.) **(M/L)**
- **G20 · AudioZone polish** (new) — overlapping zones both play (no priority/ducking), and unlike `AmbientSound` it has no non-Master-bus guard, so a bare child player silently ignores the volume sliders. **(M/S–M)**
- **G21 · Minor** — no quest turn-in affordance in the journal for `auto_complete=false` quests; no letterbox/cinematic-bars option (fade only); `LevelData.display_name` is dead metadata (no level-select consumes it); `GoapProfile.goals` subset is un-authorable by design (a "coward that only flees" isn't expressible). **(L)**

## The guide is out of date (designer-surface gap)

Because the guide *is* how a non-coder discovers what's possible, its staleness is itself a capability gap. Of the 15 systems shipped today, **12 are entirely undocumented** (LevelDoor/PlayerSpawn, BuildGate, QuestStarter, dialogue consequences, `target_on_fail`, DialogueSelector, designer toast, quest chaining/hooks, `cleared`/`wait_for_clear`, AmbientSound, AudioZone, Restocker, the ItemIds dropdowns). Worse, several lines are now **actively wrong**:

- `AUTHORING_GUIDE.md:1528` & `:1932` — "quest progress is **not** save-persisted yet… don't build a quest that assumes mid-quest reloads work." **False** — `GameState.gd:238-261` persists it. Tells designers to avoid a working feature.
- `:1446` & `:1527` — "`reward_reputation` … **NOT granted yet** … Don't rely on it." **False** — `GameState.gd:433` grants it.
- `:1490`, `:1526` — "`ENTER_AREA` and `USE_ITEM` have **no auto-hook**." **Stale** — `GameState.notify_area_entered` / `notify_use` now fire them.
- `:331` — CutsceneAction enum listed as `{ WAIT, SET_FLAG, CALL_METHOD, DIALOGUE, CAMERA_MOVE, FADE }`, missing the shipped `TOAST`/`CAPTION`.
- `:705` — the `DialogueChoice` field table lists only `text/target/required_stat/required_value`, omitting the entire Consequences group + `target_on_fail` + flag-gates.
- `:195` — frames the level seam as "isn't wired into the shipped scene yet"; it now ships LevelDoor/PlayerSpawn portals (which is right that it's not wired — see C1 — but for the wrong reason).

Highest-value doc fixes, in order: (1) delete the three "not done yet" falsehoods; (2) rewrite §8 DialogueChoice to cover consequences/fail-branch/flag-gates — the single biggest no-code capability jump; (3) add catalogue + worked-example entries for the seven new drop-ins.

## Recommended next moves

1. **Fix C1** (level-flow wiring) — small, unblocks the whole multi-level pillar that "shipped" today.
2. **Ship G1 + G3 starter content** (`example_*.tres`, prefabs, a `LevelTemplate.tscn`, one real `LevelData.tres`) — a half-day that makes everything already built actually approachable.
3. **De-stale the guide (G2)** — at minimum the three wrong lines; ideally the §8 rewrite + new-component entries.
4. Then pick the design direction you care about most: **progression (G4)**, **navigation (G5)**, or **cinematics depth (G8/G9)**.

---

*Method: 5 parallel domain agents re-checked the morning audit's ranks against current code (HEAD `854884c`), citing `file:symbol`; C1, the missing-XP/starter-content findings, and the guide-staleness lines were hand-verified. Read-only — no game or test run.*
