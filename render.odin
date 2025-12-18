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

	state.rendering.depth_width = width
	state.rendering.depth_height = height

	// Depth texture
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
		view_proj = view_proj,
		model     = model,
		time      = state.elapsed,
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
	// Geometry Pass - Render to swapchain
	// ==========================================================================
	{
		color_attachment := wgpu.RenderPassColorAttachment {
			view       = texture_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp     = .Clear,
			storeOp    = .Store,
			clearValue = {0.1, 0.1, 0.1, 1.0},
		}

		depth_attachment := wgpu.RenderPassDepthStencilAttachment {
			view            = state.rendering.depth_texture_view,
			depthLoadOp     = .Clear,
			depthStoreOp    = .Store,
			depthClearValue = 1.0,
			depthReadOnly   = false,
		}

		pass_desc := wgpu.RenderPassDescriptor {
			label                  = "Geometry Pass",
			colorAttachmentCount   = 1,
			colorAttachments       = &color_attachment,
			depthStencilAttachment = &depth_attachment,
		}

		pass := wgpu.CommandEncoderBeginRenderPass(encoder, &pass_desc)

		wgpu.RenderPassEncoderSetPipeline(pass, state.pipelines.geometry_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(pass, 0, state.pipelines.geometry_bind_group)
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
			.Uint16,
			0,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderDrawIndexed(pass, state.buffers.triangle_index_count, 1, 0, 0, 0)

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
	if state.rendering.depth_texture_view != nil do wgpu.TextureViewRelease(state.rendering.depth_texture_view)
	if state.rendering.depth_texture != nil do wgpu.TextureRelease(state.rendering.depth_texture)
}
