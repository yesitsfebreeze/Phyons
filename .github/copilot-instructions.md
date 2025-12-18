# Copilot Instructions - Volume Aware Vertices

## Project Overview

This is an **Odin-language** WebGPU renderer implementing a deferred G-buffer pipeline for "volume-aware" mesh rendering. The core algorithm shrinks meshes inward via iterative centroid calculations to create skeletal approximations, enabling SDF-like thickness estimation.

## Architecture

### Rendering Pipeline (Deferred Two-Pass)
1. **Geometry Pass** (`geo.vs.wgsl`, `geo.fs.wgsl`): Writes to G-buffers (normal, material, distance) + dual depth buffers (front/back)
2. **Shading Pass** (`shading.vs.wgsl`, `shading.fs.wgsl`): Full-screen quad reads G-buffers to compute final lighting/thickness

### Key Files by Responsibility
- [state.odin](state.odin) - Global `State` struct: all WGPU handles, camera, buffers, pipelines
- [render.odin](render.odin) - G-buffer creation (`ensure_gbuffers`), frame rendering
- [pipeline.odin](pipeline.odin) - Pipeline creation with bind groups and layouts
- [geometry.odin](geometry.odin) - `Vertex` struct (64 bytes aligned), mesh building
- [skeletonize.odin](skeletonize.odin) - Centroid-shrinking algorithm with ray-triangle intersection
- [shaders.odin](shaders.odin) - WGSL shader loading from `.wgsl` files

### Data Flow
```
Vertex → geometry pass → G-buffers (normal/material/distance) + depth_front/depth_back
                                     ↓
                        shading pass → thickness = back_depth - front_depth → final color
```

## Build & Run

```bash
odin run .    # Build and run (task "build" in VS Code)
```

No external dependencies beyond Odin's vendor packages (`glfw`, `wgpu`).

## Code Conventions

### Vertex Structure (64-byte aligned)
All vertex attributes must maintain alignment for WebGPU buffer requirements:
```odin
Vertex :: struct {
    position, color, reference_centroid, normal: linalg.Vector3f32,
    material_id, opacity, distance_to_center, _pad: f32,  // _pad for 64-byte alignment
}
```

### State Management
- Single global `state: State` variable holds all GPU/window state
- Nested structs: `state.gapi`, `state.shaders`, `state.buffers`, `state.rendering`, `state.pipelines`, `state.camera`
- Init order matters: `window → wgpu → shaders → camera → buffers → geometry → pipeline`

### Resource Cleanup Pattern
Always release WGPU resources in reverse order:
```odin
cleanup :: proc() {
    cleanup_rendering()  // G-buffers first
    cleanup_buffers()
    cleanup_pipelines()
    cleanup_shaders()
    cleanup_wgpu()
    cleanup_window()
}
```

### Shader Naming Convention
- Files: `{name}.{stage}.wgsl` (e.g., `geo.vs.wgsl`, `shading.fs.wgsl`)
- Loaded via `SHADER_FILES` table in [shaders.odin](shaders.odin)

## Key Algorithms

### Skeletonization ([skeletonize.odin](skeletonize.odin))
- Shoots rays inward from face centroids, finds opposite-side hits via Möller–Trumbore
- Skeleton point = midpoint between face centroid and opposite surface
- Results averaged per-vertex for smooth interior representation

### Reference Depth
Each vertex stores `reference_centroid` - displacement to original surface for reconstruction.

## WGSL Shader Bindings
- Geometry pass: `@group(0) @binding(0)` = uniform buffer (view_proj, model, time)
- Shading pass: `@binding(0-4)` = G-buffer textures + depths, `@binding(5)` = sampler
