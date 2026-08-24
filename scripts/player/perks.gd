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


## Every Perk id authored on disk: scan PERK_DIR, load each .tres/.res and collect its non-empty INTERNAL `id` —
## distinct + sorted. EDITOR/TEST use only: it self-populates the PROPERTY_HINT_ENUM_SUGGESTION dropdown for
## DialogueChoice.required_perk_id (and any future perk-id picker), so a designer PICKS a perk id instead of
## typing one that must match EXACTLY. Never on a hot path — runtime resolution stays by_id's direct path load
## (export-safe) and PerkManager keeps the unlocked map. Mirrors the Factions / ItemIds registry scans.
##
## Reading the INTERNAL id rather than the filename is deliberate: every perk-id consumer compares against
## PerkManager._unlocked, which keys on Perk.id (PerkManager.unlock_perk), so THAT is the id that actually gates.
## By convention id == filename (the same convention by_id resolves on), so the two agree today; if a
## copy-pasted .tres ever drifts, this lists the gating id while by_id would fail to resolve it. Silent about
## that drift on purpose — like by_id, and for the same reason (see the header): perk-id validation lives in the
## CYBER SUNDAY perk inspector, and a dropdown scan is no place to push warnings.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(PERK_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")  # exported builds may append .remap to packed resources
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var res := load(PERK_DIR.path_join(f))
		# Type-filter, NOT item_ids.gd's duck-typed `res.get("id")`: plenty of other resources carry an `id` too (a
		# Faction / Item / Quest .tres parked in this folder would hand one over), and offering that as a perk id
		# suggests a gate PerkManager can never satisfy. Naming Perk costs nothing here — by_id already returns one,
		# so the no-compile-time-dep reason item_ids.gd ducks for does not apply.
		if res is Perk:
			var pid := String((res as Perk).id)
			if pid != "" and not out.has(pid):
				out.append(pid)
	out.sort()
	return out


## The perk ids as a comma-separated string, for a PROPERTY_HINT_ENUM_SUGGESTION dropdown hint_string.
static func ids_csv() -> String:
	return ",".join(ids())


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
