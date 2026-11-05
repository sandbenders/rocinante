// Turns every color into its opposite: `amount` is how much, 0 to 1. A canvas holds colors already multiplied by their alpha, so the opposite is alpha minus the color (the same as 1 minus it on a window).
float amount;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float4 c = scene.SampleLevel(scene_sampler, uv, 0);
    return float4(lerp(c.rgb, c.a - c.rgb, amount), c.a);
}
