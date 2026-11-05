// SPDX-License-Identifier: 0BSD
//
// Making new pictures out of the pixels of one: cut a part out (`crop`), scale it
// (`resize`), change its colours or blur it (`filter`) and let another picture decide
// what shows (`mask`). A picture here is `width` by `height` pixels of red, green, blue
// and alpha, 8 bits each, straight alpha, rows from the top, as the image store keeps
// them. Everything is pure CPU work on byte slices and gives a new slice: the picture it
// was made from is never changed. Anything that mixes pixels (resizing, blurring,
// averaging) mixes them with their alpha already multiplied in, so the colour of a
// see-through pixel never bleeds into its neighbours.
package gfx

import "core:math"

// What `filter` can do to a picture.
Filter_Kind :: enum u8 {
	Gray,      // each pixel becomes the gray of how bright it looks
	Invert,    // each colour becomes its opposite; alpha stays
	Threshold, // black below a brightness, white from it
	Posterize, // only a few steps of each colour
	Blur,      // a soft blur by a radius in pixels
	Edges,     // where the picture changes quickly, bright; gray elsewhere
	Pixelate,  // blocks of one colour
}

// The amount a filter uses when none is given: a brightness (0 to 255) for threshold, a
// number of steps for posterize, a radius in pixels for blur and a block size in pixels for pixelate.
filter_default_amount :: proc "contextless" (kind: Filter_Kind) -> f64 {
	switch kind {
	case .Threshold: return 128
	case .Posterize: return 4
	case .Blur:      return 2
	case .Pixelate:  return 8
	case .Gray, .Invert, .Edges:
	}
	return 0
}

// How bright a colour looks, 0 to 255 (the weights the eye gives red, green and blue).
brightness_of :: proc "contextless" (r, g, b: f32) -> f32 {
	return 0.299 * r + 0.587 * g + 0.114 * b
}

@(private)
to_byte :: proc "contextless" (v: f32) -> u8 {
	return u8(clamp(v + 0.5, 0, 255))
}

// The picture's colours with each colour channel multiplied by its alpha (0 to 1), four
// floats a pixel: red, green and blue from 0 to 255, alpha from 0 to 1.
@(private)
premultiplied :: proc(pixels: []u8, allocator := context.temp_allocator) -> []f32 {
	out := make([]f32, len(pixels), allocator)
	for i := 0; i < len(pixels); i += 4 {
		a := f32(pixels[i + 3]) / 255
		out[i], out[i + 1], out[i + 2], out[i + 3] = f32(pixels[i]) * a, f32(pixels[i + 1]) * a, f32(pixels[i + 2]) * a, a
	}
	return out
}

// Straight bytes from premultiplied floats.
@(private)
unpremultiplied :: proc(floats: []f32, allocator := context.allocator) -> []u8 {
	out := make([]u8, len(floats), allocator)
	for i := 0; i < len(floats); i += 4 {
		a := floats[i + 3]
		if a <= 0.0001 {
			continue
		}
		out[i], out[i + 1], out[i + 2], out[i + 3] = to_byte(floats[i] / a), to_byte(floats[i + 1] / a), to_byte(floats[i + 2] / a), to_byte(a * 255)
	}
	return out
}

// ---- crop ----

// The part of a picture inside the box `x y w h` (in pixels, from the top left), cut to
// the picture: a box that sticks out gives only what is inside, and one that is entirely
// outside, or empty, gives nothing (a 0 by 0 picture).
pixels_crop :: proc(src: []u8, width, height: int, x, y, w, h: f64, allocator := context.allocator) -> (out: []u8, out_width, out_height: int) {
	if !finite_f64(x, y, w, h) || w <= 0 || h <= 0 || width <= 0 || height <= 0 {
		return nil, 0, 0
	}
	x0 := clamp(int(math.floor(x)), 0, width)
	y0 := clamp(int(math.floor(y)), 0, height)
	x1 := clamp(int(math.ceil(x + w)), 0, width)
	y1 := clamp(int(math.ceil(y + h)), 0, height)
	out_width, out_height = x1 - x0, y1 - y0
	if out_width <= 0 || out_height <= 0 {
		return nil, 0, 0
	}
	out = make([]u8, out_width * out_height * 4, allocator)
	for row in 0 ..< out_height {
		copy(out[row * out_width * 4:][:out_width * 4], src[((y0 + row) * width + x0) * 4:][:out_width * 4])
	}
	return
}

