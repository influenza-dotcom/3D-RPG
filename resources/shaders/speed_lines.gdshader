shader_type canvas_item;

// White speed-vignette + radial air streaks for a fast-movement rush. `intensity` (0..1) is driven
// from the player's speed (the SAME value as the wind SFX), so the visual and audio ramp together.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, .09);   // stark white
uniform float reach : hint_range(0.0, 1.0) = 0.35;              // how far in from the edge the white bleeds
uniform float streak_count = 35.0;                              // number of radial air streaks
uniform float streak_speed = 5.5;                               // how fast streaks rush outward
uniform float streak_amount : hint_range(0.0, 2.0) = 0.7;       // streak brightness over the flat vignette

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

void fragment() {
	vec2 d = UV - 0.5;
	float dist = length(d) * 2.0;            // 0 centre, ~1 at edge mid-points, ~1.4 corners
	float ang = atan(d.y, d.x);

	// Edge vignette: transparent in the safe centre, ramps to solid at the very edge.
	float vig = smoothstep(1.0 - reach, 1.0, dist);

	// Radial streaks: each angular segment gets a random phase, flows outward over time, and is
	// brightest near the edges (masked by the vignette).
	float seg = floor((ang / 6.2831853 + 0.5) * streak_count);
	float phase = hash(seg);
	float flow = fract(phase * 9.0 + dist * 4.0 - TIME * streak_speed * (0.6 + phase));
	float streak = smoothstep(0.55, 1.0, flow) * vig;

	float a = (vig + streak * streak_amount) * intensity;
	COLOR = vec4(color.rgb, clamp(a, 0.0, 1.0) * color.a);
}
