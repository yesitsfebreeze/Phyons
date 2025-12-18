package phyons

import "vendor:wgpu"

// Create or recreate depth texture when window size changes
ensure_depth_texture :: proc() -> bool {
	width := state.gapi.surface_config.width
	height := state.gapi.surface_config.height

	// Check if we need to recreate
	if state.rendering.depth_width == width &&
	   state.rendering.depth_height == height &&
	   state.rendering.depth_texture != nil {
		return true
	}

	// Release old resources
	if state.rendering.depth_texture_view != nil do wgpu.TextureViewRelease(state.rendering.depth_texture_view)
	if state.rendering.depth_texture != nil do wgpu.TextureRelease(state.rendering.depth_texture)
	if state.rendering.face_id_texture_view != nil do wgpu.TextureViewRelease(state.rendering.face_id_texture_view)
	if state.rendering.face_id_texture != nil do wgpu.TextureRelease(state.rendering.face_id_texture)
	if state.rendering.output_texture_view != nil do wgpu.TextureViewRelease(state.rendering.output_texture_view)
	if state.rendering.output_texture != nil do wgpu.TextureRelease(state.rendering.output_texture)

	state.rendering.depth_width = width
	state.rendering.depth_height = height

	// Hardware depth texture (z-buffer)
	depth_desc := wgpu.TextureDescriptor {
		label         = "Depth Texture",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .Depth24Plus,
		usage         = {.RenderAttachment},
	}
	state.rendering.depth_texture = wgpu.DeviceCreateTexture(state.gapi.device, &depth_desc)
	if state.rendering.depth_texture == nil {
		log_err("Failed to create depth texture")
		return false
	}

	depth_view_desc := wgpu.TextureViewDescriptor {
		format          = .Depth24Plus,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	state.rendering.depth_texture_view = wgpu.TextureCreateView(
		state.rendering.depth_texture,
		&depth_view_desc,
	)

	// Face ID texture (RGBA32Float - stores barycentric coords in RGB, triangle ID in A)
	face_id_desc := wgpu.TextureDescriptor {
		label         = "Face ID Texture",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .RGBA32Float,
		usage         = {.RenderAttachment, .TextureBinding},
	}
	state.rendering.face_id_texture = wgpu.DeviceCreateTexture(state.gapi.device, &face_id_desc)
	if state.rendering.face_id_texture == nil {
		log_err("Failed to create vertex indices texture")
		return false
	}

	face_id_view_desc := wgpu.TextureViewDescriptor {
		format          = .RGBA32Float,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	state.rendering.face_id_texture_view = wgpu.TextureCreateView(
		state.rendering.face_id_texture,
		&face_id_view_desc,
	)

	// Output texture (RGBA32Float - computed depth/opacity from compute pass)
	output_desc := wgpu.TextureDescriptor {
		label         = "Output Texture",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .RGBA32Float,
		usage         = {.StorageBinding, .TextureBinding, .CopySrc},
	}
	state.rendering.output_texture = wgpu.DeviceCreateTexture(state.gapi.device, &output_desc)
	if state.rendering.output_texture == nil {
		log_err("Failed to create output texture")
		return false
	}

	output_view_desc := wgpu.TextureViewDescriptor {
		format          = .RGBA32Float,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	state.rendering.output_texture_view = wgpu.TextureCreateView(
		state.rendering.output_texture,
		&output_view_desc,
	)

	// Recreate bind groups since texture views changed (only if pipelines exist)
	if state.pipelines.rasterize_pipeline != nil {
		recreate_rasterize_bind_group()
	}
	if state.pipelines.drawing_pipeline != nil {
		recreate_drawing_bind_group()
	}
	if state.pipelines.present_pipeline != nil {
		recreate_present_bind_group()
	}

	return true
}

render_frame :: proc() {
	// Get current surface texture
	surface_texture := wgpu.SurfaceGetCurrentTexture(state.gapi.surface)

	if surface_texture.status != .SuccessOptimal {
		log_err("Failed to get surface texture")
		return
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	// Create texture view for swapchain
	texture_view_desc := wgpu.TextureViewDescriptor {
		format          = state.gapi.surface_config.format,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	texture_view := wgpu.TextureCreateView(surface_texture.texture, &texture_view_desc)
	defer wgpu.TextureViewRelease(texture_view)

	// Ensure depth texture is created/resized
	if !ensure_depth_texture() {
		log_err("Failed to ensure depth texture")
		return
	}

	// Update uniforms
	model := mat4_translate(vec3{0, 0, 0})
	view_matrix := get_view_matrix()
	proj := get_projection_matrix()
	view_proj := proj * view_matrix

	uniforms := Uniforms {
		view_proj      = view_proj,
		model          = model,
		time           = state.elapsed,
		screen_width   = f32(state.gapi.surface_config.width),
		screen_height  = f32(state.gapi.surface_config.height),
		triangle_count = f32(state.buffers.triangle_index_count / 3),
	}
	wgpu.QueueWriteBuffer(
		state.gapi.queue,
		state.buffers.uniform_buffer,
		0,
		&uniforms,
		size_of(Uniforms),
	)

	// Create command encoder
	encoder_desc := wgpu.CommandEncoderDescriptor {
		label = "Command Encoder",
	}
	encoder := wgpu.DeviceCreateCommandEncoder(state.gapi.device, &encoder_desc)
	defer wgpu.CommandEncoderRelease(encoder)

	// ==========================================================================
	// Pass 1: Geometry Pass - Rasterize face IDs
	// ==========================================================================
	{
		// Render to face ID texture (RGBA32Float - barycentric RGB, triangle ID in A)
		face_id_attachment := wgpu.RenderPassColorAttachment {
			view       = state.rendering.face_id_texture_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp     = .Clear,
			storeOp    = .Store,
			clearValue = {0, 0, 0, -1}, // A=-1 means no geometry
		}

		depth_attachment := wgpu.RenderPassDepthStencilAttachment {
			view            = state.rendering.depth_texture_view,
			depthLoadOp     = .Clear,
			depthStoreOp    = .Store,
			depthClearValue = 1.0,
			depthReadOnly   = false,
		}

		pass_desc := wgpu.RenderPassDescriptor {
			label                  = "Face ID Pass",
			colorAttachmentCount   = 1,
			colorAttachments       = &face_id_attachment,
			depthStencilAttachment = &depth_attachment,
		}

		pass := wgpu.CommandEncoderBeginRenderPass(encoder, &pass_desc)

		wgpu.RenderPassEncoderSetPipeline(pass, state.pipelines.rasterize_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(pass, 0, state.pipelines.rasterize_bind_group)
		wgpu.RenderPassEncoderSetVertexBuffer(
			pass,
			0,
			state.buffers.phyon_buffer,
			0,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderSetIndexBuffer(
			pass,
			state.buffers.triangle_index_buffer,
			.Uint32,
			0,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderDrawIndexed(pass, state.buffers.triangle_index_count, 1, 0, 0, 0)

		wgpu.RenderPassEncoderEnd(pass)
		wgpu.RenderPassEncoderRelease(pass)
	}

	// ==========================================================================
	// Pass 2: Drawing Pass - Process face IDs into image
	// ==========================================================================
	{
		pass := wgpu.CommandEncoderBeginComputePass(encoder, nil)

		wgpu.ComputePassEncoderSetPipeline(pass, state.pipelines.drawing_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, state.pipelines.drawing_bind_group)

		// Dispatch workgroups (8x8 threads per group)
		width := state.gapi.surface_config.width
		height := state.gapi.surface_config.height
		workgroups_x := (width + 7) / 8
		workgroups_y := (height + 7) / 8
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, workgroups_x, workgroups_y, 1)

		wgpu.ComputePassEncoderEnd(pass)
		wgpu.ComputePassEncoderRelease(pass)
	}

	// ==========================================================================
	// Pass 3: Present Pass - Render depth buffer to screen
	// ==========================================================================
	{
		color_attachment := wgpu.RenderPassColorAttachment {
			view       = texture_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp     = .Clear,
			storeOp    = .Store,
			clearValue = {0.1, 0.1, 0.15, 1.0},
		}

		pass_desc := wgpu.RenderPassDescriptor {
			label                = "Present Pass",
			colorAttachmentCount = 1,
			colorAttachments     = &color_attachment,
		}

		pass := wgpu.CommandEncoderBeginRenderPass(encoder, &pass_desc)

		wgpu.RenderPassEncoderSetPipeline(pass, state.pipelines.present_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(pass, 0, state.pipelines.present_bind_group)
		wgpu.RenderPassEncoderDraw(pass, 3, 1, 0, 0) // Fullscreen triangle

		wgpu.RenderPassEncoderEnd(pass)
		wgpu.RenderPassEncoderRelease(pass)
	}

	// Submit command buffer
	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)
	wgpu.QueueSubmit(state.gapi.queue, {command_buffer})

	// Present
	wgpu.SurfacePresent(state.gapi.surface)
}

cleanup_rendering :: proc() {
	if state.rendering.output_texture_view != nil do wgpu.TextureViewRelease(state.rendering.output_texture_view)
	if state.rendering.output_texture != nil do wgpu.TextureRelease(state.rendering.output_texture)
	if state.rendering.face_id_texture_view != nil do wgpu.TextureViewRelease(state.rendering.face_id_texture_view)
	if state.rendering.face_id_texture != nil do wgpu.TextureRelease(state.rendering.face_id_texture)
	if state.rendering.depth_texture_view != nil do wgpu.TextureViewRelease(state.rendering.depth_texture_view)
	if state.rendering.depth_texture != nil do wgpu.TextureRelease(state.rendering.depth_texture)
}
