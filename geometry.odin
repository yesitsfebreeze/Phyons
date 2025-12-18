package phyons

import "core:math/linalg"

Vertex :: struct {
	position:           linalg.Vector3f32,
	color:              linalg.Vector3f32,
	reference_centroid: linalg.Vector3f32,
	normal:             linalg.Vector3f32,
	material_id:        f32, // Using f32 for alignment, will be cast to u32 in shader
	opacity:            f32,
	distance_to_center: f32,
	_pad:               f32, // Padding to 64 bytes
}

init_geometry :: proc() -> bool {
	// Create a cube shape using the volume manager
	cube_shape := make_cube_shape(2.0, {1.0, 1.0, 1.0})

	// Add a single cube volume at the origin
	add_volume(cube_shape)

	// Rebuild buffers to upload geometry to GPU
	if !rebuild_volume_buffers() {
		return false
	}

	return true
}

update_geometry :: proc(time: f32) {
	// Upload updated vertices to GPU via buffers module
	update_vertex_buffer()
}

// Geometry cleanup is handled by cleanup_buffers() in buffers.odin
