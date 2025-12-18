@group(0) @binding(0)
var output_texture: texture_2d<f32>;

@group(0) @binding(1)
var tex_sampler: sampler;

struct FragmentOutput {
	@location(0) color: vec4<f32>,
}

@fragment
fn fs_main(@location(0) uv: vec2<f32>) -> FragmentOutput {
	var out: FragmentOutput;
	out.color = textureSample(output_texture, tex_sampler, uv);
	return out;
}
