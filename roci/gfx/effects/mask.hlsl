// The picture where the stencil shows: its alpha multiplied by the stencil's brightness times
// the stencil's alpha, the stencil stretched over it. `scene` is the picture and `stencil` the
// stencil; `premultiplied` says for each (x the picture, y the stencil) whether its colors are
// already multiplied by its alpha, as a canvas's are. The result is a canvas's: multiplied.
float2 premultiplied;

Texture2D<float4> stencil : register(t1, space2);
SamplerState stencil_sampler : register(s1, space2);

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float4 p = scene.SampleLevel(scene_sampler, uv, 0);
    float4 s = stencil.SampleLevel(stencil_sampler, uv, 0);
    if (premultiplied.x < 0.5)
    {
        p.rgb *= p.a;
    }
    float3 c = premultiplied.y < 0.5 ? s.rgb * s.a : s.rgb;
    float show = saturate(dot(c, float3(0.299, 0.587, 0.114)));
    return p * show;
}
