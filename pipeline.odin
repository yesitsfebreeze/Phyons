package phyons

import "vendor:wgpu"

// Store bind group layouts for recreation
@(private = "file")
rasterize_bind_group_layout: wgpu.BindGroupLayout
@(private = "file")
compute_bind_group_layout: wgpu.BindGroupLayout

// shaders
@(private = "file")
rasterize_vertex_shader: wgpu.ShaderModule
@(private = "file")
rasterize_fragment_shader: wgpu.ShaderModule
@(private = "file")
compute_shader: wgpu.ShaderModule

init_pipeline :: proc() -> bool {
	// Get shader modules

	err := false

	rasterize_vertex_shader, err = get_shader("rasterize.vs")
	rasterize_fragment_shader, err = get_shader("rasterize.fs")
	compute_shader, err = get_shader("depth.cs")

	if err do return false

	// ==========================================================================
	// Create rasterize bind group layout (uniform buffer only - no storage texture)
	// ==========================================================================

	rasterize_bind_layout_entries := [1]wgpu.BindGroupLayoutEntry {
		{binding = 0, visibility = {.Vertex, .Fragment}, buffer = {type = .Uniform}},
	}
	rasterize_bind_layout_desc := wgpu.BindGroupLayoutDescriptor {
		label      = "Rasterize Bind Group Layout",
		entryCount = len(rasterize_bind_layout_entries),
		entries    = &rasterize_bind_layout_entries[0],
	}
	rasterize_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		state.gapi.device,
		&rasterize_bind_layout_desc,
	)

	// ==========================================================================
	// Create pipeline layout
	// ==========================================================================

	pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		label                = "Geometry Pipeline Layout",
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &rasterize_bind_group_layout,
	}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(state.gapi.device, &pipeline_layout_desc)
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	// ==========================================================================
	// Vertex attributes
	// ==========================================================================

	vertex_attributes := []wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0}, // position
		{format = .Float32x3, offset = 12, shaderLocation = 1}, // normal
		{format = .Float32, offset = 24, shaderLocation = 2}, // depth
		{format = .Float32, offset = 28, shaderLocation = 3}, // opacity
	}

	vertex_buffer_layout := wgpu.VertexBufferLayout {
		arrayStride    = size_of(Phyon),
		stepMode       = .Vertex,
		attributeCount = uint(len(vertex_attributes)),
		attributes     = raw_data(vertex_attributes),
	}

	// ==========================================================================
	// Create Rasterize Pipeline
	// ==========================================================================

	color_target := wgpu.ColorTargetState {
		format    = .R32Uint, // Output face ID as uint
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}

	fragment_state := wgpu.FragmentState {
		module      = rasterize_fragment_shader,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &color_target,
	}

	depth_stencil := wgpu.DepthStencilState {
		format            = .Depth24Plus,
		depthWriteEnabled = .True,
		depthCompare      = .Less,
	}

	pipeline_desc := wgpu.RenderPipelineDescriptor {
		label = "Rasterize Pipeline",
		layout = pipeline_layout,
		vertex = {
			module = rasterize_vertex_shader,
			entryPoint = "vs_main",
			bufferCount = 1,
			buffers = &vertex_buffer_layout,
		},
		fragment = &fragment_state,
		primitive = {topology = .TriangleList, cullMode = .Back, frontFace = .CCW},
		depthStencil = &depth_stencil,
		multisample = {count = 1, mask = ~u32(0)},
	}

	state.pipelines.rasterize_pipeline = wgpu.DeviceCreateRenderPipeline(
		state.gapi.device,
		&pipeline_desc,
	)
	if state.pipelines.rasterize_pipeline == nil {
		log_err("Failed to create rasterize pipeline")
		return false
	}

	// ==========================================================================
	// Create Compute Bind Group Layout
	// ==========================================================================
	compute_bind_entries := [5]wgpu.BindGroupLayoutEntry {
		// Uniforms
		{binding = 0, visibility = {.Compute}, buffer = {type = .Uniform}},
		// Face ID texture (read)
		{
			binding = 1,
			visibility = {.Compute},
			texture = {sampleType = .Uint, viewDimension = ._2D},
		},
		// Phyon buffer (read)
		{binding = 2, visibility = {.Compute}, buffer = {type = .ReadOnlyStorage}},
		// Index buffer (read)
		{binding = 3, visibility = {.Compute}, buffer = {type = .ReadOnlyStorage}},
		// Output texture (write)
		{
			binding = 4,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA32Float, viewDimension = ._2D},
		},
	}
	compute_bind_layout_desc := wgpu.BindGroupLayoutDescriptor {
		label      = "Compute Bind Group Layout",
		entryCount = len(compute_bind_entries),
		entries    = &compute_bind_entries[0],
	}
	compute_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		state.gapi.device,
		&compute_bind_layout_desc,
	)

	// ==========================================================================
	// Create Compute Pipeline Layout
	// ==========================================================================
	compute_pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		label                = "Compute Pipeline Layout",
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &compute_bind_group_layout,
	}
	compute_pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		state.gapi.device,
		&compute_pipeline_layout_desc,
	)
	defer wgpu.PipelineLayoutRelease(compute_pipeline_layout)

	// ==========================================================================
	// Create Compute Pipeline
	// ==========================================================================
	compute_desc := wgpu.ComputePipelineDescriptor {
		label = "Depth Compute Pipeline",
		layout = compute_pipeline_layout,
		compute = {module = compute_shader, entryPoint = "cs_main"},
	}
	state.pipelines.compute_pipeline = wgpu.DeviceCreateComputePipeline(
		state.gapi.device,
		&compute_desc,
	)
	if state.pipelines.compute_pipeline == nil {
		log_err("Failed to create compute pipeline")
		return false
	}

	// Create initial bind groups
	recreate_rasterize_bind_group()
	if state.pipelines.rasterize_bind_group == nil {
		log_err("Failed to create rasterize bind group")
		return false
	}

	recreate_compute_bind_group()
	if state.pipelines.compute_bind_group == nil {
		log_err("Failed to create compute bind group")
		return false
	}

	return true
}

