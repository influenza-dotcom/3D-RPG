extends GutTest

## ProvokeOnAttack drop-in: the player-attack hostility decision lifted out of NPC._on_damaged_by. A NEUTRAL
## flips hostile on the first player hit; a FRIENDLY forgives until cumulative damage passes
## host.friendly_aggro_threshold (then aggros + stops following); `enabled = false` never turns hostile.
## Driven here with a duck-typed stub host so the branches are pinned without an NPC _ready / scene tree.

## Minimal NPC stand-in exposing exactly the surface ProvokeOnAttack.react() touches; records the side effects.
class StubHost extends RefCounted:
	var _hostile: bool = false
	var _disposition: int = Disposition.Kind.NEUTRAL
	var _following: bool = false
	var _player_aggression: float = 0.0
	var friendly_aggro_threshold: float = 8.0
	var _voice = null  # null -> the bark calls are skipped (no NpcVoice off-tree)
	var provoke_count: int = 0
	var stop_following_count: int = 0
	var last_attacker = null
	func is_hostile() -> bool: return _hostile
	func resolved_disposition() -> int: return _disposition
	func is_following() -> bool: return _following
	func stop_following() -> void: stop_following_count += 1; _following = false
	func provoke(attacker = null) -> void: provoke_count += 1; last_attacker = attacker

func _player_attacker() -> Node:
	# A node in the &"Player" group (in-tree so is_in_group resolves), auto-freed at test end.
	var a := Node.new()
	add_child_autofree(a)
	a.add_to_group(&"Player")
	return a


func test_defaults_enabled() -> void:
	var p := ProvokeOnAttack.new()
	assert_true(p.enabled, "ProvokeOnAttack defaults enabled so an auto-built instance keeps the old behaviour")
	p.free()

func test_neutral_provokes_on_first_hit() -> void:
	var p := ProvokeOnAttack.new()
	var h := StubHost.new()
	h._disposition = Disposition.Kind.NEUTRAL
	p.react(h, _player_attacker(), 1.0)
	assert_eq(h.provoke_count, 1, "a NEUTRAL NPC provokes on the first player hit")
	assert_eq(h.stop_following_count, 0, "a neutral isn't following, so nothing to stop")
	p.free()
	h = null

func test_friendly_forgives_under_threshold() -> void:
	var p := ProvokeOnAttack.new()
	var h := StubHost.new()
	h._disposition = Disposition.Kind.FRIENDLY
	h.friendly_aggro_threshold = 8.0
	p.react(h, _player_attacker(), 3.0)
	assert_eq(h.provoke_count, 0, "a FRIENDLY under the threshold forgives the hit (no aggro)")
	assert_almost_eq(h._player_aggression, 3.0, 0.001, "the hit accumulates toward the threshold")
	p.free()
	h = null

func test_friendly_aggros_past_threshold_and_stops_following() -> void:
	var p := ProvokeOnAttack.new()
	var h := StubHost.new()
	h._disposition = Disposition.Kind.FRIENDLY
	h.friendly_aggro_threshold = 8.0
	h._following = true
	p.react(h, _player_attacker(), 8.0)
	assert_eq(h.provoke_count, 1, "a FRIENDLY past the threshold finally aggros")
	assert_eq(h.stop_following_count, 1, "a following companion stops following when it turns")
	p.free()
	h = null

func test_disabled_never_provokes() -> void:
	var p := ProvokeOnAttack.new()
	p.enabled = false
	var h := StubHost.new()
	h._disposition = Disposition.Kind.NEUTRAL
	p.react(h, _player_attacker(), 100.0)
	assert_eq(h.provoke_count, 0, "enabled=false -> the NPC never turns hostile from being hit")
	assert_almost_eq(h._player_aggression, 0.0, 0.001, "a disabled gate doesn't even accumulate aggression")
	p.free()
	h = null

func test_non_player_attacker_ignored() -> void:
	var p := ProvokeOnAttack.new()
	var h := StubHost.new()
	h._disposition = Disposition.Kind.NEUTRAL
	var enemy := Node.new()  # NOT in the Player group
	add_child_autofree(enemy)
	p.react(h, enemy, 5.0)
	assert_eq(h.provoke_count, 0, "only a PLAYER hit provokes — an enemy's stray fire doesn't flip a neutral")
	p.free()
	h = null

func test_already_hostile_ignored() -> void:
	var p := ProvokeOnAttack.new()
	var h := StubHost.new()
	h._hostile = true
	h._disposition = Disposition.Kind.NEUTRAL
	p.react(h, _player_attacker(), 5.0)
	assert_eq(h.provoke_count, 0, "an already-hostile NPC doesn't re-provoke")
	assert_almost_eq(h._player_aggression, 0.0, 0.001, "an already-hostile NPC doesn't accumulate forgiveness")
	p.free()
	h = null
