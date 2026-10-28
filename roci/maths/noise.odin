// SPDX-License-Identifier: 0BSD
//
// Perlin noise in one to four dimensions, simplex noise in one to four, and
// layered ("fractal") noise built on Perlin. This is Perlin's improved noise (Perlin, "Improving Noise", SIGGRAPH
// 2002: the quintic fade curve and the twelve edge gradients). The permutation
// table comes from the seed, so the same seed gives the same landscape, and the
// interpreter and compiled sketches share this one implementation. Results run from 0 to 1, like Processing's noise().
//
// Simplex noise is Gustavson's ("Simplex noise demystified", 2005): the same
// idea on a skewed grid of triangles, tetrahedra and their four-dimensional
// kin, which is smoother in its directions and cheaper in high dimensions.
// The four-dimensional corner order is found by ranking the coordinates, as in
// his later simplexnoise1234, instead of by a lookup table.
package maths

import "core:math"

Noise :: struct {
	perm: [512]u8, // 256 shuffled values, repeated so lookups never wrap by hand
}

// A noise field for a seed. Every seed is valid.
noise_make :: proc(seed: u64) -> Noise {
	n: Noise
	for i in 0 ..< 256 {
		n.perm[i] = u8(i)
	}
	r := rng_make(seed)
	// Fisher-Yates shuffle.
	for i := 255; i > 0; i -= 1 {
		j := int(rng_int(&r, 0, i64(i)))
		n.perm[i], n.perm[j] = n.perm[j], n.perm[i]
	}
	for i in 0 ..< 256 {
		n.perm[i + 256] = n.perm[i]
	}
	return n
}

@(private)
fade :: proc "contextless" (t: f64) -> f64 {
	return t * t * t * (t * (t * 6 - 15) + 10)
}

// Dot product of the point's offset with one of twelve gradient directions.
@(private)
grad :: proc "contextless" (hash: u8, x, y, z: f64) -> f64 {
	h := hash & 15
	u := x if h < 8 else y
	v: f64
	switch {
	case h < 4:
		v = y
	case h == 12 || h == 14:
		v = x
	case:
		v = z
	}
	return (u if h & 1 == 0 else -u) + (v if h & 2 == 0 else -v)
}

// Noise from 0 to 1 at a point on a line.
noise1 :: proc "contextless" (n: ^Noise, x: f64) -> f64 {
	return noise3(n, x, 0, 0)
}

// Noise from 0 to 1 at a point on a plane.
noise2 :: proc "contextless" (n: ^Noise, x, y: f64) -> f64 {
	return noise3(n, x, y, 0)
}

// Noise from 0 to 1 at a point in space. At whole-number points it is exactly 0.5.
noise3 :: proc "contextless" (n: ^Noise, x_in, y_in, z_in: f64) -> f64 {
	x, y, z := x_in, y_in, z_in
	fx, fy, fz := math.floor(x_in), math.floor(y_in), math.floor(z_in)
	// The lattice repeats every 256; i64 first so huge or negative values wrap cleanly.
	xi, yi, zi := int(i64(fx) & 255), int(i64(fy) & 255), int(i64(fz) & 255)
	x, y, z = x - fx, y - fy, z - fz
	u, v, w := fade(x), fade(y), fade(z)

	p := &n.perm
	a := int(p[xi]) + yi
	aa := int(p[a]) + zi
	ab := int(p[a + 1]) + zi
	b := int(p[xi + 1]) + yi
	ba := int(p[b]) + zi
	bb := int(p[b + 1]) + zi

	x1 := math.lerp(grad(p[aa], x, y, z), grad(p[ba], x - 1, y, z), u)
	x2 := math.lerp(grad(p[ab], x, y - 1, z), grad(p[bb], x - 1, y - 1, z), u)
	y1 := math.lerp(x1, x2, v)
	x3 := math.lerp(grad(p[aa + 1], x, y, z - 1), grad(p[ba + 1], x - 1, y, z - 1), u)
	x4 := math.lerp(grad(p[ab + 1], x, y - 1, z - 1), grad(p[bb + 1], x - 1, y - 1, z - 1), u)
	y2 := math.lerp(x3, x4, v)
	return 0.5 + 0.5 * math.lerp(y1, y2, w)
}

