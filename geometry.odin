package phyons

import "core:os"
import "core:path/filepath"
import "vendor/tinyobj"


// Split phyon storage for GPU - inside and outside positions in parallel buffers
// Same index in both buffers = same logical phyon

// Inside phyon - 16 bytes (centroid position + material)
Phyon_Inside :: struct {
	position:    vec3, // Interior/centroid position (12 bytes)
	material_id: u32, // Interior material ID (4 bytes)
}

// Outside phyon - 32 bytes (surface position + normal + material)
Phyon_Outside :: struct {
	position:    vec3, // Surface position (12 bytes)
	material_id: u32, // Surface material ID (4 bytes)
	normal:      vec3, // Surface normal (12 bytes)
	_pad:        u32, // Padding for alignment (4 bytes)
}

// Legacy combined struct for compatibility during transition
Phyon :: struct {
	position: vec3, // Interior/centroid position (12 bytes)
	depth:    f32, // Distance to surface (4 bytes)
	normal:   vec3, // Surface normal (12 bytes)
	opacity:  f32, // Opacity (4 bytes)
}

// Assets directory relative to working directory (project root when using odin run .)
@(private = "file")
ASSETS_DIR :: "../assets/"

// Load a shape from an OBJ file using tinyobj
// Returns INVALID_SHAPE_ID on failure
load_obj_shape :: proc(filename: string, color: vec3 = {1, 1, 1}) -> ShapeId {

	rel := relative_path(filename, ASSETS_DIR, context.temp_allocator)
	path := join_path({ASSETS_DIR, rel}, context.temp_allocator)

	// Read the OBJ file
	data, ok := os.read_entire_file(path)
	if !ok {
		log_err("Failed to read OBJ file:", filename)
		return INVALID_SHAPE_ID
	}
	defer delete(data)

	// Get the base directory for material files
	base_dir := filepath.dir(filename)
	defer if len(base_dir) > 0 {
		delete(base_dir)
	}

	// Parse the OBJ file with triangulation enabled
	obj := tinyobj.parse_obj(string(data), base_dir, tinyobj.FLAG_TRIANGULATE)
	defer tinyobj.destroy(&obj)

	if !obj.success {
		log_err("Failed to parse OBJ file:", filename)
		return INVALID_SHAPE_ID
	}

	// Extract positions from tinyobj attrib (3 floats per vertex)
	num_verts := len(obj.attrib.vertices) / 3
	if num_verts == 0 {
		log_err("OBJ file has no vertices:", filename)
		return INVALID_SHAPE_ID
	}

	// Build vertex positions array
	positions := make([]vec3, num_verts)
	defer delete(positions)

	for i := 0; i < num_verts; i += 1 {
		positions[i] = {
			obj.attrib.vertices[i * 3 + 0],
			obj.attrib.vertices[i * 3 + 1],
			obj.attrib.vertices[i * 3 + 2],
		}
	}

	// Build indices from faces (each face is a triangle after FLAG_TRIANGULATE)
	num_faces := len(obj.attrib.face_num_verts)
	indices := make([dynamic]u32)
	defer delete(indices)

	face_idx := 0
	for f := 0; f < num_faces; f += 1 {
		num_face_verts := obj.attrib.face_num_verts[f]
		for v := 0; v < num_face_verts; v += 1 {
			vi := obj.attrib.faces[face_idx]
			if vi.v_idx != tinyobj.INVALID_INDEX {
				append(&indices, u32(vi.v_idx))
			}
			face_idx += 1
		}
	}

	if len(indices) == 0 {
		log_err("OBJ file has no valid faces:", filename)
		return INVALID_SHAPE_ID
	}

	// Compute mesh centroid
	centroid := vec3{0, 0, 0}
	for p in positions {
		centroid += p
	}
	centroid /= f32(num_verts)

	// Build split phyon buffers
	inside_phyons := make([]Phyon_Inside, num_verts)
	outside_phyons := make([]Phyon_Outside, num_verts)
	defer delete(inside_phyons)
	defer delete(outside_phyons)

	for i := 0; i < num_verts; i += 1 {
		pos := positions[i]
		to_surface := pos - centroid
		normal := normalize(to_surface)

		inside_phyons[i] = Phyon_Inside {
			position    = centroid,
			material_id = 0, // Default material
		}
		outside_phyons[i] = Phyon_Outside {
			position    = pos,
			material_id = 0, // Default material
			normal      = normal,
		}
	}

	num_tris := len(indices) / 3
	log_info("Loaded OBJ:", filename, "- vertices:", num_verts, "faces:", num_tris)

	free_all(context.temp_allocator)
	return make_shape(inside_phyons, outside_phyons, indices[:])
}

init_geometry :: proc() -> bool {
	// Rebuild buffers to upload geometry to GPU
	if !rebuild_volume_buffers() {
		return false
	}

	return true
}

update_geometry :: proc(_time: f32) {
	// Currently no per-frame vertex updates needed
	// Split phyon buffers are updated on demand via rebuild_volume_buffers
}

// Geometry cleanup is handled by cleanup_buffers() in buffers.odin
