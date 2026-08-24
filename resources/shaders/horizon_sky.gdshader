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
		float w = smoothstep(0.0, edge_fade, v) * (1.0 - smoothstep(1.0 - edge_fade, 1.0, v));
		col = mix(col, img, w);
	}

	// Warm amber LIGHT-POLLUTION haze hugging the horizon + a hazy sun toward sun_azimuth (no stars: the glow drowns them).
	float band = exp(-abs(h) / haze_height) * haze_strength;
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
