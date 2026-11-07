module mpv

// Event is one event from Mpv.wait_event. Its payload (data) belongs to mpv and
// is only valid until the next wait_event on the same handle; the accessor
// methods copy it into V values, so call them before waiting again.
pub struct Event {
	raw &C.mpv_event = unsafe { nil }
pub:
	id             EventId
	error          int // < 0 for a failed async request; see check
	reply_userdata u64
	data           voidptr
}

// check returns the event's error, for replies to async requests.
pub fn (e &Event) check() ! {
	check(e.error)!
}

pub struct EventProperty {
pub:
	name   string
	format Format
	data   Node // NodeNone if the property is unavailable
}

pub struct EventLogMessage {
pub:
	prefix    string
	level     string
	text      string // without the trailing newline
	log_level LogLevel
}

pub struct EventStartFile {
pub:
	playlist_entry_id i64
}

pub struct EventEndFile {
pub:
	reason                      EndFileReason
	error                       int // set when reason is .error
	playlist_entry_id           i64
	playlist_insert_id          i64
	playlist_insert_num_entries int
}

pub struct EventHook {
pub:
	name string
	id   u64 // pass to Mpv.hook_continue
}

// property returns the payload of property_change and get_property_reply events.
pub fn (e &Event) property() EventProperty {
	p := unsafe { &C.mpv_event_property(e.data) }
	format := unsafe { Format(p.format) }
	mut data := Node(NodeNone{})
	if !isnil(p.data) {
		data = match format {
			.string, .osd_string { Node(cstr(unsafe { *&&char(p.data) })) }
			.flag { Node(unsafe { *&int(p.data) } != 0) }
			.int64 { Node(unsafe { *&i64(p.data) }) }
			.double { Node(unsafe { *&f64(p.data) }) }
			.node { node_to_v(unsafe { &C.mpv_node(p.data) }) }
			else { Node(NodeNone{}) }
		}
	}
	return EventProperty{
		name:   cstr(p.name)
		format: format
		data:   data
	}
}

// log_message returns the payload of log_message events.
pub fn (e &Event) log_message() EventLogMessage {
	l := unsafe { &C.mpv_event_log_message(e.data) }
	return EventLogMessage{
		prefix:    cstr(l.prefix)
		level:     cstr(l.level)
		text:      cstr(l.text).trim_right('\n')
		log_level: unsafe { LogLevel(l.log_level) }
	}
}

// start_file returns the payload of start_file events.
pub fn (e &Event) start_file() EventStartFile {
	s := unsafe { &C.mpv_event_start_file(e.data) }
	return EventStartFile{
		playlist_entry_id: s.playlist_entry_id
	}
}

// end_file returns the payload of end_file events.
pub fn (e &Event) end_file() EventEndFile {
	s := unsafe { &C.mpv_event_end_file(e.data) }
	return EventEndFile{
		reason:                      unsafe { EndFileReason(s.reason) }
		error:                       s.error
		playlist_entry_id:           s.playlist_entry_id
		playlist_insert_id:          s.playlist_insert_id
		playlist_insert_num_entries: s.playlist_insert_num_entries
	}
}

// client_message returns the arguments of client_message events.
pub fn (e &Event) client_message() []string {
	s := unsafe { &C.mpv_event_client_message(e.data) }
	mut out := []string{cap: s.num_args}
	for i in 0 .. s.num_args {
		out << cstr(unsafe { s.args[i] })
	}
	return out
}

// hook returns the payload of hook events.
pub fn (e &Event) hook() EventHook {
	h := unsafe { &C.mpv_event_hook(e.data) }
	return EventHook{
		name: cstr(h.name)
		id:   h.id
	}
}

// command_reply returns the result of a command_async or command_node_async call.
pub fn (e &Event) command_reply() Node {
	c := unsafe { &C.mpv_event_command(e.data) }
	return node_to_v(&c.result)
}

// to_node returns the whole event as a map, in the shape mpv's JSON IPC sends:
// {'event': 'property-change', 'id': ..., 'name': ..., 'data': ...}.
pub fn (e &Event) to_node() Node {
	if isnil(e.raw) {
		return map[string]Node{}
	}
	mut n := C.mpv_node{}
	if C.mpv_event_to_node(&n, e.raw) < 0 {
		return map[string]Node{}
	}
	defer {
		C.mpv_free_node_contents(&n)
	}
	return node_to_v(&n)
}
