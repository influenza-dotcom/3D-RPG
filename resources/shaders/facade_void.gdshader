shader_type spatial;

// THE BOTTOMLESS FACADE — the skin of the "you are standing on something enormous" illusion
// (scripts/components/skyscraper_void.gd builds the geometry it wears).
//
// ⭐ THE REFERENCE IS PERIPETEIA, picked by the user with a screenshot: looking down the side of a tower block
// in the rain. Four things in that frame decide every line below, and all four are the OPPOSITE of the "clean
// modern skyline" this file drew in its first pass:
//   1. EVERYTHING IS ONE COLD HUE — the air, the concrete, the distance. (The reference reads blue-TEAL; this
//      palette is graded blue instead, because teal puts green over red and this game's 12-bit RGB444 dither
//      turns that into a green speckle over the whole building. Same coldness, a hue away from the trap.)
//   2. THERE IS NO GROUND AND NO HORIZON LINE. The drop just falls off into darker and darker teal. That is why
//      the fog plane the component can build now ships DISABLED: a lit fog floor draws a line across the view
//      and tells the eye exactly how deep the hole is.
//   3. A DISTANT BUILDING IS NOTHING BUT ITS WINDOW LIGHTS. Its concrete dissolves completely while the lights
//      stay — so lit windows RESIST the haze (`light_haze_resist`) instead of fading with the wall they sit in.
//      That single term is what turns the far towers into constellations instead of grey slabs.
//   4. THE WALLS READ AS STACKED HORIZONTAL LEDGES, not as a window grid: a bright slab edge catching the light
//      with a dark line under it, once per storey, and small dense windows punched into the field between. Big
//      glassy bays are a different century's building.
//
// A tower wall is drawn PROCEDURALLY instead of textured for one reason: the pattern is anchored in WORLD space
// (v_world.y drives the storeys), not in the mesh's UVs. That is what makes the drop read as bottomless — the
// geometry can be kilometres tall and the floors never swim, stretch or seam, because a storey belongs to a
// WORLD HEIGHT, not to a vertex.
//
// ⭐ NO `TIME` ANYWHERE, ON PURPOSE. The lit-window pattern is a hash of (bay, floor), and a hash fed by TIME is
// the shader-grain strobe this project has already been bitten by: TIME grows unbounded, its float precision
// decays, and a "static" hash starts flickering hours into a session. Every window here is lit or dark for the
// whole run, decided by its position. The `mod(..., hash_wrap)` below is the same precision argument one level
// down: `sin()` fed a floor index of -40000 returns mush, so the index is wrapped into a range where the hash is
// still well conditioned, and the pattern repeats every `hash_wrap` floors instead of degenerating into stripes.
//
// ⭐ UNSHADED. The drop has no lights in it (and must not depend on the level's), the whole point of the lower
// floors is that they dissolve, and a shaded facade at 90° to every wall would read as four flat tones. The face
// tint below does the "this wall faces away from the moon" job for a fraction of the cost. Environment fog still
// applies to an unshaded surface, so a level with its own fog gets it ON TOP of the camera-relative haze here —
// deliberate: the haze must not depend on the level having fog.

render_mode unshaded, shadows_disabled, ambient_light_disabled;

// ---------------------------------------------------------------------------------------------------------
// THE GRID. Metres, not ratios: these are the only numbers telling the eye how big the building is. The
// defaults are a housing block, not an office tower — short storeys, narrow bays, small windows.
uniform float floor_height : hint_range(1.0, 12.0) = 3.0;      // metres, one storey
uniform float bay_width : hint_range(0.5, 20.0) = 2.2;         // metres, one window column
uniform float window_width : hint_range(0.0, 1.0) = 0.46;      // share of a bay that is glass
uniform float window_height : hint_range(0.0, 1.0) = 0.40;     // share of a storey that is glass
uniform float window_sill : hint_range(0.0, 1.0) = 0.34;       // how far up the storey the glass starts
uniform float ledge_height : hint_range(0.0, 0.5) = 0.10;      // share of a storey taken by the slab edge
// ⭐ THE RHYTHM HAS TO BE BROKEN OR IT READS AS WALLPAPER. Every `pier_every` bays is a BLIND structural pier
// (no window at all), which is what a real panel block does at its stair cores and expansion joints — and what
// stops a kilometre of identical window columns looking like a tiled texture. 0 disables it.
uniform float pier_every : hint_range(0.0, 24.0) = 7.0;
// A share of (bay-group, storey) cells is a RECESSED loggia: the concrete goes to shadow and the glass dims, so
// the facade gets dark patches running across it instead of one flat field.
uniform float recess_chance : hint_range(0.0, 1.0) = 0.16;
uniform float hash_wrap : hint_range(16.0, 4096.0) = 512.0;    // floors/bays before the lit pattern repeats

