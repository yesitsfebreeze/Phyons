struct Uniforms {
	view_proj: mat4x4<f32>,
	model: mat4x4<f32>,
	time: f32,
	screen_width: f32,
	screen_height: f32,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

@group(0) @binding(1)
var custom_depth_texture: texture_storage_2d<r32float, write>;

struct FragmentInput {
	@builtin(position) frag_coord: vec4<f32>,
	@location(0) world_normal: vec3<f32>,
	@location(1) depth: f32,
	@location(2) depth_point_ndc: vec3<f32>,
	@location(3) inside_world: vec3<f32>,
	@location(4) surface_world: vec3<f32>,
}

struct FragmentOutput {
	@location(0) color: vec4<f32>,
}

@fragment
fn fs_main(in: FragmentInput) -> FragmentOutput {
	var out: FragmentOutput;

	// Convert depth point from NDC to screen coordinates
	let depth_screen_x = (in.depth_point_ndc.x * 0.5 + 0.5) * uniforms.screen_width;
	let depth_screen_y = (1.0 - (in.depth_point_ndc.y * 0.5 + 0.5)) * uniforms.screen_height;

	// Convert to integer pixel coordinates
	let pixel_x = i32(depth_screen_x);
	let pixel_y = i32(depth_screen_y);

	// Check bounds and write 1.0 to the custom depth buffer at that location
	if (pixel_x >= 0 && pixel_x < i32(uniforms.screen_width) && pixel_y >= 0 && pixel_y < i32(uniforms.screen_height)) {
		// Write the depth value (normalized 0-1 from NDC z)
		let depth_value = in.depth_point_ndc.z * 0.5 + 0.5;
		textureStore(custom_depth_texture, vec2<i32>(pixel_x, pixel_y), vec4<f32>(depth_value, 0.0, 0.0, 1.0));
	}

	// Output the depth visualization as the color
	// Use the depth point's z value for visualization
	let depth_normalized = in.depth_point_ndc.z * 0.5 + 0.5;
	out.color = vec4<f32>(depth_normalized, depth_normalized, depth_normalized, 1.0);

	return out;
}
