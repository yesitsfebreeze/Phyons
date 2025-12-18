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

// Create vertex buffer with given vertices
create_vertex_buffer :: proc(vertices: []Vertex) -> bool {
	if state.buffers.vertex_buffer != nil {
		wgpu.BufferRelease(state.buffers.vertex_buffer)
	}

	vertex_buffer_desc := wgpu.BufferDescriptor {
		label            = "Vertex Buffer",
		size             = u64(len(vertices) * size_of(Vertex)),
		usage            = {.Vertex, .CopyDst},
		mappedAtCreation = false,
	}
	state.buffers.vertex_buffer = wgpu.DeviceCreateBuffer(state.gapi.device, &vertex_buffer_desc)
	if state.buffers.vertex_buffer == nil {
		log_err("Failed to create vertex buffer")
		return false
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.vertex_buffer,
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
create_triangle_index_buffer :: proc(indices: []u16) -> bool {
	if state.buffers.triangle_index_buffer != nil {
		wgpu.BufferRelease(state.buffers.triangle_index_buffer)
	}

	tri_index_buffer_desc := wgpu.BufferDescriptor {
		label            = "Triangle Index Buffer",
		size             = u64(len(indices) * size_of(u16)),
		usage            = {.Index, .CopyDst},
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
	if state.buffers.vertex_buffer == nil || state.buffers.vertices == nil {
		return
	}

	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.vertex_buffer,
		0,
		raw_data(state.buffers.vertices),
		uint(len(state.buffers.vertices) * size_of(Vertex)),
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
	if state.buffers.vertices != nil {
		delete(state.buffers.vertices)
	}
	if state.buffers.vertex_buffer != nil {
		wgpu.BufferRelease(state.buffers.vertex_buffer)
	}
	if state.buffers.index_buffer != nil {
		wgpu.BufferRelease(state.buffers.index_buffer)
	}
	if state.buffers.triangle_index_buffer != nil {
		wgpu.BufferRelease(state.buffers.triangle_index_buffer)
	}
	if state.buffers.uniform_buffer != nil {
		wgpu.BufferRelease(state.buffers.uniform_buffer)
	}
}
