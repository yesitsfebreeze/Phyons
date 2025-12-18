package phyons

import "core:fmt"
import "vendor:glfw"

main :: proc() {
	if !init() {
		fmt.println("Failed to initialize")
		return
	}
	defer cleanup()

	fmt.println("Starting render loop...")

	// Initialize timing
	state.last_time = glfw.GetTime()

	// Main loop
	for !glfw.WindowShouldClose(state.window) {
		loop()
	}

	fmt.println("Shutting down...")
}

init :: proc() -> bool {
	if !init_window() {
		fmt.println("Failed to initialize window")
		return false
	}

	if !init_wgpu() {
		fmt.println("Failed to initialize WebGPU")
		return false
	}

	if !init_shaders() {
		fmt.println("Failed to load shaders")
		return false
	}

	init_camera()
	init_volume_manager()

	if !init_buffers() {
		fmt.println("Failed to initialize buffers")
		return false
	}

	if !init_geometry() {
		fmt.println("Failed to initialize geometry")
		return false
	}

	if !init_pipeline() {
		fmt.println("Failed to create pipeline")
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
