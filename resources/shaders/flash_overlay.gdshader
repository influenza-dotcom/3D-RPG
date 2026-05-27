shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec3 flash_color : source_color = vec3(0.25, 0.0, 0.0);
uniform float flash_strength : hint_range(0.0, 4.0) = 4.0;

void fragment() {
	ALBEDO = flash_color * flash_strength;
	ALPHA = 1.0;
}
