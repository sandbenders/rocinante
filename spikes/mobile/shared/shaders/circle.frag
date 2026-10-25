// SPDX-License-Identifier: 0BSD
#version 450

// A circle that drifts around the screen, drawn as a distance to its edge so
// its rim is smooth. Fragment uniforms live in descriptor set 3 in SDL's GPU API.
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 color;

layout(set = 3, binding = 0) uniform Params {
    vec2 size;  // the window in pixels
    float time; // seconds
    float unused;
} params;

void main() {
    vec2 pixel = uv * params.size;
    vec2 centre = params.size * 0.5
        + vec2(sin(params.time * 1.5), cos(params.time * 1.1)) * params.size * 0.15;
    float radius = min(params.size.x, params.size.y) * 0.18;
    float inside = 1.0 - smoothstep(-1.0, 1.0, length(pixel - centre) - radius);

    vec3 background = vec3(0.07, 0.09, 0.16);
    vec3 fill = vec3(1.0, 0.55, 0.12);
    color = vec4(mix(background, fill, inside), 1.0);
}