// COLOURS. ⭐ TUNE THESE ON THE COMPONENT, NOT HERE. skyscraper_void.gd drives every one of them from an
// @export Color, and Godot converts a Color written into a `source_color` uniform from sRGB to LINEAR. A vec3
// literal in shader source is passed through RAW instead, so the defaults below are the LINEAR equivalents and
// are NOT the numbers a designer would pick — they only apply to a material with no component behind it. (The
// same two-space trap as horizon_sky.gdshader; a linear value typed into the component's export renders the
// whole drop about five times too dark.) The sRGB each default represents is in its comment.
// ⭐⭐GREEN MUST NEVER EXCEED RED HERE. The game quantises the screen to 12-bit RGB444 and dithers it, and a
// green-leaning dark colour comes back out of that lattice as a ghostly green speckle over the whole building
// (reported from the live game, 2026-09-18). The palette is graded cold BLUE for that reason, not for taste.
uniform vec3 wall_color : source_color = vec3(0.024, 0.027, 0.056);            // ~sRGB (0.17,0.18,0.26) wet concrete
uniform vec3 ledge_color : source_color = vec3(0.044, 0.048, 0.091);           // ~sRGB (0.23,0.24,0.33) lit slab edge
uniform vec3 shadow_color : source_color = vec3(0.008, 0.010, 0.021);          // ~sRGB (0.09,0.10,0.16) under the slab
uniform vec3 window_dark_color : source_color = vec3(0.005, 0.006, 0.014);     // ~sRGB (0.07,0.08,0.13) dead glass
uniform vec3 window_lit_color : source_color = vec3(0.956, 0.745, 0.397);      // ~sRGB (0.98,0.88,0.66) warm bulb
uniform vec3 window_lit_cool_color : source_color = vec3(0.479, 0.572, 0.956); // ~sRGB (0.72,0.78,0.98) strip light
uniform float lit_cool_share : hint_range(0.0, 1.0) = 0.28;    // how many lit windows take the cool tone
uniform float window_lit_energy : hint_range(0.0, 8.0) = 1.0;  // >1 blooms a window through glow, smearing its hue
uniform float lit_chance : hint_range(0.0, 1.0) = 0.22;        // share of windows with a light on
uniform float grime_strength : hint_range(0.0, 1.0) = 0.30;    // vertical staining + per-cell jitter

// FACE TINT — a cheap directional read so the four walls of a box don't render as one flat tone.
uniform vec3 tint_dir = vec3(0.4, 0.0, 0.9);
uniform float tint_min : hint_range(0.0, 1.0) = 0.6;

// ---------------------------------------------------------------------------------------------------------
// THE HAZE IS THE ILLUSION, AND IT IS ONE FOG, NOT TWO FADES.
//
// ⭐⭐WHY THIS WAS REWRITTEN. The first model faded a surface by how many metres it sat BELOW THE EYE, separately
// from how far away it was. That is a horizontal SLICE PLANE across the whole city: every building, near or far,
// dissolves at exactly the same height, so they all "fade out in the middle somewhere" instead of receding —
// reported from the live game twice, and no amount of range tuning could fix it, because the slice is the model.
//
// What replaces it is what fog actually does: light is extinguished along the REAL view ray, and the fog is
// thicker further down. So the amount of murk between you and a point depends on the true 3D distance to it AND
// on how deep it lies — and those are not independent, because looking further down a building means looking
// further away. A near wall therefore stays readable hundreds of metres down while a distant tower is gone at
// eye level, which is exactly the read the reference has and the slice plane could never produce.
//
//     extinction = distance * density(depth),  fog = 1 - exp(-extinction)
//
// The knobs are in metres so they can be reasoned about: fog is total at `haze_distance` when you look level,
// and every `haze_depth_boost` metres of depth doubles the density (so it closes in that much sooner looking
// down). `haze_clear` is a small bubble of perfectly clear air around the camera.
uniform float haze_clear : hint_range(0.0, 500.0) = 40.0;        // metres of clear air before any fog
uniform float haze_distance : hint_range(10.0, 20000.0) = 2200.0;// metres to total fog, looking level
uniform float haze_depth_boost : hint_range(5.0, 2000.0) = 150.0;// metres of depth that DOUBLE the density
uniform float haze_max : hint_range(0.0, 1.0) = 1.0;             // 1.0 = the far end is literally invisible

