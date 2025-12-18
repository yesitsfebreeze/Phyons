package phyons

import "core:math"
import "core:math/linalg"

vec2 :: linalg.Vector2f32
vec3 :: linalg.Vector3f32
vec4 :: linalg.Vector4f32

mat2 :: linalg.Matrix2f32
mat2_IDENTITY :: linalg.MATRIX2F32_IDENTITY
mat3 :: linalg.Matrix3f32
mat3_IDENTITY :: linalg.MATRIX3F32_IDENTITY
mat4 :: linalg.Matrix4f32
mat4_IDENTITY :: linalg.MATRIX4F32_IDENTITY


cross :: linalg.cross
length :: linalg.length
dot :: linalg.dot
normalize :: linalg.normalize


PI :: math.PI
INF :: math.INF_F32
to_radians :: math.to_radians
to_degrees :: math.to_degrees
cos :: math.cos
sin :: math.sin
sqrt :: math.sqrt
atan2 :: math.atan2
abs :: math.abs


// Manipulations

mat4_look_at :: linalg.matrix4_look_at_f32
mat4_perspective :: linalg.matrix4_perspective_f32
mat4_translate :: linalg.matrix4_translate_f32
mat4_scale :: linalg.matrix4_scale_f32
mat4_inverse :: linalg.matrix4_inverse_f32

mat4_rotate_x :: proc(angle: f32) -> mat4 {
	return linalg.matrix4_rotate_f32(angle, {1, 0, 0})
}

mat4_rotate_y :: proc(angle: f32) -> mat4 {
	return linalg.matrix4_rotate_f32(angle, {0, 1, 0})
}

mat4_rotate_z :: proc(angle: f32) -> mat4 {
	return linalg.matrix4_rotate_f32(angle, {0, 0, 1})
}

mat4_rotate_axis :: proc(angle: f32, axis: vec3) -> mat4 {
	return linalg.matrix4_rotate_f32(angle, axis)
}
