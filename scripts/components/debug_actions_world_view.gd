extends RefCounted

## The VIEW commands of the in-game debug console (`inspect`, `navdebug`, `perf`, `wireframe`/`overdraw`/`unshaded`,
## `screenshot`, `hud`, `dither`, `dof`, `sway`, `lens`): one of the three command families split out of
## debug_actions_world.gd on 2026-09-11. `DebugActionsWorld.run()` still owns EVERY match arm — a registry row's
## case lives there and calls in here — so adding a command is still ONE registry row + ONE match case, plus the
## `_cmd_*` static in the family file it belongs to. Shared helpers live in debug_actions_world_common.gd
## (`Common.`). `quantize` deliberately stays in the main file: tests/test_color_quantization.gd pins its arm and
## its Settings poke there. The lens probe (scripts/tools/__lens_probe.gd) reads DOF_AUTHORED / LENS_AUTHORED here.
##
## CONTRACT (as the main file): a `_cmd_*` returns the lines to print — NEVER null, NEVER push_error.

const Common := preload("res://scripts/components/debug_actions_world_common.gd")
# Brand-new class_names are preloaded BY PATH into an untyped-usable const, never referenced by their class_name:
# until the editor rescans, a type annotation fails the WHOLE file to parse with "Could not find type X" and that
# cascades into every script that touches it. Precedent: debug_overlay.gd:11 (ErrorSinkScript).
const DebugCommandsScript := preload("res://scripts/components/debug_commands.gd")
# Existing classes, but preloaded by path for the same reason the registries are: no compile-time class dependency,
# so a stale global-class cache can never take this file down with it.
const DebugOverlayScript := preload("res://scripts/components/debug_overlay.gd")
const NavDebugOverlayScript := preload("res://scripts/components/nav_debug_overlay.gd")
const GroupsScript := preload("res://scripts/world/groups.gd")


# =============================================================================================================
# VIEW
# =============================================================================================================

## The look-at inspector (a Node3D, so it lives under the current scene, not on the console's CanvasLayer).
static func _cmd_inspect(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var insp := Common._inspector(ctx)
	if insp == null:
		return Common._one("inspect: no DebugInspector available (%s missing, or the name is taken under the current scene)" % Common.INSPECTOR_SCRIPT_PATH)
	if not insp.has_method(&"is_enabled") or not insp.has_method(&"set_enabled"):
		return Common._one("inspect: DebugInspector is missing set_enabled/is_enabled")
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], bool(insp.call(&"is_enabled"))))
	insp.call(&"set_enabled", on)
	return Common._one("inspect %s" % ("ON — live state is drawn over whatever you aim at" if on else "OFF"))

## The AI/nav overlay. Created on demand: NO level in the project ships a NavDebugOverlay, so a command that
## expects to find one finds nothing. It is parented under the CURRENT SCENE, never under the console's
## CanvasLayer, because it renders through an AiDebugDraw (a Node3D) child that must live in the 3D world — and
## whose _ready forces an identity transform, so it has to sit at world origin anyway.
static func _cmd_navdebug(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := Common._tree(ctx)
	if tree == null:
		return Common._one("no SceneTree")
	var created := false
	var ov := Common._find_or_create(tree.current_scene, &"DebugNavOverlay", NavDebugOverlayScript)
	if ov == null:
		return Common._one("could not create a NavDebugOverlay under the current scene")
	if not ov.has_meta(&"debug_layers_armed"):
		ov.set_meta(&"debug_layers_armed", true)
		created = true
		# The four AI layers ship OFF; this command promises cones, factions, GOAP labels and zones, so arm them
		# once on the instance we own rather than silently showing only the navmesh. Guarded by a meta so a
		# designer who later unticks a layer in the remote inspector doesn't get it forced back on next toggle.
		for setter: StringName in [&"set_show_sight_cones", &"set_show_faction_colors", &"set_show_goap_labels", &"set_show_trigger_zones"]:
			if ov.has_method(setter):
				ov.call(setter, true)
	var current := bool(ov.get(&"enabled"))
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], current))
	if ov.has_method(&"set_enabled"):
		ov.call(&"set_enabled", on)
	else:
		ov.set(&"enabled", on)
	var out := PackedStringArray()
	out.append("navdebug %s%s" % ["ON" if on else "OFF", "  (overlay created — no level ships one)" if created else ""])
	out.append("! PROCESS-WIDE: this writes NavigationServer3D.set_debug_enabled, the tree's debug_navigation_hint, and debug_enabled on EVERY NavigationAgent3D — not just this overlay's own drawing.")
	return out

## The F3 perf HUD. A CanvasLayer, so it hangs off the console's host and rides with it.
static func _cmd_perf(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := Common._tree(ctx)
	if tree == null or tree.current_scene == null:
		return Common._one("no scene to find or mount the perf overlay in")
	# ⭐Find the SHIPPED overlay first, by SCRIPT and anywhere under the scene — scenes/game.tscn carries one named
	# "DebugOverlay". A name-keyed find-or-create under the console host used to grow a SECOND overlay (two panels,
	# two ErrorSinks counting independently) the moment `perf` was typed. Only when none exists at all is one
	# created, at the scene root so it survives level swaps.
	var ov := Common._find_by_script(tree.current_scene, DebugOverlayScript)
	if ov == null:
		ov = Common._find_or_create(tree.current_scene, &"DebugOverlay", DebugOverlayScript)
	if ov == null:
		return Common._one("could not find or create a DebugOverlay")
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], bool(ov.get(&"visible"))))
	ov.set(&"visible", on)
	var out := PackedStringArray()
	out.append("perf %s (its own F3 key still works)" % ("ON" if on else "OFF"))
	return out

## wireframe / overdraw / unshaded are ONE Viewport.debug_draw enum, not three independent switches — so they are
## treated as one state: turning one on turns the others off, and "off" returns to DEBUG_DRAW_DISABLED. The
## viewport's own field is the source of truth (no shadow state to drift).
static func _cmd_debug_draw(cmd: String, ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var tree := Common._tree(ctx)
	if tree == null or tree.root == null:
		return Common._one("no viewport")
	var vp := tree.root as Viewport
	var want := Viewport.DEBUG_DRAW_DISABLED
	match cmd:
		"wireframe": want = Viewport.DEBUG_DRAW_WIREFRAME
		"overdraw": want = Viewport.DEBUG_DRAW_OVERDRAW
		"unshaded": want = Viewport.DEBUG_DRAW_UNSHADED
	var previous := vp.debug_draw
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], previous == want))
	var out := PackedStringArray()
	if on:
		if cmd == "wireframe" and not Common._wireframes_armed:
			# WIREFRAME renders NOTHING until the server has been told to generate wireframe index buffers, and
			# nothing else in the project ever calls this. One-shot: it is a process-wide arm, not a mode.
			RenderingServer.set_debug_generate_wireframes(true)
			Common._wireframes_armed = true
			out.append("armed RenderingServer.set_debug_generate_wireframes(true) — required once, or wireframe draws nothing.")
		vp.debug_draw = want
		if previous != Viewport.DEBUG_DRAW_DISABLED and previous != want:
			out.append("(%s replaced the previous debug draw mode — these three share one enum)" % cmd)
		out.append("%s ON" % cmd)
	else:
		vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
		out.append("%s OFF — debug draw back to DISABLED" % cmd)
	return out

## 16777216 -> "16,777,216". Thousands separators by hand: %d has none, and a raw nine-digit run in a console
## line is unreadable at a glance, which is the whole point of printing the count next to the depth.
static func _grouped(n: int) -> String:
	var digits := str(maxi(n, 0))
	var out := ""
	var seen := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		seen += 1
		if seen % 3 == 0 and i > 0:
			out = "," + out
	return out