uniform vec3 haze_color : source_color = vec3(0.010, 0.014, 0.048);  // ~sRGB (0.11,0.13,0.24) the cold blue murk
// ⭐ WHAT THE MURK BECOMES FURTHER DOWN. Fading everything to one flat `haze_color` is not enough: that colour is
// LIGHTER than the void behind it, so a fully-fogged tower keeps a perfect silhouette. This should be THE SAME
// COLOUR AS THE SKY BELOW THE HORIZON (the component reads it off the sky for you).
uniform vec3 haze_deep_color : source_color = vec3(0.002, 0.003, 0.006);  // ~sRGB (0.03,0.04,0.08) the void
uniform float haze_deep_full : hint_range(1.0, 8000.0) = 420.0;  // metres below the eye where the murk IS the void
// Set to 0 by the component for its (optional, off by default) fog plane: that plane IS the fog, so thickening
// it by its own depth would only turn it dark.
uniform float below_haze_mult : hint_range(0.0, 1.0) = 1.0;

// ⭐ LIGHT CARRIES FURTHER THROUGH FOG THAN CONCRETE — BUT IT STILL DIES. A lit window sees the density divided
// by this, so its lights linger well past the depth where their wall has gone, and then go too. A REACH, not a
// resist: capping the fog on windows instead left every light partly visible for ever, and a tower's foot was
// readable as the line where its lights stopped.
uniform float light_haze_reach : hint_range(1.0, 6.0) = 1.9;

// ⭐⭐WHERE THE DROP STOPS BEING DRAWN AT ALL. Fading toward a colour only hides a surface when the thing BEHIND
// it is that colour, and in the shipped level it is not: the map is wrapped in a painted SKYBOX BRUSH, against
// whose bright art a fogged tower stayed a dark silhouette with a visible flat bottom. So past this fraction of
// the fog, an ordered 4x4 dither discards a rising share of the surface's pixels until none are left — and a
// discarded pixel shows whatever is really behind it. Held late so the COLOUR fade does most of the work: the
// dither is a visible screen-door while it is half-on.
//
// ⭐ A DISCARD, NOT TRANSPARENCY: alpha would push the whole skyline into the transparent queue, where these
// overlapping boxes (one mesh) cannot be sorted against each other.
uniform float dissolve_begin : hint_range(0.0, 1.0) = 0.85;

uniform bool flat_fill = false;
uniform vec3 flat_fill_color : source_color = vec3(0.008, 0.010, 0.021);

varying vec3 v_world;
varying vec2 v_surface;   // x = metres along the wall (from the mesh UV), y = unused
varying vec3 v_normal_w;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_surface = UV;   // the builder writes METRES into UV, not 0..1 — see skyscraper_void.gd
	v_normal_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// The classic 4x4 ordered (Bayer) threshold matrix, 0..1, indexed by SCREEN pixel. Screen-space on purpose: the
// stipple then stays a fixed fine grain instead of swimming over the geometry as it recedes.
float ordered_dither(vec2 frag) {
	int x = int(mod(frag.x, 4.0));
	int y = int(mod(frag.y, 4.0));
	int i = x + y * 4;
	float m[16] = {
		 0.0,  8.0,  2.0, 10.0,
		12.0,  4.0, 14.0,  6.0,
		 3.0, 11.0,  1.0,  9.0,
		15.0,  7.0, 13.0,  5.0
	};
	return (m[i] + 0.5) / 16.0;
}

// Stable 0..1 hash of a (bay, floor) cell. Wrapped before the sin() for the precision reason in the header.
float cell_hash(vec2 cell, float salt) {
	vec2 c = mod(cell, vec2(hash_wrap));
	return fract(sin(dot(c, vec2(127.1, 311.7)) + salt) * 43758.5453);
}

// The two haze fades. `below` is measured from the CAMERA's height, `away` is plain camera distance; the stronger
// wins, so neither a tower directly underfoot nor one at eye level a kilometre out escapes the murk.
//
// ⭐ `eye_y` IS PASSED IN, NOT READ HERE. Godot's shader built-ins (CAMERA_POSITION_WORLD, VERTEX, ...) exist only
// inside vertex()/fragment()/light() — a user-defined function that names one fails to COMPILE with "Unknown
// identifier in expression", and a shader that fails to compile takes the whole facade down to a blank material.
// How much murk lies between the eye and this point: the real 3D distance through fog whose density rises with
// depth. `reach` divides the density for a light source (see light_haze_reach). Returns 0..1.
float fog_amount(vec3 world_pos, vec3 view_pos, float eye_y, float reach) {
	float depth = max(eye_y - world_pos.y, 0.0) * below_haze_mult;
	// Density at eye level is calibrated so that `haze_distance` metres of it extinguishes ~95% (e^-3), and it
	// doubles every `haze_depth_boost` metres of depth. Unbounded on purpose: straight down must always end in
	// total murk, however close the wall you are looking along happens to be.
	float density = (3.0 / max(haze_distance, 1.0)) * (1.0 + depth / max(haze_depth_boost, 1.0));
	float through = max(length(view_pos) - haze_clear, 0.0);
	return clamp(1.0 - exp(-through * density / max(reach, 1.0)), 0.0, 1.0) * haze_max;
}

