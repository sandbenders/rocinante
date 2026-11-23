// SPDX-License-Identifier: 0BSD
#+feature dynamic-literals
package main

import "core:encoding/endian"
import "core:strings"
import "core:testing"

@(test)
test_windows_formats_are_the_zip_alone_unless_asked :: proc(t: ^testing.T) {
	formats, bad := parse_windows_formats("")
	testing.expect_value(t, bad, "")
	testing.expect_value(t, len(formats), 1)
	testing.expect_value(t, formats[0], Windows_Format.Zip)

	formats, bad = parse_windows_formats("msix")
	testing.expect_value(t, len(formats), 1)
	testing.expect_value(t, formats[0], Windows_Format.Msix)

	// in the order they are made, each once, whatever the order and case they are written in
	formats, bad = parse_windows_formats(" MSIX, zip ,msix,")
	testing.expect_value(t, len(formats), 2)
	testing.expect_value(t, formats[0], Windows_Format.Zip)
	testing.expect_value(t, formats[1], Windows_Format.Msix)

	formats, _ = parse_windows_formats("all")
	testing.expect_value(t, len(formats), 2)
	formats, _ = parse_windows_formats("appx")
	testing.expect_value(t, formats[0], Windows_Format.Msix)

	_, bad = parse_windows_formats("zip, msi")
	testing.expect_value(t, bad, "msi")
}

@(test)
test_windows_names_are_safe_for_files :: proc(t: ^testing.T) {
	names := windows_names("Wild Vex", "wild-vex", "1.0.1")
	testing.expect_value(t, names.folder, "Wild Vex")
	testing.expect_value(t, names.executable, "wild-vex.exe")
	testing.expect_value(t, names.zip, "wild-vex-1.0.1-windows-x64.zip")
	testing.expect_value(t, names.msix, "wild-vex-1.0.1-windows-x64.msix")

	testing.expect_value(t, windows_file_name(`A/B: "c"?`), `A-B- -c--`)
	testing.expect_value(t, windows_file_name("Rain..  "), "Rain")
	testing.expect_value(t, windows_file_name("  Rain"), "Rain")
	testing.expect_value(t, windows_file_name("tab\there"), "tab-here")
	testing.expect_value(t, windows_file_name("Café"), "Café")
	testing.expect_value(t, windows_file_name(""), "app")
	testing.expect_value(t, windows_file_name(". ."), "app")
}

@(test)
test_a_windows_version_is_four_numbers_of_at_most_65535 :: proc(t: ^testing.T) {
	numbers, problem := windows_version("1.0.1", 7)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, numbers, [4]int{1, 0, 1, 7})

	numbers, problem = windows_version("2", 0)
	testing.expect_value(t, numbers, [4]int{2, 0, 0, 0})
	numbers, problem = windows_version("2026.11.23", 65535)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, numbers, [4]int{2026, 11, 23, 65535})

	_, problem = windows_version("1.65536", 1)
	testing.expect(t, strings.contains(problem, "65536") && strings.contains(problem, "65535"), problem)
	_, problem = windows_version("1.0", 65536)
	testing.expect(t, strings.contains(problem, "build number is 65536"), problem)
	_, problem = windows_version("1.0", -1)
	testing.expect(t, problem != "", "a negative build")
	for bad in ([]string{"", "1.2.3.4", "1..2", "a.b", "-1", "+1", "1.0-beta"}) {
		_, problem = windows_version(bad, 1)
		testing.expectf(t, strings.contains(problem, "up to three numbers"), "%q: %s", bad, problem)
	}
}

