// Turns every color into its opposite: `amount` is how much, 0 to 1.
float amount;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float4 c = scene.SampleLevel(scene_sampler, uv, 0);
    return float4(lerp(c.rgb, 1.0 - c.rgb, amount), c.a);
}
