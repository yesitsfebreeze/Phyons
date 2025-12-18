# Phyons - Target Architecture Plan

## Overview

Pure **compute shader rasterizer** with **GPU-based depth sorting** for front-to-back rendering. No vertex/fragment shaders for geometry - just raw point data projected and rasterized entirely in compute.

---

## Core Concepts

### 1. Split Phyon Storage

Instead of a single phyon buffer, we use **two parallel buffers** with matching indices:

```
Buffer A: Inside Phyons   [position, material_id]
Buffer B: Outside Phyons  [position, normal, material_id]
```

**Benefits:**
- Each phyon has **inside material** AND **outside material**
- Interpolate between materials based on thickness/depth
- More cache-friendly access patterns (smaller structs per buffer)
- Same index in both buffers = same logical phyon

```odin
Phyon_Inside :: struct {
    position:    vec3,      // Centroid/interior position
    material_id: u32,       // Interior material (bone, core, etc.)
}

Phyon_Outside :: struct {
    position:    vec3,      // Surface position
    normal:      vec3,      // Surface normal (for shading + backface cull)
    material_id: u32,       // Surface material (skin, shell, etc.)
}
```

### 2. GPU-Based Volume Sorting

Each volume stores a **centroid** (average or center-most inside phyon position). Sorting happens entirely on GPU:

```wgsl
struct VolumeInfo {
    model:              mat4x4<f32>,
    centroid:           vec3<f32>,      // Center of volume (world space)
    phyon_offset:       u32,
    phyon_count:        u32,
    index_offset:       u32,
    triangle_count:     u32,
    _pad:               u32,
}
```

**Sorting Strategy:**
1. **Sort Pass** (compute): Project each volume's centroid to view space, compute Z
2. **Bitonic Sort** (compute): Sort volume indices by Z (front-to-back)
3. **Draw Pass** (compute): Process volumes in sorted order

For small volume counts (<64), a simple insertion sort in a single workgroup is fine.

### 3. Draw Order Buffer

GPU computes and stores sorted volume indices:

```wgsl
@group(0) @binding(X) var<storage, read_write> draw_order: array<u32>;  // Sorted indices
@group(0) @binding(Y) var<storage, read_write> volume_depths: array<f32>;  // For sorting
```

---

## Rendering Pipeline

### Three-Pass Pure Compute

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pass 1: Sort Volumes (GPU)                   │
├─────────────────────────────────────────────────────────────────┤
│ Dispatch: 1 workgroup (for small volume counts)                 │
│                                                                 │
│ 1. Each thread: project volume[i].centroid to view space        │
│ 2. Store depth in volume_depths[i]                              │
│ 3. Initialize draw_order[i] = i                                 │
│ 4. Barrier                                                      │
│ 5. Sort draw_order by volume_depths (bitonic or insertion)      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Pass 2: Clear (GPU)                          │
├─────────────────────────────────────────────────────────────────┤
│ Clear depth buffer to MAX_UINT                                  │
│ Clear output texture to background color                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Pass 3: Rasterize (GPU)                      │
├─────────────────────────────────────────────────────────────────┤
│ For each volume_id in draw_order (front-to-back):               │
│   For each triangle in volume:                                  │
│     1. Fetch 3 outside phyons → project to screen space         │
│     2. Compute screen-space triangle bounding box               │
│     3. For each pixel in bounding box:                          │
│        a. Compute barycentric coordinates                       │
│        b. Skip if outside triangle                              │
│        c. Interpolate normal from 3 outside phyons              │
│        d. Backface cull: skip if dot(normal, view_dir) < 0      │
│        e. Interpolate depth                                     │
│        f. Atomic depth test (atomicMin on depth buffer)         │
│        g. If passed: write color + material to output           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Pass 4: Present                              │
├─────────────────────────────────────────────────────────────────┤
│ Fullscreen quad to display output texture                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## GPU Buffer Layout

### Bindings (Compute Shader)

```wgsl
// Sort pass
@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> volume_info: array<VolumeInfo>;
@group(0) @binding(2) var<storage, read_write> draw_order: array<u32>;
@group(0) @binding(3) var<storage, read_write> volume_depths: array<f32>;

// Rasterize pass
@group(0) @binding(0) var<uniform> uniforms: Uniforms;
@group(0) @binding(1) var<storage, read> inside_phyons: array<PhyonInside>;
@group(0) @binding(2) var<storage, read> outside_phyons: array<PhyonOutside>;
@group(0) @binding(3) var<storage, read> indices: array<u32>;
@group(0) @binding(4) var<storage, read> draw_order: array<u32>;
@group(0) @binding(5) var<storage, read> volume_info: array<VolumeInfo>;
@group(0) @binding(6) var output_texture: texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(7) var<storage, read_write> depth_buffer: array<atomic<u32>>;
```

### Uniforms

```wgsl
struct Uniforms {
    view_proj:      mat4x4<f32>,
    inv_view_proj:  mat4x4<f32>,
    view:           mat4x4<f32>,
    camera_pos:     vec3<f32>,
    time:           f32,
    screen_width:   f32,
    screen_height:  f32,
    volume_count:   u32,
    _pad:           u32,
}
```

### Volume Info

```wgsl
struct VolumeInfo {
    model:              mat4x4<f32>,
    centroid:           vec3<f32>,      // Center point for depth sorting
    phyon_offset:       u32,            // Start index in phyon buffers
    phyon_count:        u32,
    index_offset:       u32,            // Start index in index buffer
    triangle_count:     u32,
    _pad:               u32,
}
```

