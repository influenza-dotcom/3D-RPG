# CYBER SUNDAY — Game-Design Gap Audit (2026-06-20)

A 10-lens multi-agent audit (combat feel, enemy-AI depth, build/progression, stealth fantasy, narrative
reactivity, world/exploration, economy/loot, social/faction, feel/UX/onboarding, systemic emergence) →
synthesis → skeptical critique. 75 raw gaps deduped. Distinct from the [capability-gap plan](2026-06-19-capability-gap-plan.md)
(which was about *designer-authoring* reach and is now code-complete); this is about *game-design* depth.

**Core finding:** the engine is rich, the **content and the cross-wiring are empty.** Almost every gap is one of
two shapes — (a) a system that exists but is walled off from the systems it should feed, or (b) a system that
exists but has zero authored content. Very little is genuinely unbuilt.

---

## Top themes

- **A — Combat is a flat DPS trade with no tactical texture.** No recoil/spread/bloom (the "recoil" is a cosmetic
  gun-mesh tween); HP is the only defense for both sides (no armor/weakpoints beyond headshots); `_act_alerted` is
  close-to-range-and-strafe so N enemies = N open-field duelists; damage is one scalar (no status/elements), so
  weapons differ only in numbers.
- **B — The cast is a set of perceptual islands (no group AI).** `alert_to`/`investigate_point` exist but are
  never called on *another* NPC; NPCs never write the `&"noise"` channel (a firefight is silent to off-screen
  guards, so the shipped `hearing_initiates` can't react to combat); no alarm/reinforcement; group search is N
  solo searches.
- **C — Progression doesn't touch the verbs.** No stat/perk affects combat (gunplay only tightens idle sway a
  scope negates); stealth and progression never touch; zero authored perks, all 5 abilities are passive movement
  gates; every stat is strictly-better at a flat identical cost (builds converge).
- **D — The world doesn't react, and the player can't read it.** Reputation is read in exactly one place
  (shot/not-shot) — the whole neutral band is inert; a witnessed murder and a shadow-kill cost identical rep
  (crime is invisible); dialogue can't condition on rep/perks/items/quest state or change reputation; NPCs have no
  memory; quests can't fail/branch/expire.
- **E — Loot/economy is a one-way quantity exercise.** No rarity/quality (a corpse pistol == a shop pistol); no
  weapon mods; consumables system fully built with ZERO content (one heal pack); money inflates (sinks saturate).
- **F — Nothing is actually assembled, and a new player learns nothing.** The playable level instances NONE of the
  exploration kit (Door/Lock/Container/Trigger/Spawner are templates only; TestLevel is a flat NPC sandbox); all
  traversal abilities are granted at start (verticality is decorative); no character creation, no tutorialization,
  no pause.

---

## Ranked shortlist — 12 highest-leverage gaps (impact × emergence × inverse-effort)

| # | Gap | Exists now | Fix | Effort | Composes with |
|---|-----|-----------|-----|--------|---------------|
| 1 | Alert propagation between NPCs | alert_to/investigate_point only called on an NPC's OWN perception | On alert, call it on same-faction allies in radius | M | factions, noise, barks, GuardDuty, alarm |
| 2 | NPC gunfire/death emits noise | only player+decoys write the noise channel | mirror NoiseEmitter onto the NPC fire site | S | the noise channel + hearing_initiates; #1 |
| 3 | Weapons apply status on hit | StatusEffect full but only via a drunk consumable | on_hit_effect+chance on WeaponData, applied in damage_trace | M | elements/hazards, panic AI, slow→backstab |
| 4 | Authored consumable/StatusEffect content | engine complete, ZERO .tres, one heal pack | author ~6 .tres (stim/haste/armor/poison/molotov/antidote) | M | hotbar, money sink, #3 |
| 5 | Recoil / spread bloom on firing | accuracy is only idle aim-wander | per-weapon recoil/bloom/recovery; firing pushes a transient offset | M | aim_sway, the GUNPLAY stat, ADS, cover |
| 6 | Stat/perk affects combat | gunplay only scales idle sway | read CharacterStats in ShotResolver (dmg%/crit/headshot) | M | Perk.stat_bonuses — makes a "gunner build" possible |
| 7 | Reputation payoff surface | read in ONE place (hostile/not) | required_reputation gates on DialogueChoice/BuildGate + faction pricing | M | Merchant, dialogue, BuildGate, Restocker |
| 8 | Crime / witness system | kill costs same rep seen or not | LOS/light decides "seen": witnessed = rep hit + report, unwitnessed = free | L | the join of stealth × faction |
| 9 | Exploding/chaining hazard barrels | explosion_area + SpawnOnDestroy exist but blasts never seed blasts | an ExplosiveBarrel (CanDestroy → explosion_area on death) | S | destructibles, ragdoll, #3, AI danger-sense |
| 10 | Dialogue reads & writes state | gates only on stat/flag; effects only flags/quests/item/money | add rep/perk/item/objective reads + add_reputation/aggro consequences | S→M | Reputation, PerkManager, GameState |
| 11 | Coordinated group search | per-NPC ring around own last-known-pos | feed a SHARED origin + per-member sector to begin_search | M | SearchState; depends on #1 |
| 12 | Loot rarity/quality axis | a corpse pistol == a shop pistol | rarity field rolled in a weighted LootTable; tint tooltip + stat variance | L | LootTable, pricing, mods, money sink |

