// A soft blur: the picture averaged over a disc of `amount` pixels around each pixel.
float amount;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 texel = 1.0 / size;
    float4 sum = 0.0;
    float total = 0.0;
    for (int i = 0; i < 40; i++)
    {
        float r = sqrt((i + 0.5) / 40.0);
        float a = i * 2.39996323;
        float2 offset = float2(cos(a), sin(a)) * r * amount * texel;
        float w = 1.0 - r * r * 0.5;
        sum += scene.SampleLevel(scene_sampler, uv + offset, 0) * w;
        total += w;
    }
    return sum / total;
}
