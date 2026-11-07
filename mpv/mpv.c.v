module mpv

// On Windows the module is self-contained: mpv's headers in include/, and
// import definitions for libmpv-2.dll (libmpv.dll.a for GCC, mpv.def for TCC).
// The program needs libmpv-2.dll next to it, or on PATH, only at run time.
// Elsewhere libmpv comes from pkg-config.
$if windows {
	#flag -I @VMODROOT/include
	$if tinyc {
		#flag @VMODROOT/mpv.def
	} $else {
		#flag -L @VMODROOT
		#flag -lmpv
	}
} $else {
	#pkgconfig mpv
}

#flag -I @VMODROOT
#include "helper.h"

pub struct C.mpv_handle {}

pub struct C.mpv_render_context {}

@[typedef]
struct C.mpv_node {
	format int
}

@[typedef]
struct C.mpv_node_list {
	num int
}

@[typedef]
struct C.mpv_byte_array {
	data voidptr
	size usize
}

@[typedef]
struct C.mpv_event {
	event_id       int
	error          int
	reply_userdata u64
	data           voidptr
}

@[typedef]
struct C.mpv_event_property {
	name   &char
	format int
	data   voidptr
}

@[typedef]
struct C.mpv_event_log_message {
	prefix    &char
	level     &char
	text      &char
	log_level int
}

@[typedef]
struct C.mpv_event_start_file {
	playlist_entry_id i64
}

@[typedef]
struct C.mpv_event_end_file {
	reason                      int
	error                       int
	playlist_entry_id           i64
	playlist_insert_id          i64
	playlist_insert_num_entries int
}

@[typedef]
struct C.mpv_event_client_message {
	num_args int
	args     &&char
}

@[typedef]
struct C.mpv_event_hook {
	name &char
	id   u64
}

@[typedef]
struct C.mpv_event_command {
	result C.mpv_node
}

// client.h
fn C.mpv_client_api_version() u64
fn C.mpv_error_string(code int) &char
fn C.mpv_free(data voidptr)
fn C.mpv_client_name(h &C.mpv_handle) &char
fn C.mpv_client_id(h &C.mpv_handle) i64
fn C.mpv_create() &C.mpv_handle
fn C.mpv_initialize(h &C.mpv_handle) int
fn C.mpv_destroy(h &C.mpv_handle)
fn C.mpv_terminate_destroy(h &C.mpv_handle)
fn C.mpv_create_client(h &C.mpv_handle, name &char) &C.mpv_handle
fn C.mpv_create_weak_client(h &C.mpv_handle, name &char) &C.mpv_handle
fn C.mpv_load_config_file(h &C.mpv_handle, filename &char) int
fn C.mpv_get_time_ns(h &C.mpv_handle) i64
fn C.mpv_get_time_us(h &C.mpv_handle) i64
fn C.mpv_free_node_contents(node &C.mpv_node)
fn C.mpv_set_option(h &C.mpv_handle, name &char, format int, data voidptr) int
fn C.mpv_set_option_string(h &C.mpv_handle, name &char, data &char) int
fn C.mpv_command(h &C.mpv_handle, args &&char) int
fn C.mpv_command_node(h &C.mpv_handle, args &C.mpv_node, result &C.mpv_node) int
fn C.mpv_command_ret(h &C.mpv_handle, args &&char, result &C.mpv_node) int
fn C.mpv_command_string(h &C.mpv_handle, args &char) int
fn C.mpv_command_async(h &C.mpv_handle, reply_userdata u64, args &&char) int
fn C.mpv_command_node_async(h &C.mpv_handle, reply_userdata u64, args &C.mpv_node) int
fn C.mpv_abort_async_command(h &C.mpv_handle, reply_userdata u64)
fn C.mpv_set_property(h &C.mpv_handle, name &char, format int, data voidptr) int
fn C.mpv_set_property_string(h &C.mpv_handle, name &char, data &char) int
fn C.mpv_del_property(h &C.mpv_handle, name &char) int
fn C.mpv_set_property_async(h &C.mpv_handle, reply_userdata u64, name &char, format int, data voidptr) int
fn C.mpv_get_property(h &C.mpv_handle, name &char, format int, data voidptr) int
fn C.mpv_get_property_async(h &C.mpv_handle, reply_userdata u64, name &char, format int) int
fn C.mpv_observe_property(h &C.mpv_handle, reply_userdata u64, name &char, format int) int
fn C.mpv_unobserve_property(h &C.mpv_handle, registered_reply_userdata u64) int
fn C.mpv_event_name(event int) &char
fn C.mpv_event_to_node(dst &C.mpv_node, src &C.mpv_event) int
fn C.mpv_request_event(h &C.mpv_handle, event int, enable int) int
fn C.mpv_request_log_messages(h &C.mpv_handle, min_level &char) int
fn C.mpv_wait_event(h &C.mpv_handle, timeout f64) &C.mpv_event
fn C.mpv_wakeup(h &C.mpv_handle)
fn C.mpv_set_wakeup_callback(h &C.mpv_handle, cb fn (voidptr), d voidptr)
fn C.mpv_wait_async_requests(h &C.mpv_handle)
fn C.mpv_hook_add(h &C.mpv_handle, reply_userdata u64, name &char, priority int) int
fn C.mpv_hook_continue(h &C.mpv_handle, id u64) int
fn C.mpv_get_wakeup_pipe(h &C.mpv_handle) int

