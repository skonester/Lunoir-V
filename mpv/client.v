// Module mpv provides V bindings for libmpv's client and render APIs.
module mpv

// Mpv is a libmpv client handle.
@[heap]
pub struct Mpv {
	handle &C.mpv_handle
}

// WakeupFn is called on an mpv thread; see Mpv.set_wakeup_callback.
pub type WakeupFn = fn (data voidptr)

// client_api_version returns the client API version libmpv was built with,
// as (major << 16) | minor.
pub fn client_api_version() u64 {
	return C.mpv_client_api_version()
}

// new creates an uninitialized mpv instance and its client handle.
// Set options, then call initialize.
pub fn new() !&Mpv {
	h := C.mpv_create()
	if isnil(h) {
		return MpvError{
			code: int(ErrorCode.nomem)
		}
	}
	return &Mpv{
		handle: h
	}
}

// create_client creates another client handle connected to the same player.
pub fn (m &Mpv) create_client(name string) !&Mpv {
	h := C.mpv_create_client(m.handle, &char(name.str))
	if isnil(h) {
		return MpvError{
			code: int(ErrorCode.generic)
		}
	}
	return &Mpv{
		handle: h
	}
}

// create_weak_client is create_client, except the player can quit while
// weak clients are still connected.
pub fn (m &Mpv) create_weak_client(name string) !&Mpv {
	h := C.mpv_create_weak_client(m.handle, &char(name.str))
	if isnil(h) {
		return MpvError{
			code: int(ErrorCode.generic)
		}
	}
	return &Mpv{
		handle: h
	}
}

pub fn (m &Mpv) api_version() u64 {
	return C.mpv_client_api_version()
}

// name returns the name of this client handle.
pub fn (m &Mpv) name() string {
	return cstr(C.mpv_client_name(m.handle))
}

// id returns the ID of this client handle.
pub fn (m &Mpv) id() i64 {
	return C.mpv_client_id(m.handle)
}

// initialize starts an mpv instance created with new.
pub fn (m &Mpv) initialize() ! {
	check(C.mpv_initialize(m.handle))!
}

// terminate_destroy shuts the player down and destroys this handle.
// Free any RenderContext first.
pub fn (m &Mpv) terminate_destroy() {
	C.mpv_terminate_destroy(m.handle)
}

// destroy disconnects and destroys this handle without terminating the player,
// unless it was the last non-weak handle.
pub fn (m &Mpv) destroy() {
	C.mpv_destroy(m.handle)
}

// load_config_file loads an mpv config file.
pub fn (m &Mpv) load_config_file(filename string) ! {
	check(C.mpv_load_config_file(m.handle, &char(filename.str)))!
}

// time_us returns mpv's internal time in microseconds.
pub fn (m &Mpv) time_us() i64 {
	return C.mpv_get_time_us(m.handle)
}

// time_ns returns mpv's internal time in nanoseconds.
pub fn (m &Mpv) time_ns() i64 {
	return C.mpv_get_time_ns(m.handle)
}

// set_option sets an option; the format follows from the Node variant.
// Options can only be set this way before initialize; afterwards use set_property.
pub fn (m &Mpv) set_option(name string, value Node) ! {
	n := node_to_c(value)
	defer {
		C.vmpv_node_free(n)
	}
	check(C.mpv_set_option(m.handle, &char(name.str), C.vmpv_node_arg_format(n),
		C.vmpv_node_arg_data(n)))!
}

// set_option_string sets an option from a string, as on the command line.
pub fn (m &Mpv) set_option_string(name string, value string) ! {
	check(C.mpv_set_option_string(m.handle, &char(name.str), &char(value.str)))!
}

// command runs a command given as a list of arguments, e.g. ['loadfile', path].
pub fn (m &Mpv) command(args []string) ! {
	argv := c_argv(args)
	check(C.mpv_command(m.handle, argv.data))!
}

// command_string runs a command given as one string, parsed by mpv.
pub fn (m &Mpv) command_string(cmd string) ! {
	check(C.mpv_command_string(m.handle, &char(cmd.str)))!
}

// command_ret runs a command and returns its result.
pub fn (m &Mpv) command_ret(args []string) !Node {
	argv := c_argv(args)
	mut result := C.mpv_node{}
	check(C.mpv_command_ret(m.handle, argv.data, &result))!
	defer {
		C.mpv_free_node_contents(&result)
	}
	return node_to_v(&result)
}

