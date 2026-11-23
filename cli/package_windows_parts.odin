// SPDX-License-Identifier: 0BSD
//
// The pieces of a Windows app that are only text or bytes: which formats were asked for, the names of the files, the four numbers
// of a Windows version, the resource script that puts the icon, the version and the manifest into the program, the manifest of an
// MSIX package, the libraries a program asks for (read from its import table), and the code-signing certificates PowerShell lists.
// They are kept apart from the commands that run tools so each can be tested alone, on any system. (The file is `_parts`, not
// `_windows`, because Odin reads a `_windows` suffix as "only on Windows".)
package main

import "core:encoding/endian"
import "core:fmt"
import "core:strconv"
import "core:strings"

// What `roci package windows` can make.
Windows_Format :: enum {
	Zip,
	Msix,
}

WINDOWS_FORMATS :: [?]Windows_Format{.Zip, .Msix}

// The formats a `--format` (or the `formats` of the `[windows]` part of `sketch.toml`) names: words separated by commas, `all` for
// both. `bad` is the first word that is no format. Each is once, in the order they are made. An empty text is the zip alone.
parse_windows_formats :: proc(text: string, allocator := context.temp_allocator) -> (formats: []Windows_Format, bad: string) {
	wanted: [Windows_Format]bool
	given := false
	for piece in strings.split(text, ",", context.temp_allocator) {
		word := strings.to_lower(strings.trim_space(piece), context.temp_allocator)
		if word == "" {
			continue
		}
		given = true
		switch word {
		case "all":
			for f in WINDOWS_FORMATS {
				wanted[f] = true
			}
		case "zip":          wanted[.Zip] = true
		case "msix", "appx": wanted[.Msix] = true
		case:
			return nil, strings.trim_space(piece)
		}
	}
	if !given {
		wanted[.Zip] = true
	}
	made := make([dynamic]Windows_Format, allocator)
	for f in WINDOWS_FORMATS {
		if wanted[f] {
			append(&made, f)
		}
	}
	return made[:], ""
}

// The names of what a Windows package is made of.
Windows_Names :: struct {
	folder:     string, // the app's folder, which the zip holds: `Wildvex`
	executable: string, // `wildvex.exe`
	zip:        string, // `wildvex-1.0.1-windows-x64.zip`
	msix:       string, // `wildvex-1.0.1-windows-x64.msix`
}

windows_names :: proc(name, slug, version: string) -> Windows_Names {
	return Windows_Names{
		folder     = windows_file_name(name),
		executable = strings.concatenate({slug, ".exe"}, context.temp_allocator),
		zip        = fmt.tprintf("%s-%s-windows-x64.zip", slug, version),
		msix       = fmt.tprintf("%s-%s-windows-x64.msix", slug, version),
	}
}

// A name as Windows takes it for a file or folder: the characters it refuses (`< > : " / \ | ? *` and the control ones) become
// dashes, and dots and spaces at the end go, since Windows drops them. A name of nothing left is `app`.
windows_file_name :: proc(name: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for r in name {
		switch r {
		case '<', '>', ':', '"', '/', '\\', '|', '?', '*':
			strings.write_rune(&b, '-')
		case:
			if r < ' ' {
				strings.write_rune(&b, '-')
			} else {
				strings.write_rune(&b, r)
			}
		}
	}
	text := strings.trim_right(strings.to_string(b), ". ")
	text = strings.trim_left(text, " ")
	return text if text != "" else "app"
}

// The four numbers of a Windows version: the version people see, up to three numbers (missing ones are 0), then the build. Each
// is at most 65,535, which is all a Windows version can hold; `problem` says, in plain words, which is too large. `date` must be
// made a day's version before it comes here.
windows_version :: proc(version: string, build: int) -> (numbers: [4]int, problem: string) {
	parts := strings.split(version, ".", context.temp_allocator)
	if len(parts) == 0 || len(parts) > 3 {
		return {}, fmt.tprintf("The version `%s` should be up to three numbers separated by dots, such as 1.0.1.", version)
	}
	for part, i in parts {
		n, ok := strconv.parse_int(part, 10)
		if !ok || n < 0 || len(part) == 0 || part[0] == '+' || part[0] == '-' {
			return {}, fmt.tprintf("The version `%s` should be up to three numbers separated by dots, such as 1.0.1.", version)
		}
		if n > 65535 {
			return {}, fmt.tprintf("The version `%s` has %d in it, and a Windows version holds numbers up to 65535 only.", version, n)
		}
		numbers[i] = n
	}
	if build < 0 || build > 65535 {
		return {}, fmt.tprintf("The build number is %d, and a Windows version holds numbers up to 65535 only. Set `build` in sketch.toml to a smaller number.", build)
	}
	numbers[3] = build
	return numbers, ""
}

