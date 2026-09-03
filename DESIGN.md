# CYBERSUNDAY — Design

**What this document is.** The one-page answer to "what is this game, and what should I work on
next?" It outranks `ARCHITECTURE_REVIEW.md`, `docs/AUTHORING_GUIDE.md` and every review file for
that question. Those describe how the machine is built; this describes what the machine is for.

**Where it came from.** Every claim below was derived from systems and text already in this
repository — nothing here is invented. Citations are given so you can check the reading. Where a
genuine design call had to be made rather than read off the code, it is marked **⚠ MY CALL** and you
should overwrite it with what you actually meant.

**Status:** draft v1, 2026-08-13, written by an outside contractor. **Owner: you.** Rewrite freely;
the worst outcome is that this sits here unchallenged because it was easier than disagreeing with it.

---

## The premise

You are in debt to the thing that is watching you, and it is watching you in order to price you.

**CYBERSUNDAY** is a first-person immersive sim set in **Headshot City**, where the currency is the
**Zorkmid** and the bank is called **the Ledger**. The Ledger is not a metaphor. It is the same
entity the first-launch Terms of Service calls "the Server, the Mainframe, the Distant Authority, or
the Ledger" — the always-online apparatus that claims to record every act, omission and hesitation
you have ever made (`resources/ui/terms_of_service.gd:35`). It finances the chrome in your body, and
it remembers what you do with it. The code already states this as a rule:
*"the entity financing your body-mods is the entity that remembers what you do with them"*
(`scripts/ui/player_text.gd:200-201`).

The Ledger does not judge you morally. It judges you **actuarially**. It reads your character sheet
as a loan application and files a verdict: *"Preferred debtor — 780. We like your odds of living
long enough."* When it declines you, it gives a reason from a form: *"Filed reason: life expectancy
under the repayment term."* *"Filed reason: no visible means of support."* *"Filed reason:
allocation left undrawn — see 'Notable Cowardice'."* — a callback to the standing heading the Terms
gate files your declined choices under.

> **Note on those lines:** they live at `scripts/ui/player_text.gd:202-207` (the six bands) and
> `:212-220` (the eight filed reasons), and their `[PH]` markers have already been cleared. They are
> plainly *written* — they are among the best copy in the project — and the marker is still
> over-applied elsewhere. Before treating a raw `[PH]` count as a work estimate, audit which are
> genuinely empty and which are just unblessed. The real backlog is smaller than the count suggests.

And it pays you, quietly, for shooting people in the head. `credit_standing_per_headshot = 0.05`,
doubled for a kill where every wound was a headshot. The comment in the source names the joke and
never tells the player: *"The Ledger's algorithm is opaque and rewards 'productive conduct' it
declines to explain … the surveillance dividend"* (`resources/tuning/EconomySettings.gd:221-225`).

That is the game. Not "cyberpunk mercenary." **A comedy about being scored.**

---

## The three pillars

**1. The Ledger is always watching, and it is always adding.**
Debt compounds 2% at every in-game dawn; savings earn 0.5%. One signed number is both
(`GameState.account`) — depositing *is* repayment, and you can never hold a death-safe hoard while
you owe. A day is 600 real seconds, so the first bill lands ~7.5 minutes into a session and every
10 minutes after. The clock is the antagonist. Everything else is you trying to outrun it.

**2. Every atrocity comes with a receipt.**
A kill plays a cha-ching. An all-headshot kill plays canned crowd applause. Shooting a severed limb
out of the air pays a "Confetti!" bounty. A kill past 30 m pays per metre. Your entire cash wallet
transfers to whoever kills you. The world does not disapprove of violence — it *itemises* it. And
the same canned applause plays when you pet a dog (`scripts/npc/death.gd:56` and `:61-62`,
`scripts/components/pettable.gd:140`), which is the whole comic thesis in one sound file: the city
congratulates you identically for a perfect execution and for basic kindness, because it cannot tell
the difference and has never tried.

