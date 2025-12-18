package phyons

import "vendor:wgpu"

// Store bind group layout for recreation
@(private = "file")
geometry_bind_group_layout: wgpu.BindGroupLayout

init_pipeline :: proc() -> bool {
	// Get shader modules
	geom_vertex_shader := get_shader("geo.vs")
	geom_fragment_shader := get_shader("geo.fs")

	if geom_vertex_shader == nil || geom_fragment_shader == nil {
		log_err("Failed to get required shader modules")
		return false
	}

	// ==========================================================================
	// Create bind group layout (uniform buffer + storage texture)
	// ==========================================================================

	bind_layout_entries := [2]wgpu.BindGroupLayoutEntry {
		{binding = 0, visibility = {.Vertex, .Fragment}, buffer = {type = .Uniform}},
		{
			binding = 1,
			visibility = {.Fragment},
			storageTexture = {access = .WriteOnly, format = .R32Float, viewDimension = ._2D},
		},
	}
	bind_layout_desc := wgpu.BindGroupLayoutDescriptor {
		label      = "Geometry Bind Group Layout",
		entryCount = len(bind_layout_entries),
		entries    = &bind_layout_entries[0],
	}
	geometry_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		state.gapi.device,
		&bind_layout_desc,
	)

	// ==========================================================================
	// Create pipeline layout
	// ==========================================================================

	pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		label                = "Geometry Pipeline Layout",
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &geometry_bind_group_layout,
	}
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(state.gapi.device, &pipeline_layout_desc)
	defer wgpu.PipelineLayoutRelease(pipeline_layout)

	// ==========================================================================
	// Vertex attributes
	// ==========================================================================

	vertex_attributes := []wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0}, // inside
		{format = .Float32x3, offset = 12, shaderLocation = 1}, // ref
	}

	vertex_buffer_layout := wgpu.VertexBufferLayout {
		arrayStride    = size_of(Phyon),
		stepMode       = .Vertex,
		attributeCount = uint(len(vertex_attributes)),
		attributes     = raw_data(vertex_attributes),
	}

	// ==========================================================================
	// Create Geometry Pipeline
	// ==========================================================================

	color_target := wgpu.ColorTargetState {
		format    = state.gapi.surface_config.format,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}

	fragment_state := wgpu.FragmentState {
		module      = geom_fragment_shader,
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
		label = "Geometry Pipeline",
		layout = pipeline_layout,
		vertex = {
			module = geom_vertex_shader,
			entryPoint = "vs_main",
			bufferCount = 1,
			buffers = &vertex_buffer_layout,
		},
		fragment = &fragment_state,
		primitive = {topology = .TriangleList, cullMode = .Back, frontFace = .CCW},
		depthStencil = &depth_stencil,
		multisample = {count = 1, mask = ~u32(0)},
	}

	state.pipelines.geometry_pipeline = wgpu.DeviceCreateRenderPipeline(
		state.gapi.device,
		&pipeline_desc,
	)
	if state.pipelines.geometry_pipeline == nil {
		log_err("Failed to create geometry pipeline")
		return false
	}

	// Create initial bind group (custom depth texture should exist by now)
	recreate_geometry_bind_group()
	if state.pipelines.geometry_bind_group == nil {
		log_err("Failed to create geometry bind group")
		return false
	}

	return true
}

// Recreate bind group when custom depth texture changes (on resize)
recreate_geometry_bind_group :: proc() {
	// Release old bind group
	if state.pipelines.geometry_bind_group != nil {
		wgpu.BindGroupRelease(state.pipelines.geometry_bind_group)
		state.pipelines.geometry_bind_group = nil
	}

	// Need custom depth texture view to exist
	if state.rendering.custom_depth_texture_view == nil {
		return
	}

	bind_entries := [2]wgpu.BindGroupEntry {
		{binding = 0, buffer = state.buffers.uniform_buffer, size = size_of(Uniforms)},
		{binding = 1, textureView = state.rendering.custom_depth_texture_view},
	}
	bind_desc := wgpu.BindGroupDescriptor {
		label      = "Geometry Bind Group",
		layout     = geometry_bind_group_layout,
		entryCount = len(bind_entries),
		entries    = &bind_entries[0],
	}
	state.pipelines.geometry_bind_group = wgpu.DeviceCreateBindGroup(state.gapi.device, &bind_desc)
}

cleanup_pipelines :: proc() {
	if state.pipelines.geometry_bind_group != nil do wgpu.BindGroupRelease(state.pipelines.geometry_bind_group)
	if state.pipelines.geometry_pipeline != nil do wgpu.RenderPipelineRelease(state.pipelines.geometry_pipeline)
	if geometry_bind_group_layout != nil do wgpu.BindGroupLayoutRelease(geometry_bind_group_layout)
}
