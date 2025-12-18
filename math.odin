package phyons

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

translate :: proc(vec: vec3) -> mat4 {
	return linalg.matrix4_translate_f32(vec)
}

scale :: proc(vec: vec3) -> mat4 {
	return linalg.matrix4_scale_f32(vec)
}

rotate_x :: proc(angle: f32) -> mat4 {
	return linalg.matrix4_rotate_f32(angle, {1, 0, 0})
}

rotate_y :: proc(angle: f32) -> mat4 {
	return linalg.matrix4_rotate_f32(angle, {0, 1, 0})
}

rotate_z :: proc(angle: f32) -> mat4 {
	return linalg.matrix4_rotate_f32(angle, {0, 0, 1})
}

rotate_axis :: proc(angle: f32, axis: vec3) -> mat4 {
	return linalg.matrix4_rotate_f32(angle, axis)
}
