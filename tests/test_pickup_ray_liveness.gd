extends GutTest

## PickupRay (ray_cast.gd) T2 liveness bail — a DEAD player must not grab / interact / throw, and (the per-frame
## twin in _physics_process) must not keep the hover cues painted: _unhandled_input reads
## `not (player as Character).is_alive()` as its FIRST statement and returns, and _physics_process reads the SAME
## predicate to swap the outline/readout updates for _clear_look_cues(). The full input-routing (InputMap +
## viewport + autoload menu screens) and the live raycast can't be driven off-tree, so this pins the exact
## PREDICATE the bails read on a bare Character built via .new() (NO add_child, NO _ready — Character._ready is
## not run here), plus the state-reset contract of _clear_look_cues on a bare PickupRay.
##
## Character is @abstract (can't be instantiated directly), so we subclass it with a bare concrete _Stub — the same
## trick test_smoke._ConcreteCharacter / test_character._Stub use. And because _ready never runs here, hp is NOT seeded
## from max_hp (the running game seeds it in _ready), so we set hp = max_hp by hand to reproduce the LIVE state the
## bail must let through — is_alive() is `not _dead and hp > 0.0`, and an un-readied Character has hp == 0.0.

## Concrete stand-in for the @abstract Character base (mirrors test_smoke._ConcreteCharacter / test_character._Stub).
class _Stub extends Character:
	pass


func test_is_alive_true_by_default() -> void:
	# A LIVE Character (_dead false, hp seeded > 0) is alive → the bail never fires → input routes normally.
	var c := _Stub.new()
	c.hp = c.max_hp  # _ready (which seeds this) is intentionally not run off-tree, so stamp the live HP by hand
	assert_true(c.is_alive(), "a live Character is alive — the PickupRay bail lets input through")
	c.free()


func test_is_alive_false_when_dead() -> void:
	# The moment take_damage latches _dead (which happens BEFORE die() during the whole cinematic), is_alive() is false
	# — the exact condition the PickupRay bail returns on, so a mid-keel-over grab / interact / throw is refused (C9/C14).
	var c := _Stub.new()
	c.hp = c.max_hp  # start alive, then latch death, so the assertion isolates the _dead latch (not a 0-hp default)
	c._dead = true
	assert_false(c.is_alive(), "_dead latched → is_alive() false → PickupRay bails for the whole death cinematic")
	c.free()


func test_clear_look_cues_resets_hover_state() -> void:
	# The dead-player per-frame gate calls _clear_look_cues() every physics frame of the cinematic — it must drop
	# EVERY hover-cue field (talk handler, look-highlight target, distance sentinel, readout latch) so nothing
	# lingers highlighted or read out on the corpse's crosshair. Off-tree PickupRay (.new(), no _ready, no live
	# raycast): seed the look-state by hand and assert one call resets it all. `player` stays null, so
	# _drive_readout's `as Player` downcast is null and the HUD push is skipped — the STATE reset is the contract
	# pinned here. The stand-in handler is a plain Node with no set_look_highlight, exercising the has_method guard.
	var ray := PickupRay.new()
	var handler := Node.new()
	ray._talk_handler = handler
	ray._highlighted = handler
	ray._talk_distance = 2.0
	ray._readout_shown = true
	ray._clear_look_cues()
	assert_null(ray._talk_handler, "dead-player clear must drop the talk handler")
	assert_null(ray._highlighted, "dead-player clear must drop the look-highlight target")
	assert_eq(ray._talk_distance, INF, "dead-player clear must reset the talk-distance sentinel")
	assert_false(ray._readout_shown, "dead-player clear must clear the readout-shown latch")
	handler.free()
	ray.free()
