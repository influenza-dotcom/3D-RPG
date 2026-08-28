extends RefCounted

## @system Rendering
## @seam THE PRESENTATION DIALS OF post_process.gdshader, in ONE place. Every screen that wears the retro
## overlay — the in-game one on the Player's ColorRect (scripts/player/player.gd) and the boot screen's own
## copy in scenes/computerroom.tscn — pushes the same six uniforms from the same player Settings through
## `apply_dials()`. Anything that is about the PLAYER's state rather than the presentation (low_hp, hurt,
## night vision, the death fades, the lens bend) stays with its owner; this file is only the part that must
## look identical everywhere.
## @risk THE BOOT SCREEN IS NOT DRIVEN BY THE PLAYER. It is a standalone scene with no Player node, so before
## this existed it never received ANY of these — the player's Dithering and Colour Depth rows did nothing on
## the first thing they see, and it quantised at its own authored `color_steps` forever. A new host that
## draws this shader must call apply_dials() every frame or it silently inherits that bug.
## @test res://tests/test_retro_post.gd
##
## STATICS ONLY — no nodes, no tree access. Godot has no shared-material story here (each screen authors its
## own ShaderMaterial so an artist can restyle one without the other), so "one material" was never an option;
## one FUNCTION is.

## Horizontal cells the retro downscale quantises to, in RETRO presentation. 1584 = 2x the 792 px logical
## buffer: at or above the buffer width the resample is an identity (no dropped columns) AND the shader's
## Bayer cell collapses to the true 1:1 buffer pixel it was designed for. A count just ABOVE the buffer
## instead — 960, say — is the ~1.21:1 comb the shader's own render_scale note warns about, which crawls on
## fences and railings. Shared so the two hosts cannot disagree about the number that defines the look.
const PIXELATION_CELLS := 1584.0


## Push the player's presentation choices onto `mat`. Safe to call every frame (that is how both hosts use
## it) and safe on a null / shader-less material, so a host need not guard.
##
## POLLED rather than pushed on change, deliberately, and for the reason player.gd's own comment gives: the
## in-game ColorRect is REBUILT with the player on every respawn and level load, so a push-on-change would
## have to go and find the new material afterwards. One uniform write per frame can never go stale.
static func apply_dials(mat: ShaderMaterial) -> void:
	if mat == null or mat.shader == null:
		return
	# The ordered dither's STRENGTH is the player's; its matrix SIZE (`bayer_order`) stays authored on the
	# material, because which grid suits a screen is an art choice and not a preference.
	mat.set_shader_parameter("dither_strength", Settings.dither_strength)
	# Colour Depth as the per-channel STEP COUNT the shader wants, never the menu index — the mapping from
	# "15-bit (PS1)" to vec3(31,31,31) lives in Settings.color_quantize_levels alone, and Vector3.ZERO is the
	# sentinel for "leave this material at its authored color_steps" (what the default option pushes).
	mat.set_shader_parameter("quantize_levels", Settings.color_quantize_levels(Settings.color_quantization))
	mat.set_shader_parameter("colorblind_mode", Settings.colorblind_mode)
	mat.set_shader_parameter("contrast", Settings.contrast)
	# THE PRESENTATION SPLIT. In RETRO the logical canvas IS the render target, so one dither cell is one
	# buffer pixel and the authored cell count is pushed verbatim. In HIGH FIDELITY the buffer is NATIVE, so
	# the cell is scaled to keep its ~1-canvas-px size instead of shrinking to a native pixel of fine noise,
	# and the downscale is lifted to 2x the native width to stay clear of the comb zone.
	mat.set_shader_parameter("pixel_scale", maxf(1.0, roundf(Settings.native_scale())))
	mat.set_shader_parameter("render_scale", cells_for_presentation())


## The downscale cell count for the CURRENT presentation. maxf against the live render width rather than
## PIXELATION_CELLS * native_scale(): an ultrawide's logical canvas is WIDER than 792 (aspect expand), so the
## scalar product can land above the buffer width yet below the safe ~2x zone — still a comb.
static func cells_for_presentation() -> float:
	if Settings.native_scale() > 1.0:
		return maxf(PIXELATION_CELLS, 2.0 * float(Settings.render_size().x))
	return PIXELATION_CELLS