// command_async runs a command asynchronously; its result arrives as a
// command_reply event carrying reply_userdata.
pub fn (m &Mpv) command_async(reply_userdata u64, args []string) ! {
	argv := c_argv(args)
	check(C.mpv_command_async(m.handle, reply_userdata, argv.data))!
}

// command_node runs a command given as a []Node of arguments, or a map with
// named arguments, and returns its result.
pub fn (m &Mpv) command_node(args Node) !Node {
	n := node_to_c(args)
	defer {
		C.vmpv_node_free(n)
	}
	mut result := C.mpv_node{}
	check(C.mpv_command_node(m.handle, n, &result))!
	defer {
		C.mpv_free_node_contents(&result)
	}
	return node_to_v(&result)
}

// command_node_async is the asynchronous form of command_node.
pub fn (m &Mpv) command_node_async(reply_userdata u64, args Node) ! {
	n := node_to_c(args)
	defer {
		C.vmpv_node_free(n)
	}
	check(C.mpv_command_node_async(m.handle, reply_userdata, n))!
}

// abort_async_command aborts the async commands started with reply_userdata.
pub fn (m &Mpv) abort_async_command(reply_userdata u64) {
	C.mpv_abort_async_command(m.handle, reply_userdata)
}

// set_property sets a property; the format follows from the Node variant.
pub fn (m &Mpv) set_property(name string, value Node) ! {
	n := node_to_c(value)
	defer {
		C.vmpv_node_free(n)
	}
	check(C.mpv_set_property(m.handle, &char(name.str), C.vmpv_node_arg_format(n),
		C.vmpv_node_arg_data(n)))!
}

// set_property_string sets a property from a string.
pub fn (m &Mpv) set_property_string(name string, value string) ! {
	check(C.mpv_set_property_string(m.handle, &char(name.str), &char(value.str)))!
}

// set_property_async sets a property asynchronously; the result arrives as a
// set_property_reply event carrying reply_userdata.
pub fn (m &Mpv) set_property_async(reply_userdata u64, name string, value Node) ! {
	n := node_to_c(value)
	defer {
		C.vmpv_node_free(n)
	}
	check(C.mpv_set_property_async(m.handle, reply_userdata, &char(name.str),
		C.vmpv_node_arg_format(n), C.vmpv_node_arg_data(n)))!
}

// del_property deletes a property, e.g. a user-data/ entry.
pub fn (m &Mpv) del_property(name string) ! {
	check(C.mpv_del_property(m.handle, &char(name.str)))!
}

// get_property reads a property in the given format, returned as the matching
// Node variant: string for .string and .osd_string, bool, i64, f64, or a tree for .node.
pub fn (m &Mpv) get_property(name string, format Format) !Node {
	match format {
		.none {
			check(C.mpv_get_property(m.handle, &char(name.str), int(Format.none), unsafe { nil }))!
			return NodeNone{}
		}
		.string, .osd_string {
			return m.get_string(name, format)!
		}
		.flag {
			return m.get_property_flag(name)!
		}
		.int64 {
			return m.get_property_int(name)!
		}
		.double {
			return m.get_property_double(name)!
		}
		.node {
			return m.get_property_node(name)!
		}
		else {
			return MpvError{
				code: int(ErrorCode.invalid_parameter)
			}
		}
	}
}

// get_property_string reads a property as a string.
pub fn (m &Mpv) get_property_string(name string) !string {
	return m.get_string(name, .string)
}

// get_property_osd_string reads a property as a string formatted for display.
pub fn (m &Mpv) get_property_osd_string(name string) !string {
	return m.get_string(name, .osd_string)
}

fn (m &Mpv) get_string(name string, format Format) !string {
	mut p := &char(unsafe { nil })
	check(C.mpv_get_property(m.handle, &char(name.str), int(format), &p))!
	defer {
		C.mpv_free(p)
	}
	return cstr(p)
}

pub fn (m &Mpv) get_property_flag(name string) !bool {
	mut v := int(0)
	check(C.mpv_get_property(m.handle, &char(name.str), int(Format.flag), &v))!
	return v != 0
}

pub fn (m &Mpv) get_property_int(name string) !i64 {
	mut v := i64(0)
	check(C.mpv_get_property(m.handle, &char(name.str), int(Format.int64), &v))!
	return v
}

