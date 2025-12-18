struct FragmentInput {
	@location(0) world_normal: vec3<f32>,
	@location(1) depth: f32,
	@location(2) view_depth: f32,
}

struct FragmentOutput {
	@location(0) color: vec4<f32>,
}

@fragment
fn fs_main(in: FragmentInput) -> FragmentOutput {
	var out: FragmentOutput;

	// Simple shading based on normal (hemisphere lighting)
	let light_dir = normalize(vec3<f32>(0.5, 1.0, 0.3));
	let ndotl = dot(in.world_normal, light_dir) * 0.5 + 0.5;

	// Base color from normal for visualization
	let normal_color = in.world_normal * 0.5 + 0.5;

	// Combine lighting with normal color
	let lit_color = normal_color * ndotl;

	// Use depth to modulate alpha for visualization
	out.color = vec4<f32>(lit_color, 1.0);

	return out;
}
