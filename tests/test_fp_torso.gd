extends GutTest

## Contract tests for the first-person TORSO (look-down body awareness): looking down shows your own chest —
## your chosen body model, your drawn shirt, your skin tint — on the same rig as the FP legs. The rules that
## must hold, because their failures are silent:
##   1. BODY-ONLY: the FP rig must never mount a HEAD — it sits exactly where the camera is.
##   2. A whole_body appearance (one-piece character model) SKIPS the torso — it can't drop its head.
##   3. The customizer's drawn shirt reaches the FP chest (it planar-projects untinted, like the portrait).
##   4. Crouching sinks the torso by the head's own live drop (_update_fp_torso), so a standing-tuned pose
##      never clips the lowered camera.
## The FP body lives on the Player's FirstPersonBody component (scripts/player/first_person_body.gd) since the
## extraction — every pin below targets it. Off-tree source/export pins only (the test_player_core idiom) —
## building the rig needs a live tree.

const FP_BODY_SOURCE := "res://scripts/player/first_person_body.gd"

func test_the_fp_torso_ships_on() -> void:
	var p = load(FP_BODY_SOURCE).new()
	assert_true(p.first_person_torso,
		"first_person_torso must default ON — looking down should show your chest, not just legs")
	assert_true(p.has_method("_configure_fp_torso"),
		"the catalog body-only slice must exist — without it the torso never mounts")
	assert_true(p.has_method("_update_fp_torso"),
		"and the per-frame crouch-follow must exist — without it a crouch drops the camera into the chest")
	p.free()

func test_the_fp_torso_is_body_only() -> void:
	var src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	assert_false(src.contains("rig.head_model"),
		"the FP torso slice must NEVER mount a head — it sits exactly where the camera is")
	assert_true(src.contains("body.whole_body"),
		"a whole_body appearance must be skipped — a one-piece character model can't have its head chopped off")
	assert_true(src.contains("CharacterAppearanceCatalog.shirt_texture(host.appearance)"),
		"the drawn shirt must reach the FP torso — the shirt creator's art belongs on YOUR chest too")
	assert_true(src.contains("body_texture_planar = shirt != null"),
		"a drawn shirt must planar-project (set BEFORE body_texture) — the torso's own UVs scatter it to scraps")

func test_the_torso_faces_the_players_forward() -> void:
	# Body options are authored facing the NPC's +Z forward (body_model_rotation's own doc); the player faces
	# -Z, so the FP stamp must yaw 180 on top — without it you wear the torso BACKWARDS (the first-playtest bug).
	var src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	assert_true(src.contains("body.rotation + Vector3(0.0, 180.0, 0.0)"),
		"the FP torso must flip the catalog yaw 180 — NPC bodies face +Z, the player faces -Z")

func test_the_torso_is_dither_see_through_and_hides_on_crouch() -> void:
	# The Odyssey-style treatment: present but see-through at rest, fully faded while crouched (your chest
	# would fill the lowered view), always as a DITHERED screen-door — never smooth alpha blending, which
	# would re-sort against the world and break the PS1 read.
	var src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	# Re-pinned when the look-down dissolve landed: the crouch fade composes ON TOP of it (_update_fp_torso
	# builds `see` from the pitch fade, then lerps that toward 1.0 on crouch_t) instead of starting from the
	# rest transparency. Every load-bearing fact is still pinned — the driver is host.crouch.crouch_t, the
	# endpoint is a true 1.0 (fully out, not a partial ghost), and it rides the already-eased value unsmoothed —
	# plus the new one: crouch stacks over the dissolve rather than replacing it.
	assert_true(src.contains("lerpf(see, 1.0, host.crouch.crouch_t"),
		"crouching must fade the torso fully out (and back in on stand) over the look-down dissolve, riding the already-eased crouch_t")
	var swap_src := FileAccess.get_file_as_string("res://scripts/components/body_model_swap.gd")
	assert_true(swap_src.contains("TRANSPARENCY_ALPHA_HASH"),
		"the body see-through must be alpha-HASH (dithered) — depth-writes stay on, no transparency sorting")
	var shader_src := FileAccess.get_file_as_string("res://resources/shaders/shirt_planar.gdshader")
	assert_true(shader_src.contains("see_through"),
		"the drawn-shirt shader must carry the see_through dither — a custom-shirt chest must fade like a plain one")
	assert_true(swap_src.contains("sm.shader == ShirtPlanarShader"),
		"and the see-through pass must route the planar ShaderMaterial to that uniform (foreign shaders stay untouched)")
	# ⭐2026-08-16: this pin used to assert the OPPOSITE rule — solid by default, dithering OUT as the look
	# buried. That is only safe if the body is off-screen whenever you are not looking at it, and it is not:
	# the landing dip, the stair step-smoothing, the crouch and the walk-bob all drop the LENS toward a body
	# that has not moved, and the player saw their own chest while running, crouching and climbing stairs.
	# The rule is now inverted — HIDDEN until you look down — because a gate on the LOOK cannot be defeated by
	# anything that moves the camera.
	assert_true(src.contains("inverse_lerp(fp_body_reveal_start_deg"),
		"visibility must be PITCH-driven — the body is hidden until the look buries past the reveal band")
	assert_true(src.contains("lerpf(1.0, fp_torso_transparency, reveal)"),
		"...and it must ease from FULLY INVISIBLE toward its resting see-through, not the other way up")
	var p = load(FP_BODY_SOURCE).new()
	assert_between(p.fp_torso_transparency, 0.0, 0.5,
		"the FP torso rests near-solid ONCE REVEALED — this knob is the ghost amount, not the hide")
	assert_gt(p.fp_body_reveal_full_deg, p.fp_body_reveal_start_deg,
		"the reveal band must be a real range (full > start), or the ease divides toward a pop")
	assert_gt(p.fp_body_reveal_start_deg, 20.0,
		"the reveal must not start at a glance — below ~20 degrees you are looking where you are GOING, not at yourself")
	p.free()

func test_death_gibs_shed_the_torso_see_through() -> void:
	# Dying flings your torso as a body-part gib; the FP see-through must NOT ride along — a crouched death
	# otherwise throws a near-invisible torso that still offers its pickup prompt.
	var src := FileAccess.get_file_as_string("res://scripts/effects/body_part_gib.gd")
	assert_true(src.contains("bms_body_transp"),
		"the gib strip must clear the tagged see-through materials (the duplicated override AND per-surface dups)")
	assert_true(src.contains("see_through"),
		"and zero the planar shirt shader's see_through uniform on its duplicated override")

func test_the_torso_crouch_follow_tracks_the_heads_live_drop() -> void:
	# The clip-safety contract: the torso sinks by exactly the head's current drop below its standing height,
	# so chest-to-eye spacing is constant and a pose tuned standing stays clear crouched (and through any
	# other head-lowering the Crouch component drives).
	var src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	assert_true(src.contains("_fp_head_standing_y - host.head.position.y"),
		"the sink must be measured off the Head's LIVE position, not a duplicated crouch constant")
