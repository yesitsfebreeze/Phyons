// Fragment shader outputs GPU-interpolated phyon data to textures
// These textures store everything needed to reconstruct the smooth surface

struct FragmentInput {
	@builtin(position) frag_coord: vec4<f32>,
	@location(0) inside: vec3<f32>,
	// Anchor point (GPU interpolated)
	@location(1) normal: vec3<f32>,
	// Surface direction (GPU interpolated)
	@location(2) depth: f32,
	// Distance to surface (GPU interpolated)
	@location(3) material_id: f32,
	// Material identifier
}

struct FragmentOutput {
	@location(0) inside_depth: vec4<f32>,
	// xyz = inside position, w = depth
	@location(1) normal_material: vec4<f32>,
	// xyz = normal, w = material_id
}

@fragment
fn fs_main(in: FragmentInput) -> FragmentOutput {
	var out: FragmentOutput;

	// Store interpolated inside position and depth
	out.inside_depth = vec4<f32>(in.inside, in.depth);

	// Store interpolated normal and material ID
	out.normal_material = vec4<f32>(in.normal, in.material_id);

	return out;
}
