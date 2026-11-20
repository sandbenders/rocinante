// SPDX-License-Identifier: 0BSD
//
// The phone's own vibration. An Android phone's vibrator is a haptic device of SDL's (its Java side lists it as
// `VIBRATOR_SERVICE`), so it is played for the time asked. An iPhone has no way to ask for a length: the system's
// vibrate sound buzzes for the time it chooses. Everywhere else there is nothing to vibrate and nothing happens.
package platform

import sdl "vendor:sdl3"

// The vibrator once it is open, on a phone that has one.
@(private) phone_haptic: ^sdl.Haptic

when ODIN_PLATFORM_SUBTARGET == .Android {

	// Buzzes the phone for `seconds`. False when it has no vibrator or would not.
	vibrate :: proc(seconds: f64) -> bool {
		if phone_haptic == nil {
			if !sdl.InitSubSystem({.HAPTIC}) {
				return false
			}
			count: i32
			ids := sdl.GetHaptics(&count)
			if ids == nil {
				return false
			}
			defer sdl.free(ids)
			if count < 1 {
				return false
			}
			phone_haptic = sdl.OpenHaptic(ids^)
			if phone_haptic == nil || !sdl.InitHapticRumble(phone_haptic) {
				phone_haptic = nil
				return false
			}
		}
		return sdl.PlayHapticRumble(phone_haptic, 1, u32(seconds * 1000))
	}
} else when ODIN_PLATFORM_SUBTARGET == .iPhone {
	foreign import audio_toolbox "system:AudioToolbox.framework"

	@(default_calling_convention = "c")
	foreign audio_toolbox {
		AudioServicesPlaySystemSound :: proc(id: u32) ---
	}

	// The system sound that vibrates a phone.
	VIBRATE_SOUND :: 4095

	vibrate :: proc(seconds: f64) -> bool {
		AudioServicesPlaySystemSound(VIBRATE_SOUND)
		return true
	}
} else {
	vibrate :: proc(seconds: f64) -> bool {
		return false
	}
}
