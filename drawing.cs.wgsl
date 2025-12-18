// Compute shader for processing rasterized data into final output

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

struct Phyon {
	position: vec3<f32>,
	normal: vec3<f32>,
	depth: f32,
	opacity: f32,
}

struct Surface {
	inside: vec3<f32>,
	outside: vec3<f32>,
	normal: vec3<f32>,
	depth: f32,
	color: vec3<f32>,
}

@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

@group(0) @binding(1)
var rasterize_texture: texture_2d<f32>;

@group(0) @binding(2)
var<storage, read> phyons: array<Phyon>;

@group(0) @binding(3)
var<storage, read> indices: array<u32>;

@group(0) @binding(4)
var output_texture: texture_storage_2d<rgba32float, write>;

@group(0) @binding(5)
var<storage, read_write> depth_buffer: array<atomic<u32>>;

// Clear entry point - clears both depth buffer and output texture
@compute @workgroup_size(8, 8, 1)
fn cs_clear(@builtin(global_invocation_id) global_id: vec3<u32>) {
	let pixel = vec2<i32>(global_id.xy);
	let dims = vec2<i32>(i32(uniforms.screen_width), i32(uniforms.screen_height));

	if (pixel.x >= dims.x || pixel.y >= dims.y) {
		return;
	}

	// Clear depth buffer to max depth (farthest)
	let idx = pixel_to_index(pixel, dims.x);
	atomicStore(&depth_buffer[idx], 0xFFFFFFFFu);

	// Clear output texture to black
	textureStore(output_texture, pixel, vec4<f32>(0.0, 0.0, 0.0, 0.0));
}

// Get linear index for depth buffer
fn pixel_to_index(pixel: vec2<i32>, width: i32) -> u32 {
	return u32(pixel.y * width + pixel.x);
}

// Atomic depth test using bitcast (works because positive floats sort correctly as u32)
// Returns true if we won the depth test (we're closer than existing depth)
fn depth_test(pixel: vec2<i32>, depth: f32, width: i32) -> bool {
	let idx = pixel_to_index(pixel, width);
	let depth_bits = bitcast<u32>(depth);
	let old_bits = atomicMin(&depth_buffer[idx], depth_bits);
	return depth_bits <= old_bits;
}

// Get camera ray direction for a pixel
fn get_camera_ray(pixel: vec2<i32>) -> vec3<f32> {
	let ndc_x = (f32(pixel.x) + 0.5) / uniforms.screen_width * 2.0 - 1.0;
	let ndc_y = 1.0 - (f32(pixel.y) + 0.5) / uniforms.screen_height * 2.0;

	let near_point = uniforms.inv_view_proj * vec4<f32>(ndc_x, ndc_y, 0.0, 1.0);
	let far_point = uniforms.inv_view_proj * vec4<f32>(ndc_x, ndc_y, 1.0, 1.0);

	let near = near_point.xyz / near_point.w;
	let far = far_point.xyz / far_point.w;

	return normalize(far - near);
}

// Ray-plane intersection, returns intersection point
fn ray_plane_intersect(ray_origin: vec3<f32>, ray_dir: vec3<f32>, plane_point: vec3<f32>, plane_normal: vec3<f32>) -> vec3<f32> {
	let denom = dot(plane_normal, ray_dir);
	if (abs(denom) < 0.0001) {
		return plane_point;
	}
	let t = dot(plane_point - ray_origin, plane_normal) / denom;
	return ray_origin + ray_dir * t;
}

// Compute barycentric coordinates for point p in triangle (a, b, c)
fn compute_barycentric(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>) -> vec3<f32> {
	let v0 = b - a;
	let v1 = c - a;
	let v2 = p - a;

	let d00 = dot(v0, v0);
	let d01 = dot(v0, v1);
	let d11 = dot(v1, v1);
	let d20 = dot(v2, v0);
	let d21 = dot(v2, v1);

	let denom = d00 * d11 - d01 * d01;
	if (abs(denom) < 0.0001) {
		return vec3<f32>(1.0, 0.0, 0.0);
	}

	let v = (d11 * d20 - d01 * d21) / denom;
	let w = (d00 * d21 - d01 * d20) / denom;
	let u = 1.0 - v - w;

	return vec3<f32>(u, v, w);
}

// Get surface position from phyon (centroid + normal * depth) - in MODEL space
fn get_surface_pos_model(p: Phyon) -> vec3<f32> {
	return p.position + p.normal * p.depth;
}

// Transform model space point to world space
fn model_to_world(point: vec3<f32>) -> vec3<f32> {
	return (uniforms.model * vec4<f32>(point, 1.0)).xyz;
}

// Transform model space normal to world space (using transpose of inverse for correct normal transform)
// For uniform scaling, this simplifies to just applying the model matrix's rotation
fn normal_to_world(n: vec3<f32>) -> vec3<f32> {
	// Extract the 3x3 rotation/scale part of model matrix
	// For correct normal transformation with non-uniform scale, we'd need inverse transpose
	// For now assuming uniform scale or no scale
	return normalize((uniforms.model * vec4<f32>(n, 0.0)).xyz);
}

// Get the 3 phyons for a face using the index buffer
fn get_face_phyons(face_id: u32) -> array<Phyon, 3> {
	let i0 = indices[face_id * 3u + 0u];
	let i1 = indices[face_id * 3u + 1u];
	let i2 = indices[face_id * 3u + 2u];
	return array<Phyon, 3>(phyons[i0], phyons[i1], phyons[i2]);
}

