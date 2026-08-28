shader_type sky;

// A grounded "Deus Ex" HORIZON sky. The level's authored skybox image (use_panorama) is mapped CYLINDRICALLY
// -- wrapped flat around the horizon as a band -- instead of the equirectangular SPHERE mapping that pinches a
// picture at the poles. A sky gradient sits above the band, ground below, and a warm amber LIGHT-POLLUTION
// haze hugs the horizon (no stars -- the city glow drowns them). `flash` floods the sky with `flash_color` for
// about a second on a kill -- both are driven by StarSky.flash_kill, never authored here (see below).

uniform sampler2D panorama : source_color, filter_linear;  // the level's authored skybox image (bound by StarSky)
uniform bool use_panorama = false;   // true -> lay the image flat along the horizon; false -> plain gradient
uniform float pano_yaw : hint_range(-3.1416, 3.1416) = 0.0;  // rotate the image horizontally
uniform float pano_tiles : hint_range(0.25, 8.0) = 1.0;      // times the image wraps the horizon (raise if a non-panoramic photo looks stretched)
uniform float band_bottom : hint_range(-0.8, 0.4) = -0.2;    // EYEDIR.y where the image's BOTTOM edge sits
uniform float band_top : hint_range(0.1, 1.2) = 0.6;         // EYEDIR.y where the image's TOP edge sits
uniform float edge_fade : hint_range(0.0, 0.4) = 0.1;        // soft blend of the image's top/bottom into sky/ground

uniform vec3 zenith_color : source_color = vec3(0.015, 0.025, 0.055);  // deep night sky straight up
uniform vec3 horizon_color : source_color = vec3(0.06, 0.11, 0.16);    // hazy blue at the horizon (behind/around the image)
uniform vec3 ground_color : source_color = vec3(0.015, 0.02, 0.03);    // below the image
uniform vec3 haze_color : source_color = vec3(0.85, 0.45, 0.18);       // warm amber light-pollution glow / hazy sun
uniform float gradient_power : hint_range(0.3, 3.0) = 0.85;
uniform float haze_height : hint_range(0.02, 0.6) = 0.16;
uniform float haze_strength : hint_range(0.0, 2.0) = 0.45;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.5;
uniform float sun_azimuth : hint_range(-3.1416, 3.1416) = 0.7;