void fragment() {
	// ⭐ ONE EXIT, NO EARLY `return`. Godot rejects `return` inside a processor function outright ("Using 'return'
	// in the 'fragment' processor function is incorrect"), so every branch writes `col` and falls through to the
	// same haze mix — which is also what keeps a roof cap in the same fog as the walls under it.
	vec3 col;
	float lit = 0.0;   // 1 on a lit window: the one surface allowed to resist the haze

	if (flat_fill) {
		col = flat_fill_color;
	} else {
		// --- the grid cell this pixel is in ---------------------------------------------------------------
		float fy = v_world.y / max(floor_height, 0.001);       // WORLD height -> storeys (the anchor)
		float fx = v_surface.x / max(bay_width, 0.001);        // metres along the wall -> bays
		vec2 cell = vec2(floor(fx), floor(fy));
		float in_bay = fract(fx);
		float in_floor = fract(fy);

		// --- the stacked-ledge read ------------------------------------------------------------------------
		// Bottom of each storey: the slab edge, lit along its top; immediately above it the shadow it throws on
		// the wall. Everything else is concrete field, with one small window punched into it.
		bool is_ledge = in_floor < ledge_height;
		bool is_shadow = !is_ledge && in_floor < ledge_height * 1.9;
		bool blind_pier = pier_every >= 1.0 && mod(floor(fx), pier_every) < 0.5;
		bool recessed = cell_hash(vec2(floor(fx * 0.25), cell.y), 5.9) < recess_chance;
		bool is_window = !blind_pier
			&& abs(in_bay - 0.5) < window_width * 0.5
			&& in_floor > window_sill && in_floor < window_sill + window_height;

		if (is_window) {
			float h = cell_hash(cell, 0.0);
			if (h < lit_chance) {
				// Two bulb tones: a block where every lit window is one colour reads as a texture, not a city.
				vec3 tone = cell_hash(cell, 19.7) < lit_cool_share ? window_lit_cool_color : window_lit_color;
				col = tone * window_lit_energy * (0.72 + 0.56 * cell_hash(cell, 41.3));
				lit = 1.0;
			} else {
				col = window_dark_color;
			}
		} else if (is_ledge) {
			col = ledge_color;
		} else if (is_shadow) {
			col = shadow_color;
		} else {
			col = wall_color;
		}
		// A recessed bay sits in its own shade — the glass in it too, which is why this runs AFTER the window.
		if (recessed) {
			col *= 0.62;
		}

		// --- grime, on the CONCRETE only -------------------------------------------------------------------
		// Two terms: a per-column stain running the whole height of the building (rain streaking down the
		// panels, which is what stops a kilometre of wall reading as wallpaper) and a per-cell jitter. Never on
		// a lit window — a window whose brightness changed as you moved past it would read as a flicker.
		if (lit < 0.5) {
			float streak = cell_hash(vec2(floor(fx * 3.0), 0.0), 7.1) - 0.5;
			float speck = cell_hash(cell, 71.3) - 0.5;
			col *= 1.0 + (streak * 0.7 + speck * 0.3) * grime_strength;
		}

		// --- face tint: which way this wall looks ----------------------------------------------------------
		float facing = dot(normalize(v_normal_w), normalize(tint_dir)) * 0.5 + 0.5;
		col *= mix(tint_min, 1.0, facing);
	}

	// --- the murk between here and the eye ---------------------------------------------------------------
	float haze = fog_amount(v_world, VERTEX, CAMERA_POSITION_WORLD.y, lit > 0.5 ? light_haze_reach : 1.0);
	// The fog's own colour darkens with depth toward the void (see haze_deep_color), so a surface that is
	// already fully fogged keeps sinking into the backdrop instead of holding a silhouette.
	float deep = clamp((CAMERA_POSITION_WORLD.y - v_world.y) / max(haze_deep_full, 0.001), 0.0, 1.0);
	ALBEDO = mix(col, mix(haze_color, haze_deep_color, deep), haze);

	// ...and past `dissolve_begin` the fog stops drawing it at all, so it vanishes into whatever is actually
	// behind it rather than into a colour we guessed. Fully fogged = nothing rasterised at all.
	float dis = clamp((haze - dissolve_begin) / max(1.0 - dissolve_begin, 0.001), 0.0, 1.0);
	if (dis >= 1.0 || (dis > 0.0 && ordered_dither(FRAGCOORD.xy) < dis)) {
		discard;
	}
}
