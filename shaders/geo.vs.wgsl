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
	@location(0) inside: vec3<f32>,
	@location(1) reference: vec3<f32>,
}

struct VertexOutput {
	@builtin(position) surface: vec4<f32>,
	@location(0) world_normal: vec3<f32>,
	@location(1) depth: f32,
	@location(2) depth_point_ndc: vec3<f32>,
	// The projected depth point in NDC
	@location(3) inside_world: vec3<f32>,
	@location(4) surface_world: vec3<f32>,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;

	// Compute surface from inside + ref
	let surface = in.inside + in.reference;

	// Transform positions to world space
	let inside_world = (uniforms.model * vec4<f32>(in.inside, 1.0)).xyz;
	let surface_world = (uniforms.model * vec4<f32>(surface, 1.0)).xyz;

	// Normal is the normalized ref direction (inside to surface)
	let reference_world = (uniforms.model * vec4<f32>(in.reference, 0.0)).xyz;
	let world_normal = normalize(reference_world);
	let depth = length(reference_world);

	// Use surface position for rasterization (so triangles have area)
	out.surface = uniforms.view_proj * vec4<f32>(surface_world, 1.0);

	// Compute the depth point: inside + normal * depth = surface
	// This is the point we want to project to get the custom depth
	let depth_point = inside_world + world_normal * depth;
	let depth_point_clip = uniforms.view_proj * vec4<f32>(depth_point, 1.0);

	// Store NDC coordinates for the depth point (will interpolate across triangle)
	out.depth_point_ndc = depth_point_clip.xyz / depth_point_clip.w;

	out.world_normal = world_normal;
	out.depth = depth;
	out.inside_world = inside_world;
	out.surface_world = surface_world;

	return out;
}