@(test)
test_the_resource_script_holds_the_icon_the_version_and_the_manifest :: proc(t: ^testing.T) {
	info := Windows_App_Info{name = `Wild "Vex"`, id = "org.example.wildvex", executable = "wildvex.exe", publisher = "Ada", numbers = {1, 2, 3, 4}, icon = "C:/a b/icons/windows/wildvex.ico", manifest = "C:/w/app.manifest"}
	rc := windows_rc(info)
	testing.expect(t, strings.has_prefix(rc, "#pragma code_page(65001)\n"), rc)
	testing.expect(t, strings.contains(rc, "1 ICON \"C:/a b/icons/windows/wildvex.ico\"\n"), rc)
	testing.expect(t, strings.contains(rc, "1 24 \"C:/w/app.manifest\"\n"), rc)
	testing.expect(t, strings.contains(rc, "FILEVERSION 1,2,3,4\nPRODUCTVERSION 1,2,3,4\n"), rc)
	testing.expect(t, strings.contains(rc, `VALUE "ProductName", "Wild ""Vex"""`), rc)
	testing.expect(t, strings.contains(rc, `VALUE "FileDescription", "Wild ""Vex"""`), "the name stands for a missing description")
	testing.expect(t, strings.contains(rc, `VALUE "FileVersion", "1.2.3.4"`), rc)
	testing.expect(t, strings.contains(rc, `VALUE "CompanyName", "Ada"`), rc)
	testing.expect(t, strings.contains(rc, `VALUE "OriginalFilename", "wildvex.exe"`), rc)
	testing.expect(t, strings.contains(rc, `VALUE "Translation", 0x409, 1200`), rc)

	// with no publisher there is no CompanyName line, and a description is its own
	info.publisher = ""
	info.description = "Ships"
	rc = windows_rc(info)
	testing.expect(t, !strings.contains(rc, "CompanyName"), rc)
	testing.expect(t, strings.contains(rc, `VALUE "FileDescription", "Ships"`), rc)

	testing.expect(t, strings.contains(WINDOWS_MANIFEST, "PerMonitorV2"), "the program knows each screen's density")
}

@(test)
test_the_msix_manifest_names_the_package_and_asks_only_for_what_the_sketch_uses :: proc(t: ^testing.T) {
	info := Windows_App_Info{name = "Rain & Snow", id = "org.example.rain_snow", executable = "rain.exe", subject = "CN=Ada Lovelace, O=\"Engines\", C=GB", publisher = "Ada Lovelace", numbers = {1, 0, 2, 9}}
	xml := appx_manifest(info)
	testing.expect(t, strings.contains(xml, `<Identity Name="org.example.rain-snow" Publisher="CN=Ada Lovelace, O=&quot;Engines&quot;, C=GB" Version="1.0.2.9" ProcessorArchitecture="x64"/>`), xml)
	testing.expect(t, strings.contains(xml, "<DisplayName>Rain &amp; Snow</DisplayName>"), xml)
	testing.expect(t, strings.contains(xml, "<PublisherDisplayName>Ada Lovelace</PublisherDisplayName>"), xml)
	testing.expect(t, strings.contains(xml, `Executable="rain.exe" EntryPoint="Windows.FullTrustApplication"`), xml)
	testing.expect(t, strings.contains(xml, `Description="Rain &amp; Snow"`), "the name stands for a missing description")
	testing.expect(t, strings.contains(xml, `<rescap:Capability Name="runFullTrust"/>`), xml)
	testing.expect(t, strings.contains(xml, MSIX_MIN_WINDOWS), xml)
	testing.expect(t, !strings.contains(xml, "microphone") && !strings.contains(xml, "webcam"), xml)

	info.microphone = true
	info.camera = true
	info.publisher = ""
	xml = appx_manifest(info)
	testing.expect(t, strings.contains(xml, "<DeviceCapability Name=\"microphone\"/>\n    <DeviceCapability Name=\"webcam\"/>\n  </Capabilities>"), xml)
	testing.expect(t, strings.contains(xml, "<PublisherDisplayName>Rain &amp; Snow</PublisherDisplayName>"), "the name stands for a missing publisher")

	testing.expect_value(t, xml_text(`<a href='x'>&</a>`), "&lt;a href=&apos;x&apos;&gt;&amp;&lt;/a&gt;")
}

@(test)
test_an_msix_name_is_letters_digits_dots_and_dashes_of_3_to_50 :: proc(t: ^testing.T) {
	testing.expect_value(t, msix_name("org.example.wildvex"), "org.example.wildvex")
	testing.expect_value(t, msix_name("org.example.wild_vex"), "org.example.wild-vex")
	testing.expect_value(t, msix_name("a"), "a--")
	testing.expect_value(t, msix_name(""), "---")
	testing.expect_value(t, len(msix_name(strings.repeat("x", 80, context.temp_allocator))), 50)
	testing.expect_value(t, msix_name("org.é"), "org.--")
}

