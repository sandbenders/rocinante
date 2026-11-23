// SPDX-License-Identifier: 0BSD
//
// The installer of a packaged sketch on Windows, `name-version-windows-x64-setup.exe`: this program with the app's files appended
// as an archive (`roci/install`). Run, it asks once (unless `/S`) and puts the app in Program Files for everyone, with a Start menu
// shortcut and an entry in Settings, Apps; `/D=<folder>` chooses another folder. The app carries the same program, without the
// archive, as `uninstall.exe`, which Settings, Apps runs with `/uninstall`: it copies itself out of the app's folder, starts the
// copy with `/remove <folder> /wait <its process>` and ends, and the copy takes the folder, the shortcut and the entry away, then
// has Windows delete it at the next start. What the app keeps for each person (`%APPDATA%\<id>`) is left alone.
//
// Its manifest asks for an administrator, so Windows asks before it runs. Every question and message is a Windows message box,
// which screen readers read. The exit code is 0 when it did what it was asked, 1 when it was told no, 2 when it failed and 3 when
// the app was open.
package setup

import "../../install"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import win "core:sys/windows"

EXIT_DONE      :: 0
EXIT_CANCELLED :: 1
EXIT_FAILED    :: 2
EXIT_IN_USE    :: 3

main :: proc() {
	command := install.parse_command(os.args[1:])
	if command.bad != "" {
		say(fmt.tprintf("I don't know `%s`. The installer takes /S (ask nothing) and /D=<folder> (where to install).", command.bad), "Setup", .Error, command.silent)
		os.exit(EXIT_FAILED)
	}
	switch command.mode {
	case .Install:   os.exit(run_install(command))
	case .Uninstall: os.exit(run_uninstall(command))
	case .Remove:    os.exit(run_remove(command))
	}
}

Tone :: enum {
	Info,
	Error,
}

// Says something in a message box, unless the installer was told to be silent.
say :: proc(text, title: string, tone: Tone, silent: bool) {
	if silent {
		return
	}
	icon: win.UINT = win.MB_ICONINFORMATION if tone == .Info else win.MB_ICONERROR
	_ = win.MessageBoxW(nil, win.utf8_to_wstring(text), win.utf8_to_wstring(title), win.MB_OK | icon)
}

// Asks a question with OK and Cancel; a silent installer takes OK.
ask :: proc(text, title: string, silent: bool) -> bool {
	if silent {
		return true
	}
	return win.MessageBoxW(nil, win.utf8_to_wstring(text), win.utf8_to_wstring(title), win.MB_OKCANCEL | win.MB_ICONQUESTION) == win.IDOK
}

// The whole path of this program.
own_path :: proc() -> string {
	buffer: [win.MAX_PATH_WIDE]u16
	n := win.GetModuleFileNameW(nil, raw_data(buffer[:]), win.DWORD(len(buffer)))
	text, _ := win.wstring_to_utf8(cast(win.wstring)raw_data(buffer[:]), int(n))
	return text
}

// A folder Windows knows, such as Program Files.
known_folder :: proc(folder_id: win.GUID) -> (path: string, ok: bool) {
	id := folder_id
	p: win.LPWSTR
	if win.SHGetKnownFolderPath(&id, 0, nil, &p) != 0 {
		return "", false
	}
	defer win.CoTaskMemFree(p)
	text, err := win.wstring_to_utf8(cast(win.wstring)p, -1)
	return text, err == nil
}

