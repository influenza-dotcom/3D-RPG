extends GutTest

## GUT suite for the single NPC class (scripts/npc/npc.gd). After the structural fold NPC is the ONE
## concrete non-player actor (Character -> NPC); the former Enemy / RangedEnemy classes are gone and
## their behaviour lives here, data-driven (weapon_data null = civilian, set = combatant). These
## asserts guard the class shape and that `NPC is Character` stays true, so every `is Character` /
## `is NPC` runtime check across combat / effects / death keeps matching.
##
## NPC is now concrete (instantiable), but we still build off-tree (load().new() WITHOUT add_child)
## so _ready never runs — it spawns a Perception / NavigationAgent3D and calls get_tree(). The
## @abstract REMOVAL is asserted by source-grepping npc.gd (no runtime abstract flag in GDScript),
## the same _read_file pattern test_smoke.gd uses.

const NPC_PATH := "res://scripts/npc/npc.gd"

func test_npc_script_loads() -> void:
	var script = load(NPC_PATH)
	assert_not_null(script, "npc.gd must load — it is the single non-player actor class")
	assert_true(script is GDScript, "npc.gd must be a GDScript")

func test_npc_is_concrete_not_abstract() -> void:
	# The fold makes NPC the single CONCRETE class — the @abstract annotation must be GONE, or the
	# enemy scenes that instance npc.gd would fail to load.
	var content := _read_file(NPC_PATH)
	assert_false("@abstract" in content,
		"npc.gd must NOT be @abstract — NPC is now the single concrete class the enemy scenes instance")
	assert_true("class_name NPC" in content,
		"npc.gd must declare class_name NPC so `is NPC` checks and the scene scripts resolve globally")

func test_npc_is_a_character_actor() -> void:
	# The fold must keep NPC a Character / CharacterBody3D so combat / effects / death (`is Character`
	# and `is NPC` checks in attack.gd, explosion_area.gd, player.gd) plus move_and_slide keep working.
	# Off-tree (no add_child) so _ready never runs.
	var n = load(NPC_PATH).new()
	assert_true(n is NPC, "an npc.gd instance must be an NPC")
	assert_true(n is Character,
		"NPC must stay a Character (NPC -> Character) so every `is Character` runtime check keeps matching")
	assert_true(n is CharacterBody3D,
		"NPC must stay a CharacterBody3D so move_and_slide / blast physics still apply")
	n.free()

func test_npc_outline_exports_default_to_combat_rim() -> void:
	# NPC owns the combat outline (Phase 2). Defaults reproduce the old hardcoded Character rim,
	# now actually reaching the shader. Off-tree so _ready -> _setup_outline never runs.
	var n = load(NPC_PATH).new()
	assert_true(n.has_outline, "NPC.has_outline must default true so combatants still get their outline")
	assert_eq(n.outline_color, Color.BLACK, "NPC.outline_color must default black — the dark combat rim")
	assert_eq(n.outline_width, 0.085,
		"NPC.outline_width 0.085 is the intended rim thickness, fed to the shader's outline_width uniform")
	n.free()

func test_npc_display_name_defaults_empty() -> void:
	# NPCs have a name (shown as the dialogue speaker label). Default empty => unnamed, label hidden.
	var n = load(NPC_PATH).new()
	assert_eq(n.display_name, "",
		"NPC.display_name must default empty so an unnamed NPC hides the dialogue speaker label")
	n.free()

func test_npc_weapon_knockback_immunity_defaults_off() -> void:
	var n = load(NPC_PATH).new()
	assert_false(n.immune_to_weapon_knockback,
		"immune_to_weapon_knockback must default false so existing enemies still take their weapon's recoil")
	n.free()

func test_npc_thanks_lines_contains_the_assist_thank() -> void:
	# THANKS_LINES is the pool the assist-thanks bark draws from. Assert the constant (the SAFE surface —
	# no tree / Talkable / TTS needed): a non-empty Array that includes the canonical "Hey, thanks!" line.
	assert_true(NPC.THANKS_LINES is Array,
		"NPC.THANKS_LINES must be an Array — thank_for_assist() picks a random line from it")
	assert_gt(NPC.THANKS_LINES.size(), 0,
		"NPC.THANKS_LINES must be non-empty so the assist-thanks bark always has a line to say")
	assert_true(NPC.THANKS_LINES.has("Hey, thanks!"),
		"NPC.THANKS_LINES must contain \"Hey, thanks!\" — the canonical assist-thanks line")

func test_npc_has_assist_and_bark_methods() -> void:
	# Assert the assist-thanks ENTRY POINT (thank_for_assist) and the unified bark EMITTER (_emit_bark,
	# which every bark path routes through) both exist on an instance. has_method only — we do NOT drive
	# them: _emit_bark awaits get_tree() and the thanks path needs a Talkable, so both need the tree.
	# Off-tree (no add_child) so _ready never runs, matching this suite's construction idiom.
	var n = load(NPC_PATH).new()
	assert_true(n.has_method("thank_for_assist"),
		"NPC must expose thank_for_assist() — the assist-thanks entry point called from _on_died")
	assert_true(n.has_method("_emit_bark"),
		"NPC must expose _emit_bark() — the single bark emitter every bark/thanks/remark path routes through")
	n.free()

# Local source reader (mirrors test_smoke.gd's own _read_file — a file-local helper there, not a
# shared GutTest method, so this suite defines its own copy).
func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	var s := f.get_as_text()
	f.close()
	return s
