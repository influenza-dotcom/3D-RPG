shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.05;
uniform float grain_size : hint_range(0.1, 10.0) = 1.0;

void fragment() {
	vec4 original_color = texture(screen_texture, SCREEN_UV);

	// TIME is WRAPPED before entering the hash (same fix as post_process.gdshader): raw TIME grows until
	// float32 sin() loses per-pixel precision (~minutes into a session) and the grain degenerates into
	// large correlated patches that strobe together. fract() keeps the seed bounded forever.
	float grain_t = fract(TIME * 13.7);
	float noise = (fract(sin(dot(UV * (1.0 / grain_size) + grain_t, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;

	original_color.rgb += noise * grain_amount;

	COLOR = clamp(original_color, 0.0, 1.0);
}
