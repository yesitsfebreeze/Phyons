package phyons

import "core:os"
import "core:strings"
import "vendor:wgpu"

_ :: os
_ :: strings

// Compile-time flag: use -define:EMBED_SHADERS=true for release builds
EMBED_SHADERS :: #config(EMBED_SHADERS, false)
// Shader directory relative to executable (bin/)
DEV_SHADER_DIR :: "../"

ShadersState :: struct {
	modules: map[string]wgpu.ShaderModule,
}

SHADER_EXTENSION: string : ".wgsl"

// Shader file definitions as name-index pairs
ShaderIndex :: enum {
	RASTERIZE_VS,
	RASTERIZE_FS,
	DEPTH_CS,
}

SHADER_NAMES := [ShaderIndex]string {
	.RASTERIZE_VS = "rasterize.vs",
	.RASTERIZE_FS = "rasterize.fs",
	.DEPTH_CS     = "depth.cs",
}

// Embedded shader data (only included in release builds)
when EMBED_SHADERS {
	@(private = "file")
	EMBEDDED_SHADERS := [ShaderIndex]string {
		.RASTERIZE_VS = #load("rasterize.vs.wgsl", string),
		.RASTERIZ_FS  = #load("rasterize.fs.wgsl", string),
		.DEPTH_CS     = #load("depth.cs.wgsl", string),
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
		path := strings.join({DEV_SHADER_DIR, name, SHADER_EXTENSION}, "")
		defer delete(path)
		data, ok := os.read_entire_file(path)
		if !ok {
			log_info("Failed to read shader file:", path)
			return "", false
		}
		return string(data), true
	}
}

init_shaders :: proc() -> bool {
	state.shaders.modules = make(map[string]wgpu.ShaderModule)

	when EMBED_SHADERS {
		log_info("Using embedded shaders (release mode)")
	} else {
		log_info("Loading shaders from disk (debug mode)")
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
			log_info("Failed to create shader module:", name)
			return false
		}

		state.shaders.modules[name] = module
	}

	return true
}

// Get a shader module by name
get_shader :: proc(name: string) -> (wgpu.ShaderModule, bool) {
	if module, ok := state.shaders.modules[name]; ok {
		return module, true
	}
	log_info("Shader not found:", name)
	return nil, false
}

cleanup_shaders :: proc() {
	for _, module in state.shaders.modules {
		if module != nil {
			wgpu.ShaderModuleRelease(module)
		}
	}
	delete(state.shaders.modules)
}