// A small PE file: a DOS header pointing at the PE header, an optional header of the given magic with its import directory, one
// section from 0x1000 in memory at 0x200 in the file, and the import table there naming `dlls`.
@(private = "file")
fake_pe :: proc(magic: u16, dlls: []string) -> []u8 {
	data := make([]u8, 0x400, context.temp_allocator)
	data[0], data[1] = 'M', 'Z'
	pe := 0x80
	endian.put_u32(data[0x3C:], .Little, u32(pe))
	copy(data[pe:], "PE\x00\x00")
	endian.put_u16(data[pe + 6:], .Little, 1) // one section
	optional_size := 240 if magic == 0x20B else 224
	endian.put_u16(data[pe + 20:], .Little, u16(optional_size))
	optional := pe + 24
	endian.put_u16(data[optional:], .Little, magic)
	directories := optional + (112 if magic == 0x20B else 96)
	endian.put_u32(data[directories + 8:], .Little, 0x1000) // the import table, at the section's start
	section := optional + optional_size
	endian.put_u32(data[section + 8:], .Little, 0x200)   // size in memory
	endian.put_u32(data[section + 12:], .Little, 0x1000) // where in memory
	endian.put_u32(data[section + 16:], .Little, 0x200)  // size in the file
	endian.put_u32(data[section + 20:], .Little, 0x200)  // where in the file
	// descriptors, then the names after them
	names_at := 0x200 + 20 * (len(dlls) + 1)
	for dll, i in dlls {
		descriptor := 0x200 + 20 * i
		endian.put_u32(data[descriptor:], .Little, 1) // an import lookup table, so the descriptor is not all zeros
		endian.put_u32(data[descriptor + 12:], .Little, u32(0x1000 + names_at - 0x200))
		copy(data[names_at:], dll)
		names_at += len(dll) + 1
	}
	return data
}

@(test)
test_the_libraries_a_program_asks_for_are_read_from_its_import_table :: proc(t: ^testing.T) {
	names, ok := pe_imports(fake_pe(0x20B, {"KERNEL32.dll", "SDL3.dll", "SDL3_ttf.dll"}))
	testing.expect(t, ok)
	testing.expect_value(t, len(names), 3)
	if len(names) == 3 {
		testing.expect_value(t, names[0], "KERNEL32.dll")
		testing.expect_value(t, names[2], "SDL3_ttf.dll")
	}
	// a 32-bit program keeps its directories elsewhere
	names, ok = pe_imports(fake_pe(0x10B, {"USER32.dll"}))
	testing.expect(t, ok)
	testing.expect_value(t, len(names), 1)
	// a program that asks for nothing
	names, ok = pe_imports(fake_pe(0x20B, {}))
	testing.expect(t, ok)
	testing.expect_value(t, len(names), 0)
	none := fake_pe(0x20B, {"A.dll"})
	endian.put_u32(none[0x80 + 24 + 112 + 8:], .Little, 0)
	names, ok = pe_imports(none)
	testing.expect(t, ok && len(names) == 0, "no import table at all")

	// what is not a PE file, or runs off its end
	_, ok = pe_imports(nil)
	testing.expect(t, !ok)
	_, ok = pe_imports(transmute([]u8)string("#!/bin/sh\necho this is not a program at all, and it is long enough to have a header\n"))
	testing.expect(t, !ok)
	bad_magic := fake_pe(0x20B, {"A.dll"})
	endian.put_u16(bad_magic[0x80 + 24:], .Little, 0x107)
	_, ok = pe_imports(bad_magic)
	testing.expect(t, !ok, "a ROM image")
	no_pe := fake_pe(0x20B, {"A.dll"})
	no_pe[0x80] = 'N'
	_, ok = pe_imports(no_pe)
	testing.expect(t, !ok, "no PE signature")
	far := fake_pe(0x20B, {"A.dll"})
	endian.put_u32(far[0x3C:], .Little, 0xFFFF)
	_, ok = pe_imports(far)
	testing.expect(t, !ok, "a PE header past the end")
	outside := fake_pe(0x20B, {"A.dll"})
	endian.put_u32(outside[0x80 + 24 + 112 + 8:], .Little, 0x9000)
	_, ok = pe_imports(outside)
	testing.expect(t, !ok, "an import table in no section")
	cut := fake_pe(0x20B, {"A.dll"})
	_, ok = pe_imports(cut[:0x200 + 10])
	testing.expect(t, !ok, "a table cut short")
	unended := fake_pe(0x20B, {"A.dll"})
	for i in 0x200 + 40 ..< len(unended) {
		unended[i] = 'x'
	}
	_, ok = pe_imports(unended)
	testing.expect(t, !ok, "a name with no end")
}

