package phyons

import "core:fmt"
import "core:os"
import "core:strings"
import "vendor:wgpu"

ShadersState :: struct {
	modules: map[string]wgpu.ShaderModule,
}

SHADER_EXTENSION: string : ".wgsl"

// Shader file definitions
SHADER_FILES :: [?]struct {
	name: string,
	path: string,
} {
	{"geo_vs", "geo.vs"},
	{"geo_fs", "geo.fs"},
	{"shading_vs", "shading.vs"},
	{"shading_fs", "shading.fs"},
	{"wireframe_vs", "wireframe.vs"},
	{"present_fs", "present.vs"}, // This appears to be the wireframe fragment shader
}

init_shaders :: proc() -> bool {
	state.shaders.modules = make(map[string]wgpu.ShaderModule)

	for shader_info in SHADER_FILES {
		path := strings.join({shader_info.path, SHADER_EXTENSION}, "")
		// Read shader file
		data, ok := os.read_entire_file(path)
		if !ok {
			fmt.println("Failed to read shader file:", path)
			return false
		}
		defer delete(data)

		// Create shader module
		source := wgpu.ShaderSourceWGSL {
			chain = {sType = .ShaderSourceWGSL},
			code = string(data),
		}
		desc := wgpu.ShaderModuleDescriptor {
			label       = shader_info.name,
			nextInChain = cast(^wgpu.ChainedStruct)&source,
		}

		module := wgpu.DeviceCreateShaderModule(state.gapi.device, &desc)
		if module == nil {
			fmt.println("Failed to create shader module:", shader_info.name)
			return false
		}

		state.shaders.modules[shader_info.name] = module
		fmt.println("Loaded shader:", shader_info.name)
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
	for name, module in state.shaders.modules {
		if module != nil {
			wgpu.ShaderModuleRelease(module)
		}
	}
	delete(state.shaders.modules)
}
