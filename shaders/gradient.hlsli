// SPDX-License-Identifier: 0BSD
//
// Gradient lookup, shared by shapes.hlsl and mesh.hlsl (CLAUDE.md section 5.9).
// The CPU bakes every gradient of the frame into one texture (roci/gfx/gradient.odin):
// gradient n has a row of 256 colours at row 2n and its parameters at row 2n + 1,
// texel 0: the kind (0 linear, 1 radial, 2 conic), the angle as a fraction of a
// turn, and the centre as fractions of the box. A pixel's place in the ramp is
// worked out here from where it is in the shape's own space.
//
// Resources follow SDL's GPU rules: the fragment stage's first sampler is texture
// t0 and sampler s0 in space2 (set 2 in SPIR-V).

static const float GRADIENT_ROWS = 256.0; // MAX_GRADIENTS in roci/gfx/gradient.odin
static const float RAMP_WIDTH = 256.0;    // RAMP_WIDTH there

Texture2D<float4> gradient_texture : register(t0, space2);
SamplerState gradient_sampler : register(s0, space2);

// The colour (straight alpha) of gradient `gradient` (1 and up) at the point `p`,
// measured from the middle of the shape's bounding box, whose half size is
// `box_half`.
float4 gradient_colour(uint gradient, float2 p, float2 box_half)
{
    uint row = gradient - 1;
    float4 params = gradient_texture.Load(int3(0, row * 2 + 1, 0));
    uint kind = uint(params.x + 0.5);
    float turns = params.y;
    float2 size = max(box_half * 2.0, 1e-4);
    float2 centre = (params.zw - 0.5) * size;

    float t = 0.0;
    if (kind == 0)
    {
        // Along a line at the angle, as long as it takes to reach both corners.
        float a = turns * 6.28318530718;
        float2 d = float2(cos(a), sin(a));
        float extent = abs(size.x * d.x) + abs(size.y * d.y);
        t = dot(p, d) / max(extent, 1e-4) + 0.5;
    }
    else if (kind == 1)
    {
        // From the centre out to the edge of the box on each side.
        t = length((p - centre) / (size * 0.5));
    }
    else
    {
        // Round the centre, clockwise (y points down) from the start angle.
        float2 q = p - centre;
        t = frac(atan2(q.y, q.x) / 6.28318530718 - turns);
    }
    float u = (saturate(t) * (RAMP_WIDTH - 1.0) + 0.5) / RAMP_WIDTH;
    float v = (float(row) * 2.0 + 0.5) / (GRADIENT_ROWS * 2.0);
    return gradient_texture.SampleLevel(gradient_sampler, float2(u, v), 0);
}
