// SPDX-License-Identifier: 0BSD
//
// The pixel verbs: `pixel`, `pixels`, `picture`, `crop`, `resize`, `filter` and `mask`,
// over roci/pixels.odin. A picture they make is another picture; none of them changes the
// one it was given. A picture that is not there gives the empty answer without a word
// (`load` already said so); a canvas that could not be read back is a runtime message.
package interp

import "../"
import "../lang"
import "core:fmt"
import "core:math"

@(private)
picture_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call, code: Verb_Code) -> Value {
	picture: roci.Image
	if len(call.args) > 0 {
		picture = as_image(eval(it, call.args[0]))
	}
	#partial switch code {
	case .Pixel:
		at, _ := option_pair(it, call.options, "at")
		colour, ok := roci.pixel_of(picture, at.x, at.y)
		if !ok {
			say_unreadable(it, e)
		}
		return colour
	case .Pixels:
		colours, too_big, ok := roci.colors_of(picture, context.temp_allocator)
		out := new_list(it)
		if !ok {
			say_unreadable(it, e)
		} else if too_big {
			size := roci.image_size(picture)
			fail(it, .Picture_Too_Big, e.span, "", fmt.tprintf("%d", int(size.x * size.y)), "", "small = resize photo size 64 0\ncolors = pixels small")
		}
		for c in colours {
			append(&out.items, c)
		}
		return out
	case .Picture:
		size, _ := option_pair(it, call.options, "size")
		width, height := int(math.round(size.x)) if is_finite(size.x) else 0, int(math.round(size.y)) if is_finite(size.y) else 0
		colours := make([dynamic]roci.Colour, context.temp_allocator)
		if list := as_list(option_or_nil(it, call.options, "from")); list != nil {
			for item in list.items {
				append(&colours, as_colour(item))
			}
		}
		made := roci.picture_from_colors(colours[:], width, height)
		if made == 0 {
			say_bad_size(it, e, "A picture is at least 1 by 1 pixels and at most 16384 on a side, and 32 million pixels in all.", "small = picture from [ red blue ] size 2 1")
		}
		return made
	case .Crop:
		at, _ := option_pair(it, call.options, "at")
		size, _ := option_pair(it, call.options, "size")
		made, ok := roci.crop_picture(picture, at.x, at.y, size.x, size.y)
		if !ok {
			say_unreadable(it, e)
		}
		return made
	case .Resize:
		size, _ := option_pair(it, call.options, "size")
		own := roci.image_size(picture)
		width, height := size.x, size.y
		// A side given as 0 follows the picture's shape.
		if width <= 0 && height > 0 && own.y > 0 {
			width = own.x * height / own.y
		} else if height <= 0 && width > 0 && own.x > 0 {
			height = own.y * width / own.x
		}
		smooth := as_text(option_or_nil(it, call.options, "as")) != "nearest"
		made, ok := roci.resize_picture(picture, width, height, smooth)
		if !ok {
			say_unreadable(it, e)
		} else if made == 0 && own.x > 0 {
			say_bad_size(it, e, "A picture is at least 1 by 1 pixels and at most 16384 on a side, and 32 million pixels in all. A side of 0 follows the picture's shape, so one side has to be given.", "small = resize photo size 64 0")
		}
		return made
	case .Filter:
		kind: roci.Filter
		switch as_text(option_or_nil(it, call.options, "as")) {
		case "gray":      kind = .Gray
		case "invert":    kind = .Invert
		case "threshold": kind = .Threshold
		case "posterize": kind = .Posterize
		case "blur":      kind = .Blur
		case "edges":     kind = .Edges
		case "pixelate":  kind = .Pixelate
		case:             return 0
		}
		amount: Maybe(f64)
		if v, found := option_value(it, call.options, "by"); found {
			amount = as_number(v)
		}
		made, ok := roci.filter_picture(picture, kind, amount)
		if !ok {
			say_unreadable(it, e)
		}
		return made
	case .Mask:
		stencil := as_image(option_or_nil(it, call.options, "by"))
		made, ok := roci.mask_picture(picture, stencil)
		if !ok {
			say_unreadable(it, e)
		}
		return made
	}
	return nil
}

@(private)
is_finite :: proc(v: f64) -> bool {
	return !math.is_nan(v) && !math.is_inf(v)
}

@(private)
say_unreadable :: proc(it: ^Interp, e: ^lang.IR) {
	fail(it, .Pixels_Unavailable, e.span, "", fmt.tprintf("The graphics card would not give the canvas back (%s), so there are no pixels to read.", roci.last_error()), "", "")
}

@(private)
say_bad_size :: proc(it: ^Interp, e: ^lang.IR, why, example: string) {
	fail(it, .Picture_Size, e.span, "", why, "", example)
}
