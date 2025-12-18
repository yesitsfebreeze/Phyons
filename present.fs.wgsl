// Fragment shader for displaying the depth buffer

@group(0) @binding(0)
var output_texture: texture_2d<f32>;

@group(0) @binding(1)
var texture_sampler: sampler;

@fragment
fn fs_main(@location(0) uv: vec2<f32>) -> @location(0) vec4<f32> {
	let value = textureSample(output_texture, texture_sampler, uv);
	return value;
}
