extends GutTest

## The GameSettings AUTOLOAD (managers/GameSettings.gd) — the one registry every system reads its tuning off
## (`GameSettings.<group>.<field>`). It is a table of preload()-ed .tres slots, so its whole contract is the
## table: every slot is present, is the RIGHT resource class (a slot re-pointed at the wrong .tres would still
## be non-null), lives at the conventional res://resources/tuning/<Class>.tres path, and is shared (one object,
## not a per-reader copy — a designer edit in the inspector must reach every reader). Pinned against the
## already-registered autoload; a second `.new()` would preload the same table for nothing.
##
## tests/test_autoload_order.gd smoke-checks nine slots are non-null; this file pins the FULL table + the class
## and path of each slot, that every value a .tres authors is the value the registry serves, plus the one runtime
## flag (allow_timescale_changes) — read, never mutated.

const SCRIPT_PATH := "res://managers/GameSettings.gd"
const TUNING_DIR := "res://resources/tuning/"

## slot name -> the global class its resource must be (mirrors the typed `var` table in GameSettings.gd).
const SLOTS := {
	&"player_movement": "PlayerMovementSettings",
	&"player_crouch": "PlayerCrouchSettings",
	&"player_aim": "PlayerAimSettings",
	&"player_lean": "PlayerLeanSettings",
	&"bunnyhop": "BunnyhopSettings",
	&"camera": "CameraSettings",
	&"screen_shake": "ScreenShakeSettings",
	&"weapon_general": "WeaponGeneralSettings",
	&"effects": "EffectsSettings",
	&"audio": "AudioSettings",
	&"physics_damage": "PhysicsDamageSettings",
	&"economy": "EconomySettings",
	&"player_feedback": "PlayerFeedbackSettings",
	&"npc_ai": "NpcAiSettings",
	&"npc_audio": "NpcAudioSettings",
	&"npc_bark": "NpcBarkSettings",
	&"reputation": "ReputationSettings",
	&"distraction": "DistractionSettings",
	&"dialogue": "DialogueSettings",
	&"search": "SearchSettings",
	&"takedown": "SilentTakedownSettings",
	&"inventory": "InventorySettings",
	&"light_stealth": "LightStealthSettings",
	&"pickpocket": "PickpocketSettings",
	&"xp": "XpSettings",
	&"hud": "HudSettings",
	&"pickup_beacons": "PickupBeaconSettings",
	&"difficulty": "DifficultySettings",
	&"wait": "WaitSettings",
	&"station_music": "StationMusicSettings",
	&"wander_music": "WanderMusicSettings",
}


func _class_of(res: Resource) -> String:
	var s := res.get_script() as Script
	if s == null:
		return ""
	return String(s.get_global_name())


func test_the_registered_autoload_is_this_script() -> void:
	assert_not_null(GameSettings, "the GameSettings autoload must be registered — every tuning read goes through it")
	var by_path := get_tree().root.get_node_or_null(^"/root/GameSettings")
	assert_eq(by_path, GameSettings, "/root/GameSettings must be the same node the GameSettings global resolves to")
	assert_eq((GameSettings.get_script() as Script).resource_path, SCRIPT_PATH,
		"the autoload must run managers/GameSettings.gd (project.godot's autoload entry)")


func test_every_slot_is_present_and_the_right_class() -> void:
	for slot in SLOTS:
		assert_true(slot in GameSettings, "GameSettings must expose a `%s` slot" % slot)
		var res: Variant = GameSettings.get(slot)
		assert_not_null(res, "GameSettings.%s must be preloaded (a nil slot = readers crash at their first field access)" % slot)
		if res == null:
			continue
		assert_true(res is Resource, "GameSettings.%s must be a Resource" % slot)
		assert_eq(_class_of(res), SLOTS[slot],
			"GameSettings.%s must be a %s — the wrong class is non-null but every typed read of it fails" % [slot, SLOTS[slot]])


func test_every_slot_lives_at_the_conventional_tuning_path() -> void:
	for slot in SLOTS:
		var res: Resource = GameSettings.get(slot)
		if res == null:
			continue
		var expected := "%s%s.tres" % [TUNING_DIR, SLOTS[slot]]
		assert_eq(res.resource_path, expected,
			"GameSettings.%s must be the designer-editable %s (a tuning file that moved is a slot pointing at a stale copy)" % [slot, expected])
		assert_true(ResourceLoader.exists(expected), "%s must exist on disk" % expected)
		var script := res.get_script() as Script
		assert_eq(script.resource_path, "%s%s.gd" % [TUNING_DIR, SLOTS[slot]],
			"the %s script must sit beside its .tres in resources/tuning/" % SLOTS[slot])


func test_slots_are_shared_with_the_resource_cache_not_private_copies() -> void:
	# A reader that load()s the .tres by path (a tool script, a test) and a reader going through the registry
	# must see ONE object, or an inspector edit reaches one and not the other.
	for slot in SLOTS:
		var res: Resource = GameSettings.get(slot)
		if res == null:
			continue
		var cached := load(res.resource_path)
		assert_same(cached, res, "GameSettings.%s must be the cached resource, not a duplicate" % slot)


