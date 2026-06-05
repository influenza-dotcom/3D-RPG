shader_type canvas_item;

// Use nearest filtering to keep the pixels sharp (no blur between blocks)
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_nearest;

// --- Retro post-process (downscale / posterize / dither) ---
uniform int color_steps = 32;
uniform bool enable_dithering = true;
// Now works with any positive float: 0.5 = double resolution, 1.0 = native, 2.0 = half res, etc.
uniform float render_scale = 320.0;

// --- Film grain (applied last, over the processed image) ---
uniform float grain_amount : hint_range(0.0, 1.0) = 0.05;
uniform float grain_size : hint_range(0.1, 10.0) = 1.0;

// --- Night vision (toggled/faded from code: 0 = off, 1 = full) ---
uniform float night_vision = 0.0;
uniform vec3 nv_tint : source_color = vec3(0.25, 1.0, 0.35);
uniform float nv_gain : hint_range(0.5, 4.0) = 1.8;
uniform float nv_gamma : hint_range(0.2, 1.0) = 0.55;

// --- Hurt flash (spiked from code on taking damage: 0 = none, 1 = full): drains colour toward a
//     darkened, red-tinted grayscale so a hit reads as the life being knocked out of you. ---
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform vec3 hurt_tint : source_color = vec3(0.7, 0.05, 0.06);

// --- Low HP (sustained, driven from code by HP fraction: 0 = healthy, 1 = near death): a black edge
//     vignette + colour drain so the world tunnels + greys as you bleed out. Distinct from the
//     transient red `hurt` flash above. ---
uniform float low_hp : hint_range(0.0, 1.0) = 0.0;

// --- Colorblind correction (daltonization): 0 none, 1 protanopia, 2 deuteranopia, 3 tritanopia. ---
uniform int colorblind_mode = 0;

// --- 4x4 Bayer Dither Matrix ---
float dither_pattern(ivec2 pixel_coord) {
    int x = pixel_coord.x % 4;
    int y = pixel_coord.y % 4;
    float[16] matrix = float[](
         0.0,  8.0,  2.0, 10.0,
        12.0,  4.0, 14.0,  6.0,
         3.0, 11.0,  1.0,  9.0,
        15.0,  7.0, 13.0,  5.0
    );
    return matrix[y * 4 + x] / 16.0;
}

// Daltonization: simulate the colour deficiency in LMS cone space, then shift the lost contrast into
// channels the viewer can still see. Explicit dot products (not mat3s) to avoid column/row-major bugs.
vec3 daltonize(vec3 rgb, int mode) {
    float L = dot(rgb, vec3(17.8824, 43.5161, 4.11935));
    float M = dot(rgb, vec3(3.45565, 27.1554, 3.86714));
    float S = dot(rgb, vec3(0.0299566, 0.184309, 1.46709));
    float l = L;
    float m = M;
    float s = S;
    if (mode == 1) {
        l = 2.02344 * M - 2.52581 * S;       // protanopia
    } else if (mode == 2) {
        m = 0.494207 * L + 1.24827 * S;      // deuteranopia
    } else {
        s = -0.395913 * L + 0.801109 * M;    // tritanopia
    }
    vec3 lms = vec3(l, m, s);
    vec3 sim = vec3(
        dot(lms, vec3(0.0809444479, -0.130504409, 0.116721066)),
        dot(lms, vec3(-0.0102485335, 0.0540193266, -0.113614708)),
        dot(lms, vec3(-0.000365296938, -0.00412161469, 0.693511405))
    );
    vec3 err = rgb - sim;
    vec3 shift = vec3(0.0, 0.7 * err.r + err.g, 0.7 * err.r + err.b);
    return clamp(rgb + shift, 0.0, 1.0);
}

void fragment() {
    // --- 1. Downscale using UV quantization (works for any render_scale) ---
    // Each output pixel picks the colour from a fixed grid cell.
    vec2 low_res_uv = floor(SCREEN_UV * render_scale) / render_scale;
    vec3 final_color = texture(SCREEN_TEXTURE, low_res_uv).rgb;

    // --- 2. Posterize ---
    float steps = float(color_steps);
    final_color = floor(final_color * steps + 0.5) / steps;

    // --- 3. Dither (optional) ---
    if (enable_dithering) {
        float d = dither_pattern(ivec2(FRAGCOORD.xy));
        final_color = floor((final_color + d / steps) * steps) / steps;
    }

    // --- 4. Night vision: lift the darks, amplify, and tint green. Toggled from code. ---
    if (night_vision > 0.0) {
        float nv_lum = dot(final_color, vec3(0.299, 0.587, 0.114));
        nv_lum = clamp(pow(nv_lum, nv_gamma) * nv_gain, 0.0, 1.0);
        final_color = mix(final_color, nv_lum * nv_tint, night_vision);
    }

    // --- 4b. Hurt: hard drain to a dark, red-tinted desaturation + a tunnel-vision vignette, so a
    //     hit reads as the wind being knocked out of you. Spiked + eased from code. ---
    if (hurt > 0.0) {
        float h_lum = dot(final_color, vec3(0.299, 0.587, 0.114));
        vec3 muted = mix(vec3(h_lum), h_lum * hurt_tint * 2.0, 0.5);
        float vig = 1.0 - smoothstep(0.25, 0.95, length(SCREEN_UV - 0.5) * 1.4) * hurt * 0.85;
        final_color = mix(final_color, muted * 0.55, hurt) * vig;
    }

    // --- 4c. Low HP: desaturate + a black vignette that closes in as health drops (sustained). ---
    if (low_hp > 0.0) {
        float lhp_lum = dot(final_color, vec3(0.299, 0.587, 0.114));
        final_color = mix(final_color, vec3(lhp_lum), low_hp * 0.8);
        float lhp_vig = 1.0 - smoothstep(0.12, 0.78, length(SCREEN_UV - 0.5) * 1.4) * low_hp;
        final_color *= lhp_vig;
    }

    // --- 4d. Colorblind correction (daltonization), applied to the finished image. ---
    if (colorblind_mode > 0) {
        final_color = daltonize(final_color, colorblind_mode);
    }

    // --- 5. Film grain, layered on top of the retro image ---
    float noise = (fract(sin(dot(SCREEN_UV * (1.0 / grain_size) + TIME, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;
    final_color += noise * grain_amount;

    COLOR = vec4(clamp(final_color, 0.0, 1.0), 1.0);
}
