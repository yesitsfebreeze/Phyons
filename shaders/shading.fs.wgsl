@group(0) @binding(0)
var gbuffer_normal: texture_2d<f32>;
@group(0) @binding(1)
var gbuffer_material: texture_2d<f32>;
@group(0) @binding(2)
var gbuffer_distance: texture_2d<f32>;
@group(0) @binding(3)
var depth_front: texture_depth_2d;
@group(0) @binding(4)
var depth_back: texture_depth_2d;
@group(0) @binding(5)
var tex_sampler: sampler;

struct FragmentInput {
	@location(0) uv: vec2<f32>,
}

@fragment
fn fs_main(in: FragmentInput) -> @location(0) vec4<f32> {
	// Sample G-buffers
	let normal_sample = textureSample(gbuffer_normal, tex_sampler, in.uv);
	let material_sample = textureSample(gbuffer_material, tex_sampler, in.uv);
	let distance_sample = textureSample(gbuffer_distance, tex_sampler, in.uv);

	// Sample depth textures
	let front_depth = textureSample(depth_front, tex_sampler, in.uv);
	let back_depth = textureSample(depth_back, tex_sampler, in.uv);

	// Debug: Depth buffer preview in top-right corner (25% of screen)
	let debug_size = 0.125;
	let debug_uv = (in.uv - vec2<f32>(1.0 - debug_size, 0.0)) / debug_size;
	if debug_uv.x >= 0.0 && debug_uv.x <= 1.0 && debug_uv.y >= 0.0 && debug_uv.y <= 1.0 {
		// Sample depth at the remapped UV
		let debug_depth = textureSample(depth_front, tex_sampler, debug_uv);
		// Linearize depth for better visualization (near=0.1, far=100.0)
		let near = 0.1;
		let far = 100.0;
		let linear_depth = near * far / (far - debug_depth * (far - near));
		// Normalize to visible range and invert (near=white, far=black)
		let normalized = 1.0 - clamp(linear_depth / 10.0, 0.0, 1.0);
		return vec4<f32>(vec3<f32>(normalized), 1.0);
	}

	// Decode normal from [0,1] to [-1,1] range
	let world_normal = normalize(normal_sample.rgb * 2.0 - 1.0);
	let opacity = normal_sample.a;

	let material_id = material_sample.r * 255.0;
	let distance_to_center = distance_sample.r;

	// Calculate thickness (SDF-like interval)
	let thickness = back_depth - front_depth;

	// Simple shading based on normal (directional light from top-right-front)
	let light_dir = normalize(vec3<f32>(0.5, 1.0, 0.5));
	let ndotl = max(dot(world_normal, light_dir), 0.0);
	let ambient = 0.2;
	let diffuse = ndotl * 0.8;

	// Material-based coloring
	var base_color: vec3<f32>;
	if material_id < 0.5 {
		base_color = vec3<f32>(0.3, 0.3, 0.4);
		// Inner layer - dark blue-gray
	}
	else {
		base_color = vec3<f32>(0.9, 0.85, 0.8);
		// Outer layer - warm white
	}

	// Modulate by distance to center for depth visualization
	let depth_factor = clamp(distance_to_center * 2.0, 0.0, 1.0);
	base_color = mix(base_color * 0.7, base_color, depth_factor);

	// Add thickness-based rim effect (SDF-like)
	let rim = smoothstep(0.0, 0.02, thickness) * 0.3;

	let final_color = base_color * (ambient + diffuse) + rim;

	// Background check (if no geometry was rendered)
	if opacity < 0.01 {
		return vec4<f32>(0.1, 0.1, 0.1, 1.0);
		// Background color
	}

	return vec4<f32>(final_color, 1.0);
}
