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
}

struct VertexOutput {
	@builtin(position) position: vec4<f32>,
	@location(0) @interpolate(flat) idx: u32,
	@location(1) barycentrics: vec3<f32>,
	// Interpolated across triangle
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
	var out: VertexOutput;

	// Reconstruct surface position from centroid + normal * depth
	let surface_pos = in.position + in.normal * in.depth;

	// Transform position to clip space
	let world_pos = (uniforms.model * vec4<f32>(surface_pos, 1.0)).xyz;
	out.position = uniforms.view_proj * vec4<f32>(world_pos, 1.0);

	// Pass vertex_index (fragment shader derives triangle ID as idx / 3)
	out.idx = in.vertex_index;

	// Output corner barycentrics - GPU interpolates these across the triangle
	let vert_in_tri = in.vertex_index % 3u;
	switch vert_in_tri {
		case 0u : {
			out.barycentrics = vec3<f32>(1.0, 0.0, 0.0);
		}
		case 1u : {
			out.barycentrics = vec3<f32>(0.0, 1.0, 0.0);
		}
		default : {
			out.barycentrics = vec3<f32>(0.0, 0.0, 1.0);
		}
	}

	return out;
}
