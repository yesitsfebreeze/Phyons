package phyons


// A Shape is a reusable geometry definition (split phyon buffers + indices)
Shape :: struct {
	inside_phyons:    []Phyon_Inside,
	outside_phyons:   []Phyon_Outside,
	triangle_indices: []u32,
	centroid:         vec3, // Average of inside positions, for depth sorting
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

// Create a shape from split phyon buffers and indices, returns a shape_id
make_shape :: proc(
	inside_phyons: []Phyon_Inside,
	outside_phyons: []Phyon_Outside,
	indices: []u32,
) -> ShapeId {
	assert(len(inside_phyons) == len(outside_phyons), "Inside/outside phyon counts must match")

	num_verts := len(inside_phyons)

	// Copy inside phyons
	shape_inside := make([]Phyon_Inside, num_verts)
	copy(shape_inside, inside_phyons)

	// Copy outside phyons
	shape_outside := make([]Phyon_Outside, num_verts)
	copy(shape_outside, outside_phyons)

	// Copy triangle indices
	tri_indices := make([]u32, len(indices))
	copy(tri_indices, indices)

	// Compute centroid from inside positions
	centroid := vec3{0, 0, 0}
	for p in inside_phyons {
		centroid += p.position
	}
	if num_verts > 0 {
		centroid /= f32(num_verts)
	}

	shape := Shape {
		inside_phyons    = shape_inside,
		outside_phyons   = shape_outside,
		triangle_indices = tri_indices,
		centroid         = centroid,
	}

	append(&state.volume_manager.shapes, shape)
	return ShapeId(len(state.volume_manager.shapes) - 1)
}

// Create a shape from raw positions and indices (convenience function)
make_shape_from_positions :: proc(positions: []vec3, indices: []u32) -> ShapeId {
	// Compute mesh centroid
	mesh_centroid := vec3{0, 0, 0}
	for pos in positions {
		mesh_centroid += pos
	}
	mesh_centroid /= f32(len(positions))

	// Build split phyon buffers
	inside_phyons := make([]Phyon_Inside, len(positions))
	outside_phyons := make([]Phyon_Outside, len(positions))
	defer delete(inside_phyons)
	defer delete(outside_phyons)

	for i := 0; i < len(positions); i += 1 {
		pos := positions[i]
		to_surface := pos - mesh_centroid
		normal := normalize(to_surface)

		inside_phyons[i] = Phyon_Inside {
			position    = mesh_centroid,
			material_id = 0,
		}
		outside_phyons[i] = Phyon_Outside {
			position    = pos,
			material_id = 0,
			normal      = normal,
		}
	}

	return make_shape(inside_phyons, outside_phyons, indices)
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

	// Count totals and visible volumes
	total_verts := 0
	total_triangles := 0
	visible_volume_count := 0

	for &vol in state.volume_manager.volumes {
		if !vol.visible {
			continue
		}
		shape := get_shape(vol.shape_id)
		if shape == nil {
			continue
		}
		total_verts += len(shape.inside_phyons)
		total_triangles += len(shape.triangle_indices) / 3
		visible_volume_count += 1
	}

	if total_verts == 0 {
		state.volume_manager.dirty = false
		return true
	}

	// Build merged arrays
	merged_inside := make([dynamic]Phyon_Inside, 0, total_verts)
	merged_outside := make([dynamic]Phyon_Outside, 0, total_verts)
	merged_tri_indices := make([dynamic]u32, 0, total_triangles * 3)
	volume_infos := make([dynamic]VolumeGPU, 0, visible_volume_count)
	defer delete(merged_tri_indices)

	vertex_offset: u32 = 0
	index_offset: u32 = 0

	for &vol in state.volume_manager.volumes {
		if !vol.visible {
			continue
		}
		shape := get_shape(vol.shape_id)
		if shape == nil {
			continue
		}

		num_phyons := u32(len(shape.inside_phyons))
		num_triangles := u32(len(shape.triangle_indices) / 3)

		// Transform centroid to world space
		centroid4 := vec4{shape.centroid.x, shape.centroid.y, shape.centroid.z, 1.0}
		world_centroid := vol.transform * centroid4

		// Add volume info
		vol_info := VolumeGPU {
			model          = vol.transform,
			centroid       = {world_centroid.x, world_centroid.y, world_centroid.z},
			phyon_offset   = vertex_offset,
			phyon_count    = num_phyons,
			index_offset   = index_offset,
			triangle_count = num_triangles,
		}
		append(&volume_infos, vol_info)

		// Transform and add phyons
		for i := 0; i < int(num_phyons); i += 1 {
			inside := shape.inside_phyons[i]
			outside := shape.outside_phyons[i]

			// Transform inside position
			in_pos4 := vec4{inside.position.x, inside.position.y, inside.position.z, 1.0}
			in_transformed := vol.transform * in_pos4

			// Transform outside position
			out_pos4 := vec4{outside.position.x, outside.position.y, outside.position.z, 1.0}
			out_transformed := vol.transform * out_pos4

			// Transform normal (direction - no translation, w=0)
			normal4 := vec4{outside.normal.x, outside.normal.y, outside.normal.z, 0.0}
			normal_transformed := vol.transform * normal4
			new_normal := normalize(
				vec3{normal_transformed.x, normal_transformed.y, normal_transformed.z},
			)

			append(
				&merged_inside,
				Phyon_Inside {
					position = {in_transformed.x, in_transformed.y, in_transformed.z},
					material_id = inside.material_id,
				},
			)
			append(
				&merged_outside,
				Phyon_Outside {
					position = {out_transformed.x, out_transformed.y, out_transformed.z},
					material_id = outside.material_id,
					normal = new_normal,
				},
			)
		}

		// Add triangle indices with offset
		for idx in shape.triangle_indices {
			append(&merged_tri_indices, idx + vertex_offset)
		}

		vertex_offset += num_phyons
		index_offset += num_triangles * 3
	}

	// Update state buffers - clean up old
	if state.buffers.inside_phyons != nil do delete(state.buffers.inside_phyons)
	if state.buffers.outside_phyons != nil do delete(state.buffers.outside_phyons)
	if state.buffers.volume_infos != nil do delete(state.buffers.volume_infos)

	state.buffers.inside_phyons = merged_inside[:]
	state.buffers.outside_phyons = merged_outside[:]
	state.buffers.volume_infos = volume_infos[:]
	state.buffers.phyon_count = u32(len(merged_inside))
	state.buffers.face_count = u32(total_triangles)
	state.buffers.volume_count = u32(visible_volume_count)

	// Create GPU buffers
	if !create_split_phyon_buffers(merged_inside[:], merged_outside[:]) {
		return false
	}

	if !create_volume_info_buffer(volume_infos[:]) {
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
		if shape.inside_phyons != nil do delete(shape.inside_phyons)
		if shape.outside_phyons != nil do delete(shape.outside_phyons)
		if shape.triangle_indices != nil do delete(shape.triangle_indices)
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
