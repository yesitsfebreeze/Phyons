package phyons


// Create a cube shape
make_cube_shape :: proc(size: f32 = 1.0, color: vec3 = {1, 1, 1}) -> ShapeId {
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

	indices := []u32 {
		0,
		1,
		2,
		0,
		2,
		3,
		5,
		4,
		7,
		5,
		7,
		6,
		4,
		0,
		3,
		4,
		3,
		7,
		1,
		5,
		6,
		1,
		6,
		2,
		3,
		2,
		6,
		3,
		6,
		7,
		4,
		5,
		1,
		4,
		1,
		0,
	}

	return make_shape_from_positions(positions, indices, color)
}
