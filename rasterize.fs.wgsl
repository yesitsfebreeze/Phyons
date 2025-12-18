struct FragmentInput {
	@builtin(position) frag_coord: vec4<f32>,
	@location(0) @interpolate(flat) triangle_id: u32,
	@location(1) bary: vec3<f32>,
}

struct FragmentOutput {
	@location(0) data: vec4<u32>,
}

// Pack a float [0,1] into a u32 with high precision
fn pack_unorm(v: f32) -> u32 {
	return u32(clamp(v, 0.0, 1.0) * 65535.0);
}

@fragment
fn fs_main(in: FragmentInput) -> FragmentOutput {
	var out: FragmentOutput;

	// R: triangle_id
	// G: packed bary.x and bary.y (16 bits each) - bary.z can be reconstructed as 1-x-y
	// B: unused (available for future use)
	// A: 1 to indicate valid pixel
	let bary_packed = (pack_unorm(in.bary.x) << 16u) | pack_unorm(in.bary.y);

	out.data = vec4<u32>(in.triangle_id, bary_packed, 0u, 1u);
	return out;
}