---

## Quick wins (high-impact S/M, wire-two-existing-systems / author-empty-content)

- **#2 NPC noise on fire (S) + #1 alert propagation (M)** — do as a pair. Together a firefight wakes a building,
  which finally makes the whole shipped stealth layer pay off in combat. Highest emergence-per-hour in the audit.
- **#9 exploding barrels (S)** — one component; turns explosions + destructibles + ragdolls into spectacle.
- **#10 dialogue reads/writes reputation & state (S→M)** — closes the loop between the rich rep + dialogue systems.
- **#3 + #4 status-on-hit + author consumables (M+M)** — unlocks elemental weapons, fills the empty consumable
  layer, AND gives the economy a recurring sink, all on running code.
- **#5 recoil/bloom + #6 combat stats (M+M)** — per-gun personality + a real payoff for the gunplay stat/perks.
- **#7 reputation gates + faction pricing (M)** — graded payoffs across the neutral band.
- **Polish cluster (S each):** silent-kill LOS gate (a kill currently alerts witnesses with no LOS), level-up
  fanfare (currently quieter than a kill), floating damage numbers, pickup toasts, an editable death card over the
  existing black hold (designer-set message, default "You were killed."), and a real **pause** (reuse the get_tree().paused + PROCESS_MODE_ALWAYS idiom the shop /
  level-up screens already use).

---

## Big bets (L/XL — pick at most one or two; each is a new pillar)

- **Cover / flanking / suppression (XL)** — decompose the monolithic FireArmed GOAP action into
  TakeCover/Peek/Reposition/Suppress + a drop-in CoverPoint marker (matches the InvestigatePoint/PatrolPoint
  idiom). Turns firefights from HP-trading into a positional puzzle; the biggest lever on combat replayability.
- **Element chemistry substrate (XL — scoped down)** — NOT the full matrix; ship #3 status-on-hit + #9 hazards +
  a single wet/burning tag and one reaction (wet cancels burning, fire ignites a zone). The "0451" identity. Only
  after #3/#4/#9 (they ARE its substrate).
- **Weapon mods / attachments (XL)** — turns a flat weapon list into a build space + the economy's main sink;
  partner to rarity. **Prereq:** WeaponData.duplicate() is shallow, so per-instance stat deltas aren't expressible
  today — fix instancing first.
- **A vertical-slice reference level (L)** — author ONE level that actually instances Door+Lock+Container+Trigger+
  Spawner+LevelDoor+ShadowVolume composed (locked door → key in a guarded container → flag opens a shortcut).
  Today the playable level instances none of the kit, so "editor is the modding surface" is unproven and the
  emergence is theoretical. Highest-leverage *validation* item + the canonical clone-source.
- **Character creation (L — explicitly requested)** — name + body-model swap + spend 1 starting stat point, as a
  CanvasLayer between New Game and the world fade-in. Cheap for its category: CharacterStats (6 typed stats +
  StatInfo tooltips) = the picker, BodyModelSwap = the appearance step, LevelUpScreen = a forkable stat-picker;
  missing only a `name` on GameState + the screen. Pair with **active, costed abilities (L)** (hack/cloak/slow on
  a RAM/focus pool) so the build identity has combat verbs to grow into (all 5 abilities are passive today).

---

## Critique — what the audit itself missed (and the one call)

The synthesis is sharp on cross-wiring but **blind to the temporal/experiential layer**:

- **No pacing / difficulty curve** — enemy density, time-to-kill, when power spikes land; nothing addresses
  whether minute 5 and minute 90 feel different. Every "build this" adds breadth, none addresses the curve.
- **Save / checkpoint UX is the actual core loop** for an immersive sim (you reload after a botched stealth run) —
  and it's absent from all 75 gaps. What persists, when, is death even meaningful without a save model?
- **Audio / music** — an immersive sim lives on the detection stinger, combat-vs-explore music states, spatial
  gunfire cues. (Ironically #2 "NPCs emit noise" is half an audio problem the audit never frames as one.)
- **Replayability** beyond "builds converge" — no NG+, no build-defining early choices, no reason to replay a
  hand-built level.
- **Scope realism** — shipping five XL pillars is fantasy for a solo/tiny team; rarity tiers / weapon mods /
  element chemistry are genuinely fine to OMIT for a content-empty game.

**Build this next: the vertical-slice reference level.** It's mis-ranked as a validation nicety but it's the only
item that converts this from a tech demo into a game — it forces real content, exposes which of the 75 systems
actually matter when composed (most won't), surfaces the pacing/save/audio gaps the audit missed (you can't build
a real level without confronting them), and gives every cheap quick-win a real stage to prove itself on instead of
a flat NPC sandbox. Everything else is adding rooms to a house with no floor.
