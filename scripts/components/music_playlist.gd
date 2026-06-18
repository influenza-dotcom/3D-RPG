class_name MusicPlaylist
extends RefCounted

## Pure, Node-free track-ordering for the in-world Radio's folder playlist — the same "logic stays a
## RefCounted so it's GUT-testable off-tree" idiom as RadioPlaybackState / SearchState. It holds a list of
## track PATHS and a play cursor; the Radio owns the actual AudioStream loading + playback. No Node, no I/O,
## no Time, no global RNG (shuffle is seeded), so it runs headless without tripping the engine-error wall.
##
## ORDER: set_tracks() builds a play order over the track indices — identity, or a DETERMINISTIC Fisher-Yates
## shuffle from a passed seed (the SearchState.regenerate phase-seed precedent: same seed + same paths -> same
## order, every run). current() reads the track at the cursor; advance() steps to the next, wrapping when
## `loop` (the radio cycles its folder forever) or returning "" once exhausted when not.

## The track file paths, in their on-disk (unshuffled) order. The play ORDER indexes into this.
var tracks: PackedStringArray = PackedStringArray()
## true -> play order is a seeded shuffle of `tracks`; false -> on-disk order.
var shuffle: bool = false
## true -> advance() wraps past the last track back to the first; false -> exhausts (current() goes "").
var loop: bool = true
## Cursor into `_order` (NOT into `tracks` — `_order[index]` is the real track index).
var index: int = 0

## The play order: a permutation of [0, tracks.size()). Identity unless shuffled.
var _order: PackedInt32Array = PackedInt32Array()

## (Re)load the playlist. `paths` are track file paths (any order); `p_shuffle`/`p_seed` pick a deterministic
## shuffle; `p_loop` cycles the folder. Resets the cursor to the first track of the (possibly shuffled) order.
func set_tracks(paths: PackedStringArray, p_shuffle: bool = false, p_seed: int = 0, p_loop: bool = true) -> void:
	tracks = PackedStringArray(paths)
	shuffle = p_shuffle
	loop = p_loop
	index = 0
	_rebuild_order(p_seed)

func _rebuild_order(p_seed: int) -> void:
	_order = PackedInt32Array()
	for i in range(tracks.size()):
		_order.append(i)
	if shuffle and tracks.size() > 1:
		# Fisher-Yates with a SEEDED RNG -> reproducible (no global RNG, no Time). Same seed -> same order.
		var rng := RandomNumberGenerator.new()
		rng.seed = p_seed
		for i in range(_order.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: int = _order[i]
			_order[i] = _order[j]
			_order[j] = tmp

## True while there's at least one track.
func has_tracks() -> bool:
	return tracks.size() > 0

## Number of tracks.
func size() -> int:
	return tracks.size()

## The path at the play cursor, or "" if empty / exhausted (a non-looping playlist walked off the end).
func current() -> String:
	if index < 0 or index >= _order.size():
		return ""
	return tracks[_order[index]]

## The current track's bare filename (no folder), for the NPC quality scorer / display. "" if empty.
func current_name() -> String:
	var path := current()
	return path.get_file() if not path.is_empty() else ""

## Step to the next track and return it. Wraps to the first when `loop`; otherwise parks past the end and
## returns "" (and keeps returning "" until set_tracks reloads).
func advance() -> String:
	if _order.is_empty():
		return ""
	index += 1
	if index >= _order.size():
		if loop:
			index = 0
		else:
			index = _order.size()  # exhausted sentinel -> current() returns ""
			return ""
	return current()
