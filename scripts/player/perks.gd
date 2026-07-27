extends RefCounted
## Perk registry: resolve the game's Perk resources by their stable id, mirroring the Factions registry idiom —
## by convention each perk's id matches its .tres filename under resources/perks/ (tough_hide.tres -> id
## &"tough_hide"), so resolution is a plain path load (export-safe, cached by the resource loader). Introduced
## as the DISPLAY-LABEL seam: BuildGate stores only a required_perk ID, and its deny toast needs the authored
## Perk.display_name behind that id. Deliberately SILENT on a miss (unlike Factions.by_id): a label lookup runs
## at toast/prompt time, and perk-id validation already lives in the CYBER SUNDAY perk inspector.
##
## Preloaded as a const where needed (NO class_name on purpose — nothing for the test suite's global script
## class cache to miss, matching factions.gd / ability_registry.gd).

const PERK_DIR := "res://resources/perks/"


## The Perk whose id (== its .tres filename) is `id`, or null (blank id / no such perk on disk).
static func by_id(id: StringName) -> Perk:
	if String(id).is_empty():
		return null
	for ext in [".tres", ".res"]:
		var path: String = PERK_DIR + String(id) + ext
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is Perk:
				return res
	return null


## The player-facing label for a perk id: the authored Perk.display_name VERBATIM (it may carry the "[PH] "
## marker — a caller composing it into an already-[PH]-prefixed template strips it via PlayerText.strip_prefix),
## else the raw id — so a missing/blank name degrades to exactly what callers rendered before authoring (their
## own capitalize of the id), never to a blank. The by-ID twin of the with-resource-in-hand display idiom
## PerkStation._perk_label / the level-up perk rows already use.
static func display_label(id: StringName) -> String:
	var p := by_id(id)
	if p != null and not p.display_name.is_empty():
		return p.display_name
	return String(id)
