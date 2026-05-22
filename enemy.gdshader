shader_type spatial;
render_mode cull_front, unshaded;

uniform float outline_width = 0.05;
uniform vec4 outline_color : source_color = vec4(1.0);

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}