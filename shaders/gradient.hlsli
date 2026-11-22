// SPDX-License-Identifier: 0BSD
//
// Gradient lookup, shared by shapes.hlsl and mesh.hlsl.
// The CPU bakes every gradient of the frame into one texture (roci/gfx/gradient.odin):
// gradient n has a row of 256 colours at row 2n and its parameters at row 2n + 1,
// texel 0: the kind (0 linear, 1 radial, 2 conic), the angle as a fraction of a
// turn, and the centre as fractions of the box. An SVG drawing's gradients are
// kinds 3 (linear) and 4 (radial with a focal point): texel 0 then holds the kind,
// how the colors go on past the ends (0 the end colors, 1 mirrored, 2 again) and
// the focal point, and texels 1 to 3 the transform from the box to the gradient's
// own space, each number as two halves to add. A pixel's place in the ramp is
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
    else if (kind == 2)
    {
        // Round the centre, clockwise (y points down) from the start angle.
        float2 q = p - centre;
        t = frac(atan2(q.y, q.x) / 6.28318530718 - turns);
    }
    else
    {
        // An SVG gradient: the point is carried into the gradient's own space, where a linear one is x and a
        // radial one runs from the focal point out to the circle of radius 1 round the origin.
        float4 m0 = gradient_texture.Load(int3(1, row * 2 + 1, 0));
        float4 m1 = gradient_texture.Load(int3(2, row * 2 + 1, 0));
        float4 m2 = gradient_texture.Load(int3(3, row * 2 + 1, 0));
        float2 u = p / max(box_half, 1e-4);
        float2 q = float2((m0.x + m0.y) * u.x + (m1.x + m1.y) * u.y + (m2.x + m2.y),
                          (m0.z + m0.w) * u.x + (m1.z + m1.w) * u.y + (m2.z + m2.w));
        t = q.x;
        if (kind == 4)
        {
            // the point on the circle along the ray from the focal point through q is focus + k d
            float2 e = params.zw;
            float2 d = q - e;
            float dd = dot(d, d);
            float ed = dot(e, d);
            float k = (-ed + sqrt(max(ed * ed - dd * (dot(e, e) - 1.0), 0.0))) / max(dd, 1e-20);
            t = dd <= 0.0 ? 0.0 : (k > 0.0 ? 1.0 / k : 1.0);
        }
        uint spread = uint(turns + 0.5);
        if (spread == 2)
        {
            t = frac(t);
        }
        else if (spread == 1)
        {
            float r = fmod(abs(t), 2.0);
            t = r > 1.0 ? 2.0 - r : r;
        }
    }
    float u = (saturate(t) * (RAMP_WIDTH - 1.0) + 0.5) / RAMP_WIDTH;
    float v = (float(row) * 2.0 + 0.5) / (GRADIENT_ROWS * 2.0);
    return gradient_texture.SampleLevel(gradient_sampler, float2(u, v), 0);
}
