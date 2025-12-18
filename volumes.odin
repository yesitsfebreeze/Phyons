package phyons


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


// Initialize the volume manager
init_volume_manager :: proc() {
	state.volume_manager.shapes = make([dynamic]Shape)
	state.volume_manager.volumes = make([dynamic]Volume)
	state.volume_manager.dirty = false
}

// Create a shape from vertices and indices, returns a shape_id
make_shape :: proc(vertices: []Phyon, indices: []u32) -> ShapeId {
	num_verts := len(vertices)

	// Copy vertices
	shape_verts := make([]Phyon, num_verts)
	copy(shape_verts, vertices)

	// Compute per-vertex normals if not provided
	vertex_normals := make([]vec3, num_verts)
	defer delete(vertex_normals)

	// Accumulate face normals to vertices
	for i := 0; i < len(indices); i += 3 {
		i0, i1, i2 := int(indices[i]), int(indices[i + 1]), int(indices[i + 2])
		v0 := vertices[i0].position
		v1 := vertices[i1].position
		v2 := vertices[i2].position

		edge1 := v1 - v0
		edge2 := v2 - v0
		face_normal := cross(edge1, edge2)

		vertex_normals[i0] += face_normal
		vertex_normals[i1] += face_normal
		vertex_normals[i2] += face_normal
	}

	// Normalize and update vertex normals (only if they were zero)
	for i := 0; i < num_verts; i += 1 {
		if length(shape_verts[i].normal) < 0.001 {
			n := vertex_normals[i]
			len_sq := dot(n, n)
			if len_sq > 0.0001 {
				shape_verts[i].normal = n / sqrt(len_sq)
			}
		}
	}

	// Copy triangle indices
	tri_indices := make([]u32, len(indices))
	copy(tri_indices, indices)

	// Build wireframe indices from edges
	edge_set := make(map[[2]int]bool)
	defer delete(edge_set)

	for i := 0; i < len(indices); i += 3 {
		a, b, c := int(indices[i]), int(indices[i + 1]), int(indices[i + 2])
		edges := [][2]int{{a, b}, {b, c}, {c, a}}
		for edge in edges {
			sorted_edge := [2]int{min(edge[0], edge[1]), max(edge[0], edge[1])}
			edge_set[sorted_edge] = true
		}
	}

	wire_indices := make([dynamic]u16, 0, len(edge_set) * 2)
	for edge in edge_set {
		append(&wire_indices, u16(edge[0]), u16(edge[1]))
	}

	shape := Shape {
		phyons            = shape_verts,
		triangle_indices  = tri_indices,
		wireframe_indices = wire_indices[:],
	}

	append(&state.volume_manager.shapes, shape)
	return ShapeId(len(state.volume_manager.shapes) - 1)
}

// Create a shape from raw positions and indices (convenience function)
make_shape_from_positions :: proc(
	positions: []vec3,
	indices: []u32,
	color: vec3 = {1, 1, 1},
) -> ShapeId {
	// Compute mesh centroid
	mesh_centroid := vec3{0, 0, 0}
	for pos in positions {
		mesh_centroid += pos
	}
	mesh_centroid /= f32(len(positions))

	// Build vertices
	vertices := make([]Phyon, len(positions))
	defer delete(vertices)

	for i := 0; i < len(positions); i += 1 {
		pos := positions[i]
		dist_to_center := length(pos - mesh_centroid)
		vertices[i] = Phyon {
			position           = pos,
			color              = color,
			reference_centroid = {0, 0, 0},
			normal             = {0, 0, 0}, // Will be computed in make_shape
			material_id        = 1.0,
			opacity            = 1.0,
			distance_to_center = dist_to_center,
			_pad               = 0.0,
		}
	}

	return make_shape(vertices, indices)
}

// Add a volume (instance of a shape) to the scene
add_volume :: proc(
	shape_id: ShapeId,
	transform: mat4 = mat4_IDENTITY,
	color: vec3 = {1, 1, 1},
	opacity: f32 = 1.0,
) -> VolumeId {
	if int(shape_id) >= len(state.volume_manager.shapes) {
		log_err("Invalid shape_id:", shape_id)
		return INVALID_VOLUME_ID
	}

	volume := Volume {
		shape_id  = shape_id,
		transform = transform,
		color     = color,
		opacity   = opacity,
		visible   = true,
	}

	append(&state.volume_manager.volumes, volume)
	state.volume_manager.dirty = true

	return VolumeId(len(state.volume_manager.volumes) - 1)
}

// Remove a volume from the scene
remove_volume :: proc(volume_id: VolumeId) {
	if int(volume_id) >= len(state.volume_manager.volumes) {
		return
	}
	state.volume_manager.volumes[volume_id].visible = false
	state.volume_manager.dirty = true
}

// Set volume visibility
set_volume_visible :: proc(volume_id: VolumeId, visible: bool) {
	if int(volume_id) >= len(state.volume_manager.volumes) {
		return
	}
	state.volume_manager.volumes[volume_id].visible = visible
	state.volume_manager.dirty = true
}

