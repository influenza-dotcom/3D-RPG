# Editor-closed finish pass — 2026-07-11 remediation

The review remediation (`fix-plan-2026-07-11.md`, 64 fixes) was applied **with the
editor open**, so all `.gd` code + new GUT tests + doc edits are in the working
tree, verified by re-read + static symbol checks only. This runbook lists the
handful of steps that could NOT be done with the editor open. Do them in one
session with the **editor closed** (except the final icon bake + reopen).

Absolute root: `C:/Users/dalla/3D RPG/rpg`. Never `git add -A` — the tree carries
the user's in-flight work. No commits unless the user asks.

---

## 1. Scene edits (editor closed — a .tscn buffered in the open editor reverts)

- [ ] **P0-1 — empty the New-Game ability grant.** `scenes/game.tscn:38`:
  ```
  starting_unlocks = Array[String](["laser_sight", "wall_climb", "air_dash", "slide", "grapple_hook", "grapple"])
  ```
  → replace with `starting_unlocks = Array[String]([])` (keep the line, just empty
  it — matches `Player.tscn:55`). This restores the chip-install economy (a fresh
  game must start with zero abilities). `tests/test_new_game_contract.gd` pins it.

- [ ] **B-F63 / C56 — delete the stray floating `stupidbody`.** `scenes/game.tscn`:
  remove the node (around lines 60–61, floating at y≈5951) **and** its now-orphaned
  `ext_resource` line (`stupidbody.blend`, id `6_p57ef`). `6_p57ef` occurs exactly
  twice today; after the edit, zero. `git diff scenes/game.tscn` must show exactly
  those deletions + the P0-1 line change — nothing else (the user hand-authors this
  scene). Easiest in the editor's Scene dock (deleting the node auto-drops the
  ext_resource), but that means doing it *in* the editor — either close-edit the
  text, or do it in-editor and re-verify the diff.

---

## 2. `--import` once → generate `.gd.uid` sidecars, then verify

```powershell
& "C:\Users\dalla\bin\godot.cmd" --headless --path "C:/Users/dalla/3D RPG/rpg" --import
```
(Absolute `--path` — bare `.` silently fails on the spaced path. NEVER run
`--import` after reopening the editor.)

This generates a `.gd.uid` for every new test script this remediation created:
`test_new_game_contract.gd`, `test_pickup_ray_liveness.gd`, `test_grid_overflow_strip.gd`,
`test_dialogue_suspend_closed.gd`, `test_ps1_applier.gd`, `test_ragdoll_scene.gd`,
`test_chess_wager.gd`, `test_world_frozen.gd`, `test_npc_flee_targetless.gd`,
`test_npc_give_up_barks.gd` (and any others added by the batches). It also
regenerates a valid resource uid on `resources/factions/neutral_wildlife.tres`
(**C64** already removed the malformed hand-written one).

- [ ] Confirm no test script is missing its sidecar (each new `.gd` needs a `.gd.uid`):
  ```powershell
  Get-ChildItem "C:\Users\dalla\3D RPG\rpg\tests\*.gd" | Where-Object { -not (Test-Path ($_.FullName + ".uid")) }
  ```
  Expect empty. Commit each new `.gd.uid` **with** its script.

---

## 3. Full GUT run (the empirical gate — editor stays closed)

```powershell
& "C:\Users\dalla\bin\godot.cmd" --headless --path "C:/Users/dalla/3D RPG/rpg" -s addons/gut/gut_cmdln.gd -gexit
```

New / extended tests that should be **green** (this is their first real run):
`test_game_save.gd` (profile_active + persuasion→streetwise v2 migration + gone-bit
as_bool), `test_new_game_contract.gd`, `test_character_inventory_grid.gd` (rehome +
transfer-rollback-survives-refit), `test_modal_registry.gd` (registry size/12,
gameplay_suppressed loop, close-sweep drift), `test_npc_facade_contract.gd`
(_react_distraction both-branches), `test_pickup_ray_liveness.gd`, `test_hotbar.gd`
(liveness + zorkmids-not-holdable), `test_attack_draw_lock.gd` (_fire_should_abort),
`test_world_frozen.gd`, `test_chess_wager.gd`, `test_chess_ai.gd` (HALF_PAWN),
`test_chip_install.gd` (zero-value chip filtered; 7-chip count), `test_target_liveness.gd`
(retarget throttle), `test_npc_flee_targetless.gd`, `test_npc_give_up_barks.gd`,
`test_faction.gd` / `test_npc_vs_npc.gd` (provoke reversal, raiders-hostile-at-0),
`test_ps1_applier.gd`, `test_interaction_occlusion.gd` (held-prop mask),
`test_effects.gd` (Explosion.instantiate_recovering), `test_options_menu.gd`
(music-dialog freed-capture), `test_dialogue_suspend_closed.gd`, `test_player_menus.gd`
(has_player), `test_ragdoll_scene.gd`, `test_loot_drop.gd` (pickpocket-tile no double-debit).

