struct FragmentInput {
	@location(0) world_normal: vec3<f32>,
	@location(1) material_id: f32,
	@location(2) opacity: f32,
	@location(3) distance_to_center: f32,
	@location(4) view_depth: f32,
	@location(5) surface_depth: f32,
	// Interpolated surface depth
}

struct GBufferOutput {
	// RGB: normal (encoded), A: opacity
	@location(0) normal: vec4<f32>,
	// R: material_id, G: unused, B: unused, A: unused
	@location(1) material: vec4<f32>,
	// R: distance_to_center, G: view_depth, B: unused, A: unused
	@location(2) distance: vec4<f32>,
	// Custom depth based on interpolated surface position
	@builtin(frag_depth) frag_depth: f32,
}

@fragment
fn fs_main(in: FragmentInput) -> GBufferOutput {
	var out: GBufferOutput;

	// Encode normal from [-1,1] to [0,1] range
	out.normal = vec4<f32>(in.world_normal * 0.5 + 0.5, in.opacity);
	out.material = vec4<f32>(in.material_id / 255.0, 0.0, 0.0, 1.0);
	out.distance = vec4<f32>(in.distance_to_center, in.view_depth, 0.0, 1.0);

	// Write custom depth based on interpolated surface position
	// This decouples visibility (interior skeleton) from depth ordering (surface)
	out.frag_depth = in.surface_depth;

	return out;
}