// Interpolate phyon from face ID using ray reconstruction
// Returns Surface with all positions in WORLD space
fn interp_phyon_from_face(pixel: vec2<i32>, face_id: u32) -> Surface {
	let tri = get_face_phyons(face_id);
	let p0 = tri[0];
	let p1 = tri[1];
	let p2 = tri[2];

	// Get surface positions in MODEL space
	let a_model = get_surface_pos_model(p0);
	let b_model = get_surface_pos_model(p1);
	let c_model = get_surface_pos_model(p2);

	// Transform to WORLD space for ray intersection
	let a = model_to_world(a_model);
	let b = model_to_world(b_model);
	let c = model_to_world(c_model);

	// Compute triangle normal in world space
	let tri_normal = normalize(cross(b - a, c - a));

	// Get ray through this pixel (world space)
	let ray_dir = get_camera_ray(pixel);
	let ray_origin = uniforms.camera_pos;

	// Intersect ray with triangle plane (world space)
	let hit_point = ray_plane_intersect(ray_origin, ray_dir, a, tri_normal);

	// Compute barycentric from hit point
	let bary = compute_barycentric(hit_point, a, b, c);

	let inside = p0.position * bary.x + p1.position * bary.y + p2.position * bary.z;
	let normal = normalize(p0.normal * bary.x + p1.normal * bary.y + p2.normal * bary.z);
	let depth = p0.depth * bary.x + p1.depth * bary.y + p2.depth * bary.z;
	let outside = inside + normal * depth;

	var result: Surface;
	result.inside = model_to_world(inside);
	result.outside = model_to_world(outside);
	result.normal = normal_to_world(normal);
	result.depth = depth;

	return result;
}

// Convert WORLD space point to screen pixel coordinates
fn world_to_screen(world_pos: vec3<f32>) -> vec2<i32> {
	let clip_pos = uniforms.view_proj * vec4<f32>(world_pos, 1.0);
	let ndc_pos = clip_pos.xyz / clip_pos.w;

	// NDC to screen - Y is flipped (screen Y=0 at top, NDC Y=1 at top)
	let screen_x = (ndc_pos.x * 0.5 + 0.5) * uniforms.screen_width;
	let screen_y = (1.0 - (ndc_pos.y * 0.5 + 0.5)) * uniforms.screen_height;

	return vec2<i32>(i32(screen_x), i32(screen_y));
}

// Get NDC depth for a WORLD space position (0 = near, 1 = far)
fn get_ndc_depth_world(world_pos: vec3<f32>) -> f32 {
	let clip_pos = uniforms.view_proj * vec4<f32>(world_pos, 1.0);
	return (clip_pos.z / clip_pos.w) * 0.5 + 0.5;
}

@compute @workgroup_size(8, 8, 1)
fn cs_main(@builtin(global_invocation_id) global_id: vec3<u32>) {
	let pixel = vec2<i32>(global_id.xy);
	let dims = vec2<i32>(i32(uniforms.screen_width), i32(uniforms.screen_height));

	if (pixel.x >= dims.x || pixel.y >= dims.y) {
		return;
	}

	// Load rasterized data: RGB = barycentrics, A = normalized face_id
	let data = textureLoad(rasterize_texture, pixel, 0);

	// Check if pixel is empty (alpha = 0 means no geometry)
	if (data.a <= 0.0) {
		return;
	}

	// Reconstruct face ID from normalized value
	let face_id = u32(round(data.a * uniforms.face_count)) - 1u;
	let bary = data.rgb;

	var color: vec3<f32> = vec3<f32>(0.0, 0.0, 0.0);

	let p0 = phyons[indices[face_id * 3u + 0u]];
	let p1 = phyons[indices[face_id * 3u + 1u]];
	let p2 = phyons[indices[face_id * 3u + 2u]];

	let inside = p0.position * bary.x + p1.position * bary.y + p2.position * bary.z;
	let normal = normalize(p0.normal * bary.x + p1.normal * bary.y + p2.normal * bary.z);
	let depth = p0.depth * bary.x + p1.depth * bary.y + p2.depth * bary.z;
	let outside = inside + normal * depth;

	textureStore(output_texture, pixel, vec4<f32>(normal, 1.0));
	// // Interpolated barycentrics from rasterizer

	// // Get the 3 phyons for this triangle
	// let tri = get_face_phyons(face_id);
	// let p0 = tri[0];
	// let p1 = tri[1];
	// let p2 = tri[2];

	// // Interpolate phyon attributes using barycentrics from rasterizer
	// let inside = p0.position * bary.x + p1.position * bary.y + p2.position * bary.z;
	// let normal = normalize(p0.normal * bary.x + p1.normal * bary.y + p2.normal * bary.z);
	// let depth = p0.depth * bary.x + p1.depth * bary.y + p2.depth * bary.z;
	// let outside = inside + normal * depth;

	// // Transform to world space
	// let outside_world = model_to_world(outside);
	// let normal_world = normal_to_world(normal);

	// // Reproject the reconstructed surface position to screen
	// let out_pixel = world_to_screen(outside_world);

	// // Bounds check for output pixel
	// if (out_pixel.x < 0 || out_pixel.x >= dims.x || out_pixel.y < 0 || out_pixel.y >= dims.y) {
	// 	return;
	// }

	// // Compute depth at the reconstructed surface position (world space)
	// let ndc_depth = get_ndc_depth_world(outside_world);

	// // Atomic depth test - only write if we're closer
	// if (!depth_test(out_pixel, ndc_depth, dims.x)) {
	// 	return;
	// }

	// // Simple lighting in WORLD space
	// let light_dir = normalize(vec3<f32>(1.0, 1.0, 1.0));
	// let ndotl = max(dot(normal_world, light_dir), 0.0);
	// let ambient = 0.2;
	// let diffuse = ndotl * 0.8;
	// let color = vec3<f32>(0.8, 0.6, 0.4) * (ambient + diffuse);

	// textureStore(output_texture, out_pixel, vec4<f32>(color, 1.0));
}
