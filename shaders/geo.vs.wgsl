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
	@builtin(position) surface: vec4<f32>,
	@location(0) world_normal: vec3<f32>,
	@location(1) depth: f32,
	@location(2) depth_point_ndc: vec3<f32>,
	// The projected depth point in NDC
	@location(3) w_inside: vec3<f32>,
	@location(4) w_surface: vec3<f32>,
	@location(5) opacity: f32,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;

	// Compute surface from position + normal * depth
	let surface = in.position + in.normal * (in.depth * 0.25);

	// Transform positions to world space
	let w_position = (uniforms.model * vec4<f32>(in.position, 1.0)).xyz;
	let w_surface = (uniforms.model * vec4<f32>(surface, 1.0)).xyz;

	// Transform normal (direction - no translation, w=0)
	let w_normal = normalize((uniforms.model * vec4<f32>(in.normal, 0.0)).xyz);
	// Depth may scale with transform, recompute from transformed positions
	let w_depth = length(w_surface - w_position);

	// Use surface position for rasterization (so triangles have area)
	out.surface = uniforms.view_proj * vec4<f32>(w_surface, 1.0);

	// Compute the depth point: position + normal * depth = surface
	// This is the point we want to project to get the custom depth
	let depth_point = w_position + w_normal * w_depth;
	let depth_point_clip = uniforms.view_proj * vec4<f32>(depth_point, 1.0);

	// Store NDC coordinates for the depth point (will interpolate across triangle)
	out.depth_point_ndc = depth_point_clip.xyz / depth_point_clip.w;

	out.world_normal = w_normal;
	out.depth = w_depth;
	out.w_inside = w_position;
	out.w_surface = w_surface;
	out.opacity = in.opacity;

	return out;
}
