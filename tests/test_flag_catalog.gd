extends GutTest

## THE STORY FLAG CATALOG (workstream 4). resources/story/FlagCatalog.tres lists every story flag with a one-line
## description; every flag field suggests its names in the Inspector (PROPERTY_HINT_ENUM_SUGGESTION — typable, never a
## closed enum); ScanWiring WARNs on a flag the content uses that the catalog does not list.
##
## The hint checks read get_property_list(), the path the Inspector takes: the engine runs _validate_property for every
## script in the chain there, so TutorialPrompt's own seen_flag hint and TriggerVolume's set_flag hint both apply.

const StoryFlags := preload("res://scripts/quests/story_flags.gd")
const ScanWiring := preload("res://addons/cybersunday_tools/panel_audit/scan_wiring.gd")


func _hint_of(obj: Object, field: String) -> Dictionary:
	for p in obj.get_property_list():
		if str(p["name"]) == field:
			return p
	return {}


func _assert_suggests_flags(obj: Object, field: String, label: String) -> void:
	var p := _hint_of(obj, field)
	assert_false(p.is_empty(), "%s exports %s" % [label, field])
	assert_eq(int(p.get("hint", -1)), PROPERTY_HINT_ENUM_SUGGESTION, "%s.%s is a SUGGESTION dropdown (still typable)" % [label, field])
	assert_eq(str(p.get("hint_string", "")), StoryFlags.names_csv(), "%s.%s suggests exactly the catalogued flags" % [label, field])


func test_the_shipped_catalog_loads_and_lists_the_flag_code_sets() -> void:
	var cat := StoryFlags.catalog()
	assert_not_null(cat, "resources/story/FlagCatalog.tres loads as a FlagCatalog")
	assert_true(cat is FlagCatalog, "and it is the FlagCatalog class")
	var code_flag := String(GameState.HOLSTER_FORGIVENESS_TUTORIAL_SEEN_FLAG)
	assert_true(StoryFlags.names().has(code_flag), "the flag GameState sets from code is catalogued")
	assert_ne((cat as FlagCatalog).description(StringName(code_flag)), "", "with its one-line description")
	for n in StoryFlags.names():
		assert_ne((cat as FlagCatalog).description(StringName(n)), "", "every catalogued flag carries a description (%s)" % n)
	assert_eq(StoryFlags.name_set().size(), StoryFlags.names().size(), "name_set mirrors names")


func test_a_catalog_answers_names_sorted_and_its_descriptions() -> void:
	var cat := FlagCatalog.new()
	cat.flags = {&"bridge_lowered": "The winch was pulled.", &"alarm_live": "The warehouse alarm tripped."}
	assert_eq(cat.names(), PackedStringArray(["alarm_live", "bridge_lowered"]), "names are sorted for the dropdown")
	assert_true(cat.has_flag(&"alarm_live"), "has_flag finds a catalogued name")
	assert_false(cat.has_flag(&"alarm_lives"), "a typo is not catalogued")
	assert_false(cat.has_flag(&""), "a blank name never is")
	assert_eq(cat.description(&"bridge_lowered"), "The winch was pulled.", "description reads the value")
	assert_eq(cat.description(&"nope"), "", "an unknown flag has no description")
	cat = null


func test_every_flag_field_on_a_resource_suggests_the_catalog() -> void:
	var choice := DialogueChoice.new()
	_assert_suggests_flags(choice, "required_flag", "DialogueChoice")
	_assert_suggests_flags(choice, "set_flag", "DialogueChoice")
	var row := DialogueSelectorRow.new()
	_assert_suggests_flags(row, "required_flag", "DialogueSelectorRow")
	var quest := Quest.new()
	_assert_suggests_flags(quest, "expire_on_flag", "Quest")
	var stage := QuestStage.new()
	_assert_suggests_flags(stage, "set_flag_on_enter", "QuestStage")
	var action := CutsceneAction.new()
	_assert_suggests_flags(action, "flag_name", "CutsceneAction")
	choice = null
	row = null
	quest = null
	stage = null
	action = null


func test_a_flag_objective_suggests_flags_and_a_pickup_objective_suggests_items() -> void:
	var obj := QuestObjective.new()
	obj.type = QuestObjective.Type.FLAG
	_assert_suggests_flags(obj, "target_id", "QuestObjective(FLAG)")
	obj.type = QuestObjective.Type.PICKUP
	assert_ne(str(_hint_of(obj, "target_id").get("hint_string", "")), StoryFlags.names_csv(),
		"a PICKUP objective's target_id keeps the item-id suggestions, not flags")
	obj = null


func test_every_flag_field_on_a_component_suggests_the_catalog() -> void:
	var nodes := {
		"Door": [Door.new(), ["unlock_flag"]],
		"Lock": [Lock.new(), ["unlock_flag"]],
		"Merchant": [Merchant.new(), ["required_flag"]],
		"Readable": [Readable.new(), ["set_flag_on_read"]],
		"Switch": [Switch.new(), ["set_flag"]],
		"TriggerVolume": [TriggerVolume.new(), ["set_flag"]],
		"TutorialPrompt": [TutorialPrompt.new(), ["seen_flag", "set_flag"]],
	}
	for label in nodes:
		var node: Node = nodes[label][0]
		for field in nodes[label][1]:
			_assert_suggests_flags(node, field, label)
		node.free()


func test_scan_wiring_warns_on_every_used_flag_the_catalog_does_not_list() -> void:
	var writers := {"met_the_fixer": true, "alarm_live": true}
	var readers := {"met_the_fixer": true, "met_teh_fixer": true}
	var catalogued := {"met_the_fixer": true}
	var rows: Array = ScanWiring.uncatalogued_flag_findings(writers, readers, catalogued, {"met_teh_fixer": "res://x.tres"})
	assert_eq(rows.size(), 2, "one WARN per used-but-uncatalogued name (written or read)")
	assert_eq(rows.map(func(r): return str(r["severity"])), ["WARN", "WARN"], "WARN, not ERROR — the flag still works")
	assert_true(str(rows[0]["message"]).contains("\"alarm_live\""), "sorted: alarm_live first")
	assert_true(str(rows[1]["message"]).contains("\"met_teh_fixer\""), "then the typo")
	assert_eq(str(rows[1]["source"]), "res://x.tres", "the row points at the file that used it")
	assert_eq(ScanWiring.uncatalogued_flag_findings(writers, readers, {"met_the_fixer": true, "alarm_live": true, "met_teh_fixer": true}).size(), 0,
		"a fully catalogued project is quiet")