## "2026-08-18 14:03:07" (Time.get_datetime_string_from_system(false, true)) -> "2026-08-18_14-03-07": a filename
## with no spaces or colons (Windows refuses a colon; a space is merely annoying in a shell). Also swallows the "T"
## of the ISO form, so either datetime flavour maps to the same shape. Pure.
static func screenshot_stamp(datetime: String) -> String:
	return datetime.replace(" ", "_").replace("T", "_").replace(":", "-")

## Same-second collisions are real (two `screenshot`s in one exec file, or a bind held down): the serial bumps while
## the stamp repeats within this process, and file_exists() covers a previous session's leftovers.
static var _last_shot_stamp := ""

static var _last_shot_serial := 0

static func _next_screenshot_path() -> String:
	var stamp := screenshot_stamp(Time.get_datetime_string_from_system(false, true))
	if stamp != _last_shot_stamp:
		_last_shot_stamp = stamp
		_last_shot_serial = 0
	var base := Common.SCREENSHOT_DIR.path_join(stamp)
	while true:
		_last_shot_serial += 1
		var candidate := (base + ".png") if _last_shot_serial == 1 else ("%s_%d.png" % [base, _last_shot_serial])
		if not FileAccess.file_exists(candidate):
			return candidate
	return base + ".png"  # unreachable — the loop returns the first free name

## Every visible-toggleable debug READOUT a clean frame must lose: the Groups.DEBUG_SURFACE CanvasLayers (console,
## menu), every CanvasLayer anywhere in the tree whose script is one of CLEAN_HIDDEN_SCRIPT_PATHS (F3 overlay, ailog
## panel, events column — wherever a designer parented them), and the F4 inspector's AiDebugDraw renderer (a Node3D
## drawing labels in the world; present only while `inspect` is on, read duck-typed off the inspector's private
## `_renderer`). Deduped by instance. The driver only ever touches the members that are VISIBLE when it runs.
static func _clean_hidables(tree: SceneTree) -> Array[Node]:
	var out: Array[Node] = []
	var seen := {}
	for s in tree.get_nodes_in_group(GroupsScript.DEBUG_SURFACE):
		if is_instance_valid(s) and s is CanvasLayer and not seen.has(s.get_instance_id()):
			seen[s.get_instance_id()] = true
			out.append(s)
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if not is_instance_valid(n):
			continue
		var scr := n.get_script() as Script
		var scr_path := String(scr.resource_path) if scr != null else ""
		if scr_path != "":
			if n is CanvasLayer and Common.CLEAN_HIDDEN_SCRIPT_PATHS.has(scr_path) and not seen.has(n.get_instance_id()):
				seen[n.get_instance_id()] = true
				out.append(n)
			elif scr_path == Common.INSPECTOR_SCRIPT_PATH:
				var renderer: Variant = n.get(&"_renderer")
				if renderer != null and is_instance_valid(renderer) and renderer is Node3D and not seen.has(renderer.get_instance_id()):
					seen[renderer.get_instance_id()] = true
					out.append(renderer)
		for child in n.get_children():
			stack.push_back(child)
	return out

## Report lines from a root-parented helper. The console (a Groups.DEBUG_SURFACE member with echo(), which appends
## whether or not its panel is up and mirrors to stdout) is the transcript; when no surface has echo() — the console
## was freed by a reload mid-capture, or the command came from a scene without one — plain print() is the fallback,
## so the result is never lost. Never push_warning: that would inflate the F3 ErrorSink tallies.
static func _echo_to_surfaces(tree: SceneTree, lines: PackedStringArray) -> void:
	var echoed := false
	if tree != null:
		for s in tree.get_nodes_in_group(GroupsScript.DEBUG_SURFACE):
			if is_instance_valid(s) and s.has_method(&"echo"):
				s.call(&"echo", lines)
				echoed = true
	if not echoed:
		for line in lines:
			print(line)

## `hud [on|off]` — hide / show the player HUD, restoring exactly what was hidden.
##
## THE HUD is scripts/ui/ui.gd's CanvasLayer under the Player (Player.tscn "UI"): every readout — the HP/ammo labels
## and bars, the hotbar, the crosshair (a direct child, ui.gd:187-198), the stamina ring / bar, the minimap + clock +
## objective tracker, the toast stack, the blood splatter, and every PlayerHud overlay (stealth badge, prompts, enemy
## health bar, hit flashes — all `ui.add_child`, player_hud.gd:69-236) — is a DIRECT CHILD of that layer. Nothing HUD-
## like lives elsewhere. Also on that layer is the post-process ColorRect (colour quantisation / dither / grain /
## night vision, ui.tscn) — that is the game's LOOK, not the HUD, and it must survive a "clean" frame.
##
## Two nodes the HUD ghost (scripts/ui/hud_ghost.gd) adds are the exception that proves the rule, and both fall out
## correctly with no wiring here: its `HudGhost` display TextureRect IS a direct CanvasItem child (seated just above
## the post-process ColorRect, so it is drawn as a HUD element rather than fed into that shader), so it
## is swept like any other readout and a "clean" frame has no ghost trails in it; its `HudGhostDriver` is a plain
## Node, so the `child is CanvasItem` filter skips it the same way that filter skips any nested CanvasLayer — which
## is what we want, because the driver only writes shader uniforms and its accumulator has nothing left to photograph
## once the HUD is hidden. The driver also honours the same bail latch (ui.gd hands it `_death_hidden_hud.is_empty()` each frame), so
## it cannot re-show the display out from under a sweep.
##
## MECHANISM: ui.hide_hud_for_death() + our own path snapshot, NOT a hand-rolled child sweep. The reason is the UI's
## per-frame drivers: _apply_stamina_mode (every frame from _update_stamina_readout), _apply_minimap_visibility (every
## frame from _process) and _apply_crosshair_visibility (every holster / dialogue change) each WRITE `visible` on the
## ring / bar / minimap / clock / crosshair — and each BAILS only while `ui._death_hidden_hud` is non-empty (ui.gd:
## 508-511, 566-570, 957-963). A snapshot that merely set `visible = false` would see those nodes resurrected on the
## very next frame; hide_hud_for_death() is the ONE sweep that also arms that bail latch, and it already spares the
## ColorRect. What we own on top is the SNAPSHOT: UI-relative node paths in ctx state (STATE_HUD_HIDDEN), because
## the UI's own list is not ours to trust — die() REPLACES it (a death while `hud off` is in force re-records only
## what was visible, i.e. nothing) and the revive CONSUMES it — so `hud on` restores from OUR paths, then releases
## the latch and re-derives the crosshair from the live holster / dialogue state (see _hud_show for why that is not
## restore_hud_after_death()).
##
## Whether the reuse is safe outside death: YES for the hide (the sweep + latch is exactly the contract we need, and
## the toast-swallowing / readout-clearing gates are on the PLAYER's `_dying` / `_hud_quiet` flags, not on the UI
## list — we never touch those). The restore half is NOT reused: restore_hud_after_death() also frees every live
## toast + the money float (_purge_transient_notices), a revive-only sweep a screenshot must not perform.
##
## Refused while the death cinematic owns the HUD (`_dying` / `_hud_quiet`): the sweep would clobber the cinematic's
## own list. Three known, documented leaks: (1) a conversation's close re-shows the HP bar / ammo / hotbar / toasts
## (_set_gameplay_hud_visible + _on_dialogue_finished write those directly, bypassing the latch); (2) the PLAYER's own
## per-frame HUD pushers — set_stealth_level / set_detection_meter every physics tick, the look-at name on a new
## target, the takedown / pet / claim cue facades, the enemy HP bar on a hit — re-show their labels past the latch,
## because they gate on Player `_dying` / `_hud_quiet` (never on the UI list), flags this command must not set (they
## also swallow toasts and damage juice). For both, a second `hud off` RE-SWEEPS (non-clobbering — _hud_hide) and
## merges; `screenshot clean` covers them with its own pre-draw pass. (3) A death while hidden finds nothing to sweep,
## so its latch never arms and the ring / minimap / clock / crosshair re-derive over the fade — cosmetic, `hud off`
## again after the revive.
##
## Released in release_scene_scoped_state: the UI is freed WITH the Player on a scene reload, so only the state key
## needs erasing (a fresh Player must never be "restored" from a stale snapshot). `warp` keeps the Player, and the
## hide with it — correct, and the same rule `notarget` follows.
static func _cmd_hud(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var player := Common._player(ctx)
	if player == null:
		return Common._one("hud: no player — the HUD is the Player's UI layer, and there is no player in the tree")
	var ui := _hud_layer(player)
	if ui == null:
		return Common._one("hud: the player's UI has no hide_hud_for_death() / restore_hud_after_death() seam — nothing this command can drive")
	if _hud_owned_by_death(player):
		return Common._one("hud: the death cinematic owns the HUD right now (Player._dying / _hud_quiet) — wait for the respawn")
	var state := Common._state(ctx)
	var hidden_now := state.has(Common.STATE_HUD_HIDDEN)
	var held := _hud_held_paths(state)
	# `hud on` = shown, so the toggle's "current" is "is the HUD up".
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], not hidden_now))
	var out := PackedStringArray()
	if on:
		if not hidden_now:
			return Common._one("hud is already ON (nothing hidden by `hud off`)")
		var shown := _hud_show(ui, held)
		state.erase(Common.STATE_HUD_HIDDEN)
		out.append("hud ON — restored %d of the %d HUD node(s) `hud off` hid%s" % [
			shown, held.size(), "" if shown == held.size() else " (the rest were freed meanwhile — expired toasts, a money float)"])
		out.append("  crosshair re-derived from the live holster / dialogue state, not the snapshot; toasts pushed while hidden survive.")
		return out

	var newly := _hud_hide(ui)
	var merged := held.duplicate()
	for p in newly:
		if not merged.has(p):
			merged.append(p)
	state[Common.STATE_HUD_HIDDEN] = merged
	if hidden_now:
		out.append("hud OFF — re-swept: hid %d node(s) that had come back (a conversation's close, or the Player's per-frame stealth / look-at / prompt / enemy-HP pushers, past the latch); %d held for `hud on`" % [newly.size(), merged.size()])
	else:
		out.append("hud OFF — hid %d direct child(ren) of %s: %s" % [newly.size(), String(ui.name), _hud_names(ui, newly)])
	out.append("  kept: the post-process ColorRect (colour steps / dither / grain — the LOOK, not the HUD). `hud on` restores exactly these.")
	out.append("  ! sneaking / a new look-at target / a prompt / a hit re-show their own label past the latch (Player-driven, gated on _dying, not on this) — `hud off` again re-sweeps; `screenshot clean` re-sweeps by itself.")
	out.append("  ! a death while hidden finds nothing to sweep, so the ring / minimap / clock / crosshair re-derive over the fade — `hud off` again after the revive.")
	return out

