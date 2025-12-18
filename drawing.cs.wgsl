// Compute shader for processing rasterized data into final output

struct Uniforms {
	view_proj: mat4x4<f32>,
	model: mat4x4<f32>,
	time: f32,
	screen_width: f32,
	screen_height: f32,
	triangle_count: f32,
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
var rasterize_texture: texture_2d<f32>;

@group(0) @binding(2)
var<storage, read> phyons: array<Phyon>;

@group(0) @binding(3)
var<storage, read> indices: array<u32>;

@group(0) @binding(4)
var output_texture: texture_storage_2d<rgba32float, write>;

fn interp_phyon(data: vec4<f32>) -> Phyon {
	let id = u32(round(data.a * uniforms.triangle_count));
	let bary = data.rgb;
	let p0 = phyons[indices[id * 3u + 0u]];
	let p1 = phyons[indices[id * 3u + 1u]];
	let p2 = phyons[indices[id * 3u + 2u]];

	var phyon = Phyon();
	phyon.position = mat3x3<f32>(p0.position, p1.position, p2.position) * bary;
	phyon.normal = normalize(mat3x3<f32>(p0.normal, p1.normal, p2.normal) * bary);
	phyon.depth = p0.depth * bary.x + p1.depth * bary.y + p2.depth * bary.z;

	return phyon;
}

@compute @workgroup_size(8, 8, 1)
fn cs_main(@builtin(global_invocation_id) global_id: vec3<u32>) {
	let data = vec2<i32>(global_id.xy);
	let dims = vec2<i32>(i32(uniforms.screen_width), i32(uniforms.screen_height));

	// Bounds check
	if (data.x >= dims.x || data.y >= dims.y) {
		return;
	}

	let data_tex = textureLoad(rasterize_texture, data, 0);

	if (data_tex.a < 0.0) {
		textureStore(output_texture, data, vec4<f32>(0.0, 0.0, 0.0, 0.0));
		return;
	}

	let phyon = interp_phyon(data_tex);
	let surface = phyon.position + phyon.normal * phyon.depth;

	// now we must project the position to screen space, so we can write
	// the correct pixel position

	textureStore(output_texture, data, vec4<f32>(1.0, 0.0, 0.0, 1.0));
}
