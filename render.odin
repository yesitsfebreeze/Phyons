package phyons

import "vendor:wgpu"

// Create or recreate textures when window size changes
// Returns (success, textures_changed)
ensure_render_textures :: proc() -> (bool, bool) {
	width := state.gapi.surface_config.width
	height := state.gapi.surface_config.height

	// Check if we need to recreate
	if state.rendering.render_width == width &&
	   state.rendering.render_height == height &&
	   state.rendering.output_texture != nil {
		return true, false
	}

	// Release old resources
	if state.rendering.output_texture_view != nil do wgpu.TextureViewRelease(state.rendering.output_texture_view)
	if state.rendering.output_texture != nil do wgpu.TextureRelease(state.rendering.output_texture)

	state.rendering.render_width = width
	state.rendering.render_height = height

	// Output texture - final rendered image from compute pass
	output_desc := wgpu.TextureDescriptor {
		label         = "Output Texture",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .RGBA32Float,
		usage         = {.StorageBinding, .TextureBinding},
	}
	state.rendering.output_texture = wgpu.DeviceCreateTexture(state.gapi.device, &output_desc)
	if state.rendering.output_texture == nil {
		log_err("Failed to create output texture")
		return false, false
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

	// Create software depth buffer for compute shader
	if !create_depth_buffer(width, height) {
		return false, false
	}

	return true, true
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

	// Ensure textures are created/resized
	ok, textures_changed := ensure_render_textures()
	if !ok {
		log_err("Failed to ensure render textures")
		return
	}

	// Recreate bind groups if textures changed
	if textures_changed {
		recreate_drawing_bind_group()
		recreate_present_bind_group()
	}

	// Update uniforms
	view_matrix := get_view_matrix()
	proj := get_projection_matrix()
	view_proj := proj * view_matrix
	inv_view_proj := mat4_inverse(view_proj)

	uniforms := Uniforms {
		view_proj     = view_proj,
		inv_view_proj = inv_view_proj,
		view          = view_matrix,
		camera_pos    = state.camera.position,
		time          = state.elapsed,
		screen_width  = f32(state.gapi.surface_config.width),
		screen_height = f32(state.gapi.surface_config.height),
		volume_count  = state.buffers.volume_count,
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
	// Pass 1: Clear - reset output texture and depth buffer
	// ==========================================================================
	{
		pass := wgpu.CommandEncoderBeginComputePass(encoder, nil)

		wgpu.ComputePassEncoderSetPipeline(pass, state.pipelines.clear_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, state.pipelines.drawing_bind_group)

		width := state.gapi.surface_config.width
		height := state.gapi.surface_config.height
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, (width + 7) / 8, (height + 7) / 8, 1)

		wgpu.ComputePassEncoderEnd(pass)
		wgpu.ComputePassEncoderRelease(pass)
	}

	// ==========================================================================
	// Pass 2: Drawing compute - pure compute rasterization
	// ==========================================================================
	{
		pass := wgpu.CommandEncoderBeginComputePass(encoder, nil)

		wgpu.ComputePassEncoderSetPipeline(pass, state.pipelines.drawing_pipeline)
		wgpu.ComputePassEncoderSetBindGroup(pass, 0, state.pipelines.drawing_bind_group)

		// Dispatch one thread per pixel
		width := state.gapi.surface_config.width
		height := state.gapi.surface_config.height
		wgpu.ComputePassEncoderDispatchWorkgroups(pass, (width + 7) / 8, (height + 7) / 8, 1)

		wgpu.ComputePassEncoderEnd(pass)
		wgpu.ComputePassEncoderRelease(pass)
	}

	// ==========================================================================
	// Pass 3: Present - render output texture to screen
	// ==========================================================================
	{
		color_attachment := wgpu.RenderPassColorAttachment {
			view       = texture_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp     = .Clear,
			storeOp    = .Store,
			clearValue = {0.05, 0.05, 0.08, 1.0},
		}

		pass_desc := wgpu.RenderPassDescriptor {
			label                = "Present Pass",
			colorAttachmentCount = 1,
			colorAttachments     = &color_attachment,
		}

		pass := wgpu.CommandEncoderBeginRenderPass(encoder, &pass_desc)

		wgpu.RenderPassEncoderSetPipeline(pass, state.pipelines.present_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(pass, 0, state.pipelines.present_bind_group)
		wgpu.RenderPassEncoderDraw(pass, 6, 1, 0, 0) // Full-screen quad

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
}
