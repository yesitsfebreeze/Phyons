struct Uniforms {
	view_proj: mat4x4<f32>,
	inv_view_proj: mat4x4<f32>,
	model: mat4x4<f32>,
	camera_pos: vec3<f32>,
	time: f32,
	screen_width: f32,
	screen_height: f32,
	phyon_count: f32,
	face_count: f32,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

struct FragmentInput {
	@builtin(position) frag_coord: vec4<f32>,
	@location(0) @interpolate(flat) face_id: u32,
}

struct FragmentOutput {
	@location(0) data: vec4<f32>,
}

@fragment
fn fs_main(in: FragmentInput) -> FragmentOutput {
	var out: FragmentOutput;

	// Output face_id normalized to [0,1] range
	// We reconstruct the triangle's 3 phyons in the compute shader using indices[face_id * 3 + 0/1/2]
	let normalized_id = f32(in.face_id) / uniforms.face_count;
	out.data = vec4<f32>(0.0, 0.0, 0.0, normalized_id);
	return out;
}