@(private)
finite_f64 :: proc "contextless" (values: ..f64) -> bool {
	for v in values {
		if math.is_nan(v) || math.is_inf(v) {
			return false
		}
	}
	return true
}

// ---- resize ----

// A picture scaled to `dw` by `dh` pixels. Smooth scaling mixes the pixels it covers: a
// smaller picture takes the average of the pixels each new one stands for, a bigger one
// mixes the four pixels round the place; `smooth` false takes the nearest pixel instead,
// which keeps hard edges. A size that is not at least 1 by 1 gives nothing.
pixels_resize :: proc(src: []u8, width, height, dw, dh: int, smooth: bool, allocator := context.allocator) -> []u8 {
	if width <= 0 || height <= 0 || dw <= 0 || dh <= 0 || len(src) != width * height * 4 {
		return nil
	}
	out := make([]u8, dw * dh * 4, allocator)
	if !smooth {
		for y in 0 ..< dh {
			sy := min(int((f64(y) + 0.5) * f64(height) / f64(dh)), height - 1)
			for x in 0 ..< dw {
				sx := min(int((f64(x) + 0.5) * f64(width) / f64(dw)), width - 1)
				copy(out[(y * dw + x) * 4:][:4], src[(sy * width + sx) * 4:][:4])
			}
		}
		return out
	}
	// Two passes, across and then down, each by whichever way suits the axis.
	source := premultiplied(src)
	across := resample_axis(source, width, height, dw, true)
	down := resample_axis(across, dw, height, dh, false)
	result := unpremultiplied(down, allocator)
	copy(out, result)
	delete(result, allocator)
	return out
}

// Scales one axis of premultiplied pixels: `horizontal` says which. Going down in size it
// averages every source pixel a new one covers, by how much of it they cover; going up it
// mixes the two pixels either side of the new one's middle.
@(private)
resample_axis :: proc(src: []f32, width, height, to: int, horizontal: bool) -> []f32 {
	from := width if horizontal else height
	out_width, out_height := to, height
	if !horizontal {
		out_width, out_height = width, to
	}
	out := make([]f32, out_width * out_height * 4, context.temp_allocator)
	scale := f64(from) / f64(to)
	lines := height if horizontal else width
	for i in 0 ..< to {
		lo, hi := f64(i) * scale, f64(i + 1) * scale
		if to < from {
			first, last := int(math.floor(lo)), min(int(math.ceil(hi)) - 1, from - 1)
			total := f32(0)
			for s in first ..= last {
				weight := f32(min(hi, f64(s + 1)) - max(lo, f64(s)))
				total += weight
				for line in 0 ..< lines {
					at := ((line * width + s) if horizontal else (s * width + line)) * 4
					put := ((line * out_width + i) if horizontal else (i * out_width + line)) * 4
					for k in 0 ..< 4 {
						out[put + k] += src[at + k] * weight
					}
				}
			}
			for line in 0 ..< lines {
				put := ((line * out_width + i) if horizontal else (i * out_width + line)) * 4
				for k in 0 ..< 4 {
					out[put + k] /= total
				}
			}
		} else {
			centre := (f64(i) + 0.5) * scale - 0.5
			a := int(math.floor(centre))
			t := f32(centre - f64(a))
			b := a + 1
			a, b = clamp(a, 0, from - 1), clamp(b, 0, from - 1)
			for line in 0 ..< lines {
				at_a := ((line * width + a) if horizontal else (a * width + line)) * 4
				at_b := ((line * width + b) if horizontal else (b * width + line)) * 4
				put := ((line * out_width + i) if horizontal else (i * out_width + line)) * 4
				for k in 0 ..< 4 {
					out[put + k] = src[at_a + k] * (1 - t) + src[at_b + k] * t
				}
			}
		}
	}
	return out
}

// ---- filter ----

