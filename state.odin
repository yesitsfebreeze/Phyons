package phyons

import "core:math/linalg"
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
	vertex_buffer:         wgpu.Buffer,
	index_buffer:          wgpu.Buffer,
	uniform_buffer:        wgpu.Buffer,
	triangle_index_buffer: wgpu.Buffer,
	// Counts
	index_count:           u32,
	triangle_index_count:  u32,
	vertex_count:          u32,
	// Vertex data (CPU-side for updates)
	vertices:              []Vertex,
}

RenderingState :: struct {
	// G-Buffer textures (deferred rendering)
	gbuffer_normal:        wgpu.Texture,
	gbuffer_normal_view:   wgpu.TextureView,
	gbuffer_material:      wgpu.Texture,
	gbuffer_material_view: wgpu.TextureView,
	gbuffer_distance:      wgpu.Texture,
	gbuffer_distance_view: wgpu.TextureView,
	// Depth textures
	depth_front:           wgpu.Texture,
	depth_front_view:      wgpu.TextureView,
	depth_back:            wgpu.Texture,
	depth_back_view:       wgpu.TextureView,
	depth_texture:         wgpu.Texture, // Legacy wireframe depth
	depth_texture_view:    wgpu.TextureView,
	// Dimensions
	gbuffer_width:         u32,
	gbuffer_height:        u32,
}

PipelinesState :: struct {
	// Render pipelines
	geometry_pipeline:         wgpu.RenderPipeline,
	geometry_back_pipeline:    wgpu.RenderPipeline,
	shading_pipeline:          wgpu.RenderPipeline,
	wireframe_pipeline:        wgpu.RenderPipeline,
	// Bind groups
	geometry_bind_group:       wgpu.BindGroup,
	shading_bind_group:        wgpu.BindGroup,
	shading_bind_group_layout: wgpu.BindGroupLayout,
	// Samplers
	gbuffer_sampler:           wgpu.Sampler,
}

Camera :: struct {
	position:     vec3,
	target:       vec3,
	up:           vec3,
	yaw:          f32,
	pitch:        f32,
	radius:       f32,
	last_mouse_x: f64,
	last_mouse_y: f64,
	first_mouse:  bool,
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

state: State

Uniforms :: struct #align (16) {
	view_proj: linalg.Matrix4f32,
	model:     linalg.Matrix4f32,
	time:      f32,
	_pad:      [3]f32,
}
