extends GutTest

## LookAtInteractable — the shared base for the look-at world components (Wave 0 dedup) + its opt-in collider
## auto-fit. Off-tree: .new() (no _ready), so we drive the talk gate a subclass inherits through the interaction
## ray's own check, that the 4 components share the base, and that the collider auto-fit is a SAFE opt-in. The
## highlight tests below run the real _ready in a tiny in-tree harness (a bare Node3D host + a MeshInstance3D — no
## actor, no autoload) and read the outline id the tint duplicate is actually PAINTING (its `disposition_id` instance
## uniform), never only the stashed base id, which a hover borrow deliberately leaves untouched.


## A LookAtInteractable subclass that refuses the talk gate (the shape of an empty container or a looted corpse).
class _RefusingInteractable extends LookAtInteractable:
	func can_be_talked_to() -> bool:
		return false


## Readable (a note / sign / terminal) defines no can_be_talked_to of its own, so the base's answer is the one the
## interaction ray reads (PickupRay._is_interactable) to light the hover and let Interact through. A note that
## refused would sit in the world with no highlight and no way to read it. CONTROL: a subclass that does refuse is
## NOT actable through the same check, so the pass comes from the handler's answer, not from a ray that waves every
## handler through.
func test_a_note_that_does_not_override_the_talk_gate_is_actable_by_the_ray() -> void:
	var ray := PickupRay.new()
	var note := Readable.new()
	var refusing := _RefusingInteractable.new()
	assert_true(ray._is_interactable(note),
		"a Readable inherits the base talk gate, and the interaction ray must treat it as actable (hover + Interact)")
	assert_false(ray._is_interactable(refusing),
		"control: a subclass whose can_be_talked_to() refuses is not actable through the same ray check")
	note.free()
	refusing.free()
	ray.free()


func test_world_components_share_the_base() -> void:
	# The 4 components extend the base, so the talk-handler surface + outline live in one place.
	for path in [
		"res://scripts/components/container.gd",
		"res://scripts/components/can_pick_up.gd",
		"res://scripts/components/merchant.gd",
		"res://scripts/components/lootable_corpse.gd",
	]:
		var inst = load(path).new()
		assert_true(inst is LookAtInteractable, "%s must extend LookAtInteractable" % path)
		inst.free()


func test_auto_fit_collider_is_opt_in_and_safe() -> void:
	var li := LookAtInteractable.new()
	assert_false(li.auto_fit_collider, "collider auto-fit is OPT-IN (default off) — hand-sized colliders are never touched")
	li._fit_hitbox_to_host()  # off-tree: no host meshes -> safe no-op
	assert_eq(li.get_child_count(), 0, "with no host meshes, no hitbox is created (safe no-op)")
	li.free()


## XC1: the pure-delegate @tool subclasses (Switch, Readable) define no _ready of their own and inherit the base
## one. The editor half of that guard (Engine.is_editor_hint()) cannot be faked headless, but the RUNTIME half can
## be driven: if a subclass ever grew a _ready that forgot super(), it would stop joining the talk layer and stop
## highlighting its host, and the interaction ray would silently never find it.
func test_pure_delegate_subclasses_inherit_the_runtime_wiring() -> void:
	for path in ["res://scripts/components/switch_lever.gd", "res://scripts/components/readable.gd"]:
		var host := Node3D.new()
		add_child_autofree(host)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		host.add_child(mesh)
		var inst: LookAtInteractable = load(path).new()
		inst.collision_layer = 1  # the Area3D default, so the assert below proves _ready rewrote it
		host.add_child(inst)  # inherited _ready -> talk layer + _build_outline
		assert_eq(inst.collision_layer, TalkHelpers.TALK_LAYER,
			"%s must still join the talk layer through the inherited _ready, or the interaction ray never hits it" % path)
		assert_eq(inst.collision_mask, 0, "%s is aimed at, it senses nothing" % path)
		inst.set_look_highlight(true)
		assert_eq(_painted_id(mesh), float(InkOutline.TINT_ID_HOVER),
			"%s must highlight its host on look-at through the inherited outline build" % path)
		inst.set_look_highlight(false)
		assert_null(mesh.get_node_or_null(InkOutline.TINT_DUP_NAME),
			"%s must give the host back on look-away (the hover-created ring is freed)" % path)


## --- The borrowed-outline contract (the 2026-08-15 ATM bug) -----------------------------------------------
## A mesh carries exactly ONE outline id, and the hover BORROWS it: on look-at it stamps white and remembers
## what was there, on look-away it puts that back. The shipping ATM is authored `highlight_color = Color(1,1,1,0)`
## + `highlight_width = 0.0` ("no hover outline") AND sits directly under the level root, so its host was the
## whole map: hovering it took the outline off every actor in the level until you looked away. Two independent
## pins, either of which alone kills that symptom — keep both, they guard different halves: the invisible-highlight
## refusal below, and the actor/prop prune after it.
## (Until 2026-08-27 the borrowed thing was the ONE `material_overlay` slot and the outline was an inverted
## hull. Same contract, one layer down: the slot is now the tint duplicate's id.)

class _FakeActor extends Node3D:
	func flash_red() -> void:  # Character's API — this subtree drives its own outline
		pass

class _FakeProp extends Node3D:
	func set_outline_visible(_want = null) -> void:  # Throwable's API — this subtree drives its own outline
		pass


