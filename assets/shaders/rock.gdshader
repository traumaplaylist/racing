shader_type spatial;
// Sandstone: world-space triplanar strata (bands follow world height on every rock),
// sand at the base (vertex alpha) so buttes grow out of the ground, dusty tops.
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_scale = 0.05;
uniform float detail_scale = 0.23;
uniform float sand_scale = 0.07;
uniform vec3 tint : source_color = vec3(1.0);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

vec3 tri(sampler2D t, vec3 p, vec3 bw, float s) {
	vec3 x = texture(t, p.zy * s * vec2(1.0, -1.0)).rgb;
	vec3 z = texture(t, p.xy * s * vec2(1.0, -1.0)).rgb;
	vec3 y = texture(t, p.xz * s).rgb;
	return x * bw.x + y * bw.y + z * bw.z;
}

void fragment() {
	vec3 bw = pow(abs(wnrm), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec3 rock = tri(rock_tex, wpos, bw, rock_scale);
	vec3 detail = tri(rock_tex, wpos + vec3(13.0), bw, detail_scale);
	rock = rock * (0.65 + 0.7 * dot(detail, vec3(0.333)));
	float up = smoothstep(0.55, 0.95, wnrm.y);
	rock = mix(rock, rock * 1.12 + vec3(0.07, 0.045, 0.02), up * 0.7);
	vec3 sand = texture(sand_tex, wpos.xz * sand_scale).rgb;
	ALBEDO = mix(sand, rock * COLOR.r * tint, COLOR.a);
	ROUGHNESS = 0.94;
	SPECULAR = 0.25;
}
