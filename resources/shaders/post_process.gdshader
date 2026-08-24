shader_type canvas_item;

// Use nearest filtering to keep the pixels sharp (no blur between blocks)
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, repeat_disable, filter_nearest;

// --- Retro post-process (downscale / posterize / dither) ---
uniform int color_steps = 32;
// AUTHORED master gate for the ordered dither (per-material, in the .tscn). The PLAYER's dial is
// `dither_strength` below — this stays true in both shipped materials and exists so a scene can opt a
// dither out entirely regardless of the player's setting.
uniform bool enable_dithering = true;
// Bayer matrix ORDER IN BITS, not its width: 0 = off, 1 = 2x2, 2 = 4x4, 3 = 8x8. A bigger matrix carries
// more threshold levels (N*N of them), so it reconstructs a gradient more finely at the same `color_steps`
// — 8x8 is the classic ordered-dither look, 2x2 is the crunchy one. Authored per material (an art choice,
// like `color_steps`), NOT a player setting: the player gets the strength dial instead.
uniform int bayer_order : hint_range(0, 3) = 3;
// 0 = no dither (a plain round-to-nearest posterize, i.e. hard banding), 1 = the full ordered dither.
// Driven live from code by Settings.dither_strength (Options -> Video -> Dithering), the contrast /
// colorblind_mode idiom — see player.gd _update_low_hp.
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;
// CELL COUNT across the screen's WIDTH — NOT a divisor. The fragment does
// floor(SCREEN_UV * render_scale) / render_scale, so this is "how many blocks wide is the image",
// and LOWER = chunkier. (An older comment here claimed 0.5/1.0/2.0 = double/native/half res; that
// divisor semantic was never what the code did, and believing it is how ui.tscn ended up at 960.)
//
// PITFALL — keep it either well BELOW or well ABOVE the real back-buffer width, never just above it.
// The back buffer is 792 px wide (project.godot: 396 viewport x stretch scale 0.5). A cell count
// slightly FINER than the buffer is not a downscale at all: it is a resample through a grid the
// source cannot feed, so floor() maps several output columns onto the same source column and skips
// others entirely. At 960-over-792 that silently dropped 168 of 792 source columns (21%) in a fixed
// 4-5 px comb, which chews on exactly the highest-frequency thing on screen — fence weave, railings,
// aerials, window mullions — and makes them crawl when you pan.
//   < 792  = a real chunky downscale (computerroom.tscn uses 320 for the CRT look — intended)
//   >= ~2x = effectively no downscale, quantization lands sub-pixel (ui.tscn uses 1584)
uniform float render_scale = 320.0;

// --- Colour quantization (Options -> Video -> Colour Depth; pushed live by player.gd, the contrast /
//     dither_strength idiom) ---
// Per-channel STEP COUNT the finished frame is snapped to. A channel lands on one of `steps + 1` values,
// so 31 is the PlayStation's own 5-bit-per-channel RGB555 framebuffer (32 levels) and 255 is 8-bit, i.e.
// what the buffer already holds — off. A vec3 rather than a second scalar because the depths worth having
// are UNEQUAL: RGB565 spends its spare bit on green (31, 63, 31) because the eye resolves green finest,
// and RGB332 starves blue (7, 7, 3) for the same reason. `color_steps` could never express either.
//
// vec3(0.0) is the sentinel for NOBODY IS DRIVING THIS MATERIAL, and the fragment then falls back to the
// authored scalar `color_steps`. That is what keeps an un-driven material — computerroom.tscn's CRT wall,
// or this shader opened on a bare quad in the editor — looking exactly as it was authored, so the default
// here must stay zero. The player's overlay is driven every frame and never sees the fallback.
uniform vec3 quantize_levels = vec3(0.0);

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

// --- Death cinematic (driven from code on player death): a FULL grayscale drain (death_bw), a black
//     vignette that CLOSES from the edges to the centre (death_vignette), and a flat fade of the whole
//     frame to black (death_fade). All go all the way to black and are applied last so they override every
//     other effect. death_vignette is the "tunnel closing in" on death; death_fade is the flat fade the
//     spawn fade-UP reuses (death_vignette 0..1 = closing, death_fade 1..0 = the unfade back in). ---
uniform float death_bw : hint_range(0.0, 1.0) = 0.0;
uniform float death_vignette : hint_range(0.0, 1.0) = 0.0;
uniform float death_fade : hint_range(0.0, 1.0) = 0.0;

