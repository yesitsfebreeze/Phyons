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
SHADER_FILES: []string = {
	"geo.vs",
	"geo.fs",
	"shading.vs",
	"shading.fs",
	"wireframe.vs",
	"present.vs", // This appears to be the wireframe fragment shader
}

init_shaders :: proc() -> bool {
	state.shaders.modules = make(map[string]wgpu.ShaderModule)

	for name in SHADER_FILES {
		path := strings.join({name, SHADER_EXTENSION}, "")
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
