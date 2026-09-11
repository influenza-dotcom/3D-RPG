extends GutTest

## Slice 3 (Door): open/close/toggle mechanics + the pivot swing + the look-at label, the lock gate (Lock child /
## keyed item / unlock_flag — unit-tested below, reusing lock.gd's path), and NPC bump-to-open (npc_try_open,
## swing_sign_away, of_collider). Built off-tree with a manually-assigned pivot, so _swing_to takes its off-tree
## branch (snap, no tween) — pure + tree-free.

func test_open_close_toggle_swings_pivot() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.open_angle = 90.0
	assert_false(door.is_open(), "starts closed")
	door.open()
	assert_true(door.is_open(), "open() opens it")
	assert_almost_eq(pivot.rotation.y, deg_to_rad(90.0), 0.001, "pivot swung to open_angle")
	door.close()
	assert_false(door.is_open(), "close() closes it")
	assert_almost_eq(pivot.rotation.y, 0.0, 0.001, "pivot swung back closed")
	door.toggle()
	assert_true(door.is_open(), "toggle from closed -> open")
	pivot.free()
	door.free()

func test_open_is_idempotent() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.open()
	door.open()  # second open is a no-op (already open)
	assert_true(door.is_open(), "stays open")
	pivot.free()
	door.free()

func test_area_hitbox_follows_pivot_swing() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	var hitbox := CollisionShape3D.new()
	door.add_child(pivot)
	door.add_child(hitbox)
	door.pivot = pivot
	door.open_angle = 90.0
	hitbox.position = Vector3(0.5, 1.0, 0.0)
	door.open()
	assert_almost_eq(hitbox.rotation.y, deg_to_rad(90.0), 0.001, "the look-at hitbox rotates with the door panel")
	door.close()
	assert_almost_eq(hitbox.rotation.y, 0.0, 0.001, "the look-at hitbox returns to its closed rotation")
	assert_almost_eq(hitbox.position, Vector3(0.5, 1.0, 0.0), Vector3(0.001, 0.001, 0.001), "the closed hitbox returns to its authored offset")
	door.free()

func test_look_name_reflects_state() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.locked = false
	assert_eq(door.look_name(), "[PH] Open door", "closed + unlocked -> Open door")
	door.open()
	assert_eq(door.look_name(), "[PH] Close door", "open -> Close door")
	door.locked = true
	assert_eq(door.look_name(), "[PH] Locked", "locked (no flag) -> Locked")
	pivot.free()
	door.free()

func test_config_warning_without_pivot() -> void:
	var door := Door.new()
	# This pins the MISSING-PIVOT warning only. Doors are destructible by default, and a bare Node3D pivot has no
	# damage-taking blocker, so the durability warning (its own test: test_config_warning_when_the_blocker_cannot_take_damage)
	# would fire here too and fail "no warning once a pivot is assigned" — switch durability off to isolate this one.
	door.destructible = false
	assert_false(door._get_configuration_warnings().is_empty(), "warns when pivot is unassigned")
	var pivot := Node3D.new()
	door.pivot = pivot
	assert_true(door._get_configuration_warnings().is_empty(), "no warning once a pivot is assigned")
	pivot.free()
	door.free()


# --- Built-in key/lockpick gate (the same shared LockRules rule the Lock component uses) ---

## A minimal opener: a backpack, no toast surface (the door null-guards notify_toast). Built off-tree, so _try_unlock
## runs without the door entering the tree (no _ready / talk-layer setup needed to exercise the lock decision).
class _Opener extends Node:
	var inventory: CharacterInventory

func _stub_item(id: StringName) -> Item:
	var it := Item.new()
	it.id = id
	it.max_stack = 10
	return it

