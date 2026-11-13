module main

import os
import net
import time
import x.json2

fn project_root() string {
	for root in [os.dir(os.executable()), os.getwd(), @VMODROOT] {
		if os.is_dir(os.join_path(root, 'lunoir', 'src', 'shared', 'i18n')) { return root }
	}
	return os.dir(os.executable())
}

fn launch_targets(args []string) []string {
	mut targets := []string{}
	for arg in args {
		if arg == '' || arg.starts_with('-') { continue
		 }
		if is_url(arg) {
			targets << arg
		} else if os.exists(arg) {
			targets << os.abs_path(arg)
		}
	}
	return targets
}

fn main() {
	run_player() or {
		eprintln(err.msg())
		log_native(err.msg())
		C.MessageBoxW(unsafe { nil }, err.msg().to_wide(), 'Lunoir V'.to_wide(), u32(0x10))
		exit(1)
	}
}

fn log_native(message string) {
	base := os.getenv('LOCALAPPDATA')
	directory := os.join_path(if base == '' { os.temp_dir() } else { base }, 'Lunoir V')
	os.mkdir_all(directory) or { return }
	mut file := os.open_append(os.join_path(directory, 'native.log')) or { return }
	file.writeln('${time.now()} ${message}') or {}
	file.close()
}

fn run_player() ! {
	root := project_root()
	mut profile := new_profile(default_profile_directory())
	startup := launch_targets(os.args[1..])
	mut instance := new_instance(profile.directory)
	defer { C.lv_instance_close(instance) }
	if C.lv_instance_claimed(instance) == 0 {
		message := json_encode(startup.map(json2.Any(it)))
		if C.lv_instance_forward(instance, &char(message.str), 15000) != 0 { return }
	}
	if text_value(get(profile.settings, 'screenshotDir')) == '' {
		profile.set_setting('screenshotDir', screenshot_dir(profile.settings))!
	}
	t := new_translator(root, text_value(get(profile.settings, 'uiLanguage')))
	mut app := App{
		root:          root
		profile:       profile
		t:             t
		ui:            new_flet(&t)
		caption:       'Lunoir · V · ${os.getpid()}'
		last_activity: time.now().unix_milli()
		properties:    {
			'pause':    json2.Any(false)
			'volume':   get(profile.settings, 'volume')
			'duration': 0
			'time-pos': 0
			'mute':     false
			'seekable': true
			'speed':    1
		}
		instance:      instance
	}
	if script := os.read_file(os.getenv('LUNOIR_V_TEST_SCRIPT')) {
		a := list_value(json_decode(script) or { json2.Any([]json2.Any{}) })
		app.test_steps = a
	}
	if os.getenv('LUNOIR_V_SNAPSHOTS') != '' {
		app.ui.set('page', 'enable_screenshots', true)
		app.ui.set_id(3, 'enable_screenshots', true)
	}
	app.ui.set('page', 'title', app.caption)
	if truth(get(app.profile.settings, 'rememberWindow')) {
		bounds := object(get(app.profile.settings, 'windowBounds'))
		if bounds.len > 0 {
			app.ui.set('window', 'left', get(bounds, 'x'))
			app.ui.set('window', 'top', get(bounds, 'y'))
			app.ui.set('window', 'width', clamp(number(get(bounds, 'width')), 900, 16000))
			app.ui.set('window', 'height', clamp(number(get(bounds, 'height')), 560, 16000))
		}
	}
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	address := listener.addr()!
	client := os.join_path(root, 'flet_lunoir', 'runtime', 'flet', 'flet', 'flet.exe')
	if !os.is_file(client) {
		return error('The Flet desktop runtime is missing. Run build-native.ps1 once.')
	}
	job := C.lv_job()
	if isnil(job) { return error('Could not create the player process job') }
	defer { C.CloseHandle(job) }
	pidfile := os.join_path(os.temp_dir(), 'lunoir-flet-${os.getpid()}.pid')
	defer { os.rm(pidfile) or {} }
	client_log := os.join_path(os.temp_dir(), 'lunoir-flet-${os.getpid()}.log')
	process := start_process([client, 'tcp://${address}', pidfile,
		os.join_path(root, 'lunoir', 'src', 'renderer', 'src', 'assets')], root, '', client_log, job)!
	app.flet_pid = int(process.pid)
	defer { C.lv_process_close(process, 1) }
	listener.set_accept_timeout(15 * time.second)
	mut conn := listener.accept()!
	defer { conn.close() or {} }
	app.ui.conn = conn
	incoming := chan json2.Any{cap: 512}
	spawn read_flet(conn, incoming)
	defer { app.close() }
	started := time.now().unix_milli()
	exit_after := os.getenv('LUNOIR_V_EXIT_AFTER').int()
	mut opened := false
	for !app.closed {
		C.lv_pump()
		for _ in 0 .. 200 {
			select {
				message := <-incoming {
					app.message(message)
				}
				else {
					break
				}
			}
		}
		if app.ui.registered && !app.ready {
			parent := C.lv_find_window(app.caption.to_wide())
			if !isnil(parent) {
				app.surface = new_video(parent, 0)!
				app.backend.start(app.surface.hwnd, []string{}, true)!
				for property in startup_properties(app.profile.settings) {
					app.try_set(property.name, property.value)
				}
				app.try_set('screenshot-template', '%F_%wH-%wM-%wS')
				app.ready = true
				app.thumbs.parent = parent
				app.drop = C.lv_drop_create(parent)
				C.lv_instance_serve(instance, parent)
				app.width = number(app.ui.prop('window', 'width'))
				app.height = number(app.ui.prop('window', 'height'))
				app.layout()
				log_native('Lunoir V ${app_version} connected to Flet; mpv API ${mpv_api_label()}')
			}
		}
		if app.ready {
			if !opened {
				opened = true
				app.open_paths(startup)
			}
			for event in app.backend.events() {
				app.handle_event(event)
			}
			app.tick()
		}
		app.ui.flush() or { app.closed = true }
		if C.lv_process_wait(process, 0) != 0 { app.closed = true }
		if exit_after > 0 && time.now().unix_milli() - started >= exit_after * 1000 {
			app.closed = true
		}
		time.sleep(20 * time.millisecond)
	}
}
