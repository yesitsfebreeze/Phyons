// Pure compute shader rasterizer
// TODO: Implement full triangle rasterization in Phase 2

struct Uniforms {
	view_proj: mat4x4<f32>,
	inv_view_proj: mat4x4<f32>,
	view: mat4x4<f32>,
	camera_pos: vec3<f32>,
	time: f32,
	screen_width: f32,
	screen_height: f32,
	volume_count: u32,
	_pad: u32,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;
@group(0) @binding(1)
var output_tex: texture_storage_2d<rgba32float, write>;
@group(0) @binding(2)
var<storage, read_write> depth_buffer: array<atomic<u32>>;

fn depth_to_uint(depth: f32) -> u32 {
	return u32(clamp(depth, 0.0, 1.0) * 4294967295.0);
}

// Main drawing pass - placeholder until full rasterization is implemented
@compute @workgroup_size(8, 8)
fn cs_main(@builtin(global_invocation_id) global_id: vec3<u32>) {
	let screen_size = vec2<u32>(u32(uniforms.screen_width), u32(uniforms.screen_height));

	if (global_id.x >= screen_size.x || global_id.y >= screen_size.y) {
		return;
	}

	let pixel = vec2<i32>(global_id.xy);

	// Placeholder: draw a simple gradient to verify compute shader works
	let uv = vec2<f32>(f32(global_id.x) / uniforms.screen_width, f32(global_id.y) / uniforms.screen_height);

	// Animated gradient based on time
	let t = uniforms.time * 0.5;
	let color = vec3<f32>(0.5 + 0.5 * sin(uv.x * 6.28 + t), 0.5 + 0.5 * sin(uv.y * 6.28 + t * 1.3), 0.5 + 0.5 * sin((uv.x + uv.y) * 3.14 + t * 0.7));

	textureStore(output_tex, pixel, vec4<f32>(color * 0.3, 1.0));
}

// Clear pass - resets output texture and depth buffer
@compute @workgroup_size(8, 8)
fn cs_clear(@builtin(global_invocation_id) global_id: vec3<u32>) {
	let screen_size = vec2<u32>(u32(uniforms.screen_width), u32(uniforms.screen_height));

	if (global_id.x >= screen_size.x || global_id.y >= screen_size.y) {
		return;
	}

	let pixel = vec2<i32>(global_id.xy);
	let idx = global_id.y * screen_size.x + global_id.x;

	// Clear output to background color
	textureStore(output_tex, pixel, vec4<f32>(0.05, 0.05, 0.08, 1.0));

	// Clear depth to max (far)
	atomicStore(&depth_buffer[idx], 0xFFFFFFFFu);
}
