package phyons

import "core:fmt"
import "core:os"
import "core:strings"
import "vendor:wgpu"

_ :: os
_ :: strings

// Compile-time flag: use -define:EMBED_SHADERS=true for release builds
EMBED_SHADERS :: #config(EMBED_SHADERS, false)

ShadersState :: struct {
	modules: map[string]wgpu.ShaderModule,
}

SHADER_EXTENSION: string : ".wgsl"

// Shader file definitions as name-index pairs
ShaderIndex :: enum {
	GEO_VS,
	GEO_FS,
	SHADING_VS,
	SHADING_FS,
	WIREFRAME_VS,
	PRESENT_FS,
}

SHADER_NAMES := [ShaderIndex]string {
	.GEO_VS       = "geo.vs",
	.GEO_FS       = "geo.fs",
	.SHADING_VS   = "shading.vs",
	.SHADING_FS   = "shading.fs",
	.WIREFRAME_VS = "wireframe.vs",
	.PRESENT_FS   = "present.fs",
}

// Embedded shader data (only included in release builds)
when EMBED_SHADERS {
	@(private = "file")
	EMBEDDED_SHADERS := [ShaderIndex]string {
		.GEO_VS       = #load("shaders/geo.vs.wgsl", string),
		.GEO_FS       = #load("shaders/geo.fs.wgsl", string),
		.SHADING_VS   = #load("shaders/shading.vs.wgsl", string),
		.SHADING_FS   = #load("shaders/shading.fs.wgsl", string),
		.WIREFRAME_VS = #load("shaders/wireframe.vs.wgsl", string),
		.PRESENT_FS   = #load("shaders/present.fs.wgsl", string),
	}
}

// Load shader source - from embedded data in release, from file in debug
when EMBED_SHADERS {
	load_shader_source :: proc(idx: ShaderIndex) -> (string, bool) {
		// Release mode: use embedded shaders
		return EMBEDDED_SHADERS[idx], true
	}
} else {
	load_shader_source :: proc(idx: ShaderIndex) -> (string, bool) {
		// Debug mode: load from file for hot-reloading during development
		name := SHADER_NAMES[idx]
		path := strings.join({"shaders/", name, SHADER_EXTENSION}, "")
		defer delete(path)
		data, ok := os.read_entire_file(path)
		if !ok {
			fmt.println("Failed to read shader file:", path)
			return "", false
		}
		return string(data), true
	}
}

init_shaders :: proc() -> bool {
	state.shaders.modules = make(map[string]wgpu.ShaderModule)

	when EMBED_SHADERS {
		fmt.println("Using embedded shaders (release mode)")
	} else {
		fmt.println("Loading shaders from disk (debug mode)")
	}

	for idx in ShaderIndex {
		name := SHADER_NAMES[idx]
		shader_source, ok := load_shader_source(idx)
		if !ok {
			return false
		}
		// In debug mode, we need to free the allocated string later
		when !EMBED_SHADERS {
			defer delete(transmute([]u8)shader_source)
		}

		// Create shader module
		source := wgpu.ShaderSourceWGSL {
			chain = {sType = .ShaderSourceWGSL},
			code = shader_source,
		}
		desc := wgpu.ShaderModuleDescriptor {
			label       = name,
			nextInChain = cast(^wgpu.ChainedStruct)&source,
		}

		module := wgpu.DeviceCreateShaderModule(state.gapi.device, &desc)
		if module == nil {
			fmt.println("Failed to create shader module:", name)
			return false
		}

		state.shaders.modules[name] = module
		fmt.println("Loaded shader:", name)
	}

	return true
}

// Get a shader module by name
get_shader :: proc(name: string) -> wgpu.ShaderModule {
	if module, ok := state.shaders.modules[name]; ok {
		return module
	}
	fmt.println("Shader not found:", name)
	return nil
}

cleanup_shaders :: proc() {
	for _, module in state.shaders.modules {
		if module != nil {
			wgpu.ShaderModuleRelease(module)
		}
	}
	delete(state.shaders.modules)
}