// Layers of noise, each `lacunarity` times finer and `gain` times quieter than
// the one before, added up and scaled back to 0 to 1. Processing's noiseDetail
// uses 4 octaves, a lacunarity of 2 and a gain of 0.5, and so do the defaults.
noise_fbm :: proc "contextless" (n: ^Noise, x, y, z: f64, octaves := 4, lacunarity := 2.0, gain := 0.5) -> f64 {
	total, amplitude, frequency, norm := 0.0, 1.0, 1.0, 0.0
	for _ in 0 ..< max(octaves, 1) {
		total += amplitude * noise3(n, x * frequency, y * frequency, z * frequency)
		norm += amplitude
		amplitude *= gain
		frequency *= lacunarity
	}
	return total / norm
}

// ---- four dimensions, and simplex noise ----

// The twelve edge directions of a cube, for 2D and 3D simplex noise.
@(private)
GRAD3 := [12][3]f64{
	{1, 1, 0}, {-1, 1, 0}, {1, -1, 0}, {-1, -1, 0},
	{1, 0, 1}, {-1, 0, 1}, {1, 0, -1}, {-1, 0, -1},
	{0, 1, 1}, {0, -1, 1}, {0, 1, -1}, {0, -1, -1},
}

// The 32 directions with one zero and three of +1 or -1, for 4D noise.
@(private)
GRAD4 := [32][4]f64{
	{0, 1, 1, 1}, {0, 1, 1, -1}, {0, 1, -1, 1}, {0, 1, -1, -1},
	{0, -1, 1, 1}, {0, -1, 1, -1}, {0, -1, -1, 1}, {0, -1, -1, -1},
	{1, 0, 1, 1}, {1, 0, 1, -1}, {1, 0, -1, 1}, {1, 0, -1, -1},
	{-1, 0, 1, 1}, {-1, 0, 1, -1}, {-1, 0, -1, 1}, {-1, 0, -1, -1},
	{1, 1, 0, 1}, {1, 1, 0, -1}, {1, -1, 0, 1}, {1, -1, 0, -1},
	{-1, 1, 0, 1}, {-1, 1, 0, -1}, {-1, -1, 0, 1}, {-1, -1, 0, -1},
	{1, 1, 1, 0}, {1, 1, -1, 0}, {1, -1, 1, 0}, {1, -1, -1, 0},
	{-1, 1, 1, 0}, {-1, 1, -1, 0}, {-1, -1, 1, 0}, {-1, -1, -1, 0},
}

// Scales a raw simplex or 4D Perlin sum, which runs roughly -1 to 1, to 0 to
// 1, clamping the rare overshoot.
@(private)
unit :: proc "contextless" (v: f64) -> f64 {
	return 0.5 + 0.5 * clamp(v, -1, 1)
}

// 4D Perlin noise needs a smaller scale than 3D: its gradients have three
// non-zero parts, so a corner's pull is up to sqrt(3) long. Two million random
// samples gave raw values up to about 1.14, so 0.8 fills most of 0 to 1 and
// `unit` clamps the rare overshoot.
@(private)
PERLIN4_SCALE :: 0.8

// Noise from 0 to 1 at a point in space and time (or any four numbers).
noise4 :: proc "contextless" (n: ^Noise, x_in, y_in, z_in, w_in: f64) -> f64 {
	fx, fy, fz, fw := math.floor(x_in), math.floor(y_in), math.floor(z_in), math.floor(w_in)
	xi, yi, zi, wi := int(i64(fx) & 255), int(i64(fy) & 255), int(i64(fz) & 255), int(i64(fw) & 255)
	x, y, z, w := x_in - fx, y_in - fy, z_in - fz, w_in - fw
	u, v, s, r := fade(x), fade(y), fade(z), fade(w)

	p := &n.perm
	values: [16]f64
	for corner in 0 ..< 16 {
		dx, dy, dz, dw := corner & 1, corner >> 1 & 1, corner >> 2 & 1, corner >> 3 & 1
		h := p[int(p[int(p[int(p[xi + dx]) + yi + dy]) + zi + dz]) + wi + dw]
		g := GRAD4[h & 31]
		values[corner] = g[0] * (x - f64(dx)) + g[1] * (y - f64(dy)) + g[2] * (z - f64(dz)) + g[3] * (w - f64(dw))
	}
	// Blend along x, then y, then z, then w.
	for i in 0 ..< 8 {values[i] = math.lerp(values[2 * i], values[2 * i + 1], u)}
	for i in 0 ..< 4 {values[i] = math.lerp(values[2 * i], values[2 * i + 1], v)}
	for i in 0 ..< 2 {values[i] = math.lerp(values[2 * i], values[2 * i + 1], s)}
	return unit(PERLIN4_SCALE * math.lerp(values[0], values[1], r))
}