func test_door_pickable_gate_consumes_a_lockpick() -> void:
	var door := Door.new()
	door.locked = true
	door.pickable = true  # opt IN to lockpicking (default off = dead bolt)
	var opener := _Opener.new()
	opener.inventory = CharacterInventory.new()
	assert_false(door._try_unlock(opener), "locked + pickable but no lockpick -> stays locked")
	assert_true(door.locked)
	opener.inventory.add(_stub_item(&"lockpick"), 1)
	assert_true(door._try_unlock(opener), "a lockpick picks a pickable door")
	assert_false(door.locked, "the door is unlocked")
	assert_eq(opener.inventory.count_of_id(&"lockpick"), 0, "the pick is consumed (consumes_pick default true)")
	opener.inventory.free()
	opener.free()
	door.free()

func test_door_key_takes_precedence_over_a_lockpick() -> void:
	var door := Door.new()
	door.locked = true
	door.key_item_id = &"keycard_red"
	door.pickable = true  # keyed AND pickable — the "have the key OR pick it" door
	var opener := _Opener.new()
	opener.inventory = CharacterInventory.new()
	opener.inventory.add(_stub_item(&"keycard_red"), 1)
	opener.inventory.add(_stub_item(&"lockpick"), 1)
	assert_true(door._try_unlock(opener), "carrying the key opens the keyed+pickable door")
	assert_eq(opener.inventory.count_of_id(&"keycard_red"), 1, "the reusable key is not consumed (consume_key default false)")
	assert_eq(opener.inventory.count_of_id(&"lockpick"), 1, "the lockpick is untouched — the key took precedence")
	opener.inventory.free()
	opener.free()
	door.free()

func test_door_locked_is_a_dead_bolt_unless_pickable() -> void:
	var door := Door.new()
	door.locked = true  # no key, pickable defaults FALSE -> a sealed dead bolt (preserves the old behaviour)
	var opener := _Opener.new()
	opener.inventory = CharacterInventory.new()
	opener.inventory.add(_stub_item(&"lockpick"), 1)
	assert_false(door._try_unlock(opener), "a plain locked door is a dead bolt — a lockpick can't open it unless `pickable` is ON")
	assert_true(door.locked, "it stays locked")
	opener.inventory.free()
	opener.free()
	door.free()

func test_door_delegates_entirely_to_a_child_lock() -> void:
	# A child Lock OWNS unlocking: the Door's own built-in fields are ignored (door.gd _try_unlock early-returns on it).
	var door := Door.new()
	door.locked = false                # Door's own bolt off — the child Lock provides the lock
	door.key_item_id = &"phantom_key"  # a built-in key that MUST be ignored while a child Lock is present
	var lk := Lock.new()               # child Lock: locked + pickable by default
	door.add_child(lk)
	var opener := _Opener.new()
	opener.inventory = CharacterInventory.new()
	assert_false(door._try_unlock(opener), "no lockpick -> the child Lock holds (the door's phantom built-in key is ignored)")
	opener.inventory.add(_stub_item(&"lockpick"), 1)
	assert_true(door._try_unlock(opener), "a lockpick picks the CHILD Lock (delegation), not the door's built-in gate")
	assert_false(lk.locked, "the child Lock is now open")
	assert_false(door.locked, "and the Door reflects unlocked")
	opener.inventory.free()
	opener.free()
	door.free()  # frees the child Lock too


# --- NPCs open doors by walking into them (npc.gd _open_bumped_doors -> Door.of_collider + npc_try_open) ---
# The opener is a bare off-tree Node3D standing in for the NPC: npc_try_open only reads is_inside_tree /
# global_position off it, so the whole rule runs without an NPC's _ready (CLAUDE.md: never in a unit test). Off-tree,
# npc_try_open falls back to the authored swing side; the away-side pick is pinned on the pure swing_sign_away below.

func test_npc_opens_an_unlocked_door() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	var npc := Node3D.new()
	assert_true(door.npc_try_open(npc), "an unlocked door opens for an NPC that walks into it")
	assert_true(door.is_open(), "and it is now open")
	assert_true(door.npc_try_open(npc), "bumping an already-open door reports open (no re-swing)")
	npc.free()
	pivot.free()
	door.free()

func test_npc_cannot_open_a_locked_door() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.locked = true
	door.pickable = true  # even a PICKABLE lock: NPCs never pick
	var npc := Node3D.new()
	assert_false(door.npc_try_open(npc), "a locked door stays a wall to NPCs")
	assert_false(door.is_open(), "it stays closed")
	assert_true(door.locked, "the NPC never touched the lock — lock state is the player's alone")
	npc.free()
	pivot.free()
	door.free()