## Mirrors the CameraAttributesPractical authored in scenes/player/camera_rig.tscn, plus Godot's own defaults for
## the three fields that scene never writes. `dof reset` restores THIS rather than a snapshot taken at first touch:
## `ctx.state` is per-front-end, so a snapshot the MENU took after the CONSOLE had already dialled something would
## "restore" the console's value instead of the authored one. Same shape, and the same caveat, as
## SHADER_DEFAULT_BAYER_ORDER above: if camera_rig.tscn is re-authored this is cosmetic drift (a wrong `reset`
## target and a wrong report line), not a behaviour bug.
const DOF_AUTHORED := {
	# ABSENT from camera_rig.tscn -> engine default false. That is why the authored near_distance below has never
	# done anything: someone tuned a near blur and never wrote its switch (the same dead-knob shape as
	# `auto_exposure_max_sensitivity = 400.0` on the next line of that .tscn with `auto_exposure_enabled` absent).
	"near_enabled": false,
	"near_distance": 0.5,     # camera_rig.tscn -- authored, and dead until `dof near` flips the switch
	"near_transition": 1.0,   # absent -> engine default
	# The far half was RETIRED from camera_rig.tscn on 2026-08-24: its 30 m far blur was tuned when the main
	# level's volumetric fog had the far field ~78% covered, and the day the level dropped that fog the whole
	# distance rendered as naked mush ("things in the distance are WAY too blurry"). Both fields are now absent
	# from the .tscn -> engine defaults. ADS still gets far blur (set_scope_dof pushes it to
	# GameSettings.camera.dof_scoped_far_distance while scoped); only the RESTING state is blur-free.
	"far_enabled": false,     # absent -> engine default
	"far_distance": 10.0,     # absent -> engine default
	"far_transition": 5.0,    # absent -> engine default
	"amount": 0.1,            # absent -> engine default
}