// What the program's version resource and the MSIX manifest say about the app.
Windows_App_Info :: struct {
	name:        string,   // what people call it
	id:          string,   // org.example.wildvex
	executable:  string,   // wildvex.exe
	description: string,   // one line about it; the name when empty
	publisher:   string,   // who made it, as people read it
	subject:     string,   // the certificate's subject, CN=..., which an MSIX must name exactly as its publisher
	numbers:     [4]int,   // the version and the build
	icon:        string,   // the .ico, with slashes
	manifest:    string,   // the manifest file, with slashes
	microphone:  bool,     // the sketch listens: an MSIX asks for the microphone
	camera:      bool,     // the sketch looks: an MSIX asks for the camera
}

// A text as a string of a resource script: in quotes, with a quote written twice.
rc_text :: proc(text: string) -> string {
	escaped, _ := strings.replace_all(text, `"`, `""`, context.temp_allocator)
	return strings.concatenate({`"`, escaped, `"`}, context.temp_allocator)
}

// The resource script Odin's `-resource:` gives `rc`: the icon Explorer and the taskbar show, the version Explorer's Details shows,
// and the manifest. It is UTF-8, which the first line tells `rc`, so a name with accents stays as it is written.
windows_rc :: proc(info: Windows_App_Info) -> string {
	b := strings.builder_make(context.temp_allocator)
	n := info.numbers
	dotted := fmt.tprintf("%d.%d.%d.%d", n[0], n[1], n[2], n[3])
	description := info.description if info.description != "" else info.name
	fmt.sbprintf(&b, "#pragma code_page(65001)\n")
	fmt.sbprintf(&b, "1 ICON %s\n", rc_text(info.icon))
	fmt.sbprintf(&b, "1 24 %s\n\n", rc_text(info.manifest)) // 24 is RT_MANIFEST, 1 the program's own
	fmt.sbprintf(&b, "1 VERSIONINFO\nFILEVERSION %d,%d,%d,%d\nPRODUCTVERSION %d,%d,%d,%d\nFILEFLAGSMASK 0x3fL\nFILEFLAGS 0x0L\nFILEOS 0x40004L\nFILETYPE 0x1L\nFILESUBTYPE 0x0L\n", n[0], n[1], n[2], n[3], n[0], n[1], n[2], n[3])
	fmt.sbprintf(&b, "BEGIN\n  BLOCK \"StringFileInfo\"\n  BEGIN\n    BLOCK \"040904B0\"\n    BEGIN\n")
	pairs := [?][2]string{
		{"CompanyName", info.publisher},
		{"FileDescription", description},
		{"FileVersion", dotted},
		{"InternalName", info.id},
		{"OriginalFilename", info.executable},
		{"ProductName", info.name},
		{"ProductVersion", dotted},
	}
	for pair in pairs {
		if pair[1] != "" {
			fmt.sbprintf(&b, "      VALUE %s, %s\n", rc_text(pair[0]), rc_text(pair[1]))
		}
	}
	fmt.sbprintf(&b, "    END\n  END\n  BLOCK \"VarFileInfo\"\n  BEGIN\n    VALUE \"Translation\", 0x409, 1200\n  END\nEND\n")
	return strings.to_string(b)
}

// The program's manifest: Windows 10 and 11, the size of each screen's pixels known (SDL draws at the screen's density), and
// the controls of Windows' own dialogs in their current look.
WINDOWS_MANIFEST :: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
    </windowsSettings>
  </application>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
    </dependentAssembly>
  </dependency>
