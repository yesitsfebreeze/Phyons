package phyons

import "vendor:wgpu"

init_pipeline :: proc() -> bool {
	// ==========================================================================
	// Get shader modules from shaders state
	// ==========================================================================

	geom_vertex_shader := get_shader("geo.vs")
	geom_fragment_shader := get_shader("geo.fs")
	shade_vertex_shader := get_shader("shading.vs")
	shade_fragment_shader := get_shader("shading.fs")
	wire_vertex_shader := get_shader("wireframe.vs")
	wire_fragment_shader := get_shader("present.fs")

	if geom_vertex_shader == nil ||
	   geom_fragment_shader == nil ||
	   shade_vertex_shader == nil ||
	   shade_fragment_shader == nil ||
	   wire_vertex_shader == nil ||
	   wire_fragment_shader == nil {
		log_err("Failed to get required shader modules")
		return false
	}

	// ==========================================================================
	// Create bind group layouts
	// ==========================================================================

	// Geometry pass bind group layout (uniform buffer)
	geom_bind_layout_entry := wgpu.BindGroupLayoutEntry {
		binding = 0,
		visibility = {.Vertex},
		buffer = {type = .Uniform},
	}
	geom_bind_layout_desc := wgpu.BindGroupLayoutDescriptor {
		label      = "Geometry Bind Group Layout",
		entryCount = 1,
		entries    = &geom_bind_layout_entry,
	}
	geom_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
		state.gapi.device,
		&geom_bind_layout_desc,
	)
	defer wgpu.BindGroupLayoutRelease(geom_bind_group_layout)

	// Shading pass bind group layout (G-buffer textures + sampler)
	shade_bind_layout_entries := []wgpu.BindGroupLayoutEntry {
		{
			binding = 0,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		}, // gbuffer_normal
		{
			binding = 1,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		}, // gbuffer_material
		{
			binding = 2,
			visibility = {.Fragment},
			texture = {sampleType = .Float, viewDimension = ._2D},
		}, // gbuffer_distance
		{
			binding = 3,
			visibility = {.Fragment},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		}, // depth_front
		{
			binding = 4,
			visibility = {.Fragment},
			texture = {sampleType = .Depth, viewDimension = ._2D},
		}, // depth_back
		{binding = 5, visibility = {.Fragment}, sampler = {type = .Filtering}}, // sampler
	}
	shade_bind_layout_desc := wgpu.BindGroupLayoutDescriptor {
		label      = "Shading Bind Group Layout",
		entryCount = uint(len(shade_bind_layout_entries)),
		entries    = raw_data(shade_bind_layout_entries),
	}
	state.pipelines.shading_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		state.gapi.device,
		&shade_bind_layout_desc,
	)

	// ==========================================================================
	// Create geometry bind group
	// ==========================================================================

	geom_bind_entry := wgpu.BindGroupEntry {
		binding = 0,
		buffer  = state.buffers.uniform_buffer,
		size    = size_of(Uniforms),
	}
	geom_bind_desc := wgpu.BindGroupDescriptor {
		label      = "Geometry Bind Group",
		layout     = geom_bind_group_layout,
		entryCount = 1,
		entries    = &geom_bind_entry,
	}
	state.pipelines.geometry_bind_group = wgpu.DeviceCreateBindGroup(
		state.gapi.device,
		&geom_bind_desc,
	)

	// ==========================================================================
	// Create sampler for shading pass
	// ==========================================================================

	sampler_desc := wgpu.SamplerDescriptor {
		label         = "G-Buffer Sampler",
		addressModeU  = .ClampToEdge,
		addressModeV  = .ClampToEdge,
		addressModeW  = .ClampToEdge,
		magFilter     = .Linear,
		minFilter     = .Linear,
		mipmapFilter  = .Nearest,
		maxAnisotropy = 1,
	}
	state.pipelines.gbuffer_sampler = wgpu.DeviceCreateSampler(state.gapi.device, &sampler_desc)

	// ==========================================================================
	// Create pipeline layouts
	// ==========================================================================

	// Geometry pipeline layout
	geom_pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		label                = "Geometry Pipeline Layout",
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &geom_bind_group_layout,
	}
	geom_pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		state.gapi.device,
		&geom_pipeline_layout_desc,
	)
	defer wgpu.PipelineLayoutRelease(geom_pipeline_layout)

	// Shading pipeline layout
	shade_pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		label                = "Shading Pipeline Layout",
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &state.pipelines.shading_bind_group_layout,
	}
	shade_pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		state.gapi.device,
		&shade_pipeline_layout_desc,
	)
	defer wgpu.PipelineLayoutRelease(shade_pipeline_layout)

	// ==========================================================================
	// Vertex attributes (for geometry and wireframe)
	// ==========================================================================

	vertex_attributes := []wgpu.VertexAttribute {
		{format = .Float32x3, offset = 0, shaderLocation = 0}, // position
		{format = .Float32x3, offset = 12, shaderLocation = 1}, // color
		{format = .Float32x3, offset = 24, shaderLocation = 2}, // reference_centroid
		{format = .Float32x3, offset = 36, shaderLocation = 3}, // normal
		{format = .Float32, offset = 48, shaderLocation = 4}, // material_id
		{format = .Float32, offset = 52, shaderLocation = 5}, // opacity
		{format = .Float32, offset = 56, shaderLocation = 6}, // distance_to_center
	}

	vertex_buffer_layout := wgpu.VertexBufferLayout {
		arrayStride    = size_of(Phyon),
		stepMode       = .Vertex,
		attributeCount = uint(len(vertex_attributes)),
		attributes     = raw_data(vertex_attributes),
	}

	// ==========================================================================
	// Create Geometry Pipeline (MRT - Multiple Render Targets)
	// ==========================================================================

	geom_color_targets := []wgpu.ColorTargetState {
		{format = .RGBA16Float, writeMask = wgpu.ColorWriteMaskFlags_All}, // normal
		{format = .RGBA8Unorm, writeMask = wgpu.ColorWriteMaskFlags_All}, // material
		{format = .RGBA16Float, writeMask = wgpu.ColorWriteMaskFlags_All}, // distance
	}

	geom_fragment_state := wgpu.FragmentState {
		module      = geom_fragment_shader,
		entryPoint  = "fs_main",
		targetCount = uint(len(geom_color_targets)),
		targets     = raw_data(geom_color_targets),
	}

	geom_depth_stencil := wgpu.DepthStencilState {
		format            = .Depth24Plus,
		depthWriteEnabled = .True,
		depthCompare      = .Less,
	}

	// Frontface geometry pipeline (cull back faces)
	geom_pipeline_desc := wgpu.RenderPipelineDescriptor {
		label = "Geometry Pipeline (Front)",
		layout = geom_pipeline_layout,
		vertex = {
			module = geom_vertex_shader,
			entryPoint = "vs_main",
			bufferCount = 1,
			buffers = &vertex_buffer_layout,
		},
		fragment = &geom_fragment_state,
		primitive = {topology = .TriangleList, cullMode = .Back, frontFace = .CCW},
		depthStencil = &geom_depth_stencil,
		multisample = {count = 1, mask = ~u32(0)},
	}

	state.pipelines.geometry_pipeline = wgpu.DeviceCreateRenderPipeline(
		state.gapi.device,
		&geom_pipeline_desc,
	)
	if state.pipelines.geometry_pipeline == nil {
		log_err("Failed to create geometry pipeline")
		return false
	}

	// Backface geometry pipeline (cull front faces) - depth-only for inside depth
	geom_back_depth_stencil := wgpu.DepthStencilState {
		format            = .Depth24Plus,
		depthWriteEnabled = .True,
		depthCompare      = .Greater, // Farthest backface wins
	}

	geom_back_pipeline_desc := wgpu.RenderPipelineDescriptor {
		label = "Geometry Pipeline (Back)",
		layout = geom_pipeline_layout,
		vertex = {
			module = geom_vertex_shader,
			entryPoint = "vs_main",
			bufferCount = 1,
			buffers = &vertex_buffer_layout,
		},
		fragment = nil, // Depth-only pass - no fragment shader
		primitive = {topology = .TriangleList, cullMode = .Front, frontFace = .CCW},
		depthStencil = &geom_back_depth_stencil,
		multisample = {count = 1, mask = ~u32(0)},
	}

	state.pipelines.geometry_back_pipeline = wgpu.DeviceCreateRenderPipeline(
		state.gapi.device,
		&geom_back_pipeline_desc,
	)
	if state.pipelines.geometry_back_pipeline == nil {
		log_err("Failed to create backface geometry pipeline")
		return false
	}

	// ==========================================================================
	// Create Shading Pipeline (Fullscreen pass)
	// ==========================================================================

	shade_color_target := wgpu.ColorTargetState {
		format    = state.gapi.surface_config.format,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}

	shade_fragment_state := wgpu.FragmentState {
		module      = shade_fragment_shader,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &shade_color_target,
	}

	shade_pipeline_desc := wgpu.RenderPipelineDescriptor {
		label = "Shading Pipeline",
		layout = shade_pipeline_layout,
		vertex = {
			module      = shade_vertex_shader,
			entryPoint  = "vs_main",
			bufferCount = 0, // No vertex buffer - procedural fullscreen triangle
		},
		fragment = &shade_fragment_state,
		primitive = {topology = .TriangleList, cullMode = .None, frontFace = .CCW},
		multisample = {count = 1, mask = ~u32(0)},
	}

	state.pipelines.shading_pipeline = wgpu.DeviceCreateRenderPipeline(
		state.gapi.device,
		&shade_pipeline_desc,
	)
	if state.pipelines.shading_pipeline == nil {
		log_err("Failed to create shading pipeline")
		return false
	}

	// ==========================================================================
	// Create Wireframe Pipeline (for overlay)
	// ==========================================================================

	wire_color_target := wgpu.ColorTargetState {
		format    = state.gapi.surface_config.format,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}

	wire_fragment_state := wgpu.FragmentState {
		module      = wire_fragment_shader,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &wire_color_target,
	}

	wire_depth_stencil := wgpu.DepthStencilState {
		format            = .Depth24Plus,
		depthWriteEnabled = .True,
		depthCompare      = .Less,
	}

	wire_pipeline_desc := wgpu.RenderPipelineDescriptor {
		label = "Wireframe Pipeline",
		layout = geom_pipeline_layout,
		vertex = {
			module = wire_vertex_shader,
			entryPoint = "vs_main",
			bufferCount = 1,
			buffers = &vertex_buffer_layout,
		},
		fragment = &wire_fragment_state,
		primitive = {topology = .LineList, cullMode = .None, frontFace = .CCW},
		depthStencil = &wire_depth_stencil,
		multisample = {count = 1, mask = ~u32(0)},
	}

	state.pipelines.wireframe_pipeline = wgpu.DeviceCreateRenderPipeline(
		state.gapi.device,
		&wire_pipeline_desc,
	)
	if state.pipelines.wireframe_pipeline == nil {
		log_err("Failed to create wireframe pipeline")
		return false
	}

	return true
}

cleanup_pipelines :: proc() {
	if state.pipelines.geometry_bind_group != nil do wgpu.BindGroupRelease(state.pipelines.geometry_bind_group)
	if state.pipelines.shading_bind_group != nil do wgpu.BindGroupRelease(state.pipelines.shading_bind_group)
	if state.pipelines.shading_bind_group_layout != nil do wgpu.BindGroupLayoutRelease(state.pipelines.shading_bind_group_layout)
	if state.pipelines.gbuffer_sampler != nil do wgpu.SamplerRelease(state.pipelines.gbuffer_sampler)
	if state.pipelines.geometry_pipeline != nil do wgpu.RenderPipelineRelease(state.pipelines.geometry_pipeline)
	if state.pipelines.geometry_back_pipeline != nil do wgpu.RenderPipelineRelease(state.pipelines.geometry_back_pipeline)
	if state.pipelines.shading_pipeline != nil do wgpu.RenderPipelineRelease(state.pipelines.shading_pipeline)
	if state.pipelines.wireframe_pipeline != nil do wgpu.RenderPipelineRelease(state.pipelines.wireframe_pipeline)
}
