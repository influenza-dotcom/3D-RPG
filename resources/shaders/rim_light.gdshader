shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec3 rim_color : source_color = vec3(0.95, 0.88, 0.75);
uniform float rim_power : hint_range(0.1, 8.0) = 5.0;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.5;
uniform float top_bias : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float top = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	float weight = mix(1.0, top, top_bias);
	ALBEDO = rim_color * fresnel * rim_strength * weight;
}
