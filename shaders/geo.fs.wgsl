struct FragmentInput {
	@location(0) world_normal: vec3<f32>,
	@location(1) material_id: f32,
	@location(2) opacity: f32,
	@location(3) distance_to_center: f32,
	@location(4) view_depth: f32,
	@location(5) surface_depth: f32,
}

struct FragmentOutput {
	@location(0) color: vec4<f32>,
	@builtin(frag_depth) frag_depth: f32,
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

	out.color = vec4<f32>(lit_color, in.opacity);

	// Write custom depth based on interpolated surface position
	out.frag_depth = in.surface_depth;

	return out;
}