// The picture with a filter applied. `amount` is what the filter uses (see
// `filter_default_amount`); a number that is not a number takes the default. Alpha is kept
// by every filter except blur and pixelate, which mix it like a colour.
pixels_filter :: proc(src: []u8, width, height: int, kind: Filter_Kind, amount: f64, allocator := context.allocator) -> []u8 {
	if width <= 0 || height <= 0 || len(src) != width * height * 4 {
		return nil
	}
	n := amount if finite_f64(amount) else filter_default_amount(kind)
	switch kind {
	case .Gray, .Invert, .Threshold, .Posterize:
		return filter_per_pixel(src, kind, n, allocator)
	case .Blur:
		return filter_blur(src, width, height, n, allocator)
	case .Edges:
		return filter_edges(src, width, height, allocator)
	case .Pixelate:
		return filter_pixelate(src, width, height, n, allocator)
	}
	return nil
}

@(private)
filter_per_pixel :: proc(src: []u8, kind: Filter_Kind, amount: f64, allocator := context.allocator) -> []u8 {
	out := make([]u8, len(src), allocator)
	steps := clamp(f32(amount), 2, 255) // posterize: how many levels of each colour
	level := f32(clamp(amount, 0, 255))   // threshold: the brightness it turns at
	for i := 0; i < len(src); i += 4 {
		r, g, b := f32(src[i]), f32(src[i + 1]), f32(src[i + 2])
		out[i + 3] = src[i + 3]
		switch kind {
		case .Gray:
			v := to_byte(brightness_of(r, g, b))
			out[i], out[i + 1], out[i + 2] = v, v, v
		case .Invert:
			out[i], out[i + 1], out[i + 2] = 255 - src[i], 255 - src[i + 1], 255 - src[i + 2]
		case .Threshold:
			v := u8(255) if brightness_of(r, g, b) >= level else u8(0)
			out[i], out[i + 1], out[i + 2] = v, v, v
		case .Posterize:
			step := 255 / (steps - 1)
			out[i], out[i + 1], out[i + 2] = to_byte(math.floor(r / step + 0.5) * step), to_byte(math.floor(g / step + 0.5) * step), to_byte(math.floor(b / step + 0.5) * step)
		case .Blur, .Edges, .Pixelate:
		}
	}
	return out
}

// Box widths whose three passes make a blur close to a gaussian one of spread `sigma`
// (the "boxes for gauss" method): each is odd, so it has a middle.
@(private)
box_widths :: proc "contextless" (sigma: f64) -> [3]int {
	ideal := math.sqrt(12 * sigma * sigma / 3 + 1)
	lower := int(math.floor(ideal))
	if lower % 2 == 0 {
		lower -= 1
	}
	upper := lower + 2
	split := int(math.round((12 * sigma * sigma - 3 * f64(lower * lower) - 12 * f64(lower) - 9) / (-4 * f64(lower) - 4)))
	widths: [3]int
	for i in 0 ..< 3 {
		widths[i] = lower if i < split else upper
		widths[i] = max(widths[i], 1)
	}
	return widths
}

// One pass of a box blur of this radius along one axis, with the edge pixel repeated.
@(private)
box_pass :: proc(src: []f32, width, height, radius: int, horizontal: bool) -> []f32 {
	out := make([]f32, len(src), context.temp_allocator)
	length := width if horizontal else height
	lines := height if horizontal else width
	window := f32(2 * radius + 1)
	at :: proc(width: int, horizontal: bool, line, i: int) -> int {
		return ((line * width + i) if horizontal else (i * width + line)) * 4
	}
	for line in 0 ..< lines {
		sum: [4]f32
		for i in -radius ..= radius {
			p := at(width, horizontal, line, clamp(i, 0, length - 1))
			for k in 0 ..< 4 {
				sum[k] += src[p + k]
			}
		}
		for i in 0 ..< length {
			put := at(width, horizontal, line, i)
			for k in 0 ..< 4 {
				out[put + k] = sum[k] / window
			}
			leaving := at(width, horizontal, line, clamp(i - radius, 0, length - 1))
			entering := at(width, horizontal, line, clamp(i + radius + 1, 0, length - 1))
			for k in 0 ..< 4 {
				sum[k] += src[entering + k] - src[leaving + k]
			}
		}
	}
	return out
}

@(private)
filter_blur :: proc(src: []u8, width, height: int, radius: f64, allocator := context.allocator) -> []u8 {
	if radius < 0.5 {
		out := make([]u8, len(src), allocator)
		copy(out, src)
		return out
	}
	widths := box_widths(min(radius, 200) / 2)
	pixels := premultiplied(src)
	for w in widths {
		pixels = box_pass(pixels, width, height, (w - 1) / 2, true)
		pixels = box_pass(pixels, width, height, (w - 1) / 2, false)
	}
	return unpremultiplied(pixels, allocator)
}

