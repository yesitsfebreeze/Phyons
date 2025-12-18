package phyons

import "vendor:wgpu"

// Create or recreate textures when window size changes
// Returns (success, textures_changed)
ensure_render_textures :: proc() -> (bool, bool) {
	width := state.gapi.surface_config.width
	height := state.gapi.surface_config.height

	// Check if we need to recreate
	if state.rendering.depth_width == width &&
	   state.rendering.depth_height == height &&
	   state.rendering.depth_texture != nil {
		return true, false
	}

	// Release old resources
	if state.rendering.depth_texture_view != nil do wgpu.TextureViewRelease(state.rendering.depth_texture_view)
	if state.rendering.depth_texture != nil do wgpu.TextureRelease(state.rendering.depth_texture)
	if state.rendering.inside_depth_texture_view != nil do wgpu.TextureViewRelease(state.rendering.inside_depth_texture_view)
	if state.rendering.inside_depth_texture != nil do wgpu.TextureRelease(state.rendering.inside_depth_texture)
	if state.rendering.normal_material_texture_view != nil do wgpu.TextureViewRelease(state.rendering.normal_material_texture_view)
	if state.rendering.normal_material_texture != nil do wgpu.TextureRelease(state.rendering.normal_material_texture)
	if state.rendering.output_texture_view != nil do wgpu.TextureViewRelease(state.rendering.output_texture_view)
	if state.rendering.output_texture != nil do wgpu.TextureRelease(state.rendering.output_texture)

	state.rendering.depth_width = width
	state.rendering.depth_height = height

	// Hardware depth texture (z-buffer for rasterize pass)
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
		return false, false
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

	// Inside+depth texture (xyz=inside position, w=phyon depth)
	inside_depth_desc := wgpu.TextureDescriptor {
		label         = "Inside Depth Texture",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .RGBA32Float,
		usage         = {.RenderAttachment, .TextureBinding},
	}
	state.rendering.inside_depth_texture = wgpu.DeviceCreateTexture(state.gapi.device, &inside_depth_desc)
	if state.rendering.inside_depth_texture == nil {
		log_err("Failed to create inside_depth texture")
		return false, false
	}

	inside_depth_view_desc := wgpu.TextureViewDescriptor {
		format          = .RGBA32Float,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	state.rendering.inside_depth_texture_view = wgpu.TextureCreateView(
		state.rendering.inside_depth_texture,
		&inside_depth_view_desc,
	)

	// Normal+material texture (xyz=normal, w=material_id)
	normal_material_desc := wgpu.TextureDescriptor {
		label         = "Normal Material Texture",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .RGBA32Float,
		usage         = {.RenderAttachment, .TextureBinding},
	}
	state.rendering.normal_material_texture = wgpu.DeviceCreateTexture(state.gapi.device, &normal_material_desc)
	if state.rendering.normal_material_texture == nil {
		log_err("Failed to create normal_material texture")
		return false, false
	}

	normal_material_view_desc := wgpu.TextureViewDescriptor {
		format          = .RGBA32Float,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	state.rendering.normal_material_texture_view = wgpu.TextureCreateView(
		state.rendering.normal_material_texture,
		&normal_material_view_desc,
	)

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
	model := mat4_translate(vec3{0, 0, 0})
	view_matrix := get_view_matrix()
	proj := get_projection_matrix()
	view_proj := proj * view_matrix
	inv_view_proj := mat4_inverse(view_proj)

	uniforms := Uniforms {
		view_proj     = view_proj,
		inv_view_proj = inv_view_proj,
		model         = model,
		camera_pos    = state.camera.position,
		time          = state.elapsed,
		screen_width  = f32(state.gapi.surface_config.width),
		screen_height = f32(state.gapi.surface_config.height),
		phyon_count   = f32(state.buffers.phyon_count),
		face_count    = f32(state.buffers.face_count),
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
	// Pass 1: Rasterize - output inside+depth and normal+material per pixel
	// ==========================================================================
	{
		color_attachments := [2]wgpu.RenderPassColorAttachment {
			{
				view       = state.rendering.inside_depth_texture_view,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				loadOp     = .Clear,
				storeOp    = .Store,
				clearValue = {0.0, 0.0, 0.0, 0.0}, // material_id=0 means no geometry
			},
			{
				view       = state.rendering.normal_material_texture_view,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				loadOp     = .Clear,
				storeOp    = .Store,
				clearValue = {0.0, 0.0, 0.0, 0.0}, // material_id=0 in w
			},
		}

		depth_attachment := wgpu.RenderPassDepthStencilAttachment {
			view            = state.rendering.depth_texture_view,
			depthLoadOp     = .Clear,
			depthStoreOp    = .Store,
			depthClearValue = 1.0,
			depthReadOnly   = false,
		}

		pass_desc := wgpu.RenderPassDescriptor {
			label                  = "Rasterize Pass",
			colorAttachmentCount   = 2,
			colorAttachments       = &color_attachments[0],
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
	// Pass 2: Clear - reset output texture and depth buffer
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
	// Pass 3: Drawing compute - read interpolated data, reproject to smooth surface
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
	// Pass 4: Present - render output texture to screen
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
	if state.rendering.normal_material_texture_view != nil do wgpu.TextureViewRelease(state.rendering.normal_material_texture_view)
	if state.rendering.normal_material_texture != nil do wgpu.TextureRelease(state.rendering.normal_material_texture)
	if state.rendering.inside_depth_texture_view != nil do wgpu.TextureViewRelease(state.rendering.inside_depth_texture_view)
	if state.rendering.inside_depth_texture != nil do wgpu.TextureRelease(state.rendering.inside_depth_texture)
	if state.rendering.depth_texture_view != nil do wgpu.TextureViewRelease(state.rendering.depth_texture_view)
	if state.rendering.depth_texture != nil do wgpu.TextureRelease(state.rendering.depth_texture)
}
