// SPDX-License-Identifier: 0BSD
//
// How a packaged app starts. Its assets are in the bundle (`assets` is looked for in `resources`), and the bundle is
// read-only and the program's folder is nothing a person chose, so everything the sketch writes (`output/`, what it
// remembers, its vault) goes in the app's own folder, which the program works from. The files a sketch ships to start
// from (`memory.toml`, the vault and its key, `ui.toml`) are copied there the first time.
package rt

import "core:os"
import "core:strings"

// The files of the bundle that become the app's own copy the first time it runs.
SEED_FILES := [?]string{"memory.toml", "vault.bin", "vault.key", "ui.toml"}

// Points the program at its bundle and its own folder, seeds that folder and works from it. `resources` is where the
// bundle keeps the sketch's files and `data` the folder the app may write in.
enter_app :: proc(resources, data: string) {
	use_home(resources, data)
	lenient_args = true
	seed_home(resources, data)
	if data != "" {
		_ = os.change_directory(data)
	}
}

// Copies each seed file the bundle has into `data` when `data` has no file of that name. Gives how many were copied.
seed_home :: proc(resources, data: string) -> int {
	copied := 0
	for name in SEED_FILES {
		from := strings.concatenate({strings.trim_right(resources, "/"), "/", name}, context.temp_allocator)
		to := strings.concatenate({strings.trim_right(data, "/"), "/", name}, context.temp_allocator)
		if !os.is_file(from) || os.exists(to) {
			continue
		}
		bytes, err := os.read_entire_file(from, context.temp_allocator)
		if err != nil {
			continue
		}
		if os.write_entire_file(to, bytes) == nil {
			copied += 1
		}
	}
	return copied
}
