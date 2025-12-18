package phyons

import "vendor:wgpu"

init_buffers :: proc() -> bool {
	// Create uniform buffer
	uniform_buffer_desc := wgpu.BufferDescriptor {
		label            = "Uniform Buffer",
		size             = size_of(Uniforms),
		usage            = {.Uniform, .CopyDst},
		mappedAtCreation = false,
	}
	state.buffers.uniform_buffer = wgpu.DeviceCreateBuffer(state.gapi.device, &uniform_buffer_desc)
	if state.buffers.uniform_buffer == nil {
		log_err("Failed to create uniform buffer")
		return false
	}

	return true
}

// Create split phyon buffers (inside + outside)
create_split_phyon_buffers :: proc(inside: []Phyon_Inside, outside: []Phyon_Outside) -> bool {
	// Release old buffers
	if state.buffers.inside_phyon_buffer != nil {
		wgpu.BufferRelease(state.buffers.inside_phyon_buffer)
	}
	if state.buffers.outside_phyon_buffer != nil {
		wgpu.BufferRelease(state.buffers.outside_phyon_buffer)
	}

	// Create inside phyon buffer
	inside_buffer_desc := wgpu.BufferDescriptor {
		label            = "Inside Phyon Buffer",
		size             = u64(len(inside) * size_of(Phyon_Inside)),
		usage            = {.Storage, .CopyDst},
		mappedAtCreation = false,
	}
	state.buffers.inside_phyon_buffer = wgpu.DeviceCreateBuffer(
		state.gapi.device,
		&inside_buffer_desc,
	)
	if state.buffers.inside_phyon_buffer == nil {
		log_err("Failed to create inside phyon buffer")
		return false
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.inside_phyon_buffer,
		0,
		raw_data(inside),
		uint(inside_buffer_desc.size),
	)

	// Create outside phyon buffer
	outside_buffer_desc := wgpu.BufferDescriptor {
		label            = "Outside Phyon Buffer",
		size             = u64(len(outside) * size_of(Phyon_Outside)),
		usage            = {.Storage, .CopyDst},
		mappedAtCreation = false,
	}
	state.buffers.outside_phyon_buffer = wgpu.DeviceCreateBuffer(
		state.gapi.device,
		&outside_buffer_desc,
	)
	if state.buffers.outside_phyon_buffer == nil {
		log_err("Failed to create outside phyon buffer")
		return false
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.outside_phyon_buffer,
		0,
		raw_data(outside),
		uint(outside_buffer_desc.size),
	)

	return true
}

// Create volume info buffer
create_volume_info_buffer :: proc(volume_infos: []VolumeGPU) -> bool {
	if state.buffers.volume_info_buffer != nil {
		wgpu.BufferRelease(state.buffers.volume_info_buffer)
	}

	if len(volume_infos) == 0 {
		return true
	}

	buffer_desc := wgpu.BufferDescriptor {
		label            = "Volume Info Buffer",
		size             = u64(len(volume_infos) * size_of(VolumeGPU)),
		usage            = {.Storage, .CopyDst},
		mappedAtCreation = false,
	}
	state.buffers.volume_info_buffer = wgpu.DeviceCreateBuffer(state.gapi.device, &buffer_desc)
	if state.buffers.volume_info_buffer == nil {
		log_err("Failed to create volume info buffer")
		return false
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.volume_info_buffer,
		0,
		raw_data(volume_infos),
		uint(buffer_desc.size),
	)

	return true
}

// Create draw order buffer (for GPU sorting)
create_draw_order_buffer :: proc(max_volumes: u32) -> bool {
	if state.buffers.draw_order_buffer != nil {
		wgpu.BufferRelease(state.buffers.draw_order_buffer)
	}

	if max_volumes == 0 {
		return true
	}

	buffer_desc := wgpu.BufferDescriptor {
		label            = "Draw Order Buffer",
		size             = u64(max_volumes * size_of(u32)),
		usage            = {.Storage, .CopyDst},
		mappedAtCreation = false,
	}
	state.buffers.draw_order_buffer = wgpu.DeviceCreateBuffer(state.gapi.device, &buffer_desc)
	if state.buffers.draw_order_buffer == nil {
		log_err("Failed to create draw order buffer")
		return false
	}

	return true
}

