// Fullscreen quad vertex shader for displaying textures

struct VertexOutput {
	@builtin(position) position: vec4<f32>,
	@location(0) uv: vec2<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
	// Generate fullscreen triangle (covers clip space)
	// Vertex 0: (-1, -1), Vertex 1: (3, -1), Vertex 2: (-1, 3)
	var out: VertexOutput;
	let x = f32(i32(vertex_index & 1u) * 2 - 1);
	let y = f32(i32(vertex_index >> 1u) * 2 - 1);

	// Use oversized triangle for fullscreen coverage
	let pos_x = f32(vertex_index & 1u) * 4.0 - 1.0;
	let pos_y = f32(vertex_index >> 1u) * 4.0 - 1.0;

	out.position = vec4<f32>(pos_x, pos_y, 0.0, 1.0);
	out.uv = vec2<f32>((pos_x + 1.0) * 0.5, (1.0 - pos_y) * 0.5);

	return out;
}