// Recreate rasterize bind group (on resize)
recreate_rasterize_bind_group :: proc() {
	// Release old bind group
	if state.pipelines.rasterize_bind_group != nil {
		wgpu.BindGroupRelease(state.pipelines.rasterize_bind_group)
		state.pipelines.rasterize_bind_group = nil
	}

	bind_entries := [1]wgpu.BindGroupEntry {
		{binding = 0, buffer = state.buffers.uniform_buffer, size = size_of(Uniforms)},
	}
	bind_desc := wgpu.BindGroupDescriptor {
		label      = "Rasterize Bind Group",
		layout     = rasterize_bind_group_layout,
		entryCount = len(bind_entries),
		entries    = &bind_entries[0],
	}
	state.pipelines.rasterize_bind_group = wgpu.DeviceCreateBindGroup(
		state.gapi.device,
		&bind_desc,
	)
}

// Recreate compute bind group (on resize)
recreate_compute_bind_group :: proc() {
	// Release old bind group
	if state.pipelines.compute_bind_group != nil {
		wgpu.BindGroupRelease(state.pipelines.compute_bind_group)
		state.pipelines.compute_bind_group = nil
	}

	// Need all textures and buffers to exist
	if state.rendering.face_id_texture_view == nil ||
	   state.rendering.output_texture_view == nil ||
	   state.buffers.phyon_buffer == nil ||
	   state.buffers.triangle_index_buffer == nil {
		return
	}

	bind_entries := [5]wgpu.BindGroupEntry {
		{binding = 0, buffer = state.buffers.uniform_buffer, size = size_of(Uniforms)},
		{binding = 1, textureView = state.rendering.face_id_texture_view},
		{binding = 2, buffer = state.buffers.phyon_buffer, size = wgpu.WHOLE_SIZE},
		{binding = 3, buffer = state.buffers.triangle_index_buffer, size = wgpu.WHOLE_SIZE},
		{binding = 4, textureView = state.rendering.output_texture_view},
	}
	bind_desc := wgpu.BindGroupDescriptor {
		label      = "Compute Bind Group",
		layout     = compute_bind_group_layout,
		entryCount = len(bind_entries),
		entries    = &bind_entries[0],
	}
	state.pipelines.compute_bind_group = wgpu.DeviceCreateBindGroup(state.gapi.device, &bind_desc)
}

cleanup_pipelines :: proc() {
	if state.pipelines.compute_bind_group != nil do wgpu.BindGroupRelease(state.pipelines.compute_bind_group)
	if state.pipelines.compute_pipeline != nil do wgpu.ComputePipelineRelease(state.pipelines.compute_pipeline)
	if compute_bind_group_layout != nil do wgpu.BindGroupLayoutRelease(compute_bind_group_layout)
	if state.pipelines.rasterize_bind_group != nil do wgpu.BindGroupRelease(state.pipelines.rasterize_bind_group)
	if state.pipelines.rasterize_pipeline != nil do wgpu.RenderPipelineRelease(state.pipelines.rasterize_pipeline)
	if rasterize_bind_group_layout != nil do wgpu.BindGroupLayoutRelease(rasterize_bind_group_layout)
}
