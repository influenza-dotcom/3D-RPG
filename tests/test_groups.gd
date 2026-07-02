extends GutTest

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
