package phyons

import "core:fmt"
import "vendor:glfw"

init_window :: proc() -> bool {
	// Initialize GLFW
	if !glfw.Init() {
		fmt.println("Failed to initialize GLFW")
		return false
	}

	// Create window (no OpenGL context - using WebGPU)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)

	state.window = glfw.CreateWindow(
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		"Phyons",
		nil,
		nil,
	)

	if state.window == nil {
		fmt.println("Failed to create window")
		return false
	}

	// Set up input callbacks
	glfw.SetCursorPosCallback(state.window, mouse_callback)
	glfw.SetScrollCallback(state.window, scroll_callback)
	glfw.SetWindowSizeCallback(state.window, resize_callback)

	return true
}

show_window :: proc() {
	glfw.ShowWindow(state.window)
}

cleanup_window :: proc() {
	if state.window != nil {
		glfw.DestroyWindow(state.window)
	}
	glfw.Terminate()
}
