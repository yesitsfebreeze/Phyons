// Compute shader: Read interpolated phyon data, reconstruct smooth surface, reproject

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
@group(0) @binding(1)
var inside_depth_tex: texture_2d<f32>;
// xyz=inside, w=depth
@group(0) @binding(2)
var normal_material_tex: texture_2d<f32>;
// xyz=normal, w=material
@group(0) @binding(3)
var output_tex: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4)
var<storage, read_write> depth_buffer: array<atomic<u32>>;

fn depth_to_uint(depth: f32) -> u32 {
	// Convert depth to u32 for atomic comparison (larger = farther)
	return u32(clamp(depth, 0.0, 1.0) * 4294967295.0);
}

@compute @workgroup_size(8, 8)
fn cs_main(@builtin(global_invocation_id) global_id: vec3<u32>) {
	let screen_size = vec2<u32>(u32(uniforms.screen_width), u32(uniforms.screen_height));

	if (global_id.x >= screen_size.x || global_id.y >= screen_size.y) {
		return;
	}

	let pixel = vec2<i32>(global_id.xy);

	// Read interpolated phyon data from rasterize pass
	let inside_depth = textureLoad(inside_depth_tex, pixel, 0);
	let normal_material = textureLoad(normal_material_tex, pixel, 0);

	let material_id = normal_material.w;

	// Skip background pixels (material_id == 0)
	if (material_id < 0.5) {
		return;
	}

	// Extract interpolated values
	let inside = inside_depth.xyz;
	let phyon_depth = inside_depth.w;
	let normal = normalize(normal_material.xyz);

	// Reconstruct the SMOOTH surface position
	// This is where the magic happens - the interpolated normal creates curvature!
	let outside = inside + normal * phyon_depth;

	// Project smooth surface point to screen space
	let clip = uniforms.view_proj * vec4<f32>(outside, 1.0);
	let ndc = clip.xyz / clip.w;

	// Convert to pixel coordinates
	let target_x = i32((ndc.x * 0.5 + 0.5) * uniforms.screen_width);
	let target_y = i32((1.0 - (ndc.y * 0.5 + 0.5)) * uniforms.screen_height);

	// Bounds check
	if (target_x < 0 || target_x >= i32(screen_size.x) || target_y < 0 || target_y >= i32(screen_size.y)) {
		return;
	}

	// Depth for the reprojected point (in NDC, 0 = near, 1 = far)
	let reprojected_depth = ndc.z * 0.5 + 0.5;

	// Atomic depth test at TARGET pixel
	let target_idx = u32(target_y) * screen_size.x + u32(target_x);
	let new_depth_uint = depth_to_uint(reprojected_depth);

	// Try to write if we're closer (atomicMin for depth test)
	let old_depth = atomicMin(&depth_buffer[target_idx], new_depth_uint);

	if (new_depth_uint <= old_depth) {
		// We won the depth test - compute lighting and write color

		// Simple Blinn-Phong lighting
		let light_dir = normalize(vec3<f32>(1.0, 1.0, 1.0));
		let view_dir = normalize(uniforms.camera_pos - outside);

		let ndotl = max(dot(normal, light_dir), 0.0);
		let ambient = 0.15;
		let diffuse = ndotl * 0.7;

		let half_vec = normalize(light_dir + view_dir);
		let spec = pow(max(dot(normal, half_vec), 0.0), 32.0) * 0.3;

		let base_color = vec3<f32>(0.8, 0.6, 0.4);
		let color = base_color * (ambient + diffuse) + vec3<f32>(spec);

		textureStore(output_tex, vec2<i32>(target_x, target_y), vec4<f32>(color, 1.0));
	}
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
