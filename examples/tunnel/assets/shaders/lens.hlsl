// What a cheap lens does to a picture: the colors drift apart toward the edges, the corners
// go dark, a fine grain flickers and there are faint lines. It reads only the picture before
// it, so it can follow any other effect. `strength` is how much of all that to use.
float strength;

float hash(float2 p)
{
    // no sin: its result for a big number differs between graphics drivers
    float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 centered = uv - 0.5;
    float2 shift = centered * dot(centered, centered) * 0.05 * strength;
    float r = scene.Sample(scene_sampler, uv + shift).r;
    float g = scene.Sample(scene_sampler, uv).g;
    float b = scene.Sample(scene_sampler, uv - shift).b;
    float3 color = float3(r, g, b);

    float lines = 0.96 + 0.04 * sin(uv.y * size.y * 3.14159);
    float grain = (hash(uv * size + frame) - 0.5) * 0.06 * strength;
    float vignette = 1.0 - smoothstep(0.35, 0.9, length(centered * float2(1.0, 0.8)) * 1.4) * 0.7 * strength;
    color = (color * lines + grain) * vignette;
    // a touch of contrast
    color = lerp(color, smoothstep(0.0, 1.0, color), 0.4);
    return float4(color, 1.0);
}
