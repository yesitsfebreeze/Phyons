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
	@location(0) position: vec3<f32>,
	@location(1) normal: vec3<f32>,
	@location(2) depth: f32,
	@location(3) opacity: f32,
	@location(4) triangle_id: u32,
	@location(5) vertex_in_tri: u32,
}

struct VertexOutput {
	@builtin(position) position: vec4<f32>,
	@location(0) @interpolate(flat) triangle_id: u32,
	@location(1) bary: vec3<f32>,  // Barycentric coordinates (will be interpolated)
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;

	// Reconstruct surface position from centroid + normal * depth
	let surface_pos = in.position + in.normal * in.depth;

	// Transform position to clip space
	let world_pos = (uniforms.model * vec4<f32>(surface_pos, 1.0)).xyz;
	out.position = uniforms.view_proj * vec4<f32>(world_pos, 1.0);

	// Triangle ID from vertex attribute
	out.triangle_id = in.triangle_id;

	// Barycentric coordinates: each vertex of a triangle gets (1,0,0), (0,1,0), or (0,0,1)
	// The rasterizer will interpolate these across the triangle surface
	out.bary = vec3<f32>(
		f32(in.vertex_in_tri == 0u),
		f32(in.vertex_in_tri == 1u),
		f32(in.vertex_in_tri == 2u)
	);

	return out;
}
