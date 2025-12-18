package phyons

import "vendor:wgpu"

// Store bind group layouts for recreation
@(private = "file")
rasterize_bind_group_layout: wgpu.BindGroupLayout
@(private = "file")
drawing_bind_group_layout: wgpu.BindGroupLayout
@(private = "file")
present_bind_group_layout: wgpu.BindGroupLayout

// shaders
@(private = "file")
rasterize_vertex_shader: wgpu.ShaderModule
@(private = "file")
rasterize_fragment_shader: wgpu.ShaderModule
@(private = "file")
drawing_shader: wgpu.ShaderModule
@(private = "file")
present_vertex_shader: wgpu.ShaderModule
@(private = "file")
present_fragment_shader: wgpu.ShaderModule

init_pipeline :: proc() -> bool {
	// Get shader modules
	ok: bool

	rasterize_vertex_shader, ok = get_shader("rasterize.vs")
	if !ok do return false
	rasterize_fragment_shader, ok = get_shader("rasterize.fs")
	if !ok do return false
	drawing_shader, ok = get_shader("drawing.cs")
	if !ok do return false
	present_vertex_shader, ok = get_shader("present.vs")
	if !ok do return false
	present_fragment_shader, ok = get_shader("present.fs")
	if !ok do return false

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
		{format = .Uint32, offset = 32, shaderLocation = 4}, // face_id
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
		format    = .RGBA32Float, // Output barycentric (RGB) + triangle ID (A)
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
	// Create Drawing Bind Group Layout
	// ==========================================================================
	drawing_bind_entries := [6]wgpu.BindGroupLayoutEntry {
		// Uniforms
		{binding = 0, visibility = {.Compute}, buffer = {type = .Uniform}},
		// Face ID texture (read) - RGBA32Float with face ID
		{
			binding = 1,
			visibility = {.Compute},
			texture = {sampleType = .UnfilterableFloat, viewDimension = ._2D},
		},
		// Phyon buffer (read)
		{binding = 2, visibility = {.Compute}, buffer = {type = .ReadOnlyStorage}},
		// Triangle indices buffer (read) - defines triangle connectivity
		{binding = 3, visibility = {.Compute}, buffer = {type = .ReadOnlyStorage}},
		// Output texture (write)
		{
			binding = 4,
			visibility = {.Compute},
			storageTexture = {access = .WriteOnly, format = .RGBA32Float, viewDimension = ._2D},
		},
		// depth buffer (read/write atomic)
		{binding = 5, visibility = {.Compute}, buffer = {type = .Storage}},
	}
	drawing_bind_layout_desc := wgpu.BindGroupLayoutDescriptor {
		label      = "Drawing Bind Group Layout",
		entryCount = len(drawing_bind_entries),
		entries    = &drawing_bind_entries[0],
	}
	drawing_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		state.gapi.device,
		&drawing_bind_layout_desc,
	)

	// ==========================================================================
	// Create Drawing Pipeline Layout
	// ==========================================================================
	drawing_pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		label                = "Drawing Pipeline Layout",
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &drawing_bind_group_layout,
	}
	drawing_pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		state.gapi.device,
		&drawing_pipeline_layout_desc,
	)
	defer wgpu.PipelineLayoutRelease(drawing_pipeline_layout)

	// ==========================================================================
	// Create Clear Pipeline (uses same layout as drawing)
	// ==========================================================================
	clear_desc := wgpu.ComputePipelineDescriptor {
		label = "Clear Compute Pipeline",
		layout = drawing_pipeline_layout,
		compute = {module = drawing_shader, entryPoint = "cs_clear"},
	}
	state.pipelines.clear_pipeline = wgpu.DeviceCreateComputePipeline(
		state.gapi.device,
		&clear_desc,
	)
	if state.pipelines.clear_pipeline == nil {
		log_err("Failed to create clear pipeline")
		return false
	}

	// ==========================================================================
	// Create Drawing Pipeline
	// ==========================================================================
	drawing_desc := wgpu.ComputePipelineDescriptor {
		label = "Drawing Compute Pipeline",
		layout = drawing_pipeline_layout,
		compute = {module = drawing_shader, entryPoint = "cs_main"},
	}
	state.pipelines.drawing_pipeline = wgpu.DeviceCreateComputePipeline(
		state.gapi.device,
		&drawing_desc,
	)
	if state.pipelines.drawing_pipeline == nil {
		log_err("Failed to create drawing pipeline")
		return false
	}

	// ==========================================================================
	// Create Present Bind Group Layout
	// ==========================================================================
	present_bind_entries := [2]wgpu.BindGroupLayoutEntry {
		// Output texture (read) - RGBA32Float is not filterable
		{
			binding = 0,
			visibility = {.Fragment},
			texture = {sampleType = .UnfilterableFloat, viewDimension = ._2D},
		},
		// Sampler - non-filtering for RGBA32Float
		{binding = 1, visibility = {.Fragment}, sampler = {type = .NonFiltering}},
	}
	present_bind_layout_desc := wgpu.BindGroupLayoutDescriptor {
		label      = "Present Bind Group Layout",
		entryCount = len(present_bind_entries),
		entries    = &present_bind_entries[0],
	}
	present_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		state.gapi.device,
		&present_bind_layout_desc,
	)

	// ==========================================================================
	// Create Present Pipeline Layout
	// ==========================================================================
	present_pipeline_layout_desc := wgpu.PipelineLayoutDescriptor {
		label                = "Present Pipeline Layout",
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &present_bind_group_layout,
	}
	present_pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		state.gapi.device,
		&present_pipeline_layout_desc,
	)
	defer wgpu.PipelineLayoutRelease(present_pipeline_layout)

	// ==========================================================================
	// Create Present Pipeline
	// ==========================================================================
	present_color_target := wgpu.ColorTargetState {
		format    = state.gapi.surface_config.format,
		writeMask = wgpu.ColorWriteMaskFlags_All,
	}

	present_fragment := wgpu.FragmentState {
		module      = present_fragment_shader,
		entryPoint  = "fs_main",
		targetCount = 1,
		targets     = &present_color_target,
	}

	present_pipeline_desc := wgpu.RenderPipelineDescriptor {
		label = "Present Pipeline",
		layout = present_pipeline_layout,
		vertex = {module = present_vertex_shader, entryPoint = "vs_main"},
		fragment = &present_fragment,
		primitive = {topology = .TriangleList},
		multisample = {count = 1, mask = ~u32(0)},
	}

	state.pipelines.present_pipeline = wgpu.DeviceCreateRenderPipeline(
		state.gapi.device,
		&present_pipeline_desc,
	)
	if state.pipelines.present_pipeline == nil {
		log_err("Failed to create present pipeline")
		return false
	}

	// Create initial bind groups
	recreate_rasterize_bind_group()
	if state.pipelines.rasterize_bind_group == nil {
		log_err("Failed to create rasterize bind group")
		return false
	}

	recreate_drawing_bind_group()
	if state.pipelines.drawing_bind_group == nil {
		log_err("Failed to create drawing bind group")
		return false
	}

	recreate_present_bind_group()
	if state.pipelines.present_bind_group == nil {
		log_err("Failed to create present bind group")
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

// Recreate drawing bind group (on resize)
recreate_drawing_bind_group :: proc() {
	// Release old bind group
	if state.pipelines.drawing_bind_group != nil {
		wgpu.BindGroupRelease(state.pipelines.drawing_bind_group)
		state.pipelines.drawing_bind_group = nil
	}

	// Need all textures and buffers to exist
	if state.rendering.face_id_texture_view == nil ||
	   state.rendering.output_texture_view == nil ||
	   state.buffers.phyon_buffer == nil ||
	   state.buffers.triangle_index_buffer == nil ||
	   state.buffers.depth_buffer == nil {
		return
	}

	bind_entries := [6]wgpu.BindGroupEntry {
		{binding = 0, buffer = state.buffers.uniform_buffer, size = size_of(Uniforms)},
		{binding = 1, textureView = state.rendering.face_id_texture_view},
		{binding = 2, buffer = state.buffers.phyon_buffer, size = wgpu.WHOLE_SIZE},
		{binding = 3, buffer = state.buffers.triangle_index_buffer, size = wgpu.WHOLE_SIZE},
		{binding = 4, textureView = state.rendering.output_texture_view},
		{binding = 5, buffer = state.buffers.depth_buffer, size = wgpu.WHOLE_SIZE},
	}
	bind_desc := wgpu.BindGroupDescriptor {
		label      = "Drawing Bind Group",
		layout     = drawing_bind_group_layout,
		entryCount = len(bind_entries),
		entries    = &bind_entries[0],
	}
	state.pipelines.drawing_bind_group = wgpu.DeviceCreateBindGroup(state.gapi.device, &bind_desc)
}

// Recreate present bind group (on resize)
recreate_present_bind_group :: proc() {
	// Release old bind group
	if state.pipelines.present_bind_group != nil {
		wgpu.BindGroupRelease(state.pipelines.present_bind_group)
		state.pipelines.present_bind_group = nil
	}

	// Need output texture to exist
	if state.rendering.output_texture_view == nil {
		return
	}

	// Create sampler for texture sampling (non-filtering for RGBA32Float)
	sampler_desc := wgpu.SamplerDescriptor {
		addressModeU  = .ClampToEdge,
		addressModeV  = .ClampToEdge,
		addressModeW  = .ClampToEdge,
		magFilter     = .Nearest,
		minFilter     = .Nearest,
		mipmapFilter  = .Nearest,
		maxAnisotropy = 1,
	}
	sampler := wgpu.DeviceCreateSampler(state.gapi.device, &sampler_desc)

	bind_entries := [2]wgpu.BindGroupEntry {
		{binding = 0, textureView = state.rendering.output_texture_view},
		{binding = 1, sampler = sampler},
	}
	bind_desc := wgpu.BindGroupDescriptor {
		label      = "Present Bind Group",
		layout     = present_bind_group_layout,
		entryCount = len(bind_entries),
		entries    = &bind_entries[0],
	}
	state.pipelines.present_bind_group = wgpu.DeviceCreateBindGroup(state.gapi.device, &bind_desc)
}

cleanup_pipelines :: proc() {
	if state.pipelines.present_bind_group != nil do wgpu.BindGroupRelease(state.pipelines.present_bind_group)
	if state.pipelines.present_pipeline != nil do wgpu.RenderPipelineRelease(state.pipelines.present_pipeline)
	if present_bind_group_layout != nil do wgpu.BindGroupLayoutRelease(present_bind_group_layout)
	if state.pipelines.drawing_bind_group != nil do wgpu.BindGroupRelease(state.pipelines.drawing_bind_group)
	if state.pipelines.drawing_pipeline != nil do wgpu.ComputePipelineRelease(state.pipelines.drawing_pipeline)
	if state.pipelines.clear_pipeline != nil do wgpu.ComputePipelineRelease(state.pipelines.clear_pipeline)
	if drawing_bind_group_layout != nil do wgpu.BindGroupLayoutRelease(drawing_bind_group_layout)
	if state.pipelines.rasterize_bind_group != nil do wgpu.BindGroupRelease(state.pipelines.rasterize_bind_group)
	if state.pipelines.rasterize_pipeline != nil do wgpu.RenderPipelineRelease(state.pipelines.rasterize_pipeline)
	if rasterize_bind_group_layout != nil do wgpu.BindGroupLayoutRelease(rasterize_bind_group_layout)
}
