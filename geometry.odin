package phyons

import "core:os"
import "core:path/filepath"
import "vendor/tinyobj"


Phyon :: struct {
	position:      vec3,
	normal:        vec3,
	depth:         f32,
	opacity:       f32,
	triangle_id:   u32, // Which triangle this vertex belongs to
	vertex_in_tri: u32, // 0, 1, or 2 - position within triangle (for barycentric)
}

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
	num_surfaces := len(obj.attrib.vertices) / 3
	if num_surfaces == 0 {
		log_err("OBJ file has no vertices:", filename)
		return INVALID_SHAPE_ID
	}

	// Build vertex positions array
	surfaces := make([]vec3, num_surfaces)
	defer delete(surfaces)

	for i := 0; i < num_surfaces; i += 1 {
		surfaces[i] = {
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
	inside := vec3{0, 0, 0}
	for s in surfaces do inside += s
	inside /= f32(len(surfaces))

	// Build vertices with all attributes
	vertices := make([]Phyon, num_surfaces)
	defer delete(vertices)

	for i := 0; i < num_surfaces; i += 1 {
		pos := surfaces[i]
		surface := pos - inside
		vertices[i] = Phyon {
			position = inside,
			normal   = normalize(surface),
			depth    = length(surface),
		}
	}

	log_info(
		"Loaded OBJ:",
		filename,
		"- surface points:",
		num_surfaces,
		"faces:",
		len(indices) / 3,
	)

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
