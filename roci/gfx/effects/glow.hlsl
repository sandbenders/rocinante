// A glow: what is brighter than `threshold` is blurred over a disc of `amount` pixels and
// added back to the picture, `strength` times.
float amount;
float strength;
float threshold;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 texel = 1.0 / size;
    float4 base = scene.SampleLevel(scene_sampler, uv, 0);
    float3 bloom = 0.0;
    float total = 0.0;
    for (int i = 0; i < 48; i++)
    {
        float r = sqrt((i + 0.5) / 48.0);
        float a = i * 2.39996323;
        float2 offset = float2(cos(a), sin(a)) * r * amount * texel;
        float3 c = scene.SampleLevel(scene_sampler, uv + offset, 0).rgb;
        float bright = max(max(c.r, c.g), c.b);
        float3 over = c * saturate((bright - threshold) / max(1.0 - threshold, 0.001));
        float w = 1.0 - r * r * 0.6;
        bloom += over * w;
        total += w;
    }
    bloom /= total;
    return float4(base.rgb + bloom * strength * 2.0, base.a);
}