run_install :: proc(command: install.Command) -> int {
	program, read_err := os.read_entire_file(own_path(), context.allocator)
	if read_err != nil {
		say("I cannot read the installer itself.", "Setup", .Error, command.silent)
		return EXIT_FAILED
	}
	archive, found := install.find_archive(program)
	entries: []install.Entry
	read_ok := false
	if found {
		entries, read_ok = install.read_archive(archive)
	}
	if !read_ok {
		say("The installer is damaged: the app it carries cannot be read. Download it again.", "Setup", .Error, command.silent)
		return EXIT_FAILED
	}
	app: install.App
	described := false
	for e in entries {
		if e.path == install.SETUP_INI {
			if data, good := install.entry_bytes(e); good {
				app, described = install.read_ini(string(data))
			}
		}
	}
	if !described {
		say("The installer is damaged: it does not say which app it carries. Download it again.", "Setup", .Error, command.silent)
		return EXIT_FAILED
	}
	title := fmt.tprintf("%s Setup", app.name)

	folder := command.folder
	if folder == "" {
		program_files, have := known_folder(win.FOLDERID_ProgramFiles)
		if !have {
			say("I cannot find the Program Files folder.", title, .Error, command.silent)
			return EXIT_FAILED
		}
		folder = strings.concatenate({program_files, `\`, app.folder})
	}
	folder = strings.trim_right(folder, `\/`)
	previous_version, previous_folder := installed(app.id)
	if !ask(install.ask_install(app, folder, previous_version), title, command.silent) {
		return EXIT_CANCELLED
	}

	// the version before goes first, wherever it was; a folder that is not an app's is never emptied
	for old, i in ([]string{previous_folder, folder}) {
		if old == "" || !os.exists(old) || (i == 1 && strings.equal_fold(old, previous_folder)) {
			continue
		}
		if !os.exists(strings.concatenate({old, `\`, install.SETUP_INI})) {
			if entries_in(old) > 0 {
				say(fmt.tprintf("The folder %s has other files in it. Choose an empty folder.", old), title, .Error, command.silent)
				return EXIT_FAILED
			}
			continue
		}
		if !remove_app_files(old) {
			say(install.said_in_use(app), title, .Error, command.silent)
			return EXIT_IN_USE
		}
	}

	for e in entries {
		target := strings.concatenate({folder, `\`, windows_slashes(e.path)})
		data, good := install.entry_bytes(e)
		if !good {
			_ = os.remove_all(folder)
			say(fmt.tprintf("The installer is damaged: %s does not match what was packed. Download it again.", e.path), title, .Error, command.silent)
			return EXIT_FAILED
		}
		if os.make_directory_all(filepath.dir(target)) != nil && !os.is_directory(filepath.dir(target)) || os.write_entire_file(target, data) != nil {
			_ = os.remove_all(folder)
			say(fmt.tprintf("I cannot write %s.", target), title, .Error, command.silent)
			return EXIT_FAILED
		}
	}
	if !make_shortcut(app, folder) {
		say("The app is installed, but I could not add it to the Start menu.", title, .Error, command.silent)
	}
	if !write_entry(app, folder) {
		say("The app is installed, but I could not add it to Settings, Apps, which removes it.", title, .Error, command.silent)
	}
	say(install.said_installed(app), title, .Info, command.silent)
	return EXIT_DONE
}

windows_slashes :: proc(path: string) -> string {
	result, _ := strings.replace_all(path, "/", `\`)
	return result
}

entries_in :: proc(folder: string) -> int {
	list, err := os.read_all_directory_by_path(folder, context.temp_allocator)
	return 0 if err != nil else len(list)
}

// Takes away an installed app's folder. False when a file of it is open (the app is running), and then nothing is taken: every
// file is first opened for writing with no sharing, which Windows refuses for a running program or a library it has loaded
// (renaming is no test, since Windows lets a running program be renamed).
remove_app_files :: proc(folder: string) -> bool {
	if in_use(folder) {
		return false
	}
	_ = os.remove_all(folder)
	return !os.exists(folder)
}

// Whether a file in the folder, or in the folders in it, is open.
in_use :: proc(folder: string) -> bool {
	entries, err := os.read_all_directory_by_path(folder, context.temp_allocator)
	if err != nil {
		return false
	}
	for entry in entries {
		path := strings.concatenate({folder, `\`, entry.name})
		#partial switch entry.type {
		case .Directory:
			if in_use(path) {
				return true
			}
		case .Regular:
			handle := win.CreateFileW(win.utf8_to_wstring(path), win.GENERIC_WRITE, 0, nil, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, nil)
			if handle == win.INVALID_HANDLE_VALUE {
				if win.GetLastError() == win.ERROR_SHARING_VIOLATION {
					return true
				}
				continue
			}
			win.CloseHandle(handle)
		}
	}
	return false
}

// The version installed and its folder, from the app's entry in Settings, Apps; empty when there is none.
installed :: proc(id: string) -> (version, folder: string) {
	key := win.utf8_to_wstring(strings.concatenate({install.UNINSTALL_KEY, id}))
	read :: proc(key: win.wstring, name: string) -> string {
		buffer: [1024]u16
		size := win.DWORD(size_of(buffer))
		if win.RegGetValueW(win.HKEY_LOCAL_MACHINE, key, win.utf8_to_wstring(name), win.RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nil, raw_data(buffer[:]), &size) != 0 {
			return ""
		}
		text, _ := win.wstring_to_utf8(cast(win.wstring)raw_data(buffer[:]), -1)
		return text
	}
	return read(key, "DisplayVersion"), read(key, "InstallLocation")
}

RRF_SUBKEY_WOW6464KEY :: 0x00010000

// Writes the app's entry in Settings, Apps.
write_entry :: proc(app: install.App, folder: string) -> bool {
	key: win.HKEY
	path := win.utf8_to_wstring(strings.concatenate({install.UNINSTALL_KEY, app.id}))
	if win.RegCreateKeyExW(win.HKEY_LOCAL_MACHINE, path, 0, nil, 0, win.KEY_WRITE | win.KEY_WOW64_64KEY, nil, &key, nil) != 0 {
		return false
	}
	defer win.RegCloseKey(key)
	for v in install.uninstall_values(app, folder) {
		name := win.utf8_to_wstring(v.name)
		status: win.LSTATUS
		if v.is_number {
			number := win.DWORD(v.number)
			status = win.RegSetValueExW(key, name, 0, win.REG_DWORD, cast(^win.BYTE)&number, size_of(number))
		} else {
			wide := win.utf8_to_utf16(v.text)
			terminated := make([]u16, len(wide) + 1, context.temp_allocator)
			copy(terminated, wide)
			status = win.RegSetValueExW(key, name, 0, win.REG_SZ, cast(^win.BYTE)raw_data(terminated), win.DWORD(len(terminated) * 2))
		}
		if status != 0 {
			return false
		}
	}
	return true
}

foreign import advapi32 "system:Advapi32.lib"
@(default_calling_convention = "system")
foreign advapi32 {
	RegDeleteKeyExW :: proc(hKey: win.HKEY, lpSubKey: win.LPCWSTR, samDesired: win.REGSAM, Reserved: win.DWORD) -> win.LSTATUS ---
}

remove_entry :: proc(id: string) {
	path := win.utf8_to_wstring(strings.concatenate({install.UNINSTALL_KEY, id}))
	_ = RegDeleteKeyExW(win.HKEY_LOCAL_MACHINE, path, win.KEY_WOW64_64KEY, 0)
}

// ---- the Start menu shortcut, through the shell's ShellLink object ----

CLSID_ShellLink := win.GUID{0x00021401, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
IID_IShellLinkW := win.GUID{0x000214F9, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}
IID_IPersistFile := win.GUID{0x0000010B, 0x0000, 0x0000, {0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}}

IShellLinkW :: struct {
	vtable: ^IShellLinkW_VTable,
}

// In the order of shobjidl_core.h: IUnknown's three, then IShellLinkW's eighteen.
IShellLinkW_VTable :: struct {
	QueryInterface:      proc "system" (this: ^IShellLinkW, riid: ^win.GUID, out: ^rawptr) -> win.HRESULT,
	AddRef:              proc "system" (this: ^IShellLinkW) -> win.ULONG,
	Release:             proc "system" (this: ^IShellLinkW) -> win.ULONG,
	GetPath:             rawptr,
	GetIDList:           rawptr,
	SetIDList:           rawptr,
	GetDescription:      rawptr,
	SetDescription:      proc "system" (this: ^IShellLinkW, text: win.LPCWSTR) -> win.HRESULT,
	GetWorkingDirectory: rawptr,
	SetWorkingDirectory: proc "system" (this: ^IShellLinkW, dir: win.LPCWSTR) -> win.HRESULT,
	GetArguments:        rawptr,
	SetArguments:        rawptr,
	GetHotkey:           rawptr,
	SetHotkey:           rawptr,
	GetShowCmd:          rawptr,
	SetShowCmd:          rawptr,
	GetIconLocation:     rawptr,
	SetIconLocation:     rawptr,
	SetRelativePath:     rawptr,
	Resolve:             rawptr,
	SetPath:             proc "system" (this: ^IShellLinkW, file: win.LPCWSTR) -> win.HRESULT,
}

IPersistFile :: struct {
	vtable: ^IPersistFile_VTable,
}

// IUnknown's three, IPersist's GetClassID, then IPersistFile's five.
IPersistFile_VTable :: struct {
	QueryInterface: rawptr,
	AddRef:         rawptr,
	Release:        proc "system" (this: ^IPersistFile) -> win.ULONG,
	GetClassID:     rawptr,
	IsDirty:        rawptr,
	Load:           rawptr,
	Save:           proc "system" (this: ^IPersistFile, file: win.LPCWSTR, remember: win.BOOL) -> win.HRESULT,
	SaveCompleted:  rawptr,
	GetCurFile:     rawptr,
}

shortcut_path :: proc(app: install.App) -> (path: string, ok: bool) {
	programs, have := known_folder(win.FOLDERID_CommonPrograms)
	if !have {
		return "", false
	}
	return strings.concatenate({programs, `\`, app.folder, ".lnk"}), true
}

make_shortcut :: proc(app: install.App, folder: string) -> bool {
	path, have := shortcut_path(app)
	if !have {
		return false
	}
	_ = win.CoInitializeEx(nil, .APARTMENTTHREADED)
	defer win.CoUninitialize()
	link: ^IShellLinkW
	if win.CoCreateInstance(&CLSID_ShellLink, nil, win.CLSCTX_INPROC_SERVER, &IID_IShellLinkW, cast(^win.LPVOID)&link) != 0 || link == nil {
		return false
	}
	defer link.vtable.Release(link)
	_ = link.vtable.SetPath(link, win.utf8_to_wstring(strings.concatenate({folder, `\`, app.executable})))
	_ = link.vtable.SetWorkingDirectory(link, win.utf8_to_wstring(folder))
	_ = link.vtable.SetDescription(link, win.utf8_to_wstring(app.name))
	file: ^IPersistFile
	if link.vtable.QueryInterface(link, &IID_IPersistFile, cast(^rawptr)&file) != 0 || file == nil {
		return false
	}
	defer file.vtable.Release(file)
	return file.vtable.Save(file, win.utf8_to_wstring(path), true) == 0
}

// ---- removing ----

// The uninstaller in the app's folder: asks, copies itself out of the folder (a running program cannot be deleted), starts the
// copy and ends.
run_uninstall :: proc(command: install.Command) -> int {
	self := own_path()
	folder := filepath.dir(self)
	ini, read_err := os.read_entire_file(strings.concatenate({folder, `\`, install.SETUP_INI}), context.temp_allocator)
	app, ok := install.read_ini(string(ini))
	if read_err != nil || !ok {
		say(fmt.tprintf("%s does not hold an app made by rocinante, so I leave it alone.", folder), "Uninstall", .Error, command.silent)
		return EXIT_FAILED
	}
	title := fmt.tprintf("Uninstall %s", app.name)
	if !ask(install.ask_remove(app), title, command.silent) {
		return EXIT_CANCELLED
	}
	temp, have_temp := temp_folder()
	if !have_temp {
		say("I cannot find a folder for temporary files.", title, .Error, command.silent)
		return EXIT_FAILED
	}
	copy_path := fmt.tprintf(`%s\roci-uninstall-%d.exe`, temp, win.GetCurrentProcessId())
	if !win.CopyFileW(win.utf8_to_wstring(self), win.utf8_to_wstring(copy_path), false) {
		say("I cannot copy the uninstaller out of the app's folder.", title, .Error, command.silent)
		return EXIT_FAILED
	}
	line := fmt.tprintf(`"%s" /remove "%s" /wait %d%s`, copy_path, folder, win.GetCurrentProcessId(), " /S" if command.silent else "")
	startup := win.STARTUPINFOW{cb = size_of(win.STARTUPINFOW)}
	info: win.PROCESS_INFORMATION
	if !win.CreateProcessW(nil, win.utf8_to_wstring(line), nil, nil, false, 0, nil, nil, &startup, &info) {
		say("I cannot start the uninstaller.", title, .Error, command.silent)
		return EXIT_FAILED
	}
	win.CloseHandle(info.hProcess)
	win.CloseHandle(info.hThread)
	return EXIT_DONE
}

temp_folder :: proc() -> (path: string, ok: bool) {
	buffer: [win.MAX_PATH_WIDE]u16
	n := win.GetTempPathW(win.DWORD(len(buffer)), cast(win.LPCWSTR)raw_data(buffer[:]))
	if n == 0 {
		return "", false
	}
	text, err := win.wstring_to_utf8(cast(win.wstring)raw_data(buffer[:]), int(n))
	return strings.trim_right(text, `\`), err == nil
}

// The copy of the uninstaller: waits for the one that started it, takes the app away, and has Windows delete this copy later.
run_remove :: proc(command: install.Command) -> int {
	if command.waiting > 0 {
		if process := win.OpenProcess(win.SYNCHRONIZE, false, win.DWORD(command.waiting)); process != nil {
			_ = win.WaitForSingleObject(process, 30_000)
			win.CloseHandle(process)
		}
	}
	defer _ = win.MoveFileExW(win.utf8_to_wstring(own_path()), nil, win.MOVEFILE_DELAY_UNTIL_REBOOT)
	folder := strings.trim_right(command.folder, `\/`)
	ini, read_err := os.read_entire_file(strings.concatenate({folder, `\`, install.SETUP_INI}), context.temp_allocator)
	app, ok := install.read_ini(string(ini))
	// only a folder that holds an app made by rocinante, with its uninstaller, is ever taken away
	if read_err != nil || !ok || !os.exists(strings.concatenate({folder, `\uninstall.exe`})) {
		say(fmt.tprintf("%s does not hold an app made by rocinante, so I leave it alone.", folder), "Uninstall", .Error, command.silent)
		return EXIT_FAILED
	}
	title := fmt.tprintf("Uninstall %s", app.name)
	if !remove_app_files(folder) {
		say(install.said_in_use(app), title, .Error, command.silent)
		return EXIT_IN_USE
	}
	if path, have := shortcut_path(app); have {
		_ = os.remove(path)
	}
	remove_entry(app.id)
	say(install.said_removed(app), title, .Info, command.silent)
	return EXIT_DONE
}