## `dof [near|far|amount|off|on|reset] [value] [transition]` -- dial the camera's depth of field live.
##
## WHY THIS IS A LENS DIAL AND NOT A BLUR TOY. Defocus is the one depth cue the FOV slider cannot fake. In a
## pinhole projection an object's on-screen size is h / (2 d tan(fov/2)), so for ANY two objects the tan term
## cancels: FOV is a UNIFORM scale on the whole image and moves framing, never near-to-far separation. Blur is a
## function of distance, so it does separate them. THE NEAR HALF IS THE WHOLE EFFECT here: a windowed A/B
## (2026-08-20, when the rig still authored a 30 m far blur under volumetric fog) measured `near 1.0` at ~16%
## of frame change and `amount` alone at ~1.5%, because `amount` only strengthens blur that already exists and
## the far field was ~78% fog at that 30 m onset. Both far blur and the main level's fog are gone since
## 2026-08-24, which makes the near half MORE of the whole effect, not less.
## And it separates them where it is wanted: the weapon and the
## carry-hands render through ViewModelCamera's own Camera3D, built with NO CameraAttributes on purpose
## (scripts/camera/view_model_camera.gd:116-117), so everything here softens the WORLD while what is in your
## hands stays sharp.
##
## THE NEAR RAMP RUNS TOWARD THE LENS, which is the opposite of what the field names suggest. Godot's near blur
## is SHARP at dof_blur_near_distance and reaches FULL STRENGTH at (distance - transition), so a transition >= the
## distance puts full blur behind the camera and the effect never reaches full strength anywhere. camera_rig.tscn
## shipped in exactly that state (0.5 distance against the default 1.0 transition) on top of the missing switch --
## so `dof near <m>` auto-sizes the transition unless you give one, and always says where the ramp landed.
##
## THE FAR HALF IS SHARED WITH THE ADS. CameraEffects.set_scope_dof() rewrites dof_blur_far_enabled AND
## dof_blur_far_distance on every scope, and on unscope restores the PAIR it snapshotted in _ready()
## (`_dof_default_far_enabled` / `_dof_default_far_distance`). So every far-side verb here (`far <d>`, `far 0`,
## `off`, `on`, `reset`) writes that snapshot pair too (and `far <d>` REPORTS whether the write took) --
## otherwise the next ADS cycle would silently undo it and read as "the command did nothing". Unscope used to
## force the enabled flag TRUE unconditionally, which made `dof off` honest only until the next aim; since
## 2026-08-24 (far blur retired from camera_rig.tscn) the restore honours the snapshot, so far-side overrides
## hold. Nothing at runtime touches the NEAR fields, so a near override is stable without any snapshot.
##
## HOW LONG AN OVERRIDE LASTS -- longer than you expect, the same trap as `dither`. CameraAttributesPractical is
## a SUB-RESOURCE of the cached camera_rig.tscn PackedScene and is not resource_local_to_scene, so the camera a
## respawn or a level change builds carries the SAME attributes object, still holding whatever this wrote. An
## override therefore survives death, respawn and level transitions and only clears on a process restart or an
## explicit `dof reset`. No auto-restore on purpose: an A/B dial that snapped back on the next death is useless.
static func _cmd_dof(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var cam := _camera_effects(ctx)
	if cam == null:
		return Common._one("dof: no player camera -- depth of field lives on the CameraEffects Camera3D, and there is no player in the tree")
	var attrs := cam.attributes as CameraAttributesPractical
	if attrs == null:
		return Common._one("dof: the player camera carries no CameraAttributesPractical -- nothing to drive (camera_rig.tscn authors one; a scene edit must have dropped it)")

	var out := PackedStringArray()
	var verb := "" if args.is_empty() else args[0].strip_edges().to_lower()
	match verb:
		"amount":
			if args.size() < 2:
				out.append("dof amount needs a value 0-1. It scales the blur RADIUS at BOTH ends without moving where either one starts -- but it only makes EXISTING blur stronger, it cannot create any. Both ends ship OFF (the far half was retired 2026-08-24 with the main level's fog), so on the authored state this dial acts on nothing. Turn `dof near` or `dof far` on first; then it is worth something.")
			else:
				attrs.dof_blur_amount = clampf(float(args[1]), 0.0, 1.0)
				out.append("dof amount %.3f -- blur radius, both ends; the onset distances are untouched." % attrs.dof_blur_amount)
				if not attrs.dof_blur_near_enabled and not attrs.dof_blur_far_enabled:
					out.append("  ! BOTH ends are OFF (the shipped state), so this is scaling nothing at all. `dof near <m>` or `dof far <m>` first.")
				elif not attrs.dof_blur_near_enabled:
					out.append("  ! near blur is OFF, so this is only scaling the FAR blur. `dof near 1.0` for the depth cue.")
				if attrs.dof_blur_amount > 0.2:
					out.append("  ! past ~0.2 the near field crawls: project.godot ships use_taa=false, screen_space_aa=0 and msaa_3d=0, so nothing temporally stabilises a screen-space gather.")
		"near":
			if args.size() < 2:
				out.append("dof near needs a distance in metres, or 0 to switch it off. Sharp AT that distance, blurrier toward the lens.")
			else:
				var near_d := maxf(float(args[1]), 0.0)
				if near_d <= 0.0:
					attrs.dof_blur_near_enabled = false
					out.append("dof near OFF -- the world's near field is sharp again. Nothing at runtime rewrites the near fields, so this holds until you change it back or the process restarts.")
				else:
					var near_t := near_d * 0.75
					if args.size() >= 3:
						near_t = maxf(float(args[2]), 0.0)
					else:
						out.append("dof near: no transition given, so the ramp was auto-sized to %.2f m (0.75 x the distance) -- that is what makes it land in front of the lens instead of behind it." % near_t)
					attrs.dof_blur_near_enabled = true
					attrs.dof_blur_near_distance = near_d
					attrs.dof_blur_near_transition = near_t
					out.append("dof near ON -- sharp at %.2f m, ramping to full blur %.2f m from the lens." % [near_d, maxf(near_d - near_t, 0.0)])
					if near_t >= near_d:
						out.append("  ! transition >= distance, so full blur wants to land at %.2f m -- BEHIND the lens. The blur will never reach full strength anywhere in front of you. Pass a transition smaller than the distance." % (near_d - near_t))
		"far":
			if args.size() < 2:
				out.append("dof far needs a distance in metres, or 0 to switch it off. Sharp UNTIL that distance, full blur `transition` metres past it.")
			else:
				var far_d := maxf(float(args[1]), 0.0)
				if args.size() >= 3:
					attrs.dof_blur_far_transition = maxf(float(args[2]), 0.0)
				if far_d <= 0.0:
					attrs.dof_blur_far_enabled = false
					cam.set(&"_dof_default_far_enabled", false)
					out.append("dof far OFF -- and it HOLDS through aim cycles: unscope restores CameraEffects' snapshot pair, and this just wrote enabled=false into it. (That is also the shipped state since 2026-08-24.)")
				else:
					attrs.dof_blur_far_enabled = true
					attrs.dof_blur_far_distance = far_d
					cam.set(&"_dof_default_far_enabled", true)
					cam.set(&"_dof_default_far_distance", far_d)
					out.append("dof far ON -- sharp until %.2f m, full blur by %.2f m." % [far_d, far_d + attrs.dof_blur_far_transition])
					# Report whether the snapshot write actually took: set() on a property this camera does not
					# have is a silent no-op, and the symptom would be "it reverted after I aimed once".
					var snap: Variant = cam.get(&"_dof_default_far_distance")
					if snap is float and is_equal_approx(float(snap), far_d):
						out.append("  also wrote CameraEffects' _dof_default_far_enabled/_distance snapshot pair, so the next unscope restores THIS far blur instead of the authored state (far off).")
					else:
						out.append("  ! this camera has no _dof_default_far_distance to update, so the first unscope after an ADS will restore the authored state (far blur OFF) and undo the line above.")
		"off":
			attrs.dof_blur_near_enabled = false
			attrs.dof_blur_far_enabled = false
			cam.set(&"_dof_default_far_enabled", false)
			out.append("dof OFF at both ends -- the A/B kill switch, NOT a restore (`dof reset` puts the authored values back).")
			out.append("  holds through aim cycles: the far half's unscope-restore snapshot was set to off too. (Off IS the shipped state at both ends.)")
		"on":
			attrs.dof_blur_near_enabled = true
			attrs.dof_blur_far_enabled = true
			cam.set(&"_dof_default_far_enabled", true)
			out.append("dof ON at both ends, at the CURRENT distances -- not the authored ones (which ship both ends OFF). `dof reset` for those. The far half's unscope-restore snapshot was switched ON but keeps its own distance (the last `dof far <d>`, or the authored one), so an aim cycle lands the far blur THERE -- `dof far <d>` to pin a distance.")
		"reset":
			attrs.dof_blur_near_enabled = bool(DOF_AUTHORED["near_enabled"])
			attrs.dof_blur_near_distance = float(DOF_AUTHORED["near_distance"])
			attrs.dof_blur_near_transition = float(DOF_AUTHORED["near_transition"])
			attrs.dof_blur_far_enabled = bool(DOF_AUTHORED["far_enabled"])
			attrs.dof_blur_far_distance = float(DOF_AUTHORED["far_distance"])
			attrs.dof_blur_far_transition = float(DOF_AUTHORED["far_transition"])
			attrs.dof_blur_amount = float(DOF_AUTHORED["amount"])
			cam.set(&"_dof_default_far_enabled", bool(DOF_AUTHORED["far_enabled"]))
			cam.set(&"_dof_default_far_distance", float(DOF_AUTHORED["far_distance"]))
			out.append("dof reset -- camera_rig.tscn's authored state is back: BOTH ends off. The near half has been dead since the day it was typed (authored near_distance 0.5, switch never written); the far half was retired 2026-08-24 when the main level dropped the volumetric fog that had been hiding its 30 m blur.")

	out.append_array(_dof_report(ctx, attrs))
	return out

## The always-printed live block. The whole point of the command is A/B-ing a look, so every run ends by saying
## what the lens is actually doing -- including the two things that decide whether a change is even visible: what
## is EXEMPT from it (the view model) and whether the volumetric fog has already swallowed the far field.
static func _dof_report(ctx: Dictionary, attrs: CameraAttributesPractical) -> PackedStringArray:
	var out := PackedStringArray()
	var near_text := "off"
	if attrs.dof_blur_near_enabled:
		near_text = "on, sharp at %.2f m -> full %.2f m" % [
			attrs.dof_blur_near_distance, maxf(attrs.dof_blur_near_distance - attrs.dof_blur_near_transition, 0.0)]
	var far_text := "off"
	if attrs.dof_blur_far_enabled:
		far_text = "on, sharp to %.1f m -> full %.1f m" % [
			attrs.dof_blur_far_distance, attrs.dof_blur_far_distance + attrs.dof_blur_far_transition]
	out.append("live: amount %.3f | near %s | far %s" % [attrs.dof_blur_amount, near_text, far_text])
	out.append("  the view model is IMMUNE by construction -- the gun and the carry-hands render through ViewModelCamera's own Camera3D, built with no CameraAttributes on purpose. Only the WORLD softens, which is the whole near/far separation.")

	# Is there anything left out there to blur? On a level that runs volumetric fog (TestLevel does; the main
	# level dropped its 2026-08-24), the engine-default 0.05/m density has the far field most of the way to
	# opaque well before a far blur even starts -- which is the difference between "the far blur did nothing"
	# and "the far blur is not the problem". Self-gating: prints only when fog AND far blur are both live.
	var env := _lens_world_env(ctx)
	if env != null and env.volumetric_fog_enabled and attrs.dof_blur_far_enabled and attrs.dof_blur_far_distance > 0.0:
		var opacity := 1.0 - exp(-maxf(env.volumetric_fog_density, 0.0) * attrs.dof_blur_far_distance)
		out.append("  fog check: volumetric fog (density %.3f/m) is already %d%% opaque at the far onset (%.1f m) -- the more of that there is, the less a far blur can add, and the far field is ALSO softened by the PS1 snap fade (20-40 m) and the ink fade (40-90 m)." % [
			env.volumetric_fog_density, int(round(opacity * 100.0)), attrs.dof_blur_far_distance])
	out.append("  overrides survive death, respawn and level changes (shared sub-resource of the cached camera_rig.tscn) -- only a process restart or `dof reset` clears them. Commit what you like into scenes/player/camera_rig.tscn.")
	return out

## GunPose's @export names behind the short words this command takes. Kept as a table so `sway` and its report
## cannot drift on a spelling, and so a knob added here is one row rather than two match arms.
const SWAY_KNOBS := {
	"pos": &"mouse_sway_pos",
	"max": &"mouse_sway_max",
	"roll": &"mouse_sway_roll_deg",
	"pitch": &"mouse_sway_pitch_deg",
	"decay": &"mouse_sway_decay",
}

## Mirrors the @export defaults in scripts/effects/gun_pose.gd. GunPose is built with .new() by GunMesh, so it
## has NO .tscn override surface anywhere in the project -- these script defaults ARE the shipped values, and
## `sway reset` restores them. Cosmetic drift if gun_pose.gd is re-tuned, same as DOF_AUTHORED above.
const SWAY_AUTHORED := {"pos": 0.04, "max": 0.35, "roll": 0.0, "pitch": 0.0, "decay": 12.0}

## Three graded settings for A/B, indexed by `sway preset N`. Peak hip-fire lag is pos x max: 26 mm / 38 mm /
## 55 mm against the shipped 14 mm. Roll and pitch ship at literal 0.0, so every preset switches on two channels
## that have never run.
const SWAY_PRESETS: Array[Dictionary] = [
	{"pos": 0.065, "max": 0.40, "roll": 1.0, "pitch": 0.6, "decay": 10.0},
	{"pos": 0.085, "max": 0.45, "roll": 1.6, "pitch": 1.0, "decay": 9.0},
	{"pos": 0.110, "max": 0.50, "roll": 2.4, "pitch": 1.5, "decay": 8.0},
]

const SWAY_PRESET_NAMES: Array[String] = ["timid", "recommended", "loud"]

## `sway [pos|max|roll|pitch|decay|preset|off|reset] [value]` -- dial how far the view model lags behind a turn.
##
## WHY A GUN LAG IS A DEPTH CUE. Turning is by far the most frequent camera motion in the game, and a pure yaw
## carries ZERO parallax: every depth sweeps the screen at the same angular rate, so a turn tells the eye nothing
## about distance. The only near-to-far separation a turn can produce is a NEAR object that fails to keep up with
## it. GunPose already has the whole mechanism -- it accumulates MouseInput.rotate into `_mouse_sway`, clamps it to
## mouse_sway_max, decays it, and converts it into a gun offset -- but it ships at 0.04 x 0.35 = 14 mm of travel
## with the roll and pitch channels at literal 0.0. The feature is wired and switched almost off.
##
## THIS DOES NOT SURVIVE A DEATH, A RESPAWN OR A LEVEL CHANGE -- the exact opposite of `dof` on the same menu
## page, and worth knowing before you conclude a preset "stopped working". GunMesh builds a FRESH GunPose with
## GunPose.new() every time it is set up, so a new Player comes up on the script defaults. `dof` overrides ride a
## shared PackedScene sub-resource and outlive everything; these ride a node that gets rebuilt.
##
## MOUSE SWAY SITS OUTSIDE EVERY ACCESSIBILITY GATE. Settings.view_bob_enabled reaches only GunPose's walk-bob
## factor; the `_mouse_sway` decay and the four mouse_off / roll / pitch terms run unconditionally, and
## Settings.fov_effects_enabled never reaches GunPose at all. That is survivable at the shipped 14 mm. Committing
## a preset without adding the gate to gun_pose.gd first is a straight regression for motion-sensitive players,
## and rotation-linked view-model motion provokes more than translation-linked bob does.
##
## It moves the gun MODEL only: the shot ray is AimSway's, and the crosshair never moves. ADS damps the whole
## block by ads_sway_mult (0.35 as shipped), so the aimed peak stays near today's hip-fire number whatever you
## dial here -- the report prints both.
static func _cmd_sway(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var pose := _gun_pose(ctx)
	if pose == null:
		return Common._one("sway: no GunPose -- mouse sway lives on the pose node GunMesh builds under the player's view model, and there is no player (or no gun mesh) in the tree")

	var out := PackedStringArray()
	var verb := "" if args.is_empty() else args[0].strip_edges().to_lower()
	var knob: StringName = SWAY_KNOBS.get(verb, &"")
	if knob != &"":
		if args.size() < 2:
			out.append("sway %s needs a value -- live is %.3f, authored is %.3f." % [verb, Common._float_of(pose.get(knob)), float(SWAY_AUTHORED[verb])])
		else:
			var v := maxf(float(args[1]), 0.0)
			pose.set(knob, v)
			out.append("sway %s %.3f (authored %.3f)" % [verb, v, float(SWAY_AUTHORED[verb])])
	else:
		match verb:
			"preset":
				if args.size() < 2:
					out.append("sway preset needs an index: 0 %s, 1 %s, 2 %s." % SWAY_PRESET_NAMES)
				else:
					var idx := int(float(args[1]))
					if idx < 0 or idx >= SWAY_PRESETS.size():
						out.append("sway preset must be 0, 1 or 2 (%s) -- got \"%s\", nothing changed." % [", ".join(SWAY_PRESET_NAMES), args[1]])
					else:
						_sway_apply(pose, SWAY_PRESETS[idx])
						out.append("sway preset %d (%s) applied -- all five knobs at once, so the A/B is one command each way (`sway reset` for the shipped feel)." % [idx, SWAY_PRESET_NAMES[idx]])
			"off":
				_sway_apply(pose, {"pos": 0.0, "max": SWAY_AUTHORED["max"], "roll": 0.0, "pitch": 0.0, "decay": SWAY_AUTHORED["decay"]})
				out.append("sway OFF -- the gun is welded to the camera. The A/B floor: turn hard with this on, then `sway preset 1`, and the difference IS the depth cue.")
			"reset":
				_sway_apply(pose, SWAY_AUTHORED)
				out.append("sway reset -- gun_pose.gd's shipped defaults are back (roll and pitch to literal 0.0, which is how they ship).")

	out.append_array(_sway_report(pose))
	return out

## Write one knob table onto the live GunPose. Missing keys are left alone, so a partial table is a partial write
## rather than a silent zeroing.
static func _sway_apply(pose: Node, values: Dictionary) -> void:
	for word in SWAY_KNOBS:
		if values.has(word):
			pose.set(SWAY_KNOBS[word], float(values[word]))

## The always-printed live block, in the units that actually decide the feel: peak lag is pos x max (that product
## is the number to compare, not either factor), and the aimed peak is that times ads_sway_mult.
static func _sway_report(pose: Node) -> PackedStringArray:
	var pos := Common._float_of(pose.get(&"mouse_sway_pos"))
	var cap := Common._float_of(pose.get(&"mouse_sway_max"))
	var ads := Common._float_of(pose.get(&"ads_sway_mult"), 0.35)
	var peak := pos * cap
	var out := PackedStringArray()
	out.append("live: pos %.3f | max %.2f | roll %.2f deg | pitch %.2f deg | decay %.1f" % [
		pos, cap, Common._float_of(pose.get(&"mouse_sway_roll_deg")), Common._float_of(pose.get(&"mouse_sway_pitch_deg")),
		Common._float_of(pose.get(&"mouse_sway_decay"))])
	out.append("  peak lag %.1f mm hip-fire (pos x max) | %.1f mm aimed (x ads_sway_mult %.2f) | shipped is %.1f mm" % [
		peak * 1000.0, peak * ads * 1000.0, ads, float(SWAY_AUTHORED["pos"]) * float(SWAY_AUTHORED["max"]) * 1000.0])
	out.append("  ! gone on death / respawn / level change -- GunMesh rebuilds GunPose from the script defaults each time (unlike `dof`, which outlives all three).")
	out.append("  ! outside every accessibility gate: Settings.view_bob_enabled reaches only the walk-bob. Add the gate in gun_pose.gd before committing a raised value.")
	out.append("  gun MODEL only -- the shot ray is AimSway's and the crosshair never moves.")
	return out

## The player's main Camera3D (a CameraEffects), or null off-level / on the main menu. Typed as Camera3D rather
## than CameraEffects so a host that swapped the script still yields its `attributes`; the two CameraEffects
## privates this file pokes go through set()/get(), which degrade to a no-op and a null instead of a parse error.
static func _camera_effects(ctx: Dictionary) -> Camera3D:
	var player := Common._player(ctx)
	if player == null:
		return null
	var raw: Variant = player.get(&"camera_effects")
	if raw == null or not is_instance_valid(raw):
		return null
	return raw as Camera3D

## The live GunPose node GunMesh builds under the view model, or null when there is no player / no gun mesh.
## Reached duck-typed through a private member on purpose: `_pose` is GunMesh-internal and there is no public
## accessor, and a typed hop would turn a missing host into a parse-time dependency rather than a null here.
static func _gun_pose(ctx: Dictionary) -> Node:
	var player := Common._player(ctx)
	if player == null:
		return null
	var raw_mesh: Variant = player.get(&"gun_mesh")
	if raw_mesh == null or not is_instance_valid(raw_mesh):
		return null
	var mesh := raw_mesh as Node
	if mesh == null:
		return null
	var raw_pose: Variant = mesh.get(&"_pose")
	if raw_pose == null or not is_instance_valid(raw_pose):
		return null
	return raw_pose as Node

## The level's Environment, or null. Read only to REPORT how much fog is already sitting in front of the far
## blur -- this command never writes it (CameraEffects owns the scoped fog thin, and two writers would fight).
static func _lens_world_env(ctx: Dictionary) -> Environment:
	var tree := Common._tree(ctx)
	if tree == null:
		return null
	var we := tree.get_first_node_in_group(GroupsScript.WORLD_ENVIRONMENT) as WorldEnvironment
	if we == null:
		return null
	return we.environment

## Mirrors the @export defaults in resources/tuning/CameraSettings.gd ("Lens" group). `lens reset` restores THESE
## rather than a snapshot: `ctx.state` is per-front-end, so a snapshot the MENU took after the CONSOLE had already
## dialled something would restore the console's value. Cosmetic drift if CameraSettings.gd is re-tuned, the same
## caveat as DOF_AUTHORED and SHADER_DEFAULT_BAYER_ORDER above.
##
## ⭐ resources/tuning/CameraSettings.tres carries NO property overrides at all, so these .gd defaults really are
## the shipped values — there is no second place to look.
const LENS_AUTHORED := {"barrel": 0.12, "chroma": 0.35}

## `lens [barrel] [chroma]` — dial the world's barrel (fisheye) lens live.
##
## WHAT IT IS. post_process.gdshader bends the SCREEN FETCH radially: the centre of the frame is magnified and the
## periphery squeezed, so straight lines off the centre bow outward. That is the only way to get a fisheye here —
## a Camera3D cannot do it. FOV is a UNIFORM scale on the projected image (`h / (2 d tan(fov/2))`: for any two
## points the tan term cancels), so no field-of-view number bends a straight line; it just changes how much you
## can see. The bend has to happen after projection, which is why it lives in the post-process.
##
## ⭐ THE NUMBER IS CENTRE MAGNIFICATION MINUS ONE. The shader normalises the bend by the corner and divides by
## its own value there, so `0.12` reads as "the middle of the frame is ~12% bigger" and the CORNERS STAY PINNED.
## Pinning is not cosmetic: SCREEN_TEXTURE is `repeat_disable`, so a fetch running past the edge would smear the
## border texel down the whole side. It also means this can never produce a black edge, at any strength.
##
## ⭐ WRITES THE SOURCE, NOT THE MATERIAL — and that is the whole reason this function is not two lines.
## player.gd re-pushes `lens_barrel` onto the material EVERY FRAME (`_update_low_hp`, beside contrast / dither /
## quantize_levels), so a direct `set_shader_parameter` here would be overwritten on the very next frame and read
## as "the command did nothing" — the same coupling `_cmd_dither` documents for dither strength. So this writes
## `GameSettings.camera.lens_barrel_amount` / `lens_chroma_amount`, which is what player.gd multiplies.
##
## ⭐ WHICH MEANS THE PLAYER'S SLIDER CAN VETO IT. The pushed value is `amount x Settings.lens_curve`
## (Options -> Accessibility -> "Lens Curve"). At lens_curve 0 the frame is flat no matter what you type here, so
## the report always prints both numbers and the product, and says so outright when the scale is what is winning.
##
## ⭐ HOW LONG IT LASTS: the whole PROCESS, and no further. `GameSettings.camera` is a preloaded Resource shared
## by every scene, so an override survives death, respawn and level changes (the same lifetime as a `dof` override
## and the opposite of `sway`) — but nothing ever writes it to disk. To keep a value, put it in
## resources/tuning/CameraSettings.tres in the Inspector, or change the @export default in CameraSettings.gd.
static func _cmd_lens(_ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var cam_set: Variant = GameSettings.get(&"camera")
	if cam_set == null:
		return Common._one("lens: GameSettings has no `camera` group — nothing to drive (a reimport transient; try again in a second)")
	var out := PackedStringArray()
	if not args.is_empty():
		var barrel := maxf(float(args[0]), -0.25)
		(cam_set as Resource).set(&"lens_barrel_amount", barrel)
		if barrel <= 0.0:
			out.append("lens FLAT — the shader early-outs to a plain screen fetch, so the frame is pixel-identical to a build without the feature (and costs nothing).")
		else:
			out.append("lens barrel %.3f — the centre of the frame reads ~%.0f%% bigger, corners pinned." % [barrel, barrel * 100.0])
			if barrel > 0.35:
				out.append("  ! past ~0.35 the periphery smears rather than bends: the bend is squeezing more source pixels into fewer output ones, and SCREEN_TEXTURE is point-filtered.")
	if args.size() >= 2:
		var chroma := clampf(float(args[1]), 0.0, 1.0)
		(cam_set as Resource).set(&"lens_chroma_amount", chroma)
		out.append("lens chroma %.2f — the colour fringe, as a fraction of the bend, so it grows with the curve and vanishes with it. This is what makes a warp read as GLASS." % chroma)

	# Always report: this command writes the AUTHORED amount, the player's slider scales it, and only the product
	# reaches the GPU. Printing one of the three is how someone concludes the command is broken.
	var live_barrel := Common._float_of((cam_set as Resource).get(&"lens_barrel_amount"))
	var live_chroma := Common._float_of((cam_set as Resource).get(&"lens_chroma_amount"))
	var scale := Common._float_of(Settings.get(&"lens_curve"), 1.0)
	out.append("live: barrel %.3f x Lens Curve %.2f = %.3f reaching the shader | chroma %.2f | authored %.3f / %.2f" % [
		live_barrel, scale, live_barrel * scale, live_chroma,
		float(LENS_AUTHORED["barrel"]), float(LENS_AUTHORED["chroma"])])
	if live_barrel > 0.0 and scale <= 0.0:
		out.append("  ! Options -> Accessibility -> \"Lens Curve\" is at 0, so the frame is FLAT whatever you type here. That slider is the veto.")
	out.append("  the HUD does not bend with it: the post-process ColorRect and the HUD share one CanvasLayer, but the HUD draws ABOVE this shader. The crosshair sits at the centre, which is the one point a radial warp never moves.")
	out.append("  in-memory for the whole PROCESS — survives death, respawn and level changes (GameSettings.camera is a shared preloaded Resource) and is never written to disk. Commit a value in resources/tuning/CameraSettings.tres.")
	return out

## `dither [strength] [grid]` — tune the ordered (Bayer) dither the screen post-process quantises through, live.
##
## TWO KNOBS WITH TWO DIFFERENT HOMES, and mixing them up is the trap this comment exists for:
##  - STRENGTH is the PLAYER's dial (Options -> Video -> Dithering), so it is written through
##    `Settings.set_dither_strength` and NEVER onto the material. player.gd pushes `Settings.dither_strength` onto
##    this exact uniform EVERY FRAME (_update_low_hp), so a direct material write would be stomped on the next
##    frame and read as "the command did nothing". Writing Settings also persists it, like the Options slider.
##  - GRID is the MATERIAL's authored art choice (`bayer_order`, set in scenes/player/ui.tscn), which nothing
##    polls — so it goes straight onto the material. Deliberately NOT written to Settings: it is a palette
##    decision to eyeball here and then commit to the .tscn, not a player preference.
##
## ⭐ HOW LONG A GRID OVERRIDE LASTS, precisely — it is longer than you expect. The ShaderMaterial is a
## SUB-RESOURCE OF THE CACHED PackedScene, so the fresh player instantiated by a respawn or a level change gets
## the SAME material object, still carrying whatever this command wrote. (That is the documented shape of the old
## "respawned to a black screen" bug — see player.gd _restart_scene.) An override therefore survives death,
## respawn and level transitions, and only clears when the PROCESS restarts. There is no auto-restore on
## purpose: an A/B dial that silently snapped back on the next death would be useless. To hand the art back,
## re-run the command with the authored grid, which the report line below always prints.
##
## `grid` is typed as the matrix WIDTH (2 / 4 / 8 — what you see) and stored as the ORDER IN BITS (1 / 2 / 3 —
## what the shader loops over); 0 turns the matrix off at the material and leaves plain round-to-nearest banding.
static func _cmd_dither(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var mat := _post_process_material(ctx)
	if mat == null:
		return Common._one("dither: no post-process material — the Bayer dither lives on the player's UI/ColorRect, and there is no player (or no shaded ColorRect) in the tree")
	var out := PackedStringArray()
	if not args.is_empty():
		var strength := clampf(float(args[0]), 0.0, 1.0)
		Settings.set_dither_strength(strength)
		out.append("dither strength %.2f -> Settings (Options -> Video -> Dithering), saved; player.gd pushes it to the shader next frame." % strength)
	if args.size() >= 2:
		var grid := int(float(args[1]))
		# Typed target, never `:=` off a Dictionary read: Dictionary.get() is a Variant, so `:=` would infer
		# Variant and `as int` is not a cast GDScript offers for a built-in type.
		var order: int = GRID_TO_BAYER_ORDER.get(grid, -1)
		if order < 0:
			out.append("dither: grid must be 2, 4 or 8 (the matrix width), or 0 for off — got \"%s\", grid left unchanged." % args[1])
		elif order == 0:
			mat.set_shader_parameter("bayer_order", 0)
			out.append("dither grid OFF (bayer_order 0) — the frame now quantises by plain round-to-nearest, i.e. visible banding.")
		else:
			mat.set_shader_parameter("bayer_order", order)
			out.append("dither grid %dx%d (bayer_order %d) — on the material, and it OUTLIVES death / respawn / a level change (cached PackedScene sub-resource); only a process restart clears it. Commit it to scenes/player/ui.tscn to keep it for real." % [grid, grid, order])
	# Always report the resulting state: the whole point of the command is A/B-ing a look, and the two knobs live
	# in different places, so seeing them side by side is what stops the next person writing grid into Settings.
	# get_shader_parameter answers null for a uniform the MATERIAL never overrode (it does not fall through to the
	# shader's own default), so every read here degrades explicitly rather than printing "0" / "false" as if the
	# material had said so.
	var live_order := Common._int_of(mat.get_shader_parameter("bayer_order"), -1)
	var order_text := str(live_order)
	var shown_order := live_order
	if live_order < 0:
		shown_order = SHADER_DEFAULT_BAYER_ORDER
		order_text = "%d (shader default — the material carries no override)" % SHADER_DEFAULT_BAYER_ORDER
	var grid_text := "off"
	if shown_order > 0:
		grid_text = "%dx%d" % [1 << shown_order, 1 << shown_order]
	var enabled_raw: Variant = mat.get_shader_parameter("enable_dithering")
	var enabled := true if enabled_raw == null else bool(enabled_raw)
	out.append("live: strength %.2f | grid %s (bayer_order %s) | enable_dithering %s | color_steps %d" % [
		Settings.dither_strength, grid_text, order_text, str(enabled),
		Common._int_of(mat.get_shader_parameter("color_steps"), 0)])
	out.append("  the dither only has something to do where the palette BANDS — fewer colour steps = a louder pattern.")
	out.append("  authored grid is %dx%d (scenes/player/ui.tscn) — re-run `dither %.2f %d` to hand a grid override back." % [
		1 << SHADER_DEFAULT_BAYER_ORDER, 1 << SHADER_DEFAULT_BAYER_ORDER,
		Settings.dither_strength, 1 << SHADER_DEFAULT_BAYER_ORDER])
	return out

## Matrix WIDTH (what a human types) -> `bayer_order` (the bit count the shader loops over). 0 is a real entry: it
## is how the command turns the matrix off, and it must not collide with the "unknown grid" -1.
const GRID_TO_BAYER_ORDER := {0: 0, 2: 1, 4: 2, 8: 3}

## Mirrors `uniform int bayer_order ... = 3` in post_process.gdshader — used only to LABEL a material that carries
## no override of its own (get_shader_parameter answers null there, not the shader default). If the shader default
## ever changes, this line is cosmetic drift, not a behaviour bug.
const SHADER_DEFAULT_BAYER_ORDER := 3

## The ShaderMaterial on the player's post-process ColorRect (`UI/ColorRect` — the same node player.gd caches as
## `_nv_rect` and drives night vision / hurt / low-HP / the death fade through). Null off-level, on the main menu,
## or if the ColorRect ever loses its material. Kept separate from `_hud_layer` because this is explicitly the
## node `hud off` REFUSES to touch: it is the LOOK, not the HUD.
static func _post_process_material(ctx: Dictionary) -> ShaderMaterial:
	var player := Common._player(ctx)
	if player == null:
		return null
	var rect := player.get_node_or_null("UI/ColorRect") as CanvasItem
	if rect == null:
		return null
	return rect.material as ShaderMaterial

## The player's UI CanvasLayer, or null when there is none or it lacks the two-method seam this command rides on.
static func _hud_layer(player: Node) -> Node:
	if player == null or not is_instance_valid(player):
		return null
	var raw: Variant = player.get(&"ui")
	if raw == null or not is_instance_valid(raw):
		return null
	var ui := raw as Node
	if ui == null or not ui.has_method(&"hide_hud_for_death") or not ui.has_method(&"restore_hud_after_death"):
		return null
	return ui

## True while the death cinematic or the revive quiet window owns the HUD (player.gd:2455 `_dying`, :2479
## `_hud_quiet`) — the two windows in which the UI's death list belongs to the cinematic, not to us.
static func _hud_owned_by_death(player: Node) -> bool:
	return player != null and is_instance_valid(player) and (Common._bool_of(player.get(&"_dying")) or Common._bool_of(player.get(&"_hud_quiet")))

## The paths `hud off` is holding, as a fresh PackedStringArray (empty when none, or when the state was clobbered).
static func _hud_held_paths(state: Dictionary) -> PackedStringArray:
	var raw: Variant = state.get(Common.STATE_HUD_HIDDEN)
	if raw is PackedStringArray:
		return (raw as PackedStringArray).duplicate()
	return PackedStringArray()

## Run the UI's own death sweep (hides every VISIBLE direct CanvasItem child except the post-process ColorRect and
## arms the per-frame bail latch — see _cmd_hud) and read back WHAT it hid as UI-relative node paths. The list is
## the UI's private `_death_hidden_hud` (Array[CanvasItem]), read duck-typed; if it cannot be read the sweep still
## happened and the caller's snapshot is simply empty — _hud_show then falls back to the public restore.
##
## ⭐ONLY when the latch is NOT already armed. hide_hud_for_death() `.clear()`s the list FIRST and re-records just what
## is visible NOW — so a second call while a hide is in force (a repeated `hud off`, two `screenshot clean`s in one
## exec tick) drops every earlier node off the UI's own list, and when nothing new is visible leaves it EMPTY: the
## latch RELEASED with the HUD still down, and the ring / minimap / clock / crosshair re-derive on the very next
## frame. An armed latch is therefore extended by the non-clobbering _hud_sweep_more instead.
static func _hud_hide(ui: Node) -> PackedStringArray:
	var raw: Variant = ui.get(&"_death_hidden_hud")
	if raw is Array and not (raw as Array).is_empty():
		return _hud_sweep_more(ui)
	ui.call(&"hide_hud_for_death")
	var out := PackedStringArray()
	raw = ui.get(&"_death_hidden_hud")
	if raw is Array:
		for ci in (raw as Array):
			if ci != null and is_instance_valid(ci) and ci is Node:
				out.append(String(ui.get_path_to(ci)))
	return out

## The NON-CLOBBERING sweep: hide every VISIBLE direct CanvasItem child except the post-process ColorRect — the same
## rule as ui.hide_hud_for_death() (ui.gd:649-657), mirrored rather than called because that call `.clear()`s the
## death list first (see _hud_hide) — and APPEND each to the UI's list so the bail latch stays armed and grows.
## Used wherever a hide is already in force: the `hud off` re-sweep, and the screenshot driver's second pass (the
## Player's per-frame HUD pushers — set_stealth_level / set_detection_meter every physics tick, the look-at name,
## the takedown / pet / claim cues, the enemy HP bar — write `visible` on direct children of this layer PAST the
## latch, because they gate on the PLAYER's `_dying` / `_hud_quiet`, which nothing here may set). Returns the
## UI-relative paths of what it hid. If the private list cannot be read the nodes are still hidden (the caller's
## path snapshot restores them) — only the latch is not extended.
static func _hud_sweep_more(ui: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var keep := ui.get_node_or_null(^"ColorRect")
	# The UI's OWN list when readable (Arrays are references — appending here extends the latch); a throwaway
	# otherwise, so the loop below needs no second branch.
	var latch: Array = []
	var raw: Variant = ui.get(&"_death_hidden_hud")
	if raw is Array:
		latch = raw
	for child in ui.get_children():
		if child == keep or not (child is CanvasItem):
			continue
		var ci := child as CanvasItem
		if not ci.visible:
			continue
		ci.visible = false
		if not latch.has(ci):
			latch.append(ci)
		out.append(String(ui.get_path_to(ci)))
	return out

## Show every path in `paths` that still resolves (freed toasts / floats are skipped), then hand the HUD back to its
## per-frame drivers: empty the bail latch and re-derive the crosshair from the live holster / dialogue latches
## (they kept updating while the apply bailed, ui.gd:1012 — a weapon holstered under the hide must come back with
## NO crosshair, so the snapshot's `visible` is deliberately not the last word for it). Returns how many resolved.
##
## This is restore_hud_after_death() MINUS its _purge_transient_notices(): that purge frees every live toast + the
## money float, which is right for a revive and wrong for a `hud on` or a one-frame screenshot. So the latch is
## cleared directly (duck-typed, same private list _hud_hide reads) and the UI's own re-derive is called; anything
## still in the UI's list (a death mid-hide can leave a subset there) is shown too so no swept node stays dark
## whichever list it landed in. Only when the private list is unreadable does this fall back to the public
## restore_hud_after_death() — the latch MUST be released, or the ring / minimap / clock stay hidden for good.
static func _hud_show(ui: Node, paths: PackedStringArray) -> int:
	var shown := 0
	for p in paths:
		var n := ui.get_node_or_null(NodePath(p))
		if n != null and n is CanvasItem:
			(n as CanvasItem).visible = true
			shown += 1
	var raw: Variant = ui.get(&"_death_hidden_hud")
	if raw is Array:
		var latch: Array = raw
		for ci in latch:
			if ci != null and is_instance_valid(ci) and ci is CanvasItem:
				(ci as CanvasItem).visible = true
		latch.clear()
		if ui.has_method(&"_apply_crosshair_visibility"):
			ui.call(&"_apply_crosshair_visibility")
	else:
		ui.call(&"restore_hud_after_death")
	return shown

## The mid-capture-death hand-off (see _ShotDriver._restore): append our still-hidden nodes to the UI's death list
## so the revive's restore_hud_after_death() shows them. Duck-typed on the same private list; a no-op if unreadable
## (then the nodes come back on the next `hud off` / `hud on` round trip or the reload).
static func _hud_adopt_into_death_sweep(ui: Node, paths: PackedStringArray) -> void:
	var raw: Variant = ui.get(&"_death_hidden_hud")
	if not (raw is Array):
		return
	var latch: Array = raw
	for p in paths:
		var n := ui.get_node_or_null(NodePath(p))
		if n != null and n is CanvasItem and not latch.has(n):
			latch.append(n)

## "HP, AMMO, BloodSplatter, ColorRect, Label, ... +N more" — the swept nodes by name, or by CLASS for the code-built
## ones (their auto names, "@Label@42", say nothing). Capped so a 30-node sweep is one readable line.
const HUD_NAMES_MAX := 12

static func _hud_names(ui: Node, paths: PackedStringArray) -> String:
	var bits := PackedStringArray()
	for p in paths:
		if bits.size() >= HUD_NAMES_MAX:
			bits.append("+%d more" % (paths.size() - HUD_NAMES_MAX))
			break
		var n := ui.get_node_or_null(NodePath(p))
		if n == null:
			continue
		var label := String(n.name)
		if label.begins_with("@"):
			label = n.get_class()
		bits.append(label)
	return ", ".join(bits) if not bits.is_empty() else "(nothing was visible)"