// ---------------------------------------------------------------------------------------------------------
// DAY RE-GRADE OF THE HORIZON BAND. Driven by DayNightSky (`drive_sky`), which writes `day` in the same frame
// as zenith_color/horizon_color, so the band and the gradient above it move together.
//
// ⭐⭐WHY THIS EXISTS: the gradient is only HALF the sky. The authored skybox image laid along the horizon
// carries its OWN painted night sky, so lerping the gradient to day while the band stayed night drew a hard
// dark ARC across the top of the image at noon (probe-verified) — a bright blue sky with a black band bolted
// under it. The band has to become day too, or neither should.
//
// ⭐THE ARTWORK IS NOT REPAINTED, ONLY ITS PALETTE MOVES. The shipped skybox (assets/textures/hdi.png) is a
// 107-colour paletted image in which FIVE colours are 99.5% of every pixel: the navy sky, a mid-blue cloud
// highlight, black, the violet city silhouette and the red window lights. So "make it day" is a palette
// problem. Each sampled colour is pulled toward the day colour of whichever key it is nearest, weighted by
// INVERSE SQUARE distance, plus an identity term at `band_match_radius` so a colour far from every key keeps
// itself instead of averaging into mush. The weighting is CONTINUOUS on purpose: a filtered texel sitting
// between two palette colours lands between their two day colours, so silhouette edges stay clean. A
// nearest-colour `if` would speckle every edge, because bilinear filtering blends the palette.
//
// ⭐⭐THE MATCH RUNS IN PERCEPTUAL (sRGB) SPACE, NOT LINEAR. This skybox is very dark, and in linear its palette
// collapses toward zero (navy->black is 0.033 in linear vs 0.200 in sRGB) — distances stop discriminating and
// every weight goes mushy. The sampled texel is converted back to sRGB, matched there, and returned to linear.
// The `source_color` uniforms below arrive LINEAR and are converted to sRGB here to be matched.
//
// ⭐⭐THEIR DEFAULTS ARE THEREFORE WRITTEN IN LINEAR, WHICH IS NOT WHAT THEY LOOK LIKE. Godot sRGB-converts a
// Color a designer PICKS in the Inspector, but a vec3 literal declared in shader source is passed through RAW.
// Writing the pretty sRGB value here encodes it twice — the band came out pale and pink (probe-verified). The
// sRGB value each default actually represents is in the comment beside it; edit THAT, then convert.
//
// ⭐`day` defaults to 0.0 = THE AUTHORED NIGHT IMAGE, UNTOUCHED. A level with no DayNightSky (or with drive_sky
// off) never writes it, so this whole block is inert and the band renders exactly as it always has.
// DESIGNER: every colour below is a live knob — re-grade the day sky by dragging colour pickers.
uniform float day : hint_range(0.0, 1.0) = 0.0;
uniform float band_match_radius : hint_range(0.05, 1.0) = 0.42;
// ⭐THE AMBER LIGHT-POLLUTION HAZE IS A NIGHT PHENOMENON — it is the city's own glow bouncing off the air, and
// it is not there at midday. Left running at full strength it painted a sunset over the noon sky: the horizon
// band went orange and the skyline read pink, so the sky said "dusk" no matter how blue the zenith got. This
// scales the haze band toward `day`. 1.0 = never fades (the pre-existing behaviour); at day 0 it is inert
// either way, so an undriven level is untouched.
uniform float day_haze_scale : hint_range(0.0, 1.0) = 0.25;
uniform vec3 night_sky_tone : source_color = vec3(0.0000, 0.0000, 0.0331);  // sRGB (0, 0, 51)
uniform vec3 day_sky_tone : source_color = vec3(0.1170, 0.1812, 0.4020);  // sRGB (96, 118, 170)
uniform vec3 night_cloud_tone : source_color = vec3(0.0000, 0.0331, 0.1329);  // sRGB (0, 51, 102)
uniform vec3 day_cloud_tone : source_color = vec3(0.3325, 0.4508, 0.6939);  // sRGB (156, 179, 217)
uniform vec3 night_dark_tone : source_color = vec3(0.0000, 0.0000, 0.0000);  // sRGB (0, 0, 0)
uniform vec3 day_dark_tone : source_color = vec3(0.0612, 0.0723, 0.1384);  // sRGB (70, 76, 104)
// ⭐⭐BLACK IS TWO DIFFERENT THINGS AND NEEDS TWO DAY COLOURS. #000000 is 30% of the skybox and the single
// largest thing the player ever sees in the sky (measured 6-7% of the FRAME at every framing) — up high it is
// the CLOUD BANK, down low it is the line-work inside the skyline. One day colour cannot serve both: lift it
// enough to read as daylight cloud and the city's detail washes out; keep it dark and a black blot hangs in
// the noon sky. So the black key's target is chosen by HEIGHT in the band. The split is safe because it is
// measured: rows 0-100 of the image are 0.0% city and 0.0% window pixels, so above v = 0.28 there is no
// skyline detail to protect.
uniform vec3 day_cloud_bank_tone : source_color = vec3(0.3050, 0.3916, 0.5776);  // sRGB (150, 168, 200)
uniform vec3 night_city_tone : source_color = vec3(0.0331, 0.0103, 0.3185);  // sRGB (51, 26, 153)
uniform vec3 day_city_tone : source_color = vec3(0.3050, 0.2307, 0.5520);  // sRGB (150, 132, 196)
uniform vec3 night_window_tone : source_color = vec3(0.5457, 0.0030, 0.0030);  // sRGB (195, 10, 10)
uniform vec3 day_window_tone : source_color = vec3(0.6105, 0.0578, 0.0369);  // sRGB (205, 68, 54)

