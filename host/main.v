// vmpv-host: a stand-in for mpv.exe built on the V libmpv binding.
//
// Front ends that drive mpv.exe over its JSON IPC (such as Lunoir) can launch
// this instead: it takes mpv-style --option=value arguments, plays through
// libmpv, and serves the --input-ipc-server pipe itself, so every request and
// event passes through the binding rather than libmpv's own IPC server.
//
//	vmpv-host [--option=value | --flag | --no-flag ...] [file ...]
//
// With no file, no --input-ipc-server and no --idle it exits at once, as mpv.exe
// does when it has nothing to do.
//
// Host-only options:
//	--vmpv-native-ipc   let libmpv serve --input-ipc-server instead (for comparison)
//
// Environment:
//	VMPV_HOST_LOG=path  append a trace of every IPC request to path
module main

import mpv
import os
import sync
import time

struct Config {
mut:
	options    [][]string // [name, value] in command-line order
	ipc_server string
	native_ipc bool
	files      []string
}

fn parse_args(args []string) Config {
	mut c := Config{}
	mut only_files := false
	for a in args {
		if only_files || !a.starts_with('--') {
			c.files << a
			continue
		}
		if a == '--' {
			only_files = true
			continue
		}
		mut name, mut value := a[2..].split_once('=') or { a[2..], '' }
		if !a.contains('=') {
			if name.starts_with('no-') {
				name, value = name[3..], 'no'
			} else {
				value = 'yes'
			}
		}
		match name {
			'input-ipc-server' { c.ipc_server = value }
			'vmpv-native-ipc' { c.native_ipc = value != 'no' }
			else { c.options << [name, value] }
		}
	}
	return c
}

fn main() {
	cfg := parse_args(os.args[1..])
	trace('start: ${os.args[1..]}')
	if cfg.files.len == 0 && cfg.ipc_server == '' && !cfg.options.any(it[0] == 'idle' && it[1] != 'no') {
		// mpv.exe with nothing to do prints its usage and exits. This host has no
		// window or console, so idling here would leave an invisible process
		// (e.g. after a double-click in Explorer).
		stderr_line('usage: vmpv-host [--option=value | --flag | --no-flag ...] [file ...]')
		exit(0)
	}
	m := mpv.new() or {
		log_err('mpv_create failed: ${err}')
		exit(1)
	}
	for opt in cfg.options {
		m.set_option_string(opt[0], opt[1]) or {
			// mpv.exe would refuse to start; keep going so one option libmpv
			// lacks does not take the whole front end down.
			log_err('option --${opt[0]}=${opt[1]}: ${err}')
		}
	}
	if cfg.ipc_server != '' && cfg.native_ipc {
		m.set_option_string('input-ipc-server', cfg.ipc_server) or {
			log_err('input-ipc-server: ${err}')
		}
	}
	// Like mpv.exe's terminal output: warnings and errors on stderr.
	m.request_log_messages('warn') or {}
	m.initialize() or {
		log_err('initialize failed: ${err}')
		exit(1)
	}
	if cfg.ipc_server != '' && !cfg.native_ipc {
		spawn serve_pipe(cfg.ipc_server, m)
	}
	for f in cfg.files {
		m.command(['loadfile', f, 'append-play']) or { log_err('loadfile ${f}: ${err}') }
	}
	for {
		e := m.wait_event(-1)
		match e.id {
			.log_message {
				l := e.log_message()
				prefix := if l.prefix == 'cplayer' { '' } else { '[${l.prefix}] ' }
				stderr_line(prefix + l.text)
			}
			.shutdown {
				break
			}
			else {}
		}
	}
	trace('shutdown')
	m.terminate_destroy()
}

const log_path = os.getenv('VMPV_HOST_LOG')
const log_mu = sync.new_mutex()

fn log_err(msg string) {
	stderr_line('vmpv-host: ${msg}')
	trace('error: ${msg}')
}

// trace appends a timestamped line to $VMPV_HOST_LOG, if set.
fn trace(msg string) {
	if log_path == '' {
		return
	}
	log_mu.lock()
	defer {
		log_mu.unlock()
	}
	mut f := os.open_append(log_path) or { return }
	f.writeln('${time.now().format_ss_milli()} [${os.getpid()}] ${msg}') or {}
	f.close()
}
