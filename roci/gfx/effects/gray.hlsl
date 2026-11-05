// Takes the color out: `amount` is how much, 0 to 1.
float amount;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float4 c = scene.SampleLevel(scene_sampler, uv, 0);
    float g = dot(c.rgb, float3(0.299, 0.587, 0.114));
    return float4(lerp(c.rgb, float3(g, g, g), amount), c.a);
}
