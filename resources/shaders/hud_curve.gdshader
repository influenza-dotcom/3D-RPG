shader_type canvas_item;
render_mode blend_premul_alpha;

// Curved-glass HUD: resample the corner instrument panel through a cylindrical warp, so the panel wraps
// TOWARD the viewer at its edges -- the inside of a curved monitor, not the outside of a CRT bulge. The
// difference is one sign, and it is the whole read of the effect; see `curve`. Mounted on a full-rect ColorRect on the player's UI
// CanvasLayer (ui.gd `_curve_rect`), sampling the SubViewport that ui.gd's `_weighted` carrier renders
// into. The crosshair, the stamina ring, the combat arcs and every screen-projected annotation stay
// OUTSIDE this pass and dead flat -- they annotate the aim point or a world bearing, and a warped one
// would lie. That split is ui.gd's existing moved-vs-pinned rule, reused verbatim.
//
// (*) render_mode blend_premul_alpha IS LOAD-BEARING. A Viewport render target stores PREMULTIPLIED alpha
// -- measured on 4.7.1: a red texel written at alpha 0.5 reads back (0.498, 0.0, 0.0, 0.498), not
// (1.0, 0.0, 0.0, 0.5). Compositing that under the DEFAULT mix blend multiplies by alpha a second time,
// darkening every partially-transparent HUD pixel by ~25% while leaving opaque ones untouched. The
// symptom is dark halos around outlined glyphs and every fade tween going muddy -- not a uniformly dim
// HUD, which is why it is easy to look straight at and not see.
//
// (*) The warp still reads outside 0..1 near the edge midpoints, so `hud_tex` carries repeat_disable AND
// the fragment early-outs to transparent rather than trusting clamp-to-edge: a clamped edge texel smears
// any readout touching the border into a streak down the bezel. filter_nearest keeps the panel crunchy under
// the canvas's ~2.4x nearest upscale -- a linear tap here is the one change that would soften the whole
// HUD, and the uniform hint beats the node's texture_filter either way.

uniform sampler2D hud_tex : repeat_disable, filter_nearest;
// Per-axis bend. `.x` bends the X coordinate (so VERTICAL lines bow), `.y` bends Y (so HORIZONTAL lines
// bow) -- see warp() for the cross-coupling that makes that true.
//
// SIGN IS THE SHAPE, and it is the whole difference between the two screens people mean by "curved":
//   POSITIVE = CONCAVE, the inside of the cylinder -- a curved MONITOR wrapping toward you at the edges.
//     Horizontal lines bow UP in the middle and the edge midpoints tuck in; the corners stay put.
//   NEGATIVE = CONVEX, the outside of the bulge -- an old CRT face. The mirror image, and the thing you
//     get for free if you ever "simplify" the minus sign in warp() away.
// Magnitude is the fraction of the half-extent the edge midpoint travels: 0.06 moves the bottom-centre
// content ~13 px up on the 792x444 canvas.
//
// Driven live from code by ui.gd (_apply_hud_curve) out of GameSettings.hud.hud_curve_*, scaled by the
// Options -> Accessibility "HUD Curve" slider -- the ps1_warp_intensity idiom.
uniform vec2 curve = vec2(0.0, 0.0);
// Alpha falloff toward the bent edge: the panel dimming as it turns away from the light. Reaches full
// strength in the corners, half at the edge midpoints. 0 = an evenly lit panel.
uniform float edge_fade : hint_range(0.0, 1.0) = 0.0;
// Lens fringe, as a FRACTION OF THE WARP ITSELF (not an absolute offset) -- red reads a weaker bend and
// blue a stronger one, so the fringe grows with the curve instead of fighting it. APPROXIMATE by
// construction: the three taps carry different alphas and are recombined in premultiplied space, so this
// fringes anti-aliased glyph edges as well as colour. 0 = off, and off is the default.
uniform float chroma : hint_range(0.0, 1.0) = 0.0;

// Map a centred output point (`d`, -1..1 across the rect) onto the source UV it should read. `k` scales
// the whole bend so the chroma taps can walk it per channel.
//
// EACH AXIS IS BENT BY THE SQUARE OF THE OTHER -- x by y*y, y by x*x. That cross-coupling is what makes
// this read as a cylinder rather than a fisheye: with only `curve.y` live, a horizontal line bows while
// every vertical stays perfectly upright, which is exactly a monitor curved about a vertical axis. A
// radial dot(d, d) term instead would bend both at once and always look like a lens.
//
// (*) FITTED, and that is what makes the concave direction usable at all. A concave panel projects to a
// PINCUSHION -- edges bowing inward, corners flaring OUT past the original rectangle -- so drawn raw it
// would push the bottom-left HP bar clean off the canvas. Dividing by the bend at the extreme (|d| = 1 on
// the driving axis) pins the CORNERS to the corners: the panel bows inward from its edge midpoints and
// nothing ever leaves the screen, in either direction of the sign. The transparent slivers this leaves
// are at the EDGE MIDPOINTS, which is geometrically what the bowed edge of a curved screen looks like.
//
// The clamp only guards the divide: `curve` is authored well inside it, and 1.0 - c is the fit factor.
vec2 warp(vec2 d, float k) {
	vec2 c = clamp(curve * k, vec2(-0.9), vec2(0.5));
	vec2 bend = vec2(1.0 - c.x * d.y * d.y, 1.0 - c.y * d.x * d.x);
	return (d * bend / (vec2(1.0) - c)) * 0.5 + vec2(0.5);
}

void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	vec2 uv = warp(d, 1.0);
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		// Off the bowed panel entirely -- the slivers outside its bowed edges. Transparent, never a
		// clamped edge texel, which would smear an edge-touching readout down the border.
		COLOR = vec4(0.0);
	} else {
		vec4 c = texture(hud_tex, uv);
		if (chroma > 0.0) {
			// Green stays on the true sample, so the panel's own geometry and its coverage are the ones
			// the middle tap saw; red and blue only tint the edges of what green already placed.
			vec4 cr = texture(hud_tex, warp(d, 1.0 - chroma));
			vec4 cb = texture(hud_tex, warp(d, 1.0 + chroma));
			c = vec4(cr.r, c.g, cb.b, c.a);
		}
		// Premultiplied space: ONE multiply fades colour and coverage together, which is exactly right.
		COLOR = c * (1.0 - edge_fade * dot(d, d) * 0.5);
	}
}
