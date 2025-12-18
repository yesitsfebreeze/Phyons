package phyons

scene_init :: proc() {
	shape := load_obj_shape("fibonacci-sphere.obj", {0.8, 0.2, 0.2})
	add_volume(shape)

	shape2 := make_cube(1.0, {0.2, 0.8, 0.2})
	volume2 := add_volume(shape2)

	translate_volume(volume2, {0.75, 0.0, 0.0})

}

scene_update :: proc() {

}
