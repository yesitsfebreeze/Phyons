struct Uniforms {
	view_proj: mat4x4<f32>,
	model: mat4x4<f32>,
	time: f32,
	screen_width: f32,
	screen_height: f32,
	triangle_count: f32,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

struct FragmentInput {
	@builtin(position) frag_coord: vec4<f32>,
	@location(0) @interpolate(flat) triangle_id: u32,
	@location(1) bary: vec3<f32>,
}

struct FragmentOutput {
	@location(0) data: vec4<f32>,
}

@fragment
fn fs_main(in: FragmentInput) -> FragmentOutput {
	var out: FragmentOutput;

	// RGB: barycentric coordinates (full precision)
	// A: normalized triangle_id [0,1] (or -1 for no hit, handled by clear color)
	let normalized_id = f32(in.triangle_id) / uniforms.triangle_count;
	out.data = vec4<f32>(in.bary, normalized_id);
	return out;
}
