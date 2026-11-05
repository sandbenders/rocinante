// Film grain that flickers every frame: `amount` is how strong, 0 to 1.
float amount;

float hash(float2 p)
{
    return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float4 c = scene.SampleLevel(scene_sampler, uv, 0);
    float n = hash(uv * size + frac(frame * 0.0137) * 100.0) - 0.5;
    return float4(c.rgb + n * amount, c.a);
}
