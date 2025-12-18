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
	@location(0) position: vec3<f32>,  // inside/anchor point
	@location(1) depth: f32,           // distance to surface
	@location(2) normal: vec3<f32>,    // surface direction
	@location(3) opacity: f32,
}

struct VertexOutput {
	@builtin(position) clip_position: vec4<f32>,
	// These will be GPU-interpolated across the triangle!
	@location(0) inside: vec3<f32>,    // Anchor point (interpolated)
	@location(1) normal: vec3<f32>,    // Surface direction (interpolated)
	@location(2) depth: f32,           // Distance to surface (interpolated)
	@location(3) material_id: f32,     // Material identifier
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;

	// Reconstruct surface position for rasterization (flat triangles for visibility/depth sorting)
	let surface_pos = in.position + in.normal * in.depth;

	out.clip_position = uniforms.view_proj * vec4<f32>(surface_pos, 1.0);
	
	// Pass phyon attributes - GPU will interpolate these across the triangle
	out.inside = in.position;
	out.normal = in.normal;
	out.depth = in.depth;
	out.material_id = 1.0; // Could come from vertex data

	return out;
}
