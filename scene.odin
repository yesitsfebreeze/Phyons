package phyons

scene_init :: proc() {

	sphere := load_obj_shape("fibonacci-sphere.obj", {0.8, 0.2, 0.2})
	add_volume(sphere)
	// translate_volume(v_sphere, {0.75, 0.0, 0.0})

	// cube := make_cube(1.0, {0.2, 0.8, 0.2})
	// add_volume(cube)
}

scene_update :: proc() {

}
