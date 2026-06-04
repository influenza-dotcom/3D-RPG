shader_type spatial;
render_mode unshaded, depth_draw_never, cull_back, blend_add;

// NPC aim-laser beam. ADDITIVE (blend_add, set in render_mode so it's unambiguous — unlike a
// StandardMaterial3D blend_mode, which can still alpha-blend): the beam ADDS its colour to the scene
// scaled by `strength`, so lowering the strength fades it to INVISIBLE. It can NEVER darken toward
// black the way an alpha-blended beam does (which read as "becomes more black" while fading), and a
// neutral/black hue simply adds nothing instead of painting a black streak. ALPHA tracks strength so
// it also composites cleanly if it ever lands in an alpha-blended pass (e.g. a SubViewport).

uniform vec3 beam_color = vec3(1.0, 0.0, 0.0);
uniform float strength : hint_range(0.0, 8.0) = 0.0;

void fragment() {
	ALBEDO = beam_color * strength;
	ALPHA = clamp(strength, 0.0, 1.0);
}
