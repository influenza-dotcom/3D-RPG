shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// ONE RAIN DROP, FORESHORTENED. Drawn by rain_fall.gd as the draw pass of its GPUParticles3D.
//
// ⭐ WHY THIS EXISTS AT ALL. The node already sets `transform_align =
// TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY`, which turns each streak to lie along the direction the drop is
// really travelling instead of along the screen's up. That alone fixes the DIRECTION of the streak — but not
// its LENGTH, because the engine NORMALISES the velocity after flattening it into the screen plane. So a drop
// coming straight at the camera still draws at its full length: look up at rain falling straight down and you
// get a sky full of full-size streaks that should have collapsed to points. Perspective is missing exactly the
// term the normalise threw away, and that term is what this shader puts back.
//
// The maths is one dot product. `across` is |sin| of the angle between the line of fall and the line of sight:
// 1 when the drop crosses the view (full streak), 0 when you are staring straight up or down its path.
//
// ⭐ IT DOES NOT SHRINK TO NOTHING, ON PURPOSE. A streak seen exactly end-on is geometrically a point, and rain
// that ERASES itself the moment you look up at it is a worse lie than rain that never turned in the first
// place. `end_on_length` floors the collapse and `end_on_width` fattens what is left, so a drop coming at your
// face reads as the short thick dash it actually looks like rather than a hair or a hole.

/// Unit vector, in WORLD space, along which every drop travels. Written by rain_fall.gd from its lean + wind
/// heading; a constant for the whole field because the emitter gives every drop the same direction (spread 0).
uniform vec3 fall_direction = vec3(0.0, -1.0, 0.0);
/// Fraction of `drop_length` a streak keeps when it is seen dead end-on. Never 0 — see the header.
uniform float end_on_length : hint_range(0.02, 1.0) = 0.16;
/// Multiple of `drop_width` a streak swells to as it collapses, so end-on drops read as dots, not as slivers.
uniform float end_on_width : hint_range(1.0, 8.0) = 3.0;

// --- SKY OCCLUSION ------------------------------------------------------------------------------------------
// ⭐ WHY A DROP CULLS ITSELF INSTEAD OF THE EMITTER STOPPING. The obvious way to keep rain out of a room is to
// switch the emitter off under a roof, and that is what this component used to do — but the field rides the
// camera, so switching it off deletes the weather EVERYWHERE, including the street you can see through the
// doorway. Standing indoors watching a dry city is a worse lie than the leak it fixed.
//
// So the cutoff moved down to the individual drop. rain_fall.gd keeps a small rolling heightfield around the
// camera — one texel per world cell, holding the height of the TOPMOST thing over that cell — and a drop below
// that height simply collapses to a point and rasterises nothing. That is per-drop sky occlusion: rain stops at
// the roof line and keeps falling one cell further out, a doorway has weather on one side of it, and the drops
// you would see THROUGH the roof are hidden by the roof's own geometry, which the depth test was always doing.
//
// The lookup is world-anchored (cell = floor(world.xz / cell_size)) and the texture WRAPS, so a texel is a fixed
// patch of the world and walking does not shimmer the pattern — the grid scrolls under you like a virtual
// texture. Nearest filtering, deliberately: blending two cells' heights across the wrap seam would invent roofs.

/// True only while rain_fall.gd has actually built and assigned the heightfield below.
uniform bool sky_occlusion_enabled = false;
/// R32F. Texel (cell.x mod N, cell.z mod N) holds the world Y of the topmost surface over that world cell, or a
/// large negative number where the sky is open. NEAREST + REPEAT is load-bearing — see above.
uniform sampler2D sky_height : filter_nearest, repeat_enable, hint_default_black;
/// Metres per cell, and the grid's width in cells. Both come from rain_fall.gd's own grid, never guessed here.
uniform float sky_cell_size = 1.0;
uniform int sky_grid_cells = 24;

void vertex() {
	vec3 drop_world = MODEL_MATRIX[3].xyz;

	// How high the sky is blocked over this drop. Left far below every drop when occlusion is off, so the branch
	// below is then always the drawing one.
	float roof = -1.0e9;
	if (sky_occlusion_enabled) {
		vec2 cell = floor(drop_world.xz / sky_cell_size) + 0.5;
		roof = textureLod(sky_height, cell / float(sky_grid_cells), 0.0).r;
	}

	// ⭐ NO `return` HERE. Godot inlines this function's body into the generated main(), so returning early would
	// skip writing the position along with everything else. The cull is an else-branch, not an exit.
	if (drop_world.y < roof) {
		// Under a roof: every corner of the quad onto one point, so it rasterises nothing at all.
		VERTEX = vec3(0.0);
	} else {
		// The line of sight to THIS drop, not the camera's forward: across a 75-degree view the two differ by
		// enough to matter, and using the forward vector puts the collapse in the middle of the screen instead
		// of around the point the rain is actually falling from.
		vec3 to_drop = drop_world - INV_VIEW_MATRIX[3].xyz;
		float dist = length(to_drop);
		vec3 view_dir = dist > 0.001 ? to_drop / dist : vec3(0.0, 0.0, -1.0);
		float along = dot(normalize(fall_direction), view_dir);
		float across = sqrt(clamp(1.0 - along * along, 0.0, 1.0));
		// The quad's local Y is the streak's length (rain_fall.gd builds it that way) and X is its width.
		VERTEX.y *= max(across, end_on_length);
		VERTEX.x *= mix(end_on_width, 1.0, across);
	}
}

void fragment() {
	// COLOR is the particle's own colour from the process material: rain is a smear of whatever light is behind
	// it, so the low alpha and the additive blend above do all the work.
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