---

## Sorting Implementation

### Simple Sort (< 64 volumes)

Single workgroup, insertion sort in shared memory:

```wgsl
var<workgroup> shared_depths: array<f32, 64>;
var<workgroup> shared_order: array<u32, 64>;

@compute @workgroup_size(64, 1, 1)
fn cs_sort(@builtin(local_invocation_id) lid: vec3<u32>) {
    let i = lid.x;
    
    if (i < uniforms.volume_count) {
        // Project centroid to view space
        let world_pos = volume_info[i].model * vec4(volume_info[i].centroid, 1.0);
        let view_pos = uniforms.view * world_pos;
        shared_depths[i] = view_pos.z;
        shared_order[i] = i;
    }
    
    workgroupBarrier();
    
    // Simple insertion sort (thread 0 only for simplicity)
    if (lid.x == 0u) {
        for (var i = 1u; i < uniforms.volume_count; i++) {
            let key_depth = shared_depths[i];
            let key_order = shared_order[i];
            var j = i;
            while (j > 0u && shared_depths[j - 1u] > key_depth) {
                shared_depths[j] = shared_depths[j - 1u];
                shared_order[j] = shared_order[j - 1u];
                j--;
            }
            shared_depths[j] = key_depth;
            shared_order[j] = key_order;
        }
    }
    
    workgroupBarrier();
    
    // Write to global memory
    if (i < uniforms.volume_count) {
        draw_order[i] = shared_order[i];
    }
}
```

### Bitonic Sort (> 64 volumes)

For larger scenes, implement parallel bitonic sort across multiple workgroups.

---

## Dispatch Strategy

### Per-Triangle Dispatch

```odin
// For each volume in draw_order
for vol_idx in 0..<volume_count {
    volume := volumes[draw_order[vol_idx]]
    wgpu.compute_pass_set_push_constants(pass, {.COMPUTE}, 0, size_of(u32), &vol_idx)
    wgpu.compute_pass_dispatch_workgroups(pass, volume.triangle_count, 1, 1)
}
```

Each workgroup handles one triangle, rasterizes all its pixels.

### Alternative: Indirect Dispatch

Pre-compute dispatch arguments in a buffer, use `dispatch_workgroups_indirect` for each volume.

---

## Implementation Phases

### Phase 1: Split Phyon Buffers
- [ ] Create `Phyon_Inside` and `Phyon_Outside` structs
- [ ] Modify geometry loading to populate both buffers
- [ ] Update GPU buffer creation and uploads
- [ ] Compute volume centroids during loading

### Phase 2: GPU Volume Sorting
- [ ] Create sort compute shader
- [ ] Create draw_order and volume_depths buffers
- [ ] Implement simple insertion sort
- [ ] Test with multiple volumes

### Phase 3: Pure Compute Rasterizer
- [ ] Implement compute shader triangle rasterization
- [ ] Implement atomic depth buffer
- [ ] Implement barycentric interpolation
- [ ] Implement backface culling via normal check
- [ ] Process volumes in sorted order

### Phase 4: Material System
- [ ] Define material buffer
- [ ] Implement dual-material lookup (inside/outside)
- [ ] Implement material blending based on thickness/angle

### Phase 5: Optimizations
- [ ] Bitonic sort for large volume counts
- [ ] Tile-based binning for many triangles
- [ ] Hierarchical depth buffer
- [ ] Early-Z rejection

---

## Data Flow Diagram

```
                    ┌──────────────┐
                    │   OBJ File   │
                    └──────┬───────┘
                           │ load
                           ▼
              ┌────────────────────────┐
              │     Geometry Loader    │
              │  (compute inside/out)  │
              │  (compute centroid)    │
              └────────────┬───────────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
    │   Inside    │ │   Outside   │ │   Indices   │
    │   Phyons    │ │   Phyons    │ │   Buffer    │
    └──────┬──────┘ └──────┬──────┘ └──────┬──────┘
           │               │               │
           └───────────────┴───────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │   Volume (instance)    │
              │   - model matrix       │
              │   - centroid           │
              │   - phyon/index ranges │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │    GPU Sort Pass       │
              │  project centroids     │
              │  sort by view Z        │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │     draw_order[]       │
              │   [vol2, vol0, vol1]   │
              └────────────┬───────────┘
                           │
                           ▼
              ┌─────────────────────────────────────────────────────────────────┐
              │   GPU Rasterize Pass   │
              │  for each sorted vol:  │
              │    rasterize triangles │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │    Output Texture      │
              │    + Depth Buffer      │
              └────────────────────────┘
```

---

## Notes

### Why GPU Sorting?
- Data already on GPU (centroids in volume_info)
- No CPU-GPU sync needed
- Scales better with volume count
- Single frame latency

### Why Centroid-Based?
- Simple: one point per volume
- Good enough for most scenes (volumes don't heavily overlap)
- Can upgrade to per-triangle sorting if needed

### Limitations
- Intersecting volumes may have artifacts
- Very large volumes may sort incorrectly
- Solution: split large volumes, or use per-triangle sorting

---

## References

- Bitonic Sort on GPU: https://developer.nvidia.com/gpugems/gpugems2/part-vi-simulation-and-numerical-algorithms/chapter-46-improved-gpu-sorting
- Software Rasterization: https://www.scratchapixel.com/
- Atomic Operations in WGSL: https://www.w3.org/TR/WGSL/#atomic-builtin-functions
