struct VertexOutput {
	@builtin(position) position: vec4<f32>,
	@location(0) uv: vec2<f32>,
}

// Fullscreen triangle trick - no vertex buffer needed
@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
	var out: VertexOutput;
			
	// Generate fullscreen triangle vertices procedurally
	let x = f32((vertex_index << 1u) & 2u);
	let y = f32(vertex_index & 2u);
			
	out.position = vec4<f32>(x * 2.0 - 1.0, y * 2.0 - 1.0, 0.0, 1.0);
	out.uv = vec2<f32>(x, 1.0 - y);  // Flip Y for texture coordinates
			
	return out;
}
