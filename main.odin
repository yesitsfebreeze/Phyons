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

loop :: proc() {
	glfw.PollEvents()

	// Calculate delta time
	current_time := glfw.GetTime()
	state.dt = f32(current_time - state.last_time)
	state.last_time = current_time
	state.elapsed += state.dt

	update_camera()

	// Rebuild GPU buffers if volumes changed
	rebuild_volume_buffers()

	update_geometry(state.elapsed)
	render_frame()

	state.frame_count += 1
}

init :: proc() -> bool {
	// Initialize window
	if !init_window() {
		fmt.println("Failed to initialize window")
		return false
	}

	// Initialize WebGPU
	if !init_wgpu() {
		fmt.println("Failed to initialize WebGPU")
		return false
	}

	// Load shaders
	if !init_shaders() {
		fmt.println("Failed to load shaders")
		return false
	}

	// Initialize camera
	init_camera()

	// Initialize volume manager
	init_volume_manager()

	// Initialize buffers (uniform buffer needed by pipelines)
	if !init_buffers() {
		fmt.println("Failed to initialize buffers")
		return false
	}

	// Create cube geometry using volume manager
	if !init_geometry() {
		fmt.println("Failed to initialize geometry")
		return false
	}

	// Create render pipelines
	if !init_pipeline() {
		fmt.println("Failed to create pipeline")
		return false
	}

	show_window()
	return true
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
