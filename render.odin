package phyons

import "core:fmt"
import "core:math/linalg"
import "vendor:wgpu"

// Create or recreate G-buffer textures when window size changes
ensure_gbuffers :: proc() -> bool {
	width := state.gapi.surface_config.width
	height := state.gapi.surface_config.height

	// Check if we need to recreate
	if state.rendering.gbuffer_width == width &&
	   state.rendering.gbuffer_height == height &&
	   state.rendering.gbuffer_normal != nil {
		return true
	}

	// Release old resources
	if state.rendering.gbuffer_normal_view != nil do wgpu.TextureViewRelease(state.rendering.gbuffer_normal_view)
	if state.rendering.gbuffer_normal != nil do wgpu.TextureRelease(state.rendering.gbuffer_normal)
	if state.rendering.gbuffer_material_view != nil do wgpu.TextureViewRelease(state.rendering.gbuffer_material_view)
	if state.rendering.gbuffer_material != nil do wgpu.TextureRelease(state.rendering.gbuffer_material)
	if state.rendering.gbuffer_distance_view != nil do wgpu.TextureViewRelease(state.rendering.gbuffer_distance_view)
	if state.rendering.gbuffer_distance != nil do wgpu.TextureRelease(state.rendering.gbuffer_distance)
	if state.rendering.depth_front_view != nil do wgpu.TextureViewRelease(state.rendering.depth_front_view)
	if state.rendering.depth_front != nil do wgpu.TextureRelease(state.rendering.depth_front)
	if state.rendering.depth_back_view != nil do wgpu.TextureViewRelease(state.rendering.depth_back_view)
	if state.rendering.depth_back != nil do wgpu.TextureRelease(state.rendering.depth_back)
	if state.pipelines.shading_bind_group != nil do wgpu.BindGroupRelease(state.pipelines.shading_bind_group)

	state.rendering.gbuffer_width = width
	state.rendering.gbuffer_height = height

	// G-buffer: Normal (RGBA16Float) - RGB: normal, A: opacity
	normal_desc := wgpu.TextureDescriptor {
		label         = "G-Buffer Normal",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .RGBA16Float,
		usage         = {.RenderAttachment, .TextureBinding},
	}
	state.rendering.gbuffer_normal = wgpu.DeviceCreateTexture(state.gapi.device, &normal_desc)
	if state.rendering.gbuffer_normal == nil {
		fmt.println("Failed to create G-buffer normal texture")
		return false
	}

	normal_view_desc := wgpu.TextureViewDescriptor {
		format          = .RGBA16Float,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	state.rendering.gbuffer_normal_view = wgpu.TextureCreateView(
		state.rendering.gbuffer_normal,
		&normal_view_desc,
	)

	// G-buffer: Material (RGBA8Unorm) - R: material_id
	material_desc := wgpu.TextureDescriptor {
		label         = "G-Buffer Material",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .RGBA8Unorm,
		usage         = {.RenderAttachment, .TextureBinding},
	}
	state.rendering.gbuffer_material = wgpu.DeviceCreateTexture(state.gapi.device, &material_desc)
	if state.rendering.gbuffer_material == nil {
		fmt.println("Failed to create G-buffer material texture")
		return false
	}

	material_view_desc := wgpu.TextureViewDescriptor {
		format          = .RGBA8Unorm,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	state.rendering.gbuffer_material_view = wgpu.TextureCreateView(
		state.rendering.gbuffer_material,
		&material_view_desc,
	)

	// G-buffer: Distance (RGBA16Float) - R: distance_to_center, G: view_depth
	distance_desc := wgpu.TextureDescriptor {
		label         = "G-Buffer Distance",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .RGBA16Float,
		usage         = {.RenderAttachment, .TextureBinding},
	}
	state.rendering.gbuffer_distance = wgpu.DeviceCreateTexture(state.gapi.device, &distance_desc)
	if state.rendering.gbuffer_distance == nil {
		fmt.println("Failed to create G-buffer distance texture")
		return false
	}

	distance_view_desc := wgpu.TextureViewDescriptor {
		format          = .RGBA16Float,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	state.rendering.gbuffer_distance_view = wgpu.TextureCreateView(
		state.rendering.gbuffer_distance,
		&distance_view_desc,
	)

	// Depth Front (frontface depth - "outside" position)
	depth_front_desc := wgpu.TextureDescriptor {
		label         = "Depth Front",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .Depth24Plus,
		usage         = {.RenderAttachment, .TextureBinding},
	}
	state.rendering.depth_front = wgpu.DeviceCreateTexture(state.gapi.device, &depth_front_desc)
	if state.rendering.depth_front == nil {
		fmt.println("Failed to create depth front texture")
		return false
	}

	depth_front_view_desc := wgpu.TextureViewDescriptor {
		format          = .Depth24Plus,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	state.rendering.depth_front_view = wgpu.TextureCreateView(
		state.rendering.depth_front,
		&depth_front_view_desc,
	)

	// Depth Back (backface depth - "inside" position)
	depth_back_desc := wgpu.TextureDescriptor {
		label         = "Depth Back",
		size          = {width, height, 1},
		mipLevelCount = 1,
		sampleCount   = 1,
		dimension     = ._2D,
		format        = .Depth24Plus,
		usage         = {.RenderAttachment, .TextureBinding},
	}
	state.rendering.depth_back = wgpu.DeviceCreateTexture(state.gapi.device, &depth_back_desc)
	if state.rendering.depth_back == nil {
		fmt.println("Failed to create depth back texture")
		return false
	}

	depth_back_view_desc := wgpu.TextureViewDescriptor {
		format          = .Depth24Plus,
		dimension       = ._2D,
		mipLevelCount   = 1,
		arrayLayerCount = 1,
	}
	state.rendering.depth_back_view = wgpu.TextureCreateView(
		state.rendering.depth_back,
		&depth_back_view_desc,
	)

	// Create shading bind group with G-buffer textures
	shade_bind_entries := []wgpu.BindGroupEntry {
		{binding = 0, textureView = state.rendering.gbuffer_normal_view},
		{binding = 1, textureView = state.rendering.gbuffer_material_view},
		{binding = 2, textureView = state.rendering.gbuffer_distance_view},
		{binding = 3, textureView = state.rendering.depth_front_view},
		{binding = 4, textureView = state.rendering.depth_back_view},
		{binding = 5, sampler = state.pipelines.gbuffer_sampler},
	}
	shade_bind_desc := wgpu.BindGroupDescriptor {
		label      = "Shading Bind Group",
		layout     = state.pipelines.shading_bind_group_layout,
		entryCount = uint(len(shade_bind_entries)),
		entries    = raw_data(shade_bind_entries),
	}
	state.pipelines.shading_bind_group = wgpu.DeviceCreateBindGroup(
		state.gapi.device,
		&shade_bind_desc,
	)
	if state.pipelines.shading_bind_group == nil {
		fmt.println("Failed to create shading bind group")
		return false
	}

	// Also update legacy depth texture for wireframe overlay
	if state.rendering.depth_texture_view != nil do wgpu.TextureViewRelease(state.rendering.depth_texture_view)
	if state.rendering.depth_texture != nil do wgpu.TextureRelease(state.rendering.depth_texture)
	state.rendering.depth_texture = wgpu.DeviceCreateTexture(state.gapi.device, &depth_front_desc)
	state.rendering.depth_texture_view = wgpu.TextureCreateView(
		state.rendering.depth_texture,
		&depth_front_view_desc,
	)

	return true
}

render_frame :: proc() {
	// Get current surface texture
	surface_texture := wgpu.SurfaceGetCurrentTexture(state.gapi.surface)

	if surface_texture.status != .SuccessOptimal {
		fmt.println("Failed to get surface texture")
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

	// Ensure G-buffers are created/resized
	if !ensure_gbuffers() {
		fmt.println("Failed to ensure G-buffers")
		return
	}

	// Update uniforms
	model := linalg.matrix4_translate_f32(vec3{0, 0, 0})
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
	// PASS 1: Geometry Pass (Frontface) - Write to G-buffers
	// ==========================================================================
	{
		color_attachments := []wgpu.RenderPassColorAttachment {
			{
				view       = state.rendering.gbuffer_normal_view,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				loadOp     = .Clear,
				storeOp    = .Store,
				clearValue = {0.5, 0.5, 0.5, 0.0}, // Default normal (up), zero opacity
			},
			{
				view = state.rendering.gbuffer_material_view,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = {0.0, 0.0, 0.0, 0.0},
			},
			{
				view = state.rendering.gbuffer_distance_view,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = {0.0, 0.0, 0.0, 0.0},
			},
		}

		depth_attachment := wgpu.RenderPassDepthStencilAttachment {
			view            = state.rendering.depth_front_view,
			depthLoadOp     = .Clear,
			depthStoreOp    = .Store,
			depthClearValue = 1.0,
			depthReadOnly   = false,
		}

		geom_pass_desc := wgpu.RenderPassDescriptor {
			label                  = "Geometry Pass (Front)",
			colorAttachmentCount   = uint(len(color_attachments)),
			colorAttachments       = raw_data(color_attachments),
			depthStencilAttachment = &depth_attachment,
		}

		geom_pass := wgpu.CommandEncoderBeginRenderPass(encoder, &geom_pass_desc)

		wgpu.RenderPassEncoderSetPipeline(geom_pass, state.pipelines.geometry_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(geom_pass, 0, state.pipelines.geometry_bind_group)
		wgpu.RenderPassEncoderSetVertexBuffer(
			geom_pass,
			0,
			state.buffers.vertex_buffer,
			0,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderSetIndexBuffer(
			geom_pass,
			state.buffers.triangle_index_buffer,
			.Uint16,
			0,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderDrawIndexed(
			geom_pass,
			state.buffers.triangle_index_count,
			1,
			0,
			0,
			0,
		)

		wgpu.RenderPassEncoderEnd(geom_pass)
		wgpu.RenderPassEncoderRelease(geom_pass)
	}

	// ==========================================================================
	// PASS 2: Geometry Pass (Backface) - Capture inside depth
	// ==========================================================================
	{
		// No color attachments needed for backface pass - just depth
		depth_attachment := wgpu.RenderPassDepthStencilAttachment {
			view            = state.rendering.depth_back_view,
			depthLoadOp     = .Clear,
			depthStoreOp    = .Store,
			depthClearValue = 0.0, // Clear to 0 (near) since we want farthest backface
			depthReadOnly   = false,
		}

		back_pass_desc := wgpu.RenderPassDescriptor {
			label                  = "Geometry Pass (Back)",
			colorAttachmentCount   = 0,
			colorAttachments       = nil,
			depthStencilAttachment = &depth_attachment,
		}

		back_pass := wgpu.CommandEncoderBeginRenderPass(encoder, &back_pass_desc)

		wgpu.RenderPassEncoderSetPipeline(back_pass, state.pipelines.geometry_back_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(back_pass, 0, state.pipelines.geometry_bind_group)
		wgpu.RenderPassEncoderSetVertexBuffer(
			back_pass,
			0,
			state.buffers.vertex_buffer,
			0,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderSetIndexBuffer(
			back_pass,
			state.buffers.triangle_index_buffer,
			.Uint16,
			0,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderDrawIndexed(
			back_pass,
			state.buffers.triangle_index_count,
			1,
			0,
			0,
			0,
		)

		wgpu.RenderPassEncoderEnd(back_pass)
		wgpu.RenderPassEncoderRelease(back_pass)
	}

	// ==========================================================================
	// PASS 3: Shading Pass - Reconstruct final image from G-buffers
	// ==========================================================================
	{
		color_attachment := wgpu.RenderPassColorAttachment {
			view       = texture_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp     = .Clear,
			storeOp    = .Store,
			clearValue = {0.1, 0.1, 0.1, 1.0},
		}

		shade_pass_desc := wgpu.RenderPassDescriptor {
			label                  = "Shading Pass",
			colorAttachmentCount   = 1,
			colorAttachments       = &color_attachment,
			depthStencilAttachment = nil, // No depth for fullscreen quad
		}

		shade_pass := wgpu.CommandEncoderBeginRenderPass(encoder, &shade_pass_desc)

		wgpu.RenderPassEncoderSetPipeline(shade_pass, state.pipelines.shading_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(shade_pass, 0, state.pipelines.shading_bind_group)
		wgpu.RenderPassEncoderDraw(shade_pass, 3, 1, 0, 0) // Fullscreen triangle

		wgpu.RenderPassEncoderEnd(shade_pass)
		wgpu.RenderPassEncoderRelease(shade_pass)
	}

	// ==========================================================================
	// PASS 4: Wireframe Overlay - Draw wireframe on top
	// ==========================================================================
	{
		color_attachment := wgpu.RenderPassColorAttachment {
			view       = texture_view,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			loadOp     = .Load, // Keep existing shaded image
			storeOp    = .Store,
		}

		depth_attachment := wgpu.RenderPassDepthStencilAttachment {
			view            = state.rendering.depth_texture_view,
			depthLoadOp     = .Clear,
			depthStoreOp    = .Store,
			depthClearValue = 1.0,
			depthReadOnly   = false,
		}

		wire_pass_desc := wgpu.RenderPassDescriptor {
			label                  = "Wireframe Pass",
			colorAttachmentCount   = 1,
			colorAttachments       = &color_attachment,
			depthStencilAttachment = &depth_attachment,
		}

		wire_pass := wgpu.CommandEncoderBeginRenderPass(encoder, &wire_pass_desc)

		wgpu.RenderPassEncoderSetPipeline(wire_pass, state.pipelines.wireframe_pipeline)
		wgpu.RenderPassEncoderSetBindGroup(wire_pass, 0, state.pipelines.geometry_bind_group)
		wgpu.RenderPassEncoderSetVertexBuffer(
			wire_pass,
			0,
			state.buffers.vertex_buffer,
			0,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderSetIndexBuffer(
			wire_pass,
			state.buffers.index_buffer,
			.Uint16,
			0,
			wgpu.WHOLE_SIZE,
		)
		wgpu.RenderPassEncoderDrawIndexed(wire_pass, state.buffers.index_count, 1, 0, 0, 0)

		wgpu.RenderPassEncoderEnd(wire_pass)
		wgpu.RenderPassEncoderRelease(wire_pass)
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
	if state.rendering.gbuffer_normal_view != nil do wgpu.TextureViewRelease(state.rendering.gbuffer_normal_view)
	if state.rendering.gbuffer_normal != nil do wgpu.TextureRelease(state.rendering.gbuffer_normal)
	if state.rendering.gbuffer_material_view != nil do wgpu.TextureViewRelease(state.rendering.gbuffer_material_view)
	if state.rendering.gbuffer_material != nil do wgpu.TextureRelease(state.rendering.gbuffer_material)
	if state.rendering.gbuffer_distance_view != nil do wgpu.TextureViewRelease(state.rendering.gbuffer_distance_view)
	if state.rendering.gbuffer_distance != nil do wgpu.TextureRelease(state.rendering.gbuffer_distance)
	if state.rendering.depth_front_view != nil do wgpu.TextureViewRelease(state.rendering.depth_front_view)
	if state.rendering.depth_front != nil do wgpu.TextureRelease(state.rendering.depth_front)
	if state.rendering.depth_back_view != nil do wgpu.TextureViewRelease(state.rendering.depth_back_view)
	if state.rendering.depth_back != nil do wgpu.TextureRelease(state.rendering.depth_back)
}
