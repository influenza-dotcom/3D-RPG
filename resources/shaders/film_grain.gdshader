shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.05;
uniform float grain_size : hint_range(0.1, 10.0) = 1.0;

void fragment() {
	vec4 original_color = texture(screen_texture, SCREEN_UV);

	float noise = (fract(sin(dot(UV * (1.0 / grain_size) + TIME, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 2.0;

	original_color.rgb += noise * grain_amount;

	COLOR = clamp(original_color, 0.0, 1.0);
}
