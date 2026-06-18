extends GutTest

## MusicPlaylist: the pure, Node-free track-ordering for the Radio's folder playlist. Every method takes only
## String paths / ints and touches no tree, no Time, no global RNG (shuffle is seeded), so we .new() it and
## assert ordering directly off-tree, releasing the ref per CLAUDE.md.

const MP := preload("res://scripts/components/music_playlist.gd")

func _paths(n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(n):
		out.append("res://music/track_%02d.mp3" % i)
	return out

# --- Empty ---

func test_empty_has_no_tracks() -> void:
	var p := MP.new()
	assert_false(p.has_tracks(), "a fresh playlist has no tracks")
	assert_eq(p.size(), 0, "size 0 when empty")
	assert_eq(p.current(), "", "current() is empty when there are no tracks")
	assert_eq(p.advance(), "", "advance() is empty when there are no tracks (no crash)")
	p = null

func test_set_empty_paths_stays_empty() -> void:
	var p := MP.new()
	p.set_tracks(PackedStringArray(), false, 0, true)
	assert_false(p.has_tracks(), "explicit empty path list -> no tracks")
	assert_eq(p.current(), "", "current() empty")
	p = null

# --- Single track ---

func test_single_track_current() -> void:
	var p := MP.new()
	p.set_tracks(_paths(1), false, 0, true)
	assert_true(p.has_tracks(), "one track -> has_tracks")
	assert_eq(p.size(), 1, "size 1")
	assert_eq(p.current(), "res://music/track_00.mp3", "current() is the only track")
	p = null

func test_single_loop_repeats_on_advance() -> void:
	var p := MP.new()
	p.set_tracks(_paths(1), false, 0, true)  # loop = true
	assert_eq(p.advance(), "res://music/track_00.mp3", "looping single track wraps back to itself")
	assert_eq(p.advance(), "res://music/track_00.mp3", "and again")
	p = null

func test_single_no_loop_exhausts_on_advance() -> void:
	var p := MP.new()
	p.set_tracks(_paths(1), false, 0, false)  # loop = false
	assert_eq(p.advance(), "", "non-looping single track exhausts after one advance")
	assert_eq(p.current(), "", "current() goes empty once exhausted")
	assert_eq(p.advance(), "", "stays exhausted on further advances")
	p = null

# --- Multi track ---

func test_multi_advances_in_order() -> void:
	var p := MP.new()
	p.set_tracks(_paths(3), false, 0, true)
	assert_eq(p.current(), "res://music/track_00.mp3", "starts at the first track")
	assert_eq(p.advance(), "res://music/track_01.mp3", "advance -> second")
	assert_eq(p.advance(), "res://music/track_02.mp3", "advance -> third")
	p = null

func test_multi_loop_wraps_past_end() -> void:
	var p := MP.new()
	p.set_tracks(_paths(3), false, 0, true)
	p.advance()  # -> 1
	p.advance()  # -> 2
	assert_eq(p.advance(), "res://music/track_00.mp3", "looping wraps past the last track to the first")
	p = null

func test_multi_no_loop_exhausts_past_end() -> void:
	var p := MP.new()
	p.set_tracks(_paths(3), false, 0, false)
	p.advance()  # -> 1
	p.advance()  # -> 2
	assert_eq(p.advance(), "", "non-looping exhausts past the last track")
	assert_eq(p.current(), "", "current() empty once exhausted")
	p = null

# --- current_name ---

func test_current_name_is_basename() -> void:
	var p := MP.new()
	p.set_tracks(_paths(2), false, 0, true)
	assert_eq(p.current_name(), "track_00.mp3", "current_name() is the bare filename, not the full path")
	assert_eq(MP.new().current_name(), "", "current_name() empty when there are no tracks")
	p = null

# --- Shuffle (deterministic, seeded) ---

func _order_of(p) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(p.current())
	for _i in range(p.size() - 1):
		out.append(p.advance())
	return out

func test_shuffle_same_seed_is_deterministic() -> void:
	var a := MP.new()
	var b := MP.new()
	a.set_tracks(_paths(8), true, 12345, true)
	b.set_tracks(_paths(8), true, 12345, true)
	assert_eq(_order_of(a), _order_of(b), "same seed + same paths -> identical shuffled order, every run")
	a = null
	b = null

func test_shuffle_is_a_permutation_of_the_tracks() -> void:
	var p := MP.new()
	var src := _paths(8)
	p.set_tracks(src, true, 999, true)
	var order := _order_of(p)
	assert_eq(order.size(), src.size(), "shuffle keeps every track exactly once (count)")
	var sorted_src := src.duplicate()
	sorted_src.sort()
	var sorted_order := order.duplicate()
	sorted_order.sort()
	assert_eq(sorted_order, sorted_src, "shuffle is a permutation — same set of tracks, none lost or duplicated")
	p = null

func test_shuffle_actually_reorders_for_some_seed() -> void:
	# Across a handful of seeds at least one must differ from the on-disk order (proves shuffle isn't a no-op).
	var src := _paths(8)
	var identity := MP.new()
	identity.set_tracks(src, false, 0, true)
	var id_order := _order_of(identity)
	var any_differs := false
	for s in range(1, 12):
		var p := MP.new()
		p.set_tracks(src, true, s, true)
		if _order_of(p) != id_order:
			any_differs = true
		p = null
	assert_true(any_differs, "shuffle produces a non-identity order for at least one seed")
	identity = null

func test_unshuffled_keeps_disk_order() -> void:
	var p := MP.new()
	p.set_tracks(_paths(4), false, 0, true)
	assert_eq(_order_of(p), _paths(4), "no shuffle -> tracks play in the order given")
	p = null
