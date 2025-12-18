package phyons

import "base:runtime"
import "core:math"
import "core:math/linalg"
import "vendor:glfw"
import "vendor:wgpu"

init_camera :: proc() {
	state.camera = Camera {
		position    = {0, 0, 5},
		target      = {0, 0, 0},
		up          = {0, 1, 0},
		yaw         = -90.0,
		pitch       = 0.0,
		radius      = 5.0,
		first_mouse = true,
	}
}

update_camera :: proc() {
	c := &state.camera

	// Convert spherical to cartesian
	yaw_rad := math.to_radians(c.yaw)
	pitch_rad := math.to_radians(c.pitch)

	c.position = vec3 {
		c.radius * math.cos(pitch_rad) * math.cos(yaw_rad),
		c.radius * math.sin(pitch_rad),
		c.radius * math.cos(pitch_rad) * math.sin(yaw_rad),
	}

	// Handle keyboard input
	if glfw.GetKey(state.window, glfw.KEY_W) == glfw.PRESS {
		c.radius = max(MIN_RADIUS, c.radius - ZOOM_SENSITIVITY * 0.1)
	}
	if glfw.GetKey(state.window, glfw.KEY_S) == glfw.PRESS {
		c.radius = min(MAX_RADIUS, c.radius + ZOOM_SENSITIVITY * 0.1)
	}
}

get_view_matrix :: proc() -> linalg.Matrix4f32 {
	c := &state.camera
	return linalg.matrix4_look_at_f32(c.position, c.target, c.up)
}

get_projection_matrix :: proc() -> linalg.Matrix4f32 {
	aspect := f32(state.width) / f32(state.height)
	return linalg.matrix4_perspective_f32(math.to_radians(f32(45)), aspect, 0.1, 100.0)
}

mouse_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	context = runtime.default_context()

	c := &state.camera

	// Only rotate if left mouse button is pressed
	if glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS {
		if c.first_mouse {
			c.last_mouse_x = xpos
			c.last_mouse_y = ypos
			c.first_mouse = false
		}

		xoffset := xpos - c.last_mouse_x
		yoffset := c.last_mouse_y - ypos // Reversed
		c.last_mouse_x = xpos
		c.last_mouse_y = ypos

		c.yaw += f32(xoffset) * MOUSE_SENSITIVITY
		c.pitch += f32(yoffset) * MOUSE_SENSITIVITY

		// Clamp pitch
		c.pitch = clamp(c.pitch, -89.0, 89.0)
	} else {
		// Reset first_mouse when button is not pressed
		c.first_mouse = true
	}
}

scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	context = runtime.default_context()

	c := &state.camera
	c.radius -= f32(yoffset) * ZOOM_SENSITIVITY
	c.radius = clamp(c.radius, MIN_RADIUS, MAX_RADIUS)
}

resize_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	context = runtime.default_context()

	if width > 0 && height > 0 {
		state.width = width
		state.height = height

		// Reconfigure surface
		state.gapi.surface_config.width = u32(width)
		state.gapi.surface_config.height = u32(height)
		wgpu.SurfaceConfigure(state.gapi.surface, &state.gapi.surface_config)
	}
}