</assembly>
`

// A text in XML: the five characters XML gives a meaning written as entities.
xml_text :: proc(text: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for r in text {
		switch r {
		case '&':  strings.write_string(&b, "&amp;")
		case '<':  strings.write_string(&b, "&lt;")
		case '>':  strings.write_string(&b, "&gt;")
		case '"':  strings.write_string(&b, "&quot;")
		case '\'': strings.write_string(&b, "&apos;")
		case:      strings.write_rune(&b, r)
		}
	}
	return strings.to_string(b)
}

// The package name an MSIX takes from the app's id: letters, digits, dots and dashes, 3 to 50 of them, so anything else becomes a
// dash and a long id is cut.
msix_name :: proc(id: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for c in transmute([]u8)id {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '-' {
			strings.write_byte(&b, c)
		} else {
			strings.write_byte(&b, '-')
		}
	}
	name := strings.to_string(b)
	if len(name) > 50 {
		name = name[:50]
	}
	for len(name) < 3 {
		name = strings.concatenate({name, "-"}, context.temp_allocator)
	}
	return name
}

// The oldest Windows an MSIX installs on: Windows 10 1809, the first that installs one by opening it.
MSIX_MIN_WINDOWS :: "10.0.17763.0"

// The `AppxManifest.xml` of an MSIX: the package (its name from the id, the publisher the certificate's subject, the version), the
// app in it, started as a full program (`runFullTrust`), its logos in `logos`, and the microphone and the camera only when the
// sketch uses them.
appx_manifest :: proc(info: Windows_App_Info) -> string {
	b := strings.builder_make(context.temp_allocator)
	n := info.numbers
	description := info.description if info.description != "" else info.name
	publisher_name := info.publisher if info.publisher != "" else info.name
	fmt.sbprintf(&b, `<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
         IgnorableNamespaces="uap rescap">
  <Identity Name="%s" Publisher="%s" Version="%d.%d.%d.%d" ProcessorArchitecture="x64"/>
  <Properties>
    <DisplayName>%s</DisplayName>
    <PublisherDisplayName>%s</PublisherDisplayName>
    <Logo>logos\StoreLogo.png</Logo>
  </Properties>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="%s" MaxVersionTested="10.0.26100.0"/>
  </Dependencies>
  <Resources>
    <Resource Language="en-us"/>
  </Resources>
  <Applications>
    <Application Id="App" Executable="%s" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="%s" Description="%s" BackgroundColor="transparent" Square150x150Logo="logos\Square150x150Logo.png" Square44x44Logo="logos\Square44x44Logo.png"/>
    </Application>
  </Applications>
  <Capabilities>
    <rescap:Capability Name="runFullTrust"/>