func test_npc_cannot_open_through_a_locked_child_lock() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	var lk := Lock.new()  # locked + pickable by default; the Door's own bolt stays off
	door.add_child(lk)
	var npc := Node3D.new()
	assert_false(door.npc_try_open(npc), "a still-locked child Lock refuses the NPC even with the Door's own bolt off")
	assert_true(lk.locked, "the NPC never picks the child Lock")
	npc.free()
	pivot.free()
	door.free()  # frees the child Lock too

func test_npc_can_open_off_makes_a_player_only_door() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.npc_can_open = false
	var npc := Node3D.new()
	assert_false(door.npc_try_open(npc), "npc_can_open OFF: NPCs treat the door as a wall")
	assert_false(door.is_open(), "it stays closed")
	door.open()
	assert_true(door.is_open(), "the player / script path (open()) ignores npc_can_open")
	npc.free()
	pivot.free()
	door.free()

func test_swing_sign_away_picks_the_side_away_from_the_opener() -> void:
	# A panel hinged at the origin, extending along +X. Derive where the AUTHORED swing ends rather than hardcoding the
	# engine's rotation handedness, then stand the opener on that side and on the other.
	var panel := Vector3(0.5, 1.0, 0.0)
	var angle := deg_to_rad(90.0)
	var authored_end := Basis(Vector3.UP, angle) * Vector3(panel.x, 0.0, panel.z)
	assert_eq(Door.swing_sign_away(Vector3.ZERO, 0.0, angle, panel, authored_end * 3.0), -1.0,
		"an opener standing where the authored swing ends gets the MIRROR swing — the panel must not sweep through them")
	assert_eq(Door.swing_sign_away(Vector3.ZERO, 0.0, angle, panel, -authored_end * 3.0), 1.0,
		"an opener on the far side keeps the authored swing")
	assert_eq(Door.swing_sign_away(Vector3.ZERO, 0.0, angle, Vector3.ZERO, authored_end * 3.0), 1.0,
		"no measurable panel (a point on the hinge) is a tie and keeps the authored side")
	# The same pick holds for a door already turned in its frame and hinged off the origin.
	var yaw := deg_to_rad(40.0)
	var hinge := Vector3(3.0, 0.0, -2.0)
	var turned_arm := Basis(Vector3.UP, yaw + angle) * Vector3(panel.x, 0.0, panel.z)
	assert_eq(Door.swing_sign_away(hinge, yaw, angle, panel, hinge + turned_arm * 3.0), -1.0,
		"closed_yaw and the hinge offset are honoured")

func test_door_opened_on_the_mirror_side_closes_back_to_rest() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	door.pivot = pivot
	door.open_angle = 90.0
	door._open_toward(-1.0)  # what open_away_from does for an NPC standing on the authored side
	assert_almost_eq(pivot.rotation.y, deg_to_rad(-90.0), 0.001, "an NPC-side open swings to the mirror of open_angle")
	door.close()
	assert_almost_eq(pivot.rotation.y, 0.0, 0.001, "close() returns it to the same closed rest from either side")
	door.open()
	assert_almost_eq(pivot.rotation.y, deg_to_rad(90.0), 0.001, "a later player / script open() uses the authored side again")
	pivot.free()
	door.free()

# --- Durability: shoot the door down (Door.take_damage, forwarded from door_panel.gd on the blocker) ---
# Off-tree: no _ready (hp is seeded from max_hp's default by the initialiser; tests set both explicitly), no FX / SFX /
# noise (all gated on is_inside_tree), no ledger (_persist no-ops off-tree). The pivot is add_child'd to the door so
# the break's queue_free of it is owned by the door's own free.

## Stands in for the Player: records the on_damaged_target push the door makes (the enemy-health-bar seam).
class _Attacker extends Node:
	var pushes: Array = []
	func on_damaged_target(target: Node, hp: float, max_hp: float, hp_before: float = -1.0) -> void:
		pushes.append([target, hp, max_hp, hp_before])