func test_no_two_slots_share_a_resource() -> void:
	var seen := {}
	for slot in SLOTS:
		var res: Resource = GameSettings.get(slot)
		if res == null:
			continue
		var id := res.get_instance_id()
		assert_false(seen.has(id), "GameSettings.%s must not alias another slot (%s)" % [slot, seen.get(id, "")])
		seen[id] = slot


func test_the_slot_table_matches_the_script_exactly() -> void:
	# Drift guard both ways: a slot added to GameSettings.gd must be added here (so its class + path get pinned),
	# and a slot removed there must leave this table. Enumerates the script's own Resource-typed vars.
	var script := GameSettings.get_script() as Script
	var declared := {}
	for p in script.get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if p.type == TYPE_OBJECT:
			declared[StringName(p.name)] = true
	for slot in SLOTS:
		assert_true(declared.has(slot), "GameSettings.gd must declare the `%s` slot this test pins" % slot)
	for name in declared:
		assert_true(SLOTS.has(name), "GameSettings.gd declares `%s` — add it to SLOTS so its class + path are pinned" % name)
	assert_eq(declared.size(), SLOTS.size(), "the pinned table and the script's Resource slots must be the same size")


func test_allow_timescale_changes_is_a_bool_that_ships_true() -> void:
	# The one non-resource member: a runtime-mutable flag (managers/GameSettings.gd:95, deliberately NOT in a .tres
	# "because tests toggle it" — debug_actions_world's `timescale` override clears and restores it). So the live
	# autoload value can legitimately be false mid-suite and only its TYPE is pinned here; the DEFAULT is read off a
	# throwaway bare instance of the same script. (Script.get_property_default_value() is NOT the read for this:
	# GDScript only records defaults for @export-ed members, so it answers null for a plain `var` and would pin
	# nothing.) Nothing here mutates the autoload.
	var live: Variant = GameSettings.allow_timescale_changes
	assert_typeof(live, TYPE_BOOL, "allow_timescale_changes must stay a bool — bullet-time gates read it as one")
	var fresh: Node = (GameSettings.get_script() as Script).new()  # off-tree: GameSettings declares no _ready
	assert_eq(fresh.allow_timescale_changes, true,
		"allow_timescale_changes must default to true — a false default silently disables bullet time everywhere")
	fresh.free()


## Field types whose value can be compared across two independent loads of the same .tres. Object-typed fields
## (Curves, the underwriting rows) are skipped: a cache-bypassing reload mints fresh sub-resources, so they would
## differ by identity even when the file reached the registry intact.
const COMPARABLE_TYPES := [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2,
	TYPE_VECTOR3, TYPE_COLOR]

## Slots the Settings autoload legitimately overwrites at boot with the player's own Options (FOV and mouse
## sensitivity onto `camera`, the shake-scale product onto `screen_shake` — managers/Settings.gd), so their live
## value is SUPPOSED to differ from the file.
const OPTIONS_OVERLAID_SLOTS := [&"camera", &"screen_shake"]


## Most of the tuning .tres files author nothing (their @export defaults ARE the tuning), so "is the value
## positive" cannot tell a parsed file from a bare script instance. What CAN: every field a .tres actually
## authors (its parsed value differs from a bare instance of the same script) must read back from the registry
## as the AUTHORED value. A slot built from code, or pointed at a copy that dropped the designer's edits, serves
## the script default there and fails by name. The closing count proves at least one shipped file authors
## something, so the sweep can never pass vacuously.
func test_authored_tres_values_reach_the_registry_not_code_defaults() -> void:
	var authored := 0
	for slot in SLOTS:
		if slot in OPTIONS_OVERLAID_SLOTS:
			continue
		var live: Resource = GameSettings.get(slot)
		if live == null:
			continue  # test_every_slot_is_present_and_the_right_class names the missing slot
		if live.resource_path.is_empty():
			fail_test("GameSettings.%s was not loaded from its .tres (empty resource_path) — a designer's edits there never reach the game" % slot)
			continue
		var parsed := ResourceLoader.load(live.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var bare: Resource = (live.get_script() as Script).new()
		for p in parsed.get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or int(p.usage) & PROPERTY_USAGE_STORAGE == 0:
				continue
			if not (int(p.type) in COMPARABLE_TYPES):
				continue
			var from_file: Variant = parsed.get(p.name)
			var script_default: Variant = bare.get(p.name)
			if from_file == script_default:
				continue  # not authored in the file: registry and code agree by construction
			authored += 1
			assert_eq(live.get(p.name), from_file,
				"GameSettings.%s.%s must serve the value %s authors (%s), not the script default (%s)" % [
					slot, p.name, live.resource_path, str(from_file), str(script_default)])
		bare = null
		parsed = null
	assert_gt(authored, 0,
		"at least one shipped tuning .tres must author a non-default value (NpcAiSettings.tres / SearchSettings.tres do) — zero means the sweep compared nothing")
