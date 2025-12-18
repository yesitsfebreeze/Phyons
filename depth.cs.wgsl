// Compute shader for processing rasterized data into final output

struct Uniforms {
	view_proj: mat4x4<f32>,
	model: mat4x4<f32>,
	time: f32,
	screen_width: f32,
	screen_height: f32,
}

struct Phyon {
	position: vec3<f32>,
	normal: vec3<f32>,
	depth: f32,
	opacity: f32,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

@group(0) @binding(1)
var rasterize_texture: texture_2d<u32>;

@group(0) @binding(2)
var<storage, read> phyons: array<Phyon>;

@group(0) @binding(3)
var<storage, read> indices: array<u32>;

@group(0) @binding(4)
var output_texture: texture_storage_2d<rgba32float, write>;

// Unpack a u32 into a float [0,1]
fn unpack_unorm(v: u32) -> f32 {
	return f32(v) / 65535.0;
}

// Get the three vertices of a triangle from the index buffer
fn get_triangle_vertices(triangle_id: u32) -> array<Phyon, 3> {
	let base_idx = triangle_id * 3u;
	let i0 = indices[base_idx + 0u];
	let i1 = indices[base_idx + 1u];
	let i2 = indices[base_idx + 2u];
	return array<Phyon, 3>(phyons[i0], phyons[i1], phyons[i2]);
}

// Interpolate normal using barycentric coordinates
fn interpolate_normal(verts: array<Phyon, 3>, bary: vec3<f32>) -> vec3<f32> {
	return normalize(verts[0].normal * bary.x + verts[1].normal * bary.y + verts[2].normal * bary.z);
}

// Interpolate depth using barycentric coordinates
fn interpolate_depth(verts: array<Phyon, 3>, bary: vec3<f32>) -> f32 {
	return verts[0].depth * bary.x + verts[1].depth * bary.y + verts[2].depth * bary.z;
}

@compute @workgroup_size(8, 8, 1)
fn cs_main(@builtin(global_invocation_id) global_id: vec3<u32>) {
	let pixel = vec2<i32>(global_id.xy);
	let dims = vec2<i32>(i32(uniforms.screen_width), i32(uniforms.screen_height));

	// Bounds check
	if (pixel.x >= dims.x || pixel.y >= dims.y) {
		return;
	}

	// Read data from rasterization pass
	// R = triangle_id, G = packed barycentric coords, A = 1 if valid pixel
	let tex_data = textureLoad(rasterize_texture, pixel, 0);

	// No geometry - clear background
	if (tex_data.a == 0u) {
		textureStore(output_texture, pixel, vec4<f32>(0.1, 0.1, 0.15, 1.0));
		return;
	}

	// Unpack triangle ID and barycentric coordinates
	let triangle_id = tex_data.r;
	let bary_packed = tex_data.g;
	let bary_x = unpack_unorm(bary_packed >> 16u);
	let bary_y = unpack_unorm(bary_packed & 0xFFFFu);
	let bary_z = 1.0 - bary_x - bary_y;
	let bary = vec3<f32>(bary_x, bary_y, bary_z);

	// Get the three vertices of this triangle
	let verts = get_triangle_vertices(triangle_id);

	// Interpolate normal at hit point
	let hit_normal = interpolate_normal(verts, bary);

	// Interpolate depth at hit point
	let hit_depth = interpolate_depth(verts, bary);

	// Simple lighting using interpolated normal
	let light_dir = normalize(vec3<f32>(1.0, 1.0, 1.0));
	let ndotl = max(dot(hit_normal, light_dir), 0.0);
	let ambient = 0.2;
	let diffuse = ndotl * 0.8;

	// Visualize depth with lighting
	let depth_vis = clamp(hit_depth, 0.0, 1.0);
	let color = vec3<f32>(depth_vis) * (ambient + diffuse);

	textureStore(output_texture, pixel, vec4<f32>(color, 1.0));
}
