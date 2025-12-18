# Volume Aware Vertices

The idea is to grab all vertices connected to one, calculate their centroid.

The centroids will be our actual vertices, we have the same amount of vertices just shrunken down, essentially a live skinning modifier.

If we iterate over this algorithm a couple of times, we get an inside skeletal representation of the mesh.

## Implementation

This demo performs **6 iterations** of the centroid calculation algorithm:

1. Start with an icosahedron mesh (12 vertices, each connected to 5 neighbors)
2. For each iteration, calculate the centroid of each vertex's connected neighbors
3. The centroids become the vertices for the next iteration
4. After 6 iterations, we have 7 layers total (original + 6 iterations)

Each iteration shrinks the mesh inward, creating a nested skeletal structure.

## Reference Depth

For each vertex at every iteration level, we store the **reference_depth** - the displacement vector from that vertex to the original surface position. This is a **read-only attribute** that enables:

- Analytical reconstruction of the original surface from any iteration level
- Projection outward by `reference_depth` to find the exact surface position
- Live smoothing control by interpolating between vertices
- SDF operations using the known direction and nominal depth


## Overview
The whole idea is to store 2 base informations overall.
- *interior* position
- *surface* position

The we can do a half faked sdf interpolation to almost accurately estimate thickness of an object.
Per vertex and fragment rastarization, we foward the interpolated triangle values instea of shading to the viewport.

We greate an alpha aware depth buffer, and a deferred g-buffer.
Then we can store per pixel, which object/vertex affected it and by how much due to its opacity.

Rendering is done in a secondary compute pass per pixel. (can be multi threaded)
When we render we write to the alpha depth mask, where alpha is accumulared per object.
If alpha is 1.0 (fully saturated), we know that this pixel is finished, we do not need to process it anymore.
Effectively only writing to screen the information we need to draw the full frame, no more no less.

If two objects overlap in many places, we can also solve this by comparing their depth value when writing the pixel.
if its higher, we overwrite the depth and g-buffer to accept the frontmost pixel.
This causes a little overdraw in areas, but thats negligable for the result.


# General workflow

We use a standard triangle rasterization as the visibility oracle and let the GPU’s depth test decide the correct front-most surface per pixel. This means we can employ a lot of already known optimization techniques.


For each object, we rasterize its triangles directly against a global depth buffer; the fragment shader outputs interpolated attributes instead of final color. Such as interior, surface, material ID, opacity, and any extra interpolateable scalar we want/need (for example a distance-to-center term).


The depth buffer guarantees correct per-pixel ordering regardless of object submission order, so front-to-back sorting and BVH culling are only optimizations, not correctness requirements.

Pixels that are already fully opaque naturally stop contributing because later fragments fail the depth test or are blended out.

To approximate an SDF-like behavior, capture frontface depth as the “outside” position and, when needed, backface depth as the “interior” position in a second pass; this gives a view-ray interval per object that can be used at shading time for subtraction, thickness, or interior effects.

The final framebuffer is reconstructed in a later pass by shading from the stored per-pixel attributes rather than direct fragment output, effectively misusing the vertex/fragment stages as an interpolation and visibility system instead of a traditional immediate shading pipeline.



