varying highp vec3 var_world_position;
varying mediump vec3 var_world_normal;
varying highp vec3 var_position;
varying mediump vec3 var_normal;

uniform lowp vec4 tint;
uniform highp vec4 fog;
uniform lowp vec4 fog_color;
uniform mediump vec4 grid;
uniform mediump vec4 light_directional;
uniform mediump vec4 light_ambient;
uniform mediump vec4 normal_strength;

uniform lowp sampler2D texture0;
uniform lowp sampler2D normalmap;

// The mesh buffers carry position + normal only (no texcoord0, no tangent), so both the
// albedo and the normal map are projected triplanar from world space rather than sampled
// through UVs. Both use the same planes and the same blend weights so they stay in register.

lowp vec3 triplanar_sampling(sampler2D tex_x, sampler2D tex_y, sampler2D tex_z, vec3 world_pos, vec3 world_normal, float falloff, vec2 tiling)
{
	vec3 proj_normal = pow(abs(world_normal), vec3(falloff));
	proj_normal /= (proj_normal.x + proj_normal.y + proj_normal.z) + 0.00001;
	vec3 norm_sign = sign(world_normal);
	lowp vec3 x_norm = texture2D(tex_x, tiling * world_pos.zy * vec2(norm_sign.x, 1.0)).rgb;
	lowp vec3 y_norm = texture2D(tex_y, tiling * world_pos.xz * vec2(norm_sign.y, 1.0)).rgb;
	lowp vec3 z_norm = texture2D(tex_z, tiling * world_pos.xy * vec2(-norm_sign.z, 1.0)).rgb;
	return x_norm * proj_normal.x + y_norm * proj_normal.y + z_norm * proj_normal.z;
}

// Triplanar normal mapping, "whiteout" blend. Each plane's tangent-space normal is decoded
// from [0,1] to [-1,1], folded together with the geometric normal, then swizzled onto world
// axes before blending. world_normal must already be normalized.
mediump vec3 triplanar_normal(sampler2D nmap, vec3 world_pos, vec3 world_normal, float falloff, vec2 tiling)
{
	vec3 blend = pow(abs(world_normal), vec3(falloff));
	blend /= (blend.x + blend.y + blend.z) + 0.00001;
	vec3 norm_sign = sign(world_normal);

	// Same planes and sign flips as the albedo above, so the two stay aligned
	mediump vec3 n_x = texture2D(nmap, tiling * world_pos.zy * vec2(norm_sign.x, 1.0)).rgb * 2.0 - 1.0;
	mediump vec3 n_y = texture2D(nmap, tiling * world_pos.xz * vec2(norm_sign.y, 1.0)).rgb * 2.0 - 1.0;
	mediump vec3 n_z = texture2D(nmap, tiling * world_pos.xy * vec2(-norm_sign.z, 1.0)).rgb * 2.0 - 1.0;

	// Undo the mirrored UVs on the back faces
	n_x.x *= norm_sign.x;
	n_y.x *= norm_sign.y;
	n_z.x *= -norm_sign.z;

	// Whiteout blend: keep the geometric normal dominant, let the map perturb it
	n_x = vec3(n_x.xy + world_normal.zy, abs(n_x.z) * world_normal.x);
	n_y = vec3(n_y.xy + world_normal.xz, abs(n_y.z) * world_normal.y);
	n_z = vec3(n_z.xy + world_normal.xy, abs(n_z.z) * world_normal.z);

	return normalize(n_x.zyx * blend.x + n_y.xzy * blend.y + n_z.xyz * blend.z);
}

void main()
{
	// Pre-multiply alpha since all Defold materials do that
	vec4 tint_pm = vec4(tint.xyz * tint.w, tint.w);

	// Interpolated normals are not unit length
	mediump vec3 geom_normal = normalize(var_world_normal);

	// Make grid
	vec3 overlay_color = mix(vec3(1.0), triplanar_sampling(texture0, texture0, texture0, var_world_position, geom_normal, grid.z, grid.xy), grid.w);

	// Perturb the shading normal by the normal map
	mediump vec3 mapped_normal = triplanar_normal(normalmap, var_world_position, geom_normal, grid.z, grid.xy);
	mediump vec3 shade_normal = normalize(mix(geom_normal, mapped_normal, clamp(normal_strength.x, 0.0, 1.0)));

	// Directional light
	float diff_intensity = light_directional.w;
	float diff_light = max(dot(shade_normal, normalize(light_directional.xyz)), 0.0) * diff_intensity;
	float ambient_intensity = light_ambient.w;
	vec3 light = (ambient_intensity + diff_light) * light_ambient.rgb;
	vec3 final_color = (tint_pm.rgb * overlay_color) * light;

	// Fog
	float distance = abs(var_position.z);
	float fog_min = fog.x;
	float fog_max = fog.y;
	float fog_intensity = fog.w;
	float fog_factor = (1.0 - clamp((fog_max - distance) / (fog_max - fog_min), 0.0, 1.0)) * fog_intensity;

	// Color + Fog
	gl_FragColor = vec4(mix(final_color, fog_color.rgb, fog_factor), 1.0);
}
