struct Uniforms {
	view_proj: mat4x4<f32>,
	model: mat4x4<f32>,
	time: f32,
	screen_width: f32,
	screen_height: f32,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

struct VertexInput {
	@builtin(vertex_index) vertex_index: u32,
	@location(0) position: vec3<f32>,
	@location(1) normal: vec3<f32>,
	@location(2) depth: f32,
	@location(3) opacity: f32,
}

struct VertexOutput {
	@builtin(position) position: vec4<f32>,
	@location(0) @interpolate(flat) face_id: u32,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;

	// Compute surface position (position + normal * depth)
	let surface = in.position + in.normal * (in.depth * 0.25);

	// Transform to world space then clip space
	let w_surface = (uniforms.model * vec4<f32>(surface, 1.0)).xyz;
	out.position = uniforms.view_proj * vec4<f32>(w_surface, 1.0);

	// Face ID = vertex_index / 3 (each triangle has 3 vertices)
	out.face_id = in.vertex_index / 3u;

	return out;
}
