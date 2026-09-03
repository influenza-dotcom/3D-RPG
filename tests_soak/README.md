# Soak harness — dynamic multi-NPC QA

The **soak harness** is a headless QA tool for the bug classes unit tests structurally can't reach: the ones that
only appear when the game *runs over time with many agents*. It boots a real level, spawns a wave of **real
wandering NPCs** (their full `_ready` runs — unlike a unit test), ticks the game loop for seconds of game-time,
and watches for:

- **Stranded NPCs** — an NPC that keeps giving up in one spot (`NPC._stranded_cycles >= 3`) is wedged on a
  bad-bake navmesh island (a prop / car roof the bake made walkable). This is the recurring nav-grind pain,
  caught automatically instead of by a human noticing pacing in a playtest.
- **Node / orphan leaks** — spawning then freeing waves of NPCs must return the node count to baseline. An upward
  trend across waves means a spawn path leaked (a failed `.free()`, a signal holding a dead NPC alive).

The soak harness itself needs **no player and no combat**: idle NPCs with `wanders = true` roam the navmesh on their
own, which is exactly what surfaces traversal faults. (The `tests_soak/` folder also hosts other harnesses
that *do* spawn combatants — the combat smoke test, the burst-fire gate and the NPC-pool reuse test — see
**Pieces** below.)

## Why it lives here (not in `tests/`)

`tests/run.cmd` runs the fast unit suite (`res://tests`), which `CLAUDE.md` says must stay pure — in particular
**don't run `NPC._ready()` in a unit test**. That rule protects the fast suite. The soak is the deliberate
opt-in exception: running the real brain over time *is* the point. Keeping it in `res://tests_soak` (a sibling,
not a subdir of `res://tests`) means the default run never picks it up.

The pure pass/fail logic (`SoakReport`) *is* covered by the fast suite, in
[`tests/test_soak_report.gd`](../tests/test_soak_report.gd).

## Run it

```
tests_soak\run_soak.cmd
```

or directly:

```
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=res://tests_soak/soak.gutconfig.json -gexit
```

`-gconfig` points at [`soak.gutconfig.json`](soak.gutconfig.json) (dirs = `res://tests_soak`) so the default
`res://.gutconfig.json` (dirs = `res://tests`) is **not** loaded — otherwise GUT would run the whole fast suite
alongside the soak. Because that config sets `include_subdirs = true` with the `test_` prefix, this one command runs
**all four** heavy harnesses in `tests_soak/`: the wandering-NPC soak (`test_soak.gd`), the combat smoke test
(`test_combat_smoke.gd`, an armed raider vs. a dummy), the burst-fire gate (`test_npc_burst_fire.gd`, the SMG's
*brrrp — breathe — brrrp* rhythm sampled off a real magazine), and the NPC-pool reuse test
(`test_npc_pool_reuse.gd`, acquire→kill→re-acquire cycles against a real `NpcPool`).

The test always prints the `SoakReport.summary()` (pass or fail) — FPS-free numbers you can read at a glance.

## Audit a real level (the actual payoff)

The committed test targets `NavSandbox.tscn` — the clean-bake baseline — so it stays **green** and proves the
harness works. To hunt for real nav faults, edit [`test_soak.gd`](test_soak.gd):

- Point `const LEVEL` at the level you want to audit.
- Raise `npc_count` / `stranded_seconds` to stress more of the navmesh for longer.

A stranded NPC then **fails** with its name and the exact `(x, y, z)` of the bad spot — feed that to
`File → Run scripts/tools/audit_navmesh.gd` (or carve the prop with a `NavBlocker(CARVE)` and re-bake).

## Pieces

| File | Role |
|------|------|
| [`scripts/tools/soak_harness.gd`](../scripts/tools/soak_harness.gd) | `SoakHarness` Node — boots the soak, spawns waves, samples, returns a `SoakReport`. Drop-in: add it under any level and `await run_soak()`. |
| [`scripts/tools/soak_report.gd`](../scripts/tools/soak_report.gd) | `SoakReport` — pure result + verdict (`ok()`, `has_stranded()`, `is_leaking()`, `summary()`). |
| [`tests_soak/test_soak.gd`](test_soak.gd) | The opt-in integration test that drives the harness on `NavSandbox`. |
| [`tests/test_soak_report.gd`](../tests/test_soak_report.gd) | Fast off-tree coverage of the verdict math. |
| [`scripts/tools/combat_smoke_harness.gd`](../scripts/tools/combat_smoke_harness.gd) | `CombatSmokeHarness` Node — spawns a real armed raider vs. an unarmed dummy and runs the full perceive→fire→hit→`take_damage` combat chain, returning a `CombatSmokeReport`. |
| [`scripts/tools/combat_smoke_report.gd`](../scripts/tools/combat_smoke_report.gd) | `CombatSmokeReport` — pure result + verdict (`damage_landed()`, `converged()`, `leaking()`, `summary()`). |
| [`tests_soak/test_combat_smoke.gd`](test_combat_smoke.gd) | The opt-in combat integration test that drives the harness on `NavSandbox`. |
| [`tests_soak/test_npc_burst_fire.gd`](test_npc_burst_fire.gd) | The opt-in BURST gate (`WeaponData.npc_burst_count`). Runs the same harness with `sample_shots` on and times the shooter's magazine: full strings happen, none exceed the authored count, rounds inside a string come at the gun's cyclic rate, the gap between strings is still `min_shot_interval`, and a bursting SMG clearly out-shoots one round per cadence. Burst fire's whole meaning is a timing PATTERN, which no off-tree test can see. |
| [`scripts/tools/npc_pool_reuse_harness.gd`](../scripts/tools/npc_pool_reuse_harness.gd) | `NpcPoolReuseHarness` Node — warms a fleet into an `NpcPool` and runs acquire→kill→re-acquire cycles, returning an `NpcPoolReuseReport`. Proves REAL `NPC._ready` + death + `reset_for_reuse` (the pooling reset surface the fast suite can't run). |
| [`scripts/tools/npc_pool_reuse_report.gd`](../scripts/tools/npc_pool_reuse_report.gd) | `NpcPoolReuseReport` — pure result + verdict (`reused_all_same`, `pool_stable()`, `reset_clean`, `ok()`, `summary()`). |
| [`tests_soak/test_npc_pool_reuse.gd`](test_npc_pool_reuse.gd) | The opt-in pooling integration test that drives the harness on `NavSandbox` (pairs with the fast [`tests/test_npc_pool.gd`](../tests/test_npc_pool.gd) that pins the pure reset surface). |
