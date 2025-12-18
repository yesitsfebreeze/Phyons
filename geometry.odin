package phyons

import "core:os"
import "core:path/filepath"
import "vendor/tinyobj"


// Load a shape from an OBJ file using tinyobj
// Returns INVALID_SHAPE_ID on failure
load_obj_shape :: proc(filename: string, color: vec3 = {1, 1, 1}) -> ShapeId {
	// Read the OBJ file
	data, ok := os.read_entire_file(filename)
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
	num_positions := len(obj.attrib.vertices) / 3
	if num_positions == 0 {
		log_err("OBJ file has no vertices:", filename)
		return INVALID_SHAPE_ID
	}

	// Extract normals (3 floats per normal)
	num_normals := len(obj.attrib.normals) / 3

	// Build vertex positions array
	positions := make([]vec3, num_positions)
	defer delete(positions)

	for i := 0; i < num_positions; i += 1 {
		positions[i] = {
			obj.attrib.vertices[i * 3 + 0],
			obj.attrib.vertices[i * 3 + 1],
			obj.attrib.vertices[i * 3 + 2],
		}
	}

	// Build normals array if available
	normals: []vec3
	if num_normals > 0 {
		normals = make([]vec3, num_normals)
		defer delete(normals)
		for i := 0; i < num_normals; i += 1 {
			normals[i] = {
				obj.attrib.normals[i * 3 + 0],
				obj.attrib.normals[i * 3 + 1],
				obj.attrib.normals[i * 3 + 2],
			}
		}
	}

	// Build indices from faces (each face is a triangle after FLAG_TRIANGULATE)
	num_faces := len(obj.attrib.face_num_verts)
	indices := make([dynamic]u32)
	defer delete(indices)

	face_idx := 0
	for f := 0; f < num_faces; f += 1 {
		num_verts := obj.attrib.face_num_verts[f]
		for v := 0; v < num_verts; v += 1 {
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
	mesh_centroid := vec3{0, 0, 0}
	for pos in positions {
		mesh_centroid += pos
	}
	mesh_centroid /= f32(len(positions))

	// Build vertices with all attributes
	vertices := make([]Phyon, num_positions)
	defer delete(vertices)

	for i := 0; i < num_positions; i += 1 {
		pos := positions[i]
		dist_to_center := length(pos - mesh_centroid)
		vertices[i] = Phyon {
			position           = pos,
			color              = color,
			reference_centroid = {0, 0, 0},
			normal             = {0, 0, 0}, // Will be computed in make_shape if not set
			material_id        = 1.0,
			opacity            = 1.0,
			distance_to_center = dist_to_center,
			_pad               = 0.0,
		}
	}

	// Apply normals from OBJ if available (indexed separately in OBJ format)
	// Note: OBJ allows different normal indices per face vertex, but we're using
	// a simpler approach where normals are computed per-vertex in make_shape
	// For more accurate OBJ normal support, we'd need to expand vertices

	log_info("Loaded OBJ:", filename, "- vertices:", num_positions, "triangles:", len(indices) / 3)

	return make_shape(vertices, indices[:])
}

init_geometry :: proc() -> bool {
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
