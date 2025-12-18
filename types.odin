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
	// Geometry buffers
	phyon_buffer:          wgpu.Buffer,
	index_buffer:          wgpu.Buffer,
	uniform_buffer:        wgpu.Buffer,
	triangle_index_buffer: wgpu.Buffer,
	// Counts
	index_count:           u32,
	triangle_index_count:  u32,
	phyon_count:           u32,
	// Vertex data (CPU-side for updates)
	phyons:                []Phyon,
}

RenderingState :: struct {
	// Depth texture
	depth_texture:             wgpu.Texture,
	depth_texture_view:        wgpu.TextureView,
	// Custom depth buffer (for volume rendering)
	custom_depth_texture:      wgpu.Texture,
	custom_depth_texture_view: wgpu.TextureView,
	// Dimensions
	depth_width:               u32,
	depth_height:              u32,
}

PipelinesState :: struct {
	// Render pipeline
	geometry_pipeline:   wgpu.RenderPipeline,
	// Bind groups
	geometry_bind_group: wgpu.BindGroup,
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
	model:         mat4,
	time:          f32,
	screen_width:  f32,
	screen_height: f32,
	_pad:          f32,
}