func _durable_door(hp: float) -> Door:
	var door := Door.new()
	var pivot := Node3D.new()
	door.add_child(pivot)
	door.pivot = pivot
	door.max_hp = hp
	door.hp = hp
	return door

func test_a_hit_chips_the_door_and_pushes_the_attackers_health_readout() -> void:
	var door := _durable_door(50.0)
	var shooter := _Attacker.new()
	watch_signals(door)
	door.take_damage(12.0, false, shooter)
	assert_almost_eq(door.hp, 38.0, 0.001, "damage drains hp")
	assert_false(door.is_destroyed(), "still standing above 0")
	assert_signal_emitted(door, "damaged", "damaged fires per hit")
	assert_eq(shooter.pushes.size(), 1, "the attacker is told once per hit (Player.on_damaged_target -> the enemy health bar)")
	if shooter.pushes.size() == 1:
		assert_eq(shooter.pushes[0][0], door, "the push names the DOOR as the target")
		assert_almost_eq(float(shooter.pushes[0][1]), 38.0, 0.001, "with its hp AFTER the hit")
		assert_almost_eq(float(shooter.pushes[0][2]), 50.0, 0.001, "and its max_hp")
		assert_almost_eq(float(shooter.pushes[0][3]), 50.0, 0.001, "and the PRE-hit hp, so the bar draws its chip shard")
	shooter.free()
	door.free()

func test_non_positive_damage_and_an_indestructible_door_are_ignored() -> void:
	var door := _durable_door(20.0)
	var shooter := _Attacker.new()
	door.take_damage(0.0, false, shooter)
	door.take_damage(-5.0, false, shooter)
	assert_almost_eq(door.hp, 20.0, 0.001, "zero / negative damage changes nothing")
	assert_eq(shooter.pushes.size(), 0, "and never raises the attacker's readout")
	door.destructible = false
	door.take_damage(999.0, false, shooter)
	assert_almost_eq(door.hp, 20.0, 0.001, "destructible OFF: a blast door shrugs off any hit")
	assert_false(door.is_destroyed(), "and never breaks")
	shooter.free()
	door.free()

func test_lethal_damage_breaks_the_door_once() -> void:
	var door := _durable_door(10.0)
	door.locked = true  # a lock is no defence against a shotgun
	var shooter := _Attacker.new()
	watch_signals(door)
	door.take_damage(6.0, false, shooter)
	door.take_damage(6.0, false, shooter)
	assert_true(door.is_destroyed(), "hp reached 0: the door is broken")
	assert_almost_eq(door.hp, 0.0, 0.001, "hp floors at 0 (never negative — the bar reads it by value)")
	assert_signal_emit_count(door, "destroyed", 1, "destroyed fires exactly once")
	assert_null(door.pivot, "the pivot (panel + blocker) is dropped: the doorway is physically clear")
	assert_false(door.can_be_talked_to(), "no interaction on a broken frame")
	assert_eq(door.collision_layer, 0, "and its look-at hitbox leaves the talk layer, so the ray never finds it")
	assert_eq(shooter.pushes.size(), 2, "both hits pushed the readout")
	if shooter.pushes.size() == 2:
		assert_almost_eq(float(shooter.pushes[1][1]), 0.0, 0.001, "the killing hit pushes the final 0 before the break")
	# A further hit is swallowed: no second break, no push.
	door.take_damage(6.0, false, shooter)
	assert_signal_emit_count(door, "destroyed", 1, "a hit on rubble does not re-break it")
	assert_eq(shooter.pushes.size(), 2, "nor push the readout")
	shooter.free()
	door.free()

func test_a_broken_door_is_open_to_npcs_and_ignores_open_close() -> void:
	var door := _durable_door(5.0)
	door.locked = true
	door.take_damage(5.0)
	var npc := Node3D.new()
	assert_true(door.npc_try_open(npc), "a broken door is no wall to an NPC, locked or not — there is no panel")
	assert_false(door.is_open(), "it is not 'open' either: open/close are meaningless on rubble")
	door.open()
	assert_false(door.is_open(), "open() on a broken door is a no-op (it must not overwrite the destroyed ledger bit)")
	npc.free()
	door.free()