## The id a mesh's tint duplicate is currently PAINTING (its instance uniform — what the ink shader reads), or -1
## when the mesh has no duplicate at all.
func _painted_id(m: MeshInstance3D) -> float:
	var dup := m.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	if dup == null:
		return -1.0
	var v: Variant = dup.get_instance_shader_parameter(&"disposition_id")
	return float(v) if v != null else -1.0


## One harness for the guard AND its control, so the only thing that differs between them is the authored
## highlight: a host carrying a mesh that already wears somebody's HOSTILE ring, plus a bare mesh with no ring.
func _highlight_rig(color: Color, width: float) -> Dictionary:
	var host := Node3D.new()
	add_child_autofree(host)
	var ringed := MeshInstance3D.new()
	ringed.mesh = BoxMesh.new()
	InkOutline.apply_tint_mesh(ringed, InkOutline.TINT_ID_HOSTILE)  # stand-in for an NPC's disposition outline
	host.add_child(ringed)
	var bare := MeshInstance3D.new()
	bare.mesh = BoxMesh.new()
	host.add_child(bare)
	var li := LookAtInteractable.new()
	li.highlight_color = color
	li.highlight_width = width
	host.add_child(li)  # _ready -> _build_outline
	return {"li": li, "ringed": ringed, "bare": bare}


func test_visible_highlight_borrows_the_outline_and_gives_it_back() -> void:
	# CONTROL for the guard below: the same rig with the default visible highlight really does borrow.
	var rig := _highlight_rig(Color(1.0, 1.0, 1.0, 1.0), 1.0)
	var li: LookAtInteractable = rig["li"]
	var ringed: MeshInstance3D = rig["ringed"]
	var bare: MeshInstance3D = rig["bare"]
	assert_eq(_painted_id(ringed), float(InkOutline.TINT_ID_HOSTILE), "setup: the mesh starts wearing the hostile ring")
	li.set_look_highlight(true)
	assert_eq(_painted_id(ringed), float(InkOutline.TINT_ID_HOVER),
		"a visible highlight must paint the hover white over the mesh while it is looked at")
	assert_eq(_painted_id(bare), float(InkOutline.TINT_ID_HOVER),
		"a bare mesh gets a hover ring built for the look-at")
	li.set_look_highlight(false)
	assert_eq(_painted_id(ringed), float(InkOutline.TINT_ID_HOSTILE),
		"look-away must paint the borrowed hostile ring back, not leave the enemy white")
	assert_null(bare.get_node_or_null(InkOutline.TINT_DUP_NAME),
		"look-away must free the ring the hover built on bare scenery")


func test_invisible_highlight_never_borrows_the_outline() -> void:
	# Exactly how the shipping ATM is authored (alpha 0 AND width 0), then each switch on its own: either one
	# alone means "this one gets no hover outline".
	for authored in [[Color(1.0, 1.0, 1.0, 0.0), 0.0], [Color(1.0, 1.0, 1.0, 0.0), 1.0], [Color(1.0, 1.0, 1.0, 1.0), 0.0]]:
		var rig := _highlight_rig(authored[0], authored[1])
		var li: LookAtInteractable = rig["li"]
		var ringed: MeshInstance3D = rig["ringed"]
		var bare: MeshInstance3D = rig["bare"]
		li.set_look_highlight(true)
		assert_eq(_painted_id(ringed), float(InkOutline.TINT_ID_HOSTILE),
			"an invisible highlight (color %s, width %s) must leave the hostile ring PAINTED while looked at - borrowing it strips the actor's outline" % [authored[0], authored[1]])
		assert_false(ringed.get_node(InkOutline.TINT_DUP_NAME).has_meta(InkOutline.TINT_HOVER_META),
			"an invisible highlight must not take ownership of the ring's colour at all")
		assert_null(bare.get_node_or_null(InkOutline.TINT_DUP_NAME),
			"an invisible highlight must not build a hover ring on bare scenery either")
		li.set_look_highlight(false)
		assert_eq(_painted_id(ringed), float(InkOutline.TINT_ID_HOSTILE),
			"look-away leaves the hostile ring exactly as it was")


func test_highlight_never_adopts_an_actor_or_prop_subtree() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var own := MeshInstance3D.new()
	own.mesh = BoxMesh.new()
	host.add_child(own)
	var actor := _FakeActor.new()
	var actor_mesh := MeshInstance3D.new()
	actor_mesh.mesh = BoxMesh.new()
	actor.add_child(actor_mesh)
	host.add_child(actor)
	var prop := _FakeProp.new()
	var prop_mesh := MeshInstance3D.new()
	prop_mesh.mesh = BoxMesh.new()
	prop.add_child(prop_mesh)
	host.add_child(prop)
	var li := LookAtInteractable.new()  # default white highlight -> a REAL borrow, so the prune is what saves us
	host.add_child(li)  # _ready -> _build_outline
	assert_true(li._meshes.has(own), "the host's own mesh IS collected (the highlight still works)")
	assert_false(li._meshes.has(actor_mesh),
		"an actor subtree (flash_red) is pruned — it drives its own disposition outline + damage flash")
	assert_false(li._meshes.has(prop_mesh),
		"a prop subtree (set_outline_visible) is pruned — it drives its own rest/claimed outline")
