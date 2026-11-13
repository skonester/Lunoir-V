module main

import os
import time

#include "@VMODROOT/v_lunoir/platform_win.h"
#flag -luser32 -lgdi32 -lcomdlg32 -lshell32 -lole32 -luuid -lwinhttp

@[typedef]
struct C.LunoirProcess {
	handle voidptr
	pid    u32
}

@[typedef]
struct C.LunoirHttp {
	data         &char
	len          int
	status       int
	url          &char
	content_type &char
}

fn C.lv_replace(&u16, &u16) int
fn C.MessageBoxW(voidptr, &u16, &u16, u32) int
fn C.lv_locale() &char
fn C.lv_pictures() &char
fn C.lv_decode_text(&char, int, u32) &char
fn C.lv_job() voidptr
fn C.lv_start(&u16, &u16, &u16, &u16, voidptr) &C.LunoirProcess
fn C.lv_process_wait(&C.LunoirProcess, u32) int
fn C.lv_process_exit(&C.LunoirProcess) int
fn C.lv_process_close(&C.LunoirProcess, int)
fn C.lv_fetch(&u16, &u16) C.LunoirHttp
fn C.lv_http_free(&C.LunoirHttp)
fn C.lv_find_window(&u16) voidptr
fn C.lv_video_create(voidptr) voidptr
fn C.lv_client(voidptr, &int)
fn C.lv_bounds(voidptr, &int)
fn C.lv_position(voidptr, int, int, int, int)
fn C.lv_region(voidptr, int, int, int, &int, int)
fn C.lv_cursor(voidptr, voidptr, &int) int
fn C.lv_focused(voidptr) int
fn C.lv_key(int) int
fn C.lv_show(voidptr, int)
fn C.lv_raise(voidptr)
fn C.lv_destroy(voidptr)
fn C.lv_focus(voidptr)
fn C.lv_pump()
fn C.lv_open_dialog(voidptr, int, int, &u16) &char
fn C.CloseHandle(voidptr) int

fn owned_c_string(ptr &char) string {
	if isnil(ptr) { return '' }
	result := unsafe { cstring_to_vstring(ptr).clone() }
	unsafe { C.free(ptr) }
	return result
}

fn atomic_replace(from string, to string) ! {
	if C.lv_replace(from.to_wide(), to.to_wide()) == 0 { return error('Could not replace ${to}') }
}

fn system_locale() string {
	return owned_c_string(C.lv_locale())
}

fn pictures_folder() string {
	path := owned_c_string(C.lv_pictures())
	return if path == '' { os.join_path(os.home_dir(), 'Pictures') } else { path }
}

fn decode_source_text(body string, content_type string) string {
	mut charset := 'utf-8'
	if at := content_type.to_lower().index('charset=') {
		charset = content_type[at + 8..].all_before(';').trim(' "\'').to_lower()
	}
	codepages := {
		'utf-8':        65001
		'utf8':         65001
		'utf-16':       1200
		'utf-16le':     1200
		'utf-16be':     1201
		'gbk':          936
		'gb2312':       936
		'gb18030':      54936
		'big5':         950
		'shift_jis':    932
		'shift-jis':    932
		'cp932':        932
		'euc-kr':       51949
		'cp949':        949
		'windows-1250': 1250
		'windows-1251': 1251
		'windows-1252': 1252
		'cp1251':       1251
		'cp1252':       1252
		'iso-8859-1':   28591
		'latin-1':      28591
		'koi8-r':       20866
		'cp866':        866
	}
	return owned_c_string(C.lv_decode_text(&char(body.str), body.len, u32(codepages[charset] or {
		65001
	})))
}

struct HttpResponse {
	body         string
	url          string
	content_type string
	status       int
}

fn http_fetch(url string, agent string) !HttpResponse {
	mut response := C.lv_fetch(url.to_wide(), agent.to_wide())
	defer { C.lv_http_free(&response) }
	if response.status == 0 || isnil(response.data) { return error('Could not download ${url}') }
	if response.status >= 400 { return error('HTTP ${response.status}: ${url}') }
	return HttpResponse{
		body:         unsafe { tos(&u8(response.data), response.len).clone() }
		url:          if isnil(response.url) {
			url
		} else {
			unsafe { cstring_to_vstring(response.url).clone() }
		}
		content_type: if isnil(response.content_type) {
			''
		} else {
			unsafe { cstring_to_vstring(response.content_type).clone() }
		}
		status:       response.status
	}
}

fn quote_argument(value string) string {
	mut result := '"'
	mut slashes := 0
	for ch in value.bytes() {
		if ch == `\\` {
			slashes++
			continue
		}
		if ch == `"` {
			result += '\\'.repeat(slashes * 2 + 1) + '"'
		} else {
			result += '\\'.repeat(slashes) + ch.ascii_str()
		}
		slashes = 0
	}
	return result + '\\'.repeat(slashes * 2) + '"'
}

fn start_process(args []string, cwd string, output string, errors string, job voidptr) !&C.LunoirProcess {
	command := args.map(quote_argument(it)).join(' ')
	process := C.lv_start(command.to_wide(), cwd.to_wide(), output.to_wide(), errors.to_wide(), job)
	if isnil(process) { return error('Could not start ${args[0]}') }
	return process
}

fn capture_process(args []string, timeout time.Duration) !string {
	base := os.join_path(os.temp_dir(), 'lunoir-v-${os.getpid()}-${time.now().unix_micro()}')
	output, errors := base + '.out', base + '.err'
	defer {
		os.rm(output) or {}
		os.rm(errors) or {}
	}
	job := C.lv_job()
	if isnil(job) { return error('Could not create the subprocess job') }
	defer { C.CloseHandle(job) }
	process := start_process(args, '', output, errors, job)!
	if C.lv_process_wait(process, u32(timeout / time.millisecond)) == 0 {
		C.lv_process_close(process, 1)
		return error('Process timed out: ${args[0]}')
	}
	code := C.lv_process_exit(process)
	C.lv_process_close(process, 0)
	if code != 0 { return error(os.read_file(errors) or { 'Process failed: ${args[0]}' }) }
	return os.read_file(output)!
}

fn open_dialog(parent voidptr, folder bool, multiple bool, extensions []string) []string {
	pattern := extensions.map('*.' + it).join(';')
	filter := 'Media\x00${pattern}\x00All files\x00*.*\x00\x00'
	result :=
		owned_c_string(C.lv_open_dialog(parent, int(folder), int(multiple), filter.to_wide())).trim_right('\n')
	if result == '' { return []string{} }
	lines := result.split('\n')
	if lines.len <= 1 || folder { return lines }
	return lines[1..].map(os.join_path(lines[0], it))
}