vec3 band_to_srgb(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(1e-5)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 band_to_linear(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// One key's contribution. `eps` keeps an exact hit finite while still letting it dominate every other term by
// ~4 orders of magnitude, so a key colour lands on its day colour exactly.
void band_key(vec3 c, vec3 key, vec3 target, inout vec3 acc, inout float wsum) {
	vec3 d = c - band_to_srgb(key);
	float w = 1.0 / (dot(d, d) + 1e-4);
	acc += w * band_to_srgb(target);
	wsum += w;
}

vec3 regrade_band(vec3 lit, float v) {
	vec3 c = band_to_srgb(lit);
	float wsum = 1.0 / (band_match_radius * band_match_radius + 1e-4);
	vec3 acc = c * wsum;
	band_key(c, night_sky_tone, day_sky_tone, acc, wsum);
	band_key(c, night_cloud_tone, day_cloud_tone, acc, wsum);
	band_key(c, night_dark_tone, mix(day_cloud_bank_tone, day_dark_tone, smoothstep(0.28, 0.55, v)), acc, wsum);
	band_key(c, night_city_tone, day_city_tone, acc, wsum);
	band_key(c, night_window_tone, day_window_tone, acc, wsum);
	return mix(lit, band_to_linear(acc / wsum), clamp(day, 0.0, 1.0));
}
// ---------------------------------------------------------------------------------------------------------
// TWO INDEPENDENT FLASH CHANNELS, both driven by StarSky (up / hold / down per channel), NEITHER authored here.
// Their live colours come from GameSettings.effects and are re-written on every trigger; the defaults below are
// only the fallback for a sky painted by something other than StarSky. Renaming any of these four uniforms
// silently reverts or disables a flash -- tests/test_effects.gd pins all four names for exactly that reason.
//
// They are SEPARATE uniforms rather than one shared pair on purpose: you get hit while killing constantly, and a
// single channel would mean each trigger killed the other's tween and repainted its colour mid-beat -- a kill's
// hot red would be cut to the darker hurt red by the next bullet, and vice versa.
uniform float flash : hint_range(0.0, 1.0) = 0.0;             // KILL: StarSky.flash_kill (hot red, ~1 s)
uniform vec3  flash_color : source_color = vec3(1.0, 0.1, 0.08);
uniform float hurt_flash : hint_range(0.0, 1.0) = 0.0;        // TOOK DAMAGE: StarSky.flash_hurt (red, shorter)
uniform vec3  hurt_flash_color : source_color = vec3(0.85, 0.0, 0.0);

void sky() {
	float h = EYEDIR.y;                                  // -1 (down) .. 1 (up), 0 = horizon
	float az = atan(EYEDIR.x, EYEDIR.z);
	float a = az / 6.28318530718 + 0.5;                  // azimuth wrapped 0..1

	// Base gradient (sky above the horizon, ground below) -- shows around / beyond the image.
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, zenith_color, pow(h, gradient_power));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 4.0, 0.0, 1.0));
	}

	// CYLINDRICAL band: U wraps around the horizon, V maps the image linearly across [band_bottom, band_top] --
	// a flat backdrop, no spherical pinch. Outside the band fades into the sky/ground gradient.
	if (use_panorama) {
		float u = fract(a * pano_tiles + pano_yaw / 6.28318530718);
		float v = (band_top - h) / max(band_top - band_bottom, 0.001);
		vec3 img = texture(panorama, vec2(u, clamp(v, 0.0, 1.0))).rgb;
		if (day > 0.0001) {
			img = regrade_band(img, clamp(v, 0.0, 1.0));
		}
		float w = smoothstep(0.0, edge_fade, v) * (1.0 - smoothstep(1.0 - edge_fade, 1.0, v));
		col = mix(col, img, w);
	}

	// Warm amber LIGHT-POLLUTION haze hugging the horizon + a hazy sun toward sun_azimuth (no stars: the glow drowns them).
	float band = exp(-abs(h) / haze_height) * haze_strength * mix(1.0, day_haze_scale, clamp(day, 0.0, 1.0));
	float sun = exp(-abs(h) / (haze_height * 1.4)) * pow(max(0.0, cos(az - sun_azimuth)), 3.0) * sun_glow;
	col += haze_color * (band + sun);

	col = mix(col, flash_color, clamp(flash, 0.0, 1.0));
	// HURT is applied AFTER the kill flash so that when both channels are up at once the DAMAGE read wins: being
	// shot is more urgent information than having scored.
	// NOTE: both cues ship RED now, which blunts that. At sky_flash_peak = 1.0 the kill flash REPLACES the sky, so
	// a hit landing mid-kill only pulls (1.0, 0.1, 0.08) toward (0.85, 0.0, 0.0) at 0.55 -- a ~20% brightness dip
	// with NO hue change, where the old purple kill flash swung the hue hard. Ordering still means the hurt wash is
	// not swallowed, but it no longer reads as a different colour. To get that separation back, drop sky_flash_peak
	// below 1.0 (so the hurt mix has a non-red base to pull from) or move one of the two colours off red.
	col = mix(col, hurt_flash_color, clamp(hurt_flash, 0.0, 1.0));
	COLOR = col;
}
