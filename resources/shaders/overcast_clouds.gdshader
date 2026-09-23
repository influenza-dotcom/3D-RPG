shader_type spatial;

// THE OVERCAST DECK — the lid over the drop (scripts/components/skyscraper_void.gd builds the disc it wears).
//
// A single horizontal disc high over the level, painted with procedural cloud cover and faded out toward its own
// rim so it melts into the sky instead of ending at an edge. Seen from underneath it reads as a solid overcast
// sky; seen from above (a tower that pokes through it, a very high fall) it reads as a cloud floor.
//
// ⭐ WHY A DECK AND NOT THE SKY SHADER. Clouds in `horizon_sky.gdshader` would be clouds in EVERY level in the
// game, and that shader is shared, load-bearing and already carries the day/night re-grade. A deck is opt-in per
// level, sits at a height the designer picks relative to the roof, and can be removed by unticking one box.
//
// ⭐ TRANSPARENT, UNLIKE EVERYTHING ELSE IN THIS COMPONENT. The facade and the towers dissolve with a dither
// precisely to STAY OUT of the transparent queue (they are one mesh of overlapping boxes that cannot sort against
// each other). The deck has no such problem — it is one flat disc, nothing overlaps it, and it is the last thing
// drawn — so it can use real alpha, which is what lets cloud edges be soft instead of stippled.
//
// ⭐⭐THE DRIFT IS SAFE BECAUSE THE NOISE IS EXACTLY PERIODIC, NOT BECAUSE IT IS SLOW. This project has been
// bitten by TIME-driven shader noise: TIME grows unbounded, its float precision decays, and a pattern that was
// stable at boot starts crawling or strobing hours into a session. The fix here is structural rather than a
// plea to keep the speed low:
//
//   • `hash12` wraps its cell coordinate at `NOISE_PERIOD`, so the base noise repeats exactly every that many
//     cells;
//   • every octave uses a lacunarity of EXACTLY 2.0 (with a constant offset per octave to stop the grids lining
//     up visibly), so octave n repeats every NOISE_PERIOD / 2^n cells — which means the WHOLE fbm repeats on
//     NOISE_PERIOD;
//   • the drift offset is taken `mod NOISE_PERIOD` in CELL space, so when it wraps it lands on an identical
//     pattern. The wrap is not "imperceptible", it is invisible: the sampled value is bit-for-bit the same.
//
// The wrapped offset also stays inside [0, NOISE_PERIOD), so no amount of uptime can rot the precision of what
// is actually fed to the noise. A non-integer lacunarity (the usual trick for hiding grid alignment) would break
// the periodicity and bring the whole problem back, which is why the octave offsets do that job instead.

render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled;

// ⭐ NEUTRAL GREY, NOT BLUE-GREY. Overcast is the one thing in this scene that should read as colourless; the
// blue-grey these started as just looked like more sky. (Equal channels are safe under the game's RGB444
// quantiser — the rule it breaks is green ABOVE red, and grey has none.)
uniform vec3 cloud_dark : source_color = vec3(0.047, 0.047, 0.050);   // ~sRGB (0.24,0.24,0.25) the underside
uniform vec3 cloud_light : source_color = vec3(0.133, 0.133, 0.141);  // ~sRGB (0.40,0.40,0.41) lit edges
uniform float coverage : hint_range(0.0, 1.0) = 0.78;    // 1 = solid lid, 0 = clear sky
uniform float softness : hint_range(0.01, 1.0) = 0.42;   // how gradually a cloud edge thins out
uniform float cloud_scale : hint_range(10.0, 8000.0) = 650.0;  // metres across one noise cell
uniform float opacity : hint_range(0.0, 1.0) = 0.95;
uniform float drift : hint_range(0.0, 40.0) = 24.0;      // metres per second the deck slides (see the header)
uniform vec2 drift_dir = vec2(1.0, 0.25);                // which way the weather is going (normalised in code)

// The rim fade: alpha falls to nothing over the outer part of the disc, so the deck has no visible edge and no
// silhouette against the sky — the same "never let it end where the player can see it end" rule the drop follows.
uniform float rim_fade_start : hint_range(0.0, 1.0) = 0.45;
uniform vec3 disc_centre = vec3(0.0);
uniform float disc_radius = 6000.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// The period the whole cloud field repeats on, in CELLS. A power of two so that every octave's period is also a
// whole number of cells (see the header): that is what makes the drift wrap invisible.
const float NOISE_PERIOD = 4096.0;

float hash12(vec2 p) {
	return fract(sin(dot(mod(p, NOISE_PERIOD), vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise with smooth interpolation — cheap, and at this scale (hundreds of metres per cell) nobody can tell
// it from gradient noise.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Four octaves is the least that stops overcast reading as lumps. ⭐ Lacunarity is EXACTLY 2.0 and each octave is
// nudged by a constant instead: the usual trick of using 2.03 to break grid alignment would also break the
// periodicity the drift depends on (see the header). A constant offset hides the alignment just as well and
// leaves the period intact, because shifting the input by NOISE_PERIOD still shifts every octave by a whole
// multiple of it.
float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amp;
		p = p * 2.0 + vec2(37.0, 17.0);
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec2 p = v_world.xz / max(cloud_scale, 1.0);
	if (drift > 0.0) {
		// Metres travelled -> CELLS travelled, wrapped at the noise's own period so the wrap lands on an
		// identical field and the coordinate fed to the noise can never grow (see the header).
		float travelled = mod(TIME * drift / max(cloud_scale, 1.0), NOISE_PERIOD);
		p += normalize(drift_dir + vec2(0.0001)) * travelled;
	}

	float n = fbm(p);
	// `coverage` slides the threshold: at 1.0 even the thinnest noise counts as cloud (a solid lid), at 0.0
	// nothing does. `softness` is how much of the noise range the edge is spread over.
	float edge = 1.0 - coverage;
	float cover = smoothstep(edge - softness * 0.5, edge + softness * 0.5, n);

	float radius = length(v_world.xz - disc_centre.xz);
	float rim = 1.0 - smoothstep(max(disc_radius, 1.0) * rim_fade_start, max(disc_radius, 1.0), radius);

	ALBEDO = mix(cloud_dark, cloud_light, clamp(n * 1.35, 0.0, 1.0));
	ALPHA = clamp(cover * rim * opacity, 0.0, 1.0);
}
