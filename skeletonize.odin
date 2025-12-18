package phyons

SkeletonResult :: struct {
	original_vertices:  []vec3,
	innermost_vertices: []vec3,
	indices:            []u32,
}

// Ray-triangle intersection (Möller–Trumbore)
ray_triangle_intersect :: proc(origin, dir, v0, v1, v2: vec3) -> (bool, f32) {
	edge1, edge2 := v1 - v0, v2 - v0
	h := cross(dir, edge2)
	a := dot(edge1, h)
	if abs(a) < 0.0000001 do return false, 0

	f := 1.0 / a
	s := origin - v0
	u := f * dot(s, h)
	if u < 0 || u > 1 do return false, 0

	q := cross(s, edge1)
	v := f * dot(dir, q)
	if v < 0 || u + v > 1 do return false, 0

	t := f * dot(edge2, q)
	return t > 0.0000001, t
}

skeletonize :: proc(vertices: []vec3, indices: []u32) -> SkeletonResult {
	original := make([]vec3, len(vertices))
	copy(original, vertices)

	// Accumulate skeleton points per vertex
	skel_sum := make([]vec3, len(vertices))
	skel_count := make([]int, len(vertices))
	defer delete(skel_sum)
	defer delete(skel_count)

	// Process each face
	for face := 0; face < len(indices) / 3; face += 1 {
		i := face * 3
		a, b, c := indices[i], indices[i + 1], indices[i + 2]
		v0, v1, v2 := vertices[a], vertices[b], vertices[c]

		// Face centroid and inward normal
		centroid := (v0 + v1 + v2) / 3.0
		normal := cross(v1 - v0, v2 - v0)
		if dot(normal, normal) < 0.0001 do continue
		ray_dir := -normalize(normal)

		// Find closest hit on opposite side
		closest := INF
		for other := 0; other < len(indices); other += 3 {
			if other / 3 == face do continue
			hit, t := ray_triangle_intersect(
				centroid,
				ray_dir,
				vertices[indices[other]],
				vertices[indices[other + 1]],
				vertices[indices[other + 2]],
			)
			if hit && t < closest do closest = t
		}

		// Skeleton point = midpoint to opposite side (or centroid if no hit)
		skel_pt := centroid if closest == INF else centroid + ray_dir * (closest * 0.5)

		// Add to all 3 vertices of this face
		skel_sum[a] += skel_pt
		skel_count[a] += 1
		skel_sum[b] += skel_pt
		skel_count[b] += 1
		skel_sum[c] += skel_pt
		skel_count[c] += 1
	}

	// Average per vertex
	result := make([]vec3, len(vertices))
	for i in 0 ..< len(vertices) {
		result[i] = skel_sum[i] / f32(skel_count[i]) if skel_count[i] > 0 else vertices[i]
	}

	result_indices := make([]u32, len(indices))
	copy(result_indices, indices)
	return {original, result, result_indices}
}
