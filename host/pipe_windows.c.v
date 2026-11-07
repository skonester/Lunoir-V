module main

import mpv

#flag -I @VMODROOT/host
#include "pipe_win.h"

fn C.vh_pipe_create(path &u16, first int) voidptr
fn C.vh_pipe_accept(h voidptr) int
fn C.vh_pipe_read(h voidptr, buf voidptr, size int) int
fn C.vh_pipe_write(h voidptr, buf voidptr, size int) int
fn C.vh_pipe_cancel(h voidptr)
fn C.vh_pipe_close(h voidptr)
fn C.vh_stderr_write(s &char, len int)

// Pipe is one connected client of the IPC named pipe.
struct Pipe {
	h voidptr
}

// pipe_path turns an --input-ipc-server value into a pipe path, as mpv does:
// names without a \\.\pipe\ prefix are placed under it.
fn pipe_path(name string) string {
	if name.starts_with('\\\\.\\pipe\\') || name.starts_with('//./pipe/') {
		return name
	}
	return '\\\\.\\pipe\\' + name
}

// serve_pipe accepts clients on the named pipe forever, serving each one in
// its own thread.
fn serve_pipe(name string, core &mpv.Mpv) {
	path := pipe_path(name)
	mut first := true
	mut clients := 0
	for {
		h := C.vh_pipe_create(path.to_wide(), if first { 1 } else { 0 })
		if isnil(h) {
			log_err('ipc: could not create pipe ${path}')
			return
		}
		first = false
		if C.vh_pipe_accept(h) == 0 {
			C.vh_pipe_close(h)
			continue
		}
		clients++
		spawn serve_client(core, Pipe{h}, clients)
	}
}

// read returns the next chunk from the client, or none once it is gone.
fn (p Pipe) read(mut buf []u8) ?int {
	n := C.vh_pipe_read(p.h, buf.data, buf.len)
	if n < 0 {
		return none
	}
	return n
}

fn (p Pipe) write(s string) bool {
	return C.vh_pipe_write(p.h, s.str, s.len) != 0
}

fn (p Pipe) cancel() {
	C.vh_pipe_cancel(p.h)
}

fn (p Pipe) close() {
	C.vh_pipe_close(p.h)
}

// stderr_line writes one line to stderr; eprintln output is lost when the host
// is built with -subsystem windows, as it is for Lunoir.
fn stderr_line(s string) {
	line := s + '
'
	C.vh_stderr_write(&char(line.str), line.len)
}