**3. The skyline is the scoring surface.**
The district is 156 × 157 m and ~60 m tall. Only 35% of walkable ground is street; **30% is rooftop
at ~12 m and another 14% is tower-top climbing to 33 m**, with an underlevel at −7 to −18 m reached
through three manholes. Verticality, not floorplan, is what this level is. The per-metre marksman
bounty and the sniper archetype (`resources/characters/sniper.tres` — 150 m sight, slow fire, starts
unloaded, and currently placed nowhere: no scene in the project references it) are the other two
thirds of the same idea. **⚠ MY CALL:** commit to *the player owns the roofs, the NPCs own the
street*. That works with the level and the AI exactly as they exist today; the reverse needs a nav
re-bake first.

---

## The core loop

> **Owe → hunt → get paid → decide what to do with it → the sun comes up and you owe more.**

1. **You start in the red.** New Game bills your implants straight onto the account (200–900 zm
   each — the laser-sight chip drops to 100 for any build carrying gunplay above 0), so the run
   legitimately opens in debt, and the Ledger rates your build before you have done anything.
2. **You earn almost exclusively by killing** — 1 zm base, 2 for a headshot, 4 for an all-headshot
   kill, plus collateral, confetti and long-range extras. Style is not cosmetic; style is income.
3. **You bank it or you carry it.** Banked money survives your death and earns interest. Carried
   money is spendable without the 3% non-cash fee — and transfers to your killer.
4. **Dawn posts the interest** and burns a point of standing if you are in arrears.
5. **Your credit score sets your ceiling** — how much chrome you can put on the tab, which is how
   much better you can get at step 2.

That is a complete, closed, already-implemented loop. **Nothing in it is speculative.**

**The rent is armed.** `RentCollector` is authored on the level root at **20 zm every in-game day**
(`scenes/levels/trenchboom_test_level.tscn`, pinned by `tests/test_shipping_level_rent.gd`). 20 sits
deliberately in the daily-expense tier the rest of the economy already uses — a health pack is 25, a
pistol 50, two pistol reloads 20, the old man's ask 56 — so one good score buys several days but
idling never does. It takes from the **cash wallet**, never the bank, so banking your money is also
how you dodge the landlord; that tension is the point.

**The rent now serves notice first.** It used to not, and the result was the sharpest playtest
reaction this project has had: *"what fucking rent?"* Nothing in the game establishes a tenancy —
there is no landlord, no lease and no home anywhere in the project — so the collector's first and
only player-facing artefact was a red *Rent unpaid* toast. And it was guaranteed: the clock is
600 s/day starting at noon, so the first dawn lands **7m30s into a fresh run**, while
`player_starting_money` is `0`. Every new player met the rent as an accusation about a debt the game
had never mentioned, with an empty wallet the game itself had dealt them. The fix was not to soften
the rent but to make it announce itself — `notice_message` states the terms at the first dawn,
`grace_days = 1` puts the first charge a full in-game day later, and the miss line now names the
shortfall instead of gesturing at it. The joke ("you owe money you did not agree to owe") only lands
once the game admits it is making one.

**⚠ OPEN — the cadence is still argued against the wrong unit.** The paragraph above prices 20 zm
against a *day*, but a day here is **10 real minutes**: that is 120 zm/hour of play, against an
income of 1–4 zm per kill on a level with six NPCs, three of them armed raiders. "One good score
buys several days" is not currently true at any score the level can actually pay out. Either
`period_days` goes up, `rent_amount` comes down, or `day_length_seconds` does — but the number needs
re-deriving against real minutes, not in-game days.

**What is still missing: a reason to stop.** There is no fail state. Rent that cannot be paid takes
what you have, toasts the shortfall, and fires `payment_missed` — **and nothing is listening to that
signal.** An unpayable debt still just compounds forever.

**⚠ MY CALL, and the most important open item in this document:** wire something to
`payment_missed`. That signal is now the single highest-leverage hook in the game — it is the one
place the economy can grow teeth, and it costs a connection, not a system.

---

## What a session feels like

Twenty to forty minutes. You wake owing money you did not agree to owe, in a district where the only
licensed industry is violence and the only sanction is social. You take a contract, or you take a
roof and a rifle. You get paid in receipts and applause. You go to a machine in the wall that
applauds you — tinnily, through a forty-cent speaker — for paying back part of what you owe. Then
the sun comes up and the number goes up anyway.

