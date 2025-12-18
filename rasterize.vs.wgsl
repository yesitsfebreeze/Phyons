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

struct VertexInput {
	@builtin(vertex_index) vertex_index: u32,
	@location(0) position: vec3<f32>,
	@location(1) normal: vec3<f32>,
	@location(2) depth: f32,
	@location(3) opacity: f32,
	@location(4) face_id: u32,
}

struct VertexOutput {
	@builtin(position) position: vec4<f32>,
	@location(0) @interpolate(flat) face_id: u32,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;

	// Reconstruct surface position from centroid + normal * depth
	let surface_pos = in.position + in.normal * in.depth;

	// Transform position to clip space
	let world_pos = (uniforms.model * vec4<f32>(surface_pos, 1.0)).xyz;
	out.position = uniforms.view_proj * vec4<f32>(world_pos, 1.0);

	// Output the face ID
	out.face_id = in.face_id;

	return out;
}
