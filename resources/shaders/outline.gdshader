shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_thickness : hint_range(0.0, 0.2) = 0.02;
uniform bool use_smooth_normals = false;

void vertex() {
	vec3 disp_normal = NORMAL;
	if (use_smooth_normals) {
		disp_normal = COLOR.rgb * 2.0 - 1.0;
	}
	VERTEX += disp_normal * outline_thickness;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
