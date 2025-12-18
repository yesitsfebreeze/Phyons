package phyons

// Create a Fibonacci sphere with spiral line connections
make_sphere :: proc(radius: f32 = 1.0, num_points: int = 256, color: vec3 = {1, 1, 1}) -> ShapeId {
	// Golden ratio for Fibonacci distribution
	PHI :: 1.618033988749895
	golden_angle := PI * (3.0 - sqrt(f32(5.0))) // ~2.39996 radians

	positions := make([]vec3, num_points)
	defer delete(positions)

	// Generate Fibonacci sphere points
	for i := 0; i < num_points; i += 1 {
		// y goes from 1 to -1 (top to bottom)
		y := 1.0 - (f32(i) / f32(num_points - 1)) * 2.0

		// radius at this y level
		r := sqrt(1.0 - y * y)

		// golden angle increment
		theta := golden_angle * f32(i)

		x := cos(theta) * r
		z := sin(theta) * r

		positions[i] = vec3{x, y, z} * radius
	}

	// Create indices for spiral line segments (connect consecutive points)
	// Each line segment needs 2 indices, and we create degenerate triangles for lines
	// Using triangle list: for each line segment, create a thin triangle
	num_segments := num_points - 1
	indices := make([]u32, num_segments * 3)
	defer delete(indices)

	for i := 0; i < num_segments; i += 1 {
		// Create degenerate triangle (line) by repeating one vertex
		indices[i * 3 + 0] = u32(i)
		indices[i * 3 + 1] = u32(i + 1)
		indices[i * 3 + 2] = u32(i + 1) // Degenerate - makes a line visually
	}

	return make_shape_from_positions(positions, indices)
}


// Create a cube shape
make_cube :: proc(size: f32 = 1.0, color: vec3 = {1, 1, 1}) -> ShapeId {
	half := size * 0.5

	positions := []vec3 {
		{-half, -half, -half}, // 0
		{half, -half, -half}, // 1
		{half, half, -half}, // 2
		{-half, half, -half}, // 3
		{-half, -half, half}, // 4
		{half, -half, half}, // 5
		{half, half, half}, // 6
		{-half, half, half}, // 7
	}

	indices: [dynamic]u32
	defer delete(indices)
	append(&indices, 0, 2, 1)
	append(&indices, 0, 3, 2)
	append(&indices, 5, 7, 4)
	append(&indices, 5, 6, 7)
	append(&indices, 4, 3, 0)
	append(&indices, 4, 7, 3)
	append(&indices, 1, 6, 5)
	append(&indices, 1, 2, 6)
	append(&indices, 3, 6, 2)
	append(&indices, 3, 7, 6)
	append(&indices, 4, 1, 5)
	append(&indices, 4, 0, 1)

	return make_shape_from_positions(positions, indices[:])
}
