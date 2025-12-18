struct Uniforms {
	view_proj: mat4x4<f32>,
	model: mat4x4<f32>,
	time: f32,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

struct VertexInput {
	@builtin(vertex_index) vertex_index: u32,
	@location(0) position: vec3<f32>,
	@location(1) color: vec3<f32>,
	@location(2) reference_centroid: vec3<f32>,
	@location(3) normal: vec3<f32>,
	@location(4) material_id: f32,
	@location(5) opacity: f32,
	@location(6) distance_to_center: f32,
}

struct VertexOutput {
	@builtin(position) position: vec4<f32>,
	@location(0) world_normal: vec3<f32>,
	@location(1) material_id: f32,
	@location(2) opacity: f32,
	@location(3) distance_to_center: f32,
	@location(4) view_depth: f32,
	@location(5) surface_depth: f32,
	// Depth of interpolated surface position
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;

	// Interior position (skeleton) - used for rasterization/visibility
	let interior_world = uniforms.model * vec4<f32>(in.position, 1.0);
	out.position = uniforms.view_proj * interior_world;

	// Surface position = interior + reference_centroid displacement
	let surface_pos = in.position + in.reference_centroid * 0.5;
	let surface_world = uniforms.model * vec4<f32>(surface_pos, 1.0);
	let surface_clip = uniforms.view_proj * surface_world;

	// Transform normal to world space (assuming uniform scale)
	let world_normal = (uniforms.model * vec4<f32>(in.normal, 0.0)).xyz;
	out.world_normal = normalize(world_normal);

	out.material_id = in.material_id;
	out.opacity = in.opacity;
	out.distance_to_center = in.distance_to_center;
	out.view_depth = out.position.z / out.position.w;
	// Interior depth (normalized)
	out.surface_depth = surface_clip.z / surface_clip.w;
	// Surface depth for frag_depth

	return out;
}
