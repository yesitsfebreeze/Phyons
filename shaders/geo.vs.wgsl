struct Uniforms {
	view_proj: mat4x4<f32>,
	model: mat4x4<f32>,
	time: f32,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

struct VertexInput {
	@builtin(vertex_index) vertex_index: u32,
	@location(0) inside: vec3<f32>,
	@location(1) surface: vec3<f32>,
	@location(2) depth: f32,
}

struct VertexOutput {
	@builtin(position) position: vec4<f32>,
	@location(0) world_normal: vec3<f32>,
	@location(1) depth: f32,
	@location(2) view_depth: f32,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;

	// Use inside position for rasterization (skeletal interior)
	let inside_world = uniforms.model * vec4<f32>(in.inside, 1.0);
	out.position = uniforms.view_proj * inside_world;

	// Compute normal from inside->surface direction
	let to_surface = in.surface - in.inside;
	let world_normal = normalize((uniforms.model * vec4<f32>(to_surface, 0.0)).xyz);
	out.world_normal = world_normal;

	out.depth = in.depth;
	out.view_depth = out.position.z / out.position.w;

	return out;
}
