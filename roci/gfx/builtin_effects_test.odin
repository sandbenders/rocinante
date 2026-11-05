// SPDX-License-Identifier: 0BSD
package gfx

import "core:testing"

@(test)
test_every_builtin_effect_translates :: proc(t: ^testing.T) {
	defer shaders_stop()
	for b in BUILTIN_EFFECTS {
		id, message := shader_add(b.source, b.name, .Effect)
		testing.expectf(t, message == "", "%s: %s", b.name, message)
		testing.expect(t, shader_ok(id), b.name)
		data := shader_data(id)
		// Every default names a value the shader reads.
		for d in b.defaults {
			found := false
			for p in data.params.list {
				found ||= p.name == d.name
			}
			testing.expectf(t, found, "%s has no value called %s", b.name, d.name)
		}
	}
}

@(test)
test_builtin_effect_lookup :: proc(t: ^testing.T) {
	testing.expect(t, builtin_effect("blur") != nil)
	testing.expect(t, builtin_effect("blur.hlsl") == nil)
	testing.expect(t, builtin_effect("") == nil)
	testing.expect(t, builtin_effect("Blur") == nil)
}
