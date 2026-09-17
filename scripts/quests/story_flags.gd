extends RefCounted
## Story-flag registry: the names in the FlagCatalog, for a PROPERTY_HINT_ENUM_SUGGESTION dropdown on every flag field
## (DialogueChoice.required_flag / set_flag, DialogueSelectorRow.required_flag, Quest.expire_on_flag,
## QuestStage.set_flag_on_enter, a FLAG QuestObjective's target_id, Door / Lock.unlock_flag, Merchant.required_flag,
## Readable.set_flag_on_read, Switch / TriggerVolume.set_flag, TutorialPrompt.seen_flag, CutsceneAction.flag_name),
## and for ScanWiring's uncatalogued-flag WARN. A SUGGESTION, never a closed enum: a flag not yet in the catalog stays
## typable, and the Audit tab reports it.
##
## NO class_name on purpose — const-preloaded where needed, matching the ItemIds / Factions / Calibers registries, so
## there is nothing for the global script class cache to miss. The catalog is loaded lazily by PATH (not preloaded), so
## a @tool Resource that preloads this file never drags the catalog .tres into its own load chain. Editor / test use —
## runtime flag reads and writes never touch it.

const CATALOG_PATH := "res://resources/story/FlagCatalog.tres"


## The FlagCatalog resource, or null when the file is missing or is not a catalog (every consumer degrades to "no
## suggestions" / "nothing catalogued").
static func catalog() -> Resource:
	if not ResourceLoader.exists(CATALOG_PATH):
		return null
	var res := load(CATALOG_PATH)
	return res if res != null and res.has_method(&"names") else null


## Every catalogued flag name, sorted.
static func names() -> PackedStringArray:
	var cat := catalog()
	return cat.names() if cat != null else PackedStringArray()


## The flag names as a comma-separated string, for a PROPERTY_HINT_ENUM_SUGGESTION dropdown hint_string.
static func names_csv() -> String:
	return ",".join(names())


## The catalogued names as a set { name: true }, for ScanWiring's uncatalogued check.
static func name_set() -> Dictionary:
	var out := {}
	for n in names():
		out[n] = true
	return out
