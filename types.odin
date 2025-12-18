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
	depth_buffer:          wgpu.Buffer, // Software depth for compute shader
	// Counts
	index_count:           u32,
	triangle_index_count:  u32,
	phyon_count:           u32,
	face_count:            u32,
	// Vertex data (CPU-side for updates)
	phyons:                []Phyon,
}

RenderingState :: struct {
	// Hardware depth texture (z-buffer for rasterize pass)
	depth_texture:           wgpu.Texture,
	depth_texture_view:      wgpu.TextureView,
	// Inside+depth texture (xyz=inside position, w=phyon depth)
	inside_depth_texture:      wgpu.Texture,
	inside_depth_texture_view: wgpu.TextureView,
	// Normal+material texture (xyz=normal, w=material_id)
	normal_material_texture:      wgpu.Texture,
	normal_material_texture_view: wgpu.TextureView,
	// Output texture (final image from compute pass)
	output_texture:          wgpu.Texture,
	output_texture_view:     wgpu.TextureView,
	// Dimensions
	depth_width:             u32,
	depth_height:            u32,
}

PipelinesState :: struct {
	// Rasterize pipeline (outputs inside+depth and normal+material)
	rasterize_pipeline:   wgpu.RenderPipeline,
	rasterize_bind_group: wgpu.BindGroup,
	// Clear compute pipeline
	clear_pipeline:       wgpu.ComputePipeline,
	// Drawing compute pipeline (reprojects to smooth surface)
	drawing_pipeline:     wgpu.ComputePipeline,
	drawing_bind_group:   wgpu.BindGroup,
	// Present pipeline (renders output texture to screen)
	present_pipeline:     wgpu.RenderPipeline,
	present_bind_group:   wgpu.BindGroup,
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
	model:         mat4,
	camera_pos:    vec3,
	time:          f32,
	screen_width:  f32,
	screen_height: f32,
	phyon_count:   f32,
	face_count:    f32,
}
