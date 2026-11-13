// SPDX-License-Identifier: 0BSD
//
// Where a corner of a 3D shape is in the world: the mesh's corner, stretched as the instance
// says (a capsule's two halves move apart by params.x, and a torus's ring grows a tube params.y
// thick), then moved by the three rows of the instance's transform. Shared by the shader that
// draws the scene and the one that draws its shadow, so they put every corner in the same place.

float3 shape_world(float3 position, float3 normal, float stretch, float4 row0, float4 row1, float4 row2, float4 params)
{
    float3 shaped = position + normal * params.y;
    shaped.y += stretch * params.x;
    float4 p = float4(shaped, 1.0);
    return float3(dot(row0, p), dot(row1, p), dot(row2, p));
}
