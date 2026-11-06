// SPDX-License-Identifier: 0BSD
package imgui

import "core:testing"

// Dear ImGui keeps one global context, so there is a single test that uses it.
@(test)
test_a_frame_of_widgets_is_built_and_draws_triangles :: proc(t: ^testing.T) {
	ctx := create_context()
	defer destroy_context(ctx)
	if !testing.expect(t, ctx != nil) {
		return
	}
	io := get_io()
	if !testing.expect(t, io != nil) {
		return
	}
	// no backend here: say the renderer takes the font textures, as a backend does
	io.backend_flags |= BackendFlags_RendererHasTextures
	io.display_size = {320, 200}
	io.delta_time = 1.0 / 60
	io.config_flags |= ConfigFlags_NavEnableKeyboard
	testing.expect(t, io.config_flags & ConfigFlags_NavEnableKeyboard != 0)

	value: f32 = 5
	// a window is sized from its contents on its first frame and drawn from the second
	for _ in 0 ..< 3 {
		new_frame()
		if begin("test") {
			testing.expect(t, !button("press"))
			testing.expect(t, !slider_float("size", &value, 0, 10))
			text("hello")
		}
		end()
		render()
	}
	data := get_draw_data()
	if testing.expect(t, data != nil) {
		testing.expect(t, data.valid)
		testing.expect(t, data.total_vtx_count > 0, "the window and its widgets make vertices")
		testing.expect(t, data.total_idx_count >= data.total_vtx_count)
	}
	testing.expect_value(t, value, f32(5))
}