If any fail: the code was written blind (editor open blocked compile). Read the
failure, fix in place, re-run. Known deliberate-behavior-change to expect green
(not a regression): LevelUp/PerkManager now emit `damaged` on a stat raise via
`CharacterStats.restamp_derived` — the byte-identity stubs lack the signal so their
math is unchanged.

---

## 4. Asset bake + reopen (C52)

- [ ] **Bake the missing chip icon.** `chip_chess_visualizer` is the only chip
  without a baked inventory icon. Run the project's two-pass CLI icon baker for it
  (needs a WINDOWED renderer, not `--headless`) so it writes
  `resources/icons/chip_chess_visualizer.png` (+ `.import`), matching the other six
  chips. Then reopen the editor to import the PNG.

---

## 5. Playtest checklist (in-tree behaviors that can't be unit-tested)

Drive `game.tscn` (New Game) — these are the behavior changes whose *code* landed
but whose runtime effect is only observable in play:

- [ ] **P0-1/P0-2:** New Game → you have NO abilities; install a chip → it grants.
  Die under RELOAD_CHECKPOINT_FRESH death mode → you respawn with your run intact
  (stats/unlocks/money), not a default build.
- [ ] **P0-3:** loot a corpse whose coin tile overflows a full grid → the coin
  shows in the overflow strip below the grid (click to take); corpse drains and the
  ragdoll fades.
- [ ] **P0-4:** while a guard has you in sight-range but hasn't noticed you, throw a
  decoy → it turns to investigate; hide a body in that state → it gets discovered.
- [ ] **T1:** die with Chess / a pet-naming box open → both close during the
  cinematic (nothing floats over it). F9 under an open backpack/loot/options → no
  reload.
- [ ] **T2:** grab a prop during the death cinematic → doesn't survive the revive
  still-carried. A shot whose wind-up is interrupted by holstering/carry/death →
  doesn't resolve. Hotbar keys inert during a cutscene / name box.
- [ ] **T3:** try to hotbar-assign / hold the zorkmids coin tile → refused. Pickpocket
  a zorkmids tile off a live NPC → their pocket float isn't double-debited.
- [ ] **T5:** open a wagered chess match vs a White opponent and Esc without moving →
  NOT charged the wager. Install a chip whose ability id doesn't resolve → not
  charged (guard fires before payment).
- [ ] **T6:** stand in a hazard / poisoned, then start a cutscene → no damage ticks
  through the control-locked window.
- [ ] **T7:** a fleeing townsperson given a scripted investigate → no per-frame
  errors. A partial-clip / empty-reserve NPC → no dry-click SFX spam; it stands down.
- [ ] **T8:** provoke then holster near a factioned NPC → it can de-escalate (rep
  restored). Spawn an auto-aggro squad → faction rep drops once, not ×N.
- [ ] **C31:** author a Pettable/Claimable `max_range` of 5–8 → the verb works at
  that range (no silent 4 m cap).
- [ ] **C49:** a level with a ShaderMaterial surface under Ps1Warp → not painted flat
  white.

---

## What this remediation did NOT touch (still open, by design)

- **M1** QuestTracker autoload split — parked (L-effort, GameState is user-dirty).
- **explosive_barrel.gd** holds a 4th copy of the explosion reimport-recovery idiom
  (out of Batch 16 scope) — route it through `Explosion.instantiate_recovering()`
  in a later pass.
- The older `editor_closed_session_runbook.md` (Locomotor/NpcHeadAnchor/NpcTuning
  migrations) is a **separate** pending strand — unrelated to this remediation.
