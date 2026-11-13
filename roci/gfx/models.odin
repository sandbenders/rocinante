// SPDX-License-Identifier: 0BSD
//
// The models a sketch has loaded, kept on this thread like the pictures are: `model_add` reads a
// file's bytes once (gltf.odin) and gives it a number that the scene's shapes name. A file that
// is read again with a new modification time keeps its number and its place, with a new
// `version`, so a model that is edited while the sketch runs is drawn as it now is and the
// renderer knows to send it to the graphics card again.
package gfx

import "core:strings"

Model_Id :: distinct u32

Model_Slot :: struct {
	path:    string, // the file, as the interpreter found it
	stamp:   i64,    // when it was last changed (nanoseconds), or any number that changes with the file
	version: u32,
	data:    Model_Data,
}

@(thread_local) model_slots: [dynamic]Model_Slot
@(thread_local) model_epoch_value: int

// Which set of models the numbers belong to: it changes when they are all let go.
model_epoch :: proc() -> int {
	return model_epoch_value
}

// Keeps a model read from the file `path`, whose `stamp` is when it changed. Takes over the
// arrays of `data`. A file that is already here has the same number, and a new version.
model_add :: proc(path: string, stamp: i64, data: Model_Data) -> Model_Id {
	for &slot, i in model_slots {
		if slot.path == path {
			model_data_destroy(&slot.data)
			slot.data, slot.stamp = data, stamp
			slot.version += 1
			return Model_Id(i + 1)
		}
	}
	append(&model_slots, Model_Slot{path = strings.clone(path), stamp = stamp, version = 1, data = data})
	return Model_Id(len(model_slots))
}

// The number of the model read from `path` when it was last changed at `stamp`, if there is one.
model_find :: proc(path: string, stamp: i64) -> (id: Model_Id, found: bool) {
	for slot, i in model_slots {
		if slot.path == path && slot.stamp == stamp {
			return Model_Id(i + 1), true
		}
	}
	return 0, false
}

// A model's data, or nil for a number that names none.
model_data :: proc(id: Model_Id) -> ^Model_Data {
	if id == 0 || int(id) > len(model_slots) {
		return nil
	}
	return &model_slots[int(id) - 1].data
}

model_version :: proc(id: Model_Id) -> u32 {
	if id == 0 || int(id) > len(model_slots) {
		return 0
	}
	return model_slots[int(id) - 1].version
}

// Lets go of every model.
models_stop :: proc() {
	for &slot in model_slots {
		delete(slot.path)
		model_data_destroy(&slot.data)
	}
	delete(model_slots)
	model_slots = nil
	model_epoch_value += 1
}

// Reads a model file's bytes as the kind of file its name says: an `.obj` is a Wavefront model and
// anything else is glTF (`.glb` or `.gltf`).
model_read :: proc(path: string, bytes: []byte, reader: Gltf_Reader = nil, allocator := context.allocator) -> (Model_Data, Gltf_Error) {
	if strings.has_suffix(strings.to_lower(path, context.temp_allocator), ".obj") {
		return obj_read(bytes, reader, allocator)
	}
	return gltf_read(bytes, reader, allocator)
}
