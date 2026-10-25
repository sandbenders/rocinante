// SPDX-License-Identifier: 0BSD
#version 450

// A triangle that covers the whole screen, made from the vertex number alone,
// so the pipeline needs no vertex buffer.
layout(location = 0) out vec2 uv;

void main() {
    vec2 corner = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
    uv = corner;
    gl_Position = vec4(corner * 2.0 - 1.0, 0.0, 1.0);
}