// Create triangle index buffer (for geometry pass)
create_triangle_index_buffer :: proc(indices: []u32) -> bool {
	if state.buffers.triangle_index_buffer != nil {
		wgpu.BufferRelease(state.buffers.triangle_index_buffer)
	}

	tri_index_buffer_desc := wgpu.BufferDescriptor {
		label            = "Triangle Index Buffer",
		size             = u64(len(indices) * size_of(u32)),
		usage            = {.Index, .CopyDst, .Storage},
		mappedAtCreation = false,
	}
	state.buffers.triangle_index_buffer = wgpu.DeviceCreateBuffer(
		state.gapi.device,
		&tri_index_buffer_desc,
	)
	if state.buffers.triangle_index_buffer == nil {
		log_err("Failed to create triangle index buffer")
		return false
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.triangle_index_buffer,
		0,
		raw_data(indices),
		uint(tri_index_buffer_desc.size),
	)

	state.buffers.triangle_index_count = u32(len(indices))
	return true
}

// Update vertex buffer data on GPU
update_vertex_buffer :: proc() {
	if state.buffers.phyon_buffer == nil || state.buffers.phyons == nil {
		return
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.phyon_buffer,
		0,
		raw_data(state.buffers.phyons),
		uint(len(state.buffers.phyons) * size_of(Phyon)),
	)
}

// Update uniform buffer data on GPU
update_uniform_buffer :: proc(uniforms: ^Uniforms) {
	if state.buffers.uniform_buffer == nil {
		return
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.uniform_buffer,
		0,
		uniforms,
		size_of(Uniforms),
	)
}

cleanup_buffers :: proc() {
	// CPU-side data
	if state.buffers.inside_phyons != nil do delete(state.buffers.inside_phyons)
	if state.buffers.outside_phyons != nil do delete(state.buffers.outside_phyons)
	if state.buffers.volume_infos != nil do delete(state.buffers.volume_infos)
	if state.buffers.phyons != nil do delete(state.buffers.phyons)

	// GPU buffers
	if state.buffers.inside_phyon_buffer != nil do wgpu.BufferRelease(state.buffers.inside_phyon_buffer)
	if state.buffers.outside_phyon_buffer != nil do wgpu.BufferRelease(state.buffers.outside_phyon_buffer)
	if state.buffers.volume_info_buffer != nil do wgpu.BufferRelease(state.buffers.volume_info_buffer)
	if state.buffers.draw_order_buffer != nil do wgpu.BufferRelease(state.buffers.draw_order_buffer)
	if state.buffers.phyon_buffer != nil do wgpu.BufferRelease(state.buffers.phyon_buffer)
	if state.buffers.triangle_index_buffer != nil do wgpu.BufferRelease(state.buffers.triangle_index_buffer)
	if state.buffers.depth_buffer != nil do wgpu.BufferRelease(state.buffers.depth_buffer)
	if state.buffers.uniform_buffer != nil do wgpu.BufferRelease(state.buffers.uniform_buffer)
}

// Create or resize software depth buffer for compute shader
create_depth_buffer :: proc(width: u32, height: u32) -> bool {
	if state.buffers.depth_buffer != nil {
		wgpu.BufferRelease(state.buffers.depth_buffer)
	}

	// One u32 per pixel for atomic depth testing
	buffer_size := u64(width * height * size_of(u32))

	depth_buffer_desc := wgpu.BufferDescriptor {
		label            = "Software Depth Buffer",
		size             = buffer_size,
		usage            = {.Storage, .CopyDst},
		mappedAtCreation = false,
	}
	state.buffers.depth_buffer = wgpu.DeviceCreateBuffer(state.gapi.device, &depth_buffer_desc)
	if state.buffers.depth_buffer == nil {
		log_err("Failed to create software depth buffer")
		return false
	}

	return true
}