pub fn (m &Mpv) get_property_double(name string) !f64 {
	mut v := f64(0)
	check(C.mpv_get_property(m.handle, &char(name.str), int(Format.double), &v))!
	return v
}

// get_property_node reads a property as a Node tree, e.g. track-list.
pub fn (m &Mpv) get_property_node(name string) !Node {
	mut n := C.mpv_node{}
	check(C.mpv_get_property(m.handle, &char(name.str), int(Format.node), &n))!
	defer {
		C.mpv_free_node_contents(&n)
	}
	return node_to_v(&n)
}

// get_property_async reads a property asynchronously; the value arrives as a
// get_property_reply event carrying reply_userdata.
pub fn (m &Mpv) get_property_async(reply_userdata u64, name string, format Format) ! {
	check(C.mpv_get_property_async(m.handle, reply_userdata, &char(name.str), int(format)))!
}

// observe_property sends a property_change event carrying reply_userdata
// whenever the property changes.
pub fn (m &Mpv) observe_property(reply_userdata u64, name string, format Format) ! {
	check(C.mpv_observe_property(m.handle, reply_userdata, &char(name.str), int(format)))!
}

// unobserve_property stops all observations registered with reply_userdata and
// returns how many were removed.
pub fn (m &Mpv) unobserve_property(reply_userdata u64) !int {
	rc := C.mpv_unobserve_property(m.handle, reply_userdata)
	check(rc)!
	return rc
}

// request_event enables or disables an event.
pub fn (m &Mpv) request_event(id EventId, enable bool) ! {
	check(C.mpv_request_event(m.handle, int(id), if enable { 1 } else { 0 }))!
}

// request_log_messages enables log_message events at min_level and above:
// one of no, fatal, error, warn, info, v, debug, trace.
pub fn (m &Mpv) request_log_messages(min_level string) ! {
	check(C.mpv_request_log_messages(m.handle, &char(min_level.str)))!
}

// hook_add registers a hook such as on_load; higher priorities run first.
// Each resulting hook event must be answered with hook_continue.
pub fn (m &Mpv) hook_add(reply_userdata u64, name string, priority int) ! {
	check(C.mpv_hook_add(m.handle, reply_userdata, &char(name.str), priority))!
}

// hook_continue lets mpv continue after a hook event; pass its EventHook.id.
pub fn (m &Mpv) hook_continue(id u64) ! {
	check(C.mpv_hook_continue(m.handle, id))!
}

// wait_event waits up to timeout seconds (negative: forever) for the next event.
// The returned Event's payload is only valid until the next wait_event call.
pub fn (m &Mpv) wait_event(timeout f64) Event {
	ev := C.mpv_wait_event(m.handle, timeout)
	return Event{
		raw:            ev
		id:             unsafe { EventId(ev.event_id) }
		error:          ev.error
		reply_userdata: ev.reply_userdata
		data:           ev.data
	}
}

// wakeup interrupts a wait_event call on another thread.
pub fn (m &Mpv) wakeup() {
	C.mpv_wakeup(m.handle)
}

// set_wakeup_callback makes mpv call cb(data) when new events are queued.
// cb runs on an mpv thread: it must not call mpv functions or allocate,
// only signal the thread that calls wait_event. Pass nil to remove it.
pub fn (m &Mpv) set_wakeup_callback(cb WakeupFn, data voidptr) {
	C.mpv_set_wakeup_callback(m.handle, cb, data)
}

// wakeup_pipe returns the read end of a pipe that receives data when events
// are queued, or -1 on error. client.h says Windows always returns -1, but
// current builds return a C runtime file descriptor there too.
pub fn (m &Mpv) wakeup_pipe() int {
	return C.mpv_get_wakeup_pipe(m.handle)
}

// wait_async_requests blocks until all async requests of this handle are done.
pub fn (m &Mpv) wait_async_requests() {
	C.mpv_wait_async_requests(m.handle)
}

// c_argv returns args as a NULL-terminated array of C strings. The pointers
// borrow from args, which must stay alive while the array is in use.
fn c_argv(args []string) []&char {
	mut argv := []&char{cap: args.len + 1}
	for a in args {
		argv << &char(a.str)
	}
	argv << &char(unsafe { nil })
	return argv
}
