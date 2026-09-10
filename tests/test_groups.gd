extends GutTest

const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")
const GroupsReflect := preload("res://addons/cybersunday_tools/core/groups_reflect.gd")

## Production source roots that must contain ZERO raw group-call literals — every group name goes through a Groups
## const (IDE autocomplete, safe rename, no silent typo drift). addons/ is excluded (the audit tooling documents
## example literals in comments) and tests/ is excluded (synthetic fixtures use throwaway group names on purpose),
## mirroring scan_disk's own SKIP_DIRS.
const PRODUCTION_ROOTS := ["res://scripts", "res://managers", "res://scenes", "res://resources"]

## M6: Groups.human_player(tree) is the ONE home for "which PLAYER-group member is the human" (companions join the
## same group for targeting but are NPCs, not Player). These verify the accessor's null/filter behavior, and a
## source-scan pins that every former hand-rolled `get_nodes_in_group("Player") ... not (p is NPC)` site now routes
## through it (the duplicated identity logic F78 flagged). A real Player can't be instantiated in-tree here (its
## _ready builds weapon/nav/audio + mutates statics — see CLAUDE.md), so the positive path is covered by playtest;
## the negative + centralization are covered here.

# Every site the M6 refactor routed through Groups.human_player (drift guard).
const ROUTED_SITES := [
	"res://scripts/ui/inventory_screen.gd",
	"res://scripts/ui/options_menu.gd",
	"res://scripts/ui/stats_screen.gd",
	"res://scripts/npc/npc.gd",
	"res://scripts/components/Throwable.gd",
	"res://scripts/components/music_director.gd",
	"res://scripts/components/prop_follow.gd",
	"res://scripts/components/reward_stinger.gd",
	"res://scripts/dialogue/dialogue_view.gd",
]


func test_human_player_null_tree_is_null() -> void:
	# A static util can't call get_tree(); an off-tree caller passes null (get_tree() is null then) and gets null back.
	assert_null(Groups.human_player(null), "a null tree yields no human player")


func test_human_player_ignores_non_player_group_members() -> void:
	# A PLAYER-group member that is NOT a `Player` (a companion is an NPC; a stray node is neither) must be skipped —
	# human_player positively identifies the Player class, so it never returns a non-Player member.
	var stub := Node3D.new()
	add_child_autofree(stub)
	stub.add_to_group(Groups.PLAYER)
	# With only a non-Player member in the PLAYER group (a headless GUT run has no real Player node), human_player must
	# return null — proving it filters by the Player class rather than returning the first group member.
	assert_null(Groups.human_player(get_tree()), "a PLAYER group with only a non-Player member yields no human player")
	stub.remove_from_group(Groups.PLAYER)


func test_human_player_sites_route_through_groups() -> void:
	# M6 centralization: every human-vs-companion lookup routes through Groups.human_player — no site re-implements the
	# local group-scan + non-NPC filter that F78 flagged as ~11-way duplication (and incidental UI->NPC coupling).
	for path in ROUTED_SITES:
		var src := FileAccess.get_file_as_string(path)
		assert_ne(src, "", "source should be readable: %s" % path)
		assert_true(src.contains("Groups.human_player("), "%s should route the human-player lookup through Groups.human_player" % path)


## Hard enforcement of "no hardcoded group literals": walk production source and assert no .gd uses a raw group-call
## literal (add_to_group(&"npc"), get_nodes_in_group("Player"), the dead lowercase "player", …) that the audit tags
## fixable — every one must be a Groups const. Reuses the audit's own comment-aware scanner over the REAL registry
## (GroupsReflect), so this guard and the CYBER SUNDAY audit panel can never disagree. Regressing (reintroducing a
## literal) fails this test — the drift guard the task asked for.
func test_no_raw_group_literals_in_production_source() -> void:
	var allowed := GroupsReflect.allowed_names()
	var const_names := GroupsReflect.const_by_name()
	assert_gt(allowed.size(), 0, "the Groups registry reflected at least one name (reflection is working)")
	var offenders: Array = []
	for root in PRODUCTION_ROOTS:
		_collect_group_literal_offenders(root, allowed, const_names, offenders)
	assert_eq(offenders.size(), 0, "production source must use Groups consts, not raw group literals:\n%s" % "\n".join(PackedStringArray(offenders)))


func _collect_group_literal_offenders(dir: String, allowed: Dictionary, const_names: Dictionary, offenders: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var full: String = dir.path_join(entry)
		if d.current_is_dir():
			_collect_group_literal_offenders(full, allowed, const_names, offenders)
		elif entry.get_extension() == "gd":
			var src := FileAccess.get_file_as_string(full)
			for f in ScanDisk.scan_gd_text(src, full, allowed, const_names):
				# A dead-player ERROR or a registered group_literal WARN carries a fix descriptor -> it's a raw literal
				# that must be a const. An unregistered-typo WARN has no fix; the audit surfaces it, but it's a
				# different concern (a possible new group), so don't fail this centralization guard on it.
				if f.get("fix") is Dictionary:
					offenders.append("%s — %s" % [full, f["message"]])
		entry = d.get_next()
	d.list_dir_end()


## Groups.is_usable — the "safe to read a TRANSFORM off this cached handle?" gate. The bug it exists for: a node
## REMOVED from the tree but not yet freed still passes is_instance_valid, and Node3D.get_global_transform() then
## hard-fails ("Condition \"!is_inside_tree()\" is true. Returning: Transform3D()") once per read. Two live paths
## produce exactly that node — reload_current_scene detaching the current scene (Player included) a frame before it
## frees it, and NpcPool.reclaim parking a dead body off-tree — so the detached case below is the whole point.
## NOTE: these deliberately never READ a transform off the off-tree node; doing so would emit the engine error and
## GUT's error tracker fails any test that crosses one.
func test_is_usable_true_only_while_in_tree() -> void:
	var n := Node3D.new()
	add_child_autofree(n)
	assert_true(Groups.is_usable(n), "a node inside the tree is usable")

func test_is_usable_false_for_detached_but_still_valid_node() -> void:
	var n := Node3D.new()
	add_child(n)
	remove_child(n)
	assert_true(is_instance_valid(n), "precondition: a detached node is still a VALID instance (this is the trap)")
	assert_false(Groups.is_usable(n), "a detached-but-valid node is NOT safe to read a transform off")
	n.free()

func test_is_usable_false_for_freed_and_null() -> void:
	var n := Node3D.new()
	n.free()
	assert_false(Groups.is_usable(n), "a freed handle is not usable (and the untyped param must not crash on it)")
	assert_false(Groups.is_usable(null), "null is not usable")
