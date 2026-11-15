// SPDX-License-Identifier: 0BSD
//
// MIDI out in the language: `midi note`, `midi release`, `midi set`, `midi bend`, `midi program`, `midi to`,
// `midi outputs`, `midi clock` and `midi stop`. The sending is `roci`'s (`roci/midi_out.odin`).
package interp

import "core:fmt"
import "core:strings"

import "../"
import "../lang"

// Says there is nowhere to send, once for each place that tried.
@(private)
say_midi_result :: proc(it: ^Interp, result: roci.Midi_Out_Result, span: lang.Span, picked: string) {
	switch result {
	case .Sent, .Not_Sent:
		// a device that would not take a message is not worth a message each time: the next is tried
	case .No_Device:
		a, b := "", "No MIDI output was found on this computer, so there is nowhere to send to."
		if picked != "" {
			a = fmt.tprintf(" called `%s`", picked)
			b = "No output has that in its name."
		}
		fail(it, .Midi_Out_Missing, span, a, b, "", "midi to \"\"")
	}
}

// An option's number, when it was written.
@(private)
midi_option :: proc(it: ^Interp, call: lang.IR_Call, word: string) -> Maybe(f64) {
	if v, ok := option_value(it, call.options, word); ok {
		return as_number(v)
	}
	return nil
}

@(private)
midi_out_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call, code: Verb_Code) {
	picked := roci.midi_to_name_now()
	result := roci.Midi_Out_Result.Sent
	channel := midi_option(it, call, "channel")
	#partial switch code {
	case .Midi_Note:
		result = roci.midi_note(as_number(eval(it, call.args[0])), midi_option(it, call, "velocity"), channel, midi_option(it, call, "for"))
	case .Midi_Release:
		if len(call.args) > 0 {
			result = roci.midi_release(as_number(eval(it, call.args[0])), channel)
		} else {
			result = roci.midi_release(nil, channel)
		}
	case .Midi_Set:
		to := midi_option(it, call, "to")
		result = roci.midi_set(as_number(eval(it, call.args[0])), to.? or_else 0, channel)
	case .Midi_Bend:
		result = roci.midi_bend(as_number(eval(it, call.args[0])), channel)
	case .Midi_Program:
		result = roci.midi_program(as_number(eval(it, call.args[0])), channel)
	case .Midi_To:
		roci.midi_to(as_text(eval(it, call.args[0])))
		return
	case .Midi_Clock:
		result = roci.midi_clock(as_number(eval(it, call.args[0])))
	case .Midi_Stop:
		roci.midi_clock_stop()
		return
	}
	say_midi_result(it, result, e.span, picked)
}

// `midi outputs`: the names as a list of text.
@(private)
midi_outputs_verb :: proc(it: ^Interp) -> Value {
	names := roci.midi_outputs(context.temp_allocator)
	items := make([]Value, len(names), context.temp_allocator)
	for n, i in names {
		items[i] = strings.clone(n, it.alloc)
	}
	return new_list(it, ..items)
}