@(private)
filter_edges :: proc(src: []u8, width, height: int, allocator := context.allocator) -> []u8 {
	light := make([]f32, width * height, context.temp_allocator)
	for i in 0 ..< width * height {
		a := f32(src[i * 4 + 3]) / 255
		light[i] = brightness_of(f32(src[i * 4]), f32(src[i * 4 + 1]), f32(src[i * 4 + 2])) * a
	}
	at :: proc(light: []f32, width, height, x, y: int) -> f32 {
		return light[clamp(y, 0, height - 1) * width + clamp(x, 0, width - 1)]
	}
	out := make([]u8, len(src), allocator)
	for y in 0 ..< height {
		for x in 0 ..< width {
			gx := -at(light, width, height, x - 1, y - 1) + at(light, width, height, x + 1, y - 1) -
				2 * at(light, width, height, x - 1, y) + 2 * at(light, width, height, x + 1, y) -
				at(light, width, height, x - 1, y + 1) + at(light, width, height, x + 1, y + 1)
			gy := -at(light, width, height, x - 1, y - 1) - 2 * at(light, width, height, x, y - 1) - at(light, width, height, x + 1, y - 1) +
				at(light, width, height, x - 1, y + 1) + 2 * at(light, width, height, x, y + 1) + at(light, width, height, x + 1, y + 1)
			v := to_byte(math.sqrt(gx * gx + gy * gy) / 4) // a jump of the whole range across the kernel is 255
			i := (y * width + x) * 4
			out[i], out[i + 1], out[i + 2], out[i + 3] = v, v, v, src[i + 3]
		}
	}
	return out
}

@(private)
filter_pixelate :: proc(src: []u8, width, height: int, block: f64, allocator := context.allocator) -> []u8 {
	size := max(int(math.round(block)), 1)
	out := make([]u8, len(src), allocator)
	pixels := premultiplied(src)
	for by := 0; by < height; by += size {
		for bx := 0; bx < width; bx += size {
			x1, y1 := min(bx + size, width), min(by + size, height)
			sum: [4]f32
			for y in by ..< y1 {
				for x in bx ..< x1 {
					for k in 0 ..< 4 {
						sum[k] += pixels[(y * width + x) * 4 + k]
					}
				}
			}
			count := f32((x1 - bx) * (y1 - by))
			mean := [4]f32{sum[0] / count, sum[1] / count, sum[2] / count, sum[3] / count}
			a := mean.a
			value: [4]u8
			if a > 0.0001 {
				value = {to_byte(mean.r / a), to_byte(mean.g / a), to_byte(mean.b / a), to_byte(a * 255)}
			}
			for y in by ..< y1 {
				for x in bx ..< x1 {
					copy(out[(y * width + x) * 4:][:4], value[:])
				}
			}
		}
	}
	return out
}

// ---- mask ----

// The picture with its alpha multiplied by how much of the stencil shows at the same
// place: white and solid shows the picture, black or see-through hides it. The stencil
// is stretched over the picture when it is another size.
pixels_mask :: proc(src: []u8, width, height: int, stencil: []u8, stencil_width, stencil_height: int, allocator := context.allocator) -> []u8 {
	if width <= 0 || height <= 0 || len(src) != width * height * 4 || stencil_width <= 0 || stencil_height <= 0 || len(stencil) != stencil_width * stencil_height * 4 {
		return nil
	}
	fitted := stencil
	if stencil_width != width || stencil_height != height {
		fitted = pixels_resize(stencil, stencil_width, stencil_height, width, height, true, context.temp_allocator)
	}
	out := make([]u8, len(src), allocator)
	for i := 0; i < len(src); i += 4 {
		show := brightness_of(f32(fitted[i]), f32(fitted[i + 1]), f32(fitted[i + 2])) / 255 * f32(fitted[i + 3]) / 255
		out[i], out[i + 1], out[i + 2] = src[i], src[i + 1], src[i + 2]
		out[i + 3] = to_byte(f32(src[i + 3]) * show)
	}
	return out
}
