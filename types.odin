package phyons

import "vendor:glfw"
import "vendor:wgpu"

WgpuState :: struct {
	instance:       wgpu.Instance,
	surface:        wgpu.Surface,
	adapter:        wgpu.Adapter,
	device:         wgpu.Device,
	queue:          wgpu.Queue,
	surface_config: wgpu.SurfaceConfiguration,
}

BuffersState :: struct {
	// Split phyon buffers (new architecture)
	inside_phyon_buffer:   wgpu.Buffer,
	outside_phyon_buffer:  wgpu.Buffer,
	volume_info_buffer:    wgpu.Buffer,
	draw_order_buffer:     wgpu.Buffer,
	// Other buffers
	uniform_buffer:        wgpu.Buffer,
	triangle_index_buffer: wgpu.Buffer,
	depth_buffer:          wgpu.Buffer, // Software depth for compute shader
	// Counts
	triangle_index_count:  u32,
	phyon_count:           u32,
	face_count:            u32,
	volume_count:          u32,
	// CPU-side data
	inside_phyons:         []Phyon_Inside,
	outside_phyons:        []Phyon_Outside,
	volume_infos:          []VolumeGPU,
	// Legacy (to be removed)
	phyon_buffer:          wgpu.Buffer,
	phyons:                []Phyon,
}

RenderingState :: struct {
	// Output texture (final image from compute pass)
	output_texture:      wgpu.Texture,
	output_texture_view: wgpu.TextureView,
	// Dimensions
	render_width:        u32,
	render_height:       u32,
}

PipelinesState :: struct {
	// Clear compute pipeline
	clear_pipeline:     wgpu.ComputePipeline,
	// Drawing compute pipeline (pure compute rasterization)
	drawing_pipeline:   wgpu.ComputePipeline,
	drawing_bind_group: wgpu.BindGroup,
	// Present pipeline (renders output texture to screen)
	present_pipeline:   wgpu.RenderPipeline,
	present_bind_group: wgpu.BindGroup,
}


State :: struct {
	window:         glfw.WindowHandle,
	width:          i32,
	height:         i32,
	frame_count:    u64,
	dt:             f32,
	last_time:      f64,
	elapsed:        f32,

	// States
	gapi:           WgpuState,
	shaders:        ShadersState,
	buffers:        BuffersState,
	rendering:      RenderingState,
	pipelines:      PipelinesState,
	camera:         Camera,
	volume_manager: VolumeManagerState,
}


Uniforms :: struct #align (16) {
	view_proj:     mat4,
	inv_view_proj: mat4,
	view:          mat4, // View matrix for depth sorting
	camera_pos:    vec3,
	time:          f32,
	screen_width:  f32,
	screen_height: f32,
	volume_count:  u32,
	_pad:          u32,
}

// GPU-side volume info for compute shader - 96 bytes aligned
VolumeGPU :: struct #align (16) {
	model:          mat4, // Model transform (64 bytes)
	centroid:       vec3, // Center point for depth sorting (12 bytes)
	phyon_offset:   u32, // Start index in phyon buffers (4 bytes)
	phyon_count:    u32, // Number of phyons (4 bytes)
	index_offset:   u32, // Start index in index buffer (4 bytes)
	triangle_count: u32, // Number of triangles (4 bytes)
	_pad:           u32, // Padding (4 bytes)
}
