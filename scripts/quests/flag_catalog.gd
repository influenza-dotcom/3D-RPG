@tool
class_name FlagCatalog
extends Resource

## @system Story Flags
## @seam FlagCatalog (resources/story/FlagCatalog.tres, read through scripts/quests/story_flags.gd) lists every story flag name with a one-line description; every flag field (set_flag / required_flag / unlock_flag / expire_on_flag / set_flag_on_enter / FLAG objective target_id …) suggests these names in the Inspector, and ScanWiring WARNs on a flag the content uses that is not listed.
## @risk The dropdowns are SUGGESTIONS (PROPERTY_HINT_ENUM_SUGGESTION), not a closed enum, so a typo still saves — the ScanWiring WARN (Audit tab, validate_all) is what catches it; never turn the hint into PROPERTY_HINT_ENUM, or a flag not yet catalogued could not be typed at all.
## @test res://tests/test_flag_catalog.gd
##
## THE STORY FLAG CATALOG. Story flags are free-text keys in GameState's flag store: a TriggerVolume writes
## `met_the_fixer`, a dialogue choice reads `met_the_fixer`, a quest objective waits on it. Nothing ties the three
## spellings together, so at dozens of quests one rename or typo silently cuts a chain. The catalog is the one list of
## the names the game uses, each with the sentence a designer needs to reuse it correctly.
##
## Author it in the Inspector (CYBER SUNDAY → Browse → Story Flags opens it): add a key per flag, the value is its
## one-line description ("set when the player first reaches the alley mouth"). Runtime never reads it — GameState keeps
## taking any name — so an uncatalogued flag still works; it only draws the Audit / validate_all WARN.

## Flag name -> one-line description of what setting it means and who sets it.
@export var flags: Dictionary[StringName, String] = {}


## Every catalogued flag name, sorted, as Strings (the dropdown hint order).
func names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in flags:
		var s := String(k)
		if s != "" and not out.has(s):
			out.append(s)
	out.sort()
	return out


## The description for `flag_name`, or "" when it is not catalogued.
func description(flag_name: StringName) -> String:
	return String(flags.get(flag_name, ""))


## Whether `flag_name` is catalogued.
func has_flag(flag_name: StringName) -> bool:
	return flag_name != &"" and flags.has(flag_name)