`, xml_text(msix_name(info.id)), xml_text(info.subject), n[0], n[1], n[2], n[3], xml_text(info.name), xml_text(publisher_name), MSIX_MIN_WINDOWS, xml_text(info.executable), xml_text(info.name), xml_text(description))
	if info.microphone {
		fmt.sbprintf(&b, "    <DeviceCapability Name=\"microphone\"/>\n")
	}
	if info.camera {
		fmt.sbprintf(&b, "    <DeviceCapability Name=\"webcam\"/>\n")
	}
	fmt.sbprintf(&b, "  </Capabilities>\n</Package>\n")
	return strings.to_string(b)
}

// The libraries a Windows program or library asks for, read from its import table (the PE format: the DOS header points at the
// PE header, whose optional header's second data directory is the import table, an array of 20-byte descriptors ending in one of
// zeros, each naming a DLL). False when the bytes are not a 64-bit or 32-bit PE file, or the table runs off the end.
pe_imports :: proc(data: []u8, allocator := context.temp_allocator) -> (names: []string, ok: bool) {
	u16_at :: proc(data: []u8, at: int) -> (u16, bool) {
		if at < 0 || at + 2 > len(data) {
			return 0, false
		}
		return endian.get_u16(data[at:at + 2], .Little)
	}
	u32_at :: proc(data: []u8, at: int) -> (u32, bool) {
		if at < 0 || at + 4 > len(data) {
			return 0, false
		}
		return endian.get_u32(data[at:at + 4], .Little)
	}
	if len(data) < 64 || data[0] != 'M' || data[1] != 'Z' {
		return nil, false
	}
	pe := int(u32_at(data, 0x3C) or_return)
	if pe + 24 > len(data) || string(data[pe:pe + 4]) != "PE\x00\x00" {
		return nil, false
	}
	sections := int(u16_at(data, pe + 6) or_return)
	optional_size := int(u16_at(data, pe + 20) or_return)
	optional := pe + 24
	magic := u16_at(data, optional) or_return
	directories: int
	switch magic {
	case 0x20B: directories = optional + 112 // PE32+, 64-bit
	case 0x10B: directories = optional + 96  // PE32, 32-bit
	case:       return nil, false
	}
	import_rva := int(u32_at(data, directories + 8) or_return)
	found := make([dynamic]string, allocator)
	if import_rva == 0 {
		return found[:], true
	}
	// a place in memory (RVA) as a place in the file, through the section that holds it
	table := optional + optional_size
	to_file :: proc(data: []u8, table, sections, rva: int) -> (int, bool) {
		for i in 0 ..< sections {
			at := table + i * 40
			if at + 40 > len(data) {
				return 0, false
			}
			virtual_size, _ := endian.get_u32(data[at + 8:at + 12], .Little)
			virtual_at, _ := endian.get_u32(data[at + 12:at + 16], .Little)
			raw_size, _ := endian.get_u32(data[at + 16:at + 20], .Little)
			raw_at, _ := endian.get_u32(data[at + 20:at + 24], .Little)
			size := max(int(virtual_size), int(raw_size))
			if rva >= int(virtual_at) && rva < int(virtual_at) + size {
				return rva - int(virtual_at) + int(raw_at), true
			}
		}
		return 0, false
	}
	at := to_file(data, table, sections, import_rva) or_return
	for {
		if at + 20 > len(data) {
			return nil, false
		}
		name_rva := int(u32_at(data, at + 12) or_return)
		first := u32_at(data, at) or_return
		thunk := u32_at(data, at + 16) or_return
		if name_rva == 0 && first == 0 && thunk == 0 {
			break
		}
		name_at := to_file(data, table, sections, name_rva) or_return
		end := name_at
		for end < len(data) && data[end] != 0 {
			end += 1
		}
		if end >= len(data) {
			return nil, false
		}
		append(&found, strings.clone(string(data[name_at:end]), allocator))
		at += 20
	}
	return found[:], true
}

// Whether a DLL is part of Windows, so an app never carries it: the API sets (`api-ms-win-…`, `ext-ms-…`), and the ones in
// `system_names` (what the Windows folder's System32 holds, in lower case).
windows_system_dll :: proc(name: string, system_names: map[string]bool) -> bool {
	lower := strings.to_lower(name, context.temp_allocator)
	if strings.has_prefix(lower, "api-ms-win-") || strings.has_prefix(lower, "ext-ms-") {
		return true
	}
	return lower in system_names
}

// A code-signing certificate of the user's store, as `windows_certificates_script` lists it.
Windows_Certificate :: struct {
	thumbprint: string, // forty hexadecimal digits
	subject:    string, // CN=Your Name, O=..., C=...
}

// The PowerShell that lists the current user's code-signing certificates that have their private key and have not expired, one a
// line: the thumbprint, a bar, the subject.
WINDOWS_CERTIFICATES_SCRIPT :: `Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } | ForEach-Object { $_.Thumbprint + '|' + $_.Subject }`

// The certificates in what `WINDOWS_CERTIFICATES_SCRIPT` printed; a line that is not a thumbprint and a subject is passed over.
parse_windows_certificates :: proc(text: string, allocator := context.temp_allocator) -> []Windows_Certificate {
	found := make([dynamic]Windows_Certificate, allocator)
	for line in strings.split_lines(text, context.temp_allocator) {
		trimmed := strings.trim_space(line)
		bar := strings.index_byte(trimmed, '|')
		if bar < 0 {
			continue
		}
		thumbprint := strings.trim_space(trimmed[:bar])
		subject := strings.trim_space(trimmed[bar + 1:])
		if !is_thumbprint(thumbprint) || subject == "" {
			continue
		}
		append(&found, Windows_Certificate{thumbprint = strings.to_upper(thumbprint, allocator), subject = strings.clone(subject, allocator)})
	}
	return found[:]
}

is_thumbprint :: proc(text: string) -> bool {
	if len(text) != 40 {
		return false
	}
	for c in transmute([]u8)text {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
			return false
		}
	}
	return true
}

// The certificate `wanted` names among `certificates`: its thumbprint (spaces and case do not matter), or a part of its subject
// that names one certificate only. Empty `wanted` takes the one certificate there is. `problem` says in plain words why none was
// taken; with nothing wanted and none there, there is no problem and no certificate: the app is not signed.
pick_windows_certificate :: proc(certificates: []Windows_Certificate, wanted: string) -> (picked: Windows_Certificate, found: bool, problem: string) {
	if wanted == "" {
		switch len(certificates) {
		case 0:
			return {}, false, ""
		case 1:
			return certificates[0], true, ""
		}
		return {}, false, fmt.tprintf("There are %d code-signing certificates in your store, and I do not know which to sign with. Name one with --sign (its thumbprint, or a part of its name).", len(certificates))
	}
	squeezed, _ := strings.replace_all(wanted, " ", "", context.temp_allocator)
	if is_thumbprint(squeezed) {
		for c in certificates {
			if strings.equal_fold(c.thumbprint, squeezed) {
				return c, true, ""
			}
		}
		return {}, false, fmt.tprintf("No code-signing certificate in your store has the thumbprint %s (it needs its private key, and must not have expired).", wanted)
	}
	matches := 0
	for c in certificates {
		if strings.contains(strings.to_lower(c.subject, context.temp_allocator), strings.to_lower(wanted, context.temp_allocator)) {
			picked = c
			matches += 1
		}
	}
	switch matches {
	case 0:
		return {}, false, fmt.tprintf("No code-signing certificate in your store is named `%s` (it needs its private key, and must not have expired).", wanted)
	case 1:
		return picked, true, ""
	}
	return {}, false, fmt.tprintf("%d code-signing certificates in your store are named `%s`. Name one by its thumbprint.", matches, wanted)
}

// The common name of a certificate's subject (`Your Name` of `CN=Your Name, O=...`), for the publisher people read; the whole
// subject when it has none.
subject_common_name :: proc(subject: string) -> string {
	// the parts are separated by commas, and a value in quotes may hold commas of its own
	rest := subject
	for len(rest) > 0 {
		rest = strings.trim_left_space(rest)
		equals := strings.index_byte(rest, '=')
		if equals < 0 {
			break
		}
		key := strings.trim_space(rest[:equals])
		rest = rest[equals + 1:]
		value: string
		if strings.has_prefix(rest, `"`) {
			close := strings.index_byte(rest[1:], '"')
			if close < 0 {
				value, rest = rest[1:], ""
			} else {
				value, rest = rest[1:close + 1], rest[close + 2:]
			}
		} else {
			comma := strings.index_byte(rest, ',')
			if comma < 0 {
				value, rest = strings.trim_space(rest), ""
			} else {
				value, rest = strings.trim_space(rest[:comma]), rest[comma:]
			}
		}
		if key == "CN" {
			return value
		}
		comma := strings.index_byte(rest, ',')
		rest = rest[comma + 1:] if comma >= 0 else ""
	}
	return subject
}

