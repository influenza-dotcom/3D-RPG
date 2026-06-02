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

    // --- 5. Film grain, layered on top of the retro image ---
    float noise = (fract(sin(dot(SCREEN_UV * (1.0 / grain_size) + TIME, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;
    final_color += noise * grain_amount;

    COLOR = vec4(clamp(final_color, 0.0, 1.0), 1.0);
}
