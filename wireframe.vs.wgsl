struct Uniforms {
	view_proj: mat4x4<f32>,
	model: mat4x4<f32>,
	time: f32,
}

@group(0) @binding(0) var<uniform> uniforms: Uniforms;

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
	@location(0) color: vec3<f32>,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;
	out.position = uniforms.view_proj * uniforms.model * vec4<f32>(in.position, 1.0);
	out.color = in.color;
	return out;
}