func test_config_warning_when_the_blocker_cannot_take_damage() -> void:
	var door := Door.new()
	var pivot := Node3D.new()
	var bare := StaticBody3D.new()  # a blocker WITHOUT door_panel.gd: shots have no take_damage to call
	door.add_child(pivot)
	pivot.add_child(bare)
	door.pivot = pivot
	assert_false(door._get_configuration_warnings().is_empty(), "destructible ON + a bare blocker body warns: the door can never be hurt")
	door.destructible = false
	assert_true(door._get_configuration_warnings().is_empty(), "destructible OFF: a bare blocker is fine")
	door.destructible = true
	var panel := load("res://scripts/components/door_panel.gd").new() as StaticBody3D
	pivot.add_child(panel)
	assert_true(door._get_configuration_warnings().is_empty(), "a door_panel.gd body under the pivot satisfies it")
	door.free()

func test_panel_script_forwards_hits_and_answers_the_melee_gate() -> void:
	var door := _durable_door(30.0)
	var panel := load("res://scripts/components/door_panel.gd").new() as StaticBody3D
	door.pivot.add_child(panel)
	panel.call(&"take_damage", 10.0, false, null)
	assert_almost_eq(door.hp, 20.0, 0.001, "the blocker forwards take_damage to its Door (of_collider)")
	assert_true(DamageApplier.blocks_melee(panel), "default: a melee swing is refused at the panel")
	door.melee_can_damage = true
	assert_false(DamageApplier.blocks_melee(panel), "melee_can_damage ON: swings land")
	var wall := StaticBody3D.new()
	assert_false(DamageApplier.blocks_melee(wall), "a body without the gate method never blocks (swings behave as before)")
	assert_false(DamageApplier.blocks_melee(null), "null-safe")
	var loose := load("res://scripts/components/door_panel.gd").new() as StaticBody3D
	assert_false(DamageApplier.blocks_melee(loose), "a panel with no Door above it neither blocks nor forwards")
	loose.call(&"take_damage", 5.0, false, null)  # swallowed, no error
	loose.free()
	wall.free()
	door.free()

func test_texture_skins_the_panel_meshes_and_clears_back_to_the_authored_material() -> void:
	var door := _durable_door(1.0)
	var mesh := MeshInstance3D.new()
	var authored := StandardMaterial3D.new()
	mesh.material_override = authored
	door.pivot.add_child(mesh)
	var tex := PlaceholderTexture2D.new()
	door.texture = tex
	var mat := mesh.material_override as StandardMaterial3D
	assert_not_null(mat, "setting `texture` puts a StandardMaterial3D override on the panel mesh")
	if mat != null:
		assert_eq(mat.albedo_texture, tex, "with the texture as its albedo")
		assert_true(mat.has_meta(Door.TEXTURE_MAT_META), "tagged as door-generated")
		door.texture_tint = Color.RED
		assert_eq((mesh.material_override as StandardMaterial3D).albedo_color, Color.RED, "the tint re-applies IN PLACE")
		assert_eq(mesh.material_override, mat, "(no new material per edit)")
	door.texture = null
	assert_eq(mesh.material_override, authored, "clearing the texture restores the authored override")
	door.free()

func test_of_collider_finds_the_owning_door() -> void:
	# The prefab's shape: Door / DoorPivot / DoorBody — an NPC's slide contact reports the DoorBody.
	var door := Door.new()
	var pivot := Node3D.new()
	var body := StaticBody3D.new()
	door.add_child(pivot)
	pivot.add_child(body)
	door.pivot = pivot
	assert_eq(Door.of_collider(body), door, "the panel's blocker resolves to its Door")
	var wall := StaticBody3D.new()
	assert_null(Door.of_collider(wall), "an unrelated wall resolves to null")
	assert_null(Door.of_collider(null), "null-safe")
	wall.free()
	door.free()  # frees the pivot + body too
