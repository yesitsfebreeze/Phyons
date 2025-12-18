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

// Create or resize  depth buffer for compute shader depth testing
ensure_depth_buffer :: proc(width: u32, height: u32) -> bool {
	required_size := u64(width * height * size_of(u32))

	// Check if buffer exists and is correct size
	if state.buffers.depth_buffer != nil {
		current_size := wgpu.BufferGetSize(state.buffers.depth_buffer)
		if current_size == required_size {
			return true
		}
		// Release old buffer if size changed
		wgpu.BufferRelease(state.buffers.depth_buffer)
		state.buffers.depth_buffer = nil
	}

	// Create new buffer
	buffer_desc := wgpu.BufferDescriptor {
		label            = "Depth Buffer",
		size             = required_size,
		usage            = {.Storage, .CopyDst},
		mappedAtCreation = false,
	}
	state.buffers.depth_buffer = wgpu.DeviceCreateBuffer(state.gapi.device, &buffer_desc)
	if state.buffers.depth_buffer == nil {
		log_err("Failed to create depth buffer")
		return false
	}

	return true
}

// Clear depth buffer to max depth (0xFFFFFFFF = farthest)
clear_depth_buffer :: proc() {
	if state.buffers.depth_buffer == nil {
		return
	}

	buffer_size := wgpu.BufferGetSize(state.buffers.depth_buffer)
	pixel_count := buffer_size / size_of(u32)

	// Create temporary array filled with max u32
	clear_data := make([]u32, pixel_count)
	defer delete(clear_data)

	for i in 0 ..< pixel_count {
		clear_data[i] = 0xFFFFFFFF
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.depth_buffer,
		0,
		raw_data(clear_data),
		uint(buffer_size),
	)
}

// Create vertex buffer with given vertices
create_vertex_buffer :: proc(vertices: []Phyon) -> bool {
	if state.buffers.phyon_buffer != nil {
		wgpu.BufferRelease(state.buffers.phyon_buffer)
	}

	vertex_buffer_desc := wgpu.BufferDescriptor {
		label            = "Vertex Buffer",
		size             = u64(len(vertices) * size_of(Phyon)),
		usage            = {.Vertex, .CopyDst, .Storage},
		mappedAtCreation = false,
	}
	state.buffers.phyon_buffer = wgpu.DeviceCreateBuffer(state.gapi.device, &vertex_buffer_desc)
	if state.buffers.phyon_buffer == nil {
		log_err("Failed to create vertex buffer")
		return false
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.phyon_buffer,
		0,
		raw_data(vertices),
		uint(vertex_buffer_desc.size),
	)

	return true
}

// Create wireframe index buffer (line list)
create_index_buffer :: proc(indices: []u16) -> bool {
	if state.buffers.index_buffer != nil {
		wgpu.BufferRelease(state.buffers.index_buffer)
	}

	index_buffer_desc := wgpu.BufferDescriptor {
		label            = "Index Buffer",
		size             = u64(len(indices) * size_of(u16)),
		usage            = {.Index, .CopyDst},
		mappedAtCreation = false,
	}
	state.buffers.index_buffer = wgpu.DeviceCreateBuffer(state.gapi.device, &index_buffer_desc)
	if state.buffers.index_buffer == nil {
		log_err("Failed to create index buffer")
		return false
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.index_buffer,
		0,
		raw_data(indices),
		uint(index_buffer_desc.size),
	)

	state.buffers.index_count = u32(len(indices))
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
	if state.buffers.phyons != nil {
		delete(state.buffers.phyons)
	}
	if state.buffers.phyon_buffer != nil {
		wgpu.BufferRelease(state.buffers.phyon_buffer)
	}
	if state.buffers.index_buffer != nil {
		wgpu.BufferRelease(state.buffers.index_buffer)
	}
	if state.buffers.triangle_index_buffer != nil {
		wgpu.BufferRelease(state.buffers.triangle_index_buffer)
	}
	if state.buffers.depth_buffer != nil {
		wgpu.BufferRelease(state.buffers.depth_buffer)
	}
	if state.buffers.uniform_buffer != nil {
		wgpu.BufferRelease(state.buffers.uniform_buffer)
	}
}