@(test)
test_a_dll_is_windows_own_by_its_api_set_or_its_place_in_system32 :: proc(t: ^testing.T) {
	system := map[string]bool{"kernel32.dll" = true, "d3dcompiler_47.dll" = true}
	defer delete(system)
	testing.expect(t, windows_system_dll("KERNEL32.dll", system))
	testing.expect(t, windows_system_dll("D3DCOMPILER_47.dll", system))
	testing.expect(t, windows_system_dll("api-ms-win-core-synch-l1-2-0.dll", system))
	testing.expect(t, windows_system_dll("ext-ms-win-ntuser-window-l1-1-0.dll", system))
	testing.expect(t, !windows_system_dll("SDL3.dll", system))
}

@(test)
test_code_signing_certificates_are_read_and_one_is_picked :: proc(t: ^testing.T) {
	listing := "0123456789ABCDEF0123456789ABCDEF01234567|CN=Ada Lovelace, O=Engines, C=GB\r\nnot a line\r\nshort|CN=x\r\nfedcba9876543210fedcba9876543210fedcba98|CN=Rocinante Test\r\n|CN=empty\r\n"
	certificates := parse_windows_certificates(listing)
	testing.expect_value(t, len(certificates), 2)
	if len(certificates) != 2 {
		return
	}
	testing.expect_value(t, certificates[1].thumbprint, "FEDCBA9876543210FEDCBA9876543210FEDCBA98")
	testing.expect_value(t, certificates[0].subject, "CN=Ada Lovelace, O=Engines, C=GB")

	// none asked for: the one there is, none when there are none, and a question when there are several
	picked, found, problem := pick_windows_certificate(certificates[:1], "")
	testing.expect(t, found && problem == "" && picked.subject == certificates[0].subject)
	_, found, problem = pick_windows_certificate(nil, "")
	testing.expect(t, !found && problem == "", "no certificate: the app is not signed, and that is no error")
	_, found, problem = pick_windows_certificate(certificates, "")
	testing.expect(t, !found && strings.contains(problem, "2 code-signing certificates"), problem)

	// by thumbprint, spaces and case aside, or by a part of the name that is one certificate's
	picked, found, _ = pick_windows_certificate(certificates, "fedcba98 76543210fedcba9876543210fedcba98")
	testing.expect(t, found && picked.subject == "CN=Rocinante Test")
	picked, found, _ = pick_windows_certificate(certificates, "ada")
	testing.expect(t, found && picked.thumbprint == certificates[0].thumbprint)
	_, found, problem = pick_windows_certificate(certificates, "1111111111111111111111111111111111111111")
	testing.expect(t, !found && strings.contains(problem, "thumbprint"), problem)
	_, found, problem = pick_windows_certificate(certificates, "Babbage")
	testing.expect(t, !found && strings.contains(problem, "`Babbage`"), problem)
	_, found, problem = pick_windows_certificate(certificates, "CN=")
	testing.expect(t, !found && strings.contains(problem, "2 code-signing certificates"), problem)

	testing.expect_value(t, subject_common_name("CN=Ada Lovelace, O=Engines"), "Ada Lovelace")
	testing.expect_value(t, subject_common_name(`O=Engines, CN="Ada, Countess", C=GB`), "Ada, Countess")
	testing.expect_value(t, subject_common_name(`CN="unclosed`), "unclosed")
	testing.expect_value(t, subject_common_name("CN=Last"), "Last")
	testing.expect_value(t, subject_common_name("no equals here"), "no equals here")
	testing.expect_value(t, subject_common_name("O=Engines"), "O=Engines")
}

@(test)
test_the_newest_windows_sdk_folder_is_found_number_by_number :: proc(t: ^testing.T) {
	testing.expect_value(t, newest_sdk_folder({"10.0.19041.0", "10.0.26100.0", "10.0.22621.0", "x64", "arm64"}), "10.0.26100.0")
	testing.expect_value(t, newest_sdk_folder({"10.0.9.0", "10.0.10.0"}), "10.0.10.0")
	testing.expect_value(t, newest_sdk_folder({"x64", "10.0.a.0"}), "")
	testing.expect_value(t, newest_sdk_folder({}), "")
}

@(test)
test_smartscreen_is_explained_signed_or_not :: proc(t: ^testing.T) {
	testing.expect(t, strings.contains(smartscreen_note(false), "Run anyway"))
	testing.expect(t, strings.contains(smartscreen_note(true), "signed"))
}

@(test)
test_paths_are_written_with_slashes_or_backslashes :: proc(t: ^testing.T) {
	testing.expect_value(t, slashed(`C:\Users\a b\x`), "C:/Users/a b/x")
	testing.expect_value(t, windows_path("C:/Users/a b/x"), `C:\Users\a b\x`)
}
