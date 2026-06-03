extends GutTest

## GUT suite for the Phase 1 NPC type seam (scripts/npc/npc.gd).
##
## NPC is an @abstract class inserted between Character and Enemy
## (Character -> NPC -> Enemy) so future non-player actors can extend NPC without
## enemy-combat baggage. These asserts guard that the seam exists and is shaped
## correctly, and — critically — that `Enemy is Character` stays TRANSITIVELY true
## so every `is Character` / `is Enemy` runtime check across combat/effects keeps working.
##
## @abstract cannot be probed at runtime (GDScript exposes no is_abstract flag, and
## NPC.new() on an abstract class halts the runner rather than returning a catchable
## value), so the annotation is asserted by source-grepping npc.gd's text — the same
## _read_file pattern test_smoke.gd uses for enemy.gd's _on_damaged/_on_died.
##
## Phase 2: NPC now owns the combat OUTLINE (has_outline / outline_color / outline_width
## exports, applied in _ready via TalkHelpers.make_outline_material). Those export defaults
## are asserted below off a bare Enemy (load().new(), no add_child -> _ready never runs).

const NPC_PATH := "res://scripts/npc/npc.gd"
const ENEMY_PATH := "res://scenes/enemies/enemy.gd"


# --- NPC class exists and is shaped correctly ------------------------------

func test_npc_script_loads() -> void:
	var script = load(NPC_PATH)
	assert_not_null(script,
		"npc.gd must load — it is the shared base for all non-player actors")
	assert_true(script is GDScript,
		"npc.gd must be a GDScript")


func test_npc_is_declared_abstract() -> void:
	# No runtime abstract flag in GDScript; assert the source carries the annotation
	# (same source-grep approach as test_smoke's enemy hitstop-handler check).
	var content := _read_file(NPC_PATH)
	assert_true("@abstract" in content,
		"npc.gd must be @abstract so NPC is a base only and can never be instantiated directly")
	assert_true("class_name NPC" in content,
		"npc.gd must declare class_name NPC so subclasses and `is NPC` checks resolve globally")


# --- The Character -> NPC -> Enemy chain ------------------------------------

func test_enemy_extends_npc() -> void:
	# Build off-tree (load().new() WITHOUT add_child) so enemy.gd's _ready never runs —
	# matches the construction note in test_enemies.gd / test_player_core.gd.
	var e = load(ENEMY_PATH).new()
	assert_true(e is NPC,
		"Enemy must extend NPC (the new Character -> NPC -> Enemy seam)")
	e.free()


func test_enemy_is_still_a_character_transitively() -> void:
	# The whole point of a THIN seam: inserting NPC must not break `Enemy is Character`,
	# which combat/effects/death rely on (attack.gd, explosion_area.gd, death.gd, etc.).
	var e = load(ENEMY_PATH).new()
	assert_true(e is Character,
		"Enemy must STAY a Character transitively (Enemy -> NPC -> Character) so every `is Character` runtime check keeps matching enemies")
	assert_true(e is CharacterBody3D,
		"Enemy must stay a CharacterBody3D so move_and_slide / blast physics still apply")
	e.free()


# --- NPC combat-outline exports (Phase 2; defaults reproduce the old Character rim) --------

func test_npc_outline_exports_default_to_enemy_rim() -> void:
	# NPC owns the combat outline (Phase 2). Defaults must reproduce the old Character rim
	# values that used to be hardcoded consts, now actually reaching the shader. Built off-tree
	# (load().new() WITHOUT add_child) so _ready -> _setup_outline never runs; we read the raw
	# exported defaults off the bare object, matching this file's other Enemy construction.
	var e = load(ENEMY_PATH).new()  # Enemy extends NPC extends Character
	assert_true(e.has_outline,
		"NPC.has_outline must default true so enemies still get their combat outline")
	assert_eq(e.outline_color, Color.BLACK,
		"NPC.outline_color must default black -- the enemy's dark combat rim")
	assert_eq(e.outline_width, 0.085,
		"NPC.outline_width 0.085 is the intended rim thickness, now fed to the shader's outline_width uniform")
	e.free()


# Local source reader (mirrors test_smoke.gd's own _read_file — it is a file-local
# helper there, not a shared GutTest method, so this suite defines its own copy).
func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	var s := f.get_as_text()
	f.close()
	return s
