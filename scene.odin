package phyons

scene_init :: proc() {
	shape := load_obj_shape("assets/fibonacci-sphere.obj", {0.8, 0.2, 0.2})
	add_volume(shape)
}

scene_update :: proc() {

}
