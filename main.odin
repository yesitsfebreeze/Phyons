package phyons

import "vendor:glfw"

state: State

main :: proc() {
	init_logging()
	defer cleanup_logging()

	if !init() {
		log_err("Failed to initialize")
		return
	}
	defer cleanup()

	log_info("Starting render loop...")

	state.last_time = glfw.GetTime()
	for !glfw.WindowShouldClose(state.window) {
		loop()
	}

	log_info("Shutting down...")
}

init :: proc() -> bool {
	if !init_window() {
		log_err("Failed to initialize window")
		return false
	}

	if !init_wgpu() {
		log_err("Failed to initialize WebGPU")
		return false
	}

	if !init_shaders() {
		log_err("Failed to load shaders")
		return false
	}

	init_camera()
	init_volume_manager()

	// Initialize scene (creates shapes and volumes)
	scene_init()

	if !init_buffers() {
		log_err("Failed to initialize buffers")
		return false
	}

	if !init_geometry() {
		log_err("Failed to initialize geometry")
		return false
	}

	if !init_pipeline() {
		log_err("Failed to create pipeline")
		return false
	}

	show_window()
	return true
}

loop :: proc() {
	glfw.PollEvents()

	// Calculate delta time
	current_time := glfw.GetTime()
	state.dt = f32(current_time - state.last_time)
	state.last_time = current_time
	state.elapsed += state.dt

	update_camera()
	rebuild_volume_buffers()
	scene_update()
	render_frame()

	state.frame_count += 1
}

cleanup :: proc() {
	cleanup_rendering()
	cleanup_buffers()
	cleanup_volume_manager()
	cleanup_pipelines()
	cleanup_shaders()
	cleanup_wgpu()
	cleanup_window()
}
