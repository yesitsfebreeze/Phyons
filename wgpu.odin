package phyons

import "core:fmt"
import "vendor:glfw"
import "vendor:wgpu"

init_wgpu :: proc() -> bool {
	g := &state.gapi

	// Create instance
	instance_desc := wgpu.InstanceDescriptor{}
	g.instance = wgpu.CreateInstance(&instance_desc)
	if g.instance == nil {
		fmt.println("Failed to create WebGPU instance")
		return false
	}

	// Create surface
	when ODIN_OS == .Windows {
		hwnd := glfw.GetWin32Window(state.window)
		surface_hwnd_desc := wgpu.SurfaceSourceWindowsHWND {
			chain = {sType = .SurfaceSourceWindowsHWND},
			hinstance = nil,
			hwnd = hwnd,
		}
		surface_desc := wgpu.SurfaceDescriptor {
			nextInChain = cast(^wgpu.ChainedStruct)&surface_hwnd_desc,
		}
		g.surface = wgpu.InstanceCreateSurface(g.instance, &surface_desc)
	}
	if g.surface == nil {
		fmt.println("Failed to create surface")
		return false
	}

	// Request adapter
	adapter_options := wgpu.RequestAdapterOptions {
		compatibleSurface = g.surface,
		powerPreference   = .HighPerformance,
	}

	adapter_callback_info := wgpu.RequestAdapterCallbackInfo {
		mode = .WaitAnyOnly,
		callback = proc "c" (
			status: wgpu.RequestAdapterStatus,
			adapter: wgpu.Adapter,
			message: string,
			userdata1: rawptr,
			userdata2: rawptr,
		) {
			(cast(^wgpu.Adapter)userdata1)^ = adapter
		},
		userdata1 = &g.adapter,
	}

	_ = wgpu.InstanceRequestAdapter(
		g.instance,
		&adapter_options,
		adapter_callback_info,
	)

	if g.adapter == nil {
		fmt.println("Failed to get adapter")
		return false
	}

	// Request device
	device_desc := wgpu.DeviceDescriptor {
		label = "Main Device",
	}

	device_callback_info := wgpu.RequestDeviceCallbackInfo {
		mode = .WaitAnyOnly,
		callback = proc "c" (
			status: wgpu.RequestDeviceStatus,
			device: wgpu.Device,
			message: string,
			userdata1: rawptr,
			userdata2: rawptr,
		) {
			(cast(^wgpu.Device)userdata1)^ = device
		},
		userdata1 = &g.device,
	}

	_ = wgpu.AdapterRequestDevice(g.adapter, &device_desc, device_callback_info)

	if g.device == nil {
		fmt.println("Failed to get device")
		return false
	}

	g.queue = wgpu.DeviceGetQueue(g.device)

	// Configure surface
	state.width = WINDOW_WIDTH
	state.height = WINDOW_HEIGHT

	g.surface_config = wgpu.SurfaceConfiguration {
		device      = g.device,
		format      = .BGRA8UnormSrgb,
		usage       = {.RenderAttachment},
		width       = u32(state.width),
		height      = u32(state.height),
		presentMode = .Fifo,
		alphaMode   = .Opaque,
	}
	wgpu.SurfaceConfigure(g.surface, &g.surface_config)

	return true
}

cleanup_wgpu :: proc() {
	g := &state.gapi

	if g.queue != nil do wgpu.QueueRelease(g.queue)
	if g.device != nil do wgpu.DeviceRelease(g.device)
	if g.adapter != nil do wgpu.AdapterRelease(g.adapter)
	if g.surface != nil do wgpu.SurfaceRelease(g.surface)
	if g.instance != nil do wgpu.InstanceRelease(g.instance)
}