// The newest folder of the Windows SDK's tools in a listing of `Windows Kits\10\bin`: the highest `10.0.N.0` among `names`,
// compared number by number. Empty when there is none.
newest_sdk_folder :: proc(names: []string) -> string {
	best := ""
	best_numbers: [4]int
	for name in names {
		parts := strings.split(name, ".", context.temp_allocator)
		if len(parts) != 4 {
			continue
		}
		numbers: [4]int
		whole := true
		for part, i in parts {
			n, ok := strconv.parse_int(part, 10)
			if !ok || n < 0 {
				whole = false
				break
			}
			numbers[i] = n
		}
		if !whole {
			continue
		}
		newer := best == ""
		for i in 0 ..< 4 {
			if best == "" || numbers[i] == best_numbers[i] {
				continue
			}
			newer = numbers[i] > best_numbers[i]
			break
		}
		if newer {
			best, best_numbers = name, numbers
		}
	}
	return best
}

// What SmartScreen does with the app, said after it is made.
smartscreen_note :: proc(signed: bool) -> string {
	if signed {
		return "The app is signed. SmartScreen may still warn the first people who run it, until the certificate has a reputation; a certificate kept in an EV or cloud signing service has one sooner."
	}
	return "The app is not signed, so Windows' SmartScreen says it is from an unknown publisher: people choose More info, then Run anyway. To sign it, put a code-signing certificate in your certificate store and package again, or name one with --sign."
}
