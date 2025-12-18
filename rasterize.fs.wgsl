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
	@location(0) @interpolate(flat) idx: u32,
	@location(1) barycentrics: vec3<f32>,
}

struct FragmentOutput {
	@location(0) color: vec4<f32>,
}

@fragment
fn fs_main(in: FragmentInput) -> FragmentOutput {
	var out: FragmentOutput;

	out.color = vec4<f32>(in.barycentrics, f32(in.idx) / uniforms.face_count);

	return out;
}
