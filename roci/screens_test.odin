package roci

import "core:testing"

@(test)
test_a_headless_run_has_one_stand_in_screen :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	all := screens()
	testing.expect_value(t, len(all), 1)
	testing.expect_value(t, all[0].width, 1920)
	testing.expect_value(t, all[0].height, 1080)
	testing.expect_value(t, all[0].density, 1)
	testing.expect_value(t, all[0].refresh, 60)
	testing.expect(t, all[0].main)
}

@(test)
test_a_test_can_say_what_screens_there_are :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	set_screens({{name = "Left", x = -2560, width = 2560, height = 1440, density = 1, refresh = 144}, {name = "Laptop", width = 1512, height = 982, density = 2, refresh = 120, main = true}})
	all := screens()
	testing.expect_value(t, len(all), 2)
	testing.expect_value(t, all[0].name, "Left")
	testing.expect_value(t, all[0].x, -2560)
	testing.expect_value(t, all[1].density, 2)
	testing.expect(t, all[1].main && !all[0].main)
	set_screens(nil)
	testing.expect_value(t, len(screens()), 1)
	testing.expect_value(t, screens()[0].name, "Screen")
}

@(test)
test_the_platform_is_one_of_the_known_names :: proc(t: ^testing.T) {
	name := platform_name()
	known := false
	for n in ([]string{"macos", "windows", "linux", "freebsd", "openbsd", "ios", "android"}) {
		known ||= n == name
	}
	testing.expect(t, known)
	when ODIN_OS == .Darwin && !ODIN_PLATFORM_SUBTARGET_IOS {
		testing.expect_value(t, name, "macos")
	}
}

@(test)
test_c_reads_the_platform_and_the_screens_by_place :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer abi_text_stop()
	testing.expect_value(t, string(abi_platform()), platform_name())
	testing.expect_value(t, abi_screen_count(), 1)
	testing.expect_value(t, abi_screen_size(0), Abi_Vec2{1920, 1080})
	set_screens({{name = "Main", width = 1512, height = 982, density = 2, refresh = 120, main = true}, {name = "Side", x = 1512, y = -100, width = 1920, height = 1080, density = 1}})
	testing.expect_value(t, abi_screen_count(), 2)
	testing.expect_value(t, string(abi_screen_name(0)), "Main")
	testing.expect_value(t, string(abi_screen_name(1)), "Side")
	testing.expect_value(t, abi_screen_pos(1), Abi_Vec2{1512, -100})
	testing.expect_value(t, abi_screen_size(0), Abi_Vec2{1512, 982})
	testing.expect_value(t, abi_screen_density(0), 2)
	testing.expect_value(t, abi_screen_refresh(0), 120)
	testing.expect_value(t, abi_screen_refresh(1), 0)
	testing.expect_value(t, abi_screen_main(0), 1)
	testing.expect_value(t, abi_screen_main(1), 0)
	// places that are not there are quiet zeros and an empty name
	testing.expect_value(t, string(abi_screen_name(2)), "")
	testing.expect_value(t, string(abi_screen_name(-1)), "")
	testing.expect_value(t, abi_screen_size(2), Abi_Vec2{})
	testing.expect_value(t, abi_screen_density(-1), 0)
	testing.expect_value(t, abi_screen_main(9), 0)
}

@(test)
test_a_headless_run_has_no_safe_area_and_a_test_can_give_one :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, safe_area(), Safe_Area{})
	set_safe_area({top = 54, bottom = 30, left = 12, right = 8})
	defer set_safe_area({})
	testing.expect_value(t, safe_area(), Safe_Area{top = 54, bottom = 30, left = 12, right = 8})
	// C reads the same
	insets := abi_safe_area()
	testing.expect_value(t, insets, Abi_Insets{54, 30, 12, 8})
}
