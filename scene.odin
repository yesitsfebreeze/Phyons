package phyons

scene_init :: proc() {
	cube_shape := make_cube(2.0, {1.0, 1.0, 1.0})
	add_volume(cube_shape)
}

scene_update :: proc() {

}
