// Compute shader for processing face IDs into depth/opacity information

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
var face_id_texture: texture_2d<u32>;

@group(0) @binding(2)
var<storage, read> phyons: array<Phyon>;

@group(0) @binding(3)
var<storage, read> indices: array<u32>;

@group(0) @binding(4)
var output_texture: texture_storage_2d<rgba32float, write>;

@compute @workgroup_size(8, 8, 1)
fn cs_main(@builtin(global_invocation_id) global_id: vec3<u32>) {
	let pixel = vec2<i32>(global_id.xy);
	let dims = vec2<i32>(i32(uniforms.screen_width), i32(uniforms.screen_height));

	// Bounds check
	if (pixel.x >= dims.x || pixel.y >= dims.y) {
		return;
	}

	// Read face ID from the rasterization pass
	// Face ID is stored in R channel, 0xFFFFFFFF means no face
	let face_id = textureLoad(face_id_texture, pixel, 0).r;

	// No face at this pixel - write clear values
	if (face_id == 0xFFFFFFFFu) {
		textureStore(output_texture, pixel, vec4<f32>(1.0, 0.0, 0.0, 0.0));
		return;
	}

	// Get the three vertex indices for this face
	let base_idx = face_id * 3u;
	let i0 = indices[base_idx + 0u];
	let i1 = indices[base_idx + 1u];
	let i2 = indices[base_idx + 2u];

	// Get the three phyons (vertices) for this face
	let p0 = phyons[i0];
	let p1 = phyons[i1];
	let p2 = phyons[i2];

	// Average the properties across the face
	let avg_depth = (p0.depth + p1.depth + p2.depth) / 3.0;
	let avg_opacity = (p0.opacity + p1.opacity + p2.opacity) / 3.0;

	// Compute depth points in world space (inside + normal * depth)
	let w_pos0 = (uniforms.model * vec4<f32>(p0.position, 1.0)).xyz;
	let w_pos1 = (uniforms.model * vec4<f32>(p1.position, 1.0)).xyz;
	let w_pos2 = (uniforms.model * vec4<f32>(p2.position, 1.0)).xyz;

	let w_norm0 = normalize((uniforms.model * vec4<f32>(p0.normal, 0.0)).xyz);
	let w_norm1 = normalize((uniforms.model * vec4<f32>(p1.normal, 0.0)).xyz);
	let w_norm2 = normalize((uniforms.model * vec4<f32>(p2.normal, 0.0)).xyz);

	// Average depth point position
	let avg_depth_point = (w_pos0 + w_norm0 * p0.depth + w_pos1 + w_norm1 * p1.depth + w_pos2 + w_norm2 * p2.depth) / 3.0;

	// Project to get depth value
	let clip = uniforms.view_proj * vec4<f32>(avg_depth_point, 1.0);
	let ndc_z = clip.z / clip.w;
	let depth_value = ndc_z * 0.5 + 0.5;

	// Write output:
	// R = depth from camera
	// G = depth value (same for now, could track max across frames)
	// B = opacity
	// A = 1.0 (valid pixel)
	textureStore(output_texture, pixel, vec4<f32>(depth_value, depth_value, avg_opacity, 1.0));
}