// --- Colorblind correction (daltonization): 0 none, 1 protanopia, 2 deuteranopia, 3 tritanopia. ---
uniform int colorblind_mode = 0;

// --- Contrast (player setting, Video tab; driven from code via Settings.contrast): scales the finished
//     image around mid-gray. 1.0 = the authored look; <1 washes toward gray, >1 deepens. ---
uniform float contrast : hint_range(0.5, 1.5) = 1.0;

// --- Lens (barrel / fisheye) -------------------------------------------------------------------------------
// Bends the SCREEN FETCH radially: the centre of the frame is magnified and the periphery squeezed, so straight
// lines off the centre bow outward. That is barrel distortion — a wide lens — and it is the one thing that reads
// as "fisheye" without touching the projection (a Camera3D cannot do it: FOV is a uniform scale, see
// CameraEffects.base_fov). `hud_curve.gdshader` deliberately does NOT use a radial term, because its job is a
// cylinder; its own comment says a `dot(d, d)` term "would bend both at once and always look like a lens". This
// is that term, on purpose.
//
// ⭐ THE NUMBER IS CENTRE MAGNIFICATION MINUS ONE, because the bend is normalised by the corner and then divided
// by itself at the corner (see lens_warp): 0.08 = the centre reads ~8% bigger, the CORNERS STAY PINNED to the
// corners. Pinning is not cosmetic — SCREEN_TEXTURE is `repeat_disable`, so a fetch that ran past the edge would
// smear the border texel down the whole side. It also means this never shows black bars, at any strength.
// Driven live from code by player.gd out of GameSettings.camera.lens_barrel scaled by the Options → Video "Lens
// Curve" slider (Settings.lens_curve) — the ps1_warp_intensity / hud_curve idiom. 0 = perfectly flat, and 0 is
// the default so the CRT wall in computerroom.tscn (the other material on this shader) is untouched.
uniform float lens_barrel : hint_range(-0.25, 1.0) = 0.0;
// Lens fringe, as a FRACTION OF THE BEND rather than an absolute offset — red reads a slightly weaker bend and
// blue a slightly stronger one, so the colour split grows with the curve instead of fighting it and vanishes
// with it. This is what makes the warp read as GLASS rather than as a wobble. 0 = off (default); at 1.0 the red
// and blue taps read a bend 20% weaker / stronger than green. Costs two extra screen taps, and only when it is
// actually on.
uniform float lens_chroma : hint_range(0.0, 1.0) = 0.0;

