// Film grain that flickers every frame: `amount` is how strong, 0 to 1.
float amount;

float hash(float2 p)
{
    // no sin: its result for a big number differs between graphics drivers
    float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float4 c = scene.SampleLevel(scene_sampler, uv, 0);
    float n = hash(floor(uv * size) + floor(frac(frame * 0.0137) * 100.0)) - 0.5;
    return float4(c.rgb + n * amount, c.a);
}
