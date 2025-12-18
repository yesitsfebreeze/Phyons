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
	vertex_buffer:         wgpu.Buffer,
	index_buffer:          wgpu.Buffer,
	uniform_buffer:        wgpu.Buffer,
	triangle_index_buffer: wgpu.Buffer,
	// Counts
	index_count:           u32,
	triangle_index_count:  u32,
	vertex_count:          u32,
	// Vertex data (CPU-side for updates)
	vertices:              []Phyon,
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
	view_proj: mat4,
	model:     mat4,
	time:      f32,
	_pad:      [3]f32,
}


Phyon :: struct {
	position:           vec3,
	color:              vec3,
	reference_centroid: vec3,
	normal:             vec3,
	material_id:        f32, // Using f32 for alignment, will be cast to u32 in shader
	opacity:            f32,
	distance_to_center: f32,
	_pad:               f32, // Padding to 64 bytes
}

// A Shape is a reusable geometry definition (vertices + indices)
Shape :: struct {
	phyons:            []Phyon,
	triangle_indices:  []u32, // Triangle indices for geometry pass
	wireframe_indices: []u16, // Edge indices for wireframe pass
}

// A Volume is an instance of a shape in the world
Volume :: struct {
	shape_id:  ShapeId,
	transform: mat4,
	color:     vec3,
	opacity:   f32,
	visible:   bool,
}

ShapeId :: distinct u32
VolumeId :: distinct u32

INVALID_SHAPE_ID :: ShapeId(max(u32))
INVALID_VOLUME_ID :: VolumeId(max(u32))

VolumeManagerState :: struct {
	shapes:  [dynamic]Shape,
	volumes: [dynamic]Volume,
	dirty:   bool, // True if buffers need rebuild
}