// --- Bayer (ordered-dither) threshold matrix, 2x2 / 4x4 / 8x8 ---
//
// Evaluated as a FORMULA instead of a stored table so one function serves every size: a `float[16]`
// const can only ever be one matrix, which is why the version this replaced was hardcoded to 4x4.
//
// The matrix is defined recursively —
//     M_1  = [ 0 ]
//     M_2N = [ [ 4*M_N + 0, 4*M_N + 2 ],
//              [ 4*M_N + 3, 4*M_N + 1 ] ]
// — so each finer level multiplies the value by 4 and adds an offset picked by ONE bit of x and one of y:
//     offset(xb, yb) = 2*(xb ^ yb) + yb        // (0,0)->0  (1,0)->2  (0,1)->3  (1,1)->1
// Walking the coordinate bits LOW to HIGH with `v = v*4 + offset` gives the HIGH coordinate bits the small
// weights and the low bits the large ones, which is that recursion unrolled. At order 2 it reproduces the
// classic 4x4 table this file used to spell out (0 8 2 10 / 12 4 14 6 / 3 11 1 9 / 15 7 13 5) EXACTLY —
// same matrix, computed rather than typed — and at order 3 the canonical 8x8. Every size comes out a
// permutation of 0..N*N-1, which is what makes the thresholds spread evenly over one quantisation step.
//
// Returns the threshold in (0, 1), CENTRED: the +0.5 makes the matrix mean exactly 0.5, so a full-strength
// dither has no DC bias (a bare v/(N*N) averages 0.5 - 1/(2*N*N) and would darken the whole frame by a
// fraction of a colour step). 0.5 is also what "no dither" means below, so the two blend cleanly.
float bayer(ivec2 pixel_coord, int order) {
    int size = 1 << order;
    // Wrap with AND, never `%`: size is a power of two, and GLSL's % keeps the sign — a negative coordinate
    // (possible on any off-screen fragment) would index the matrix from the wrong side.
    int x = pixel_coord.x & (size - 1);
    int y = pixel_coord.y & (size - 1);
    int v = 0;
    // Constant loop bound + break rather than `k < order`: the bound must not depend on a uniform, or the
    // shader is at the mercy of the driver's willingness to compile a dynamically-bounded loop.
    for (int k = 0; k < 3; k++) {
        if (k >= order) {
            break;
        }
        int xb = (x >> k) & 1;
        int yb = (y >> k) & 1;
        v = v * 4 + 2 * (xb ^ yb) + yb;
    }
    return (float(v) + 0.5) / float(size * size);
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

// Map an output UV onto the source UV the barrel lens should read it from. `k` is passed in rather than read off
// the uniform so the chroma taps can walk it per channel; `aspect` likewise, because a Godot shader's built-ins
// (SCREEN_PIXEL_SIZE) are not reliably visible inside a user function.
//
// The shape: centre the coordinate, stretch X by the aspect so the bend is a CIRCLE and not an ellipse, then
// scale the radius by (1 + k*r2n) where r2n is 0 at the centre and 1 at the corner. Dividing that by its own
// value at the corner (1 + k) pins the corners — the same fitted-normalisation trick hud_curve.gdshader uses so
// its concave panel cannot flare content off the canvas.
vec2 lens_warp(vec2 uv, float k, float aspect) {
    vec2 c = uv * 2.0 - 1.0;
    c.x *= aspect;
    float r2_corner = aspect * aspect + 1.0;
    float r2n = dot(c, c) / r2_corner;
    c *= (1.0 + k * r2n) / (1.0 + k);
    c.x /= aspect;
    return c * 0.5 + 0.5;
}

// One screen tap through the lens, or three when the fringe is on. Early-outs to a plain fetch when the lens is
// flat, so the shipped default costs nothing at all.
vec3 lens_sample(vec2 uv, float aspect) {
    if (lens_barrel == 0.0) {
        return texture(SCREEN_TEXTURE, uv).rgb;
    }
    if (lens_chroma <= 0.0) {
        return texture(SCREEN_TEXTURE, lens_warp(uv, lens_barrel, aspect)).rgb;
    }
    // 0.2 = the fringe at chroma 1.0, as a fraction of the bend. Kept small deliberately: past about a fifth the
    // split stops reading as glass and starts reading as a broken frame.
    float spread = lens_barrel * lens_chroma * 0.2;
    return vec3(
        texture(SCREEN_TEXTURE, lens_warp(uv, lens_barrel - spread, aspect)).r,
        texture(SCREEN_TEXTURE, lens_warp(uv, lens_barrel, aspect)).g,
        texture(SCREEN_TEXTURE, lens_warp(uv, lens_barrel + spread, aspect)).b);
}

void fragment() {
    // --- 1. Downscale using UV quantization (works for any render_scale) ---
    // Each output pixel picks the colour from a fixed grid cell.
    vec2 low_res_uv = floor(SCREEN_UV * render_scale) / render_scale;
    // The LENS bends the FETCH only — `low_res_uv` itself stays screen-aligned, so the pixelation grid and the
    // Bayer threshold derived from it below stay square to the display instead of stretching with the warp.
    float lens_aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
    vec3 final_color = lens_sample(low_res_uv, lens_aspect);

    // --- 2+3. Posterize, with the Bayer threshold folded IN (ONE quantisation, not two; there is no
    //          separate step 3 any more, which is the whole point) ---
    //
    // ⭐ THE TRAP THIS FIXES: posterizing first and dithering after is a mathematical NO-OP, and that is
    // exactly what this shader used to do. Step 2 landed the colour on k/steps; step 3 then computed
    // floor((k/steps + d/steps) * steps)/steps = floor(k + d)/steps, and d < 1 always floors straight back
    // to k. Every pixel, every colour, every matrix cell — the 4x4 Bayer table above it was never able to
    // change a single output value (proved by evaluating the shipped chain over 1001 input levels x all 16
    // cells: 0 differences). A dither has to BE the rounding decision, so there is only one quantise now
    // and the matrix supplies its threshold.
    //
    // Why it works: `floor(c*steps + d)` rounds up exactly when the fractional part exceeds 1 - d. Feed d
    // from a matrix whose cells are spread evenly over (0,1) and a colour sitting 1/3 of the way between
    // two palette steps rounds up in 1/3 of the cells, so the eye averages the tile back to the original
    // colour: the band becomes a pattern instead of an edge.
    //
    // `dither_strength` shrinks the threshold spread around 0.5, so 0 degenerates to floor(c*steps + 0.5)
    // — plain round-to-nearest, bit-identical to the old step 2 — and 1 is the full matrix. No branch on
    // the player's value beyond the gate: the mix IS the dial.

    // Per-channel levels from the player's Colour Depth dial; the vec3(0) sentinel falls back to the
    // material's authored scalar, so an un-driven scene quantises exactly as it always did.
    vec3 steps = quantize_levels.r > 0.0 ? quantize_levels : vec3(float(color_steps));
    float threshold = 0.5;
    if (enable_dithering && bayer_order > 0 && dither_strength > 0.0) {
        // Dither on the DOWNSCALED grid, not on raw fragments. `low_res_uv` already names the block this
        // fragment took its colour from, so mapping it back to pixels hands every fragment inside one
        // chunky block the SAME threshold — one dithered colour per VISIBLE pixel, instead of a sub-block
        // pattern that shimmers as the camera moves. Where render_scale is at or above the back-buffer
        // width (ui.tscn ships 1584 over a 792 px buffer = no real downscale) this collapses exactly back
        // to the fragment's own integer coordinate, so the shipped chain gets a true 1:1 screen-pixel
        // Bayer. Derived from low_res_uv rather than render_scale so it can never disagree with whatever
        // grid step 1 actually sampled.
        ivec2 dither_px = ivec2(floor(low_res_uv / SCREEN_PIXEL_SIZE));
        threshold = mix(0.5, bayer(dither_px, bayer_order), dither_strength);
    }
    // ONE threshold across all three channels on purpose: an ordered dither is a spatial decision about
    // this PIXEL, and per-channel thresholds would decorrelate the channels into colour fringing on flat
    // greys. The channels differ only in how many levels they have to choose between.
    final_color = floor(final_color * steps + threshold) / steps;

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

    // --- 4e. Contrast (player setting): scale around mid-gray. Before grain (so grain amplitude stays
    //     consistent) and before the death fade (multiplicative, so black still reaches pure black). ---
    if (contrast != 1.0) {
        final_color = clamp((final_color - 0.5) * contrast + 0.5, 0.0, 1.0);
    }

    // --- 5. Film grain, layered on top of the retro image ---
    // TIME must be WRAPPED before entering the hash: sin() runs in float32, so once TIME passes a few
    // hundred seconds the argument reaches tens of thousands, where float32 resolution (~0.004+) exceeds
    // the per-pixel UV step — neighbouring pixels hash to the SAME value and the fine grain degenerates
    // into large correlated PATCHES that strobe together ("flashing textures" on flat walls/stairs,
    // worsening with session uptime). fract() keeps the seed in [0,1) forever, so the sine argument stays
    // small and the grain stays per-pixel fine at any uptime. 13.7 is an arbitrary non-integer rate so
    // the wrap phase never locks to a frame-rate multiple.
    float grain_t = fract(TIME * 13.7);
    float noise = (fract(sin(dot(SCREEN_UV * (1.0 / grain_size) + grain_t, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;
    final_color += noise * grain_amount;

    // --- 6. Death cinematic: drain the finished frame to grayscale, then fade it to black. Applied last
    //     (over grain + everything) so a dying view greys out and goes fully black before the reload. ---
    if (death_bw > 0.0) {
        float death_lum = dot(final_color, vec3(0.299, 0.587, 0.114));
        final_color = mix(final_color, vec3(death_lum), clamp(death_bw, 0.0, 1.0));
    }
    // Closing vignette: the still-lit radius shrinks from off-screen (nothing dark at 0) to past centre
    // (everything black at 1), so the darkness sweeps in from the edges and swallows the frame.
    if (death_vignette > 0.0) {
        float dv_d = length(SCREEN_UV - vec2(0.5)) / 0.70710678;      // 0 at centre .. ~1 at the corners
        float dv_lit = mix(1.6, -0.5, clamp(death_vignette, 0.0, 1.0)); // radius of the lit area, shrinking past centre
        float dv_v = clamp((dv_lit - dv_d) / 0.45, 0.0, 1.0);          // 1 lit, 0 black, 0.45 soft edge
        final_color *= dv_v;
    }
    final_color *= (1.0 - clamp(death_fade, 0.0, 1.0));

    COLOR = vec4(clamp(final_color, 0.0, 1.0), 1.0);
}