// render.h
fn C.mpv_render_context_set_update_callback(ctx &C.mpv_render_context, cb fn (voidptr), d voidptr)
fn C.mpv_render_context_update(ctx &C.mpv_render_context) u64
fn C.mpv_render_context_report_swap(ctx &C.mpv_render_context)
fn C.mpv_render_context_free(ctx &C.mpv_render_context)

// helper.h
fn C.vmpv_node_string(n &C.mpv_node) &char
fn C.vmpv_node_flag(n &C.mpv_node) int
fn C.vmpv_node_int64(n &C.mpv_node) i64
fn C.vmpv_node_double(n &C.mpv_node) f64
fn C.vmpv_node_list(n &C.mpv_node) &C.mpv_node_list
fn C.vmpv_node_ba(n &C.mpv_node) &C.mpv_byte_array
fn C.vmpv_node_list_at(l &C.mpv_node_list, i int) &C.mpv_node
fn C.vmpv_node_list_key(l &C.mpv_node_list, i int) &char
fn C.vmpv_node_new() &C.mpv_node
fn C.vmpv_node_set_none(n &C.mpv_node)
fn C.vmpv_node_set_string(n &C.mpv_node, s &char, len usize)
fn C.vmpv_node_set_flag(n &C.mpv_node, v int)
fn C.vmpv_node_set_int64(n &C.mpv_node, v i64)
fn C.vmpv_node_set_double(n &C.mpv_node, v f64)
fn C.vmpv_node_set_bytes(n &C.mpv_node, data voidptr, size usize)
fn C.vmpv_node_set_list(n &C.mpv_node, num int, is_map int) &C.mpv_node_list
fn C.vmpv_node_list_set_key(l &C.mpv_node_list, i int, s &char, len usize)
fn C.vmpv_node_free(n &C.mpv_node)
fn C.vmpv_node_arg_format(n &C.mpv_node) int
fn C.vmpv_node_arg_data(n &C.mpv_node) voidptr
fn C.vmpv_render_create_sw(ctx &&C.mpv_render_context, h &C.mpv_handle) int
fn C.vmpv_render_sw(ctx &C.mpv_render_context, w int, h int, format &char, stride usize, ptr voidptr) int
fn C.vmpv_render_create_gl(ctx &&C.mpv_render_context, h &C.mpv_handle, get_proc_address GetProcAddressFn, cb_ctx voidptr) int
fn C.vmpv_render_gl(ctx &C.mpv_render_context, fbo int, w int, h int, flip_y int) int