The register is **bureaucratic absurdism**, not cyberpunk cool. The longest and most confident piece
of writing in this project is a fake EULA that slowly loses its mind. The second longest is a bank's
adverse-action notice. **Defensible reference points, all supported by text already in the repo:**
Douglas Adams' Vogon paperwork, Pratchett's Ankh-Morpork guild-and-ledger comedy, the Fallout
terminal-and-perk-card voice the `[ HIDDEN ]` badge already imitates, and the Zork/NetHack lineage
that gave the Zorkmid its name. **Not** Blade Runner melancholy. **Not** Cyberpunk 2077 swagger.
Nothing in the source text supports either.

---

## The first ten minutes

A real sequence, so the numbering means something. Nothing here needs a new system.

1. **The gauntlet.** Warning card → Terms of Service → the sky reveals **CYBERSUNDAY** 168 seconds
   into the intro, hung 1 km out so the skyline occludes it (`scenes/game.tscn:24-37` — the title is
   authored there as an override; the component's own default is the two-word "CYBER SUNDAY"). This
   already works and is the best-executed thing in the game. Leave it alone.
2. **The Ledger prices you.** Character creation, then the implant screen: it reads your build,
   files a verdict and a reason, and sets your line. You buy chrome on credit. **You are now in
   debt and the clock is running.** This also already works.
3. **You spawn on the street with nothing but fists — and your first gun is on a corpse.** There is
   no weapon *pickup* in the district, but there is an armed raider: **"Bastard"**, 3 HP, faction
   `raiders`, carrying a pistol (`scenes/levels/trenchboom_test_level.tscn:2637-2643`, whose
   `weapon_data` resolves to `resources/weapons/pistol.tres`). **⚠ MY CALL:** keep it
   that way. A city that sells you a body on credit should not hand you a gun; you take your first
   one off someone who no longer needs it, and the cha-ching that follows is the tutorial. What is
   missing is not the weapon — it is *placing Bastard where a new player will meet him within about
   thirty seconds.*
4. **The old man asks for 56 Zorkmids** or the Red Dot District kills him. He is already written and
   already standing there.
5. **The raider offers 100 to kill the man at the ATM.** Already written, three lines away. This is
   your moral fork and it is free: **the man at the ATM is the old man.** *(**⚠ MY CALL** — the
   text does not say so today. It should. Two NPCs, two offers, one target: help him earn it, or
   take the contract on him. That is your first quest and it costs one afternoon of wiring.)*
6. **First dawn, ~7.5 minutes in.** "The Ledger added 4 zorkmids to what you owe." The player learns
   what the game is actually about at the moment they can no longer un-learn it.

---

## What this game is NOT

A scope fence. Every line here is a thing the systems could tempt you into and shouldn't.

- **Not an open world.** One district, 156 m across, stacked five deep. Depth, not width.
- **Not a story-driven RPG.** There is no branching narrative and no ending written. The Ledger is a
  *situation*, not a plot. Quests are contracts.
- **Not a simulation of civic life.** The GOAP roster is Survive / Engage / Investigate / Detect /
  Idle — a fight-or-hide vocabulary. NPCs in Headshot City are threat-processors, and **that is the
  satire**, not a gap to fill. Do not promise shopkeeping, working or socialising without budgeting
  new GOAP goals.
- **Not a crime game.** There is no law, no wanted level, no police, and there should not be.
  Enforcement is private, priced and personal — which is exactly what the raider's contract and the
  Red Dot District's collectors already imply.
- **Not a chess game.** `scripts/chess/` is 886 lines of complete rules engine and AI, placed
  nowhere. Either a chess table goes in the district this month as a Ledger-adjacent gag about
  opaque scoring, or it gets deleted.

---

## The open questions only you can answer

1. **Is CYBERSUNDAY the title?** It is in the sky, and the editor plugin is named after it. Assumed
   fixed here.
2. **What happens when you can't pay?** The one hole in the loop. Eviction? A collector NPC who
   comes for you? Repossession of installed chrome — the Ledger taking back the arm it financed?
   *(That last one is thematically perfect and mechanically supported: implants can be uninstalled.)*
3. **Is the Ledger ever wrong, and does the game ever say so?** Right now it is an unchallenged
   authority. Satire usually wants a crack in it.
4. **Does the player have a name, or are they "the Perpetually Observed"?** The game already hides
   NPC names behind "Stranger" until introduced. Pointing that at the player is available.

---

## Appendix A — what already exists

Read this as your inventory, not your backlog. Everything marked ✅ is implemented and reachable.

| Pillar | Backed by | State |
| --- | --- | --- |
| Debt clock | `scripts/components/ledger_accrual.gd` (on the Player), `WorldClock` 600 s/day | ✅ armed |
| Credit score | `scripts/player/stat_underwriting.gd`, 24 authored actuarial weights, 300–850, 5 bands | ✅ armed |
| Surveillance dividend | `EconomySettings.credit_standing_per_headshot` | ✅ armed, **never explained to the player** |
| Bounty economy | `EconomySettings` kill/headshot/collateral/confetti/long-range | ✅ armed |
| Death moves money | wallet → killer, or a physics money bag | ✅ armed |
| Rent | `scripts/components/rent_collector.gd`, 20 zm/day on the level root | ✅ **armed** |
| Fail state | `payment_missed` fires with the shortfall | ⛔ **signal has no listener** |
| Vertical district | `alive.map`, 15,600 m² over five altitude bands | ✅ built, **barely populated** |
| Sniper enemy | `resources/characters/sniper.tres`, 150 m sight | ⛔ **placed nowhere — no scene in the project references the archetype** |
| Six stats | no soft cap, straight-line effects, all six have real read sites | ✅ armed |
| Stranger names | `GameState.reveal_name` | ✅ armed |
| Provoke / pardon | holster to "ask for forgiveness" | ✅ armed |
| NPC barks (~20 categories) | delivery system complete, TTS + 14 m bubble | ⛔ **zero lines written** |
| NPCs review your radio | `scripts/components/music_quality.gd`, deterministic hash, 4 tiers | ⛔ **zero lines written** |
| Quests | 2 authored, both `[PH]`-titled | ⛔ **neither reachable** |

---

## Appendix B — the writing backlog, in priority order

The delivery constraint on everything below: lines are spoken by **Flite text-to-speech** with
per-character rate and pitch, in a bubble, on a 6-second cooldown, within 14 m. Write **short
declaratives**. No subordinate clauses. No jokes that depend on spelling. Mis-tuned voices are a
comic resource — the severed Head speaks at rate 10.0, pitch 2.0.

1. **The ~20 bark categories.** Greet, thanks, spot, hurt, reload, search, flee, check-body, three
   death-witness reactions, warn, aggro, pardon, pardon-fleeing. This is the single highest-leverage
   writing task in the project and will do more for perceived world-density than any new quest.
   *Note:* the old example lines in `scripts/npc/bark_set.gd`'s doc comments are scrubbed AI placeholder text —
   do not paste them back.
2. **The two existing offers, wired into two real quests.** The systems are done; this is authoring.
3. **Audit the ~196 `[PH]` strings in `scripts/ui/player_text.gd` — 90 constants plus ~106 inline
   templates — and the further 71 marked literals in `.tres` and scene files, then write the ones
   that are genuinely empty.** Many are already written and merely unblessed, and the whole Ledger
   band-and-reason set has already had its markers cleared — that five-minute pass is done. The
   naming palette for the rest already exists and is good: *Chrome Grin, Ironheart Locket,
   Featherframe Weave, Mule Rig, Trigger Bone, Second Wind Cell, Deadeye Optic*. Body parts plus
   industrial materials, sold on credit, described by a bank.
4. **The level's name.** Done — the shipping `LevelData` already reads `display_name = "Headshot
   City"` (`resources/levels/trenchboom.tres:9`), unmarked.
5. **Item and perk descriptions.** The ten weapon mods are written (and still `[PH]`-marked); the
   other 39 item resources and both perks are empty. Write them in the Ledger's voice — these are
   collateral, and the bank has an opinion about their resale value.
6. **The music critic.** Four tiers × a handful of lines turns the radio into a running gag about
   arbitrary aesthetic authority — thematically the same joke as the Ledger scoring *you*.
7. **Normalise the character-name register.** Right now it runs Murray Chen / Kyle alongside
   Ms. Vile / Von Lime alongside Bastard / the Yard Guard. Three different games. **⚠ MY CALL:**
   lean on the epithet register — it matches "the Perpetually Observed", and nobody has a name until
   they give you one.

---

*One rule to keep this document honest: if a change does not serve a pillar in this file, it is not
the next thing to work on. If you keep wanting to do work this file does not justify, change this
file first — deliberately — rather than working around it.*