@(private)
perm_at :: proc "contextless" (n: ^Noise, i: int) -> int {
	return int(n.perm[i])
}

// One corner's share of a simplex sum: its gradient dotted with the offset,
// faded out to nothing at distance sqrt(radius_sq): 0.5 in 2D and 0.6 in 3D and
// 4D, as in Gustavson's reference (decided 2026-10-27, so results match other
// simplex noise). At 0.6 the field has tiny steps, about 0.001 on the 0 to 1
// scale, where simplexes meet; 0.5 would remove them but is not the reference.
@(private)
corner_share :: proc "contextless" (radius_sq, dist_sq, dot: f64) -> f64 {
	t := radius_sq - dist_sq
	if t < 0 {
		return 0
	}
	t *= t
	return t * t * dot
}

// Simplex noise from 0 to 1 on a line. In one dimension the "simplex" is the
// stretch between two whole numbers, and each end pulls with a gradient between
// 1 and 8 (up or down), fading to nothing a whole step away.
simplex1 :: proc "contextless" (n: ^Noise, x: f64) -> f64 {
	i0 := math.floor(x)
	x0 := x - i0
	x1 := x0 - 1
	h0 := n.perm[int(i64(i0) & 255)]
	h1 := n.perm[int(i64(i0 + 1) & 255)]
	grad1 :: proc "contextless" (hash: u8) -> f64 {
		g := f64(1 + hash & 7)
		return -g if hash & 8 != 0 else g
	}
	sum := corner_share(1, x0 * x0, grad1(h0) * x0) + corner_share(1, x1 * x1, grad1(h1) * x1)
	return unit(0.395 * sum)
}

// Simplex noise from 0 to 1 on a plane (factor 70, Gustavson's).
simplex2 :: proc "contextless" (n: ^Noise, x, y: f64) -> f64 {
	F2 :: 0.36602540378443864676 // (sqrt(3) - 1) / 2
	G2 :: 0.21132486540518711775 // (3 - sqrt(3)) / 6
	skew := (x + y) * F2
	i, j := math.floor(x + skew), math.floor(y + skew)
	unskew := (i + j) * G2
	x0, y0 := x - (i - unskew), y - (j - unskew)
	// Which of the two triangles of the skewed square the point is in.
	i1, j1 := 1, 0
	if x0 <= y0 {
		i1, j1 = 0, 1
	}
	x1, y1 := x0 - f64(i1) + G2, y0 - f64(j1) + G2
	x2, y2 := x0 - 1 + 2 * G2, y0 - 1 + 2 * G2
	ii, jj := int(i64(i) & 255), int(i64(j) & 255)
	g0 := GRAD3[perm_at(n, ii + perm_at(n, jj)) % 12]
	g1 := GRAD3[perm_at(n, ii + i1 + perm_at(n, jj + j1)) % 12]
	g2 := GRAD3[perm_at(n, ii + 1 + perm_at(n, jj + 1)) % 12]
	sum := corner_share(0.5, x0 * x0 + y0 * y0, g0[0] * x0 + g0[1] * y0)
	sum += corner_share(0.5, x1 * x1 + y1 * y1, g1[0] * x1 + g1[1] * y1)
	sum += corner_share(0.5, x2 * x2 + y2 * y2, g2[0] * x2 + g2[1] * y2)
	return unit(70 * sum)
}

