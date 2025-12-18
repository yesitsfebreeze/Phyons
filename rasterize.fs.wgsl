struct Uniforms {
	view_proj: mat4x4<f32>,
	model: mat4x4<f32>,
	time: f32,
	screen_width: f32,
	screen_height: f32,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

struct FragmentInput {
	@builtin(position) frag_coord: vec4<f32>,
	@location(0) @interpolate(flat) face_id: u32,
}

struct FragmentOutput {
	@location(0) face_id: u32,
}

@fragment
fn fs_main(in: FragmentInput) -> FragmentOutput {
	var out: FragmentOutput;
	out.face_id = in.face_id;
	return out;
}
