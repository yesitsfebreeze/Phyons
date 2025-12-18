# Copilot Instructions - Phyons (Volume Aware Vertices)

## Project Overview

**Odin-language** WebGPU renderer for "volume-aware" mesh rendering. Stores interior + surface positions per vertex to enable SDF-like thickness estimation without ray marching.

## Architecture

### Three-Pass Rendering Pipeline
1. **Rasterize** (`rasterize.vs/fs.wgsl`): Outputs `face_id` + barycentric coords to `RGBA32Float` texture
2. **Drawing** (`drawing.cs.wgsl`): Compute shader reads face data, interpolates phyon attributes, computes lighting
3. **Present** (`present.vs/fs.wgsl`): Full-screen quad renders output texture to screen

### Key Files
| File | Purpose |
|------|---------|
| [types.odin](types.odin) | Global `State` struct with nested: `gapi`, `shaders`, `buffers`, `rendering`, `pipelines`, `camera`, `volume_manager` |
| [volumes.odin](volumes.odin) | `Shape` (reusable geometry) + `Volume` (instanced transforms) |
| [geometry.odin](geometry.odin) | `Phyon` struct (position, normal, depth, opacity, face_id), OBJ loading |
| [pipeline.odin](pipeline.odin) | Pipeline/bind group creation |
| [render.odin](render.odin) | Texture creation (`ensure_depth_texture`), frame rendering |
| [shaders.odin](shaders.odin) | WGSL loading with `EMBED_SHADERS` compile flag |
| [scene.odin](scene.odin) | Scene setup—add shapes/volumes here |

### Core Data Structures
```odin
Phyon :: struct {           // GPU vertex (40 bytes)
    position: vec3,         // Interior/centroid position
    normal:   vec3,         // Surface normal  
    depth:    f32,          // Distance to surface
    opacity:  f32,
    face_id:  u32,
    _pad:     u32,
}
```
Surface reconstruction: `surface_pos = phyon.position + phyon.normal * phyon.depth`


## Build & Run

Do not cd into subdirectories; run from project root.

**IMPORTANT**: When running terminal commands, the first character is sometimes cut off. Add a leading space before commands to work around this:
```bash
 odin run . -out:bin/phyons.exe   # Note the leading space
```

Use VS Code tasks: `build`, `run`, `release` (defined in `.vscode/tasks.json`)

## Code Conventions

### Init Order (dependencies matter)
```
window → wgpu → shaders → camera → volume_manager → scene → buffers → geometry → depth_texture → pipeline
```

### Cleanup Order (reverse of init)
```odin
cleanup_rendering() → cleanup_buffers() → cleanup_volume_manager() → cleanup_pipelines() → cleanup_shaders() → cleanup_wgpu()
```

### Shader Naming
- Pattern: `{name}.{stage}.wgsl` where stage is `vs`, `fs`, or `cs`
- Registered in `SHADER_NAMES` array in [shaders.odin](shaders.odin)

### Adding New Shapes
```odin
// In scene.odin or custom code:
shape_id := make_cube(1.0)           // Built-in primitive
shape_id := load_obj_shape("file.obj")  // OBJ from assets/
volume_id := add_volume(shape_id)
translate_volume(volume_id, {x, y, z})
```

## WGSL Bindings

### Rasterize Pass (group 0)
- `@binding(0)` Uniforms (view_proj, inv_view_proj, model, camera_pos, time, screen dims)

### Drawing Compute Pass (group 0)
- `@binding(0)` Uniforms
- `@binding(1)` Face ID texture (from rasterize)
- `@binding(2)` Phyon storage buffer (read)
- `@binding(3)` Index storage buffer (read)
- `@binding(4)` Output texture (write)

### Uniforms Struct (must match CPU side)
```wgsl
struct Uniforms {
    view_proj: mat4x4<f32>,
    inv_view_proj: mat4x4<f32>,
    model: mat4x4<f32>,
    camera_pos: vec3<f32>,
    time: f32,
    screen_width: f32,
    screen_height: f32,
    phyon_count: f32,
    face_count: f32,
}
```

## External Dependencies
- `vendor:wgpu` - WebGPU bindings
- `vendor:glfw` - Window management  
- `vendor/tinyobj` - OBJ file parsing (local copy)