// Simplex noise from 0 to 1 in space.
simplex3 :: proc "contextless" (n: ^Noise, x, y, z: f64) -> f64 {
	F3 :: 1.0 / 3.0
	G3 :: 1.0 / 6.0
	skew := (x + y + z) * F3
	i, j, k := math.floor(x + skew), math.floor(y + skew), math.floor(z + skew)
	unskew := (i + j + k) * G3
	x0, y0, z0 := x - (i - unskew), y - (j - unskew), z - (k - unskew)
	// Which of the six tetrahedra of the skewed cube the point is in.
	i1, j1, k1, i2, j2, k2: int
	switch {
	case x0 >= y0 && y0 >= z0: i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 1, 0
	case x0 >= y0 && x0 >= z0: i1, j1, k1, i2, j2, k2 = 1, 0, 0, 1, 0, 1
	case x0 >= y0:             i1, j1, k1, i2, j2, k2 = 0, 0, 1, 1, 0, 1
	case y0 < z0:              i1, j1, k1, i2, j2, k2 = 0, 0, 1, 0, 1, 1
	case x0 < z0:              i1, j1, k1, i2, j2, k2 = 0, 1, 0, 0, 1, 1
	case:                      i1, j1, k1, i2, j2, k2 = 0, 1, 0, 1, 1, 0
	}
	x1, y1, z1 := x0 - f64(i1) + G3, y0 - f64(j1) + G3, z0 - f64(k1) + G3
	x2, y2, z2 := x0 - f64(i2) + 2 * G3, y0 - f64(j2) + 2 * G3, z0 - f64(k2) + 2 * G3
	x3, y3, z3 := x0 - 1 + 3 * G3, y0 - 1 + 3 * G3, z0 - 1 + 3 * G3
	ii, jj, kk := int(i64(i) & 255), int(i64(j) & 255), int(i64(k) & 255)
	hash :: proc "contextless" (n: ^Noise, a, b, c: int) -> int {
		return perm_at(n, a + perm_at(n, b + perm_at(n, c))) % 12
	}
	g0 := GRAD3[hash(n, ii, jj, kk)]
	g1 := GRAD3[hash(n, ii + i1, jj + j1, kk + k1)]
	g2 := GRAD3[hash(n, ii + i2, jj + j2, kk + k2)]
	g3 := GRAD3[hash(n, ii + 1, jj + 1, kk + 1)]
	sum := corner_share(0.6, x0 * x0 + y0 * y0 + z0 * z0, g0[0] * x0 + g0[1] * y0 + g0[2] * z0)
	sum += corner_share(0.6, x1 * x1 + y1 * y1 + z1 * z1, g1[0] * x1 + g1[1] * y1 + g1[2] * z1)
	sum += corner_share(0.6, x2 * x2 + y2 * y2 + z2 * z2, g2[0] * x2 + g2[1] * y2 + g2[2] * z2)
	sum += corner_share(0.6, x3 * x3 + y3 * y3 + z3 * z3, g3[0] * x3 + g3[1] * y3 + g3[2] * z3)
	return unit(32 * sum)
}

// Simplex noise from 0 to 1 in four dimensions (space and time, say).
simplex4 :: proc "contextless" (n: ^Noise, x, y, z, w: f64) -> f64 {
	F4 :: 0.30901699437494742410 // (sqrt(5) - 1) / 4
	G4 :: 0.13819660112501051518 // (5 - sqrt(5)) / 20
	skew := (x + y + z + w) * F4
	i, j, k, l := math.floor(x + skew), math.floor(y + skew), math.floor(z + skew), math.floor(w + skew)
	unskew := (i + j + k + l) * G4
	off := [4]f64{x - (i - unskew), y - (j - unskew), z - (k - unskew), w - (l - unskew)}
	// Rank the four offsets, largest first: that order is the path from the
	// cell's origin to its far corner through the simplex the point is in.
	rank: [4]int
	for a in 0 ..< 4 {
		for b in a + 1 ..< 4 {
			if off[a] > off[b] {rank[a] += 1} else {rank[b] += 1}
		}
	}
	cell := [4]int{int(i64(i) & 255), int(i64(j) & 255), int(i64(k) & 255), int(i64(l) & 255)}
	sum := 0.0
	// Corner 0 is the origin, corners 1 to 3 step through the ranked axes, corner 4 is (1,1,1,1).
	for corner in 0 ..< 5 {
		step: [4]int
		for axis in 0 ..< 4 {
			if corner == 4 || rank[axis] >= 4 - corner {
				step[axis] = 1
			}
		}
		if corner == 0 {
			step = {}
		}
		d: [4]f64
		dist_sq := 0.0
		for axis in 0 ..< 4 {
			d[axis] = off[axis] - f64(step[axis]) + f64(corner) * G4
			dist_sq += d[axis] * d[axis]
		}
		h := perm_at(n, cell[0] + step[0] + perm_at(n, cell[1] + step[1] + perm_at(n, cell[2] + step[2] + perm_at(n, cell[3] + step[3]))))
		g := GRAD4[h % 32]
		sum += corner_share(0.6, dist_sq, g[0] * d[0] + g[1] * d[1] + g[2] * d[2] + g[3] * d[3])
	}
	return unit(27 * sum)
}