// Update volume transform
set_volume_transform :: proc(volume_id: VolumeId, transform: mat4) {
	if int(volume_id) >= len(state.volume_manager.volumes) {
		return
	}
	state.volume_manager.volumes[volume_id].transform = transform
	state.volume_manager.dirty = true
}

// Update volume color
set_volume_color :: proc(volume_id: VolumeId, color: vec3) {
	if int(volume_id) >= len(state.volume_manager.volumes) {
		return
	}
	state.volume_manager.volumes[volume_id].color = color
	state.volume_manager.dirty = true
}

// Get shape by ID
get_shape :: proc(shape_id: ShapeId) -> ^Shape {
	if int(shape_id) >= len(state.volume_manager.shapes) {
		return nil
	}
	return &state.volume_manager.shapes[shape_id]
}

// Get volume by ID
get_volume :: proc(volume_id: VolumeId) -> ^Volume {
	if int(volume_id) >= len(state.volume_manager.volumes) {
		return nil
	}
	return &state.volume_manager.volumes[volume_id]
}

// Rebuild GPU buffers from all visible volumes
rebuild_volume_buffers :: proc() -> bool {
	if !state.volume_manager.dirty {
		return true
	}

	// Count total vertices and indices
	total_verts := 0
	total_tri_indices := 0
	total_wire_indices := 0

	for &vol in state.volume_manager.volumes {
		if !vol.visible {
			continue
		}
		shape := get_shape(vol.shape_id)
		if shape == nil {
			continue
		}
		total_verts += len(shape.phyons)
		total_tri_indices += len(shape.triangle_indices)
		total_wire_indices += len(shape.wireframe_indices)
	}

	if total_verts == 0 {
		state.volume_manager.dirty = false
		return true
	}

	// Build merged arrays
	merged_verts := make([dynamic]Phyon, 0, total_verts)
	merged_tri_indices := make([dynamic]u16, 0, total_tri_indices)
	merged_wire_indices := make([dynamic]u16, 0, total_wire_indices)
	defer delete(merged_tri_indices)
	defer delete(merged_wire_indices)

	vertex_offset: u32 = 0

	for &vol in state.volume_manager.volumes {
		if !vol.visible {
			continue
		}
		shape := get_shape(vol.shape_id)
		if shape == nil {
			continue
		}

		// Transform and add vertices
		for v in shape.phyons {
			new_vert := v

			// Transform position
			pos4 := vec4{v.position.x, v.position.y, v.position.z, 1.0}
			transformed_pos := vol.transform * pos4
			new_vert.position = {transformed_pos.x, transformed_pos.y, transformed_pos.z}

			// Transform normal (use inverse transpose for correct normal transformation)
			// For simplicity, assuming uniform scale - just rotate the normal
			normal4 := vec4{v.normal.x, v.normal.y, v.normal.z, 0.0}
			transformed_normal := vol.transform * normal4
			new_vert.normal = normalize(
				vec3{transformed_normal.x, transformed_normal.y, transformed_normal.z},
			)

			// Apply volume color and opacity
			new_vert.color = vol.color * v.color
			new_vert.opacity = vol.opacity * v.opacity

			append(&merged_verts, new_vert)
		}

		// Add triangle indices with offset
		for idx in shape.triangle_indices {
			append(&merged_tri_indices, u16(idx + vertex_offset))
		}

		// Add wireframe indices with offset
		for idx in shape.wireframe_indices {
			append(&merged_wire_indices, u16(u32(idx) + vertex_offset))
		}

		vertex_offset += u32(len(shape.phyons))
	}

	// Update state buffers
	if state.buffers.vertices != nil {
		delete(state.buffers.vertices)
	}
	state.buffers.vertices = merged_verts[:]
	state.buffers.vertex_count = u32(len(merged_verts))

	// Create GPU buffers
	if !create_vertex_buffer(merged_verts[:]) {
		return false
	}

	if !create_index_buffer(merged_wire_indices[:]) {
		return false
	}

	if !create_triangle_index_buffer(merged_tri_indices[:]) {
		return false
	}

	state.volume_manager.dirty = false
	return true
}

// Mark volumes as dirty (need buffer rebuild)
mark_volumes_dirty :: proc() {
	state.volume_manager.dirty = true
}

// Cleanup volume manager
cleanup_volume_manager :: proc() {
	for &shape in state.volume_manager.shapes {
		if shape.phyons != nil do delete(shape.phyons)
		if shape.triangle_indices != nil do delete(shape.triangle_indices)
		if shape.wireframe_indices != nil do delete(shape.wireframe_indices)
	}
	delete(state.volume_manager.shapes)
	delete(state.volume_manager.volumes)
}


translate_volume :: proc(volume_id: VolumeId, translation: vec3) {
	vol := get_volume(volume_id)
	if vol == nil {
		return
	}
	translation_matrix := mat4_translate(translation)
	vol.transform = translation_matrix * vol.transform
	state.volume_manager.dirty = true
}
