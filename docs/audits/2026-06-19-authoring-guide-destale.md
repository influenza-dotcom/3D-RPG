# Authoring-guide de-stale audit — 2026-06-19

A 24-agent workflow re-reviewed `docs/AUTHORING_GUIDE.md` against the live code for staleness — chapter-cluster
accuracy auditors with an adversarial verify stage, plus completeness auditors over the shipped systems.
**16 inaccuracies confirmed (0 false positives), 10 shipped systems found entirely undocumented.**

**Status: APPLIED** in commit `c2fcce7` ("Docs: de-stale AUTHORING_GUIDE.md — 16 fixes + 10 systems
documented"). This file is the historical record of what the audit found.

See also the forward-looking [designer capability-gap audit](2026-06-19-designer-capability-gaps.md).

## Verdict

The guide was stale on two axes: drifted claims in existing chapters, and ten systems built this dev cycle
that weren't documented at all. The most damaging were the three that actively told designers to do the wrong
thing: a §2 gotcha claiming Door/TriggerVolume/spawners "don't exist yet" (they ship as drop-in components),
and two steps instructing designers to hardcode a `faction_id` suggestion string that doesn't exist in any
script (the dropdown self-populates from `resources/factions/` via `Factions.ids_csv()`).

## Accuracy — 16 confirmed corrections (all applied)

- §2 gotcha no longer claims Door / TriggerVolume / spawners are unbuilt.
- Removed the two "hardcode the `faction_id` suggestion string" instructions (the dropdown auto-populates).
- `townsfolk` disposition is **FRIENDLY**, not NEUTRAL.
- Shipped arm/leg tints come from the **`BodyModelSwap` child**, not the NPC root.
- Radio catalogue entry now describes **folder-cycling** (`music_folder`/`shuffle`/`audible_radius`), not the old single-track design.
- `head_look` + `music_reactions` **ship ON** in `NpcAiSettings.tres` (only `hearing_initiates` stays off); fixed in 3 places for consistency.
- `auto_fit_collider` editor-preview note (the dual-mode stations preview-resize an existing collider).
- `backstab_arc_degrees` ships at **90.0** (not 1.0), in both the weapons and stealth chapters.
- Detection-meter toggle governs only the graded **bar**, not the four-tier text readout, and has no always-on mode.
- `combat_strict` (Radio duck) ducks through the INVESTIGATING phase — unlike the music.
- Instance `goap_profile` is the **Profile** group ("AI (GOAP)" is the `NpcData` resource's group).
- Refreshed stale line/symbol citations (`register_swapped_head`, companion contract, faction dropdown order, Bonfire chapter ref).

## Completeness — 10 shipped systems documented

New chapters: **Story flags**; **Triggers, encounters & cutscenes**; **Quests and the Journal**; **Map and
minimap**. New subsections: **Status effects** (Items), **Perks** (NPC services), **Patrol routes** (Placing
NPCs). Plus catalogue bullets (Door, TriggerVolume, PatrolPath/PatrolBehavior, PerkStation), new Quick-reference
rows, the story-flags entry in the Saving "what persists" list, and a renumbered Contents with all **69**
in-body `§N` cross-references remapped to match.
