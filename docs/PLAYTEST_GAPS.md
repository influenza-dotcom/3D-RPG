# Playtest gaps & open questions

Generated 2026-08-28 from a source audit (6 extraction agents + fact-checker pass over
`scripts/`, `managers/`, `scenes/`, `resources/`, `project.godot`). **Nothing here was
verified by running the game** — every item is read from source or resource files.

Companion to the player manual (`docs/MANUAL.html`, also shipped in the build zip).

---

## Fix before the next playtest build

**1. `End` reloads the current level with no development-build gate.**
It is live in any build, loses unsaved progress instantly, and sits right next to the
arrow cluster. Every other debug key (`F1` menu, `F2` noclip, `F4` inspector, `` ` ``
console) is gated; this one is not. One mis-hit costs a tester their run.

**2. Confirm what is actually reachable in "Headshot City".** See gap #7 below — this is
the single biggest open question and it determines whether a playtest can tell you
anything about progression, economy, or quests.

**3. Placeholder copy is everywhere player-facing.** Chips, weapon mods, quest titles and
perks all display a `[PH]` prefix; chip descriptions are empty. Testers will report it.

---

## UNVERIFIED / GAPS

These need confirmation in a running build before they can be printed as fact.

### Controls and bindings

1. **Godot built-in action defaults.** `project.godot` never redefines `ui_cancel`, `ui_accept` or `ui_end`, so their bindings come from Godot 4.7's engine defaults, which are not readable from this repository. Escape for `ui_cancel` is only confirmed by a source comment. **`ui_accept` (dialogue advance, name-entry confirm) and `ui_end` (PlayerDebug's scene reload) have no in-repo statement of key.** Verify Enter/Space and End in-engine.
2. **Controller default for opening Settings** — `ui_cancel` includes a pad button by engine default, but nothing in-repo names which.
3. **`KEY_CTRL`** — not confirmed whether it resolves to left-Ctrl only or either Ctrl in this engine version.
4. **Night vision (N) suppression** — it runs after the dialogue early-return but before the gameplay-suppression gate, so it's blocked mid-conversation but **not verified as blocked with a menu open.** Intent unclear.
5. **Q double-binding precedence** — verified that Lean arbitrates once on the press, but the exact winner for a press that is *simultaneously* a valid takedown and a valid lean was not traced end to end.
6. **Nav debug overlay** exposes five optional action exports; all default empty and no scene sets them, so no key is bound to them today.

### Content reachability — the biggest gap

7. **Most progression and economy content is not reachable in the shipped main level.** The default level ("Headshot City") instances only: one **ChipInstaller** (dialogue-driven, with **no authored stock**, so it is install-only and cannot sell you a chip), one standalone **ATM**, one armed **RentCollector**, and — added since this audit, closing the selling half of this gap — one dialogue-driven **Merchant**: the NPC "Big Dog" (`NpcData` profile *Murray Chent*) carries a `Merchant` with `standalone = false`, so it answers the **Trade** option on her conversation, not a walk-up Interact. She stocks nothing, but a merchant with empty stock is deliberately still open for business, so loot **can** be sold — at the default `sell_mult` 0.5, out of a default 1000 zm till. There is still **no LevelUp station, no PerkStation, no RespecStation, no Healer, no Bonfire and no QuestStarter** in that scene, so there appears to be no in-world way to raise a stat, spend a skill point, respec, or receive a quest. Sections 6 and 7 above document these systems as *implemented*, not as *reachable*. **This needs a designer's answer before playtesters are pointed at them.**
8. **The two authored quests** are referenced only by `SliceTestLevel.tscn`, not by the main level.
9. **Perk shrines (PerkStation)** are implemented but instanced in **zero scenes**. Two perks exist on disk (Deadeye, Tough Hide) with no station that offers them — so no perk appears obtainable in play, and skill points currently have nowhere to be spent.
10. **The shipped LevelUp** (on the Medicine Person) sets `standalone = false`, so it does **not** answer a walk-up Interact — it is reachable only through her dialogue. It also has no `available_perks`, so its Perks section is hidden.
11. **Chip availability** — verified the chips exist and can be bought on credit at New Game or installed at a mechanic, but not that any ChipInstaller in a shipped level actually *stocks* any chip, nor that chips are placed as world loot. **A playtester's actual first route to any implant is unconfirmed.**

### Numbers and behaviour

12. **NPC perception varies by NPC and it's inconsistent.** The base NPC scene ships **500 m sight / 0.1 s detect / 1.0 s forget**; an NpcData profile overwrites those with 25 m / 1.0 s / 4.0 s *only* when `profile_fills_blanks_only` is off. In the shipped level one NPC keeps the 500 m / 0.1 s numbers. Only **three of the six** shipped NPCs actually end up neutral: two keep a node-authored `disposition = 1` (`:5193` because `profile_fills_blanks_only = true` restores the override, `:5213` because it carries no `profile` at all) and the merchant "Big Dog" (`:5366`) inherits `disposition = 1` from its profile. The other **three are hostile raiders** (`:5321`, `:5329`, `:5337`): they set `disposition = 1` on the node, but they also carry the *Bastard* profile with `profile_fills_blanks_only` left off, so `_stamp_profile_full` overwrites it — the profile authors **no** disposition, so it stamps `npc_data.gd:73`'s `HOSTILE` default, and its `faction_id = "raiders"` resolves to `raiders.tres` (`default_disposition = 0`) besides. **The node overrides do not survive `_ready`** — do not read a scene's inline `disposition` as what ships.
13. **Per-shot stamina costs** (pistol 1.8, SMG 1.19, sniper 2.25, shotgun 7.2, grenade 14.4) are arithmetic from the formula and authored values, not literals in source. The underlying "effort" figures are stated in-source.
14. **The grenade launcher's screen shake value (124312342.0) reads like debug data**, not intent. Its blast damage falls back to a global sentinel; the total of a direct hit plus blast against a 4 HP player was not traced.
15. **NPC miss chance** defaults to 0 and is set per-profile; the shipped profiles were not audited, so it's unknown whether any enemy deliberately misses.
16. **Hotbar contents** — verified the keys route correctly, but not how items get *assigned* to slots initially, so what a playtester finds on which key is unknown.
17. **Spray paint** is fully implemented and wired, but **whether the spray can is obtainable in normal play is unconfirmed** — it is left out of the weapon roster above for that reason.
18. **Gravity / fall heights** — `project.godot` sets no default gravity, so every fall figure above is in **m/s of impact speed**, exactly as the source states it. **Do not translate 16 / 24 m/s into metres of drop without verifying live gravity.**
19. **Rent timing (7m30s)** is derived from the clock (noon → dawn = 0.75 of a 600 s day) and matches a source comment, but was not observed in a running build. With one day of grace, the first actual *charge* is one further dawn after that.
20. **All tuning `.tres` files are near-empty.** Almost every number in this manual is the `@export` default in the matching `.gd`. That is the live runtime value, but a designer editing a `.tres` in-editor would override it invisibly.

### Known rough edges (from source annotations, none observed live)

21. **"Left-Handed Weapon" looks wrong by construction.** The view-model has a baked 90° yaw because weapon barrels run down local +X; the left-handed branch negates that yaw, which by the file's own helper maths would point the barrel *behind* the camera. Nothing in source says the row is broken. **Verify by eye before writing it up as a bug.**
22. **View-model mouse sway sits outside every accessibility gate.** View Bobbing, Camera Tilt and FOV Effects do not reach it. At shipped values it's ~14 mm of travel and should be unnoticeable, but no toggle removes it.
23. **A setting can persist without ever taking effect** — a documented risk class in this system, since most rows have no apply step and rely on their consumer polling every frame. If an option seems to save but does nothing after a restart, report the exact row.
24. **The windowed-mode vanish** has a runtime fix already in place and should **not** be presented as a live bug.
25. **None of these rough edges was observed live** — every one comes from a code comment or risk annotation describing a hazard the author guarded against.

### Not audited

26. The **user:// Windows path** is engine convention, not stated in-repo. Confirm the literal folder.
27. The **Options tab order** (Video, Audio, Game, Controls, Accessibility) is derived from catalog order, not authored, and was not confirmed against a running menu. No tab sets a display label, so each tab's title is its raw key string.
28. The Controls tab carries **one hint row whose text is still `[PH]`** placeholder copy.
29. **Escape priority** between overlapping screens depends on autoload declaration order. Common cases are handled (each tab consumes `ui_cancel` explicitly), but not every stacking combination was tested.
30. **Not audited at all:** the pickpocket catch/steal formulas, the Bonfire checkpoint/heal loop, the Healer price formula, the chess move-entry syntax, the Wait screen's exact hour control, the blast/rocket-jump impulse system, weapon self-knockback, level-specific interaction prompts, and the colourblind shader's actual daltonization fidelity (including whether mode 0 is a true bypass).
31. **Nothing in this manual was verified by running the game.** Everything is read from source and resource files.